#!/usr/bin/env python3
"""Survey a Zotero library: which PDFs are bigger than they should be?

    python3 Tools/sweep-zotero.py --out /tmp/zotero-sweep.tsv

**Read-only. It changes nothing**, and that is deliberate — this is step one of
the library sweep in TODO.md, and steps two and three (re-OCR the oversized files,
spreadsheet the photographed ones) act on a list a person has looked at first.
Nothing here should rewrite 16,000 of someone's documents on its own say-so.

**Per-page bytes against the item type, not raw size.** A 600-page book is
legitimately larger than a 12-page article, so ranking by raw size ranks by page
count and finds nothing. "Oversized" here means: this file costs far more per page
than other files of its own kind. R37 and R38 are the background — symbol-mode
JBIG2 in the *inputs* makes some sources tiny, and dense bilevel type used to
inflate catastrophically, one document by 9.45x.

**Only scans are candidates**, decided by `classify-source.swift` — the same
classifier the corpus gate uses to keep photographs out, and D1 is what happens
without it:

  - **scanned** — this app's job. An oversized one is a candidate for re-OCR.
  - **born-digital** — already has real text. Re-OCRing replaces good text with
    worse, so these are never candidates however large they are.
  - **photographed** — a different problem. Reported for review, never acted on.

The **classifier build** is imported from `sample-zotero.py` rather than copied;
two copies of how a scan is recognised would drift, and this register has R23, R29
and C20 to show for that. Its `classify()` is *not* reused, because it keeps only
the verdict and throws away the page count this tool exists to divide by — and its
`QUERY` is not reused either, for the reason on `QUERY` below (R50).
"""
import argparse, concurrent.futures as cf, csv, importlib.util
import os, shutil, sqlite3, statistics, subprocess, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# A scan has to cost at least this much per page before its size is worth
# questioning at all. Below it the file is small in absolute terms whatever the
# ratio says, and a 40 KB/page document that happens to be 4x its type's median
# is not worth anyone's attention.
FLOOR_BYTES_PER_PAGE = 150 * 1024

# How far above its own item type's median a scan has to sit to be called out.
# A ratio, because the types differ by more than a constant would survive.
OUTLIER_RATIO = 3.0


# **This file's own, not `sample-zotero.py`'s.** That one INNER JOINs the parent
# item, correctly, because it stratifies by item type and an attachment with no
# parent has no type to stratify by. Importing it here silently excluded every
# standalone attachment — 181 of them, 0.50 GB — and one was Robinson-Montana
# material that consequently missed the cold-storage archive (R50). A *sweep* has
# to see everything the library holds, so this LEFT JOINs and files the parentless
# ones under a pseudo-type of their own.
QUERY = """
SELECT COALESCE(it.typeName, '(standalone attachment)'),
       COALESCE(substr(dv.value, 1, 4), '?') AS yr,
       ia.path, ai.key, COALESCE(i.dateAdded, ai.dateAdded)
FROM itemAttachments ia
JOIN items ai ON ai.itemID = ia.itemID
LEFT JOIN items i ON i.itemID = ia.parentItemID
LEFT JOIN itemTypes it ON it.itemTypeID = i.itemTypeID
LEFT JOIN itemData id ON id.itemID = i.itemID AND id.fieldID =
      (SELECT fieldID FROM fields WHERE fieldName = 'date')
LEFT JOIN itemDataValues dv ON dv.valueID = id.valueID
WHERE ia.contentType = 'application/pdf' AND ia.path LIKE 'storage:%';
"""


def sampler():
    """`sample-zotero.py` as a module — its name has a hyphen, so not `import`."""
    path = os.path.join(REPO, "Tools", "sample-zotero.py")
    spec = importlib.util.spec_from_file_location("sample_zotero", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def classify_all(tool, paths, workers):
    """{path: (verdict, pages)} — every field the classifier prints, not just one."""
    out = {}
    batch = 12
    chunks = [paths[i:i + batch] for i in range(0, len(paths), batch)]

    def run(chunk):
        try:
            r = subprocess.run([tool] + chunk, capture_output=True, text=True,
                               timeout=600)
        except subprocess.TimeoutExpired:
            return {}
        found = {}
        for line in r.stdout.splitlines():
            f = line.split("\t")
            # verdict, pages, sampled, charsPerPage, maxImagePx, medianDPI,
            # saturation, illumination, path
            if len(f) >= 9:
                try:
                    found[f[8]] = (f[0], int(f[1]))
                except ValueError:
                    found[f[8]] = (f[0], 0)
        return found

    done = 0
    with cf.ThreadPoolExecutor(max_workers=workers) as pool:
        for result in pool.map(run, chunks):
            out.update(result)
            done += batch
            if done % 600 < batch:
                print(f"  {min(done, len(paths))}/{len(paths)}", flush=True)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zotero", default=os.path.expanduser("~/Zotero"))
    ap.add_argument("--out", default="/tmp/zotero-sweep.tsv")
    ap.add_argument("--limit", type=int, default=0, help="survey only the first N")
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    zs = sampler()

    db = os.path.join(args.zotero, "zotero.sqlite")
    if not os.path.exists(db):
        sys.exit(f"no zotero.sqlite at {db}")
    # A copy: Zotero holds a lock on the original while it is running, and this
    # has to be runnable without closing the user's library.
    with tempfile.TemporaryDirectory() as tmp:
        copy = os.path.join(tmp, "z.sqlite")
        shutil.copy2(db, copy)
        rows = sqlite3.connect(copy).execute(QUERY).fetchall()

    # Every PDF attachment, whatever its item type — including the ones with no
    # parent item at all. This comment claimed exactly that while the imported
    # query quietly made it false, which is how R50 happened: an assertion in a
    # comment is not a property of the code.
    records = {}
    for typ, yr, path, key, added in rows:
        if not path.startswith("storage:"):
            continue
        full = os.path.join(args.zotero, "storage", key,
                            path.split("storage:", 1)[1])
        if os.path.exists(full):
            records[full] = (typ or "unknown", yr or "?")
    paths = sorted(records)
    if args.limit:
        paths = paths[:args.limit]
    print(f"{len(paths)} PDF attachment(s) to survey", flush=True)

    print("building the classifier…", flush=True)
    tool = zs.build_classifier()
    print("classifying — the long part…", flush=True)
    verdicts = classify_all(tool, paths, args.workers)

    # Gather first, judge second: the threshold is a median over the library's
    # own scans, so it cannot be computed until every row exists.
    survey = []
    for p in paths:
        typ, yr = records[p]
        verdict, pages = verdicts.get(p, ("unseen", 0))
        try:
            size = os.path.getsize(p)
        except OSError:
            continue
        per_page = size / pages if pages > 0 else None
        survey.append({"path": p, "type": typ, "year": yr, "verdict": verdict,
                       "pages": pages, "bytes": size, "perPage": per_page})

    # Median per-page cost of the *scans* of each item type. Scans only: a type
    # whose median was dragged down by born-digital exports would call every scan
    # in it an outlier.
    medians = {}
    for typ in sorted({r["type"] for r in survey}):
        costs = [r["perPage"] for r in survey
                 if r["type"] == typ and r["verdict"] == "scanned" and r["perPage"]]
        if len(costs) >= 5:
            medians[typ] = statistics.median(costs)

    for r in survey:
        median = medians.get(r["type"])
        r["typeMedian"] = median
        r["ratio"] = (r["perPage"] / median) if median and r["perPage"] else None
        r["candidate"] = bool(
            r["verdict"] == "scanned" and r["perPage"]
            and r["perPage"] >= FLOOR_BYTES_PER_PAGE
            and r["ratio"] and r["ratio"] >= OUTLIER_RATIO)

    with open(args.out, "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["path", "itemType", "year", "verdict", "pages", "bytes",
                    "bytesPerPage", "typeMedianPerPage", "ratio", "candidate"])
        for r in sorted(survey, key=lambda r: -(r["ratio"] or 0)):
            w.writerow([r["path"], r["type"], r["year"], r["verdict"], r["pages"],
                        r["bytes"],
                        f"{r['perPage']:.0f}" if r["perPage"] else "",
                        f"{r['typeMedian']:.0f}" if r["typeMedian"] else "",
                        f"{r['ratio']:.2f}" if r["ratio"] else "",
                        "yes" if r["candidate"] else ""])

    counts = {}
    for r in survey:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    candidates = [r for r in survey if r["candidate"]]
    photographed = [r for r in survey if r["verdict"] == "photographed"]
    reclaimable = sum(int(r["bytes"] - (r["typeMedian"] or 0) * r["pages"])
                      for r in candidates)

    print(f"\n=== {len(survey)} attachments ===")
    for verdict, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {verdict:14s} {n}")
    print(f"\n  re-OCR candidates (scanned, >= {OUTLIER_RATIO}x their type's "
          f"median, >= {FLOOR_BYTES_PER_PAGE // 1024} KB/page): {len(candidates)}")
    print(f"  they hold {sum(r['bytes'] for r in candidates) / 2**30:.1f} GB; "
          f"at their type's median they would hold "
          f"{max(reclaimable, 0) / 2**30:.1f} GB less")
    print(f"  photographed, for review not action: {len(photographed)}")
    print("\n  per-page median by item type, over scans only:")
    for typ, median in sorted(medians.items(), key=lambda kv: -kv[1]):
        n = sum(1 for r in survey if r["type"] == typ and r["verdict"] == "scanned")
        print(f"    {typ:20s} {median / 1024:7.0f} KB/page   ({n} scans)")
    print(f"\n  full table: {args.out}")
    print("\n  Nothing has been changed. The next step re-OCRs the candidates and "
          "moves\n  the originals to ~/Downloads — read the table first.")


if __name__ == "__main__":
    main()
