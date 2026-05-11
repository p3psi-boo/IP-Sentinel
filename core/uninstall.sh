#!/bin/bash
# IP-Sentinel 卸载脚本

DIR="/opt/ip_sentinel"

echo "卸载 IP-Sentinel..."

# 停止并禁用 systemd timer
if command -v systemctl >/dev/null 2>&1; then
    systemctl stop ip-sentinel.timer 2>/dev/null || true
    systemctl disable ip-sentinel.timer 2>/dev/null || true
    systemctl stop ip-sentinel.service 2>/dev/null || true
    rm -f /etc/systemd/system/ip-sentinel.service /etc/systemd/system/ip-sentinel.timer
    systemctl daemon-reload 2>/dev/null || true
fi

# 兜底：停止可能正在执行的 worker
for p in standalone_worker mod_google mod_trust; do
    pkill -9 -f "$p" 2>/dev/null || true
done

# 清理旧版本残留的 crontab
crontab -l 2>/dev/null | grep -v ip_sentinel > /tmp/cron_clean 2>/dev/null || true
crontab /tmp/cron_clean 2>/dev/null || true
rm -f /tmp/cron_clean

# 删除文件
rm -rf "$DIR" /tmp/ip_sentinel_*

echo "✅ 卸载完成"
