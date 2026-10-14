#!/usr/bin/env bash
# Drive the launcher on the attached device with synthetic touches.
#
#   ./tool/drive.sh home          close the sheet
#   ./tool/drive.sh sheet         swipe up from the bottom edge
#   ./tool/drive.sh drawer        swipe up past the detent
#   ./tool/drive.sh next | prev   horizontal carousel
#   ./tool/drive.sh assist        tap the centre
set -euo pipefail

D="${NEST_DEVICE:-192.168.1.100:40967}"
ADB="adb -s $D"

# `wm size` reports the panel's *natural* orientation, which is not what input
# coordinates use once the activity has rotated. Read the real framebuffer size
# from a screencap instead so swipes land where they look like they land.
read -r W H <<<"$($ADB exec-out screencap -p | python3 -c '
import struct, sys
d = sys.stdin.buffer.read(24)
print(*struct.unpack(">II", d[16:24]))')"
: "${W:?could not read screen size from device}"

cx=$(( W / 2 )); cy=$(( H / 2 ))

case "${1:-}" in
  home)
    # Swipe down to dismiss the sheet. Start below the very top edge: y=10 is
    # inside Android's notification-shade hot zone and drags the shade over the
    # launcher instead.
    $ADB shell input swipe $cx $(( H / 4 )) $cx $(( H - 40 )) 260
    ;;

  sheet)
    # Swipe up from the very bottom — the edge the drag handle lives on.
    $ADB shell input swipe $cx $(( H - 10 )) $cx $(( H / 3 )) 300
    ;;

  drawer)
    # A shorter, faster flick carries past the detent into the full grid.
    $ADB shell input swipe $cx $(( H - 6 )) $cx $(( H / 6 )) 120
    ;;

  next)
    $ADB shell input swipe $(( W - 60 )) $cy 120 $cy 220
    ;;

  prev)
    $ADB shell input swipe 120 $cy $(( W - 60 )) $cy 220
    ;;

  assist)
    $ADB shell input tap $cx $cy
    ;;

  *)
    echo "usage: $0 {home|sheet|drawer|next|prev|assist}"
    exit 1
    ;;
esac

# Let the settle animations finish before the caller screenshots.
sleep 1.5