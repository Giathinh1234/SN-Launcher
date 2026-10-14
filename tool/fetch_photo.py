#!/usr/bin/env python3
"""Fetch the bundled photo-frame background from Wikimedia Commons.

Why a real photograph and not the procedural one it replaced: the generated
version was fine as art and wrong as *Google's*. Nest Hub's ambient images are
recognisably real photographs of calm places, and a synthetic ridge line reads
as "demo" no matter how good the gradient is.

Why Wikimedia Commons and not a stock site: every file there has a
machine-readable licence and a named author. That matters twice over — the
licence has to be checked, not assumed (this script refuses to write if the
file's live licence is not something we may redistribute), and CC/PD terms want
the author credited, which is why the author's name is rendered on screen next
to the album title.

    python3 tool/fetch_photo.py            # verify, download, write all outputs
    python3 tool/fetch_photo.py --check    # verify licence + decode only

Writes (idempotently — re-running regenerates them; only the fetch date in
ATTRIBUTION.md changes):
    assets/photo/landscape.jpg      the JPEG background (<= 1600px wide, q82)
    assets/photo/landscape.json     licence + author metadata (read by Flutter)
    assets/photo/ATTRIBUTION.md     human-readable record incl. fetch date

Dependencies: Python standard library + Pillow only. No `pip install`, and no
`curl` shell-out. TLS trust is taken from the host's own certificate store (see
`http_get`), so it runs on a stock python.org / system Python without `certifi`.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import html
import json
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request
from io import BytesIO
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT_DIR = ROOT / "assets" / "photo"

# --- The exact Commons file we ship ---------------------------------------
# "Cub Lake at dawn in Rocky Mountain National Park", by Debra Miller for the
# US National Park Service. Chosen from ~30 candidates for three reasons: the
# still lake fills the lower third with dark, even tone, which is exactly where
# the white clock sits; the golden larches give the top half its colour without
# competing; and it holds up cropped to both 1.60 (Hub Max) and 1.71 (Hub).
#
# Public domain because it is a work of the US federal government — which also
# means no attribution is legally required. It is credited on screen anyway,
# because the photographer took the picture and saying so is simply correct.
#
# The `titles=` API parameter needs the namespace-qualified, exact filename.
COMMONS_FILENAME = (
    "Cub Lake at dawn in Rocky Mountain National Park. "
    "NPS-Debra Miller (18680833532).jpg"
)
COMMONS_TITLE = "File:" + COMMONS_FILENAME

# The licence we expect and require for this file.
EXPECTED_LICENSE = "Public domain"

# A clean, human title for the JSON / attribution / on-screen caption (distinct
# from the very long Commons filename above).
DISPLAY_TITLE = "Cub Lake at Dawn"

# Commons' `Artist` field for this file reads "NPS Natural Resources", which is
# the owning agency rather than the person who pressed the shutter. The
# photographer is named in the file's own title, and crediting an agency instead
# of a human is the sort of thing that quietly erases whoever did the work.
# Prefer the real name, fall back to whatever Commons says in `strip_html(Artist)`.
PREFERRED_AUTHOR = "Debra Miller"

# Licences we are willing to ship. Everything else is refused, including the
# share-alike / no-derivatives / non-commercial variants, which impose
# obligations a bundled launcher background cannot meet.
ACCEPT_EXACT = {"public domain", "cc0", "cc0 1.0"}
# Substrings that make a licence UNACCEPTABLE even if it contains "by"/"public".
FORBIDDEN = ("nc", "nd", "-sa", "fair use", "non-free", "noncommercial")
# Substrings that make a licence acceptable (after FORBIDDEN has vetoed).
ACCEPT_SUBSTR = ("public domain", "cc0", "cc by ", "cc-by ", "cc-zero")

# A rock-solid reference for *why* a federal work is in the public domain, used
# for `licenseUrl` because the API's LicenseUrl is empty for PD works.
PUBLIC_DOMAIN_URL = "https://www.usa.gov/government-works"

# Width we ask Commons to thumbnail for (>= MAX_WIDTH so we always downscale,
# never upscale). The Commons thumbnailer serves the nearest available bucket.
FETCH_WIDTH = 2400
MAX_WIDTH = 1600     # matches the panel this targets; bigger is wasted bitmap
# 82 per brief. On a photo dimmed by a scrim the difference from the 78 the code
# once used is invisible, and the asset ships in every APK — but we honour the
# requested ~82 and keep it lossless-looking at 1600px.
JPEG_QUALITY = 82

COMMONS_API = "https://commons.wikimedia.org/w/api.php"
USER_AGENT = "NestLaunchPhotoFetcher/1.0 (educational launcher; attribution recorded)"

# Common system certificate bundles so a stock interpreter can verify Wikimedia
# without `certifi`. macOS ships /etc/ssl/cert.pem; Linux distros use the others.
_CA_CANDIDATES = (
    "/etc/ssl/cert.pem",                    # macOS + some Linux
    "/etc/pki/tls/certs/ca-bundle.crt",     # Fedora / RHEL
    "/etc/ssl/certs/ca-certificates.crt",   # Debian / Ubuntu / Arch
)


# --------------------------------------------------------------------------- #
# Networking (stdlib only, robust TLS)
# --------------------------------------------------------------------------- #
def http_get(url: str, timeout: int = 90, allow_insecure_fallback: bool = True) -> bytes:
    """GET a URL over HTTPS using only the standard library.

    Tries the host CA bundle(s), then the interpreter's default context, and
    only as an absolute last resort an unverified context (announced on stderr
    so it is never silent).
    """
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    contexts = [ssl.create_default_context(cafile=ca)
                for ca in _CA_CANDIDATES if Path(ca).exists()]
    contexts.append(ssl.create_default_context())  # interpreter/system default

    last_err = None
    for ctx in contexts:
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
                return resp.read()
        except urllib.error.URLError as err:
            last_err = err
            continue

    if allow_insecure_fallback:
        print("  ! every verified TLS context failed; retrying with an unverified "
              "context (host CA bundle missing?).", file=sys.stderr)
        ctx = ssl._create_unverified_context()
        with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
            return resp.read()
    raise SystemExit(f"HTTP GET failed for {url!r}: {last_err!r}")


# --------------------------------------------------------------------------- #
# Commons API + licence policy
# --------------------------------------------------------------------------- #
def strip_html(s) -> str:
    return re.sub(r"<[^>]+>", "", str(s or "")).strip()


def commons_api(**params) -> dict:
    params = dict(params)
    params["format"] = "json"
    url = COMMONS_API + "?" + urllib.parse.urlencode(params)
    return json.loads(http_get(url).decode("utf-8"))


def is_allowed_license(name: str) -> bool:
    """True only for public-domain / CC0 / plain CC-BY (any version)."""
    n = html.unescape(strip_html(name)).lower().strip()
    if not n:
        return False  # fail closed: unknown licence -> not allowed
    if any(bad in n for bad in FORBIDDEN):
        return False
    return n in ACCEPT_EXACT or any(tok in n for tok in ACCEPT_SUBSTR)


def fetch_metadata() -> dict:
    data = commons_api(action="query", titles=COMMONS_TITLE, prop="imageinfo",
                       iiprop="url|extmetadata|size", iiurlwidth=FETCH_WIDTH)
    pages = (data.get("query") or {}).get("pages") or {}
    for page in pages.values():
        if "missing" in page:
            sys.exit(f"Commons file not found: {COMMONS_TITLE}")
        info = (page.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata") or {}

        # Author: prefer the real photographer; fall back to the API `Artist`.
        author = PREFERRED_AUTHOR or strip_html((meta.get("Artist") or {}).get("value"))
        if not author:
            sys.exit("could not determine an author for this file; refusing to write.")

        # Licence: fail closed if we cannot read one.
        license_name = strip_html(
            (meta.get("LicenseShortName") or {}).get("value")
            or (meta.get("UsageTerms") or {}).get("value")
        )
        if not license_name:
            sys.exit("Commons returned no licence for this file; refusing to write.")

        license_url = strip_html((meta.get("LicenseUrl") or {}).get("value")) \
            or (PUBLIC_DOMAIN_URL if license_name.lower() == EXPECTED_LICENSE.lower() else "")

        return {
            "title": DISPLAY_TITLE,
            "commonsFilename": COMMONS_FILENAME,
            "author": author,
            "license": license_name,
            "licenseUrl": license_url,
            "sourceUrl": info.get("descriptionurl", ""),
            "url": info.get("thumburl") or info.get("url", ""),
            "width": info.get("width"),
            "height": info.get("height"),
        }
    sys.exit("no imageinfo in the Commons response")


def check_licence(license_name: str) -> None:
    if not is_allowed_license(license_name):
        sys.exit(f"licence {license_name!r} is not in the allowed set "
                 "(public domain / CC0 / plain CC-BY only); refusing to write.")


# --------------------------------------------------------------------------- #
# Image processing
# --------------------------------------------------------------------------- #
def build_image(raw: bytes) -> Image.Image:
    im = Image.open(BytesIO(raw)).convert("RGB")
    if im.width > MAX_WIDTH:
        h = round(im.height * MAX_WIDTH / im.width)
        im = im.resize((MAX_WIDTH, h), Image.LANCZOS)
    return im


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Fetch the ambient background photo.")
    ap.add_argument("--check", action="store_true",
                    help="verify licence + decode only; write nothing")
    args = ap.parse_args(argv)

    meta = fetch_metadata()
    check_licence(meta["license"])
    print(f"  {meta['title']}  ({meta['commonsFilename']})")
    print(f"  by {meta['author']} — {meta['license']}")

    raw = http_get(meta["url"])
    if len(raw) < 10_000:
        sys.exit("download failed or produced a suspiciously small file")
    im = build_image(raw)

    if args.check:
        print(f"  --check: licence verified ({meta['license']}), decoded {im.size}. "
              "Nothing written.")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    dest = OUT_DIR / "landscape.jpg"
    im.save(dest, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)
    meta["width"], meta["height"] = im.size

    with open(OUT_DIR / "landscape.json", "w") as f:
        json.dump({
            "title": meta["title"],
            "author": meta["author"],
            "license": meta["license"],
            "licenseUrl": meta["licenseUrl"],
            "sourceUrl": meta["sourceUrl"],
            "width": meta["width"],
            "height": meta["height"],
        }, f, indent=2)
        f.write("\n")

    today = _dt.date.today().isoformat()
    with open(OUT_DIR / "ATTRIBUTION.md", "w") as f:
        f.write(
            f"# Background photograph\n\n"
            f"| Field | Value |\n| --- | --- |\n"
            f"| Title | {meta['title']} |\n"
            f"| Author (photographer) | {meta['author']} |\n"
            f"| Licence | {meta['license']} |\n"
            f"| Licence URL | {meta['licenseUrl']} |\n"
            f"| Source (Commons) | {meta['sourceUrl']} |\n"
            f"| Rendered size | {meta['width']} × {meta['height']} px |\n\n"
            f"*Fetched {today} from Wikimedia Commons via `tool/fetch_photo.py` "
            f"(re-run to reproduce).*\n\n"
            f"The author's name is rendered on screen next to the album title in\n"
            f"`lib/src/widgets/clock_block.dart`, fed by `landscape.json`.\n\n"
            f"Public domain as a work of the US National Park Service. Credited\n"
            f"anyway, because the photographer took the picture.\n"
        )

    print(f"  -> assets/photo/landscape.jpg ({im.width}x{im.height}, "
          f"{dest.stat().st_size / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
