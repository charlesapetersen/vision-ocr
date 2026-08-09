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
    """
    out = os.path.join(tempfile.gettempdir(), "vrg-classify")
    work = tempfile.mkdtemp()
    shutil.copy2(os.path.join(REPO, "Tools", "classify-source.swift"),
                 os.path.join(work, "main.swift"))
    sources = [os.path.join(REPO, "Sources", f) for f in (
        "Prefs.swift", "Runner.swift", "Flattener.swift", "SearchableWriter.swift",
        "JBIG2.swift", "Model.swift", "ContentView.swift", "SettingsView.swift")]
    arch = subprocess.run(["uname", "-m"], capture_output=True, text=True).stdout.strip()
    cmd = ["swiftc", "-O", "-o", out, "-target", f"{arch}-apple-macos13.0"] \
        + sources + [os.path.join(work, "main.swift")]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("could not build the classifier:\n" + r.stderr[-2000:])
    return out


def classify(tool, paths, workers=8):
    """{path: verdict} for a list of PDFs. Runs the tool in parallel batches."""
    verdicts = {}
    batch = 12
    chunks = [paths[i:i + batch] for i in range(0, len(paths), batch)]

    def run(chunk):
        r = subprocess.run([tool] + chunk, capture_output=True, text=True)
        out = {}
        for line in r.stdout.splitlines():
            f = line.split("\t")
            if len(f) >= 9:
                out[f[8]] = f[0]
        return out

    with cf.ThreadPoolExecutor(max_workers=workers) as pool:
        for got in pool.map(run, chunks):
            verdicts.update(got)
    return verdicts


def era(year):
    if not year:
        return "unk"
    return "old" if year < 1960 else ("mid" if year < 2000 else "new")


def main():
    ap = argparse.ArgumentParser()
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
