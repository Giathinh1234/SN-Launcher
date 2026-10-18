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

# Locate aapt2 so the applicationId of what was just built can be read back out
# of the APK rather than assumed.
find_aapt2() {
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  ls -d "$sdk"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1
}

# A -P property does *not* reliably invalidate Gradle's up-to-date checks: build
# the reduced variant, then build ef with identical Dart defines, and Gradle can
# leave the previous APK in place — no error, no warning, wrong applicationId.
# Reading it back is the only way to know.
verify_application_id() {
  local apk="$1" expected="$2"
  local aapt2 actual
  aapt2="$(find_aapt2)"
  if [ -z "$aapt2" ]; then
    echo "  (aapt2 not found — skipping the applicationId check)"
    return 0
  fi
  actual="$("$aapt2" dump badging "$apk" 2>/dev/null |
            sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)"
  if [ "$actual" != "$expected" ]; then
    echo "  !! applicationId is '${actual:-<none found>}', expected '$expected'" >&2
    echo "     Gradle reused stale output. Run 'flutter clean', then rebuild." >&2
    return 1
  fi
  printf '  applicationId %-34s ok\n' "$actual"
}

# Per-ABI for both. An e-waste tablet is usually arm64, a spare x86 box is
# usually x86_64, and shipping one fat APK to cover both is how you end up
# debugging an x86 library that is not there.
build_one() {
  local name="$1" features="$2"
  local suffix=""
  [ "$name" = "ef" ] && suffix=".ef"

  # The ef build gets its own applicationId, so it installs alongside the
  # reduced build instead of silently replacing it. This is the whole of the
  # difference — see the block in android/app/build.gradle.kts.
  #
  # Always one argument, even when empty: macOS ships bash 3.2, where
  # "${arr[@]}" on an empty array is an unbound-variable error under `set -u`.
  # Passing `-PsnAppIdSuffix=` is equivalent to not passing it at all, because
  # findProperty returns an empty string either way.
  local id_arg=("-PsnAppIdSuffix=$suffix")

  echo "=== building $name (features: $features, applicationId suffix: '${suffix}') ==="
  flutter build apk \
    --release \
    --split-per-abi \
    "${id_arg[@]}" \
    --dart-define="SN_FEATURES=$features" \
    --dart-define="SN_BUILD_NAME=$name" \
    -t lib/main.dart
  local out="build/app/outputs/flutter-apk"
  for f in "$out"/app-*-release.apk; do
    [ -e "$f" ] || continue
    # basename first: ${f#app-} silently does nothing on a relative path, which
    # is how this produced "sn-launcher.ef-build/app/outputs/..." on the first
    # run. The build had succeeded and reported success; only the copy failed.
    local base dest
    base="$(basename "$f")"
    dest="$out/sn-launcher$suffix-${base#app-}"
    cp "$f" "$dest"
    printf '  %-46s %6.1f MB\n' "$(basename "$dest")" \
      "$(echo "scale=1; $(stat -f%z "$f") / 1048576" | bc)"
    verify_application_id "$dest" "dev.snlauncher.snlauncher$suffix"
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
echo "  reduced  dev.snlauncher.snlauncher        \"SN-Launcher\""
echo "  ef       dev.snlauncher.snlauncher.ef     \"SN-Launcher ef\""
echo
echo "Both can be installed on one device at the same time."