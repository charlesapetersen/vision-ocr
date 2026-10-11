#!/usr/bin/env python3
"""bits-table.py <pages.tsv> — ocr-bakeoff-bits' table: each of the top three at its two bit widths.

<pages.tsv> is `score-bakeoff.py --pages`'s output. For each build: words missed and words added over every
scored page (a page the build could not read counts as all missing, as score-bakeoff.py counts it), words
missed and added over the pages BOTH builds of the model read (so a guard kill neither passes for a misreading
nor, adding nothing, for a clean read), reads
cut at a limit, pages unread, mean seconds per whole and per crops read and the peak memory of any read, from
the job's log (the guard's figures: the larger of RSS and physical footprint), whole and crops apart, and the reads
the guard killed twice for passing 12 GB (`killed`, from the readings' .reason files). Then, for each memory limit
from 4 to 12 GB, the build each model should use: among those whose peak fits, the one with the fewest words missed plus
words added on the pages both read (a looping build adds hundreds of words a page while missing few: Falcon-OCR 8-bit). A build with a killed
read needs more than 12 GB on some crops, so like a build whose crops peak passes the limit it is offered for whole
pages only, marked `(whole)`.
"""
import os, sys

STATE = os.environ.get("STATE", os.path.expanduser("~/.local/state/visionocr-autonomous"))
# (model, [(build label, bits)]): Falcon-OCR's 4-bit has no readings (`failed` in bakeoff-models.tsv: every
# 4-bit build loops on s01 and s03), so its pair is 8-bit against the fitted bf16.
PAIRS = [("Falcon-OCR", [("falcon-ocr-bf16", "bf16"), ("falcon-ocr-8bit", "8")]),
         ("LightOnOCR-2-1B", [("lightonocr-2-1b-4bit-1540-quiet", "4"), ("lightonocr-2-1b-8bit-1540", "8")]),
         ("Chandra-OCR-2", [("chandra-ocr-2-oQ4", "oQ4"), ("chandra-ocr-2-oQ8", "oQ8")])]

rows = {}
for l in list(open(sys.argv[1], encoding="utf-8"))[1:]:
    f = l.rstrip("\n").split("\t")
    if f[6] != "-": rows.setdefault(f[0], {})[f[1]] = (int(f[4]), float(f[6]), float(f[7]), int(f[9]), f[10])
speed = {}
for l in open(f"{STATE}/ocrlab/bakeoff.log", encoding="utf-8"):
    f = l.rstrip("\n").split("\t")
    if len(f) > 6 and f[4] == "read":
        speed.setdefault(f[1], []).append((f[3], float(f[5].rstrip("s")), int(f[6].rstrip("MB"))))

def mean(xs): return sum(xs) / len(xs) if xs else float("nan")
out, best = [], {}
print("model\tbuild\tbits\tmiss\tadded\tmiss_both_read\tadded_both_read\tboth_pages\tcut\tunread\twhole_s\tcrops_s\twhole_peak_mb\tcrops_peak_mb\tkilled")
for model, builds in PAIRS:
    both = set.intersection(*[{i for i, r in rows[b].items() if not r[4]} for b, _ in builds])
    for b, bits in builds:
        r = rows[b]; n = sum(x[0] for x in r.values())
        miss = sum(x[0] * x[1] for x in r.values()) / n
        added = sum(x[0] * x[2] for x in r.values()) / n
        nb = sum(r[i][0] for i in both)
        mb = sum(r[i][0] * r[i][1] for i in both) / nb
        ab = sum(r[i][0] * r[i][2] for i in both) / nb
        s = speed.get(b, [])
        wp = max((x[2] for x in s if x[0] == "whole"), default=0); cp = max((x[2] for x in s if x[0] == "crops"), default=0)
        d = f"{STATE}/ocrlab/readings/{b}"
        killed = sum(1 for x in os.listdir(d) if x.endswith(".reason") and "guard killed" in open(f"{d}/{x}").read())
        best.setdefault(model, []).append((b, mb + ab, wp, cp, killed))
        print(f"{model}\t{b}\t{bits}\t{miss:.4f}\t{added:.4f}\t{mb:.4f}\t{ab:.4f}\t{len(both)}\t{sum(x[3] for x in r.values())}\t"
              f"{sum(1 for x in r.values() if x[4])}\t{mean([x[1] for x in s if x[0] == 'whole']):.1f}\t"
              f"{mean([x[1] for x in s if x[0] == 'crops']):.1f}\t{wp}\t{cp}\t{killed}")
print()
print("memory_limit_gb\t" + "\t".join(m for m, _ in PAIRS))
for gb in range(4, 13):
    cells = []
    for model, _ in PAIRS:
        full = [x for x in best[model] if max(x[2], x[3]) <= gb * 1024 and not x[4]]
        whole = [x for x in best[model] if x[2] <= gb * 1024]
        cells.append(min(full, key=lambda x: x[1])[0] if full else
                     min(whole, key=lambda x: x[1])[0] + " (whole)" if whole else "none fits")
    print(f"{gb}\t" + "\t".join(cells))
