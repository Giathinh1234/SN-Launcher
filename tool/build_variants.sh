#!/usr/bin/env bash
#
# Builds the two SN-Launcher APKs.
#
# There are two versions and this script exists so they cannot drift:
#
#   ef        every feature on. The build you put on a device to find out
#             what actually happens.
#   reduced   a launcher and nothing else — settings, quick settings, the
#             app row. This is the one that ships to other people.
#
# They are the same source. The only difference is which JSON the
# SN_FEATURES define points at, so a behavioural difference between them is a
# gating bug and never a code difference.
#
# Usage:
#   tool/build_variants.sh          # both
#   tool/build_variants.sh ef       # just the ExtraFeature build
set -euo pipefail

cd "$(dirname "$0")/.."

export PATH="$HOME/flutter/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"

want="${1:-both}"

# Per-ABI for both. An e-waste tablet is usually arm64, a spare x86 box is
# usually x86_64, and shipping one fat APK to cover both is how you end up
# debugging an x86 library that is not there.
build_one() {
  local name="$1" features="$2"
  echo "=== building $name (features: $features) ==="
  flutter build apk \
    --release \
    --split-per-abi \
    --dart-define="SN_FEATURES=$features" \
    --dart-define="SN_BUILD_NAME=$name" \
    -t lib/main.dart

  local suffix=""
  [ "$name" = "ef" ] && suffix=".ef"
  local out="build/app/outputs/flutter-apk"
  for f in "$out"/app-*-release.apk; do
    [ -e "$f" ] || continue
    cp "$f" "$out/sn-launcher$suffix-${f#app-}"
    printf '  %-52s %6.1f MB\n' "$(basename "$out/sn-launcher$suffix-${f#app-}")" \
      "$(echo "scale=1; $(stat -f%z "$f") / 1048576" | bc)"
  done
}

case "$want" in
  ef)      build_one ef      assets/features.ef.json ;;
  reduced) build_one reduced assets/features.json ;;
  both)
    build_one ef      assets/features.ef.json
    build_one reduced assets/features.json
    ;;
  *) echo "usage: $0 [ef|reduced|both]" >&2; exit 2 ;;
esac

echo
echo "Both APKs share applicationId dev.snlauncher.snlauncher, so installing"
echo "one replaces the other. Open Settings → Build to see which is running."