#!/usr/bin/env python3
"""score-words.py <truth.txt> <hypothesis.txt>

Word error of a hypothesis against a known truth: word-level Levenshtein distance over the truth's word
count, printed as `truth=N errors=E wer=P% bag=B% missing_lines=L`. Both sides are normalised the same way:
curly quotes and dashes straightened, a hyphen at a line end joined to the next word, whitespace split.
No difflib: its autojunk heuristic has faked findings here before (CLAUDE.md, Verification discipline).
`missing_lines` counts truth lines of 3+ words none of whose words' 3-grams appear in the hypothesis
in order, a coarse count of skipped lines.
"""
import re
from collections import Counter
import sys

TR = str.maketrans({"‘": "'", "’": "'", "“": '"', "”": '"', "–": "-", "—": "-",
                    " ": " ", "ﬁ": "fi", "ﬂ": "fl"})


def words(text):
    text = text.translate(TR)
    text = re.sub(r"(\w)-\s*\n\s*(\w)", r"\1\2", text)
    return text.split()


def distance(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def missing_lines(truth, hyp_words):
    grams = {tuple(hyp_words[i:i + 3]) for i in range(len(hyp_words) - 2)}
    n = 0
    for line in truth.splitlines():
        w = words(line)
        if len(w) >= 3 and not any(tuple(w[i:i + 3]) in grams for i in range(len(w) - 2)):
            n += 1
    return n


def main():
    truth = open(sys.argv[1], encoding="utf-8").read()
    hyp = open(sys.argv[2], encoding="utf-8").read()
    t, h = words(truth), words(hyp)
    e = distance(t, h)
    # Order-free: truth words the hypothesis lacks, counted with multiplicity. A column read in another
    # order costs WER heavily and this nothing, so the pair separates misreads from reading order.
    have = Counter(h)
    lost = sum(max(0, n - have[w]) for w, n in Counter(t).items())
    print(f"truth={len(t)} errors={e} wer={100 * e / max(len(t), 1):.2f}% "
          f"bag={100 * lost / max(len(t), 1):.2f}% missing_lines={missing_lines(truth, h)}")


if __name__ == "__main__":
    main()
