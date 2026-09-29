#!/usr/bin/env python3
"""make-list.py <out.tsv>: the truth-set page list (QUEUE.md `truth-set`), columns document, page, why, route, status.

Draws, with a fixed seed so the list can be rebuilt:
  * about 100 of UX-RUN-2026-09-27's green pages, spread over the output route STRESS-2026-09-26 recorded
    for the page (JBIG2, layered colour, DCT/JPX, no image) and the newspaper set;
  * up to 10 red pages per measure (colour, copy, find, legibility, selection), 46 after overlaps;
  * every page of ops/ux-regression/set.tsv and of Tools/ux-harness-selftest.sh (rotfix is built from Why 5, 9);
  * candidates for what is not text: the most coloured source page (STRESS srcColour > 0.05) of each
    document, up to 28, and 8 pages of the photograph book, confirmed or not by the reader's OBJECTS list.
    Only 15 documents pass the colour bar, so this gives 17 new pages against the queue's ~25, and colour
    cannot find stamps, signatures or pencil on grey scans; the draws and the red colour pages add more.
Typewritten and table pages are not identifiable from these files; they arrive through the draws."""
import csv, random, sys
from collections import defaultdict

rng = random.Random(20260929)
rows, seen = [], set()


def add(doc, page, why, route):
    k = (doc, int(page))
    if k not in seen:
        seen.add(k); rows.append([doc, str(page), why, route, "todo"])


route = {}
colour = {}
for r in csv.DictReader(open("STRESS-2026-09-26.tsv"), delimiter="\t"):
    if not r["page"].isdigit(): continue
    d = r["doc"].removeprefix("testdocs/")
    route[(d, int(r["page"]))] = r["route"]
    try: colour[(d, int(r["page"]))] = float(r["srcColour"])
    except ValueError: pass


def kind(doc, page):
    if doc.startswith("newspaperArticle/"): return "newspaper"
    r = route.get((doc, page), "?")
    if r == "JBIG2/1": return "jbig2"
    if r.startswith("DCT/8+DCT/8+JBIG2"): return "layered"
    if r.startswith(("DCT", "JPX")): return "dct"
    if r == "none": return "no-image"
    return "other" if r != "?" else "unknown"


def docname(r):
    s = r["set"]
    return ("owner/" if s == "owner" else s.removeprefix("testdocs/") + "/") + r["document"] + ".pdf"


green, red = defaultdict(list), defaultdict(list)
for r in csv.DictReader(open("UX-RUN-2026-09-27-pages.tsv"), delimiter="\t"):
    d, p = docname(r), int(r["page"])
    if r["flags"] == "-": green[kind(d, p)].append((d, p))
    else:
        for f in r["flags"].split(","): red[f].append((d, p))

quota = {"jbig2": 50, "layered": 25, "dct": 12, "no-image": 10, "newspaper": 3, "other": 5, "unknown": 8}
for k, n in quota.items():
    pool = sorted(green[k])
    for d, p in rng.sample(pool, min(n, len(pool))):
        add(d, p, f"ux-run green, {k}", kind(d, p))
for f in sorted(red):
    for d, p in rng.sample(sorted(red[f]), min(10, len(red[f]))):
        add(d, p, f"ux-run red, {f}", kind(d, p))

for line in open("ops/ux-regression/set.tsv"):
    if line.startswith("#") or not line.strip(): continue
    src, pages = line.split("\t")[:2]
    for p in pages.split(","):
        add(src, int(p), "ux-regression set", kind(src, int(p)))
for doc, pages in [("owner/1954 - Why.pdf", "3 4 5 6 7 8 9"), ("owner/1951 - Briefer Book Notes.pdf", "1 2 3 4 5 6"),
                   ("owner/Raskin - 1956 - New Jobs Opening to Negro in North.pdf", "1"),
                   ("owner/Hughes - The Knitting of Racial Groups in Industry (Desktop copy 2026-09-26).pdf", "1 2 3 5 7 8 9")]:
    for p in pages.split():
        add(doc, int(p), "ux-harness selftest", kind(doc, int(p)))

best = {}
for (d, p), c in colour.items():
    if c > 0.05 and (d not in best or c > best[d][1]): best[d] = (p, c)
n = 0
for d, (p, c) in sorted(best.items(), key=lambda kv: -kv[1][1]):
    if n == 28: break
    if (d, p) not in seen:
        add(d, p, f"non-text candidate, source colour {c:.2f}", kind(d, p)); n += 1
ib = "book/Ibson_2006_Picturing men.pdf"
for p in rng.sample(sorted(p for (d, p) in route if d == ib), 8):
    add(ib, p, "non-text candidate, photograph book", kind(ib, p))

with open(sys.argv[1], "w") as f:
    f.write("document\tpage\twhy\troute\tstatus\n")
    for r in rows: f.write("\t".join(r) + "\n")
print(len(rows), "pages")
