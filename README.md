# IP-Sentinel

> **注意**：当前版本为单机自治版，每个 VPS 独立运行。没有远程控制节点，也无需注册。

IP-Sentinel 是一套在单台 VPS 上自动运行的 IP 养护脚本，通过模拟真实用户访问 Google 和白名单站点，纠正 IP 地理定位误判问题。

## 快速开始

### 1. 安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/hotyue/IP-Sentinel/main/install_standalone.sh)
```

安装过程会交互式询问：
- 选择国家/地区/城市
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
[2025-01-15 14:30:25] [v3.4.0] [INFO] [Google] [US] 启动 [curl_chrome125]
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

# 区域信息（安装时已设置，通常无需修改）
REGION_CODE="US"
REGION_NAME="United States - Los Angeles"
BASE_LAT="34.0522"
BASE_LON="-118.2437"
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
│   ├── updater.sh              # 数据刷新：UA库、关键词、区域规则
│   └── uninstall.sh            # 清理脚本
├── data/                       # 静态数据
│   ├── keywords/kw_{CC}.txt    # 各国搜索词库
│   ├── regions/{CC}/...        # 区域配置（坐标、白名单）
│   ├── map.json                # 国家-州-市索引
│   └── user_agents.txt         # 浏览器指纹库（暂未消费）
├── scripts/                    # 数据生成
│   ├── fetch_trends.py         # 抓取 Google Trends RSS
│   └── ua_generator.py         # 生成 4000 条 UA
├── telemetry/worker.js         # Cloudflare Worker 统计（独立代码）
├── .github/workflows/          # 自动化任务
│   ├── daily_keywords.yml      # 每日更新关键词
│   └── ua_factory.yml          # 每月生成 UA
└── install_standalone.sh       # 安装入口
```

### 调度逻辑

`standalone_daemon.sh` 主循环：

1. **时区感知**：按区域代码硬编码偏移计算本地小时（US=-7, JP=+9, UK=+1, DE/FR=+2, 其他=+8）
2. **活动时段**：仅 08:00-22:00（本地时间）运行
3. **执行概率**：每天固定种子计算，约 60% 概率执行
4. **计划次数**：每天 1-3 次随机
5. **执行前延迟**：300-899 秒随机
6. **间隔休眠**：两次执行之间 7200-14399 秒随机
7. **模块选择**：Google 70% / Trust 30%（双开时）
8. **更新先行**：每次执行前调用 `updater.sh`

### Google 模块细节

- 读取 `data/keywords/kw_{REGION_CODE}.txt`
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

- 读取当前区域 JSON 的 `trust_module.white_urls`
- 降级：文件缺失时回退到 Wikipedia/Apple/Microsoft
- 单次会话：3-6 个请求
- 超时：15 秒
- 间隔：45-120 秒
- 成功判定：HTTP 2xx 或 3xx

### 更新逻辑

`updater.sh`：

- UA 库：30 天周期
- 关键词库：每次执行前拉取
- 区域规则：每次执行前拉取
- 日志裁剪：保留最后 2000 行

### 遥测 Worker

`telemetry/worker.js` 是独立的 Cloudflare Worker，提供：
- `/ping/agent` 和 `/ping/master`：计数器自增
- `/stats/agent` 和 `/stats/master`：Shields.io 徽章 JSON

当前安装/运行脚本**未调用**这些端点，仅作为独立代码存在。

### 扩展开发

**添加新区域**：
1. 在 `data/map.json` 添加国家/城市节点
2. 在 `data/regions/` 创建 `{CC}/{State}/{City}.json`
3. 创建 `data/keywords/kw_{CC}.txt`

**区域 JSON 格式**：
```json
{
  "region_name": "Country - City",
  "google_module": {
    "base_lat": 34.0522,
    "base_lon": -118.2437,
    "lang_params": "hl=en&gl=US",
    "valid_url_suffix": "com"
  },
  "trust_module": {
    "white_urls": ["https://...", "https://..."]
  }
}
```

---

## 版本

当前版本：`3.4.0`

## 许可证

AGPL-3.0