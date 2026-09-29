#!/usr/bin/env python3
"""page-status.py <TRUTH-PAGES.tsv> [batch]: fills the status column from $STATE/truth/<doc>/p<N>/.
A page whose meta.txt has its `words=` line is `done <batch>: words=W contested=C`; one listed in
$STATE/truth/none.tsv (document, page, reason) is `none: <reason>`; the rest keep their status. [batch]
labels pages finished since the last run. Rewrites the file in place, then prints the contested rate by
route over every done page (QUEUE.md truth-set DONE WHEN)."""
import os, re, sys
from collections import defaultdict

path = sys.argv[1]
batch = sys.argv[2] if len(sys.argv) > 2 else "?"
T = os.path.join(os.environ.get("STATE", os.path.expanduser("~/.local/state/visionocr-autonomous")), "truth")
none = {}
if os.path.exists(f"{T}/none.tsv"):
    for l in open(f"{T}/none.tsv", encoding="utf-8"):
        d, p, why = l.rstrip("\n").split("\t", 2)
        none[(d, p)] = why
rows = [l.rstrip("\n").split("\t") for l in open(path, encoding="utf-8")]
by = defaultdict(lambda: [0, 0, 0])
for r in rows[1:]:
    doc, page, why, route, status = r
    meta = f"{T}/{doc[:-4]}/p{page}/meta.txt"
    m = re.search(r"^words=(\d+) spots=\d+ contested=(\d+)", open(meta).read(), re.M) if os.path.exists(meta) else None
    if m:
        w, c = map(int, m.groups())
        old = re.match(r"done (\S+):", status)
        r[4] = f"done {old.group(1) if old else batch}: words={w} contested={c}"
        by[route][0] += 1; by[route][1] += w; by[route][2] += c
    elif (doc, page) in none:
        r[4] = f"none: {none[(doc, page)]}"
with open(path, "w", encoding="utf-8") as f:
    for r in rows: f.write("\t".join(r) + "\n")
print("route\tpages\twords\tcontested\trate")
for k, (n, w, c) in sorted(by.items()):
    print(f"{k}\t{n}\t{w}\t{c}\t{100 * c / max(w, 1):.2f}%")
