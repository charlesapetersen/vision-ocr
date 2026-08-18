#!/usr/bin/env bash
# ops/autonomous/next-item.sh — which queue item is actionable RIGHT NOW, decided deterministically.
#
# WHY A SCRIPT AND NOT THE MODEL. The session reads this instead of grepping the queue itself, for the same
# reason the daemon derives "progress" from a hash rather than asking the session whether it worked: a
# model that is asked to check its own preconditions can conclude it has. Ordering and hold state are
# mechanical facts, so they are computed mechanically and the session is handed the answer.
#
# WHAT THE QUEUE IS, AND WHY IT IS NOT THIS PROJECT'S TRACKER. `BUGS.md` (the defect register) and
# `TODO.md` (decided-but-undone work) remain the trackers of record for CONTENT — what the defect is, what
# was measured, what a fix must satisfy. Neither is machine-readable as a queue: `TODO.md` is prose-driven
# with status encoded in `## <heading> — done <date>` suffixes and holds exactly 10 checkbox lines in 45 KB,
# and `BUGS.md` is 163 entries in ~480 KB. Trying to parse an ORDER out of either would be a guard
# that cries wolf, which is the failure mode it exists to prevent.
#
# So `QUEUE.md` carries one thing the prose trackers do not: the ORDER, in a form a script can read. Each
# item cites the register entry it came from, and `check-queue-coherence.sh` cross-checks those cites
# against `BUGS.md`, so the duplication is bounded and its drift is LOUD rather than silent. That
# cross-check is the whole licence for having a second list at all — the sibling project needed three
# separate scripts to police two trackers, and the lesson recorded there is that one list makes all of them
# evaporate. This is one list plus an index, not two lists.
#
# ITEM FORMAT (column-0 markdown checkbox; the tag is the first token after the box):
#   - [ ] **C24b** — the 45 pages that draw a smaller image than the shared dictionary holds. (origin: BUGS.md C24)
#   - [ ] **T-taborder** — the tab-order walk (blocked-on: C24b) [hold] needs: owner
#
# MARKERS it understands:
#   (blocked-on: TAG[, TAG…])   do not offer until EVERY named tag is done. A MISSING tag counts as UNMET,
#                               so a typo blocks loudly instead of running work out of order.
#   [hold] / needs: owner       never offered to an unattended session, whatever else is true.
#
# A prerequisite is satisfied if it is `[x]` here, OR its register entry in `BUGS.md` is closed. Reading
# both matters: an item can be finished and its queue line archived, and a resolver that only knew the
# queue would then block every dependent forever.
#
# OUTPUT — one tab-separated line per OPEN item, in queue order:
#   ok<TAB><tag><TAB><text>              actionable now
#   blocked:<T1,T2><TAB><tag><TAB><text> waiting on unmet prerequisites (named)
#   hold<TAB><tag><TAB><text>            owner-only, never auto-executed
#
# EXIT — four codes, because they are four DIFFERENT owner actions and collapsing any of them into
# "empty" is the misreport `run-state-lib.sh` exists to undo one level up:
#   0  at least one `ok` item — the daemon has work
#   3  no `[ ]` items at all — the queue is genuinely drained; add work or set RUN STATUS: COMPLETE
#   4  `[ ]` items exist but EVERY one is blocked or held — unblock something; do not add work
#   2  cannot run: no queue file, or it has no recognisable items — surfaced, never silently "empty"
set -uo pipefail

# A backgrounded/launchd shell here has essentially no PATH — CLAUDE.md documents that `basename`, `cut`
# and `timeout` then fail silently and loops report bogus results. This runs from a `claude -p` session and
# from the health gate, so set it rather than inherit nothing.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
QUEUE="${VISIONOCR_QUEUE:-$ROOT/ops/autonomous/QUEUE.md}"
BUGS="${VISIONOCR_BUGS:-$ROOT/BUGS.md}"

[ -f "$QUEUE" ] || { echo "next-item: no queue file at $QUEUE" >&2; exit 2; }
# Absent register degrades to "no tag is known closed there" rather than failing — the queue's own `[x]`
# state is then the only evidence, which is strictly the safer direction (an unknown prereq reads as unmet).
[ -f "$BUGS" ] || BUGS=/dev/null

TAB="$(printf '\t')"

# ---- pass 1: which register tags are CLOSED --------------------------------------------------------
# BUGS.md entries are `### <TAG> · <title> — <STATUS>`. CLOSED iff the status begins FIXED / WONTFIX /
# NO DEFECT; anything else (notably `HALF FIXED`) is OPEN. Defined by exclusion on purpose: the register's
# header declares the vocabulary `OPEN · FIXED · WONTFIX`, but `HALF FIXED` is what C24 carried for the two
# days it was half done, so a whitelist of "open" spellings would report zero open entries the day someone
# coins a new one. Erring toward OPEN only ever costs a look; erring toward CLOSED unblocks work early.
BUGSTATE="$(mktemp -t vo-next-bugs)"
trap 'rm -f "$BUGSTATE"' EXIT
awk '
  /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
  fence { next }
  /^###[[:space:]]/ {
    line = $0
    sub(/^###[[:space:]]+/, "", line)
    tag = line
    if (match(tag, /^[A-Za-z0-9][A-Za-z0-9._-]*/)) tag = substr(tag, 1, RLENGTH); else next
    # Status is whatever follows the LAST em dash on the heading. Take the last, not the first: entry
    # titles contain em dashes of their own ("Correctness — loses or corrupts content").
    st = ""
    rest = line
    while (match(rest, /—/)) { st = substr(rest, RSTART + RLENGTH); rest = st }
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", st)
    gsub(/\*/, "", st)
    closed = (st ~ /^FIXED/ || st ~ /^WONTFIX/ || st ~ /^NO DEFECT/) ? "x" : " "
    if (!(tag in seen)) { seen[tag] = 1; print tag "\t" closed }
  }
' "$BUGS" > "$BUGSTATE" 2>/dev/null || true

# ---- pass 2: resolve the queue ---------------------------------------------------------------------
# Item SPANS, not lines: a `(blocked-on: …)` clause can wrap onto a continuation line, and a resolver that
# only scanned the checkbox line would silently drop the second half of a clause and offer the item.
out="$(awk -v bugstate="$BUGSTATE" '
  function flush_item() {
    if (cur_tag == "") return
    deps = alldeps(cur_span)
    held = (cur_span ~ /\[hold\]/ || cur_span ~ /needs:[[:space:]]*owner/)
    if (cur_state == "x") { cur_tag = ""; cur_span = ""; return }   # done items are not offered
    if (held) { print "hold\t" cur_tag "\t" cur_text; nopen++; cur_tag=""; cur_span=""; return }
    unmet = ""
    n = split(deps, d, ",")
    for (i = 1; i <= n; i++) {
      if (d[i] == "") continue
      if (!tag_done(d[i])) unmet = unmet (unmet == "" ? "" : ",") d[i]
    }
    if (unmet != "") print "blocked:" unmet "\t" cur_tag "\t" cur_text
    else { print "ok\t" cur_tag "\t" cur_text; nok++ }
    nopen++
    cur_tag = ""; cur_span = ""
  }
  # A tag is done if the queue ticked it, OR the register closed it. Pending anywhere wins: a `[ ]` is a
  # positive statement that the work is not finished, and it must outrank a stale `[x]` elsewhere.
  function tag_done(t) {
    if (t in qpend) return 0
    if (t in qdone) return 1
    if (t in bclosed) return bclosed[t] == "x"
    return 0                                   # unknown tag => UNMET, so a typo blocks loudly
  }
  function alldeps(s,   res, t) {
    res = ""
    while (match(s, /\(blocked-on:[^)]*\)/)) {
      t = substr(s, RSTART, RLENGTH)
      s = substr(s, RSTART + RLENGTH)
      sub(/^\(blocked-on:[[:space:]]*/, "", t)
      sub(/\)$/, "", t)
      gsub(/[[:space:]]/, "", t)
      res = res (res == "" ? "" : ",") t
    }
    return res
  }
  BEGIN {
    FS = "\t"
    while ((getline line < bugstate) > 0) {
      split(line, f, "\t")
      if (f[1] != "") bclosed[f[1]] = f[2]
    }
    close(bugstate)
    FS = " "
  }
  # Skip fenced blocks and blockquotes, so the format examples in this file’s own header — and in QUEUE.md’s
  # — cannot be resolved as real work. The sibling project shipped exactly that bug twice.
  /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
  fence { next }
  /^[[:space:]]*>/ { next }

  # First sweep is impossible in one pass (a later item may be a prerequisite of an earlier one), so the
  # checkbox STATE map is built in this same pass before any item is flushed: items are buffered and
  # emitted at END. That is why nothing prints until the file is fully read.
  /^[[:space:]]*[-*][[:space:]]+\[[ xX]\]/ {
    flush_item()
    raw = $0
    st = (raw ~ /^[[:space:]]*[-*][[:space:]]+\[[xX]\]/) ? "x" : " "
    line = raw
    sub(/^[[:space:]]*[-*][[:space:]]+\[[ xX]\][[:space:]]*/, "", line)
    sub(/^\*\*/, "", line); sub(/^`/, "", line)
    tag = line
    if (match(tag, /^[A-Za-z0-9][A-Za-z0-9._-]*/)) tag = substr(tag, 1, RLENGTH); else tag = ""
    if (tag == "") next
    if (st == "x") qdone[tag] = 1; else qpend[tag] = 1
    cur_tag = tag; cur_state = st; cur_span = raw
    # The text is what a human reads in `daemon.sh status`, so strip the tag and the markdown that bolded
    # it. Without this the label reads "C24b** — the remaining half…", i.e. the tag twice and a dangling
    # pair of asterisks — cosmetic, but this string is rendered to the owner.
    cur_text = substr(line, length(tag) + 1)
    sub(/^\*\*/, "", cur_text); sub(/^`/, "", cur_text)
    sub(/^[[:space:]]*(—|-{1,2})[[:space:]]*/, "", cur_text)
    if (length(cur_text) > 150) cur_text = substr(cur_text, 1, 147) "..."
    buf_n++
    order[buf_n] = tag; ostate[buf_n] = st; ospan[buf_n] = raw; otext[buf_n] = cur_text
    cur_tag = ""    # spans are re-walked at END; this pass only builds the maps
    next
  }
  # Continuation of the item above: anything until the next checkbox or a markdown heading.
  /^#/ { next }
  buf_n > 0 { ospan[buf_n] = ospan[buf_n] " " $0 }

  END {
    for (k = 1; k <= buf_n; k++) {
      cur_tag = order[k]; cur_state = ostate[k]; cur_span = ospan[k]; cur_text = otext[k]
      flush_item()
    }
    # Communicate the tallies out of band; the caller turns them into the exit code.
    print "##COUNTS##\t" nopen+0 "\t" nok+0
  }
' "$QUEUE")" || { echo "next-item: could not parse $QUEUE" >&2; exit 2; }

counts="$(printf '%s\n' "$out" | grep '^##COUNTS##' | tail -1)"
printf '%s\n' "$out" | grep -v '^##COUNTS##'

nopen="$(printf '%s' "$counts" | cut -f2)"; case "$nopen" in ''|*[!0-9]*) nopen=0 ;; esac
nok="$(printf '%s' "$counts" | cut -f3)";  case "$nok"  in ''|*[!0-9]*) nok=0 ;;  esac

# No items AND no recognisable checkbox lines at all is a malformed queue, not a drained one — the
# distinction the exit table above exists for. Tell them apart by whether the file has any checkbox.
if [ "$nopen" -eq 0 ]; then
  if grep -qE '^[[:space:]]*[-*][[:space:]]+\[[ xX]\]' "$QUEUE" 2>/dev/null; then
    exit 3    # items exist, all `[x]` — genuinely drained
  fi
  echo "next-item: $QUEUE has no recognisable checkbox items — is it the right file?" >&2
  exit 2
fi
[ "$nok" -gt 0 ] && exit 0
exit 4
