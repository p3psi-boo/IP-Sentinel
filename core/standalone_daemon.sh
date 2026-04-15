#!/bin/bash
# IP-Sentinel 单机自治 Daemon

set -e

DIR="/opt/ip_sentinel"
CFG="${DIR}/config.conf"
STATE="${DIR}/core/.daemon_state"

[ -f "$CFG" ] || { echo "Config missing"; exit 1; }
source "$CFG"

# 检测 curl-impersonate
for cmd in curl_chrome125 curl_chrome131 curl_chrome120 curl_chrome116 curl_chrome; do
    command -v "$cmd" >/dev/null 2>&1 && { CURL="$cmd"; break; }
done
[ -z "$CURL" ] && { echo "curl-impersonate required"; exit 1; }

# 时区转小时
get_local_hour() {
    local off=$(case "$REGION_CODE" in "US") echo -7;; "JP") echo +9;; "UK") echo +1;; "DE"|"FR") echo +2;; *) echo +8;; esac)
    local h=$(( $(date -u +%H) + off ))
    [ $h -lt 0 ] && h=$((24 + h)) || [ $h -ge 24 ] && h=$((h - 24))
    echo $h
}

log() {
    printf "[%s] [v%s] [%s] [Daemon] [%s] %s\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" "${AGENT_VERSION:-3.4.0}" "$1" "$REGION_CODE" "$2" >> "${DIR}/logs/sentinel.log"
}

# 检查是否在活动时段 (8-22点)
in_active() {
    local h=$(get_local_hour)
    [ $h -ge 8 ] && [ $h -lt 22 ]
}

# 今日是否执行 (60%概率)
should_run() {
    local seed=$(($(echo "$(date +%Y%m%d)$REGION_CODE" | cksum | awk '{print $1}') % 100))
    [ $seed -lt 60 ]
}

# 计划执行次数 (1-3次)
planned() {
    echo $(( ($(date +%Y%m%d | cksum | awk '{print $1}') % 3) + 1 ))
}

# 已完成次数
completed() {
    local today=$(date +%Y%m%d)
    [ -f "$STATE" ] && [ "$(head -n1 "$STATE")" == "$today" ] && tail -n1 "$STATE" || echo "0"
}

# 更新计数
update() {
    printf "%s\n%s\n" "$(date +%Y%m%d)" "$1" > "$STATE"
}

# 到明早8点的秒数
to_morning() {
    local h=$(get_local_hour)
    echo $(( (24 - h + 8) * 3600 + RANDOM % 1800 ))
}

# 执行养护
maintain() {
    log "INFO" "开始养护 [$CURL]"

    [ -x "${DIR}/core/updater.sh" ] && bash "${DIR}/core/updater.sh" >/dev/null 2>&1

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
    today=$(date +%Y%m%d)
    done=$(completed)

    # 新的一天重置
    [ ! -f "$STATE" ] || [ "$(head -n1 "$STATE" 2>/dev/null)" != "$today" ] && { done=0; log "INFO" "新的一天"; }

    if in_active; then
        if should_run; then
            plan=$(planned)
            log "INFO" "计划 $plan 次，已完成 $done 次"

            if [ $done -lt $plan ]; then
                jitter=$((RANDOM % 600 + 300))
                log "INFO" "延迟 ${jitter}s"
                sleep $jitter

                maintain
                done=$((done + 1))
                update $done

                if [ $done -lt $plan ]; then
                    log "INFO" "下次: $(( (7200 + RANDOM % 7200) / 3600 ))小时后"
                    sleep $((7200 + RANDOM % 7200))
                else
                    log "INFO" "今日完成"
                    sleep $(to_morning)
                fi
            else
                sleep $(to_morning)
            fi
        else
            log "INFO" "今日休息"
            sleep $(to_morning)
        fi
    else
        log "INFO" "非活动时段 ($(get_local_hour):00)"
        sleep $(to_morning)
    fi
done
