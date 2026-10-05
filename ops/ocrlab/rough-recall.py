"""rough-recall.py <transcript.txt> <reading.txt> — a sanity figure, NOT the bake-off's score.

Bag-of-words recall and precision: the share of the transcript's words (lower-cased, letters and
digits only) that the reading holds, counted with multiplicity, and the share of the reading's words
the transcript holds. It ignores order and contested words, so it only tells a model that reads the
page from one that does not; `ocr-bakeoff` scores the way `truth-harness` does.
"""
import re, sys
from collections import Counter

def words(path):
    t = open(path, encoding="utf-8", errors="replace").read()
    t = re.sub(r"(?m)^\d+ \d+ \d+ \d+\t", "", t)        # a truth transcript's line boxes
    t = re.sub(r"<[^>]+>", " ", t)                      # HTML or grounding tags some models emit
    return Counter(w for w in re.findall(r"[a-z0-9]+", t.lower()))

truth, read = words(sys.argv[1]), words(sys.argv[2])
hit = sum((truth & read).values())
print(f"{hit / max(1, sum(truth.values())):.3f}\t{hit / max(1, sum(read.values())):.3f}")
