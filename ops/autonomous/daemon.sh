#!/usr/bin/env bash
# ops/autonomous/daemon.sh — ONE-COMMAND prep + launch + verify for the autonomous run.
#
# Collapses the whole "start the daemon" dance — install the runtime copies, check every prerequisite,
# guard the stale-COMPLETE and double-launch footguns, launch detached, verify the first cycle actually
# started — into a single command, so none of it ever has to be re-derived from README.md again.
#
# Run from a checkout; THIS script's checkout is the one the daemon will work in:
#   ./ops/autonomous/daemon.sh start      # install + check prereqs + launch under launchd KeepAlive, so a
#                                         #   crash / OOM / stray kill auto-restarts. Best for a long run.
#   ./ops/autonomous/daemon.sh            # same thing — a BARE invocation means `start`.
#   ./ops/autonomous/daemon.sh keepalive  # explicit alias for the default, for when you want it in writing.
#   ./ops/autonomous/daemon.sh stop       # bootout the launchd job FIRST, then kill the daemon + its children
#   ./ops/autonomous/daemon.sh status     # read-only; extra args pass through (e.g. `status --details`)
#   ./ops/autonomous/daemon.sh nohup      # opt-in: detached nohup, NO crash-restart
#   ./ops/autonomous/daemon.sh --dry-run [verb]   # resolve the mode and exit, installing/launching nothing
#
# Ported from `Archive Suite/ops/autonomous/daemon.sh`. What is DIFFERENT here, and why:
#   * there is no L0 plan file to check. This project's queue is COMMITTED (`ops/autonomous/QUEUE.md`) and
#     its run state is a small per-machine file ($STATE/RUN.md), so `start` checks two things rather than
#     one — and the queue question is delegated to `next-item.sh` instead of grepping for `[ ]` here. That
#     resolver tells four outcomes apart (actionable / drained / all blocked / malformed) and this script
#     must react DIFFERENTLY to each; a grep cannot see the difference between the last three.
#   * `stop` kills FOUR patterns, not three: this daemon also runs a run-log compactor between cycles.
#   * `start` reports the SUITE LOCK before launching, because this project cannot run two test suites at
#     once (CLAUDE.md's first environment trap) and a daemon that is waiting looks identical to one stuck.
#   * `status` prints NOTHING of its own — see status(), which is where that decision is argued.
set -uo pipefail

# ⚠️ EXPLICIT PATH, for exactly the reason the daemon and the plist each set one. vision-ocr's CLAUDE.md
# lists it as an environment trap: "Backgrounded shell commands have essentially no PATH — basename, cut,
# timeout fail silently and loops report bogus results." This script is routinely run from an agent's
# backgrounded shell, and with no PATH every check below (`pgrep`, `install`, `plutil`, `git`, `sed`) would
# fail SILENTLY — and each failure would then be read as "the prerequisite is missing" rather than "the tool
# that checks it is missing", which is the more expensive of the two mistakes.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# Escape a string for use as the REPLACEMENT half of `sed s|…|…|`. Only `&` and `\` are special there (`|`
# cannot appear in an absolute path we would render). Without this, a checkout under a directory containing
# `&` — legal on macOS — renders the placeholder back INTO ITSELF: `/Users/x/R&D/vision-ocr` turns
# `__REPO__` into `/Users/x/R__REPO__D/vision-ocr` in both the resume prompt and the plist, and `plutil
# -lint` cannot see that at all because the result is still well-formed XML.
sed_repl() { printf '%s' "$1" | sed -e 's/[\\&]/\\&/g'; }

# ===== CONFIG — every value here is the daemon's, not this script's ======================================
# vision-ocr-autonomous.sh is the CONTRACT: it decides where state lives, what the job is called and which
# env var it needs. Everything below is read off that file, so a change there must be mirrored here.
REPO="$(cd "$(dirname "$0")/../.." && pwd)"        # this script's checkout = where the daemon works
STATE="${VISIONOCR_STATE:-$HOME/.local/state/visionocr-autonomous}"
STATE_DEFAULT="$HOME/.local/state/visionocr-autonomous"   # what the plist hardcodes; see the keepalive lane
BIN="$HOME/.local/bin"
CLAUDE="$BIN/claude"
DAEMON_SRC="$REPO/ops/autonomous/vision-ocr-autonomous.sh"
DAEMON_DST="$BIN/vision-ocr-autonomous.sh"
COMPACT_SRC="$REPO/ops/autonomous/compact-runlog.sh"
COMPACT_DST="$BIN/compact-runlog.sh"              # the daemon's $COMPACTOR default
PROMPT_SRC="$REPO/ops/autonomous/resume-prompt.txt"
PROMPT_DST="$STATE/resume-prompt.txt"             # the daemon's $PROMPT
RUN="$STATE/RUN.md"                               # the daemon's $RUN
QUEUE="$REPO/ops/autonomous/QUEUE.md"
LOG="$STATE/daemon.log"
# Resolved the way the DAEMON resolves it (`export VISIONOCR_TEST_LOCK="${VISIONOCR_TEST_LOCK:-$STATE/test.lock}"`),
# so `stop` and the pre-launch report look at the same directory the gate will actually take. ⚠️ test-lock.sh's
# OWN default is the hardcoded ~/.local/state/visionocr-autonomous/test.lock — it does not derive from $STATE —
# so this must be passed in explicitly on every call, or an overridden $STATE silently consults a different lock.
LOCKDIR="${VISIONOCR_TEST_LOCK:-$STATE/test.lock}"
NEXT="$REPO/ops/autonomous/next-item.sh"
DIGEST="$REPO/ops/autonomous/status-digest.sh"
TESTLOCK="$REPO/ops/autonomous/test-lock.sh"
JOB="com.visionocr.autonomous"                    # launchd label: matches the .plist AND the daemon's $JOB
PLIST_SRC="$REPO/ops/autonomous/$JOB.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$JOB.plist"
GUI_DOMAIN="gui/$(id -u)"                         # per-user launchd domain for a LaunchAgent
# The daemon builds its $JOB from `com.${VISIONOCR_LABEL:-visionocr}.autonomous`, but the plist's `Label` is
# COMMITTED TEXT, so the label cannot follow that override. Say so rather than launching a job whose label
# does not match the one the daemon boots out when it parks.
if [ -n "${VISIONOCR_LABEL:-}" ] && [ "${VISIONOCR_LABEL}" != "visionocr" ]; then
  echo "⚠️  VISIONOCR_LABEL='$VISIONOCR_LABEL' is set, but the plist's Label is the committed literal '$JOB'." >&2
  echo "    The daemon would then bootout 'com.${VISIONOCR_LABEL}.autonomous' — a job launchd never" >&2
  echo "    registered — so park and RUN-STATUS-COMPLETE would fail to stop it and KeepAlive would" >&2
  echo "    relaunch it. Unset VISIONOCR_LABEL, or edit the plist's Label to match." >&2
fi
# =======================================================================================================

# The daemon's own terminal check is `grep -q '^RUN STATUS: COMPLETE'` — anchored at COLUMN 0, no leading
# whitespace tolerated. Match it CHARACTER FOR CHARACTER: a looser pattern here would refuse to start over
# an indented line the daemon will never act on, and a tighter one would let the stale-COMPLETE footgun
# through. (An indented "COMPLETE" is therefore invisible to BOTH — a run-state file worth fixing, not
# something for this script to paper over.)
runstatus() { grep -m1 '^RUN STATUS:' "$RUN" 2>/dev/null | cut -c1-90; }

# status — ONE renderer, in status-digest.sh. This function only forwards to it and adds NO formatting.
#
# In the project this was ported from, this function printed six sections of its own (process, run state,
# plan, GUI, keychain, log tail) and THEN pasted the whole digest underneath: the run state appeared TWICE,
# in two different wordings, and a reader had to already know which of the two copies was the current one.
# A fix to one wording never reached the other. So: no formatting lives here. `--details` and anything else
# passes straight through to the digest, which owns the whole vocabulary.
status() {
  if [ -x "$DIGEST" ]; then
    # Pass all three paths explicitly. The digest defaults REPO to ~/Claude/vision-ocr, so from a worktree it
    # would otherwise describe a DIFFERENT checkout than the one this script installs from — the sort of
    # wrong-but-plausible report this project's whole process exists to stop. The lock path goes too because
    # the digest asks test-lock.sh, whose own default is hardcoded and does not follow $STATE.
    VISIONOCR_REPO="$REPO" VISIONOCR_STATE="$STATE" VISIONOCR_TEST_LOCK="$LOCKDIR" "$DIGEST" "$@"
  else
    # Never leave the owner with nothing: this is the command you run WHEN THINGS ARE ALREADY BROKEN, so a
    # missing renderer must degrade to the two facts that matter rather than to an error.
    echo "status-digest.sh is missing or not executable at:"
    echo "  $DIGEST"
    echo
    if pgrep -f vision-ocr-autonomous.sh >/dev/null 2>&1; then
      echo "The worker IS running (pid $(pgrep -f vision-ocr-autonomous.sh | head -1))."
    else
      echo "The worker is NOT running. Start it: $0"
    fi
    tail -n 8 "$LOG" 2>/dev/null
  fi
}

fail() { echo "ERROR: $*" >&2; exit 1; }

# Optional `--dry-run`, accepted ONLY as the first arg: resolve the verb + launch mode, say so, and exit
# before anything is installed, rendered, launched or killed.
#
# An EXPLICIT FLAG and deliberately NOT an env var: an env var could be exported once while iterating in a
# shell and then silently turn a real `daemon.sh` into a success-reporting no-op for the rest of the
# session — the owner would read "would launch in mode 'keepalive'" as a launch. A flag you have to type
# cannot be inherited, and cannot be forgotten in a profile.
DRYRUN=""
if [ "${1:-}" = "--dry-run" ]; then DRYRUN=1; shift; fi

# Resolve the verb FIRST and reject anything unknown, with the list. Never alias a typo to `start`: this
# command's default action launches a budget-spending unattended run, so a misspelling must stop rather
# than do the most expensive plausible thing.
VERB="${1:-start}"
case "$VERB" in
  start|keepalive|nohup|stop|status) ;;
  *) fail "unknown command '$VERB'. Use one of: start | stop | status | nohup | keepalive
  (a bare '$0' means start; '--dry-run' is accepted only as the FIRST argument)" ;;
esac
MODE=""
case "$VERB" in
  start|keepalive) MODE=keepalive ;;   # DEFAULT: launchd KeepAlive, so a crash/OOM/kill auto-restarts.
  nohup)           MODE=nohup ;;       # opt-in: detached, no crash-restart.
esac

# LOUD and unmistakable, so a preview is never mistaken for a real start. Note that `--dry-run stop` also
# stops here: a dry run that kills processes is not a dry run.
if [ -n "$DRYRUN" ]; then
  case "$VERB" in
    status|stop) echo "=== DRY RUN === verb '$VERB' resolved; its path was NOT run. NOTHING installed, launched or killed." ;;
    *)           echo "=== DRY RUN === would launch in mode '$MODE' — NOTHING installed, rendered or launched." ;;
  esac
  exit 0
fi

case "$VERB" in
  status) shift || true; status "$@"; exit 0 ;;   # extra args pass through to the digest
  stop)
    # `launchctl bootout` FIRST, then kill. Under KeepAlive=true a bare `pkill` is not a stop at all —
    # launchd relaunches the daemon within ThrottleInterval, so killing before de-registering the job just
    # costs a cycle and leaves the owner sure they stopped something. Harmless no-op in the `nohup` lane,
    # where no such job exists.
    booted=0
    launchctl bootout "$GUI_DOMAIN/$JOB" 2>/dev/null && { booted=1; echo "launchd job booted out."; }

    # FOUR patterns, because each names a SEPARATE orphan class that the other three do not match. Dropping
    # any one of them leaves something running that the owner believes they stopped:
    #   (a) the daemon loop itself;
    #   (b) the resume session — a bare `claude -p` whose argv is the PROMPT TEXT, so the script-name
    #       pattern cannot see it. Killing only (a) reparents it to init, where it runs on against stale
    #       state (the repeated-orphan bug). ⚠️ CROSS-FILE CONTRACT: the phrase below must appear VERBATIM
    #       in ops/autonomous/resume-prompt.txt. If that prompt is reworded, this pattern must move with it,
    #       or `stop` starts silently leaving a live budget-spending session behind.
    #   (c) an in-flight health gate — `bash health-gate.sh` -> build + suite, matched by NEITHER of the
    #       above (same bare-child class as (b)), so without it `stop` leaves a full build and a ~40 min
    #       suite running, holding the suite lock for the best part of an hour;
    #   (d) the run-log compactor, which the daemon runs BETWEEN cycles, i.e. exactly when the loop is not
    #       inside a session and a `stop` is most likely to land.
    # None of these patterns can match daemon.sh itself, nor an interactive Claude session.
    k=0
    pkill -f 'vision-ocr-autonomous\.sh'                        >/dev/null 2>&1 && { k=1; echo "daemon loop stopped."; }
    pkill -f 'autonomous maintenance session for Vision OCR'    >/dev/null 2>&1 && { k=1; echo "in-flight resume session stopped."; }
    pkill -f 'ops/autonomous/health-gate\.sh'                   >/dev/null 2>&1 && { k=1; echo "in-flight health gate stopped (its build + suite go with it)."; }
    pkill -f 'compact-runlog\.sh'                               >/dev/null 2>&1 && { k=1; echo "in-flight run-log compactor stopped."; }
    # Three outcomes, and two of them used to read alike. "Booted out but nothing to kill" is a NORMAL
    # state (a crashed daemon inside ThrottleInterval, or one that parked itself), and it is not the same
    # answer as "there was nothing here at all".
    if   [ "$k" = 1 ];      then echo "daemon stopped."
    elif [ "$booted" = 1 ]; then echo "launchd job stopped — its process was already down (crash window, or it had parked itself)."
    else                         echo "daemon was not running."; fi

    # ⚠️ RELEASE THE SUITE LOCK, but only if it is ours to release. A health gate we just killed cannot run
    # its own EXIT trap, so it can leave the lock dir behind — and a lock nobody owns is invisible: it does
    # not show up as a running process, only as later suites refusing to start.
    # test-lock.sh's `release` REFUSES when the recorded holder pid is not its own, which is precisely the
    # behaviour wanted here: it must never break the lock out from under the owner's interactive suite. So
    # the refusal is not an error to work around — it is the answer, and the useful thing this branch adds
    # is telling the owner WHICH refusal they got. (Read test-lock.sh: a holder pid that no longer exists is
    # reclaimed on the very next `acquire`, without waiting out MAXAGE, so a dead holder needs no action.)
    if [ -d "$LOCKDIR" ]; then
      hp="$(cat "$LOCKDIR/pid" 2>/dev/null)"
      if [ -x "$TESTLOCK" ] && VISIONOCR_TEST_LOCK="$LOCKDIR" "$TESTLOCK" release 2>/dev/null; then
        echo "suite lock released."
      elif [ -n "$hp" ] && kill -0 "$hp" 2>/dev/null; then
        echo "suite lock LEFT ALONE — pid $hp holds it and is still ALIVE, so it is not ours to break."
        echo "  If that is your own \`./run_tests.sh\`, nothing to do. Otherwise: $TESTLOCK status"
      else
        echo "suite lock: holder pid ${hp:-?} is gone, so the lock is STALE — no action needed."
        echo "  test-lock.sh reclaims a dead holder on the next acquire, without waiting out its MAXAGE."
        echo "  Confirm with: $TESTLOCK status"
      fi
    fi
    exit 0 ;;
esac

# ================================ start ================================================================
# 1. PREREQUISITES — each failure names the fix, because "missing" alone sends the owner reading README.md.
[ -x "$CLAUDE" ] || fail "claude CLI not executable at $CLAUDE — install or symlink it there.
  It MUST live outside ~/Desktop: a launchd-context bash cannot exec anything under Desktop (TCC). It dies
  with 'Operation not permitted', which the loop cannot distinguish from a failed session, so the daemon
  would silently no-op EVERY cycle."
[ -f "$DAEMON_SRC" ] || fail "daemon script missing: $DAEMON_SRC
  Either this is not a vision-ocr checkout, or ops/autonomous/ has not been merged into it."
[ -f "$PROMPT_SRC" ] || fail "resume prompt missing: $PROMPT_SRC
  The daemon feeds this file to every session; there is nothing to run without it. See ops/autonomous/README.md."
[ -f "$RUN" ] || fail "no run-state file at $RUN
  Create it FIRST — the daemon refuses to run blind, and RUN.md is deliberately NOT in the repo (it is
  per-machine run state, not source). Copy the template, then edit its '## FOCUS' section:
      cp $REPO/ops/autonomous/RUN.md.template '$RUN'
  It needs, at minimum, one COLUMN-0 line — plain text, never markdown, because the daemon greps for it:
      RUN STATUS: IN_PROGRESS — <one-line note about this run>
  The rest of the shape (## FOCUS, ## HOLD, ## SESSION LOG) is in ops/autonomous/README.md."
[ -f "$QUEUE" ] || fail "queue missing: $QUEUE
  It is committed, so a checkout without it is incomplete — check you are on a branch that has it."
[ -x "$NEXT" ] || fail "queue resolver missing or not executable: $NEXT
  It decides whether there is work at all; starting without it would mean starting blind."

# Is there anything to DO? Ask the resolver rather than grepping, and react differently to each of its four
# exit codes — collapsing any of them into "empty" is the misreport run-state-lib.sh exists to undo one
# level up. Its stderr is left visible on purpose: the malformed-queue case explains itself there.
items="$("$NEXT" "$REPO")"; nrc=$?
case "$nrc" in
  0) ;;   # actionable work exists — the only silent case
  3) fail "the queue is DRAINED: every item in $QUEUE is [x].
  Starting now would burn sessions to conclude there is nothing to do. Either add work to QUEUE.md, or
  finish the run by setting the marker in $RUN to:  RUN STATUS: COMPLETE — <why>" ;;
  2) fail "$NEXT could not parse $QUEUE (exit 2) — see its message above.
  That is a MALFORMED queue, not an empty one, so refusing is the point: a daemon started against an
  unreadable queue idles and eventually parks, blaming the wrong thing." ;;
  4) echo "⚠️  WARNING: items remain but EVERY one is blocked or held — nothing is actionable right now."
     printf '%s\n' "$items" | awk -F'\t' '$1 ~ /^blocked/ || $1 == "hold" { printf "      %-8s %-12s %s\n", $1, $2, substr($3, 1, 58) }'
     echo "    Starting anyway (this is a WARN, not a refusal — you may be about to unblock one). But expect"
     echo "    the daemon to find nothing, double its backoff each cycle, and PARK once VISIONOCR_IDLE_STOP"
     echo "    (72h by default) elapses. Unblocking something is the fix; adding more work is not." ;;
  *) echo "⚠️  WARNING: $NEXT exited $nrc, which is not one of its documented codes (0/2/3/4) — treating it"
     echo "    as 'unknown' and continuing. Check it by hand: $NEXT" ;;
esac
if [ "$nrc" = 0 ]; then
  echo "queue OK — the first items a session would be offered:"
  printf '%s\n' "$items" | awk -F'\t' '$1 == "ok" && n < 3 { printf "      %-12s %s\n", $2, substr($3, 1, 66); n++ }'
  nok="$(printf '%s\n' "$items" | awk -F'\t' '$1 == "ok" { n++ } END { printf "%d", n + 0 }')"
  [ "$nok" -gt 3 ] && echo "      … and $(( nok - 3 )) more actionable."
fi

# WARN, never refuse, on the hook: it is what refuses a commit whose tests fail, and it is the ONLY thing
# standing between an unattended session and pushing untested code. Its absence is a real risk but it is
# also a legitimate choice for a run that touches no code, so this is a warning with the one-line fix.
hooks="$(git -C "$REPO" config core.hooksPath 2>/dev/null)"
if [ "$hooks" != ".githooks" ]; then
  echo "⚠️  WARNING: core.hooksPath is '${hooks:-unset}', not '.githooks', in $REPO."
  echo "    .githooks/pre-commit is what refuses a commit whose tests fail. Without it an unattended"
  echo "    session can commit and PUSH untested code, and nothing downstream would notice."
  echo "    Fix (once per clone):  git config core.hooksPath .githooks"
fi

# 2. INSTALL the committed copies to the runtime location. The REPO is the source of truth; ~/.local/bin is
#    only a runtime cache, which is why this is unconditional rather than "if newer".
mkdir -p "$BIN" "$STATE"
install -m 755 "$DAEMON_SRC" "$DAEMON_DST" || fail "could not install $DAEMON_SRC -> $DAEMON_DST"
if [ -f "$COMPACT_SRC" ]; then
  install -m 755 "$COMPACT_SRC" "$COMPACT_DST" || fail "could not install $COMPACT_SRC -> $COMPACT_DST"
else
  # WARN, not a refusal: the daemon already degrades when $COMPACTOR is absent (it only runs it when the
  # file is executable). What is lost is bounded and worth naming — RUN.md's SESSION LOG grows without
  # limit, so every fresh session pays more to orient itself before it does any work.
  echo "⚠️  WARNING: no run-log compactor at $COMPACT_SRC — not installed."
  echo "    The daemon degrades cleanly (it skips a missing \$COMPACTOR), so this does not block a start."
  echo "    What you lose: $RUN's SESSION LOG is not kept bounded, and every session's startup cost grows."
  [ -x "$COMPACT_DST" ] && \
    echo "    NOTE: a PREVIOUSLY installed copy is still at $COMPACT_DST and the daemon WILL use that one."
fi
# The committed prompt carries a __REPO__ placeholder rather than one machine's absolute path; render the
# real checkout in here, because the session that reads it needs a literal path it can hand to `cd`.
sed "s|__REPO__|$(sed_repl "$REPO")|g" "$PROMPT_SRC" >"$PROMPT_DST" \
  || fail "could not render the resume prompt into $PROMPT_DST"
echo "installed: daemon -> $DAEMON_DST ; resume prompt -> $PROMPT_DST"

# 3. DON'T DOUBLE-LAUNCH. Check the process AND the launchd job UNCONDITIONALLY — not only in keepalive
#    mode. A keepalive job can be REGISTERED but momentarily process-down (a crash or a ThrottleInterval
#    window), and a plain start would then miss it via pgrep and launch a second sibling that the first
#    one's self-bootout cannot stop. Checking the job regardless is what catches that cross-mode collision.
#    `pgrep -f` is unavoidable here — the daemon runs as `bash …/vision-ocr-autonomous.sh`, whose process
#    NAME is `bash`, so the `-x` form CLAUDE.md prefers cannot see it at all. It is the same pattern
#    status-digest.sh uses, deliberately: one detector, so a fix cannot reach only half of them. What that
#    costs is the trap CLAUDE.md names — any process whose command line merely CONTAINS the script name
#    matches, so a parent shell that was invoked with the path in its own argv can produce a false positive.
#    That direction is the safe one (a refusal to start, never a second daemon), and the `pgrep -fl` below
#    prints what matched, so a false hit is visible rather than mysterious.
if pgrep -f vision-ocr-autonomous.sh >/dev/null 2>&1 \
   || launchctl print "$GUI_DOMAIN/$JOB" >/dev/null 2>&1; then
  echo "daemon ALREADY running (or the launchd job is loaded) — NOT launching a second one:"
  pgrep -fl vision-ocr-autonomous.sh || echo "  (process down but job loaded — launchd will relaunch it)"
  echo "  To switch modes or restart: '$0 stop' first, then '$0' (or '$0 nohup')."
  echo; status; exit 0
fi

# 4. GUARD THE STALE-COMPLETE FOOTGUN. A finished run leaves `RUN STATUS: COMPLETE`, and the daemon's first
#    tick would then boot itself out and exit — a launch that reports success and does nothing. Print the
#    exact edit instead of silently no-op'ing.
st="$(runstatus)"
if printf '%s' "$st" | grep -q 'COMPLETE'; then
  cat >&2 <<EOF
RUN STATUS is COMPLETE — the daemon would start, read that line, and immediately stop itself.
To (re)start a run, edit:
  $RUN
  * set the COLUMN-0 marker line to:  RUN STATUS: IN_PROGRESS — <one-line note>
  * and give it a steer under '## FOCUS' if what to do next is not obvious from the queue.
Then re-run: $0
EOF
  exit 1
fi
echo "run state OK: ${st:-(no 'RUN STATUS:' line — the daemon will treat that as not-complete)}"

# 5. REPORT THE SUITE LOCK before launching. Two suites at once corrupt BOTH runs (CLAUDE.md's first
#    environment trap: `build/tests` has no bundle id, so every worktree shares
#    ~/Library/Preferences/tests.plist), so the daemon's first health gate WAITS behind a live one. That
#    wait is correct behaviour and looks exactly like a hang in the log, so say it now — before it happens
#    — rather than answering "why is it stuck?" later.
if [ -x "$TESTLOCK" ]; then
  echo "suite lock:"
  tl_out="$(VISIONOCR_TEST_LOCK="$LOCKDIR" "$TESTLOCK" status 2>&1)"; tl_rc=$?
  printf '%s\n' "$tl_out" | sed 's/^/  /'
  if [ "$tl_rc" != 0 ]; then
    echo "  ^ BUSY. This is NOT a fault and NOT a reason to wait before starting: the first health gate will"
    echo "    QUEUE behind it (up to VISIONOCR_TEST_LOCK_WAIT, 3600s) rather than run a second suite."
    echo "    Expect a quiet daemon log until that finishes. Nothing is stuck."
  fi
else
  echo "⚠️  WARNING: no suite lock at $TESTLOCK — the daemon's gate and the pre-commit hook cannot serialise"
  echo "    against your own ./run_tests.sh, and two suites at once corrupt both runs."
fi

# 6. LAUNCH — launchd KeepAlive (default, crash-restart) or opt-in detached nohup.
if [ "$MODE" = keepalive ]; then
  # RunAtLoad launches the daemon; KeepAlive=true relaunches it on any bootout-less death (crash, OOM, a
  # stray signal). Every INTENTIONAL stop boots the job out first — `daemon.sh stop`, park_run, and the
  # RUN-STATUS-COMPLETE exit — so deliberate stops still stick. A LaunchAgent loads in the GUI login
  # session, so this survives a daemon CRASH but not a logout or reboot (reboot-survival is out of scope).
  #
  # launchd expands neither `~` nor `$HOME` in a path, so the committed template carries __HOME__/__REPO__
  # placeholders and the real values are rendered in here. Lint the RENDERED file: that — not the template —
  # is what launchd loads, and a botched substitution is only visible in the result.
  if [ "$STATE" != "$STATE_DEFAULT" ]; then
    echo "⚠️  WARNING: VISIONOCR_STATE is overridden to $STATE, but the plist passes only VISIONOCR_REPO,"
    echo "    so the launchd-started daemon will use the DEFAULT $STATE_DEFAULT — not the directory whose"
    echo "    RUN.md and prompt were just checked and rendered. Use the 'nohup' lane (which inherits this"
    echo "    shell's environment) if the override was deliberate."
  fi
  [ -f "$PLIST_SRC" ] || fail "LaunchAgent template missing: $PLIST_SRC"
  mkdir -p "$HOME/Library/LaunchAgents"
  rendered="$(mktemp)"
  sed -e "s|__HOME__|$(sed_repl "$HOME")|g" -e "s|__REPO__|$(sed_repl "$REPO")|g" "$PLIST_SRC" >"$rendered" \
    || { rm -f "$rendered"; fail "could not render plist: $PLIST_SRC"; }
  plutil -lint "$rendered" >/dev/null || { rm -f "$rendered"; fail "plist is malformed AFTER rendering: $PLIST_SRC"; }
  install -m 644 "$rendered" "$PLIST_DST" || { rm -f "$rendered"; fail "could not install $PLIST_DST"; }
  rm -f "$rendered"
  launchctl bootout "$GUI_DOMAIN/$JOB" 2>/dev/null || true    # clear any stale registration first
  if launchctl bootstrap "$GUI_DOMAIN" "$PLIST_DST"; then
    echo "launched (launchd KeepAlive [default]; plist -> $PLIST_DST) — a crash/kill auto-restarts it."
  else
    fail "launchctl bootstrap failed — check: launchctl print $GUI_DOMAIN/$JOB"
  fi
else
  # macOS has NO `setsid`; a subshell + nohup is how the daemon survives this shell returning (it reparents
  # to init). VISIONOCR_REPO must be passed the same way the launchd lane passes it (plist
  # EnvironmentVariables): the installed daemon lives outside any checkout and REFUSES to start without it.
  # ⚠️ CLAUDE.md: "`nohup … &` reports success immediately while the real work runs orphaned. Wait on the
  # process; don't trust the exit code." That is exactly why step 7 exists and why it checks the LOG rather
  # than this line's exit status — the `&` below cannot fail informatively.
  ( VISIONOCR_REPO="$REPO" nohup "$DAEMON_DST" >"$STATE/nohup.out" 2>&1 & )
  echo "launched (detached nohup — NO crash-restart; the default '$0' uses launchd KeepAlive instead)."
fi

# 7. VERIFY THE FIRST CYCLE ACTUALLY STARTED — a BOUNDED poll, never an unbounded wait. Two conditions, and
#    both are needed: a live process alone can be a daemon about to die on a missing prerequisite, and a
#    'daemon up' line alone can be left over from a previous run.
ok=""
for _ in $(seq 1 20); do          # 20 x 0.5s = ~10s
  if pgrep -f vision-ocr-autonomous.sh >/dev/null 2>&1 \
     && tail -n 8 "$LOG" 2>/dev/null | grep -q 'daemon up'; then
    ok=1; break
  fi
  sleep 0.5
done
echo
if [ -n "$ok" ]; then
  echo "✅ CONFIRMED: the daemon is up and starting its first cycle."
else
  echo "⚠️  NOT CONFIRMED within 10s. It may still come up — this is an inconclusive result, not a failure."
  echo "    Look, in this order:"
  echo "      $LOG                                  (the daemon's own log; expect '=== daemon up (pid …')"
  echo "      $STATE/launchd.err.log                (a failure BEFORE the daemon's first line lands here)"
  echo "      launchctl print $GUI_DOMAIN/$JOB      (ThrottleInterval is 60s: a job that died once may"
  echo "                                             simply not have been relaunched yet)"
fi
status
