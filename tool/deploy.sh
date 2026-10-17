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

# ── Find the device ──────────────────────────────────────────────────────────
# Wireless debugging (Android 11+) assigns an *ephemeral* port. The address that
# worked last week is not guaranteed to work now, so the configured one is only
# the first guess. Order of preference:
#   1. $D, if it happens to be right
#   2. `adb mdns services` — the tablet advertises itself over mDNS while
#      wireless debugging is on, which is the authoritative answer
#   3. a scan of the ephemeral range, for when mDNS is unavailable
online() { $ADB get-state >/dev/null 2>&1; }

mdns_connect() {
  # Lines look like: adb-<hash>  _adb-tls-connect._tcp  192.168.1.100:55555
  adb mdns services 2>/dev/null \
    | grep '_adb-tls-connect' \
    | awk '{print $NF}' \
    | while read -r addr; do
        adb connect "$addr" >/dev/null 2>&1 || true
      done
  adb devices | grep -q "device$"
}

scan_connect() {
  python3 - <<'PY'
import socket, concurrent.futures
HOST = '192.168.1.100'
def probe(p):
    s = socket.socket(); s.settimeout(1.0)
    try:
        if s.connect_ex((HOST, p)) == 0:
            return p
    except Exception:
        pass
    finally:
        s.close()
for p in concurrent.futures.ThreadPoolExecutor(max_workers=500).map(
        probe, range(30000, 50000)):
    if p:
        print(p)
PY
}

connect_any() {
  adb connect "$D" >/dev/null 2>&1 || true
  if online; then return 0; fi

  echo "  $D not answering; trying mDNS discovery"
  for _ in $(seq 1 10); do
    mdns_connect && online && { D="$($ADB devices | awk -v k="device$" '$2==k{print $1}' | head -1)"; return 0; }
    sleep 3
  done

  echo "  mDNS found nothing; scanning the ephemeral port range"
  for p in $(scan_connect); do
    if adb connect "192.168.1.100:$p" 2>&1 | grep -q "connected to"; then
      D="192.168.1.100:$p"
      echo "  found adb on port $p"
      return 0
    fi
  done
  return 1
}

if ! connect_any; then
  cat <<EOF
device not reachable.

  Tried: $D, mDNS discovery, and a scan of ports 30000-49999 on 192.168.1.100.

If the tablet is powered off or off Wi-Fi, none of that can work -- a machine
that is not on the network cannot be reached from it. Wake it, confirm it is on
the same Wi-Fi, and run this again.

If it IS awake and on Wi-Fi but wireless debugging is off, enable it in
Developer options; it will show a fresh IP:port.
EOF
  exit 1
fi

echo "connected: $D"
export NEST_DEVICE="$D"
# `$ADB` was expanded at the top of this script with the *original* address, so
# it still names the stale port after discovery. Re-derive it, or every command
# after install silently targets a device that is not there.
ADB="adb -s $D"

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