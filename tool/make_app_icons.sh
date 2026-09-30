#!/usr/bin/env bash
# 从**一张**源图生成 iOS 19 张 + 安卓 5 档全部 App 图标。
#
# 用法:
#   tool/make_app_icons.sh <源图.png>
#
# 为什么要有这个脚本:手工做一遍是 24 个文件、8 种尺寸、两套命名规则,
# 漏一张不会报错 —— Xcode 只在归档时警告一句、Android 直接用默认图,
# 而且最容易错的是**把带 alpha 的图放进 iOS 1024**(App Store 直接拒收)。
# 与其让人对着表格切图,不如让机器切并当场校验。
#
# 对源图的要求(脚本会逐条检查,不合格直接退出,不生成半套):
#   · ≥ 1024×1024,且必须是正方形
#   · **不能有 alpha 通道** —— App Store Connect 对 1024 图标是硬性拒收
#   · PNG
#
# ⚠️ 脚本不做「补白底」这种自作聪明的事:带 alpha 的图直接拒。
#    自动填白可能把设计师有意留的透明区域填成难看的白块,而且没人会发现 ——
#    宁可让人重新导出一版,也不要悄悄改了品牌资产。

set -euo pipefail

SRC="${1:-}"
if [[ -z "$SRC" ]]; then
  echo "用法: $0 <源图.png>" >&2
  exit 2
fi
if [[ ! -f "$SRC" ]]; then
  echo "找不到源图: $SRC" >&2
  exit 2
fi

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$APP_DIR/ios/Runner/Assets.xcassets/AppIcon.appiconset"
AND_RES="$APP_DIR/android/app/src/main/res"

# ---- 预检:不合格就一张都不生成 ----
W=$(sips -g pixelWidth "$SRC" | tail -1 | awk '{print $2}')
H=$(sips -g pixelHeight "$SRC" | tail -1 | awk '{print $2}')
ALPHA=$(sips -g hasAlpha "$SRC" | tail -1 | awk '{print $2}')

fail() { echo "✗ $1" >&2; exit 1; }

[[ "$W" == "$H" ]] || fail "源图不是正方形(${W}×${H})。App 图标必须正方形,拉伸会变形。"
[[ "$W" -ge 1024 ]] || fail "源图只有 ${W}px,不足 1024。放大会糊,App Store 那张是 1024×1024。"
[[ "$ALPHA" == "no" ]] || fail "源图带 alpha 通道。App Store Connect 对 1024 图标**硬性拒收**带 alpha 的。
  请在导出时把背景压成不透明实色再来(脚本不替你填,填错了没人发现)。"

echo "✓ 源图 ${W}×${H},无 alpha"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

gen() { # gen <边长> <输出路径>
  sips -s format png -z "$1" "$1" "$SRC" --out "$2" >/dev/null
}

# ---- iOS:19 张,文件名必须与 Contents.json 里登记的一致 ----
declare -a IOS=(
  "40:Icon-App-20x20@2x.png"    "60:Icon-App-20x20@3x.png"
  "29:Icon-App-29x29@1x.png"    "58:Icon-App-29x29@2x.png"
  "87:Icon-App-29x29@3x.png"    "80:Icon-App-40x40@2x.png"
  "120:Icon-App-40x40@3x.png"   "120:Icon-App-60x60@2x.png"
  "180:Icon-App-60x60@3x.png"   "20:Icon-App-20x20@1x.png"
  "76:Icon-App-76x76@1x.png"    "152:Icon-App-76x76@2x.png"
  "167:Icon-App-83.5x83.5@2x.png"
  "40:Icon-App-40x40@1x.png"
  "1024:Icon-App-1024x1024@1x.png"
)
for e in "${IOS[@]}"; do
  gen "${e%%:*}" "$IOS_DIR/${e##*:}"
done

# ---- Android:5 档密度 ----
declare -a AND=("48:mdpi" "72:hdpi" "96:xhdpi" "144:xxhdpi" "192:xxxhdpi")
for e in "${AND[@]}"; do
  d="$AND_RES/mipmap-${e##*:}"
  mkdir -p "$d"
  gen "${e%%:*}" "$d/ic_launcher.png"
done

# ---- 回执:逐个回读,别只信 sips 的 exit 0 ----
echo
echo "生成结果(回读实际尺寸):"
BAD=0
for e in "${IOS[@]}"; do
  f="$IOS_DIR/${e##*:}"
  got=$(sips -g pixelWidth "$f" 2>/dev/null | tail -1 | awk '{print $2}')
  [[ "$got" == "${e%%:*}" ]] || { echo "  ✗ $f 期望 ${e%%:*} 实际 ${got:-缺失}"; BAD=1; }
done
for e in "${AND[@]}"; do
  f="$AND_RES/mipmap-${e##*:}/ic_launcher.png"
  got=$(sips -g pixelWidth "$f" 2>/dev/null | tail -1 | awk '{print $2}')
  [[ "$got" == "${e%%:*}" ]] || { echo "  ✗ $f 期望 ${e%%:*} 实际 ${got:-缺失}"; BAD=1; }
done
[[ "$BAD" == 0 ]] && echo "  ✓ iOS ${#IOS[@]} 张 + Android ${#AND[@]} 档,尺寸全部核对通过"

echo
echo "下一步:"
echo "  1. 去掉 test/release_readiness_test.dart 里图标那条的 skip(它会变成守卫)"
echo "  2. flutter test test/release_readiness_test.dart   # 确认不再是默认图、无 alpha"
echo "  3. flutter build ipa --no-codesign                 # 确认 Flutter 校验不再警告图标"

exit $BAD
