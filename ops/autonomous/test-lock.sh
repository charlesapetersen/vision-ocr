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
#   test-lock.sh record --label L --seconds N [--rc R]          append one row to the suite-timing ledger
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
# ⚠️ THE WAIT MUST EXCEED ONE SUITE ON A BUSY MACHINE, OR IT REFUSES HEALTHY WORK. This was 1800 (30 min)
# and read "a suite is 3-6 min", a figure nobody had ever timed. Timed on 2026-08-16 the same suite took
# 416-632 s on a quiet machine and ~37-40 min with a daemon session and an interactive session alongside it,
# and ~45 min per run overnight on 2026-08-17 — so 1800 was comfortably shorter than a loaded run, and
# anything queued behind a healthy suite gave up. (That range read 80-632 s until 2026-08-17: its floor was
# an `exit 133` crash rather than a fast suite, so the wait budget here was partly sized off a suite that
# died. BUGS.md C24b.)
# `.githooks/pre-commit` then reported that the lock "never freed", naming a wedge over a suite that still
# had minutes to go. 3600 covers the worst run observed so far with headroom. Re-derive it from
# $STATE/suite-timings.tsv (worst row you are willing to survive, plus headroom) rather than from this
# comment — the ledger is the authority. 0 means "fail immediately if busy".
WAIT_DEFAULT="${VISIONOCR_TEST_LOCK_WAIT:-3600}"
# A holder whose pid is gone is stale immediately (see _holder_alive). This is the backstop for the other
# case: a live pid that has wandered off (a wedged suite). 90 min was chosen as "well past the 3-6 min
# suite"; against a 39m30s suite it is only 2.3x, and the gate that wraps one measured 44m53s — so this is
# now the tightest of the three margins, not the loosest. Kept at 5400 because breaking a lock is worse
# than waiting for one, but it must be re-derived, not inherited, if the suite grows again.
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
# A probe child (below) is only ever forked BY a suite, so as a boolean this stays exactly right and is
# deliberately left as the cheap one-process question. Only the REPORT needs to tell the two apart.
_suite_live() { pgrep -x tests >/dev/null 2>&1; }

# ---- reporting the `tests` set: one suite, or two, or one and its own probe children ----------------------
# `pgrep -x tests` matches the suite's OWN CHILDREN. Tests/main.swift re-executes build/tests with
# --probe-hostile-page, --probe-hostile-numbers and --probe-deep-outline, and a child of `tests` is also
# named `tests`, so a healthy single suite shows up as two or three pids. `status` printed that list raw
# (`suite RUNNING — pid(s) 1536 98565`), and TWO PIDS IS THE READING CLAUDE.md TELLS A SESSION TO TREAT AS
# CORRUPTION. It cost a session the time to rule that out every time the probes happened to be up — and the
# worse half is that it teaches the reader to discount a two-pid reading, which is the one reading that would
# matter if two suites ever really did run. So the fix must make the genuine two-suite case LOUDER, not
# quieter; `status`'s two-suite line says so in capitals and prove-test-lock.sh [12] asserts it.
_ppid_of() { ps -p "$1" -o ppid= 2>/dev/null | tr -d ' '; }

# _is_probe_child PID SET — 0 if some ANCESTOR of PID is itself in SET.
#
# Ancestry within the set, NOT `ps -o comm=`: comm and `pgrep -x` do not agree about a process renamed with
# `exec -a` (which is how the harness makes a process genuinely named `tests` — a *copy* of an Apple platform
# binary is SIGKILLed at exec on Apple Silicon), and the question has to be answered about the same set pgrep
# produced. Walking to the grandparent and beyond matters too: a probe that forks its own helper is still not
# a suite.
#
# ⚠️ A pid whose ancestry cannot be READ counts as a SUITE, not as a child — `ps` returns nothing for a
# process that exited between the pgrep and the ps. Over-reporting a suite makes a caller wait; under-
# reporting one runs two suites at once, which is the thing this whole file exists to prevent. So the
# unresolvable case falls on the safe side, and that is check, not comment (prove-test-lock.sh [12]).
#
# ⚠️ THE ANCHORING SPACES IN THE MEMBERSHIP TEST ARE THE WHOLE OF THE EXACT-MATCH. Without both of them
# `*"$up"*` is a SUBSTRING test, and a low-pid ancestor that happens to be a decimal substring of a set
# member turns a genuine second suite into a probe child of the first — the exact reading this code exists to
# make louder, switched off. Measured 2026-08-19 with an interposed `ps`: set {45678, 999}, 45678's ancestor
# 456, unanchored -> `1 suite (pid 999), plus 1 probe child of it (pid 45678)`. Found by an adversarial review
# because the anchoring was pinned by NOTHING; it is [12b] now.
#
# ⚠️ THE HOP BOUND IS LOAD-BEARING, and this comment said the opposite. It read "a process tree cannot
# contain a cycle, so 24 is unreachable rather than tuned" — true of one instant, FALSE of this walk, which
# samples one `ps` per hop. A pid recycled between two hops can close a loop: measured 2026-08-19 with an
# interposed `ps` reporting 500->600->700->600, the bound-less copy of this file was still spinning after 6 s
# and had to be killed, and `status` is what `daemon.sh` prints before the daemon starts. A1.3's idiom for a
# bounded walk over data you do not own, and it is a check now rather than an assurance.
#
# Stopping at ppid 0 and 1 is an EARLY EXIT, not a guard: neither is ever a `tests` pid, so the membership
# test cannot match them and the walk would terminate one hop later anyway (`ps -p 0` prints nothing here).
# It saves one `ps` per pid. Said plainly because a mutant dropping either conjunct is behaviour-identical and
# correctly survives — calling them guards would make that survivor look like a gap in the checks.
_is_probe_child() {
  local set=" $2 " up hops=0
  up="$(_ppid_of "$1")"
  while [ -n "$up" ] && [ "$up" != 0 ] && [ "$up" != 1 ] && [ "$hops" -lt 24 ]; do
    case "$set" in *" $up "*) return 0 ;; esac
    up="$(_ppid_of "$up")"
    hops=$(( hops + 1 ))
  done
  return 1
}

_count()   { echo $#; }
_pidlist() { case $# in 1) printf 'pid %s' "$1" ;; *) printf 'pids %s' "$*" ;; esac; }

# _suite_report — echo the human sentence for a NON-EMPTY `tests` set. Every pid pgrep returned appears in
# it: a classifier may relabel a pid, it may never drop one (invariant 1, in an instrument).
_suite_report() {
  local pids="$1" p roots="" kids="" nroots nkids msg
  for p in $pids; do
    if _is_probe_child "$p" "$pids"; then kids="${kids:+$kids }$p"; else roots="${roots:+$roots }$p"; fi
  done
  nroots="$(_count $roots)"; nkids="$(_count $kids)"
  # ⚠️ nroots CAN be 0, and this said it could not. The proof it carried — a finite acyclic ancestry has a
  # member with no ancestor inside it — is true of one instant and false of a walk that samples one `ps` per
  # hop: a pid recycled between hops can make every member look like somebody's descendant. Verified reachable
  # 2026-08-19 with an interposed `ps` reporting 100<->200, where the previous code printed
  # `0 suite (pids ), plus 2 probe children of it (pids 100 200)` — no alarm, over two live `tests` processes.
  # So it is a branch with a check on it rather than a proof in a comment (CONTRIBUTING 4c cuts both ways:
  # an unreachable else is worse than none, and a REACHABLE one written off as unreachable is worse still).
  if [ "$nroots" = 0 ]; then
    printf '⚠️ %s tests process(es), NONE of them parentless — inconsistent ps reading, treat as BUSY (%s)' \
      "$(_count $pids)" "$(_pidlist $pids)"
    return 0
  fi
  if [ "$nroots" -gt 1 ]; then
    # No "two" and no "BOTH": with three roots this line used to read "3 SUITES AT ONCE — two suites corrupt
    # BOTH runs", and "of it" below had no antecedent once there was more than one suite.
    msg="⚠️ $nroots SUITES AT ONCE ($(_pidlist $roots)) — concurrent suites corrupt ALL of them"
  else
    msg="$nroots suite ($(_pidlist $roots))"
  fi
  if [ "$nkids" = 1 ]; then
    msg="$msg, plus 1 probe child ($(_pidlist $kids))"
  elif [ "$nkids" -gt 1 ]; then
    msg="$msg, plus $nkids probe children ($(_pidlist $kids))"
  fi
  printf '%s' "$msg"
}

# WHY the last _try_acquire said busy. THE PHANTOM HOLDER, THE DEAD-HOLDER MISLABEL AND THE RECLAIM THAT
# NEVER HAPPENED WERE ALL ONE DEFECT: `acquire` re-DERIVED the reason from the lock directory *after*
# `_try_acquire` had already changed or deleted it. Three fixes in a row patched the derivation and each left
# a case (`'' holds the suite lock (pid )` -> "from a dead holder" over a live holder -> "just reclaimed (see
# the line above)" with nothing above it and nothing reclaimed, found 2026-08-19 by an adversarial review with
# an interposed `pgrep` that flips). So the reason is now RECORDED BY THE FUNCTION THAT KNOWS IT and read, not
# reconstructed. It carries no behaviour: _try_acquire's return values are unchanged and nothing branches on
# this except the message.
#
# THREE variables, not one packed string: labels legitimately contain spaces (`pre-commit 999` is one this
# repo writes), so any `cut -d' '` on a packed form is a field-splitting defect waiting for the first
# multi-word label.
_TL_BUSY=""; _TL_BUSY_LABEL=""; _TL_BUSY_PID=""
# Try once. 0 = acquired. 1 = busy.
_try_acquire() {
  local label="$1"
  _TL_BUSY=""; _TL_BUSY_LABEL=""; _TL_BUSY_PID=""
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
      _TL_BUSY="out-of-band-suite"
      return 1
    fi
    return 0
  fi
  # Held. Reclaim it only if the holder is provably gone, or it has aged out.
  local age; age="$(_holder_age)"
  if ! _holder_alive; then
    echo "test-lock: holder pid $(_holder_pid) is gone (lock ${age}s old) — reclaiming." >&2
    rm -rf "$LOCKDIR" 2>/dev/null || true
    _TL_BUSY="reclaimed-dead"
    return 1     # deliberately do NOT acquire on this pass: let the next loop iteration race for it
                 # fairly, so two reclaimers cannot both conclude they own it.
  fi
  if [ "$MAXAGE" -gt 0 ] && [ "$age" -ge "$MAXAGE" ]; then
    echo "test-lock: holder '$(_holder_label)' (pid $(_holder_pid)) has held the lock ${age}s (>= ${MAXAGE}s) — breaking it." >&2
    rm -rf "$LOCKDIR" 2>/dev/null || true
    _TL_BUSY="reclaimed-aged"
    return 1
  fi
  # A live holder inside MAXAGE: the ordinary busy case. Capture its label and pid HERE, while the lock still
  # exists — reading them later is what invented a phantom three times.
  _TL_BUSY="held"; _TL_BUSY_LABEL="$(_holder_label)"; _TL_BUSY_PID="$(_holder_pid)"
  return 1
}

acquire() {
  local label="$1" wait_s="$2" waited=0 _why="" _lbl="" _hpid=""
  mkdir -p "$(dirname "$LOCKDIR")" 2>/dev/null || true
  while :; do
    _try_acquire "$label" && return 0
    [ "$wait_s" -le 0 ] && return 4
    [ "$waited" -ge "$wait_s" ] && return 4
    # 5s granularity: a suite runs for minutes, so polling faster buys nothing and a launchd daemon
    # should not spin. Announce once, not every poll, or the daemon log fills with waiting notices.
    #
    # ⚠️ READ THE REASON, DO NOT RE-DERIVE IT. This block used to re-read the lock directory here, after
    # `_try_acquire` had already deleted or broken it, and it was wrong three times running: `_holder_label` /
    # `_holder_pid` read empty after a reclaim and it printed `test-lock: '' holds the suite lock (pid )` into
    # the daemon log immediately under the line explaining the reclaim (observed 2026-08-16 in
    # /tmp/vo-commit.log; it cost real time, read as a second unknown holder). The fix for that said "from a
    # dead holder" after an aged-out break-in of a LIVE holder. The fix for THAT said "just reclaimed (see the
    # line above)" on the yield-to-an-out-of-band-suite path, where nothing was reclaimed and there is no line
    # above — verified 2026-08-19 with an interposed `pgrep` that reports a suite once and then none. Every one
    # of the three was the same mistake: reconstructing a fact from state that had moved. `$_TL_BUSY` is set by
    # the branch that knows, so there is nothing left to reconstruct.
    [ "$waited" = 0 ] && {
      _why="$_TL_BUSY"
      case "$_why" in
        out-of-band-suite)
          echo "test-lock: a suite is already running (pgrep -x tests) — waiting up to ${wait_s}s…" >&2 ;;
        held)
          _lbl="$_TL_BUSY_LABEL"; _hpid="$_TL_BUSY_PID"
          echo "test-lock: '${_lbl:-?}' holds the suite lock (pid ${_hpid:-?}) — waiting up to ${wait_s}s…" >&2 ;;
        reclaimed-dead)
          echo "test-lock: the lock was just reclaimed from a holder whose pid is gone — racing for it, up to ${wait_s}s…" >&2 ;;
        reclaimed-aged)
          echo "test-lock: the lock was just broken after ageing out (see the line above) — racing for it, up to ${wait_s}s…" >&2 ;;
        *)
          # Not a fallback for a case above — it is the honest answer when `_try_acquire` returned busy without
          # recording why, which would mean a path was added and this case was not. Says so rather than
          # guessing, and it is a check.
          echo "test-lock: the suite lock is busy for an unrecorded reason — waiting up to ${wait_s}s…" >&2 ;;
      esac
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
  # ONE pgrep, and the report is derived from its output rather than from a second call: asking twice can
  # give two different answers about the same machine, and for a mutex a report that disagrees with itself is
  # exactly how two callers each conclude the suite is free.
  # (No trailing-space trim: `_pidlist` joins with `"$*"`, and the membership test needs a space on BOTH sides
  # of a candidate, so a trailing one changes nothing. It was defensive code that asserted nothing — a mutant
  # deleting it was correctly indistinguishable from a pass — so it is gone rather than commented.)
  local pids
  pids="$(pgrep -x tests 2>/dev/null | tr '\n' ' ')"
  if [ -n "$pids" ]; then
    printf 'suite  RUNNING — %s (pgrep -x tests)\n' "$(_suite_report "$pids")"
    rc=1
  else
    printf 'suite  no `tests` process running\n'
  fi
  return "$rc"
}

# note_timing LABEL SECONDS [RC] — append one row to the suite-timing ledger. THE ONLY place that knows the
# format, because there are two kinds of caller and they must produce the same rows: `run` (the health gate
# and every session) times the command itself, while `.githooks/pre-commit` holds the lock with
# acquire/trap-release so its "waiting for the suite" notice reaches the terminal instead of a log file —
# and so has to hand its own timing in. The hook is the MOST FREQUENT suite runner of the three, so a ledger
# that silently skipped it would under-report exactly the runs the owner most wants to see.
#
# A failure to write must NEVER fail a suite or a commit: this is instrumentation, not a gate.
note_timing() {
  local lbl="${1:-?}" secs="${2:-}" rc="${3:-0}" led load
  case "$secs" in ''|*[!0-9]*) return 0 ;; esac
  led="${VISIONOCR_SUITE_TIMINGS:-${VISIONOCR_STATE:-$HOME/.local/state/visionocr-autonomous}/suite-timings.tsv}"
  {
    mkdir -p "$(dirname "$led")" 2>/dev/null || true
    [ -s "$led" ] || printf 'when\tlabel\tseconds\trc\tloadavg1\n' >> "$led"
    # The 1-minute load average AT THE END of the run. Without it two rows are not comparable — the same
    # suite has been timed at 80 s and at 2370 s on this machine, and load is most of the difference.
    load="$(uptime 2>/dev/null | sed -n 's/.*load averages*: *\([0-9.]*\).*/\1/p')"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$lbl" "$secs" "$rc" "${load:-?}" >> "$led"
  } 2>/dev/null || true
  return 0
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
  record)
    # Positional-free on purpose: the caller is a hook writing a machine-read row, and a transposed
    # seconds/rc pair would corrupt the ledger silently.
    # ⚠️ $LABEL is ALREADY SET by the global option parser above, which consumes `--label` before any
    # subcommand sees it. Defaulting to "" here instead wrote every hook row as `?` — caught by running it.
    _rl="$LABEL"; _rs=""; _rr=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --label)   _rl="${2:-}"; shift 2 ;;
        --seconds) _rs="${2:-}"; shift 2 ;;
        --rc)      _rr="${2:-0}"; shift 2 ;;
        *) shift ;;
      esac
    done
    note_timing "${_rl:-?}" "$_rs" "$_rr"; exit 0 ;;
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
    # ⚠️ TIME EVERY RUN, because a single wall-clock sample of this suite is not a fact about the suite.
    # Measured on one laptop on 2026-08-16: the same suite took 416-632 s in the morning's mutation runs and
    # 37m43s at 20:31 with a daemon session and an interactive session both live. This is a personal machine
    # under wildly varying load, and it thermally throttles — so any constant derived from one timing is a
    # guess wearing a number's clothes. The project has been doing exactly that: "3-6 min" was never
    # measured at all (939680e says so in its own message: "DURATIONS ARE NOT MEASURED … inherited, not
    # established"), and replacing it with one measurement of mine would only move the guess.
    #
    # So: every suite that goes through this lock records what it actually cost, and the timeouts get
    # re-derived from the DISTRIBUTION rather than from prose. This is the one place that sees them all —
    # the health gate, `.githooks/pre-commit`, and every session — which is why it lives here and not in
    # any one caller. Append-only, one line per run, and a failure to write it must never fail the suite.
    _tl_t0="$(date +%s)"
    VISIONOCR_TEST_LOCK_HELD=1 "$@"
    _tl_rc=$?
    note_timing "$LABEL" "$(( $(date +%s) - _tl_t0 ))" "$_tl_rc"
    exit "$_tl_rc"
    ;;
  ''|-h|--help|help) usage; exit 0 ;;
  *) echo "test-lock: unknown command '$CMD'" >&2; usage >&2; exit 2 ;;
esac
