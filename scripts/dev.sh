#!/usr/bin/env bash
#
# 一条命令做完「构建 → 装机 → 启动 → 截图 → 抓日志」。
#
# 为什么要有这个脚本（都是实测出来的耗时）：
#
#   · 固定 `sleep 9` 等应用起来 —— 实测安装 1.3s、启动 1.0s、首帧 <1s，
#     固定 sleep 白等一大截。这里改成 sleep 2.5。
#   · ⚠️ 不要用 `simctl spawn <dev> launchctl list` 轮询「进程起来没有」：
#     这条命令单次就要 **1.35s**，而且 App 的 label 未必含应用名，
#     一旦匹配不上就会空转到轮询上限（实测一台设备白等 84s）。宁可直接短等。
#   · `log show --last 1m` 是全量扫日志（3.0s）。改成 `--last 40s` + 跑完再取，
#     只覆盖本轮、也不会漏掉启动早期的行（比后台 `log stream` 更稳，不用管时序）。
#   · 两台设备（iPhone + iPad）分开跑时，构建只做一次、同一个 .app 装两次。
#   · 手写 UDID 容易打错 —— 这里默认自动取**所有已启动**的模拟器。
#
# 用法：
#   scripts/dev.sh                        # 构建 + 所有已启动的模拟器都跑一遍
#   scripts/dev.sh --device "iPad (A16)"  # 只跑指定设备（名字或 UDID 都行）
#   scripts/dev.sh --no-build             # 跳过构建（只改了脚本/只想看现象时）
#   scripts/dev.sh --env START_ADD=1      # 给 App 传环境变量（调试开关用）
#   scripts/dev.sh --log RACKDBG          # 只打印匹配这些关键字的日志行
#
# ⚠️ 不要在这里加 `ARCHS=` / `ENABLE_PREVIEWS=` 这类**每次调用都变**的覆盖参数：
#    构建参数一变，Xcode 就认为产物失效、下一轮直接全量重编（实测 13s → 49s）。
#    要改构建设置就改 `project.yml` + `project.pbxproj`，保持每次调用一致。
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

PROJECT="DaiDaiJi.xcodeproj"
SCHEME="DaiDaiJi"
BUNDLE_ID="com.daidaiji.app"
DERIVED="/tmp/ddj-dd"
APP="$DERIVED/Build/Products/Debug-iphonesimulator/DaiDaiJi.app"
SHOT_DIR="/tmp"
MAX_LOG_LINES="${MAX_LOG_LINES:-40}"

DO_BUILD=1
DEVICE_FILTER=""
LOG_FILTER=""
ENV_VARS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build) DO_BUILD=0; shift ;;
        --device)   DEVICE_FILTER="${2:-}"; shift 2 ;;
        --log)      LOG_FILTER="${2:-}"; shift 2 ;;
        --env)      ENV_VARS+=("${2:-}"); shift 2 ;;
        -h|--help)  sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "未知参数：$1（--help 看用法）" >&2; exit 2 ;;
    esac
done

# ── 取设备：默认所有已启动的模拟器 ──
# 输出「UDID<TAB>名字」两列。
# ⚠️ 只能用 while read 收集，不能用 mapfile —— macOS 自带的是 bash 3.2，没有它。
read_devices() {
    xcrun simctl list devices booted -j | python3 -c '
import json, sys
for items in json.load(sys.stdin)["devices"].values():
    for d in items:
        if d.get("state") == "Booted":
            print(d["udid"] + "\t" + d["name"])
'
}

DEVICES=()
while IFS=$'\t' read -r udid name; do
    [[ -n "$udid" ]] && DEVICES+=("$udid"$'\t'"$name")
done < <(read_devices)

if [[ ${#DEVICES[@]} -eq 0 ]]; then
    echo "没有已启动的模拟器。先启动一台，例如：" >&2
    echo "  xcrun simctl boot 'iPhone 17 Pro'   # 或 'iPad (A16)'" >&2
    exit 1
fi

# 选择目标设备
targets=()
for row in "${DEVICES[@]}"; do
    udid="${row%%$'\t'*}"; name="${row#*$'\t'}"
    if [[ -z "$DEVICE_FILTER" || "$DEVICE_FILTER" == "$udid" || "$DEVICE_FILTER" == "$name" ]]; then
        targets+=("$row")
    fi
done
if [[ ${#targets[@]} -eq 0 ]]; then
    echo "没有匹配的设备：$DEVICE_FILTER" >&2
    echo "已启动的是：" >&2
    for row in "${DEVICES[@]}"; do echo "  ${row%%$'\t'*}  ${row#*$'\t'}"; done >&2
    exit 1
fi

# ── 构建（只做一次；destination 用第一台目标设备，保持增量缓存稳定）──
first_udid="${targets[0]%%$'\t'*}"
if [[ $DO_BUILD -eq 1 ]]; then
    start=$(date +%s)
    set +e
    build_out=$(xcodebuild -quiet -project "$PROJECT" -scheme "$SCHEME" \
        -sdk iphonesimulator -destination "id=$first_udid" \
        -derivedDataPath "$DERIVED" build 2>&1)
    status=$?
    set -e
    echo "$build_out" | grep -E "error:|warning: " | head -20 || true
    if [[ $status -ne 0 ]]; then
        echo "❌ 构建失败（$(( $(date +%s) - start ))s）" >&2
        exit $status
    fi
    echo "✅ 构建成功（$(( $(date +%s) - start ))s）"
else
    echo "⏭  跳过构建（--no-build）"
fi

[[ -d "$APP" ]] || { echo "找不到产物：$APP（先去掉 --no-build 跑一次）" >&2; exit 1; }

# ── 逐台设备：装机 → 启动 → 截图 → 取本轮日志 ──
env_args=()
for kv in ${ENV_VARS[@]+"${ENV_VARS[@]}"}; do
    env_args+=("SIMCTL_CHILD_${kv%%=*}=${kv#*=}")
done

for row in "${targets[@]}"; do
    udid="${row%%$'\t'*}"; name="${row#*$'\t'}"
    slug=$(echo "$name" | tr ' ()' '---' | tr -cd '[:alnum:]-')
    shot="$SHOT_DIR/ddj-$slug.png"
    logfile=$(mktemp /tmp/ddj-log-XXXXXX.txt)
    t0=$(date +%s)
    echo "── $name"

    xcrun simctl install "$udid" "$APP"
    env "${env_args[@]+${env_args[@]}}" \
        xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" >/dev/null

    # 等首帧。热启动 2.5s 够；但「装完第一次冷启动」在 iPad 上要 4s 上下，
    # 等太短会截到白屏（看起来像 App 挂了，其实只是还没画完）。
    sleep "${SETTLE:-3.5}"
    xcrun simctl io "$udid" screenshot "$shot" >/dev/null 2>&1

    # 只取本轮日志：时间窗卡住上一轮，避免捞到旧数据
    xcrun simctl spawn "$udid" log show --last 40s --style compact \
        --predicate "process == \"DaiDaiJi\"" >"$logfile" 2>/dev/null || true

    echo "📷 $shot   （本轮 ${name} 用时 $(( $(date +%s) - t0 ))s）"

    if [[ -n "$LOG_FILTER" ]]; then
        grep -oE "$LOG_FILTER.*" "$logfile" | tail -"$MAX_LOG_LINES" || echo "（没有匹配 $LOG_FILTER 的日志）"
    else
        # 默认滤掉系统的 com.apple.* 噪声，只留 App 自己 NSLog 的行
        grep -v '\[com\.apple\.' "$logfile" | tail -"$MAX_LOG_LINES" || true
    fi
    rm -f "$logfile"
done
