#!/bin/bash
# spots-page.sh <page-dir>
# Procedure.md step 4 for a truth-set page. A spot is a reader word that no other reading confirms: it
# differs from Vision's reading of the page image (vision.txt), from Vision's reading of each crop at full
# resolution (vision-crops.txt, when present) and, where the source has a layer holding at
# least half as many words as the reader found, from that layer too (layer.txt). With no layer this is the
# calibrated case, Vision alone. A layer thinner than that is not asked: it is not a reading of the page
# (the Why scans' vendor layers hold 25 words of 500), so it may not confirm a word. Alignment is line by line
# (`xcheck.py lspots`). The spots are cut to check/<idx>.png by wordcrops.py. Prints the spot count.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
set -euo pipefail
d=$1
here=$(cd "$(dirname "$0")" && pwd)
python3 "$here/xcheck.py" lspots "$d/transcript.txt" "$d/vision.txt" | sort -t$'\t' -k1,1 > "$d/spots-vision.tsv"
if [ -f "$d/vision-crops.txt" ]; then
  python3 "$here/xcheck.py" lspots "$d/transcript.txt" "$d/vision-crops.txt" | cut -f1 | sort > "$d/spots-crops.idx"
  awk -F'\t' 'NR == FNR {l[$1]; next} $1 in l' "$d/spots-crops.idx" "$d/spots-vision.tsv" > "$d/spots-vision.tmp"
  mv "$d/spots-vision.tmp" "$d/spots-vision.tsv"
fi
rw=$(python3 "$here/xcheck.py" text "$d/transcript.txt" | wc -w)
if [ $(( $(wc -w < "$d/layer.txt") * 2 )) -ge "$rw" ]; then
  python3 "$here/xcheck.py" lspots "$d/transcript.txt" "$d/layer.txt" | cut -f1 | sort > "$d/spots-layer.idx"
  awk -F'\t' 'NR == FNR {l[$1]; next} $1 in l' "$d/spots-layer.idx" "$d/spots-vision.tsv"
else
  cat "$d/spots-vision.tsv"
fi | sort -t$'\t' -k1,1n > "$d/spots.tsv"
if [ -s "$d/spots.tsv" ]; then python3 "$here/wordcrops.py" "$d" > /dev/null; fi
wc -l < "$d/spots.tsv" | tr -d ' '
