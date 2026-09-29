#!/usr/bin/env python3
"""contest.py <page-dir> <checks-dir>: procedure.md step 4 for a truth-set page, applied as v2.
A spot's check reading (lines `path<TAB>reading` in <checks-dir>/chk-*.out) that differs from the reader's
word (case, punctuation and superscripts folded; a word of marks only, like `[?]`, must match exactly), or
is `?`, contests the word. The check never replaces it. A spot with no check reading is contested too, so a lost check cannot pass a word unseen. Writes contested.tsv (idx, word, check)
and prints `words spots contested unchecked` for the page. Refuses a missing or stale spots.tsv and a
transcript that parses to no words, so neither can pass a page with every word unseen."""
import glob, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xcheck

d, cd = os.path.realpath(sys.argv[1]), sys.argv[2]
sp = f"{d}/spots.tsv"
if not os.path.exists(sp) or os.path.getmtime(sp) < os.path.getmtime(f"{d}/transcript.txt"):
    sys.exit(f"contest.py: {sp} is missing or older than the transcript; run spots-page.sh first")
words = []
for (x, y, w, h), t in xcheck.lines(f"{d}/transcript.txt"):
    for wd in t.split():
        if words and re.search(r"\w-$", words[-1][0]) and y > words[-1][1] and wd[:1].isalnum():
            words[-1] = (words[-1][0][:-1] + wd, words[-1][1], words[-1][0])
        else:
            words.append((wd, y, None))
if not words:
    sys.exit(f"contest.py: no words parsed from {d}/transcript.txt (each line must be `x y w h<TAB>text`)")
checks = {}
for f in glob.glob(os.path.join(cd, "chk-*.out")):
    for line in open(f, encoding="utf-8"):
        if "\t" not in line: continue
        p, r = line.rstrip("\n").split("\t", 1)
        p = os.path.realpath(p.strip())
        if os.path.dirname(p) == f"{d}/check":
            checks[os.path.basename(p)[:-4]] = r.strip()
SUP = str.maketrans("⁰¹²³⁴⁵⁶⁷⁸⁹", "0123456789")
fold = lambda w: re.sub(r"[^\w]", "", w.translate(xcheck.TR).translate(SUP)).lower()


def same(r, word):
    if r is None or r in ("?", "`?`", ""): return False
    if not fold(word): return r.strip() == word  # `[?]`, a bullet: only the same marks agree
    return any(fold(t) == fold(word) for t in r.split())


def agrees(k):
    word, _, head = words[k]
    if same(checks.get(str(k)), word): return True
    # A word joined across a line-end hyphen: its crop shows the first line's half (`Prince-`) and
    # <k>t.png the second (`ton's`); both halves must agree.
    return head is not None and same(checks.get(str(k)), head) and same(checks.get(f"{k}t"), word[len(head) - 1:])


spots = [int(l.split("\t")[0]) for l in open(sp) if l.strip()]
out = []
for k in spots:
    if not agrees(k):
        r = checks.get(str(k))
        out.append(f"{k}\t{words[k][0]}\t{r if r is not None else '(no check)'}")
open(f"{d}/contested.tsv", "w").write("".join(l + "\n" for l in out))
unchecked = sum(str(k) not in checks for k in spots)
print(f"{len(words)}\t{len(spots)}\t{len(out)}\t{unchecked}")
