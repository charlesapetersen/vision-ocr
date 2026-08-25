#!/usr/bin/env bash
# prove-test-lock.sh — prove-the-mechanism harness for ops/autonomous/test-lock.sh.
#
# WHY IT IS COMMITTED: this lock is the only thing standing between an unattended daemon and the failure
# CLAUDE.md names first — two suites at once, which corrupt BOTH (build/tests has no bundle id, so every
# worktree shares ~/Library/Preferences/tests.plist and a second run's resetPrefs() wipes the first's keys
# mid-run). The symptom is a green-looking run with a few unrelated failures: evidence that is WRONG rather
# than absent. A leaked lock is the other side of the same coin — it blocks the owner's own `./run_tests.sh`
# for up to MAXAGE (90 min) with no visible cause. Neither is something to take on trust.
#
# FULLY SANDBOXED: its own $HOME, its own $VISIONOCR_TEST_LOCK path under a temp dir, and NO suite, build or
# swiftc anywhere — every "command" it locks around is /bin/sh or /bin/sleep.
#
# ⚠️ THE MACHINE-STATE PROBLEM, and how this handles it. test-lock.sh detects an out-of-band suite with
# `pgrep -x tests`, which matches any process NAMED `tests` ON THE WHOLE MACHINE. A real suite may well be
# running while this harness executes (the owner works interactively in the primary checkout), and then
# EVERY acquire legitimately refuses — so a harness that just called the script would go red for reasons
# that have nothing to do with the code. A harness that only passes on an idle machine is the instrument
# that lies, which is the exact failure this project's process exists to prevent. So:
#   * the BULK of the assertions run with `pgrep` INTERPOSED (a stub that reports "no suite"), which makes
#     them deterministic whatever else is on the machine;
#   * section [10] then exercises the REAL `pgrep -x tests` against a process this harness genuinely names
#     `tests` inside the sandbox (a copy of /bin/sleep), which is true regardless of machine state — extra
#     real matches only reinforce it. That process is deliberately short-lived (about a second): while it
#     lives, any other test-lock caller on this machine would politely yield to it.
#   * the one converse — "the real detector reports NO suite" — cannot be made deterministic, so it is
#     asserted only when the machine is in fact idle and SKIPPED, loudly, when it is not.
#
# ⚠️ Interposition is by BASH_ENV shell function, not by $PATH: test-lock.sh line 46 re-prepends
# /usr/bin:/bin to PATH itself, so a $T/bin/pgrep stub would be shadowed by the real one. preflight() proves
# the interposition works and aborts if it does not.
#
# USAGE:  ops/autonomous/tests/prove-test-lock.sh [path/to/test-lock.sh]
# EXPECTED RESULT: 71 passed, 0 failed, 0 skipped — on an IDLE machine with a working process tree.
# ⚠️ THERE ARE THREE SKIP ARMS, not one, and this line used to name only the first while the count beside it
# had been updated twice. They are: [10]'s converse ("with no suite on the machine, the real detector reports
# free"), which is undecidable while a real suite runs; [12]'s pid-chain arm, if the three-deep helper chain
# cannot be built; and [12]'s real end-to-end arm, if the real `pgrep` cannot see both `exec -a tests`
# processes. Each emits ONE skip per assertion it stands in for, named the same, so the total is 71 either way
# — see the note on [12]'s `else`. A skip is a loud SKIP, never a quiet pass.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LOCKSH="${1:-$HERE/../test-lock.sh}"
[ -f "$LOCKSH" ] || { echo "no test-lock.sh at $LOCKSH"; exit 2; }
T="$(mktemp -d)"

# Leak-proof cleanup. Every helper process (fake lock holders, the fake `tests`, a backgrounded test-lock)
# is recorded with a command-line PATTERN, and the EXIT trap only kills a pid whose command STILL matches —
# so a recycled pid is never killed. A run interrupted mid-section would otherwise leave a `sleep`-based
# holder, or a test-lock holding a lock, behind for good.
note_pid() { printf '%s\t%s\n' "$1" "$2" >> "$T/helper.pids"; }
reap_helpers() {
  [ -f "$T/helper.pids" ] || return 0
  while IFS="$(printf '\t')" read -r _p _pat; do
    [ -n "$_p" ] || continue
    case "$(ps -p "$_p" -o command= 2>/dev/null)" in
      *"$_pat"*) kill -9 "$_p" 2>/dev/null ;;
    esac
  done < "$T/helper.pids"
}
_cleanup() { reap_helpers; pkill -f "sleep 876543" 2>/dev/null; rm -rf "$T"; }
trap _cleanup EXIT
# The signal traps are the ones that matter: bash does NOT run an EXIT trap when it dies of an UNTRAPPED
# SIGTERM/SIGINT, so `trap … EXIT` alone leaks the sandbox — and a still-held lock — exactly when the harness
# is killed. Measured while writing this file.
trap '_cleanup; exit 130' INT
trap '_cleanup; exit 143' TERM
trap '_cleanup; exit 129' HUP
PASS=0; FAIL=0; SKIP=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
skip() { printf '  \033[33mSKIP\033[0m %s\n' "$1"; SKIP=$((SKIP+1)); }

# ---- sandbox --------------------------------------------------------------------------------------------
export HOME="$T/home"; mkdir -p "$HOME"
BIN="$T/bin"; mkdir -p "$BIN"
export PATH="$BIN:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export VISIONOCR_TEST_LOCK="$T/test.lock"
LOCKDIR="$T/test.lock"

# Scriptable `pgrep` stub: $T/pgrepctl holds `none`, `live`, `pids N N N…`, or `flip` (a suite on the first
# call and none afterwards — a suite that exits inside the acquire window).
# The `pids` form is what section [12] needs: `status` classifies the `tests` set by ANCESTRY within that set,
# so the assertions need a set whose parentage they control. `live` keeps its old meaning (one pid, 424242,
# that does not exist) because sections [0] and [9] assert against it.
# ⚠️ AN UNRECOGNISED CONTROL VALUE IS AN ERROR, NOT "no suite". The first version of this stub treated
# anything that was not `none`/`live` as a pid list, so a `pgset non` typo would have produced
# `1 suite (pid non)`; the version before that treated anything not `live` as "no suite", which is worse — a
# typo would have silently turned an assertion about a live suite into one about an idle machine, and passed.
echo none > "$T/pgrepctl"
cat > "$BIN/pgrep" <<STUB
#!/bin/sh
echo "pgrep \$*" >> "$T/pgrep.log"
_c="\$(cat "$T/pgrepctl" 2>/dev/null)"
case "\$_c" in
  none|'')  exit 1 ;;
  live)     echo 424242; exit 0 ;;
  flip)     echo none > "$T/pgrepctl"; echo 424242; exit 0 ;;
  pids\ *)  for _p in \${_c#pids }; do echo "\$_p"; done; exit 0 ;;
  *)        echo "pgrep stub: unrecognised control value '\$_c'" >&2; exit 3 ;;
esac
STUB
chmod +x "$BIN/pgrep"
printf 'pgrep() { "%s/pgrep" "$@"; }\n' "$BIN" > "$T/preload.sh"
pgset() { echo "$1" > "$T/pgrepctl"; }

# Scriptable `ps` stub, for the assertions the real `ps` cannot reach: this harness cannot CHOOSE pids, so
# exact-vs-substring set membership, an ancestry cycle, and a set with no parentless member are all
# untestable against the machine's own process tree. $T/psctl holds `pid ppid` lines; anything not listed
# answers as the real `ps` does for a process that has exited — nothing, exit 1.
# ⚠️ Only `-p N -o ppid=` is emulated. test-lock.sh's only other `ps` use is none; the harness's own `ps`
# calls run in the harness shell and are NOT interposed (BASH_ENV reaches the child).
: > "$T/psctl"
cat > "$BIN/psstub" <<STUB
#!/bin/sh
_want=""; _next=""
for _a in "\$@"; do
  case "\$_next" in p) _want="\$_a"; _next="" ;; *) : ;; esac
  case "\$_a" in -p) _next=p ;; esac
done
[ -n "\$_want" ] || exit 1
while read -r _p _pp; do [ "\$_p" = "\$_want" ] && { echo " \$_pp"; exit 0; }; done < "$T/psctl"
exit 1
STUB
chmod +x "$BIN/psstub"
{ printf 'pgrep() { "%s/pgrep" "$@"; }\n' "$BIN"; printf 'ps() { "%s/psstub" "$@"; }\n' "$BIN"; } > "$T/preload-ps.sh"
psset() { printf '%s\n' "$@" > "$T/psctl"; }

tl()     { BASH_ENV="$T/preload.sh" bash "$LOCKSH" "$@"; }     # stubbed detector -> deterministic
tlreal() { bash "$LOCKSH" "$@"; }                              # the REAL `pgrep -x tests`
# ⚠️ EVERY `ps`-STUBBED CALL IS BOUNDED, and that is not caution — it is required for the harness to be able to
# REPORT its own findings. Two of `mutate-test-lock.sh`'s mutants (`walk-unbounded`, `nroots-zero-unhandled`)
# make `status` loop for ever over a cyclic ancestry, so an unbounded call there does not fail the check, it
# HANGS THE WHOLE CAMPAIGN: measured 2026-08-19, four mutants ran past 560 s and had to be killed by hand, with
# no verdict for any of them. A hanging implementation must arrive as a failed assertion, so the timeout is
# inside the runner rather than around the campaign. Echoes the output and the seconds it took.
tlps() {   # $1 = ceiling in seconds; rest = test-lock.sh arguments
  local ceil="$1"; shift
  local t0 t1 p
  t0=$(date +%s)
  ( BASH_ENV="$T/preload-ps.sh" bash "$LOCKSH" "$@" ) > "$T/tlps.out" 2>&1 &
  p=$!
  local w=0; while kill -0 "$p" 2>/dev/null && [ "$w" -lt "$ceil" ]; do sleep 1; w=$(( w + 1 )); done
  if kill -0 "$p" 2>/dev/null; then kill -9 "$p" 2>/dev/null; printf 'TLPS-TIMEOUT after %ss\n' "$ceil" >> "$T/tlps.out"; fi
  wait "$p" 2>/dev/null
  t1=$(date +%s); TLPS_SECS=$(( t1 - t0 ))
  cat "$T/tlps.out"
}
TLPS_SECS=0
held()   { [ -d "$LOCKDIR" ]; }
holder() { cat "$LOCKDIR/pid" 2>/dev/null; }
clear_lock() { rm -rf "$LOCKDIR"; }
# A lock planted by hand, so a test can choose the holder pid. Files first, then the mtime: adding files to
# a directory updates its mtime, so back-dating has to come last.
plant_lock() {   # $1=pid  $2=label  [$3=touch -t stamp]
  mkdir -p "$LOCKDIR"; printf '%s\n' "$1" > "$LOCKDIR/pid"; printf '%s\n' "$2" > "$LOCKDIR/label"
  [ -n "${3:-}" ] && touch -t "$3" "$LOCKDIR"
  return 0
}
live_helper() {  # a process that is genuinely alive, to act as a lock holder; echoes its pid
  # >/dev/null 2>&1 is LOAD-BEARING, not tidiness: these run inside `$(…)`, and a backgrounded child that
  # inherits the command substitution's stdout holds the pipe open — so `LH=$(live_helper)` would block for
  # the whole 300s waiting on a process it deliberately left running.
  /bin/sleep 300 >/dev/null 2>&1 & local p=$!; note_pid "$p" "sleep 300"; echo "$p"
}
dead_pid() {     # a pid that is genuinely gone
  /bin/sleep 0.1 >/dev/null 2>&1 & local p=$!; wait "$p" 2>/dev/null; echo "$p"
}

echo "[0] SANDBOX INTEGRITY — the pgrep detector must really be interposed"
: > "$T/pgrep.log"; pgset live; clear_lock
OUT=$(tl status 2>&1); RC=$?
if [ -s "$T/pgrep.log" ] && printf '%s' "$OUT" | grep -q '424242'; then
  ok "pgrep resolves to the sandbox stub even under test-lock.sh's own PATH"
else
  bad "pgrep interposition BROKEN — every assertion below would depend on machine state. Refusing to run."
  echo; echo "=================== $PASS passed, $FAIL failed, $SKIP skipped ==================="
  exit 3
fi
pgset none
if pgrep -x tests >/dev/null 2>&1; then true; fi     # (stubbed here; the real check is in [10])
echo "    real machine state right now: $(/usr/bin/pgrep -x tests >/dev/null 2>&1 && echo 'a `tests` process IS running' || echo 'no `tests` process')"

echo "[1] ACQUIRE / RELEASE round trip"
clear_lock
OUT=$(VISIONOCR_TEST_LOCK_PID=$$ tl acquire --label prove --wait 0 2>&1); RC=$?
[ "$RC" = 0 ] && held && ok "acquire took the lock (rc 0, lockdir created)" || bad "acquire failed rc=$RC out='$OUT'"
[ "$(holder)" = "$$" ] && ok "records the CALLER's pid, not the helper's ($(holder))" || bad "holder pid is '$(holder)', expected $$"
[ "$(cat "$LOCKDIR/label" 2>/dev/null)" = prove ] && ok "records the label" || bad "label not recorded"
OUT=$(VISIONOCR_TEST_LOCK_PID=$$ tl release 2>&1); RC=$?
[ "$RC" = 0 ] && ! held && ok "release gave it back" || bad "release failed rc=$RC held=$(held && echo yes || echo no)"

echo "[2] A SECOND acquire is REFUSED while the lock is genuinely held"
clear_lock; VISIONOCR_TEST_LOCK_PID=$$ tl acquire --label first --wait 0 >/dev/null 2>&1
T0=$(date +%s); OUT=$(tl acquire --label second --wait 0 2>&1); RC=$?; T1=$(date +%s)
[ "$RC" = 4 ] && ok "--wait 0 refuses immediately with exit 4" || bad "expected rc 4, got $RC ('$OUT')"
[ $(( T1 - T0 )) -le 2 ] && ok "…and did not sit there waiting ($(( T1 - T0 ))s)" || bad "took $(( T1 - T0 ))s"
[ "$(holder)" = "$$" ] && ok "the incumbent's lock is untouched" || bad "the refused caller disturbed the lock"
OUT=$(tl run --label second --wait 0 -- /usr/bin/true 2>&1); RC=$?
[ "$RC" = 4 ] && printf '%s' "$OUT" | grep -q 'could not get the suite lock' \
  && ok "\`run\` also refuses (exit 4) and says so" || bad "run gave rc=$RC ('$OUT')"

echo "[3] REENTRANCY — VISIONOCR_TEST_LOCK_HELD=1 runs directly instead of deadlocking on itself"
# This is what stops a session's `git commit` -> .githooks/pre-commit -> suite from waiting out the whole
# --wait against a lock its own parent already holds. The lock is still HELD by us from [2] on purpose.
rm -f "$T/reentrant.marker"
T0=$(date +%s)
OUT=$(VISIONOCR_TEST_LOCK_HELD=1 tl run --label inner --wait 6 -- \
        /bin/sh -c "echo ran > '$T/reentrant.marker'; exit 0" 2>&1); RC=$?
T1=$(date +%s)
[ "$RC" = 0 ] && ok "the inner run succeeded (rc 0) with the lock held" || bad "inner run rc=$RC ('$OUT')"
[ -f "$T/reentrant.marker" ] && ok "the command actually executed" || bad "command never ran"
[ $(( T1 - T0 )) -le 3 ] && ok "returned at once — no self-deadlock ($(( T1 - T0 ))s of a 6s wait)" || bad "blocked $(( T1 - T0 ))s: it deadlocked against itself"
held && ok "the reentrant call did NOT release its parent's lock" || bad "the inner run released the outer lock"
VISIONOCR_TEST_LOCK_PID=$$ tl release >/dev/null 2>&1

echo "[4] A holder whose pid is GONE is reclaimed at once (not after MAXAGE)"
clear_lock; DP=$(dead_pid); plant_lock "$DP" ghost
T0=$(date +%s); OUT=$(tl acquire --label taker --wait 0 2>&1); RC=$?
printf '%s' "$OUT" | grep -q "holder pid $DP is gone" && ok "notices the holder is gone and says so" || bad "no reclaim message ('$OUT')"
held && bad "left the dead holder's lock in place" || ok "removed it immediately"
OUT=$(VISIONOCR_TEST_LOCK_PID=$$ tl acquire --label taker --wait 0 2>&1); RC=$?; T1=$(date +%s)
[ "$RC" = 0 ] && ok "the next pass acquires it (fair re-race, rc 0)" || bad "could not acquire after the reclaim (rc=$RC '$OUT')"
[ $(( T1 - T0 )) -le 3 ] && ok "…in seconds, nowhere near MAXAGE ($(( T1 - T0 ))s)" || bad "took $(( T1 - T0 ))s"
clear_lock

echo "[5] A lock past VISIONOCR_TEST_LOCK_MAXAGE is BROKEN even though its holder is alive"
clear_lock; LH=$(live_helper); plant_lock "$LH" wedged 202601010000
OUT=$(VISIONOCR_TEST_LOCK_MAXAGE=60 tl acquire --label taker --wait 0 2>&1); RC=$?
printf '%s' "$OUT" | grep -q 'breaking it' && ok "breaks an aged-out lock, naming the holder" || bad "did not break it ('$OUT')"
held && bad "aged-out lock left in place" || ok "the aged-out lock is gone"
kill -9 "$LH" 2>/dev/null; clear_lock

echo "[6] RELEASE REFUSES when another pid owns the lock"
LH=$(live_helper); plant_lock "$LH" someone-else
OUT=$(VISIONOCR_TEST_LOCK_PID=$$ tl release 2>&1); RC=$?
[ "$RC" = 1 ] && ok "refuses (rc 1) rather than stealing it" || bad "released someone else's lock (rc=$RC)"
printf '%s' "$OUT" | grep -q "held by pid $LH, not by this caller" && ok "…and says whose it is" || bad "no explanation ('$OUT')"
held && ok "the lock survived the refused release" || bad "the lock was removed anyway"
kill -9 "$LH" 2>/dev/null; clear_lock

echo "[7] \`run\` releases on EVERY exit path, and propagates the command's status"
OUT=$(tl run --label ok-run --wait 0 -- /bin/sh -c 'exit 0' 2>&1); RC=$?
[ "$RC" = 0 ] && ok "clean command -> rc 0" || bad "rc=$RC ('$OUT')"
held && bad "leaked the lock after a clean exit" || ok "released on a normal exit"
OUT=$(tl run --label bad-run --wait 0 -- /bin/sh -c 'exit 7' 2>&1); RC=$?
[ "$RC" = 7 ] && ok "propagates the command's exit status (7)" || bad "expected rc 7, got $RC"
held && bad "leaked the lock after a failing command" || ok "released on a nonzero exit"

echo "[8] \`run\` releases the lock when TERMed MID-COMMAND (a leak blocks the owner for MAXAGE)"
# The kill must hit the COMMAND as well as test-lock.sh, and that is not sloppiness: bash defers a TERM trap
# until the running foreground command returns (measured: a TERM at t+1s ran the EXIT trap at t+6s, when the
# `sleep 6` finished). The daemon's watchdog kills the whole descendant tree (_terminate_tree), so TERMing
# the tree is the faithful reproduction. A parent-only TERM does not leak the lock either — it just defers
# the release until the suite finishes, which is why the tree kill is the case worth asserting.
clear_lock; rm -f "$T/cmd.pid"
# Its output goes to a file, not to this harness's stderr: bash announces a foreground child killed by a
# signal ("Terminated: 15"), and that notice is test-lock.sh's, not a harness failure — in the output it
# reads like one.
( exec env BASH_ENV="$T/preload.sh" bash "$LOCKSH" run --label termtest --wait 0 -- \
    /bin/sh -c "echo \$\$ > '$T/cmd.pid'; exec /bin/sleep 876543" ) > "$T/termtest.out" 2>&1 &
TLPID=$!; note_pid "$TLPID" "$LOCKSH"
disown "$TLPID" 2>/dev/null || true    # keep bash's "Terminated: 15" job notice out of the harness output
W=0; while [ ! -f "$T/cmd.pid" ] && [ "$W" -lt 8 ]; do sleep 1; W=$(( W + 1 )); done
CMDPID="$(cat "$T/cmd.pid" 2>/dev/null)"; [ -n "$CMDPID" ] && note_pid "$CMDPID" "sleep 876543"
held && ok "the long command is running under the lock" || bad "lock was never taken (cmd.pid='$CMDPID')"
kill -TERM "$TLPID" 2>/dev/null; kill -TERM "$CMDPID" 2>/dev/null
W=0; while held && [ "$W" -lt 8 ]; do sleep 1; W=$(( W + 1 )); done
held && bad "LOCK LEAKED after a TERM — the owner's suite would block until MAXAGE" || ok "released within ${W}s of the TERM"
pkill -f "sleep 876543" 2>/dev/null; clear_lock

echo "[9] STATUS reports free / busy, and exits 0 / 1 to match"
pgset none; clear_lock
OUT=$(tl status 2>&1); RC=$?
[ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'lock   free' && ok "free + no suite -> rc 0" || bad "rc=$RC ('$OUT')"
LH=$(live_helper); plant_lock "$LH" busy-holder
OUT=$(tl status 2>&1); RC=$?
[ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q 'HELD by busy-holder' && ok "held -> rc 1, naming the holder" || bad "rc=$RC ('$OUT')"
kill -9 "$LH" 2>/dev/null; sleep 1
OUT=$(tl status 2>&1)
printf '%s' "$OUT" | grep -q 'HOLDER IS GONE' && ok "reports a stale holder as stale" || bad "did not flag the dead holder ('$OUT')"
clear_lock; pgset live
OUT=$(tl status 2>&1); RC=$?
[ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q 'suite  RUNNING' && ok "free lock but a live suite -> rc 1" || bad "rc=$RC ('$OUT')"
pgset none

echo "[10] THE REAL DETECTOR — \`pgrep -x tests\` against a process genuinely named \`tests\`"
# No stub here. A process genuinely named `tests` is exactly what `pgrep -x tests` matches (-x is the process
# NAME), so these assertions hold whether or not a real suite is also running.
# ⚠️ `exec -a tests /bin/sleep`, NOT `cp /bin/sleep $BIN/tests`: a COPY of an Apple platform binary is
# SIGKILLed at exec on Apple Silicon ("Killed: 9" from code signing), so the copy route silently produces no
# process at all and the whole section degrades to a SKIP. Measured while writing this file.
( exec -a tests /bin/sleep 765432 ) & FAKE=$!; note_pid "$FAKE" "tests 765432"
W=0; while ! /usr/bin/pgrep -x tests >/dev/null 2>&1 && [ "$W" -lt 5 ]; do sleep 1; W=$(( W + 1 )); done
clear_lock
if /usr/bin/pgrep -x tests >/dev/null 2>&1; then
  OUT=$(tlreal status 2>&1); RC=$?
  [ "$RC" = 1 ] && printf '%s' "$OUT" | grep -q 'suite  RUNNING' \
    && ok "the real \`pgrep -x tests\` sees an out-of-band suite (rc 1)" || bad "real detector missed it (rc=$RC '$OUT')"
  OUT=$(VISIONOCR_TEST_LOCK_PID=$$ tlreal acquire --label yielder --wait 0 2>&1); RC=$?
  [ "$RC" = 4 ] && ok "acquire YIELDS to a suite it did not start (exit 4)" || bad "acquired alongside a live suite (rc=$RC)"
  held && bad "left a lock behind while yielding" || ok "…and left no lock behind"
else
  skip "could not start/observe our own \`tests\` process (pid $FAKE) — the real-detector assertions cannot be made here"
  skip "acquire-yields-to-a-live-suite (same reason)"
  skip "no-lock-left-behind-while-yielding (same reason)"
fi
kill -9 "$FAKE" 2>/dev/null; wait "$FAKE" 2>/dev/null
W=0; while /usr/bin/pgrep -x tests >/dev/null 2>&1 && [ "$W" -lt 5 ]; do sleep 1; W=$(( W + 1 )); done
clear_lock
# The CONVERSE is machine-state-dependent: "the real detector reports NO suite" is only true if nothing on
# this machine is running one, and the owner may be running the suite interactively right now. Assert it
# only when it is checkable, and SKIP loudly otherwise — a green that depends on the machine being idle is
# an instrument that lies.
if /usr/bin/pgrep -x tests >/dev/null 2>&1; then
  skip "real-detector-reports-free: a \`tests\` process is running on this machine (pid(s) $(/usr/bin/pgrep -x tests | tr '\n' ' ')) — NOT this harness's, so the assertion is not decidable here"
else
  OUT=$(tlreal status 2>&1); RC=$?
  [ "$RC" = 0 ] && printf '%s' "$OUT" | grep -q 'no `tests` process running' \
    && ok "with no suite on the machine, the real detector reports free (rc 0)" || bad "rc=$RC ('$OUT')"
fi


# ---- [11] THE TIMING LEDGER — every caller shape must write the SAME row -----------------------------------
# The suite's duration was thought to vary with load (416-632 s quiet, ~37-40 min loaded, ~45 min per
# run under the C24b campaign's overnight load), so the
# constants in this file are meant to be re-derived from a ledger rather than from prose. That only works if
# the ledger sees every run, and there are TWO caller shapes: the health gate and every session use `run`,
# while .githooks/pre-commit holds the lock with acquire/trap-release — so its notice reaches the terminal
# rather than a log file — and hands its timing in with `record`. The hook is the most frequent suite runner
# of the three, so a ledger that quietly skipped it would under-report the common case.
echo "[11] the suite-timing ledger"
LED="$T/timings.tsv"; rm -f "$LED"
pgset none; clear_lock
VISIONOCR_SUITE_TIMINGS="$LED" tl run --label gate-shape --wait 0 -- /bin/sleep 1 >/dev/null 2>&1
rc_run=$?
VISIONOCR_SUITE_TIMINGS="$LED" tl record --label "pre-commit 999" --seconds 2201 --rc 0 >/dev/null 2>&1
[ "$rc_run" = 0 ] && ok "run still propagates its command status with timing on" \
                  || bad "run returned $rc_run with timing on"
[ "$(wc -l < "$LED" | tr -d " ")" = 3 ] && ok "one header plus one row per caller shape" \
                  || bad "expected 3 lines, got $(wc -l < "$LED" | tr -d " ")"
head -1 "$LED" | grep -q "^when.label.seconds.rc.loadavg1$" \
  && ok "header written once, in the documented order" || bad "header wrong: $(head -1 "$LED")"
grep -q "	gate-shape	" "$LED" && ok "the run shape (gate, sessions) is recorded" || bad "run wrote no row"
# THE regression this section exists for: --label is consumed by the GLOBAL option parser before any
# subcommand sees it, so a naive `record` defaulting its own label to "" wrote every hook row as `?`.
grep -q "	pre-commit 999	2201	0	" "$LED" \
  && ok "the record shape (pre-commit) keeps its label and handed-in duration" \
  || bad "record row wrong: $(grep -v "^when" "$LED" | tail -1)"
# A non-numeric duration must be DROPPED, not written as garbage that a later reader averages in.
VISIONOCR_SUITE_TIMINGS="$LED" tl record --label junk --seconds "abc" >/dev/null 2>&1
grep -q "	junk	" "$LED" && bad "a non-numeric duration reached the ledger" \
                          || ok "a non-numeric duration is refused, not recorded"
# ⚠️ Instrumentation must NEVER be able to fail a suite or a commit. /usr/bin/true, not /bin/true — the
# latter does not exist on macOS, and using it made this assertion fail for a reason that had nothing to do
# with the ledger. That mistake is exactly why the harness runs rather than reasons.
VISIONOCR_SUITE_TIMINGS="/nonexistent-dir-$$/x.tsv" tl run --label unwritable --wait 0 -- /usr/bin/true \
  >/dev/null 2>&1 \
  && ok "an unwritable ledger does not fail the command it is timing" \
  || bad "an unwritable ledger broke the run — instrumentation must never be a gate"
clear_lock

# ---- [12] STATUS must not read the suite's OWN probe children as extra suites -------------------------------
# `Tests/main.swift` re-executes `build/tests` with --probe-hostile-page / --probe-hostile-numbers /
# --probe-deep-outline, so a healthy suite has one or more CHILDREN also named `tests`, and `pgrep -x tests`
# matches every one. `status` used to print the raw list — `suite RUNNING — pid(s) 1536 98565` — and two pids
# is the reading CLAUDE.md tells a session to treat as corruption. It cost a session the time to rule that
# out every time, and (worse) it teaches the reader to DISCOUNT a two-pid reading, which is the one reading
# that would matter if two suites ever really did run. So the two-suite case is asserted here as loudly as
# the one-suite case.
#
# The classification is by ancestry WITHIN the set pgrep returned, not by `ps -o comm=`: comm and `pgrep -x`
# do not agree about a process renamed with `exec -a`, and the answer has to be about the same set pgrep
# produced. So these pids need a real parent/child relationship but NOT the name `tests` — the stub supplies
# the set, `ps` supplies the truth. The real `pgrep -x tests` detector is proven in [10]; the real end-to-end
# composition of the two is the last assertion of this section.
echo "[12] STATUS separates the suite from the probe children it forks of ITSELF"
pgset none; clear_lock
rm -f "$T/probe.pid" "$T/mid.pid"
# SROOT -> SPROBE -> SGRAND, a genuine three-deep chain. `exec` preserves the pid, so backgrounding a child
# and then exec-ing the parent into a long sleep keeps the parentage while giving the parent a stable pid.
( ( /bin/sleep 765431 >/dev/null 2>&1 & printf '%s' "$!" > "$T/probe.pid"
    exec /bin/sleep 765432 ) >/dev/null 2>&1 & printf '%s' "$!" > "$T/mid.pid"
  exec /bin/sleep 765430 ) >/dev/null 2>&1 &
SROOT=$!; note_pid "$SROOT" "765430"
# `disown`, as in [8]: bash announces a killed background job ("Killed: 9") on its own stderr, and in this
# harness's output that notice reads exactly like a failure. Same reason, same fix.
disown "$SROOT" 2>/dev/null || true
W=0; while { [ ! -s "$T/mid.pid" ] || [ ! -s "$T/probe.pid" ]; } && [ "$W" -lt 8 ]; do sleep 1; W=$(( W + 1 )); done
SPROBE="$(cat "$T/mid.pid" 2>/dev/null)"; SGRAND="$(cat "$T/probe.pid" 2>/dev/null)"
[ -n "$SPROBE" ] && note_pid "$SPROBE" "765432"
[ -n "$SGRAND" ] && note_pid "$SGRAND" "765431"
SOTHER=$(live_helper)          # an unrelated live process: a genuine SECOND suite
if [ -z "$SPROBE" ] || [ -z "$SGRAND" ]; then
  # ⚠️ ONE SKIP PER ASSERTION, NAMED THE SAME. The first version of this arm emitted seven skips — one of them
  # a section header — against NINE assertions in the `else`, so the totals read 56 instead of 58 and a reader
  # could not tell which three had gone. That matters because one of the nine (`the walk reaches past one hop`)
  # is the SOLE killer of a mutant that had already survived once; losing it into an unlabelled skip is the
  # instrument mislaying its own coverage — invariant 1, inside the harness, and the same shape as the defect
  # the section is about.
  echo "    could not build the pid chain (root=$SROOT probe='$SPROBE' grand='$SGRAND')"
  skip "one suite plus its probe child reads as 1 suite, naming the parent (no pid chain)"
  skip "…and names the child AS a probe child (no pid chain)"
  skip "the probe child appears nowhere in the SUITE half of the line (no pid chain)"
  skip "a live suite still exits 1 (no pid chain)"
  skip "a whole chain under one suite is all probe children (no pid chain)"
  skip "a descendant whose own parent is NOT in the set is still a probe child (no pid chain)"
  skip "two UNRELATED tests processes are still reported as two suites, loudly (no pid chain)"
  skip "two suites AND a probe child: both counts right (no pid chain)"
  skip "every pid pgrep returned appears in the line (no pid chain)"
else
  pgset "pids $SROOT $SPROBE"
  OUT=$(tl status 2>&1); RC=$?
  printf '%s' "$OUT" | grep -q "1 suite (pid $SROOT)" \
    && ok "one suite plus its probe child reads as 1 suite, naming the parent" \
    || bad "did not name the single suite: '$(printf '%s' "$OUT" | grep '^suite')'"
  printf '%s' "$OUT" | grep -q "1 probe child (pid $SPROBE)" \
    && ok "…and names the child AS a probe child" \
    || bad "the probe child is not reported as one: '$(printf '%s' "$OUT" | grep '^suite')'"
  # ⚠️ This assertion has to bite against the OLD line as well, or it is one more check that cannot fail:
  # `grep -qi 'SUITES AT ONCE'` alone was green over `pid(s) 90955 90956`, which is the very defect. So strip
  # the probe-child clause and assert the probe pid is not in what remains — the SUITE half of the line.
  SUITEHALF="$(printf '%s' "$OUT" | grep '^suite' | sed 's/, plus .*//')"
  case "$SUITEHALF" in
    *"$SPROBE"*) bad "the probe child is still listed as a suite: '$SUITEHALF'" ;;
    *)           ok "the probe child appears nowhere in the SUITE half of the line" ;;
  esac
  [ "$RC" = 1 ] && ok "a live suite still exits 1" || bad "expected rc 1, got $RC"

  # A probe that forks its own helper: the whole contiguous chain is probe children.
  pgset "pids $SROOT $SPROBE $SGRAND"
  OUT=$(tl status 2>&1)
  printf '%s' "$OUT" | grep -q "1 suite (pid $SROOT)" \
    && printf '%s' "$OUT" | grep -q "2 probe children" \
    && ok "a whole chain under one suite is all probe children" \
    || bad "the chain was misclassified: '$(printf '%s' "$OUT" | grep '^suite')'"

  # ⚠️ THE REACH OF THE WALK, pinned. The set above is CONTIGUOUS — SGRAND's own parent SPROBE is in it — so
  # a one-ppid-deep implementation classifies it correctly by accident and the check above cannot see the
  # difference. Measured: a mutant capping the walk at one hop passed all 57 checks. So this set omits the
  # INTERMEDIATE: SGRAND's parent is not a member, its grandparent is. A1.3's precedent — equal reach belongs
  # in a check, not in a comment.
  pgset "pids $SROOT $SGRAND"
  OUT=$(tl status 2>&1)
  printf '%s' "$OUT" | grep -q "1 suite (pid $SROOT), plus 1 probe child (pid $SGRAND)" \
    && ok "a descendant whose own parent is NOT in the set is still a probe child (the walk reaches past one hop)" \
    || bad "the walk stops too early: '$(printf '%s' "$OUT" | grep '^suite')'"

  # ⛔ THE READING THAT MUST SURVIVE. Suppressing probe children is only safe if two real suites still shout.
  pgset "pids $SROOT $SOTHER"
  OUT=$(tl status 2>&1)
  printf '%s' "$OUT" | grep -q '2 SUITES AT ONCE' \
    && ok "two UNRELATED tests processes are still reported as two suites, loudly" \
    || bad "two genuine suites were not flagged: '$(printf '%s' "$OUT" | grep '^suite')'"

  pgset "pids $SROOT $SPROBE $SOTHER"
  OUT=$(tl status 2>&1)
  if printf '%s' "$OUT" | grep -q "2 SUITES AT ONCE (pids $SROOT $SOTHER)" \
     && printf '%s' "$OUT" | grep -q "1 probe child (pid $SPROBE)"; then
    ok "two suites AND a probe child: both counts right, and the child is not one of the two"
  else
    bad "mixed case wrong: '$(printf '%s' "$OUT" | grep '^suite')'"
  fi
  # Invariant 1 in an instrument: a classifier may relabel a pid, never drop it.
  # ⚠️ The SUITE line only. Grepping all of $OUT also searches `lock   free (/var/folders/…)`, whose temp-dir
  # path contains digits — so a pid could "appear" in a line that is not about suites at all.
  MISSING=""; SUITELINE="$(printf '%s' "$OUT" | grep '^suite')"
  for p in $SROOT $SPROBE $SOTHER; do
    case "$SUITELINE" in *"$p"*) ;; *) MISSING="$MISSING $p" ;; esac
  done
  [ -z "$MISSING" ] && ok "every pid pgrep returned appears in the line — relabelled, never dropped" \
                    || bad "pid(s)$MISSING vanished from the report: '$SUITELINE'"
fi

# A pid whose ancestry cannot be read (it exited between the pgrep and the ps) must count as a SUITE.
# Over-reporting a suite makes a caller wait; under-reporting one runs two. 424242 does not exist.
pgset live; clear_lock
OUT=$(tl status 2>&1); RC=$?
printf '%s' "$OUT" | grep -q '1 suite (pid 424242)' \
  && ok "a pid whose parent cannot be read counts as a suite, not as a child" \
  || bad "an unresolvable pid was not reported as a suite: '$(printf '%s' "$OUT" | grep '^suite')'"

# END TO END: the REAL `pgrep -x tests` over two processes this harness genuinely names `tests`, one the
# parent of the other. Robust to machine state — a real suite elsewhere only adds its own root and children,
# and cannot change how THIS child is classified.
pgset none
rm -f "$T/rprobe.pid"
( exec -a tests /bin/bash -c "exec -a tests /bin/sleep 765433 >/dev/null 2>&1 & printf '%s' \$! > '$T/rprobe.pid'
                              exec -a tests /bin/sleep 765434" ) >/dev/null 2>&1 &
RROOT=$!; note_pid "$RROOT" "765434"
disown "$RROOT" 2>/dev/null || true
W=0; while [ ! -s "$T/rprobe.pid" ] && [ "$W" -lt 8 ]; do sleep 1; W=$(( W + 1 )); done
RPROBE="$(cat "$T/rprobe.pid" 2>/dev/null)"; [ -n "$RPROBE" ] && note_pid "$RPROBE" "765433"
if [ -n "$RPROBE" ] && /usr/bin/pgrep -x tests 2>/dev/null | grep -qx "$RROOT" \
   && /usr/bin/pgrep -x tests 2>/dev/null | grep -qx "$RPROBE"; then
  OUT=$(tlreal status 2>&1)
  printf '%s' "$OUT" | grep -qE "probe child(ren)? \(pids? [0-9 ]*$RPROBE" \
    && ok "the REAL detector's own child is classified as a probe child" \
    || bad "real end-to-end: child $RPROBE not reported as a probe child ('$(printf '%s' "$OUT" | grep '^suite')')"
else
  skip "could not observe both \`tests\` processes via the real pgrep (root=$RROOT probe='$RPROBE') — the end-to-end assertion is not decidable here"
fi
kill -9 "$RPROBE" "$RROOT" 2>/dev/null
kill -9 "$SGRAND" "$SPROBE" "$SROOT" "$SOTHER" 2>/dev/null
pgset none; clear_lock

# ---- [12b] THE THREE THINGS THE REAL `ps` CANNOT BE ASKED ----------------------------------------------------
# [12] stubs `pgrep` but uses the machine's REAL `ps`, so it can only test the ancestry relations the machine
# happens to hand it — and it cannot CHOOSE pids. Three properties of the classifier are therefore invisible to
# it, and an adversarial review found all three unpinned on 2026-08-19 by mutating a copy: two of the mutants
# scored a full 58/0/0. So `ps` is interposed here too, on the same BASH_ENV seam as `pgrep`.
echo "[12b] the classifier against an interposed \`ps\`: exact membership, a cycle, and no parentless member"
clear_lock
# (i) EXACT membership. 456 is a decimal SUBSTRING of 45678, and 45678 is a genuine second suite whose real
# ancestor 456 is not in the set. `*"$up"*` without the anchoring spaces calls it a probe child of 999 — the
# alarm this whole change exists to make louder, switched off.
psset "45678 456" "456 1" "999 1"
pgset "pids 45678 999"
OUT=$(tlps 20 status)
printf '%s' "$OUT" | grep -q '2 SUITES AT ONCE' \
  && ok "set membership is EXACT: an ancestor that is a substring of a member is not a match" \
  || bad "substring false positive silenced a second suite: '$(printf '%s' "$OUT" | grep '^suite\|TLPS-TIMEOUT')'"
# (ii) THE HOP BOUND. The walk samples one `ps` per hop, so a pid recycled between hops can close a loop; the
# bound is what stops `status` spinning, and `status` is what daemon.sh prints before the daemon starts.
psset "500 600" "600 700" "700 600"
pgset "pids 500"
OUT=$(tlps 15 status)
{ [ "$TLPS_SECS" -le 12 ] && ! printf '%s' "$OUT" | grep -q 'TLPS-TIMEOUT'; } \
  && ok "an ancestry CYCLE terminates the walk (${TLPS_SECS}s) instead of hanging status" \
  || bad "status did not return over a cyclic ps (${TLPS_SECS}s) — the hop bound is gone"
# (iii) NO PARENTLESS MEMBER. Same cause, different symptom: every member looks like somebody's descendant, so
# the root count is 0. The old code printed `0 suite (pids )` with NO alarm over two live `tests` processes.
psset "100 200" "200 100"
pgset "pids 100 200"
OUT=$(tlps 15 status)
if printf '%s' "$OUT" | grep -q 'inconsistent ps reading' \
   && printf '%s' "$OUT" | grep -q '100' && printf '%s' "$OUT" | grep -q '200'; then
  ok "a set with no parentless member is reported as an inconsistent reading, busy, naming every pid"
else
  bad "nroots=0 was not reported honestly: '$(printf '%s' "$OUT" | grep '^suite\|TLPS-TIMEOUT')'"
fi
printf '%s' "$OUT" | grep -q '0 suite' \
  && bad "printed '0 suite' while two tests processes were live" \
  || ok "…and never prints '0 suite' over a non-empty set"
: > "$T/psctl"; pgset none; clear_lock

# ---- [12c] ONE `pgrep`, so the report cannot disagree with the verdict ---------------------------------------
# `status` used to ask `_suite_live` and then `pgrep` again. Two calls can give two answers about the same
# machine: a suite exiting in between leaves the first saying RUNNING and the second returning nothing, and the
# report is then built from an empty set. Unpinned until an adversarial review reverted it and scored 58/0/0.
echo "[12c] the suite report comes from ONE pgrep call"
clear_lock; pgset flip           # a suite on the first call, none afterwards
OUT=$(tl status 2>&1); RC=$?
case "$(printf '%s' "$OUT" | grep '^suite')" in
  *"1 suite (pid 424242)"*) ok "a suite that exits mid-status is reported from the set that was actually read" ;;
  *"no \`tests\` process"*) ok "…or not at all — either is consistent; what must not happen is the third case" ;;
  *) bad "two pgrep calls disagreed and the report is built from neither: '$(printf '%s' "$OUT" | grep '^suite')'" ;;
esac
printf '%s' "$OUT" | grep -qE 'RUNNING.*(0 suite|\(pids? \))' \
  && bad "reported RUNNING over an empty pid set" || ok "never reports RUNNING over an empty pid set"
pgset none; clear_lock

# ---- [13] THE WAITING NOTICE — one assertion per REASON _try_acquire can be busy for -------------------------
# `_try_acquire` returns 1 for four different reasons and `acquire` announces once. It used to RE-DERIVE the
# reason by re-reading the lock directory — after `_try_acquire` had already deleted or broken it — and that was
# wrong three times running, each fix leaving one case:
#   * `test-lock: '' holds the suite lock (pid )` after any reclaim (observed 2026-08-16 in /tmp/vo-commit.log
#     while diagnosing a lost commit; it cost real time, read as a second unknown holder), fixed in df3ab6a and
#     pinned by NOTHING;
#   * "reclaimed from a dead holder" after an AGED-OUT break-in of a genuinely LIVE holder (found here, by
#     writing the check df3ab6a never got);
#   * "just reclaimed (see the line above)" on the yield-to-an-out-of-band-suite path, where nothing was
#     reclaimed and there IS no line above (found by an adversarial review of that fix, with a `pgrep` that
#     reports a suite once and then none).
# The reason is recorded by the branch that knows it now, so the section is one assertion per reason plus the
# "no reason was recorded" case — a states-by-doors table, CONTRIBUTING 4d, rather than three patches.
# ⚠️ --wait must be > 0 or acquire returns 4 before it ever reaches the notice.
echo "[13] the waiting notice says which of the four busy reasons it is, and invents nothing"
pgset none; clear_lock; DP=$(dead_pid); plant_lock "$DP" ghost
OUT=$(VISIONOCR_TEST_LOCK_PID=$$ tl acquire --label taker --wait 6 2>&1); RC=$?
# ⚠️ NOT `grep "(pid )"`. The original defect printed empties, but the branch that produced it defaults to
# `${_lbl:-?}` / `${_hpid:-?}`, so restoring it prints `'?' holds the suite lock (pid ?)` — and a check written
# against the empty form passed the mutant. Measured 2026-08-19: `elif true; then` was killed by the NEXT
# assertion only. After a reclaim there is no holder at all, so the phrase must not appear in any form.
printf '%s' "$OUT" | grep -q 'holds the suite lock' \
  && bad "named a holder after reclaiming a dead one: '$(printf '%s' "$OUT" | tr '\n' '|')'" \
  || ok "REASON dead holder: no phantom holder in any form"
printf '%s' "$OUT" | grep -q 'reclaimed from a holder whose pid is gone' \
  && ok "…and it says the holder's pid was gone, which is what happened" \
  || bad "the notice does not name the dead-holder reclaim: '$(printf '%s' "$OUT" | tr '\n' '|')'"
VISIONOCR_TEST_LOCK_PID=$$ tl release >/dev/null 2>&1; clear_lock
# REASON aged out, holder ALIVE. Must not be called dead.
LH=$(live_helper); plant_lock "$LH" wedged 202601010000
OUT=$(VISIONOCR_TEST_LOCK_PID=$$ VISIONOCR_TEST_LOCK_MAXAGE=60 tl acquire --label taker --wait 6 2>&1); RC=$?
if printf '%s' "$OUT" | grep -q 'breaking it' \
   && printf '%s' "$OUT" | grep -q 'broken after ageing out' \
   && ! printf '%s' "$OUT" | grep -qi 'dead\|pid is gone'; then
  ok "REASON aged out: a LIVE holder is broken without being called dead"
else
  bad "the aged-out notice misreports the holder: '$(printf '%s' "$OUT" | tr '\n' '|')'"
fi
[ "$RC" = 0 ] && ok "…and the acquire still succeeds on the next pass (rc 0)" || bad "acquire rc=$RC after the break-in"
kill -9 "$LH" 2>/dev/null; clear_lock
# REASON a live holder INSIDE MaxAge — the ordinary busy case. The label and pid must be the real ones, and a
# MULTI-WORD label must survive: this repo writes `pre-commit 999`, and any packed-string-plus-`cut` form of the
# recorded reason would print only `pre-commit`.
LH=$(live_helper); plant_lock "$LH" "pre-commit 999"
OUT=$(VISIONOCR_TEST_LOCK_PID=$$ tl acquire --label taker --wait 6 2>&1); RC=$?
printf '%s' "$OUT" | grep -q "'pre-commit 999' holds the suite lock (pid $LH)" \
  && ok "REASON held: names the live holder's WHOLE label and its pid" \
  || bad "the ordinary busy notice is wrong: '$(printf '%s' "$OUT" | tr '\n' '|')'"
[ "$RC" = 4 ] && ok "…and gives up with exit 4 rather than stealing it" || bad "expected rc 4, got $RC"
kill -9 "$LH" 2>/dev/null; clear_lock
# REASON an out-of-band suite. Nothing was reclaimed and no holder exists, so it must say neither.
pgset live
OUT=$(VISIONOCR_TEST_LOCK_PID=$$ tl acquire --label taker --wait 6 2>&1); RC=$?
if printf '%s' "$OUT" | grep -q 'a suite is already running' \
   && ! printf '%s' "$OUT" | grep -q 'reclaim\|broken after\|holds the suite lock'; then
  ok "REASON out-of-band suite: says so, and claims no reclaim and no holder"
else
  bad "the yield notice invents a reclaim or a holder: '$(printf '%s' "$OUT" | tr '\n' '|')'"
fi
held && bad "left a lock behind while yielding to an out-of-band suite" || ok "…and left no lock behind"
# The SAME path with the suite exiting inside the window — the case that produced "just reclaimed" over nothing.
pgset flip; clear_lock
OUT=$(VISIONOCR_TEST_LOCK_PID=$$ tl acquire --label taker --wait 6 2>&1); RC=$?
printf '%s' "$OUT" | grep -q 'reclaim\|broken after' \
  && bad "claimed a reclaim on the yield path, where nothing was reclaimed: '$(printf '%s' "$OUT" | tr '\n' '|')'" \
  || ok "a suite that exits inside the acquire window still produces no phantom reclaim"
pgset none; clear_lock
# THE INVERSE ROW (CONTRIBUTING 4d): the notice must NOT appear when nobody is going to wait. `--wait 0`
# short-circuits before the announce, so a caller that asked not to queue gets no "waiting up to 0s…" line.
# (The first version of this assertion planted no holder, so `--wait 0` simply ACQUIRED and it failed on rc 0 —
# a check about the notice that was really about an empty lock. Caught by running it.)
LH=$(live_helper); plant_lock "$LH" incumbent
OUT=$(VISIONOCR_TEST_LOCK_PID=$$ tl acquire --label taker --wait 0 2>&1); RC=$?
[ "$RC" = 4 ] && ok "--wait 0 refuses (rc 4) without reaching the notice at all" || bad "wait 0 rc=$RC ('$OUT')"
[ -z "$(printf '%s' "$OUT" | grep 'waiting up to')" ] \
  && ok "…and prints no waiting notice, because nobody is waiting" \
  || bad "printed a waiting notice for a caller that asked not to wait: '$(printf '%s' "$OUT" | tr '\n' '|')'"
kill -9 "$LH" 2>/dev/null; clear_lock

echo
echo "=================== $PASS passed, $FAIL failed, $SKIP skipped ==================="
[ "$FAIL" = 0 ]
