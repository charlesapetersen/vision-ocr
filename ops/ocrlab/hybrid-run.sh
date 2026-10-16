#!/bin/bash
# ops/ocrlab/hybrid-run.sh — ocr-hybrid-run: every arrangement with each of the top three over the bake-off sample,
# through the production pipeline, one page at a time, scored as a reader meets it.
#
#   hybrid-run.sh start   build the gate, helper and harness from this checkout into $H/bin, copy the scripts and
#                         the sample to $H, detach the run
#   hybrid-run.sh run     the job itself, in the foreground (what `start` detaches)
#   hybrid-run.sh status  alive or not, and pages done per combination
#   hybrid-run.sh stop    TERM the job's whole process group
# A smoke run: HYBRID_DIR=<scratch> HYBRID_COMBOS="vision-off falcon-align" HYBRID_PAGES="s03 s45" hybrid-run.sh start
#
# $H is $STATE/ocrlab/hybrid. Each sample page (OCR-SAMPLE-*.tsv, newest) is cut from its document with
# `qpdf --pages`, which keeps its geometry and resources (BUGS.md: PDFKit's extract moves the media box), to
# $H/pages/<id>.pdf, and its truth-set page linked as $H/truth/<id>/p1. For each combination below and each page
# in its set, `score-gate` publishes the page with `modelArrangement` and `modelReader` set in its defaults
# domain (vo-hybrid-gate), and `ux-harness --truth` scores the output against the source. Each run's directory
# is $H/runs/<combo>/<id>/: gate.log, the published PDF in pub/, the harness's pages.tsv/truth.tsv/document.tsv in
# score/, guard.tsv (each model call's GUARD row: seconds, peak memory) and `status`, one line:
#   ok <app s> <wall s> harness-exit <n>   published and scored (n 0 green, 1 red, 2 the harness failed)
#   failed <app s> <wall s> <reason>       the app refused the page, with its log's reason
#   skipped <reason>                       not run, and why
# `app s` is the app's own time for the file (the gate's timings.tsv), `wall s` the whole gate run.
# A page with a status is not run again, so the job resumes from what is saved. A model call the guard refused
# (75: the machine busy or memory short) is no result: the run is cleared and tried again after a minute.
# Three pages of a combination in a row stopped at the reader's time limit skip the rest of it, said.
#
# One line per run in $H/hybrid.log. While it runs the job touches $STATE/engine.lock every 20 s, so the daemon
# starts no session; it removes the lock when it ends. It will not start while the suite lock is held or a
# suite runs, and waits between pages while one does. hybrid-table.py makes OCR-HYBRID-<date>.tsv from $H/runs.
#
# Another job can run through this script (layout-compare.sh, 2026-10-16): HYBRID_SAMPLE names its sample file (else
# the newest OCR-SAMPLE-*.tsv) and HYBRID_COMBOS_TSV a file in COMBOS' columns plus a ninth, the layout detector the
# regions kind cuts with (reader-regions.sh's VISIONOCR_LAYOUT: yolo, pp or heron; `-` is yolo). Each run's keep/
# holds what its reader kept (reader-regions.sh's VISIONOCR_READER_KEEP: the regions, readings and page image).
# HYBRID_HOLD=combo takes the heavy lock once for each combination's pages (`pages`, a child of `run`) instead of
# once a page, and HYBRID_HOLD=group once for consecutive combinations sharing the part of the label after the
# first dash (one reader's three detectors): the lock's queue is first come first served, and while another project
# queues work behind every release, a page at a time gives this job one page per turn of theirs (2026-10-16: one page
# in fifteen minutes, against half-hour turns). The child gives the lock back while a suite is queued or running, so
# the suite, which takes the same lock, is not waited for from inside it; what it had done stays done, and the parent
# takes the lock again when the suite is over.
set -u
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
STATE="${STATE:-$HOME/.local/state/visionocr-autonomous}"
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
case "$STATE" in /*) ;; *) STATE="$PWD/$STATE" ;; esac
case "$OCRLAB" in /*) ;; *) OCRLAB="$PWD/$OCRLAB" ;; esac
export VISIONOCR_STATE="$STATE" OCRLAB   # run-guarded.sh's names: both must check the same test.lock
here="$(cd "$(dirname "$0")" && pwd)"
H="${HYBRID_DIR:-$STATE/ocrlab/hybrid}"   # HYBRID_DIR: a scratch directory, for a smoke run
case "$H" in /*) ;; *) H="$PWD/$H" ;; esac
# HYBRID_COMBOS / HYBRID_PAGES: space-separated labels and sample ids to run, for a smoke run; unset, all of them.
only_combos=" ${HYBRID_COMBOS:-} " only_pages=" ${HYBRID_PAGES:-} "
TESTDOCS="${TESTDOCS:-$HOME/Claude/vision-ocr/testdocs}"
case "$TESTDOCS" in /*) ;; *) TESTDOCS="$PWD/$TESTDOCS" ;; esac
DOMAIN=vo-hybrid-gate   # the gate binary's name, so its UserDefaults domain
cmd="${1:-status}"
mkdir -p "$H/runs" "$H/pages" "$H/truth" "$H/readers"
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S')	$*" >> "$H/hybrid.log"; }
alive() { local p; p=$(cat "$H/hybrid.pid" 2>/dev/null); [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }
busy() { pgrep -x tests >/dev/null || [ -d "$STATE/test.lock" ]; }
# room <need_gb>: what run-guarded.sh asks before a model call (normal pressure, need_gb reclaimable, no tart VM),
# asked before the page's gate run, so a machine short of memory is waited out without re-running the page.
room() {
    local mb; mb=$(vm_stat | /usr/bin/awk -v ps="$(sysctl -n hw.pagesize)" '/Pages (free|inactive|speculative|purgeable):/ {
        gsub(/\./, "", $NF); s += $NF } END { printf "%d", s * ps / 1048576 }')
    [ "$(sysctl -n kern.memorystatus_vm_pressure_level)" -le 1 ] && [ "$mb" -ge $(($1 * 1024)) ] \
        && ! pgrep -f 'MacOS/tart[ ]run ' >/dev/null
}

# The combinations, cheapest first: label, arrangement, reader kind, model, prompt, extra options, need_gb, pages.
# Builds are ocr-bakeoff-bits' best for each model (OCR-BITS-2026-10-11.tsv): Falcon-OCR bf16 (8-bit loops),
# LightOnOCR-2 8-bit at 1540 px (fewer missed and added than 4-bit), Chandra OCR 2 oQ8 (the build replace was
# built on; oQ4 reads within 0.02 points of it, so ocr-hybrid-pick can take oQ4's figures from the bits table).
# Pages: `other` is every page but the newspapers, whose whole page three of six models could not read in
# ocr-lab-setup (swap or loops; bakeoff.sh reads them as crops only); `newspaper` is the newspapers alone, the
# pages the region arrangement was built for (ocr-hybrid-proto: (c)'s newspaper bands are its regions).
# PaddleOCR-VL is not one of the three; it is the region reader ocr-lab-round3 named, the reference for the others.
# ocr-compare-run widened Vision's, PaddleOCR-VL's and Falcon-OCR's regions to every page, and added paddle-fill;
# LightOnOCR's and Chandra's regions stay on newspapers, as ocr-hybrid-run ran them.
COMBOS='vision-off	off	-	-	-	-	-	all
falcon-align	align	text	tiiuae/Falcon-OCR	plain	-	4	other
falcon-fill	fill	text	tiiuae/Falcon-OCR	plain	-	4	all
lighton-align	align	text	mlx-community/LightOnOCR-2-1B-8bit	""	--max-side 1540	8	other
lighton-fill	fill	text	mlx-community/LightOnOCR-2-1B-8bit	""	--max-side 1540	8	all
vision-regions	regions	regions	vision	-	-	2	all
paddle-regions	regions	regions	mlx-community/PaddleOCR-VL-1.6-4bit	OCR:	-	4	all
paddle-fill	fill	text	mlx-community/PaddleOCR-VL-1.6-4bit	OCR:	-	4	all
falcon-regions	regions	regions	tiiuae/Falcon-OCR	plain	-	4	all
lighton-regions	regions	regions	mlx-community/LightOnOCR-2-1B-8bit	""	--max-side 1540	8	newspaper
chandra-fill	fill	text	mlx-community/chandra-ocr-2-oQ8	-	-	6	all
chandra-align	align	text	mlx-community/chandra-ocr-2-oQ8	-	-	6	other
chandra-replace	replace	blocks	mlx-community/chandra-ocr-2-oQ8	-	-	6	other
chandra-regions	regions	regions	mlx-community/chandra-ocr-2-oQ8	-	-	6	newspaper'
# Combinations with no run, and why; hybrid-table.py prints them as rows.
NOT_RUN='falcon-replace	Falcon-OCR writes no boxes, and replace places the model'"'"'s own blocks (hp-replace)
lighton-replace	LightOnOCR-2'"'"'s box build boxes only pictures, not text (hp-replace)
paddle-align	PaddleOCR-VL caps its input near 1 MP, so a whole page is read at a fraction of its scan (ocr-compare-run)
vision-align/fill/replace	Vision'"'"'s reading is what align, fill and replace mend; they need a model (hp-align)
paddle-replace	PaddleOCR-VL writes no boxes, and replace places the model'"'"'s own blocks (hp-replace)'
# The job's combinations and not-run rows: HYBRID_COMBOS_TSV's copy when `start` was given one (then nothing is
# "not run"), else COMBOS and NOT_RUN above.
combos() { if [ -s "$H/combos.src.tsv" ]; then /usr/bin/grep -v '^#' "$H/combos.src.tsv"; else echo "$COMBOS"; fi; }
not_run() { [ -s "$H/combos.src.tsv" ] || echo "$NOT_RUN"; }

case "$cmd" in
status)
    if alive; then echo "running, pid $(cat "$H/hybrid.pid")"; else echo "not running"; fi
    combos | while IFS='	' read -r label _; do
        d="$H/runs/$label"
        printf '%s\tok %s\tfailed %s\tskipped %s\n' "$label" \
            "$(cat "$d"/*/status 2>/dev/null | /usr/bin/grep -c '^ok')" \
            "$(cat "$d"/*/status 2>/dev/null | /usr/bin/grep -c '^failed')" \
            "$(cat "$d"/*/status 2>/dev/null | /usr/bin/grep -c '^skipped')"
    done
    exit 0 ;;
stop)
    alive || { echo "hybrid-run: not running"; exit 0; }
    g=$(ps -o pgid= -p "$(cat "$H/hybrid.pid")" | tr -d ' ')
    [ "$g" = "$(ps -o pgid= -p $$ | tr -d ' ')" ] && { echo "hybrid-run: the job shares this shell's process group; kill it by hand" >&2; exit 1; }
    kill -TERM -- "-$g" && echo "hybrid-run: sent TERM to process group $g"
    exit 0 ;;
start)
    alive && { echo "hybrid-run: already running (pid $(cat "$H/hybrid.pid"))" >&2; exit 1; }
    busy && { echo "hybrid-run: a suite runs or test.lock is held; not starting" >&2; exit 75; }
    root="$here/../.."
    sample="${HYBRID_SAMPLE:-$(ls "$root"/OCR-SAMPLE-*.tsv | tail -1)}"
    # From copies, so removing the worktree it was started from cannot pull its scripts or binaries away.
    rm -rf "$H/scripts"; mkdir -p "$H/scripts" "$H/bin"
    cp "$here"/*.sh "$here"/*.py "$here"/*.tsv "$here"/*.txt "$root/ops/autonomous/mac-heavy-lock.sh" "$H/scripts/" \
        && cp "$sample" "$H/sample.tsv" || exit 1
    rm -f "$H/combos.src.tsv"
    if [ -n "${HYBRID_COMBOS_TSV:-}" ]; then cp "$HYBRID_COMBOS_TSV" "$H/combos.src.tsv" || exit 1; fi
    b="$(mktemp -d -t vo-hybrid-build)" || exit 1
    mkdir -p "$b/g" "$b/h"; cp "$root/Tools/score-gate.swift" "$b/g/main.swift"; cp "$root/Tools/ux-harness.swift" "$b/h/main.swift"
    echo "hybrid-run: building the gate, helper and harness from $(cd "$root" && git rev-parse --short HEAD)"
    ( cd "$root" && T="$(uname -m)-apple-macos13.0" &&
      swiftc -O -o "$b/$DOMAIN" -target "$T" $(ls Sources/*.swift | /usr/bin/grep -v App.swift) "$b/g/main.swift" &&
      swiftc -O -o "$b/visionocr-recognise" -target "$T" \
          Sources/{Prefs,Runner,Recogniser,SearchableWriter,Flattener,JBIG2}.swift Helper/main.swift &&
      swiftc -O -o "$b/ux" "$b/h/main.swift" ) > "$H/build.log" 2>&1 \
        || { echo "hybrid-run: the tools do not build, see $H/build.log" >&2; exit 1; }
    mv -f "$b/$DOMAIN" "$b/visionocr-recognise" "$b/ux" "$H/bin/" && rm -rf "$b"
    (cd "$root" && git rev-parse --short HEAD) > "$H/bin/commit"
    export STATE OCRLAB TESTDOCS HYBRID_DIR="$H"   # absolute now; the detached run reads them again
    cd "$H" || exit 1
    "$OCRLAB/venv/bin/python" -c '
import os, sys
if os.fork(): sys.exit(0)
os.setsid()
if os.fork(): sys.exit(0)
fd = os.open(sys.argv[1], os.O_WRONLY | os.O_CREAT | os.O_APPEND); os.dup2(fd, 1); os.dup2(fd, 2)
os.dup2(os.open("/dev/null", os.O_RDONLY), 0)
os.execv("/bin/bash", ["/bin/bash", sys.argv[2], "run"])' "$H/hybrid.out" "$H/scripts/hybrid-run.sh"
    sleep 3; alive && echo "hybrid-run: started, pid $(cat "$H/hybrid.pid")" || { echo "hybrid-run: did not start; see $H/hybrid.out" >&2; exit 1; }
    exit 0 ;;
run) ;;
pages) ;;   # pages <label> <arrangement> <reader or -> <set> <need>: one combination's pages, run's child under HYBRID_HOLD=combo
*) echo "hybrid-run: unknown command $cmd" >&2; exit 2 ;;
esac

cd "$H" || exit 1
for t in "$DOMAIN" visionocr-recognise ux; do [ -x "$H/bin/$t" ] || { echo "hybrid-run: no $H/bin/$t; use start" >&2; exit 1; }; done
# `stop` reaches the gate run in flight: GNU timeout puts itself in a process group of its own, so the job's
# group signal misses it; run_one keeps its pid in `gate` and the trap signals its group and it.
gate=""
trap '[ -n "$gate" ] && kill -TERM -- "-$gate" "$gate" 2>/dev/null; exit 143' TERM INT HUP
if [ "$cmd" = run ]; then
    alive && { echo "hybrid-run: already running" >&2; exit 1; }
    busy && { echo "hybrid-run: a suite runs or test.lock is held; not starting" >&2; exit 75; }
    echo $$ > "$H/hybrid.pid"
    ( while kill -0 $$ 2>/dev/null; do touch "$STATE/engine.lock"; sleep 20; done ) &
    hb=$!
    trap 'kill $hb 2>/dev/null; rm -f "$STATE/engine.lock" "$H/hybrid.pid"; defaults delete "$DOMAIN" >/dev/null 2>&1; log "job ended"' EXIT
    log "job started, pid $$, tools from $(cat "$H/bin/commit" 2>/dev/null)"

    # Pages: cut once each. From a file, never through a pipe (bakeoff.sh: a piped `while` outlives a TERM).
    /usr/bin/grep -v '^#' "$H/sample.tsv" | tail -n +2 > "$H/sample.rows"
    while IFS='	' read -r id doc page route why class; do
        t="$STATE/truth/${doc%.pdf}/p$page"
        if [ -f "$t/transcript.txt" ] && [ ! -e "$H/truth/$id/p1" ]; then mkdir -p "$H/truth/$id"; ln -s "$t" "$H/truth/$id/p1"; fi
        [ -s "$H/pages/$id.pdf" ] && continue
        case "$doc" in owner/*) src="$STATE/owner-supplied/${doc#owner/}" ;; *) src="$TESTDOCS/$doc" ;; esac
        qpdf --empty --pages "$src" "$page" -- "$H/pages/$id.pdf" 2> "$H/pages/$id.qpdf.txt"
        q=$?   # 3 is warnings only
        if [ $q != 0 ] && [ $q != 3 ]; then rm -f "$H/pages/$id.pdf"; log "cut	$id	qpdf exit $q"; else log "cut	$id	$doc p$page"; fi
    done < "$H/sample.rows"
fi

# reader <label> <kind> <model> <prompt> <extra> <need> [layout]: the combination's wrapper, which the app runs as its
# reader; `layout` is the regions kind's detector (`-` or none is yolo).
reader() {
    local w="$H/readers/$1.sh" extra="$5" layout="${7:-yolo}"
    [ "$extra" = - ] && extra=""
    [ "$layout" = - ] && layout=yolo
    { echo '#!/bin/bash'
      printf 'export HYBRID_COMBO=%q HYBRID_KIND=%q HYBRID_MODEL=%q HYBRID_PROMPT=%q HYBRID_EXTRA=%q HYBRID_NEED=%q HYBRID_LAYOUT=%q OCRLAB=%q\n' \
          "$1" "$2" "$3" "$4" "$extra" "$6" "$layout" "$OCRLAB"
      printf 'exec %q "$@"\n' "$H/scripts/reader-hybrid.sh"; } > "$w.part" && chmod +x "$w.part" && mv "$w.part" "$w"
    echo "$w"
}

# run_one <label> <arrangement> <reader path or -> <id>
run_one() {
    local label=$1 arr=$2 rdr=$3 id=$4 d="$H/runs/$1/$4" secs rc reason app since; since=$(date +%s)
    [ -f "$d/status" ] && return 0
    [ -s "$H/pages/$id.pdf" ] || { mkdir -p "$d"; echo "skipped the page could not be cut" > "$d/status"; return 0; }
    while :; do
        rm -rf "$d"; mkdir -p "$d/in" "$d/pub" "$d/score"
        cp "$H/pages/$id.pdf" "$d/in/$id.pdf"
        defaults write "$DOMAIN" modelArrangement "$arr"
        if [ "$rdr" = - ]; then defaults delete "$DOMAIN" modelReader >/dev/null 2>&1; else defaults write "$DOMAIN" modelReader "$rdr"; fi
        # Under the machine-wide heavy lock, which every guarded model call inside inherits (MAC_HEAVY_HELD), so
        # a wait for Archive Suite's work is spent here and not inside the app's 600 s for the reader. The
        # clock starts once the lock is held.
        HYBRID_PAGE="$id" HYBRID_GUARDS="$d/guard.tsv" HYBRID_STATS="$d/stats.jsonl" HYBRID_KEEP="$d/keep" \
            VISIONOCR_HELPER="$H/bin/visionocr-recognise" "$H/scripts/mac-heavy-lock.sh" run --label "hybrid $label $id" -- \
            /bin/bash -c 'date +%s > "$1/t0"; shift; exec "$@"' _ "$d" $bound "$H/bin/$DOMAIN" "$d/in" "$d/pub" \
            > "$d/gate.log" 2>&1 < /dev/null &
        gate=$!
        wait "$gate"; rc=$?; gate=""
        secs=$(( $(date +%s) - $(cat "$d/t0" 2>/dev/null || date +%s) ))
        # The app's own seconds for the file (the gate's timings.tsv), without the gate's start and its pixel
        # verification, which cost about 19 s a page whatever the arrangement: the figure to set against Vision's.
        app=$(/usr/bin/awk -F'\t' 'NR == 2 {print $2}' "$d/pub/timings.tsv" 2>/dev/null); app=${app:--}
        # A guard refusal (reader-hybrid.sh's REFUSED row) is the machine, not the reader: wait for room and try
        # again, for at most 4 hours of wall time (each try re-runs the page's Vision pass too). Under a hold the
        # guard refuses while a suite is queued, which waits for this lock: give it back (75) and leave no status,
        # so the page is run again in the next hold; and wait for room ten minutes at most, for the same reason.
        if /usr/bin/grep -q '^REFUSED' "$d/guard.tsv" 2>/dev/null; then
            log "$label	$id	guard refused: $(/usr/bin/grep '^REFUSED' "$d/guard.tsv" | tail -1 | cut -f3 | cut -c1-120)"
            if [ "$cmd" = pages ] && busy; then rm -rf "$d"; log "$label	$id	a suite is queued: the lock is given back"; return 75; fi
            [ $(( $(date +%s) - since )) -ge 14400 ] && { echo "failed $app $secs the guard refused for 4 hours" > "$d/status"; break; }
            sleep 60; waited=60
            while ! room "${need_now:-4}"; do sleep 60; waited=$((waited + 60))
                [ "$cmd" = pages ] && [ "$waited" -ge 600 ] && { rm -rf "$d"; log "$label	$id	still short after ${waited} s: the lock is given back"; return 75; }
            done
            continue
        fi
        break
    done
    [ -f "$d/status" ] && { log "$label	$id	$(cat "$d/status")"; return 0; }
    local out; out=$(ls "$d/pub"/*.pdf 2>/dev/null | head -1)
    if [ -z "$out" ]; then
        # The app's reason for a file it did not publish is in the gate's log.txt (the model's log), not on its
        # stdout; keep its most telling line, and the outcome timings.tsv gives the file.
        reason=$(/usr/bin/grep -iE 'reader|took longer|cut short|fail|error|could not' "$d/pub/log.txt" 2>/dev/null \
            | /usr/bin/grep -v '^Done' | tail -1 | tr '\t' ' ' | cut -c1-300)
        [ -n "$reason" ] || reason=$(/usr/bin/awk -F'\t' 'NR == 2 {print $3}' "$d/pub/timings.tsv" 2>/dev/null | cut -c1-300)
        echo "failed $app $secs ${reason:-gate exit $rc, nothing published}" > "$d/status"
    else
        local truth=(); [ -e "$H/truth/$id/p1" ] && truth=(--truth "$H/truth/$id")
        "$H/bin/ux" ${truth[@]+"${truth[@]}"} "$d/in/$id.pdf" "$out" "$d/score" 1 > "$d/score/stdout.tsv" 2> "$d/score/stderr.txt" < /dev/null
        echo "ok $app $secs harness-exit $?" > "$d/status"
        rm -rf "$d/score/renders" "$d/score/pairs"   # the published PDF stays; any render can be made again
    fi
    rm -rf "$d/in"
    log "$label	$id	$(cat "$d/status")"
}

# No page's gate run may hang the night: 30 minutes is three times the slowest page's reader bound and Vision.
bound=""; [ -x /opt/homebrew/bin/timeout ] && bound="/opt/homebrew/bin/timeout 1800"

# run_pages <label> <arrangement> <reader path or -> <set> <need>: the combination's pages, in the sample's order;
# a page with a status is not run again. Returns 75 when, under HYBRID_HOLD=combo, a suite is queued or running.
run_pages() {
    local label=$1 arr=$2 rdr=$3 set=$4 need=$5 late=0 id doc page route why class d need_now
    while IFS='	' read -r id doc page route why class <&3; do
        case "$set" in
            other) [ "$route" = newspaper ] && continue ;;
            newspaper) [ "$route" = newspaper ] || continue ;;
        esac
        [ "$only_pages" = "  " ] || case "$only_pages" in *" $id "*) ;; *) continue ;; esac
        if busy; then
            [ "$cmd" = pages ] && { log "$label	a suite is queued or runs: the lock is given back"; return 75; }
            log "waiting: a suite runs"; while busy; do sleep 60; done
        fi
        d="$H/runs/$label/$id"
        if [ "$late" -ge 3 ] && [ ! -f "$d/status" ]; then
            mkdir -p "$d"; echo "skipped three pages in a row before it ran past the reader's time limit" > "$d/status"
            log "$label	$id	$(cat "$d/status")"; continue
        fi
        # The guard asks need_gb while the gate holds the page's images: wait for 1 GB more than that here.
        need_now=-; [ "$need" = - ] || need_now=$((need + 1))
        if [ "$need_now" != - ] && [ ! -f "$d/status" ] && ! room "$need_now"; then
            log "$label	$id	waiting for ${need_now} GB reclaimable and no VM"
            # Under a hold, ten minutes at most: the lock is not kept against others while memory is short.
            waited=0; while ! room "$need_now"; do sleep 60; waited=$((waited + 60))
                [ "$cmd" = pages ] && [ "$waited" -ge 600 ] && { log "$label	$id	still short after ${waited} s: the lock is given back"; return 75; }
            done
        fi
        run_one "$label" "$arr" "$rdr" "$id" < /dev/null || return $?
        # Late: the app's 600 s ran out, or the reader's own 540 s did (reader-hybrid.sh notes it in stats.jsonl).
        if /usr/bin/grep -qE 'took longer than|cut short' "$d/status" || /usr/bin/grep -q '"cut": "seconds"' "$d/stats.jsonl" 2>/dev/null
        then late=$((late + 1)); else case "$(cat "$d/status")" in ok*) late=0 ;; esac; fi
    done 3< "$H/sample.rows"
    return 0
}
# pages <label> <arrangement> <reader> <set> <need> [five more]...: each combination's pages in turn, in one hold.
if [ "$cmd" = pages ]; then
    shift; rc=0
    while [ $# -ge 5 ]; do
        log "$1	start"
        run_pages "$1" "$2" "$3" "$4" "$5" || { rc=$?; break; }
        log "$1	done"
        shift 5
    done
    exit $rc
fi

# A run limited by HYBRID_COMBOS writes only those, so the table has no rows for combinations it never ran.
combos | while IFS='	' read -r label rest; do
    [ "$only_combos" = "  " ] || case "$only_combos" in *" $label "*) ;; *) continue ;; esac
    printf '%s\t%s\n' "$label" "$rest"; done > "$H/combos.tsv"
# and only the not-run rows of the models among them (the label's part before the dash).
not_run | while IFS='	' read -r label why; do
    [ "$only_combos" = "  " ] || case "$only_combos" in *" ${label%%-*}-"*) ;; *) continue ;; esac
    printf '%s\t%s\n' "$label" "$why"; done > "$H/not-run.tsv"
# run_batch: the combinations gathered in `batch` (five fields each) under one hold of the lock (header: HYBRID_HOLD
# combo or group). A child that gave the lock back for a suite (75) is run again once the suite is over, and takes
# up where its status files end.
batch=() key=""
# pending: 0 when some page of the batch has no status yet, 1 when every one has (a resumed job: no lock for it).
pending() {
    local i=0 label set id doc page route why class
    while [ "$i" -lt "${#batch[@]}" ]; do
        label=${batch[$i]} set=${batch[$((i + 3))]}
        while IFS='	' read -r id doc page route why class; do
            case "$set" in
                other) [ "$route" = newspaper ] && continue ;;
                newspaper) [ "$route" = newspaper ] || continue ;;
            esac
            [ "$only_pages" = "  " ] || case "$only_pages" in *" $id "*) ;; *) continue ;; esac
            [ -f "$H/runs/$label/$id/status" ] || return 0
        done < "$H/sample.rows"
        i=$((i + 5))
    done
    return 1
}
run_batch() {
    [ "${#batch[@]}" -gt 0 ] || return 0
    local rc
    if ! pending; then
        /bin/bash "$H/scripts/hybrid-run.sh" pages "${batch[@]}" < /dev/null
        batch=(); return 0
    fi
    while :; do
        busy && { log "$key	waiting: a suite runs"; while busy; do sleep 60; done; }
        "$H/scripts/mac-heavy-lock.sh" run --label "hybrid $key" -- \
            /bin/bash "$H/scripts/hybrid-run.sh" pages "${batch[@]}" < /dev/null
        rc=$?; [ "$rc" = 75 ] || break
    done
    [ "$rc" = 0 ] || log "$key	pages exited $rc"
    batch=()
}
while IFS='	' read -r label arr kind model prompt extra need set layout <&4; do
    [ "$only_combos" = "  " ] || case "$only_combos" in *" $label "*) ;; *) continue ;; esac
    rdr=-; [ "$kind" = - ] || rdr=$(reader "$label" "$kind" "$model" "$prompt" "$extra" "$need" "${layout:-yolo}")
    case "${HYBRID_HOLD:-page}" in
    combo) key=$label; batch=("$label" "$arr" "$rdr" "$set" "$need"); run_batch ;;
    # group: consecutive combinations whose labels share the part after the first dash (layout-combos.tsv: one
    # reader's three detectors) run in one hold, so the lock changes hands a few times a job, not a few dozen.
    group) [ "${label#*-}" = "$key" ] || run_batch; key="${label#*-}"; batch+=("$label" "$arr" "$rdr" "$set" "$need") ;;
    *) log "$label	start"; run_pages "$label" "$arr" "$rdr" "$set" "$need"; log "$label	done" ;;
    esac
done 4< "$H/combos.tsv"
run_batch
log "all combinations done"
