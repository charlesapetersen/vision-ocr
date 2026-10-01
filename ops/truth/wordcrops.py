#!/usr/bin/env python3
"""wordcrops.py <rd-dir>: for each spot in spots.tsv, find the word's ink box in page.png inside the reader's
line box (word gaps from a column ink profile) and cut it plus 10 px to check/<idx>.png; a word joined across
a line-end hyphen also gets check/<idx>t.png, its second half. Writes check/list.tsv.

wordcrops.py <rd-dir> --wide: for each index in wide-spots.tsv, a `nearest` crop whose reading disagreed, cut
wide/<idx>.png: the word and the words either side on its line, from their character offsets, half a line
height more each way, snapped outward to an ink gap no more than a line height further, plus 10 px. A miscut
(`25,000` cut at its comma) then shows the whole word, and a reading that holds it confirms it."""
import os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(__file__))
import xcheck

M = "/opt/homebrew/bin/magick"
d = sys.argv[1]
WIDE = "--wide" in sys.argv[2:]
page = f"{d}/page.png"
os.makedirs(f"{d}/check", exist_ok=True)
ls = xcheck.lines(f"{d}/transcript.txt")
# xcheck joins hyphenated line ends, so indices past a join shift; rebuild the same joined list
joined = []
for li, (_, t) in enumerate(ls):
    for wi, wd in enumerate(t.split()):
        if joined and re.search(r"\w-$", joined[-1][0]) and ls[joined[-1][1]][0][1] < ls[li][0][1] and wd[:1].isalnum():
            joined[-1] = (joined[-1][0][:-1] + wd, joined[-1][1], joined[-1][2], li)
        else:
            joined.append((wd, li, wi, None))
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


if WIDE:
    os.makedirs(f"{d}/wide", exist_ok=True)
    rows = []
    for line in open(f"{d}/wide-spots.tsv"):
        k = int(line.split("\t")[0])
        _, li, wi, _ = joined[k]
        (x, y, w, h), t = ls[li]
        ws, starts, pos = t.split(), [], 0
        for wd in ws:
            pos = t.index(wd, pos); starts.append(pos); pos += len(wd)
        a, b, n = max(wi - 1, 0), min(wi + 1, len(ws) - 1), max(len(t), 1)
        L = int(w * starts[a] / n) - h // 2
        R = int(w * (starts[b] + len(ws[b])) / n) + h // 2
        for s, e in segments(li):
            if s < L <= e and L - s <= h: L = s
            if s <= R < e and e - R <= h: R = e
        # the box is the reader's estimate and can stop short of the ink, so a crop reaching the line's
        # first or last word goes a line height past it (magick clips a crop at the page's edge)
        if a == 0: L = min(L, -h)
        if b == len(ws) - 1: R = max(R, w + h)
        cx, cy = max(x + L - 10, 0), max(y - 10, 0)
        cw, ch = x + R + 11 - cx, h + 20
        subprocess.run([M, page, "-crop", f"{cw}x{ch}+{cx}+{cy}", "+repage", f"{d}/wide/{k}.png"])
        rows.append(f"{k}\t{joined[k][0]}\t{cx}\t{cy}\t{cw}\t{ch}\twide")
    open(f"{d}/wide/list.tsv", "w").write("\n".join(rows) + "\n")
    print(d, len(rows), "wide")
    sys.exit(0)

rows = []
for line in open(f"{d}/spots.tsv"):
    k, wd, ex, ey, ew, eh = line.rstrip("\n").split("\t")
    k = int(k); ex, ey, ew, eh = map(int, (ex, ey, ew, eh))
    _, li, wi, tli = joined[k]
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
    if tli is not None:
        # A word joined across a line-end hyphen: the crop above shows its first line only, so its second
        # half, the first word of the next line, gets a crop of its own (check/<k>t.png).
        tx, ty, tw, th = ls[tli][0]
        ts = segments(tli)
        s, e = ts[0] if ts else (0, min(tw, max(th * 3, 60)))
        cx, cy, cw, ch = max(tx + s - 10, 0), max(ty - 10, 0), e - s + 21, th + 20
        subprocess.run([M, page, "-crop", f"{cw}x{ch}+{cx}+{cy}", "+repage", f"{d}/check/{k}t.png"])
        rows.append(f"{k}t\t{ls[tli][1].split()[0]}\t{cx}\t{cy}\t{cw}\t{ch}\ttail")
open(f"{d}/check/list.tsv", "w").write("\n".join(rows) + "\n")
print(d, len(rows), sum(r.endswith("exact") for r in rows), "exact")
