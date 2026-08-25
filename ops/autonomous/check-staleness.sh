#!/usr/bin/env bash
# ops/autonomous/check-staleness.sh — what the documents CLAIM, against what is true.
#
# WHY THIS EXISTS, AND WHY IT IS NOT OPTIONAL HERE. Staleness is this repo's dominant recurring failure —
# not a build break, not a regression, but a true-sounding sentence about the project's own state. The
# history says so in its own commit titles ("The status files went stale behind the work, and the register
# miscounted itself"; one about "eleven stale OPEN markers"), and `CLAUDE.md` carries the confession as a
# permanent parenthetical: *"This paragraph read 'nothing open' for a day after four entries were opened,
# which is exactly the sentence a new reader trusts most."*
#
# Measured, at the time this was written (all four found by this script's own checks, and all four are
# sentences a fresh reader — or a fresh autonomous session — takes as fact):
#   * `HANDOFF.md` says "Four entries are open" against an actual one, and still describes R56/R57 as open
#     entries that "destroy content on the default route" when both were fixed on 2026-08-16;
#   * the suite's check count is asserted as 836 (`HANDOFF.md`), 880 (`TECHNICAL.md`), 1,046 (`TODO.md`) and
#     1,042 (`ARCHITECTURE.md`), against 1,127 in `CLAUDE.md` and in the newest handoff.
# A session reading any of those orients on a false picture, and the cost lands twice: once when it acts on
# the claim, and once when the owner has to work out why it did.
#
# ⚠️ WHAT THIS SCRIPT DELIBERATELY DOES NOT DO: MEASURE THE SUITE. Only `./run_tests.sh` can say how many
# checks the suite has, it takes ~4 minutes (225 s measured 2026-08-24; the 39m30s measured 2026-08-16 was
# clamped-era — ProcessType=Background plus a missing -O, 16.2x), it runs real OCR, and TWO
# SUITES AT ONCE CORRUPT EACH OTHER
# (`~/Library/Preferences/tests.plist` is shared by every worktree — CLAUDE.md's first environment trap, and
# the whole reason `test-lock.sh` exists). This check has to be free enough to run on every gate and inside a
# git hook, so it must never start one. There is also nothing to read instead: `Tests/main.swift` holds no
# literal total — the count is a runtime counter (`var checks = 0`), so it is only knowable by running.
# Therefore the reference figure this script compares against is itself A CLAIM, and it is LABELLED
# `claimed (…)`, never `measured`. This project's culture is explicit that "an entry without evidence is a
# rumour" and that one must "state plainly whether a finding was verified by running code or only reasoned
# about"; a guard that quietly promoted a claim to a measurement would be committing the register's own
# cardinal sin while auditing it. What it CAN assert exactly, and does: THE LIVE DOCUMENTS DISAGREE WITH
# EACH OTHER. At most one of five figures can be current, and that is a defect with no measurement needed.
#
# THE CHECKS. All pure text, milliseconds, read-only. Nothing is compiled, nothing is run.
#   1. OPEN-ENTRY COUNT. The truth comes from `bugs-entry.sh --list` (the definition of record for what a
#      tag and a status are; an inline copy of the same rules is the fallback if that file is missing).
#      OPEN is by EXCLUSION — CLOSED iff the status begins FIXED / WONTFIX / NO DEFECT, so `HALF FIXED` is
#      OPEN. See that script's header for why a whitelist of "open" spellings is the wrong shape.
#      The claims are in ENGLISH ("one entry is open", "Two open", "Four entries are open"), so number WORDS
#      (`zero|no|nothing|none|one|…|twelve`) parse as well as digits, and the claim is a number token
#      followed within six tokens by the word `open`. Tokenised across line breaks on purpose: CLAUDE.md's
#      own claim wraps mid-phrase ("**one entry / is open**") and a line-at-a-time matcher misses it.
#   2. CHECK-COUNT CLAIMS across the doc set. Reference = the HIGHEST figure asserted anywhere in the set,
#      attributed to the newest-modified file that asserts it. Highest rather than newest-file-wins because
#      the count only ever RISES as checks are added (790 → 836 → 880 → 916 → 1037 → 1042 → 1046 → 1101 →
#      1127 is the series these documents themselves still record), and because on a fresh clone or a
#      `git archive` copy every mtime is identical and "most recently modified" decides nothing. Every LIVE
#      doc asserting less than the reference is reported.
#   3. REGISTER vs `CLAUDE.md` PAIRING. (a) a tag OPEN in the register that CLAUDE.md's planning paragraph
#      never mentions; (b) a tag NAMED AS OPEN whose register entry is closed. This is precisely the defect
#      CLAUDE.md asks its readers to fix in the same commit as the code.
#   4. THE READING-ORDER LIST. CLAUDE.md lists the dated `HANDOFF-*.md` files newest-first and names the top
#      one as the entry point; the resume prompt sends every session to "the NEWEST HANDOFF-*.md only". So a
#      handoff on disk but absent from that list is invisible to the daemon, a listed file that does not
#      exist is a dead link, and an entry point that is not the newest date sends every session to the wrong
#      file.
#
# ⚠️ IT IS A **WARN-ONLY** STEP IN THE HEALTH GATE, WHICH SETS THE BAR FOR WHAT MAY BE IN IT. A guard that
# cries wolf gets ignored, and being ignored is the failure it exists to prevent. So where a check could not
# be made EXACT it was LEFT OUT, and here is that list, with reasons:
#   * DATED `HANDOFF-<date>.md` FILES ARE NEVER REPORTED (they only contribute to check 2's reference pool).
#     A figure in one of them is a point-in-time record — HANDOFF-2026-08-17.md's "1,101 → 1,127 checks"
#     inside a before/after table is TRUE about that session — and CLAUDE.md's own doctrine is that dated
#     records "are evidence for one run, not claims about the present". Flagging them would demand edits to
#     honest history.
#   * NOR IS ONE UNDER A HEADING THE DOCUMENT MARKS HISTORICAL — "## The old specification, kept for the
#     commands", "— done <date>", "closed", "superseded", "archived". The heading is the date stamp, and the
#     prose beneath it is a record. Same first-fix-run lesson as the rule below: excluding one historical
#     claim just promotes the next-highest one into the report unless the whole retained section is exempt.
#   * A CHECK-COUNT CLAIM THE PROSE ITSELF DATES OR PUTS IN THE PAST IS NEVER REPORTED — "as of
#     2026-08-15 … the suite stood at 1,046 checks", or any claim on a line carrying an ISO date. It is the
#     same doctrine as the dated-handoff rule above, applied to a sentence instead of a file: such a claim is
#     TRUE, and demanding an edit to it would be demanding an edit to honest history. This was added after the
#     first real fix run, where reconciling TODO.md by DATING its stale figure — the right repair, because a
#     dated figure cannot go stale again — left this check flagging the correct version. A guard that fires on
#     the fix it just asked for is a guard that gets switched off.
#   * ONLY EACH FILE'S HIGHEST CHECK-COUNT CLAIM IS REPORTED, one finding per file. Lower figures in the
#     same file are historical sections kept on purpose: `TODO.md` carries "The suite is at **790 checks**"
#     under §"The old specification, kept for the commands", and quotes its own superseded "916 checks" in a
#     parenthetical self-correction. Both are correct writing. One line per file also matches the remedy,
#     which is "update this file", once.
#   * ONLY EACH REGION'S FIRST OPEN-COUNT CLAIM IS REPORTED, for the same reason: CLAUDE.md deliberately
#     QUOTES "nothing open" and "four entries were opened" in its confession, and BUGS.md's header says
#     "the two entries that had been waiting on a shape signal" about a pair it then reports as fixed. The
#     first such sentence in a region is the one a fresh reader trusts, which is the thing being guarded.
#   * CHECK 3(b) IS SENTENCE-SCOPED AND REQUIRES AN EXPLICIT COUNT CLAIM in that sentence. Without the count
#     requirement it fires on ordinary prose: HANDOFF.md's "(half-answered by R50, and the open half is
#     priority 1 above)" describes half of a FEATURES.md idea, not R50's register status, and R50 is closed.
#     With it, the same pass still catches the real defect ("Four entries are open … R56 … and R57 …, plus
#     R54 and R55") and produces no false positive on either checkout of either file.
#   * A SENTENCE CARRYING BOTH AN OPEN WORD AND A CLOSED WORD IS SKIPPED AS AMBIGUOUS. CLAUDE.md's status
#     sentence legitimately contains both ("**C24, half fixed** … the 45 pages … are still open"), and no
#     mechanical reading of it can be trusted. The symmetric assertion — "called FIXED here, still open in
#     the register" — is therefore NOT made per-sentence; check 1's count catches that direction exactly,
#     which is why it is the check that carries the load.
#   * THE INTRA-DATE ORDER of the reading list is not verified. `HANDOFF-2026-08-15-night.md` is newer than
#     `HANDOFF-2026-08-15.md` and no filename rule says so, so check 4 compares DATES only and asserts
#     nothing about same-day ordering.
#   * FENCED CODE BLOCKS ARE **NOT** SKIPPED, unlike everywhere else in this ops directory. The canonical
#     check-count claim lives inside one (`./run_tests.sh  # 1127 checks` in CLAUDE.md §Commands, and the
#     same line with 836 in HANDOFF.md). Skipping fences would blind this check to its own best evidence.
#
# USAGE:  check-staleness.sh [ROOT]        (ROOT defaults to this script's grandparent)
# OUTPUT: one human line per finding, then a summary, then a machine-readable block — one finding per line,
#         prefixed `staleness:`, mirroring `context-budget.sh`'s `context-budget: OVER <file>` convention.
#         The daemon's `_classify_red()` matches the step name `staleness`, so keep that prefix stable.
# EXIT:   0 nothing stale · 1 findings · 2 bad input (no register, no CLAUDE.md, unparseable register).
#         STALENESS_QUIET=1 silences the success line; it NEVER silences a finding or the machine block.
#
# Read-only. No edits, no commits, no build, no suite. Safe to run at any time, including during a suite.
set -uo pipefail

# A backgrounded/launchd shell here has essentially no PATH — CLAUDE.md documents that `basename`, `cut` and
# `timeout` then fail silently and loops report bogus results. This runs from the health gate and from a git
# hook, both of which are exactly that context, so set it rather than inherit nothing.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
SELFDIR="$(cd "$(dirname "$0")" && pwd)"
BUGS="${VISIONOCR_BUGS:-$ROOT/BUGS.md}"
GUIDE="$ROOT/CLAUDE.md"
HANDOFF="$ROOT/HANDOFF.md"
QUIET="${STALENESS_QUIET:-0}"
# A suite-total claim has been in the high hundreds since the earliest figure these documents record (790).
# Anything smaller is a block-level count — TODO.md's "15 checks in the suite" about the annotation block,
# Tests/main.swift's 18- and 14-check skip census — and reading one as a claim about the whole suite would
# be a fabricated finding.
MIN_PLAUSIBLE_CHECKS="${MIN_PLAUSIBLE_CHECKS:-500}"

[ -f "$BUGS" ]  || { echo "check-staleness: no register at $BUGS" >&2; exit 2; }
[ -f "$GUIDE" ] || { echo "check-staleness: no CLAUDE.md at $GUIDE" >&2; exit 2; }

TAB="$(printf '\t')"
TMP="$(mktemp -d -t vo-staleness)" || { echo "check-staleness: cannot make a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
TAGS="$TMP/tags"      # TAG<TAB>x|space   (x = CLOSED)
FIND="$TMP/findings"  # severity<TAB>human<TAB>machine
: > "$FIND"

finding() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FIND"; }

# ---- the register: one definition of a tag and a status --------------------------------------------------
# `bugs-entry.sh` is that definition. Prefer it over the copy below so the two can never disagree about
# whether something is open — if they did, this guard would report the documents as stale on the strength of
# a rule the rest of the daemon does not share. The inline fallback exists only so a partial checkout still
# gets a check; it is a VERBATIM copy of the same three rules (anchored tag, status after the LAST em dash,
# closed iff FIXED/WONTFIX/NO DEFECT) and must be edited in lockstep if those ever change.
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
if [ ! -s "$TAGS" ]; then
  echo "check-staleness: $BUGS has no recognisable '### <TAG> · <title> — <STATUS>' entries — wrong file?" >&2
  exit 2
fi
N_ENTRIES="$(grep -c . "$TAGS" || true)"
OPEN_TAGS="$(awk -F"$TAB" '$2 != "x" { print $1 }' "$TAGS" | tr '\n' ' ' | sed 's/ *$//')"
N_OPEN="$(awk -F"$TAB" '$2 != "x"' "$TAGS" | grep -c . || true)"
# "0 open ()" reads like a bug in this script rather than a fact about the register, and the empty-set case
# is the one a reader is most likely to distrust. Name it in words instead.
OPEN_LIST="${OPEN_TAGS:-none}"

# ---- claims + pairing, one pass per file -----------------------------------------------------------------
# Emits CLAIM (an open-count assertion), MENTION (a register tag named in the region) and CALLEDOPEN (a
# closed tag inside a sentence that asserts a count of open entries and says nothing about anything being
# fixed). Region selects how much of the file is the "status" region:
#   bugs   = the header, up to the first `## ` section     claude = the planning paragraph, to the next `## `
#   all    = the whole file (HANDOFF.md is narrative throughout)
# POSIX awk only: /usr/bin/awk here has no 3-arg match(), so everything goes through match()/RSTART/RLENGTH.
scan() {  # $1 = file, $2 = region selector
  awk -v tagfile="$TAGS" -v region="$2" '
    function isnum(t) {
      if (t ~ /^[0-9]+$/) return 1
      return (t in words)
    }
    function numval(t) { return (t ~ /^[0-9]+$/) ? t + 0 : words[t] }
    # A sentence ends at . ! or ? followed by space/EOL, or at a blank line. Claims and tag mentions are
    # scoped to it, so a count in one sentence cannot be attributed to tags named in the next.
    function flush(   i, m, a, b) {
      if (s_claim && !s_closed && s_tags != "") {
        m = split(s_tags, a, " "); split(s_lines, b, " ")
        for (i = 1; i <= m; i++) if (closed[a[i]] == "x") print "CALLEDOPEN\t" b[i] "\t" a[i]
      }
      s_tags = ""; s_lines = ""; s_claim = 0; s_closed = 0; pend = ""; pdist = 0
    }
    BEGIN {
      FS = "\t"
      while ((getline l < tagfile) > 0) { split(l, f, "\t"); if (f[1] != "") closed[f[1]] = f[2] }
      close(tagfile)
      FS = " "
      words["zero"] = 0; words["no"] = 0; words["nothing"] = 0; words["none"] = 0
      words["one"] = 1; words["two"] = 2; words["three"] = 3; words["four"] = 4; words["five"] = 5
      words["six"] = 6; words["seven"] = 7; words["eight"] = 8; words["nine"] = 9; words["ten"] = 10
      words["eleven"] = 11; words["twelve"] = 12
      inregion = (region == "bugs" || region == "all")
    }
    # The planning paragraph is prose, not a heading, so it is found by its own words. Both spellings are
    # matched because the sentence has been rewritten before and will be again.
    region == "claude" && !inregion && (/defect register/ || /Planning lives in/) { inregion = 1 }
    /^##[[:space:]]/ { if (region != "all") { if (inregion) flush(); inregion = 0 } }
    !inregion { next }
    /^[[:space:]]*$/ { flush(); next }
    {
      raw = $0
      # Mark sentence ends BEFORE punctuation is stripped, with a token no real word can collide with.
      gsub(/[.!?]$/, " xeosx", raw); gsub(/[.!?][[:space:]]/, " xeosx ", raw)
      # Commas go first, so "1,127" survives as one number token rather than splitting into 1 and 127.
      gsub(/,/, "", raw)
      gsub(/[^A-Za-z0-9]+/, " ", raw)
      n = split(raw, w, " ")
      for (i = 1; i <= n; i++) {
        t = w[i]; lt = tolower(t)
        if (lt == "xeosx") { flush(); continue }
        # `open` and not `opened`: the tokenizer keeps them distinct, and "four entries were opened" is
        # CLAUDE.md quoting its own past mistake, not asserting anything now.
        if (lt == "open" && pend != "" && pdist <= 6) {
          print "CLAIM\t" pline "\t" pend; s_claim = 1; pend = ""
        }
        if (lt == "fixed" || lt == "wontfix" || lt == "defect") s_closed = 1
        if (isnum(lt)) { pend = numval(lt); pline = FNR; pdist = 0 } else if (pend != "") pdist++
        if (t in closed) { print "MENTION\t" FNR "\t" t; s_tags = s_tags " " t; s_lines = s_lines " " FNR }
      }
    }
    END { flush() }
  ' "$1"
}

# ---- check 1: the open-entry count -----------------------------------------------------------------------
# One claim per region — the FIRST — for the reasons in the header.
check_open_count() {  # $1 = path, $2 = region, $3 = label
  [ -f "$1" ] || return 0
  local rec claimed line
  rec="$(scan "$1" "$2" | awk -F"$TAB" '$1 == "CLAIM" && !seen++ { print $2 "\t" $3 }')"
  [ -n "$rec" ] || return 0
  line="$(printf '%s' "$rec" | cut -f1)"; claimed="$(printf '%s' "$rec" | cut -f2)"
  [ "$claimed" = "$N_OPEN" ] && return 0
  finding "stale" \
    "$3:$line  claims $claimed open ≠ $N_OPEN open in BUGS.md ($OPEN_LIST)" \
    "OPEN-COUNT $3 $line $claimed $N_OPEN"
}
check_open_count "$BUGS"    bugs   "BUGS.md"
check_open_count "$GUIDE"   claude "CLAUDE.md"
check_open_count "$HANDOFF" all    "HANDOFF.md"

# ---- check 2: the suite's check count --------------------------------------------------------------------
# LIVE docs assert the present and are reported. DATED handoffs are point-in-time records: they feed the
# reference pool and are never flagged. Fences are not skipped — the canonical claim is inside one.
LIVE_DOCS="CLAUDE.md HANDOFF.md TECHNICAL.md TODO.md README.md CONTRIBUTING.md ARCHITECTURE.md"
CC="$TMP/checkcounts"; : > "$CC"          # file<TAB>line<TAB>value<TAB>live|dated
cc_scan() {  # $1 = path, $2 = label, $3 = live|dated
  [ -f "$1" ] || return 0
  awk -v label="$2" -v kind="$3" -v floor="$MIN_PLAUSIBLE_CHECKS" '
    # A token stream with ONE token of carry-over, because the claim wraps: TODO.md ends a line with
    # "the suite is at 1046" and begins the next with "checks." A line-at-a-time matcher reads that file as
    # claiming 916 (a figure it quotes only to correct) and misses the live claim entirely — measured.
    {
      # Keep the ORIGINAL text as well as the mangled one. The mangling below turns 2026-08-15 into
      # "2026 08 15", so a date test has to run on the original or it can never match.
      orig = tolower($0)
      # Track the enclosing section heading. A claim sitting under a heading the document itself marks as
      # historical is retained-on-purpose writing, not drift. TODO.md keeps "The suite is at 790 checks"
      # under "## The old specification, kept for the commands" — the heading IS the date stamp, and the
      # sentence under it needs no edit. Without this, excluding the newer dated claim above merely promotes
      # the next-highest historical figure into the report, which is what happened on the first fix run.
      if ($0 ~ /^#+ /) {
        head = tolower($0)
        hist_head = (head ~ /old specification|old spec|kept for the command|superseded|archived|closed|done [0-9]|fixed earlier|no longer/) ? 1 : 0
      }
      raw = $0
      gsub(/,/, "", raw)                       # 1,127 -> 1127, and "1,101   1,127 checks" stays two numbers
      gsub(/[^A-Za-z0-9]+/, " ", raw)
      n = split(raw, w, " ")
      for (i = 1; i <= n; i++) {
        if (tolower(w[i]) == "checks" && prev ~ /^[0-9]+$/ && prev + 0 >= floor) {
          # A claim the prose itself DATES or puts in the PAST is correct writing, not drift — the same
          # doctrine this file already applies to the dated HANDOFF-<date>.md files. Test its own
          # line AND the one before it, because the claim wraps (that is why `prev`/`pline` exist at all).
          k = kind
          both = prevorig " " orig
          if (both ~ /as of|stood at|was at|were at|had been|used to|superseded|20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) k = "dated"
          if (hist_head) k = "dated"
          print label "\t" pline "\t" prev + 0 "\t" k
        }
        prev = w[i]; pline = FNR
      }
      prevorig = orig
    }
  ' "$1" >> "$CC"
}
for d in $LIVE_DOCS; do cc_scan "$ROOT/$d" "$d" live; done
for d in "$ROOT"/HANDOFF-*.md; do [ -f "$d" ] || continue; cc_scan "$d" "$(basename "$d")" dated; done

if [ -s "$CC" ]; then
  # Reference = the highest figure asserted anywhere in the pool; the file credited is the newest-modified
  # of those asserting it. `stat -f %m` is the BSD form (this is macOS-only tooling).
  REF="$(awk -F"$TAB" '{ if ($3 + 0 > m) m = $3 + 0 } END { print m + 0 }' "$CC")"
  REFSRC=""; refmt=-1
  for f in $(awk -F"$TAB" -v r="$REF" '$3 + 0 == r { print $1 }' "$CC" | sort -u); do
    m="$(stat -f %m "$ROOT/$f" 2>/dev/null)"; case "$m" in ''|*[!0-9]*) m=0 ;; esac
    if [ "$m" -gt "$refmt" ]; then refmt="$m"; REFSRC="$f"; fi
  done
  # The newest-modified doc in the pool, for the epistemic note: if it asserts LESS than the reference, say
  # so out loud rather than silently preferring one over the other.
  NEWDOC=""; newmt=-1
  for f in $(awk -F"$TAB" '{ print $1 }' "$CC" | sort -u); do
    m="$(stat -f %m "$ROOT/$f" 2>/dev/null)"; case "$m" in ''|*[!0-9]*) m=0 ;; esac
    if [ "$m" -gt "$newmt" ]; then newmt="$m"; NEWDOC="$f"; fi
  done
  NEWMAX="$(awk -F"$TAB" -v f="$NEWDOC" '$1 == f { if ($3 + 0 > m) m = $3 + 0 } END { print m + 0 }' "$CC")"
  # One finding per LIVE doc, on that doc's HIGHEST claim.
  while IFS="$TAB" read -r f line val; do
    [ -n "${f:-}" ] || continue
    [ "$val" = "$REF" ] && continue
    finding "stale" \
      "$f:$line  claims $val checks ≠ $REF checks [claimed ($REFSRC), NOT measured]" \
      "CHECK-COUNT $f $line $val $REF"
  done < <(awk -F"$TAB" '$4 == "live" { if ($3 + 0 > best[$1]) { best[$1] = $3 + 0; ln[$1] = $2 } }
                         END { for (k in best) print k "\t" ln[k] "\t" best[k] }' "$CC" | sort)
fi

# ---- check 3: register vs CLAUDE.md ----------------------------------------------------------------------
GUIDE_SCAN="$TMP/guide"; scan "$GUIDE" claude > "$GUIDE_SCAN" 2>/dev/null || true
for t in $OPEN_TAGS; do
  # Exact field equality, not a regex: a dotted tag (`A6.1`) used as a pattern would match `A611` too, and a
  # check that can silently over-match is a check that silently reports nothing.
  awk -F"$TAB" -v t="$t" '$1 == "MENTION" && $3 == t { found = 1 } END { exit(found ? 0 : 1) }' "$GUIDE_SCAN" && continue
  finding "unpaired" \
    "CLAUDE.md  never mentions $t, which is OPEN in BUGS.md" \
    "UNMENTIONED CLAUDE.md - $t"
done
# (b) named as open in a counting sentence, closed in the register. CLAUDE.md's planning paragraph and
# HANDOFF.md only — see the header for why the dated handoffs and the other docs are out of scope.
{ sed "s/^/CLAUDE.md${TAB}/" "$GUIDE_SCAN"
  [ -f "$HANDOFF" ] && scan "$HANDOFF" all 2>/dev/null | sed "s/^/HANDOFF.md${TAB}/"
} | awk -F"$TAB" '$2 == "CALLEDOPEN" { print $1 "\t" $3 "\t" $4 }' | sort -u -t"$TAB" -k3,3 -k1,1 \
  | while IFS="$TAB" read -r f line tag; do
      [ -n "${tag:-}" ] || continue
      st="$(awk -F"$TAB" -v t="$tag" '$1 == t { print $2; exit }' "$TAGS")"
      [ "$st" = "x" ] || continue
      finding "stale" \
        "$f:$line  names $tag among the open entries ≠ CLOSED in BUGS.md" \
        "CALLED-OPEN $f $line $tag"
    done

# ---- check 4: the reading-order list ---------------------------------------------------------------------
newest_date=""
for f in "$ROOT"/HANDOFF-*.md; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  d="$(printf '%s' "$b" | sed -n 's/^HANDOFF-\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\).*/\1/p')"
  [ -n "$d" ] && [ "$d" \> "$newest_date" ] && newest_date="$d"
  grep -qF "$b" "$GUIDE" && continue
  finding "unlisted" \
    "CLAUDE.md  does not list $b, which is on disk — no session will ever read it" \
    "HANDOFF-UNLISTED $b"
done
grep -oE 'HANDOFF-[0-9A-Za-z-]+\.md' "$GUIDE" 2>/dev/null | sort -u | while IFS= read -r b; do
  [ -n "$b" ] || continue
  [ -f "$ROOT/$b" ] && continue
  finding "missing" \
    "CLAUDE.md  lists $b, which does not exist — a dead link in the reading order" \
    "HANDOFF-MISSING $b"
done
# The entry point. Asserted only when CLAUDE.md actually says "is where to start"; if the wording changed,
# this check reports nothing rather than guessing which file it meant.
ep_line="$(grep -n 'is where to start' "$GUIDE" 2>/dev/null | head -1)"
if [ -n "$ep_line" ] && [ -n "$newest_date" ]; then
  ep_no="${ep_line%%:*}"
  ep_file="$(printf '%s' "${ep_line#*:}" | sed 's/is where to start.*//' \
             | grep -oE 'HANDOFF-[0-9A-Za-z-]+\.md' | tail -1)"
  if [ -n "$ep_file" ]; then
    ep_date="$(printf '%s' "$ep_file" | sed -n 's/^HANDOFF-\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\).*/\1/p')"
    if [ -n "$ep_date" ] && [ "$ep_date" != "$newest_date" ]; then
      finding "stale" \
        "CLAUDE.md:$ep_no  names $ep_file as where to start ≠ newest handoff on disk is dated $newest_date" \
        "ENTRYPOINT CLAUDE.md $ep_no $ep_file $newest_date"
    fi
  fi
fi

# ---- report ----------------------------------------------------------------------------------------------
N_FIND="$(grep -c . "$FIND" || true)"
if [ "$N_FIND" -eq 0 ]; then
  [ "$QUIET" = 1 ] || {
    echo "  ✓ staleness: $N_ENTRIES register entries, $N_OPEN open ($OPEN_LIST); every claim checked agrees"
    [ -n "${REF:-}" ] && echo "    check count: $REF everywhere — claimed (${REFSRC:-?}), NOT measured; only ./run_tests.sh can measure it"
  }
  echo "staleness: OK $N_ENTRIES entries $N_OPEN open"
  [ -n "${REF:-}" ] && echo "staleness: CHECK-COUNT-REFERENCE $REF ${REFSRC:-?} claimed-not-measured"
  exit 0
fi

echo "  ⚠ staleness: $N_FIND claim(s) in the documents disagree with the register or with each other:"
awk -F"$TAB" '{ printf "      %-9s %s\n", $1, $2 }' "$FIND"
echo "      TRUTH: $N_OPEN of $N_ENTRIES register entries are open ($OPEN_LIST). OPEN = the status does not"
echo "             begin FIXED / WONTFIX / NO DEFECT, so HALF FIXED counts as open."
if [ -n "${REF:-}" ]; then
  echo "      CHECK COUNT: the reference $REF is CLAIMED by $REFSRC, not measured — only ./run_tests.sh can"
  echo "             measure it, and this gate must never start a second suite. What is certain is that the"
  echo "             documents contradict each other, so at most one of them is current."
  if [ -n "${NEWDOC:-}" ] && [ "${NEWMAX:-0}" != "$REF" ]; then
    echo "             (The newest-modified doc, $NEWDOC, says ${NEWMAX:-?}. The highest is taken because the"
    echo "             count only rises as checks are added; if that is wrong, $REFSRC is the file to fix.)"
  fi
fi
echo "      Fix the DOCUMENTS, not this check — and fix them in the same commit as whatever moved, which is"
echo "      the rule CLAUDE.md states about itself: 'it is the only way this line has ever stayed true'."

# Machine-readable block, one finding per line, after the human report — the convention `context-budget.sh`
# sets and `_classify_red()` in the daemon reads.
awk -F"$TAB" '{ print "staleness: " $3 }' "$FIND"
[ -n "${REF:-}" ] && echo "staleness: CHECK-COUNT-REFERENCE $REF ${REFSRC:-?} claimed-not-measured"
exit 1
