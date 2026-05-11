{
  "id": "1a7ebe0a",
  "title": "删除所有 JSON，改为 IP 地理 API 自动检测 + 内置规则",
  "tags": [],
  "status": "open",
  "created_at": "2026-05-11T04:32:20.312Z"
}

- [x] 重写 install_standalone.sh：用 api.ip.sb/geoip 自动检测地理位置，内置 7 国规则表
- [x] 修改 standalone_daemon.sh：用 TIMEZONE 环境变量获取本地小时，删除 UTC_OFFSET
- [x] 修改 mod_trust_curl_imp.sh：从 config.conf 读取 WHITE_URLS 数组
- [x] 删除 data/ 目录（map.json + 所有区域 JSON）
- [x] 更新 README.md 反映零 JSON 架构
- [x] 语法检查 + 提交
