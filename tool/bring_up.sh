#!/usr/bin/env bash
#
# Waits for Android devices to appear on the network, then identifies each one
# and installs the matching SN-Launcher APK.
#
# Both e-waste tablets sleep aggressively and drop wireless debugging with them,
# so "connect to the device" fails far more often than it does on a phone. This
# polls instead, because a device that is asleep is a normal state here and not
# an error worth giving up on.
#
#   tool/bring_up.sh                 wait 10 min, install the ef build
#   tool/bring_up.sh reduced         install the reduced build
#   tool/bring_up.sh ef 20           wait 20 min
set -uo pipefail

cd "$(dirname "$0")/.."

variant="${1:-ef}"
minutes="${2:-10}"
suffix=".ef"
[ "$variant" = "reduced" ] && suffix=""

apk_dir="build/app/outputs/flutter-apk"
out="build/shots"
mkdir -p "$out"

if ! ls "$apk_dir"/sn-launcher"$suffix"-*-release.apk >/dev/null 2>&1; then
  echo "no APKs in $apk_dir — run tool/build_variants.sh $variant first" >&2
  exit 1
fi

pick_apk() {
  # $1 = ro.product.cpu.abi. Flutter's suffix matches the ABI exactly, so
  # arm64-v8a -> sn-launcher.ef-arm64-v8a-release.apk.
  local abi="$1"
  ls "$apk_dir/sn-launcher$suffix-$abi-release.apk" 2>/dev/null
}

deadline=$(( $(date +%s) + minutes * 60 ))
seen=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  while read -r hostport; do
    [ -z "$hostport" ] && continue
    case "$hostport" in
      # Avoid re-doing a device already handled this run.
      *"|$hostport") continue ;;
    esac
    seen="$seen|$hostport"

    printf '\n=== %s ===\n' "$hostport"
    if ! adb connect "$hostport" 2>&1 | tail -1 | grep -q 'connected'; then
      echo "  refused; will retry next pass"
      seen="${seen%|$hostport}"
      continue
    fi

    abi=$(adb -s "$hostport" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')
    model=$(adb -s "$hostport" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    maker=$(adb -s "$hostport" shell getprop ro.product.manufacturer 2>/dev/null | tr -d '\r')
    release=$(adb -s "$hostport" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
    size=$(adb -s "$hostport" shell wm size 2>/dev/null | tr -d '\r' | sed 's/.*: //')
    density=$(adb -s "$hostport" shell wm density 2>/dev/null | tr -d '\r' | sed 's/.*: //')
    ram=$(adb -s "$hostport" shell cat /proc/meminfo 2>/dev/null | head -1 | tr -d '\r' \
          | awk '{printf "%.1f GB", $2/1048576}')
    aspect=$(echo "$size" | awk -F'x' '{printf "%.2f:1", $1/$2}')

    printf '  %s %s, Android %s\n' "$maker" "$model" "$release"
    printf '  %s %s @ %s (%s)\n' "$size" "$aspect" "$density" "$abi"
    printf '  RAM %s\n' "$ram"

    apk=$(pick_apk "$abi")
    if [ -z "$apk" ]; then
      echo "  !! no APK for ABI '$abi' — nothing installed"
      continue
    fi

    printf '  installing %s\n' "$(basename "$apk")"
    if adb -s "$hostport" install -r -d "$apk" 2>&1 | tail -2 | sed 's/^/    /'; then
      adb -s "$hostport" shell monkey -p dev.snlauncher.snlauncher \
        -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
      sleep 6
      adb -s "$hostport" exec-out screencap -p > "$out/$variant-$(echo "$hostport" | tr ':' '_').png"
      printf '  screenshot -> %s\n' "$out/$variant-$(echo "$hostport" | tr ':' '_').png"
    fi
  done < <(adb mdns services 2>/dev/null | grep -v '^List' | awk -F'\t' '{print $3}')

  n=$(echo "$seen" | tr '|' '\n' | grep -c . || true)
  printf '\r  waiting… %s device(s) handled, %ss left   ' \
    "$((n > 0 ? n - 1 : 0))" "$((deadline - $(date +%s)))"
  sleep 15
done

echo
echo "done. devices currently attached:"
adb devices | sed 's/^/  /'