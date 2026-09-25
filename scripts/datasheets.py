#!/usr/bin/env python3
"""Collect datasheet PDFs for every part in the BOM.

Usage: scripts/datasheets.py <bom.csv> <dest-dir>

For each unique MPN with a Datasheet URL, in order of preference:
  1. lib/datasheets/<MPN>.pdf committed in the repo (for hosts that block scripts)
  2. a cached download in $DATASHEET_CACHE (default .cache/datasheets), refetched if the URL changed
  3. a fresh download, kept only if the response really is a PDF
Writes <dest-dir>/<MPN>.pdf and <dest-dir>/index.csv (mpn, refs, source, url).
"""
import csv
import os
import re
import shutil
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCAL = ROOT / "lib" / "datasheets"
CACHE = Path(os.environ.get("DATASHEET_CACHE", ROOT / ".cache" / "datasheets"))
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"


def safe(name):
    return re.sub(r"[^A-Za-z0-9._()-]+", "_", name).strip("_")


def download(url, dest):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/pdf,*/*"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = r.read()
    except Exception as e:
        return f"error: {e}"
    if not data.startswith(b"%PDF"):
        return "not a PDF (host probably needs a browser)"
    dest.write_bytes(data)
    return None


def main(bom_csv, dest_dir):
    dest = Path(dest_dir)
    dest.mkdir(parents=True, exist_ok=True)
    CACHE.mkdir(parents=True, exist_ok=True)

    parts = {}  # mpn -> (url, [refs])
    with open(bom_csv, newline="") as f:
        for row in csv.DictReader(f):
            mpn, url = row.get("MPN", "").strip(), row.get("Datasheet", "").strip()
            if not mpn or not url.startswith("http"):
                continue
            parts.setdefault(mpn, (url, []))[1].append(row.get("Refs", ""))

    rows, missing = [], 0
    for mpn, (url, refs) in sorted(parts.items()):
        name = safe(mpn) + ".pdf"
        local, cached, stamp = LOCAL / name, CACHE / name, CACHE / (name + ".url")
        if local.exists():
            shutil.copy(local, dest / name)
            source = "repo"
        elif cached.exists() and stamp.exists() and stamp.read_text() == url:
            shutil.copy(cached, dest / name)
            source = "cache"
        else:
            err = download(url, cached)
            if err is None:
                stamp.write_text(url)
                shutil.copy(cached, dest / name)
                source = "downloaded"
            else:
                source = "missing"
                missing += 1
                print(f"::warning::datasheet {mpn}: {err} -> add lib/datasheets/{name}")
        rows.append((mpn, ",".join(refs), source, url))
        print(f"{source:10} {mpn}")

    with open(dest / "index.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["MPN", "Refs", "Source", "URL"])
        w.writerows(rows)
    print(f"{len(rows) - missing}/{len(rows)} datasheets collected")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
