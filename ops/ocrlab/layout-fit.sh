#!/bin/bash
# ops/ocrlab/layout-fit.sh — layout-compare's fit test: one detector alone over page images, each page a fresh
# process, so the load and detect seconds, region counts and the script's ink_covered are the detector's own, and
# peak memory is /usr/bin/time -l's (the guard's 2 s sample misses a sub-second run; OCR-LAYOUT-2026-10-07). Light
# work: no reader, nothing near 1 GB, one process at a time; it does not take the heavy lock.
#
#   layout-fit.sh <yolo|pp|heron> <dir of .png pages> <out dir> [conf] [device]
#
# Writes <out dir>/<detector>-<conf>.tsv, one row a page: id width height conf imgsz load_s detect_s regions
# text_regions largest_MP ink_covered peak_rss_MB seconds; the regions, an overlay and the logs in <out dir>/regions/.
set -u
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
here="$(cd "$(dirname "$0")" && pwd)"
export HF_HOME="$OCRLAB/hf" HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
[ $# -ge 3 ] || { echo "usage: layout-fit.sh <yolo|pp|heron> <pages dir> <out dir> [conf] [device]" >&2; exit 2; }
det=$1 pages=$2 out=$3 conf=${4:-} device=${5:-cpu}
py="$OCRLAB/venv/bin/python"
case "$det" in
yolo)  weights=$(ls "$OCRLAB"/hf/hub/models--wybxc--DocLayout-YOLO-DocStructBench-onnx/snapshots/*/doclayout_yolo_docstructbench_imgsz1024.onnx | head -1)
       : "${conf:=0.25}" ;;
pp)    weights="$OCRLAB/layout/pp-doclayout-v3-mlx"; : "${conf:=0.3}" ;;
heron) weights=$(ls -d "$OCRLAB"/hf/hub/models--ds4sd--docling-layout-heron/snapshots/* | head -1)
       py="$OCRLAB/venv-surya/bin/python"; : "${conf:=0.3}" ;;
*)     echo "layout-fit.sh: detector '$det' is not yolo, pp or heron" >&2; exit 2 ;;
esac
mkdir -p "$out/regions"
tsv="$out/$det-$conf.tsv"
printf 'id\twidth\theight\tconf\timgsz\tload_s\tdetect_s\tregions\ttext_regions\tlargest_MP\tink_covered\tpeak_rss_MB\tseconds\n' > "$tsv"
for png in "$pages"/*.png; do
    id=$(basename "$png" .png) stem="$out/regions/$det-$conf-$id"
    t0=$(date +%s)
    /usr/bin/time -l "$py" -I "$here/layout-regions.py" --model "$det" --weights "$weights" --conf "$conf" --device "$device" \
        --image "$png" --out "$stem.tsv" --overlay "$stem.png" > "$stem.log" 2> "$stem.err"
    rc=$?
    w=$(sips -g pixelWidth "$png" | /usr/bin/awk '/pixelWidth/ {print $2}')
    h=$(sips -g pixelHeight "$png" | /usr/bin/awk '/pixelHeight/ {print $2}')
    rss=$(/usr/bin/awk '/maximum resident set size/ {printf "%d", $1 / 1048576}' "$stem.err")
    if [ "$rc" != 0 ]; then
        echo "layout-fit: $det on $id exited $rc, see $stem.err" >&2
        printf '%s\t%s\t%s\t%s\tfailed\t-\t-\t-\t-\t-\t-\t%s\t%s\n' "$id" "$w" "$h" "$conf" "${rss:--}" "$(( $(date +%s) - t0 ))" >> "$tsv"
        continue
    fi
    line=$(tail -1 "$stem.log")
    v() { echo "$line" | tr ' ' '\n' | /usr/bin/awk -F= -v k="$1" '$1 == k {print $2}'; }
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$w" "$h" "$conf" "$(v imgsz)" "$(v load_s)" "$(v detect_s)" \
        "$(v regions)" "$(v text_regions)" "$(v largest_text_MP)" "$(v ink_covered)" "${rss:--}" "$(( $(date +%s) - t0 ))" >> "$tsv"
done
echo "layout-fit: $tsv"
