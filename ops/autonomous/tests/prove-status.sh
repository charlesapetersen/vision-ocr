#!/usr/bin/env bash
# prove-status.sh — prove-the-mechanism harness for ops/autonomous/status-digest.sh's STATE 1 block.
#
# WHY IT IS COMMITTED. run-state-lib.sh decides WHY a live daemon is not advancing and can answer five
# different things; status-digest.sh renders that answer, and the answers call for OPPOSITE owner actions
# ("go add work" / "wait, it is capped" / "wait, a suite has the lock" / "rescue the work a dead commit left
# behind" / "nothing, it is working"). The lib is careful; the RENDERER is where an answer can still be
# thrown away, and on 2026-08-16 that happened TWICE IN ONE EVENING, both times printing the same sentence:
#
#   20:33 — `daemon.sh status` printed
#       ◐  Running, but not finding anything it can do (16 minutes)
#   while its own Suite section printed "a suite is RUNNING", `pgrep -x tests` returned pid 3574 and
#   $STATE/test.lock/label held `c24b-session`. The case statement had a branch for *THROTTLED* and a
#   residual `*)`, and NONE for the WAITING FOR THE SUITE answer the lib had returned.
#
#   21:19 — with that fixed, the SAME sentence appeared over a session 59 minutes in and actively editing
#   `Tests/main.swift`. No branch was missing this time; the PREMISE was wrong. $STATE/idle.since advances
#   only when the git tip or the queue moves — it is a stopwatch on COMMITS, not on work — so every branch
#   downstream of it inherited "has not committed for an hour" and rendered it as "has done nothing".
#
# So this harness asserts BRANCH COVERAGE OF THE ANSWER SET plus the PRECEDENCE between answers, not the
# detectors themselves. Section [5] fails if the lib grows a reason the renderer has no branch for.
#
# FULLY SANDBOXED — it cannot touch the owner's machine, and cannot be perturbed by it:
#   * its own $HOME, $VISIONOCR_STATE, $VISIONOCR_TEST_LOCK and a throwaway $VISIONOCR_REPO git repo;
#   * `pgrep` and `launchctl` are interposed, so the verdict does not depend on what is running here;
#   * the digest is READ-ONLY by construction (its own header), so nothing is written outside $T;
#   * NO suite, build, swiftc or real `tests` process — deliberately, unlike prove-test-lock.sh [10]. That
#     harness already proves the real `pgrep -x tests` detector against a genuine process it names `tests`;
#     duplicating it here would spawn a process every other test-lock caller on this machine must yield to,
#     to re-prove a detector this file is not testing.
#
# ⚠️ Interposition is by BASH_ENV shell function, not by $PATH: status-digest.sh re-prepends /usr/bin:/bin to
# PATH itself, so a $T/bin/pgrep stub would be shadowed by the real one. preflight PROVES the interposition
# works and aborts if it does not — the one check that must never be taken on trust.
#
# USAGE:  ops/autonomous/tests/prove-status.sh [path/to/status-digest.sh]
# EXPECTED RESULT: 49 passed, 0 failed — MEASURED 2026-08-22, not inherited (it read 39 before section [11]
# and the assigned-vs-waiting change, then 44 before the icon and live-session assertions; this project's own
# habit is to leave such a number stale, so run it rather than trusting this line). Three independent falsifications, all actually run:
#   * against the renderer as it stood before this work — 14 passed / 26 failed, with sections [1], [6]
#     and [7] printing the measured sentences back verbatim;
#   * against a lib given a new `DISK FULL` reason and a renderer given only a `# TODO` comment for it —
#     26 / 7, section [5]. Before [5] was rewritten to read case PATTERNS instead of grepping the whole
#     file, that same plant scored a clean pass, i.e. the section could not fail;
#   * against a renderer that is nothing but `exit 1` — 9 / 24, caught in preflight. Before the exit-code
#     and output assertions existed it scored 8 PASS in silence, because every negative assertion
#     ("does NOT say …") is satisfied by no output at all.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DIGEST="${1:-$HERE/../status-digest.sh}"
LIB="$(dirname "$DIGEST")/run-state-lib.sh"
[ -f "$DIGEST" ] || { echo "no status-digest.sh at $DIGEST"; exit 2; }
[ -f "$LIB" ]    || { echo "no run-state-lib.sh beside $DIGEST"; exit 2; }
T="$(mktemp -d)"
_cleanup() { rm -rf "$T"; }
trap _cleanup EXIT
# bash does NOT run an EXIT trap when it dies of an UNTRAPPED signal, so these are what actually stop the
# sandbox leaking when the harness is pkill'd or Ctrl-C'd. Same lesson as prove-test-lock.sh, same fix.
trap '_cleanup; exit 130' INT
trap '_cleanup; exit 143' TERM
trap '_cleanup; exit 129' HUP
PASS=0; FAIL=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

# ---- sandbox --------------------------------------------------------------------------------------------
export HOME="$T/home"; mkdir -p "$HOME/Desktop"
export VISIONOCR_STATE="$T/state"; mkdir -p "$VISIONOCR_STATE"
export VISIONOCR_TEST_LOCK="$VISIONOCR_STATE/test.lock"
export VISIONOCR_REPO="$T/repo"

# A throwaway repo with a REAL `auto/*` worktree, so orphaned_work is exercised against actual git rather
# than a mock of it — reading `git worktree list` correctly is the detector's whole job.
git init -q "$VISIONOCR_REPO" 2>/dev/null
git -C "$VISIONOCR_REPO" config user.email t@t; git -C "$VISIONOCR_REPO" config user.name t
echo one > "$VISIONOCR_REPO/f.txt"; git -C "$VISIONOCR_REPO" add f.txt
git -C "$VISIONOCR_REPO" commit -qm first
git -C "$VISIONOCR_REPO" worktree add -q "$T/auto-wt" -b auto/testwt 2>/dev/null

# Stubs, as shell functions so they beat PATH lookups (see the header).
#   pgrep: `-f vision-ocr-autonomous.sh` always matches — every case here is a LIVE daemon, which is the
#          only branch of STATE 1 this harness is about. `-x tests` consults $SUITECTL.
#   launchctl: always fails ("no job loaded"). Unreached while running=1, stubbed anyway so the harness can
#          never read — or bootout — the owner's real com.visionocr.autonomous.
cat > "$T/stubs.sh" <<'STUBS'
pgrep() {
  case "$*" in
    *vision-ocr-autonomous.sh*) return 0 ;;
    *-x*tests*) [ "$(cat "$SUITECTL" 2>/dev/null)" = live ] && { echo 4242; return 0; }; return 1 ;;
  esac
  return 1
}
launchctl() { return 1; }
export -f pgrep launchctl
STUBS
export SUITECTL="$T/suitectl"; echo none > "$SUITECTL"
export BASH_ENV="$T/stubs.sh"

# idle.since: a fixed 16 minutes ago, the interval the first measured misreport was printed at.
echo $(( $(date +%s) - 960 )) > "$VISIONOCR_STATE/idle.since"

ENGINE="$VISIONOCR_STATE/engine.lock"
session_on()  { : > "$ENGINE"; }                  # fresh mtime = heartbeat alive
session_off() { rm -f "$ENGINE"; }
dirty_on()    { echo changed > "$T/auto-wt/f.txt"; }
# ⚠️ BOTH worktrees, and untracked content too — this used to restore `auto-wt/f.txt` alone. Section [7]
# creates a SECOND worktree (`auto-wt2`) to prove the renderer names every orphan and never cleans it up, so
# from [7] onward the sandbox permanently held one dirty worktree that no `dirty_off` could clear. That was
# invisible for as long as nothing put orphans into `needs`; the moment an unassigned strand started raising
# one (2026-08-22), [10]'s closing "an empty outbox still reports 'Nothing right now'" went red — correctly,
# because the sandbox did have unassigned orphaned work in it. A helper named `dirty_off` has to actually
# leave the tree clean, or every later section inherits state it did not ask for.
dirty_off()   {
  git -C "$T/auto-wt"  checkout -q -- f.txt 2>/dev/null
  git -C "$T/auto-wt2" checkout -q -- f.txt 2>/dev/null
  git -C "$T/auto-wt"  clean -qfd 2>/dev/null
  git -C "$T/auto-wt2" clean -qfd 2>/dev/null
  rm -rf "$VISIONOCR_STATE/triage" 2>/dev/null
}

# ⚠️ CAPTURE STDERR AND THE EXIT CODE, do not discard them. The first version did `2>/dev/null` and asserted
# only on substrings, so 8 of these checks were the NEGATIVE form ("does NOT say 'not finding anything'")
# and passed happily against a digest that printed nothing at all — a syntax error, a missing helper, an
# `exit 1` all scored 8 PASS. The digest's own header promises it "ALWAYS exits 0" and prints a useful
# report with no repo and no state dir, so both of those are assertable facts, not incidental.
# ⚠️ THE STATUS AND STDERR GO THROUGH FILES, NOT VARIABLES. Every caller here is `x="$(state_block)"`, a
# COMMAND SUBSTITUTION — a subshell — so a `DIGEST_RC=$?` assigned inside is discarded the moment it
# returns, and the assertion reading it tests a stale value from the previous call. The first version of
# this block did exactly that: against a renderer that was nothing but `exit 1` it still reported the
# digest had exited 0. A harness that cannot see the failure it is testing for is the whole subject of this
# file, so it is written the one way that survives a subshell.
run_digest() { bash "$DIGEST" 2>"$T/digest.err"; printf '%s' "$?" > "$T/digest.rc"; }
digest_rc()  { cat "$T/digest.rc" 2>/dev/null || printf 0; }
digest_err() { cat "$T/digest.err" 2>/dev/null; }
# STATE 1 is the icon line and the hint under it: everything after the title, up to the `Done` row.
# ⚠️ NOT a fixed `sed -n '2,5p'`. The hint is variable-length — the orphaned-work branch prints one line per
# worktree — so a fixed window silently truncates it and an assertion looking for the SECOND worktree fails
# while the renderer is perfectly correct. That produced exactly one wrong diagnosis while this file was
# being written. Delimit on the next section instead of counting lines.
state_block() {
  local o; o="$(run_digest)"
  # Fail LOUDLY rather than returning empty: an empty block silently satisfies every negative assertion.
  [ "$(digest_rc)" = 0 ] || { printf 'DIGEST-EXITED-%s\n' "$(digest_rc)"; return; }
  [ -z "$(digest_err)" ] || { printf 'DIGEST-STDERR: %s\n' "$(digest_err)"; return; }
  case "$o" in '') printf 'DIGEST-EMPTY\n'; return ;; esac
  printf '%s\n' "$o" | awk 'NR==1{next} /^  Done/{exit} {print}'
}

# preflight — PROVE the interposition before asserting anything through it. A harness whose stubs are
# shadowed still prints PASS lines; it is just measuring the wrong machine.
echo "[0] preflight — stubs really interposed"
echo live > "$SUITECTL"
if bash -c 'pgrep -x tests' >/dev/null 2>&1; then ok "pgrep stub reachable through BASH_ENV"
else bad "pgrep stub NOT interposed — every assertion below would measure the real machine"; exit 2; fi
if ! bash -c 'launchctl print gui/0/nope' >/dev/null 2>&1; then ok "launchctl stub reachable"
else bad "launchctl stub NOT interposed"; exit 2; fi
if [ -d "$T/auto-wt" ]; then ok "sandbox repo has a real auto/* worktree"
else bad "could not create the sandbox worktree — [7] would assert nothing"; exit 2; fi
echo none > "$SUITECTL"; session_off; dirty_off
# The digest must actually RUN before any negative assertion below means anything.
_pre="$(run_digest)"
[ "$(digest_rc)" = 0 ] && ok "the digest exits 0 (its header promises it always does)" \
                       || bad "the digest exited $(digest_rc) — every negative assertion below would pass vacuously"
[ -z "$(digest_err)" ] && ok "the digest writes nothing to stderr" \
                       || bad "the digest wrote to stderr: $(digest_err)"
[ "$(printf '%s\n' "$_pre" | wc -l)" -ge 6 ] && ok "the digest produces a report, not silence" \
                     || bad "the digest printed fewer than 6 lines — negative assertions would be vacuous"

# ---- [1] a suite holds the lock -------------------------------------------------------------------------
echo "[1] a suite is running under the lock"
mkdir -p "$VISIONOCR_TEST_LOCK"; echo 4242 > "$VISIONOCR_TEST_LOCK/pid"; echo c24b-session > "$VISIONOCR_TEST_LOCK/label"
echo live > "$SUITECTL"
b="$(state_block)"
case "$b" in *"Waiting for a test suite to finish"*) ok "names the suite wait" ;;
  *) bad "does not name the suite wait — got: $(printf '%s' "$b" | tr '\n' ' ')" ;; esac
case "$b" in *"not finding anything it can do"*) bad "STILL reports an empty queue over a running suite" ;;
  *) ok "does NOT report it as an empty queue" ;; esac
case "$b" in *c24b-session*) ok "names WHO holds the suite lock" ;;
  *) bad "does not name the lock holder" ;; esac

# ---- [2] a suite started outside the lock ---------------------------------------------------------------
echo "[2] a suite is running, started outside the lock"
rm -rf "$VISIONOCR_TEST_LOCK"
b="$(state_block)"
case "$b" in *"Waiting for a test suite to finish"*) ok "still names the suite wait with no lock label" ;;
  *) bad "an unlabelled suite falls through to the residual" ;; esac
case "$b" in *"outside the suite lock"*) ok "says it was started outside the lock — a different owner action" ;;
  *) bad "does not distinguish an out-of-band suite from the daemon's own" ;; esac

# ---- [3] throttled, and the reset time survives the render ----------------------------------------------
# ratelimit_phrase was called with NO argument here, which degrades to a bare "usage cap" and drops the reset
# time the lib had just computed — the half of the sentence that says whether to wait or to look.
echo "[3] the last session was refused by the usage cap"
echo none > "$SUITECTL"
reset=$(( $(date +%s) + 3600 ))
printf '{"type":"result","api_error_status":429,"resetsAt":%s}\n' "$reset" > "$VISIONOCR_STATE/last-session.log"
b="$(state_block)"
case "$b" in *"usage cap"*) ok "names the usage cap" ;;
  *) bad "does not name the cap — got: $(printf '%s' "$b" | tr '\n' ' ')" ;; esac
case "$b" in *"resets $(date -r "$reset" '+%H:%M')"*) ok "carries the reset time through to the owner" ;;
  *) bad "reset time dropped — ratelimit_phrase called without its epoch" ;; esac
case "$b" in *"not finding anything it can do"*) bad "a cap reported as an empty queue" ;;
  *) ok "does NOT report the cap as an empty queue" ;; esac
rm -f "$VISIONOCR_STATE/last-session.log"

# ---- [4] the residual really is still reachable ---------------------------------------------------------
# A fix that makes every case match something is not a fix; the empty-queue sentence must still be printed
# when the queue is in fact the reason.
echo "[4] no cap, no suite, no session, nothing orphaned — the residual"
b="$(state_block)"
case "$b" in *"not finding anything it can do"*) ok "the residual branch is still reachable" ;;
  *) bad "the empty-queue sentence can no longer be printed at all" ;; esac

# ---- [5] structural: one branch per answer the lib can give ---------------------------------------------
# The first defect was not a wrong branch, it was a MISSING one, and a new reason added to the lib would be
# swallowed by the residual exactly the same way.
echo "[5] every answer run-state-lib.sh can give has a branch in the renderer"
# ⚠️ THIS CHECK WAS ITSELF A CHECK THAT COULD NOT FAIL, for its first hours of life. It asked
# `grep -qF "$p" "$DIGEST"` — a substring search over the WHOLE FILE, comments included. Since the renderer's
# own comments narrate the history ("Hence WORKING, checked first", "…had no case here"), every reason
# matched whether or not a branch existed. Demonstrated: adding a `running, DISK FULL (…)` reason to the lib
# and giving the renderer nothing but a `# TODO` comment still scored 26/0. That is the exact scenario this
# section exists to catch, and the project's register records ten prior checks with the same defect.
#
# Now it extracts the case PATTERNS — the `*…)` labels between `case "$(idle_explanation …)"` and its `esac`
# — and matches against those alone. A comment cannot satisfy it, because a comment line does not begin
# with `*` and end with `)`.
cand="$T/reasons"; pats="$T/patterns"
awk '/case "\$\(idle_explanation/{f=1; next} f && /^[[:space:]]*esac/{f=0} f' "$DIGEST" \
  | grep -oE '^[[:space:]]*\*[^)]*\)' > "$pats"
if [ ! -s "$pats" ]; then
  bad "could not find the idle_explanation case statement in the renderer — this check is asserting nothing"
else
  # ⚠️ ONE PHRASE PER LINE throughout. The phrases contain spaces, so a space-separated accumulator splits
  # 'WAITING FOR THE SUITE' into four words and the failure message reads as gibberish.
  # BACKING OFF is the lib's own residual, deliberately matched by the renderer's `*)`, so it is excluded.
  # Two sources on purpose: a literal list saying what is known today, and a scan of the lib that catches a
  # reason nobody remembered to add to the list.
  { printf 'THROTTLED\nWAITING FOR THE SUITE\nWORKING\nORPHANED WORK\n'
    grep -o "running, [A-Z][A-Z ]*[A-Z]" "$LIB" | sed 's/^running, //'
  } | grep -v '^BACKING OFF$' | sort -u > "$cand"
  missing=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    grep -qF "$p" "$pats" || missing="$missing '$p'"
  done < "$cand"
  if [ -z "$missing" ]; then ok "every lib answer has a case PATTERN, not merely a mention in a comment"
  else bad "the renderer has no branch for:$missing — it will be reported as an empty queue"; fi
  # And the residual must still be there, or a future reason falls off the end of the case entirely.
  grep -qE '^[[:space:]]*\*\)' "$pats" \
    && ok "the residual \`*)\` is still present as the last resort" \
    || bad "no residual \`*)\` — an unmatched reason would render as an empty STATE_LINE"
fi

# ---- [6] a session is in flight — the 21:19 defect -------------------------------------------------------
echo "[6] a session is working right now"
session_on
b="$(state_block)"
case "$b" in *"Working now"*) ok "reports that it is working" ;;
  *) bad "a live session is not reported as working — got: $(printf '%s' "$b" | tr '\n' ' ')" ;; esac
# THE regression assertion. This exact sentence was printed over a session 59 minutes into real edits.
case "$b" in *"not finding anything it can do"*) bad "STILL reports a working session as an empty queue" ;;
  *) ok "does NOT report a working session as an empty queue" ;; esac
# The idle figure must not be the headline: "(62 minutes)" beside "Working now" is what made a healthy
# daemon look stuck, and it measures time since the last COMMIT, not time doing nothing.
case "$b" in *"into this session"*) ok "the headline counts session runtime, not time since the last commit" ;;
  *) bad "headline still leads with the commit stopwatch" ;; esac
case "$b" in *"time since the last COMMIT"*) ok "says explicitly what the other number measures" ;;
  *) bad "does not explain the idle figure, which is what misled the reader" ;; esac

# ---- [7] a session's commit died, leaving work behind ----------------------------------------------------
echo "[7] uncommitted work orphaned in an auto/* worktree"
session_off; dirty_on
b="$(state_block)"
case "$b" in *"never committed"*) ok "names the lost commit" ;;
  *) bad "orphaned work is not reported — got: $(printf '%s' "$b" | tr '\n' ' ')" ;; esac
case "$b" in *"not finding anything it can do"*) bad "orphaned work reported as an empty queue" ;;
  *) ok "does NOT report orphaned work as an empty queue" ;; esac
case "$b" in *auto-wt*) ok "names the worktree the work is sitting in" ;;
  *) bad "does not say WHERE the work is, so it cannot be rescued" ;; esac
case "$b" in *"file changed"*|*insertion*|*deletion*) ok "says how much work is at stake" ;;
  *) bad "no diffstat — the owner cannot judge whether to rescue it" ;; esac
# ⚠️ EVERY orphan, not just the first. The renderer originally used `${_orph%% *}`, which on the machine
# this was written on named 660 insertions in one worktree and silently omitted 887 in another.
git -C "$VISIONOCR_REPO" worktree add -q "$T/auto-wt2" -b auto/testwt2 2>/dev/null
echo changed2 > "$T/auto-wt2/f.txt"
b="$(state_block)"
case "$b" in *auto-wt*) : ;; *) bad "lost the first worktree once a second appeared" ;; esac
case "$b" in *auto-wt2*) ok "names BOTH worktrees, not just the head of the list" ;;
  *) bad "reports only the first orphan — understates the loss while looking specific" ;; esac
case "$b" in *"2 worktrees"*) ok "counts them" ;; *) bad "does not say how many" ;; esac

# ---- [8] precedence — a working session outranks everything ---------------------------------------------
# A live session's worktree is SUPPOSED to be dirty, so orphaned_work fires during every healthy session. If
# ORPHANED outranked WORKING the digest would cry wolf once per session, which is worse than silence.
echo "[8] precedence"
session_on   # dirty worktree AND a live session
b="$(state_block)"
case "$b" in *"Working now"*) ok "a live session outranks its own dirty worktree" ;;
  *) bad "reports a healthy in-flight session as orphaned work — cries wolf every session" ;; esac
echo live > "$SUITECTL"   # …and outranks a running suite, which is just what it is doing
b="$(state_block)"
case "$b" in *"Working now"*) ok "a live session outranks the suite wait" ;;
  *) bad "a session running its own suite is reported as waiting for someone else's" ;; esac
case "$b" in *"Running a test suite"*) ok "…and still says the suite is what it is doing" ;;
  *) bad "loses the fact that the session is in its suite" ;; esac
# ⚠️ …and WORKING must still SURFACE the orphan it outranks. Sessions run ~95 min back to back, so a state
# ranked below WORKING is visible a few percent of the time — and ORPHANED WORK is the only one that never
# clears by itself. Outranking it must not mean hiding it.
# ⚠️ Matched on "stranded worktree", which is the 2026-08-22 wording. The hint used to end "— see 'Needs
# you'." and no longer does, deliberately: during a live session the daemon does not assign, so the need is
# suppressed and that pointer would dangle exactly the way D16's did. What must not change is that the
# orphan is MENTIONED here at all, so that is what this asserts.
case "$b" in *"stranded worktree"*) ok "the WORKING hint still surfaces the orphaned work beneath it" ;;
  *) bad "WORKING hides orphaned work — the one state that needs a human is invisible 97% of the time" ;; esac
echo none > "$SUITECTL"

# ---- [9] a stale engine.lock must not read as working ----------------------------------------------------
# If the daemon is hard-killed the lock survives with nothing behind it. Reporting that as "Working now" is
# the same lie pointing the other way, and it would hide a dead run indefinitely.
echo "[9] a stale engine.lock is not a working session"
session_on
# 20 minutes of missed heartbeats; the lib's threshold is 300s.
touch -t "$(date -v-20M '+%Y%m%d%H%M.%S' 2>/dev/null || date '+%Y%m%d%H%M.%S')" "$ENGINE"
b="$(state_block)"
case "$b" in *"Working now"*) bad "a lock with a 20-minute-dead heartbeat still reads as working" ;;
  *) ok "a stale lock does NOT read as a working session" ;; esac
case "$b" in *"never committed"*) ok "falls through to the orphaned-work truth beneath it" ;;
  *) bad "fell past orphaned work too — got: $(printf '%s' "$b" | tr '\n' ' ')" ;; esac


# ---- [10] RUN.md's NEEDS OWNER list must reach the owner ---------------------------------------------------
# The daemon's outbox. The resume prompt tells every session to append anything needing a human here and move
# on, and RUN.md's own comment says `daemon.sh status` surfaces it under "Needs you". It did not: the digest
# raised needs from six conditions (park note, docfix, red gate, gate timeouts, COMPLETE-with-open-items, low
# disk) and never read this list at all. Measured 2026-08-16 22:51 — two real entries present, including a
# dead session's worktree holding 660 uncommitted lines, while the digest printed "Nothing right now."
echo "[10] the NEEDS OWNER outbox"
session_off; dirty_off
cat > "$VISIONOCR_STATE/RUN.md" <<'RUNMD'
RUN STATUS: IN_PROGRESS — harness

## NEEDS OWNER

<!-- This explanatory comment must NOT be mistaken for an item. -->

- **A dead session's worktree is dirty** and the daemon will never reclaim it.
- Second thing that needs a human.

## SESSION LOG

- not an item; this heading ends the section.
RUNMD
out="$(run_digest)"
printf '%s' "$out" | grep -q "Nothing right now" \
  && bad "two entries in NEEDS OWNER and the digest still says 'Nothing right now'" \
  || ok "a non-empty outbox is not reported as 'Nothing right now'"
printf '%s' "$out" | grep -q "dead session's worktree" \
  && ok "the first entry reaches the owner" || bad "first NEEDS OWNER entry not surfaced"
printf '%s' "$out" | grep -q "Second thing that needs a human" \
  && ok "so does the second — not just the head of the list" || bad "only the first entry surfaced"
printf '%s' "$out" | grep -q "must NOT be mistaken" \
  && bad "the section's HTML comment was rendered as an item" \
  || ok "the explanatory comment is not mistaken for an item"
printf '%s' "$out" | grep -q "this heading ends the section" \
  && bad "parsing ran past the next '## ' heading into SESSION LOG" \
  || ok "parsing stops at the next heading"
# And the converse, so this cannot be satisfied by always printing something.
cat > "$VISIONOCR_STATE/RUN.md" <<'RUNMD'
RUN STATUS: IN_PROGRESS — harness

## NEEDS OWNER

<!-- nothing outstanding -->

## SESSION LOG
RUNMD
run_digest | grep -q "Nothing right now" \
  && ok "an empty outbox still reports 'Nothing right now'" \
  || bad "an empty outbox no longer reports nothing — the check would pass on anything"
rm -f "$VISIONOCR_STATE/RUN.md"

# ---- [11] AN ASSIGNED STRAND IS NOT AN OWNER NEED ---------------------------------------------------------
# The 2026-08-22 change: the daemon snapshots each stranded worktree and writes a session a task for it at
# $STATE/triage/<wt>.md, so the usual state of a strand is "handled, waiting its turn" rather than "waiting
# on you". The owner asked for exactly this — *"I don't really need to review stray worktrees… I'd rather the
# daemon just decide and execute much of this work"* — and the whole value of it is that a SHORT "Needs you"
# list can be trusted. So the digest must distinguish the two, and this section pins BOTH directions, which
# is what stops it becoming another check that cannot fail: the same fixture, one file created and removed.
echo "[11] an assigned strand is queued work, not an owner need"
session_off; dirty_off; dirty_on
mkdir -p "$VISIONOCR_STATE/triage"
u="$(run_digest)"
printf '%s' "$u" | grep -q "Nothing right now" \
  && bad "an UNASSIGNED dirty worktree raised no need — the strand is invisible, which is the old behaviour" \
  || ok "an unassigned strand does raise a need"
printf '%s' "$u" | grep -qi "NO triage assignment" \
  && ok "…and the need says WHY it reached the owner (no assignment), not just that it exists" \
  || bad "the need does not distinguish an unassigned strand from any other need"
# Now assign it — the only change — and the need must disappear.
: > "$VISIONOCR_STATE/triage/auto-wt.md"
a="$(run_digest)"
printf '%s' "$a" | grep -qi "NO triage assignment" \
  && bad "the strand still reads as unassigned after a triage file was written for it" \
  || ok "assigning it removes the need — the daemon handing work to a session ends the owner's involvement"
printf '%s' "$a" | grep -qiE "queued for (a session|triage)" \
  && ok "…and it is still VISIBLE as queued work rather than silently dropped" \
  || bad "the assigned strand vanished from the digest entirely — that is silence, not delegation"
rm -rf "$VISIONOCR_STATE/triage"
r="$(run_digest)"
printf '%s' "$r" | grep -qi "no triage assignment" \
  && ok "removing the assignment brings the need back, so this section cannot pass on a constant" \
  || bad "NEGATIVE CONTROL FAILED: the need did not return once the assignment was deleted"

# ⛔ THE COLOUR IS PART OF THE CLAIM AND NOTHING PINNED IT. RED is now reserved for a strand nothing is
# assigned to — the point being that painting the HANDLED case red is how a status surface trains its reader
# to ignore red. Review measured that restoring the old unconditional `STATE_ICON="${RED}✕${OFF}"` left the
# harness at 44/0, i.e. the whole colour change was untested. Asserted on the ICON LINE only, and in both
# directions off the same fixture.
b="$(state_block)"
case "$b" in *✕*) ok "an UNASSIGNED strand is still RED — the case that does need a human" ;;
  *) bad "an unassigned strand lost its ✕ — the one state that should alarm no longer does" ;; esac
mkdir -p "$VISIONOCR_STATE/triage"; : > "$VISIONOCR_STATE/triage/auto-wt.md"
b="$(state_block)"
case "$b" in *✕*) bad "an ASSIGNED strand is still painted ✕ — the colour ignores the assignment" ;;
  *) ok "…and assigning it drops the ✕, so red keeps meaning 'nobody is coming'" ;; esac
rm -rf "$VISIONOCR_STATE/triage"

# ⛔ AND NOT DURING A LIVE SESSION, which is the assertion whose ABSENCE let the first version of this ship a
# permanent false entry in "Needs you". A running session's own worktree is supposed to be dirty and the
# daemon deliberately does not assign while one is in flight, so every strand reads unassigned mid-session —
# and the digest raised a need for it, printing "Nothing needed." three lines above "1 worktree … with NO
# triage assignment — the daemon could not hand it to a session" while the session was running in that very
# worktree. Section [8] pins the HINT during a live session and never looked at "Needs you", which is
# precisely how 44/0 coexisted with the defect. This is the missing half.
# ⛔ AND `.escalated` IS HANDLED, NOT WAITING. Leaving it out of the count made the digest contradict itself
# inside one screen — measured on the real state dir 2026-08-22: `--details` printed "escalated to you ·
# rescue COMPLETE" for a strand while "Needs you" printed "no triage assignment — snapshot or assignment
# failed" about that same strand. Both halves cannot be true. An escalation reaches the owner through
# `## NEEDS OWNER`, which this digest already renders, so counting it again here would double-report it and
# create a need that can never clear.
mkdir -p "$VISIONOCR_STATE/triage"; : > "$VISIONOCR_STATE/triage/auto-wt.escalated"
printf '%s' "$(run_digest)" | grep -qi "no triage assignment" \
  && bad "an ESCALATED strand is counted as unassigned — the digest says 'assignment failed' about a strand it also says is escalated" \
  || ok "an escalated strand is handled, not a fresh need — it reaches the owner via NEEDS OWNER instead"
rm -rf "$VISIONOCR_STATE/triage"

session_on                      # live session, worktree still dirty, still no triage file
printf '%s' "$(run_digest)" | grep -qi "no triage assignment" \
  && bad "a healthy live session raises a FALSE owner need for its own dirty worktree" \
  || ok "a live session's own dirty worktree raises NO need — the daemon assigns between sessions"
session_off
printf '%s' "$(run_digest)" | grep -qi "no triage assignment" \
  && ok "…and the need returns once the session ends, so the suppression is not a blanket mute" \
  || bad "NEGATIVE CONTROL FAILED: suppressing during a session also suppressed it afterwards"

session_off; dirty_off
printf '\n  %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
