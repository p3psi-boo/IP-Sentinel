#!/bin/bash
# IP-Sentinel Google 模块 - curl-impersonate 版

set -e

CFG="/opt/ip_sentinel/config.conf"
[ -f "$CFG" ] || { echo "Config missing"; exit 1; }
source "$CFG"

# 检测 curl-impersonate
for cmd in curl_chrome125 curl_chrome131 curl_chrome120 curl_chrome116 curl_chrome; do
    command -v "$cmd" >/dev/null 2>&1 && { CURL="$cmd"; break; }
done
[ -z "$CURL" ] && { echo "curl-impersonate not found"; exit 1; }

log() {
    printf "[%s] [v%s] [%s] [Google] [%s] %s\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" "${AGENT_VERSION:-3.4.0}" "$1" "$REGION_CODE" "$2" >> "${INSTALL_DIR}/logs/sentinel.log"
}

log "INFO" "启动 [$CURL] | 区域: $REGION_NAME"

# 加载搜索词库
KW_FILE="${INSTALL_DIR}/data/keywords/kw_${REGION_CODE}.txt"
[ -f "$KW_FILE" ] || { log "ERROR" "词库缺失"; exit 1; }
mapfile -t KEYWORDS < <(grep -v '^$' "$KW_FILE")

# 坐标抖动: base, range(米)
jitter() {
    awk "BEGIN {print $1 + ((($RANDOM % 2000) - 1000) / 1000000)}"
}

IP="${PUBLIC_IP:-${BIND_IP:-Unknown}}"
LAT=$(jitter "$BASE_LAT" 270)
LON=$(jitter "$BASE_LON" 270)
ACTIONS=$((6 + RANDOM % 5))

log "INFO" "IP: $IP | 坐标: $LAT, $LON | 动作: $ACTIONS"

# curl 选项
CURL_OPTS=""
IP_FLAG="-${IP_PREF:-4}"
if [ -n "$BIND_IP" ]; then
    CURL_OPTS="--interface $(echo "$BIND_IP" | tr -d '[]')"
    [[ "$BIND_IP" == *":"* ]] && IP_FLAG="-6" || IP_FLAG="-4"
    log "INFO" "绑定: $BIND_IP ($IP_FLAG)"
fi

# 执行动作
i=1
while [ $i -le $ACTIONS ]; do
    # 随机参数
    local_lat=$(jitter "$LAT" 1)
    local_lon=$(jitter "$LON" 1)
    kw=$(echo "${KEYWORDS[$RANDOM % ${#KEYWORDS[@]}]}" | jq -sRr @uri)

    # 构建 URL
    case $((1 + RANDOM % 4)) in
        1) url="https://www.google.com/search?q=${kw}&${LANG_PARAMS}" ;;
        2) url="https://news.google.com/home?${LANG_PARAMS}" ;;
        3) url="https://www.google.com/maps/search/${kw}/@${local_lat},${local_lon},17z?${LANG_PARAMS}" ;;
        4) url="https://connectivitycheck.gstatic.com/generate_204" ;;
    esac

    code=$($CURL $CURL_OPTS $IP_FLAG -m 15 -s -L -o /dev/null -w "%{http_code}" "$url")
    log "EXEC" "[$i/$ACTIONS] HTTP:$code | $local_lat,$local_lon"

    # 休眠 (非最后一次)
    if [ $i -lt $ACTIONS ]; then
        sleep $((90 + RANDOM % 61))
    fi
    i=$((i + 1))
done

# 自检
probe=$($CURL $CURL_OPTS $IP_FLAG -m 15 -s -L -o /dev/null -w "%{http_code}|%{url_effective}" https://www.google.com)
code=$(echo "$probe" | cut -d'|' -f1)
url=$(echo "$probe" | cut -d'|' -f2)

if [ "$code" == "000" ] || [ -z "$url" ]; then
    status="🚨 网络阻断"
else
    suffix=$(echo "$url" | awk -F/ '{print $3}' | sed 's/.*google\.//')
    if [ "$suffix" == "$VALID_URL_SUFFIX" ] || [ "$suffix" == "com" ]; then
        status="✅ 目标达成 ($suffix)"
    elif [ "$suffix" == "com.hk" ] && [ "$REGION_CODE" == "HK" ]; then
        status="✅ HK达成"
    elif [ "$suffix" == "com.hk" ]; then
        status="❌ 送中漂移"
    else
        status="⚠️ 漂移 ($suffix)"
    fi
fi

log "SCORE" "$status"
log "END" "会话结束"
