# Haptic Linear Slider

A PCB for a motorized, haptic linear slider. An RP2354 (RP2350 with built-in flash) drives a
Bourns PSM01 motorized slide potentiometer through a DRV8876 H-bridge. The board also has a
14 V boost (TLV61048) for the motor supply, a buck converter (DIO54335), USB-C, and SWD over
Tag-Connect TC2030.

Made with **KiCad 10**.

## Layout

```
haptic-linear-slider.kicad_{pro,sch,pcb}
sym-lib-table, fp-lib-table       project library tables (paths use ${KIPRJMOD})
lib/
  _symbols/
    haptic-linear-slider.kicad_sym   project symbols, library nickname "_Symbols"
    MCU_RaspberryPi_RP2350.kicad_sym RP2350 symbol from Raspberry Pi's minimal design
  _footprints.pretty/                project footprints, library nickname "_Footprints"
  _3D/                               STEP models for project footprints
scripts/export.sh                    generates fab outputs and docs with kicad-cli
scripts/site.sh                      builds the GitHub Pages index from those outputs
.github/workflows/kicad.yml          CI: export, Pages (main), releases (v* tags)
```

Use the stock KiCad libraries for anything they already cover. Add a part to the project
libraries only when they don't have it.

## Adding a part from Mouser

1. Download the KiCad model from the Mouser product page (SamacSys / Library Loader).
2. In the Symbol Editor, copy the symbol into `_Symbols`. Rename it to
   `<short description> (<manufacturer>)`, e.g. `37V 3.5A H-Bridge (Texas Instruments)`.
3. Copy the `.kicad_mod` into `lib/_footprints.pretty/` and the `.stp` into `lib/_3D/`.
4. Set the footprint's 3D model to `${KIPRJMOD}/lib/_3D/<part>.stp`. Set the symbol's
   `Footprint` field to `_Footprints:<name>`.
5. Keep the `Manufacturer_Name`, `Manufacturer_Part_Number`, `Mouser Part Number` and
   `Mouser Price/Stock` fields. The BOM export reads them.

## Generating outputs

```sh
scripts/export.sh                 # writes everything to output/ (git-ignored)
STRICT_ERC=1 scripts/export.sh    # fail on ERC violations (STRICT_DRC=1, or STRICT=1 for both)
IBOM=path/to/generate_interactive_bom.py scripts/export.sh   # also build the interactive BOM
```

This produces:

- **checks**: ERC/DRC reports
- **fab**: Gerbers and drill files (plus a zip), a grouped BOM with part-number columns, a
  pick-and-place CSV
- **docs**: schematic PDF, PCB layers PDF, top/bottom assembly drawing PDFs, top/bottom 3D
  renders (PNG), a 3D STEP model
- **presentation**: board outline SVGs, bare and with part bodies, for slides and handbooks
- **datasheets**: a PDF per BOM part, from the `Datasheet` field. Some hosts (Mouser,
  Samsung, ST, …) block scripted downloads. Save those by hand as
  `lib/datasheets/<MPN>.pdf`; the CI run summary lists which ones are missing.

The Gerber layers come from the plot settings saved in the board file (PCB Editor → Plot).
Title blocks show `${REVISION}`: "dev" in the editor, the git tag or short SHA in exports.

## CI

- **Push to `main`**: builds everything, fails on ERC violations, and publishes the latest
  outputs to GitHub Pages. Only the newest deploy is kept. Per-commit workflow artifacts
  expire after 14 days.
- **Push a `v*` tag** (e.g. `v0.1`): also attaches all outputs to a GitHub release. Tag each
  revision you send to fab.

CI uses the `kicad/kicad:10.0-full` image (it includes the stock 3D models). DRC is report-only for now. Set `STRICT_DRC: 1` in the workflow once routing is done.
