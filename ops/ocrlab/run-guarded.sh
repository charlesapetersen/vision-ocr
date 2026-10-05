#!/bin/bash
# ops/ocrlab/run-guarded.sh — run ONE OCR-model process under a memory guard.
#
#   run-guarded.sh [--label L] [--rss-gb 12] [--swap-gb 2] [--every 2] [--need-gb 4] -- <cmd> [args…]
#
# Samples the process tree every 2 s and kills it (TERM, then KILL after 5 s) when any of these holds:
#   * its memory, summed over the tree and taken as the larger of RSS and the kernel's
#     physical footprint, passes --rss-gb (12 GB, owner 2026-10-02);
#   * the kernel's memory pressure level reaches critical;
#   * swap in use has grown by more than --swap-gb since the start.
# Memory pressure is read from `sysctl kern.memorystatus_vm_pressure_level` (1 normal, 2 warn,
# 4 critical), the level `memory_pressure` reports. `memory_pressure` itself is NOT run: with no
# arguments it allocates memory until told to stop, which is the opposite of a guard.
#
# Refuses to start while a test suite runs (`pgrep -x tests`), the suite lock is held, a tart VM runs, or
# another guarded run is live; one model process at a time, machine-wide. Also refuses when memory
# pressure is above normal or under --need-gb is reclaimable, so a trip measures the model, not the load.
#
# Appends one row per run to $OCRLAB/guard.tsv and prints the same row on stderr:
#   date label exit seconds peak_mb peak_footprint_mb swap_growth_mb max_pressure killed_reason cmd
# Exit status is the command's, or 137 when the guard killed it, or 75 when it refused to start.
set -u
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
OCRLAB="${OCRLAB:-$HOME/.local/share/visionocr-ocrlab}"
STATE="${VISIONOCR_STATE:-$HOME/.local/state/visionocr-autonomous}"
label="-" rss_gb=12 swap_gb=2 every=2 need_gb=4
while [ $# -gt 0 ]; do
    case "$1" in
        --label) label="$2"; shift 2 ;;
        --rss-gb) rss_gb="$2"; shift 2 ;;
        --swap-gb) swap_gb="$2"; shift 2 ;;
        --every) every="$2"; shift 2 ;;
        --need-gb) need_gb="$2"; shift 2 ;;
        --) shift; break ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "run-guarded: unknown option $1" >&2; exit 2 ;;
    esac
done
[ $# -gt 0 ] || { echo "run-guarded: no command" >&2; exit 2; }
mkdir -p "$OCRLAB"

if pgrep -x tests >/dev/null; then echo "run-guarded: a test suite is running; refusing" >&2; exit 75; fi
# A tart VM (another project's GUI runner) holds 3+ GB; one started mid-run on 2026-10-04 and tripped the
# swap limit under a 2.5 GB model.
if pgrep -f 'tart run' >/dev/null; then echo "run-guarded: a tart VM is running; refusing" >&2; exit 75; fi
if [ -d "$STATE/test.lock" ]; then echo "run-guarded: $STATE/test.lock is held; refusing" >&2; exit 75; fi
swap_mb() { sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+)M.*/\1/' | cut -d. -f1; }
pressure() { sysctl -n kern.memorystatus_vm_pressure_level; }
# Every pid in the tree rooted at $1.
tree() {
    local all; all=$(ps -A -o pid=,ppid=)
    local want=" $1 " grew=1
    while [ $grew = 1 ]; do
        grew=0
        while read -r p pp; do
            case "$want" in *" $pp "*) case "$want" in *" $p "*) ;; *) want="$want$p "; grew=1 ;; esac ;; esac
        done <<< "$all"
    done
    echo $want
}
# Physical footprint in MB of one pid, as `footprint` reports it (Metal buffers included).
footprint_mb() {
    footprint -p "$1" 2>/dev/null | awk '/Footprint:/ { for (i = 1; i < NF; i++) if ($i == "Footprint:") {
        v = $(i+1); u = $(i+2); if (u ~ /^G/) v *= 1024; else if (u ~ /^K/) v /= 1024; else if (u == "B") v = 0
        printf "%d\n", v; exit } }'
}

# Headroom: free + inactive + speculative + purgeable pages, what the kernel can hand over without swapping.
avail_mb=$(vm_stat | awk -v ps="$(sysctl -n hw.pagesize)" '/Pages (free|inactive|speculative|purgeable):/ {
    gsub(/\./, "", $NF); s += $NF } END { printf "%d", s * ps / 1048576 }')
if [ "$(sysctl -n kern.memorystatus_vm_pressure_level)" -gt 1 ] || [ "$avail_mb" -lt $((need_gb * 1024)) ]; then
    echo "run-guarded: memory pressure above normal or only ${avail_mb} MB reclaimable (need ${need_gb} GB); refusing" >&2
    exit 75
fi
lock="$OCRLAB/guard.lock"
if ! mkdir "$lock" 2>/dev/null; then
    other=$(cat "$lock/pid" 2>/dev/null)
    # An empty pid file is a guard between its mkdir and its write: live, unless the lock is old.
    if { [ -n "$other" ] && kill -0 "$other" 2>/dev/null; } ||
       { [ -z "$other" ] && [ $(( $(date +%s) - $(stat -f %m "$lock") )) -lt 60 ]; }; then
        echo "run-guarded: guarded run ${other:-starting} is live; refusing" >&2; exit 75
    fi
    # Stale lock from a dead guard. Taking it by rename, not rm + mkdir, lets only one guard win.
    mv "$lock" "$lock.stale.$$" 2>/dev/null && rm -rf "$lock.stale.$$"
    mkdir "$lock" 2>/dev/null || { echo "run-guarded: lost the lock race; refusing" >&2; exit 75; }
fi
echo $$ > "$lock/pid"
child=""
# Whatever ends the guard (TERM from a caller, the Bash tool's time cap, ^C) takes the model with it.
cleanup() { [ -n "$child" ] && kill -KILL $(tree "$child") 2>/dev/null; rm -rf "$lock"; }
trap cleanup EXIT
trap 'exit 143' TERM INT HUP

limit_mb=$((rss_gb * 1024)) swap_limit=$((swap_gb * 1024))
swap0=$(swap_mb) start=$(date +%s)
"$@" &
child=$!
pids=$child
peak=0 peakfp=0 maxp=$(pressure) growth=0 killed="-"
while kill -0 "$child" 2>/dev/null; do
    pids=$(tree "$child")
    rss=$(ps -o rss= -p "$(echo $pids | tr ' ' ',')" 2>/dev/null | awk '{s+=$1} END {printf "%d", s/1024}')
    # RSS alone is blind to MLX: a 3 GB Metal array read 30 MB of RSS and 3,087 MB of footprint
    # (measured 2026-10-04). So the footprint is summed over the whole tree on every sample.
    fp=0
    for q in $pids; do f=$(footprint_mb "$q"); fp=$((fp + ${f:-0})); done
    [ "$fp" -gt "$peakfp" ] && peakfp=$fp
    [ "${rss:-0}" -gt "$peak" ] && peak=$rss
    p=$(pressure); [ "$p" -gt "$maxp" ] && maxp=$p
    growth=$(( $(swap_mb) - swap0 ))
    use=$peak; [ "$peakfp" -gt "$use" ] && use=$peakfp
    if [ "$use" -gt "$limit_mb" ]; then killed="memory_${use}MB"
    elif [ "$p" -ge 4 ]; then killed="pressure_critical"
    elif [ "$growth" -gt "$swap_limit" ]; then killed="swap_grew_${growth}MB"
    fi
    if [ "$killed" != "-" ]; then
        # KILL the pids seen before TERM as well as a fresh walk: once the child dies, its children are
        # re-parented to launchd and the walk no longer finds them (verified 2026-10-04).
        kill -TERM $pids 2>/dev/null; sleep 5; kill -KILL $pids $(tree "$child") 2>/dev/null
        break
    fi
    sleep "$every"
done
wait "$child"; rc=$?
# Children the main process left behind (a server, a worker) are not watched once it exits: end them.
kill -KILL $pids 2>/dev/null
child=""
[ "$killed" != "-" ] && rc=137
secs=$(( $(date +%s) - start ))
row="$(date '+%Y-%m-%dT%H:%M:%S')	$label	$rc	$secs	$peak	$peakfp	$growth	$maxp	$killed	$*"
echo "$row" >> "$OCRLAB/guard.tsv"
echo "GUARD	$row" >&2
exit $rc
