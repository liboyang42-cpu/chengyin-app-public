#!/usr/bin/env bash
# 生成 Android 上架签名密钥,并写好 android/key.properties。
#
# ★★ 口令由**你自己**输入,本脚本不接受命令行传参、不写进任何日志。
#    密钥一旦用于上架就**永远不能更换** —— 换了等于换一个 App,
#    老用户升不了级,ICP 备案登记的证书 MD5 也全部作废。
#    所以:生成后立刻备份 .jks 与口令到你自己的密码管理器。
#
# 用法:  bash tool/make_release_keystore.sh
set -euo pipefail

cd "$(dirname "$0")/.."
KS_DIR="$HOME/.chengyin-keys"
KS="$KS_DIR/chengyin-release.jks"
ALIAS="chengyin"
PROPS="android/key.properties"

# ★ 绝不放进仓库目录:仓库会被打包、会被同步、会被别的会话 git add。
#   放家目录下的独立目录,和代码物理隔离。
mkdir -p "$KS_DIR"
chmod 700 "$KS_DIR"

if [ -f "$KS" ]; then
  echo "已存在:$KS"
  echo "⚠️ 不覆盖。若这把钥匙已用于上架,覆盖它 = 永久失去更新该 App 的能力。"
  echo "   确认要重建,请先自己把它移走。"
  exit 1
fi

if [ -f "$PROPS" ]; then
  echo "已存在:$PROPS —— 不覆盖。"
  exit 1
fi

# ⚠️⚠️ keytool 的口令提示只能从**真正的终端**读。
#   在没有 TTY 的环境里(IDE 的命令面板、CI、编码助手 的 `!` 前缀)
#   它读到空口令,连试三次后打印「故障太多」——**然后返回 0**,
#   于是脚本会若无其事地往下跑,最后 chmod 报一句 No such file。
#   与其让人对着这堆输出猜,不如一开始就说清楚。
if [ ! -t 0 ]; then
  echo "✗ 这里没有可交互的终端(stdin 不是 TTY),keytool 读不到你的口令。"
  echo
  echo "  请**打开 Terminal.app 或 iTerm**,在里面跑:"
  echo "      cd \"$(pwd)\" && bash tool/make_release_keystore.sh"
  echo
  echo "  ★ 口令必须由你亲手输入 —— 不要用命令行参数或环境变量传,"
  echo "    那会进 ps 和 shell history。"
  exit 1
fi

echo "即将生成上架签名密钥。接下来 keytool 会问你:"
echo "  · 密钥库口令(自己想一个,记牢)"
echo "  · 姓名/组织/城市等(可随便填,但**填了就不能改**,会印在证书里)"
echo

keytool -genkeypair -v \
  -keystore "$KS" \
  -keyalg RSA -keysize 2048 \
  -validity 10000 \
  -alias "$ALIAS"

# ★ 不信 keytool 的退出码 —— 它在「故障太多」之后仍然返回 0。
#   判据看**产物在不在**(回执 ≠ 观测)。
if [ ! -s "$KS" ]; then
  echo
  echo "✗ 密钥没有生成($KS 不存在或为空)。"
  echo "  常见原因:口令少于 6 位,或输入被环境吞掉了。"
  echo "  在真正的终端里重跑,口令用 6 位以上。"
  exit 1
fi

chmod 600 "$KS"

echo
echo "密钥已生成:$KS"
echo "现在写 $PROPS —— 需要再输一次同样的口令(Gradle 构建时要用)。"
echo

# -s 不回显;不用命令行参数传口令(会进 ps 和 shell history)
read -r -s -p "密钥库口令(storePassword): " STORE_PW; echo
read -r -s -p "密钥口令(keyPassword,刚才没单独设就填同一个): " KEY_PW; echo

umask 077
cat > "$PROPS" <<EOF
storeFile=$KS
storePassword=$STORE_PW
keyAlias=$ALIAS
keyPassword=$KEY_PW
EOF
chmod 600 "$PROPS"

echo
echo "已写入 $PROPS(权限 600,已在 android/.gitignore 里)。"
echo
echo "★ 现在做三件事,一件都别省:"
echo "  1) 把 $KS 和两个口令备份到密码管理器 —— 丢了就永远更新不了这个 App"
echo "  2) 重新出包:flutter build apk --release"
echo "  3) **回读验证**签名真的换了(别信构建回执):"
echo "     apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk"
echo "     出来的 DN 必须**不再是** CN=Android Debug"
echo
echo "  备案要用的证书 MD5(上架后填):"
echo "     keytool -list -v -keystore $KS -alias $ALIAS | grep MD5"
