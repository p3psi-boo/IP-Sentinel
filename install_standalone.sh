#!/bin/bash
# IP-Sentinel 单机自治版安装脚本

set -e

REPO="https://raw.githubusercontent.com/hotyue/IP-Sentinel/main"
DIR="/opt/ip_sentinel"
VER="3.4.0"

echo "IP-Sentinel 单机自治版 v${VER}"
echo "================================"

# 检查 curl-impersonate
echo -e "\n[0/5] 检查 curl-impersonate..."
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
echo -e "\n[1/5] 安装依赖..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl jq cron procps >/dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
    yum install -y curl jq cronie procps-ng >/dev/null 2>&1
    systemctl enable crond --now 2>/dev/null || true
fi

# 通用选择函数
select_item() {
    local file=$1 desc=$2
    local count=$(wc -l <"$file")
    if [ "$count" -eq 1 ]; then
        cut -d'|' -f1 "$file"
        return
    fi
    echo "$desc:"
    nl "$file"
    read -p "选择 (默认1): " sel
    sel=${sel:-1}
    sed -n "${sel}p" "$file" | cut -d'|' -f1
}

# 区域选择
echo -e "\n[2/5] 选择区域..."
curl -sL "${REPO}/data/map.json" -o /tmp/map.json

jq -r '.countries[] | "\(.id)|\(.name)"' /tmp/map.json > /tmp/countries.txt
REGION_CODE=$(select_item /tmp/countries.txt "国家/地区")

jq -r ".countries[] | select(.id==\"$REGION_CODE\") | .states[] | \"\(.id)|\(.name)\"" /tmp/map.json > /tmp/states.txt
STATE=$(select_item /tmp/states.txt "州/省")

jq -r ".countries[] | select(.id==\"$REGION_CODE\") | .states[] | select(.id==\"$STATE\") | .cities[] | \"\(.id)|\(.name)\"" /tmp/map.json > /tmp/cities.txt
CITY=$(select_item /tmp/cities.txt "城市")

rm -f /tmp/*.json /tmp/*.txt

# 功能配置
echo -e "\n[3/5] 功能配置..."
echo "1) Google 区域纠偏"
echo "2) IP 信用净化"
echo "3) 双管齐下 (默认)"
read -p "选择: " mod
mod=${mod:-3}

ENABLE_GOOGLE="true"
ENABLE_TRUST="false"
[ "$mod" == "2" ] && { ENABLE_GOOGLE="false"; ENABLE_TRUST="true"; }
[ "$mod" == "3" ] && ENABLE_TRUST="true"

# 网络配置
echo -e "\n[4/5] 网络配置..."
IPV4=$(curl -4 -s -m 3 api.ip.sb/ip 2>/dev/null || echo "")
IPV6=$(curl -6 -s -m 3 api.ip.sb/ip 2>/dev/null || echo "")

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

# 创建目录并拉取数据
mkdir -p "${DIR}/core" "${DIR}/data/keywords" "${DIR}/data/regions/${REGION_CODE}/${STATE}" "${DIR}/logs"

curl -sL "${REPO}/data/regions/${REGION_CODE}/${STATE}/${CITY}.json" -o "${DIR}/data/regions/${REGION_CODE}/${STATE}/${CITY}.json"
JSON="${DIR}/data/regions/${REGION_CODE}/${STATE}/${CITY}.json"
[ ! -s "$JSON" ] && { echo "❌ 区域数据拉取失败"; exit 1; }

REGION_NAME=$(jq -r '.region_name' "$JSON")
BASE_LAT=$(jq -r '.google_module.base_lat' "$JSON")
BASE_LON=$(jq -r '.google_module.base_lon' "$JSON")
LANG_PARAMS=$(jq -r '.google_module.lang_params' "$JSON")
VALID_URL_SUFFIX=$(jq -r '.google_module.valid_url_suffix' "$JSON")

# 写入配置
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
EOF

chmod 600 "${DIR}/config.conf"

# 部署组件
echo -e "\n[5/5] 部署组件..."
for f in core/standalone_daemon.sh core/updater.sh core/uninstall.sh data/user_agents.txt; do
    curl -sL "${REPO}/${f}" -o "${DIR}/${f}"
done

[ "$ENABLE_GOOGLE" == "true" ] && {
    curl -sL "${REPO}/core/mod_google_curl_imp.sh" -o "${DIR}/core/mod_google_curl_imp.sh"
    curl -sL "${REPO}/data/keywords/kw_${REGION_CODE}.txt" -o "${DIR}/data/keywords/kw_${REGION_CODE}.txt"
}
[ "$ENABLE_TRUST" == "true" ] && curl -sL "${REPO}/core/mod_trust_curl_imp.sh" -o "${DIR}/core/mod_trust_curl_imp.sh"

chmod +x ${DIR}/core/*.sh

# 开机自启
crontab -l 2>/dev/null | grep -v ip_sentinel > /tmp/cron_clean || true
echo "@reboot nohup bash ${DIR}/core/standalone_daemon.sh >> ${DIR}/logs/daemon.log 2>&1 &" >> /tmp/cron_clean
crontab /tmp/cron_clean && rm -f /tmp/cron_clean

# 初始化并启动
echo $(date +%s) > "${DIR}/core/.ua_last_update"
nohup bash "${DIR}/core/standalone_daemon.sh" >> "${DIR}/logs/daemon.log" 2>&1 &

echo -e "\n================================"
echo "🎉 部署完成!"
echo "📍 区域: $REGION_NAME"
echo "🔐 引擎: $CURL_IMP"
echo "📜 日志: tail -f ${DIR}/logs/sentinel.log"
echo "================================"
