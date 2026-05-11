#!/bin/bash
# IP-Sentinel 工具函数库

# ==========================================
# 通用日志（输出到 stdout，由外部重定向管理）
# ==========================================

log_sentinel() {
    printf "[%s] [v%s] [%s] [%s] [%s] %s\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" "${AGENT_VERSION:-3.4.0}" "$1" "$2" "$3" "$4"
}

# ==========================================
# curl-impersonate 检测
# ==========================================

detect_curl_imp() {
    for cmd in curl_chrome131 curl_chrome130 curl_chrome129 curl_chrome128 curl_chrome125 curl_chrome120 curl_chrome116 curl_chrome; do
        command -v "$cmd" >/dev/null 2>&1 && { echo "$cmd"; return 0; }
    done
    return 1
}

# ==========================================
# User-Agent 生成器 (纯 Bash)
# ==========================================

generate_chrome_version() {
    local major=$((RANDOM % 4 + 122))
    local build=$((RANDOM % 1501 + 5000))
    local patch=$((RANDOM % 141 + 10))
    echo "${major}.0.${build}.${patch}"
}

generate_ua() {
    local platform=${1:-"random"}
    local chrome_ver=$(generate_chrome_version)

    if [ "$platform" == "random" ]; then
        local r=$((RANDOM % 4))
        case $r in
            0) platform="windows" ;;
            1) platform="macos" ;;
            2) platform="ios" ;;
            3) platform="android" ;;
        esac
    fi

    case $platform in
        windows)
            echo "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${chrome_ver} Safari/537.36"
            ;;
        macos)
            local mac_minor=$((RANDOM % 5 + 11))
            local mac_patch=$((RANDOM % 6 + 1))
            if [ $((RANDOM % 2)) -eq 0 ]; then
                echo "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_${mac_minor}_${mac_patch}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${chrome_ver} Safari/537.36"
            else
                local safari_build=$((RANDOM % 6 + 6051))
                local safari_minor=$((RANDOM % 4 + 1))
                echo "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_${mac_minor}_${mac_patch}) AppleWebKit/${safari_build}.15 (KHTML, like Gecko) Version/17.${safari_minor} Safari/${safari_build}.15"
            fi
            ;;
        ios)
            local device=$((RANDOM % 2))
            local ios_major=$((RANDOM % 2 + 16))
            local ios_minor=$((RANDOM % 5 + 1))
            local ios_patch=$((RANDOM % 3 + 1))
            local safari_build=$((RANDOM % 6 + 6051))
            local safari_minor=$((RANDOM % 4))
            if [ $device -eq 0 ]; then
                echo "Mozilla/5.0 (iPhone; CPU iPhone OS ${ios_major}_${ios_minor}_${ios_patch} like Mac OS X) AppleWebKit/${safari_build}.15 (KHTML, like Gecko) Version/${ios_major}.${safari_minor} Mobile/15E148 Safari/604.1"
            else
                echo "Mozilla/5.0 (iPad; CPU OS ${ios_major}_${ios_minor}_${ios_patch} like Mac OS X) AppleWebKit/${safari_build}.15 (KHTML, like Gecko) Version/${ios_major}.${safari_minor} Mobile/15E148 Safari/604.1"
            fi
            ;;
        android)
            local android_ver=$((RANDOM % 3 + 12))
            local models=("Pixel 8 Pro" "Pixel 8" "Pixel 7a" "Pixel 7 Pro" "SM-S928B" "SM-S928U" "SM-S918B" "SM-A546B" "SM-A346B" "23113RKC6C" "23049PCD8G" "CPH2437" "V2227A" "PGT-AN10" "NX729J")
            local idx=$((RANDOM % ${#models[@]}))
            local model="${models[$idx]}"
            echo "Mozilla/5.0 (Linux; Android ${android_ver}; ${model}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${chrome_ver} Mobile Safari/537.36"
            ;;
        *)
            echo "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${chrome_ver} Safari/537.36"
            ;;
    esac
}

# ==========================================
# Google Trends 实时拉取
# ==========================================

fetch_trends_live() {
    local region_code="${1:-US}"
    local geo="$region_code"
    [ "$region_code" == "UK" ] && geo="GB"

    local url="https://trends.google.com/trending/rss?geo=${geo}"
    local tmpfile="/tmp/trends_${region_code}.xml"

    curl -s -L --max-time 10 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "$url" -o "$tmpfile" 2>/dev/null

    if [ -s "$tmpfile" ]; then
        sed -n 's/.*<title>\([^<]*\)<\/title>.*/\1/p' "$tmpfile" | grep -v "^Google Trends" | head -20
        rm -f "$tmpfile"
        return 0
    else
        rm -f "$tmpfile"
        return 1
    fi
}

# 获取关键词，失败时使用备用词库
get_keywords() {
    local region_code="${1:-US}"
    local live_keywords=$(fetch_trends_live "$region_code")

    if [ -n "$live_keywords" ]; then
        echo "$live_keywords"
    else
        echo "weather
news
maps
gmail
youtube
amazon
translate
finance
shopping
flights"
    fi
}
