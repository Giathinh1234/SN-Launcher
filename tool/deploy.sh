#!/usr/bin/env bash
# Install and launch SN-Launcher on the attached tablet.
#
# Exists because adb-over-network cannot wake a sleeping device: the T20 answers
# ping but adbd is suspended on every port, so there is no way to install or
# launch remotely until someone touches the screen. Wake it, then:
#
#     ./tool/deploy.sh
#
# Options:
#   --no-build     install whatever APK is already built
#   --perf         enable the on-screen frame-timing overlay (debug builds only)
set -euo pipefail
cd "$(dirname "$0")/.."

export PATH="$HOME/flutter/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"

D="${NEST_DEVICE:-192.168.1.100:40967}"
ADB="adb -s $D"
PKG=dev.snlauncher.snlauncher
ACTIVITY="$PKG/.MainActivity"

build=1
perf=""
for arg in "$@"; do
  case "$arg" in
    --no-build) build=0 ;;
    --perf) perf="--dart-define=PERF_OVERLAY=true" ;;
    *) echo "unknown option: $arg"; exit 1 ;;
  esac
done

# ── Wait for the device rather than failing on the first refused connection ──
if ! $ADB get-state >/dev/null 2>&1; then
  echo "waiting for $D — wake the tablet if this hangs"
  for _ in $(seq 1 30); do
    adb connect "$D" >/dev/null 2>&1 || true
    if $ADB get-state >/dev/null 2>&1; then break; fi
    sleep 2
  done
fi
$ADB get-state >/dev/null 2>&1 || { echo "device not reachable"; exit 1; }

if [[ $build -eq 1 ]]; then
  echo "building release apk"
  # shellcheck disable=SC2086
  flutter build apk --release --target-platform android-arm64 $perf
fi

APK=build/app/outputs/flutter-apk/app-release.apk
[[ -f $APK ]] || { echo "no apk — run without --no-build"; exit 1; }

echo "installing $APK"
./tool/device.sh install "$APK"

# A sleeping tablet comes back with the keyguard up and a short screen timeout.
# Without this the very first screenshot is a black rectangle and every
# measurement taken from it is meaningless.
$ADB shell settings put system screen_off_timeout 1800000
$ADB shell input keyevent KEYCODE_WAKEUP
$ADB shell wm dismiss-keyguard 2>/dev/null || true
sleep 1

echo "launching"
$ADB shell am force-stop "$PKG"
sleep 1
$ADB shell am start -n "$ACTIVITY" >/dev/null
sleep 8

# Prove it actually painted rather than just started.
$ADB exec-out screencap -p > build/device/launch.png
python3 - <<'PY'
import numpy as np
from PIL import Image
a = np.array(Image.open('build/device/launch.png').convert('RGB')).astype(float)
mean = a.mean()
# A launcher that failed to build shows black or Flutter's red error box.
black = (a.max(axis=2) < 12).mean()
print(f"  mean luma {mean:.1f}, black pixels {black:.1%}",
      "-> looks like it painted" if black < 0.55 else "-> SUSPICIOUS, check the screen")
PY

echo
echo "open on the tablet. screenshots land in build/device/."