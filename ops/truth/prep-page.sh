#!/bin/bash
# prep-page.sh <bin-dir> <document> <page>
# Session steps 1-2 of procedure.md for one truth-set page, plus the two readings step 4 aligns with:
# page.png (400 dpi, 300 when a side is over 14 in), crops/, vision.txt and vision-crops.txt
# (vision-read over the page and over each crop), layer.txt (the
# source's own text layer via PDFKit, empty when it has none), brief.txt (the READER prompt verbatim,
# the crop list and the crop command) and meta.txt. <document> is a TRUTH-PAGES row: `owner/<file>` is in
# $STATE/owner-supplied/, anything else under testdocs/. Output in $STATE/truth/<document>/p<N>/, never
# committed. Prints that directory.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
set -eu
B=$1 doc=$2 n=$3
here=$(cd "$(dirname "$0")" && pwd)
STATE=${STATE:-$HOME/.local/state/visionocr-autonomous}
case "$doc" in
  owner/*) src="$STATE/owner-supplied/${doc#owner/}" ;;
  *)       src="${TESTDOCS:-$here/../../testdocs}/$doc" ;;
esac
[ -f "$src" ] || { echo "no source: $src" >&2; exit 1; }
d="$STATE/truth/${doc%.pdf}/p$n"
mkdir -p "$d"
dpi=400
size=$("$B/render-page" "$src" "$n" 400 "$d/page.png")   # prints WxH
w=${size%x*} h=${size#*x}
if [ "$w" -gt 5600 ] || [ "$h" -gt 5600 ]; then dpi=300; size=$("$B/render-page" "$src" "$n" 300 "$d/page.png"); fi
rm -rf "$d/crops"; "$B/cut-crops" "$d/page.png" "$d/crops" > /dev/null
"$B/vision-read" "$d/page.png" > "$d/vision.txt"
"$B/vision-read" "$d"/crops/c*.png > "$d/vision-crops.txt"
"$B/page-text" "$src" "$n" > "$d/layer.txt"
{
  awk '/^## READER prompt/{f=1; next} /^## /{f=0} f && /^>/{sub(/^> ?/, ""); print}' "$here/procedure.md"
  printf '\nCrops (name, x, y, w, h in page pixels, overlap):\n'
  awk -F'\t' -v d="$d/crops" 'NR > 1 {print d "/" $0}' "$d/crops/crops.tsv"
  printf '\nCrop command: /opt/homebrew/bin/magick \"%s\" -crop WxH+X+Y \"%s/zoom-N.png\"  (then Read that file). Do not Read page.png itself.\n' "$d/page.png" "$d"
  printf '\nWrite your complete answer (the lines, then COLUMNS:, then OBJECTS:) with the Write tool to %s/transcript.txt, and reply only '"'"'done'"'"'.\n' "$d"
} > "$d/brief.txt"
{
  echo "procedure=$(awk '/version/{print; exit}' "$here/procedure.md" | sed 's/.*version \([0-9]*\).*/v\1/')"
  echo "source=$doc"
  echo "sha256=$(shasum -a 256 "$src" | cut -d' ' -f1)"
  echo "page=$n dpi=$dpi px=$size"
} > "$d/meta.txt"
echo "$d"
