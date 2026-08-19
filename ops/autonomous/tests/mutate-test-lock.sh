#!/usr/bin/env bash
# mutate-test-lock.sh — put each of test-lock.sh's guards back as a defect, on a COPY, and prove
# prove-test-lock.sh objects.
#
# WHY IT IS COMMITTED RATHER THAN RUN ONCE AND DESCRIBED. `Tools/mutate.py` covers `Sources/`; nothing covered
# the shell, and `ops/autonomous/test-lock.sh` is the one file standing between an unattended daemon and the
# failure CLAUDE.md names first. The 2026-08-19 `lock-report` commit was reviewed adversarially and SEVEN of the
# reviewer's twelve mutants survived a harness the author had already run nine of his own against — including
# one that turned `⚠️ 2 SUITES AT ONCE` into `1 suite plus a probe child`. A campaign described in a commit
# message cannot be re-run against the next change; this can. `Tools/mutation-log.tsv` and
# `SELFTEST-MUTANTS-2026-08-17.tsv` are the precedent for keeping the artefact.
#
# ⚠️ IT RUNS NO SUITE AND NO BUILD. Every run is `prove-test-lock.sh` against a copy: fully sandboxed, ~60 s
# each, so the whole catalogue is ~18 minutes rather than the ~45 min PER MUTANT that `Tools/mutate.py` costs.
# ⚠️ That still exceeds a 10-minute command ceiling, so a full pass may need chunking with `--only`; the
# 2026-08-19 artefact was assembled that way, and each row is a real harness run either way.
#
# USAGE
#   ops/autonomous/tests/mutate-test-lock.sh [--only SUBSTRING] [--out TSV]
# EXIT: 0 every mutant killed · 1 a mutant SURVIVED (or the pristine control failed) · 2 a mutation NOT-APPLIED
#
# READING THE RESULT. `killed` is what you want; a SURVIVOR is either a check that cannot fail or a value
# nothing depends on, and `BUGS.md` T5 records how to tell those apart. `NOT-APPLIED` means the edit did not
# match — the mutant tested nothing and must be re-expressed, NOT counted either way. Two of this file's
# entries needed re-expressing before they bit; one exposed a check that could not fail, and one SURVIVED and
# was right to (it changed behaviour without expressing the defect) — see the note above that mutant.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../test-lock.sh"
HARNESS="$HERE/prove-test-lock.sh"
ONLY=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --out)  OUT="${2:-}";  shift 2 ;;
    -h|--help) sed -n '/^# USAGE/,/^# READING/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "mutate-test-lock: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
[ -f "$SRC" ]     || { echo "no test-lock.sh at $SRC" >&2; exit 2; }
[ -f "$HARNESS" ] || { echo "no harness at $HARNESS" >&2; exit 2; }
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT INT TERM HUP

# ⚠️ THE TSV IS BUILT IN SCRATCH AND MOVED INTO PLACE AT THE END. Two of these launched onto one `--out`
# interleave their rows, and the result looks like one campaign that measured something — which is the shape
# `BUGS.md` C26 gave its corpus driver a `flock` for. Measured 2026-08-19 while writing this file: two copies
# ran for fifteen minutes against the same path before anyone noticed, because the log simply stopped growing.
# Staging plus one `mv` is CLAUDE.md invariant 2 at instrument scale — build into scratch, publish on success —
# and it makes the last writer win cleanly instead of producing a blend of two runs.
KILLED=0; SURVIVED=0; NOTAPPLIED=0
STAGE="$D/out.tsv"
row() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }
[ -n "$OUT" ] && row mutant verdict failing_checks summary > "$STAGE"

# mutant NAME MARKER SED_EXPR…
#   NAME    the catalogue name, also what --only matches
#   MARKER  the NOT-APPLIED detector, and the whole reason this runs rather than reasons: a mutation that
#           silently fails to match looks exactly like a mutant with nothing to say. Two forms —
#             "TEXT"   TEXT must have DISAPPEARED from the file (a replacement or a deletion)
#             "+TEXT"  TEXT must have APPEARED in the file (an INSERTION removes nothing, so the absence form
#                      cannot express one; the first version of this file had no `+` and reported an applied
#                      insertion mutant as NOT-APPLIED, measured 2026-08-19)
#           ⚠️ PICK A MARKER THAT ONLY THE CODE CONTAINS. `no-two-suite-alarm` used `SUITES AT ONCE`, which
#           also appears in the COMMENT above the line it edits, so the detector matched the comment and
#           reported the mutation as not applied while it had applied perfectly. One string, two meanings —
#           and the failure direction is the dangerous one, because NOT-APPLIED reads as "nothing to see".
#           A single line, never multi-line: `grep -qF` treats an embedded newline as two alternatives, so a
#           two-line marker matches if EITHER line survives, which is not the question being asked.
mutant() {
  local name="$1" marker="$2"; shift 2
  [ -n "$ONLY" ] && case "$name" in *"$ONLY"*) ;; *) return 0 ;; esac
  local f="$D/$name.sh"; cp "$SRC" "$f"
  # ⛔ AN AMBIGUOUS ABSENCE MARKER IS A CONFIGURATION ERROR, REFUSED HERE. It bit TWICE in this one file, and
  # the second time only because the first was fixed as an instance rather than swept as a pattern
  # (CONTRIBUTING 4b, inside the campaign tool): `no-two-suite-alarm` and `probe-children-not-printed` both
  # used strings that ALSO appear in test-lock.sh's comments, so the detector matched the comment and reported
  # NOT-APPLIED over a mutation that had applied perfectly — and NOT-APPLIED reads as "nothing to see", which
  # is the wrong direction to fail in. Counting occurrences in the PRISTINE file turns the trap into a gate.
  case "$marker" in
    +*) ;;
    *)  local n; n="$(grep -cF -- "$marker" "$SRC")"
        if [ "${n:-0}" != 1 ]; then
          printf '%-32s ⛔ BAD MARKER — %s occurrence(s) in the pristine file; it must match exactly one\n' \
            "$name" "${n:-0}"
          [ -n "$OUT" ] && row "$name" BAD-MARKER - "marker occurs ${n:-0} times, not once" >> "$STAGE"
          NOTAPPLIED=$(( NOTAPPLIED + 1 )); return 0
        fi ;;
  esac
  local e; for e in "$@"; do perl -0pi -e "$e" "$f"; done
  local applied=1
  case "$marker" in
    +*) grep -qF -- "${marker#+}" "$f" || applied=0 ;;
    *)  grep -qF -- "$marker"     "$f" && applied=0 ;;
  esac
  if [ "$applied" = 0 ]; then
    printf '%-32s NOT-APPLIED  (the edit did not match; re-express it)\n' "$name"
    [ -n "$OUT" ] && row "$name" NOT-APPLIED - "the edit did not match" >> "$STAGE"
    NOTAPPLIED=$(( NOTAPPLIED + 1 )); return 0
  fi
  local out; out="$(bash "$HARNESS" "$f" 2>&1)"
  local nf; nf="$(printf '%s\n' "$out" | grep -c 'FAIL')"
  local first; first="$(printf '%s\n' "$out" | grep 'FAIL' | head -1 | sed 's/^ *//; s/\x1b\[[0-9;]*m//g')"
  if [ "$nf" -gt 0 ]; then
    printf '%-32s killed by %2s check(s)\n' "$name" "$nf"
    [ -n "$OUT" ] && row "$name" killed "$nf" "${first:-?}" >> "$STAGE"
    KILLED=$(( KILLED + 1 ))
  else
    printf '%-32s ⚠️ SURVIVED — a check that cannot fail, or a value nothing depends on (BUGS.md T5)\n' "$name"
    [ -n "$OUT" ] && row "$name" SURVIVED 0 "-" >> "$STAGE"
    SURVIVED=$(( SURVIVED + 1 ))
  fi
}

# ---- the pristine control. A campaign whose control is red is measuring the harness, not the mutants. -------
if [ -z "$ONLY" ]; then
  cp "$SRC" "$D/pristine.sh"
  pout="$(bash "$HARNESS" "$D/pristine.sh" 2>&1)"
  pline="$(printf '%s\n' "$pout" | grep '=====' | tail -1 | sed 's/=//g; s/^ *//; s/ *$//')"
  if printf '%s\n' "$pout" | grep -q 'FAIL'; then
    echo "PRISTINE CONTROL FAILED — $pline"; printf '%s\n' "$pout" | grep 'FAIL' | head -5
    [ -n "$OUT" ] && row pristine CONTROL-FAILED - "$pline" >> "$STAGE"
    exit 1
  fi
  printf '%-32s control OK — %s\n' pristine "$pline"
  [ -n "$OUT" ] && row pristine control-ok 0 "$pline" >> "$STAGE"
fi

# ---- the classifier -----------------------------------------------------------------------------------------
# The anchoring spaces are the whole of the exact-match. Unanchored, a low-pid ancestor that is a decimal
# SUBSTRING of a set member silences a genuine second suite. Killed only by [12b](i), which needs the `ps` stub.
mutant membership-unanchored 'case "$set" in *" $up "*) return 0 ;; esac' \
  's/case "\$set" in \*" \$up "\*\) return 0 ;; esac/case "$set" in *"$up"*) return 0 ;; esac/'
# Leading space only: the half-fix, which is still a substring test at the tail.
mutant membership-half-anchored 'case "$set" in *" $up "*) return 0 ;; esac' \
  's/case "\$set" in \*" \$up "\*\) return 0 ;; esac/case "$set" in *" $up"*) return 0 ;; esac/'
# The walk must reach past the direct parent. Killed only by the GAPPED set in [12]; a contiguous chain is
# classified correctly by a one-hop implementation and this survived the first version of that check.
mutant walk-one-hop-only '[ "$hops" -lt 24 ]' 's/\[ "\$hops" -lt 24 \]/[ "$hops" -lt 1 ]/'
# The bound itself: without it a recycled pid closing a loop hangs `status`, which daemon.sh prints at startup.
mutant walk-unbounded '[ "$hops" -lt 24 ]' 's/ && \[ "\$hops" -lt 24 \]//'
# An unresolvable ancestry must fall on the SAFE side (a suite), not the convenient one (a child).
mutant unresolvable-is-a-child '+[ -z "$up" ] && return 0' 's/(up="\$\(_ppid_of "\$1"\)"\n)/$1  [ -z "\$up" ] \&\& return 0\n/'
mutant roots-and-kids-swapped 'then kids=' \
  's/then kids="\$\{kids:\+\$kids \}\$p"; else roots="\$\{roots:\+\$roots \}\$p"; fi/then roots="\${roots:+\$roots }\$p"; else kids="\${kids:+\$kids }\$p"; fi/'

# ---- the report ---------------------------------------------------------------------------------------------
mutant no-two-suite-alarm 'msg="⚠️ $nroots SUITES AT ONCE' \
  's/    msg="⚠️ \$nroots SUITES AT ONCE \(\$\(_pidlist \$roots\)\) — concurrent suites corrupt ALL of them"/    msg="\$nroots suite (\$(_pidlist \$roots))"/'
mutant nroots-counted-as-one-word 'nroots="$(_count $roots)"' \
  's/nroots="\$\(_count \$roots\)"/nroots="\$(_count "\$roots")"/'
# A classifier may relabel a pid; it may never drop one (invariant 1, in an instrument).
mutant probe-children-not-printed 'msg="$msg, plus 1 probe child' \
  's/  if \[ "\$nkids" = 1 \]; then\n[^\n]*\n  elif \[ "\$nkids" -gt 1 \]; then\n[^\n]*\n  fi\n//s'
mutant pidlist-always-plural "1) printf 'pid %s'" \
  "s/1\\) printf 'pid %s' \"\\\$1\" ;;/1) printf 'pids %s' \"\\\$1\" ;;/"
# nroots=0 over a non-empty set is REACHABLE (one `ps` per hop, a recycled pid). Printing `0 suite (pids )`
# with no alarm over two live `tests` processes is the failure this branch exists to prevent.
mutant nroots-zero-unhandled 'inconsistent ps reading' \
  's/  if \[ "\$nroots" = 0 \]; then\n[^\n]*\n[^\n]*\n    return 0\n  fi\n//s'
# One pgrep: two calls can disagree, and the report would then be built from a set that no longer exists.
# ⚠️ THE ORDER IS THE DEFECT, NOT THE CONDITION. The first form of this mutant only swapped
# `[ -n "$pids" ]` for `_suite_live`, leaving the `pgrep` read FIRST — behaviourally different, but not wrong,
# so it SURVIVED and was right to (BUGS.md T5's "a value nothing depends on"). The hazard needs the pgrep read
# INSIDE the `if`, which is the design that was reverted from: `_suite_live` answers true, the second `pgrep`
# then returns nothing, and the report is built from an empty set -> `RUNNING — 0 suite (pids )`.
mutant status-asks-pgrep-twice 'if [ -n "$pids" ]; then' \
  's/  local pids\n  pids="\$\(pgrep -x tests 2>\/dev\/null \| tr .\\n. . .\)"\n  if \[ -n "\$pids" \]; then/  local pids\n  if _suite_live; then\n    pids="\$(pgrep -x tests 2>\/dev\/null | tr \x27\\n\x27 \x27 \x27)"/s'

# ---- the waiting notice -------------------------------------------------------------------------------------
# The reason must be READ, not re-derived. Each of these is one of the three shipped phantoms put back.
mutant notice-rederives-the-holder '_why="$_TL_BUSY"' \
  's/      _why="\$_TL_BUSY"/      _why="held"; _TL_BUSY_LABEL="\$(_holder_label)"; _TL_BUSY_PID="\$(_holder_pid)"/'
mutant notice-calls-aged-out-dead 'broken after ageing out' \
  's/the lock was just broken after ageing out \(see the line above\)/the lock was just reclaimed from a dead holder/'
mutant notice-claims-reclaim-on-yield 'a suite is already running' \
  's/          echo "test-lock: a suite is already running \(pgrep -x tests\) — waiting up to \$\{wait_s\}s…" >&2 ;;/          echo "test-lock: the lock was just reclaimed (see the line above) — racing for it, up to \${wait_s}s…" >\&2 ;;/'
# A new busy path that forgets to record its reason: the `*)` arm is what makes that visible instead of silent.
mutant busy-reason-not-recorded '_TL_BUSY="reclaimed-aged"' \
  's/    _TL_BUSY="reclaimed-aged"\n//'
mutant multiword-label-truncated '_TL_BUSY_LABEL="$(_holder_label)"; _TL_BUSY_PID' \
  's/  _TL_BUSY="held"; _TL_BUSY_LABEL="\$\(_holder_label\)"; _TL_BUSY_PID="\$\(_holder_pid\)"/  _TL_BUSY="held"; _TL_BUSY_LABEL="\$(_holder_label | cut -d\x27 \x27 -f1)"; _TL_BUSY_PID="\$(_holder_pid)"/'

echo
echo "=== $KILLED killed, $SURVIVED SURVIVED, $NOTAPPLIED NOT-APPLIED ==="
[ -n "$OUT" ] && { cp "$STAGE" "$OUT" && echo "wrote $OUT"; }
[ "$NOTAPPLIED" -gt 0 ] && exit 2
[ "$SURVIVED" = 0 ]
