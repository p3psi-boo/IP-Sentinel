#!/bin/bash
# IP-Sentinel Trust 模块 - curl-impersonate 版

set -e

DIR="/opt/ip_sentinel"
CFG="${DIR}/config.conf"
[ -f "$CFG" ] || exit 1
source "$CFG"

REGION="${REGION_CODE:-US}"

# 检测 curl-impersonate
for cmd in curl_chrome125 curl_chrome131 curl_chrome120 curl_chrome116 curl_chrome; do
    command -v "$cmd" >/dev/null 2>&1 && { CURL="$cmd"; break; }
done
[ -z "$CURL" ] && { echo "curl-impersonate not found" >&2; exit 1; }

log() {
    printf "[%s] [v%s] [%s] [Trust] [%s] %s\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" "${AGENT_VERSION:-3.4.0}" "$1" "$REGION" "$2" | tee -a "${DIR}/logs/sentinel.log"
}

# 加载白名单
JSON=$(find "${DIR}/data/regions" -name "*.json" 2>/dev/null | head -n1)
[ -f "$JSON" ] && mapfile -t URLS < <(jq -r '.trust_module.white_urls[]' "$JSON" 2>/dev/null)

# 兜底
[ ${#URLS[@]} -eq 0 ] && URLS=("https://en.wikipedia.org/wiki/Special:Random" "https://www.apple.com/" "https://www.microsoft.com/")

log "START" "净化 [$CURL] | ${#URLS[@]}个站点"

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
    code=$($CURL $CURL_OPTS $IP_FLAG -s -o /dev/null -w "%{http_code}" -m 15 "$url")

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
