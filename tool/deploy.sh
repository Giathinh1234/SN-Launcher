#!/usr/bin/env bash
# Install and launch SN-Launcher on an attached device.
#
# Designed for testing across a pile of e-waste tablets, so it never assumes
# the device it was written against. Point it anywhere:
#
#     ./tool/deploy.sh 192.168.1.55
#     ./tool/deploy.sh 192.168.1.55:5555
#     ./tool/deploy.sh                       # falls back to mDNS discovery
#     NEST_DEVICE=host:port ./tool/deploy.sh
#
# Options:
#   --no-build     install whatever APK is already built
#   --perf         on-screen frame-timing overlay
#   --scan         sweep a /24 range for a device advertising wireless adb
set -uo pipefail
cd "$(dirname "$0")/.."

export PATH="$HOME/flutter/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"

PKG=dev.snlauncher.snlauncher
ACTIVITY="$PKG/.MainActivity"
TARGET=""
build=1
perf=""
scan=0

for arg in "$@"; do
  case "$arg" in
    --no-build) build=0 ;;
    --perf) perf="--dart-define=PERF_OVERLAY=true" ;;
    --scan) scan=1 ;;
    -*) echo "unknown option: $arg"; exit 1 ;;
    *) TARGET="$arg" ;;
  esac
done

D="${TARGET:-${NEST_DEVICE:-}}"

online() { adb devices | awk -v k="$D" '$1==k && $2=="device"{found=1} END{exit !found}'; }

# ── Find a device ────────────────────────────────────────────────────────────
#
# Wireless debugging assigns an *ephemeral* port, so an address that worked last
# time is not guaranteed to work now. Order of preference:
#   1. whatever the caller gave us
#   2. `adb mdns services` — the tablet advertises its current IP:port while
#      wireless debugging is on. This is the authoritative answer.
#   3. a scan, for when mDNS is unavailable or the device is at a new address.
find_via_mdns() {
  adb mdns services 2>/dev/null \
    | grep '_adb-tls-connect' \
    | awk '{print $NF}' \
    | while read -r addr; do adb connect "$addr" >/dev/null 2>&1 || true; done
  local hit
  hit="$(adb devices | awk '$2=="device" && $1 !~ /^emulator/{print $1; exit}')"
  [ -n "$hit" ] && D="$hit" && return 0
  return 1
}

scan_for_device() {
  local base="${1:-192.168.1}"
  python3 - "$base" <<'PY'
import socket, concurrent.futures, sys
base = sys.argv[1].rsplit('.', 1)[0]
hosts = [f"{base}.{h}" for h in range(1, 255)]
ports = list(range(30000, 50000, 7)) + [5555]
def probe(a):
    h, p = a
    s = socket.socket(); s.settimeout(0.4)
    try:
        if s.connect_ex((h, p)) == 0:
            return (h, p)
    except Exception:
        pass
    finally:
        s.close()
for r in concurrent.futures.ThreadPoolExecutor(max_workers=900).map(
        probe, [(h, p) for h in hosts for p in ports]):
    if r:
        print(f"{r[0]}:{r[1]}")
PY
}

if [ "$scan" = 1 ]; then
  BASE="${D%%.*}"
  echo "scanning ${BASE}.0/24 for wireless adb (this takes a minute)"
  found=""
  while read -r hp; do
    [ -n "$hp" ] || continue
    if adb connect "$hp" 2>&1 | grep -q "connected to"; then
      found="$hp"; break
    fi
  done < <(scan_for_device "$BASE")
  if [ -n "$found" ]; then
    D="$found"; echo "found $D"
  else
    echo "nothing found on ${BASE}.0/24"; exit 1
  fi
elif [ -n "$D" ]; then
  adb connect "$D" >/dev/null 2>&1 || true
  if ! online; then
    echo "$D not answering; trying mDNS discovery"
    for _ in $(seq 1 6); do
      find_via_mdns && break
      sleep 3
    done
  fi
else
  echo "no device given; trying mDNS discovery"
  find_via_mdns || true
fi

if [ -z "$D" ] || ! online; then
  cat <<EOF
No device reachable.

Tried: ${D:-<nothing given>}, then mDNS discovery.

If the tablet is powered off or off Wi-Fi none of that can work - a machine
that is not on the network cannot be reached from it. Wake it, confirm it is on
the same Wi-Fi, and either pass its address:

    ./tool/deploy.sh 192.168.1.55

or let mDNS find it, which works whenever wireless debugging is enabled in
Developer options.
EOF
  exit 1
fi

echo "connected: $D"
export NEST_DEVICE="$D"
ADB="adb -s $D"   # re-derived: $D may have changed during discovery

# ── Build ─────────────────────────────────────────────────────────────────────
if [ "$build" -eq 1 ]; then
  echo "building release apk"
  # shellcheck disable=SC2086
  flutter build apk --release --target-platform android-arm64 $perf \
    || { echo "build failed"; exit 1; }
fi

APK=build/app/outputs/flutter-apk/app-release.apk
[ -f "$APK" ] || { echo "no apk — run without --no-build"; exit 1; }

echo "installing $APK"
$ADB install -r "$APK" || { echo "install failed"; exit 1; }

# A sleeping tablet comes back with the keyguard up and a short screen timeout.
# Without this the first screenshot is black and every measurement taken from it
# is meaningless.
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
mkdir -p build/device
$ADB exec-out screencap -p > build/device/launch.png
python3 - <<'PY'
import numpy as np
from PIL import Image
a = np.array(Image.open('build/device/launch.png').convert('RGB')).astype(float)
black = (a.max(axis=2) < 12).mean()
print(f"  mean luma {a.mean():.1f}, black pixels {black:.1%}",
      "-> looks like it painted" if black < 0.55 else "-> SUSPICIOUS, look at the screen")
PY

# Report what the hardware actually is. Useful when testing a new device and
# the launcher renders differently.
$ADB shell getprop ro.product.model 2>/dev/null | sed 's/^/  model: /'
$ADB shell getprop ro.build.version.release 2>/dev/null | sed 's/^/  android: /'
$ADB shell wm size 2>/dev/null | sed 's/^/  /'

echo
echo "open on the device. screenshots land in build/device/."