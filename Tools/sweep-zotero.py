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
  - **textual** — added by A12.4 — and **no-page-image**, which predates it. Both
    rejected like the rest.
    A12.4 also means the verdicts differ from any run before 2026-08-15: the
    classifier asks the app's own two questions now, and on the 233-document
    corpus that moved 2 documents from `scanned` to `born-digital`.

**A comparison basis, printed on every row.** "Its own kind" needs enough files of
that kind to have a median worth dividing by, and `MINIMUM_SCANS_FOR_MEDIAN` below
carries the measurement of how many. A type with fewer is compared to the
library-wide scan median instead, with `basis=library`, and its outliers are marked
`review` rather than `candidate` — visible to a person, never acted on unread. R54
is why, and R54 is not only about the type it names: on the 2026-08-13 run **eight**
item types had too few scans for their own median, and one of them — `blogPost`,
5 scans — held the highest median in the table.

The **classifier build and its output parser** are both imported from
`sample-zotero.py` rather than copied; two copies of how a scan is recognised
would drift, and this register has R23, R29 and C20 to show for that. Its
`QUERY` is not reused, for the reason on `QUERY` below (R50).

This file used to keep its own copy of the parser, on the stated grounds that
`classify()` "keeps only the verdict and throws away the page count this tool
exists to divide by". That was true and it was the wrong remedy: the copy carried
the column layout with it, so when A12.4 added two columns to the classifier the
layout had to be right in two files at once. `classify_rows` hands back every
field; `classify()` is the one-field convenience built on it.
"""
import argparse, csv, importlib.util
import os, shutil, sqlite3, statistics, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# A scan has to cost at least this much per page before its size is worth
# questioning at all. Below it the file is small in absolute terms whatever the
# ratio says, and a 40 KB/page document that happens to be 4x its type's median
# is not worth anyone's attention.
FLOOR_BYTES_PER_PAGE = 150 * 1024

# How far above its own item type's median a scan has to sit to be called out.
# A ratio, because the types differ by more than a constant would survive.
OUTLIER_RATIO = 3.0

# How many scans an item type needs before its median is used as that type's
# characteristic cost. **Measured, not chosen** — R54 is what the old value of 5
# cost, and the fix is not about the one type R54 named.
#
# Bootstrap over the 2026-08-13 whole-library run, 2,000 draws a cell: p90 of
# |median over n files / median over all of that type's scans - 1|.
#
#   type              scans    n=5   n=10   n=20   n=50  n=100
#   journalArticle     5026    72%    47%    35%    22%    15%
#   book               1414   102%    72%    52%    28%    20%
#   newspaperArticle    852    94%    64%    50%    34%    22%
#   thesis              562    20%    13%    10%     7%     5%
#   document            349   135%    75%    55%    37%    28%
#   magazineArticle     323   275%   167%   100%    59%    34%
#   bookSection         287   183%   111%    57%    32%    22%
#
# A denominator a third too small turns a file at 2.0x its type's real cost into
# a 3.0x candidate, and OUTLIER_RATIO is 3.0 — so an error of that size is not a
# rounding matter, it is the whole test. n=5 admits errors up to 275%. 100 is
# where the worst-behaved type first comes under ~35%.
#
# The table lists the seven types with 250+ scans; `report`, at 108, is the eighth
# that clears 100. **Those eight hold 8,921 of the run's 9,106 scans — 98.0%.**
# Summing the table alone gives 8,813 and 96.8%, which is the wrong denominator for
# this sentence and was caught by a reviewer doing exactly that.
#
# The rest — bill, webpage, manuscript, hearing, letter, conferencePaper, blogPost,
# presentation, and the parentless attachments R54 is filed against — are
# reported against the library-wide scan median instead, with `basis` saying so,
# and are **not** called candidates. `blogPost` is the reason that matters in both
# directions: 5 scans, and the highest median in the table at 430 KB/page, used as
# the divisor for those same 5 files.
MINIMUM_SCANS_FOR_MEDIAN = 100


# **This file's own, not `sample-zotero.py`'s.** That one INNER JOINs the parent
# item, correctly, because it stratifies by item type and an attachment with no
# parent has no type to stratify by. Importing it here silently excluded every
# standalone attachment — 181 of them, 0.50 GB — and one was Robinson-Montana
# material that consequently missed the cold-storage archive (R50). A *sweep* has
# to see everything the library holds, so this LEFT JOINs and files the parentless
# ones under a pseudo-type of their own.
#
# **The pseudo-type is a label, not a kind**, which is R54. Re-measured 2026-08-15:
# 181 parentless PDF attachments still on disk out of **15,367** — the LEFT JOIN
# finds exactly 181 more than the INNER one — and of those 181 the repaired
# classifier calls **160 born-digital, 16 scanned, 3 photographed, 1 no-page-image,
# 1 unreadable**. So the pooled median R54 objected to stood on 16 files, not 181,
# and their per-page spread is IQR/median **7.92** against 1.21 for the median real
# item type and 3.17 for the widest one. R54's own "181 of 15,901" divided by the
# population of the run *before* the LEFT JOIN, which excluded them.
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


def classify_all(zs, tool, paths, workers):
    """{path: (verdict, pages)} — two of the fields `classify_rows` returns."""
    out = {}
    for path, row in zs.classify_rows(tool, paths, workers, progress=600).items():
        try:
            pages = int(row["pages"])
        except ValueError:
            pages = 0
        out[path] = (row["verdict"], pages)
    return out


def judge(survey):
    """Fill in `basis`, `typeMedian`, `ratio`, `candidate` and `review` in place.

    Separate from `main` so `--self-test` can drive it: this is where R54 lived,
    and it is arithmetic over a list of dicts with no library and no classifier
    anywhere near it. Returns the medians it used, the types too small to have
    one, the library-wide median, and the per-type cost lists.
    """
    # Median per-page cost of the *scans* of each item type. Scans only: a type
    # whose median was dragged down by born-digital exports would call every scan
    # in it an outlier.
    scan_costs = {}
    for r in survey:
        if r["verdict"] == "scanned" and r["perPage"]:
            scan_costs.setdefault(r["type"], []).append(r["perPage"])
    medians = {typ: statistics.median(costs) for typ, costs in scan_costs.items()
               if len(costs) >= MINIMUM_SCANS_FOR_MEDIAN}
    small = {typ: len(costs) for typ, costs in scan_costs.items()
             if typ not in medians}

    # The fallback basis, over every scan in the library. Not a substitute for a
    # type's own median — it pools types whose medians run 40 to 430 KB/page — and
    # that is the point: a ratio against it is worth *reading*, never worth acting
    # on unread, so nothing computed from it becomes a candidate.
    all_scans = [c for costs in scan_costs.values() for c in costs]
    library_median = statistics.median(all_scans) if all_scans else None

    for r in survey:
        median = medians.get(r["type"])
        r["basis"] = "type" if median else ("library" if library_median else "")
        if not median:
            median = library_median
        r["typeMedian"] = median
        r["ratio"] = (r["perPage"] / median) if median and r["perPage"] else None
        outlier = bool(
            r["verdict"] == "scanned" and r["perPage"]
            and r["perPage"] >= FLOOR_BYTES_PER_PAGE
            and r["ratio"] and r["ratio"] >= OUTLIER_RATIO)
        # A candidate is a file the next step may act on unread, so it needs a
        # comparison to its *own* kind. An outlier on the library basis is a file
        # for a person to look at, which is a different claim and gets a different
        # column value rather than being folded into this one or dropped from the
        # table. R54's parentless attachments are 181 files and 0.50 GB; dropping
        # them is what the import bug it came from already did once.
        r["candidate"] = outlier and r["basis"] == "type"
        r["review"] = outlier and r["basis"] != "type"

    return medians, small, library_median, scan_costs, all_scans


def self_test():
    """Check `judge`. `--self-test`, run by the pre-commit hook when staged.

    R54's whole content is a denominator taken over the wrong population, and
    nothing in this file could have noticed: `judge` never ran outside a real
    sweep, which needs a Zotero library and half an hour of rendering. It takes a
    list of dicts, so it can be driven directly.
    """
    failures = []

    def check(name, ok):
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
        if not ok:
            failures.append(name)

    kb = 1024

    def rec(typ, per_page_kb, verdict="scanned", pages=10):
        return {"path": f"/{typ}-{per_page_kb}-{id(object()):x}.pdf", "type": typ,
                "year": "2000", "verdict": verdict, "pages": pages,
                "bytes": int(per_page_kb * kb * pages), "perPage": per_page_kb * kb}

    # A big type at 100 KB/page, an under-populated one at the same cost, and one
    # oversized file in each. Same numbers on both sides of the line, so the only
    # thing that differs is how many files stand behind the median.
    survey = [rec("journalArticle", 100) for _ in range(MINIMUM_SCANS_FOR_MEDIAN)]
    survey += [rec("blogPost", 100) for _ in range(5)]
    big_outlier = rec("journalArticle", 400)
    small_outlier = rec("blogPost", 400)
    # A parentless attachment: the pseudo-type R54 is filed against, which gets no
    # special case anywhere in `judge` — it is under-populated, and that is all.
    parentless = rec("(standalone attachment)", 400)
    # A cheap, well-populated type, so the floor can be tested by something the
    # ratio does *not* also reject. `tiny` is 4.0x its type's median and 40 KB a
    # page: over the outlier ratio, under the floor, and the floor is the only
    # reason it is not a candidate. The first version of this check used a file
    # that failed the ratio test too, so it passed with FLOOR_BYTES_PER_PAGE
    # deleted — a check that cannot fail, in a self-test written to catch one.
    survey += [rec("thesis", 10) for _ in range(MINIMUM_SCANS_FOR_MEDIAN)]
    tiny = rec("thesis", 40)
    survey += [big_outlier, small_outlier, parentless, tiny]

    medians, small, library_median, _, _ = judge(survey)

    check("a type with enough scans gets its own median",
          "journalArticle" in medians)
    check(f"a type with fewer than {MINIMUM_SCANS_FOR_MEDIAN} does not",
          "blogPost" in small and "blogPost" not in medians)
    check("the parentless pseudo-type is treated as exactly that, an under-"
          "populated type", "(standalone attachment)" in small)
    check("a well-populated type's outlier is a candidate",
          big_outlier["candidate"] and not big_outlier["review"])
    check("the same file in an under-populated type is 'review', not a candidate",
          small_outlier["review"] and not small_outlier["candidate"])
    check("...and so is the parentless one",
          parentless["review"] and not parentless["candidate"])
    check("an under-populated row still gets a ratio, on the library basis",
          small_outlier["basis"] == "library" and small_outlier["ratio"] is not None)
    check("a well-populated row says so",
          big_outlier["basis"] == "type")
    check("a file over the outlier ratio but under the floor is neither",
          tiny["ratio"] >= OUTLIER_RATIO
          and tiny["perPage"] < FLOOR_BYTES_PER_PAGE
          and not tiny["candidate"] and not tiny["review"])
    check("every candidate has a real median behind it, so 'GB reclaimable' "
          "cannot silently subtract zero",
          all(r["typeMedian"] for r in survey if r["candidate"]))
    check("the library median is over every scan, not every file",
          library_median == statistics.median(
              [r["perPage"] for r in survey if r["verdict"] == "scanned"]))

    # Born-digital and photographed files are never candidates however large, and
    # never enter a median. The tool's docstring promises both.
    born = rec("journalArticle", 4000, verdict="born-digital")
    photo = rec("journalArticle", 4000, verdict="photographed")
    survey2 = [rec("journalArticle", 100) for _ in range(MINIMUM_SCANS_FOR_MEDIAN)]
    survey2 += [born, photo]
    medians2, _, _, costs2, _ = judge(survey2)
    check("a born-digital file is never a candidate", not born["candidate"])
    check("a photographed file is never a candidate", not photo["candidate"])
    check("neither enters its type's median",
          len(costs2["journalArticle"]) == MINIMUM_SCANS_FOR_MEDIAN)

    # A type with **no scans at all** — every file in it born-digital, which is the
    # common case in a real library. It has no median of its own, so its rows take
    # the library basis; `small` cannot see it, because `small` is built from the
    # per-type scan lists and this type has none. The report has to count these,
    # and the first version could not.
    webpages = [rec("webpage", 900, verdict="born-digital") for _ in range(40)]
    survey3 = [rec("journalArticle", 100) for _ in range(MINIMUM_SCANS_FOR_MEDIAN)]
    survey3 += webpages
    _, small3, _, costs3, _ = judge(survey3)
    check("a type with no scans at all still takes the library basis",
          all(r["basis"] == "library" for r in webpages))
    check("…and is invisible to `small`, so the report must not count from it",
          "webpage" not in small3 and "webpage" not in costs3)
    borrowed3 = {}
    for r in survey3:
        if r["basis"] == "library":
            borrowed3[r["type"]] = borrowed3.get(r["type"], 0) + 1
    check("…and the report's own counting names it and adds up",
          borrowed3 == {"webpage": 40})

    print(f"self-test: {len(failures)} failure(s)")
    return 1 if failures else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true",
                    help="check the outlier judgement against a synthetic "
                         "survey, and exit")
    ap.add_argument("--zotero", default=os.path.expanduser("~/Zotero"))
    ap.add_argument("--out", default="/tmp/zotero-sweep.tsv")
    ap.add_argument("--limit", type=int, default=0, help="survey only the first N")
    ap.add_argument("--workers", type=int, default=8)
    args = ap.parse_args()

    if args.self_test:
        sys.exit(self_test())

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
    verdicts = classify_all(zs, tool, paths, args.workers)

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

    medians, small, library_median, scan_costs, all_scans = judge(survey)

    with open(args.out, "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["path", "itemType", "year", "verdict", "pages", "bytes",
                    "bytesPerPage", "medianPerPage", "basis", "ratio", "candidate"])
        # Candidates first, then the rows compared to their own kind, then the
        # library-basis ones — whose ratios are inflated for any type that is
        # dearer per page than the library average, and would otherwise sit at the
        # top of the table looking like the worst offenders in it.
        order = sorted(survey, key=lambda r: (not r["candidate"],
                                              r["basis"] != "type",
                                              -(r["ratio"] or 0)))
        for r in order:
            w.writerow([r["path"], r["type"], r["year"], r["verdict"], r["pages"],
                        r["bytes"],
                        f"{r['perPage']:.0f}" if r["perPage"] else "",
                        f"{r['typeMedian']:.0f}" if r["typeMedian"] else "",
                        r["basis"],
                        f"{r['ratio']:.2f}" if r["ratio"] else "",
                        "yes" if r["candidate"] else ("review" if r["review"] else "")])

    counts = {}
    for r in survey:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    candidates = [r for r in survey if r["candidate"]]
    review = [r for r in survey if r["review"]]
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
        print(f"    {typ:23s} {median / 1024:7.0f} KB/page   "
              f"({len(scan_costs[typ])} scans)")

    # Said out loud, every run. A type quietly borrowing the library's median is
    # the shape R54 is: 181 files were compared to a "type" that was 16
    # heterogeneous scans wearing a pseudo-type's name, and nothing in the output
    # said which files those were or that anything had happened.
    if library_median:
        print(f"\n  library-wide scan median: {library_median / 1024:.0f} KB/page "
              f"over {len(all_scans)} scans")
    # Counted over the rows that actually took the library basis, not over
    # `small`. `small` is built from `scan_costs`, so a type with **zero** scans —
    # every file in it born-digital, which is the common case in a real library —
    # never appears there while all of its rows still carry `basis=library`. The
    # first version listed `small`, printed the row count for *every* borrowing
    # type beside it, and so reported "45 file(s) in those types" over 5: a
    # 9x over-count and 40 files in a type it had not named. Exactly the silence
    # this block was added to end.
    borrowed = {}
    for r in survey:
        if r["basis"] == "library":
            borrowed.setdefault(r["type"], 0)
            borrowed[r["type"]] += 1
    if borrowed:
        print(f"  {len(borrowed)} item type(s) have fewer than "
              f"{MINIMUM_SCANS_FOR_MEDIAN} scans of their own, so no median of "
              f"theirs is that type's cost:")
        for typ, files in sorted(borrowed.items(), key=lambda kv: -kv[1]):
            print(f"    {typ:23s} {files:5d} file(s), "
                  f"{len(scan_costs.get(typ, []))} of them scans")
        print(f"  {sum(borrowed.values())} file(s) in those types are reported "
              f"against the library-wide median, basis=library.")
        print(f"  {len(review)} of them clear the outlier test on that basis — "
              f"'review' in the table, NOT candidates: a ratio against a pooled "
              f"median is not a comparison to a file's own kind.")
    print(f"\n  full table: {args.out}")
    print("\n  Nothing has been changed. The next step re-OCRs the candidates and "
          "moves\n  the originals to ~/Downloads — read the table first.")


if __name__ == "__main__":
    main()
