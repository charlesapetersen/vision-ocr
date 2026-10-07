#!/usr/bin/env python3
"""score-bakeoff.py [--pages pages.tsv] — score the bake-off's saved readings against the truth set.

Scores each reading as `Tools/ux-harness.swift --truth` scores Vision's reading of the source (its `visMiss`):
the page's body words that are not contested, lower-cased to letters and digits (`norm`), matched as a
multiset against the reading's words. `miss` is the share of those words the reading lacks, which is words
wrong and words missing together: a word read wrong is a word missing from the bag. Order is not scored: a
crops reading repeats the overlap between crops and lists the crops in their own order, and an ordered
alignment would charge a model for the cut, not for its reading. `added` is the reading's words matched by
no transcript word (contested, figure and handwriting words included, so reading them is not counted
against a model), over the scored words.

The transcript is read as `loadTruth` reads it: `x y w h<TAB>text` lines up to `COLUMNS:`, a leading
`[fig]`/`[hand]` mark making a line figure or handwriting (scored apart, not here), `[table]` body, a
line-end hyphen joined to the next line's first word, then `contested-second.tsv` (else `contested.tsv`),
`[?]` words and `contested-harness.tsv` all unscored.

The reading scored for a page is the whole-page reading, and the crops reading on a newspaper, which the
job read as crops only; `crops_miss` is beside it wherever crops were read. A page the reader could not read
(a `.reason`: the guard killed it twice) counts as all missing, so every label is averaged over the same
pages; pages under 20 scored words are left out, as the harness gives them no `visMiss`. Readings have tags
stripped and transcripts do not, so on the two pages whose print holds a literal tag (s41, s42) Vision's
figure is up to 0.6 points off the harness's. Classes: `newspaper` by route;
`old` print for documents dated before 1985 (the year in the file name, or `YEAR` below); else `modern`.
Prints one row per label and page (`--pages`), the miss by route (`--routes`), and the summary per label and
class on stdout.
"""
import json, os, re, sys
from collections import Counter

STATE = os.environ.get("STATE", os.path.expanduser("~/.local/state/visionocr-autonomous"))
J, TRUTH = f"{STATE}/ocrlab", f"{STATE}/truth"
# documents with no year in the name: Hughes's typescript is dated 1946 in its text; Batzell's article and
# Naylor's thesis are recent (an 1870s subject, a 2006 thesis); Burke's page 1 is a modern journal's own page
YEAR = {"Hughes": 1946, "Batzell": 2014, "NAYLOR": 2006, "Burke": 2010}
DROPPED = {"qwen3.5-9b-4bit"}   # the owner dropped it after 8 pages (OCR-BAKEOFF-COUNT-2026-10-07.tsv)
# read 20:45-23:37 on 2026-10-04 while the owner, a Codex VM run and a Claude session shared the Mac (owner,
# 2026-10-05): their speed does not count until a quiet re-time; their words do
BUSY = {"deepseek-ocr-2-4bit", "lightonocr-2-1b-4bit-1540"}


def norm(s):
    return "".join(c for c in s.lower() if c.isalnum())


def tokens(s):
    s = re.sub(r"(?m)^\d+ \d+ \d+ \d+\t", "", s)      # line boxes, as rough-recall.py strips them
    # HTML, comments or grounding tags some models emit; a tag never spans a line, or a page printing a
    # literal `<span` (ProQuest's headers) loses everything up to the next `>`
    s = re.sub(r"<!--.*?-->|<[^<>\n]+>", " ", s, flags=re.S)
    return [w for w in (norm(x) for x in s.split()) if w]


def load_truth(d):
    lines, section = [], "lines"
    raw = open(f"{d}/transcript.txt", encoding="utf-8").read().replace("\r\n", "\n").replace("\r", "\n")
    for r in raw.split("\n"):
        if r.startswith("COLUMNS:"): section = "columns"; continue
        if r.startswith("OBJECTS:"): section = "objects"; continue
        if section != "lines": continue
        m = re.match(r"(?s)^\s*([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s*\t(.*)$", r)
        if not m: continue
        text, kind = m.group(5), "body"
        mm = re.match(r"^\s*(\[(fig|table|hand)\]\s*)+", text)
        if mm:
            kind = "fig" if "[fig]" in mm.group(0) else "hand" if "[hand]" in mm.group(0) else "body"
            text = text[mm.end():]
        lines.append((int(m.group(2)), text, kind))
    words = []   # [text, line, kind, contested]
    for li, (y, text, kind) in enumerate(lines):
        for w in text.split():
            p = words[-1] if words else None
            if p and re.search(r"\w-$", p[0]) and y > lines[p[1]][0] and (w[0].isalpha() or w[0].isdigit()):
                p[0] = p[0][:-1] + w
            else:
                words.append([w, li, kind, False])
    cf = f"{d}/contested-second.tsv" if os.path.exists(f"{d}/contested-second.tsv") else f"{d}/contested.tsv"
    for f in (cf, f"{d}/contested-harness.tsv"):
        if not os.path.exists(f): continue
        for row in open(f, encoding="utf-8").read().splitlines():
            c = row.split("\t")
            if not re.fullmatch(r"\d+", c[0]) or int(c[0]) >= len(words): continue
            # as loadTruth: a re-read row naming another word means the transcript moved; stop
            if f.endswith("harness.tsv") and len(c) > 1 and c[1] != words[int(c[0])][0]:
                sys.exit(f"score-bakeoff: {f}: word {c[0]} is {words[int(c[0])][0]!r} in the transcript, {c[1]!r} there")
            words[int(c[0])][3] = True
    for w in words:
        if "[?]" in w[0]: w[3] = True
    scored = [norm(w[0]) for w in words if w[2] == "body" and not w[3] and norm(w[0])]
    every = [norm(w[0]) for w in words if norm(w[0])]
    return scored, every


def matched(ref, got):
    have = Counter(got)
    n = 0
    for w in ref:
        if have[w] > 0: have[w] -= 1; n += 1
    return n


def year_of(doc):
    for k, v in YEAR.items():
        if k in doc: return v
    m = re.search(r"(?<!\d)(1[89]\d\d|20\d\d)(?!\d)", os.path.basename(doc))
    return int(m.group(1)) if m else None


def main():
    pages_out = sys.argv[sys.argv.index("--pages") + 1] if "--pages" in sys.argv else None
    sample = [l.rstrip("\n").split("\t") for l in open(f"{J}/sample.tsv", encoding="utf-8") if not l.startswith("#")]
    sample = [dict(zip(sample[0], r)) for r in sample[1:]]
    for s in sample:
        y = year_of(s["document"])
        s["cls"] = "newspaper" if s["route"] == "newspaper" else "old" if y and y < 1985 else "modern"
        s["truth"] = load_truth(f"{TRUTH}/{s['document'][:-4]}/p{s['page']}")
    labels = sorted(l for l in os.listdir(f"{J}/readings") if l not in DROPPED and os.path.isdir(f"{J}/readings/{l}"))
    rows, summary = [], {}
    for label in labels + ["vision.crops"]:
        for s in sample:
            scored, every = s["truth"]
            base = f"{J}/readings/{label.split('.')[0] if label == 'vision.crops' else label}/{s['id']}"
            def score(path):
                if not os.path.exists(path) or len(scored) < 20: return None
                got = tokens(open(path, encoding="utf-8", errors="replace").read())
                return 1 - matched(scored, got) / len(scored), (len(got) - matched(every, got)) / len(scored)
            whole, crops = score(f"{base}.txt"), score(f"{base}.crops.txt")
            # `vision.crops` is Vision reading every page as its crops: the app recognises in bands, never one
            # plain render scaled down, which on Briefer's typescript loses over half the words
            prim, used = (crops, "crops") if s["cls"] == "newspaper" or label == "vision.crops" else (whole, "whole")
            cut = 0
            js = f"{base}.crops.json" if used == "crops" else f"{base}.json"
            if os.path.exists(js):
                try: cut = int(json.loads(open(js).read().strip().splitlines()[-1]).get("cut", "-") != "-")
                except (ValueError, IndexError): pass
            reason = ""
            if prim is None:
                rf = f"{base}.crops.reason" if used == "crops" else f"{base}.reason"
                reason = open(rf).read().strip() if os.path.exists(rf) else "no reading"
            # under 20 scored words the harness gives no visMiss either
            if len(scored) < 20: prim, reason = None, "under 20 scored words"
            # a page a reader could not read (the guard killed it) is all missing: it is what that reader gives
            elif prim is None: prim = (1.0, 0.0)
            rows.append((label, s["id"], s["cls"], s["route"], len(scored), used, prim, crops, cut, reason))
            if prim is not None:
                a = summary.setdefault((label, s["cls"]), [0, 0.0, 0.0, 0, 0])
                a[0] += len(scored); a[1] += prim[0] * len(scored); a[2] += prim[1] * len(scored); a[3] += 1; a[4] += cut
    # The app's own published text layer, as `ux-harness --truth` measured it (`layerMiss`, the same match over
    # the page's whole layer) at 832b7ac in TRUTH-RUN-2026-09-30-pages.tsv
    run = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../TRUTH-RUN-2026-09-30-pages.tsv")
    hdr, layer = None, {}
    for l in open(run, encoding="utf-8"):
        if l.startswith("#"): continue
        f = l.rstrip("\n").split("\t")
        if hdr is None: hdr = f; continue
        r = dict(zip(hdr, f))
        if r["layerMiss"] not in ("-", ""): layer[(r["document"], r["page"])] = float(r["layerMiss"])
    for s in sample:
        n, v = len(s["truth"][0]), layer.get((s["document"], s["page"]))
        if len(s["truth"][0]) >= 20 and v is not None:
            a = summary.setdefault(("app-layer@832b7ac", s["cls"]), [0, 0.0, 0.0, 0, 0])
            a[0] += n; a[1] += v * n; a[3] += 1
    f4 = lambda v: "-" if v is None else f"{v:.4f}"
    if pages_out:
        with open(pages_out, "w") as f:
            f.write("label\tid\tclass\troute\tscored\tread\tmiss\tadded\tcrops_miss\tcut\treason\n")
            for r in rows:
                f.write("\t".join([r[0], r[1], r[2], r[3], str(r[4]), r[5], f4(r[6] and r[6][0]), f4(r[6] and r[6][1]),
                                   f4(r[7] and r[7][0]), str(r[8]), r[9]]) + "\n")
    # Speed and memory: each read's seconds and peak MB from the job's log (the guard's figures), whole reads
    # and crops reads apart; from `time-reads.sh`'s times.tsv (`--times`) for Vision, never timed by the job,
    # and for the labels it re-read on a quiet machine, whose log figures are then given only for those pages.
    speed = {}
    for l in open(f"{J}/bakeoff.log", encoding="utf-8"):
        f = l.rstrip("\n").split("\t")
        if len(f) > 6 and f[4] == "read":
            speed.setdefault((f[1], f[3]), []).append((f[2], float(f[5].rstrip("s")), int(f[6].rstrip("MB"))))
    quiet = {}
    if "--times" in sys.argv:
        for l in list(open(sys.argv[sys.argv.index("--times") + 1], encoding="utf-8"))[1:]:
            f = l.rstrip("\n").split("\t")
            # a failed read (exit not 0) is not a reading's time; load1 is kept to say how quiet it was
            if f[3] and (len(f) < 7 or f[6] == "0"):
                quiet.setdefault((f[0], f[2]), []).append((f[1], float(f[3]), int(f[4] or 0), float(f[5])))
    def sp(reads, ids=None):
        r = [x for x in reads if ids is None or x[0] in ids]
        return (f"{sum(x[1] for x in r) / len(r):.1f}", str(max(x[2] for x in r))) if r else ("-", "-")
    cols = ["old", "newspaper", "modern"]
    if "--routes" in sys.argv:   # the same miss by the app's route, as the truth run reports it
        by = {}
        for r in rows:
            if r[6] is not None:
                a = by.setdefault((r[0], r[3]), [0, 0.0]); a[0] += r[4]; a[1] += r[6][0] * r[4]
        routes = sorted({k[1] for k in by})
        with open(sys.argv[sys.argv.index("--routes") + 1], "w") as f:
            f.write("label\t" + "\t".join(routes) + "\n")
            for label in labels + ["vision.crops"]:
                f.write(label + "\t" + "\t".join(f"{by[(label, rt)][1] / by[(label, rt)][0]:.4f}" if (label, rt) in by else "-"
                                                for rt in routes) + "\n")
            f.write("words\t" + "\t".join(str(by[("vision", rt)][0]) for rt in routes) + "\n")
    print("label\t" + "\t".join(f"{c}_miss\t{c}_added" for c in cols) + "\tpages\tunread\tcut"
          "\twhole_s\twhole_peak_mb\tcrops_s\tcrops_peak_mb\ttimed")
    for label in labels + ["vision.crops", "app-layer@832b7ac"]:
        cells = []
        for c in cols:
            a = summary.get((label, c))
            cells += [f"{a[1] / a[0]:.4f}" if a else "-",
                      "-" if not a or label.startswith("app-layer") else f"{a[2] / a[0]:.4f}"]
        n = sum(summary.get((label, c), [0] * 5)[3] for c in cols)
        cut = sum(summary.get((label, c), [0] * 5)[4] for c in cols)
        unscored = sum(1 for r in rows if r[0] == label and r[9] and not r[9].startswith("under 20"))
        key = "vision" if label == "vision.crops" else label
        if (key, "whole") in quiet:
            ids = {x[0] for x in quiet[(key, "whole")]}
            w, c = sp(quiet[(key, "whole")]), sp(quiet.get((key, "crops"), []))
            loads = [x[3] for x in quiet[(key, "whole")] + quiet.get((key, "crops"), [])]
            timed = f"time-reads.sh on {len(ids)} pages, guarded, load {min(loads):.1f}-{max(loads):.1f}"
            if key != "vision":
                lw = sp(speed.get((key, "whole"), []), ids)
                timed += f", whole only (the job's log, busy, on the same pages: {lw[0]} s); crops from the job's log, busy"
                c = sp(speed.get((key, "crops"), []))
        elif label.startswith("app-layer"):
            w = c = ("-", "-"); timed = "-"
        else:
            w, c, timed = sp(speed.get((key, "whole"), [])), sp(speed.get((key, "crops"), [])), "the job's log"
            if key in BUSY: timed += ", BUSY machine: not counted until re-timed"
        print("\t".join([label] + cells + [str(n), str(unscored), str(cut), w[0], w[1], c[0], c[1], timed]))

if __name__ == "__main__":
    main()
