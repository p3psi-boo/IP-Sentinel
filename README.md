# IP-Sentinel

在单台 VPS 上自动运行 IP 养护，模拟真实用户访问 Google 和白名单站点，纠正 IP 地理定位误判。

## 安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/install_standalone.sh)
```

安装自动检测 VPS 地理位置，交互式选择模块和 IP 协议。

## 依赖

- [curl-impersonate](https://github.com/lwthiker/curl-impersonate)（`curl_chrome*` 命令）
- `systemd`, `curl`, `jq`, `procps`

## 查看日志

```bash
journalctl -u ip-sentinel -f
```

## 配置

编辑 `/opt/ip_sentinel/config.conf`，修改后 `systemctl daemon-reload`。

```bash
ENABLE_GOOGLE="true"    # Google 纠偏
ENABLE_TRUST="true"     # Trust 净化
IP_PREF="4"             # 4=IPv4, 6=IPv6
BIND_IP="1.2.3.4"       # NAT 环境留空
```

## 卸载

```bash
bash /opt/ip_sentinel/core/uninstall.sh
```

## 调度机制

systemd timer 每小时 08:00-22:00 唤醒一次 oneshot worker。基于日期种子生成 1-3 个执行窗口，命中则随机延迟 5-15 分钟后执行，当天重启计划不变。

### 推荐的 systemd 配置

`/etc/systemd/system/ip-sentinel.service`

```ini
[Unit]
Description=IP-Sentinel IP maintenance worker
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/ip_sentinel/core/standalone_worker.sh
Nice=19
StandardOutput=journal
StandardError=journal
```

`/etc/systemd/system/ip-sentinel.timer`

```ini
[Unit]
Description=IP-Sentinel hourly check (08:00-22:00)

[Timer]
OnCalendar=*-*-* 08..22:00:00
AccuracySec=5min
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
```

说明：
- `Nice=19`：养护任务以低优先级运行，不抢占业务资源
- `AccuracySec=5min`：放宽触发精度，避免 systemd 过度聚合调度
- `RandomizedDelaySec=300`：各 VPS 实际触发时间分散在 ±5 分钟内，避免全局并发尖峰
- `Persistent=true`：系统关机期间错过的触发，下次开机后会补执行

应用配置：

```bash
systemctl daemon-reload
systemctl enable --now ip-sentinel.timer
```

## 添加新区域

在 `install_standalone.sh` 的 `case` 表中新增国家分支，填入 `VALID_URL_SUFFIX`、`LANG_PARAMS`、`WHITE_URLS`。

## 版本

`3.4.0` | AGPL-3.0
