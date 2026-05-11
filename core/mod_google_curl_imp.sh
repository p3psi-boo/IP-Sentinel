#!/bin/bash
# IP-Sentinel Google 模块 - curl-impersonate 版 (运行时数据版)

set -e

DIR="/opt/ip_sentinel"
CFG="${DIR}/config.conf"
[ -f "$CFG" ] || { echo "Config missing"; exit 1; }
source "$CFG"

# 加载工具函数
UTILS="${DIR}/core/utils.sh"
[ -f "$UTILS" ] && source "$UTILS"

# 检测 curl-impersonate
for cmd in curl_chrome131 curl_chrome130 curl_chrome129 curl_chrome128 curl_chrome125 curl_chrome120 curl_chrome116 curl_chrome; do
    command -v "$cmd" >/dev/null 2>&1 && { CURL="$cmd"; break; }
done
[ -z "$CURL" ] && { echo "curl-impersonate not found"; exit 1; }

log() {
    printf "[%s] [v%s] [%s] [Google] [%s] %s\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" "${AGENT_VERSION:-3.4.0}" "$1" "$REGION_CODE" "$2" >> "${DIR}/logs/sentinel.log"
}

log "INFO" "启动 [$CURL] | 区域: $REGION_NAME"

# 实时拉取关键词
log "INFO" "正在拉取实时趋势数据..."
KEYWORDS=$(fetch_trends_live "$REGION_CODE")

# 如果拉取失败，使用备用词库
if [ -z "$KEYWORDS" ]; then
    log "WARN" "实时趋势拉取失败，使用备用词库"
    KEYWORDS="weather
news
maps
gmail
translate"
fi

# 转换为数组
mapfile -t KEYWORD_ARRAY <<< "$KEYWORDS"
log "INFO" "关键词库: ${#KEYWORD_ARRAY[@]} 条"

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

# 生成随机 UA 用于此会话
SESSION_UA=$(generate_ua "random")
log "INFO" "UA: ${SESSION_UA:0:50}..."

# 执行动作
i=1
while [ $i -le $ACTIONS ]; do
    # 随机参数
    local_lat=$(jitter "$LAT" 1)
    local_lon=$(jitter "$LON" 1)
    kw_idx=$((RANDOM % ${#KEYWORD_ARRAY[@]}))
    kw="${KEYWORD_ARRAY[$kw_idx]}"
    # URL 编码关键词
    kw_encoded=$(printf '%s' "$kw" | jq -sRr @uri 2>/dev/null || echo "$kw")

    # 构建 URL
    case $((1 + RANDOM % 4)) in
        1) url="https://www.google.com/search?q=${kw_encoded}&${LANG_PARAMS}" ;;
        2) url="https://news.google.com/home?${LANG_PARAMS}" ;;
        3) url="https://www.google.com/maps/search/${kw_encoded}/@${local_lat},${local_lon},17z?${LANG_PARAMS}" ;;
        4) url="https://connectivitycheck.gstatic.com/generate_204" ;;
    esac

    code=$($CURL $CURL_OPTS $IP_FLAG -m 15 -s -L -o /dev/null -w "%{http_code}" -H "User-Agent: $SESSION_UA" "$url")
    log "EXEC" "[$i/$ACTIONS] HTTP:$code | $local_lat,$local_lon | kw:${kw:0:15}"

    # 休眠 (非最后一次)
    if [ $i -lt $ACTIONS ]; then
        sleep $((90 + RANDOM % 61))
    fi
    i=$((i + 1))
done

# 自检
probe=$($CURL $CURL_OPTS $IP_FLAG -m 15 -s -L -o /dev/null -w "%{http_code}|%{url_effective}" -H "User-Agent: $SESSION_UA" https://www.google.com)
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
