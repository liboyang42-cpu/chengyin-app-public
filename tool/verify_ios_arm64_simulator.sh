#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="${FLUTTER_BIN:-$(command -v flutter || true)}"
if [[ -z "$flutter_bin" || ! -x "$flutter_bin" ]]; then
  echo "Flutter was not found. Put it on PATH or set FLUTTER_BIN." >&2
  exit 1
fi
device_name="${IOS_SIMULATOR_NAME:-Chengyin-Parity-iPhone13-0822}"
bundle_id="com.chengyinhub.chengyinApp"
run_dir="$(mktemp -d /tmp/chengyin-ios-arm64-simulator.XXXXXX)"
build_log="$run_dir/build.log"

# ★ 2026-09-15(Task 1.4):高德拆掉之后,生产 pod 图**本身**就能编 arm64 模拟器。
#   原来那套「换成替身 plugin 跑完再还原 Podfile.lock」的备份/还原逻辑连同
#   CY_ARM64_SIMULATOR 一起删了 —— 它只为绕开 AMapFoundation 缺 arm64 切片而存在。

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This check requires an Apple Silicon host." >&2
  exit 1
fi

device_id="${IOS_SIMULATOR_UDID:-}"
if [[ -z "$device_id" ]]; then
  device_id="$({ xcrun simctl list devices available || true; } \
    | sed -nE "/${device_name//\//\\/}/s/.*\(([0-9A-F-]{36})\).*/\1/p" \
    | head -n 1)"
fi

if [[ -z "$device_id" ]]; then
  runtime_id="$(xcrun simctl list runtimes available \
    | sed -nE 's/.*(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+).*/\1/p' \
    | tail -n 1)"
  if [[ -z "$runtime_id" ]]; then
    echo "No available iOS simulator runtime was found." >&2
    exit 1
  fi
  device_id="$(xcrun simctl create \
    "$device_name" \
    com.apple.CoreSimulator.SimDeviceType.iPhone-13 \
    "$runtime_id")"
fi

xcrun simctl boot "$device_id" 2>/dev/null || true
xcrun simctl bootstatus "$device_id" -b

(
  cd "$repo_root"
  "$flutter_bin" build ios --simulator --debug >"$build_log" 2>&1
) || {
  tail -c 12000 "$build_log"
  exit 1
}

runner_app="$repo_root/build/ios/iphonesimulator/Runner.app"
runner_binary="$runner_app/Runner"
runner_archs="$(lipo -archs "$runner_binary")"
if [[ " $runner_archs " != *" arm64 "* ]]; then
  echo "Runner is not installable on an Apple Silicon simulator: $runner_archs" >&2
  exit 1
fi

xcrun simctl install "$device_id" "$runner_app"
launch_output="$(xcrun simctl launch --terminate-running-process "$device_id" "$bundle_id")"
if [[ "$launch_output" != *"$bundle_id:"* ]]; then
  echo "Runner did not launch: $launch_output" >&2
  exit 1
fi

launch_pid="${launch_output##*: }"
if [[ ! "$launch_pid" =~ ^[0-9]+$ ]]; then
  echo "Runner launch did not return a process id: $launch_output" >&2
  exit 1
fi

for _ in 1 2 3; do
  sleep 1
  if ! kill -0 "$launch_pid" 2>/dev/null; then
    echo "Runner exited during the startup observation window (pid $launch_pid)." >&2
    exit 1
  fi
done

process_command="$(ps -p "$launch_pid" -o command=)"
if [[ "$process_command" != *"/Runner.app/Runner" ]]; then
  echo "Observed pid is not the installed Runner process: $process_command" >&2
  exit 1
fi

printf 'IOS_ARM64_SIMULATOR_OK device=%s archs=%s launch=%s process=%s\n' \
  "$device_id" "$runner_archs" "$launch_output" "$process_command"
