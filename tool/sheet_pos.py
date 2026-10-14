#!/usr/bin/env python3
"""
Locate the launcher sheet's top edge in a device screenshot.

Detects the hard horizontal edge where the sheet's flat fill meets whatever is
behind it, by taking the strongest vertical gradient in the lower half. Works for
any ambient palette — a colour threshold does not, because the sheet is cream in
daylight and burnt orange at dusk.
"""
import sys

import numpy as np
from PIL import Image


def sheet_top(path):
    a = np.array(Image.open(path).convert("RGB")).astype(float)
    H, W = a.shape[:2]
    # Mean absolute vertical difference, per row.
    g = a.mean(axis=2)
    grad = np.abs(np.diff(g, axis=0)).mean(axis=1)
    lo = int(H * 0.35)
    y = lo + int(np.argmax(grad[lo:]))
    return y, H


def sheet_open_fraction(path):
    """How much of the sheet is on screen, 0..1, from its top edge."""
    y, H = sheet_top(path)
    return 1.0 - y / H


if __name__ == "__main__":
    for p in sys.argv[1:]:
        y, H = sheet_top(p)
        print(f"{p:>18}  sheet top y={y:>5}  ({H} tall)  open={1 - y/H:.2f}")