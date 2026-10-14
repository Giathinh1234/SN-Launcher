#!/usr/bin/env bash
# Capture a screenshot from the connected device and pull it locally.
#   ./tool/device.sh shot <name>
#   ./tool/device.sh perf
#   ./tool/device.sh launch | stop | install <apk>
set -euo pipefail

D="${NEST_DEVICE:-192.168.1.100:40967}"
ADB="adb -s $D"
OUT="$(cd "$(dirname "$0")/.." && pwd)/build/device"

mkdir -p "$OUT"

case "${1:-}" in
  shot)
    name="${2:-shot}"
    # -d 0 renders at native resolution with no scaling.
    $ADB exec-out screencap -p > "$OUT/$name.png"
    echo "$OUT/$name.png"
    ;;

  perf)
    # 5 seconds of frame timing, reset first so the window is clean.
    $ADB shell dumpsys gfxinfo dev.snlauncher.snlauncher reset > /dev/null 2>&1 || true
    sleep 5
    $ADB shell dumpsys gfxinfo dev.snlauncher.snlauncher 2>/dev/null \
      | sed -n '1,40p'
    ;;

  mem)
    $ADB shell dumpsys meminfo dev.snlauncher.snlauncher 2>/dev/null \
      | sed -n '1,20p'
    ;;

  launch)
    $ADB shell am start -n dev.snlauncher.snlauncher/.MainActivity
    ;;

  stop)
    $ADB shell am force-stop dev.snlauncher.snlauncher
    ;;

  install)
    $ADB install -r -d "$2"
    ;;

  logcat)
    $ADB logcat -d -s flutter:* AndroidRuntime:E ActivityManager:E | tail -60
    ;;

  *)
    echo "usage: $0 {shot <name>|perf|mem|launch|stop|install <apk>|logcat}"
    exit 1
    ;;
esac