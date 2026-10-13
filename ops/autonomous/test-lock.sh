#!/usr/bin/env bash
# ops/autonomous/test-lock.sh — ONE test suite at a time per worktree (machine-wide until cs-narrow-lock).
#
# ONE ENTRY PER WORKTREE (concurrent-suites, cs-narrow-lock, 2026-10-13). Since cs-domains and cs-paths a suite's
# settings, reports and temporary files are its own, so what two suites still share is: their worktree's build/
# (the binaries run_tests.sh writes and runs), which only another suite in the SAME tree touches; and the binary
# cache, the stamps and the timing ledger in $STATE. So $LOCKDIR is now a directory of entries, one per
# worktree (`$LOCKDIR/wt-<sha of the tree's path>/` holding pid, label and tree), and a suite waits only for
# another suite in its own tree. The directory exists while any entry does, so callers that ask "is a suite in
# flight?" with `[ -d test.lock ]` (run-guarded.sh, bakeoff.sh, hybrid-run.sh) still get the right answer. The
# shared state is serialised where it is written: run_tests.sh takes an flock around a cache entry's write and
# prune, and note_timing below around the ledger append; stamps and cache reads are a temp-then-rename and need
# none. A lock with `pid` at its top level and no `format` file is an OLDER test-lock.sh's machine-wide hold:
# it excludes everyone, as it always did. The other way round, the top carries `format` and a mirror of one
# live entry's pid and label, so an older script waits rather than taking the entries for dead (see _mirror).
# One window is left: between a fresh directory's mkdir and its first mirror an older script reads no pid and
# removes the directory, as two older scripts could already do to each other. Rejected: per-tree lock
# directories beside test.lock (`test.lock.<key>`), which every `[ -d test.lock ]` caller would have missed.
# The rest of this header is the history of the machine-wide lock; its reasoning still holds within one tree.
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
# ISOLATED SUITES (concurrent-suites, cs-paths). A suite built since cs-paths has its own preferences domain,
# report directory and temporary directory, and says so with a marker file named by its pid in
# $VISIONOCR_SUITE_MARKS (default `$(getconf DARWIN_USER_TEMP_DIR)visionocr-isolated-suites`). Such a suite
# cannot collide with another, so the out-of-band check no longer counts it; a `tests` process with no marker,
# or with one older than the process (a recycled pid), is an older binary and still counts.
#
# USAGE
#   test-lock.sh run [--label L] [--wait S] -- <cmd> [args…]   acquire, run <cmd>, release (the main form)
#   test-lock.sh acquire [--label L] [--wait S]                 acquire and return (caller must release)
#   test-lock.sh release                                        release a lock this pid tree holds
#   test-lock.sh status                                         who holds it + whether a suite is live (read-only)
#   test-lock.sh holders                                        one line per holder: pid, label, age, entry (TABs)
#   test-lock.sh drop-under PID                                 drop holds whose holder is gone or under PID
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
# ✅ 2026-08-24: the suite is 236 s measured (ProcessType=Background plus a missing -O had cost 16.2x), so
# BOTH margins here are now ~15-20x rather than 2.3x. Deliberately not reduced — breaking a lock is still
# worse than waiting for one, and every figure in this comment predates the fix.
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

# THIS caller's entry: its worktree is the git top level of the current directory (every caller runs from its
# tree's root: the hook, the gate, `test-lock.sh run -- ./run_tests.sh`), or the directory itself outside git.
# VISIONOCR_TEST_LOCK_TREE names it explicitly (the harnesses).
_tree() {
  local t="${VISIONOCR_TEST_LOCK_TREE:-}"
  [ -n "$t" ] || { t="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$t" ]; } || t="$PWD"
  (cd "$t" 2>/dev/null && pwd -P) || printf '%s\n' "$t"
}
TREE="$(_tree)"
ENTRY="$LOCKDIR/wt-$(printf '%s' "$TREE" | shasum -a 256 | cut -c1-12)"
# THE TOP OF THE DIRECTORY, AND OLDER SCRIPTS. An older test-lock.sh takes the whole directory and writes pid
# and label at its top; that is a legacy hold, and it excludes every tree. An older script also READS that pid
# whenever its own mkdir fails, and with none there it took every entry for a dead holder's and removed the
# whole directory (adversarial review, verified 2026-10-13: a second suite then started in a tree whose first
# was still running). So a per-worktree lock carries `format` and a MIRROR at its top, the pid and label of one
# live entry (see _mirror), and an older script waits for it like any held lock.
_legacy() { { [ -f "$LOCKDIR/pid" ] || [ -f "$LOCKDIR/label" ]; } && [ ! -f "$LOCKDIR/format" ]; }
# What this caller contends for: its entry, or the whole directory while an older script holds it.
_held_dir() { if _legacy; then echo "$LOCKDIR"; else echo "$ENTRY"; fi; }

_pid_in()   { cat "$1/pid"   2>/dev/null; }
_label_in() { cat "$1/label" 2>/dev/null; }
_age_in() {
  local m; m="$(stat -f %m "$1" 2>/dev/null)"
  case "$m" in ''|*[!0-9]*) echo 0; return ;; esac
  echo $(( $(_now) - m ))
}
# A holder pid that no longer exists means the process died without releasing (a killed session, a
# watchdog TERM, a closed laptop lid). That is the common case on this machine, so it must resolve
# instantly rather than waiting out MAXAGE.
_alive_in() {
  local p; p="$(_pid_in "$1")"
  case "$p" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$p" 2>/dev/null
}
# _drop DIR — remove one hold: an entry, or an older script's pid and label (never the entries beside them).
# The directory itself goes only once it is empty: rmdir refuses a non-empty one, so a racing acquire that has
# just made its entry keeps it, and one whose `mkdir` lost the directory to this rmdir simply tries again.
_drop() {
  if [ "$1" = "$LOCKDIR" ]; then rm -f "$LOCKDIR/pid" "$LOCKDIR/label" 2>/dev/null
  else rm -rf "$1" 2>/dev/null; _mirror; fi
  rmdir "$LOCKDIR" 2>/dev/null
  return 0
}
# _mirror — keep the top's pid and label naming a LIVE entry, or remove them and `format` once no entry is left.
# `format` is written before the pid and removed after it, so a reader never sees a mirror as a legacy hold.
# A mirror that already names a live entry is left alone. An entry made but not yet written is not live; its
# own acquire mirrors itself once its pid is in.
_mirror() {
  local d p top any=0 live=""
  [ -d "$LOCKDIR" ] && ! _legacy || return 0
  top="$(_pid_in "$LOCKDIR")"
  for d in "$LOCKDIR"/wt-*; do
    [ -d "$d" ] || continue
    any=1; _alive_in "$d" || continue
    [ "$(_pid_in "$d")" = "$top" ] && return 0
    [ -n "$live" ] || live="$d"
  done
  if [ -n "$live" ]; then
    d="$live"; p="$(_pid_in "$d")"
    printf 'per-worktree 1\n' > "$LOCKDIR/format" 2>/dev/null
    printf '%s\n' "$p" > "$LOCKDIR/.pid.$$" 2>/dev/null && mv -f "$LOCKDIR/.pid.$$" "$LOCKDIR/pid" 2>/dev/null
    { _label_in "$d"; } > "$LOCKDIR/.label.$$" 2>/dev/null && mv -f "$LOCKDIR/.label.$$" "$LOCKDIR/label" 2>/dev/null
    return 0
  fi
  [ "$any" = 1 ] && return 0
  rm -f "$LOCKDIR/pid" "$LOCKDIR/label" 2>/dev/null; rm -f "$LOCKDIR/format" 2>/dev/null
  return 0
}
_holder_pid()   { _pid_in "$(_held_dir)"; }
_holder_label() { _label_in "$(_held_dir)"; }
_holder_age()   { _age_in "$(_held_dir)"; }
_holder_alive() { _alive_in "$(_held_dir)"; }

# _hold_dirs — the directory of every hold, one per line; an older script's hold comes first.
_hold_dirs() {
  local d
  _legacy && printf '%s\n' "$LOCKDIR"
  for d in "$LOCKDIR"/wt-*; do [ -d "$d" ] && printf '%s\n' "$d"; done
  return 0
}
# _holders — one line per hold: pid, label, age in seconds, directory, TAB-separated (`holders` prints it).
_holders() {
  local d
  _hold_dirs | while IFS= read -r d; do
    printf '%s\t%s\t%s\t%s\n' "$(_pid_in "$d")" "$(_label_in "$d")" "$(_age_in "$d")" "$d"
  done
}

SUITE_MARKS="${VISIONOCR_SUITE_MARKS:-$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)visionocr-isolated-suites}"

# _start_of PID — the process's start time in epoch seconds, or nothing.
_start_of() {
  # UTC on both sides: a local time in the autumn fall-back hour reads an hour early, which would let a
  # stale marker pass for a process that reused its pid.
  local s; s="$(TZ=UTC0 LC_ALL=C ps -p "$1" -o lstart= 2>/dev/null | sed 's/ *$//')"
  [ -n "$s" ] && TZ=UTC0 LC_ALL=C date -j -f '%a %b %d %T %Y' "$s" +%s 2>/dev/null
}

# _is_isolated PID — 0 if PID carries an isolation marker written no earlier than the process started. A
# marker left by a dead suite whose pid an older binary then reused predates that process, so it does not count.
_is_isolated() {
  local mt st
  [ -f "$SUITE_MARKS/$1" ] || return 1
  mt="$(stat -f %m "$SUITE_MARKS/$1" 2>/dev/null)"; st="$(_start_of "$1")"
  case "$mt" in ''|*[!0-9]*) return 1 ;; esac
  case "$st" in ''|*[!0-9]*) return 1 ;; esac
  [ "$mt" -ge "$st" ]
}

# Is a suite running that did NOT come through this lock and could collide with one? See the -x note and
# ISOLATED SUITES in the header. Probe children are skipped, as the report skips them; a set in which no
# member reads as parentless is busy, the safe side (see _suite_report). Isolated suites do not count.
_suite_live() {
  local pids p roots=0
  pids="$(pgrep -x tests 2>/dev/null | tr '\n' ' ')"
  [ -n "${pids// /}" ] || return 1
  for p in $pids; do
    _is_probe_child "$p" "$pids" && continue
    roots=$(( roots + 1 ))
    _is_isolated "$p" || return 0
  done
  [ "$roots" = 0 ]
}

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
  local iso="" niso
  for p in $roots; do _is_isolated "$p" && iso="${iso:+$iso }$p"; done
  niso="$(_count $iso)"
  if [ "$nroots" -gt 1 ] && [ "$niso" = "$nroots" ]; then
    # Every one has its own settings, reports and temporary files (ISOLATED SUITES in the header).
    msg="$nroots isolated suites at once ($(_pidlist $roots)), each with its own settings and files"
  elif [ "$nroots" -gt 1 ]; then
    # No "two" and no "BOTH": with three roots this line used to read "3 SUITES AT ONCE — two suites corrupt
    # BOTH runs", and "of it" below had no antecedent once there was more than one suite.
    msg="⚠️ $nroots SUITES AT ONCE ($(_pidlist $roots)) — concurrent suites corrupt ALL of them"
    [ "$niso" -gt 0 ] && msg="$msg (isolated: $(_pidlist $iso))"
  else
    msg="$nroots suite ($(_pidlist $roots))"
    [ "$niso" = 1 ] && msg="$msg, isolated"
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
  # The entry's mkdir can also fail because a releasing holder's rmdir took the directory between the two
  # mkdirs (see _drop); that is not a hold, so it is tried again at once.
  local tries=0 hd
  _mirror    # repair a mirror left naming a holder that died without releasing
  while ! _legacy && [ "$tries" -lt 5 ]; do
    mkdir "$LOCKDIR" 2>/dev/null
    if mkdir "$ENTRY" 2>/dev/null; then
      printf '%s\n' "$OWNER_PID" > "$ENTRY/pid"   2>/dev/null || true
      printf '%s\n' "$label" > "$ENTRY/label" 2>/dev/null || true
      _mirror
      printf '%s\n' "$TREE" > "$ENTRY/tree" 2>/dev/null || true
      # Re-check for an out-of-band suite AFTER taking the lock, then yield to it. Checking only before
      # would leave a window: a hand-run suite that starts between the check and the mkdir would run
      # alongside ours, which is the exact collision this file exists to prevent.
      if _suite_live; then
        _drop "$ENTRY"
        _TL_BUSY="out-of-band-suite"
        return 1
      fi
      return 0
    fi
    [ -d "$ENTRY" ] && break
    tries=$(( tries + 1 ))
  done
  # Held, by a suite in this tree or by an older script's machine-wide lock. Reclaim it only if the holder is
  # provably gone, or it has aged out.
  hd="$(_held_dir)"
  local age; age="$(_age_in "$hd")"
  if ! _alive_in "$hd"; then
    echo "test-lock: holder pid $(_pid_in "$hd") is gone (lock ${age}s old) — reclaiming." >&2
    _drop "$hd"
    _TL_BUSY="reclaimed-dead"
    return 1     # deliberately do NOT acquire on this pass: let the next loop iteration race for it
                 # fairly, so two reclaimers cannot both conclude they own it.
  fi
  if [ "$MAXAGE" -gt 0 ] && [ "$age" -ge "$MAXAGE" ]; then
    echo "test-lock: holder '$(_label_in "$hd")' (pid $(_pid_in "$hd")) has held the lock ${age}s (>= ${MAXAGE}s) — breaking it." >&2
    _drop "$hd"
    _TL_BUSY="reclaimed-aged"
    return 1
  fi
  # A live holder inside MAXAGE: the ordinary busy case. Capture its label and pid HERE, while the lock still
  # exists — reading them later is what invented a phantom three times.
  _TL_BUSY="held"; _TL_BUSY_LABEL="$(_label_in "$hd")"; _TL_BUSY_PID="$(_pid_in "$hd")"
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
  local hd p; hd="$(_held_dir)"; p="$(_pid_in "$hd")"
  [ -d "$hd" ] || { rmdir "$LOCKDIR" 2>/dev/null; return 0; }
  if [ "$p" != "$OWNER_PID" ] && [ -n "$p" ]; then
    echo "test-lock: not releasing — the lock is held by pid $p, not by this caller ($OWNER_PID)." >&2
    return 1
  fi
  _drop "$hd"
  return 0
}

# drop_under PID — drop every hold whose holder is gone or is PID or one of its descendants. For the daemon's
# park, which until cs-narrow-lock did `rm -rf test.lock`: with one entry per tree that would also take the
# entry of a suite still running in another tree (or the owner's), and a second suite could then start there.
drop_under() {
  local root="$1" d p up hops
  case "$root" in ''|*[!0-9]*) echo "test-lock: drop-under needs a pid" >&2; return 2 ;; esac
  _hold_dirs | while IFS= read -r d; do
    p="$(_pid_in "$d")"; up="$p"; hops=0
    if _alive_in "$d"; then
      # Bounded for the reason _is_probe_child is (one `ps` per hop; a recycled pid can close a loop).
      while [ -n "$up" ] && [ "$up" != "$root" ] && [ "$up" != 0 ] && [ "$up" != 1 ] && [ "$hops" -le 23 ]; do
        up="$(_ppid_of "$up")"; hops=$(( hops + 1 ))
      done
      [ "$up" = "$root" ] || continue
    fi
    _drop "$d"
  done
  return 0
}

status() {
  local rc=0 hl stale hd tr dirs
  dirs="$(_hold_dirs)"
  if [ -n "$dirs" ]; then
    while IFS= read -r hd; do
      hl="$(_label_in "$hd")"; [ -n "$hl" ] || hl="?"
      stale=""; _alive_in "$hd" || stale=" — HOLDER IS GONE (stale; the next acquire reclaims it)"
      tr="$(cat "$hd/tree" 2>/dev/null)"
      if [ "$hd" = "$LOCKDIR" ]; then tr=" [machine-wide: an older test-lock.sh]"; else tr="${tr:+ [$tr]}"; fi
      printf 'lock   HELD by %s (pid %s), %ss old%s%s\n' "$hl" "$(_pid_in "$hd")" "$(_age_in "$hd")" "$stale" "$tr"
    done <<EOF
$dirs
EOF
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
    # The 1-minute load average AT THE END of the run. Without it two rows are not comparable — the same
    # suite has been timed at 80 s and at 2370 s on this machine, and load is most of the difference.
    load="$(uptime 2>/dev/null | sed -n 's/.*load averages*: *\([0-9.]*\).*/\1/p')"
    # Suites in two trees can now finish together: the header test and the append are one step under an
    # flock, so an empty ledger gets one header. A lock not had in 10 s appends anyway (instrumentation).
    _flock "$led.lock" 10
    [ -s "$led" ] || printf 'when\tlabel\tseconds\trc\tloadavg1\n' >> "$led"
    printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%F %T')" "$lbl" "$secs" "$rc" "${load:-?}" >> "$led"
    _funlock
  } 2>/dev/null || true
  return 0
}

# _flock FILE SECS — an exclusive flock(2) on FILE through fd 9, held by this shell until _funlock or its exit
# (the kernel releases it if the process dies, so it cannot go stale). perl takes it on the shared open file
# and exits; the lock belongs to the open file, which this shell keeps. Non-zero if not had within SECS.
_flock() {
  exec 9>>"$1" || return 1
  perl -MFcntl=:flock -e 'alarm shift; open(my $f, ">&=", 9) or exit 2; flock($f, LOCK_EX) or exit 1' "$2"
}
_funlock() { exec 9>&-; }

# THE MACHINE LOCK is not taken here. run_tests.sh takes mac-heavy-lock.sh itself around ./build/tests alone
# (EFFICIENCY-PLAN round 2), so Archive Suite does not wait on this suite's compiles; test.lock still covers the
# whole script. Until 2026-10-07 `run` wrapped its entire command in the heavy lock, compile included. `run` hands
# the suite its lock directory (touched while the suite waits for the heavy lock, so MAXAGE does not break a
# suite lock whose holder is only queued) and its label, and a file in which the suite says how it went.
# ⚠️ `run` is for ./run_tests.sh. Anything else wrapped in it gets test.lock and NOT the heavy lock.
_suite_env() { export VISIONOCR_TEST_LOCK_DIR="$(_held_dir)" VISIONOCR_SUITE_LABEL="${LABEL:-suite}"; }

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
  holders) _holders; exit 0 ;;
  drop-under) drop_under "${1:-}"; exit $? ;;
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
      _suite_env; exec "$@"
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
    # 37m43s at 20:31 with a daemon session and an interactive session both live. (2026-08-24: that gap was
    # the scheduling band, not load — see the plist's ProcessType comment. Now 236 s.) This is a personal machine
    # under wildly varying load, and it thermally throttles — so any constant derived from one timing is a
    # guess wearing a number's clothes. The project has been doing exactly that: "3-6 min" was never
    # measured at all (939680e says so in its own message: "DURATIONS ARE NOT MEASURED … inherited, not
    # established"), and replacing it with one measurement of mine would only move the guess.
    #
    # So: every suite that goes through this lock records what it actually cost, and the timeouts get
    # re-derived from the DISTRIBUTION rather than from prose. This is the one place that sees them all —
    # the health gate, `.githooks/pre-commit`, and every session — which is why it lives here and not in
    # any one caller. Append-only, one line per run, and a failure to write it must never fail the suite.
    # The suite writes compiled / cache-hit / stamp-skip into VISIONOCR_SUITE_NOTE, and the row's label carries
    # it, so a two-second stamp skip is not read as a suite.
    _tl_t0="$(date +%s)"
    _tl_note="$(mktemp -t vo-suite-note 2>/dev/null || true)"
    trap 'release >/dev/null 2>&1; [ -n "$_tl_note" ] && rm -f "$_tl_note"' EXIT
    _suite_env
    VISIONOCR_TEST_LOCK_HELD=1 VISIONOCR_SUITE_NOTE="$_tl_note" "$@"
    _tl_rc=$?
    _tl_kind="$(head -1 "$_tl_note" 2>/dev/null)"
    note_timing "$LABEL${_tl_kind:+ [$_tl_kind]}" "$(( $(date +%s) - _tl_t0 ))" "$_tl_rc"
    exit "$_tl_rc"
    ;;
  ''|-h|--help|help) usage; exit 0 ;;
  *) echo "test-lock: unknown command '$CMD'" >&2; usage >&2; exit 2 ;;
esac
