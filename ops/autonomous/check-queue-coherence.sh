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
# OUTPUT: one human line per finding, then a summary, then a machine-readable block — one finding per line,
#         prefixed `queue-coherence:`, mirroring `context-budget.sh`'s `context-budget: OVER <file>`
#         convention. The daemon's `_classify_red()` matches the step name `queue-coherence`; keep it stable.
# EXIT:   0 in sync · 1 drift · 2 bad input (no queue, no register, or a queue with no recognisable items —
#         surfaced rather than reported as "nothing to check").
#         QUEUE_COHERENCE_QUIET=1 silences the success line; it NEVER silences a finding.
#
# Warn-only in the health gate. Read-only: no edits, no commits, no build, no suite.
set -uo pipefail

# A backgrounded/launchd shell here has essentially no PATH — CLAUDE.md documents that `basename`, `cut` and
# `timeout` then fail silently and loops report bogus results. This runs from the health gate and from a git
# hook, both of which are exactly that context, so set it rather than inherit nothing.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

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
# The inline fallback is a verbatim copy of the same three rules (anchored tag, status after the LAST em
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
