#!/bin/bash
# IP-Sentinel 热更新 - 简化版 (数据已改为运行时获取)

set -e

DIR="/opt/ip_sentinel"
CFG="${DIR}/config.conf"

[ -f "$CFG" ] || exit 1
source "$CFG"

log() {
    printf "[%s] [v%s] [%s] [Updater] [%s] %s\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" "${AGENT_VERSION:-未知}" "$1" "$REGION_CODE" "$2" >> "$LOG_FILE"
}

log "INFO" "开始维护"

# 日志瘦身 (保留2000行)
if [ -f "$LOG_FILE" ]; then
    local lines=$(wc -l < "$LOG_FILE")
    if [ "$lines" -gt 2000 ]; then
        tail -n 2000 "$LOG_FILE" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
        log "INFO" "日志清理完成 (保留2000行)"
    fi
fi

# 检查核心文件完整性
for file in utils.sh mod_google_curl_imp.sh mod_trust_curl_imp.sh standalone_daemon.sh; do
    if [ ! -f "${DIR}/core/$file" ]; then
        log "WARN" "核心文件缺失: $file"
    fi
done

# 检查目录结构
[ ! -d "${DIR}/logs" ] && mkdir -p "${DIR}/logs" && log "INFO" "创建日志目录"
[ ! -d "${DIR}/data" ] && mkdir -p "${DIR}/data" && log "INFO" "创建数据目录"

log "INFO" "维护结束"
