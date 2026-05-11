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

## 添加新区域

在 `install_standalone.sh` 的 `case` 表中新增国家分支，填入 `VALID_URL_SUFFIX`、`LANG_PARAMS`、`WHITE_URLS`。

## 版本

`3.4.0` | AGPL-3.0
