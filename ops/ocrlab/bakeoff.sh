#!/bin/bash
# ops/ocrlab/bakeoff.sh — read the bake-off sample with every candidate, one model process at a time.
#
#   bakeoff.sh start [--build fitted]   copy the scripts and sample to $J, build the render tools, detach the run
#   bakeoff.sh run   [--build fitted]   the job itself, in the foreground (what `start` detaches)
#   bakeoff.sh status                   alive or not, and readings per model
#   bakeoff.sh stop                     TERM the job's whole process group (the guard takes its model with it)
#
# $J is $STATE/ocrlab. The sample is OCR-SAMPLE-*.tsv (newest), the builds bakeoff-models.tsv rows whose `set`
# is the --build value. Each page is rendered as the truth set rendered it (ops/truth/prep-page.sh: PDFKit
# grey, 400 dpi, 300 when a side passes 5,600 px) to $J/pages/<id>.png and cut by cut-crops into
# $J/pages/<id>/. Vision's readings are the truth set's own, of the same render (vision.txt, vision-crops.txt),
# copied to readings/vision/.
#
# Readings: $J/readings/<label>/<id>.txt (whole page) and <id>.crops.txt (the crops, joined), each written
# when made, with <id>[.crops].err holding the guard's GUARD row (seconds, peak memory) and, for MLX, a
# .json of read-mlx.py's statistics. A reading never made has a .reason instead. A rerun skips both, so
# the job resumes from what is saved. Newspapers are read as crops only: in ocr-lab-setup three of six
# models tripped the swap limit on a whole newspaper page and the other three looped. Any other page is
# read whole, and also as crops when its whole reading holds under 90% of the transcript's words
# (rough-recall.py), the item's "if that loses lines". A read stopped at its time limit (900 s whole, 2,400 s
# crops) is kept as the reading; its .json says `"cut": "seconds"`, and the scorer must count it so.
#
# One progress line per reading in $J/bakeoff.log. While it runs the job touches $STATE/engine.lock every
# 20 s, so the daemon starts no session; it removes the lock when it ends. It will not start while the
# suite lock is held or a suite runs, and each guarded read refuses (75) while one does; the job waits.
set -u
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
STATE="${STATE:-$HOME/.local/state/visionocr-autonomous}"
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
export VISIONOCR_STATE="$STATE"   # run-guarded.sh's name for it: both must check the same test.lock
export HF_HOME="$OCRLAB/hf" HF_HUB_DISABLE_TELEMETRY=1 HF_HUB_OFFLINE=1
J="$STATE/ocrlab"
here="$(cd "$(dirname "$0")" && pwd)"
py="$OCRLAB/venv/bin/python"
TESTDOCS="${TESTDOCS:-$HOME/Claude/vision-ocr/testdocs}"
cmd="${1:-status}"; [ $# -gt 0 ] && shift
build=fitted
while [ $# -gt 0 ]; do
    case "$1" in --build) build="$2"; shift 2 ;; *) echo "bakeoff: unknown option $1" >&2; exit 2 ;; esac
done
mkdir -p "$J/readings/vision" "$J/pages"
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S')	$*" >> "$J/bakeoff.log"; }
alive() { local p; p=$(cat "$J/bakeoff.pid" 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
busy() { pgrep -x tests >/dev/null || [ -d "$STATE/test.lock" ]; }

case "$cmd" in
status)
    if alive; then echo "running, pid $(cat "$J/bakeoff.pid")"; else echo "not running"; fi
    n=$(/usr/bin/grep -vc '^#' "$J/sample.tsv" 2>/dev/null); echo "sample: $((n - 1)) pages"
    for d in "$J"/readings/*/; do
        l=$(basename "$d")
        printf '%s\twhole %s\tcrops %s\treasons %s\n' "$l" "$(ls "$d" | /usr/bin/grep -c '^s[0-9]*\.txt$')" \
            "$(ls "$d" | /usr/bin/grep -c '\.crops\.txt$')" "$(ls "$d" | /usr/bin/grep -c '\.reason$')"
    done
    exit 0 ;;
stop)
    alive || { echo "bakeoff: not running"; exit 0; }
    g=$(ps -o pgid= -p "$(cat "$J/bakeoff.pid")" | tr -d ' ')
    # A job not started by `start` may share this shell's group; TERM to the group would end the caller too.
    [ "$g" = "$(ps -o pgid= -p $$ | tr -d ' ')" ] && { echo "bakeoff: the job shares this shell's process group; kill it by hand" >&2; exit 1; }
    kill -TERM -- "-$g" && echo "bakeoff: sent TERM to process group $g"
    exit 0 ;;
start)
    alive && { echo "bakeoff: already running (pid $(cat "$J/bakeoff.pid"))" >&2; exit 1; }
    busy && { echo "bakeoff: a suite runs or test.lock is held; not starting" >&2; exit 75; }
    sample=$(ls "$here"/../../OCR-SAMPLE-*.tsv | tail -1)
    # The job runs from copies, so removing the worktree it was started from cannot pull its script away.
    rm -rf "$J/scripts"; mkdir -p "$J/scripts" "$J/bin"
    cp "$here"/*.sh "$here"/*.py "$here"/*.tsv "$J/scripts/" && cp "$sample" "$J/sample.tsv" || exit 1
    for t in render-page cut-crops; do
        [ -x "$J/bin/$t" ] || swiftc -O -o "$J/bin/$t" "$here/../truth/$t.swift" || exit 1
    done
    # Detached for real: a new session, so the end of the starting shell or of its session cannot take it.
    "$py" -c '
import os, sys
if os.fork(): sys.exit(0)
os.setsid()
if os.fork(): sys.exit(0)
fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_APPEND); os.dup2(fd, 1); os.dup2(fd, 2)
os.dup2(os.open("/dev/null", os.O_RDONLY), 0)
os.execv("/bin/bash", ["/bin/bash", sys.argv[2], "run", "--build", sys.argv[3]])' \
        "$J/bakeoff.out" "$J/scripts/bakeoff.sh" "$build"
    sleep 3; alive && echo "bakeoff: started, pid $(cat "$J/bakeoff.pid")" || { echo "bakeoff: did not start; see $J/bakeoff.out" >&2; exit 1; }
    exit 0 ;;
run) ;;
*) echo "bakeoff: unknown command $cmd" >&2; exit 2 ;;
esac

alive && { echo "bakeoff: already running" >&2; exit 1; }
busy && { echo "bakeoff: a suite runs or test.lock is held; not starting" >&2; exit 75; }
echo $$ > "$J/bakeoff.pid"
( while kill -0 $$ 2>/dev/null; do touch "$STATE/engine.lock"; sleep 20; done ) &
hb=$!
trap 'kill $hb 2>/dev/null; rm -f "$STATE/engine.lock" "$J/bakeoff.pid"; log "job ended"' EXIT
trap 'exit 143' TERM INT HUP
log "job started, build $build, pid $$"

# Pages: render, cut and copy Vision's readings, once each.
# The sample is read from a file, never through a pipe: a `while` at the end of a pipe runs in a subshell
# that a TERM to this shell does not stop and a KILL orphans, still reading.
/usr/bin/grep -v '^#' "$J/sample.tsv" | tail -n +2 > "$J/sample.rows"
while IFS='	' read -r id doc page route why class; do
    truth="$STATE/truth/${doc%.pdf}/p$page"
    cp "$truth/transcript.txt" "$J/pages/$id.truth.txt" 2>/dev/null
    [ -f "$truth/vision.txt" ] && cp "$truth/vision.txt" "$J/readings/vision/$id.txt"
    [ -f "$truth/vision-crops.txt" ] && cp "$truth/vision-crops.txt" "$J/readings/vision/$id.crops.txt"
    [ -s "$J/pages/$id/crops.tsv" ] && continue
    case "$doc" in owner/*) src="$STATE/owner-supplied/${doc#owner/}" ;; *) src="$TESTDOCS/$doc" ;; esac
    # A failed render leaves no files, so the next run tries it again; the readers skip the page meanwhile.
    size=$("$J/bin/render-page" "$src" "$page" 400 "$J/pages/$id.png") || { rm -f "$J/pages/$id.png"; log "render	$id	failed"; continue; }
    w=${size%x*} h=${size#*x}
    if [ "$w" -gt 5600 ] || [ "$h" -gt 5600 ]; then size=$("$J/bin/render-page" "$src" "$page" 300 "$J/pages/$id.png"); fi
    rm -rf "$J/pages/$id"
    "$J/bin/cut-crops" "$J/pages/$id.png" "$J/pages/$id" > /dev/null || { rm -rf "$J/pages/$id" "$J/pages/$id.png"; log "render	$id	cut-crops failed"; continue; }
    # Same render, same cutter: the crops must be the truth set's. Say so if they are not.
    cmp -s "$J/pages/$id/crops.tsv" "$truth/crops/crops.tsv" || log "render	$id	crops differ from the truth set's"
    log "render	$id	$size	$(( $(wc -l < "$J/pages/$id/crops.tsv") - 1 )) crops"
done < "$J/sample.rows"

# field <col> <label>: one column of the label's bakeoff-models.tsv row.
field() { /usr/bin/awk -F'\t' -v l="$2" -v c="$1" '!/^#/ && $1 == l {print $c; exit}' "$J/scripts/bakeoff-models.tsv"; }

# read_one <label> <id> <whole|crops>
read_one() {
    local label=$1 id=$2 mode=$3 d="$J/readings/$1" base out img more="" prompt extra rc tries kills reason
    mkdir -p "$d"
    base="$d/$id"; [ "$mode" = crops ] && base="$d/$id.crops"
    out="$base.txt"
    [ -s "$out" ] || [ -f "$base.reason" ] && return 0
    img="$J/pages/$id.png"
    # No render (or no crops) is not a reason: the next run renders again and reads it then.
    [ -s "$J/pages/$id/crops.tsv" ] || { log "$label	$id	$mode	skipped	no render yet"; return 0; }
    prompt=$(field 5 "$label") extra=$(field 6 "$label")
    [ "$extra" = - ] && extra=""
    kills=0 tries=0
    while :; do
        if [ "$(field 3 "$label")" = surya ]; then
            local tmp; tmp=$(mktemp -d "${TMPDIR:-/tmp}/bakeoff-surya.XXXXXX")
            local input="$img"; [ "$mode" = crops ] && input="$J/pages/$id"
            # surya_ocr reads every image in a directory: give it the crops alone.
            if [ "$mode" = crops ]; then mkdir "$tmp/in"; cp "$J/pages/$id"/c*.png "$tmp/in/"; input="$tmp/in"; fi
            "$J/scripts/run-guarded.sh" --label "bakeoff.$label.$id.$mode" --need-gb "$(field 7 "$label")" -- \
                "$OCRLAB/venv-surya/bin/surya_ocr" "$input" --output_dir "$tmp/out" > "$base.out" 2> "$base.err"
            rc=$?
            if [ "$rc" = 0 ]; then
                local res; res=$(find "$tmp/out" -name results.json | head -1)
                if [ "$mode" = crops ]; then
                    "$py" "$J/scripts/surya-text.py" "$res" "$out.part" $(/usr/bin/awk -F'\t' 'NR>1 {sub(/\.png$/, "", $1); print $1}' "$J/pages/$id/crops.tsv")
                else
                    "$py" "$J/scripts/surya-text.py" "$res" "$out.part"
                fi || rc=1
            fi
            rm -rf "$tmp"
        else
            local dir repo; repo=$(field 4 "$label")
            # local/<name> is a build converted into $OCRLAB/mlx/<name> (try-mlx.sh's third form).
            case "$repo" in local/*) dir="$OCRLAB/mlx/${repo#local/}"; /usr/bin/grep -q '"quantization"' "$dir/config.json" 2>/dev/null ;;
                *) dir=$("$py" -c "from huggingface_hub import snapshot_download; print(snapshot_download('$repo'))") ;; esac \
                || { echo "weights not in the lab" > "$base.reason"; log "$label	$id	$mode	reason	weights not in the lab"; return 0; }
            if [ "$mode" = crops ]; then more="--crops $J/pages/$id/crops.tsv --max-tokens 3000 --seconds 2400"
            else more="--seconds 900"; case "$extra" in *--max-side*) ;; *) more="$more --max-side 3300" ;; esac; fi
            local p=(); case "$prompt" in -) ;; '""') p=(--prompt "") ;; *) p=(--prompt "$prompt") ;; esac
            "$J/scripts/run-guarded.sh" --label "bakeoff.$label.$id.$mode" --need-gb "$(field 7 "$label")" -- \
                "$py" "$J/scripts/read-mlx.py" "$dir" "$img" "$out.part" "${p[@]+"${p[@]}"}" $more $extra \
                > "$base.json" 2> "$base.err"
            rc=$?
        fi
        if [ "$rc" = 75 ]; then           # the guard refused: the machine is busy. Wait, without counting it.
            tries=$((tries + 1))
            if [ "$tries" -ge 240 ]; then echo "guard refused for 4 hours" > "$base.reason"; break; fi
            sleep 60; continue
        fi
        if [ "$rc" = 0 ] && [ -s "$out.part" ]; then mv "$out.part" "$out"; break; fi
        if [ "$rc" = 137 ]; then
            kills=$((kills + 1))
            reason=$(/usr/bin/grep '^GUARD' "$base.err" | tail -1 | /usr/bin/awk -F'\t' '{print $10}')
            log "$label	$id	$mode	guard	$reason (kill $kills)"
            [ "$kills" -lt 2 ] && { sleep 30; continue; }
            echo "the guard killed it twice: $reason" > "$base.reason"; break
        fi
        echo "exit $rc: $(/usr/bin/grep -v '^GUARD' "$base.err" | tail -3 | tr '\n' ' ' | cut -c1-300)" > "$base.reason"; break
    done
    rm -f "$out.part"
    local g; g=$(/usr/bin/grep '^GUARD' "$base.err" 2>/dev/null | tail -1)
    if [ -s "$out" ]; then
        log "$label	$id	$mode	read	$(echo "$g" | /usr/bin/awk -F'\t' '{a=$6; b=$7; print $5 "s\t" (a>b?a:b) "MB"}')	$(tail -1 "$base.json" 2>/dev/null | /usr/bin/grep -o '"cut": "[^"]*"')	$(wc -c < "$out" | tr -d ' ') chars"
    else
        log "$label	$id	$mode	reason	$(cat "$base.reason")"
    fi
}

# read_model <label>: every sample page, whole then (where it is owed) as crops.
read_model() {
    local label=$1 id doc page route why class r
    log "$label	start"
    while IFS='	' read -r id doc page route why class <&3; do
        busy && { log "waiting: a suite runs"; while busy; do sleep 60; done; }
        # Every reader gets /dev/null as stdin: anything that reads it would eat the sample's lines.
        if [ "$route" = newspaper ]; then read_one "$label" "$id" crops < /dev/null; continue; fi
        read_one "$label" "$id" whole < /dev/null
        if [ -s "$J/readings/$label/$id.txt" ]; then
            r=$("$py" "$J/scripts/rough-recall.py" "$J/pages/$id.truth.txt" "$J/readings/$label/$id.txt" < /dev/null | cut -f1)
            /usr/bin/awk -v r="$r" 'BEGIN {exit !(r < 0.9)}' && read_one "$label" "$id" crops < /dev/null
        fi
    done 3< "$J/sample.rows"
    log "$label	done"
}

# Qwen3.5-9B's last guarded try, through try-mlx.sh as ocr-lab-setup measured the others, only once at
# least 8 GB is reclaimable (it tripped once at 5.9 GB). It joins the run if it fits; if not, its weights go.
if [ ! -f "$J/qwen9b.decided" ]; then
    kills=$(/usr/bin/awk -F'\t' '$2 ~ /^qwen3.5-9b-4bit/ && $9 != "-"' "$OCRLAB/guard.tsv" | wc -l | tr -d ' ')
    if [ "$kills" -lt 2 ]; then
        log "qwen3.5-9b-4bit	last try (guard kills so far: $kills)"
        HF_HUB_OFFLINE=0 NEED_GB=8 "$J/scripts/try-mlx.sh" qwen3.5-9b-4bit mlx-community/Qwen3.5-9B-4bit > "$J/qwen9b.try" 2>&1 < /dev/null
        # try-mlx.sh's rows: label repo page exit seconds load read tokens cut peak_mb mlx_peak recall precision killed
        rows=$(/usr/bin/awk -F'\t' 'NF >= 14' "$J/qwen9b.try" | wc -l | tr -d ' ')
        refused=$(/usr/bin/awk -F'\t' 'NF >= 14 && $4 == 75' "$J/qwen9b.try" | wc -l | tr -d ' ')
        ok=$(/usr/bin/awk -F'\t' 'NF >= 14 && $4 == 0 && $10 < 12288 && $12 >= 0.5' "$J/qwen9b.try" | wc -l | tr -d ' ')
        killed=$(/usr/bin/awk -F'\t' 'NF >= 14 && $4 == 137' "$J/qwen9b.try" | wc -l | tr -d ' ')
        if [ "$ok" = 2 ]; then echo fits > "$J/qwen9b.decided"; log "qwen3.5-9b-4bit	fits; added"
        elif [ "$killed" = 0 ] && { [ "$refused" -gt 0 ] || [ "$rows" = 0 ]; }; then
            # A page the guard (or try-mlx.sh itself) refused is not a try: it stays owed, weights kept.
            log "qwen3.5-9b-4bit	not fully tried: refused (under 8 GB reclaimable, the machine busy, or disk; see qwen9b.try); still owed"
        else   # the guard killed it (its second trip), or it read a page badly: out, as in OCR-MODELS' `fits`
            echo "does not fit" > "$J/qwen9b.decided"; log "qwen3.5-9b-4bit	does not fit; weights dropped"
            "$py" "$J/scripts/drop-weights.py" mlx-community/Qwen3.5-9B-4bit >> "$J/qwen9b.try" 2>&1 < /dev/null
        fi
    else
        echo "tripped twice before" > "$J/qwen9b.decided"
    fi
fi

labels=$(/usr/bin/awk -F'\t' -v b="$build" '!/^#/ && $2 == b {print $1}' "$J/scripts/bakeoff-models.tsv")
[ "$build" = fitted ] && [ "$(cat "$J/qwen9b.decided" 2>/dev/null)" = fits ] && labels="$labels qwen3.5-9b-4bit"
for label in $labels; do read_model "$label"; done
log "all models done"
