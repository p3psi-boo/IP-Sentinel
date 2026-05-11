# IP-Sentinel

> **注意**：当前版本为单机自治版，每个 VPS 独立运行。没有远程控制节点，也无需注册。

IP-Sentinel 是一套在单台 VPS 上自动运行的 IP 养护脚本，通过模拟真实用户访问 Google 和白名单站点，纠正 IP 地理定位误判问题。

## 快速开始

### 1. 安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/install_standalone.sh)
```

安装过程会自动检测 VPS 的地理位置（国家、城市、坐标），并交互式询问：
- 选择模块（Google 纠偏 / Trust 净化 / 双开）
- 选择 IP 协议（IPv4/IPv6）

### 2. 依赖要求

**必须**：
- [curl-impersonate](https://github.com/lwthiker/curl-impersonate)（提供 `curl_chrome*` 命令）

**系统自带或自动安装**：
- `curl`, `jq`, `cron`, `procps`

### 3. 查看状态

```bash
# 看运行日志
tail -f /opt/ip_sentinel/logs/sentinel.log

# 看守护进程
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
# 开关模块
ENABLE_GOOGLE="true"       # Google 纠偏模块
ENABLE_TRUST="true"         # Trust 净化模块

# 网络设置
IP_PREF="4"                  # 优先协议 4=IPv4, 6=IPv6
BIND_IP="1.2.3.4"            # 绑定 IP（NAT 环境留空）

# 区域信息（安装时已自动检测，通常无需修改）
REGION_CODE="US"
REGION_NAME="Los Angeles - US"
BASE_LAT="34.0522"
BASE_LON="-118.2437"
TIMEZONE="America/Los_Angeles"

# Trust 白名单（安装时已根据内置规则表写入）
WHITE_URLS=(
    "https://en.wikipedia.org/wiki/Special:Random"
    "https://www.yahoo.com/"
    ...
)
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

### 代码结构

```
IP-Sentinel/
├── core/                      # 运行时代码
│   ├── standalone_daemon.sh    # 主调度器：随机休眠、选模块、维持单例
│   ├── mod_google_curl_imp.sh  # Google 模块：随机搜索/地图/新闻请求
│   ├── mod_trust_curl_imp.sh   # Trust 模块：白名单站点随机访问
│   ├── utils.sh                # 共享工具：UA生成、日志、curl检测
│   ├── updater.sh              # 日志裁剪、文件完整性检查
│   └── uninstall.sh            # 清理脚本
├── install_standalone.sh       # 安装入口
└── version.txt                 # 版本号
```

### 调度逻辑

`standalone_daemon.sh` 主循环：

1. **时区感知**：按 `config.conf` 中的 `TIMEZONE` 计算本地小时（精确，无需硬编码 UTC 偏移）
2. **活动时段**：仅 08:00-22:00（本地时间）运行
3. **执行概率**：每天固定种子计算，约 60% 概率执行
4. **计划次数**：每天 1-3 次随机
5. **执行前延迟**：300-899 秒随机
6. **间隔休眠**：两次执行之间 7200-14399 秒随机
7. **模块选择**：Google 70% / Trust 30%（双开时）
8. **更新先行**：每次执行前调用 `updater.sh`

### Google 模块细节

- 实时拉取 Google Trends RSS 作为关键词
- 坐标抖动：基准坐标 ±0.001°（约 100m）
- 单次会话：6-10 个请求
- 请求类型随机：Search / News / Maps / connectivitycheck
- 超时：15 秒
- 间隔：90-150 秒
- 自检：最后访问 google.com，根据跳转域名判定状态
  - `com` 或匹配 `valid_url_suffix` → 成功
  - `com.hk` 且区域不是 HK → 漂移
  - 网络失败 → 阻断

### Trust 模块细节

- 白名单来自 `config.conf` 的 `WHITE_URLS` 数组（安装时根据国家代码匹配内置规则表）
- 降级：数组为空时回退到 Wikipedia/Apple/Microsoft
- 单次会话：3-6 个请求
- 超时：15 秒
- 间隔：45-120 秒
- 成功判定：HTTP 2xx 或 3xx

### 更新逻辑

`updater.sh`：
- 日志裁剪：保留最后 2000 行
- 核心文件完整性检查

### 扩展开发

**添加新区域**：
在 `install_standalone.sh` 的内置 `case` 规则表中新增国家代码分支，填入：
- `VALID_URL_SUFFIX`（Google 域名后缀）
- `LANG_PARAMS`（搜索语言参数）
- `WHITE_URLS`（当地白名单站点，用 `|` 分隔）

安装脚本会通过 `api.ip.sb/geoip` 自动检测新国家的 VPS 坐标，无需维护静态 JSON。

---

## 版本

当前版本：`3.4.0`

## 许可证

AGPL-3.0
