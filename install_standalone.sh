#!/bin/bash
# IP-Sentinel 单机自治版安装脚本 (systemd timer)
#
# 安装后系统上只保留：
# - /opt/ip_sentinel/config.conf   静态配置
# - /opt/ip_sentinel/core/*.sh     运行时代码
# - /etc/systemd/system/ip-sentinel.*  systemd unit 文件
# 无守护进程常驻，无状态文件，无内部日志写入

set -e

REPO="https://raw.githubusercontent.com/hotyue/IP-Sentinel/main"
DIR="/opt/ip_sentinel"
VER="3.4.0"

echo "IP-Sentinel 单机自治版 v${VER}"
echo "================================"

# 检查 curl-impersonate
echo -e "\n[0/3] 检查 curl-impersonate..."
CURL_IMP=""
for cmd in curl_chrome125 curl_chrome131 curl_chrome120 curl_chrome116 curl_chrome; do
    command -v "$cmd" >/dev/null 2>&1 && { CURL_IMP="$cmd"; break; }
done

if [ -z "$CURL_IMP" ]; then
    echo "请先安装 curl-impersonate:"
    echo "https://github.com/lwthiker/curl-impersonate/releases"
    exit 1
fi
echo "✅ 使用: $CURL_IMP"

# 安装依赖
echo -e "\n[1/3] 安装依赖..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl jq cron procps >/dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl jq cronie procps-ng >/dev/null 2>&1
fi

# 检查 systemd
if ! command -v systemctl >/dev/null 2>&1; then
    echo "❌ systemd 未找到，本版本依赖 systemd timer"
    exit 1
fi

# 网络与自动地理检测
echo -e "\n[2/3] 网络与地理检测..."
IPV4=$(curl -4 -s -m 3 api.ip.sb/ip 2>/dev/null || echo "")
IPV6=$(curl -6 -s -m 3 api.ip.sb/ip 2>/dev/null || echo "")

if [ -n "$IPV4" ]; then
    GEO=$(curl -4 -s -m 5 "https://api.ip.sb/geoip" 2>/dev/null || echo "")
else
    GEO=$(curl -6 -s -m 5 "https://api.ip.sb/geoip" 2>/dev/null || echo "")
fi

REGION_CODE=$(echo "$GEO" | jq -r '.country_code // empty')
CITY=$(echo "$GEO" | jq -r '.city // empty')
BASE_LAT=$(echo "$GEO" | jq -r '.latitude // empty')
BASE_LON=$(echo "$GEO" | jq -r '.longitude // empty')
TIMEZONE=$(echo "$GEO" | jq -r '.timezone // empty')

[ -z "$REGION_CODE" ] && { echo "❌ 地理检测失败"; exit 1; }
echo "📍 检测: $CITY, $REGION_CODE | $BASE_LAT, $BASE_LON"

# 根据国家代码匹配内置规则
case "$REGION_CODE" in
    US)
        VALID_URL_SUFFIX="com"
        LANG_PARAMS="hl=en&gl=US"
        WHITE_URLS="https://en.wikipedia.org/wiki/Special:Random|https://www.yahoo.com/|https://www.target.com/|https://www.npr.org/|https://www.weather.com/|https://www.amazon.com/|https://www.cdc.gov/"
        ;;
    JP)
        VALID_URL_SUFFIX="com"
        LANG_PARAMS="hl=ja&gl=JP"
        WHITE_URLS="https://ja.wikipedia.org/wiki/Special:Random|https://www.yahoo.co.jp/|https://www.rakuten.co.jp/|https://www.nhk.or.jp/|https://kakaku.com/|https://www.goo.ne.jp/|https://www.amazon.co.jp/"
        ;;
    UK)
        VALID_URL_SUFFIX="co.uk"
        LANG_PARAMS="hl=en&gl=GB"
        WHITE_URLS="https://www.bbc.co.uk/|https://www.gov.uk/|https://www.amazon.co.uk/|https://www.theguardian.com/uk|https://www.nhs.uk/|https://en.wikipedia.org/wiki/Special:Random|https://www.ebay.co.uk/"
        ;;
    DE)
        VALID_URL_SUFFIX="de"
        LANG_PARAMS="hl=de&gl=DE"
        WHITE_URLS="https://www.amazon.de/|https://www.spiegel.de/|https://www.tagesschau.de/|https://de.wikipedia.org/wiki/Spezial:Zuf%C3%A4llige_Seite|https://www.ebay.de/|https://www.bild.de/|https://www.kicker.de/"
        ;;
    FR)
        VALID_URL_SUFFIX="fr"
        LANG_PARAMS="hl=fr&gl=FR"
        WHITE_URLS="https://www.lemonde.fr/|https://www.lefigaro.fr/|https://www.amazon.fr/|https://www.service-public.fr/|https://fr.wikipedia.org/wiki/Sp%C3%A9cial:Page_au_hasard|https://www.cdiscount.com/|https://www.fnac.com/"
        ;;
    SG)
        VALID_URL_SUFFIX="com.sg"
        LANG_PARAMS="hl=en-SG&gl=SG"
        WHITE_URLS="https://www.straitstimes.com/|https://www.channelnewsasia.com/|https://www.gov.sg/|https://shopee.sg/|https://en.wikipedia.org/wiki/Special:Random|https://www.fairprice.com.sg/|https://www.dbs.com.sg/"
        ;;
    HK)
        VALID_URL_SUFFIX="com.hk"
        LANG_PARAMS="hl=zh-HK&gl=HK"
        WHITE_URLS="https://www.gov.hk/|https://www.hko.gov.hk/|https://www.scmp.com/|https://www.hk01.com/|https://zh.wikipedia.org/wiki/Special:Random|https://www.hktvmall.com/|https://www.mtr.com.hk/"
        ;;
    *)
        echo "⚠️ 国家 $REGION_CODE 暂无内置规则，使用通用 US 规则"
        VALID_URL_SUFFIX="com"
        LANG_PARAMS="hl=en&gl=US"
        WHITE_URLS="https://en.wikipedia.org/wiki/Special:Random|https://www.apple.com/|https://www.microsoft.com/"
        ;;
esac

REGION_NAME="${CITY:-$REGION_CODE} - ${REGION_CODE}"

# 功能配置
echo -e "\n[3/3] 功能配置..."
echo "1) Google 区域纠偏"
echo "2) IP 信用净化"
echo "3) 双管齐下 (默认)"
read -p "选择: " mod
mod=${mod:-3}

ENABLE_GOOGLE="true"
ENABLE_TRUST="false"
[ "$mod" == "2" ] && { ENABLE_GOOGLE="false"; ENABLE_TRUST="true"; }
[ "$mod" == "3" ] && ENABLE_TRUST="true"

# IP 协议选择
echo -e "\nIP 协议:"
[ -n "$IPV4" ] && echo "1) IPv4: $IPV4"
[ -n "$IPV6" ] && echo "2) IPv6: $IPV6"
read -p "选择: " ip
ip=${ip:-1}

if [ "$ip" == "2" ] && [ -n "$IPV6" ]; then
    PUBLIC_IP="[$IPV6]"
    IP_PREF="6"
    RAW_IP="$IPV6"
else
    PUBLIC_IP="$IPV4"
    IP_PREF="4"
    RAW_IP="$IPV4"
fi

# NAT 检测
TEST_URL=$([[ "$RAW_IP" == *":"* ]] && echo "https://[2606:4700:4700::1111]" || echo "https://1.1.1.1")
if curl --interface "$RAW_IP" -sI -m 3 "$TEST_URL" >/dev/null 2>&1; then
    echo "✅ 原生直连"
    BIND_IP="$PUBLIC_IP"
else
    echo "⚠️ NAT环境"
    BIND_IP=""
fi

# 写入配置
mkdir -p "${DIR}/core"

cat > "${DIR}/config.conf" << EOF
AGENT_VERSION="$VER"
REGION_CODE="$REGION_CODE"
REGION_NAME="$REGION_NAME"
BASE_LAT="$BASE_LAT"
BASE_LON="$BASE_LON"
LANG_PARAMS="$LANG_PARAMS"
VALID_URL_SUFFIX="$VALID_URL_SUFFIX"
ENABLE_GOOGLE="$ENABLE_GOOGLE"
ENABLE_TRUST="$ENABLE_TRUST"
INSTALL_DIR="$DIR"
LOG_FILE="${DIR}/logs/sentinel.log"
IP_PREF="$IP_PREF"
PUBLIC_IP="$PUBLIC_IP"
BIND_IP="$BIND_IP"
TIMEZONE="$TIMEZONE"
WHITE_URLS=(
$(echo "$WHITE_URLS" | tr '|' '\n' | sed 's/^/    "/;s/$/"/')
)
EOF

chmod 600 "${DIR}/config.conf"

# 部署组件
echo -e "\n[4/4] 部署组件..."
for f in core/standalone_worker.sh core/uninstall.sh core/utils.sh; do
    curl -sL "${REPO}/${f}" -o "${DIR}/${f}"
done

[ "$ENABLE_GOOGLE" == "true" ] && curl -sL "${REPO}/core/mod_google_curl_imp.sh" -o "${DIR}/core/mod_google_curl_imp.sh"
[ "$ENABLE_TRUST" == "true" ] && curl -sL "${REPO}/core/mod_trust_curl_imp.sh" -o "${DIR}/core/mod_trust_curl_imp.sh"

chmod +x ${DIR}/core/*.sh

# 写入 systemd unit
cat > /etc/systemd/system/ip-sentinel.service << 'EOF'
[Unit]
Description=IP-Sentinel IP maintenance worker
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/ip_sentinel/core/standalone_worker.sh
StandardOutput=journal
StandardError=journal
EOF

cat > /etc/systemd/system/ip-sentinel.timer << 'EOF'
[Unit]
Description=IP-Sentinel hourly check (08:00-22:00)

[Timer]
OnCalendar=*-*-* 08..22:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now ip-sentinel.timer

# 清理旧版本残留的 crontab
crontab -l 2>/dev/null | grep -v ip_sentinel > /tmp/cron_clean || true
crontab /tmp/cron_clean 2>/dev/null || true
rm -f /tmp/cron_clean

echo -e "\n================================"
echo "🎉 部署完成!"
echo "📍 区域: $REGION_NAME"
echo "🔐 引擎: $CURL_IMP"
echo "📜 日志: journalctl -u ip-sentinel -f"
echo "⏰ 查看定时器: systemctl status ip-sentinel.timer"
echo "================================"
