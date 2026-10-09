#!/bin/bash
# reader-regions.sh — the app's model reader (`Prefs.modelReader`) for `modelArrangement=regions`: the page cut
# into DocLayout-YOLO regions (layout-regions.py, then dedupe-regions.py, as newsbench.sh cuts NewsBench's
# pages), each region read by PaddleOCR-VL-1.6-4bit, the region reader ocr-lab-round3 named.
#
#   reader-regions.sh <page image> <out.tsv>   writes one block a line, `x0 y0 x1 y1 label text`, exit 0
#
# The app aligns each block's words onto the Vision lines inside it (`Recogniser.regionAligned`). A region
# whose reading runs to the token cap (a loop) is kept: its words that do not agree with Vision's lines
# change nothing. A reading stopped by --seconds is not, and exits 1, so the app fails the file rather than
# publish a page half read. For ocr-hybrid-proto's measurements, not for shipping, as reader-falcon.sh.
set -u
[ $# -eq 2 ] || { echo "usage: reader-regions.sh <page image> <out.tsv>" >&2; exit 2; }
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
here="$(cd "$(dirname "$0")" && pwd)"
export HF_HOME="$OCRLAB/hf" HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
py="$OCRLAB/venv/bin/python"
weights=$(ls "$OCRLAB"/hf/hub/models--wybxc--DocLayout-YOLO-DocStructBench-onnx/snapshots/*/doclayout_yolo_docstructbench_imgsz1024.onnx 2>/dev/null | head -1)
[ -n "$weights" ] || { echo "reader-regions.sh: DocLayout-YOLO's ONNX weights are not in the lab" >&2; exit 1; }
work="$(mktemp -d -t visionocr-regions)" || exit 1
trap 'rm -rf "$work"' EXIT
"$py" -I "$here/layout-regions.py" --model yolo --weights "$weights" --image "$1" --out "$work/regions.tsv" \
    > "$work/layout.log" || { echo "reader-regions.sh: layout failed" >&2; exit 1; }
"$py" -I "$here/dedupe-regions.py" "$work/regions.tsv" "$work/deduped.tsv" > /dev/null \
    || { echo "reader-regions.sh: dedupe failed" >&2; exit 1; }
# A box clipped to the page's edge can come back under 2 px wide or tall, and no crop of it can be written.
/usr/bin/awk -F'\t' 'NR == 1 || ($4 >= 2 && $5 >= 2)' "$work/deduped.tsv" > "$work/crops.tsv"
# No text region: no block, and the app keeps Vision's reading.
if [ "$(/usr/bin/awk 'END {print NR}' "$work/crops.tsv")" -lt 2 ]; then : > "$2"; exit 0; fi
# 540 s of reading, as reader-chandra.sh: the app's own bound is 600 s for the whole page.
stats="$("$py" -I "$here/read-mlx.py" mlx-community/PaddleOCR-VL-1.6-4bit "$1" "$work/read.txt" --prompt "OCR:" \
    --crops "$work/crops.tsv" --one-line-each --max-tokens 3000 --seconds 540)" || exit 1
case "$stats" in *'"cut": "seconds"'*) echo "reader-regions.sh: reading cut short: $stats" >&2; exit 1;; esac
# For measuring: VISIONOCR_READER_KEEP=<dir> keeps each page's regions and readings beside a copy of the image.
if [ -n "${VISIONOCR_READER_KEEP:-}" ]; then
    k="$VISIONOCR_READER_KEEP/$(date +%s)-$$"
    cp "$work/crops.tsv" "$k.crops.tsv"; cp "$work/read.txt" "$k.read.txt"; cp "$1" "$k.${1##*.}"
fi
# Each crop's reading is one line of read.txt, in crops.tsv's order (its header aside).
"$py" -I - "$1" "$work/crops.tsv" "$work/read.txt" "$2" <<'EOF'
import sys
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
image, crops, read, out = sys.argv[1:5]
w, h = Image.open(image).size
rows = open(crops).read().splitlines()[1:]
texts = open(read).read().split("\n")
if texts and texts[-1] == "":
    texts.pop()
if len(texts) != len(rows):
    sys.exit(f"reader-regions.sh: {len(rows)} regions but {len(texts)} readings")
with open(out, "w") as f:
    for row, text in zip(rows, texts):
        _, x, y, cw, ch = row.split("\t")[:5]
        x, y, cw, ch = int(x), int(y), int(cw), int(ch)
        text = " ".join(text.replace("\t", " ").split())
        f.write(f"{x / w:.5f}\t{y / h:.5f}\t{(x + cw) / w:.5f}\t{(y + ch) / h:.5f}\tregion\t{text}\n")
EOF
