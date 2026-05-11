# IP-Sentinel

> **注意**：当前版本为单机自治版，每个 VPS 独立运行。没有远程控制节点，也无需注册。

IP-Sentinel 是一套在单台 VPS 上自动运行的 IP 养护脚本，通过模拟真实用户访问 Google 和白名单站点，纠正 IP 地理定位误判问题。

## 快速开始

### 1. 安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/install_standalone.sh)
```

安装过程会自动检测 VPS 的地理位置（国家、城市、坐标、时区），并交互式询问：
- 选择模块（Google 纠偏 / Trust 净化 / 双开）
- 选择 IP 协议（IPv4/IPv6）

### 2. 依赖要求

**必须**：
- [curl-impersonate](https://github.com/lwthiker/curl-impersonate)（提供 `curl_chrome*` 命令）

**系统自带或自动安装**：
- `curl`, `jq`, `cron`, `procps`

### 3. 查看状态

```bash
tail -f /opt/ip_sentinel/logs/daemon.log
```

日志格式示例：
```
[2025-01-15 14:30:25] [v3.4.0] [INFO] [Daemon] [US] 启动 [curl_chrome125]
[2025-01-15 14:30:45] [v3.4.0] [EXEC] [Google] [US] [1/8] HTTP:200 | 34.0522,-118.2439
[2025-01-15 14:30:45] [v3.4.0] [SCORE] [Google] [US] ✅ 目标达成 (com)
```

### 4. 配置调整

编辑 `/opt/ip_sentinel/config.conf`：

```bash
ENABLE_GOOGLE="true"       # Google 纠偏模块
ENABLE_TRUST="true"         # Trust 净化模块
IP_PREF="4"                  # 优先协议 4=IPv4, 6=IPv6
BIND_IP="1.2.3.4"            # 绑定 IP（NAT 环境留空）
```

修改后重启：
```bash
pkill -f standalone_daemon
nohup bash /opt/ip_sentinel/core/standalone_daemon.sh >> /opt/ip_sentinel/logs/daemon.log 2>&1 &
```

### 5. 卸载

```bash
bash /opt/ip_sentinel/core/uninstall.sh
```

---

## 开发者文档

### 设计哲学：Stateless

IP-Sentinel 在运行时不向磁盘写入任何状态文件：
- 无 `.daemon_state` 计数器：调度基于**日期种子**生成固定执行窗口
- 无内部日志文件写入：全部输出到 **stdout**，由外部重定向管理（systemd/docker/cron）
- 无 `updater.sh`：没有需要维护的本地数据缓存
- 安装后磁盘上只保留静态配置 (`config.conf`) 和代码 (`core/*.sh`)

### 代码结构

```
IP-Sentinel/
├── core/
│   ├── standalone_daemon.sh    # 主调度器
│   ├── mod_google_curl_imp.sh  # Google 模块
│   ├── mod_trust_curl_imp.sh   # Trust 模块
│   ├── utils.sh                # 共享工具
│   └── uninstall.sh            # 清理脚本
├── install_standalone.sh       # 安装入口
└── version.txt
```

### 调度逻辑

守护进程每小时检查一次（`sleep 3600`）：

1. **日期种子**：`$(date +%Y%m%d)$REGION_CODE` 生成今日计划
2. **休息概率**：40% 概率今日完全休息
3. **执行窗口**：休息日外，生成 1-3 个随机执行小时（08-22）
4. **命中执行**：当前小时匹配窗口时，随机延迟 300-900 秒后执行
5. **自然冷却**：执行后睡 3600 秒到下一检查点，避免密集触发
6. **重启安全**：同一天内重启计划不变（种子基于日期），不会重复执行同一窗口

### 扩展开发

**添加新区域**：
在 `install_standalone.sh` 的 `case` 规则表中新增国家代码分支，填入：
- `VALID_URL_SUFFIX`（Google 域名后缀）
- `LANG_PARAMS`（搜索语言参数）
- `WHITE_URLS`（当地白名单站点，用 `|` 分隔）

安装脚本通过 `api.ip.sb/geoip` 自动检测新国家的 VPS 坐标，无需维护静态数据文件。

---

## 版本

当前版本：`3.4.0`

## 许可证

AGPL-3.0
