#!/bin/bash
# reader-regions.sh — the app's model reader (`Prefs.modelReader`) for `modelArrangement=regions`: the page cut
# into layout regions (layout-regions.py, then dedupe-regions.py, as newsbench.sh cuts NewsBench's
# pages), each region read by PaddleOCR-VL-1.6-4bit, the region reader ocr-lab-round3 named.
#
#   reader-regions.sh <page image> <out.tsv>   writes one block a line, `x0 y0 x1 y1 label text`, exit 0
#
# The app aligns each block's words onto the Vision lines inside it (`Recogniser.regionAligned`). A region
# whose reading runs to the token cap (a loop) is kept: its words that do not agree with Vision's lines
# change nothing. A reading stopped by --seconds is not, and exits 1, so the app fails the file rather than
# publish a page half read. For ocr-hybrid-proto's measurements, not for shipping, as reader-falcon.sh.
#
# VISIONOCR_LAYOUT names the detector (layout-compare, 2026-10-16): `yolo` (default) is DocLayout-YOLO DocStructBench,
# the one the app ships; `pp` PP-DocLayoutV3 in MLX at conf 0.3, the setting OCR-LAYOUT-2026-10-07 chose; `heron`
# docling-layout-heron under torch in the lab's venv-surya. VISIONOCR_LAYOUT_CONF overrides the detector's confidence.
# Every detector's boxes go through dedupe-regions.py and the size filter below alike, so only the boxes differ.
set -u
[ $# -eq 2 ] || { echo "usage: reader-regions.sh <page image> <out.tsv>" >&2; exit 2; }
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
here="$(cd "$(dirname "$0")" && pwd)"
export HF_HOME="$OCRLAB/hf" HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
py="$OCRLAB/venv/bin/python"
layout="${VISIONOCR_LAYOUT:-yolo}" lpy="$py" lconf="${VISIONOCR_LAYOUT_CONF:-}"
case "$layout" in
yolo)
    weights=$(ls "$OCRLAB"/hf/hub/models--wybxc--DocLayout-YOLO-DocStructBench-onnx/snapshots/*/doclayout_yolo_docstructbench_imgsz1024.onnx 2>/dev/null | head -1)
    : "${lconf:=0.25}" ;;
pp)
    weights="$OCRLAB/layout/pp-doclayout-v3-mlx"
    : "${lconf:=0.3}" ;;
heron)
    weights=$(ls -d "$OCRLAB"/hf/hub/models--ds4sd--docling-layout-heron/snapshots/* 2>/dev/null | head -1)
    lpy="$OCRLAB/venv-surya/bin/python"
    : "${lconf:=0.3}" ;;
*)  echo "reader-regions.sh: VISIONOCR_LAYOUT is '$layout', not yolo, pp or heron" >&2; exit 2 ;;
esac
[ -n "$weights" ] && [ -e "$weights" ] || { echo "reader-regions.sh: $layout's weights are not in the lab" >&2; exit 1; }
work="$(mktemp -d -t visionocr-regions)" || exit 1
trap 'rm -rf "$work"' EXIT
"$lpy" -I "$here/layout-regions.py" --model "$layout" --weights "$weights" --conf "$lconf" --image "$1" --out "$work/regions.tsv" \
    > "$work/layout.log" || { echo "reader-regions.sh: layout failed" >&2; exit 1; }
"$py" -I "$here/dedupe-regions.py" "$work/regions.tsv" "$work/deduped.tsv" > /dev/null \
    || { echo "reader-regions.sh: dedupe failed" >&2; exit 1; }
# A box clipped to the page's edge can come back under 2 px wide or tall, and no crop of it can be written.
/usr/bin/awk -F'\t' 'NR == 1 || ($4 >= 2 && $5 >= 2)' "$work/deduped.tsv" > "$work/crops.tsv"
# For measuring: VISIONOCR_READER_KEEP=<dir> keeps each page's regions, readings and the layout's log beside a
# copy of the image. Kept before the reading, so a page the reader fails still shows its regions.
keep=""
if [ -n "${VISIONOCR_READER_KEEP:-}" ]; then
    mkdir -p "$VISIONOCR_READER_KEEP"
    keep="$VISIONOCR_READER_KEEP/$(date +%s)-$$"
    cp "$work/regions.tsv" "$keep.regions.tsv"; cp "$work/crops.tsv" "$keep.crops.tsv"; cp "$work/layout.log" "$keep.layout.log"
    cp "$1" "$keep.${1##*.}"
fi
# No text region: no block, and the app keeps Vision's reading.
if [ "$(/usr/bin/awk 'END {print NR}' "$work/crops.tsv")" -lt 2 ]; then : > "$2"; exit 0; fi
# 540 s of reading, as reader-chandra.sh: the app's own bound is 600 s for the whole page.
# VISIONOCR_REGION_MODEL and VISIONOCR_REGION_PROMPT read the regions with another model (ocr-hybrid-run's
# reader-hybrid.sh), with VISIONOCR_REGION_EXTRA's read-mlx.py options; prompt `""` is none, as LightOnOCR takes,
# and `-` read-mlx.py's own. Unset, the region reader is PaddleOCR-VL's.
# VISIONOCR_REGION_MODEL=vision reads none: each region is written unread, labelled `layout`, and the app reads it
# with its own Vision request (`Recogniser.visionRegionText`, ocr-vision-regions), so the arrangement needs no model.
label=region
if [ "${VISIONOCR_REGION_MODEL:-}" = vision ]; then
    label=layout
    /usr/bin/awk 'NR > 1 {print ""}' "$work/crops.tsv" > "$work/read.txt"
else
rp=(--prompt "${VISIONOCR_REGION_PROMPT:-OCR:}"); [ "${VISIONOCR_REGION_PROMPT:-}" = '""' ] && rp=(--prompt "")
[ "${VISIONOCR_REGION_PROMPT:-}" = - ] && rp=()
stats="$("$py" -I "$here/read-mlx.py" "${VISIONOCR_REGION_MODEL:-mlx-community/PaddleOCR-VL-1.6-4bit}" "$1" "$work/read.txt" \
    ${rp[@]+"${rp[@]}"} ${VISIONOCR_REGION_EXTRA:-} \
    --crops "$work/crops.tsv" --one-line-each --max-tokens 3000 --seconds 540)" || exit 1
case "$stats" in *'"cut": "seconds"'*) echo "reader-regions.sh: reading cut short: $stats" >&2; exit 1;; esac
fi
[ -n "$keep" ] && cp "$work/read.txt" "$keep.read.txt"
# Each crop's reading is one line of read.txt, in crops.tsv's order (its header aside).
"$py" -I - "$1" "$work/crops.tsv" "$work/read.txt" "$2" "$label" <<'EOF'
import sys
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
image, crops, read, out, label = sys.argv[1:6]
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
        f.write(f"{x / w:.5f}\t{y / h:.5f}\t{(x + cw) / w:.5f}\t{(y + ch) / h:.5f}\t{label}\t{text}\n")
EOF
