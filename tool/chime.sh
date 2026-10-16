#!/usr/bin/env bash
# Audible cue for when I need something from you.
#
# Asking a question in a terminal is easy to miss when the window is not
# focused. This is the "I need you" chime.
set -euo pipefail
SOUND="${SN_CHIME:-/System/Library/Sounds/Ping.aiff}"
VOLUME="${SN_VOLUME:-0.35}"

if [[ "${SN_QUIET:-0}" == "1" ]]; then
  exit 0
fi

[[ -f "$SOUND" ]] || SOUND=/System/Library/Sounds/Glass.aiff

# Two strikes: one for the question, one after a beat so it reads as a prompt
# rather than a notification.
afplay -v "$VOLUME" "$SOUND" 2>/dev/null || true
sleep 0.35
afplay -v "$VOLUME" "$SOUND" 2>/dev/null || true