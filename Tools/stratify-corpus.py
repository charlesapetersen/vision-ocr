#!/usr/bin/env python3
"""Scale a sampled per-page measurement to the whole corpus, one document at a time.

    python3 Tools/stratify-corpus.py --rows INKBAR-2026-08-19.tsv \
        --sample INKBAR-2026-08-19.tsv \
        --where inkOut:ge:0.045 --where inkOut:lt:0.08 --where barDelta:ne:same \
        --bytes layered,layeredAtBar --verbose

    python3 Tools/stratify-corpus.py --rows SHAPETERM-BYTES-2026-08-21.tsv \
        --sample INKBAR-2026-08-19.tsv --where lineN:ge:1 --bytes layered,layeredAtBar

    python3 Tools/stratify-corpus.py --control          # reproduce C26's published figures
    python3 Tools/stratify-corpus.py --self-test        # 0 corpus reads except the control block

Note the shape of the second invocation, because it is the one that generalises: `--rows` is a
**73-row subset** of a 2,129-row sample and `--sample` is the sweep the subset was drawn from. Both
files must be named; the identity check below is what makes getting it wrong loud.

**This exists because the obvious estimate is measurably 5.96x high, and that number
is this project's own.** `Flattener.sampleIndices` takes up to 12 pages from a document
whatever its length, so a page in a 1-page document is sampled with certainty and a page
in a 40-page one with probability 12/40. Pooling — "16 of 2,129 sampled pages moved, so
16/2129 of 16,987 pages move" — therefore weights every sampled page equally when they
carry wildly different numbers of unsampled siblings. C26 published both numbers: pooled
says ~130 pages and ~24 MB, per-document says ~21 pages and ~4.0 MB, and the pooled one
was retracted. That retraction was arithmetic in a session and left nothing runnable
behind; this file is the runnable version, and its `--control` mode asserts the six
figures C26 published so a change here cannot quietly move them.

**The estimator.** For each document *d* with `pages_d` pages in the corpus census and
`sampled_d` rows in the sample, and `hit_d` of those rows selected by the predicate:

    stratified = Σ_d  hit_d · pages_d / sampled_d

and the same expression with a byte delta in place of the count. A document sampled
completely (`sampled_d == pages_d`) contributes its own measured value with no scaling at
all, so the estimate carries an **exact** subtotal alongside it: that part of the
corpus-level claim rests on no assumption about an unsampled page, and it is the honest
thing to quote when the estimate is challenged. ⚠️ It is a **no-scaling** subtotal and not
"the part that was measured" — every selected row was measured, whatever its document's
sampling rate. Reporting it as the measured share understated the measurement by ~5x in
one draft that quoted this file. `--verbose` prints the per-document breakdown, which is where a single long
document dominating an estimate becomes visible — in C26's band, 68% of one figure was
one 300-page document, and that is the sort of fact a total hides.

**What it does not claim.** The estimator assumes a document's unsampled pages behave
like its sampled ones. That is an assumption, not a measurement, and it is the whole
reason the exact subtotal is printed beside the estimate. It also assumes the census's
page count is the population the sample was drawn from; `--sample` is required rather
than defaulted to `--rows` precisely because getting that denominator wrong is the easy
mistake and it inflates: using a 73-row subset's own per-document counts as the
denominator reads `Jones et al_2010` as 3 of 5 rather than 3 of 12, and 9.00 rather than
3.75 pages. So the identity check below is mandatory.

**The mandatory identity check.** Every (`document`, `page`) pair in `--rows` must exist
in `--sample`. A `--rows` file that is not a subset of the sample it is being scaled
against is a wrong-file error rather than a small bias, and it exits 3 instead of
printing. This is the same class as the throwaway lookup in C28's picture arm that keyed
`"p" + page` against a column already reading `p6` and reported 0 of 10 — §3 of
`CLAUDE.md`, the instrument measuring itself. Here the instrument refuses instead.

Columns: `--rows` and `--sample` need `document` and `page`; the census needs `path` and
`pages`. `--where COL:OP:VALUE` is repeatable and ANDed, with OP in
`ge gt le lt eq ne`; `ge/gt/le/lt` compare as floats and refuse a non-numeric cell in a
row that reaches them, `eq/ne` compare as strings. `--bytes BEFORE,AFTER` prices the
selection as `after - before` per row and refuses a non-numeric cell in a selected row —
a `-` silently read as 0 would understate a total, which is the direction that makes a
fix look cheap.

Exit codes: 1 an unreadable or malformed input file (a missing column included), 2
refused arguments, 3 the identity check (rows not a subset of the sample, or duplicate
keys in either), 4 a census problem (a document missing, or more sampled rows than the
document has pages), 5 a non-numeric cell where a number is required, 6 a failed
`--self-test` or `--control`, **7 an empty selection** — `--allow-empty` if you meant it.

⛔ **Three of those refusals used to be unreachable and the review of this file's own diff
found them.** The `--where` and `--bytes` column checks lived inside the per-row loops, so
`--bytes layered,NOSUCHCOL` over a predicate that selected nothing printed `+0 B` on exit
0, and an `eq`/`ne` clause on a misspelled column was never existence-checked when an
earlier clause had already excluded every row. Columns are now validated against the
header before any row is read, and an empty selection is exit 7 rather than a
publishable-looking `0.00 pages / +0 B` — the silent-success defect `score-corpus` and
`score-threshold-loss` both had.
"""

import argparse
import io
import os
import shutil
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_CENSUS = os.path.join(REPO, "CORPUS-2026-08-15.tsv")
CENSUS_PREFIX = "testdocs/"

# Measured by running `--self-test`. The last check asserts that this many ran, so a
# case deleted or short-circuited by an early `return` cannot pass unnoticed — the trap
# `sweep-ink-bar.py` carries the same guard for.
EXPECTED_CHECKS = 54

# C26's published corpus figures for the `[0.045, 0.08)` band, from `BUGS.md` C26 and
# `CLAUDE.md`. `--control` asserts every one of them against the committed sweep, so this
# file cannot start disagreeing with the register in silence.
CONTROL = {
    "rows": "INKBAR-2026-08-19.tsv",
    "sample": "INKBAR-2026-08-19.tsv",
    "where": ["inkOut:ge:0.045", "inkOut:lt:0.08", "barDelta:ne:same"],
    "bytes": "layered,layeredAtBar",
    # published                                          measured here
    "sampled_pages": 16,                               # 16 of the band's 17 move
    "docs": 10,                                        # over 10 documents of 233
    "sampled_bytes": 2965653,                          # +2,965,653 B
    "strat_pages_round": 21,                           # "~21 pages of 16,987"
    "strat_bytes_mb": 4.0,                             # "~4.0 MB"
    "pooled_over_strat": 5.96,                         # "6x high, retracted"
    "exact_bytes": 1489670,                            # "1,489,670 B are exact"
    "exact_pages": 8,                                  # "8 pages … are exact"
    "fully_sampled_docs": 86,                          # "86 documents were sampled completely"
    "corpus_pages": 16987,
    "sample_rows": 2129,
}


def die(code, message):
    sys.stderr.write("stratify-corpus: " + message + "\n")
    sys.exit(code)


def read_tsv(path):
    """Header and rows of a TSV, skipping blank lines and `#` comments.

    Every dated record in this repo carries a `# bar=… corpus=… binary=…` provenance
    line under its header, so skipping `#` is not optional politeness.
    """
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().split("\n")
    except OSError as err:
        die(1, "cannot read %s: %s" % (path, err))
    header, rows = None, []
    for line in lines:
        if not line.strip() or line.startswith("#"):
            continue
        cells = line.split("\t")
        if header is None:
            header = cells
            continue
        # A torn final row is short rather than absent; pad so a missing trailing cell
        # reads as empty and is refused by whatever asks it for a number, rather than
        # raising an IndexError three functions away.
        if len(cells) < len(header):
            cells = cells + [""] * (len(header) - len(cells))
        rows.append(dict(zip(header, cells)))
    if header is None:
        die(1, "%s has no header row" % path)
    return header, rows


def need_columns(path, header, wanted):
    missing = [c for c in wanted if c not in header]
    if missing:
        die(1, "%s is missing column(s): %s" % (path, ", ".join(missing)))


def read_census(path):
    """{document: pages} keyed the way a per-page TSV names its documents."""
    header, rows = read_tsv(path)
    need_columns(path, header, ["path", "pages"])
    census = {}
    for row in rows:
        doc = row["path"]
        if doc.startswith(CENSUS_PREFIX):
            doc = doc[len(CENSUS_PREFIX):]
        if doc in census:
            # Last-wins on a duplicate path would silently pick one of two page counts and
            # every factor in the run would divide by it. Refused for the same reason a
            # duplicated sample row is.
            die(3, "the census names %s twice — one of its two page counts would silently "
                   "win every scale factor in this run" % doc)
        try:
            census[doc] = int(row["pages"])
        except ValueError:
            die(5, "census row %s has a non-numeric pages cell %r" % (doc, row["pages"]))
    return census


def parse_where(specs):
    ops = {"ge", "gt", "le", "lt", "eq", "ne"}
    out = []
    for spec in specs:
        parts = spec.split(":", 2)
        if len(parts) != 3:
            die(2, "--where wants COL:OP:VALUE, got %r" % spec)
        col, op, value = parts
        if op not in ops:
            die(2, "--where op must be one of %s, got %r" % (" ".join(sorted(ops)), op))
        out.append((col, op, value))
    return out


def matches(row, wheres, source):
    for col, op, value in wheres:
        if col not in row:
            die(1, "%s has no column %r for --where" % (source, col))
        cell = row[col]
        if op in ("eq", "ne"):
            hit = (cell == value) if op == "eq" else (cell != value)
        else:
            try:
                left, right = float(cell), float(value)
            except ValueError:
                # A `-` in a numeric comparison is not a small error: on this corpus it
                # marks a page the layering decision never reached, and reading it as 0
                # would sweep every such page into an `inkOut:lt:` selection.
                return False
            hit = {"ge": left >= right, "gt": left > right,
                   "le": left <= right, "lt": left < right}[op]
        if not hit:
            return False
    return True


def numeric_where_skips(rows, wheres, source):
    """Rows a numeric --where could not read. Reported, never silently dropped."""
    skipped = 0
    for row in rows:
        for col, op, value in wheres:
            if op in ("eq", "ne"):
                continue
            if col not in row:
                die(1, "%s has no column %r for --where" % (source, col))
            try:
                float(row[col])
            except ValueError:
                skipped += 1
                break
    return skipped


def estimate(selected, sample_counts, census, byte_cols, rows_path):
    """Per-document stratified estimate, its exact subtotal, and the pooled one."""
    per_doc = {}
    for row in selected:
        doc = row["document"]
        entry = per_doc.setdefault(doc, {"hits": 0, "delta": 0})
        entry["hits"] += 1
        if byte_cols:
            before, after = byte_cols
            for col in (before, after):
                if col not in row:
                    die(1, "%s has no column %r for --bytes" % (rows_path, col))
                try:
                    float(row[col])
                except ValueError:
                    die(5, "selected row %s %s has a non-numeric %s cell %r — a `-` read "
                           "as 0 would understate the total"
                        % (doc, row.get("page", "?"), col, row[col]))
            entry["delta"] += int(row[after]) - int(row[before])

    result = {
        "per_doc": {}, "sampled_pages": 0, "sampled_bytes": 0,
        "strat_pages": 0.0, "strat_bytes": 0.0,
        "exact_pages": 0, "exact_bytes": 0, "exact_docs": 0,
        "docs": len(per_doc),
    }
    for doc, entry in per_doc.items():
        total = census[doc]
        sampled = sample_counts[doc]
        factor = total / float(sampled)
        exact = (total == sampled)
        result["per_doc"][doc] = {
            "hits": entry["hits"], "delta": entry["delta"],
            "sampled": sampled, "pages": total, "factor": factor,
            "est_pages": entry["hits"] * factor,
            "est_bytes": entry["delta"] * factor,
            "exact": exact,
        }
        result["sampled_pages"] += entry["hits"]
        result["sampled_bytes"] += entry["delta"]
        result["strat_pages"] += entry["hits"] * factor
        result["strat_bytes"] += entry["delta"] * factor
        if exact:
            result["exact_pages"] += entry["hits"]
            result["exact_bytes"] += entry["delta"]
            result["exact_docs"] += 1
    return result


def run(rows_path, sample_path, census_path, wheres, byte_cols, allow_empty=False):
    census = read_census(census_path)

    rows_header, rows = read_tsv(rows_path)
    need_columns(rows_path, rows_header, ["document", "page"])
    # Up front, against the HEADER — not inside the per-row loops, where a predicate that
    # selects nothing reaches neither check. This is the unreachable-guard finding.
    need_columns(rows_path, rows_header, [c for c, _, _ in wheres])
    if byte_cols:
        need_columns(rows_path, rows_header, list(byte_cols))
    sample_header, sample_rows = read_tsv(sample_path)
    need_columns(sample_path, sample_header, ["document", "page"])

    sample_keys = set()
    sample_counts = {}
    for row in sample_rows:
        sample_keys.add((row["document"], row["page"]))
        sample_counts[row["document"]] = sample_counts.get(row["document"], 0) + 1
    if len(sample_keys) != len(sample_rows):
        die(3, "%s holds duplicate (document, page) rows — a second sweep appended into "
               "it, and every count off it is inflated" % sample_path)

    strays = [(r["document"], r["page"]) for r in rows
              if (r["document"], r["page"]) not in sample_keys]
    if strays:
        die(3, "%d of %d --rows pages are not in --sample (%s …) — the rows must be a "
               "subset of the sample they are scaled against"
            % (len(strays), len(rows), "; ".join("%s %s" % s for s in strays[:3])))

    for doc, sampled in sample_counts.items():
        if doc not in census:
            die(4, "%s is in %s but not in the census %s" % (doc, sample_path, census_path))
        if sampled > census[doc]:
            die(4, "%s has %d sampled rows but the census gives it %d pages"
                % (doc, sampled, census[doc]))

    selected = [r for r in rows if matches(r, wheres, rows_path)]
    if not selected and not allow_empty:
        die(7, "the selection is empty over %d rows — `0.00 pages / +0 B` on exit 0 reads "
               "like an answer, so this is a refusal; pass --allow-empty if you meant it"
            % len(rows))
    result = estimate(selected, sample_counts, census, byte_cols, rows_path)
    result["corpus_pages"] = sum(census.values())
    result["census_docs"] = len(census)
    result["sample_rows"] = len(sample_rows)
    result["rows_read"] = len(rows)
    result["where_skipped"] = numeric_where_skips(rows, wheres, rows_path)
    result["fully_sampled_docs"] = sum(
        1 for doc, n in sample_counts.items() if n == census[doc])
    denominator = float(result["sample_rows"])
    result["pooled_pages"] = result["sampled_pages"] * result["corpus_pages"] / denominator
    result["pooled_bytes"] = result["sampled_bytes"] * result["corpus_pages"] / denominator
    return result


def report(result, verbose, tsv):
    if tsv:
        print("\t".join(["document", "hits", "sampled", "pages", "factor",
                         "estPages", "deltaBytes", "estBytes", "exact"]))
        for doc, d in sorted(result["per_doc"].items(),
                             key=lambda kv: -kv[1]["est_pages"]):
            print("\t".join([doc, str(d["hits"]), str(d["sampled"]), str(d["pages"]),
                             "%.4f" % d["factor"], "%.2f" % d["est_pages"],
                             str(d["delta"]), "%.0f" % d["est_bytes"],
                             "yes" if d["exact"] else "no"]))
        return
    print("rows read              %d (%d skipped by a numeric --where they could not be "
          "read for)" % (result["rows_read"], result["where_skipped"]))
    print("selected               %d pages in %d documents"
          % (result["sampled_pages"], result["docs"]))
    print("sample                 %d rows; census %d documents, %d pages, %d sampled "
          "completely" % (result["sample_rows"], result["census_docs"],
                          result["corpus_pages"], result["fully_sampled_docs"]))
    print("measured bytes         %+d B over the selected pages" % result["sampled_bytes"])
    print("stratified estimate    %.2f pages of %d, %+.0f B"
          % (result["strat_pages"], result["corpus_pages"], result["strat_bytes"]))
    print("  of which exact       %d pages, %+d B (in %d fully-sampled documents)"
          % (result["exact_pages"], result["exact_bytes"], result["exact_docs"]))
    pooled = result["pooled_pages"]
    ratio = pooled / result["strat_pages"] if result["strat_pages"] else float("nan")
    print("pooled estimate        %.2f pages, %+.0f B — %.2fx the stratified one, and "
          "wrong" % (pooled, result["pooled_bytes"], ratio))
    if verbose:
        print("")
        print("per document, by estimated pages:")
        for doc, d in sorted(result["per_doc"].items(),
                             key=lambda kv: -kv[1]["est_pages"]):
            print("  %2d/%2d sampled, %4d pages -> %8.2f pages %+12d B %s %s"
                  % (d["hits"], d["sampled"], d["pages"], d["est_pages"],
                     d["est_bytes"], "EXACT " if d["exact"] else "      ", doc))


def control(census_path, quiet=False):
    """Reproduce C26's published band figures. Returns a list of (name, ok)."""
    spec = CONTROL
    rows_path = os.path.join(REPO, spec["rows"])
    sample_path = os.path.join(REPO, spec["sample"])
    for path in (rows_path, sample_path, census_path):
        if not os.path.exists(path):
            die(6, "control needs %s and it is not here" % path)
    result = run(rows_path, sample_path, census_path,
                 parse_where(spec["where"]), tuple(spec["bytes"].split(",")))
    ratio = result["pooled_pages"] / result["strat_pages"]
    checks = [
        ("band moves 16 sampled pages", result["sampled_pages"] == spec["sampled_pages"]),
        ("over 10 documents", result["docs"] == spec["docs"]),
        ("+2,965,653 B measured", result["sampled_bytes"] == spec["sampled_bytes"]),
        ("corpus is 16,987 pages", result["corpus_pages"] == spec["corpus_pages"]),
        ("sample is 2,129 rows", result["sample_rows"] == spec["sample_rows"]),
        ("stratified rounds to ~21 pages",
         round(result["strat_pages"]) == spec["strat_pages_round"]),
        ("stratified rounds to ~4.0 MB",
         round(result["strat_bytes"] / 1e6, 1) == spec["strat_bytes_mb"]),
        ("pooled is 5.96x the stratified one",
         round(ratio, 2) == spec["pooled_over_strat"]),
        ("1,489,670 B of it is exact", result["exact_bytes"] == spec["exact_bytes"]),
        ("8 pages of it are exact", result["exact_pages"] == spec["exact_pages"]),
        ("86 documents sampled completely",
         result["fully_sampled_docs"] == spec["fully_sampled_docs"]),
    ]
    if not quiet:
        for name, ok in checks:
            print("%s %s" % ("ok  " if ok else "FAIL", name))
        print("")
        report(result, verbose=False, tsv=False)
    return checks


def self_test(census_path):
    ran = []
    failed = []

    def check(name, ok):
        ran.append(name)
        print("%s %s" % ("ok  " if ok else "FAIL", name))
        if not ok:
            failed.append(name)

    work = tempfile.mkdtemp(prefix="stratify-selftest-")

    def write(name, text):
        path = os.path.join(work, name)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        return path

    # One long document sampled 1-in-4 and one short one sampled completely. A pooled
    # estimate cannot tell them apart; a stratified one must.
    census = write("census.tsv",
                   "path\tpages\n"
                   "testdocs/long.pdf\t40\n"
                   "testdocs/short.pdf\t2\n"
                   "testdocs/absent.pdf\t5\n")
    sample = write("sample.tsv",
                   "document\tpage\tv\tb0\tb1\n"
                   "long.pdf\tp1\t9\t100\t400\n"
                   "long.pdf\tp2\t1\t100\t100\n"
                   "long.pdf\tp3\t9\t100\t300\n"
                   "long.pdf\tp4\t1\t100\t100\n"
                   "long.pdf\tp5\t1\t100\t100\n"
                   "long.pdf\tp6\t1\t100\t100\n"
                   "long.pdf\tp7\t1\t100\t100\n"
                   "long.pdf\tp8\t1\t100\t100\n"
                   "long.pdf\tp9\t1\t100\t100\n"
                   "long.pdf\tp10\t1\t100\t100\n"
                   "short.pdf\tp1\t9\t100\t200\n"
                   "short.pdf\tp2\t1\t100\t100\n")
    hi = parse_where(["v:ge:9"])
    res = run(sample, sample, census, hi, ("b0", "b1"))

    check("selects the three high rows", res["sampled_pages"] == 3)
    check("over two documents", res["docs"] == 2)
    # long: 2 hits, 10 of 40 sampled -> 8.00; short: 1 hit, 2 of 2 -> 1.00
    check("stratified is 9.00 pages, not 4.25", abs(res["strat_pages"] - 9.0) < 1e-9)
    # 3 hits x 47 census pages / 12 sample rows. The fixture's average scale factor
    # (47/12 = 3.92) is above the hit-weighted one (9/3 = 3.0), so pooling reads high —
    # the same direction as the real corpus, for the same reason.
    check("pooled is 11.75 pages and differs",
          abs(res["pooled_pages"] - 3 * 47 / 12.0) < 1e-9)
    check("pooled is 1.31x the stratified one here, so the two are not interchangeable",
          abs(res["pooled_pages"] / res["strat_pages"] - 1.3055555) < 1e-6)
    check("measured bytes are +600", res["sampled_bytes"] == 600)
    # long deltas 300 + 200 = 500 -> x4 = 2000; short 100 -> x1 = 100
    check("stratified bytes are +2,100", abs(res["strat_bytes"] - 2100) < 1e-6)
    check("the completely-sampled document is exact", res["exact_pages"] == 1)
    check("its bytes are exact too", res["exact_bytes"] == 100)
    check("one document was sampled completely", res["exact_docs"] == 1)
    check("the corpus is 47 pages over 3 census documents",
          res["corpus_pages"] == 47 and res["census_docs"] == 3)
    check("a census document with no sample rows at all is not called fully sampled",
          res["fully_sampled_docs"] == 1)
    check("per-document factor for the long document is 4.0",
          abs(res["per_doc"]["long.pdf"]["factor"] - 4.0) < 1e-9)

    # A subset of the sample scaled against the sample: the denominators must come from
    # the sample, not from the subset. This is the inflating mistake the docstring names.
    subset = write("subset.tsv",
                   "document\tpage\tv\tb0\tb1\n"
                   "long.pdf\tp1\t9\t100\t400\n"
                   "long.pdf\tp3\t9\t100\t300\n")
    sub = run(subset, sample, census, hi, ("b0", "b1"))
    check("a 2-row subset scaled against the 12-row sample is 8.00 pages",
          abs(sub["strat_pages"] - 8.0) < 1e-9)
    self_scaled = run(subset, subset, census, hi, ("b0", "b1"))
    check("the same subset scaled against ITSELF reads 40.00 — 5.0x high, which is why "
          "--sample is required", abs(self_scaled["strat_pages"] - 40.0) < 1e-9)
    # ⛔ The pooled denominator MUST be the sample's row count and not the rows file's, and
    # this is the only configuration in which those two differ. Every other fixture and the
    # whole control block call run(sample, sample, …), where they are equal by
    # construction — so before this check a `denominator = rows_read` mutant passed 42 of
    # 42 while changing every pooled figure and every pooled/stratified ratio the register
    # publishes. Found by the adversarial review of this file's own diff.
    check("the pooled denominator is the SAMPLE's 12 rows, not the rows file's 2 "
          "(7.83 pages, not 47.00)", abs(sub["pooled_pages"] - 2 * 47 / 12.0) < 1e-9)
    check("and its pooled bytes divide by 12 too (+1,958 B, not +11,750)",
          abs(sub["pooled_bytes"] - 500 * 47 / 12.0) < 1e-6)

    # Predicate operators.
    for op, want in (("gt:1", 3), ("ge:1", 12), ("lt:9", 9), ("le:9", 12)):
        o, v = op.split(":")
        got = run(sample, sample, census, parse_where(["v:%s:%s" % (o, v)]), None)
        check("--where v:%s selects %d" % (op, want), got["sampled_pages"] == want)
    got = run(sample, sample, census, parse_where(["page:eq:p1"]), None)
    check("--where page:eq:p1 selects 2", got["sampled_pages"] == 2)
    got = run(sample, sample, census, parse_where(["page:ne:p1"]), None)
    check("--where page:ne:p1 selects 10", got["sampled_pages"] == 10)

    # A `-` cell in a numeric --where is reported as a skip, never read as 0.
    dashed = write("dashed.tsv",
                   "document\tpage\tv\tb0\tb1\n"
                   "short.pdf\tp1\t-\t100\t200\n"
                   "short.pdf\tp2\t9\t100\t300\n")
    got = run(dashed, sample, census, parse_where(["v:lt:5"]), None, allow_empty=True)
    check("a `-` cell is not selected by v:lt:5", got["sampled_pages"] == 0)
    check("and it is counted as skipped rather than dropped in silence",
          got["where_skipped"] == 1)

    def refuses(name, code, rows_path, sample_path, census_path_, wheres, byte_cols):
        pid = os.fork()
        if pid == 0:
            devnull = os.open(os.devnull, os.O_WRONLY)
            os.dup2(devnull, 2)
            try:
                run(rows_path, sample_path, census_path_, wheres, byte_cols)
            except SystemExit as exc:
                os._exit(exc.code if isinstance(exc.code, int) else 1)
            os._exit(0)
        _, status = os.waitpid(pid, 0)
        got = status >> 8 if status & 0xFF == 0 else -1
        check(name + " (exit %d)" % code, got == code)

    stray = write("stray.tsv",
                  "document\tpage\tv\tb0\tb1\n"
                  "long.pdf\tp99\t9\t100\t400\n")
    refuses("a rows page absent from the sample is refused", 3,
            stray, sample, census, hi, ("b0", "b1"))

    dupes = write("dupes.tsv",
                  "document\tpage\tv\tb0\tb1\n"
                  "short.pdf\tp1\t9\t100\t200\n"
                  "short.pdf\tp1\t9\t100\t200\n")
    refuses("a sample with duplicate (document, page) rows is refused", 3,
            dupes, dupes, census, hi, ("b0", "b1"))

    thin = write("thin-census.tsv", "path\tpages\ntestdocs/short.pdf\t2\n")
    refuses("a sample document missing from the census is refused", 4,
            sample, sample, thin, hi, ("b0", "b1"))

    tiny = write("tiny-census.tsv",
                 "path\tpages\ntestdocs/long.pdf\t3\ntestdocs/short.pdf\t2\n")
    refuses("more sampled rows than the document has pages is refused", 4,
            sample, sample, tiny, hi, ("b0", "b1"))

    dashbytes = write("dashbytes.tsv",
                      "document\tpage\tv\tb0\tb1\n"
                      "short.pdf\tp1\t9\t-\t200\n")
    refuses("a `-` in a --bytes cell of a SELECTED row is refused", 5,
            dashbytes, sample, census, hi, ("b0", "b1"))

    refuses("a --where column that does not exist is refused", 1,
            sample, sample, census, parse_where(["nope:ge:1"]), None)
    refuses("a --bytes column that does not exist is refused", 1,
            sample, sample, census, hi, ("b0", "nope"))
    # ⛔ The same two refusals, in the configuration where they used to be UNREACHABLE: a
    # predicate that selects nothing never entered the per-row loops the checks lived in,
    # so `--bytes b0,nope` printed `+0 B` on exit 0 and a misspelled `eq` column was never
    # looked for. Both found by the adversarial review of this file's own diff.
    refuses("a --bytes column that does not exist is refused even when NOTHING is selected",
            1, sample, sample, census, parse_where(["v:ge:99"]), ("b0", "nope"))
    refuses("a misspelled eq column is refused even behind a clause that excludes every "
            "row", 1, sample, sample, census,
            parse_where(["v:ge:99", "nope:eq:x"]), None)
    refuses("an empty selection is refused rather than printing 0.00 pages on exit 0", 7,
            sample, sample, census, parse_where(["v:ge:99"]), ("b0", "b1"))
    empty = run(sample, sample, census, parse_where(["v:ge:99"]), ("b0", "b1"),
                allow_empty=True)
    check("--allow-empty prints the zero report instead",
          empty["sampled_pages"] == 0 and empty["strat_pages"] == 0.0)

    dup_census = write("dup-census.tsv",
                       "path\tpages\n"
                       "testdocs/long.pdf\t40\n"
                       "testdocs/long.pdf\t4\n"
                       "testdocs/short.pdf\t2\n")
    refuses("a census that names one document twice is refused", 3,
            sample, sample, dup_census, hi, ("b0", "b1"))

    # ⛔ The output layer had no check at all: three mutants that swapped which field
    # `report()` prints in which slot passed the whole self-test, and every number this
    # tool has published was read off `report()`. Same review.
    captured = io.StringIO()
    saved = sys.stdout
    try:
        sys.stdout = captured
        report(res, verbose=True, tsv=False)
        printed = captured.getvalue()
        sys.stdout = saved
        sys.stdout = captured2 = io.StringIO()
        report(res, verbose=False, tsv=True)
        printed_tsv = captured2.getvalue()
    finally:
        sys.stdout = saved
    check("report() prints the stratified estimate in the stratified slot",
          "stratified estimate    9.00 pages of 47, +2100 B" in printed)
    check("report() prints the pooled estimate in the pooled slot, with its ratio",
          "pooled estimate        11.75 pages, +2350 B — 1.31x" in printed)
    check("report() prints the exact subtotal and not the stratified one",
          "of which exact       1 pages, +100 B (in 1 fully-sampled documents)" in printed)
    check("report() --verbose names the long document's 8.00 estimated pages",
          "2/10 sampled,   40 pages ->     8.00 pages" in printed)
    check("--tsv puts estPages in the estPages column, not hits",
          "long.pdf\t2\t10\t40\t4.0000\t8.00\t500\t2000\tno" in printed_tsv)

    # The control block: the same committed files the register quotes.
    print("")
    print("-- control: C26's published band figures --")
    for name, ok in control(census_path, quiet=True):
        check("control: " + name, ok)

    check("all %d cases ran, none of them vanished" % EXPECTED_CHECKS,
          len(ran) + 1 == EXPECTED_CHECKS)
    shutil.rmtree(work, ignore_errors=True)
    print("")
    print("%d checks, %d failed" % (len(ran), len(failed)))
    return 6 if failed else 0


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--rows", help="per-page TSV to select from")
    parser.add_argument("--sample", help="the TSV whose rows ARE the sample; supplies "
                                        "every per-document denominator. Required, and "
                                        "not defaulted to --rows on purpose.")
    parser.add_argument("--census", default=DEFAULT_CENSUS,
                        help="corpus census with path and pages (default: %(default)s)")
    parser.add_argument("--where", action="append", default=[], metavar="COL:OP:VALUE",
                        help="repeatable, ANDed; OP in ge gt le lt eq ne")
    parser.add_argument("--bytes", metavar="BEFORE,AFTER",
                        help="price the selection as AFTER - BEFORE per row")
    parser.add_argument("--verbose", action="store_true",
                        help="per-document breakdown")
    parser.add_argument("--tsv", action="store_true",
                        help="emit the per-document breakdown as TSV instead of a report")
    parser.add_argument("--allow-empty", action="store_true",
                        help="print a zero report instead of exiting 7 on an empty selection")
    parser.add_argument("--control", action="store_true",
                        help="reproduce C26's published band figures and exit")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test(args.census)
    if args.control:
        checks = control(args.census)
        return 6 if any(not ok for _, ok in checks) else 0
    if not args.rows or not args.sample:
        parser.error("--rows and --sample are both required "
                     "(see --control for a worked example)")
    byte_cols = None
    if args.bytes:
        parts = args.bytes.split(",")
        if len(parts) != 2:
            die(2, "--bytes wants BEFORE,AFTER, got %r" % args.bytes)
        byte_cols = tuple(parts)
    result = run(args.rows, args.sample, args.census,
                 parse_where(args.where), byte_cols, args.allow_empty)
    report(result, args.verbose, args.tsv)
    return 0


if __name__ == "__main__":
    sys.exit(main())
