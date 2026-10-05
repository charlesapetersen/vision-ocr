"""make-sample.py <out.tsv> — the bake-off sample, from the truth set's own lists.

    $OCRLAB/venv/bin/python ops/ocrlab/make-sample.py OCR-SAMPLE-<date>.tsv

Takes, in this order and without repeats: every TRUTH-PAGES page of the regression set and the
ux-harness self-test, every newspaper, then 20 pages the truth run classed green, drawn with a fixed
seed round-robin over their routes so each route is represented. Only pages with a transcript in
$STATE/truth/ are taken (the scorer needs one). Ids are s01... in that order; the readings use them.
"""
import os, random, sys

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.dirname(os.path.dirname(here))
state = os.environ.get("STATE", os.path.expanduser("~/.local/state/visionocr-autonomous"))

def rows(path):
    lines = [l for l in open(os.path.join(repo, path), encoding="utf-8").read().splitlines() if not l.startswith("#")]
    head = lines[0].split("\t")
    return [dict(zip(head, l.split("\t"))) for l in lines[1:]]

pages = rows("TRUTH-PAGES-2026-09-29.tsv")
classes = {(r["document"], r["page"]): r["class"] for r in rows("TRUTH-RUN-2026-09-30-pages.tsv")}
has_truth = lambda r: os.path.exists(f"{state}/truth/{r['document'][:-4]}/p{r['page']}/transcript.txt")

picked, seen = [], set()
def take(r, why):
    k = (r["document"], r["page"])
    if k in seen or not has_truth(r): return
    seen.add(k); picked.append((r, why))

for r in pages:
    if r["why"].startswith(("ux-regression set", "ux-harness selftest")): take(r, r["why"].split(",")[0])
for r in pages:
    if r["route"] == "newspaper": take(r, "newspaper")
rng = random.Random(20261004)
by_route = {}
for r in pages:
    if classes.get((r["document"], r["page"])) == "green" and (r["document"], r["page"]) not in seen and has_truth(r):
        by_route.setdefault(r["route"], []).append(r)
for v in by_route.values(): rng.shuffle(v)
routes, n = sorted(by_route), 0
while n < 20 and any(by_route.values()):
    for route in routes:
        if n < 20 and by_route[route]:
            take(by_route[route].pop(), "green draw"); n += 1

with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write("# OCR-SAMPLE: the ocr-bakeoff sample, made by ops/ocrlab/make-sample.py from TRUTH-PAGES-2026-09-29.tsv and\n"
            "# TRUTH-RUN-2026-09-30-pages.tsv (green draw: seed 20261004, round-robin over routes). The queue item\n"
            "# counted 45 regression and self-test pages; TRUTH-PAGES holds 39 (31 + 8), and three newspapers are among them.\n")
    f.write("id\tdocument\tpage\troute\twhy\tclass\n")
    for i, (r, why) in enumerate(picked, 1):
        f.write(f"s{i:02d}\t{r['document']}\t{r['page']}\t{r['route']}\t{why}\t{classes.get((r['document'], r['page']), '-')}\n")
print(f"{len(picked)} pages", file=sys.stderr)
