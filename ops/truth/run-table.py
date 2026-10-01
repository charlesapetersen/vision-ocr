#!/usr/bin/env python3
"""The truth-harness run's tables, from `ops/truth/run-harness.sh`'s results.tsv (QUEUE.md `truth-harness`).

    ops/truth/run-table.py <results.tsv> <pages-out.tsv> <docs-out.tsv> [<W>]

Numbers only, no transcript text, so both tables may be committed. Per page: the old measures' verdict
(`flags`, scored against Vision's reading of the source) beside the truth's, never merged: `text`
(`tcopy`, `tfind`), `other` (`tink`, `tcolour`, the element check, no model) and `judge` (`worse` when a
blind judge found the output worse than the source on some crop pair). A class: `green` (both pass), `red`
(both fail), `old-only` (the old measures fail, the truth passes), `truth-only` (the reverse), `crash` (no
truth row). With <W>, the run directory, the tables also carry the blind re-read (`reread.py`: rows of
`truth-words.tsv` re-read, confirmed, and contested, which the scoring then left out; `unread` rows were
not re-read, on pages red on copy whatever a re-read finds) and the judges (`judge.py`: pairs identical,
judged, and the output's verdicts and kinds of loss). Without a re-read, a `tcopy` or `tfind` counts words
nobody has confirmed. Prints the classes by route.
"""
import sys, os, collections

PH = "page refWords leg1 leg2 inkRatio inkLum srcCol colKept find cols inside cover overInk wer prec recall splits welds echoes hyph midBreaks geom msSrc msOut flags".split()
TH = "trWords contested scored right wrong missing added splits welds hyph copyErr find order fig hand visMiss layerMiss pairs elInk elCol tflags".split()
DH = "pages bytes openMs open qpdf outline labels links annots title flags".split()
TEXT, OTHER = {"tcopy", "tfind"}, {"tink", "tcolour"}
RR = ["reread", "confirmed", "rrContested", "unread"]
JG = ["identical", "judged", "same", "worse", "better", "both", "out-missing", "out-faded", "out-harder", "out-colour", "rejudged"]

def flags(s): return set() if s in ("-", "") else set(s.split(","))
def show(s): return ",".join(sorted(s)) or "-"

def tsv(path):
    rows = [l.rstrip("\n").split("\t") for l in open(path, encoding="utf-8")]
    return [dict(zip(rows[0], r)) for r in rows[1:]]

res = sys.argv[1]
W = sys.argv[4].rstrip("/") if len(sys.argv) > 4 else None
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

# the re-read and the judges, keyed by (document, page in the source)
rr, jg = collections.defaultdict(collections.Counter), {}
if W:
    job = {}
    for line in open(f"{W}/jobs.txt", encoding="utf-8"):
        f = line.rstrip("\n").split("\t"); job[f"d{f[1]}"] = (f[2], f[4].split(","))
    if os.path.exists(f"{W}/reread/log.tsv"):
        for r in tsv(f"{W}/reread/select.tsv"):
            if r["reread"] == "no": rr[(job[r["d"]][0], r["orig"])]["unread"] += 1
        for r in tsv(f"{W}/reread/log.tsv"):
            c = rr[(job[r["d"]][0], r["orig"])]; c["reread"] += 1
            c["confirmed" if r["verdict"] == "confirmed" else "rrContested"] += 1
    if os.path.exists(f"{W}/judge/pages.tsv"):
        for r in tsv(f"{W}/judge/pages.tsv"):
            if r["doc"].startswith("ctrl:"): continue
            doc, plist = job[r["doc"]]
            jg[(doc, plist[int(r["page"]) - 1])] = r

def judged(key):
    """`worse` when the output is worse on some pair, `-` when every pair was judged or identical and none
    is, `?` when some pair has no verdict"""
    j = jg.get(key)
    if j is None: return "?"
    if int(j["worse"]) + int(j["both"]): return "worse"
    return "-" if int(j["unjudged"]) + int(j["unparsed"]) == 0 else "?"

cols = ("document page route drawn old cols truth text other judge class trWords contested scored wrong missing "
        "added splits welds hyph copyErr find order fig hand visMiss layerMiss elInk elCol oldFind prec inside cover").split() + RR + JG
out = [cols]
byroute = collections.defaultdict(collections.Counter)
perdoc = collections.defaultdict(lambda: collections.Counter())
for (doc, p), (why, route) in sorted(listing.items(), key=lambda kv: (kv[1][1], kv[0][0], int(kv[0][1]))):
    P, T = pages.get((doc, p)), truth.get((doc, p))
    old = flags(P["flags"]) if P else None
    extra = [str(rr[(doc, p)][k]) for k in RR] + [jg[(doc, p)][k] if (doc, p) in jg else "-" for k in JG]
    if T is None:
        cls = "crash"
        row = [doc, p, route, why, show(old) if old is not None else "crash", P["cols"] if P else "-", "crash", "-", "-", "-", cls]
        row += ["-"] * (len(cols) - len(row) - len(extra)) + extra
    else:
        tf, jv = flags(T["tflags"]), judged((doc, p))
        oldred, truthred = bool(old) if old is not None else True, bool(tf) or jv == "worse"
        cls = {(False, False): "green", (True, True): "red", (True, False): "old-only", (False, True): "truth-only"}[(oldred, truthred)]
        row = [doc, p, route, why, show(old) if old is not None else "crash", P["cols"] if P else "-",
               show(tf | ({"judge"} if jv == "worse" else set())), show(tf & TEXT), show(tf & OTHER), jv, cls] + [T[k] for k in
               "trWords contested scored wrong missing added splits welds hyph copyErr find order fig hand visMiss layerMiss elInk elCol".split()] + \
              [P[k] if P else "-" for k in ("find", "prec", "inside", "cover")] + extra
        c = perdoc[doc]
        for k in ("scored", "wrong", "missing", "added"):
            try: c[k] += int(T[k])
            except ValueError: pass
        c["truthText"] += bool(tf & TEXT); c["truthOther"] += bool(tf & OTHER); c["judgeWorse"] += jv == "worse"
        c["oldRed"] += oldred
        for k, on in (("text", tf & TEXT), ("other", tf & OTHER), ("judge", jv == "worse")): byroute[route][k] += bool(on)
    for k in ("confirmed", "rrContested", "unread"): perdoc[doc][k] += rr[(doc, p)][k]
    perdoc[doc]["pages"] += 1
    byroute[route][cls] += 1
    byroute[route]["pages"] += 1
    out.append(row)

with open(sys.argv[2], "w", encoding="utf-8") as fh:
    fh.write(f"# TRUTH-RUN pages: the pipeline at {built}, default settings, each truth-set page scored by the old measures\n"
             "# and by `ux-harness --truth` on the same output. Numbers only. `text` is the copy and Find verdict after the\n"
             "# blind re-read (`reread`..`unread`); `other` the element ink and colour check, no model; `judge` the blind\n"
             "# judges (`identical`..`out-colour`, kinds of loss counted on the output's side; `rejudged` pairs carry the\n"
             "# second round's verdict, `judge/out2/`). Never merged.\n")
    for r in out: fh.write("\t".join(r) + "\n")

dcols = "document pages oldRed truthText truthOther judgeWorse scored wrong missing added copyErr confirmed rrContested unread bytes docFlags".split()
with open(sys.argv[3], "w", encoding="utf-8") as fh:
    fh.write(f"# TRUTH-RUN documents: the pipeline at {built}; copyErr pooled over the document's truth pages after the re-read;\n"
             "# bytes is the cut document's output over its source (the harness's `bytes`), docFlags the harness's document flags.\n")
    fh.write("\t".join(dcols) + "\n")
    for doc in sorted(perdoc):
        c, D = perdoc[doc], docs.get(doc, {})
        err = (c["wrong"] + c["missing"] + c["added"]) / c["scored"] if c["scored"] else 0.0
        fh.write("\t".join([doc, str(c["pages"]), str(c["oldRed"]), str(c["truthText"]), str(c["truthOther"]), str(c["judgeWorse"]),
                            str(c["scored"]), str(c["wrong"]), str(c["missing"]), str(c["added"]), f"{err:.3f}",
                            str(c["confirmed"]), str(c["rrContested"]), str(c["unread"]),
                            D.get("bytes", "crash"), D.get("flags", "crash")]) + "\n")

print(f"route        pages  green  red  old-only  truth-only  crash   text  other  judge   (pipeline at {built})")
tot = collections.Counter()
for route in sorted(byroute):
    c = byroute[route]; tot.update(c)
    print(f"{route:<12} {c['pages']:>5}  {c['green']:>5}  {c['red']:>3}  {c['old-only']:>8}  {c['truth-only']:>10}  {c['crash']:>5}  {c['text']:>5}  {c['other']:>5}  {c['judge']:>5}")
print(f"{'all':<12} {tot['pages']:>5}  {tot['green']:>5}  {tot['red']:>3}  {tot['old-only']:>8}  {tot['truth-only']:>10}  {tot['crash']:>5}  {tot['text']:>5}  {tot['other']:>5}  {tot['judge']:>5}")
for doc, p in sorted(crashes): print(f"crash row: {doc} {p}: {crashes[(doc, p)]}")
