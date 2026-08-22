#!/usr/bin/env bash
# ops/autonomous/status-digest.sh — "what is the autonomous worker doing?", answered in ten seconds of reading.
#
# THE ONE STATUS RENDERER. `daemon.sh status` calls this and adds nothing of its own; the daemon redirects its
# output into $STATE/STATUS.md every cycle and on park. There is deliberately no second copy of this formatting
# anywhere — in the project this was ported from, daemon.sh printed its own sections and THEN pasted the digest
# underneath, so the run state appeared twice, in two wordings, and a fix to one never reached the other.
#
# AUDIENCE: the owner, at a glance, not an engineer reading logs. So the default view answers only the five
# questions actually worth waking up to —
#     is it running? · what has it done? · how much is left? · is the code healthy? · does it need me?
# — in plain words, no internal tags and no raw log tails. Everything else (commit, branch, launchd internals,
# disk, the log tail) is real but DIAGNOSTIC, so it lives behind `--details` and is surfaced by default only
# when it is actually a problem.
#
# READ-ONLY, and it ALWAYS exits 0: no writes, no prompts, no network, and every field degrades to "?"/"—"
# rather than erroring, because this is the thing the owner runs WHEN SOMETHING IS ALREADY BROKEN. It must
# still print a useful report with no repo, no state dir and no RUN.md at all. Anything it infers rather than
# observes says so — an entry without evidence is a rumour (CLAUDE.md §Verification discipline).
#
# ⚠️ TWO LIES THIS FILE EXISTS TO PREVENT, both of which have actually been printed by its ancestor:
#   1. "tests passed, N commits ago" over a run that had PARKED on a RED gate 41 minutes earlier — because
#      $STATE/last-gate advances ONLY on green and so cannot report a failure at all. See the health block.
#   2. "a suite is running" on a machine with none — `pgrep -f` matching every waiter. See the suite block.
set -uo pipefail
# Backgrounded shells here have essentially no PATH (CLAUDE.md: `basename`/`cut` fail SILENTLY and loops
# report bogus results), and the daemon calls this from exactly that launchd context. Set it explicitly.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

REPO="${VISIONOCR_REPO:-$HOME/Claude/vision-ocr}"
STATE="${VISIONOCR_STATE:-$HOME/.local/state/visionocr-autonomous}"
JOB="com.visionocr.autonomous"; GUI_DOMAIN="gui/$(id -u)"
LOG="$STATE/daemon.log"; RUNMD="$STATE/RUN.md"; QUEUE="$REPO/ops/autonomous/QUEUE.md"
PARKNOTE="$HOME/Desktop/VISION-OCR-RUN-PARKED.txt"
DAEMON_CMD="./ops/autonomous/daemon.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
# Resolved beside THIS script, not under $REPO: a worktree's digest must consult that worktree's resolver,
# so the two can be iterated on together without one reading the other checkout's copy.
RESOLVER="$HERE/next-item.sh"

DETAILS=0
case "${1:-}" in -d|--details|--detail|-v|--verbose|full) DETAILS=1 ;; esac

# Every git read goes through this — never `cd`, and never trust the output without the exit code, because a
# FAILED `git status`/`log` also prints nothing and an output-only check reads a broken repo as clean.
g() { git -C "$REPO" "$@" 2>/dev/null; }
HAVE_GIT=0; g rev-parse --git-dir >/dev/null 2>&1 && HAVE_GIT=1
# Coerce any non-numeric to 0: `[ "$x" -gt 0 ]` on an empty string is FATAL, and every count below comes out
# of a file that may not exist.
num() { case "${1:-}" in ''|*[!0-9]*) echo 0 ;; *) echo "$1" ;; esac; }

# Colour only when a human is watching. The daemon redirects this into STATUS.md, and escape codes in a file
# are worse than no colour at all.
if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; GRN=$'\033[32m'; AMB=$'\033[33m'; RED=$'\033[31m'; OFF=$'\033[0m'
else B=""; DIM=""; GRN=""; AMB=""; RED=""; OFF=""; fi

# plural N word -> "1 commit" / "3 commits". Writing "commit(s)" at a human is a small rudeness.
plural() { [ "$(num "${1:-0}")" = 1 ] && printf '1 %s' "$2" || printf '%s %ss' "$(num "${1:-0}")" "$2"; }
# "3 hours"/"12 minutes" from a number of seconds — for people, not for parsing.
human_secs() {
  local s; s="$(num "${1:-0}")"
  if   [ "$s" -lt 90 ]    ; then plural "$s" second
  elif [ "$s" -lt 5400 ]  ; then plural "$(( s / 60 ))" minute
  elif [ "$s" -lt 172800 ]; then plural "$(( s / 3600 ))" hour
  else                           plural "$(( s / 86400 ))" day; fi
}
# Cut to N chars on a WORD boundary, so a truncated commit subject does not end mid-syllable. Subjects in this
# repo are full English sentences up to ~99 chars, so this fires often — clip them, never wrap them.
clip() {
  local s="${1:-}" n="${2:-60}"
  [ "${#s}" -le "$n" ] && { printf '%s' "$s"; return; }
  s="${s:0:$n}"; s="${s% *}"; printf '%s…' "$s"
}

# Why a live daemon is idle is decided in run-state-lib.sh, shared with daemon.sh so the wording cannot drift.
# Guarded because daemon.sh may be running from a checkout that predates the lib — degrade, never blank-line.
if [ -r "$HERE/run-state-lib.sh" ]; then
  . "$HERE/run-state-lib.sh"
else
  idle_explanation() { printf 'running, BACKING OFF (idle %ss — reason undetermined)' "${1:-?}"; }
  ratelimit_phrase() { printf 'usage cap'; }
  # Stubs for everything else the lib exports, so the branches below can call them unconditionally. A missing
  # function here would print `command not found` INTO the digest — the one thing this file must never do.
  ratelimit_reset_epoch() { return 1; }
  suite_blocking() { return 1; }
  session_in_flight() { return 1; }
  orphaned_work() { return 1; }
  orphaned_work_summary() { return 1; }
fi

# ---------------------------------------------------------------------------------------------------
# STATE 1 — is it running, and if not, why? Sets STATE_ICON, STATE_LINE, STATE_HINT (may be empty).
# Each branch is a DIFFERENT owner action, and two of them are historically reported as each other.
# ---------------------------------------------------------------------------------------------------
running=0; pgrep -f vision-ocr-autonomous.sh >/dev/null 2>&1 && running=1
supervised=0; launchctl print "$GUI_DOMAIN/$JOB" >/dev/null 2>&1 && supervised=1
since="$(cat "$STATE/idle.since" 2>/dev/null)"
STATE_HINT=""

if [ -n "${VISIONOCR_STATUS_PARKED:-}" ]; then
  # Set by the daemon while it is parking: park_run calls this BEFORE its `launchctl bootout`, so the process
  # is still alive for another moment and the pgrep below would say "working" for a run that has given up.
  STATE_ICON="${AMB}◆${OFF}"; STATE_LINE="Stopped itself — what is left needs a decision from you"
  STATE_HINT="reason: $(printf '%s' "$VISIONOCR_STATUS_PARKED" | tr -d '\n' | cut -c1-70)"
elif [ "$running" = 1 ]; then
  case "$since" in
    ''|*[!0-9]*) STATE_ICON="${GRN}●${OFF}"; STATE_LINE="Working now" ;;
    *)
      idle=$(( $(date +%s) - since ))
      STATE_ICON="${AMB}◐${OFF}"
      # Each answer run-state-lib.sh can give is a DIFFERENT owner action — "go add work", "it is capped, it
      # resumes by itself", "it is behind a suite, it resumes by itself", "a commit died, its work is sitting
      # in a worktree" and "it is working right now, leave it alone". The residual used to be printed over
      # all of them.
      #
      # ⚠️ THERE MUST BE ONE BRANCH HERE PER ANSWER `idle_explanation` CAN GIVE, and section [5] of
      # tests/prove-status.sh fails the build if there is not. Consuming only some of them silently
      # re-creates the exact lie the lib was written to end. It has now happened twice in one day:
      #   * 20:33 — the suite branch, the one added FOR this project, had no case here, so the line read
      #     "Running, but not finding anything it can do (16 minutes)" while the digest's OWN 'Suite' line
      #     said RUNNING and a suite was three minutes into a forty-minute run.
      #   * 21:19 — with that fixed, the SAME sentence appeared again, this time over a session 59 minutes
      #     in and actively editing `Tests/main.swift`. Nothing was wrong with the branches; the premise was.
      #     $STATE/idle.since advances on a COMMIT, so it is a stopwatch on landings, NOT on work, and every
      #     branch below inherits that. Hence WORKING, checked first: "it has not committed for an hour" and
      #     "it has done nothing for an hour" are different sentences and only one of them was ever true.
      # The residual `*)` must stay LAST and stay the only unnamed case.
      case "$(idle_explanation "$idle")" in
        *WORKING*)
          # NOT amber, and no idle figure in the headline: this is the healthy state, and printing "(62
          # minutes)" beside it is what made a working daemon look stuck in the first place.
          STATE_ICON="${GRN}●${OFF}"
          _forsec="$(session_in_flight)"
          STATE_LINE="Working now — $(human_secs "${_forsec:-0}") into this session"
          if suite_blocking >/dev/null; then
            STATE_HINT="Running a test suite. Last commit was $(human_secs "$idle") ago."
          else
            STATE_HINT="Nothing needed. The $(human_secs "$idle") below is time since the last COMMIT, not idle time."
          fi
          # ⚠️ ORPHANED WORK HAS TO SURFACE HERE TOO, even though WORKING outranks it. Sessions run ~95 min
          # back to back with a ~3 min gap, so the states below are visible a few percent of the time — and
          # ORPHANED WORK is the ONLY one that does not clear by itself. Ranking it under a state that holds
          # 97% of the time would hide the single thing that actually needs a human until someone happened
          # to look in a gap. It cannot be promoted above WORKING (a live session's own worktree is supposed
          # to be dirty, so it would cry wolf every session — tests/prove-status.sh [8] pins that), so it
          # rides along in the hint instead.
          if _owk="$(orphaned_work)"; then
            _n=0; for _d in $_owk; do _n=$((_n+1)); done
            STATE_HINT="$STATE_HINT  ⚠ also: $(plural "$_n" 'worktree') holding uncommitted work — see 'Needs you'."
          fi ;;
        *THROTTLED*)
          # Pass the epoch through: ratelimit_phrase with no argument degrades to a bare "usage cap" and throws
          # away the reset time the lib just computed, which is the half of the sentence the owner acts on.
          STATE_LINE="Paused — it hit the $(ratelimit_phrase "$(ratelimit_reset_epoch)")"
          STATE_HINT="This is NOT out of work; it retries by itself. Idle $(human_secs "$idle")." ;;
        *'WAITING FOR THE SUITE'*)
          STATE_LINE="Waiting for a test suite to finish ($(human_secs "$idle"))"
          STATE_HINT="This is NOT out of work — $(suite_blocking), and two at once corrupt both. It goes by itself." ;;
        *'ORPHANED WORK'*)
          # RED, not amber: unlike the two above this does NOT clear by itself, and what is at risk is
          # finished work rather than a few minutes of waiting.
          STATE_ICON="${RED}✕${OFF}"
          # ⚠️ EVERY worktree, not `${_orph%% *}`. The first cut named only the head of the list, which on
          # the machine this was written on meant reporting 660 insertions in one worktree and silently
          # omitting 887 in another — understating the loss by more than half while looking specific.
          _orph="$(orphaned_work)"; _osum=""; _on=0
          for _d in $_orph; do
            _on=$((_on + 1))
            _osum="$_osum   ${_d/#$HOME/~} —$(orphaned_work_summary "$_d")"$'\n'
          done
          STATE_LINE="Work was never committed — $(plural "$_on" 'worktree') holding it ($(human_secs "$idle") since the last commit)"
          STATE_HINT="NOT an empty queue. Nothing is lost until these are removed:"$'\n'"${_osum%$'\n'}" ;;
        *)
          STATE_LINE="Running, but not finding anything it can do ($(human_secs "$idle"))"
          STATE_HINT="Usually means what is left is waiting on you — see 'Needs you' below." ;;
      esac ;;
  esac
elif [ "$supervised" = 1 ]; then
  # Job loaded but no process: either between restarts, or crash-looping. Never let those two read alike.
  lec="$(launchctl print "$GUI_DOMAIN/$JOB" 2>/dev/null | awk -F'= ' '/last exit code/{gsub(/[^0-9-]/,"",$2); print $2; exit}')"
  STATE_ICON="${RED}✕${OFF}"; STATE_LINE="Set to run, but not running right now"
  STATE_HINT="Restarting, or failing to start (last exit ${lec:-?}). If it persists: $DAEMON_CMD stop, then $DAEMON_CMD start"
elif tail -n 8 "$LOG" 2>/dev/null | grep -q 'PARKED' || [ -f "$PARKNOTE" ]; then
  STATE_ICON="${AMB}◆${OFF}"; STATE_LINE="Stopped itself — what is left needs a decision from you"
  STATE_HINT="Nothing is lost. Clear what it is waiting on, then restart it: $DAEMON_CMD start"
  [ -f "$PARKNOTE" ] && STATE_HINT="$STATE_HINT  (see ${PARKNOTE/#$HOME/~})"
else
  STATE_ICON="${DIM}○${OFF}"; STATE_LINE="Not running"
  STATE_HINT="Nothing is working on the project right now. Start it: $DAEMON_CMD start"
fi

# ---------------------------------------------------------------------------------------------------
# STATE 2 — what has it done, how much is left, is the code healthy, is a suite running?
# ---------------------------------------------------------------------------------------------------
commits24=0; lastwhen="?"; lastsubj=""
if [ "$HAVE_GIT" = 1 ]; then
  commits24="$(num "$(g log --since='24 hours ago' --oneline | wc -l | tr -d ' ')")"
  lastwhen="$(g log -1 --format='%cr')"; lastwhen="${lastwhen:-—}"
  lastsubj="$(clip "$(g log -1 --format='%s')" 62)"
fi

# QUEUE.md is committed, so it can contain a FORMAT EXAMPLE of a checkbox inside a fence or a quote — skip
# those, or documenting the queue inflates the queue. And anchor the box to the bullet with `[[:space:]]+`,
# never `.*`: `[-*]` accepts the `*` of `**bold**`, so `.*` matches any wrapped prose line that merely
# mentions a checkbox later on. Both mistakes have been made and both only ever showed up as a wrong count.
#
# HELD ITEMS ARE COUNTED SEPARATELY, and that is not a cosmetic preference. `[hold]` / `needs: owner` items
# are printed by `next-item.sh` but never OFFERED, so folding them into "N items queued" overstates what the
# run can actually do — it reported "13 items queued" against 10 actionable ones on the first real render.
# In a project whose stated rule is that an entry without evidence is a rumour, the check-in surface must not
# round up its own backlog.
# ⛔ BUT THE HELD FIGURE IS NOT RENDERED AT ALL — owner, 2026-08-21. DO NOT PUT IT BACK; its absence is the
# decision, not an oversight. It read `· 3 items waiting on you`, and every word of that was wrong except the
# number: `## HOLD` is a PERMANENT exclusion class ("These are offered to nobody" — its own header), so
# nothing in it is pending an owner action and the count cannot go down. `taborder` was accepted as a known
# gap on 2026-08-13 rather than queued, `release` is the standing release item and explicitly "not a
# one-off", and `corpus-write` is a policy guardrail on `testdocs/`. A constant that reads as an inbox is
# the `check-staleness.sh` failure again — a line that cannot change gets read as noise until the one time
# it matters. Owner-only work is visible where it is decided: `next-item.sh` still prints it as `hold`, and
# `QUEUE.md`'s own section names all three. `hold_q` is still tallied below because the resolver's own
# accounting is what keeps holds OUT of `open_q`; it just is not printed.
# ⚠️ ASK THE RESOLVER, DO NOT RE-DERIVE. `next-item.sh` is the single authority on what an item is and
# whether it is actionable, and it accumulates each item's FULL SPAN — so a `(blocked-on: …)` clause or a
# `[hold]` marker that wrapped onto a continuation line is still seen. A second implementation here got
# that wrong the first time it ran for real: it counted only the checkbox line, so the `release` item —
# whose `[hold]` sits on its second line — was reported as actionable work, and the digest read
# "11 queued · 2 waiting on you" for a queue with 10 offerable items and 3 held.
#
# That is the specific failure the sibling project documents: if the renderer and the resolver disagree
# about what an item is, the renderer reports numbers the daemon will never act on. So the awk fallback
# below exists ONLY for a checkout where the resolver is missing, and it says so when it is used.
open_q=0; done_q=0; hold_q=0
if [ -x "$RESOLVER" ]; then
  # Exit codes are meaningful (0 actionable / 3 drained / 4 all blocked / 2 malformed) but we want the
  # tallies either way, so the status is deliberately ignored here — `2` is surfaced separately below.
  ni="$(VISIONOCR_QUEUE="$QUEUE" VISIONOCR_BUGS="$REPO/BUGS.md" "$RESOLVER" "$REPO" 2>/dev/null)"
  ni_rc=$?
  open_q="$(num "$(printf '%s\n' "$ni" | grep -c '^ok	')")"
  blocked_q="$(num "$(printf '%s\n' "$ni" | grep -c '^blocked:')")"
  hold_q="$(num "$(printf '%s\n' "$ni" | grep -c '^hold	')")"
  # Done items are not printed by the resolver (it offers open work only), so that one figure is still
  # counted here — a ticked box is unambiguous on its own line and needs no span walk.
  done_q="$(num "$(grep -cE '^[[:space:]]*[-*][[:space:]]+\[[xX]\]' "$QUEUE" 2>/dev/null)")"
else
  ni_rc=0; blocked_q=0
  qc="$(awk '
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence || /^[[:space:]]*>/ { next }
    /^[[:space:]]*[-*][[:space:]]+\[[ xX]\]/ {
      match($0, /\[[ xX]\]/)                     # 2-arg match only: /usr/bin/awk has no 3-arg form
      if (substr($0, RSTART + 1, 1) != " ") { d++; next }
      if ($0 ~ /\[hold\]/ || $0 ~ /needs:[[:space:]]*owner/) h++; else o++
    }
    END { printf "%d %d %d", o + 0, d + 0, h + 0 }' "$QUEUE" 2>/dev/null)"
  set -- $qc
  open_q="$(num "${1:-0}")"; done_q="$(num "${2:-0}")"; hold_q="$(num "${3:-0}")"
fi

# $STATE/last-gate holds a sha written ONLY on a green gate, so on its own this block is STRUCTURALLY
# incapable of reporting a gate that has since gone RED — it once printed "Build and tests passed, 30 changes
# ago" for a run that had parked on a RED gate 41 minutes earlier, read as "healthy, just stale" when the
# truth was "the last full check FAILED". So read the verdict line out of last-gate.log too and prefer RED.
# ⚠️ That file is written IN PLACE, so it is half-written WHILE a gate runs — skip it then, don't half-read it.
gate_red=""
if ! pgrep -f 'ops/autonomous/health-gate\.sh' >/dev/null 2>&1; then
  gate_red="$(grep '^HEALTH GATE: RED' "$STATE/last-gate.log" 2>/dev/null | tail -n 1 \
              | sed 's/^HEALTH GATE: RED[^A-Za-z0-9]*//' | tr -s ' ' | sed 's/^ *//; s/ *$//')"
fi
gate_last="$(cat "$STATE/last-gate" 2>/dev/null)"
if [ -n "$gate_red" ]; then
  HEALTH="${RED}The last full check FAILED${OFF}: $(clip "$gate_red" 48) — that step is broken now"
elif [ -n "$gate_last" ] && [ "$HAVE_GIT" = 1 ] && g cat-file -e "${gate_last}^{commit}"; then
  gate_behind="$(num "$(g rev-list --count "$gate_last..HEAD")")"
  case "$gate_behind" in
    0) HEALTH="Build, suite and tool type-check passed, on the current code" ;;
    *) HEALTH="Build, suite and tool type-check passed, $(plural "$gate_behind" commit) ago" ;;
  esac
elif [ -n "$gate_last" ]; then
  HEALTH="Last passed at ${gate_last:0:7} — a commit this checkout does not have, so how stale is unknown"
else
  HEALTH="Not checked yet — the next run will do a full build, suite and tool type-check"
fi

# ⚠️ `pgrep -x tests`, NEVER `pgrep -f build/tests` — CLAUDE.md names this as its own trap: the `-f` form
# matches every WAITER whose command line holds the string, including this shell, so the guard reports a suite
# on a machine with none. Four such loops once sat waiting on each other while nothing ran. test-lock.sh
# already gets this right and also sees the lock, so ask it first; fall back only if it is missing.
lock_line=""
if [ -x "$HERE/test-lock.sh" ]; then
  # Pass VISIONOCR_STATE through: test-lock.sh derives its lock directory from it, so a digest rendered
  # against a scratch state dir must not report on the REAL lock. Getting this wrong is not a cosmetic
  # mislabel — for a mutex, reporting the wrong lock is how two callers each conclude the suite is free.
  tl="$(VISIONOCR_STATE="$STATE" "$HERE/test-lock.sh" status 2>/dev/null)"   # read-only; exit 1 = busy
  lock_line="$(printf '%s\n' "$tl" | grep '^lock' | sed 's/^lock[[:space:]]*//')"
  if printf '%s\n' "$tl" | grep -q '^suite  *RUNNING'; then
    SUITE="${AMB}a suite is RUNNING${OFF} — do not start another (they share ~/Library/Preferences/tests.plist)"
  else SUITE="no test suite running"; fi
elif pgrep -x tests >/dev/null 2>&1; then
  SUITE="${AMB}a suite is RUNNING${OFF} — do not start another (pgrep -x tests; test-lock.sh is missing)"
else SUITE="no test suite running (pgrep -x tests; test-lock.sh is missing)"; fi

# ---------------------------------------------------------------------------------------------------
# STATE 3 — does it need me? Only genuine, actionable asks; each says what to DO, not what is wrong.
# Nothing that is actually WRONG may hide behind --details, so everything below prints with no flag.
# ---------------------------------------------------------------------------------------------------
run_status="$(grep -m1 '^[[:space:]]*RUN STATUS:' "$RUNMD" 2>/dev/null | sed 's/^[[:space:]]*//')"
disk_gb="$(df -m "$REPO" 2>/dev/null | awk 'NR==2{printf "%d", $4/1024}')"
case "$disk_gb" in ''|*[!0-9]*) disk_gb="" ;; esac    # unknown is not the same as zero — don't warn on it
gate_to="$(num "$(cat "$STATE/gate-timeouts" 2>/dev/null | tr -dc '0-9')")"
needs=""
add_need() { needs="$needs"$'\n'"    • $1"; }

# ⚠️ RUN.md's `## NEEDS OWNER` LIST — THE DAEMON'S OUTBOX, AND IT WAS NEVER READ HERE. This is the mechanism
# the resume prompt gives every session for anything that needs a human ("append here and move on — it never
# waits, because nobody is awake to answer"), and RUN.md's own comment beside the heading states that
# "`daemon.sh status` surfaces this under 'Needs you'". It did not. Six conditions below could raise a need —
# a park note, a docfix, a red gate, gate timeouts, COMPLETE-with-open-items, low disk — and not one of them
# was this list.
#
# Measured 2026-08-16 22:51: two real entries sat in NEEDS OWNER, including a dead session's worktree holding
# 660 uncommitted lines with removal instructions, while this digest printed "Needs you  Nothing right now."
# That is the same lie as the state line above, in the one section whose entire job is answering "does it
# need me?", and it silently breaks the half of the arrangement that makes unattended work safe: a session
# writes the note, moves on, and the note is never delivered.
#
# Parsed rather than dumped: only top-level `- ` bullets between the heading and the next `## `, with the
# explanatory HTML comment skipped, so the section's own prose cannot masquerade as an item.
if [ -f "$RUNMD" ]; then
  while IFS= read -r _n; do
    [ -n "$_n" ] || continue
    add_need "$(clip "$_n" 88)"
  done <<EOF
$(awk '
    /^## NEEDS OWNER/ { inb = 1; next }
    inb && /^## /     { exit }
    inb && /<!--/     { inc = 1 }
    inb && inc        { if (/-->/) inc = 0; next }
    inb && /^- /      { sub(/^- /, ""); gsub(/\*\*/, ""); print }
  ' "$RUNMD" 2>/dev/null)
EOF
fi

[ -f "$PARKNOTE" ] && \
  add_need "It parked and left you a note: $(clip "$(head -n 1 "$PARKNOTE" 2>/dev/null)" 62) (${PARKNOTE/#$HOME/~})"
[ -f "$STATE/docfix" ] && \
  add_need "It wants a doc trimmed: $(clip "$(head -n 1 "$STATE/docfix" 2>/dev/null)" 62)"
[ -n "$gate_red" ] && \
  add_need "The last full check FAILED ($(clip "$gate_red" 40)) — fix that before anything else lands"
[ "$gate_to" -gt 0 ] && \
  add_need "$(plural "$gate_to" gate) timed out — the suite may be wedged: $DAEMON_CMD status --details"
case "$run_status" in
  *COMPLETE*) [ "$open_q" -gt 0 ] && \
    add_need "The run says COMPLETE but $(plural "$open_q" item) are still open — it needs a new steer (## FOCUS in RUN.md)" ;;
esac
[ -n "$disk_gb" ] && [ "$disk_gb" -lt 5 ] && \
  add_need "Only ${disk_gb} GB free on $REPO's volume — a build plus a suite needs more room than that"

# ---------------------------------------------------------------------------------------------------
# RENDER — the default view. Five answers, nothing else.
# ---------------------------------------------------------------------------------------------------
printf '%s\n' "${B}Vision OCR — autonomous worker${OFF}   ${DIM}$(date '+%a %-d %b, %H:%M')${OFF}"
printf '\n  %s  %s\n' "$STATE_ICON" "${B}${STATE_LINE}${OFF}"
[ -n "$STATE_HINT" ] && printf '     %s%s%s\n' "$DIM" "$STATE_HINT" "$OFF"

if [ "$HAVE_GIT" != 1 ]; then
  printf '\n  %-10s %s\n' "Done" "? — no git checkout at $REPO"
elif [ "$commits24" -gt 0 ]; then
  printf '\n  %-10s %s in the last 24 hours · latest %s\n' "Done" "$(plural "$commits24" commit)" "$lastwhen"
else
  printf '\n  %-10s nothing in the last 24 hours · latest commit %s\n' "Done" "$lastwhen"
fi
[ -n "$lastsubj" ] && printf '  %-10s %s%s%s\n' "" "$DIM" "\"$lastsubj\"" "$OFF"
if [ -f "$QUEUE" ]; then
  printf '  %-10s %s queued · %s finished\n' "Left" "$(plural "$open_q" item)" "$done_q"
else
  printf '  %-10s %s\n' "Left" "? — no queue file at $QUEUE"
fi
printf '  %-10s %s\n' "Health" "$HEALTH"
printf '  %-10s %s\n' "Suite" "$SUITE"

if [ -n "$needs" ]; then
  printf '\n  %-10s%s\n' "Needs you" "$needs"
else
  printf '\n  %-10s %sNothing right now.%s\n' "Needs you" "$GRN" "$OFF"
fi

# ---------------------------------------------------------------------------------------------------
# RENDER — --details. Diagnostics, for when the view above says something is wrong.
# ---------------------------------------------------------------------------------------------------
if [ "$DETAILS" = 1 ]; then
  focus="$(awk '/^## FOCUS/{f=1;next} f&&/^## /{exit} f&&NF' "$RUNMD" 2>/dev/null | head -n 2 | tr '\n' ' ')"
  printf '\n  %s\n' "${B}Details${OFF}"
  printf '  %-18s %s\n' "current code" "$([ "$HAVE_GIT" = 1 ] && clip "$(g log -1 --format='%h %s')" 62 || echo '?')"
  printf '  %-18s %s\n' "branch" "$([ "$HAVE_GIT" = 1 ] && g rev-parse --abbrev-ref HEAD || echo '?')"
  printf '  %-18s %s\n' "run state" "${run_status:-(no RUN.md)}"
  printf '  %-18s %s\n' "your steer" "$(clip "${focus:-(no ## FOCUS section)}" 62)"
  printf '  %-18s %s\n' "restart on crash" "$([ "$supervised" = 1 ] && echo 'yes (launchd keeps it alive)' || echo 'no (not loaded in launchd)')"
  printf '  %-18s %s\n' "disk free" "${disk_gb:-?} GB"
  printf '  %-18s %s\n' "suite lock" "${lock_line:-? (test-lock.sh missing)}"
  printf '\n  %s\n' "${B}Next up${OFF}"
  awk '
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence || /^[[:space:]]*>/ { next }
    /^[[:space:]]*[-*][[:space:]]+\[ \]/ { sub(/^[[:space:]]*[-*][[:space:]]+\[ \][[:space:]]*/, ""); print "    " substr($0, 1, 74); n++ }
    n == 3 { exit }' "$QUEUE" 2>/dev/null || true
  [ "$open_q" -gt 0 ] || printf '    (nothing open)\n'
  printf '\n  %s\n' "${B}Last few log lines${OFF}"
  if [ -s "$LOG" ]; then tail -n 12 "$LOG" 2>/dev/null | sed 's/^/    /'
  else printf '    (no log yet)\n'; fi
else
  printf '\n  %smore: %s status --details%s\n' "$DIM" "$DAEMON_CMD" "$OFF"
fi
exit 0
