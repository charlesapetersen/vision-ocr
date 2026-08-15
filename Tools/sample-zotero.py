#!/usr/bin/env python3
"""Rebuild the test corpus by sampling a Zotero library.

The corpus itself is not committed — it is third-party copyrighted material — but
`testdocs/manifest.tsv` records what was sampled, and this reproduces an
equivalent sample from any Zotero library.

    python3 Tools/sample-zotero.py --dest testdocs

Stratifies by item type x era (pre-1960, 1960-1999, 2000+, undated), two
documents per bucket. Reads a *copy* of zotero.sqlite, since Zotero locks the
original while running.

**Every candidate is classified first, and only scans are kept.** Item type says
what a document *is*; it says nothing about how the PDF was made. Without that
gate the 2026-08 corpus came out 40 born-digital, 10 hand-photographed and only
27 actual scans out of 78 — and the project's headline accuracy figures were
quoted off it for months. See BUGS.md D1 and CORPUS-2026-08-08.md.

`manuscript` and `letter` are excluded outright: in a historian's library those
are archival photographs and finding aids, which are Archive Processor's job,
not this app's. Pass --types to override.

Needs `Tools/classify-source.swift`, which it compiles once against `Sources/`.
"""
import argparse, collections, concurrent.futures as cf, csv, os, random
import shutil, sqlite3, subprocess, sys, tempfile

# No manuscript, no letter — see the module docstring.
TYPES = {"journalArticle", "book", "newspaperArticle", "magazineArticle",
         "thesis", "bookSection", "report", "document"}

QUERY = """
SELECT it.typeName,
       COALESCE(substr(dv.value, 1, 4), '?') AS yr,
       ia.path, ai.key, i.dateAdded
FROM itemAttachments ia
JOIN items ai ON ai.itemID = ia.itemID
JOIN items i ON i.itemID = ia.parentItemID
JOIN itemTypes it ON it.itemTypeID = i.itemTypeID
LEFT JOIN itemData id ON id.itemID = i.itemID AND id.fieldID =
      (SELECT fieldID FROM fields WHERE fieldName = 'date')
LEFT JOIN itemDataValues dv ON dv.valueID = id.valueID
WHERE ia.contentType = 'application/pdf' AND ia.path LIKE 'storage:%';
"""


REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def build_classifier():
    """Compile Tools/classify-source.swift against the real sources.

    Against the real sources on purpose: the classifier's page-image test is
    `Flattener.pageIsAnImage`, the same function the app uses to decide whether
    it is about to discard someone's digital text (C17). A second copy of that
    rule would drift from the first, which is exactly how `picture-signals`
    ended up measuring a page production never renders (T2).

    **That sentence was false for a week, in this file, about this tool.**
    Compiling against `Sources/` is necessary and was not sufficient: the
    classifier linked `Flattener` and then computed its own page-image test from
    two different cross-page aggregates, which is A12.4. It calls
    `Flattener.pageIsAnImage` per page and `Flattener.hasDigitalText` per
    document now. Linking a function is not calling it.
    """
    out = os.path.join(tempfile.gettempdir(), "vrg-classify")
    work = tempfile.mkdtemp()
    shutil.copy2(os.path.join(REPO, "Tools", "classify-source.swift"),
                 os.path.join(work, "main.swift"))
    # Globbed, not listed. This was a hand-written list and it went stale the
    # moment the app grew a file: by 2026-08-13 it was missing Recogniser.swift,
    # RunReport.swift and Updater.swift, and the classifier had simply stopped
    # compiling — so this script, and anything built on it, failed at the first
    # step. `run_tests.sh` globs for exactly this reason and says so (R48).
    # App.swift stays out: its @main collides with classify-source's top level.
    sources = sorted(
        os.path.join(REPO, "Sources", f)
        for f in os.listdir(os.path.join(REPO, "Sources"))
        if f.endswith(".swift") and f != "App.swift")
    arch = subprocess.run(["uname", "-m"], capture_output=True, text=True).stdout.strip()
    cmd = ["swiftc", "-O", "-o", out, "-target", f"{arch}-apple-macos13.0"] \
        + sources + [os.path.join(work, "main.swift")]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("could not build the classifier:\n" + r.stderr[-2000:])
    return out


# The classifier's output contract, in one place. `sweep-zotero.py` imports this
# module for the parser as well as the build, because two copies of a column
# layout are the same defect as two copies of a rule — and this layout has
# already grown two columns once (A12.4 added `imagePages` and `digitalText`),
# which silently shifted `path` from field 8 to field 10 for anyone indexing from
# the front.
FIELDS = ["verdict", "pages", "sampled", "imagePages", "digitalText",
          "charsPerPage", "maxImagePx", "medianDPI", "saturation",
          "illumination", "path"]


def parse_rows(text):
    """([row-dict], [unparsed line]) for the classifier's stdout.

    Exact field count, not `>= 9`. A row with the wrong number of fields is
    reported, never quietly dropped: this project has shipped a row printing 10
    fields under a 9-column header (T14) and one printing 12 under 11 (A12.3),
    and on both occasions the consumer's `>=` accepted it. A path containing a
    literal tab lands here too, as an unparsed line rather than as a mis-split
    one.
    """
    rows, bad = [], []
    for line in text.splitlines():
        f = line.split("\t")
        if len(f) != len(FIELDS):
            bad.append(line)
            continue
        rows.append(dict(zip(FIELDS, f)))
    return rows, bad


def classify_rows(tool, paths, workers=8, progress=0):
    """{path: row-dict} for a list of PDFs, run in parallel batches.

    A batch, because one process launch per document is most of the cost at this
    scale. But a batch is also a blast radius: the classifier traps on a
    malformed PDF now and then, and when it does, every path *after* the
    offending one in its chunk goes unmeasured too — 11 documents rejected for
    one document's defect, invisibly, since an unseen path and a rejected one
    look identical downstream. So a chunk that comes back short is retried one
    path at a time, and only the paths that fail alone are left unmeasured.

    `progress` prints a line every N paths when non-zero.
    """
    batch = 12
    chunks = [paths[i:i + batch] for i in range(0, len(paths), batch)]
    unparsed, late = [], []

    def once(chunk, timeout):
        """({path: row}, [unparsed line], [path that ran out of time])."""
        try:
            # A timeout, because its absence is unbounded: one document that
            # renders forever otherwise stalls the whole sweep with no output.
            # 600 s for a chunk of 12 is what `sweep-zotero.py` has always used.
            r = subprocess.run([tool] + chunk, capture_output=True, text=True,
                               timeout=timeout)
        except subprocess.TimeoutExpired:
            return {}, [], list(chunk)
        rows, bad = parse_rows(r.stdout)
        return {row["path"]: row for row in rows}, bad, []

    def run(chunk):
        found, bad, timed = once(chunk, 600)
        missing = [p for p in chunk if p not in found]
        if missing and len(chunk) > 1:
            # 120 s a document, not 600: retrying a *timed-out* chunk at the
            # chunk's own bound would let one pathological file cost 12 x 600 s.
            # The corpus averages 0.85 s a document, so 120 s is 140x the mean.
            #
            # The chunk attempt's diagnostics are *discarded*, not added to: every
            # malformed row belongs to a path that produced no usable row, so that
            # path is in `missing` and its row comes back from the retry. Keeping
            # both counted one malformed row twice — "2 unparsable rows" over one
            # bad document, in a change whose whole value is honest reporting.
            bad, timed = [], []
            for p in missing:
                got, more, slow = once([p], 120)
                found.update(got)
                bad += more
                timed += slow
        return found, bad, timed

    out, done = {}, 0
    with cf.ThreadPoolExecutor(max_workers=workers) as pool:
        for found, bad, timed in pool.map(run, chunks):
            out.update(found)
            unparsed += bad
            late += timed
            done += batch
            if progress and done % progress < batch:
                print(f"  {min(done, len(paths))}/{len(paths)}", flush=True)
    # Both of these are silence otherwise, and silence here reads downstream as
    # "not a scan" — a rejection nobody chose.
    if unparsed:
        print(f"  {len(unparsed)} unparsable classifier row(s); first: "
              f"{unparsed[0][:120]}", flush=True)
    if late:
        print(f"  {len(late)} document(s) the classifier could not finish; "
              f"first: {late[0]}", flush=True)
    missed = [p for p in paths if p not in out]
    if missed:
        print(f"  {len(missed)} document(s) unmeasured (the classifier gave no "
              f"row); first: {missed[0]}", flush=True)
    return out


def classify(tool, paths, workers=8):
    """{path: verdict} for a list of PDFs."""
    return {p: r["verdict"]
            for p, r in classify_rows(tool, paths, workers).items()}


def self_test():
    """Check the classifier-output parser and the batch runner. `--self-test`.

    Against a *fake* classifier — a shell script — because the real one needs a
    PDF and 0.85 s a document, and neither is what is under test here. Nothing in
    this repository ran a Python tool's own checks before this one: the whole
    gate for `Tools/*.py` was `py_compile`, which is why the pre-commit hook now
    runs `--self-test` on any staged Python tool that advertises one.

    Three properties, each watched failing first by breaking the code back:

      1. a row with the wrong field count is *reported*, not accepted. The `>= 9`
         it replaced accepted a 10-field row under a 9-column header (T14) and a
         12-field one under 11 (A12.3).
      2. a chunk whose classifier dies part-way still yields every other path in
         it. Before the retry, paths *after* the trap were lost — and an unseen
         path is indistinguishable downstream from a rejected one, so twelve
         documents left a library sweep for one document's defect, silently.
      3. `path` is read as the last field. A12.4 added two columns to this TSV,
         which moved `path` from field 8 to field 10 under every consumer that
         indexed from the front.
    """
    failures = []

    def check(name, ok, detail=""):
        # The detail goes out only on a failure, and only then: the Swift suite's
        # habit, and the reason a red line here is diagnosable without a rerun.
        print(f"  {'ok  ' if ok else 'FAIL'} {name}"
              + ("" if ok or not detail else f" — {detail}"))
        if not ok:
            failures.append(name)

    def row_text(path, verdict="scanned"):
        return "\t".join([verdict, "10", "5", "5", "no", "1200", "1600", "300",
                          "0.000", "0.050", path])

    # 1 — the field count is exact, and a short row is reported.
    rows, bad = parse_rows(row_text("/a.pdf") + "\n"
                           + "\t".join(["scanned"] * 9) + "\n"
                           + "\t".join(["scanned"] * 12))
    check("an 11-field row parses", len(rows) == 1)
    check("a 9-field and a 12-field row are both reported, not accepted",
          len(bad) == 2)

    # 3 — path is the last field, spaces and all. `testdocs/` filenames have them.
    rows, _ = parse_rows(row_text("/x/A Book, 1954 - Why.pdf"))
    check("path is the last field, spaces intact",
          rows and rows[0]["path"] == "/x/A Book, 1954 - Why.pdf")
    check("the fields either side of the new columns still line up",
          rows and rows[0]["imagePages"] == "5" and rows[0]["digitalText"] == "no"
          and rows[0]["medianDPI"] == "300")

    # 2 — a trap part-way through a chunk costs only its own document.
    work = tempfile.mkdtemp()
    fake = os.path.join(work, "fake-classify")
    with open(fake, "w") as fh:
        fh.write("#!/bin/bash\n"
                 "for p in \"$@\"; do\n"
                 "  case \"$p\" in\n"
                 # Faithful to the real failure: a Swift trap is SIGILL/SIGABRT
                 # part-way through the arguments, with the rows before it
                 # already on stdout.
                 "    *TRAP*) kill -ABRT $$ ;;\n"
                 "    *) printf '%s\\t10\\t5\\t5\\tno\\t1200\\t1600\\t300\\t0.000\\t0.050\\t%s\\n' scanned \"$p\" ;;\n"
                 "  esac\n"
                 "done\n")
    os.chmod(fake, 0o755)

    # One chunk of 12 — the batch size — with the trap third. Paths 4 through 12
    # are reachable only through the retry.
    paths = [f"/tmp/doc{i}.pdf" for i in range(1, 13)]
    paths[2] = "/tmp/doc3-TRAP.pdf"
    got = classify_rows(fake, paths, workers=2)
    check("the trapping document is the only one missing",
          sorted(got) == sorted(p for p in paths if "TRAP" not in p))
    check("a path after the trap in the same chunk is measured",
          "/tmp/doc12.pdf" in got)

    # A malformed row is reported once, not once per attempt. The retry re-runs the
    # offending path, so counting the chunk's diagnostics as well as the retry's
    # reported "2 unparsable rows" over a single bad document.
    short = os.path.join(work, "short-classify")
    with open(short, "w") as fh:
        fh.write("#!/bin/bash\n"
                 "for p in \"$@\"; do\n"
                 "  case \"$p\" in\n"
                 # Ten fields where eleven are promised — T14's shape, on purpose.
                 "    *BAD*) printf 'scanned\\t10\\t5\\t5\\tno\\t1200\\t1600\\t300\\t0.000\\t%s\\n' \"$p\" ;;\n"
                 "    *) printf '%s\\t10\\t5\\t5\\tno\\t1200\\t1600\\t300\\t0.000\\t0.050\\t%s\\n' scanned \"$p\" ;;\n"
                 "  esac\n"
                 "done\n")
    os.chmod(short, 0o755)
    bad_paths = [f"/tmp/s{i}.pdf" for i in range(1, 13)]
    bad_paths[4] = "/tmp/s5-BAD.pdf"
    import io as _io
    import contextlib
    buf = _io.StringIO()
    with contextlib.redirect_stdout(buf):
        got_short = classify_rows(short, bad_paths, workers=2)
    noise = buf.getvalue()
    check("a malformed row is counted once, not once per attempt",
          "1 unparsable classifier row(s)" in noise, noise.strip().replace("\n", " | "))
    check("…and the eleven good documents in its chunk are still measured",
          len(got_short) == 11 and "/tmp/s5-BAD.pdf" not in got_short)
    check("classify() reduces the same run to verdicts",
          classify(fake, paths[:2]) == {p: "scanned" for p in paths[:2]})
    shutil.rmtree(work, ignore_errors=True)

    print(f"self-test: {len(failures)} failure(s)")
    return 1 if failures else 0


def era(year):
    if not year:
        return "unk"
    return "old" if year < 1960 else ("mid" if year < 2000 else "new")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--self-test", action="store_true",
                    help="check the classifier-output parser and the batch "
                         "runner against a fake classifier, and exit")
    ap.add_argument("--zotero", default=os.path.expanduser("~/Zotero"))
    ap.add_argument("--dest", default="testdocs")
    ap.add_argument("--per-bucket", type=int, default=2)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--added-since", default="",
                    help="only items added to Zotero on or after this date, "
                         "e.g. 2021-08-08")
    ap.add_argument("--exclude-manifest", default="",
                    help="a previous manifest.tsv; its zotero_key items are "
                         "skipped, so a rebuild samples fresh material")
    ap.add_argument("--types", default="",
                    help="comma-separated item types, overriding the default set")
    ap.add_argument("--allow-any-kind", action="store_true",
                    help="skip the scanned-only gate. Only for reproducing an old "
                         "corpus; see BUGS.md D1 for what it costs.")
    args = ap.parse_args()

    if args.self_test:
        sys.exit(self_test())

    types = set(t.strip() for t in args.types.split(",") if t.strip()) or TYPES

    db = os.path.join(args.zotero, "zotero.sqlite")
    if not os.path.exists(db):
        sys.exit(f"no zotero.sqlite at {db}")

    # Copy first: Zotero holds a lock while it is running.
    with tempfile.TemporaryDirectory() as tmp:
        copy = os.path.join(tmp, "z.sqlite")
        shutil.copy2(db, copy)
        rows = sqlite3.connect(copy).execute(QUERY).fetchall()

    skip = set()
    if args.exclude_manifest and os.path.exists(args.exclude_manifest):
        with open(args.exclude_manifest) as fh:
            for row in csv.reader(fh, delimiter="\t"):
                if len(row) > 3 and row[3] not in ("zotero_key", "zotero_source"):
                    # Older manifests stored the full source path here; current
                    # ones store the bare key. Both reduce to the storage key.
                    skip.add(os.path.basename(os.path.dirname(row[3])) or row[3])
        print(f"excluding {len(skip)} document(s) already in "
              f"{args.exclude_manifest}")

    candidates = collections.defaultdict(list)
    for typ, yr, path, key, added in rows:
        if typ not in types or not path.startswith("storage:"):
            continue
        if args.added_since and (added or "") < args.added_since:
            continue
        full = os.path.join(args.zotero, "storage", key, path.split("storage:", 1)[1])
        if not os.path.exists(full) or key in skip:
            continue
        try:
            year = int(yr)
        except ValueError:
            year = 0
        candidates[(typ, era(year))].append(full)

    random.seed(args.seed)

    # THE GATE. Classify lazily, bucket by bucket, taking candidates in random
    # order until the bucket is full — classifying all 1,880 candidates in a real
    # library to fill 78 slots would be an hour of rendering for nothing.
    buckets = collections.defaultdict(list)
    if args.allow_any_kind:
        print("WARNING: --allow-any-kind — sampling without the scanned gate. "
              "This is how the 2026-08 corpus ended up 65% material this app is "
              "not for; see BUGS.md D1.")
        buckets = candidates
    else:
        tool = build_classifier()
        rejected = collections.Counter()
        for key, pool in sorted(candidates.items()):
            pool = pool[:]
            random.shuffle(pool)
            kept, i = [], 0
            while len(kept) < args.per_bucket and i < len(pool):
                # A window at a time: one process launch per document is most of
                # the cost at this scale.
                window = pool[i:i + max(args.per_bucket * 4, 8)]
                i += len(window)
                verdicts = classify(tool, window)
                for path in window:
                    v = verdicts.get(path, "unreadable")
                    if v == "scanned":
                        kept.append(path)
                        if len(kept) >= args.per_bucket:
                            break
                    else:
                        rejected[v] += 1
            buckets[key] = kept
            short = args.per_bucket - len(kept)
            if short > 0:
                print(f"  {key[0]}/{key[1]}: only {len(kept)} scan(s) available "
                      f"out of {len(pool)} candidates")
        print("rejected by the gate: "
              + ", ".join(f"{v} {k}" for k, v in rejected.most_common()))
    os.makedirs(args.dest, exist_ok=True)
    manifest = []
    for key in sorted(buckets):
        chosen = buckets[key]
        if args.allow_any_kind:
            chosen = random.sample(chosen, min(args.per_bucket, len(chosen)))
        for src in chosen:
            sub = os.path.join(args.dest, key[0])
            os.makedirs(sub, exist_ok=True)
            target = os.path.join(sub, os.path.basename(src))
            stem, ext = os.path.splitext(target)
            n = 2
            while os.path.exists(target):
                target = f"{stem} {n}{ext}"
                n += 1
            shutil.copy2(src, target)
            # The storage key, not the full path: this file is committed, and a
            # home directory full of someone's reading has no business in it.
            manifest.append([key[0], key[1], os.path.relpath(target, args.dest),
                             os.path.basename(os.path.dirname(src))])

    with open(os.path.join(args.dest, "manifest.tsv"), "w", newline="") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["type", "era", "file", "zotero_key"])
        w.writerows(sorted(manifest))
    print(f"sampled {len(manifest)} documents from {len(buckets)} buckets into {args.dest}")


if __name__ == "__main__":
    main()
