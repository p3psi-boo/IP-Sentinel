#!/bin/bash
# IP-Sentinel Worker (systemd oneshot)
#
# 无状态设计：
# - 不写入任何状态文件
# - 日志输出到 stdout，由 systemd journal 捕获
# - 每次执行后自动退出，由 systemd timer 每小时唤醒

set -e

DIR="/opt/ip_sentinel"
CFG="${DIR}/config.conf"

[ -f "$CFG" ] || { echo "Config missing"; exit 1; }
source "$CFG"

# 加载工具函数
UTILS="${DIR}/core/utils.sh"
[ -f "$UTILS" ] || { echo "utils.sh missing"; exit 1; }
source "$UTILS"

log() { log_sentinel "$1" "Worker" "$REGION_CODE" "$2"; }

# 生成今日执行计划（1-3个执行小时，基于日期种子）
get_schedule() {
    local seed=$(($(echo "$(date +%Y%m%d)$REGION_CODE" | cksum | awk '{print $1}') % 100))
    if [ $seed -ge 60 ]; then
        return  # 今日休息
    fi
    local count=$(( ($(echo "$(date +%Y%m%d)" | cksum | awk '{print $1}') % 3) + 1 ))
    local i
    for i in $(seq 1 $count); do
        local h=$(( 8 + $(echo "$(date +%Y%m%d)$i" | cksum | awk '{print $1}') % 14 ))
        echo $h
    done | sort -u
}

h=$(TZ="${TIMEZONE:-UTC}" date +%H)
schedule=$(get_schedule)

# 当前小时不匹配 → 无事发生，直接退出
[ -n "$schedule" ] && echo "$schedule" | grep -qx "$h" || exit 0

# 命中窗口：随机延迟后执行
jitter=$((RANDOM % 600 + 300))
log "INFO" "命中计划 ${h}:00，延迟 ${jitter}s"
sleep $jitter

# 检测 curl-impersonate
CURL=$(detect_curl_imp) || { log "WARN" "curl-impersonate 未找到"; exit 1; }

# 选模块
local mod=""
if [ "$ENABLE_GOOGLE" == "true" ] && [ "$ENABLE_TRUST" == "true" ]; then
    [ $((RANDOM % 100)) -le 70 ] && mod="mod_google_curl_imp.sh" || mod="mod_trust_curl_imp.sh"
elif [ "$ENABLE_GOOGLE" == "true" ]; then
    mod="mod_google_curl_imp.sh"
elif [ "$ENABLE_TRUST" == "true" ]; then
    mod="mod_trust_curl_imp.sh"
fi

[ -n "$mod" ] && [ -x "${DIR}/core/$mod" ] && { log "INFO" "执行: $mod"; nice -n 19 bash "${DIR}/core/$mod"; } || log "WARN" "无可用模块"

log "INFO" "养护结束"
