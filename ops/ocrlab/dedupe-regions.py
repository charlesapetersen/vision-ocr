#!/usr/bin/env python3
"""ops/ocrlab/dedupe-regions.py <regions.tsv> <crops.tsv> [--min-inside F] [--no-figures]

Turns layout-regions.py's `order label score x0 y0 x1 y1 megapixels` into the `name x y w h overlap` crops
TSV read-mlx.py's --crops reads, ready for a region reader. DocLayout-YOLO has no class-agnostic
suppression, so one block often comes back twice (a `title` and a `plain text` over the same ink). Boxes
are taken highest score first, and one is dropped when more than F (default 0.5) of its own area lies
inside a box already kept. Every box but images, tables, seals and formulas is kept, `abandon` (running
heads) included; `figure` too, because YOLO boxes some headlines as figures (`--no-figures` drops them).
Rows keep the detector's order; `overlap` is `yes` when a kept crop still touches another kept one.
Prints `kept=N dropped=M` on stdout.
"""
import argparse

NON_TEXT = {"image", "chart", "table", "seal", "isolate_formula", "formula", "formula_number"}

ap = argparse.ArgumentParser()
ap.add_argument("regions")
ap.add_argument("out")
ap.add_argument("--min-inside", type=float, default=0.5)
ap.add_argument("--no-figures", action="store_true")
a = ap.parse_args()

skip = NON_TEXT | ({"figure"} if a.no_figures else set())
rows = []
for line in open(a.regions).read().splitlines()[1:]:
    order, label, score, x0, y0, x1, y1 = line.split("\t")[:7]
    if label in skip:
        continue
    rows.append((int(order), float(score), int(x0), int(y0), int(x1), int(y1)))


def inter(p, q):
    w = min(p[4], q[4]) - max(p[2], q[2])
    h = min(p[5], q[5]) - max(p[3], q[3])
    return max(0, w) * max(0, h)


def area(p):
    return (p[4] - p[2]) * (p[5] - p[3])


kept = []
for r in sorted(rows, key=lambda r: -r[1]):
    if all(inter(r, k) <= a.min_inside * area(r) for k in kept):
        kept.append(r)
kept.sort()
with open(a.out, "w") as f:
    f.write("name\tx\ty\tw\th\toverlap\n")
    for i, r in enumerate(kept, 1):
        touch = any(inter(r, k) > 0 for k in kept if k is not r)
        f.write(f"c{i:03d}.png\t{r[2]}\t{r[3]}\t{r[4] - r[2]}\t{r[5] - r[3]}\t{'yes' if touch else 'no'}\n")
print(f"kept={len(kept)} dropped={len(rows) - len(kept)}")
