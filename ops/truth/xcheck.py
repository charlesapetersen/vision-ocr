#!/usr/bin/env python3
"""xcheck.py text <transcript>            -> transcript's words as text, one printed line per line
   xcheck.py spots <transcript> <vision.txt> -> TSV of reader words that differ from Vision's reading:
      idx  word  x y w h (page px, estimated from the line box by character offset)
   xcheck.py lspots <transcript> <other.txt> -> the same, aligned line by line (truth-set)
`spots` aligns word-level Levenshtein over the whole page, in the reader's order against the other's. That
fails where the two orders differ: two columns Vision reads in another order make every word a spot.
`lspots` aligns each reader line against the other text's line sharing most words with it, and lets the
lines either side confirm only the words at the matching edge (a line split differently), so order between
lines does not matter; a reader line sharing no word with any line is all
spots, which is the procedure's "every line only one of them has"."""
import re, sys

MARK = re.compile(r"^\s*(\[(fig|table|hand)\]\s*)+")
TR = str.maketrans({"‘": "'", "’": "'", "“": '"', "”": '"', "–": "-", "—": "-", " ": " "})


def lines(path):
    out = []
    for raw in open(path, encoding="utf-8"):
        raw = raw.rstrip("\n")
        if raw.startswith(("COLUMNS:", "OBJECTS:")):
            break
        m = re.match(r"^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*\t(.*)$", raw)
        if not m:
            continue
        x, y, w, h = map(int, m.groups()[:4])
        out.append(((x, y, w, h), MARK.sub("", m.group(5))))
    return out


def norm(wd):
    return wd.translate(TR)


def align(a, b):
    n, m = len(a), len(b)
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1): d[i][0] = i
    for j in range(m + 1): d[0][j] = j
    for i in range(1, n + 1):
        ai = a[i - 1]; row = d[i]; prev = d[i - 1]
        for j in range(1, m + 1):
            row[j] = min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + (ai != b[j - 1]))
    ok = [False] * n
    i, j = n, m
    while i > 0 and j > 0:
        if a[i - 1] == b[j - 1] and d[i][j] == d[i - 1][j - 1]:
            ok[i - 1] = True; i -= 1; j -= 1
        elif d[i][j] == d[i - 1][j - 1] + 1: i -= 1; j -= 1
        elif d[i][j] == d[i - 1][j] + 1: i -= 1
        else: j -= 1
    return ok


if __name__ == "__main__":
    mode, tr = sys.argv[1], sys.argv[2]
    ls = lines(tr)
    if mode == "text":
        print("\n".join(t for _, t in ls))
        sys.exit(0)
    words, lid = [], []  # (word, box), and each word's reader line
    for li, ((x, y, w, h), t) in enumerate(ls):
        L = max(len(t), 1)
        for mm in re.finditer(r"\S+", t):
            wx = x + int(w * mm.start() / L); ww = max(int(w * (mm.end() - mm.start()) / L), 10)
            words.append((mm.group(), (wx, y, ww, h))); lid.append(li)
    joined, jlid = [], []
    for (wd, box), li in zip(words, lid):
        if joined and re.search(r"\w-$", joined[-1][0]) and box[1] > joined[-1][1][1] and wd[:1].isalnum():
            joined[-1] = (joined[-1][0][:-1] + wd, joined[-1][1])
        else:
            joined.append((wd, box)); jlid.append(li)
    words, lid = joined, jlid
    vis = open(sys.argv[3], encoding="utf-8").read().translate(TR)
    vis = re.sub(r"(\w)-\s*\n\s*(\w)", r"\1\2", vis)
    if mode == "lspots":
        other = [l.split() for l in vis.split("\n") if l.split()]
        sets = [set(l) for l in other]
        ok = [False] * len(words)
        byline = {}
        for k, li in enumerate(lid): byline.setdefault(li, []).append(k)
        for ks in byline.values():
            mine = [norm(words[k][0]) for k in ks]
            score = [len(set(mine) & st) for st in sets]
            if not score or max(score) == 0: continue
            b = score.index(max(score))
            got = align(mine, other[b])
            # A neighbouring line may confirm only the words at the matching edge: the reader's unmatched
            # head against the previous line's tail, its unmatched tail against the next line's head. A
            # window over all three lines let a stray `the` match the next line's first word.
            n = 0
            while n < len(got) and not got[n]: n += 1
            if n and b > 0: got[:n] = align(mine[:n], other[b - 1][-n:])
            m = 0
            while m < len(got) and not got[-1 - m]: m += 1
            if m and b + 1 < len(other): got[len(got) - m:] = align(mine[len(got) - m:], other[b + 1][:m])
            for k, good in zip(ks, got): ok[k] = good
    else:
        ok = align([norm(w) for w, _ in words], vis.split())
    for k, ((wd, (x, y, w, h)), good) in enumerate(zip(words, ok)):
        if not good:
            print(f"{k}\t{wd}\t{x}\t{y}\t{w}\t{h}")
