#!/usr/bin/env bash
# End-to-end check on real hardware: install, launch, exercise every gesture,
# capture screenshots, and pull frame + memory stats.
set -uo pipefail

cd "$(dirname "$0")/.."
export PATH="$HOME/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"

APK=build/app/outputs/flutter-apk/app-release.apk
[ -f "$APK" ] || { echo "build the apk first: flutter build apk --release --target-platform android-arm64"; exit 1; }

hr() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

hr "install"
./tool/device.sh install "$APK"

hr "launch"
./tool/device.sh stop
./tool/device.sh launch
sleep 4

hr "cold start"
./tool/device.sh stop; sleep 1
START=$(python3 -c 'import time;print(time.time())')
./tool/device.sh launch >/dev/null
# Poll logcat for the first frame instead of guessing a sleep.
for i in $(seq 1 40); do
  if ./tool/device.sh logcat 2>/dev/null | grep -q "Displayed dev.snlauncher"; then break; fi
  sleep 0.5
done
python3 -c "import time;print(f'  tap -> first frame: {time.time()-$START:.1f}s')"

hr "home screen"
./tool/device.sh shot dev_home

hr "swipe up -> launcher sheet"
./tool/drive.sh sheet
./tool/device.sh shot dev_sheet

hr "swipe up again -> full app drawer"
./tool/drive.sh sheet
./tool/device.sh shot dev_drawer

hr "back to home"
./tool/device.sh stop; ./tool/device.sh launch; sleep 3

hr "frame timing (5s idle)"
./tool/device.sh perf

hr "frame timing (5s scrolling the drawer)"
./tool/drive.sh sheet; ./tool/drive.sh sheet
./tool/device.sh perf

hr "memory"
./tool/device.sh mem

hr "errors"
./tool/device.sh logcat

hr "verify"
for f in dev_home dev_sheet dev_drawer; do
  [ -f "build/device/$f.png" ] && python3 tool/verify.py "build/device/$f.png"
done