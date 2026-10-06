#!/usr/bin/env bash
# prove-mac-heavy-lock.sh — one heavy job at a time on the Mac, shared with Archive Suite (QUEUE
# `mac-heavy-lock`, owner 2026-10-06 after the Mac froze with both projects' heavy work running at once).
#
# WHAT IT PROVES, against the real ops/autonomous/mac-heavy-lock.sh in a sandboxed lock directory:
#   [1] takers from two different projects never hold it at once, and each writes its owner record;
#   [2] the same run against a MUTANT whose take always succeeds overlaps, so [1] can fail;
#   [3] a dead holder is reclaimed; a live one, or a taker that has not yet written its owner, is not;
#   [4] a waiter is visible to `waiting-under` from its ancestors only, keeps MAC_HEAVY_TOUCH fresh, and its
#       wait is unbounded unless --wait is given;
#   [5] test-lock.sh `run` (both its own and the hook's reentrant form) and ops/ocrlab/run-guarded.sh take it,
#       including the copy the bake-off runs from $STATE/ocrlab/scripts;
#   [6] the holder forwards TERM to its command and keeps the caller's stdin.
# The daemon side (a gate or session queued on it is neither timed out nor killed as wedged) is
# prove-gate-fix.sh [8], which already has the sandboxed daemon.
# It runs no suite, build or model. ~40 s.  USAGE: ops/autonomous/tests/prove-mac-heavy-lock.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OPS="$(cd "$HERE/.." && pwd)"
H="$OPS/mac-heavy-lock.sh"
[ -x "$H" ] || { echo "no helper at $H"; exit 2; }
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOME="$T/home"; mkdir -p "$HOME"
export MAC_HEAVY_LOCK="$T/state/mac-heavy.lock" MAC_HEAVY_POLL=1
unset MAC_HEAVY_HELD VISIONOCR_TEST_LOCK_HELD
L="$MAC_HEAVY_LOCK"
waitfor() { local end=$(( $(date +%s) + $2 )); while [ "$(date +%s)" -lt "$end" ]; do eval "$1" && return 0; sleep 0.2; done; return 1; }

# A critical section that notices company: mkdir fails if another taker is inside.
cat > "$T/inside.sh" <<'EOF'
#!/bin/bash
mkdir "$1/in" 2>/dev/null || echo overlap >> "$1/overlap"
cat "$MAC_HEAVY_LOCK/owner" >> "$1/owners" 2>/dev/null
sleep 0.4
echo "$MAC_HEAVY_PROJECT" >> "$1/ran"
rmdir "$1/in" 2>/dev/null
EOF
chmod +x "$T/inside.sh"
contend() {   # $1 helper, $2 scratch dir: six takers, alternating projects, started together
  mkdir -p "$2"; local i pids=""
  for i in 1 2 3 4 5 6; do
    if [ $((i % 2)) = 0 ]; then p=archive-suite; else p=vision-ocr; fi
    MAC_HEAVY_PROJECT=$p "$1" run --label "taker $i" -- "$T/inside.sh" "$2" 2>/dev/null & pids="$pids $!"
  done
  wait $pids
}

echo "[1] takers from two projects never hold it at once"
contend "$H" "$T/c1"
[ "$(wc -l < "$T/c1/ran" 2>/dev/null | tr -d ' ')" = 6 ] && ok "all six takers ran" || bad "ran: $(cat "$T/c1/ran" 2>/dev/null | tr '\n' ' ')"
[ ! -s "$T/c1/overlap" ] && ok "no two were inside at once" || bad "$(wc -l < "$T/c1/overlap") overlaps"
grep -q '^project=archive-suite' "$T/c1/owners" && grep -q '^project=vision-ocr' "$T/c1/owners" \
  && [ "$(grep -c '^pid=[0-9]' "$T/c1/owners")" = 6 ] && [ "$(grep -c '^start=[0-9]' "$T/c1/owners")" = 6 ] \
  && ok "each holder wrote pid, project and start" || bad "owner records: $(tr '\n' ' ' < "$T/c1/owners" | cut -c1-200)"
[ ! -d "$L" ] && ok "released at the end" || bad "lock left behind"

echo "[2] a mutant whose take always succeeds is caught"
sed 's|if mkdir "\$LOCK" 2>/dev/null; then|if mkdir -p "$LOCK" 2>/dev/null; then|' "$H" > "$T/mutant.sh"; chmod +x "$T/mutant.sh"
cmp -s "$H" "$T/mutant.sh" && bad "the mutation did not apply — this section is vacuous"
contend "$T/mutant.sh" "$T/c2"
[ -s "$T/c2/overlap" ] && ok "the mutant overlapped ($(wc -l < "$T/c2/overlap" | tr -d ' ') times), so [1] can fail" || bad "the mutant never overlapped — [1] proves nothing"
rm -rf "$L"

echo "[3] a dead holder is reclaimed; a live or half-written one is not"
sleep 0 & dead=$!; wait "$dead"
mkdir -p "$L"; printf 'pid=%s\nproject=archive-suite\nlabel=gone\nstart=1\n' "$dead" > "$L/owner"
"$H" run --label reclaimer --wait 5 -- true 2>"$T/r.err"; rc=$?
[ "$rc" = 0 ] && ok "a taker got past a dead holder" || bad "rc=$rc: $(cat "$T/r.err")"
grep -q "reclaimed from dead holder 'gone' (archive-suite, pid $dead" "$T/state/mac-heavy.log" && ok "the reclaim is logged" || bad "log: $(cat "$T/state/mac-heavy.log" 2>/dev/null)"
mkdir -p "$L"
"$H" run --label early --wait 2 -- true 2>/dev/null; rc=$?
[ "$rc" = 4 ] && [ -d "$L" ] && ok "a fresh lock with no owner yet is left alone" || bad "rc=$rc, lock $( [ -d "$L" ] && echo kept || echo removed)"
touch -t 202001010000 "$L"
"$H" run --label late --wait 5 -- true 2>/dev/null; rc=$?
[ "$rc" = 0 ] && ok "an ownerless lock over 60 s old is reclaimed" || bad "rc=$rc"
mkdir -p "$L"; printf 'pid=%s\nproject=archive-suite\nlabel=recycled\nstart=1000\n' "$$" > "$L/owner"
"$H" run --label after-recycle --wait 5 -- true 2>/dev/null; rc=$?
[ "$rc" = 0 ] && ok "a live pid that started after the lock was taken (recycled) does not hold it" || bad "rc=$rc"
MAC_HEAVY_PROJECT=archive-suite "$H" run --label holder -- sleep 4 & hp=$!
waitfor '[ -s "$L/owner" ]' 5
"$H" run --label impatient --wait 1 -- true 2>/dev/null; rc=$?
[ "$rc" = 4 ] && ok "a live holder from the other project is not reclaimed (--wait 1 gave up)" || bad "rc=$rc"
wait "$hp"

echo "[4] a waiter is visible to its ancestors, keeps MAC_HEAVY_TOUCH fresh, and waits without a limit"
MAC_HEAVY_PROJECT=archive-suite "$H" run --label holder -- sleep 7 & hp=$!
waitfor '[ -s "$L/owner" ]' 5
mkdir "$T/touched"; touch -t 202001010000 "$T/touched"
bash -c 'MAC_HEAVY_TOUCH="$1" "$2" run --label waiter -- touch "$3"' _ "$T/touched" "$H" "$T/waiter.ran" 2>"$T/w.err" & parent=$!
sleep 30 & unrelated=$!
waitfor '[ -n "$(ls "$L.waiting" 2>/dev/null)" ]' 5
"$H" waiting-under "$parent" && ok "waiting-under the waiter's parent: yes" || bad "waiting-under the parent said no"
"$H" waiting-under "$unrelated" && bad "waiting-under an unrelated process said yes" || ok "waiting-under an unrelated process: no"
grep -q "'waiter' waiting for the machine lock, held by 'holder' (archive-suite" "$T/w.err" && ok "the wait is announced, naming the holder" || bad "notice: $(cat "$T/w.err")"
sleep 2
[ "$(( $(date +%s) - $(stat -f %m "$T/touched") ))" -lt 5 ] && ok "MAC_HEAVY_TOUCH kept fresh while waiting" || bad "touched path not refreshed"
"$H" status > "$T/status.out"
grep -q "HELD by 'holder' (archive-suite" "$T/status.out" && grep -q 'label=waiter' "$T/status.out" && ok "status names the holder and the waiter" || bad "status: $(cat "$T/status.out")"
wait "$hp"; wait "$parent"
[ -f "$T/waiter.ran" ] && ok "the waiter ran after a 7 s hold with no --wait (unbounded)" || bad "the waiter never ran"
"$H" waiting-under "$$" && bad "still listed as waiting after it took the lock" || ok "no longer waiting once it ran"
[ -z "$(ls "$L.waiting" 2>/dev/null)" ] && ok "its wait file is gone" || bad "wait files left: $(ls "$L.waiting")"
{ kill "$unrelated"; wait "$unrelated"; } 2>/dev/null

echo "[5] the suite lock and the guarded model runs take it"
export VISIONOCR_TEST_LOCK="$T/test.lock" VISIONOCR_SUITE_TIMINGS="$T/timings.tsv"
"$OPS/test-lock.sh" run --label probe-suite -- cat "$L/owner" > "$T/tl.out" 2>/dev/null
grep -q '^label=probe-suite' "$T/tl.out" && ok "test-lock.sh run holds mac-heavy around its command" || bad "owner seen inside: $(cat "$T/tl.out")"
VISIONOCR_TEST_LOCK_HELD=1 "$OPS/test-lock.sh" run --label "pre-commit 1" -- cat "$L/owner" > "$T/tl2.out" 2>/dev/null
grep -q '^label=pre-commit 1' "$T/tl2.out" && ok "…and so does its reentrant form, which the pre-commit hook uses" || bad "reentrant: $(cat "$T/tl2.out")"
export VISIONOCR_STATE="$T/vstate" OCRLAB="$T/ocrlab"; mkdir -p "$VISIONOCR_STATE"
MAC_HEAVY_PROJECT=archive-suite "$H" run --label holder -- sleep 4 & hp=$!
waitfor '[ -s "$L/owner" ]' 5
"$OPS/../ocrlab/run-guarded.sh" --need-gb 0 -- true 2>/dev/null & gp=$!
waitfor 'grep -qs "label=run-guarded" "$L.waiting"/*' 3 && kill -0 "$gp" 2>/dev/null \
  && ok "run-guarded.sh waits on mac-heavy before anything else" || bad "run-guarded did not queue on the lock"
wait "$hp"; wait "$gp"
grep -q 'autonomous/mac-heavy-lock.sh' "$OPS/../ocrlab/bakeoff.sh" && ok "bakeoff.sh copies the helper beside its scripts" || bad "bakeoff.sh does not copy the helper"
mkdir -p "$T/copy"; cp "$OPS/../ocrlab/run-guarded.sh" "$H" "$T/copy/"
MAC_HEAVY_PROJECT=archive-suite "$H" run --label holder -- sleep 4 & hp=$!
waitfor '[ -s "$L/owner" ]' 5
"$T/copy/run-guarded.sh" --need-gb 0 -- true 2>"$T/copy.err" & gp=$!
waitfor 'grep -qs "label=run-guarded" "$L.waiting"/*' 3 && ok "a copied run-guarded.sh (as the bake-off runs it) finds the helper beside it and queues" \
  || bad "the copied run-guarded did not queue: $(cat "$T/copy.err")"
wait "$hp"; wait "$gp"

echo "[6] the holder passes signals and stdin to its command"
"$H" run --label victim -- sleep 30 & hp=$!
waitfor '[ -s "$L/owner" ]' 5; sleep 0.5
kid="$(pgrep -P "$hp" sleep)"
kill -TERM "$hp"
waitfor '! kill -0 "$hp" 2>/dev/null' 5
[ -n "$kid" ] && ! kill -0 "$kid" 2>/dev/null && ok "TERM to the holder's pid ended its command" || bad "command ${kid:-?} outlived its holder"
[ ! -d "$L" ] && ok "…and released the lock" || bad "lock left after TERM"
[ "$(echo through | "$H" run -- cat)" = through ] && ok "the command reads the caller's stdin" || bad "stdin lost"

echo ""
echo "=================== $PASS passed, $FAIL failed ==================="
[ "$FAIL" = 0 ]
