#!/usr/bin/env python3
"""
Exercise the rotation pool against the live Wikimedia Commons API.

The pool in `lib/src/services/photo_frame_service.dart` is a hardcoded list of
Commons filenames. That is only safe if every entry actually resolves and is
still licence-clean, because a stale entry means the rotation silently skips a
photo every cycle — or, worse, installs something under a licence we would not
accept.

This checks, for every entry:
  * the file still exists on Commons
  * the licence is still one of public domain / CC0 / CC-BY
  * a 1600px thumbnail is actually offered

    python3 tool/verify_photo_pool.py

Exits non-zero if any entry fails, so it can be run in CI.
"""
import json
import os
import re
import subprocess
import sys
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SERVICE = os.path.join(ROOT, "lib", "src", "services", "photo_frame_service.dart")

FORBIDDEN = ("-nc", "-nd", "-sa", "sharealike", "share alike", "share-alike",
             "fair use", "non-free")
ALLOWED_PREFIXES = ("public domain", "cc0", "cc by")


def pool_titles():
    src = open(SERVICE, encoding="utf-8").read()
    block = src[src.index("static const List<PhotoSource> pool = ["):]
    block = block[:block.index("\n  ];")]
    return re.findall(r"PhotoSource\(\s*\n?\s*'((?:[^'\\]|\\.)*)'", block)


def api(title):
    q = urllib.parse.urlencode({
        "action": "query",
        "titles": "File:" + title,
        "prop": "imageinfo",
        "iiprop": "url|extmetadata|size",
        "iiurlwidth": "1600",
        "format": "json",
    })
    url = "https://commons.wikimedia.org/w/api.php?" + q
    for _ in range(3):
        out = subprocess.run(
            ["curl", "-sSL", "--max-time", "90", "-H",
             "User-Agent: SNLauncher/0.2 (pool verifier)", url],
            capture_output=True, text=True).stdout
        try:
            return json.loads(out)
        except Exception:
            pass
    return None


def main():
    titles = pool_titles()
    print(f"checking {len(titles)} pool entries against Commons\n")
    failures = []
    for t in titles:
        t = t.replace("\\'", "'")
        d = api(t)
        if d is None:
            print(f"  ERROR    (no response)  {t[:52]}")
            failures.append(t)
            continue
        pages = ((d.get("query") or {}).get("pages")) or {}
        page = next(iter(pages.values()), None)
        if page is None or "missing" in page:
            print(f"  MISSING                {t[:52]}")
            failures.append(t)
            continue
        info = ((page.get("imageinfo") or [{}])[0])
        em = info.get("extmetadata") or {}
        lic = ((em.get("LicenseShortName") or {}).get("value") or "")
        low = lic.lower().strip()
        if not low or any(b in low for b in FORBIDDEN) or \
                not low.startswith(ALLOWED_PREFIXES):
            print(f"  BAD LICENCE {lic[:18]:<19} {t[:40]}")
            failures.append(t)
            continue
        if not info.get("thumburl"):
            print(f"  NO THUMB               {t[:52]}")
            failures.append(t)
            continue
        print(f"  ok  {lic[:18]:<20} {t[:48]}")

    print()
    if failures:
        print(f"FAIL: {len(failures)} of {len(titles)} unusable")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"PASS: all {len(titles)} entries resolve and are licence-clean")
    return 0


if __name__ == "__main__":
    sys.exit(main())