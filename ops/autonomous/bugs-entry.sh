#!/usr/bin/env bash
# ops/autonomous/bugs-entry.sh — ONE entry out of BUGS.md, and nothing else.
#
# WHY THIS EXISTS. `BUGS.md` is ~480 KB — roughly 120,000 tokens. A session that reads it whole spends its
# ENTIRE context orienting and has nothing left to work with, and the register is not even the thing it
# needed: it needed one entry. The resume prompt therefore tells every session to come here
# (`bugs-entry.sh <TAG>`, "never `cat BUGS.md`, never grep it whole"), and `next-item.sh` hands out tags on
# the understanding that this can turn one into its entry. That makes this file load-bearing for the daemon's
# whole read-narrowly rule, not a convenience: without it the rule is an instruction a model can quietly
# fail, and with it the cheap path is also the only path anyone documents.
#
# THE FORMAT IT PARSES, verified against the file rather than assumed (measured 2026-08-16, both this
# checkout and the primary one): 7 `## <section>` headings and 163 entries of the form
# `### <TAG> · <title> — <STATUS>`, five of the seven sections holding entries. The raw `### ` count is
# 166, and the difference is NOT three more entries — it is prose sub-headings written INSIDE entry bodies
# (`### What it costs, end to end`, `### Why this is \`WONTFIX\` rather than open — the owner's call,
# 2026-08-17`). An entry's BODY runs from its `###` line to the next `###` or `##`.
#
# ⚠️ THE STATUS IS AFTER THE **LAST** EM DASH, NOT THE FIRST. Entry titles carry em dashes of their own —
# `### C20 · \`headroom\` and \`rightLimit\` disagree about "the same line", crushing runs to sub-point
# height — FIXED` — and so do section headings (`## Correctness — loses or corrupts content`). Taking the
# first would read that title fragment as a status and classify the entry OPEN. Observed status spellings:
# FIXED (144), WONTFIX, NO DEFECT, HALF FIXED, plus qualified forms (`FIXED, third round unrun`,
# `FIXED *(was unverified; now settled by measurement)*`, `OPEN, and the campaign it asked for has now
# been run`).
#
# OPEN IS DEFINED BY EXCLUSION, and this is the load-bearing decision in the file. An entry is CLOSED iff
# its status begins `FIXED`, `WONTFIX` or `NO DEFECT`; ANYTHING ELSE IS OPEN — notably `HALF FIXED`.
# Why not a whitelist of "open" spellings: the register's own header declares the vocabulary
# `OPEN · FIXED · WONTFIX`, but `HALF FIXED` is what C24 carried for the two days it was half done, and
# the register has nothing open as of 2026-08-17. The exclusion rule stays because the vocabulary drifts. A
# whitelist would have to be taught every new coinage, and the day someone invents the next one it reports
# ZERO OPEN ENTRIES — the most confidently wrong sentence this project can print about itself. Erring toward
# OPEN costs a look at an entry; erring toward CLOSED hides work. So: exclusion, and the list of closed
# prefixes is short, stable and only ever shrinks a claim.
#   `FIXED, third round unrun` classifies CLOSED, and that is right rather than a concession: the fix
#   LANDED, and an unrun verification round is a follow-up that owes its own item. Reading it as OPEN would
#   park a shipped entry forever and would make "open" mean "not yet perfect" instead of "not yet fixed".
#
# ⚠️ TAG MATCHING IS EXACT, so `C2` cannot match `C24` or `C25` — all three exist in this register, and a
# prefix match would hand a session the wrong entry while looking like it worked. Lookup is string
# EQUALITY on the extracted tag; there is no substring path in this file at all.
#
# CONSISTENCY WITH `next-item.sh` IS DELIBERATE AND IS THE POINT. Its pass 1 extracts the same tag with the
# same anchored `^[A-Za-z0-9][A-Za-z0-9._-]*`, takes the status after the same LAST em dash, and closes on
# the same three prefixes. If the extractor and the resolver disagreed about what a tag or a status is, the
# queue would offer work whose entry cannot be found — the failure this pair of files exists to avoid.
# ONE DIVERGENCE, in the safe direction, recorded because a later reader will otherwise "fix" it: this file
# ALSO requires an entry tag to LOOK like one (`^[A-Za-z]+[0-9]+([.][0-9]+)*$` — `C24`, `R55`, `U13`, `T14`,
# `D3`, `H2`, `F1`, and the dotted `A6.1` forms in the sibling REVIEW file). That is a strict SUBSET of what
# `next-item.sh` accepts, so the two can never disagree about a real tag; it only stops prose sub-headings
# entering the entry list as tags `What` and `Why` with an OPEN status invented out of their own sentence.
# It is not hypothetical: in the primary checkout `### Why this is \`WONTFIX\` rather than open — the
# owner's call, 2026-08-17, and the arithmetic behind it` yields tag `Why`, status "the owner's call,
# 2026-08-17, …", which begins none of the three closed prefixes and is therefore OPEN. Without the shape
# rule `--list-open` would report TWO open entries there against an actual one, and `check-staleness.sh`
# counts these lines to decide whether the documents are lying — so the phantom would make the
# staleness guard itself the thing that is stale. In the resolver the same phantom is harmless (nothing can
# be `blocked-on: Why`), which is why that file can afford the looser rule and this one cannot.
#
# USAGE
#   bugs-entry.sh <TAG> [--file PATH]        print that one entry in full (heading + body)
#   bugs-entry.sh --status <TAG> [--file PATH]   print just its status, one line
#   bugs-entry.sh --list-open [--file PATH]  print `TAG<TAB>STATUS<TAB>title` for every OPEN entry
#   bugs-entry.sh --list [--file PATH]       the same, for every entry
#   Default file: $ROOT/BUGS.md, where $ROOT is this script's grandparent directory. `--file` and
#   $VISIONOCR_BUGS (the same variable `next-item.sh` reads) both override it.
#
# EXIT: 0 found / printed at least one line · 1 not found, or `--list-open` found nothing open (a real
#       state, not an error — a session may test for it) · 2 usage error, or a register with no
#       recognisable entries at all, which is surfaced rather than reported as an empty list.
#
# Read-only. Prints to stdout, never edits, never commits.
set -uo pipefail

# A backgrounded/launchd shell here has essentially no PATH — CLAUDE.md documents that `basename`, `cut` and
# `timeout` then fail silently and loops report bogus results. This runs from a `claude -p` session, from the
# health gate and from a git hook, so set it rather than inherit nothing.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# ⚠️ The sibling scripts here resolve their root from `${1:-…}`. This one CANNOT: its first positional is the
# TAG, and `bugs-entry.sh C24` would otherwise be read as a root of "C24". Same default, different door —
# `--file` (which the interface needs anyway) and $VISIONOCR_BUGS are the overrides.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUGS="${VISIONOCR_BUGS:-$ROOT/BUGS.md}"

usage() { sed -n '/^# USAGE/,/^# Read-only/p' "$0" | sed 's/^# \{0,1\}//; /^Read-only/d'; }

MODE=""; WANT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file)   BUGS="${2:-}"; shift 2 || true ;;
    --list)      MODE=list;     shift ;;
    --list-open) MODE=listopen; shift ;;
    --status)
      MODE=status; shift
      WANT="${1:-}"; [ $# -gt 0 ] && shift
      ;;
    -h|--help|help) usage; exit 0 ;;
    -*) echo "bugs-entry: unknown option '$1'" >&2; usage >&2; exit 2 ;;
    *)
      if [ -z "$MODE" ]; then MODE=entry; WANT="$1"; shift
      else echo "bugs-entry: unexpected argument '$1'" >&2; usage >&2; exit 2; fi
      ;;
  esac
done

[ -n "$MODE" ] || { usage >&2; exit 2; }
case "$MODE" in
  entry|status) [ -n "$WANT" ] || { echo "bugs-entry: $MODE needs a TAG" >&2; exit 2; } ;;
esac
[ -f "$BUGS" ] || { echo "bugs-entry: no register file at $BUGS" >&2; exit 2; }

# The parser reports its tallies on stderr (found / entries seen / lines printed) so that stdout stays pure
# — a session pipes this straight into a prompt. A temp file rather than a var, because the awk runs INSIDE a
# pipeline and a subshell cannot hand a variable back. Removed on every exit path, including a TERM.
META_F="$(mktemp -t vo-bugs-entry)" || { echo "bugs-entry: cannot make a temp file" >&2; exit 2; }
trap 'rm -f "$META_F"' EXIT

# ---- the one parser -------------------------------------------------------------------------------------
# All four modes share it, so there is exactly one definition of "an entry", "a tag" and "a status" in this
# file. Two `## `/`### ` states are tracked: whether we are inside a fenced block (a heading there is an
# EXAMPLE, not an entry — the same skip `next-item.sh` applies) and whether we are inside the wanted entry
# (a fence inside that entry's body must still be PRINTED, which is why the fence flag gates heading
# detection only).
#
# POSIX awk only: /usr/bin/awk on macOS has no 3-arg match(), so every capture goes through
# match()/RSTART/RLENGTH/substr.
awk -v mode="$MODE" -v want="$WANT" '
  function tidy(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
  # Status = everything after the LAST em dash on the heading. Walk forward, keeping the last tail seen.
  function status_of(h,   st, rest) {
    st = ""; rest = h
    while (match(rest, /—/)) { st = substr(rest, RSTART + RLENGTH); rest = st }
    gsub(/\*/, "", st)                 # `FIXED *(twice)*` -> `FIXED (twice)`
    gsub(/~/, "", st)                  # struck-through headings in the sibling REVIEW file
    return tidy(st)
  }
  function closed_of(st) { return (st ~ /^FIXED/ || st ~ /^WONTFIX/ || st ~ /^NO DEFECT/) ? 1 : 0 }
  # Title = between the tag and the LAST em dash. Cosmetic only; it is what a human reads in a list.
  # Cut on the dash rather than on the status STRING: the status has had its `*` markers stripped by then, so
  # `FIXED *(twice)*` no longer occurs literally in the heading and a string search silently keeps the whole
  # `— FIXED *(twice)*` tail in the title.
  function title_of(h, tag,   t, rest, pre, best) {
    t = substr(h, length(tag) + 1)
    sub(/^[[:space:]]*(·|-|—)[[:space:]]*/, "", t)
    rest = t; pre = ""; best = ""
    while (match(rest, /—/)) {
      best = pre substr(rest, 1, RSTART - 1)
      pre  = pre substr(rest, 1, RSTART + RLENGTH - 1)
      rest = substr(rest, RSTART + RLENGTH)
    }
    if (best != "") t = best
    gsub(/~/, "", t)
    t = tidy(t)
    if (length(t) > 120) t = substr(t, 1, 117) "..."
    return t
  }

  /^[[:space:]]*(```|~~~)/ { fence = !fence; if (inwant) print; next }
  fence                    { if (inwant) print; next }

  # A `## ` section heading ends whatever entry was being printed; it is never an entry itself.
  /^##[[:space:]]/ && !/^###/ { inwant = 0; next }

  /^###[[:space:]]/ {
    h = $0; sub(/^###[[:space:]]+/, "", h)
    sub(/^~~/, "", h)                  # the REVIEW file strikes closed findings through in place
    tag = h
    if (match(tag, /^[A-Za-z0-9][A-Za-z0-9._-]*/)) tag = substr(tag, 1, RLENGTH); else tag = ""
    # An entry tag is a letter prefix plus an integer, optionally dotted. Anything else is a prose
    # sub-heading inside an entry — see the header. It is NOT an entry, and it must not end one either.
    if (tag == "" || tag !~ /^[A-Za-z]+[0-9]+([.][0-9]+)*$/) { if (inwant) print; next }
    inwant = 0
    st = status_of(h); if (st == "") st = "(none)"
    seen_any++
    if (mode == "entry" || mode == "status") {
      if (tag == want) {                       # EXACT match: C2 is not C24
        if (found) next                        # first occurrence wins, as in next-item.sh
        found = 1
        if (mode == "status") { print st; exit }
        inwant = 1; print $0
      }
      next
    }
    if (mode == "list" || (mode == "listopen" && !closed_of(st))) {
      n_out++
      print tag "\t" st "\t" title_of(h, tag)
    }
    next
  }

  inwant { print }
  END { print "##META##\t" (found ? 1 : 0) "\t" seen_any+0 "\t" n_out+0 > "/dev/stderr" }
' "$BUGS" 2>"$META_F" | awk '
  # Trim trailing blank lines off an entry body so consecutive entries do not read as one blank-padded blob.
  /^[[:space:]]*$/ { blanks = blanks $0 "\n"; next }
  { printf "%s", blanks; blanks = ""; print }
'
META="$(cat "$META_F" 2>/dev/null)"
# Anything the parser wrote to stderr that is NOT the meta line is a real awk error and must not be swallowed.
printf '%s\n' "$META" | grep -v '^##META##' | grep -v '^$' >&2 || true
META="$(printf '%s\n' "$META" | grep '^##META##' | tail -1)"

found="$(printf '%s' "$META" | cut -f2)";  case "$found"    in ''|*[!0-9]*) found=0 ;;    esac
entries="$(printf '%s' "$META" | cut -f3)"; case "$entries" in ''|*[!0-9]*) entries=0 ;;  esac
listed="$(printf '%s' "$META" | cut -f4)";  case "$listed"   in ''|*[!0-9]*) listed=0 ;;   esac

# A register with no recognisable entries is a WRONG FILE, not an empty one — the same distinction
# `next-item.sh` draws between a drained queue and an unparseable one. Never report it as "nothing found".
if [ "$entries" -eq 0 ]; then
  echo "bugs-entry: $BUGS has no recognisable '### <TAG> · <title> — <STATUS>' entries — is it the right file?" >&2
  exit 2
fi

case "$MODE" in
  entry|status)
    [ "$found" -eq 1 ] && exit 0
    echo "bugs-entry: no entry tagged '$WANT' in $BUGS ($entries entries scanned)." >&2
    echo "            Tags are exact — 'C2' is not 'C24'. List them:  $0 --list" >&2
    exit 1 ;;
  list)
    [ "$listed" -gt 0 ] && exit 0
    exit 2 ;;   # unreachable in practice: $entries>0 means list printed something
  listopen)
    [ "$listed" -gt 0 ] && exit 0
    # Not an error. Say it on stderr so a session that ran this to ask "what is open?" gets an answer
    # rather than silence, and keep stdout empty so a counting caller reads 0.
    echo "bugs-entry: nothing OPEN in $BUGS ($entries entries scanned; CLOSED = status begins FIXED/WONTFIX/NO DEFECT)." >&2
    exit 1 ;;
esac
