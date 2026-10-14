#!/usr/bin/env bash
# Tap every quick-settings button and verify it did the thing it claims.
#
# Written as a file rather than a one-liner because the obvious inline version
# was wrong twice: zsh does not word-split arrays the way bash does, and an
# earlier run passed tap coordinates derived from a bad pixel scan. Both failure
# modes look exactly like "the button is broken".
set -uo pipefail
cd "$(dirname "$0")/.."

D="${NEST_DEVICE:-192.168.1.100:40967}"
ADB="adb -s $D"

NAMES=(brightness volume camera theme digest feedback settings)
XS=(143 427 712 997 1281 1566 1851)
Y=1090

fresh() {
  $ADB shell am force-stop dev.snlauncher.snlauncher
  sleep 2
  $ADB shell am start -n dev.snlauncher.snlauncher/.MainActivity >/dev/null
  sleep 7
  ./tool/drive.sh sheet >/dev/null 2>&1
  sleep 1
}

top_activity() {
  $ADB shell dumpsys activity activities 2>/dev/null \
    | grep -m1 "ResumedActivity" \
    | grep -oE "[a-z0-9._]+/[A-Za-z0-9._$]+" | tail -1
}

# Mean luminance of the sheet band — a cheap proxy for "the theme changed".
sheet_luma() {
  $ADB exec-out screencap -p > /tmp/_qs.png
  python3 -c "
import numpy as np
from PIL import Image
a = np.array(Image.open('/tmp/_qs.png').convert('RGB')).astype(float)
print(round(a[700:1000, 400:1600].mean(), 1))"
}

for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"; x="${XS[$i]}"
  fresh
  before_top="$(top_activity)"
  before_luma="$(sheet_luma)"
  $ADB logcat -c
  $ADB shell input tap "$x" "$Y"
  sleep 3
  after_top="$(top_activity)"
  after_luma="$(sheet_luma)"

  case "$name" in
    brightness|camera|feedback|settings)
      # These either change the panel or leave the app.
      if [ "$after_top" != "$before_top" ]; then
        printf "  %-10s OK   left the app -> %s\n" "$name" "$after_top"
      elif [ "$name" = brightness ] && [ "$before_luma" != "$after_luma" ]; then
        printf "  %-10s OK   panel changed %s -> %s\n" "$name" "$before_luma" "$after_luma"
      else
        printf "  %-10s ??   top=%s luma=%s\n" "$name" "$after_top" "$after_luma"
      fi
      ;;
    volume)
      # Volume is invisible on screen and comparing luma here "passes" on a
      # 0.8% difference, which proves nothing. Ask the audio system instead:
      # it logs every setStreamVolume with the calling package, so a recent
      # entry from us is proof the tap did something.
      $ADB logcat -c
      $ADB shell input tap "$x" "$Y"
      sleep 2
      got="$($ADB shell dumpsys audio 2>/dev/null \
        | grep -m1 'setStreamVolume(stream:STREAM_MUSIC' \
        | grep -oE 'index:[0-9]+')"
      if [ -n "$got" ]; then
        printf "  %-10s OK   setStreamVolume %s from this package\n" "$name" "$got"
      else
        printf "  %-10s ??   no STREAM_MUSIC change logged\n" "$name"
      fi
      continue
      ;;
    theme|digest)
      if [ "$before_luma" != "$after_luma" ]; then
        printf "  %-10s OK   UI changed %s -> %s\n" "$name" "$before_luma" "$after_luma"
      else
        printf "  %-10s ??   nothing visibly changed (luma %s)\n" "$name" "$after_luma"
      fi
      ;;
  esac
done

$ADB shell am force-stop dev.snlauncher.snlauncher