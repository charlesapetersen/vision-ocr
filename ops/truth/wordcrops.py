#!/usr/bin/env python3
"""wordcrops.py <rd-dir>: for each spot in spots.tsv, find the word's ink box in page.png inside the reader's
line box (word gaps from a column ink profile) and cut it plus 10 px to check/<idx>.png. Writes check/list.tsv."""
import os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
import xcheck

M = "/opt/homebrew/bin/magick"
d = sys.argv[1]
page = f"{d}/page.png"
os.makedirs(f"{d}/check", exist_ok=True)
ls = xcheck.lines(f"{d}/transcript.txt")
# xcheck joins hyphenated line ends, so indices past a join shift; rebuild the same joined list
joined = []
for li, (_, t) in enumerate(ls):
    for wi, wd in enumerate(t.split()):
        if joined and re.search(r"\w-$", joined[-1][0]) and ls[joined[-1][1]][0][1] < ls[li][0][1] and wd[:1].isalnum():
            joined[-1] = (joined[-1][0][:-1] + wd, joined[-1][1], joined[-1][2])
        else:
            joined.append((wd, li, wi))
prof = {}


def segments(li):
    if li in prof:
        return prof[li]
    x, y, w, h = ls[li][0]
    out = subprocess.run([M, page, "-crop", f"{w}x{h}+{x}+{y}", "+repage", "-colorspace", "gray",
                          "-threshold", "55%", "-negate", "-scale", f"{w}x1!", "-depth", "8", "gray:-"],
                         capture_output=True).stdout
    ink = [b > 3 for b in out]
    gap = max(int(h * 0.22), 6)
    segs, s, run = [], None, 0
    for i, v in enumerate(ink + [False] * (gap + 1)):
        if v:
            if s is None: s = i
            run = 0; e = i
        elif s is not None:
            run += 1
            if run > gap:
                segs.append((s, e)); s = None
    prof[li] = segs
    return segs


rows = []
for line in open(f"{d}/spots.tsv"):
    k, wd, ex, ey, ew, eh = line.rstrip("\n").split("\t")
    k = int(k); ex, ey, ew, eh = map(int, (ex, ey, ew, eh))
    _, li, wi = joined[k]
    x, y, w, h = ls[li][0]
    segs = segments(li)
    nwords = len(ls[li][1].split())
    if len(segs) == nwords:
        s, e = segs[wi]
    elif segs:
        c = ex + ew / 2 - x
        s, e = min(segs, key=lambda se: abs((se[0] + se[1]) / 2 - c))
    else:
        s, e = ex - x, ex - x + ew
    cx, cy = max(x + s - 10, 0), max(y - 10, 0)
    cw, ch = e - s + 21, h + 20
    subprocess.run([M, page, "-crop", f"{cw}x{ch}+{cx}+{cy}", "+repage", f"{d}/check/{k}.png"])
    rows.append(f"{k}\t{wd}\t{cx}\t{cy}\t{cw}\t{ch}\t{'exact' if len(segs) == nwords else 'nearest'}")
open(f"{d}/check/list.tsv", "w").write("\n".join(rows) + "\n")
print(d, len(rows), sum(r.endswith("exact") for r in rows), "exact")
