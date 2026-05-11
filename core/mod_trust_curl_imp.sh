#!/bin/bash
# IP-Sentinel Trust 模块 - curl-impersonate 版

set -e

DIR="/opt/ip_sentinel"
CFG="${DIR}/config.conf"
[ -f "$CFG" ] || exit 1
source "$CFG"

REGION="${REGION_CODE:-US}"

# 加载工具函数
UTILS="${DIR}/core/utils.sh"
[ -f "$UTILS" ] || { echo "utils.sh missing"; exit 1; }
source "$UTILS"

# 检测 curl-impersonate
CURL=$(detect_curl_imp) || { echo "curl-impersonate not found" >&2; exit 1; }

log() { log_sentinel "$1" "Trust" "$REGION" "$2"; }

# 白名单来自 config.conf 的 WHITE_URLS 数组
URLS=("${WHITE_URLS[@]}")
[ ${#URLS[@]} -eq 0 ] && URLS=("https://en.wikipedia.org/wiki/Special:Random" "https://www.apple.com/" "https://www.microsoft.com/")

# 生成此会话的 UA
SESSION_UA=$(generate_ua "random")
log "START" "净化 [$CURL] | ${#URLS[@]}个站点 | UA:${SESSION_UA:0:30}..."

# curl 选项
CURL_OPTS=""
IP_FLAG="-${IP_PREF:-4}"
if [ -n "$BIND_IP" ]; then
    CURL_OPTS="--interface $(echo "$BIND_IP" | tr -d '[]')"
    [[ "$BIND_IP" == *":"* ]] && IP_FLAG="-6" || IP_FLAG="-4"
fi

# 执行
STEPS=$((RANDOM % 4 + 3))
SUCCESS=0

i=1
while [ $i -le $STEPS ]; do
    url=${URLS[$RANDOM % ${#URLS[@]}]}
    code=$($CURL $CURL_OPTS $IP_FLAG -s -o /dev/null -w "%{http_code}" -m 15 -H "User-Agent: $SESSION_UA" "$url")

    if [[ "$code" =~ ^(20[0-9]|30[1-8])$ ]]; then
        log "EXEC" "[$i/$STEPS] $code | $url"
        SUCCESS=$((SUCCESS + 1))
    else
        log "EXEC" "[$i/$STEPS] 失败 $code | $url"
    fi

    [ $i -lt $STEPS ] && sleep $((RANDOM % 76 + 45))
    i=$((i + 1))
done

[ $SUCCESS -ge $((STEPS / 2)) ] && log "SCORE" "完成 $SUCCESS/$STEPS" || log "SCORE" "受阻 $SUCCESS/$STEPS"
log "END" "会话结束"
