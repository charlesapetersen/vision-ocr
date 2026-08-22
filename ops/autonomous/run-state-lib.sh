# run-state-lib.sh — the ONE place that decides WHY the daemon is idle.
# SOURCE this (`. "$(dirname "$0")/run-state-lib.sh"`), never execute it.
#
# WHY THIS FILE EXISTS — ported from the Archive Suite daemon, where it was written after a measured
# misreport. On 2026-07-31 that project's `daemon.sh status` said "running, BACKING OFF (idle 3375s —
# sessions finding no actionable work)" for an hour while the truth was a 429: every session for the
# previous two hours had been refused by the five-hour usage cap and died in ~5 seconds, and the queue
# resolver was offering ~20 actionable items the whole time.
#
# The point is that the two states call for OPPOSITE responses from the owner — "the queue is drained, go
# add work or stop the daemon" versus "it is throttled, it resumes by itself at 07:30" — and the status
# line asserted the first while the second was true. The daemon's BACKOFF *behaviour* is correct either way
# (waiting longer is exactly what a cap wants), so this file changes REPORTING ONLY and touches no control
# flow. That separation is why it is safe to port wholesale.
#
# It lives here rather than inside either renderer because `daemon.sh` and `status-digest.sh` both render
# this state, and a detector written twice is a detector that gets fixed once.
#
# THE VISION-OCR ADDITION: a third reason. This project cannot run two test suites at once (CLAUDE.md's
# first environment trap — `build/tests` has no bundle id, so every worktree shares
# ~/Library/Preferences/tests.plist), so `test-lock.sh` serialises them. That means a healthy, unthrottled
# daemon with a full queue can still sit doing nothing because the owner is running a suite interactively.
# Reporting that as "finding no actionable work" would send the owner hunting an empty queue while the real
# answer is "it is politely waiting for you, and will go by itself". Same class of lie, so it gets the same
# treatment: its own branch, in this file, in the callers' shared wording.
#
# Works under `set -uo pipefail` (every caller uses it) — no unguarded command substitution, no bare
# trailing `[ ]`, and every function returns explicitly.

# ratelimit_reset_epoch [logfile] — echo the cap's reset epoch and return 0 if the MOST RECENT session
# ended refused by a usage cap; return 1 (echoing nothing) otherwise. Reads only the last session's own
# log, so a cap hit yesterday cannot colour today's status.
#
# Keyed on the TERMINAL result record (`"api_error_status":429`), NOT on the `rate_limit_event` record: a
# session can log a rate_limit_event, recover, and go on to do useful work, and reporting that as throttled
# would be the same class of lie in the other direction. `resetsAt` is read separately because it appears
# on the event, not on the result.
ratelimit_reset_epoch() {
  local f="${1:-${STATE:-$HOME/.local/state/visionocr-autonomous}/last-session.log}" reset
  [ -f "$f" ] || return 1
  grep -q '"api_error_status":429' "$f" 2>/dev/null || return 1
  reset="$(grep -o '"resetsAt":[0-9]*' "$f" 2>/dev/null | tail -1 | cut -d: -f2)"
  printf '%s' "${reset:-}"
  return 0
}

# ratelimit_phrase EPOCH — a human tail for the status line. Distinguishes "still capped, resumes at HH:MM"
# from "the cap has already lifted, the next scheduled attempt will get through", because those too are
# different owner actions (wait, vs. it is already fixing itself and needs nothing).
ratelimit_phrase() {
  local reset="${1:-}" now
  now="$(date +%s)"
  case "$reset" in
    ''|*[!0-9]*) printf 'usage cap' ; return 0 ;;
  esac
  if [ "$reset" -gt "$now" ] 2>/dev/null; then
    printf 'usage cap, resets %s' "$(date -r "$reset" '+%H:%M' 2>/dev/null || echo '?')"
  else
    printf 'usage cap, already reset %s — next attempt should get through' \
      "$(date -r "$reset" '+%H:%M' 2>/dev/null || echo '?')"
  fi
  return 0
}

# suite_blocking — return 0 if a test suite is running that the daemon must wait behind, echoing a short
# phrase naming who holds it. This is the vision-ocr-specific branch described in the header.
#
# ⚠️ `pgrep -x tests`, NEVER `pgrep -f build/tests`. CLAUDE.md records this as its own trap: the `-f` form
# matches every WAITER whose command line contains the string — including this shell — so a "is a suite
# running?" guard reports yes on a machine with no suite on it. Four such loops once sat waiting on each
# other while nothing ran, and the guard they fed refused to start the real run. `-x` matches the process
# NAME, which for `build/tests` is exactly `tests`.
suite_blocking() {
  local lockdir="${VISIONOCR_TEST_LOCK:-${STATE:-$HOME/.local/state/visionocr-autonomous}/test.lock}" lbl
  if pgrep -x tests >/dev/null 2>&1; then
    lbl="$(cat "$lockdir/label" 2>/dev/null)"
    if [ -n "$lbl" ]; then
      printf 'a test suite is running (%s)' "$lbl"
    else
      # No lock label => it was started outside the lock, i.e. almost certainly the owner by hand or an
      # agent shelling out directly. Say so, because it changes who has to do something about it.
      printf 'a test suite is running, started outside the suite lock (an interactive run, most likely yours)'
    fi
    return 0
  fi
  return 1
}

# orphaned_work — echo the `auto/*` worktrees holding UNCOMMITTED work and return 0; return 1 (echoing
# nothing) when there are none. This is a fourth thing "the daemon advanced nothing" can mean, and it is the
# opposite of the other three: not "there is nothing to do" but "a session DID the work and the commit did
# not land".
#
# WHY IT EXISTS — measured 2026-08-16. A session worked 95 minutes, went green 1137/1137, backgrounded its
# `git commit`, and ended its turn; ending a turn kills background tasks, so the pre-commit hook died partway
# through its suite (`Terminated: 15`) and the tip never moved. The daemon's verdict is DERIVED from the tip
# and the queue — both correct, both unchanged — so it logged "advanced nothing (queue + tip unchanged)" and
# backed off. Every word true, the whole misleading: 660 insertions across 8 files were sitting staged in
# the session's own worktree /private/tmp/vo-20260816-184311-95643, and the NEXT session (…-202151-2803)
# redid them from scratch. Getting those two paths the right way round matters — the first draft of this
# comment named the successor as the victim, which would have sent a reader to the wrong tree.
#
# ⚠️ NO "IS A SESSION LIVE" GUARD IN HERE, ON PURPOSE — `idle_explanation` checks session_in_flight FIRST and
# returns before reaching this, and the daemon calls this only after `wait`ing on its session. A running
# session's worktree is SUPPOSED to be dirty; putting the guard in the ordering rather than in the detector
# keeps this function answering exactly one question.
#
# ⛔ THIS COMMENT USED TO DEFEND `--untracked-files=no` AND ITS PREMISE WAS FALSE. It read: "every worktree
# carries an untracked `build/` full of compiler output, and counting that as lost work would report EVERY
# worktree, always." Measured 2026-08-22 on all three live worktrees: **none of them has a `build/` directory
# at all**, they are 5.4-5.5 MB each, and `build/` is gitignored anyway — so plain `--porcelain` never listed
# it. The argument was for a cost that could not be incurred, and it bought a real blind spot: a strand whose
# only output was a NEW file was not an orphan, so it got no rescue patch and no assignment while
# `git worktree remove` still refused it, leaving it in volatile /private/tmp with no copy anywhere. Untracked
# content is counted now; see the note at the test itself.
orphaned_work() {
  local repo="${REPO:-$HOME/Claude/vision-ocr}" dir ref found=""
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 1
  while IFS="$(printf '\t')" read -r dir ref; do
    [ -n "$dir" ] || continue
    [ "$dir" = "$repo" ] && continue
    case "$ref" in refs/heads/auto/*) ;; *) continue ;; esac
    [ -d "$dir" ] || continue
    # ⛔ UNTRACKED CONTENT COUNTS. This read `--untracked-files=no`, and that made a whole class of strand
    # INVISIBLE: a worktree holding only NEW files — which is what a measurement sweep produces, a fresh
    # `.tsv` and nothing else — was not an orphan, so it got no rescue patch, no assignment and no mention
    # beyond `housekeeping()`'s "left N … for manual review" count. `git worktree remove` still refuses it
    # (untracked files make a worktree dirty), so it sat in volatile /private/tmp with NO copy anywhere,
    # which is strictly worse than the partial-patch bug of 2026-08-22 that sat beside it.
    # Safe to widen because every build product here is gitignored and plain `--porcelain` excludes ignored
    # paths: `.gitignore` covers `build/`, `testdocs/*`, `Tools/mutation-out/`, `__pycache__/` and
    # `output.[0-9]*`, and a real session worktree checked 2026-08-22 listed 5 modified files and exactly
    # one untracked `.tsv` — no build noise. So this cannot start crying wolf over compiler output.
    [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ] || continue
    found="$found $dir"
  done <<EOF
$(git -C "$repo" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{w=substr($0,10)} /^branch /{print w"\t"substr($0,8)}')
EOF
  [ -n "$found" ] || return 1
  printf '%s' "${found# }"
  return 0
}

# orphaned_work_summary DIR — "what is actually in there", so the owner can judge whether it is worth
# rescuing without going to look. Staged first, since a died-in-the-hook commit leaves its work staged.
orphaned_work_summary() {
  local d="${1:-}" n
  { [ -n "$d" ] && [ -d "$d" ]; } || return 1
  n="$(git -C "$d" diff --cached --shortstat 2>/dev/null)"
  [ -n "$n" ] || n="$(git -C "$d" diff --shortstat 2>/dev/null)"
  printf '%s' "${n:- uncommitted changes}"
  return 0
}

# session_in_flight — echo how many seconds the CURRENT resume session has been running and return 0; return
# 1 when no session is live. $STATE/engine.lock is the daemon's OWN answer to this question (`tick` skips a
# cycle when it finds one fresh), which is why this reads that rather than pgrep — CLAUDE.md's `pgrep -f`
# trap is that the pattern matches every process whose command line CONTAINS it, and the session's command
# line is the entire resume prompt, so half the greps one would reach for here match themselves.
#
# ⚠️ A STALE LOCK MUST NOT READ AS "WORKING". If the daemon is hard-killed (lid, SIGKILL) the lock survives
# with nothing behind it. The daemon heartbeats the file every **60 s** (the `touch "$LOCK"` subshell in the
# session launcher — NOT $HB_POLL, which is the health watchdog's 20 s and a different clock entirely), so
# an mtime older than a few minutes means the heartbeat stopped: lock present, session gone.
#
# ⚠️ THE ELAPSED FIGURE IS BEST-EFFORT AND CAN OVERSTATE, in exactly one case. Birth time (%B) is the
# session's start on the normal path — verified against daemon.log's launch line — but the daemon's
# stale-lock TAKEOVER path `touch`es the EXISTING file rather than recreating it, and `touch` preserves
# birthtime on APFS (measured). So after a hard kill plus a takeover, this reports the age of the DEAD
# session's lock, not the live one's. It is a display figure, never a control input, and the liveness half
# (%m) stays correct either way — but do not build anything on the elapsed number without fixing the
# takeover to `rm -f` the lock first.
session_in_flight() {
  local lock="${STATE:-$HOME/.local/state/visionocr-autonomous}/engine.lock" beat born now
  [ -f "$lock" ] || return 1
  beat="$(stat -f %m "$lock" 2>/dev/null)"; born="$(stat -f %B "$lock" 2>/dev/null)"
  case "$beat" in ''|*[!0-9]*) return 1 ;; esac
  now="$(date +%s)"
  # 300 s = five missed 60-second heartbeats. Generous on purpose: a false "it is dead" here would report a
  # working session as an idle queue, which is the whole failure this file exists to prevent.
  [ "$(( now - beat ))" -lt 300 ] || return 1
  case "$born" in ''|*[!0-9]*) born="$beat" ;; esac
  printf '%s' "$(( now - born ))"
  return 0
}

# idle_explanation IDLE_SECONDS — the full one-line reason a live daemon is not advancing. This is the
# function the status renderers call, and it is what keeps the wording identical across both of them.
#
# ORDER MATTERS, and it is not arbitrary. WORKING is first because it is not a reason to be idle at all —
# it is the answer that the premise is wrong, and it outranks every explanation below it. Throttling is next
# because a capped session cannot have reached the suite. The suite wait is a real, self-clearing wait.
# ORPHANED WORK is fourth: a session ran and produced something, so it is emphatically not an empty queue.
# "No actionable work" is LAST — it is the residual, and making it the fallback is precisely the bug this
# file exists to fix, so it must never be reachable while a more specific explanation holds.
#
# ⚠️ THE CALLER'S IDLE CLOCK IS NOT A WORK CLOCK. $STATE/idle.since advances only when the git tip or the
# queue moves, i.e. on a COMMIT — so a session that has been writing code for an hour without committing
# shows an hour of "idle", and every renderer that read that number alone has reported a working daemon as a
# drained one. Measured 2026-08-16 21:19: a session 59 minutes in, actively editing `Tests/main.swift`, was
# rendered as "Running, but not finding anything it can do (62 minutes)". Hence the WORKING branch.
idle_explanation() {
  local idle="${1:-?}" reset suite ran orph
  if ran="$(session_in_flight)"; then
    printf 'running, WORKING (a session has been in flight %ss; idle %ss only measures time since the last COMMIT, and a session that has not committed yet has not been idle)' \
      "$ran" "$idle"
    return 0
  fi
  if reset="$(ratelimit_reset_epoch)"; then
    printf 'running, THROTTLED (idle %ss — last session was REFUSED by the %s; this is NOT an empty queue)' \
      "$idle" "$(ratelimit_phrase "$reset")"
    return 0
  fi
  if suite="$(suite_blocking)"; then
    printf 'running, WAITING FOR THE SUITE (idle %ss — %s, and two suites at once corrupt both; it goes by itself when that finishes)' \
      "$idle" "$suite"
    return 0
  fi
  if orph="$(orphaned_work)"; then
    printf 'running, ORPHANED WORK (idle %ss — a session did the work but its commit never landed; uncommitted changes are sitting in %s. This is NOT an empty queue)' \
      "$idle" "$orph"
    return 0
  fi
  printf 'running, BACKING OFF (idle %ss — sessions finding no actionable work; retrying, widening the gap)' \
    "$idle"
  return 0
}
