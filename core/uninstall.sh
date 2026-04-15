#!/bin/bash
# IP-Sentinel 卸载脚本

DIR="/opt/ip_sentinel"

echo "卸载 IP-Sentinel..."

# 停止进程
for p in tg_daemon agent_daemon standalone_daemon webhook runner updater tg_report mod_google mod_trust; do
    pkill -9 -f "$p" 2>/dev/null || true
done

# 清理定时任务
crontab -l 2>/dev/null | grep -v ip_sentinel > /tmp/cron_clean 2>/dev/null || true
crontab /tmp/cron_clean 2>/dev/null || true
rm -f /tmp/cron_clean

# 删除文件
rm -rf "$DIR" /tmp/ip_sentinel_*

echo "✅ 卸载完成"
