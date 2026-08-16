#!/usr/bin/env bash
# ops/autonomous/test-lock.sh — ONE test suite at a time, machine-wide.
#
# WHY THIS EXISTS, and why it is the first file of this daemon rather than an afterthought.
# CLAUDE.md's first environment trap: "Never run two suites at once, in any two worktrees."
# `build/tests` has no bundle identifier, so `UserDefaults.standard` lands in a domain keyed by the
# process NAME — ~/Library/Preferences/tests.plist — and EVERY worktree shares that one file. A second
# suite's resetPrefs() removes every key and wipes the first one's settings mid-run. Measured:
# 882/883 -> 877/879, two failures in the run-report block, because the other run cleared
# `writeRunReport` between this one setting it and the batch finishing.
#
# An unattended daemon makes that trap MUCH easier to hit than a human does, in three ways a human does not:
#   1. it fires a session every cycle, and every code commit runs the suite via .githooks/pre-commit;
#   2. its health gate runs the suite on a cadence, in the daemon loop;
#   3. the owner keeps working interactively in the primary checkout at the same time (this repo had two
#      such sessions live while this file was being written).
# So the collision is not hypothetical here, and its symptom is the WORST kind: a green-looking run with
# a handful of unrelated failures, i.e. evidence that is wrong rather than absent. This project's whole
# process exists to stop exactly that ("suspect the instrument first"), so the daemon must not manufacture it.
#
# WHAT IT GUARDS AGAINST, and what it deliberately does not. This is a COOPERATIVE lock: it serialises
# every caller that goes through it. It cannot stop a suite launched by something that never heard of it
# (a hand-typed `./run_tests.sh` in a fresh clone, an agent shelling out directly). So it ALSO consults
# `pgrep`, which sees those — that is the belt to the lockfile's braces, and the reason `status` reports
# both.
#
# ⚠️ `pgrep -x tests`, NEVER `pgrep -f build/tests` — CLAUDE.md names this as its own trap. The `-f` form
# matches every WAITER whose command line contains the string, including the pgrep's own shell, so a
# "is a suite running?" guard reports yes on a machine with no suite on it. Four such loops once sat
# waiting on each other while nothing ran, and the guard they fed refused to start the real run. `-x`
# matches the process NAME, which for build/tests is exactly `tests`.
#
# USAGE
#   test-lock.sh run [--label L] [--wait S] -- <cmd> [args…]   acquire, run <cmd>, release (the main form)
#   test-lock.sh acquire [--label L] [--wait S]                 acquire and return (caller must release)
#   test-lock.sh release                                        release a lock this pid tree holds
#   test-lock.sh status                                         who holds it + whether a suite is live (read-only)
#
# EXIT: 0 ok (for `run`, the command's own status is propagated) · 4 could not acquire within --wait
#       · 2 usage error.  `status` is 0 when free, 1 when busy.
set -uo pipefail

# Backgrounded shell commands here have essentially no PATH (CLAUDE.md: basename/cut/timeout fail
# silently and loops report bogus results), and this script is invoked from a launchd daemon, a git hook
# and a health gate — all three of those contexts. Set it explicitly rather than inheriting nothing.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# ⚠️ DERIVE FROM $VISIONOCR_STATE, do not hardcode the state directory. The first cut defaulted straight to
# `$HOME/.local/state/visionocr-autonomous/test.lock`, which meant a caller running with a custom
# VISIONOCR_STATE — every test harness, and `daemon.sh status` pointed at a scratch state dir — silently
# consulted the REAL lock instead of its own. That reports on the wrong machine state, and for a mutex the
# consequence is worse than a wrong number: two callers each believing they hold different locks is exactly
# the double-suite this file exists to prevent. Fixed here, in the one place, rather than by having every
# caller remember to pass VISIONOCR_TEST_LOCK.
LOCKDIR="${VISIONOCR_TEST_LOCK:-${VISIONOCR_STATE:-$HOME/.local/state/visionocr-autonomous}/test.lock}"
# A suite is 3-6 min and a gate can legitimately queue behind one, so the default wait is generous.
# 0 means "fail immediately if busy".
WAIT_DEFAULT="${VISIONOCR_TEST_LOCK_WAIT:-1800}"
# A holder whose pid is gone is stale immediately (see _holder_alive). This is the backstop for the
# other case: a live pid that has wandered off (a wedged suite). 90 min is well past the 3-6 min suite
# and the ~10 min gate, so it can only fire on something genuinely stuck.
MAXAGE="${VISIONOCR_TEST_LOCK_MAXAGE:-5400}"

# WHOSE pid owns the lock. For `run` this script stays alive as the command's parent, so its own `$$` is the
# honest answer. But `acquire` and `release` are SEPARATE invocations — two different processes — so a bare
# `$$` would record this short-lived helper's pid on acquire and then compare against a DIFFERENT one on
# release, and release would refuse to unlock what the caller legitimately holds. The pre-commit hook uses
# exactly that acquire/trap-release shape, so this is not hypothetical.
#
# Recording the CALLER's pid also makes the stale check correct rather than merely permissive: the holder of
# record becomes the process that will actually still be alive while the suite runs, so `_holder_alive` gives
# a true answer when a hook or a gate is killed mid-run.
OWNER_PID="${VISIONOCR_TEST_LOCK_PID:-$$}"

usage() { sed -n '/^# USAGE/,/^# EXIT/p' "$0" | sed 's/^# \{0,1\}//'; }

_now() { date +%s; }
_holder_pid()   { cat "$LOCKDIR/pid"   2>/dev/null; }
_holder_label() { cat "$LOCKDIR/label" 2>/dev/null; }
_holder_age() {
  local m; m="$(stat -f %m "$LOCKDIR" 2>/dev/null)"
  case "$m" in ''|*[!0-9]*) echo 0; return ;; esac
  echo $(( $(_now) - m ))
}
# A holder pid that no longer exists means the process died without releasing (a killed session, a
# watchdog TERM, a closed laptop lid). That is the common case on this machine, so it must resolve
# instantly rather than waiting out MAXAGE.
_holder_alive() {
  local p; p="$(_holder_pid)"
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$p" 2>/dev/null
}

# Is a suite running that did NOT come through this lock? See the -x note in the header.
_suite_live() { pgrep -x tests >/dev/null 2>&1; }

# Try once. 0 = acquired. 1 = busy.
_try_acquire() {
  local label="$1"
  # mkdir is atomic on every filesystem this repo runs on, which is why the lock is a DIRECTORY and not
  # a file written with `>`. Two racing `[ -f ] && touch` callers both win; two racing mkdirs cannot.
  if mkdir "$LOCKDIR" 2>/dev/null; then
    printf '%s\n' "$OWNER_PID" > "$LOCKDIR/pid"   2>/dev/null || true
    printf '%s\n' "$label" > "$LOCKDIR/label" 2>/dev/null || true
    # Re-check for an out-of-band suite AFTER taking the lock, then yield to it. Checking only before
    # would leave a window: a hand-run suite that starts between the check and the mkdir would run
    # alongside ours, which is the exact collision this file exists to prevent.
    if _suite_live; then
      rm -rf "$LOCKDIR" 2>/dev/null || true
      return 1
    fi
    return 0
  fi
  # Held. Reclaim it only if the holder is provably gone, or it has aged out.
  local age; age="$(_holder_age)"
  if ! _holder_alive; then
    echo "test-lock: holder pid $(_holder_pid) is gone (lock ${age}s old) — reclaiming." >&2
    rm -rf "$LOCKDIR" 2>/dev/null || true
    return 1     # deliberately do NOT acquire on this pass: let the next loop iteration race for it
                 # fairly, so two reclaimers cannot both conclude they own it.
  fi
  if [ "$MAXAGE" -gt 0 ] && [ "$age" -ge "$MAXAGE" ]; then
    echo "test-lock: holder '$(_holder_label)' (pid $(_holder_pid)) has held the lock ${age}s (>= ${MAXAGE}s) — breaking it." >&2
    rm -rf "$LOCKDIR" 2>/dev/null || true
    return 1
  fi
  return 1
}

acquire() {
  local label="$1" wait_s="$2" waited=0
  mkdir -p "$(dirname "$LOCKDIR")" 2>/dev/null || true
  while :; do
    _try_acquire "$label" && return 0
    [ "$wait_s" -le 0 ] && return 4
    [ "$waited" -ge "$wait_s" ] && return 4
    # 5s granularity: a suite runs for minutes, so polling faster buys nothing and a launchd daemon
    # should not spin. Announce once, not every poll, or the daemon log fills with waiting notices.
    [ "$waited" = 0 ] && {
      if _suite_live; then
        echo "test-lock: a suite is already running (pgrep -x tests) — waiting up to ${wait_s}s…" >&2
      else
        echo "test-lock: '$(_holder_label)' holds the suite lock (pid $(_holder_pid)) — waiting up to ${wait_s}s…" >&2
      fi
    }
    sleep 5; waited=$(( waited + 5 ))
  done
}

# Release only what we hold. A release that does not check the pid is how a stale caller steals the lock
# from whoever legitimately took it over after a break-in above.
release() {
  local p; p="$(_holder_pid)"
  if [ -d "$LOCKDIR" ] && [ "$p" != "$OWNER_PID" ] && [ -n "$p" ]; then
    echo "test-lock: not releasing — the lock is held by pid $p, not by this caller ($OWNER_PID)." >&2
    return 1
  fi
  rm -rf "$LOCKDIR" 2>/dev/null || true
  return 0
}

status() {
  local rc=0 lbl stale=""
  if [ -d "$LOCKDIR" ]; then
    lbl="$(_holder_label)"; [ -n "$lbl" ] || lbl="?"
    _holder_alive || stale=" — HOLDER IS GONE (stale; the next acquire reclaims it)"
    printf 'lock   HELD by %s (pid %s), %ss old%s\n' \
      "$lbl" "$(_holder_pid)" "$(_holder_age)" "$stale"
    rc=1
  else
    printf 'lock   free (%s)\n' "$LOCKDIR"
  fi
  if _suite_live; then
    printf 'suite  RUNNING — pid(s) %s (pgrep -x tests)\n' "$(pgrep -x tests | tr '\n' ' ')"
    rc=1
  else
    printf 'suite  no `tests` process running\n'
  fi
  return "$rc"
}

# ---- dispatch ----
LABEL="${VISIONOCR_TEST_LOCK_LABEL:-$(basename "${0##*/}")-$$}"
WAIT="$WAIT_DEFAULT"
CMD="${1:-}"; shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --label) LABEL="${2:-}"; shift 2 ;;
    --wait)  WAIT="${2:-}";  shift 2 ;;
    --)      shift; break ;;
    *)       break ;;
  esac
done
case "$WAIT" in ''|*[!0-9]*) echo "test-lock: --wait must be a whole number of seconds" >&2; exit 2 ;; esac

case "$CMD" in
  status)  status; exit $? ;;
  release) release; exit $? ;;
  acquire) acquire "$LABEL" "$WAIT"; exit $? ;;
  run)
    [ $# -gt 0 ] || { echo "test-lock: 'run' needs a command after --" >&2; usage >&2; exit 2; }
    # REENTRANCY. A session's `git commit` fires .githooks/pre-commit, which runs the suite under this
    # lock. If that commit happens inside something that ALREADY holds the lock, a second acquire would
    # deadlock against itself for the whole --wait. The env var is only visible to children of the
    # holder, so it answers "am I inside my own critical section?" exactly, with no pid archaeology.
    if [ "${VISIONOCR_TEST_LOCK_HELD:-}" = 1 ]; then
      exec "$@"
    fi
    acquire "$LABEL" "$WAIT" || {
      echo "test-lock: could not get the suite lock within ${WAIT}s — NOT running '$1'." >&2
      echo "           Check who has it:  $0 status" >&2
      exit 4
    }
    # Release on ANY exit path, including a TERM from the daemon's watchdog: a lock leaked by a killed
    # gate would block every later suite until MAXAGE, which on this machine means the whole night.
    trap 'release >/dev/null 2>&1' EXIT
    trap 'exit 143' TERM
    trap 'exit 130' INT
    VISIONOCR_TEST_LOCK_HELD=1 "$@"
    exit $?
    ;;
  ''|-h|--help|help) usage; exit 0 ;;
  *) echo "test-lock: unknown command '$CMD'" >&2; usage >&2; exit 2 ;;
esac
