#!/bin/bash

# ==========================================================
# 脚本名称: uninstall_master.sh (IP-Sentinel Master 一键卸载脚本 v3.4.0)
# 核心功能: 终止调度进程、清理看门狗定时任务、抹除数据库与配置
# ==========================================================

MASTER_DIR="/opt/ip_sentinel_master"
CONF_FILE="${MASTER_DIR}/master.conf"

echo "========================================================"
echo "      🗑️ 准备卸载 IP-Sentinel Master (控制中枢)"

# [v3.4.0 优化] 卸载前读取并播报中枢版本号
if [ -f "$CONF_FILE" ]; then
    MASTER_VER=$(grep "^MASTER_VERSION=" "$CONF_FILE" | cut -d'"' -f2)
    [ -n "$MASTER_VER" ] && echo "        📍 目标版本: v${MASTER_VER}"
fi
echo "========================================================"

echo -e "\n⚠️ 警告: 此操作将永久删除包含所有节点档案的 SQLite 数据库！"
read -p "确定要继续卸载吗？(y/n) [默认 n]: " CONFIRM_DEL
if [[ ! "$CONFIRM_DEL" =~ ^[Yy]$ ]]; then
    echo "已取消卸载操作。"
    exit 0
fi

# 1. 停止运行中的 Master 守护进程
echo "[1/3] 正在终止后台中枢调度进程..."
pgrep -f tg_master.sh | xargs -r kill -9 >/dev/null 2>&1

# 2. 清除看门狗定时任务 (Cron)
echo "[2/3] 正在清理系统定时任务 (Cron)..."
crontab -l 2>/dev/null | grep -v "tg_master.sh" > /tmp/cron_backup
crontab /tmp/cron_backup
rm -f /tmp/cron_backup

# 3. 删除所有文件、配置与数据库
echo "[3/3] 正在抹除核心程序、配置文件与 SQLite 数据库..."
if [ -d "$MASTER_DIR" ]; then
    rm -rf "$MASTER_DIR"
fi

echo "========================================================"
echo "✅ 卸载彻底完成！Master 司令部已从您的系统中无痕移除。"
echo "========================================================"