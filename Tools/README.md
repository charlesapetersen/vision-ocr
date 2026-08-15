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

## What each one measures

| tool | question it answers |
|---|---|
| `score-corpus.swift` | Per document: line-start/line-end selectability, text-layer offset, source line tightness, word retention. One TSV row per document. |
| `score-line-separation.swift` | Do recognised lines survive as *separate* lines in the output? The metric that matches "selecting a paragraph skips a line": `merged=M/N` over adjacent visual-line pairs, plus a `runaway=` character share. Optional `headroomFactor`, `minimumVertical`, `reserveEms` as argv[3-5]. **Carries a self-test that runs on every invocation** (exit 4). Figures from before T14 are not comparable — it used to divide PDFKit lines by Vision fragments. |
| `make-observations.swift` | `<pdf> <out.json> [password]` — the reference JSON the three probes below read. Invariant 3's procedure was not executable without it. A wrapper over `Recogniser.extract` at `textFormat = .json`, so the probes read the same bytes Extract Text ▸ JSON gives a user. |
| `score-gate.swift` | **The release gate.** Every document in a corpus through `OCRModel.start()` end to end, at the app's own concurrency — the check the unit suite cannot do. Run before any release touching `Flattener`, `SearchableWriter` or `JBIG2`; baseline in HANDOFF.md. |
| `score-routing.swift` | Per page: bilevel or greyscale, and KB/page. Catches both a picture routed to 1-bit (content destroyed) and text routed to greyscale (file balloons). |
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
| `pdf-extract-pages.swift` | `<src> <dest> <page…>` — pull pages into a small fixture. |
| `pdf-page-text.swift` | `<pdf> <page>` — that page's embedded text, no OCR. |
| `pdf-info.swift` | Pages, how many carry text, total characters, page box, encryption. |
| `pdf-embedded-text.swift` | Whole-document embedded text. Use to prove OCR happened rather than a text layer being read back. |
| `sample-zotero.py` | Rebuild the test corpus from a Zotero library. **Classifies every candidate and keeps only scans** — item type says what a document is, not how the PDF was made, and without that gate the corpus came out 65% material this app is not for (D1). |
| `classify-source.swift` | scanned / born-digital / photographed, per file, from page-image geometry, text density, saturation and an illumination gradient. The gate `sample-zotero.py` uses, and the same page-image test the app uses before discarding anyone's text (C17). |
| `score-mrc.swift` | What MRC layering would cost per picture page, with the reconstruction's PSNR beside the size. Carries its own Sauvola — see the header. |
| `score-picture-codec.swift` | Codec comparison for the pages that take the picture route. |
| `score-text-route.swift` | Published bytes of a text page **both ways** — layered vs 1-bit — using shipped code for each. The measurement that priced TODO item 1 at 8.2 KB/page. |
| `score-threshold-loss.swift` | How much a page would lose to the 1-bit threshold. **Carries a refused signal** (BUGS.md R56) with a self-test that runs on every invocation; round five of that work starts here. |
| `score-annotations.swift` | Did a reader's marks land where they were? Renders both files and compares each mark's *footprint centroid* — not its coverage, which the header explains. |
| `make-plate-fixtures.swift` | Builds the six synthetic adversarial pages the corpus cannot produce: pale drawing, flat mid-luminance colour, tonal plate, coarse halftone, text-only, red-ink text. R56 and R57 came out of these. |
| `sweep-zotero.py` | The library-wide size survey. **R54 is open against it.** |
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
