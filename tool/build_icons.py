#!/usr/bin/env python3
"""
Build the bundled Material Symbols subset and its Dart lookup table.

Why a subset at all: the official Material Symbols Rounded variable font is
**15 MB** with four axes. That is absurd to ship in an APK meant for 1 GB
e-waste hardware, and three of the four axes (FILL, GRAD, opsz) are not even
reachable through Flutter's IconData — it cannot address variable axes.

So: take only the codepoints this launcher uses, instantiate the variable font
down to a single static instance (FILL=0, GRAD=0, opsz=24, wght=400), and ship
that. 15 MB -> 52 KB, and every glyph still renders.

The codepoints come from Google's own authoritative `.codepoints` file in the
material-design-icons repo, never from guesswork: a wrong codepoint renders as
the wrong icon or a blank box, and neither is obvious until you look at it.

    python3 tool/build_icons.py

Requires: fonttools.
"""
import os
import subprocess
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_TTF = os.path.join(ROOT, "assets", "fonts", "MaterialSymbolsRounded.ttf")
OUT_DART = os.path.join(ROOT, "lib", "src", "theme", "nest_icons.dart")

BASE = ("https://raw.githubusercontent.com/google/material-design-icons/"
        "master/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D")
TTF_URL = f"{BASE}.ttf"
CPS_URL = f"{BASE}.codepoints"

# The icons this launcher actually draws. Add a name here, re-run, done.
WANTED = """
brightness_6 brightness_7 dark_mode light_mode mode_night night_shelter
volume_up volume_down volume_mute volume_off
photo_camera camera_alt videocam videocam_off cast cast_connected
calendar_month event event_available today edit_calendar
cloud cloud_done cloud_sync wb_sunny wb_twilight wb_incandescent
thermostat thermostat_auto device_thermostat
settings settings_suggest tune
zoom_in zoom_out
feedback info help_outline support_agent contact_support
add remove close check chevron_right chevron_left arrow_back arrow_forward
more_horiz more_vert expand_more expand_less
wifi wifi_off bluetooth bluetooth_audio signal_wifi_4_bar
nightlight bedtime bedtime_off lightbulb light_mode
star star_half star_outline favorite favorite_border
search refresh sync update
schedule timer alarm alarm_on do_not_disturb_on notifications
map location_on directions_car directions_walk local_gas_station
local_pharmacy local_hospital restaurant school work store storefront
home home_work smart_display tv desktop_windows laptop
sports_esports music_note queue_music library_music album audiotrack
podcasts radio headphones speaker graphic_eq
news article rss_feed live_tv theaters movie
person account_circle contacts group
access_time schedule history
image photo_library photo_album collections wallpaper collections_bookmark
crop_original landscape park forest
play_arrow pause stop skip_next skip_previous shuffle repeat
mic mic_off mic_none keyboard record_voice_over
chat smart_toy auto_awesome
link content_copy share archive unarchive print
contrast palette color_lens format_color_fill
bolt energy_savings_leaf solar_power eco recycling
grid_view apps dashboard tab tabs view_list view_agenda
lock lock_open translate language public
emoticon mood sentiment_satisfied
""".split()


def fetch(url, dest):
    if os.path.exists(dest):
        return dest
    print(f"  downloading {os.path.basename(dest)} …")
    with urllib.request.urlopen(url, timeout=120) as r, open(dest, "wb") as f:
        f.write(r.read())
    return dest


def main():
    tmp = os.path.join(HERE, ".msym-cache")
    os.makedirs(tmp, exist_ok=True)
    os.makedirs(os.path.dirname(OUT_TTF), exist_ok=True)
    os.makedirs(os.path.dirname(OUT_DART), exist_ok=True)

    ttf = fetch(TTF_URL, os.path.join(tmp, "full.ttf"))
    cps_path = fetch(CPS_URL, os.path.join(tmp, "codepoints.txt"))

    codepoints = {}
    with open(cps_path) as f:
        for line in f:
            parts = line.split()
            if len(parts) == 2:
                codepoints[parts[0]] = int(parts[1], 16)

    names = sorted({n for n in WANTED if n in codepoints})
    missing = sorted({n for n in WANTED if n not in codepoints})
    if missing:
        # A missing name means the upstream font renamed it; fail loudly rather
        # than silently shipping a glyph-less icon.
        sys.exit(f"unknown Material Symbols names: {missing}")
    if not names:
        sys.exit("no icons matched — upstream codepoints file may have changed")

    unicodes = ",".join(f"U+{codepoints[n]:04X}" for n in names)

    subset = os.path.join(tmp, "subset.ttf")
    subprocess.run(
        ["pyftsubset", ttf, f"--unicodes={unicodes}",
         f"--output-file={subset}", "--layout-features=",
         "--no-hinting", "--desubroutinize", "--name-IDs=*"],
        check=True,
    )
    # Freeze the variable axes. Flutter's IconData cannot set them, so leaving
    # fvar in place means the renderer picks an arbitrary instance.
    subprocess.run(
        ["python3", "-m", "fontTools.varLib.instancer", subset,
         "FILL=0", "GRAD=0", "opsz=24", "wght=400",
         f"--output={OUT_TTF}"],
        check=True,
    )

    from fontTools.ttLib import TTFont
    font = TTFont(OUT_TTF)
    cmap = font.getBestCmap()
    unmapped = [n for n in names if codepoints[n] not in cmap]
    if unmapped:
        sys.exit(f"subset dropped glyphs it should not have: {unmapped}")

    full_mb = os.path.getsize(ttf) / 1e6
    out_kb = os.path.getsize(OUT_TTF) / 1e3
    print(f"  {len(names)} icons, {full_mb:.1f} MB -> {out_kb:.0f} KB")

    with open(OUT_DART, "w") as f:
        f.write(_dart(names, codepoints))
    print(f"  wrote {os.path.relpath(OUT_DART, ROOT)}")


def _camel(name):
    return "".join(p.capitalize() for p in name.split("_"))


def _dart(names, codepoints):
    lines = [
        "// GENERATED by tool/build_icons.py — do not edit by hand.",
        "//",
        "// Google's own icon set, subsetted and frozen to a static instance.",
        "// See that script for why this exists rather than shipping the 15 MB",
        "// variable font.",
        "//",
        "// Licence: Apache License 2.0. See",
        "// assets/fonts/MATERIAL_SYMBOLS_LICENSE.txt.",
        "//",
        "// Codepoints are Google's, taken from the authoritative `.codepoints`",
        "// file in the material-design-icons repository. Verified against the",
        "// subset's own cmap before this file was written.",
        "",
        "import 'package:flutter/widgets.dart';",
        "",
        "// Icon names are PascalCase so each constant reads as the Material",
        "// Symbols name it came from (NestIcons.PhotoCamera).",
        "// ignore_for_file: constant_identifier_names",
        "",
        "/// Material Symbols Rounded, subsetted to the icons this launcher uses.",
        "abstract final class NestIcons {",
    ]
    for n in names:
        lines.append(
            f"  /// `{n}`\n"
            f"  static const IconData {_camel(n)} = "
            f"IconData(0x{codepoints[n]:05x}, fontFamily: 'MaterialSymbolsRounded');"
        )
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


if __name__ == "__main__":
    main()