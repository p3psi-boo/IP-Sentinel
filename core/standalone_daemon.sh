#!/bin/bash
# IP-Sentinel 单机自治 Daemon (stateless)
#
# 无状态设计：
# - 不写入任何状态文件（无 .daemon_state）
# - 日志输出到 stdout，由外部重定向管理
# - 调度基于日期种子生成固定执行窗口，每小时检查一次
# - 重启后计划不变（同一天内日期种子不变）

set -e

DIR="/opt/ip_sentinel"
CFG="${DIR}/config.conf"

[ -f "$CFG" ] || { echo "Config missing"; exit 1; }
source "$CFG"

# 加载工具函数
UTILS="${DIR}/core/utils.sh"
[ -f "$UTILS" ] || { echo "utils.sh missing"; exit 1; }
source "$UTILS"

# 检测 curl-impersonate
CURL=$(detect_curl_imp) || { echo "curl-impersonate required"; exit 1; }

log() { log_sentinel "$1" "Daemon" "$REGION_CODE" "$2"; }

# 获取本地小时
get_local_hour() {
    TZ="${TIMEZONE:-UTC}" date +%H
}

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

# 执行养护
maintain() {
    log "INFO" "开始养护 [$CURL]"

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
}

cleanup() { log "STOP" "Daemon退出"; exit 0; }
trap cleanup SIGTERM SIGINT

log "START" "Daemon启动 [$CURL] | 区域: $REGION_CODE"

while true; do
    h=$(get_local_hour)
    schedule=$(get_schedule)

    if [ $h -ge 8 ] && [ $h -lt 22 ]; then
        if [ -n "$schedule" ] && echo "$schedule" | grep -qx "$h"; then
            jitter=$((RANDOM % 600 + 300))
            log "INFO" "命中计划 ${h}:00，延迟 ${jitter}s"
            sleep $jitter
            maintain
        fi
        sleep 3600
    else
        log "INFO" "非活动时段 (${h}:00)"
        sleep $(( (24 - h + 8) * 3600 + RANDOM % 1800 ))
    fi
done
