# Measurement harnesses

Every number in `BUGS.md` came from one of these. They are standalone Swift
programs compiled against the app's own sources, so they exercise the shipped
code rather than a reimplementation of it — a lesson learned the hard way: a
regression once shipped because the tests covered the pipeline's parts and a
hand-written replica covered the whole, so nothing ever ran the real function.

## Building one

A file with top-level code must be named `main.swift`, so give each its own
directory:

```sh
mkdir -p /tmp/h && cp Tools/score-corpus.swift /tmp/h/main.swift
swiftc -O -o /tmp/score -target "$(uname -m)-apple-macos13.0" \
  $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
```

`$(ls Sources/*.swift | grep -v App.swift)` rather than a hand-kept list, because **the
enumerated version drifted four times and each drift cost someone a debugging session**:
`Recogniser.swift` (R40), `RunReport.swift` and `Updater.swift` (1.10.0), and
`Annotations.swift` (the annotation transplant). `App.swift` is the only exclusion — its
`@main` collides with a tool's top-level code. The paragraph below is kept because the
*failure shape* is worth knowing. **This list drifts**, and the failure is a wall of cascading type errors in a source file
you did not touch rather than a plain "no such symbol": omitting `Recogniser.swift`
reports `cannot find 'Recogniser' in scope` in `Model.swift`, and omitting
`SearchableWriter.swift` — which `Flattener` needs for `SearchableWriter.BoundingBox` —
reports `cannot convert value of type 'Duration' to expected argument type 'Int'`
inside `mrcLayers`. If a compile fails in code you have not edited, suspect a missing
source before the code. Three sources were added since this command was written
(`Recogniser` for R40, `RunReport` and `Updater` for 1.10.0, `Annotations` for the
annotation transplant) and each broke it.

`Sources/App.swift` stays out — its `@main` collides with the tool's top-level code.
The small `pdf-*` utilities need less: `pdf-extract-pages.swift` compiles alone, and
the ones that call `Flattener` need `Sources/SearchableWriter.swift` with it.

## Checking they all still build

```sh
Tools/check-tools-compile.sh              # every tool, about 26 seconds
Tools/check-tools-compile.sh score-mrc    # one, by name — seconds
```

**Nothing asked this question until C25**, and the answer was three times no.
`score-text-route` had never compiled in any commit while three documents cited its
output; then this script found that the annotation transplant had silently broken
`score-skew` and `score-reading-order` on 2026-08-14 by adding a field to a struct
both had transcribed by hand (T16). A tool nobody has run this month is
indistinguishable from a tool that cannot run at all, and the paragraph above about
"a wall of cascading type errors in a file you did not touch" is what that looks
like from the inside.

The pre-commit hook runs it over the *staged* tools only, which is seconds. It
type-checks rather than builds — `swiftc -typecheck` is 7 seconds a tool against 25
for `-O`, and it catches the whole class C25 and T16 were in. It does not catch a
link failure, so a tool that has just grown a dependency still wants one real build.

The Python and shell checks are **syntax only**: `py_compile` passes a body of
`return no_such_function(1)`, and `bash -n` passes a command that does not exist. They
are worth having and they are not a substitute for running the thing. Three defects in
the checker's own first version are recorded in T16, including one that would have
refused the commit that introduced it.

## What each one measures

| tool | question it answers |
|---|---|
| `score-corpus.swift` | Per document: line-start/line-end selectability, text-layer offset, source line tightness, word retention. One TSV row per document. |
| `score-line-separation.swift` | Do recognised lines survive as *separate* lines in the output? The metric that matches "selecting a paragraph skips a line": `merged=M/N` over adjacent visual-line pairs, plus a `runaway=` character share. **`welded=W/N` is property (d)** — adjacent fragments of ONE row arriving with nothing between them, `femalemember` — added for R82, because nothing here could count a weld and so every column read identical across a change that fixed seventeen of them. It groups rows at `.taller` for that column and `.shorter` for the others, deliberately: see the header. Optional `headroomFactor`, `minimumVertical`, `reserveEms` as argv[3-5]. **Carries a self-test that runs on every invocation** (exit 4). Figures from before T14 are not comparable — it used to divide PDFKit lines by Vision fragments. |
| `score-run-width.swift` | How much of its own box does each run actually cover, and how much of the height it wanted did the ceiling leave it? The two halves of the fight invariant 3 is about, counted over every fragment on the sampled pages. Built for `BUGS.md` R81, which the three probes below are **structurally unable to see**: over a run drawn at 5% of its box, their right-hand-15% rectangle sits on the line above, which does reach it, so the page scores clean. Asks the writer directly — `SearchableWriter.prepared`, `rightLimit`, `headroom`, `placement` — rather than re-deriving any of it. `crushed` is C20's symptom, both directions lost at once. **Carries a self-test that runs on every invocation** (exit 4), including a direction proof that does not go through `rightLimit`, so it keeps its ability to see a sliver on the day one is fixed. Measures the **direct** route and the header says so. |
| `make-observations.swift` | `<pdf> <out.json> [password]` — the reference JSON the three probes below read. Invariant 3's procedure was not executable without it. A wrapper over `Recogniser.extract` at `textFormat = .json`, so the probes read the same bytes Extract Text ▸ JSON gives a user. |
| `score-gate.swift` | **The release gate.** Every document in a corpus through `OCRModel.start()` end to end, at the app's own concurrency — the check the unit suite cannot do. Run before any release touching `Flattener`, `SearchableWriter` or `JBIG2`; baseline in HANDOFF.md. |
| `score-routing.swift` | Per page: bilevel or greyscale, and KB/page. Catches both a picture routed to 1-bit (content destroyed) and text routed to greyscale (file balloons). Samples four pages a document — for an acceptance run use the census below, which is the same question asked of every page. |
| `score-routing-census.swift` | **Every** page of a corpus, one row each: the route, and the shape statistics behind it. The acceptance instrument for a routing change — a before/after diff *names the pages that moved*, which is the only question worth asking of a detector refused four times for moving the wrong ones (R56, R57). Reads each page from the document it is in, never from an extract, so C24 cannot reach it. Computes nothing itself: every column is a call into `Flattener`. **Carries a self-test that runs on every invocation** (exit 4) over the labelling's awkward cases — a U, a diagonal, a comb joined at its base — and over both masks. `JOBS=n`, `PAGES=n`. 16,987 pages in about 40 minutes at `JOBS=6`. |
| `picture-signals.swift` | The three routing signals — ink coverage, continuous tone, colour saturation — plus the Otsu threshold, per page. Use when routing looks wrong. |
| `probe-line-coverage.swift` | Is the right-hand end of each line selectable, over the whole document? Catches a text layer narrower than the ink. **Third shell on one rect** — see the note below. Not affected by the page bug the other two had: it iterates `pages` correctly. |
| `probe-line-edges.swift` | `<pdf> <page> <obs.json>` — both ends of every line on one page, and **names** the ones that fail. That naming is the only reason to keep it. |
| `probe-text-offset.swift` | `<pdf> <page> <obs.json>` — slides a probe out from zero to find where each line's text actually sits. 0.00 = on the ink. Catches the drift class of bug. |

**`score-corpus`, `probe-line-edges` and `probe-line-coverage` build the same
probe rect** — `w * 0.15` at the line's own left and right edges — in three
places, and it is one idea, not three instruments. `score-corpus` is the one to
quote; the other two exist to say *which* lines failed and to sweep a whole
document. Do not report them as independent corroboration of each other, which is
what "four invariant-3 instruments" invited.

**`score-run-width` is not a fourth shell on that rect, and the difference is the
point.** The rect asks "is *anything* selectable at the end of this line", which a
neighbouring line's run can answer for it; `score-run-width` asks the writer how
wide it drew *this* run and how far the ceiling squashed it. That is why R81 —
62 of 852 shortened runs drawn under half their box on 24 newspaper pages, the
worst at 2.84% — sat under a clean score for as long as it did. Quote it for
property (c) alongside `score-corpus`, not
instead of it: one measures what the writer intends, the other what a reader can
select, and R81 is exactly a case where those two disagreed.
| `pdf-extract-pages.swift` | `<src> <dest> <page…>` — pull pages into a small fixture. |
| `pdf-page-text.swift` | `<pdf> <page>` — that page's embedded text, no OCR. |
| `pdf-info.swift` | Pages, how many carry text, total characters, page box, encryption. |
| `pdf-embedded-text.swift` | Whole-document embedded text. Use to prove OCR happened rather than a text layer being read back. |
| `sample-zotero.py` | Rebuild the test corpus from a Zotero library. **Classifies every candidate and keeps only scans** — item type says what a document is, not how the PDF was made, and without that gate the corpus came out 65% material this app is not for (D1). Owns the classifier's **build and its output parser**, both imported by `sweep-zotero.py`: `FIELDS` is the column layout in one place, and `path` is the last field because A12.4 added two columns and moved it. `--self-test` checks the parser and the batch runner against a fake classifier, and the pre-commit hook runs it. |
| `score-illumination.swift` | Is a document's illumination gradient *consistent* across its pages? Built for `BUGS.md` R55, which proposed the discriminator and could not test it: a rig repeats and hands do not. Per document it takes `classify-source`'s own five-page sample, normalises each page's nine block means by that page's brightest block so exposure drops out, and reports the spread of the remaining *shape*. **Measured over 204 corpus scans and 123 survey files:** no mechanical scan exceeds 0.0373, so this rules a flatbed out — and it does not rule hand-held in, because the gradient it builds on averages pixels above 140, which on a nearly black page are content rather than paper. Use `xargs -0`; BSD xargs has no `-d`, and the first run of this printed a header and measured nothing. |
| `classify-source.swift` | scanned / born-digital / photographed / textual / no-page-image, per file, from page-image geometry, text density, saturation and an illumination gradient. The gate `sample-zotero.py` uses. It **calls** `Flattener.pageIsAnImage` per page and `Flattener.hasDigitalText` per document now — it used to link them and compute its own answer from two cross-page aggregates, and the gate whose only purpose is D1 admitted the two documents the app calls born-digital (T17). Eleven columns, `path` last, every row through one printer. `CORPUS-2026-08-15.tsv` is a whole-corpus run of it. |
| `score-mrc.swift` | What MRC layering costs per picture page, with the reconstruction's PSNR beside the size, and which of the two the app would publish. **Calls `Flattener.mrcLayers` and reads the three files it wrote** — it used to mirror it, and the copy had drifted five ways, *not all in the same direction* (T15). **Carries a self-test that runs on every invocation** (exit 4) over two fixtures, one for each half of R50's rule and one of them colour. Refuses to run without `jbig2` **or `qpdf`** (exit 3), because the app only layers on the JBIG2 route. `MRC_BLIND=1` is the one layering still written here, and it exists because it is *not* what the app does — it differs in three ways, so only its `maskKB` column compares like for like. |
| `score-picture-codec.swift` | Codec comparison for the pages that take the picture route. |
| `score-text-route.swift` | Published bytes of a text page **both ways** — layered vs 1-bit — using shipped code for each. Cited as pricing TODO item 1 at 8.2 KB/page, which C25 records is not reproducible from any committed version of the file. Its default page sample used to be `[1, 1, 1]` on a five-page document — **page 1 three times** — and two of its four row printers were the wrong width; one `row()` over `Flattener.sampleIndices` now (T18). **Its `verdict` column mirrored only the first of `pageIsAllText()`'s two terms until 2026-08-18** — a replica of a shipped guard missing a clause, so it read `all-text` over exactly the pages R56's second term exists to protect. Both terms now; measured, no verdict on `1954 - Why.pdf` moves, because `extent` is 0.00000 there (C26) — but `allText` also gates this tool's aggregate lines, so over a corpus the two `extent > 0.05` pages in `THRESHOLD-LOSS-2026-08-18.tsv` will leave that aggregate, and that is unmeasured. Like `score-mrc.swift`, it runs Vision and can therefore print the guard's **first** term, `inkOutsideText`, which `score-threshold-loss` cannot. **It also PRICES a different bar on that term** (2026-08-18, C26 sub-step 3): `INKBAR=0.045` publishes every page twice through `Flattener.textPageInkOutsideThresholdOverride` and prints `extent`, `barVerdict`, `layeredAtBar` and `barDelta`, plus a summary saying how many pages changed verdict and what it cost. The override substitutes the guard's *comparand*, not its verdict, so `keepEveryPixel` and R56's pale term keep participating — a forced verdict would price a page refused by the second term as though the first had moved it. It refuses an `INKBAR` outside `(0,1)` or equal to the shipped bar rather than printing `same` on every row, and it reuses the shipped run's JBIG2 stencil for the second measurement because the stencil reads no downsample factor — checked per page, and a row whose stencil moves says `STENCIL-MOVED` and pays for a real encode. Measured on `1954 - Why.pdf` p4/p6/p7: 65,477 B -> 195,785 B, **2.99x**, at 10 s for 2 pages against 8 s unpriced. |
| `sweep-ink-bar.py` | The corpus **driver loop** for `score-text-route`, written for C26 sub-step 3b. It exists because of a measured trap: that tool takes ONE pdf and reads every later argument as a page number, so a glob measures document 1, drops 232 paths with no message and prints a summary that reads exactly like a corpus run. **Resumable by construction** — a document's rows are buffered and appended only when its run finishes, so "has a row" means "is done", and every document gets at least one row (`status` says which) because a document that produced none would be retried on every resume for ever. **It distinguishes the environment from the document**: the tool's exits 2 (bad `INKBAR`) and 3 (no `jbig2`) and a drifted header abort, because recording them would build a complete-looking TSV of 233 identical failures; exit 1 is this file's own problem and is recorded. **It checks the tool's 13-column header on every document** rather than splitting on tabs and hoping — T14, A12.3 and T18 are three field-count defects, and a renamed column is refused as well as an extra one. `--report` prints counts only, over `verdict` against `barVerdict`: `barVerdict` alone reads `picture` on all five priced pages of `1954 - Why.pdf` including the two the bar does not move, so counting it would report five where three is the answer. It does **not** take `test-lock.sh` — a 3-4 hour hold would block every commit hook, and the lock is about two `tests` binaries sharing one plist keyed by process name, which this is not. `--self-test` is 71 checks against stub binaries and the control run's own ten rows; the hook runs it. **The lock is a sidecar `<out>.lock` taken before anything reads or writes `--out`** — it used to be taken after the torn-row trim and after `--retry-errors`' `os.replace`, so a second launch onto a live sweep mutated the file and refused afterwards, leaving the running sweep appending to an unlinked inode while the TSV a poller reads stopped growing; `--dry-run` reads only for the same reason. |
| `score-threshold-loss.swift` | How much a page would lose to the 1-bit threshold. **Carries the four luminance signals R56 refused** in its `lost` column, with a self-test that runs on every invocation. R56 is now `FIXED` by a shape signal instead, so `lost` is history rather than a starting point — keep it for the four rounds' worth of reasons a luminance rule cannot work, and read `score-routing-census.swift` for what replaced it. **It also prints the SHIPPED signal now** (2026-08-18, C26): `extent` and `cover` from `Flattener.paleDrawing(pageMarks(…))`, which is what `paleDrawingThreshold` is actually compared against, plus `cells` and `factor` so `extent`'s integer numerator is recoverable. C26 had quoted `lost` as the number under that 5% bar; they are two different functions, and the real `extent` is **0.00000** on the two pages that lose their drawing. It cannot print `pageIsAllText()`'s verdict — that guard's first term needs Vision's text boxes and nothing here runs OCR; **`score-text-route.swift` is the tool that can**, and C26's answer came from the pair. **`--dump <dir>` writes the marks grid as an image** (2026-08-18, C26 sub-step 2) — black ink, red pale kept, blue the pale band property 2 dropped for touching ink — beside seven columns asking the same question in numbers: `paleC`, `besideInk`, `paleTall`, `inkTall`, `unionTall`, `bandOnly`, `bandTall`. Read `bandOnly` for the pale band's own tallest component — `bandTall` includes `ink`, so it is bounded below by `inkTall` and cannot attribute height to the band on its own; the review of the commit that added it caught that, and `bandOnly` is what it added. That is how C26's drawings were shown to be **ink** rather than pale marks. The blue class and `bandTall` are the tool's own arithmetic over `paperLimit`, which is production's `limit` floored, so they can differ by one grey level; `besideInk` is `Marks.paleBesideInk`, counted inside `pageMarks`, and is exact. Exits **3** rather than 0 if it measured no pages, which is how the same silent-success defect `score-corpus` had reached this tool. |
| `score-annotations.swift` | Did a reader's marks land where they were? Renders both files and compares each mark's *footprint centroid* — not its coverage, which the header explains. Its `could not render` row printed six fields under a seven-column header, so a failure's verdict landed in the `drift` column (T18). |
| `make-plate-fixtures.swift` | Builds the **eight** synthetic adversarial pages the corpus cannot produce: pale drawing, pale chart, faint marks, flat mid-luminance colour, tonal plate, coarse halftone, text-only, red-ink text. R56 and R57 came out of these and are closed by them. `run_tests.sh` builds this tool and hands the suite its path, so the fixtures the acceptance checks route are the ones defined here rather than a copy that drifts. **`pale-chart` is the one that can see `maximumInkUnderADrawing`** — `pale-drawing` sits on bare paper and reads the same at every value of it, including zero. **All eight are one page, 8.5x11, `/Rotate 0`**, so they are evidence about routing and blind to invariant 5's class — its header says so (A12.8). |
| `sweep-zotero.py` | The library-wide size survey. **R54 is `FIXED`**: a type's median is used only with `MINIMUM_SCANS_FOR_MEDIAN` scans behind it — measured, because at 5 files a median is off by up to 275% while the outlier test is 3.0x — and everything below the line is compared to the library-wide median with `basis=library` on the row and marked `review`, not `candidate`. `--self-test` drives `judge()` with no library and no classifier. |
| `check-tools-compile.sh` | Does every tool in here still build? Type-checks each Swift tool, `py_compile`s each Python one and `bash -n`s each shell one — including itself, which is how its own first version's bash-3.2 crash would have been caught, **and including `.githooks/pre-commit`**, which was the one shell script nothing checked while being the only one whose failure refuses every commit. The gate C25 and T16 needed and did not have. |
| `vm-gui-check.sh` | The interface checks that need a running app — U13, U15, U17 — in a headless VM. Exit 0 pass / 1 fail / 3 could-not-run. |
| `probe-window-reopen.swift` | Can the window be got back after it is closed mid-run? Exit 0 = yes. The one thing in this project that could not be settled by reading. **Does not compile against `Sources/`** — it is a standalone app, and its restore body is a copy of `AppDelegate.showMainWindow` that has to be kept in step. |

## Running the app for real, off-screen

```sh
Tools/vm-gui-check.sh            # or: windows | reopen | settings
```

Some interface properties cannot be settled by reading or by `run_tests.sh`:
whether the window comes back after being closed mid-run (U13), whether Settings
fits a short display (U15), and whether one window stays one window when Finder
hands the app three files (U17). All three were live bugs at some point and all
three were found by hand. The script is that by-hand pass, written down: it boots
a headless [Tart](https://github.com/cirruslabs/tart) macOS VM — its own virtual
display, so nothing appears on your screen — builds the current sources in it,
drives the app over VNC, and exits 0 / 1 / 3 for pass / fail / could-not-run.

Nine checks, about four minutes. It stops the VM on the way out, including on
failure. What it does *not* cover is the keyboard tab order, which needs
`AppleKeyboardUIMode` and reads focus rings out of pixel diffs — that one is
still done by hand, below.

The steps, if you are doing it manually or extending the script:

```sh
# 1. boot headless, with a VNC framebuffer and no host window. The two flags
#    compose: --vnc-experimental alone makes tart open Screen Sharing.app.
tart run archive-gui-runner --no-graphics --vnc-experimental >runlog 2>&1 &
grep -o 'vnc://[^ ]*' runlog          # vnc://:PASS@127.0.0.1:PORT
until tart exec archive-gui-runner true; do sleep 5; done   # the guest agent
                                       # comes up AFTER the IP; do not skip this

# 2. push the sources over the guest agent — NOT through a --dir mount
tar czf - Sources Resources build.sh | base64 | split -b 60000 - part-
for f in part-*; do tart exec -i archive-gui-runner \
  bash -lc 'cat >> ~/xfer/s.b64' < "$f"; done

# 3. build and drive
tart exec archive-gui-runner bash -lc 'cd ~/vrg && ./build.sh'
vncdotool -s 127.0.0.1::PORT -p PASS capture shot.png   # ~/.tart-mirror/vncenv
vncdotool -s 127.0.0.1::PORT -p PASS move X Y click 1   # input bypasses guest TCC
```

Requires nothing installed in the guest — recognition is Vision, in process —
except `defaults write -g AppleKeyboardUIMode -int 3` for the tab walk.

**Read state with `CGWindowListCopyWindowInfo`, filtered by pid, not with
screenshots.** VNC hands back stale frames — a capture taken four seconds after a
click showed the window in a state fifteen seconds old, which read as the fix not
working. Screenshots are for looking at layout; the window list is for deciding
whether something happened.

**Three instruments lied during that pass**, all recorded in BUGS.md under
"Verified on a running app": a window probe filtering on `kCGWindowOwnerName`
(the bundle name is `Vision Reader GUI`, spaces and all, so it reported zero
windows while the app had four); a virtiofs mount serving a 90-minute-old
`App.swift`, so the build under test was not the code under test; and a TCC
prompt on the VM's screen silently eating every keystroke, which produced a
clean, entirely fictitious tab-order result.

## Measuring layout: skew and reading order

Both of these were written to decide a feature, and both decided against it. They
are kept because the instruments are validated and the next person to have the
idea should start from a working one.

**`score-skew.swift`** — how crooked a page is, from its own text lines. Carries
the estimator itself, deliberately: the app does not deskew, so putting it in
`Sources/` would ship dead code. Three modes, and the first is the one that
matters.

- `--validate` plants angles **in the pixels**, re-measures, and reports the
  error. Not in its own point cloud — a self-test that reuses the search it is
  testing flatters itself. It found the sign inverted on the first run, with the
  magnitude right, which would have doubled every page's skew. The 0.0° control
  passed throughout: zero has no sign.
- `--summary` sweeps a corpus and prints the distribution, counting the pages it
  **abstained** on rather than dropping them.
- `--recover` / `--recover-render` recognise each page before and after
  correcting it, and count characters. Use `--recover-render`: it folds the
  rotation into the render so each side is sampled from the vector source exactly
  once. `--recover` rotates the finished bitmap, which samples "after" twice and
  charges the difference to deskew — it reported −1.33% where the fair
  comparison reported +0.26% on the same interim rows.

**`score-reading-order.swift`** — whether Vision's order is wrong on
multi-column pages. Two modes, and they exist because the obvious one has a hole.

- default: column bands from the observations' own x-coverage, then *switches*
  (consecutive observations landing in different bands) and *interleaving*
  (switches ÷ column breaks; 1.0 is perfect).
- `--gutter`: bands from the **ink** instead. This is the mode to trust. If
  Vision welds lines across a gutter, the observations span both columns, the
  default mode sees no gap, and files the page as single-column — excluding the
  one defect worth finding by the act of looking for it.

Neither metric can tell a table from prose, and the corpus pages that score worst
are a four-column table and a table of contents, both read *correctly*. Render the
worst pages and look at them before believing a score.

## Two traps in this environment

**Backgrounded shell commands run with essentially no `PATH`.** `basename`, `cut`
and `timeout` all silently fail, so a loop reports bogus failures for every row.
Use absolute paths, or export `PATH` inside the command.

**`nohup … &` inside a backgrounded command reports success immediately** while the
real work continues orphaned. Wait on the process, don't trust the exit code.
