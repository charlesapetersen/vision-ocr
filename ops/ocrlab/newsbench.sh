#!/bin/bash
# ops/ocrlab/newsbench.sh — read NewsBench's scored pages with one reader, whole or on DocLayout-YOLO regions.
#
#   newsbench.sh <label|vision> <whole|yolo> [stem…]
#
# <label> is a bakeoff-models.tsv row (its prompt, extra and need_gb), or `vision` for ops/truth/vision-read.swift
# (the app's Vision settings). `yolo` reads each page as its DocLayout-YOLO regions (layout-regions.py, then
# dedupe-regions.py), cut once per page into $NB/regions/<stem>.crops.tsv and joined in the stand-in order.
# Readings go to $NB/ocr-results/<label>-<mode>/<stem>.txt, where NewsBench's own score.py finds them; read-mlx.py's
# statistics and the guard's row to $NB/runs/<label>-<mode>/<stem>.{json,err}. A page with a reading is skipped,
# so a rerun finishes what a cut-off one left. With no stems, every page newsbench.csv does not exclude.
# Every model process runs under run-guarded.sh (memory guard, mac-heavy.lock), one at a time.
set -u
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
export HF_HOME="$OCRLAB/hf" HF_HUB_DISABLE_TELEMETRY=1 HF_HUB_OFFLINE=1
here="$(cd "$(dirname "$0")" && pwd)"; py="$OCRLAB/venv/bin/python"; NB="$OCRLAB/newsbench"
[ $# -ge 2 ] || { /usr/bin/sed -n '3,4p' "$0"; exit 2; }
label=$1 mode=$2; shift 2
case "$mode" in whole|yolo) ;; *) echo "mode must be whole or yolo" >&2; exit 2 ;; esac
res="$NB/ocr-results/$label-$mode" runs="$NB/runs/$label-$mode"
mkdir -p "$res" "$runs" "$NB/regions"
stems=("$@")
[ ${#stems[@]} -gt 0 ] || stems=($("$py" -c "
import csv
for r in csv.DictReader(open('$NB/newsbench.csv')):
    if not (r.get('exclude') or '').strip(): print(r['image_name'].rsplit('.', 1)[0])"))
[ ${#stems[@]} -gt 0 ] || { echo "no pages to read" >&2; exit 1; }

field() { /usr/bin/awk -F'\t' -v l="$2" -v c="$1" '!/^#/ && $1 == l {print $c; exit}' "$here/bakeoff-models.tsv"; }
yolo_w=$(ls "$OCRLAB"/hf/hub/models--wybxc--DocLayout-YOLO-DocStructBench-onnx/snapshots/*/doclayout_yolo_docstructbench_imgsz1024.onnx 2>/dev/null | head -1)

# guarded <tag> <errfile> -- cmd…: run under the guard, waiting (at most 4 hours) while it refuses on a busy machine.
guarded() {
    local tag=$1 err=$2 rc tries=0; shift 3
    while :; do
        "$here/run-guarded.sh" --label "newsbench.$tag" --need-gb "${need:-4}" -- "$@" 2> "$err"; rc=$?
        [ "$rc" = 75 ] && [ "$tries" -lt 240 ] && { tries=$((tries + 1)); sleep 60; continue; }
        return $rc
    done
}

if [ "$label" = vision ]; then
    vr="$NB/runs/vision-read"
    [ -x "$vr" ] && [ "$vr" -nt "$here/../truth/vision-read.swift" ] || swiftc -O "$here/../truth/vision-read.swift" -o "$vr" || exit 1
else
    repo=$(field 4 "$label"); [ -n "$repo" ] || { echo "no bakeoff-models.tsv row for $label" >&2; exit 2; }
    case "$repo" in local/*) dir="$OCRLAB/mlx/${repo#local/}" ;;
        *) dir=$("$py" -c "from huggingface_hub import snapshot_download; print(snapshot_download('$repo'))") || exit 1 ;; esac
    prompt=$(field 5 "$label") extra=$(field 6 "$label") need=$(field 7 "$label")
    [ "$extra" = - ] && extra=""
    p=(); case "$prompt" in -) ;; '""') p=(--prompt "") ;; *) p=(--prompt "$prompt") ;; esac
fi

for s in "${stems[@]}"; do
    img="$NB/images/$s.jpg" out="$res/$s.txt"
    [ -s "$out" ] && continue
    crops="$NB/regions/$s.crops.tsv"
    if [ "$mode" = yolo ] && [ ! -s "$crops" ]; then
        [ -n "$yolo_w" ] || { echo "DocLayout-YOLO's ONNX weights are not in the lab" >&2; exit 1; }
        guarded "layout.$s" "$NB/regions/$s.err" -- "$py" "$here/layout-regions.py" --model yolo --weights "$yolo_w" \
            --image "$img" --out "$NB/regions/$s.tsv" > "$NB/regions/$s.log" || { echo "$s: layout failed" >&2; continue; }
        "$py" "$here/dedupe-regions.py" "$NB/regions/$s.tsv" "$crops" >> "$NB/regions/$s.log" \
            || { echo "$s: dedupe failed" >&2; rm -f "$crops"; continue; }
    fi
    if [ "$mode" = yolo ] && [ "$(/usr/bin/awk 'END {print NR}' "$crops")" -lt 2 ]; then
        echo "$s: no text regions, no reading" >&2; continue
    fi
    if [ "$label" = vision ]; then
        list=("$img")
        if [ "$mode" = yolo ]; then
            tmp=$(mktemp -d "${TMPDIR:-/tmp}/newsbench-crops.XXXXXX")
            "$py" -c "
import sys
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
page = Image.open('$img')
for line in open('$crops').read().splitlines()[1:]:
    n, x, y, w, h = line.split('\t')[:5]; x, y, w, h = int(x), int(y), int(w), int(h)
    page.crop((x, y, x + w, y + h)).save('$tmp/' + n)" || { echo "$s: cutting crops failed" >&2; rm -rf "$tmp"; continue; }
            list=($(/usr/bin/awk -F'\t' -v d="$tmp" 'NR > 1 {print d "/" $1}' "$crops"))
        fi
        guarded "vision.$mode.$s" "$runs/$s.err" -- /usr/bin/time -l "$vr" "${list[@]}" > "$out.part"; rc=$?
        [ "$mode" = yolo ] && rm -rf "$tmp"
    else
        if [ "$mode" = yolo ]; then more="--crops $crops --max-tokens 3000 --seconds 3600"
        else more="--seconds 900"; case "$extra" in *--max-side*) ;; *) more="$more --max-side 3300" ;; esac; fi
        guarded "$label.$mode.$s" "$runs/$s.err" -- "$py" "$here/read-mlx.py" "$dir" "$img" "$out.part" \
            "${p[@]+"${p[@]}"}" $more $extra > "$runs/$s.json"; rc=$?
    fi
    # A read cut off by --seconds or --max-tokens exits 0 with partial text: it is kept, as bakeoff.sh keeps it, but
    # said here and in the json, so a row built on it can say so.
    cut=$(/usr/bin/sed -n 's/.*"cut": "\([^"]*\)".*/\1/p' "$runs/$s.json" 2>/dev/null)
    [ -n "$cut" ] && [ "$cut" != - ] && echo "$s: read CUT ($cut), reading incomplete" >&2
    if [ "$rc" = 0 ] && [ -s "$out.part" ]; then mv "$out.part" "$out"
    else rm -f "$out.part"; echo "$s: exit $rc, no reading (see $runs/$s.err)" >&2; fi
    /usr/bin/grep "^GUARD" "$runs/$s.err" | tail -1 | /usr/bin/cut -f1-9
done
