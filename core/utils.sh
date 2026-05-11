#!/bin/bash
# IP-Sentinel 工具函数库
# 运行时生成 UA 和拉取 Trends 数据，无需预生成文件

# ==========================================
# User-Agent 生成器 (纯 Bash 实现)
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
                # Chrome on Mac
                echo "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_${mac_minor}_${mac_patch}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${chrome_ver} Safari/537.36"
            else
                # Safari on Mac
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

# 批量生成 UA 列表到文件
generate_ua_list() {
    local count=${1:-20}
    local output_file=${2:-"/tmp/ua_list.txt"}
    > "$output_file"
    for i in $(seq 1 $count); do
        generate_ua "random" >> "$output_file"
    done
}

# ==========================================
# Google Trends 实时拉取 (纯 Bash + curl)
# ==========================================

# 解析 XML 获取标题 (使用 sed/awk，无需 xmllint)
parse_trends_xml() {
    local xml="$1"
    # 提取 <title> 标签内容，过滤掉 RSS 频道标题
    echo "$xml" | sed -n 's/.*<title>\([^<]*\)<\/title>.*/\1/p' | grep -v "^Google Trends" | head -20
}

# 实时获取某地区的热门关键词
fetch_trends_live() {
    local region_code="${1:-US}"
    # 地区码修正
    local geo="$region_code"
    [ "$region_code" == "UK" ] && geo="GB"

    local url="https://trends.google.com/trending/rss?geo=${geo}"
    local tmpfile="/tmp/trends_${region_code}.xml"

    # 使用系统 curl 拉取 (设置较短超时避免阻塞)
    curl -s -L --max-time 10 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" "$url" -o "$tmpfile" 2>/dev/null

    if [ -s "$tmpfile" ]; then
        parse_trends_xml "$(cat "$tmpfile")"
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
    local live_keywords

    # 尝试实时拉取
    live_keywords=$(fetch_trends_live "$region_code")

    if [ -n "$live_keywords" ]; then
        echo "$live_keywords"
    else
        # 备用词库 (硬编码通用词)
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

# ==========================================
# 工具函数
# ==========================================

# 坐标抖动 (单位: 度，约 111km/度)
jitter_coord() {
    local base="$1"
    local range_meters="${2:-1000}"
    # 将米转换为度 (粗略)
    local range_deg=$(awk "BEGIN {printf \"%.6f\", $range_meters / 111000}")
    local offset=$(awk "BEGIN {srand(); print ($RANDOM - 16384) / 16384 * $range_deg}")
    awk "BEGIN {printf \"%.6f\", $base + $offset}"
}

# URL 编码
url_encode() {
    local str="$1"
    printf '%s' "$str" | od -An -tx1 | tr ' ' '%' | tr -d '\n' | tr 'a-f' 'A-F' | sed 's/^/%/;s/%$//'
}
