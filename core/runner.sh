#!/bin/bash

# ==========================================================
# 脚本名称: runner.sh (IP-Sentinel 主控调度引擎 V2.0 智能分配版)
# 核心功能: 防并发延迟启动、功能开关(Feature Flag)自适应、多模块概率轮盘调度
# ==========================================================

INSTALL_DIR="/opt/ip_sentinel"
CONFIG_FILE="${INSTALL_DIR}/config.conf"

# 1. 检查并加载本地冷数据配置
if [ ! -f "$CONFIG_FILE" ]; then
    echo "配置文件丢失，请重新运行 install.sh"
    exit 1
fi
source "$CONFIG_FILE"

# 2. 全局日志写入函数 (导出给子进程共享使用)
log() {
    local module=$1
    local level=$2
    local msg=$3
    # 保证日志目录存在
    mkdir -p "${INSTALL_DIR}/logs"
    printf "[$(date '+%Y-%m-%d %H:%M:%S')] [%-5s] [%-7s] [%s] %s\n" "$level" "$module" "$REGION_CODE" "$msg" >> "$LOG_FILE"
}
export -f log
export CONFIG_FILE INSTALL_DIR

# 3. 防僵尸网络特征 (Cron Jitter) - 核心隐蔽逻辑
# 配合每 30 分钟的调度周期，将随机休眠控制在 0 到 180 秒 (3分钟) 内，彻底打散全球并发请求
JITTER_TIME=$((RANDOM % 180))
log "SYSTEM" "INFO" "主控引擎被 Cron 唤醒，进入防并发随机休眠状态: ${JITTER_TIME} 秒..."
sleep $JITTER_TIME

# 4. 唤醒并读取功能开关，执行智能调度 (Feature Flag)
log "SYSTEM" "INFO" "休眠结束，开始计算本轮任务轮盘..."

TARGET_MOD=""
MOD_NAME=""

# 智能轮盘赌算法
if [ "$ENABLE_GOOGLE" == "true" ] && [ "$ENABLE_TRUST" == "true" ]; then
    # 双管齐下: 70% 概率跑 Google 稳固定位，30% 概率跑 Trust 洗刷风控分
    ROLL=$((RANDOM % 100 + 1))
    if [ $ROLL -le 70 ]; then
        TARGET_MOD="mod_google.sh"
        MOD_NAME="Google 区域纠偏"
    else
        TARGET_MOD="mod_trust.sh"
        MOD_NAME="IP 信用净化"
    fi
elif [ "$ENABLE_GOOGLE" == "true" ]; then
    TARGET_MOD="mod_google.sh"
    MOD_NAME="Google 区域纠偏"
elif [ "$ENABLE_TRUST" == "true" ]; then
    TARGET_MOD="mod_trust.sh"
    MOD_NAME="IP 信用净化"
else
    log "SYSTEM" "WARN" "节点未开启任何养护模块，跳过本轮执行。"
    exit 0
fi

# 5. 拉起选定的业务模块
if [ -n "$TARGET_MOD" ] && [ -x "${INSTALL_DIR}/core/${TARGET_MOD}" ]; then
    log "SYSTEM" "INFO" "命中触发条件，加载并执行子模块: ${MOD_NAME}"
    # 核心降耗逻辑：使用 nice -n 19 赋予进程最低 CPU 优先级，绝不抢占 VPS 正常业务的资源
    nice -n 19 bash "${INSTALL_DIR}/core/${TARGET_MOD}"
else
    log "SYSTEM" "ERROR" "配置了模块 ${MOD_NAME}，但未找到对应的可执行脚本: ${TARGET_MOD}"
fi

log "SYSTEM" "INFO" "本轮所有模块调度完毕，哨兵继续隐蔽待命。"