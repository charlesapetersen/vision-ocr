#!/bin/bash
# reader-hybrid.sh — the model reader (`Prefs.modelReader`) behind every ocr-hybrid-run combination, one model call
# under run-guarded.sh, so each page's time and peak memory are the guard's.
#
#   reader-hybrid.sh <page image> <out> [crops.tsv]   as the app calls any reader
#
# hybrid-run.sh writes one small wrapper per combination that sets these and execs this script:
#   HYBRID_COMBO   the combination's label (vision-off, falcon-align, ...), in the guard's label
#   HYBRID_KIND    text     read-mlx.py, the page whole (align) or each crop on one line (fill)
#                  blocks   reader-chandra.sh's layout blocks (replace)
#                  regions  reader-regions.sh, its regions read by HYBRID_MODEL (regions)
#   HYBRID_MODEL   a Hub repo in the lab's cache or a directory; HYBRID_PROMPT `-` read-mlx.py's own, `""` none
#   HYBRID_EXTRA   more read-mlx.py options (LightOnOCR's --max-side 1540); HYBRID_NEED the guard's --need-gb
# and the job sets, per page: HYBRID_PAGE (the sample id, in the guard's label), HYBRID_GUARDS (a file each
# call's GUARD row is appended to) and HYBRID_STATS (read-mlx.py's statistics, one JSON line a call).
#
# A reading stopped by --seconds exits 1, so the app fails the page rather than publish a part of it; the
# app's own bound is 600 s. A guard refusal exits 75, which the app reports as a failed reader and the job
# reads in HYBRID_GUARDS (a REFUSED row) as "try again later", not as a result. For measuring, not for shipping.
set -u
[ $# -eq 2 ] || [ $# -eq 3 ] || { echo "usage: reader-hybrid.sh <page image> <out> [crops.tsv]" >&2; exit 2; }
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
here="$(cd "$(dirname "$0")" && pwd)"
export HF_HOME="$OCRLAB/hf" HF_HUB_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
py="$OCRLAB/venv/bin/python"
guards="${HYBRID_GUARDS:-/dev/null}" stats="${HYBRID_STATS:-/dev/null}"
err="$(mktemp -t visionocr-hybrid)" || exit 1
trap 'rm -f "$err" "$err.json"' EXIT
guard=("$here/run-guarded.sh" --label "hybrid.${HYBRID_COMBO:--}.${HYBRID_PAGE:--}" --need-gb "${HYBRID_NEED:-4}" --)
case "${HYBRID_KIND:-}" in
text)
    p=(); case "${HYBRID_PROMPT:--}" in -) ;; '""') p=(--prompt "") ;; *) p=(--prompt "$HYBRID_PROMPT") ;; esac
    # Crops as reader-falcon.sh reads them: a line or two each, the cap stopping one crop's loop.
    if [ $# -eq 3 ]; then more=(--crops "$3" --one-line-each --max-tokens 400 --seconds 540)
    else more=(--seconds 540); case "${HYBRID_EXTRA:-}" in *--max-side*) ;; *) more+=(--max-side 3300) ;; esac; fi
    # shellcheck disable=SC2086  # HYBRID_EXTRA is a list of options
    "${guard[@]}" "$py" -I "$here/read-mlx.py" "$HYBRID_MODEL" "$1" "$2" ${p[@]+"${p[@]}"} ${HYBRID_EXTRA:-} \
        "${more[@]}" > "$err.json" 2> "$err"
    rc=$? ;;
blocks)
    "${guard[@]}" "$here/reader-chandra.sh" "$@" > /dev/null 2> "$err"; rc=$? ;;
regions)
    # HYBRID_LAYOUT is the detector (layout-compare), HYBRID_KEEP where the run keeps regions and readings.
    VISIONOCR_REGION_MODEL="$HYBRID_MODEL" VISIONOCR_REGION_PROMPT="${HYBRID_PROMPT:-OCR:}" \
        VISIONOCR_REGION_EXTRA="${HYBRID_EXTRA:-}" VISIONOCR_LAYOUT="${HYBRID_LAYOUT:-yolo}" \
        VISIONOCR_READER_KEEP="${HYBRID_KEEP:-}" \
        "${guard[@]}" "$here/reader-regions.sh" "$@" > /dev/null 2> "$err"; rc=$? ;;
*) echo "reader-hybrid.sh: HYBRID_KIND is '${HYBRID_KIND:-}'" >&2; exit 2 ;;
esac
# The guard writes no row when it refuses to start (75): say so, for the job to try the page again.
if /usr/bin/grep -q '^GUARD' "$err"; then /usr/bin/grep '^GUARD' "$err" | tail -1 >> "$guards"
elif [ "$rc" = 75 ]; then printf 'REFUSED\t%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$(tail -1 "$err")" >> "$guards"; fi
[ -s "$err.json" ] && tail -1 "$err.json" >> "$stats"
# reader-regions.sh and reader-chandra.sh read the statistics themselves and say a cut on stderr: note it alike.
/usr/bin/grep -q 'cut short.*"cut": "seconds"' "$err" && echo '{"cut": "seconds", "said": "reader"}' >> "$stats"
[ "$rc" = 0 ] || exit "$rc"
case "$(tail -1 "$err.json" 2>/dev/null)" in *'"cut": "seconds"'*) exit 1 ;; esac
exit 0
