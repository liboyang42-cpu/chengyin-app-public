#!/usr/bin/env bash
# 上线预检 —— 一条命令告诉你「现在还差什么、下一步做什么」。
#
# ★ 为什么要有它:上线的前置条件散在四处 —— 三个测试文件、一个 keystore 脚本、
#   两份文档、还有几个只有平台后台才知道的状态。逐个记等于必漏。
#   这里收成一条命令,每一条**只报事实 + 下一步**,不报「大概可以了」。
#
# ★★ 只做**能在本机验证**的那些。平台侧的状态(ICP 备案进度、Apple 审核结果、
#   微信开放平台审核)本机看不到,一律标 [需人工] 而不是猜一个。
#   猜出来的绿比没有更坏。
#
# 用法:  bash tool/preflight.sh
#        echo $?   # 0 = 本机能验的都过了;1 = 有阻塞
cd "$(dirname "$0")/.."

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; OFF=$'\033[0m'
blockers=0

ok()    { printf '  %s✓%s %s\n' "$GRN" "$OFF" "$1"; }
bad()   { printf '  %s✗%s %s\n     %s↳ %s%s\n' "$RED" "$OFF" "$1" "$DIM" "$2" "$OFF"; blockers=$((blockers+1)); }
manual(){ printf '  %s?%s %s\n     %s↳ %s%s\n' "$YEL" "$OFF" "$1" "$DIM" "$2" "$OFF"; }

echo
echo "══ 1. Android 签名 ─────────────────────────────────"
if [ -f android/key.properties ] && [ -f "$HOME/.chengyin-keys/chengyin-release.jks" ]; then
  ok "正式 keystore 已配置"
else
  bad "还在用调试证书,打出来的包不能上架" \
      "bash tool/make_release_keystore.sh(口令只你自己知道,生成后立刻备份)"
fi

# ★ 判据看**产物**不看配置:配置对了但包是旧的照样白搭。
APK=build/app/outputs/flutter-apk/app-release.apk
if [ -f "$APK" ]; then
  SIGNER=$(find "$HOME/Library/Android/sdk/build-tools" -name apksigner 2>/dev/null | head -1)
  if [ -n "$SIGNER" ]; then
    SHA=$("$SIGNER" verify --print-certs "$APK" 2>/dev/null | grep -m1 'SHA-1' | awk '{print $NF}')
    # 77c34b34… 是本机 debug 证书。硬编码它是有意的:
    # 「不是这一个」比「像是正式的」更好判。
    if [ "$SHA" = "77c34b34040baf78a0c6e08e2143d9e91b66d8aa" ]; then
      bad "现存 APK 是**调试签名**($SHA)" "有了正式 keystore 后重新 flutter build apk --release"
    else
      ok "现存 APK 签名指纹 $SHA"
      printf '     %s↳ 微信开放平台登记的就是这一串%s\n' "$DIM" "$OFF"
    fi
  else
    manual "找不到 apksigner,没法回读 APK 签名" "装 Android build-tools 后重跑"
  fi
else
  manual "还没有 release APK" "flutter build apk --release"
fi
[ -f build/app/outputs/DEBUG_SIGNED_DO_NOT_SHIP.txt ] && \
  bad "上次构建留下了调试签名警示文件" "有正式 keystore 后重新构建,该文件会自动删除"

echo
echo "══ 2. 微信开放平台(移动应用)──────────────────────"
APPID=$(grep -oE "kWechatAppId = '[^']*'" lib/feature/auth/auth_controller.dart | grep -oE "'[^']*'" | tr -d "'")
if [ -z "$APPID" ] || [[ "$APPID" == wxYOUR* ]]; then
  bad "appid 仍是占位「${APPID:-空}」—— 登录与支付都走不通" \
      "开放平台申请**移动应用** appid(与小程序 appid 不是一个),然后改三处:
       lib/feature/auth/auth_controller.dart 的 kWechatAppId
       ios/Runner/Info.plist 的 CFBundleURLTypes scheme
       Universal Link(kWechatUniversalLink,必须 https 且以 / 结尾)"
else
  ok "appid 已填:$APPID"
fi

echo
echo "══ 3. App 内隐私政策 ────────────────────────────"
LEGAL_DOC=${CHENGYIN_LEGAL_DOC_PATH:-lib/feature/legal/legal_docs.dart}
LEGAL_OUT=$(python3 tool/legal_doc_gate.py "$LEGAL_DOC" 2>&1)
LEGAL_STATUS=$?
if [ "$LEGAL_STATUS" -eq 0 ]; then
  ok "App 内隐私政策已有结构化正文($LEGAL_OUT)"
else
  bad "App 内隐私政策正文待提供" \
      "${LEGAL_OUT}；法务定稿后填入非空 sections/version/updatedAt；公网 URL 不能代替 App 内正文"
fi

echo
echo "══ 4. 一致性对账 ──────────────────────────────────"
GAPS_OUT=$(python3 tool/endpoint_parity.py 2>/dev/null)
GAPS_STATUS=$?
PAGES_OUT=$(python3 tool/page_parity.py 2>/dev/null)
PAGES_STATUS=$?
GAPS=$(printf '%s\n' "$GAPS_OUT" | head -1)
PAGES=$(printf '%s\n' "$PAGES_OUT" | head -1)
printf '  %s· %s%s\n' "$DIM" "$GAPS" "$OFF"
printf '  %s· %s%s\n' "$DIM" "$PAGES" "$OFF"
if [ "$GAPS_STATUS" -ne 0 ] || [ "$PAGES_STATUS" -ne 0 ]; then
  bad "一致性缺口仍未清零" \
      "逐条解决上方缺口后重跑预检;后端判据默认固定为本地 github/master"
else
  ok "113 页绑定与端点等价已通过"
fi

echo
echo "══ 5. 只有平台后台知道的(本机看不到)──────────────"
manual "ICP 备案" "App 需**单独**备案,与小程序不共用;约 20 工作日。备案登记的证书 MD5 必须与上架包一致"
manual "Apple 开发者账号 / D-U-N-S" "企业账号周期最长,建议最先办"
manual "隐私政策**公网 URL**" "App Store 要公网地址,App 内页面不算;草案见 vault 04-未开始/App隐私政策_草案"
manual "生产库迁移是否已跑" "PR 合并 ≠ 落库(纯 sql 不触发部署)。export CHENGYIN_DB_PASSWORD 后跑 audit_sys_job.py"

echo
if [ "$blockers" -eq 0 ]; then
  printf '%s本机能验的都过了。%s剩下的都在平台侧,见第 6 节。\n\n' "$GRN" "$OFF"
  exit 0
fi
printf '%s本机可验的阻塞:%d 项%s(上面每条都带了下一步)\n\n' "$RED" "$blockers" "$OFF"
exit 1
