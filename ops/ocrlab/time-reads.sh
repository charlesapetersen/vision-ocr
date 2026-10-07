#!/bin/bash
# ops/ocrlab/time-reads.sh <out-dir> <label>|vision [id…] — time readers again, one guarded read at a time.
#
# ocr-bakeoff-score's two timings the bake-off's log could not give: Vision's (the job copied its readings
# from the truth run and never timed them), and DeepSeek-OCR-2's and LightOnOCR's, read on a busy machine.
# `vision` reads each sample page whole and then as its crops with ops/truth/vision-read.swift (revision 3,
# accurate, language correction: the app's settings), one process per read. A model label reads each page
# whole exactly as bakeoff.sh does (same prompt, extra, --seconds 900 and --max-side). Every read goes
# through run-guarded.sh, so its seconds and peak memory are measured the same way as the job's. With no ids,
# every sample page; a model reads only the pages it read whole (not the newspapers). Vision's reads take a
# second or two, under the guard's 2 s sample, so theirs are /usr/bin/time -l's wall time and peak RSS.
#
# Writes <out-dir>/<label>/<id>[.crops].txt and one row per read to <out-dir>/times.tsv:
#   label id mode seconds peak_mb load1 exit
# A row whose exit is not 0 is a failed read: its time is not a reading's.
# The readings are for checking against the job's; the score is the job's own readings'.
set -u
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
STATE="${STATE:-$HOME/.local/state/visionocr-autonomous}"
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
export VISIONOCR_STATE="$STATE" HF_HOME="$OCRLAB/hf" HF_HUB_DISABLE_TELEMETRY=1 HF_HUB_OFFLINE=1
J="$STATE/ocrlab"; here="$(cd "$(dirname "$0")" && pwd)"; py="$OCRLAB/venv/bin/python"
out="$1" label="$2"; shift 2
mkdir -p "$out/$label"
[ -f "$out/times.tsv" ] || printf 'label\tid\tmode\tseconds\tpeak_mb\tload1\texit\n' > "$out/times.tsv"
field() { /usr/bin/awk -F'\t' -v l="$2" -v c="$1" '!/^#/ && $1 == l {print $c; exit}' "$here/bakeoff-models.tsv"; }
ids=("$@")
[ ${#ids[@]} -gt 0 ] || ids=($(/usr/bin/awk -F'\t' '!/^#/ && $1 != "id" {print $1}' "$J/sample.tsv"))

if [ "$label" = vision ]; then
    vr="$out/vision-read"
    [ -x "$vr" ] || swiftc -O "$here/../truth/vision-read.swift" -o "$vr" || exit 1
fi

# guarded <id> <mode> <txt> -- cmd…: one guarded read, its row appended to times.tsv
guarded() {
    local id=$1 mode=$2 txt=$3 err rc g tries=0; shift 4
    err="$out/$label/$id.$mode.err"
    while :; do
        "$here/run-guarded.sh" --label "time.$label.$id.$mode" --need-gb "${need:-4}" -- "$@" > "$txt.stdout" 2> "$err"
        rc=$?
        # the guard refused (the machine is busy): wait, as bakeoff.sh does, for at most 4 hours
        [ "$rc" = 75 ] && [ "$tries" -lt 240 ] && { tries=$((tries + 1)); sleep 60; continue; }; break
    done
    g=$(/usr/bin/grep '^GUARD' "$err" | tail -1)
    local secs mb
    secs=$(echo "$g" | /usr/bin/awk -F'\t' '{print $5}') mb=$(echo "$g" | /usr/bin/awk -F'\t' '{a=$6; b=$7; print (a>b?a:b)}')
    # Vision reads in a second or two, under the guard's 2 s sample: /usr/bin/time -l's own figures instead
    if /usr/bin/grep -q 'maximum resident set size' "$err"; then
        secs=$(/usr/bin/awk '$2 == "real" {print $1}' "$err")
        # the larger of RSS and the physical footprint, as the guard takes it
        mb=$(/usr/bin/awk '/maximum resident set size|peak memory footprint/ {if ($1 > m) m = $1} END {printf "%d", m / 1048576}' "$err")
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$label" "$id" "$mode" "$secs" "$mb" \
        "$(sysctl -n vm.loadavg | /usr/bin/awk '{print $2}')" "$rc" >> "$out/times.tsv"
    [ "$rc" = 0 ] || echo "time-reads: $label $id $mode exit $rc" >&2
}

for id in "${ids[@]}"; do
    img="$J/pages/$id.png"
    if [ "$label" = vision ]; then
        guarded "$id" whole "$out/$label/$id.txt" -- /usr/bin/time -l "$vr" "$img"
        mv "$out/$label/$id.txt.stdout" "$out/$label/$id.txt"
        crops=($(/usr/bin/awk -F'\t' -v d="$J/pages/$id" 'NR>1 {print d "/" $1}' "$J/pages/$id/crops.tsv" 2>/dev/null))
        [ ${#crops[@]} -gt 0 ] || { echo "time-reads: $id has no crops" >&2; continue; }
        guarded "$id" crops "$out/$label/$id.crops.txt" -- /usr/bin/time -l "$vr" "${crops[@]}"
        mv "$out/$label/$id.crops.txt.stdout" "$out/$label/$id.crops.txt"
        continue
    fi
    [ -s "$J/readings/$label/$id.txt" ] || continue           # the job read it as crops only (a newspaper)
    [ "$(field 3 "$label")" = mlx ] || { echo "time-reads: $label is not an MLX build; bakeoff.sh's other runtimes are not here" >&2; exit 2; }
    repo=$(field 4 "$label") prompt=$(field 5 "$label") extra=$(field 6 "$label") need=$(field 7 "$label")
    [ "$extra" = - ] && extra=""
    case "$repo" in local/*) dir="$OCRLAB/mlx/${repo#local/}" ;;
        *) dir=$("$py" -c "from huggingface_hub import snapshot_download; print(snapshot_download('$repo'))") || exit 1 ;; esac
    more="--seconds 900"; case "$extra" in *--max-side*) ;; *) more="$more --max-side 3300" ;; esac
    p=(); case "$prompt" in -) ;; '""') p=(--prompt "") ;; *) p=(--prompt "$prompt") ;; esac
    guarded "$id" whole "$out/$label/$id.txt" -- "$py" "$here/read-mlx.py" "$dir" "$img" "$out/$label/$id.txt" "${p[@]+"${p[@]}"}" $more $extra
done
