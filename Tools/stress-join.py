#!/usr/bin/env python3
"""stress-join — one TSV row per page over a finished `score-gate` run, for `corpus-stress`.

    python3 Tools/stress-join.py <score-stress binary> <label> <corpus-root> <gate-output-dir> [jobs]

Reads the gate's `timings.tsv` (input, seconds, outcome) and `per-document.tsv`
(resemblance), finds each input's output by `OCRModel.uniqueOutputs`' rule (inputs in
the gate's sorted order, `<stem>.ocr.pdf`, then `<stem> 2.ocr.pdf`, ...), runs
`score-stress` on each pair and prints the header once, then the rows, prefixed by
the document's own columns. A document with no output gets one row with `page` 0.
"""
import os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

tool, label, root, outdir = sys.argv[1:5]
jobs = int(sys.argv[5]) if len(sys.argv) > 5 else 4

rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(outdir, "timings.tsv"))][1:]

claimed = {r[0].lower() for r in rows}
docs = []
for path, secs, outcome in rows:
    stem = os.path.splitext(os.path.basename(path))[0]
    cand, n = os.path.join(outdir, stem + ".ocr.pdf"), 2
    while cand.lower() in claimed:
        cand, n = os.path.join(outdir, f"{stem} {n}.ocr.pdf"), n + 1
    claimed.add(cand.lower())
    docs.append((path, cand, secs, outcome))

def measure(d):
    path, out, secs, outcome = d
    rel = label + "/" + os.path.relpath(path, root)
    src_b = os.path.getsize(path)
    head = [rel, str(src_b)]
    if not os.path.exists(out):
        return [head + ["", secs, outcome, "", "0"] + ["-"] * 11]
    out_b = os.path.getsize(out)
    head += [str(out_b), secs, outcome.split("(")[0], os.path.basename(out)]
    # stderr passes through: it carries score-stress's page-count warning.
    p = subprocess.run([tool, path, out], stdout=subprocess.PIPE, text=True)
    lines = [l.split("\t") for l in p.stdout.splitlines() if l]
    if p.returncode != 0 or not lines:
        return [head + ["0"] + ["-"] * 10 + [f"score-stress exit {p.returncode}"]]
    return [head + l for l in lines]

with ThreadPoolExecutor(jobs) as ex:
    results = list(ex.map(measure, docs))

# The gate writes `per-document.tsv` only after its own pixel pass, which can
# outlast the measuring above; wait for it rather than print a blank column.
per_doc = os.path.join(outdir, "per-document.tsv")
while not os.path.exists(per_doc):
    time.sleep(10)
worst = {}
for l in list(open(per_doc))[1:]:
    c = l.rstrip("\n").split("\t")
    worst[c[0]] = c[6]

hdr = subprocess.run([tool, "--header"], capture_output=True, text=True).stdout.strip()
print("doc\tsrcBytes\toutBytes\tseconds\toutcome\tresemblance\t" + hdr)
for result in results:
    for r in result:
        if r[5]:
            r[5] = worst.get(r[5], "")
        print("\t".join(r))
