#!/bin/bash
# The `truth-harness` run: publish every truth-set page with this checkout and score it with
# `ux-harness --truth`, the old measures beside it on the same output (QUEUE.md `truth-harness`).
#
#   ops/truth/run-harness.sh <W>
#
# Each document in TRUTH-PAGES-2026-09-29.tsv is cut to its listed pages (`qpdf --empty --pages`, which
# `ops/ux-regression/set.tsv` measured equal to a whole-document run), published by `Tools/score-gate` at
# default settings, and scored by `Tools/ux-regression.sh --score-one`, so W is laid out as that script
# lays it out (in/ pub/ score/). Publishing runs in chunks of 16 documents, each into an empty directory
# as the gate requires, and a document is scored as soon as its chunk is out, one harness at a time.
# Rerun with the same W to resume: a scored document (`score/d<N>.done`) is skipped, and a half-scored
# one is scored again from nothing. `results.tsv` at the end holds every row, in ux-regression's format.
# Runs the pipeline and PDFKit: run it alone, never beside a suite. Exit: 0 done · 2 could not run.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIST="$ROOT/TRUTH-PAGES-2026-09-29.tsv"
STATE="${VISIONOCR_STATE:-$HOME/.local/state/visionocr-autonomous}"
OWNER="$STATE/owner-supplied"
TD="${VISIONOCR_TESTDOCS:-$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir)/.." && pwd)/testdocs}"
W="${1:-}"
[ -n "$W" ] || { echo "usage: ops/truth/run-harness.sh <W>"; exit 2; }
[ -d "$TD/book" ] && [ -d "$OWNER" ] || { echo "run-harness: no corpus at $TD or no $OWNER"; exit 2; }
mkdir -p "$W/in" "$W/pub" "$W/score" "$W/g" "$W/h"

if [ ! -x "$W/ux" ]; then
    cp "$ROOT/Tools/score-gate.swift" "$W/g/main.swift"
    cp "$ROOT/Tools/ux-harness.swift" "$W/h/main.swift"
    ( cd "$ROOT" && T="$(uname -m)-apple-macos13.0" &&
      swiftc -O -o "$W/gate" -target "$T" $(ls Sources/*.swift | grep -v App.swift) "$W/g/main.swift" &&
      swiftc -O -o "$W/visionocr-recognise" -target "$T" \
          Sources/{Prefs,Runner,Recogniser,SearchableWriter,Flattener,JBIG2}.swift Helper/main.swift &&
      swiftc -O -o "$W/ux" "$W/h/main.swift" ) > "$W/build.log" 2>&1 ||
        { rm -f "$W/ux"; echo "run-harness: the tools do not build, see $W/build.log"; exit 2; }
    ( cd "$ROOT" && git rev-parse --short HEAD ) > "$W/built-at.txt"
fi

# jobs.txt: one line per document, numbered in the list's order, pages ascending; written once, so a
# resumed run keeps the numbering
if [ ! -s "$W/jobs.txt" ]; then
    /usr/bin/python3 - "$LIST" "$W" > "$W/jobs.txt" <<'PY' || { rm -f "$W/jobs.txt"; exit 2; }
import sys
docs = {}
for i, line in enumerate(open(sys.argv[1], encoding="utf-8")):
    f = line.rstrip("\n").split("\t")
    if i == 0 or len(f) < 2: continue
    docs.setdefault(f[0], set()).add(int(f[1]))
for n, (src, pages) in enumerate(docs.items(), 1):
    print("\t".join([sys.argv[2], str(n), src, "pages", ",".join(map(str, sorted(pages)))]))
PY
fi

total=$(/usr/bin/wc -l < "$W/jobs.txt" | tr -d ' ')
echo "run-harness: $total documents into $W, built at $(cat "$W/built-at.txt")"
chunk=16 k=0
while [ $((k * chunk)) -lt "$total" ]; do
    first=$((k * chunk + 1)) last=$(((k + 1) * chunk)); k=$((k + 1))
    todo=()
    while IFS=$'\t' read -r _ n source mode pages; do
        [ "$n" -ge "$first" ] && [ "$n" -le "$last" ] || continue
        [ -f "$W/score/d$n.done" ] && continue
        todo+=("$n")
        [ -f "$W/in/d$n.pdf" ] && continue
        case "$source" in owner/*) src="$OWNER/${source#owner/}";; *) src="$TD/$source";; esac
        [ -f "$src" ] || { echo "run-harness: $source is not at $src"; exit 2; }
        qpdf --empty --pages "$src" "$pages" -- "$W/in/d$n.pdf" 2> "$W/in/d$n.qpdf.txt"
        q=$?   # 3 is warnings only
        [ $q = 0 ] || [ $q = 3 ] || { rm -f "$W/in/d$n.pdf"; echo "run-harness: qpdf could not cut $source (exit $q)"; exit 2; }
    done < "$W/jobs.txt"
    [ ${#todo[@]} -gt 0 ] || continue
    # publish what this chunk has not published yet
    rm -rf "$W/chunk"; mkdir -p "$W/chunk/in" "$W/chunk/out"
    for n in "${todo[@]}"; do [ -f "$W/pub/d$n.ocr.pdf" ] || cp "$W/in/d$n.pdf" "$W/chunk/in/"; done
    if [ -n "$(ls -A "$W/chunk/in")" ]; then
        t0=$(date +%s)
        VISIONOCR_HELPER="$W/visionocr-recognise" "$W/gate" "$W/chunk/in" "$W/chunk/out" > "$W/gate-c$k.log" 2>&1
        g=$?   # 1 is the gate's own hard checks failing, which is a result
        echo "run-harness: chunk $k published in $(( $(date +%s) - t0 )) s, gate exit $g"
        printf 'gate\tscore-gate\tc%s\texit %s\n' "$k" "$g" > "$W/score/gate-c$k.rows"
        for f in "$W/chunk/out"/*.ocr.pdf; do [ -f "$f" ] && mv "$f" "$W/pub/"; done
    fi
    for n in "${todo[@]}"; do
        line="$(awk -F'\t' -v n="$n" '$2 == n' "$W/jobs.txt")"
        source="$(echo "$line" | cut -f3)" pages="$(echo "$line" | cut -f5)"
        # a half-scored document again from nothing: --score-one's `ln -s` into an existing link would
        # write inside the truth set
        rm -rf "$W/score/d$n" "$W/score/d$n.rows"
        t0=$(date +%s)
        "$ROOT/Tools/ux-regression.sh" --score-one "$W" "$n" "$source" pages "$pages"
        echo "$(( $(date +%s) - t0 ))" > "$W/score/d$n.done"
    done
    echo "run-harness: chunk $k scored ($(ls "$W/score"/*.done | /usr/bin/wc -l | tr -d ' ') of $total documents)"
done
rm -rf "$W/chunk"
{ printf '# truth-harness run %s, %s\n' "$(date +%Y-%m-%d)" "$(cat "$W/built-at.txt")"
  printf 'kind\tsource\tpage\t...\n'
  cat "$W/score"/gate-c*.rows 2>/dev/null
  n=0; while [ $n -lt "$total" ]; do n=$((n + 1)); cat "$W/score/d$n.rows"; done; } > "$W/results.tsv"
echo "run-harness: results $W/results.tsv"
