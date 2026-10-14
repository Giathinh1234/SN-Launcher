#!/usr/bin/env python3
"""
Verify the layout running on real hardware against the measured design
constants in lib/src/theme/nest_metrics.dart.

Takes a device screenshot, locates the same elements that were measured off
the rectified photographs of a real Nest Hub, and reports the error in design
units (px at the canonical 1024x600 canvas) so results are comparable across
any screen the app runs on.

    python3 tool/verify.py build/device/home.png home
    python3 tool/verify.py build/device/sheet.png sheet

The second argument is what the caller expects to be on screen. It is asserted,
not inferred: without it a screenshot of the wrong state still prints
confident-looking numbers, which is worse than no output at all. Exits non-zero
on mismatch.

Measurement is always *relative* to whatever is behind the element — the sheet
is cream at noon and a saturated burnt orange at dusk, and the home screen now
carries a photograph, so any absolute colour threshold silently stops working.
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


def main(path, expect=None):
    """
    `expect` is one of "home", "sheet", "drawer" — what the caller believes the
    screenshot shows. Checked at the end and turned into a non-zero exit, so a
    broken gesture step fails loudly instead of producing confident numbers
    measured against the wrong screen.
    """
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

    # ── Is the sheet up? ────────────────────────────────────────────────────
    # Decided before anything else, because it determines what is measurable.
    # When the sheet is open it covers the bottom 49.6% of the screen and the
    # clock block lives inside that band — measuring it then reports the
    # occluder, not the clock.
    #
    # Detected by *flatness*, not saturation. The sheet is a solid fill; what is
    # behind it is a photograph. Saturation was the old test and it broke the
    # moment the home screen gained a landscape — a green field is as saturated
    # as any brand disc. What survives any background is that a flat fill puts
    # nearly all its pixels in one luminance bucket. Measured: 0.12 on the
    # photo frame, 0.62 on the sheet.
    sheet_top = int(H * SHEET_TOP_FRACTION)
    band = im[sheet_top + int(H * 0.05):sheet_top + int(H * 0.25)]
    hist, _ = np.histogram(grey[sheet_top + int(H * 0.06):sheet_top + int(H * 0.24)],
                           bins=256, range=(0, 256))
    flatness = hist.max() / hist.sum()
    sheet_open = flatness > 0.35

    # The sheet's own fill colour, as the mean of the pixels in the dominant
    # luminance bucket. Everything measurable in the sheet is defined *relative
    # to this*, never against a fixed colour: the fill is cream at noon and a
    # saturated burnt orange at dusk, and at dusk its own saturation (85) is
    # well above the 50 an absolute "is this colourful" threshold would use, so
    # the old test saw one continuous sheet instead of six badges.
    modal_lum = int(hist.argmax())
    fill_mask = np.abs(grey[sheet_top + int(H * 0.06):sheet_top + int(H * 0.24)]
                       - modal_lum) <= 3
    fill_rgb = im[sheet_top + int(H * 0.06):sheet_top + int(H * 0.24)][fill_mask].mean(axis=0) \
        if fill_mask.any() else np.array([255.0, 255.0, 255.0])

    rows = []

    # ── Clock / date / album on the home screen ──────────────────────────────
    # The date sits directly above the clock, so pick the ink band whose height
    # best matches the expected digit block rather than taking the first band.
    # Stop before the weather glyph, which sits on the same baseline and
    # would otherwise widen the band past the clock's own digits.
    if not sheet_open:
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
    else:
        rows.append(("clock block", "occluded by sheet", None))

    # ── Launcher sheet ──────────────────────────────────────────────────────
    if expect == "drawer":
        # Past the second detent the badge row has scrolled away and the full
        # app grid is on screen instead. Measuring the row here reports a 158px
        # pitch against an expected 118 and looks like a layout regression when
        # nothing is wrong.
        rows.append(("app badge row", "not on screen (drawer open)", None))
    elif not sheet_open:
        rows.append(("app badge row", "sheet closed", None))
    else:
        # Anything far enough from the sheet's own fill to be a badge or a
        # glyph. 40 is the middle of a wide plateau (25-70 all give the same
        # six centres), which is what a real margin should look like.
        marks = np.abs(band - fill_rgb).max(axis=2) > 40
        cols = marks.sum(axis=0)
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
            rows.append(("app badge row", "sheet is flat but no brand colour found", None))

    rows.append(("sheet state", f"{'open' if sheet_open else 'closed'} "
                                f"(flatness {flatness:.2f})", None))

    # ── Report ──────────────────────────────────────────────────────────────
    print(f"  {'element':<16} detail")
    print("  " + "-" * 66)
    for name, detail, err in rows:
        tail = "" if err is None else f"   max err {err:.1f} design px"
        print(f"  {name:<16} {detail}{tail}")

    # An assertion, not a guess: the caller said what state to expect, so a
    # screenshot that is not in that state is a failure, not something to
    # quietly measure anyway. This is what caught the harness swiping from
    # inside Android's own bottom inset — the sheet simply never opened, and
    # every downstream number was then a measurement of the wrong thing.
    problems = []
    if expect == "home" and sheet_open:
        problems.append("expected the home screen, but the sheet is open")
    if expect in ("sheet", "drawer") and not sheet_open:
        problems.append(f"expected the {expect} screen, but the sheet is closed")
    if expect == "home" and "occluded by sheet" in [d for _, d, _ in rows]:
        problems.append("clock block was not measurable")

    if problems:
        print("\n  FAIL")
        for p in problems:
            print(f"    - {p}")
    print()
    return problems


if __name__ == "__main__":
    expect = sys.argv[2] if len(sys.argv) > 2 else None
    if main(sys.argv[1], expect):
        sys.exit(1)