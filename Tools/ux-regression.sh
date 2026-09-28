#!/bin/bash
# Is the app's output on the regression set no worse than the baseline, on any measure?
#
#   Tools/ux-regression.sh [--out DIR]              publish the set with this checkout, score, compare
#   Tools/ux-regression.sh --baseline [--out DIR]   the same, print the comparison, then write
#                                                   ops/ux-regression/baseline.tsv whatever it says
#   Tools/ux-regression.sh --compare RESULTS.tsv    compare an existing results file with the baseline
# DIR must be new or empty: an earlier run's outputs left in it would be scored as this checkout's.
#
# The set is `ops/ux-regression/set.tsv`: the owner's reported pages, one page per defect class and a few
# per route (QUEUE.md rule 9). This builds `Tools/score-gate`, the helper and `Tools/ux-harness` from this
# checkout, publishes every document in the set through the production pipeline, scores the named pages
# with the harness, each document in its own process (a crash is a result, not an abort), and compares
# every column with the baseline. About 5 minutes; it runs the pipeline, so run it alone, never beside a
# suite.
#
# A page is WORSE when it gains a red flag, loses its row, or a measure moves the wrong way past its
# tolerance: 0.02 on the shares (leg1 leg2 colKept find inside cover overInk prec recall wer and the
# midBreaks share; inkRatio's distance from 1.00, since above 1 is strokes filled in), 3 on inkLum, 0 on
# the counts (splits welds echoes, hyph's kept joins), and `geom` leaving `ok`. A document is WORSE when
# its output grows more than 2%, keeps fewer pages, outline entries, links or annotations, or gains a
# document flag. A page or document that crashes the harness is WORSE, and one that already crashed is
# WORSE if it now crashes differently (it no longer publishes, say); so is the gate exiting differently.
# `cols` is reported when it changes and never counts either way. Timings are ignored. Vision is
# deterministic here: a second run on unchanged code read 0 worse, 0 better (2026-09-28). The harness's own blind spots stand (see the queue item
# `ux-regression-set`): legibility is unreliable, `find` strips punctuation, `echoes` cannot see C44.
#
# Needs the owner's files in $STATE/owner-supplied/ and the corpus in testdocs/ (the primary checkout's,
# found through git, when this is a worktree; VISIONOCR_TESTDOCS overrides).
# Exit: 0 no worse · 1 something worse · 2 could not run · 3 skipped (the owner's files or corpus absent).
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SET="$ROOT/ops/ux-regression/set.tsv"
BASE="$ROOT/ops/ux-regression/baseline.tsv"
STATE="${VISIONOCR_STATE:-$HOME/.local/state/visionocr-autonomous}"
OWNER="$STATE/owner-supplied"
TD="${VISIONOCR_TESTDOCS:-$(cd "$ROOT" && cd "$(git rev-parse --git-common-dir)/.." && pwd)/testdocs}"

# compare <baseline> <results>: prints WORSE / better / changed lines, exits 1 on any WORSE
compare() {
    /usr/bin/python3 - "$1" "$2" <<'PY'
import sys, os, traceback
def die(t, v, tb): traceback.print_exception(t, v, tb); sys.stderr.flush(); os._exit(2)
sys.excepthook = die   # a malformed file is "could not run", never "worse"
def load(p):
    rows = {}
    for line in open(p, encoding="utf-8"):
        if line.startswith("#") or not line.strip(): continue
        f = line.rstrip("\n").split("\t")
        if f[0] == "kind": continue
        rows[(f[1], f[2])] = f
    return rows
base, new = load(sys.argv[1]), load(sys.argv[2])
PH = "page refWords leg1 leg2 inkRatio inkLum srcCol colKept find cols inside cover overInk wer prec recall splits welds echoes hyph midBreaks geom msSrc msOut flags".split()
DH = "pages bytes openMs open qpdf outline labels links annots title flags".split()
def num(s):
    try: return float(s)
    except ValueError: return None
def frac(s, share):
    a, _, b = s.partition("/")
    try: a, b = float(a), float(b)
    except ValueError: return None
    return (a / b if b else 0.0) if share else a
def flags(s): return set() if s in ("-", "") else set(s.split(","))
worse, notes = [], []
def say(bad, where, what, o, n):
    (worse if bad else notes).append(("WORSE  " if bad else "better ") + f"{where}  {what}  {o} -> {n}")
for key, b in sorted(base.items()):
    where = {"DOC": f"{key[0]} (document)", "-": key[0]}.get(key[1], f"{key[0]} p{key[1]}")
    n = new.get(key)
    if n is None: worse.append(f"WORSE  {where}  no row in the results"); continue
    if len(n) != len(b) and n[0] == b[0]:
        worse.append(f"WORSE  {where}  the row has {len(n)} fields, the baseline's {len(b)}"); continue
    if b[0] != n[0]:
        (worse if n[0] == "crash" else notes).append(
            ("WORSE  " if n[0] == "crash" else "better ") + f"{where}  was {b[0]}, now {n[0]}  {' '.join(n[3:]) if n[0] == 'crash' else ''}")
        continue
    if b[0] in ("crash", "gate"):
        # a crash that crashes differently, or a gate that exits differently, is not known to be better
        if b[3:] != n[3:]: worse.append(f"WORSE  {where}  {' '.join(b[3:])} -> {' '.join(n[3:])}")
        continue
    if b[0] == "page":
        B, N = dict(zip(PH, b[2:])), dict(zip(PH, n[2:]))
        for m in "leg1 leg2 colKept find inside cover overInk prec recall".split():
            o, v = num(B[m]), num(N[m])
            if o is not None and v is None: say(True, where, m, B[m], N[m])
            elif o is not None and abs(v - o) > 0.02 + 1e-9: say(v < o, where, m, B[m], N[m])
        o, v = num(B["inkRatio"]), num(N["inkRatio"])  # 1.00 = as solid as the source; above is filled in
        if o is not None and v is None: say(True, where, "inkRatio", B["inkRatio"], N["inkRatio"])
        elif o is not None and abs(abs(v - 1) - abs(o - 1)) > 0.02 + 1e-9:
            say(abs(v - 1) > abs(o - 1), where, "inkRatio", B["inkRatio"], N["inkRatio"])
        for m, tol in (("wer", 0.02), ("inkLum", 3), ("splits", 0), ("welds", 0), ("echoes", 0)):
            o, v = num(B[m]), num(N[m])
            if o is not None and v is None: say(True, where, m, B[m], N[m])
            elif o is not None and abs(v - o) > tol + 1e-9: say(v > o, where, m, B[m], N[m])
        for m, share, tol in (("hyph", False, 0), ("midBreaks", True, 0.02)):
            o, v = frac(B[m], share), frac(N[m], share)
            if o is not None and v is not None and abs(v - o) > tol + 1e-9: say(v > o, where, m, B[m], N[m])
        if B["geom"] != N["geom"]: say(B["geom"] == "ok", where, "geom", B["geom"], N["geom"])
        if B["cols"] != N["cols"]: notes.append(f"changed {where}  cols  {B['cols']} -> {N['cols']}")
        gained, lost = flags(N["flags"]) - flags(B["flags"]), flags(B["flags"]) - flags(N["flags"])
        if gained: say(True, where, "flags", B["flags"], N["flags"])
        elif lost: say(False, where, "flags", B["flags"], N["flags"])
    else:
        B, N = dict(zip(DH, b[3:])), dict(zip(DH, n[3:]))
        def out(s):
            try: return float(s.split(">")[1])
            except (IndexError, ValueError): return None
        o, v = out(B["bytes"]), out(N["bytes"])
        if o and v is not None and abs(v - o) > 0.02 * o: say(v > o, where, "bytes", B["bytes"], N["bytes"])
        for m in "pages outline links annots".split():
            o, v = out(B[m]), out(N[m])
            if o is not None and v is not None and v != o: say(v < o, where, m, B[m], N[m])
        for m, good in (("open", "yes"), ("qpdf", "clean"), ("labels", "same"), ("title", "same")):
            if B[m] != N[m]: say(N[m] != good, where, m, B[m], N[m])
        gained, lost = flags(N["flags"]) - flags(B["flags"]), flags(B["flags"]) - flags(N["flags"])
        if gained: say(True, where, "flags", B["flags"], N["flags"])
        elif lost: say(False, where, "flags", B["flags"], N["flags"])
for key in sorted(set(new) - set(base)):
    notes.append(f"new    {key[0]} p{key[1]}  not in the baseline")
for l in notes + worse: print(l)
pages = sum(1 for k, v in base.items() if k[1] not in ("DOC", "-"))
docs = sum(1 for k, v in base.items() if k[1] == "DOC")
print(f"ux-regression: {len(worse)} worse, {sum(1 for l in notes if l.startswith('better'))} better, over {pages} pages and {docs} documents")
sys.exit(1 if worse else 0)
PY
    local rc=$?
    [ $rc -le 1 ] || { echo "ux-regression: the compare failed (exit $rc)"; return 2; }
    return $rc
}

MODE=check OUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --baseline) MODE=baseline;;
        --out) OUT="${2:-}"; [ -n "$OUT" ] || { echo "ux-regression: --out needs a directory"; exit 2; }; shift;;
        --compare) [ -f "$BASE" ] || { echo "ux-regression: no baseline at $BASE"; exit 2; }
                   [ -f "${2:-}" ] || { echo "ux-regression: no results file '${2:-}'"; exit 2; }
                   compare "$BASE" "$2"; exit $?;;
        --score-one) shift; MODE=score-one; break;;
        *) echo "usage: Tools/ux-regression.sh [--baseline] [--out DIR] | --compare RESULTS.tsv"; exit 2;;
    esac
    shift
done

# --score-one <W> <n> <source-label> <mode> <pages>: one document, in its own process
if [ "$MODE" = score-one ]; then
    W="$1" n="$2" label="$3" mode="$4" pages="$5"
    src="$W/in/d$n.pdf" out="$W/pub/d$n.ocr.pdf" d="$W/score/d$n" rows="$W/score/d$n.rows"
    mkdir -p "$d"
    list="$pages"
    [ "$mode" = pages ] && list="$(seq 1 "$(echo "$pages" | tr ',' '\n' | /usr/bin/wc -l | tr -d ' ')" | paste -sd, -)"
    rc=0
    if [ -f "$out" ]; then "$W/ux" "$src" "$out" "$d" "$list" > "$d/stdout.tsv" 2> "$d/stderr.txt" || rc=$?
    else rc=noout; fi
    : > "$rows"
    i=0
    for p in $(echo "$pages" | tr ',' ' '); do
        i=$((i + 1)); q="$p"; [ "$mode" = pages ] && q="$i"
        row="$(awk -F'\t' -v q="$q" 'NR > 1 && $1 == q' "$d/pages.tsv" 2>/dev/null)"
        if [ -n "$row" ]; then printf 'page\t%s\t%s\t%s\n' "$label" "$p" "$(echo "$row" | cut -f2-)" >> "$rows"
        else printf 'crash\t%s\t%s\tharness exit %s, no row\n' "$label" "$p" "$rc" >> "$rows"; fi
    done
    row="$(sed -n 2p "$d/document.tsv" 2>/dev/null)"
    if [ -n "$row" ]; then printf 'doc\t%s\tDOC\t%s\n' "$label" "$row" >> "$rows"
    else printf 'crash\t%s\tDOC\tharness exit %s, no document row\n' "$label" "$rc" >> "$rows"; fi
    exit 0
fi

[ -f "$OWNER/1954 - Why.pdf" ] || { echo "ux-regression: SKIP, the owner's files are not in $OWNER"; exit 3; }
[ -d "$TD/book" ] || { echo "ux-regression: SKIP, no corpus at $TD"; exit 3; }
W="${OUT:-$(mktemp -d /tmp/ux-regression.XXXXXX)}"
# a directory holding an earlier run would have its outputs scored as this checkout's
[ -z "$(ls -A "$W" 2>/dev/null)" ] || { echo "ux-regression: $W is not empty"; exit 2; }
mkdir -p "$W/in" "$W/pub" "$W/score" "$W/g" "$W/h"
cp "$ROOT/Tools/score-gate.swift" "$W/g/main.swift"
cp "$ROOT/Tools/ux-harness.swift" "$W/h/main.swift"
( cd "$ROOT" && T="$(uname -m)-apple-macos13.0" &&
  swiftc -O -o "$W/gate" -target "$T" $(ls Sources/*.swift | grep -v App.swift) "$W/g/main.swift" &&
  swiftc -O -o "$W/visionocr-recognise" -target "$T" \
      Sources/{Prefs,Runner,Recogniser,SearchableWriter,Flattener,JBIG2}.swift Helper/main.swift &&
  swiftc -O -o "$W/ux" "$W/h/main.swift" ) > "$W/build.log" 2>&1 ||
    { echo "ux-regression: the tools do not build, see $W/build.log"; exit 2; }

# the inputs, as d<N>.pdf in set order; jobs.txt carries what --score-one needs
: > "$W/jobs.txt"
n=0
while IFS=$'\t' read -r source pages mode why; do
    case "$source" in ''|'#'*) continue;; esac
    n=$((n + 1))
    case "$source" in owner/*) src="$OWNER/${source#owner/}";; *) src="$TD/$source";; esac
    [ -f "$src" ] || { echo "ux-regression: $source is not at $src"; exit 2; }
    if [ "$mode" = pages ]; then
        qpdf --empty --pages "$src" "$pages" -- "$W/in/d$n.pdf" 2> "$W/in/d$n.qpdf.txt"
        q=$?   # 3 is warnings only
        [ $q = 0 ] || [ $q = 3 ] || { echo "ux-regression: qpdf could not cut $source (exit $q)"; exit 2; }
    else cp "$src" "$W/in/d$n.pdf"; fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$W" "$n" "$source" "$mode" "$pages" >> "$W/jobs.txt"
done < "$SET"

echo "ux-regression: publishing $n documents into $W/pub"
VISIONOCR_HELPER="$W/visionocr-recognise" "$W/gate" "$W/in" "$W/pub" > "$W/gate.log" 2>&1
g=$?   # 1 is the gate's own hard checks failing, which is a result; anything else is a failed run
[ $g -le 1 ] || { echo "ux-regression: the gate exited $g, see $W/gate.log"; exit 2; }
echo "ux-regression: scoring"
tr '\t\n' '\0\0' < "$W/jobs.txt" | xargs -0 -n 5 -P 4 "$0" --score-one
{ printf '# ux-regression results %s, %s\n' "$(date +%Y-%m-%d)" "$(cd "$ROOT" && git rev-parse --short HEAD)"
  printf 'kind\tsource\tpage\t...\n'
  printf 'gate\tscore-gate\t-\texit %s\n' "$g"
  i=0; while [ $i -lt $n ]; do i=$((i + 1)); cat "$W/score/d$i.rows"; done; } > "$W/results.tsv"
echo "ux-regression: results $W/results.tsv"
rc=0
if [ -f "$BASE" ]; then compare "$BASE" "$W/results.tsv"; rc=$?
else echo "ux-regression: no baseline at $BASE"; rc=2; fi
if [ "$MODE" = baseline ]; then
    # printed above first, so a regression is never absorbed into the new baseline unseen
    cp "$W/results.tsv" "$BASE"; echo "ux-regression: baseline written to $BASE"
    /usr/bin/grep -c '^crash' "$BASE" | xargs echo "ux-regression: crash rows:"
    exit 0
fi
exit $rc
