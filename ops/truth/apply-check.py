#!/usr/bin/env python3
"""apply-check.py <rd-dir> <truth.txt> <app.txt>: apply CHECK readings ($CHECKS/chk-*.out, lines `path<TAB>reading`)
to the reader's words and score. V2=1 applies procedure v2 (a check that differs contests the word; it never
replaces it); unset applies v1 (the check reading stands).
Prints: raw reader bag lost before/after check, contested count, and a fair lost share for reader-after
and app (case and punctuation folded; a truth word split `con- servatism` merged when the joined form
is in the hypothesis)."""
import glob, os, re, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xcheck

d, truth, app = sys.argv[1:4]
TR = xcheck.TR


def reader_words():
    ls = xcheck.lines(f"{d}/transcript.txt")
    out = []
    for (x, y, w, h), t in ls:
        for wd in t.split():
            if out and re.search(r"\w-$", out[-1][0]) and y > out[-1][1] and wd[:1].isalnum():
                out[-1] = (out[-1][0][:-1] + wd, out[-1][1])
            else:
                out.append((wd, y))
    return [w for w, _ in out]


def sim(a, b):
    a, b = a.lower(), b.lower()
    return sum(1 for x, y in zip(a, b) if x == y) - abs(len(a) - len(b))


words = reader_words()
checks = {}
for f in glob.glob(os.path.join(os.environ.get("CHECKS", "."), "chk-*.out")):
    for line in open(f, encoding="utf-8"):
        if "\t" not in line: continue
        p, r = line.rstrip("\n").split("\t", 1)
        if f"/{os.path.basename(d)}/check/" in p:
            checks[int(os.path.basename(p)[:-4])] = r.strip()
contested = 0
changed = 0
after = list(words)
for k, r in checks.items():
    if r in ("?", "`?`", ""):
        after[k] = None; contested += 1; continue
    toks = r.split()
    if os.environ.get("V2"):
        f = lambda w: re.sub(r"[^\w]", "", w.translate(TR)).lower()
        if not any(f(t) == f(words[k]) for t in toks):
            after[k] = None; contested += 1
        continue
    best = max(toks, key=lambda t: sim(t, words[k])) if len(toks) > 1 else toks[0]
    if best != words[k]: changed += 1
    after[k] = best


def fold(ws):
    out = []
    for w in ws:
        for piece in w.translate(TR).split("-"):
            piece = re.sub(r"[^\w]", "", piece).lower()
            if piece: out.append(piece)
    return out


def fair_lost(tw, hw):
    h = Counter(fold(hw)); hs = set(h)
    t = fold(tw); merged = []
    i = 0
    while i < len(t):
        for span in (3, 2):
            if i + span <= len(t) and t[i] not in hs and "".join(t[i:i + span]) in hs:
                merged.append("".join(t[i:i + span])); i += span; break
        else:
            merged.append(t[i]); i += 1
    lost = sum((Counter(merged) - h).values())
    return lost, len(merged)


def bag(tw, hw):
    return sum((Counter(tw) - Counter(hw)).values())


import importlib.util
sp = importlib.util.spec_from_file_location("sw", os.path.join(os.path.dirname(os.path.abspath(__file__)), "score-words.py"))
sw = importlib.util.module_from_spec(sp); sp.loader.exec_module(sw)
tw = sw.words(open(truth, encoding="utf-8").read())
aw = sw.words(open(app, encoding="utf-8").read())
kept = [w for w in after if w is not None]
b0 = bag(tw, words); b1 = max(bag(tw, kept) - contested, 0)
rl, n = fair_lost(tw, kept); rl = max(rl - contested, 0); n = n - contested  # score only uncontested words
r0, _ = fair_lost(tw, words)
al, _ = fair_lost(tw, aw)
print(f"{os.path.basename(d)}\ttruth={len(tw)}\tchecked={len(checks)}\tchanged={changed}\tcontested={contested}"
      f"\treader_bag_before={b0}\treader_bag_after={b1}\treader_fair={rl}/{n}={100*rl/n:.2f}%\tapp_fair={al}/{n + contested}={100*al/(n + contested):.2f}%"
      f"\treader_nocheck={r0}/{n + contested}={100*r0/(n + contested):.2f}%")
