#!/usr/bin/env bash
# prove-mac-heavy-lock.sh — one heavy job at a time on the Mac, shared with Archive Suite (QUEUE
# `mac-heavy-lock`, owner 2026-10-06 after the Mac froze with both projects' heavy work running at once).
#
# WHAT IT PROVES, against the real ops/autonomous/mac-heavy-lock.sh in a sandboxed lock directory, TWICE: once
# on its own fallback (VISIONOCR_HEAVY_DELEGATE empty) and once delegating to a SCRATCH COPY of the Agent
# Manager's bin/heavy-lock, with every path of both locks under the sandbox:
#   [1] takers from two different projects never hold it at once, and each writes its owner record;
#   [2] the same run against a MUTANT whose take always succeeds overlaps, so [1] can fail;
#   [3] a dead holder is reclaimed; a live one, or a taker that has not yet written its owner, is not;
#   [4] a waiter is visible to `waiting-under` from its ancestors only, keeps MAC_HEAVY_TOUCH fresh, and its
#       wait is unbounded unless --wait is given;
#   [5] run_tests.sh takes it around ./build/tests and not around its compiles, under test-lock.sh `run` (both
#       its own and the hook's reentrant form, which no longer take it themselves) and by hand; and
#       ops/ocrlab/run-guarded.sh takes it, including the copy the bake-off runs from $STATE/ocrlab/scripts;
#   [6] the holder forwards TERM to its command, keeps the caller's stdin and returns the command's status.
# Then, once:
#   [7] the delegate is chosen only when it is an executable file (the default path under $HOME included; EMPTY
#       forces the fallback), is told this project's name and label, passes exit codes through, and a delegated
#       taker and a fallback taker never overlap. Three mutants of the selection must each turn [7] red.
# The scratch copy comes from VISIONOCR_HEAVY_DELEGATE_SRC, else the installed manager under the real $HOME. With
# neither, the delegate passes are SKIPPED and say so. Nothing here touches the real ~/.local/state locks.
# The daemon side (a gate or session queued on it is neither timed out nor killed as wedged) is
# prove-gate-fix.sh [8], which already has the sandboxed daemon.
# It runs no suite, build or model. ~2 min.  USAGE: ops/autonomous/tests/prove-mac-heavy-lock.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OPS="$(cd "$HERE/.." && pwd)"
H="$OPS/mac-heavy-lock.sh"
[ -x "$H" ] || { echo "no helper at $H"; exit 2; }
AM_SRC="${VISIONOCR_HEAVY_DELEGATE_SRC:-${HOME:-}/Claude/Agent Manager/bin/heavy-lock}"
T="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
PASS=0; FAIL=0; SKIP=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOME="$T/home"; mkdir -p "$HOME"
export MAC_HEAVY_LOCK="$T/state/mac-heavy.lock" MAC_HEAVY_POLL=1
# The manager's own paths are sandboxed in both passes, and a fake sysctl keeps the machine's real memory
# pressure from making a delegated taker wait.
export AGENT_MANAGER_STATE="$T/am-state" HEAVY_LOCK_SYSCTL="$T/fake-sysctl"
unset MAC_HEAVY_HELD VISIONOCR_TEST_LOCK_HELD HEAVY_LOCK_FILE VISIONOCR_MAC_HEAVY
printf '#!/bin/sh\necho 1\n' > "$T/fake-sysctl"; chmod +x "$T/fake-sysctl"
L="$MAC_HEAVY_LOCK"
# A scratch tree run_tests.sh can run in, with a fake swiftc that records which locks each phase held ([5]).
. "$HERE/lib-fake-suite.sh"; FB="$T/fakebin"; fake_bin "$FB"; export SHELL="$FB/loginsh"
# test-lock.sh puts the system directories first on PATH; this puts the fakes back in front, in every bash below it.
printf 'pgrep() { return 1; }\nPATH="%s:$PATH"\n' "$FB" > "$T/no-pgrep.sh"
waitfor() { local end=$(( $(date +%s) + $2 )); while [ "$(date +%s)" -lt "$end" ]; do eval "$1" && return 0; sleep 0.2; done; return 1; }

# The scratch copy of the manager's helper, and a mutant of it whose take always succeeds.
AM="$T/am/heavy-lock"; AMMUT="$T/am/heavy-lock.mutant"; HAVE_AM=0
if [ -f "$AM_SRC" ]; then
  mkdir -p "$T/am"; cp "$AM_SRC" "$AM"; chmod +x "$AM"; HAVE_AM=1
  if [ "$(grep -cxF '        if not self.try_flock():' "$AM")" = 1 ]; then
    sed 's|^        if not self.try_flock():$|        return None  # MUTANT: every take succeeds\
&|' "$AM" > "$AMMUT"; chmod +x "$AMMUT"
  fi
fi

# A critical section that notices company: mkdir fails if another taker is inside.
cat > "$T/inside.sh" <<'EOF'
#!/bin/bash
mkdir "$1/in" 2>/dev/null || echo overlap >> "$1/overlap"
cat "$MAC_HEAVY_LOCK/owner" >> "$1/owners" 2>/dev/null
cat "$AGENT_MANAGER_STATE/heavy.owner" >> "$1/flock-owners" 2>/dev/null
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

# One pass of [1]-[6]. $1 is the mode: `fallback` (the helper's own mkdir lock) or `delegate` (the manager's copy).
prove() {
  local M="$1" C="$T/$1" rc dead hp parent unrelated gp kid
  mkdir -p "$C"; rm -rf "$L" "$L.waiting" "$AGENT_MANAGER_STATE"
  if [ "$M" = delegate ]; then
    export VISIONOCR_HEAVY_DELEGATE="$AM"
    RLOG="$AGENT_MANAGER_STATE/heavy.log"; RMSG="reclaimed the old lock from dead holder 'gone' (archive-suite, pid "
    NOTICE="'waiter' (pid [0-9]*) waiting for 'holder' (archive-suite"
  else
    export VISIONOCR_HEAVY_DELEGATE=""
    RLOG="$T/state/mac-heavy.log"; RMSG="reclaimed from dead holder 'gone' (archive-suite, pid "
    NOTICE="'waiter' waiting for the machine lock, held by 'holder' (archive-suite"
  fi
  rm -f "$RLOG"

  echo "[1 $M] takers from two projects never hold it at once"
  contend "$H" "$C/c1"
  [ "$(wc -l < "$C/c1/ran" 2>/dev/null | tr -d ' ')" = 6 ] && ok "all six takers ran" || bad "ran: $(cat "$C/c1/ran" 2>/dev/null | tr '\n' ' ')"
  [ ! -s "$C/c1/overlap" ] && ok "no two were inside at once" || bad "$(wc -l < "$C/c1/overlap") overlaps"
  grep -q '^project=archive-suite' "$C/c1/owners" && grep -q '^project=vision-ocr' "$C/c1/owners" \
    && [ "$(grep -c '^pid=[0-9]' "$C/c1/owners")" = 6 ] && [ "$(grep -c '^start=[0-9]' "$C/c1/owners")" = 6 ] \
    && ok "each holder wrote pid, project and start" || bad "owner records: $(tr '\n' ' ' < "$C/c1/owners" | cut -c1-200)"
  if [ "$M" = delegate ]; then
    [ "$(grep -c '^pid=[0-9]' "$C/c1/flock-owners" 2>/dev/null)" = 6 ] \
      && ok "each holder also held the manager's kernel lock (its heavy.owner, in the sandbox)" \
      || bad "the delegate was not used: heavy.owner seen $(grep -c '^pid=' "$C/c1/flock-owners" 2>/dev/null || echo 0) times"
  else
    [ ! -s "$C/c1/flock-owners" ] && [ ! -e "$AGENT_MANAGER_STATE/heavy.lock" ] \
      && ok "the fallback never touched the manager's lock" || bad "the fallback pass delegated"
  fi
  [ ! -d "$L" ] && ok "released at the end" || bad "lock left behind"

  echo "[2 $M] a mutant whose take always succeeds is caught"
  if [ "$M" = delegate ]; then
    if [ -x "$AMMUT" ] && ! cmp -s "$AM" "$AMMUT"; then
      export VISIONOCR_HEAVY_DELEGATE="$AMMUT"; contend "$H" "$C/c2"; export VISIONOCR_HEAVY_DELEGATE="$AM"
    else
      bad "the mutation of the manager's copy did not apply (its anchor is missing or not unique) — this section is vacuous"
    fi
  else
    sed 's|if mkdir "\$LOCK" 2>/dev/null; then|if mkdir -p "$LOCK" 2>/dev/null; then|' "$H" > "$C/mutant.sh"; chmod +x "$C/mutant.sh"
    cmp -s "$H" "$C/mutant.sh" && bad "the mutation did not apply — this section is vacuous"
    contend "$C/mutant.sh" "$C/c2"
  fi
  [ -s "$C/c2/overlap" ] && ok "the mutant overlapped ($(wc -l < "$C/c2/overlap" | tr -d ' ') times), so [1] can fail" || bad "the mutant never overlapped — [1] proves nothing"
  rm -rf "$L"

  echo "[3 $M] a dead holder is reclaimed; a live or half-written one is not"
  sleep 0 & dead=$!; wait "$dead"
  mkdir -p "$L"; printf 'pid=%s\nproject=archive-suite\nlabel=gone\nstart=1\n' "$dead" > "$L/owner"
  "$H" run --label reclaimer --wait 5 -- true 2>"$C/r.err"; rc=$?
  [ "$rc" = 0 ] && ok "a taker got past a dead holder" || bad "rc=$rc: $(cat "$C/r.err")"
  grep -qF "$RMSG$dead" "$RLOG" && ok "the reclaim is logged" || bad "log: $(cat "$RLOG" 2>/dev/null)"
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

  echo "[4 $M] a waiter is visible to its ancestors, keeps MAC_HEAVY_TOUCH fresh, and waits without a limit"
  MAC_HEAVY_PROJECT=archive-suite "$H" run --label holder -- sleep 7 & hp=$!
  waitfor '[ -s "$L/owner" ]' 5
  mkdir "$C/touched"; touch -t 202001010000 "$C/touched"
  bash -c 'MAC_HEAVY_TOUCH="$1" "$2" run --label waiter -- touch "$3"' _ "$C/touched" "$H" "$C/waiter.ran" 2>"$C/w.err" & parent=$!
  sleep 30 & unrelated=$!
  waitfor '[ -n "$(ls "$L.waiting" 2>/dev/null)" ]' 5
  "$H" waiting-under "$parent" && ok "waiting-under the waiter's parent: yes" || bad "waiting-under the parent said no"
  "$H" waiting-under "$unrelated" && bad "waiting-under an unrelated process said yes" || ok "waiting-under an unrelated process: no"
  grep -q "$NOTICE" "$C/w.err" && ok "the wait is announced, naming the holder" || bad "notice: $(cat "$C/w.err")"
  sleep 2
  [ "$(( $(date +%s) - $(stat -f %m "$C/touched") ))" -lt 5 ] && ok "MAC_HEAVY_TOUCH kept fresh while waiting" || bad "touched path not refreshed"
  "$H" status > "$C/status.out"; rc=$?
  grep -q "HELD by 'holder' (archive-suite" "$C/status.out" && grep -q 'label=waiter' "$C/status.out" && [ "$rc" = 1 ] \
    && ok "status names the holder and the waiter, and exits 1" || bad "status rc=$rc: $(cat "$C/status.out")"
  wait "$hp"; wait "$parent"
  [ -f "$C/waiter.ran" ] && ok "the waiter ran after a 7 s hold with no --wait (unbounded)" || bad "the waiter never ran"
  "$H" waiting-under "$$" && bad "still listed as waiting after it took the lock" || ok "no longer waiting once it ran"
  [ -z "$(ls "$L.waiting" 2>/dev/null)" ] && ok "its wait file is gone" || bad "wait files left: $(ls "$L.waiting")"
  "$H" status >/dev/null; rc=$?
  [ "$rc" = 0 ] && ok "status exits 0 once it is free" || bad "status rc=$rc on a free lock"
  { kill "$unrelated"; wait "$unrelated"; } 2>/dev/null

  echo "[5 $M] the suite's run phase (not its compiles) and the guarded model runs take it"
  export VISIONOCR_TEST_LOCK="$C/test.lock" VISIONOCR_SUITE_TIMINGS="$C/timings.tsv" VISIONOCR_STATE="$C/vstate"
  export FAKE_LOG="$C/fake.log" VISIONOCR_MAC_HEAVY="$H" VISIONOCR_TEST_CACHE=off VISIONOCR_SUITE_STAMP=off
  fake_tree "$OPS/../../run_tests.sh" "$C/tree"; : > "$FAKE_LOG"
  # test-lock.sh asks `pgrep -x tests` about the whole machine, where a real suite may be running.
  (cd "$C/tree" && PATH="$FB:$PATH" BASH_ENV="$T/no-pgrep.sh" bash "$OPS/test-lock.sh" run --label probe-suite -- ./run_tests.sh) >/dev/null 2>&1
  [ "$(grep -c '^compile .* heavy=no testlock=yes' "$FAKE_LOG")" = 3 ] && grep -q '^run tests .* heavy=yes label=probe-suite$' "$FAKE_LOG" \
    && ok "under test-lock.sh run, the suite holds mac-heavy around ./build/tests only, under the caller's label" \
    || bad "test-lock.sh run: $(tr '\n' ';' < "$FAKE_LOG" | cut -c1-300)"
  : > "$FAKE_LOG"
  (cd "$C/tree" && BASH_ENV="$T/no-pgrep.sh" VISIONOCR_TEST_LOCK_HELD=1 bash "$OPS/test-lock.sh" run --label "pre-commit 1" -- ./run_tests.sh) >/dev/null 2>&1
  [ "$(grep -c '^compile .* heavy=no' "$FAKE_LOG")" = 3 ] && grep -q '^run tests .* heavy=yes label=pre-commit 1$' "$FAKE_LOG" \
    && ok "…and under its reentrant form, which the pre-commit hook uses" || bad "reentrant: $(tr '\n' ';' < "$FAKE_LOG" | cut -c1-300)"
  VISIONOCR_TEST_LOCK_HELD=1 bash "$OPS/test-lock.sh" run --label bare -- sh -c '[ -d "$MAC_HEAVY_LOCK" ] && echo held || echo free' > "$C/tl3.out" 2>/dev/null
  BASH_ENV="$T/no-pgrep.sh" bash "$OPS/test-lock.sh" run --label bare2 -- sh -c '[ -d "$MAC_HEAVY_LOCK" ] && echo held || echo free' >> "$C/tl3.out" 2>/dev/null
  [ "$(tr '\n' ' ' < "$C/tl3.out")" = "free free " ] && ok "test-lock.sh run no longer takes it itself, in either form" || bad "test-lock.sh took it: $(tr '\n' ' ' < "$C/tl3.out")"
  unset FAKE_LOG VISIONOCR_MAC_HEAVY VISIONOCR_TEST_CACHE VISIONOCR_SUITE_STAMP
  export OCRLAB="$C/ocrlab"; mkdir -p "$VISIONOCR_STATE"
  MAC_HEAVY_PROJECT=archive-suite "$H" run --label holder -- sleep 4 & hp=$!
  waitfor '[ -s "$L/owner" ]' 5
  "$OPS/../ocrlab/run-guarded.sh" --need-gb 0 -- true 2>/dev/null & gp=$!
  waitfor 'grep -qs "label=run-guarded" "$L.waiting"/*' 3 && kill -0 "$gp" 2>/dev/null \
    && ok "run-guarded.sh waits on mac-heavy before anything else" || bad "run-guarded did not queue on the lock"
  wait "$hp"; wait "$gp"
  grep -q 'autonomous/mac-heavy-lock.sh' "$OPS/../ocrlab/bakeoff.sh" && ok "bakeoff.sh copies the helper beside its scripts" || bad "bakeoff.sh does not copy the helper"
  mkdir -p "$C/copy"; cp "$OPS/../ocrlab/run-guarded.sh" "$H" "$C/copy/"
  MAC_HEAVY_PROJECT=archive-suite "$H" run --label holder -- sleep 4 & hp=$!
  waitfor '[ -s "$L/owner" ]' 5
  "$C/copy/run-guarded.sh" --need-gb 0 -- true 2>"$C/copy.err" & gp=$!
  waitfor 'grep -qs "label=run-guarded" "$L.waiting"/*' 3 && ok "a copied run-guarded.sh (as the bake-off runs it) finds the helper beside it and queues" \
    || bad "the copied run-guarded did not queue: $(cat "$C/copy.err")"
  wait "$hp"; wait "$gp"
  unset VISIONOCR_TEST_LOCK VISIONOCR_SUITE_TIMINGS VISIONOCR_STATE OCRLAB

  echo "[6 $M] the holder passes signals, stdin and its command's status"
  "$H" run --label victim -- sleep 30 & hp=$!
  waitfor '[ -s "$L/owner" ]' 5; sleep 0.5
  kid="$(pgrep -P "$hp" sleep)"
  kill -TERM "$hp"
  waitfor '! kill -0 "$hp" 2>/dev/null' 5
  [ -n "$kid" ] && ! kill -0 "$kid" 2>/dev/null && ok "TERM to the holder's pid ended its command" || bad "command ${kid:-?} outlived its holder"
  [ ! -d "$L" ] && ok "…and released the lock" || bad "lock left after TERM"
  [ "$(echo through | "$H" run -- cat)" = through ] && ok "the command reads the caller's stdin" || bad "stdin lost"
  "$H" run -- sh -c 'exit 3'; rc=$?
  [ "$rc" = 3 ] && ok "run returns the command's own status" || bad "rc=$rc, not the command's 3"
}

prove fallback
if [ "$HAVE_AM" = 1 ]; then
  prove delegate
else
  echo "[1-6 delegate] SKIPPED: no Agent Manager helper at $AM_SRC (set VISIONOCR_HEAVY_DELEGATE_SRC to test one)"
  SKIP=$((SKIP+1))
fi

# [7] Which lock a take uses. $1 is the helper under test; prints one line per failed check, nothing if all hold.
# The command inside tells the two apart: the manager's heavy.owner exists only while the delegate holds its lock.
PROBE='if [ -s "$AGENT_MANAGER_STATE/heavy.owner" ]; then echo delegated; cat "$AGENT_MANAGER_STATE/heavy.owner"; else echo fallback; fi'
selection() {
  local h="$1" out rc d="$T/sel" pids i dg bogus inst="$HOME/Claude/Agent Manager/bin/heavy-lock"
  rm -rf "$d" "$L" "$AGENT_MANAGER_STATE"; mkdir -p "$d" "${inst%/*}"
  # The default path, with no override: a copy installed under (the sandbox's) $HOME is used, and is told this
  # project's name and a "<project>-<pid>" label when no --label is given.
  cp "$AM" "$inst"; chmod +x "$inst"
  out="$(unset VISIONOCR_HEAVY_DELEGATE MAC_HEAVY_PROJECT; "$h" run -- sh -c "$PROBE" 2>&1)"
  echo "$out" | head -1 | grep -qx delegated || echo "the installed default path was not used: $(echo "$out" | head -1)"
  echo "$out" | grep -qx 'project=vision-ocr' || echo "the delegate was not told project=vision-ocr: $(echo "$out" | tr '\n' ' ')"
  echo "$out" | grep -qx 'label=vision-ocr-[0-9]*' || echo "the default label is not <project>-<pid>: $(echo "$out" | tr '\n' ' ')"
  out="$(VISIONOCR_HEAVY_DELEGATE="$AM" "$h" run --label given -- sh -c "$PROBE" 2>&1)"
  echo "$out" | grep -qx 'label=given' || echo "a given --label did not win over the default: $(echo "$out" | tr '\n' ' ')"
  # EMPTY forces the fallback even with the default installed.
  out="$(VISIONOCR_HEAVY_DELEGATE= "$h" run -- sh -c "$PROBE" 2>&1)"
  [ "$out" = fallback ] || echo "an empty VISIONOCR_HEAVY_DELEGATE did not force the fallback: $out"
  # Not executable, missing, or a directory: the fallback, with the command still run under the old lock.
  cp "$AM" "$d/noexec"; chmod -x "$d/noexec"; mkdir "$d/adir"
  for bogus in "$d/noexec" "$d/missing" "$d/adir"; do
    out="$(VISIONOCR_HEAVY_DELEGATE="$bogus" "$h" run --label fb -- sh -c "$PROBE; cat \"\$MAC_HEAVY_LOCK/owner\"" 2>&1)"; rc=$?
    [ "$rc" = 0 ] && echo "$out" | head -1 | grep -qx fallback && echo "$out" | grep -qx 'label=fb' \
      || echo "a delegate at ${bogus##*/} did not fall back to the old lock (rc=$rc): $(echo "$out" | tr '\n' ' ' | cut -c1-160)"
  done
  # Arguments and exit codes pass through unchanged.
  VISIONOCR_HEAVY_DELEGATE="$AM" "$h" waiting-under notapid 2>/dev/null; rc=$?
  [ "$rc" = 2 ] || echo "waiting-under with a bad pid exited $rc through the delegate, not 2"
  VISIONOCR_HEAVY_DELEGATE="$AM" "$h" run --wait 0 -- sh -c 'exit 5' 2>/dev/null; rc=$?
  [ "$rc" = 5 ] || echo "run through the delegate exited $rc, not the command's 5"
  # A delegated taker and a fallback taker (an un-switched copy, as Archive Suite's may still be) never overlap.
  mkdir -p "$d/mix"; pids=""
  for i in 1 2 3 4 5 6; do
    if [ $((i % 2)) = 0 ]; then dg="$AM"; else dg=""; fi
    VISIONOCR_HEAVY_DELEGATE="$dg" "$h" run --label "mix $i" -- "$T/inside.sh" "$d/mix" 2>/dev/null & pids="$pids $!"
  done
  wait $pids
  [ "$(wc -l < "$d/mix/ran" 2>/dev/null | tr -d ' ')" = 6 ] && [ ! -s "$d/mix/overlap" ] \
    || echo "delegated and fallback takers overlapped or did not all run: ran=$(wc -l < "$d/mix/ran" 2>/dev/null | tr -d ' ') overlap=$(wc -l < "$d/mix/overlap" 2>/dev/null | tr -d ' ')"
  rm -f "$inst"
  return 0
}

echo "[7] the delegate is used only when it is an executable file, and keeps this project's defaults"
if [ "$HAVE_AM" = 1 ]; then
  unset VISIONOCR_HEAVY_DELEGATE
  out="$(selection "$H")"
  [ -z "$out" ] && ok "every selection check holds on the real helper" || { bad "selection:"; echo "$out" | sed 's/^/        /'; }
  # Each mutant breaks one part of the selection and must turn a check above red. Its anchor must occur once.
  mutant() {   # $1 name, $2 anchor (a fixed string), $3 its replacement
    local m="$T/sel-$1.sh" n
    n="$(grep -cF -- "$2" "$H")"
    [ "$n" = 1 ] || { bad "mutant $1: its anchor occurs $n times, not once — not applied"; return; }
    /usr/bin/python3 -c 'import sys; s=open(sys.argv[1]).read(); open(sys.argv[2],"w").write(s.replace(sys.argv[3],sys.argv[4],1))' "$H" "$m" "$2" "$3"
    chmod +x "$m"
    cmp -s "$H" "$m" && { bad "mutant $1: the file did not change — not applied"; return; }
    [ -n "$(selection "$m")" ] && ok "mutant $1 is caught" || bad "mutant $1 SURVIVED"
  }
  mutant never-delegates 'if [ -n "$HEAVY_DELEGATE" ] && [ -f' 'if false && [ -n "$HEAVY_DELEGATE" ] && [ -f'
  mutant no-exec-check ' && [ -x "$HEAVY_DELEGATE" ]; then' '; then'
  mutant no-project-default 'MAC_HEAVY_PROJECT="${MAC_HEAVY_PROJECT:-vision-ocr}" MAC_HEAVY_POLL' 'MAC_HEAVY_PROJECT="${MAC_HEAVY_PROJECT:-}" MAC_HEAVY_POLL'
else
  echo "  SKIPPED: no Agent Manager helper at $AM_SRC"
  SKIP=$((SKIP+1))
fi

echo ""
echo "=================== $PASS passed, $FAIL failed, $SKIP sections skipped ==================="
[ "$FAIL" = 0 ]
