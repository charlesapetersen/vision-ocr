#!/bin/bash
# reader-chandra.sh — the app's model reader (`Prefs.modelReader`) for `modelArrangement=replace`: Chandra OCR 2
# (oQ8, the bake-off's third reader and the only one of its top three that writes boxes), asked for layout
# blocks with chandra-layout-prompt.txt, its answer turned into the app's blocks by chandra_blocks.py.
#
#   reader-chandra.sh <page image> <out.tsv>   writes one block a line, `x0 y0 x1 y1 label text`, exit 0
#
# Falcon-OCR writes no boxes, and LightOnOCR-2's box build boxes only pictures. Chandra's boxes are blocks
# (a paragraph, a heading, a footnote), not lines; the app finds the lines in each block's ink.
# For ocr-hybrid-proto's measurements, not for shipping, as reader-falcon.sh. A reading cut short (by
# --seconds or --max-tokens) exits 1, so the app fails the file rather than publish part of a page.
set -u
[ $# -eq 2 ] || { echo "usage: reader-chandra.sh <page image> <out.tsv>" >&2; exit 2; }
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
here="$(cd "$(dirname "$0")" && pwd)"
export HF_HOME="$OCRLAB/hf" HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
answer="$(mktemp -t visionocr-chandra)" || exit 1
trap 'rm -f "$answer"' EXIT
prompt="$here/chandra-layout-prompt.txt"
[ -s "$prompt" ] || { echo "reader-chandra.sh: no prompt at $prompt" >&2; exit 1; }
# 540 s of reading, counted after the model loads: a slow page usually ends here, said, though load
# and reading together can pass the app's 600 s, and then the app's kill fails the page instead.
stats="$("$OCRLAB/venv/bin/python" -I "$here/read-mlx.py" mlx-community/chandra-ocr-2-oQ8 "$1" "$answer" \
    --prompt "$(cat "$prompt")" --max-tokens 8000 --seconds 540)" || exit 1
case "$stats" in *'"cut": "-"'*) ;; *) echo "reader-chandra.sh: reading cut short: $stats" >&2; exit 1;; esac
# For measuring: VISIONOCR_READER_KEEP=<dir> keeps each page's answer beside a copy of the image it read.
if [ -n "${VISIONOCR_READER_KEEP:-}" ]; then
    k="$VISIONOCR_READER_KEEP/$(date +%s)-$$"; cp "$answer" "$k.html"; cp "$1" "$k.${1##*.}"
fi
# Not exec: the EXIT trap removes the answer only if this shell is still here to run it.
"$OCRLAB/venv/bin/python" -I "$here/chandra_blocks.py" "$answer" "$2"
