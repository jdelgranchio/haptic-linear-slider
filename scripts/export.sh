#!/usr/bin/env bash
# Generate fabrication and documentation outputs with kicad-cli.
# Usage: scripts/export.sh [output-dir]
#   STRICT_ERC=1 / STRICT_DRC=1   fail on ERC / DRC violations (STRICT=1 sets both)
#   REVISION=...                  title-block revision (default: git describe)
#   IBOM=path/to/generate_interactive_bom.py   also build the interactive HTML BOM
#   DATASHEETS=0                  skip collecting datasheet PDFs
set -euo pipefail

cd "$(dirname "$0")/.."
NAME=haptic-linear-slider
SCH="$NAME.kicad_sch"
PCB="$NAME.kicad_pcb"
OUT="${1:-output}"

if [[ -z "${KICAD_CLI:-}" ]]; then
  if command -v kicad-cli >/dev/null; then KICAD_CLI=kicad-cli
  else KICAD_CLI="/Applications/KiCad 10/KiCad.app/Contents/MacOS/kicad-cli"; fi
fi
kc() { "$KICAD_CLI" "$@"; }

REVISION="${REVISION:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
DEF=(-D "REVISION=$REVISION")

ERC_FLAG="" DRC_FLAG=""
[[ "${STRICT_ERC:-${STRICT:-0}}" == 1 ]] && ERC_FLAG="--exit-code-violations"
[[ "${STRICT_DRC:-${STRICT:-0}}" == 1 ]] && DRC_FLAG="--exit-code-violations"

rm -rf "$OUT"
mkdir -p "$OUT"/{gerbers,assembly,docs,reports}
echo "Revision: $REVISION"

echo "==> ERC / DRC"
kc sch erc $ERC_FLAG --severity-all -o "$OUT/reports/erc.rpt" "$SCH"
kc pcb drc $DRC_FLAG --schematic-parity --severity-all -o "$OUT/reports/drc.rpt" "$PCB"

echo "==> Gerbers + drill"
kc pcb export gerbers --board-plot-params -o "$OUT/gerbers/" "$PCB"
kc pcb export drill --format excellon --excellon-separate-th \
  --generate-map --map-format gerberx2 -o "$OUT/gerbers/" "$PCB"
if command -v zip >/dev/null; then (cd "$OUT/gerbers" && zip -q "../$NAME-gerbers.zip" ./*)
else (cd "$OUT/gerbers" && python3 -m zipfile -c "../$NAME-gerbers.zip" ./*); fi

echo "==> Assembly (BOM + pick-and-place)"
kc sch export bom -o "$OUT/assembly/$NAME-bom.csv" \
  --fields 'Reference,Value,Footprint,${QUANTITY},Manufacturer_Name,Manufacturer_Part_Number,Mouser Part Number,${DNP},Datasheet' \
  --labels 'Refs,Value,Footprint,Qty,Manufacturer,MPN,Mouser PN,DNP,Datasheet' \
  --group-by 'Value,Footprint,Manufacturer_Part_Number,${DNP}' \
  --ref-range-delimiter '' \
  "$SCH"
kc pcb export pos --format csv --units mm --side both --exclude-dnp \
  -o "$OUT/assembly/$NAME-pos.csv" "$PCB"

echo "==> Docs (PDFs, outlines, renders, 3D STEP)"
kc sch export pdf "${DEF[@]}" -o "$OUT/docs/$NAME-schematic.pdf" "$SCH"
kc pcb export pdf "${DEF[@]}" --mode-multipage --include-border-title \
  --layers F.Cu,B.Cu,F.Silkscreen,B.Silkscreen,F.Mask,B.Mask --common-layers Edge.Cuts \
  -o "$OUT/docs/$NAME-pcb.pdf" "$PCB"
kc pcb export pdf "${DEF[@]}" --mode-single --include-border-title \
  --sketch-pads-on-fab-layers --crossout-DNP-footprints-on-fab-layers \
  --layers F.Fab,Edge.Cuts -o "$OUT/docs/$NAME-assembly-top.pdf" "$PCB"
kc pcb export pdf "${DEF[@]}" --mode-single --include-border-title --mirror \
  --sketch-pads-on-fab-layers --crossout-DNP-footprints-on-fab-layers \
  --layers B.Fab,Edge.Cuts -o "$OUT/docs/$NAME-assembly-bottom.pdf" "$PCB"
# Clean vector outlines for slides / handbooks (bare board, and with part bodies)
kc pcb export svg --mode-single --exclude-drawing-sheet --fit-page-to-board \
  --black-and-white --drill-shape-opt 0 --layers Edge.Cuts \
  -o "$OUT/docs/$NAME-outline.svg" "$PCB"
kc pcb export svg --mode-single --exclude-drawing-sheet --fit-page-to-board \
  --black-and-white --drill-shape-opt 0 --layers Edge.Cuts,F.Fab \
  -o "$OUT/docs/$NAME-outline-parts.svg" "$PCB"
for side in top bottom; do
  # Renders are nice-to-have: don't fail the fab outputs if the host can't render
  kc pcb render --side "$side" --quality high --zoom 1.5 \
    -o "$OUT/docs/$NAME-$side.png" "$PCB" || echo "::warning::3D render ($side) failed"
done
kc pcb export step --subst-models --force -o "$OUT/docs/$NAME.step" "$PCB"

if [[ -n "${IBOM:-}" ]]; then
  echo "==> Interactive HTML BOM"
  IBOM_PYTHON="${IBOM_PYTHON:-python3}"
  INTERACTIVE_HTML_BOM_NO_DISPLAY=1 "$IBOM_PYTHON" "$IBOM" --no-browser \
    --dest-dir "$(cd "$OUT/assembly" && pwd)" --name-format "$NAME-ibom" \
    --extra-fields "Manufacturer_Part_Number,Mouser Part Number" "$PCB"
fi

if [[ "${DATASHEETS:-1}" == 1 ]]; then
  echo "==> Datasheets"
  python3 scripts/datasheets.py "$OUT/assembly/$NAME-bom.csv" "$OUT/datasheets"
fi

echo "Done -> $OUT/"
