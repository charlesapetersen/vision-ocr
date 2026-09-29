#!/bin/bash
# make-scans.sh <bindir holding render-page and img2pdf> <pdf> <page> <outdir>
# Makes truth-calibrate's two scans of one born-digital page, with no text layer:
#   clean.pdf — 300 dpi greyscale on grey paper, light noise, good JPEG
#   hard.pdf  — 150 dpi, 1-bit, skewed 0.8 degrees, JPEG at quality 20
# The page's own text layer (or synth-pages' .txt) is the truth they are scored against.
set -eu
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
[ $# -eq 4 ] || { echo "usage: make-scans.sh <bindir> <pdf> <page> <outdir>" >&2; exit 2; }
render=$1/render-page img2pdf=$1/img2pdf pdf=$2 page=$3 out=$4
mkdir -p "$out"
"$render" "$pdf" "$page" 300 "$out/r300.png" >/dev/null
"$render" "$pdf" "$page" 150 "$out/r150.png" >/dev/null
magick "$out/r300.png" -evaluate multiply 0.87 -attenuate 0.25 +noise Gaussian -colorspace Gray \
    -quality 85 "$out/clean.jpg"
size=$(magick identify -format '%wx%h' "$out/r150.png")
magick "$out/r150.png" -background white -rotate 0.8 +repage -gravity center -extent "$size" \
    -threshold 55% -colorspace Gray -type Grayscale -quality 20 "$out/hard.jpg"
"$img2pdf" "$out/clean.jpg" 300 "$out/clean.pdf"
"$img2pdf" "$out/hard.jpg" 150 "$out/hard.pdf"
rm -f "$out/r300.png" "$out/r150.png" "$out/clean.jpg" "$out/hard.jpg"
