#!/usr/bin/env bash
# prove-stop.sh — prove-the-mechanism harness for `ops/autonomous/daemon.sh stop`.
#
# WHY IT IS COMMITTED: `daemon.sh` had NO harness at all, and on 2026-08-17 its `stop` verb was the thing
# that failed (README §Defects D1-D5). That is the worst possible file to leave uncovered, because `stop` is
# the verb an owner reaches for when something is ALREADY wrong: it is the one path guaranteed to run on a bad
# day, and it ran for weeks having never been driven by anything but a real incident.
#
# WHAT IT PROVES, and each assertion maps to a defect the incident produced:
#   [1] a stop kills the matched process's WHOLE TREE, not just the process         (D2)
#   [2] it never kills a process it cannot trace to the daemon — the owner's suite  (D2's ⛔ note)
#   [3] the suite lock is reported as OURS when we just killed its holder           (D3)
#   [4] …and LEFT ALONE, in those words, when an unrelated live process holds it    (D3, converse)
#   [5] engine.lock is cleared, so a restart does not idle out $STALE               (D4)
#   [6] a `grep`/`tail` merely READING health-gate.sh is not killed                 (D2's reader guard)
#   [7] `stop` never kills itself or the shell that invoked it
#
# FULLY SANDBOXED — it cannot touch the owner's machine, and two of the stubs are load-bearing rather than
# tidy:
#   * `launchctl` is a shell FUNCTION, so no real job is ever booted out. Without it, running this harness
#     would stop the owner's live daemon.
#   * ⚠️ `pgrep` IS INTERPOSED, AND THAT IS A SAFETY MEASURE, NOT A CONVENIENCE. `stop` resolves its victims
#     with `pgrep -f` over the WHOLE MACHINE. A harness that let the real `pgrep` through would match the
#     owner's actual daemon and actual resume session and TERM both — the harness would BE the incident. The
#     stub calls the real `pgrep` (so the real pattern matching is genuinely exercised) and then keeps only
#     pids whose command line contains this run's temp directory, i.e. only processes this harness created.
#     Nothing outside $T can be returned to `stop`, whatever is running on the machine.
#   * no suite, no build, no swiftc: every stand-in process is /bin/sleep.
#
# ⚠️ INTERPOSITION IS BY BASH_ENV, NOT $PATH — daemon.sh line 36 exports
#     PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
# which puts the SYSTEM directories AHEAD of anything prepended here, so a $T/bin/launchctl stub would be
# shadowed by /bin/launchctl. Functions beat PATH lookups. preflight() PROVES the interposition works before
# any stop is run, and aborts if it does not — the one check that must never be taken on trust, because a
# harness that quietly drove the real machine while looking sandboxed is worse than no harness.
#
# ⚠️ KNOWN COSMETIC ARTIFACT, UNATTRIBUTED — recorded rather than hidden. Every run prints macOS's `pkill` and
# `pgrep` usage screens once each, on stderr, before the first section's output. What was established about it:
#   * it is NOT the stubs. §[8] asserts no pgrep/pkill call was made without a pattern, and it passes.
#   * a PATH shim traced one of them to a `$( )` SUBSHELL of this harness (parent and grandparent both
#     `bash prove-stop.sh`), yet `bash -x` over the harness records zero pgrep/pkill invocations.
#   * it affects no assertion: all 20 pass with it present, and §[0] separately asserts the sandbox probe
#     itself writes nothing to stderr.
# Those two observations do not reconcile, and I could not attribute the call. It is left documented rather
# than suppressed with a blanket `2>/dev/null`, because silencing an unexplained message is how a real one gets
# missed later — the same reasoning §[0]'s stderr assertion exists for. If you are here because you saw it: it
# is expected, it is harmless, and finding the caller is still worth doing.
#
# USAGE:  ops/autonomous/tests/prove-stop.sh [path/to/daemon.sh]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DAEMONSH="${1:-$HERE/../daemon.sh}"
[ -f "$DAEMONSH" ] || { echo "no daemon.sh at $DAEMONSH"; exit 2; }
T="$(mktemp -d)"
STATE="$T/state"; mkdir -p "$STATE"
LOCKDIR="$STATE/test.lock"

PASS=0; FAIL=0
GRN=$'\033[32m'; RED=$'\033[31m'; OFF=$'\033[0m'
ok()  { PASS=$((PASS+1)); echo "  ${GRN}PASS${OFF} $1"; }
bad() { FAIL=$((FAIL+1)); echo "  ${RED}FAIL${OFF} $1"; }

# Every stand-in process this harness starts, so cleanup is total even on a Ctrl-C. `sleep 9763xx` argvs are
# unique to this file so a stray one is identifiable, and the reap is guarded on the sleep name so a RECYCLED
# pid is never killed.
PIDS=""
track() { PIDS="$PIDS $1"; }
cleanup() {
  local p
  for p in $PIDS; do
    case "$(ps -o command= -p "$p" 2>/dev/null)" in *sleep\ 9873*) kill -KILL "$p" 2>/dev/null ;; esac
  done
  # …and anything whose argv names THIS sandbox: the wrappers (`bash $T/inside-probe.sh`, the fake loop, the
  # stand-in suite), which the $PIDS loop cannot match because their argv is a path, not a sleep.
  # Keyed on $T, so it can only ever match processes this run created.
  pkill -f "$T" >/dev/null 2>&1
  # ⚠️ AND THE WRAPPERS' OWN `sleep` CHILDREN, which is the leak this line exists for. Measured after this
  # harness's first six runs: THIRTY orphaned `sleep` processes, up to 1h54m old. The two sweeps above are
  # both blind to them — a child's argv is bare ("sleep 976398"), so it carries no $T, and only the wrapper
  # pid was ever tracked. Killing a wrapper does not take its children: that is D2's lesson, and this file
  # reproduced it two hours after documenting it, which is exactly why prove-daemon.sh's header records the
  # same class ("four orphaned sandboxes after four pkill'd runs").
  # A tree walk cannot fix it here — by cleanup time the wrappers may already be dead and their children
  # reparented to init, so ancestry is gone. The number range IS the identity instead: 9763xx is unique to
  # this file, deliberately disjoint from prove-daemon.sh's 98732x/987654, so this cannot reach across to a
  # sibling harness even if one were running (they must not run concurrently for other reasons — see the
  # header).
  pkill -f 'sleep 9763' >/dev/null 2>&1
  rm -rf "$T"
}
trap cleanup EXIT INT TERM

# ---- the stubs, injected as functions -------------------------------------------------------------------
cat > "$T/preload.sh" <<PRELOAD
launchctl() { echo "launchctl \$*" >> "$T/launchctl.log"; return 0; }
# See the header: this is the safety belt. Real pattern matching, sandbox-only results.
pgrep() {
  local out p pat=""
  for p in "\$@"; do case "\$p" in -*) ;; *) pat="\$p" ;; esac; done
  # A bare call is a usage error in the real tool, and letting it through printed macOS's two-screen usage
  # text onto the harness's stderr, where it read as a harness fault. Refuse it the way the real one does —
  # exit 2, no matches — and RECORD it, so a caller that has lost its pattern is visible rather than silent.
  [ -n "\$pat" ] || { echo "pgrep called with no pattern: \$*" >> "$T/badcall.log"; return 2; }
  out="\$(command pgrep "\$@" 2>/dev/null)" || true
  for p in \$out; do
    case "\$(ps -o command= -p "\$p" 2>/dev/null)" in
      *"$T"*) echo "\$p" ;;
    esac
  done
}
# ⚠️ pkill MUST BE STUBBED TOO, and forgetting it is not a small mistake. The PRE-FIX daemon.sh — which this
# harness must be able to run, because "watch the test fail first" is the house rule — kills with four bare
# `pkill -f` lines, and a `pgrep`-only stub does not intercept a single one of them. Running the old code
# against a live machine would have TERMed the owner's real daemon and real resume session: the harness would
# have reproduced the incident rather than detecting it. Same filter, so pkill can only ever reach this
# sandbox, and it reports "did I match anything" through its exit status exactly as the real one does.
pkill() {
  local sig="-TERM" pat="" hit=0 p
  while [ \$# -gt 0 ]; do
    case "\$1" in
      -f) shift ;;
      -[0-9]*|-[A-Z]*) sig="\$1"; shift ;;
      *) pat="\$1"; shift ;;
    esac
  done
  [ -n "\$pat" ] || { echo "pkill called with no pattern: \$*" >> "$T/badcall.log"; return 2; }
  for p in \$(pgrep -f "\$pat"); do hit=1; command kill "\$sig" "\$p" 2>/dev/null; done
  [ "\$hit" = 1 ]
}
export -f launchctl pgrep pkill
PRELOAD

run_stop() {
  VISIONOCR_STATE="$STATE" VISIONOCR_TEST_LOCK="$LOCKDIR" \
    BASH_ENV="$T/preload.sh" bash "$DAEMONSH" stop 2>&1
}

# ---- stand-in processes ---------------------------------------------------------------------------------
# A fake daemon loop: its own path carries the pattern `stop` greps for AND $T, so the pgrep stub returns it.
# It spawns a grandchild and waits, which is the shape that broke — the expensive work in this repo is always
# at least two levels below the process whose argv matches.
mk_fake_loop() {   # echoes "parentpid grandchildpid"
  cat > "$T/vision-ocr-autonomous.sh" <<'LOOP'
#!/usr/bin/env bash
sleep 976301 &          # stands in for test-lock.sh -> run_tests.sh -> build/tests
echo "$!" > "$1"
sleep 976302
LOOP
  chmod +x "$T/vision-ocr-autonomous.sh"
  bash "$T/vision-ocr-autonomous.sh" "$T/gc.pid" >/dev/null 2>&1 &
  local pp=$!; track "$pp"
  local gc="" i
  for i in 1 2 3 4 5 6 7 8 9 10; do gc="$(cat "$T/gc.pid" 2>/dev/null)"; [ -n "$gc" ] && break; sleep 0.3; done
  track "$gc"
  echo "$pp $gc"
}

echo "prove-stop.sh — driving $DAEMONSH"
echo

# ---- preflight: the interposition must actually intercept -----------------------------------------------
echo "[0] SANDBOX INTEGRITY — the stubs must intercept under daemon.sh's own PATH"
: > "$T/launchctl.log"
outside=$( { sleep 976399 >/dev/null 2>&1 & } ; echo $! ); track "$outside"
# ⚠️ TWO CONTROLS, NOT ONE, and the positive one is the reason this block was rewritten. The first version
# asserted only that the OUTSIDE pid was absent from the probe — which an EMPTY probe satisfies, for any
# reason at all: a stub that failed to load, a usage error, a typo in the pattern. It was a check that could
# not fail, guarding the one thing this harness must never get wrong, and it sat directly above `exit 3`.
# So: a NEGATIVE control (the outside process must be invisible) AND a POSITIVE one (a process inside $T must
# be visible). Only both together distinguish "correctly filtered" from "returned nothing".
# ⚠️ THE TWO CONTROLS NEED TWO PATTERNS, and the first attempt got this wrong in a way worth recording. It
# used one pattern (`sleep 97639`) for both, expecting it to match the inside process and not the outside one.
# It matched NEITHER, and the positive control caught that and aborted: the filter keys on whether a
# process's ARGV contains $T, and a `sleep 976398` process's argv is just "sleep 976398" — the sandbox path is
# in its PARENT's argv, not its own. So the inside marker has to be matched by the pattern that names the
# SCRIPT (`inside-probe.sh`, whose argv is "bash $T/inside-probe.sh" and therefore carries both), while the
# outside control stays a bare `sleep` that legitimately carries no $T at all.
inside_marker="$T/inside-probe.sh"
printf '#!/usr/bin/env bash\nsleep 976398\n' > "$inside_marker"; chmod +x "$inside_marker"
bash "$inside_marker" >/dev/null 2>&1 &
inside=$!; track "$inside"
sleep 0.5
probe="$(VISIONOCR_STATE="$STATE" BASH_ENV="$T/preload.sh" bash -c '
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
  launchctl bootout gui/0/probe >/dev/null 2>&1
  echo "POS:$(pgrep -f "inside-probe.sh" | tr "\n" " ")"
  echo "NEG:$(pgrep -f "sleep 976399" | tr "\n" " ")"
' 2>"$T/probe.stderr")"
[ -s "$T/launchctl.log" ] \
  && ok "launchctl is the stub, even after daemon.sh's PATH export (no real bootout)" \
  || { bad "launchctl NOT intercepted — refusing to run, this would bootout the owner's real job"; exit 3; }
pos_line="$(printf '%s\n' "$probe" | sed -n 's/^POS://p')"
neg_line="$(printf '%s\n' "$probe" | sed -n 's/^NEG://p')"
case " $pos_line " in
  *" $inside "*) ok "the sandboxed pgrep DOES see a process inside \$T (positive control: the probe works)" ;;
  *) bad "the probe found nothing inside the sandbox — the filter is untestable, so this harness would prove nothing about it"
     echo "        POS='$pos_line'  stderr='$(tr -d '\n' < "$T/probe.stderr" 2>/dev/null)'"; exit 3 ;;
esac
case " $neg_line " in
  *" $outside "*) bad "pgrep stub returned a process outside the sandbox — refusing to run"; exit 3 ;;
  *) ok "…and does NOT see one outside it (negative control: stop cannot reach the owner's processes)" ;;
esac
# Any stderr from the probe is a fault in this harness, not in daemon.sh, and must not be shrugged off: an
# unexplained macOS usage screen in a test run teaches the reader to ignore output, which is how a real
# message gets missed later.
[ -s "$T/probe.stderr" ] \
  && { bad "the probe wrote to stderr — a stub was bypassed or a pattern was lost:"; sed 's/^/        /' "$T/probe.stderr"; } \
  || ok "the probe produced no stderr (no stub was bypassed)"
kill -KILL "$inside" 2>/dev/null
# And the same proof for pkill, because the PRE-FIX daemon.sh kills exclusively through it: a pgrep-only
# sandbox would let the old code loose on the machine. Assert the outside process is STILL ALIVE after a
# pkill aimed squarely at its argv.
VISIONOCR_STATE="$STATE" BASH_ENV="$T/preload.sh" bash -c '
  export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/usr/sbin:/sbin:/bin:${PATH:-}"
  pkill -f "sleep 976399" >/dev/null 2>&1' || true
sleep 0.5
kill -0 "$outside" 2>/dev/null \
  && ok "pkill is filtered too — the pre-fix code cannot reach outside this sandbox" \
  || { bad "pkill REACHED OUTSIDE THE SANDBOX — refusing to run, this would kill the owner's daemon"; exit 3; }
kill -KILL "$outside" 2>/dev/null

# ---- [1] the tree, not the process ----------------------------------------------------------------------
echo "[1] A STOP KILLS THE WHOLE TREE (the 2026-08-17 orphan, D2)"
read -r PP GC <<<"$(mk_fake_loop)"
if [ -z "${GC:-}" ]; then
  bad "the fake loop's grandchild never started — the section would have been vacuous"
else
  ok "fake loop $PP with grandchild $GC is running (assertions below are not vacuous)"
  touch "$STATE/engine.lock"
  out="$(run_stop)"
  gone=0; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do kill -0 "$GC" 2>/dev/null || { gone=1; break; }; sleep 1; done
  [ "$gone" = 1 ] && ok "the GRANDCHILD died — a suite/build two levels down is no longer orphaned" \
                  || bad "GRANDCHILD $GC SURVIVED — this is exactly the D2 defect (pkill -f killed the parent only)"
  kill -0 "$PP" 2>/dev/null && bad "the matched parent survived its own stop" || ok "the matched parent died too"
  case "$out" in
    *"TERMed"*process*) ok "the report says how many processes it TERMed, not just \"daemon stopped\"" ;;
    *) bad "no process count in the output — the owner cannot tell a loop-only stop from a full teardown: $out" ;;
  esac
  # ---- [5] engine.lock ---------------------------------------------------------------------------------
  echo "[5] ENGINE.LOCK IS CLEARED, so a restart works on its first cycle (D4)"
  [ -f "$STATE/engine.lock" ] \
    && bad "engine.lock survived the stop — a restart logs 'engine busy — skip' until it ages out \$STALE" \
    || ok "engine.lock cleared"
  case "$out" in *engine.lock*cleared*) ok "…and says so, so the owner knows a restart is clean" ;;
    *) bad "cleared it silently — the one fact that explains why a restart is immediate" ;; esac
fi

# ---- [2]+[4] the owner's own suite is untouchable -------------------------------------------------------
echo "[2] THE OWNER'S OWN SUITE IS NEVER KILLED, AND ITS LOCK IS NEVER BROKEN (D2 ⛔ / D3 converse)"
# ⚠️ THE STAND-IN HAS TO LOOK LIKE A SUITE, or this section cannot fail. A bare `sleep 976310` has no $T in
# its argv, so the pgrep stub would filter it out and it would survive no matter what `stop` did — a check
# that passes because of the sandbox rather than because of the code, which is the exact shape this project
# calls a check that cannot fail. So the stand-in is `bash $T/owner-suite/run_tests.sh`: its argv carries $T,
# the stub therefore CAN return it, and the only thing keeping it alive is that `stop` refuses to kill what it
# cannot trace to the daemon. Reintroduce a `pkill -f run_tests.sh` sweep and this goes red immediately.
mkdir -p "$T/owner-suite"
printf '#!/usr/bin/env bash\nsleep 976310\n' > "$T/owner-suite/run_tests.sh"
chmod +x "$T/owner-suite/run_tests.sh"
bash "$T/owner-suite/run_tests.sh" >/dev/null 2>&1 &
mine=$!; track "$mine"
sleep 0.5
# Prove the premise: the stub CAN see it, so its survival below is a fact about `stop`, not about the sandbox.
seen="$(VISIONOCR_STATE="$STATE" BASH_ENV="$T/preload.sh" bash -c 'pgrep -f "run_tests.sh" | tr "\n" " "')"
case "$seen" in
  *"$mine"*) ok "the stand-in suite IS visible to the sandboxed pgrep (so [2] can actually fail)" ;;
  *) bad "the stand-in is invisible to pgrep — [2] would be vacuous; fix the harness, not the daemon" ;;
esac
mkdir -p "$LOCKDIR"; echo "$mine" > "$LOCKDIR/pid"; echo "owners-interactive-suite" > "$LOCKDIR/label"
out="$(run_stop)"
sleep 1
kill -0 "$mine" 2>/dev/null \
  && ok "it is still alive — a stop cannot touch the owner's own \`./run_tests.sh\`" \
  || bad "KILLED THE OWNER'S SUITE — the one thing this verb must never do"
# ⚠️ DELIBERATELY NOT AN ASSERTION ABOUT THE NEW WORDING. The pre-fix code got THIS case right — a foreign
# lock was correctly LEFT ALONE — and its defect (D3) was that it said the same thing about its OWN child,
# so the two cases were indistinguishable. Asserting the new prose here would fail the old code for a case
# it handled correctly and would misattribute the defect. What must hold in BOTH versions is only this: it
# must never claim a foreign lock as ours. §[3] is where the discriminating assertion lives.
case "$out" in
  *"just TERMed"*|*"it IS"*ours*) bad "claimed an unrelated owner's lock as ours — would break a live interactive suite" ;;
  *"LEFT ALONE"*) ok "a foreign-held lock is LEFT ALONE (correct in both the old and the fixed code)" ;;
  *) bad "no verdict at all on a foreign-held lock: $out" ;;
esac
kill -KILL "$mine" 2>/dev/null; rm -rf "$LOCKDIR"

# ---- [3] a lock held by something we killed IS ours ----------------------------------------------------
echo "[3] A LOCK HELD BY A PROCESS THIS STOP KILLED IS REPORTED AS OURS (D3)"
read -r PP GC <<<"$(mk_fake_loop)"
if [ -z "${GC:-}" ]; then
  bad "fake loop did not start — section vacuous"
else
  mkdir -p "$LOCKDIR"; echo "$GC" > "$LOCKDIR/pid"; echo "mutants-C24-override" > "$LOCKDIR/label"
  out="$(run_stop)"
  case "$out" in
    *"just TERMed"*|*"it IS"*) ok "named as ours, with the label, and no action demanded of the owner" ;;
    *"LEFT ALONE"*) bad "STILL SAYS 'not ours to break' ABOUT ITS OWN CHILD — this is the D3 misreport verbatim" ;;
    *) bad "no verdict for a lock held by a killed descendant: $out" ;;
  esac
  case "$out" in *mutants-C24-override*) ok "…and quotes the holder's LABEL, not just a pid" ;;
    *) bad "the label is what tells the owner what was running; it is missing" ;; esac
fi
rm -rf "$LOCKDIR"

# ---- [6] a reader of the file is not an execution of it ------------------------------------------------
echo "[6] A PROCESS MERELY READING health-gate.sh IS NOT KILLED (the reader guard)"
# `pgrep -f` matches any argv CONTAINING the pattern, so an owner with `tail -f` on the gate script used to
# be a candidate for the kill — and with tree-killing, so were its children. CLAUDE.md calls this the
# instrument measuring itself.
mkdir -p "$T/ops/autonomous"; : > "$T/ops/autonomous/health-gate.sh"
tail -f "$T/ops/autonomous/health-gate.sh" >/dev/null 2>&1 &
reader=$!; track "$reader"
sleep 0.5
out="$(run_stop)"
sleep 1
if kill -0 "$reader" 2>/dev/null; then
  ok "the reader survived — argv containing a path is not the same as running it"
else
  bad "KILLED A PROCESS THAT WAS ONLY READING health-gate.sh (reader guard not working)"
fi
kill -KILL "$reader" 2>/dev/null

# ---- [7] stop never kills itself or its caller ---------------------------------------------------------
echo "[7] A STOP NEVER KILLS ITSELF OR THE SHELL THAT INVOKED IT"
# The strongest available evidence: this harness is still executing, and a marker child of THIS shell — which
# `stop` walked past while collecting trees — is still alive after two stops.
marker=$( { sleep 976320 >/dev/null 2>&1 & } ; echo $! ); track "$marker"
out="$(run_stop)"; sleep 1
kill -0 "$marker" 2>/dev/null && ok "this harness's own child survived (stop excluded itself and its ancestors)" \
                              || bad "stop killed a child of the invoking shell — it swept up its own caller"
ok "this harness reached its own end, so no stop terminated the process running it"

# ---- the harness must not have misused its own stubs ----------------------------------------------------
echo "[8] THE HARNESS ITSELF MADE NO MALFORMED pgrep/pkill CALL"
if [ -s "$T/badcall.log" ]; then
  bad "a pattern-less pgrep/pkill call happened — a caller lost its pattern:"
  sed 's/^/        /' "$T/badcall.log"
else
  ok "every pgrep/pkill call carried a pattern"
fi

echo
echo "=================== $PASS passed, $FAIL failed ==================="
[ "$FAIL" = 0 ]
