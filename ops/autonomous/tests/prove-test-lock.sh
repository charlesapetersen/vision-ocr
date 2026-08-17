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
# EXPECTED RESULT: 43 passed, 0 failed, 0 skipped — on an IDLE machine. Section [10]'s last assertion
# ("with no suite on the machine, the real detector reports free") is the one that cannot be made
# deterministic, so it SKIPs loudly when a real suite happens to be running rather than going red.
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

# Scriptable `pgrep` stub: $T/pgrepctl holds `none` or `live`.
echo none > "$T/pgrepctl"
cat > "$BIN/pgrep" <<STUB
#!/bin/sh
echo "pgrep \$*" >> "$T/pgrep.log"
if [ "\$(cat "$T/pgrepctl" 2>/dev/null)" = live ]; then echo 424242; exit 0; fi
exit 1
STUB
chmod +x "$BIN/pgrep"
printf 'pgrep() { "%s/pgrep" "$@"; }\n' "$BIN" > "$T/preload.sh"
pgset() { echo "$1" > "$T/pgrepctl"; }

tl()     { BASH_ENV="$T/preload.sh" bash "$LOCKSH" "$@"; }   # stubbed detector -> deterministic
tlreal() { bash "$LOCKSH" "$@"; }                            # the REAL `pgrep -x tests`
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
# The suite has no single duration on this machine (416-632 s on a quiet one, ~37-40 min loaded, ~45 min per
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

echo
echo "=================== $PASS passed, $FAIL failed, $SKIP skipped ==================="
[ "$FAIL" = 0 ]
