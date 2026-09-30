#!/usr/bin/env python3
"""The truth-harness run's tables, from `ops/truth/run-harness.sh`'s results.tsv (QUEUE.md `truth-harness`).

    ops/truth/run-table.py <W>/results.tsv <pages-out.tsv> <docs-out.tsv>

Numbers only, no transcript text, so both tables may be committed. Per page: the old measures' verdict
(`flags`, scored against Vision's reading of the source) beside the truth's (`tflags`), the truth's split
into text (`tcopy`, `tfind`) and everything else (`tink`, `tcolour`), never merged, and a class:
`green` (both pass), `red` (both fail), `old-only` (the old measures fail, the truth passes), `truth-only`
(the reverse), `crash` (no truth row). Prints the classes by route. Until the blind re-read of
`truth-words.tsv` has run, a `tcopy` or `tfind` counts words the re-read has not yet confirmed.
"""
import sys, os, collections

PH = "page refWords leg1 leg2 inkRatio inkLum srcCol colKept find cols inside cover overInk wer prec recall splits welds echoes hyph midBreaks geom msSrc msOut flags".split()
TH = "trWords contested scored right wrong missing added splits welds hyph copyErr find order fig hand visMiss layerMiss pairs elInk elCol tflags".split()
DH = "pages bytes openMs open qpdf outline labels links annots title flags".split()
TEXT, OTHER = {"tcopy", "tfind"}, {"tink", "tcolour"}

def flags(s): return set() if s in ("-", "") else set(s.split(","))
def show(s): return ",".join(sorted(s)) or "-"

res = sys.argv[1]
here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
listing = {}
for i, line in enumerate(open(f"{here}/TRUTH-PAGES-2026-09-29.tsv", encoding="utf-8")):
    f = line.rstrip("\n").split("\t")
    if i and len(f) >= 4: listing[(f[0], f[1])] = (f[2], f[3])

pages, truth, docs, crashes, built = {}, {}, {}, {}, "?"
for line in open(res, encoding="utf-8"):
    if line.startswith("# truth-harness run"): built = line.split(",")[-1].strip()
    if line.startswith("#") or not line.strip(): continue
    f = line.rstrip("\n").split("\t")
    if f[0] == "page": pages[(f[1], f[2])] = dict(zip(PH, f[2:]))
    elif f[0] == "truth": truth[(f[1], f[2][1:])] = dict(zip(TH, f[3:]))
    elif f[0] == "doc": docs[f[1]] = dict(zip(DH, f[3:]))
    elif f[0] == "crash": crashes[(f[1], f[2])] = " ".join(f[3:])

cols = ("document page route drawn old cols truth text other class trWords contested scored wrong missing "
        "added splits welds hyph copyErr find order fig hand visMiss layerMiss elInk elCol oldFind prec inside cover").split()
out = [cols]
byroute = collections.defaultdict(collections.Counter)
perdoc = collections.defaultdict(lambda: collections.Counter())
for (doc, p), (why, route) in sorted(listing.items(), key=lambda kv: (kv[1][1], kv[0][0], int(kv[0][1]))):
    P, T = pages.get((doc, p)), truth.get((doc, p))
    old = flags(P["flags"]) if P else None
    if T is None:
        cls = "crash"
        row = [doc, p, route, why, show(old) if old is not None else "crash", P["cols"] if P else "-", "crash", "-", "-", cls] + ["-"] * (len(cols) - 10)
    else:
        tf = flags(T["tflags"])
        oldred, truthred = bool(old) if old is not None else True, bool(tf)
        cls = {(False, False): "green", (True, True): "red", (True, False): "old-only", (False, True): "truth-only"}[(oldred, truthred)]
        row = [doc, p, route, why, show(old) if old is not None else "crash", P["cols"] if P else "-", show(tf),
               show(tf & TEXT), show(tf & OTHER), cls] + [T[k] for k in
               "trWords contested scored wrong missing added splits welds hyph copyErr find order fig hand visMiss layerMiss elInk elCol".split()] + \
              [P[k] if P else "-" for k in ("find", "prec", "inside", "cover")]
        c = perdoc[doc]
        for k in ("scored", "wrong", "missing", "added"):
            try: c[k] += int(T[k])
            except ValueError: pass
        c["truthText"] += bool(tf & TEXT); c["truthOther"] += bool(tf & OTHER); c["oldRed"] += oldred
    perdoc[doc]["pages"] += 1
    byroute[route][cls] += 1
    byroute[route]["pages"] += 1
    out.append(row)

with open(sys.argv[2], "w", encoding="utf-8") as fh:
    fh.write(f"# TRUTH-RUN pages: the pipeline at {built}, default settings, each truth-set page scored by the old measures\n"
             "# and by `ux-harness --truth` on the same output. Numbers only. `text` counts words the blind re-read has not\n"
             "# yet confirmed; `other` is the element ink and colour check, no model. The judges' verdicts are not in it.\n")
    for r in out: fh.write("\t".join(r) + "\n")

dcols = "document pages oldRed truthText truthOther scored wrong missing added copyErr bytes docFlags".split()
with open(sys.argv[3], "w", encoding="utf-8") as fh:
    fh.write(f"# TRUTH-RUN documents: the pipeline at {built}; copyErr pooled over the document's truth pages; bytes is the\n"
             "# cut document's output over its source (the harness's `bytes`), docFlags the harness's document flags.\n")
    fh.write("\t".join(dcols) + "\n")
    for doc in sorted(perdoc):
        c, D = perdoc[doc], docs.get(doc, {})
        err = (c["wrong"] + c["missing"] + c["added"]) / c["scored"] if c["scored"] else 0.0
        fh.write("\t".join([doc, str(c["pages"]), str(c["oldRed"]), str(c["truthText"]), str(c["truthOther"]),
                            str(c["scored"]), str(c["wrong"]), str(c["missing"]), str(c["added"]), f"{err:.3f}",
                            D.get("bytes", "crash"), D.get("flags", "crash")]) + "\n")

print(f"route        pages  green  red  old-only  truth-only  crash   (pipeline at {built})")
tot = collections.Counter()
for route in sorted(byroute):
    c = byroute[route]; tot.update(c)
    print(f"{route:<12} {c['pages']:>5}  {c['green']:>5}  {c['red']:>3}  {c['old-only']:>8}  {c['truth-only']:>10}  {c['crash']:>5}")
print(f"{'all':<12} {tot['pages']:>5}  {tot['green']:>5}  {tot['red']:>3}  {tot['old-only']:>8}  {tot['truth-only']:>10}  {tot['crash']:>5}")
for doc, p in sorted(crashes): print(f"crash row: {doc} {p}: {crashes[(doc, p)]}")
