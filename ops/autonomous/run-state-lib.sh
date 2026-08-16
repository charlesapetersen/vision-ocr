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

# idle_explanation IDLE_SECONDS — the full one-line reason a live daemon is not advancing. This is the
# function the status renderers call, and it is what keeps the wording identical across both of them.
#
# ORDER MATTERS, and it is not arbitrary: throttling is checked first because a capped session cannot have
# reached the suite at all, so a 429 is the more upstream explanation. The suite check is second because it
# is a real, self-clearing wait. "No actionable work" is LAST — it is the residual, and making it the
# fallback is precisely the bug this file exists to fix, so it must never be reachable while a more
# specific explanation holds.
idle_explanation() {
  local idle="${1:-?}" reset suite
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
  printf 'running, BACKING OFF (idle %ss — sessions finding no actionable work; retrying, widening the gap)' \
    "$idle"
  return 0
}
