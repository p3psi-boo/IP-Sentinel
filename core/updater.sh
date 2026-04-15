#!/bin/bash
# IP-Sentinel 热数据更新

set -e

DIR="/opt/ip_sentinel"
CFG="${DIR}/config.conf"
UA_TS="${DIR}/core/.ua_last_update"
REPO="https://raw.githubusercontent.com/hotyue/IP-Sentinel/main"

[ -f "$CFG" ] || exit 1
source "$CFG"

log() {
    printf "[%s] [v%s] [%s] [Updater] [%s] %s\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" "${AGENT_VERSION:-未知}" "$1" "$REGION_CODE" "$2" >> "$LOG_FILE"
}

log "INFO" "开始更新"

# curl 基础命令
CURL="curl -${IP_PREF:-4} -sL"
[ -n "$BIND_IP" ] && CURL="$CURL --interface $(echo "$BIND_IP" | tr -d '[]')"

# UA 指纹库 (30天周期)
NOW=$(date +%s)
LAST=$(cat "$UA_TS" 2>/dev/null | tr -d '\r\n')
[[ "$LAST" =~ ^[0-9]+$ ]] || LAST=0

if [ $((NOW - LAST)) -ge 2592000 ] || [ "$LAST" -eq 0 ]; then
    TMP="/tmp/ip_sentinel_ua.txt"
    $CURL "${REPO}/data/user_agents.txt" -o "$TMP"
    if [ -s "$TMP" ]; then
        mv "$TMP" "${DIR}/data/user_agents.txt"
        echo "$NOW" > "$UA_TS"
        log "INFO" "UA库更新成功"
    else
        log "WARN" "UA库拉取失败"
        rm -f "$TMP"
    fi
else
    log "INFO" "UA库静默期剩余 $(((2592000 - NOW + LAST) / 86400)) 天"
fi

# 搜索词库 (每日)
TMP="/tmp/ip_sentinel_kw.txt"
$CURL "${REPO}/data/keywords/kw_${REGION_CODE}.txt" -o "$TMP"
if [ -s "$TMP" ]; then
    mv "$TMP" "${DIR}/data/keywords/kw_${REGION_CODE}.txt"
    log "INFO" "词库(kw_${REGION_CODE})更新成功"
else
    log "WARN" "词库拉取失败"
    rm -f "$TMP"
fi

# 区域规则库
JSON=$(find "${DIR}/data/regions" -name "*.json" 2>/dev/null | head -n1)
if [ -n "$JSON" ]; then
    REL=${JSON#*${DIR}/}
    TMP="/tmp/ip_sentinel_region.json"
    $CURL "${REPO}/${REL}" -o "$TMP"
    if [ -s "$TMP" ]; then
        mv "$TMP" "$JSON"
        log "INFO" "区域规则更新成功"
    else
        log "WARN" "区域规则拉取失败"
        rm -f "$TMP"
    fi
fi

# 日志瘦身 (保留2000行)
if [ -f "$LOG_FILE" ]; then
    tail -n 2000 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
    log "INFO" "日志清理完成"
fi

log "INFO" "更新结束"
