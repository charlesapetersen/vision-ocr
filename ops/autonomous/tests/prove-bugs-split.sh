#!/usr/bin/env bash
# prove-bugs-split.sh — an entry may live in `bugs/<TAG>.md`, with `BUGS.md` holding its heading line as an index
# (QUEUE.md bugs-split, sub-box bs-readers). Fixtures only: its own mktemp register and git repo; it never reads
# the real `BUGS.md`, runs the suite or commits anywhere but its sandbox.
#
# WHAT IT PROVES
#   [1] `bugs-entry.sh` prints the same entry, status and lists for a register whose entries are inline and for
#       the same register with two of them moved to files;
#   [2] a mutant `bugs-entry.sh` that reads only `BUGS.md` turns [1] red; [2b] an empty entry file exits 2, and
#       a body left under an index line whose file exists is reported on stderr;
#   [3] the pre-commit hook's rule-8 check refuses, in an unattended session below max effort, a WONTFIX close
#       written inline in `BUGS.md`, and one written in an entry's file, with or without its index line; it lets
#       a move of an already-WONTFIX entry into its file through; it lets the second max-effort session close;
#   [4] a mutant hook that reads only `BUGS.md` lets the file-only close through, so [3] goes red.
# USAGE:  ops/autonomous/tests/prove-bugs-split.sh
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

HERE="$(cd "$(dirname "$0")" && pwd)"
RESOLVER="$HERE/../bugs-entry.sh"
HOOK="$HERE/../../../.githooks/pre-commit"
T="$(mktemp -d -t vo-bugs-split)" || exit 2
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

# ---- fixtures: one register inline, the same register split ------------------------------------------------
# C24's body holds a fence with a heading-shaped line and a prose sub-heading, the two things the parser must
# not end an entry on; C2 is a prefix of C24 and is closed WONTFIX.
entry_c1() { printf '%s\n' '### C1 · first — OPEN' '' 'Body of C1.' ''; }
entry_c2() { printf '%s\n' '### C2 · prefix of C24 — WONTFIX' '' 'Body of C2.' ''; }
entry_c24() {
  printf '%s\n' '### C24 · title — with a dash — FIXED *(twice)*' '' 'First paragraph.' '' \
    '```' '### C99 · inside a fence — OPEN' '```' '' '### What it costs, end to end' '' 'Last line.' ''
}
mkdir -p "$T/inline" "$T/split/bugs"
{ printf '%s\n' '# Register' '' '## Correctness — loses content' ''; entry_c1; entry_c24; entry_c2
  printf '%s\n' '## Other' '' '### T1 · last — FIXED' '' 'Body of T1.'; } > "$T/inline/BUGS.md"
{ printf '%s\n' '# Register' '' '## Correctness — loses content' ''; entry_c1
  entry_c24 | head -1; echo; entry_c2 | head -1; echo
  printf '%s\n' '## Other' '' '### T1 · last — FIXED' '' 'Body of T1.'; } > "$T/split/BUGS.md"
entry_c24 > "$T/split/bugs/C24.md"
entry_c2  > "$T/split/bugs/C2.md"

same_reads() {   # $1 resolver; prints the first query on which the two registers disagree
  for q in "C24" "C2" "C1" "T1" "--status C24" "--status C2" "--list" "--list-open"; do
    # shellcheck disable=SC2086
    a="$(bash "$1" $q --file "$T/inline/BUGS.md" 2>&1; echo "exit $?")"
    # shellcheck disable=SC2086
    b="$(bash "$1" $q --file "$T/split/BUGS.md" 2>&1; echo "exit $?")"
    [ "$a" = "$b" ] || { echo "$q"; return; }
  done
}

echo "[1] the resolver reads an entry moved to its file the same"
d="$(same_reads "$RESOLVER")"
[ -z "$d" ] && ok "inline and split registers agree on 8 queries" || bad "they disagree on '$d'"
out="$(bash "$RESOLVER" C24 --file "$T/split/BUGS.md")"
case "$out" in *"Last line."*) ok "C24 is printed from bugs/C24.md, through its fence and sub-heading" ;;
  *) bad "C24 from the split register lacks its body: $out" ;; esac

echo "[2] a resolver that reads only BUGS.md goes red"
sed 's/if ((getline line < ef) > 0) {/if (0) {/' "$RESOLVER" > "$T/mutant-resolver.sh"
cmp -s "$RESOLVER" "$T/mutant-resolver.sh" && bad "the mutation did not apply"
d="$(same_reads "$T/mutant-resolver.sh")"
[ -n "$d" ] && ok "the mutant disagrees, first on '$d'" || bad "the mutant reads the same: the fixture is blind"

echo "[2b] a broken move is reported, not read as an entry"
cp -R "$T/split" "$T/broken"; : > "$T/broken/bugs/C24.md"
bash "$RESOLVER" C24 --file "$T/broken/BUGS.md" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "an empty bugs/C24.md exits 2" || bad "an empty entry file exited $rc"
cp "$T/split/bugs/C24.md" "$T/broken/bugs/C24.md"; cp "$T/inline/BUGS.md" "$T/broken/BUGS.md"
err="$(bash "$RESOLVER" C24 --file "$T/broken/BUGS.md" 2>&1 >/dev/null)"
case "$err" in *"still holds"*) ok "a body left under the index line is reported" ;;
  *) bad "a leftover inline body was dropped silently: '$err'" ;; esac

# ---- the hook's rule-8 check ------------------------------------------------------------------------------
R="$T/repo"; mkdir -p "$R/.githooks"
git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t
cp "$T/inline/BUGS.md" "$R/BUGS.md"
git -C "$R" add -A && git -C "$R" commit -qm start --no-verify
export VISIONOCR_STATE="$T/state"; mkdir -p "$VISIONOCR_STATE"; : > "$VISIONOCR_STATE/attempts.tsv"
export VISIONOCR_HEAD_ITEM=bugs-split
hook_says() {    # $1 hook, $2 effort: prints refused or allowed for what is staged in $R
  # Refused means the rule-8 message, not any non-zero exit: a hook that crashes must not pass as refusing.
  if out="$(cd "$R" && VISIONOCR_UNATTENDED=1 VISIONOCR_SESSION_EFFORT="$2" bash "$1" 2>&1)"; then echo allowed
  else case "$out" in *"QUEUE.md rule 8"*) echo refused ;; *) echo "crashed: $out" ;; esac; fi
}

echo "[3] the hook's rule-8 check reads the entry file"
sed 's/^### C1 · first — OPEN$/### C1 · first — WONTFIX/' "$T/inline/BUGS.md" > "$R/BUGS.md"; git -C "$R" add -A
[ "$(hook_says "$HOOK" medium)" = refused ] && ok "an inline WONTFIX close in BUGS.md is still refused" \
  || bad "an inline WONTFIX close went through"
# The move commit: C2 (already WONTFIX) and C24 go to their files, BUGS.md becomes the index.
cp "$T/split/BUGS.md" "$R/BUGS.md"; mkdir -p "$R/bugs"; cp "$T/split/bugs/"*.md "$R/bugs/"
git -C "$R" add -A
[ "$(hook_says "$HOOK" medium)" = allowed ] && ok "moving a WONTFIX entry into its file is not a close" \
  || bad "the move of an already-WONTFIX entry was refused"
git -C "$R" commit -qm move --no-verify
sed -i '' '1s/— FIXED \*(twice)\*$/— WONTFIX/' "$R/bugs/C24.md"; git -C "$R" add -A
[ "$(hook_says "$HOOK" medium)" = refused ] && ok "a WONTFIX close written only in bugs/C24.md is refused" \
  || bad "a file-only WONTFIX close went through"
sed -i '' 's/^### C24 · title — with a dash — FIXED \*(twice)\*$/### C24 · title — with a dash — WONTFIX/' "$R/BUGS.md"
git -C "$R" add -A
[ "$(hook_says "$HOOK" medium)" = refused ] && ok "the same close in file and index is refused" \
  || bad "a file-and-index WONTFIX close went through"
printf 'bugs-split\t2026-10-14 04:00\tmax\t60\n' > "$VISIONOCR_STATE/attempts.tsv"
[ "$(hook_says "$HOOK" max)" = allowed ] && ok "the second max-effort session may close" \
  || bad "the second max-effort session was refused"
: > "$VISIONOCR_STATE/attempts.tsv"

echo "[4] a hook that reads only BUGS.md goes red"
git -C "$R" show HEAD:BUGS.md > "$R/BUGS.md"; git -C "$R" add -A   # back to the file-only close
sed 's|-- BUGS.md bugs/ |-- BUGS.md |' "$HOOK" > "$T/mutant-hook"
cmp -s "$HOOK" "$T/mutant-hook" && bad "the hook mutation did not apply"
[ "$(hook_says "$T/mutant-hook" medium)" = allowed ] \
  && ok "the mutant lets the file-only close through, so [3] would be red" \
  || bad "the mutant still refuses: [3] cannot tell it from the real hook"

echo "prove-bugs-split: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
