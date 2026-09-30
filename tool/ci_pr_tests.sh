#!/usr/bin/env bash
# PR 选测:只跑与本次改动相关的测试子集;全量留给 main push(合入后兜底)。
#
# 用法:
#   tool/ci_pr_tests.sh <base-sha>            # 选子集并真跑(CI 的 pull_request 路径)
#   tool/ci_pr_tests.sh <base-sha> --dry-run  # 只打印选中清单与理由,不跑
#
# 口径(与 .github/workflows/ci.yml 一致):
#   · 子集只是「少跑」,不是「少判」:analyze 照旧全量、守门测试无论如何都带上、
#     branch protection 的检查名不变、失败照旧判红。
#   · 映射:lib/<a>/<b>/… → test/<a>/<b>(存在就用它,否则退化到 test/<a>);
#     另有仓里的平铺惯例 test/<a>/<b>*_test.dart 一并命中;test/ 内改动的文件直接选。
#   · 共享面命中 → 退化全量(理由打在日志里),退化时 --concurrency=1 与 main 一致。
#   · 子集为空 → 只跑守门测试,绝不退化成「什么都不跑」。
set -euo pipefail

# 恒跑的仓级门禁 = 顶层 test/*_test.dart 全体(41 条 / 100 用例,2026-09-18 实测全绿)。
# 含对账四件套(endpoint_reachability 接口可达 ≠ 页面点得到 / page_parity 128 页 /
# router_targets_exist 每个 context.push 的目标都存在 / paired_endpoints 成对接口不许只接一半;
# 其中几个带 needs-local-env:CI 上被 --exclude-tags 跳过、本机跑则真跑,两边带上都不亏),
# 以及 no_material_* / light_pages_no_static_colors / product_vocabulary / no_dev_strings_in_ui 等。
# 它们读 lib/ 却不受 lib/<a>/<b> → test/<a>/<b> 映射覆盖:只改 lib/feature/** 时一条都不跑,
# 加了 Material 控件 / 静态色的 PR 会在 PR 阶段假绿,而 main 的全量又常被 cancel 兜不住。
# 消费处是 `[ -e "$g" ]`,不认 glob —— 这里先展开成真实路径。
GUARDS=( test/*_test.dart )
_guards=()
for g in "${GUARDS[@]}"; do
  for f in $g; do [ -e "$f" ] && _guards+=("$f"); done
done
GUARDS=("${_guards[@]}")

if [ $# -lt 1 ]; then
  echo "用法: tool/ci_pr_tests.sh <base-sha> [--dry-run]" >&2
  exit 2
fi
base="$1"
dry=0
[ "${2:-}" = "--dry-run" ] && dry=1

# 共享面:这些文件一动,子集就选不准(它们本身参与测试的编译/执行/选取),
# 一律退化全量。前四个是任务书的清单,后几个是同类补充(理由见每行)。
is_shared() {
  case "$1" in
    pubspec.yaml|pubspec.lock) return 0 ;;                 # 依赖
    lib/core/*|lib/main.dart|lib/app/*) return 0 ;;        # 全 App 共享代码
    tool/*|.github/workflows/*) return 0 ;;                # 仓自己的工具 / CI 本体
    analysis_options.yaml|dart_test.yaml) return 0 ;;      # lint / 测试框架配置
    test/flutter_test_config.dart) return 0 ;;             # 全局测试壳,所有测试都过它
    test/support/*) return 0 ;;                            # 61 个测试文件 import 它
    third_party/*) return 0 ;;                             # vendored 原生插件
  esac
  return 1
}

all_tests() {
  find test -name '*_test.dart' -not -path 'test/golden/*' | sort
}

sel="$(mktemp)"
trap 'rm -f "$sel"' EXIT
: > "$sel"

log() { echo "$@" >&2; }

run_tests() { # run_tests <concurrency> <理由>
  local c="$1" why="$2"
  local args=() expanded p
  while IFS='|' read -r p _; do args+=("$p"); done < <(sort -t'|' -k1,1 -u "$sel")
  expanded=0
  for p in "${args[@]}"; do expanded=$((expanded + $(find "$p" -name '*_test.dart' -not -path 'test/golden/*' | wc -l | tr -d ' '))); done
  log ""
  log "=== 选中 ${#args[@]} 个路径 / ${expanded} 个测试文件 --concurrency=$c ($why) ==="
  while IFS='|' read -r p r; do log "  $p   ← $r"; done < <(sort -t'|' -k1,1 -u "$sel")
  if [ "$dry" = 1 ]; then log "(dry-run,不跑)"; return 0; fi
  log "--- flutter test 开始 ---"
  flutter test "${args[@]}" --exclude-tags needs-local-env --concurrency="$c"
}

if ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
  log "::error::base $base 不在本仓库(是不是 checkout 的 fetch-depth 太浅?)—— 拿不到 diff 就不能假装选得准,退化全量"
  while IFS= read -r t; do printf '%s|%s\n' "$t" "退化全量:base 不可达" >> "$sel"; done < <(all_tests)
  run_tests 1 "退化全量"
  exit 0
fi

changed="$(git diff --name-only "${base}...HEAD")"
log "=== PR 选测 base=$base ==="
log "改动 $(printf '%s\n' "$changed" | grep -c . || true) 个文件:"
printf '%s\n' "$changed" | sed 's/^/  /' >&2

mode=subset
for f in $changed; do
  if is_shared "$f"; then mode=full; reason="$f 命中共享面"; break; fi
done

if [ "$mode" = full ]; then
  log "→ 退化全量:$reason"
  while IFS= read -r t; do printf '%s|%s\n' "$t" "退化全量:$reason" >> "$sel"; done < <(all_tests)
  run_tests 1 "退化全量"
  exit 0
fi

for f in $changed; do
  case "$f" in
    lib/*.dart)
      d="${f#lib/}"; d="$(dirname "$d")"
      while :; do
        hit=0
        if [ -d "test/$d" ]; then printf '%s|%s\n' "test/$d" "[目录] $f" >> "$sel"; hit=1; fi
        for g in test/"$d"*_test.dart; do
          [ -e "$g" ] && { printf '%s|%s\n' "$g" "[平铺] $f" >> "$sel"; hit=1; }
        done
        [ "$hit" = 1 ] && break
        case "$d" in */*) d="$(dirname "$d")" ;; *) break ;; esac
      done
      ;;
    test/golden/*) : ;;   # golden 归 golden-baseline job,这里不选
    # 删掉 / 改名的文件在 diff 里仍以旧路径出现 —— 那不是可跑的路径,喂给
    # flutter test 只会 "Does not exist" 判红(2026-09-18 实测)。
    test/*_test.dart)
      [ -e "$f" ] || continue
      printf '%s|%s\n' "$f" "[改动即选]" >> "$sel" ;;
    test/*)
      [ -d "$(dirname "$f")" ] || continue
      printf '%s|%s\n' "$(dirname "$f")" "[测试辅助改动] $f" >> "$sel" ;;
  esac
done

for g in "${GUARDS[@]}"; do [ -e "$g" ] && printf '%s|%s\n' "$g" "[守门,恒跑]" >> "$sel"; done

if [ "$(cut -d'|' -f1 "$sel" | grep -vxF -f <(printf '%s\n' "${GUARDS[@]}") | grep -c . || true)" = 0 ]; then
  log "→ 子集为空(改动没落到任何 test 目录),只跑守门测试"
fi

n=$(cut -d'|' -f1 "$sel" | sort -u | wc -l | tr -d ' ')
expanded=0
for p in $(cut -d'|' -f1 "$sel" | sort -u); do
  expanded=$((expanded + $(find "$p" -name '*_test.dart' -not -path 'test/golden/*' | wc -l | tr -d ' ')))
done
# 子集原样用 4 路并发;子集大到接近全量时退回 1,避开 ci.yml 记录过的 SIGTERM 内存坑。
c=4
[ "$expanded" -gt 200 ] && c=1
run_tests "$c" "子集"
