#!/usr/bin/env python3
"""ops/ocrlab/fused-regions.py — where C41's fused rows sit in a layout detector's regions (layout-compare, lc-fused).

    fused-regions.py <cfr output> <crops.tsv> <page image> [--label L] [--rows]

`cfr output` is Tools/count-fused-rows.swift's print with examples (ONE-RUN / TWO-RUNS lines: the row's y and x0-x1
as fractions of the published page, `run=` the extent of the drawn run through the gutter, `at=` the gutter it joins
across); `crops.tsv` the regions the reader was given for that very run (reader-regions.sh's kept `name x y w h
overlap`, page pixels of `page image`, after dedupe-regions.py and the size filter, in the order the app took them).
Each ONE-RUN row, a single drawn run across a printed gutter, is placed as `Recogniser.regionAligned` places a
Vision line: the first region (in order) holding the run's centre and three quarters of its width takes it. (The
app also passes over a region whose reading has no words; the readings are not consulted here.) The run is then
  spans      taken by a region that reaches across the gutter: whatever reads that region reads both columns onto
             this one line, so the region explains the fused row as the reader sees it;
  straddles  taken by no region, with a region ending at or left of the gutter and another starting at or right of
             it: the row was fused before any region was read (Vision's box), and a cut at the boundary would split it;
  crossed    taken by no region, and a region reaching across the gutter touches the run without holding it (the run
             runs past that region's edge): the region spans two columns, and no boundary sits at the gutter;
  one-side   the region that takes the run, or every region touching it, lies on one side of the gutter;
  none       no text region touches the run.
TWO-RUNS rows (two drawn runs PDFKit groups on one line, C39) are counted, not placed. Prints one TSV line:
label oneRun spans straddles crossed oneSide none twoRuns; --rows prints each ONE-RUN row's verdict and region first.
Measured in page fractions: the kept image is the page the app read, so its pixels map to the published page.
"""
import argparse
import re
import sys

from PIL import Image

Image.MAX_IMAGE_PIXELS = None

ap = argparse.ArgumentParser()
ap.add_argument("cfr")
ap.add_argument("crops")
ap.add_argument("image")
ap.add_argument("--label", default="-")
ap.add_argument("--rows", action="store_true")
a = ap.parse_args()

W, H = Image.open(a.image).size
regions = []
for line in open(a.crops, encoding="utf-8").read().splitlines()[1:]:
    f = line.split("\t")
    x, y, w, h = (int(v) for v in f[1:5])
    regions.append((f[0], x / W, y / H, (x + w) / W, (y + h) / H))

pat = re.compile(r"^(ONE-RUN|TWO-RUNS)\s+gap=(\S+) gutter=(\S+) y=(\S+) x=(\S+)-(\S+)(?: run=(\S+)-(\S+))? at=(\S+)\s+(.*)$")
rows = []
for line in open(a.cfr, encoding="utf-8"):
    m = pat.match(line.rstrip("\n"))
    if m:
        x0, x1 = float(m.group(5)), float(m.group(6))
        r0, r1 = (float(m.group(7)), float(m.group(8))) if m.group(7) else (x0, x1)
        rows.append((m.group(1), float(m.group(4)), r0, r1, float(m.group(9)), m.group(10)))

VERDICTS = ["spans", "straddles", "crossed", "one-side", "none"]
counts = {v: 0 for v in VERDICTS}
two = sum(1 for r in rows if r[0] == "TWO-RUNS")
for kind, y, x0, x1, at, text in rows:
    if kind != "ONE-RUN":
        continue
    cx, cy, width = (x0 + x1) / 2, y, x1 - x0
    taker = None
    for name, rx0, ry0, rx1, ry1 in regions:
        if rx0 <= cx <= rx1 and ry0 <= cy <= ry1 and min(x1, rx1) - max(x0, rx0) >= 0.75 * width:
            taker = (name, rx0, rx1)
            break
    if taker:
        verdict = "spans" if taker[1] < at < taker[2] else "one-side"
    else:
        touching = [(n, rx0, rx1) for n, rx0, ry0, rx1, ry1 in regions if ry0 <= cy <= ry1 and min(x1, rx1) > max(x0, rx0)]
        left = any(rx1 <= at for _, _, rx1 in touching)
        right = any(rx0 >= at for _, rx0, _ in touching)
        crossing = any(rx0 < at < rx1 for _, rx0, rx1 in touching)
        verdict = "straddles" if left and right else ("crossed" if crossing else ("one-side" if touching else "none"))
    counts[verdict] += 1
    if a.rows:
        print(f"{verdict}\t{taker[0] if taker else '-'}\ty={y:.3f}\trun={x0:.3f}-{x1:.3f}\tat={at:.3f}\t{text[:90]}")
one = sum(counts.values())
print("\t".join([a.label, str(one)] + [str(counts[v]) for v in VERDICTS] + [str(two)]))
