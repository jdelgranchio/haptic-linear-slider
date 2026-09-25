#!/usr/bin/env bash
# Generate fabrication and documentation outputs with kicad-cli.
# Usage: scripts/export.sh [output-dir]      (STRICT=1 to fail on ERC/DRC violations)
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

EXIT_FLAG=""
[[ "${STRICT:-0}" == 1 ]] && EXIT_FLAG="--exit-code-violations"

rm -rf "$OUT"
mkdir -p "$OUT"/{gerbers,assembly,docs,reports}

echo "==> ERC / DRC"
kc sch erc $EXIT_FLAG --severity-all -o "$OUT/reports/erc.rpt" "$SCH"
kc pcb drc $EXIT_FLAG --schematic-parity --severity-all -o "$OUT/reports/drc.rpt" "$PCB"

echo "==> Gerbers + drill"
kc pcb export gerbers --board-plot-params -o "$OUT/gerbers/" "$PCB"
kc pcb export drill --format excellon --excellon-separate-th \
  --generate-map --map-format gerberx2 -o "$OUT/gerbers/" "$PCB"
(cd "$OUT/gerbers" && zip -q "../$NAME-gerbers.zip" ./*)

echo "==> Assembly (BOM + pick-and-place)"
kc sch export bom -o "$OUT/assembly/$NAME-bom.csv" \
  --fields 'Reference,Value,Footprint,${QUANTITY},Manufacturer_Name,Manufacturer_Part_Number,Mouser Part Number,${DNP}' \
  --labels 'Refs,Value,Footprint,Qty,Manufacturer,MPN,Mouser PN,DNP' \
  --group-by 'Value,Footprint,Manufacturer_Part_Number,${DNP}' \
  --ref-range-delimiter '' \
  "$SCH"
kc pcb export pos --format csv --units mm --side both --exclude-dnp \
  -o "$OUT/assembly/$NAME-pos.csv" "$PCB"

echo "==> Docs (schematic PDF, 3D STEP)"
kc sch export pdf -o "$OUT/docs/$NAME-schematic.pdf" "$SCH"
kc pcb export step --subst-models --force -o "$OUT/docs/$NAME.step" "$PCB"

echo "Done -> $OUT/"
