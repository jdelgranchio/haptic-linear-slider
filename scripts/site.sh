#!/usr/bin/env bash
# Build the GitHub Pages site (latest outputs from main) from an export.sh output dir.
# Usage: scripts/site.sh [output-dir] [site-dir]
set -euo pipefail

cd "$(dirname "$0")/.."
NAME=haptic-linear-slider
OUT="${1:-output}"
SITE="${2:-site}"
REVISION="${REVISION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"

rm -rf "$SITE"
mkdir -p "$SITE"
shopt -s nullglob
cp "$OUT"/docs/*.{pdf,png,svg} "$OUT"/assembly/* "$OUT"/reports/* "$OUT"/*.zip "$SITE"/

if [[ -d "$OUT/datasheets" ]]; then cp -r "$OUT/datasheets" "$SITE/"; fi

# One list item per datasheet: local PDF if collected, else the original URL
datasheets() {
  [[ -f "$OUT/datasheets/index.csv" ]] || return 0
  python3 - "$OUT/datasheets/index.csv" <<'PY'
import csv, html, re, sys
for r in csv.DictReader(open(sys.argv[1])):
    mpn, refs = html.escape(r["MPN"]), html.escape(r["Refs"])
    name = re.sub(r"[^A-Za-z0-9._()-]+", "_", r["MPN"]).strip("_") + ".pdf"
    if r["Source"] == "missing":
        print(f'<li>{mpn} <small>({refs})</small> — <a href="{html.escape(r["URL"])}">original link</a> <small>(not cached)</small></li>')
    else:
        print(f'<li><a href="datasheets/{name}">{mpn}</a> <small>({refs})</small></li>')
PY
}

link() { [[ -e "$SITE/$1" ]] && echo "<li><a href=\"$1\">$2</a></li>" || true; }
count() { grep -oE "$2" "$OUT/reports/$1" | head -1 || echo "?"; }

cat > "$SITE/index.html" <<HTML
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Haptic Linear Slider</title>
<style>
  :root { color-scheme: light dark; --fg:#1b1b1f; --bg:#fafafa; --mute:#666; --card:#fff; --line:#ddd; }
  @media (prefers-color-scheme: dark) { :root { --fg:#eee; --bg:#121214; --mute:#999; --card:#1c1c20; --line:#333; } }
  body { font: 16px/1.5 system-ui, sans-serif; color:var(--fg); background:var(--bg); max-width:960px; margin:0 auto; padding:24px 16px; }
  h1 { margin:0 } .meta { color:var(--mute); margin:4px 0 24px }
  .renders { display:grid; grid-template-columns:repeat(auto-fit,minmax(280px,1fr)); gap:12px }
  .renders img { width:100%; background:var(--card); border:1px solid var(--line); border-radius:8px }
  section { margin-top:28px } ul { padding-left:20px } a { color:inherit }
  code { font-size:.9em }
</style></head><body>
<h1>Haptic Linear Slider</h1>
<p class="meta">Revision <code>$REVISION</code> · built $(date -u +'%Y-%m-%d %H:%M UTC') · latest <code>main</code>.
Tagged releases live on <a href="https://github.com/${GITHUB_REPOSITORY:-jdelgranchio/haptic-linear-slider}/releases">GitHub Releases</a>.</p>
<div class="renders">
  <img src="$NAME-top.png" alt="3D render, top side">
  <img src="$NAME-bottom.png" alt="3D render, bottom side">
</div>
<section><h2>Documents</h2><ul>
$(link "$NAME-schematic.pdf" "Schematic (PDF)")
$(link "$NAME-pcb.pdf" "PCB layers (PDF)")
$(link "$NAME-assembly-top.pdf" "Assembly drawing, top (PDF)")
$(link "$NAME-assembly-bottom.pdf" "Assembly drawing, bottom (PDF)")
$(link "$NAME-ibom.html" "Interactive BOM")
</ul></section>
<section><h2>Presentation</h2><ul>
$(link "$NAME-outline.svg" "Board outline (SVG)")
$(link "$NAME-outline-parts.svg" "Board outline with parts (SVG)")
$(link "$NAME-top.png" "Render, top (PNG)")
$(link "$NAME-bottom.png" "Render, bottom (PNG)")
</ul></section>
<section><h2>Fabrication</h2><ul>
$(link "$NAME-gerbers.zip" "Gerbers + drill (zip)")
$(link "$NAME-bom.csv" "BOM (CSV)")
$(link "$NAME-pos.csv" "Pick-and-place (CSV)")
</ul></section>
<section><h2>Datasheets</h2><ul>
$(datasheets)
</ul></section>
<section><h2>Checks</h2><ul>
$(link erc.rpt "ERC report") <li>$(count erc.rpt 'ERC messages: [0-9]+')</li>
$(link drc.rpt "DRC report") <li>$(count drc.rpt 'Found [0-9]+ DRC violations'), $(count drc.rpt 'Found [0-9]+ unconnected pads')</li>
</ul></section>
</body></html>
HTML
echo "Site -> $SITE/"
