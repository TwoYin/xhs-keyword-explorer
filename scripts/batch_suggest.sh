#!/bin/bash
# XHS Keyword Explorer - 小红书下拉关联词批量采集脚本
# 用法: PROFILE=<id> KEYWORDS_FILE=<file> [OUTPUT_DIR=<dir>] bash batch_suggest.sh
#
# 环境变量:
#   PROFILE         - 必填, OpenCLI browser profile ID
#   KEYWORDS_FILE   - 必填, 关键词列表文件,每行一个
#   OUTPUT_DIR      - 可选, 截图保存目录,默认 /tmp/xhs_screenshots
#   WAIT_AFTER_TYPE - 可选, 输入后等待秒数(等下拉框加载),默认 5
#   WAIT_BETWEEN    - 可选, 关键词间间隔秒数,默认 5

set -euo pipefail

# -------------------- 配置读取 --------------------
PROFILE="${PROFILE:-}"
KEYWORDS_FILE="${KEYWORDS_FILE:-}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/xhs_screenshots}"
WAIT_AFTER_TYPE="${WAIT_AFTER_TYPE:-5}"
WAIT_BETWEEN="${WAIT_BETWEEN:-5}"

if [[ -z "$PROFILE" ]]; then
  echo "错误: 未设置 PROFILE 环境变量"
  echo "用法: PROFILE=<profile-id> KEYWORDS_FILE=<file> bash $0"
  exit 1
fi

if [[ -z "$KEYWORDS_FILE" || ! -f "$KEYWORDS_FILE" ]]; then
  echo "错误: KEYWORDS_FILE 未设置或文件不存在: $KEYWORDS_FILE"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

# 读取关键词到数组
mapfile -t keywords < <(grep -v '^#' "$KEYWORDS_FILE" | grep -v '^$')

echo "=== XHS Keyword Explorer ==="
echo "Profile:   $PROFILE"
echo "Keywords:  ${#keywords[@]} 个"
echo "Output:    $OUTPUT_DIR"
echo "Wait:      ${WAIT_AFTER_TYPE}s after type | ${WAIT_BETWEEN}s between keywords"
echo ""

# -------------------- 核心函数 --------------------

# 恢复页面透明度,清空搜索框
function reset_page() {
  opencli browser "$PROFILE" eval '
    document.querySelectorAll("[class*=note], [class*=card], [class*=feed]").forEach(c => {
      c.style.opacity = "1";
      c.style.pointerEvents = "auto";
    });
    const input = document.getElementById("search-input");
    if (input) input.value = "";
  ' >/dev/null 2>&1
}

# 透明化卡片并截图
function capture() {
  opencli browser "$PROFILE" eval '
    document.querySelectorAll("[class*=note], [class*=card], [class*=feed]").forEach(c => {
      c.style.opacity = "0.1";
      c.style.pointerEvents = "none";
    });
  ' >/dev/null 2>&1
  sleep 1
  opencli browser "$PROFILE" screenshot "$1"
}

# 随机延迟(模拟人类行为)
function random_sleep() {
  local min=$1 max=$2
  local delay
  delay=$(awk -v min="$min" -v max="$max" 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
  echo "  等待 ${delay} 秒..."
  sleep "$delay"
}

# -------------------- 前置检查 --------------------

# 检查浏览器是否在小红书页面
current_url=$(opencli browser "$PROFILE" state 2>/dev/null | grep "^URL:" | awk '{print $2}' || true)
if [[ "${current_url:-}" != *"xiaohongshu.com"* ]]; then
  echo "警告: 浏览器可能不在小红书页面"
  echo "当前 URL: ${current_url:-(unknown)}"
  echo "请手动打开 https://www.xiaohongshu.com 后再运行此脚本"
  echo ""
  read -rp "是否继续? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi

# -------------------- 主循环 --------------------

for i in "${!keywords[@]}"; do
  kw="${keywords[$i]}"
  outfile="${OUTPUT_DIR}/suggest_$(printf "%03d" $i)_${kw// /_}.png"
  echo "[$((i+1))/${#keywords[@]}] 关键词: $kw"

  # Step 1: 恢复页面,清空搜索框
  reset_page
  random_sleep 2 4

  # Step 2: 获取搜索框元素引用
  # 注意: ref 编号可能随页面状态变化,此处通过 state 命令动态获取
  search_ref=$(opencli browser "$PROFILE" state 2>/dev/null | grep 'id=search-input' | grep -oP 'ref=\K\d+' | head -1)
  if [[ -z "${search_ref:-}" ]]; then
    echo "  错误: 未找到搜索框元素(search-input),跳过"
    continue
  fi

  # Step 3: 点击搜索框
  if ! opencli browser "$PROFILE" click "$search_ref" >/dev/null 2>&1; then
    echo "  错误: 无法点击搜索框(ref=$search_ref),跳过"
    continue
  fi
  random_sleep 1 2

  # Step 4: 输入关键词
  if ! opencli browser "$PROFILE" type "$search_ref" "$kw" >/dev/null 2>&1; then
    echo "  错误: 无法输入关键词,跳过"
    continue
  fi
  echo "  已输入,等待下拉框加载(API有延迟)..."
  random_sleep "$WAIT_AFTER_TYPE" "$((WAIT_AFTER_TYPE + 3))"

  # Step 5: 透明化 + 截图
  capture "$outfile"
  echo "  截图保存: $outfile"
  if [[ -f "$outfile" ]]; then
    ls -la "$outfile" | awk '{print "  文件大小:", $5, "bytes"}'
  fi

  # Step 6: 关键词间随机延迟
  if (( i < ${#keywords[@]} - 1 )); then
    echo "  下一个关键词..."
    random_sleep "$WAIT_BETWEEN" "$((WAIT_BETWEEN + 3))"
  fi
  echo ""
done

echo "=== 采集完成 ==="
echo "截图文件:"
ls -la "${OUTPUT_DIR}"/suggest_*.png 2>/dev/null || echo "(无)"
