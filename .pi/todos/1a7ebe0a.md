{
  "id": "1a7ebe0a",
  "title": "删除所有 JSON，改为 IP 地理 API 自动检测 + 内置规则",
  "tags": [],
  "status": "done",
  "created_at": "2026-05-11T04:32:20.312Z"
}

- install_standalone.sh：用 api.ip.sb/geoip 自动检测，内置 7 国规则表，删除交互式选择
- standalone_daemon.sh：改用 TZ=$TIMEZONE 精确获取本地小时，删除 UTC_OFFSET
- mod_trust_curl_imp.sh：从 config.conf 的 WHITE_URLS 数组读取白名单，删除 JSON 解析逻辑
- 删除整个 data/ 目录（9 个 JSON 文件）
- README.md 重写开发者文档
- 14 files changed, 115 insertions(+), 362 deletions(-)
已推送到 origin/main
