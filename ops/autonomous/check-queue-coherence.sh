#!/usr/bin/env bash
# ops/autonomous/check-queue-coherence.sh — the queue's cites, against the register they cite.
#
# WHY THIS EXISTS, AND WHY IT IS THE PRICE OF HAVING A QUEUE AT ALL. `ops/autonomous/QUEUE.md` carries the
# ORDER of autonomous work; `BUGS.md` (the defect register) and `TODO.md` (decided-but-undone work) remain
# the trackers of record for CONTENT — what the defect is, what was measured, what a fix must satisfy. That
# is DUPLICATED STATE, and the harm from duplicated state is not that it is redundant: it is that its drift
# is SILENT. In the sibling project an item shipped and was ticked in one tracker but left `[ ]` in the
# other, so the resolver kept offering already-finished work as "the next task" for a day, and a HUMAN
# caught it — the one reader the daemon exists to spare. Nothing else was ever going to.
#
# So this is the check that earns the second list its place. `next-item.sh` and `QUEUE.md` both name it in
# their headers as the reason the duplication is bounded and its drift LOUD, which means it has to actually
# exist and actually assert something — a cross-check cited but unwritten is worse than no cross-check,
# because two files now claim a guarantee nothing provides.
#
# WHAT IT ASSERTS, and the DIRECTION of each, because the direction is what the reader must act on:
#   * a `[ ]` queue item whose cited register entries are ALL CLOSED — the queue says there is work, the
#     register says it shipped. The daemon would REDO SHIPPED WORK, which is a whole wasted cycle and a
#     commit that undoes a fix. Reported only when EVERY cited tag is closed, never when one of several is
#     still open: a part-closed cite still carries live justification, and flagging it would be crying wolf
#     about legitimate bookkeeping. (`C24b` cited the HALF FIXED C24 while it was open — correctly silent;
#     both are closed as of 2026-08-17, so there is no open cite to be silent about at the moment.)
#     Two consequences, not one, and both are live: a session may redo the finished work, OR — following the
#     resume prompt's STEP 2 rule to "FIRST RULE OUT ALREADY-DONE: if the entry is closed … a previous
#     session finished and died before ticking" — tick a still-live item off UNREAD. The second is the worse
#     one, and it is why this fires on a `[ ]` item rather than only on a `[x]` one.
#     ⚠️ WHEN IT FIRES AND THE WORK IS GENUINELY OPEN, THE CITE IS THE THING TO FIX, NOT THE REGISTER. An
#     `(origin: …)` can be PROVENANCE — new work descended from a closed entry — and `tools-compile`
#     (C25, T16) and `mutants` (T5) are both that today: the entries record where the task came from, and
#     both are FIXED. Reword the cite (or point it at `TODO.md` / `Tools/`, which this check does not
#     resolve) so the next session is not told by its own queue that its work already shipped.
#   * a `[x]` queue item citing an entry still OPEN — ticked here, still open there. Nothing will offer that
#     work again, so it is the drift that goes UNDONE rather than redone, and it is per-tag: one open cite is
#     enough, because the register is the tracker of record and it says the work is unfinished.
#   * a cited TAG THAT DOES NOT EXIST in the register — a typo, or an entry renamed without its citation. A
#     session sent to read it gets nothing back, and `bugs-entry.sh` exits 1 on a tag it cannot find.
#   * DUPLICATE TAGS in the queue. The tag is what `(blocked-on: …)` matches and what `next-item.sh` keys its
#     done/pending maps on, first-occurrence-wins — so a reused tag makes dependency resolution ambiguous
#     and silently hides the second item's state behind the first's.
#
# WHAT IS **NOT** DRIFT, deliberately, because a check that flags legitimate asymmetry becomes noise and
# noise is ignored — the failure this file exists to prevent:
#   * AN ITEM WITH NO `(origin: …)` CITE IS SKIPPED SILENTLY. Several legitimately come from `TODO.md` prose
#     or from `Tools/` (`fault-inject`, `zotero-2`, `annot-r3`), which have no tag space at all; there is
#     nothing to compare and their absence is correct writing, not an omission.
#   * SO IS A `(context: …)` CITE, IN BOTH DIRECTIONS — and this is the one a reader has to be TOLD, because
#     `cited()` scans for `(origin: …)` clauses only and the word `context` appears nowhere in the parser, so
#     the exemption is invisible unless you notice what is ABSENT. `QUEUE.md`'s own "How to write an item"
#     section is the semantics: an `origin:` cite says *this item IS that entry*, a `context:` cite says only
#     *that entry explains why this matters*, and a footnote is not a status claim, so there are never two
#     status claims to have drifted. MEASURED 2026-08-23 on the real tree, one line of `cited()` changed:
#     harvesting `context:` as well takes this file from `OK 56 items 6 cited`, exit 0, to **24 findings —
#     16 TICKED-OPEN and 8 WOULD-REDO** over 31 cited items, and every one of the 24 is correct bookkeeping.
#     Fourteen of the sixteen `TICKED-OPEN` are `c28-*` sub-step boxes (finished sub-steps of a campaign
#     whose parent stays open BY DESIGN — the whole reason that convention exists) and the other two are
#     `c30-fork` and `alltext-replica`; two of the eight `WOULD-REDO` are `tools-compile` and `mutants`, the
#     pair the semantics section was written for, each of which says CLOSED inside its own cite text —
#     `(context: BUGS.md C25 and T16 — both CLOSED; they are why this gate matters, not the work itself)`
#     and `(context: BUGS.md T5 — CLOSED; it records how to tell a real gap from a value nothing depends
#     on)`. (⚠️ Those are two different strings; a draft here quoted the first as if it were both.) That is
#     24 of 56 items crying wolf, which is the exact failure this block exists to prevent. `--self-test`
#     pins the exemption; the one-line sabotage that harvests `context:` turns it red.
#     ⚠️ EVERY `56` HERE IS THE COUNT AT `ad5861d`. The tree now reads 58 — `queue-cite-rule` and
#     `register-dup-tag`, the boxes this work added — and the item total moves with any queue edit while `6 cited` does not, because
#     that box cites a README defect and not the register. `6 cited` is the number these findings are about.
#     ⚠️ THE COST, stated rather than left to be discovered: a `context:` cite is UNVALIDATED. Write
#     `context:` where you meant `origin:` and no status is ever compared; name a tag that does not exist
#     and no `CITE-MISSING` fires either. Both halves are pinned by `--self-test` — the second by rows e and
#     i TOGETHER, and only since the adversarial review: row e alone asserted the ABSENCE of a string the
#     fixture gave the checker no way to produce, so the whole `CITE-MISSING` verdict could be deleted with
#     the self-test still green. Row i is the positive control.
#   * SO IS AN ORIGIN THAT NAMES A FILE OTHER THAN `BUGS.md` — `(origin: REVIEW-2026-08-14.md A1.4)`,
#     `(origin: TODO.md §"2. The Zotero library sweep")`. The REVIEW file has its own tag space (dotted
#     `A6.1` forms) and its own strike-through-in-place convention; only the register's tags are checkable
#     here, and pretending otherwise would invent findings.
#   * SO IS A NON-TAG TOKEN INSIDE A `BUGS.md` CITE. `(origin: BUGS.md C24, HALF FIXED)` carries a status
#     annotation and `(origin: BUGS.md T5, Tools/mutation-log.tsv)` a file path; both are useful to a reader
#     and neither is a tag. Only tokens SHAPED like a register tag (`^[A-Za-z]+[0-9]+([.][0-9]+)*$`) are
#     resolved, which is the same shape rule `bugs-entry.sh` uses to decide what an entry is. The cost of
#     that choice, stated plainly: a typo that is not tag-shaped (`C2X`) is skipped rather than reported.
#     A tag-shaped typo (`C42`) IS reported, and that is the form typos actually take.
#
# ⚠️ PARSING MIRRORS `next-item.sh` DELIBERATELY, and that is the load-bearing property of this file. Same
# anchored checkbox regex, same code-fence and blockquote skipping, same leading `**`/backtick strip, same
# first-`[A-Za-z0-9][A-Za-z0-9._-]*`-token tag, same ITEM SPANS (an `(origin: …)` clause routinely sits on a
# continuation line, so a line-at-a-time reader would see almost no cites at all and report the whole queue
# as uncited). If this checker and the resolver disagreed about what an item is, this would report PHANTOM
# DRIFT — the precise failure it exists to prevent, and the one that gets a guard switched off.
#   One inherited quirk, copied on purpose and recorded so nobody "fixes" it here alone: the span rule is
#   greedy. Any line that is not a checkbox, a heading, a fence or a blockquote is appended to the item
#   above, so prose sitting between items belongs to the item above it in BOTH readers. That is harmless
#   today and it is a real constraint on how `QUEUE.md` may be written: prose between items must not contain
#   a parenthesised `(origin: …)` clause. If that ever needs to change, it changes in both files together.
#
# USAGE:  check-queue-coherence.sh [ROOT]        (ROOT defaults to this script's grandparent)
#         check-queue-coherence.sh --self-test   (fixtures only; touches no real queue and no register)
# OUTPUT: one human line per finding, then a summary, then a machine-readable block — one finding per line,
#         prefixed `queue-coherence:`, mirroring `context-budget.sh`'s `context-budget: OVER <file>`
#         convention. The daemon's `_classify_red()` matches the step name `queue-coherence`; keep it stable.
# EXIT:   0 in sync · 1 drift · 2 bad input (no queue, no register, or a queue with no recognisable items —
#         surfaced rather than reported as "nothing to check") · 5 a --self-test assertion failed.
#         QUEUE_COHERENCE_QUIET=1 silences the success line; it NEVER silences a finding.
#
# Warn-only in the health gate. Read-only: no edits, no commits, no build, no suite.
set -uo pipefail

# A backgrounded/launchd shell here has essentially no PATH — CLAUDE.md documents that `basename`, `cut` and
# `timeout` then fail silently and loops report bogus results. This runs from the health gate and from a git
# hook, both of which are exactly that context, so set it rather than inherit nothing.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# ---- --self-test ------------------------------------------------------------------------------------------
# WHY IT EXISTS. This file's whole job is to make one kind of drift LOUD, and until 2026-08-23 nothing
# checked the checker: `ops/autonomous/tests/` holds harnesses for the daemon, the stop path, the test lock
# and the digest, and none for this. That is how `QUEUE.md`'s sub-box rule came to assert the OPPOSITE of what
# this script does about `(context: …)` and stayed wrong while 16 ticked boxes depended on the real behaviour.
# A checker with no self-test is an assertion nobody has audited.
#
# ⚠️ IT MUST NOT BE ABLE TO PASS VACUOUSLY, which is this register's most repeated failure (ten checks that
# could not fail). Six guards, deliberately of different kinds, because none catches the others' failure:
#   (1) POSITIVE CONTROLS — rows a, c and f MUST produce their findings, tag and entry named. If the fixture
#       stops parsing (a checkbox regex change, a span change) these go missing and the self-test is red, so
#       "no findings" can never read as "the exemption holds".
#   (2) NEGATIVE CONTROLS ON THE RULE — the two `context:` rows (b, d) must produce NO finding.
#   (3) THE OTHER TWO QUADRANTS — rows g and h, the AGREEING `origin:` combinations (`[x]` on a CLOSED entry,
#       `[ ]` on an OPEN one), which must also be silent. These complete a 2x2 of {`[x]`,`[ ]`} against
#       {cite OPEN, cite CLOSED}; see the note beside them for the sabotage that survived without them.
#   (4) THE COUNTS — `N_ITEMS` and `N_CITED` are asserted from the summary line. `N_CITED` is the one that
#       bites: harvesting `context:` moves it even where a finding's presence or absence happens not to move.
#   (5) AN INVERTED ROW — `f-mixed` carries BOTH cite words on one `[ ]` item, so harvesting `context:` makes
#       its finding VANISH (the open C99 would stop `n_open` being 0) rather than appear. Guards (1)-(4) all
#       catch a finding appearing; only this one catches the sabotage by a finding disappearing, and a change
#       that trips only this row is a real change in meaning.
# Row e, `e-context-missing`, pins the COST rather than the rule: a `context:` cite naming a tag that is not
# in the register raises nothing. That is not an oversight to be fixed by whoever reads it next — it is what
# "not a status claim" implies — but it must not change by accident either.
#
# WATCHED FAILING 2026-08-23 (CONTRIBUTING §2/§4a) — FOUR `shasum`-distinct sabotages, one edit each, all
# re-measured against the final file, all exit 5. The distinct kill sets are the argument that the guards are
# not redundant:
#   * `cited()`'s `/\(origin:[^)]*\)/` widened to `/\((origin|context):[^)]*\)/` → **7 of 15** red
#     (rows b, d, e, f and both counts) — f by its finding VANISHING, which is the point of that row;
#   * the same match narrowed to `/\(provenance:[^)]*\)/`, so it harvests nothing → **7 of 15**, the
#     exit-code check among them, because a checker that finds nothing exits 0 and would otherwise look
#     exactly like a coherent tree;
#   * `TICKED-OPEN`'s guard loosened, `[ "$n_open" -gt 0 ]` → `-ge 0` → **2 of 15**, row g and the finding
#     total. ⛔ THIS ONE SURVIVED THE FIRST VERSION OF THIS SELF-TEST AT 0 RED AND EXIT 0 — see the note at
#     guard (3);
#   * `status_of()` stubbed to return closed for every tag → **3 of 15**, rows a, h and i;
#   * the whole `CITE-MISSING` verdict disabled (`if [ -n "$unknown" ]` → `if false`) → **2 of 15**, row i
#     and the finding total. ⛔ THIS ALSO SURVIVED GREEN until the adversarial review — see rows e/i;
#   * the `if (cl !~ /BUGS\.md/) continue` guard removed, so a non-register cite is resolved → **3 of 15**,
#     row j and both counts. ⛔ ALSO SURVIVED GREEN, and on the real tree it manufactures 8 phantom findings,
#     one of them on this file's own `[x] queue-cite-rule` box.
# Every sabotage is killed by a set no other sabotage's set contains; `g` is the only ROW that catches the
# third, `h` the only SILENCE assertion that catches the fourth (row `a` fires there too), `i` the only check
# that catches the fifth, and `j` the only one that catches the sixth.
# A seventh sabotage breaks the FIXTURE rather than the code — two lines inserted above the queue heredoc,
# shifting every row → **3 of 15**, rows a/c/f — which is what proves the positive controls assert the
# finding's reported LINE NUMBER and are not loose prefix matches. Its cost is that inserting a row in the
# middle of that heredoc reddens three checks until the expected line numbers are corrected; that is the
# intended trade against an assertion blind to the checker naming the wrong line.
if [ "${1:-}" = "--self-test" ]; then
  st_fail=0; st_checks=0
  st_dir="$(mktemp -d -t vo-cqc-selftest)" || { echo "self-test: cannot make a temp dir" >&2; exit 5; }
  trap 'rm -rf "$st_dir"' EXIT
  st_say() { st_checks=$(( st_checks + 1 )); }
  st_want() {   # st_want <label> <needle>   — the needle MUST appear in the captured output
    st_say
    case "$st_out" in *"$2"*) : ;; *) echo "self-test: FAIL $1 — expected to find: $2" >&2; st_fail=1 ;; esac
  }
  st_reject() { # st_reject <label> <needle> — the needle must NOT appear
    st_say
    case "$st_out" in *"$2"*) echo "self-test: FAIL $1 — should NOT have found: $2" >&2; st_fail=1 ;; *) : ;; esac
  }

  # The register fixture. `C98` closed, `C99` open, and no other entry — so a row's verdict is attributable
  # to its own cite word and nothing else. Written in the register's real `### <TAG> · … — <STATUS>` shape so
  # `bugs-entry.sh --list --file` parses it exactly as it parses BUGS.md.
  cat > "$st_dir/BUGS.md" <<'ST_BUGS'
# self-test register fixture

### C98 · an entry that shipped — FIXED

body

### C99 · an entry still being worked — OPEN

body
ST_BUGS

  # The queue fixture: the cite-word matrix. EIGHT items, of which exactly three must be findings — rows a,
  # c and f. Rows a/c/g/h are the full 2x2 of {`[x]`,`[ ]`} against {cite OPEN, cite CLOSED} on `origin:`.
  cat > "$st_dir/QUEUE.md" <<'ST_QUEUE'
# self-test queue fixture

- [x] **a-origin-open** — ticked, origin cite on an OPEN entry: drift. (origin: BUGS.md C99)
- [x] **b-context-open** — ticked, context cite on an OPEN entry: NOT drift. (context: BUGS.md C99)
- [ ] **c-origin-closed** — open, origin cite on a CLOSED entry: drift. (origin: BUGS.md C98)
- [ ] **d-context-closed** — open, context cite on a CLOSED entry: NOT drift. (context: BUGS.md C98)
- [ ] **e-context-missing** — open, context cite on a tag that does not exist: NOT reported. (context: BUGS.md C77)
- [ ] **f-mixed** — open, BOTH cite words; only the origin half counts. (origin: BUGS.md C98) (context: BUGS.md C99)
- [x] **g-origin-ticked-closed** — ticked, origin cite on a CLOSED entry: agreement, silent. (origin: BUGS.md C98)
- [ ] **h-origin-open-open** — open, origin cite on an OPEN entry: agreement, silent. (origin: BUGS.md C99)
- [ ] **i-origin-missing** — origin cite on a tag that is NOT in the register: CITE-MISSING. (origin: BUGS.md C77)
- [ ] **j-origin-elsewhere** — origin cite naming another file: skipped, silent. (origin: ops/autonomous/README.md D18)
ST_QUEUE

  # Re-invoke THIS file by an absolute path resolved from `$0`, not `$0` itself: a relative `$0` is only
  # valid from the caller's cwd, and the summary line the count assertions read is what a wrong path would
  # silently take away. `QUEUE_COHERENCE_QUIET=0` is set explicitly so a caller's exported QUIET cannot
  # remove a line an assertion depends on — the health gate is exactly such a caller.
  st_self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  st_say; [ -r "$st_self" ] || { echo "self-test: FAIL cannot resolve myself at $st_self" >&2; st_fail=1; }
  st_out="$(VISIONOCR_QUEUE="$st_dir/QUEUE.md" VISIONOCR_BUGS="$st_dir/BUGS.md" \
            QUEUE_COHERENCE_QUIET=0 bash "$st_self" 2>&1)"; st_rc=$?

  st_say; [ "$st_rc" = 1 ] || { echo "self-test: FAIL exit — expected 1 (drift), got $st_rc" >&2; st_fail=1; }

  # GUARD (1) positive controls — the origin rows must be reported, with the tag, the LINE and the entry.
  # The line number is asserted on purpose: without it these would pass a checker reporting the wrong line.
  st_want  "origin/ticked/open"  "queue-coherence: TICKED-OPEN a-origin-open 3 C99"
  st_want  "origin/open/closed"  "queue-coherence: WOULD-REDO c-origin-closed 5 C98"
  # GUARD (5) the inverted row — vanishes under a context-harvesting sabotage rather than appearing.
  st_want  "mixed/origin-half"   "queue-coherence: WOULD-REDO f-mixed 8 C98"
  # GUARD (2) negative controls on the rule itself, in both directions.
  st_reject "context/ticked/open" "b-context-open"
  st_reject "context/open/closed" "d-context-closed"
  # Row e — the exemption's COST: an unresolvable context cite raises nothing, not even CITE-MISSING.
  # ⛔ ROW i IS WHAT MAKES THAT PAIR MEAN ANYTHING, and its absence was the ELEVENTH check-that-could-not-fail
  # in this project's history — caught by the adversarial pass on the commit that added this block, not by
  # reasoning. Measured: with the whole `if [ -n "$unknown" ] … finding "cite" …` verdict DELETED from this
  # file, the self-test still read `ok`, exit 0, while the checker answered "every cite resolves and agrees"
  # over a typo'd `(origin: …)` cite. The reject below asserted the absence of a string the fixture gave the
  # checker no way to produce, and was additionally implied by the reject above it (only row e carried an
  # unresolvable tag, so any `CITE-MISSING` in the output necessarily named `e-context-missing`). Row i is
  # the positive control that fixes both, and it is also the only coverage this self-test has of the
  # checker's THIRD verdict class.
  st_reject "context/missing-tag" "e-context-missing"
  st_want   "origin/missing-tag" "queue-coherence: CITE-MISSING i-origin-missing 11 C77"
  st_reject "context/missing-tag-not-cite-missing" "CITE-MISSING e-context-missing"
  # Row j — the "clause must name BUGS.md" guard (`if (cl !~ /BUGS\.md/) continue`), which was ALSO unpinned
  # and is what keeps this file's own `[x] queue-cite-rule` box silent, since that box cites a README defect.
  # Delete that guard and the real tree grows 8 phantom findings, one of them on that very box.
  st_reject "origin/other-file-is-skipped" "j-origin-elsewhere"
  # GUARD (3) THE OTHER TWO QUADRANTS — the AGREEING `origin:` rows, which must stay silent. ⛔ These were MISSING
  # from the first version of this self-test and their absence made it survive a real sabotage: with
  # `TICKED-OPEN`'s guard loosened from `[ "$n_open" -gt 0 ]` to `-ge 0` — i.e. "report every ticked item
  # that cites anything", the condition's whole meaning gone — the self-test scored 0 red and exit 0. It
  # could not see it, because every ticked row it had either carried an open cite (reported either way) or no
  # cite at all (skipped by the `[ -n "$cites" ]` guard before any verdict). CONTRIBUTING §4d is the lesson
  # and the remedy: enumerate the states against the doors instead of reasoning about pairs. The doors here
  # are {`[x]`, `[ ]`} × {cite OPEN, cite CLOSED}, and two of the four cells were never written down.
  # Watched failing, and stated precisely because a draft of this comment over-claimed: with that `-ge 0`
  # sabotage `g` is the only ROW that goes red (the finding total goes with it, but that is a count, not a
  # row); with `status_of()` stubbed to return closed for every tag, `h` is the only SILENCE assertion that
  # goes red — row `a`'s positive control fires too, since a closed C99 removes its finding.
  st_reject "origin/ticked/closed-is-agreement" "g-origin-ticked-closed"
  st_reject "origin/open/open-is-agreement"     "h-origin-open-open"
  # GUARD (4) the counts. N_CITED = 5 (four single-origin rows plus the mixed one); 8 items in all. This is
  # what moves even when a finding's presence happens not to.
  st_want  "summary counts"      "(10 items, 6 citing BUGS.md)"
  st_want  "finding total"       "4 item(s) disagree"

  if [ "$st_fail" = 0 ]; then echo "check-queue-coherence: self-test ok ($st_checks checks)"; exit 0; fi
  echo "check-queue-coherence: SELF-TEST FAILED" >&2; exit 5
fi

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
SELFDIR="$(cd "$(dirname "$0")" && pwd)"
QUEUE="${VISIONOCR_QUEUE:-$ROOT/ops/autonomous/QUEUE.md}"
BUGS="${VISIONOCR_BUGS:-$ROOT/BUGS.md}"
QUIET="${QUEUE_COHERENCE_QUIET:-0}"

[ -f "$QUEUE" ] || { echo "check-queue-coherence: no queue file at $QUEUE" >&2; exit 2; }
# ⚠️ An absent register is EXIT 2 here, unlike in `next-item.sh` where it degrades to /dev/null. The two are
# right for their own jobs: the resolver must still hand out work when the register cannot be read (an
# unknown prerequisite reads as unmet, which is safe), whereas this file has nothing to assert at all without
# it and must say so rather than print "in sync" over a comparison it never made.
[ -f "$BUGS" ]  || { echo "check-queue-coherence: no register at $BUGS — nothing to check the cites against" >&2; exit 2; }

TAB="$(printf '\t')"
TMP="$(mktemp -d -t vo-queue-coherence)" || { echo "check-queue-coherence: cannot make a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
TAGS="$TMP/tags"; ITEMS="$TMP/items"; FIND="$TMP/findings"
: > "$FIND"
finding() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FIND"; }

# ---- the register ----------------------------------------------------------------------------------------
# `bugs-entry.sh` is the definition of record for what a tag and a status are; this file must agree with it
# and with `next-item.sh` or the three of them will contradict each other about whether an entry is closed.
# ⛔ "VERBATIM COPY" IS NOT TRUE OF THE OUTPUT, measured 2026-08-23 over the real `BUGS.md`: `bugs-entry.sh
# --list` emits **169 rows** and this fallback **168**, because the register carries TWO `### R63` headings
# (lines 12145 and 12618) and only the fallback dedupes, via `seen[tag]`. No live consequence today — both
# are `FIXED` and `status_of` takes the first match — but `status_of`'s answer becomes dependent on whether
# `bugs-entry.sh` happens to be executable the moment those two statuses diverge, and a duplicate REGISTER
# tag is the one class this file flags in `QUEUE.md` and never in `BUGS.md`. Carried as the queue's
# `register-dup-tag`. ⚠️ `--self-test` is structurally blind to it: its fixture register has no duplicate
# tag and only `FIXED`/`OPEN`, never `WONTFIX`, `NO DEFECT` or `HALF FIXED`, so it stays green with
# `bugs-entry.sh` un-executable or absent.
# The inline fallback is a copy of the same three rules (anchored tag, status after the LAST em
# dash — entry titles carry their own em dashes — closed iff FIXED/WONTFIX/NO DEFECT).
if [ -x "$SELFDIR/bugs-entry.sh" ]; then
  "$SELFDIR/bugs-entry.sh" --list --file "$BUGS" 2>/dev/null \
    | awk -F"$TAB" 'NF>=2 { print $1 "\t" (($2 ~ /^(FIXED|WONTFIX|NO DEFECT)/) ? "x" : " ") }' > "$TAGS" || true
fi
if [ ! -s "$TAGS" ]; then
  awk '
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    /^###[[:space:]]/ {
      h = $0; sub(/^###[[:space:]]+/, "", h); sub(/^~~/, "", h)
      tag = h
      if (match(tag, /^[A-Za-z0-9][A-Za-z0-9._-]*/)) tag = substr(tag, 1, RLENGTH); else next
      if (tag !~ /^[A-Za-z]+[0-9]+([.][0-9]+)*$/) next
      st = ""; rest = h
      while (match(rest, /—/)) { st = substr(rest, RSTART + RLENGTH); rest = st }
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", st); gsub(/\*/, "", st)
      if (!(tag in seen)) { seen[tag] = 1
        print tag "\t" ((st ~ /^FIXED/ || st ~ /^WONTFIX/ || st ~ /^NO DEFECT/) ? "x" : " ") }
    }
  ' "$BUGS" > "$TAGS" 2>/dev/null || true
fi
[ -s "$TAGS" ] || { echo "check-queue-coherence: $BUGS has no recognisable '### <TAG> · … — <STATUS>' entries — wrong file?" >&2; exit 2; }

# ---- the queue -------------------------------------------------------------------------------------------
# Emits, per item:  ITEM<TAB>line<TAB>state<TAB>tag<TAB>cited-tags(space separated)
# and, per reused tag:  DUP<TAB>line<TAB>tag<TAB>first-line
# POSIX awk only: /usr/bin/awk here has no 3-arg match(), so every capture is match()/RSTART/RLENGTH/substr.
awk '
  # Every tag-shaped token inside a `(origin: … BUGS.md …)` clause, after the LAST `BUGS.md` in that clause.
  # (A clause naming BUGS.md twice would drop the tags before the second mention; no such clause exists, and
  # a dropped cite fails silent-and-safe rather than inventing a finding.)
  function cited(s,   res, cl, tail, m, i, parts, t) {
    res = ""
    while (match(s, /\(origin:[^)]*\)/)) {
      cl = substr(s, RSTART, RLENGTH)
      s  = substr(s, RSTART + RLENGTH)
      if (cl !~ /BUGS\.md/) continue          # a TODO.md / REVIEW / Tools cite is not checkable here
      tail = cl
      while (match(tail, /BUGS\.md/)) tail = substr(tail, RSTART + RLENGTH)
      # Keep the tag charset intact (dots, dashes, underscores) so `Tools/mutation-log.tsv` stays ONE token
      # and fails the shape test, instead of shattering into fragments that might pass it.
      gsub(/[^A-Za-z0-9._-]+/, " ", tail)
      m = split(tail, parts, " ")
      for (i = 1; i <= m; i++) {
        t = parts[i]
        if (t ~ /^[A-Za-z]+[0-9]+([.][0-9]+)*$/) res = res (res == "" ? "" : " ") t
      }
    }
    return res
  }

  /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
  fence { next }
  /^[[:space:]]*>/ { next }                    # blockquote: commentary, never an item

  /^[[:space:]]*[-*][[:space:]]+\[[ xX]\]/ {
    raw = $0
    st = (raw ~ /^[[:space:]]*[-*][[:space:]]+\[[xX]\]/) ? "x" : " "
    line = raw
    sub(/^[[:space:]]*[-*][[:space:]]+\[[ xX]\][[:space:]]*/, "", line)
    sub(/^\*\*/, "", line); sub(/^`/, "", line)
    tag = line
    if (match(tag, /^[A-Za-z0-9][A-Za-z0-9._-]*/)) tag = substr(tag, 1, RLENGTH); else tag = ""
    boxes++
    if (tag == "") next                        # as in next-item.sh: not an item; its lines fall to the one above
    n++; otag[n] = tag; ost[n] = st; oline[n] = FNR; ospan[n] = raw
    next
  }
  /^#/ { next }                                # headings never continue an item
  n > 0 { ospan[n] = ospan[n] " " $0 }         # greedy span — see the header note

  END {
    for (k = 1; k <= n; k++) {
      # The `-` keeps a DUP record at the same field count as an ITEM record, so one
      # `read kind line st tag cites` in the caller lands the tag and the first line where it expects them.
      if (otag[k] in firstline) print "DUP\t" oline[k] "\t-\t" otag[k] "\t" firstline[otag[k]]
      else firstline[otag[k]] = oline[k]
      print "ITEM\t" oline[k] "\t" ost[k] "\t" otag[k] "\t" cited(ospan[k])
    }
    print "COUNTS\t" n + 0 "\t" boxes + 0
  }
' "$QUEUE" > "$ITEMS" 2>/dev/null || { echo "check-queue-coherence: could not parse $QUEUE" >&2; exit 2; }

N_ITEMS="$(awk -F"$TAB" '$1 == "COUNTS" { print $2; exit }' "$ITEMS")"
case "${N_ITEMS:-}" in ''|*[!0-9]*) N_ITEMS=0 ;; esac
if [ "$N_ITEMS" -eq 0 ]; then
  # A queue with no recognisable items is the WRONG FILE, not an empty one — the same distinction
  # `next-item.sh` draws between a drained queue and an unparseable one. Never report it as "in sync".
  echo "check-queue-coherence: $QUEUE has no recognisable checkbox items — is it the right file?" >&2
  exit 2
fi

# ---- resolve -------------------------------------------------------------------------------------------
status_of() { awk -F"$TAB" -v t="$1" '$1 == t { print $2; exit }' "$TAGS"; }

N_CITED=0
while IFS="$TAB" read -r kind line st tag cites; do
  case "${kind:-}" in
    DUP)
      # $cites holds the first line for a DUP record.
      finding "duplicate" \
        "QUEUE.md:$line  reuses the tag $tag (first used at line $cites) → (blocked-on: $tag) is ambiguous and next-item.sh reads only the first" \
        "DUPLICATE-TAG $tag $line $cites"
      continue ;;
    ITEM) ;;
    *) continue ;;
  esac
  [ -n "${cites:-}" ] || continue            # no BUGS.md cite: not drift, by design. Skipped silently.
  N_CITED=$(( N_CITED + 1 ))
  n_open=0; n_closed=0; unknown=""; open_tags=""; closed_tags=""
  for c in $cites; do
    s="$(status_of "$c")"
    if [ -z "$s" ]; then unknown="${unknown:+$unknown }$c"
    elif [ "$s" = "x" ]; then n_closed=$(( n_closed + 1 )); closed_tags="${closed_tags:+$closed_tags }$c"
    else n_open=$(( n_open + 1 )); open_tags="${open_tags:+$open_tags }$c"
    fi
  done

  if [ -n "$unknown" ]; then
    # A cite that resolves to nothing is reported on its own and stops the open/closed verdict: with a tag
    # unaccounted for, "every cite is closed" cannot be asserted, and asserting it anyway is how a typo turns
    # into a confident claim that shipped work is being redone.
    finding "cite" \
      "QUEUE.md:$line  item $tag cites $unknown, which is not an entry in BUGS.md → a typo or a renamed entry; bugs-entry.sh exits 1 on it" \
      "CITE-MISSING $tag $line $unknown"
    continue
  fi

  if [ "$st" = "x" ] && [ "$n_open" -gt 0 ]; then
    finding "drift" \
      "QUEUE.md:$line  item $tag is [x] but $open_tags is OPEN in BUGS.md → ticked here, still open there: nothing will offer this work again" \
      "TICKED-OPEN $tag $line $open_tags"
  elif [ "$st" != "x" ] && [ "$n_open" -eq 0 ] && [ "$n_closed" -gt 0 ]; then
    finding "drift" \
      "QUEUE.md:$line  item $tag is [ ] but every cite ($closed_tags) is CLOSED in BUGS.md → queue says work, register says shipped: a session either redoes it, or drops it unread under the resume prompt's rule-out-already-done step" \
      "WOULD-REDO $tag $line $closed_tags"
  fi
done < "$ITEMS"

# ---- report ----------------------------------------------------------------------------------------------
N_FIND="$(grep -c . "$FIND" || true)"
if [ "$N_FIND" -eq 0 ]; then
  [ "$QUIET" = 1 ] || echo "  ✓ queue-coherence: $N_ITEMS queue items, $N_CITED citing BUGS.md; every cite resolves and agrees"
  echo "queue-coherence: OK $N_ITEMS items $N_CITED cited"
  exit 0
fi

echo "  ⚠ queue-coherence: $N_FIND item(s) disagree with the register ($N_ITEMS items, $N_CITED citing BUGS.md):"
awk -F"$TAB" '{ printf "      %-10s %s\n", $1, $2 }' "$FIND"
echo "      Fix BOTH sides in the SAME commit, and fix the SIDE THAT IS WRONG: the register is the tracker of"
echo "      record for content, so a queue box follows it, not the other way round. If the work really did"
echo "      ship, delete the queue item and say so in the commit — QUEUE.md holds order, not history."

# Machine-readable block, one finding per line, after the human report — the convention `context-budget.sh`
# sets and `_classify_red()` in the daemon reads.
awk -F"$TAB" '{ print "queue-coherence: " $3 }' "$FIND"
exit 1
