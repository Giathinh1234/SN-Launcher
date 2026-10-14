#!/usr/bin/env python3
"""
Verify the layout running on real hardware against the measured design
constants in lib/src/theme/nest_metrics.dart.

Takes a device screenshot, locates the same elements that were measured off
the rectified photographs of a real Nest Hub, and reports the error in design
units (px at the canonical 1024x600 canvas) so results are comparable across
any screen the app runs on.

    python3 tool/verify.py build/device/home.png
"""
import sys
import numpy as np
from PIL import Image

# ── Design constants, mirrored from lib/src/theme/nest_metrics.dart ──────────
DESIGN_W, DESIGN_H = 1024.0, 600.0

HOME_MARGIN_X        = 66.0   # ink of the leading "0" lands at 69
CLOCK_TEXT_BOX_BOTTOM = 534.0 # digit baseline sits 13 design px above this
CLOCK_DIGIT_BOTTOM    = 521.0
CLOCK_DIGIT_HEIGHT    = 61.0
ALBUM_MARGIN_X        = 52.0

SHEET_TOP_FRACTION   = 0.496
APP_ROW_CENTER_FRAC  = 0.347
DIVIDER_FRAC         = 0.573
QS_CENTER_FRAC       = 0.824
BADGE_SIZE           = 80.0
APP_ROW_SPACING      = 118.0
QS_GLYPH_SIZE        = 40.0


def bbox(mask, x0, x1, y0, y1):
    s = mask[y0:y1, x0:x1]
    if not s.any():
        return None
    ys, xs = np.where(s)
    return (x0 + xs.min(), y0 + ys.min(), x0 + xs.max(), y0 + ys.max())


def col_runs(mask, x0, x1, y0, y1, min_w):
    s = mask[y0:y1, x0:x1]
    cols = s.sum(axis=0)
    runs, start = [], None
    for i, v in enumerate(cols):
        if v > 2 and start is None:
            start = i
        elif v <= 2 and start is not None:
            if i - start >= min_w:
                runs.append((start + x0, i - 1 + x0))
            start = None
    return runs


def main(path):
    im = np.array(Image.open(path).convert("RGB")).astype(float)
    H, W = im.shape[:2]
    u = min(W / DESIGN_W, H / DESIGN_H)
    grey = im.mean(axis=2)

    print(f"\n  screenshot {W}x{H}   scale u={u:.4f}   aspect {W/H:.3f} "
          f"(Nest Hub {DESIGN_W/DESIGN_H:.3f})\n")

    # Text/glyph ink: pick whichever polarity actually carries content.
    lum_mean = grey.mean()
    if lum_mean > 128:
        ink = grey < 120
        print("  polarity: dark ink on light background\n")
    else:
        ink = grey > 150
        print("  polarity: light ink on dark background\n")

    sat = im.max(axis=2) - im.min(axis=2)
    colour = sat > 50

    rows = []

    # ── Clock / date / album on the home screen ──────────────────────────────
    # The date sits directly above the clock, so pick the ink band whose height
    # best matches the expected digit block rather than taking the first band.
    # Stop before the weather glyph, which sits on the same baseline and
    # would otherwise widen the band past the clock's own digits.
    left0, left1 = int(W * 0.02), int(W * 0.26)
    region = ink[:, left0:left1]
    rowcount = region.sum(axis=1)
    bands, start = [], None
    for y in range(int(H * 0.45), H):
        if rowcount[y] > 0 and start is None:
            start = y
        elif rowcount[y] == 0 and start is not None:
            bands.append((start, y - 1))
            start = None
    if start is not None:
        bands.append((start, H - 1))

    want = CLOCK_DIGIT_HEIGHT * u
    if bands:
        band = min(bands, key=lambda b: abs((b[1] - b[0] + 1) - want))
        sub = region[band[0]:band[1] + 1]
        xs = np.where(sub.any(axis=0))[0]
        left = left0 + xs.min()

        # `Positioned(bottom: H - px(534))` puts the text box's bottom edge
        # at y = 534*u from the top; the digits sit 13 design px above that.
        exp_bottom = CLOCK_DIGIT_BOTTOM * u
        exp_left = 69 * u
        rows.append((
            "clock block",
            f"left {left} (exp {exp_left:.0f})  bottom {band[1]} "
            f"(exp {exp_bottom:.0f})  h {band[1]-band[0]+1} (exp {want:.0f})",
            max(abs(left - exp_left), abs(band[1] - exp_bottom)) / u,
        ))
    else:
        rows.append(("clock block", "not found", None))

    # ── Launcher sheet ──────────────────────────────────────────────────────
    sheet_top = int(H * SHEET_TOP_FRACTION)
    band = colour[sheet_top + int(H*0.05):sheet_top + int(H*0.25)]
    if band.any():
        cols = band.sum(axis=0)
        runs, start = [], None
        for i, v in enumerate(cols):
            if v > 3 and start is None:
                start = i
            elif v <= 3 and start is not None:
                if i - start > int(20 * u):
                    runs.append((start + i) // 2)
                start = None
        if len(runs) >= 4:
            centres = runs[:6]
            pad = 41 * u
            pitch = APP_ROW_SPACING * u
            exp = [pad + BADGE_SIZE*u/2 + i*pitch for i in range(len(centres))]
            err = max(abs(c - e) for c, e in zip(centres, exp)) / u
            rows.append((
                "app badge row",
                f"centres {[round(c) for c in centres]}  "
                f"pitch {(centres[-1]-centres[0])/max(1,len(centres)-1)/u:.1f} "
                f"(exp {APP_ROW_SPACING:.0f})",
                err,
            ))
        else:
            rows.append(("app badge row", "sheet not open", None))
    else:
        rows.append(("app badge row", "sheet closed", None))

    # ── Report ──────────────────────────────────────────────────────────────
    print(f"  {'element':<16} detail")
    print("  " + "-" * 66)
    for name, detail, err in rows:
        tail = "" if err is None else f"   max err {err:.1f} design px"
        print(f"  {name:<16} {detail}{tail}")
    print()


if __name__ == "__main__":
    main(sys.argv[1])