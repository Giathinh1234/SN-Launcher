#!/usr/bin/env python3
"""
Generate the default photo-frame landscape.

Why generated rather than shipped as a stock photo: licensing. A bundled
landscape photo has to come from somewhere with clear rights, and generated art
has none of that baggage. It is also tiny on disk and, more importantly, decodes
to a fraction of the memory a real photograph would.

A layered-ridge scene with atmospheric perspective — distant ridges pale and
hazy, near ridges dark and sharp. That is the sort of image a Nest Hub's Photo
Frame shows, and it complements the ambient palette instead of fighting it.

    python3 tool/make_landscape.py

Output: assets/photo/landscape.jpg (plus the Android launcher icon set).
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

W, H = 1600, 900
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "photo")


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def sky_height(y):
    """Vertical sky gradient: deep blue up top, warm amber at the horizon."""
    top = (28, 52, 96)
    mid = (86, 126, 168)
    low = (232, 168, 116)
    horizon = H * 0.62
    if y < horizon * 0.55:
        return lerp(top, mid, y / (horizon * 0.55))
    return lerp(mid, low, (y - horizon * 0.55) / (horizon * 0.45))


def ridge(seed, base_y, amplitude, roughness, samples=7):
    """A single mountain silhouette as a polyline of (x, y)."""
    rng = random.Random(seed)
    pts = []
    phase = rng.uniform(0, math.tau)
    for i in range(samples + 1):
        t = i / samples
        x = t * W
        envelope = math.sin(t * math.pi) ** 0.7
        y = (
            base_y
            - amplitude * envelope * abs(math.sin(t * math.pi * roughness + phase))
        )
        pts.append((x, y))
    return pts


def fill_below(img, pts, colour):
    draw = ImageDraw.Draw(img)
    poly = list(pts) + [(W, H), (0, H)]
    draw.polygon(poly, fill=colour)


def add_mist(img, y, height, strength):
    """A soft haze band — the thing that sells depth between ridges."""
    band = Image.new("L", (1, H), 0)
    d = ImageDraw.Draw(band)
    for i in range(int(height * 0.5)):
        t = i / max(1, height * 0.5)
        a = int(255 * strength * (1 - t) ** 2)
        yy = int(y + i)
        if 0 <= yy < H:
            d.point((0, yy), fill=a)
    band = band.filter(ImageFilter.GaussianBlur(height * 0.22))
    mask = band.resize((W, H))
    haze = Image.new("RGB", (W, H), (214, 208, 206))
    img.paste(haze, (0, 0), mask)


def build_landscape():
    img = Image.new("RGB", (W, H))
    px = img.load()
    horizon = int(H * 0.62)
    for y in range(horizon):
        c = sky_height(y)
        for x in range(W):
            px[x, y] = c

    # Sun, low and slightly off-centre so it is not a bullseye.
    sun_x, sun_y = int(W * 0.68), int(horizon * 0.72)
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for r, strength in ((330, 0.16), (200, 0.26), (110, 0.45), (52, 1.0)):
        gd.ellipse(
            [sun_x - r, sun_y - r, sun_x + r, sun_y + r],
            fill=(int(255 * strength), int(226 * strength), int(176 * strength)),
        )
    glow = glow.filter(ImageFilter.GaussianBlur(26))
    img = Image.blend(img, Image.blend(img, glow, 0.0), 0)
    img = Image.fromarray(
        __import__("numpy").clip(
            __import__("numpy").asarray(img).astype(int)
            + __import__("numpy").asarray(glow).astype(int) * 0.85,
            0, 255,
        ).astype("uint8")
    )

    # Ridges, far to near. Atmospheric perspective: distant ridges are pale and
    # low-contrast, near ridges are dark and crisp.
    layers = [
        # seed, base, amplitude, roughness, colour, mist
        (11, H * 0.60, H * 0.13, 2.1, (146, 152, 172), 0.55),
        (27, H * 0.66, H * 0.11, 1.5, (112, 120, 146), 0.45),
        (43, H * 0.73, H * 0.10, 3.0, (78, 86, 112), 0.35),
        (61, H * 0.81, H * 0.08, 1.9, (50, 58, 78), 0.22),
        (89, H * 0.90, H * 0.06, 2.6, (28, 34, 48), 0.10),
    ]
    for seed, base, amp, rough, colour, mist in layers:
        pts = ridge(seed, base, amp, rough)
        fill_below(img, pts, colour)
        add_mist(img, base - amp * 0.15, amp * 1.6, mist)

    # Gentle vignette so the clock reads well over it.
    vign = Image.new("L", (W, H), 0)
    vd = ImageDraw.Draw(vign)
    vd.ellipse([-W * 0.25, -H * 0.35, W * 1.25, H * 1.35], fill=255)
    vign = vign.filter(ImageFilter.GaussianBlur(220)).point(lambda v: 90 + v * 165 // 255)
    img = Image.composite(img, Image.new("RGB", (W, H), (10, 12, 20)), vign)

    return img


def build_launcher_icon():
    """
    The home-screen icon.

    A rounded-square tile carrying the four Assistant dots on the ambient
    gradient — readable at 48px, which is the size that actually matters on a
    home screen.
    """
    S = 1024
    tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(tile)

    # Android adaptive icons crop to a 66% safe circle; keep art inside it.
    pad = int(S * 0.17)
    box = [pad, pad, S - pad, S - pad]

    grad = Image.new("RGBA", (S, S))
    gp = grad.load()
    for y in range(S):
        t = y / S
        c = lerp((38, 70, 130), (86, 52, 118), t)
        for x in range(S):
            gp[x, y] = (*c, 255)

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=int((S - 2 * pad) * 0.235), fill=255)
    tile.paste(grad, (0, 0), mask)
    tile.putalpha(mask)

    # Assistant four-dot mark.
    c = S / 2
    r = S * 0.062
    spread = S * 0.135
    cols = [(66, 133, 244), (234, 67, 53), (251, 188, 4), (52, 168, 83)]
    order = [(-1, -1), (1, -1), (-1, 1), (1, 1)]
    d = ImageDraw.Draw(tile)
    for (dx, dy), col in zip(order, cols):
        cx, cy = c + dx * spread, c + dy * spread
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*col, 255))

    return tile


def write_icons(icon):
    res = os.path.join(os.path.dirname(__file__), "..", "android", "app", "src", "main", "res")
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in densities.items():
        path = os.path.join(res, folder)
        os.makedirs(path, exist_ok=True)
        icon.resize((size, size), Image.LANCZOS).save(os.path.join(path, "ic_launcher.png"))
    print(f"  launcher icon -> {len(densities)} densities")


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    scene = build_landscape()
    scene.save(os.path.join(OUT_DIR, "landscape.jpg"), quality=82, optimize=True,
               progressive=True)
    size = os.path.getsize(os.path.join(OUT_DIR, "landscape.jpg"))
    print(f"  landscape -> assets/photo/landscape.jpg ({W}x{H}, {size/1024:.0f} KB)")
    write_icons(build_launcher_icon())