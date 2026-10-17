#!/usr/bin/env bash
# Build every platform this project targets, skipping what the host cannot do.
#
# Not all of these are buildable from one machine:
#
#   Android   — any host with the SDK. Works everywhere.
#   macOS     — needs a full Xcode, not just the Command Line Tools.
#   Linux     — needs a Linux host. Flutter cannot cross-compile desktop
#               targets, so this has to run on the machine that will run it.
#
# Rather than failing on the first unavailable target, this reports which are
# buildable here and exits non-zero only if *none* succeeded.
#
#     ./tool/build_all.sh
set -uo pipefail
cd "$(dirname "$0")/.."

export PATH="$HOME/flutter/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"

OUT=build/release
mkdir -p "$OUT"

built=0
skipped=0

banner() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

# ── Android ──────────────────────────────────────────────────────────────────
banner "Android"
if ! command -v java >/dev/null && [ -z "${JAVA_HOME:-}" ]; then
  echo "  skipped: no JDK"
  skipped=$((skipped + 1))
else
  # Per-ABI APKs are what you actually side-load to a real tablet. The
  # universal APK is 48 MB because it carries three ABIs; the arm64 one is
  # 17.6 MB, which matters on a metered connection.
  flutter build apk --release --split-per-abi 2>&1 | grep -E "^✓|Error|FAILURE" || true
  flutter build apk --release 2>&1 | grep -E "^✓|Error|FAILURE" || true
  flutter build appbundle --release 2>&1 | grep -E "^✓|Error|FAILURE" || true
  for f in build/app/outputs/flutter-apk/app-*-release.apk \
           build/app/outputs/flutter-apk/app-release.apk \
           build/app/outputs/bundle/release/app-release.aab; do
    [ -f "$f" ] || continue
    cp "$f" "$OUT/"
  done
  if compgen -G "$OUT/*" >/dev/null; then
    built=$((built + 1))
  else
    echo "  no android artefacts produced"
    skipped=$((skipped + 1))
  fi
fi

# ── macOS ────────────────────────────────────────────────────────────────────
banner "macOS"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "  skipped: not macOS"
  skipped=$((skipped + 1))
elif ! ls -d /Applications/Xcode*.app >/dev/null 2>&1 &&
     ! xcode-select -p 2>/dev/null | grep -q "/Applications/Xcode.app"; then
  # `xcode-select -p` pointing at CommandLineTools is not enough: Flutter needs
  # the full Xcode for the macOS SDK and the AppKit build phase.
  echo "  skipped: full Xcode not installed"
  echo "           (only the Command Line Tools are present, which is not enough)"
  echo "           install Xcode, then: xcode-select -s /Applications/Xcode.app"
  skipped=$((skipped + 1))
else
  if flutter build macos --release 2>&1 | grep -E "^✓|Error|FAILURE|Xcode"; then
    rm -rf "$OUT/SN-Launcher.app"
    cp -R "build/macos/Build/Products/Release/SN-Launcher.app" "$OUT/" 2>/dev/null && built=$((built + 1))
  fi
fi

# ── Linux ────────────────────────────────────────────────────────────────────
banner "Linux"
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "  skipped: Flutter cannot cross-compile desktop targets."
  echo "           Run this script on the Linux machine (or in a container) to"
  echo "           produce the binary. Dependencies:"
  echo "             sudo apt install clang cmake ninja-build pkg-config \\"
  echo "                 libgtk-3-dev liblzma-dev"
  skipped=$((skipped + 1))
else
  flutter build linux --release 2>&1 | grep -E "^✓|Error|FAILURE" || true
  if [ -d build/linux/x64/release/bundle ]; then
    rm -rf "$OUT/SN-Launcher-linux-x64"
    cp -R build/linux/x64/release/bundle "$OUT/SN-Launcher-linux-x64"
    built=$((built + 1))
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
banner "Artefacts in $OUT/"
for f in "$OUT"/*; do
  [ -e "$f" ] || continue
  if [ -d "$f" ]; then
    printf '  %-34s %s\n' "$(basename "$f")/" "$(du -sh "$f" | cut -f1)"
  else
    printf '  %-34s %s\n' "$(basename "$f")" "$(du -h "$f" | cut -f1)"
  fi
done

echo
if [ "$built" -eq 0 ]; then
  echo "nothing built"
  exit 1
fi
echo "$built target(s) built, $skipped skipped for want of a toolchain"