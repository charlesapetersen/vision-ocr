#!/bin/bash
# reader-falcon.sh — the app's model reader (`Prefs.modelReader`) for Falcon-OCR, the bake-off's top reader
# (`OCR-BAKEOFF-2026-10-07.tsv`), out of the lab's venv and model cache.
#
#   reader-falcon.sh <page image> <out.txt>               writes the page's text to out.txt, exit 0
#   reader-falcon.sh <page image> <out.txt> <crops.tsv>   each crop's text on one line of out.txt (`fill`)
#
# For ocr-hybrid-proto's measurements, not for shipping: ocr-integrate-engine runs the winner inside the app.
# Point the app (or a score-gate build) at it with the `modelArrangement` and `modelReader` defaults, in
# the domain of the binary's name for a tool without a bundle, e.g.
#   defaults write vo-hp-gate modelArrangement align
#   defaults write vo-hp-gate modelReader "$PWD/ops/ocrlab/reader-falcon.sh"
set -u
[ $# -eq 2 ] || [ $# -eq 3 ] || { echo "usage: reader-falcon.sh <page image> <out.txt> [crops.tsv]" >&2; exit 2; }
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
here="$(cd "$(dirname "$0")" && pwd)"
export HF_HOME="$OCRLAB/hf" HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
# With a third argument (`fill`), each crop's text on one line of out.txt. A crop is a line or two, under
# 100 tokens; the cap stops one crop's loop from spending the app's 600 s on the page.
crops=()
[ $# -eq 3 ] && crops=(--crops "$3" --one-line-each --max-tokens 400)
# -I keeps the working directory off Python's path; read-mlx.py adds its own directory.
exec "$OCRLAB/venv/bin/python" -I "$here/read-mlx.py" tiiuae/Falcon-OCR "$1" "$2" --prompt plain \
    ${crops[@]+"${crops[@]}"} >/dev/null
