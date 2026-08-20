#!/usr/bin/env python3
"""Drive `score-text-route` over the whole corpus, one document per invocation.

    python3 Tools/sweep-ink-bar.py --out INKBAR-<today>.tsv --bar 0.08 \
        --corpus /Users/cp1/Claude/vision-ocr/testdocs

⛔ **That `--bar` was `0.045` when this sweep ran, and 0.045 is now the SHIPPED bar
(2026-08-19, C26's fix).** `score-text-route` exits 2 on `INKBAR` equal to the shipped
constant — "nothing to compare" — and 2 is in `CONFIG_EXITS`, so `--bar 0.045` does not
mis-measure: it aborts the sweep on document 1, by design. The comparison the committed
`INKBAR-2026-08-19.tsv` holds is now reached from the other side, with `--bar 0.08` — the
same two states with the byte columns swapped, `layered` the new behaviour and
`layeredAtBar` the old. ⚠️ **It does not reproduce that file and must not be pointed at
it**: `refuse_mixed_provenance` reads its `# bar=0.045` stamp and refuses, correctly, so a
re-measurement needs a new `--out`.

**This exists because of a measured trap, not for tidiness.** `score-text-route`
takes ONE pdf and treats every later argument as a page number, so
`score-text-route testdocs/**/*.pdf` measures document 1, silently ignores the
other 232 as unparseable page numbers, and prints a summary that reads exactly
like a corpus run. `BUGS.md` C26 sub-step 3b was blocked on a corpus number, and a
glob would have answered it with one document's. (That sweep ran 2026-08-19 —
`INKBAR-2026-08-19.tsv` — and C26 is `FIXED` as of 2026-08-20. This driver is kept
for `C28`, which needs the same walk over a different bar.)

**What the number was for, and it did its job.** C26 lost three line drawings
because `pageIsAllText()`'s first term, `inkOutsideText`, reads 0.0493-0.0660
against what was then a bar of 0.08, so the page was called all-text and its
background stored at 1/8. A bar at 0.045 refuses all three, and the per-page price
of refusing them was measured at 2.99x on those pages. What was NOT measured, and
what this sweep answered, is how many OTHER corpus pages sit in `[0.045, 0.08)` and
would newly pay it: **17, of which 16 move, over 10 documents of 233 — 4.54x and
185,353 B a page, ~+0.55% of corpus output.** R49/R50 are the entries about paying
bytes on every text page; that trade is why the constant did not move without this,
and on 2026-08-19 the owner read the arithmetic and moved it to 0.045.

**Cost, and the arithmetic rather than the slogan.** 233 documents, up to 12
sampled pages each (`Flattener.sampleIndices`, not 2), so roughly 2,500 pages.
Three documents measured 2026-08-19: `1954 - Why.pdf` 38.3 s/10 pages =
3.83 s/page, `(F) Dickens.pdf` 0.54, `Freud_Fetishism.pdf` 0.66 — the two cheap
ones are already-1-bit throughout, the row that costs nothing. 2,500 pages at the
WORST of those is 2.7 h and at the cheapest 22 min, so the "3-4 hours" this
project's register carries is a ceiling guess, **not** the floor it was written as;
the honest range is tens of minutes to about three hours, and which end depends on
the corpus's picture-route share, which is part of what the sweep measures. Either
way it can outlast a 2.5 h session backstop, hence:

**Resumable, by construction.** A document's rows are buffered and appended only
once its whole run finishes, so "the document has a row" means "the document is
done". Every document gets at least one row even when nothing was measured
(`status` says which), because a document that produces no row would be retried on
every resume for ever. Three things make that invariant absolute rather than
merely usual, each found by the review of this file:

  * a **torn final row** (a crash or `ENOSPC` between the write and the newline)
    is trimmed on resume — and so is every other row of that document, because it
    had already written some and would otherwise read as done on half its pages;
  * a sidecar `<out>.lock` is **`flock`ed before anything reads or writes `--out`**,
    so a second sweep cannot append into one file — duplicate rows inflate the
    pages, the bands and the bytes while the document count still looks right. The
    *position* is the protection: taken after the trim and the rewrite, as it was,
    the second launch mutated a live sweep's file and refused afterwards. And it is
    a sidecar because a lock on the artefact does not survive `os.replace`, which
    leaves the running sweep appending to an unlinked inode. The `.lock` is empty,
    is not the artefact, and a leftover one is harmless;
  * `--dry-run` **reads only** — it used to preview after the trim and the rewrite,
    so it deleted the error statuses of the documents it then did not re-run;
  * `--retry-errors` **rewrites** the file without the retried documents' rows
    rather than only skipping them in the resume set — filtering the set alone
    appended beside the stale row, so the document kept its old `error` status for
    ever while its pages were counted twice.

**The file states its own provenance.** A `# bar=… corpus=… binary=…` line under
the header, and a resume at a different bar or corpus root is refused rather than
mixed in — `relpath` re-keys every document under a different root, so the whole
corpus would silently re-run into one file. A relocated binary is reported, not
refused: that is a legitimate resume after a rebuild.

**A configuration error stops the sweep; a document error does not.** The tool
exits 2 on a bad `INKBAR` and 3 with no `jbig2` on PATH — conditions that will
hold for all 233 documents. Recording those as 233 `error` rows would produce a
complete-looking TSV of nothing, so they abort. Exit 1 (this file will not open)
is a property of the one document and is recorded.

**The tool's header is checked, not assumed.** `score-text-route` prints its 13
columns from one `columns` array; if that array changes, every field in this
file's output would shift one place to the left of its name. `TOOL_COLUMNS` below
is compared to the header line on every document and a mismatch aborts. Three
field-count defects (T14, A12.3, T18) are the register's argument for this.

**It does not take `test-lock.sh`.** The suite lock exists because two `tests`
binaries share `~/Library/Preferences/tests.plist` — keyed by process *name*.
This runs `score-text-route`, whose defaults land in a different domain, and it
calls `Prefs.register(migrate: false)`, which registers rather than persists. So
there is no prefs collision to serialise, and holding the lock for 3-4 hours
would block every commit hook in that window. `Prefs.register`'s own doc comment
in `Sources/Prefs.swift` says the registration is in-memory and writes nothing
when `migrate` is false, and `Snapshot.current()` is reads only — read, not
assumed. ⚠️ NOT measured by running a suite alongside the sweep; the CPU
contention is real and will make a concurrent suite slower.

**Launch it so it outlives the session** — `nohup … &` reports success
immediately while the work runs orphaned, so poll the artefact:

    cd <worktree> && export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
    setsid nohup python3 Tools/sweep-ink-bar.py --out "$STATE/INKBAR-<today>.tsv" \
        --bar 0.08 --corpus /Users/cp1/Claude/vision-ocr/testdocs \
        > "$STATE/inkbar-sweep.log" 2>&1 &
    # then, from any later session:
    wc -l "$STATE/INKBAR-2026-08-19.tsv"; tail -3 "$STATE/inkbar-sweep.log"

Keep the TSV and the log OUTSIDE the worktree (`/private/tmp` does not survive a
reboot and an `auto/` worktree is garbage-collected once pushed and clean).

`--report` reads a TSV back and prints counts only. It deliberately prints no
verdict about the constant: the population is the *input* to that decision, and
this register has enough numbers that were published one step past what was
measured. It **exits 3** over a file that measured nothing, the way
`score-threshold-loss` does — a table of zeros at rc 0 is how a later session
would conclude the sweep had finished. The band histogram prints the denominator
it should sum to, and a page is counted as newly refused on `verdict` against the
FIRST WORD of `barVerdict`: `score-text-route` appends ` STENCIL-MOVED` and
` REPLICA-DISAGREES` to that column, so an exact match dropped exactly the
anomalous pages.
"""
import argparse, errno, fcntl, os, subprocess, sys, tempfile, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# `score-text-route.swift`'s `columns`, in order. Compared against the header line
# of every document's run; a mismatch aborts rather than shifting 15 fields under
# 15 names that no longer describe them.
TOOL_COLUMNS = ["page", "route", "sat", "tone", "inkOut", "layered", "1bit",
                "delta", "verdict", "extent", "barVerdict", "layeredAtBar",
                "barDelta"]

# The one printer's one column list, `document` and `status` in front of the
# tool's own. Nothing measured is dropped on the way through: the column that
# settled C26's sub-step 2 had been sitting unread in `score-mrc`'s output for a
# day because a quotation kept only the fields that seemed relevant.
COLUMNS = ["document", "status"] + TOOL_COLUMNS

# Exit codes that describe the environment rather than the document, so they will
# recur on all 233 and must stop the sweep. 2 = bad usage or a bad `INKBAR`,
# 3 = no `jbig2` on PATH.
CONFIG_EXITS = {2, 3}

# Per-document ceiling. Only 12 pages are sampled however long the document, so at
# the slowest rate measured (3.83 s/page) a document costs ~46 s and this is 39x
# that. A document that exceeds it is recorded and the sweep goes on. (This comment
# said "~25x", which is the multiple for 6 s/page, not the 3.8 it cited.)
DEFAULT_TIMEOUT = 1800

# How many cases `--self-test` must run. Asserted at the end of it, because nothing
# else enforced the number and a mutant that made 19 cases DISAPPEAR looked like a
# pass. Measured by running the self-test, never counted by eye — `check(` call sites
# and cases-run differ, one of them being inside a loop, which is how the figure
# "34" reached five documents while a run printed 35.
EXPECTED_CHECKS = 71


def row(document, status, fields=None):
    """One row, width asserted. `fields` is the tool's 13, or None for a status row."""
    body = list(fields) if fields is not None else ["-"] * len(TOOL_COLUMNS)
    out = [document, status] + body
    # `SystemExit`, not `assert`: `python3 -O` (or `PYTHONOPTIMIZE=1` in the launch
    # environment) strips assertions, and these two are the only thing standing
    # between a field-count slip and 2,500 misaligned rows. The pre-commit hook runs
    # without `-O`, so an assertion here would be checked in the gate and absent in
    # the sweep — the worst arrangement of the two. Found by the review of this file.
    if len(out) != len(COLUMNS):
        raise SystemExit(f"{len(out)} fields under {len(COLUMNS)} columns: {out!r}")
    for f in out:
        if "\t" in str(f):
            raise SystemExit(f"tab inside a field, unwritable: {f!r}")
    return "\t".join(str(f) for f in out)


def parse_tool_output(text):
    """Split `score-text-route`'s stdout into (data rows, error).

    The tool prints its header, then one row per sampled page, then a blank line
    and a prose summary. Only the rows between are data. An unexpected header or a
    row of the wrong width is returned as an error string rather than parsed
    around — see the module docstring on why the header is not assumed.
    """
    lines = text.splitlines()
    while lines and not lines[0].strip():
        lines.pop(0)
    if not lines:
        return [], "no output"
    header = lines[0].split("\t")
    if header != TOOL_COLUMNS:
        return [], ("header drift: tool printed "
                    f"{len(header)} columns {header} — expected {TOOL_COLUMNS}")
    rows = []
    for line in lines[1:]:
        if not line.strip():
            break                      # the blank line before the summary
        fields = line.split("\t")
        if len(fields) != len(TOOL_COLUMNS):
            return [], (f"row width {len(fields)} under "
                        f"{len(TOOL_COLUMNS)} columns: {line!r}")
        rows.append(fields)
    return rows, None


def completed(path):
    """Documents already recorded in `path`, in a set. Empty if there is no file.

    Read from the `document` column, so it does not matter how many rows a
    document contributed — one status row counts as done exactly as 12 data rows
    do, which is what stops a no-pages document being retried on every resume.
    """
    done = {}
    if not os.path.exists(path):
        return done
    # `errors="replace"`, because a torn row can be torn INSIDE a UTF-8 sequence and the
    # corpus's filenames carry U+00A0. Strict decoding raised `UnicodeDecodeError` here,
    # which reached `--report` and `--dry-run` over a live sweep's file as a traceback —
    # the two commands a polling session runs. Measured by the review of this diff. The
    # real sweep never saw it because its own trim reads bytes and runs first.
    with open(path, errors="replace") as fh:
        first = fh.readline().rstrip("\n").split("\t")
        # `[""]` is what an EMPTY file's first line splits to, and it is TRUTHY — so
        # `if first and first != COLUMNS` could never take its left branch, and a
        # zero-byte `--out` was permanently unresumable while this function's own
        # docstring promised to tolerate one. Found by the review of this file.
        if first not in ([""], COLUMNS):
            raise SystemExit(f"{path}: header is {first}, not this tool's {COLUMNS}")
        # A row's last field may be a torn fragment: `flush` + `fsync` can fail on a
        # full disk (or the machine can stop) between them and the newline, and then
        # a resume would read the fragment's document as DONE and weld its next row
        # onto it. `trim_partial_row` is what makes the invariant absolute; this
        # counts what it would find so a caller can act before appending.
        for line in fh:
            if line.startswith("#"):      # the provenance stamp
                continue
            fields = line.rstrip("\n").split("\t")
            if len(fields) < 2:
                continue
            done.setdefault(fields[0], fields[1])
    return done


def torn_document(path):
    """(bytes of a torn final row, the document keys a resume owes for it) — READS ONLY.

    Split out from `trim_partial_row` so `--dry-run` can say what a real resume owes
    without truncating anything: a flag documented as "list what would run and stop"
    that repairs the file is the same class of surprise this tool exists to avoid. And
    it is ONE definition of both "torn" and "owed", so the preview cannot come to
    answer a different question than the run it previews — C20 was one idea living in
    two functions.

    **Two keys, not one.** A document's rows go out in a single `out.write`, so a tear
    can land inside a later row's KEY — leaving a prefix (`book/1954 - W`) that matches
    no row while that document's earlier rows survive as "done". So the last COMPLETE
    row's key is owed as well: it came from the same write whenever any of that
    document's rows landed, and when the tear was at the very start of the write it
    names the PREVIOUS document instead and costs one redundant re-run. Measured
    2026-08-19: without it a 3-page document read done on 2 pages.
    """
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return 0, set()
    with open(path, "rb") as fh:
        data = fh.read()
    if data.endswith(b"\n"):
        return 0, set()
    cut = data.rfind(b"\n")
    keep = cut + 1 if cut >= 0 else 0
    keys = set()

    def owe(field):
        # The header and the `#` stamp are not documents. `drop_documents` skips both
        # anyway; this only has to avoid *calling* them documents in a preview.
        if field and field != COLUMNS[0] and not field.startswith("#"):
            keys.add(field)

    owe(data[keep:].decode("utf-8", "replace").split("\t")[0])
    complete = data[:keep].splitlines()
    if complete:
        owe(complete[-1].decode("utf-8", "replace").split("\t")[0])
    return len(data) - keep, keys


def lock_path(out):
    """The sidecar `flock`ed for a whole sweep: `<out>.lock`.

    NOT `--out` itself, and that is the fix for a measured hole rather than a style
    choice. `drop_documents` rewrites through a temp file and `os.replace`, which
    swaps the inode — so a lock held on the old inode protects nothing, and the
    running sweep's own append fd would go on writing to a file no longer named. A
    sidecar is never replaced, so the lock a second sweep tests is the lock the first
    one holds. It is empty, it is not the artefact, and a leftover one is harmless:
    `flock` is released by the kernel when the process ends.
    """
    return out + ".lock"


def acquire_lock(out):
    """Hold `<out>.lock` exclusively, or refuse. Returns the handle; the CALLER closes.

    One sweep per output file. The documented workflow launches with `setsid nohup`
    and has later sessions poll, so a second launch onto the same `--out` is a
    realistic accident — and it produces duplicate rows, which inflate the pages, the
    bands and the bytes while the document count still looks right.
    """
    try:
        fh = open(lock_path(out), "a")
    except OSError as exc:
        # A missing or unwritable output directory used to arrive as a bare traceback
        # naming a `.lock` file the operator never asked for. Found by the review of
        # this diff.
        raise SystemExit(f"cannot create the sweep lock beside --out {out}: {exc}")
    try:
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as exc:
        fh.close()
        # ONLY "someone else holds it" becomes that message. A bare `except OSError`
        # reported `ENOLCK` and `EOPNOTSUPP` — a volume whose `flock` does not work at
        # all — as a phantom second sweep, so the documented launch would refuse to
        # start while blaming a run that does not exist. Measured by the review of this
        # diff, which raised all three errnos through it.
        if exc.errno not in (errno.EAGAIN, errno.EWOULDBLOCK):
            raise
        raise SystemExit(f"another sweep already holds {out}; refusing to touch it")
    return fh


def trim_partial_row(path):
    """Drop a torn final line, AND every row of the document it belonged to.

    Returns (bytes trimmed, document key or None).

    The resume invariant is "a document has a row ⇔ it is done", and a row is only a
    row once its newline is on disk. This is the one case where that is not
    automatic: a crash or `ENOSPC` between `out.write` and the newline leaves a
    fragment, and the document then reads as complete on a short set of rows.

    ⚠️ **Truncating to the last newline is NOT enough**, which is what the check for
    this found: a torn document had already written its earlier rows, so after the
    trim it still had a row and still read as done — on 1 page of 2. The document's
    whole row set has to go. Costs one document re-run; keeping it costs a silently
    short answer, which is the direction that matters.

    ⚠️ **Nor is the fragment's own key enough**, which is the review of 2026-08-19: a
    document's rows are written in ONE `out.write`, so the tear can land INSIDE a later
    row's key — and then the key is a *prefix* (`book/1954 - W`), it matches no row,
    and the landed rows of that very document survive as "done". Measured: a 3-page
    document read done on 2 pages. So the last COMPLETE row's key goes in the drop set
    too; it came from the same write whenever any of that document's rows landed. When
    the tear was at the start of the write instead, that key belongs to the *previous*
    document and costs one redundant re-run — the cheap direction.
    """
    # Detection is `torn_document`'s, so the read-only preview `--dry-run` prints and
    # the repair this does cannot come to hold two definitions of "torn" — C20 was one
    # idea in two functions.
    fragment, keys = torn_document(path)
    if not fragment:
        return 0, set()
    was = os.path.getsize(path)
    with open(path, "r+b") as fh:
        fh.truncate(was - fragment)
    if keys:
        drop_documents(path, keys)
    # Bytes, measured rather than summed. This used to add `drop_documents`' ROW COUNT
    # to a byte count and print the total as `N B`: 18 B reported for a file that shrank
    # 218. Found by the review of this diff, in the one line an unattended resume prints
    # about repairing itself.
    return was - os.path.getsize(path), keys


def provenance(args):
    """The one-line `# bar=… corpus=… binary=…` stamp a TSV carries about itself."""
    return (f"# bar={args.bar} corpus={os.path.abspath(args.corpus)} "
            f"binary={os.path.abspath(args.binary)}")


def enforced_provenance(stamp):
    """The part of a stamp a resume must MATCH: the bar and the corpus root.

    Not the binary. A different `--bar` makes the two halves of the file answer
    different questions, and a different `--corpus` re-keys every document through
    `relpath` so the whole corpus silently re-runs into one file — both are the file
    saying two things at once. A rebuilt or relocated `score-text-route` at a
    different path is a legitimate resume, so it is recorded and reported, never
    refused: enforcing it would have failed the first honest resume after a rebuild.
    """
    return [f for f in (stamp or "").split(" ") if not f.startswith("binary=")]


def recorded_provenance(path):
    """The stamp already in `path`, or None if it has none (or does not exist)."""
    if not os.path.exists(path):
        return None
    with open(path, errors="replace") as fh:
        fh.readline()                    # the header
        line = fh.readline().rstrip("\n")
    return line if line.startswith("#") else None


def drop_documents(path, keys):
    """Rewrite `path` without any row belonging to `keys`. Returns rows removed.

    Whole-file rewrite through a temp file and `os.replace`, so an interruption
    leaves either the old file or the new one and never a half-rewritten TSV.
    """
    if not os.path.exists(path):
        return 0
    removed = 0
    tmp = path + ".rewriting"
    # Strict decoding here, deliberately, where `completed()` and `report()` replace: this
    # one WRITES back what it reads, so `errors="replace"` would put U+FFFD inside a
    # filename that was only briefly torn. Its caller trims the torn row first, under the
    # lock, so a decode error here is a bug and belongs as a traceback rather than as a
    # quietly rewritten key.
    with open(path) as src, open(tmp, "w") as dst:
        for n, line in enumerate(src):
            if n == 0 or line.startswith("#"):
                dst.write(line)
                continue
            if line.rstrip("\n").split("\t")[0] in keys:
                removed += 1
                continue
            dst.write(line)
    os.replace(tmp, path)
    return removed


def corpus_documents(corpus):
    """Every pdf under `corpus`, keyed by path relative to it, sorted.

    Globbed rather than retyped: these filenames contain spaces and U+00A0.
    Sorted so a resume walks the same order as the run it is continuing.
    """
    found = []
    for base, _dirs, files in os.walk(corpus):
        for name in files:
            if not name.lower().endswith(".pdf"):
                continue
            full = os.path.join(base, name)
            key = os.path.relpath(full, corpus)
            if "\t" in key or "\n" in key:
                raise SystemExit(f"path contains a tab or newline, unwritable: {key!r}")
            found.append((key, full))
    return sorted(found)


def run_document(binary, pdf, bar, timeout):
    """One document. Returns (rows, status, config_error_or_None).

    `config_error` is set for the exits that describe the environment rather than
    this document; the caller aborts on it instead of recording it 233 times.
    """
    env = dict(os.environ)
    env["INKBAR"] = str(bar)
    try:
        done = subprocess.run([binary, pdf], capture_output=True, text=True,
                              env=env, timeout=timeout)
    except subprocess.TimeoutExpired:
        return [], f"timeout:{timeout}s", None
    except OSError as exc:
        return [], "error:exec", f"cannot run {binary}: {exc}"
    if done.returncode in CONFIG_EXITS:
        detail = (done.stderr or "").strip().splitlines()
        return [], f"error:{done.returncode}", (
            f"exit {done.returncode} is a configuration failure, so it will recur on "
            f"every document: {detail[-1] if detail else 'no message'}")
    if done.returncode != 0:
        return [], f"error:{done.returncode}", None
    rows, err = parse_tool_output(done.stdout)
    if err is not None:
        # BOTH parse failures are the environment, not the document. Header drift is
        # obvious; a row of the wrong width **under a correct header** is T18's actual
        # historical defect — "two of its four row printers were the wrong width" —
        # and it too recurs on every document. Recording it per document produced a
        # 233-row TSV of `error:parse` and `sweep()` still returned 0: measured by the
        # review of this file, and it is exactly the complete-looking-TSV-of-nothing
        # this design claims to prevent, arriving through the door left open for it.
        return [], ("error:header" if err.startswith("header drift")
                    else "error:parse"), err
    if not rows:
        return [], "no-pages", None
    return rows, "ok", None


# Column positions, by name rather than by counting — `cut -f13` has to be
# re-derived every time and this file's whole subject is fields under the wrong
# name. `report` reads through these.
AT = {name: i for i, name in enumerate(COLUMNS)}

# The band the population question is about: pages held at 1/8 today that a bar of
# 0.045 would refuse. Named here so `--report`'s histogram and the docstring cannot
# drift apart.
BANDS = [(0.0, 0.045), (0.045, 0.08), (0.08, 1.01)]


def report(path):
    """Counts from an existing TSV. No verdict about the constant — see the docstring.

    The column that answers the population question is **`verdict` against
    `barVerdict`**, not `barVerdict` alone: on the one document measured so far
    `barVerdict` reads `picture` on all five priced pages, including the two the bar
    does not move, because it is the verdict AT the bar and not a diff. A page is
    newly refused when it reads `all-text` today and `picture` at the bar.

    ⚠️ **`barVerdict` is compared on its FIRST WORD.** `score-text-route.swift` lines
    362 and 372 append `" STENCIL-MOVED"` and `" REPLICA-DISAGREES"` to it, so an
    exact `== "picture"` drops exactly the anomalous pages — measured by the review of
    this file: three newly-refused pages reported as **one**, with the other two's
    bytes missing from the totals as well. The pages that get a suffix are the ones
    R50's trade most needs counted.
    """
    if not os.path.exists(path):
        print(f"no such file: {path}")
        return 3
    done = completed(path)
    by_status = {}
    for status in done.values():
        by_status[status] = by_status.get(status, 0) + 1
    stamp = recorded_provenance(path)
    print(stamp if stamp else "⚠️ this file carries no provenance stamp, so the bar, "
          "corpus and binary it was measured with are not recorded in it")
    pages, route, verdict = 0, {}, {}
    band_counts, banded, unbanded = [0] * len(BANDS), 0, 0
    moved, moved_shipped, moved_at_bar, unpriced = 0, 0, 0, 0
    duplicate_rows = 0
    seen_rows = set()
    with open(path, errors="replace") as fh:
        fh.readline()
        for line in fh:
            f = line.rstrip("\n").split("\t")
            if len(f) != len(COLUMNS) or f[AT["status"]] != "ok":
                continue
            # One document+page must appear once. `completed()` dedupes by document,
            # this loop did not, so a TSV appended to twice printed one document and
            # double the pages, bands and bytes. Named rather than silently deduped:
            # a duplicate means something wrote the file twice and every total is
            # suspect, which is more than an arithmetic correction can say.
            key = (f[AT["document"]], f[AT["page"]])
            if key in seen_rows:
                duplicate_rows += 1
                continue
            seen_rows.add(key)
            pages += 1
            route[f[AT["route"]]] = route.get(f[AT["route"]], 0) + 1
            verdict[f[AT["verdict"]]] = verdict.get(f[AT["verdict"]], 0) + 1
            try:
                ink = float(f[AT["inkOut"]])
            except ValueError:
                continue                 # `-`: the page was never recognised
            # The bands are asserted to account for every parseable `inkOut`. Without
            # a denominator a value outside [0, 1.01) — or a `nan`, which parses as a
            # float — falls in no band and nothing says so.
            hit = False
            for n, (low, high) in enumerate(BANDS):
                if low <= ink < high:
                    band_counts[n] += 1
                    hit = True
            banded += 1 if hit else 0
            unbanded += 0 if hit else 1
            if (f[AT["verdict"]] == "all-text"
                    and f[AT["barVerdict"]].split(" ")[0] == "picture"):
                moved += 1
                # Both parsed into locals BEFORE either total moves. Adding them
                # one at a time meant a row whose `layered` parsed and whose
                # `layeredAtBar` did not left `moved_shipped` incremented and
                # `moved_at_bar` not, so the printed delta was wrong by a whole
                # page's bytes while the warning below called it merely absent.
                try:
                    shipped, at_bar = (int(f[AT["layered"]]),
                                       int(f[AT["layeredAtBar"]]))
                except ValueError:
                    unpriced += 1
                else:
                    moved_shipped += shipped
                    moved_at_bar += at_bar
    print(f"{len(done)} document(s) recorded in {path}")
    for status in sorted(by_status):
        print(f"  {by_status[status]:5d} document(s) status={status}")
    errors = sum(n for s, n in by_status.items() if s != "ok")
    if errors:
        print(f"  ⚠️ {errors} of those document(s) did not measure ok — read the "
              "statuses above before any total below")
    if duplicate_rows:
        print(f"  ⚠️ {duplicate_rows} duplicate document+page row(s) ignored; this "
              "file was appended to more than once, so treat every total as suspect")
    print(f"{pages} measured page row(s)")
    for key in sorted(route):
        print(f"  {route[key]:5d} route={key}")
    for key in sorted(verdict):
        print(f"  {verdict[key]:5d} verdict={key}")
    print(f"inkOutsideText over the {banded + unbanded} row(s) that carry one:")
    for n, (low, high) in enumerate(BANDS):
        print(f"  {band_counts[n]:5d} in [{low}, {high})")
    if unbanded:
        print(f"  ⚠️ {unbanded} row(s) carried an inkOut outside every band, so the "
              "bands do not sum to the line above")
    print(f"{moved} page(s) read all-text today and picture at the bar")
    if moved:
        print(f"  {moved_shipped} B shipped, {moved_at_bar} B at the bar, "
              f"{moved_at_bar - moved_shipped:+d} B")
        # A moved page whose bytes would not parse is a hole in the total above, so
        # it is named rather than dropped into it.
        if unpriced:
            print(f"  ⚠️ {unpriced} of them carried no byte count, so the totals "
                  "above are over the rest")
    # Exit 3 over a file that measured nothing, the way `score-threshold-loss` does
    # and for the same reason: a header-only TSV printing a table of zeros at rc 0 is
    # this project's most repeated defect, and `--report` is what a later session runs
    # to decide the sweep is finished.
    if pages == 0:
        print("no page was measured, so this file says nothing about the bar")
        return 3
    return 0


def sweep(args):
    if not os.path.isdir(args.corpus):
        raise SystemExit(f"no corpus directory at {args.corpus}")
    if not (os.path.isfile(args.binary) and os.access(args.binary, os.X_OK)):
        raise SystemExit(
            f"no executable at {args.binary}. Build it first:\n"
            "  mkdir -p /tmp/h && cp Tools/score-text-route.swift /tmp/h/main.swift\n"
            "  swiftc -O -o /tmp/score-text-route "
            "-target \"$(uname -m)-apple-macos13.0\" \\\n"
            "    $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift")
    docs = corpus_documents(args.corpus)
    # An `auto/` worktree has no `testdocs/` — it is 1.2 GB and uncommitted — and
    # `<repo>/testdocs` is this tool's DEFAULT corpus, so without this the headline
    # run is a header-only TSV and a `done: 0 document(s)` at rc 0. That is the
    # silent-success shape aimed straight at the one number the sweep exists for.
    if not docs:
        raise SystemExit(f"no pdfs under {args.corpus} — nothing to sweep")
    # `--dry-run` is read-only, so it is dispatched BEFORE the lock rather than under it:
    # taking the lock made the one command a polling session would reach for refuse
    # against the live sweep it was asking about, and made it fail in a read-only output
    # directory it was never going to write to. Found by the review of this diff. It is
    # also what keeps "`--dry-run` writes no file" literally true, `.lock` included.
    if args.dry_run:
        return dry_run(args, docs)
    # ⛔ The lock is taken BEFORE anything reads or writes `--out`, and that ordering is
    # the whole protection rather than the refusal itself. It used to be taken after the
    # torn-row trim and after `--retry-errors`' whole-file rewrite, so a second launch
    # onto a LIVE sweep's output mutated the file and refused afterwards — and
    # `drop_documents` finishes with `os.replace`, which swaps the inode, leaving the
    # running sweep appending to a file that is no longer named while the TSV a poller
    # reads simply stops growing. Hours of rendering lost with nothing saying so, which
    # is invariant 1 in a tool. Two checks pin the order, not just the refusal.
    lock = acquire_lock(args.out)
    try:
        return sweep_locked(args, docs)
    finally:
        lock.close()


def dry_run(args, docs):
    """List what a resume owes and stop. READS ONLY — see `torn_document`.

    It used to reach here after the trim and the rewrite had already run, so
    `--dry-run --retry-errors` DELETED the error statuses of the documents it then did
    not re-run: the preview costing the thing being previewed. The three subtractions
    below are the run's own, so the list cannot answer a different question.
    """
    # The refusal the real run would hit, hoisted here: a preview that lists work the run
    # will not do is a preview of nothing. Found by the review of this diff — `--dry-run
    # --bar 0.070` over a file stamped `bar=0.045` printed a to-do list and exited 0.
    refuse_mixed_provenance(args)
    done = completed(args.out)
    _, torn = torn_document(args.out)
    retry = {k for k, v in done.items()
             if args.retry_errors and v.startswith(("error", "timeout"))}
    owed = torn | retry
    if torn:
        print(f"would trim a torn final row and re-run {sorted(torn)}")
    if retry:
        print(f"would re-run {len(retry)} document(s) recorded with an error")
    todo = [(k, p) for k, p in docs if k not in done or k in owed]
    print(f"{len(docs)} document(s) under {args.corpus}; "
          f"{len(done) - len(owed & set(done))} already recorded; "
          f"{len(todo)} to do; bar {args.bar}")
    for key, _ in todo:
        print(f"  would run {key}")
    return 0


def refuse_mixed_provenance(args):
    """Refuse a resume at a different bar or corpus root. Reports a moved binary.

    One function, called by the run and by `--dry-run`, so the preview cannot accept
    what the run refuses. A different `--bar` makes the two halves of a file answer
    different questions, and a different `--corpus` re-keys every document through
    `relpath` so the whole corpus silently re-runs into one file. A rebuilt or moved
    binary is a legitimate resume: recorded and reported, never refused.
    """
    stamp, recorded = provenance(args), recorded_provenance(args.out)
    if recorded is None:
        return
    if enforced_provenance(recorded) != enforced_provenance(stamp):
        raise SystemExit(f"{args.out} was measured with\n  {recorded}\nand this "
                         f"run is\n  {stamp}\nrefusing to mix two measurements; "
                         "use a different --out")
    if recorded != stamp:
        print(f"⚠️ resuming with a different binary than the stamp records:\n"
              f"  stamp: {recorded}\n  now:   {stamp}", flush=True)


def sweep_locked(args, docs):
    """One sweep with `<out>.lock` held: resume the file, then a row per document."""
    trimmed, torn = trim_partial_row(args.out)
    if trimmed:
        print(f"trimmed a torn final row and all {trimmed} B of {sorted(torn)} from "
              f"{args.out}; those documents go back on the to-do list", flush=True)
    done = completed(args.out)
    if args.retry_errors:
        retry = {k for k, v in done.items() if v.startswith(("error", "timeout"))}
        # The rows have to GO, not just leave the resume set. Filtering the set alone
        # meant the retry APPENDED beside the old row, so the document held both an
        # `error:1` and an `ok` row: `completed()`'s `setdefault` kept the stale error
        # (so the document was retried again for ever) while `--report` counted its
        # pages twice — measured by the review of this file at exactly double the
        # truth on a one-page document.
        if retry:
            drop_documents(args.out, retry)
            done = completed(args.out)
    fresh = not os.path.exists(args.out) or os.path.getsize(args.out) == 0
    todo = [(k, p) for k, p in docs if k not in done]
    print(f"{len(docs)} document(s) under {args.corpus}; "
          f"{len(done)} already recorded; {len(todo)} to do; bar {args.bar}",
          flush=True)

    started = time.time()
    statuses = {}
    with open(args.out, "a") as out:
        if fresh:
            out.write("\t".join(COLUMNS) + "\n")
            out.flush()
        # Provenance, on the artefact itself. This TSV is meant to be committed as
        # evidence, and a resume at a different `--bar` or against a different
        # `--corpus` root would mix two measurements into one file with nothing in it
        # to say so — `relpath` even re-keys every document under a different root, so
        # the whole corpus silently re-runs into the same file. The comparison is
        # `refuse_mixed_provenance`'s, shared with `--dry-run`; only the WRITING of a
        # first stamp belongs to the run.
        if recorded_provenance(args.out) is None:
            out.write(provenance(args) + "\n")
            out.flush()
        else:
            refuse_mixed_provenance(args)
        for n, (key, path) in enumerate(todo, 1):
            t0 = time.time()
            rows, status, config = run_document(args.binary, path, args.bar,
                                                args.timeout)
            took = time.time() - t0
            if config is not None:
                # Nothing is written for this document: it is not the document's
                # fault and the next run must try it again.
                print(f"ABORT after {n - 1} document(s): {config}", flush=True)
                return 4
            text = ("\n".join(row(key, status, f) for f in rows) if rows
                    else row(key, status))
            out.write(text + "\n")
            out.flush()
            os.fsync(out.fileno())
            statuses[status] = statuses.get(status, 0) + 1
            elapsed = time.time() - started
            eta = elapsed / n * (len(todo) - n)
            print(f"[{n}/{len(todo)}] {status:12s} {len(rows):2d} row(s) "
                  f"{took:6.1f}s  elapsed {elapsed / 60:6.1f}m  "
                  f"eta {eta / 60:6.1f}m  {key}", flush=True)
    # The tally is on the LAST line on purpose: the documented polling recipe is
    # `tail -3 <log>`, and a closing `done: 233 document(s)` with no tally would
    # report 233 failures as a finished sweep to anyone reading the tail.
    bad = sum(n for s, n in statuses.items() if s != "ok")
    detail = ", ".join(f"{s}={statuses[s]}" for s in sorted(statuses))
    print(f"done: {len(todo)} document(s) in {(time.time() - started) / 60:.1f}m "
          f"[{detail or 'nothing run'}]", flush=True)
    if bad:
        print(f"⚠️ {bad} of {len(todo)} document(s) did not measure ok", flush=True)
    return 0


def self_test():
    """Drive the parser, the resume set and the abort rule against a stub binary.

    Run by the pre-commit hook, and it starts no sweep: every case here points
    `--binary` at a python script that prints canned `score-text-route` output, so
    the shape of a document's run is exercised without rendering a page.
    """
    import atexit, contextlib, io, shutil, stat
    failures, ran = [], []

    def check(name, ok):
        ran.append(name)
        print(f"  {'ok  ' if ok else 'FAIL'} {name}")
        if not ok:
            failures.append(name)

    tmp = tempfile.mkdtemp(prefix="inkbar-selftest-")
    atexit.register(shutil.rmtree, tmp, ignore_errors=True)

    header = "\t".join(TOOL_COLUMNS)
    # The two row shapes the real tool prints, taken from the 2026-08-19 control run
    # over `1954 - Why.pdf`: a priced grey page the bar moves, and an already-1-bit
    # page that carries nothing but its verdict.
    good = (f"{header}\n"
            "p4\tgrey\t0.01\t0.5\t0.0540\t22762\t70000\t+4523\tall-text\t"
            "0.00000\tpicture\t67976\t+45214\n"
            "p1\tbilevel\t-\t-\t-\t-\t-\t-\talready 1-bit\t-\t-\t-\t-\n"
            "\n"
            "2 picture-route pages: layered 1 B, 1-bit 2 B, delta +1 B (1 B/page)\n")

    def stub(name, stdout="", rc=0, stderr="", sleep=0):
        p = os.path.join(tmp, name)
        with open(p, "w") as fh:
            fh.write("#!/usr/bin/env python3\n"
                     "import sys, time, os\n"
                     f"time.sleep({sleep})\n"
                     f"sys.stdout.write({stdout!r})\n"
                     f"sys.stderr.write({stderr!r})\n"
                     f"sys.exit({rc})\n")
        os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC)
        return p

    corpus = os.path.join(tmp, "corpus", "book")
    os.makedirs(corpus)
    # Two documents, one of them with the space-and-U+00A0 shape the real corpus
    # has, so the key that goes in the TSV is exercised rather than assumed.
    names = ["Cohen_1990 Making a New Deal.pdf", "1954 -\u00a0Why.pdf"]
    for name in names:
        open(os.path.join(corpus, name), "w").close()
    open(os.path.join(tmp, "corpus", "notes.txt"), "w").close()

    docs = corpus_documents(os.path.join(tmp, "corpus"))
    check("only pdfs are swept, and the key is the path relative to the corpus",
          [k for k, _ in docs] == sorted("book/" + n for n in names))
    # A tab in a filename is legal on this volume and would silently split one
    # document's key into two fields, shifting every value after it. Refused at
    # the walk rather than at the printer, so the sweep stops before rendering
    # 2,500 pages into a file it cannot write correctly.
    tabbed = os.path.join(tmp, "tabcorpus")
    os.makedirs(tabbed)
    open(os.path.join(tabbed, "has\ttab.pdf"), "w").close()
    raised = False
    try:
        corpus_documents(tabbed)
    except SystemExit:
        raised = True
    check("a corpus filename containing a tab stops the sweep", raised)

    # --- the parser ------------------------------------------------------------
    rows, err = parse_tool_output(good)
    check("both page rows are parsed and the prose summary is not",
          err is None and len(rows) == 2 and rows[0][0] == "p4"
          and rows[1][1] == "bilevel")
    # The header check, which is the whole reason this file does not just split on
    # tabs. A tool that grew a column would otherwise put every value one name to
    # the left of what it means.
    drifted = good.replace(header, header + "\tnewColumn", 1)
    _, err = parse_tool_output(drifted)
    check("a tool header with an extra column is refused, not parsed around",
          err is not None and err.startswith("header drift"))
    renamed = good.replace("inkOut", "inkOutside", 1)
    _, err = parse_tool_output(renamed)
    check("a RENAMED column is refused too, not only a different count",
          err is not None and err.startswith("header drift"))
    narrow = good.replace("p1\tbilevel\t-", "p1\tbilevel", 1)
    _, err = parse_tool_output(narrow)
    check("a data row of the wrong width is refused",
          err is not None and "row width" in err)
    check("empty output is refused rather than read as zero pages",
          parse_tool_output("")[1] == "no output")

    # --- one document, end to end ---------------------------------------------
    rows, status, config = run_document(stub("ok.py", stdout=good), "x.pdf", 0.045, 30)
    check("a good run reports ok with its rows", status == "ok" and len(rows) == 2
          and config is None)
    # Exit 1 is "this file will not open" — the one document's problem.
    _, status, config = run_document(stub("rc1.py", rc=1), "x.pdf", 0.045, 30)
    check("exit 1 is recorded against the document, not aborted on",
          status == "error:1" and config is None)
    # Exits 2 and 3 are the environment. Recording them would build a
    # complete-looking TSV of 233 failures.
    #
    # ⚠️ The codes below are LITERAL, and the membership is asserted separately.
    # Iterating `sorted(CONFIG_EXITS)` — which is what this loop did first — makes
    # both cases DISAPPEAR when the constant is emptied instead of failing:
    # measured, `CONFIG_EXITS = set()` was killed by two checks rather than four.
    # A case generated from the value it is checking is §3 inside a self-test.
    check("the configuration exits are exactly the tool's own 2 and 3",
          CONFIG_EXITS == {2, 3})
    for rc in (2, 3):
        _, status, config = run_document(
            stub(f"rc{rc}.py", rc=rc, stderr="jbig2 not found\n"), "x.pdf", 0.045, 30)
        check(f"exit {rc} is a configuration failure and aborts",
              status == f"error:{rc}" and config is not None)
    _, status, config = run_document(stub("drift.py", stdout=drifted), "x.pdf", 0.045, 30)
    check("header drift aborts the sweep as well as failing the document",
          status == "error:header" and config is not None)
    _, status, _ = run_document(stub("empty.py", stdout=f"{header}\n"), "x.pdf", 0.045, 30)
    check("a document with no page rows is `no-pages`, not an error",
          status == "no-pages")
    _, status, _ = run_document(stub("slow.py", sleep=2), "x.pdf", 0.045, 1)
    check("a document past the timeout is recorded and the sweep continues",
          status.startswith("timeout:"))
    # `INKBAR` reaches the tool. Without this the sweep could price nothing at all
    # and every row would read `same` — the misreading the tool's own range guard
    # exists to prevent, arriving by the driver instead.
    echo = os.path.join(tmp, "echo.py")
    with open(echo, "w") as fh:
        fh.write("#!/usr/bin/env python3\nimport os, sys\n"
                 f"sys.stdout.write({header!r} + '\\n')\n"
                 "sys.stdout.write('p1\\t' + os.environ.get('INKBAR', 'UNSET')"
                 f" + '\\t' + '\\t'.join(['-'] * {len(TOOL_COLUMNS) - 2}) + '\\n')\n")
    os.chmod(echo, os.stat(echo).st_mode | stat.S_IEXEC)
    rows, status, _ = run_document(echo, "x.pdf", 0.0451, 30)
    check("the bar is passed to the tool as INKBAR",
          status == "ok" and rows[0][1] == "0.0451")

    # --- the printer -----------------------------------------------------------
    check("a status row is as wide as a data row",
          len(row("d", "no-pages").split("\t")) == len(COLUMNS)
          == len(row("d", "ok", rows[0]).split("\t")))
    # `SystemExit`, not `AssertionError`: under `python3 -O` an assertion is stripped
    # and the printer would write misaligned rows in the sweep while the hook, which
    # runs without `-O`, saw a green gate.
    raised = False
    try:
        row("d", "ok", ["only", "two"])
    except SystemExit:
        raised = True
    check("a body of the wrong width is refused by the printer", raised)
    raised = False
    try:
        row("has\ttab", "ok")
    except SystemExit:
        raised = True
    check("a field containing a tab is refused, not written", raised)

    # --- resume ----------------------------------------------------------------
    class A:
        pass
    args = A()
    args.corpus = os.path.join(tmp, "corpus")
    args.out = os.path.join(tmp, "out.tsv")
    args.bar = 0.045
    args.timeout = 30
    args.retry_errors = False
    args.dry_run = False
    args.binary = stub("sweep.py", stdout=good)
    check("a first sweep completes", sweep(args) == 0)
    first = open(args.out).read()
    check("the output carries this file's header once and both documents",
          first.startswith("\t".join(COLUMNS) + "\n")
          and all(("book/" + n) in first for n in names))
    check("every document recorded is complete", set(completed(args.out).values()) == {"ok"})
    # The resume, which is the property the whole 3-4 hour shape rests on.
    args.binary = stub("must-not-run.py", rc=99)
    check("a resume over a finished TSV runs nothing", sweep(args) == 0)
    check("and appends nothing", open(args.out).read() == first)

    # A no-pages document must count as done, or a resume retries it for ever.
    args.out = os.path.join(tmp, "out2.tsv")
    args.binary = stub("nopages.py", stdout=f"{header}\n")
    sweep(args)
    before = open(args.out).read()
    args.binary = stub("must-not-run2.py", rc=99)
    sweep(args)
    # `\tno-pages\t`, not the substring: `before.count("no-pages")` also matched a
    # status renamed to `error:no-pages`, so a mutant that turned the status into an
    # error slipped past this case with one kill instead of two.
    check("a no-pages document is not retried on resume",
          open(args.out).read() == before
          and before.count("\tno-pages\t") == 2)

    # An aborted sweep writes nothing for the document that aborted it, so the
    # document is tried again next time rather than recorded as measured.
    args.out = os.path.join(tmp, "out3.tsv")
    args.binary = stub("cfg.py", rc=3, stderr="jbig2 not found\n")
    check("a configuration failure returns 4", sweep(args) == 4)
    check("and records no document row at all", completed(args.out) == {})

    # A row of the wrong width UNDER A CORRECT HEADER is T18's own defect, and it
    # recurs on every document, so it aborts like header drift. Recorded per document
    # it produced a 233-row TSV of `error:parse` at rc 0 — the complete-looking TSV of
    # nothing. Measured by the review of this file.
    args.out = os.path.join(tmp, "out4.tsv")
    args.binary = stub("narrow.py", stdout=narrow)
    check("a row-width drift under a correct header aborts, it is not recorded 233 times",
          sweep(args) == 4 and completed(args.out) == {})

    # `--retry-errors` must REMOVE the old rows, not merely stop skipping the
    # document. Filtering the resume set alone appended beside the stale row: the
    # document then held both `error:1` and `ok`, `completed()` kept the error (so it
    # was retried for ever) and `--report` counted its pages twice.
    args.out = os.path.join(tmp, "retry.tsv")
    args.binary = stub("rc1b.py", rc=1)
    sweep(args)
    check("an errored document is recorded and skipped by a plain resume",
          set(completed(args.out).values()) == {"error:1"})
    args.retry_errors = True
    args.binary = stub("retry-ok.py", stdout=good)
    sweep(args)
    args.retry_errors = False
    body = open(args.out).read()
    check("--retry-errors replaces the errored rows instead of appending beside them",
          set(completed(args.out).values()) == {"ok"}
          and "error:1" not in body and body.count("\tok\t") == 4)

    # A torn final row must not read as a completed document. The trigger is a crash
    # or ENOSPC between the write and the newline over an unattended 3-4 hour run.
    args.out = os.path.join(tmp, "torn.tsv")
    args.binary = stub("torn.py", stdout=good)
    sweep(args)
    whole = open(args.out).read()
    with open(args.out, "w") as fh:
        fh.write(whole[:-12])            # lose the newline and part of the last row
    torn_size = os.path.getsize(args.out)
    torn_doc = sorted(completed(args.out))
    check("a torn final row would otherwise read as a completed document",
          len(torn_doc) == 2)
    # Trimming the torn LINE is not enough: that document had already written an
    # earlier row, so it still read as done on half its pages. Its whole row set goes.
    trimmed, torn_keys = trim_partial_row(args.out)
    check("the torn row's whole document is dropped, not just its last line",
          trimmed > 0 and torn_keys and len(completed(args.out)) == 1
          and not (torn_keys & set(completed(args.out))))
    # The bytes it reports are BYTES. This used to add `drop_documents`' row count to a
    # byte count, so the line an unattended resume prints about repairing itself read
    # 18 B for a file that had shrunk 218.
    check("and the trimmed figure is the bytes the file actually lost",
          trimmed == torn_size - os.path.getsize(args.out))

    # ⚠️ The tear can land INSIDE the key, and then the fragment's own key is a prefix
    # matching no row while that document's earlier rows survive as done. Measured
    # 2026-08-19 at 2 of 3 pages on a three-page document. The last COMPLETE row's key
    # is owed as well, which is what this pins; `owe(...)` on the fragment alone is the
    # mutant it kills.
    three = (f"{header}\n"
             "p1\tgrey\t0.01\t0.5\t0.0540\t1\t2\t+1\tall-text\t0.0\tpicture\t3\t+2\n"
             "p2\tgrey\t0.01\t0.5\t0.0540\t1\t2\t+1\tall-text\t0.0\tpicture\t3\t+2\n"
             "p3\tgrey\t0.01\t0.5\t0.0540\t1\t2\t+1\tall-text\t0.0\tpicture\t3\t+2\n"
             "\n3 picture-route pages: layered 1 B, 1-bit 2 B, delta +1 B (1 B/page)\n")
    args.out = os.path.join(tmp, "midkey.tsv")
    args.binary = stub("midkey.py", stdout=three)
    sweep(args)
    lines = open(args.out).read().split("\n")
    doc2 = lines[-2].split("\t")[0]                # the last row's document
    cut_in_key = "\n".join(lines[:-2] + [doc2[:len(doc2) - 6]])   # tear inside the key
    with open(args.out, "w") as fh:
        fh.write(cut_in_key)
    trim_partial_row(args.out)
    check("a tear INSIDE the document key still takes that document's landed rows",
          doc2 not in completed(args.out))
    # And a fragment carrying no key of its own (a tear before its first tab landed) is
    # the one case `drop_documents` cannot reach — its first field is `""`, which matches
    # no document — so the TRUNCATE is the whole repair there. CONTRIBUTING 4c: the branch
    # is made to execute rather than reasoned about, and a no-op truncate fails this.
    keyless = "\tok\tp1"
    with open(args.out, "a") as fh:
        fh.write(keyless)
    trimmed, torn_keys = trim_partial_row(args.out)
    after = open(args.out).read()
    check("a keyless fragment is truncated away, the branch drop_documents cannot reach",
          keyless not in after and after.endswith("\n")
          and trimmed >= len(keyless.encode()))
    args.out = os.path.join(tmp, "torn.tsv")
    # ...and `sweep()` must actually CALL that. Driving `trim_partial_row` directly
    # left "sweep does the trim" unpinned: measured, a mutant that removed the call
    # survived every case above.
    with open(args.out, "w") as fh:
        fh.write(whole[:-12])
    args.binary = stub("retorn.py", stdout=good)
    sweep(args)
    check("a sweep resumed onto a torn file re-runs that document to completion",
          len(completed(args.out)) == 2
          and set(completed(args.out).values()) == {"ok"}
          and open(args.out).read().endswith("\n"))

    # The lock. A second sweep onto one `--out` is the duplicate-row path, and nothing
    # exercised it: a mutant removing the `flock` survived.
    args.out = os.path.join(tmp, "locked.tsv")
    args.binary = stub("lock.py", stdout=good)
    sweep(args)
    holder = open(lock_path(args.out), "a")
    fcntl.flock(holder.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    raised = False
    try:
        sweep(args)
    except SystemExit:
        raised = True
    holder.close()
    check("a second sweep onto a locked output file is refused", raised)
    check("and the lock is released when the first sweep ends", sweep(args) == 0)

    # ⛔ The refusal above is not the protection; its POSITION is. The trim and
    # `--retry-errors`' whole-file rewrite used to run before the lock was taken, so a
    # second launch onto a live sweep's `--out` mutated it and refused afterwards. The
    # inode is asserted beside the bytes because `drop_documents` ends in `os.replace`:
    # identical content under a NEW inode is the destructive case, since the running
    # sweep goes on appending to the unlinked old one — its remaining hours land nowhere
    # and the file a later session polls just stops growing.
    def fingerprint(p):
        return open(p, "rb").read(), os.stat(p).st_ino

    args.out = os.path.join(tmp, "locked-order.tsv")
    args.binary = stub("lockorder.py", rc=1)          # every document errors
    sweep(args)
    holder = open(lock_path(args.out), "a")
    fcntl.flock(holder.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    before = fingerprint(args.out)
    args.retry_errors = True
    raised = False
    try:
        sweep(args)
    except SystemExit:
        raised = True
    check("--retry-errors against a LOCKED file is refused before it rewrites a row",
          raised and fingerprint(args.out) == before)
    args.retry_errors = False
    with open(args.out, "a") as fh:
        fh.write("book/torn.pdf\tok")                 # a torn final row, no newline
    before = fingerprint(args.out)
    raised = False
    try:
        sweep(args)
    except SystemExit:
        raised = True
    check("and a torn row is not trimmed out from under a running sweep either",
          raised and fingerprint(args.out) == before)
    holder.close()

    # And the lock is a SIDECAR because of this, which is a claim rather than a taste:
    # a lock held on the artefact itself does not survive `--retry-errors` rewriting it.
    # `drop_documents` ends in `os.replace`, so the running sweep's lock would sit on an
    # unlinked inode while a second sweep took the new file's lock and appended into it —
    # the duplicate-row path, reopened by the fix for it. `lock_path` returning `out`
    # unchanged is the mutant this kills.
    args.out = os.path.join(tmp, "lock-survives.tsv")
    args.binary = stub("locksurvive.py", rc=1)
    sweep(args)
    held = acquire_lock(args.out)                      # what a running sweep holds
    drop_documents(args.out, set(completed(args.out)))  # what --retry-errors does to it
    taken = True
    try:
        acquire_lock(args.out).close()
    except SystemExit:
        taken = False
    held.close()
    check("the running sweep's lock survives its own file being rewritten under it",
          not taken)

    # The `finally` that closes it. Refcounting alone happens to close the handle when
    # `sweep()`'s frame dies, so deleting the `try/finally` left the suite green — except
    # HERE, inside an `except` block, where the traceback still holds that frame and
    # therefore the handle. That is the one place the two mechanisms differ, and it is a
    # realistic one: this file's own resume path raises `SystemExit` from inside the lock.
    args.out = os.path.join(tmp, "lock-freed.tsv")
    args.binary = stub("lockfreed.py", stdout=good)
    sweep(args)
    args.bar = 0.070                                   # provokes the provenance refusal
    freed = False
    try:
        sweep(args)
    except SystemExit:
        try:
            acquire_lock(args.out).close()
            freed = True
        except SystemExit:
            freed = False
    args.bar = 0.045
    check("the lock is released even while a traceback still holds the sweep's frame",
          freed)

    # `flock` failing for a reason that is NOT "someone holds it" must not be reported as
    # a phantom sweep: on a volume whose locks do not work (ENOLCK, EOPNOTSUPP) the
    # documented 3-hour launch would refuse to start while blaming a run that does not
    # exist. A bare `except OSError` did exactly that for all three errnos tried.
    real_flock = fcntl.flock
    fcntl.flock = lambda *a, **k: (_ for _ in ()).throw(
        OSError(errno.ENOLCK, "No locks available"))
    try:
        surfaced = None
        try:
            acquire_lock(os.path.join(tmp, "nolocks.tsv"))
        except SystemExit as exc:
            surfaced = f"SystemExit: {exc}"
        except OSError as exc:
            surfaced = f"OSError:{exc.errno}"
    finally:
        fcntl.flock = real_flock
    check("a flock failure that is not contention surfaces as itself, not as a rival",
          surfaced == f"OSError:{errno.ENOLCK}")

    # A torn row can be torn INSIDE a UTF-8 sequence — the corpus's filenames carry
    # U+00A0 — and `completed()` decoded strictly, so `--report` and `--dry-run` over a
    # live sweep's file died with an uncaught `UnicodeDecodeError`. Those are the two
    # commands a polling session runs.
    args.out = os.path.join(tmp, "torn-utf8.tsv")
    args.binary = stub("tornutf8.py", stdout=good)
    sweep(args)
    with open(args.out, "ab") as fh:
        # ⚠️ Cut so the U+00A0 itself is HALVED: these bytes really are undecodable.
        # As `…encode()[:-1]` this dropped the trailing "h" instead, leaving valid
        # UTF-8 — so the case could not fail, and the mutant restoring strict
        # decoding survived it. That is how it was found; `errors="replace"` is what
        # this is really checking.
        fh.write("book/1954 -\u00a0Wh".encode("utf-8")[:-3])
    crashed = None
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            report(args.out)
            args.dry_run = True
            sweep(args)
    except UnicodeDecodeError as exc:
        crashed = str(exc)
    args.dry_run = False
    check("--report and --dry-run survive a row torn mid-UTF-8", crashed is None)

    # `--dry-run` says "list what would run and stop", and it used to reach that line
    # after the trim and the rewrite: the preview costing the thing it previewed.
    args.out = os.path.join(tmp, "locked-order.tsv")   # the torn + errored file above
    args.dry_run, args.retry_errors = True, True
    before = fingerprint(args.out)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = sweep(args)
    listed = buf.getvalue()
    check("--dry-run neither trims a torn row nor drops a retried document's rows",
          rc == 0 and fingerprint(args.out) == before)
    # ⚠️ Asserted by NAME, not by count. `== 2` was satisfied by three wrong
    # implementations — `todo = docs` ignoring the resume set entirely, a `todo` that
    # never lists a never-run document, and an `owed` that forgets the torn one — because
    # both fixture documents are owed here, so 2 is also every wrong answer's number.
    # Measured: all three kept the suite green. Found by the review of this diff.
    check("and it lists the torn row and both errored documents BY NAME as to-do",
          all(f"  would run {k}\n" in listed for k, _ in docs)
          and listed.count("would run ") == 2 and "would trim" in listed)
    # ...and the complement: a document already recorded `ok` must NOT be listed, which is
    # what "ignore the resume set" would break and the case above cannot see.
    args.out = os.path.join(tmp, "dry-partial.tsv")
    args.retry_errors = False
    args.dry_run = False
    args.binary = stub("drypartial.py", stdout=good)
    sweep(args)
    drop_documents(args.out, {docs[1][0]})            # as if only the first had run
    args.dry_run = True
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        sweep(args)
    listed = buf.getvalue()
    check("a document already recorded ok is not listed, and the unrun one is",
          f"  would run {docs[1][0]}\n" in listed
          and f"  would run {docs[0][0]}\n" not in listed)
    # A document recorded `ok` but TORN is owed even without `--retry-errors`. Needed
    # because the torn fixture above also holds both documents in `retry`, so `owed =
    # retry` — the preview forgetting the torn set entirely — was green everywhere else.
    with open(args.out, "a") as fh:
        fh.write(docs[0][0] + "\tok")             # a torn tail naming the recorded one
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        sweep(args)
    check("a torn document is owed by the preview even without --retry-errors",
          f"  would run {docs[0][0]}\n" in buf.getvalue())
    # The preview must refuse what the run refuses. `--dry-run --bar 0.070` over a file
    # stamped `bar=0.045` printed a to-do list and exited 0: a preview of work that would
    # never be done. One `refuse_mixed_provenance` for both paths now.
    args.bar = 0.070
    raised = False
    try:
        sweep(args)
    except SystemExit:
        raised = True
    check("--dry-run refuses a bar the run would refuse, rather than previewing it",
          raised)
    args.bar = 0.045
    args.dry_run, args.retry_errors = False, False

    # The provenance stamp, and the refusal to mix two measurements in one file.
    args.out = os.path.join(tmp, "prov.tsv")
    args.binary = stub("prov.py", stdout=good)
    sweep(args)
    check("the TSV records the bar, the corpus and the binary it was measured with",
          (recorded_provenance(args.out) or "").startswith(f"# bar={args.bar} corpus="))
    args.bar = 0.070
    raised = False
    try:
        sweep(args)
    except SystemExit:
        raised = True
    args.bar = 0.045
    check("a resume at a DIFFERENT bar is refused rather than mixed in", raised)
    # ...and the converse, or the rule above could be a refuse-every-resume rule
    # wearing a disguise. A relocated binary is a legitimate resume.
    args.binary = stub("prov2.py", stdout=good)
    check("a resume with the SAME bar and corpus but a rebuilt binary is allowed",
          sweep(args) == 0)

    # An empty corpus is the live silent-success path: an `auto/` worktree has no
    # `testdocs/`, and that is this tool's default `--corpus`.
    args.corpus = os.path.join(tmp, "emptycorpus")
    os.makedirs(args.corpus)
    args.out = os.path.join(tmp, "empty-corpus.tsv")
    raised = False
    try:
        sweep(args)
    except SystemExit:
        raised = True
    check("a corpus with no pdfs stops the sweep instead of reporting done: 0",
          raised and not os.path.exists(args.out))
    args.corpus = os.path.join(tmp, "corpus")

    # `--dry-run` must not render 2,500 pages, and must not create the output.
    args.out = os.path.join(tmp, "dry.tsv")
    args.dry_run = True
    args.binary = stub("must-not-run3.py", rc=99)
    check("--dry-run runs no document and writes no file",
          sweep(args) == 0 and not os.path.exists(args.out))
    args.dry_run = False

    # A zero-byte --out is resumable. `"".split("\t") == [""]` is truthy, so the old
    # header guard could never take its left branch and refused its own empty file.
    args.out = os.path.join(tmp, "zero.tsv")
    open(args.out, "w").close()
    args.binary = stub("zero.py", stdout=good)
    check("a zero-byte output file is resumed, not refused",
          sweep(args) == 0 and len(completed(args.out)) == 2)

    # --- --report ---------------------------------------------------------------
    # Driven over the ten rows of the 2026-08-19 control run on `1954 - Why.pdf`,
    # whose totals are the ones `BUGS.md` C26 already carries: the three moved pages
    # are 65,477 B shipped and 195,785 B at the bar. So this pins the reader against
    # a measurement rather than against invented rows, and it is the case that would
    # catch `--report` counting `barVerdict` alone — which reads `picture` on all
    # five priced pages here, including the two the bar does not move.
    ctl = os.path.join(tmp, "control.tsv")
    ctl_rows = [
        # page, route, inkOut, layered, verdict, barVerdict, layeredAtBar, barDelta
        ("p1", "bilevel", "-", "-", "already 1-bit", "-", "-", "-"),
        ("p2", "colour", "0.1072", "74081", "picture", "picture", "74081", "same"),
        ("p3", "bilevel", "-", "-", "already 1-bit", "-", "-", "-"),
        ("p4", "grey", "0.0540", "22762", "all-text", "picture", "67976", "+45214"),
        ("p5", "bilevel", "-", "-", "already 1-bit", "-", "-", "-"),
        ("p6", "grey", "0.0493", "20708", "all-text", "picture", "62397", "+41689"),
        ("p7", "grey", "0.0660", "22007", "all-text", "picture", "65412", "+43405"),
        ("p8", "bilevel", "-", "-", "already 1-bit", "-", "-", "-"),
        ("p9", "bilevel", "-", "-", "already 1-bit", "-", "-", "-"),
        ("p10", "grey", "0.9735", "31577", "picture", "picture", "31577", "same"),
    ]
    # Three row shapes `1954 - Why.pdf` does NOT have, kept in a SECOND fixture so
    # the control above stays exactly the ten measured rows and its byte check stays a
    # claim about measured data. The review of this file mutated each of these three
    # behaviours and found that nothing objected.
    edge_rows = [
        # (a) The MODAL corpus page: all-text today and still all-text at the bar.
        # With only the ten rows above, every `all-text` page was also moved, so
        # dropping the `barVerdict` term from `report()` survived — and over the
        # corpus that mutant reports every text page as newly refused.
        ("p1", "grey", "0.0100", "9000", "all-text", "all-text", "9000", "same"),
        # (b) A page sitting exactly ON a band edge, which is the value the whole
        # entry is about. `low <= ink < high` was killed by nothing, so `<=` at both
        # ends — double-counting a boundary page into two bands — survived.
        ("p2", "grey", "0.0450", "1000", "all-text", "picture", "3000", "+2000"),
        # (c) `barVerdict` carrying `score-text-route`'s own suffix (that tool's lines
        # 362 and 372 append ` STENCIL-MOVED` and ` REPLICA-DISAGREES`). An exact
        # `== "picture"` dropped these, and they are the anomalous pages — the ones
        # R50's trade most needs counted.
        ("p3", "grey", "0.0700", "2000", "all-text", "picture REPLICA-DISAGREES",
         "6000", "+4000"),
    ]
    def write_fixture(path, document, rows_in):
        with open(path, "w") as fh:
            fh.write("\t".join(COLUMNS) + "\n")
            for page, rt, ink, lay, verd, bverd, batbar, bdelta in rows_in:
                fields = ["-"] * len(TOOL_COLUMNS)
                fields[TOOL_COLUMNS.index("page")] = page
                fields[TOOL_COLUMNS.index("route")] = rt
                fields[TOOL_COLUMNS.index("inkOut")] = ink
                fields[TOOL_COLUMNS.index("layered")] = lay
                fields[TOOL_COLUMNS.index("verdict")] = verd
                fields[TOOL_COLUMNS.index("barVerdict")] = bverd
                fields[TOOL_COLUMNS.index("layeredAtBar")] = batbar
                fields[TOOL_COLUMNS.index("barDelta")] = bdelta
                fh.write(row(document, "ok", fields) + "\n")

    write_fixture(ctl, "book/1954 - Why.pdf", ctl_rows)
    edge = os.path.join(tmp, "edge.tsv")
    write_fixture(edge, "synthetic/edge.pdf", edge_rows)

    import io, contextlib

    def report_text(path):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = report(path)
        return rc, buf.getvalue()

    rc, out = report_text(ctl)
    check("--report over the control run returns 0", rc == 0)
    check("--report counts the three pages the bar newly refuses, not the five priced",
          "3 page(s) read all-text today and picture at the bar" in out)
    check("--report reproduces the measured bytes on those three pages",
          "65477 B shipped, 195785 B at the bar, +130308 B" in out)
    # The band the whole sweep exists to populate. Three of this document's pages sit
    # in it; p2 and p10 are above it and the six 1-bit pages carry no inkOut at all.
    check("--report puts those three pages in the [0.045, 0.08) band",
          "3 in [0.045, 0.08)" in out and "0 in [0.0, 0.045)" in out
          and "2 in [0.08, 1.01)" in out)
    check("--report counts every measured row, including the ones with no inkOut",
          "13 measured page row(s)" not in out and "10 measured page row(s)" in out)
    check("--report prints the denominator the bands are supposed to sum to",
          "inkOutsideText over the 5 row(s) that carry one:" in out)

    # The three shapes the control document does not have.
    rc, out = report_text(edge)
    check("an all-text page that is STILL all-text at the bar is not counted as moved",
          "2 page(s) read all-text today and picture at the bar" in out)
    check("a `picture` carrying score-text-route's own suffix IS counted",
          "3000 B shipped, 9000 B at the bar, +6000 B" in out)
    check("a page exactly on a band edge lands in one band, not two",
          "1 in [0.0, 0.045)" in out and "2 in [0.045, 0.08)" in out
          and "0 in [0.08, 1.01)" in out
          and "inkOutsideText over the 3 row(s) that carry one:" in out)

    # A TSV that measured nothing exits 3, the way `score-threshold-loss` does.
    nothing = os.path.join(tmp, "nothing.tsv")
    with open(nothing, "w") as fh:
        fh.write("\t".join(COLUMNS) + "\n")
    rc, out = report_text(nothing)
    check("--report over a header-only TSV exits 3 rather than printing zeros at 0",
          rc == 3 and "no page was measured" in out)
    check("--report on a missing file exits 3 with a message, not a traceback",
          report_text(os.path.join(tmp, "absent.tsv"))[0] == 3)

    # Duplicate rows inflate pages, bands and bytes while the document count still
    # looks right, so they are named and skipped rather than silently summed.
    dup = os.path.join(tmp, "dup.tsv")
    with open(dup, "w") as fh:
        fh.write(open(ctl).read())
        fh.write("".join(l for l in open(ctl).read().splitlines(True)[1:]))
    rc, out = report_text(dup)
    check("duplicate document+page rows are reported, and counted once",
          "10 duplicate document+page row(s) ignored" in out
          and "10 measured page row(s)" in out
          and "65477 B shipped, 195785 B at the bar" in out)

    # A half-priced row: `layered` is a number and `layeredAtBar` is not. Adding
    # the two totals one at a time counted the first and not the second, so the
    # printed delta was a whole page's bytes wrong while the warning under it said
    # only that a count was missing.
    half = os.path.join(tmp, "half.tsv")
    with open(half, "w") as fh:
        fh.write("\t".join(COLUMNS) + "\n")
        fields = ["-"] * len(TOOL_COLUMNS)
        fields[TOOL_COLUMNS.index("page")] = "p4"
        fields[TOOL_COLUMNS.index("route")] = "grey"
        fields[TOOL_COLUMNS.index("inkOut")] = "0.0540"
        fields[TOOL_COLUMNS.index("layered")] = "22762"
        fields[TOOL_COLUMNS.index("verdict")] = "all-text"
        fields[TOOL_COLUMNS.index("barVerdict")] = "picture"
        fields[TOOL_COLUMNS.index("layeredAtBar")] = "-"
        fh.write(row("d.pdf", "ok", fields) + "\n")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        report(half)
    out = buf.getvalue()
    check("a moved row missing one byte count contributes to NEITHER total",
          "1 page(s) read all-text today and picture at the bar" in out
          and "0 B shipped, 0 B at the bar, +0 B" in out
          and "1 of them carried no byte count" in out)

    args.out = os.path.join(tmp, "out.tsv")
    check("--report reads the sweep's own header back", report(args.out) == 0)
    mismatched = os.path.join(tmp, "alien.tsv")
    with open(mismatched, "w") as fh:
        fh.write("document\tsomething-else\n")
    raised = False
    try:
        completed(mismatched)
    except SystemExit:
        raised = True
    check("a TSV written under different columns is refused, not appended to", raised)

    # ⚠️ The count is asserted, and this is not ceremony. Nothing enforced how many
    # cases ran, so a mutant that made 19 of them VANISH looked identical to a pass
    # except in the exit code — and the "34 checks" published in five documents was
    # `check(` call sites counted by eye against 35 cases actually run, because one
    # sits inside a loop. `EXPECTED_CHECKS` is measured by running this.
    # `len(ran) + 1`, because this case is not in `ran` until `check` is entered and
    # the condition is evaluated first. Written as `len(ran) ==` it silently meant
    # "one fewer than the number a run prints", which is the same off-by-one that put
    # "34" in five documents.
    check(f"all {EXPECTED_CHECKS} cases ran, none of them vanished",
          len(ran) + 1 == EXPECTED_CHECKS)

    print(f"self-test: {len(ran)} check(s), {len(failures)} failure(s)")
    return 1 if failures else 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", help="TSV to append to; resumed if it exists")
    # 0.045 until 2026-08-19, when 0.045 BECAME the shipped bar: `score-text-route`
    # exits 2 on an `INKBAR` equal to it and 2 is in `CONFIG_EXITS`, so the default
    # invocation aborted on document 1. A default that cannot measure anything is
    # worse than no default, and `--help` was advertising it.
    ap.add_argument("--bar", type=float, default=0.08,
                    help="the INKBAR to price against the shipped bar (default 0.08; "
                         "0.045 IS the shipped bar and is refused)")
    ap.add_argument("--corpus", default=os.path.join(REPO, "testdocs"),
                    help="directory of pdfs, walked recursively (read-only)")
    ap.add_argument("--binary", default="/tmp/score-text-route",
                    help="the built score-text-route; see --help for the build line")
    ap.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT,
                    help=f"seconds per document (default {DEFAULT_TIMEOUT})")
    ap.add_argument("--retry-errors", action="store_true",
                    help="re-run documents recorded with an error status")
    ap.add_argument("--dry-run", action="store_true",
                    help="list what would run and stop")
    ap.add_argument("--report", metavar="TSV",
                    help="print counts from an existing TSV and stop")
    ap.add_argument("--self-test", action="store_true",
                    help="check the parser, the printer and resume; sweeps nothing")
    args = ap.parse_args(argv)

    # Before anything that walks a corpus or starts a render. The hook runs this on
    # every commit that stages this file, so it has to be free.
    if args.self_test:
        return self_test()
    if args.report:
        return report(args.report)
    if not args.out:
        ap.error("--out is required (or --report/--self-test)")
    return sweep(args)


if __name__ == "__main__":
    sys.exit(main())
