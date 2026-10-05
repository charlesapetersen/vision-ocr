#!/bin/bash
# ops/ocrlab/try-mlx.sh <label> <hf-repo> [prompt] [extra read-mlx.py args…]
# ops/ocrlab/try-mlx.sh <label> <hf-repo>:<model.gguf>:<mmproj.gguf> [prompt] [extra read-gguf.py args…]
#   (the second form downloads only those two files and reads through llama.cpp)
#
# Pages, made once by hand (see OCR-MODELS-*.tsv's header): pages/ordinary.png and pages/newspaper.png,
# PDFKit renders at 300 dpi, their truth transcripts as *.truth.txt, and newspaper.crops.tsv, the truth
# set's crop boxes for the newspaper page.
# Downloads one MLX build (refusing if free disk by `df` would fall below 20 GB, or the lab would pass
# 50 GB, the queue's limit), reads the ordinary and the newspaper page under run-guarded.sh, and appends one row per page to
# $OCRLAB/results.tsv (pages: ordinary, newspaper whole, newspaper as 13 crops):
#   label repo page exit seconds_total load_s read_s gen_tokens cut guard_peak_mb mlx_peak_gb
#   recall precision killed
# PAGES="newspaper newspaper-crops" reads only those. NEED_GB (default 4) is the reclaimable memory the
# guard waits for before starting; set it near a big model's expected footprint. A model the guard has killed once gets at most one
# more try, under changed conditions; after a second kill it is out (ocr-lab-setup's DONE WHEN).
# Readings are kept as $OCRLAB/out/<label>.<page>.txt. Never run two at once; the guard refuses anyway.
set -u
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
export HF_HOME="$OCRLAB/hf" HF_HUB_DISABLE_TELEMETRY=1
here="$(cd "$(dirname "$0")" && pwd)"
py="$OCRLAB/venv/bin/python"
label="$1" repo="$2"; shift 2
prompt="${1:-Transcribe all the text on this page, in reading order, as plain text.}"; [ $# -gt 0 ] && shift
mkdir -p "$OCRLAB/out"

reader="$here/read-mlx.py" files=""
case "$repo" in *:*) reader="$here/read-gguf.py"; files="${repo#*:}"; repo="${repo%%:*}" ;; esac
need_mb=$("$py" -c "
from huggingface_hub import HfApi
i = HfApi().model_info('$repo', files_metadata=True)
want = '$files'.split(':') if '$files' else None
print(sum((s.size or 0) for s in i.siblings if not want or s.rfilename in want) // 2**20)") \
    || { echo "try-mlx: cannot read $repo" >&2; exit 1; }
free_mb=$(df -m / | awk 'NR==2 {print $4}')
lab_mb=$(du -sm "$OCRLAB" | awk '{print $1}')
echo "try-mlx: $repo needs ${need_mb} MB; free ${free_mb} MB; lab ${lab_mb} MB" >&2
if [ $((free_mb - need_mb)) -lt 20480 ]; then echo "try-mlx: would leave under 20 GB free; refusing" >&2; exit 75; fi
if [ $((lab_mb + need_mb)) -gt 51200 ]; then echo "try-mlx: lab would pass 50 GB; refusing" >&2; exit 75; fi
if [ -n "$files" ]; then
    dir=$("$py" -c "
from huggingface_hub import hf_hub_download
print(','.join(hf_hub_download('$repo', f) for f in '$files'.split(':')))") || exit 1
else
    dir=$("$py" -c "from huggingface_hub import snapshot_download; print(snapshot_download('$repo'))") || exit 1
fi

# The whole newspaper page is not read by default: of the first six models, three tripped the swap limit
# on it (5-8 GB footprints) and three looped or ran out of time; none read it. PAGES=newspaper asks for it.
for page in ${PAGES:-ordinary newspaper-crops}; do
    img="$OCRLAB/pages/$page.png" truth="$OCRLAB/pages/$page.truth.txt" more=""
    case "$page" in
        newspaper) more="--seconds 120" ;;   # whole page: a model that cannot read it loops; do not wait it out
        newspaper-crops) img="$OCRLAB/pages/newspaper.png" truth="$OCRLAB/pages/newspaper.truth.txt"
                         more="--crops $OCRLAB/pages/newspaper.crops.tsv --max-tokens 3000" ;;   # a crop holds ~1,200 tokens
    esac
    out="$OCRLAB/out/$label.$page.txt" stats="$OCRLAB/out/$label.$page.json"
    rm -f "$out" "$stats"
    for wait in $(seq 1 40); do     # the guard refuses (75) while the machine is busy; wait for headroom
        start=$(date +%s)
        "$here/run-guarded.sh" --label "$label.$page" --need-gb "${NEED_GB:-4}" -- \
            "$py" "$reader" "$dir" "$img" "$out" --prompt "$prompt" $more "$@" \
            > "$stats" 2> "$OCRLAB/out/$label.$page.err"
        rc=$?
        [ "$rc" = 75 ] || break
        sleep 30
    done
    secs=$(( $(date +%s) - start ))
    g=$(grep '^GUARD' "$OCRLAB/out/$label.$page.err" | tail -1)
    peak=$(echo "$g" | awk -F'\t' '{a=$6; b=$7; print (a>b?a:b)}')
    killed=$(echo "$g" | awk -F'\t' '{print $10}')
    j=$(tail -1 "$stats")
    field() { echo "$j" | "$py" -c "import json,sys
try: print(json.loads(sys.stdin.read())['$1'])
except Exception: print('-')"; }
    rr="-	-"; [ -s "$out" ] && rr=$("$py" "$here/rough-recall.py" "$truth" "$out")
    row="$label	$repo${files:+:$files}	$page	$rc	$secs	$(field load_s)	$(field read_s)	$(field gen_tokens)	$(field cut)	$peak	$(field mlx_peak_gb)	$rr	$killed"
    echo "$row" >> "$OCRLAB/results.tsv"
    echo "$row"
    [ "$rc" = 137 ] && { echo "try-mlx: guard killed $label on $page; not reading the next page" >&2; break; }
done
