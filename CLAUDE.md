# Working in this repo

Vision OCR — macOS SwiftUI app that OCRs scanned PDFs through Apple's Vision
framework and writes its own searchable-PDF text layer. Recognition runs in a
helper process this repo builds (`Helper/main.swift` → `visionocr-recognise`),
compiling `Sources/Recogniser.swift` so the app and the helper cannot diverge —
BUGS.md R40 is why. `jbig2` and `qpdf` are the only other programs it runs.

**Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing anything** — branch,
failing test first, adversarial review of your own diff, and a pre-commit hook
that refuses a commit whose tests do not pass. It exists because this project has
repeatedly shipped regressions *inside fixes for other bugs*.

Then: [HANDOFF.md](HANDOFF.md) for the design rationale and the mistakes already
paid for, and [ARCHITECTURE.md](ARCHITECTURE.md) for the call path, the two page
boxes, and what the tests don't cover.

Planning lives in four files. [BUGS.md](BUGS.md) is the defect register — **two entries are open as
of 2026-08-18, `C26` and `C27`, both found on one document after `1.13.0` shipped. `C26` loses
content at the DEFAULT Photo detail setting; `C27` discards spot colour and is fidelity rather
than loss.** A small line
drawing is erased on the picture path because `pageIsAllText()` shrinks the tone layers 8x and 16x
and the pale-drawing guard in front of that does not fire;
three of four drawings
in a 10-page booklet went, every word survived, and `1.13.0` shipped it hours earlier having been
cut against an empty register. **This sentence said the guard "needs 5% of the page to fire" and
C26 said those marks cover 0.2% — measured 2026-08-18, that 0.2% was a different function's
column, and the quantity the 5% bar actually reads is `0.00000` on the two pages that lose the
most.** So the guard finds no drawing-shaped mark at all there, and lowering `paleDrawingThreshold`
to any value protects neither page. **And measured 2026-08-18, `paleDrawing` was never the term to
look at: the drawings are INK** — 5,495 / 4,188 / 3,379 cells below their page's own Otsu, against
8 / 350 / 0 pale cells the guard is offered — so they are cut out of the stencil by
`textRegionMask` (correctly; they are not text), left in the background, and the background is
what gets stored at 1/8. The term that decides those pages is `pageIsAllText()`'s **first** one:
`inkOutsideText` reads **0.0493–0.0660 against a bar of 0.08**, so it sees them and lets them
through, and unlike the pale term it *can* reach them. Whether to move that bar is unmeasured and
is a corpus question — read the entry's last section before touching it. **The corpus
sweep both entries were blocked on ran the same day** — 441 pages, 233 documents,
`THRESHOLD-LOSS-2026-08-18.tsv` — and it sizes the `extent` bar's population (61 picture-route
pages: 2 protected, 22 under the bar, 37 at zero, and the cluster under the bar is led by the
show-through document R56 was refused four times for), **which the next day's measurement showed
is not C26's population** — C26 turns on `inkOutsideText`, and no sweep of that has run — while
**not** sizing C27, because a mean saturation cannot see concentrated
colour and C27's own measurement was a saturated-pixel fraction no tool here prints. Both entries
carry the numbers, the retractions and what is left. It is **not** R56 — that fix is intact and
works on the other
route. **`Tools/score-gate.swift` cannot see this class**, by its own source, so do not read a
green gate as covering it. **C24 is `FIXED`**, both halves. A page that draws no
XObject at all no longer takes another page's plate resolution (85 pages over 3 documents,
structural, no threshold, 0 route changes), and **the 45 pages that draw a *different*
image than the shared dictionary holds were closed the same day** — `rebuildDPI(of:)` applies
the shipped policy to `drawnLargestImage`, the corpus gate ran, and **exactly 45 pages of
16,987 change resolution**, page-for-page the 45 the earlier sweep named. Retention against
those pages' own embedded text is **+8 words of 3,025** over the 7 that have one; bytes fall
**25% / 81% / 3%** by document. Three things in that commit are worth knowing before you
touch this area. (a) **The gate's own instrument had to be repaired first**:
`score-drawn-images`'s `shippedRebuildDPI` column compared production against the drawn walk,
so once production *became* the drawn walk it would have read `same` on all 16,987 rows — a
tool measuring itself, §3 in a tool rather than in the shell. (b) **`score-routing` was
refusing rows for three documents, not the two this register kept saying**, and its "drift"
diagnostics were the *correct* per-page resolutions all along — it was refusing its own right
answers because production held a wrong one. (c) **One row is named as an unsettled
surprise**: `Sherman_1986` p1 moves 219 → 182 recognised words on a **0.38%** resolution
change, non-monotone (the 300 fallback reads 224, above both), with only 14 words of embedded
text so nothing can grade it. **`pageIsAnImage` was deliberately not wired** — 2 pages would
flip, and it feeds D1's corpus gate, which is R55's territory. **What led up to that close
is measured as of 2026-08-17** — read the entry's `C24b` and `C24's wiring` sections before
planning anything there: `Flattener.drawnLargestImage` and `Tools/score-drawn-images.swift` report
what a page actually draws, the 45 are **39 smaller and 6 wider** (which retires the
observation the entry carried without a cause — both walks pick by *area* and report
*width*), and the constant the entry wanted recalibrated faces **three** pages. **It gets all
three right, measured 2026-08-17, so the blocker is retired**: `Tools/score-rebuild-dpi.swift`
rendered `Batzell` p22 both ways and it retains **92.8%** of its own 291 words at 70.6 DPI
against **94.2%** at the 369.6 it accidentally gets today, for **87% fewer bytes** — so
"rendering a page of type at 70 DPI is C9 again" was reasoned and is **false**, corrected in
the four places it was published. Note too that *counting characters*, which the entry asked
for, reads **1,960–1,962 across every resolution from 70.6 to 369.6** — a 0.1% spread against
word retention's 1.4 points — so it would have said "no difference" while being right by
accident; word retention against the page's own embedded text is what moves. (This sentence
said a flat "1,961 at every resolution" until 2026-08-17; three of those six rows are 1,960 or
1,962, and `BUGS.md` had it right while the two summaries flattened it.)
**The override seam is mutation-tested as of 2026-08-17, and it found an ELEVENTH check that could
not fail** — read `BUGS.md`'s `### The override seam, mutated` before trusting that block. Both
mutants are killed, but the column that matters is *how many checks object*:
`logic/C24-override-nil-means-fallback` — `nil` from the closure read as "use the fallback"
rather than "no opinion about this page" — is killed by **exactly one** check, and that check did
not exist in `c8855f6`. Against the nine checks that commit shipped the count was **zero**, so the
nearer wrong reading would have survived while the register recorded the seam as pinned. The
fixture is why: the only page it declines is the one whose shipped answer already *is* the
fallback, so every row agreed with the wrong implementation by accident.
That was the last thing standing before the wiring, and the wiring closed the entry the same
day; its `C24's wiring` section is the gate run and the close. Read that
section's review subsection too — it found **a
tenth check that could not fail** and a bare form resolving its resource names in the page's
scope rather than its invoker's, and it is where to look before believing that
`CGPDFContentStreamGetResource` searches the parent chain: measured, it does not, after a
comment in this repo said it did. **The mutant campaign is done as of 2026-08-17 — all five
killed**, so none of those five checks is one that cannot fail; its `### The campaign`
subsection also records that `mutate.py`'s startup estimate was **4.85x** low (267 min
announced as 20-55; four documents rounded that to "4x", "five", "four" and "a factor of
four" before anyone divided it), that a mutation run's cost tracks **machine contention rather
than the suite's size**, and that two of `mutation-log.tsv`'s cheapest rows are `exit 133`
crashes rather than fast suites. **The estimate now reads the log and has a `--self-test`,
and it is still 4.22x low out of sample** — the campaign section's own "negative control"
was in-sample and is relabelled; read that before quoting the startup line as a forecast.
Its self-test's coverage figure is **21 of 26 mutations killed, measured** and re-derivable
from `SELFTEST-MUTANTS-2026-08-17.tsv`; it read "12 of 14" from reasoning for a few hours,
and one of the twelve it missed was another check unable to fail — and the review of the
fix caught a second, where `run` did not act on the guard the checks pinned. **R55 is `WONTFIX`** as of 2026-08-17: the measurement campaign was run and the
owner closed it on the arithmetic — the gate's over-exclusion costs the sweep about 80
candidates and 0.7 GB against 1,164 and ~10 GB, and loosening it would admit the hand-held
photographs D1 exists to keep out. **R56 and R57 —
the pale drawing erased and the tonal plate blobbed — are `FIXED` as of 2026-08-16** by a
shape signal in `Flattener`, on the sixth attempt and the second signal class; read both
entries before touching the routing, because four luminance rounds and two shape rounds
were refused before the one that worked, and the term that closed R56 is not a threshold
on how pale a mark is but on **where it is**. **C23 — the rebuilt copy displaying what the original's crop box
hid — is `FIXED`, and there is no release blocker.** Read its entry before touching the crop
box anywhere: the fix the entry itself proposed is wrong in two measured ways, the first fix
this project shipped for it gave up JBIG2 compression it did not have to, and the crop box now
goes on **after** the qpdf merge — where `--update-from-json` replaces a page object rather than
merging into one, which turned a 7,391-byte page into 391 bytes with `qpdf --check` calling it
healthy.
Read its header before planning anything. Update it in the same commit as any fix.
Dated measurement records live beside them — `CORPUS-2026-08-08.md`, `CORPUS-2026-08-09.md`,
`CORPUS-2026-08-15.md` + `.tsv` and `MRC-2026-08-15/` — and are evidence for one run, not
claims about the present. **The corpus is 230 scans, not 233**: `CORPUS-2026-08-15.md` is
the gate re-run after T17, and it names the two documents the app itself calls
born-digital.
[TODO.md](TODO.md) is decided-but-undone work, [FEATURES.md](FEATURES.md) is ideas
with their costs and the reasons some are parked,
[RESEARCH-2026-08-16.md](RESEARCH-2026-08-16.md) is what other tools do about the
problems this register keeps re-deriving — the extractor thresholds that bound
`reserveEms`, Tesseract's two-knob text layer, and the qpdf option C23 was refused
without reading —
[RESEARCH-shape-signals.md](RESEARCH-shape-signals.md) is the same question asked of
MRC segmentation, and it is the file that corrected the picture detector's analysis
resolution by 4x and established that **nobody separates a pale drawing from
show-through**, and
[REVIEW-2026-08-14.md](REVIEW-2026-08-14.md) is the standing record of a
whole-codebase review sweep, including findings not yet fixed and areas not yet
covered. **[HANDOFF-2026-08-17.md](HANDOFF-2026-08-17.md) is where to start** — it was written
when R56 and R57 had just closed and named `R55` and `C24` as what was left; `R55` is
`WONTFIX` and `C24` is `FIXED`, both on 2026-08-17, so the register is empty — then
[HANDOFF-2026-08-16.md](HANDOFF-2026-08-16.md), then
[HANDOFF-2026-08-15-night.md](HANDOFF-2026-08-15-night.md), then
[HANDOFF-2026-08-15-evening.md](HANDOFF-2026-08-15-evening.md), then
[HANDOFF-2026-08-15-day.md](HANDOFF-2026-08-15-day.md), which has the corrections this
project's own review document got wrong. ⛔ Its process note *"Work serially. Do not fan out
to subagents"* is **WITHDRAWN as of 2026-08-16.** Subagents are wanted: `Task`, `Agent` and
`Workflow` are all permitted, and an adversarial review agent over a finished diff before
committing is expected rather than optional. Ignore that paragraph wherever you meet it — in
that hand-off or any older one. The only remaining limit is the session's own budget, and
that every subagent must be told **not to run the suite**. Then
[HANDOFF-2026-08-15.md](HANDOFF-2026-08-15.md) for the twenty-three fixes that landed
overnight, and [HANDOFF-2026-08-14.md](HANDOFF-2026-08-14.md) for the original fix order
and what is deliberately withheld from release.

*(This paragraph read "nothing open" for a day after four entries were opened, which
is exactly the sentence a new reader trusts most. If you close or open an entry,
correct it here in the same commit — it is the only way this line has ever stayed true.)*

Install the hook once per clone:

```sh
git config core.hooksPath .githooks
```

## Commands

```sh
./build.sh            # build -> build/VisionOCR.app
./build.sh --install  # + install to /Applications
./run_tests.sh        # 1,163 checks at b11c236; 8-45 min depending on machine load, real OCR
                      # measured 474 s quiet -> 2,719 s under the C24b campaign. Never size a
                      # timeout off one sample: ops/autonomous/README.md keeps the ledger.
```

Never report a change as working without `./run_tests.sh` passing. Add a test that
fails without the fix.

## Invariants — breaking these has destroyed user content before

1. **Never lose content silently.** Every path that can drop a page, a line or a
   text layer must report it. Page count is not sufficient verification; a
   truncated-but-valid PDF opens fine. Prefer failing loudly over publishing
   something plausible.
2. **Build into scratch, publish only on success.** `makeSearchablePDF` stages
   output and moves it into place after verifying the page count. Never write
   directly to the user's destination — a cancel mid-write once overwrote a good
   file with a truncated one.
3. **The text layer must satisfy four properties at once**: word spacing survives
   extraction, runs don't overlap vertically, runs span the ink, and **runs keep
   a gap from the next fragment on their own line**. Each has been broken by a
   fix to another. Re-measure all of them after any change to `SearchableWriter`.
   The instruments were repaired in `BUGS.md` T14 — before that, **all four were
   compromised and the procedure would not run**. The procedure:

   ```sh
   Tools/make-observations <finished.pdf> obs.json   # produce the reference
   Tools/probe-line-edges  <finished.pdf> <page> obs.json
   Tools/probe-text-offset <finished.pdf> <page> obs.json
   Tools/score-corpus      <source.pdf> <label> [headroomFactor] [minimumVertical] [reserveEms]
   Tools/score-line-separation <source.pdf> <label> [same three]
   Tools/score-run-width   <source.pdf> <label> [--worst N] [--pages N]
   ```

   **There are three shells on one rect, and two instruments beside them.**
   `probe-line-edges` builds the same rect as `score-corpus`'s `start=`/`end=`
   columns, character for character, and agrees with them on 48 of 48 documents;
   it is kept because it *names* the lines that fail, and `score-corpus` only
   counts them. `probe-line-coverage` is a third shell on that same rect.
   Counting them as independent is how "four instruments" became a sentence
   nobody could act on.

   `score-line-separation` and `score-run-width` are the two that ask different
   questions. **`score-run-width` was added for R81** and is the only one that can
   see it: the rect asks whether *anything* is selectable at a line's right-hand
   end, and over a run drawn at 5% of its box the answer comes from the line
   above. It asks the writer instead — how wide it drew this run, and how much of
   the height it wanted the ceiling left it — over every fragment on the page.

   What each one is for, and what it used to get wrong:

   - `score-line-separation` — properties (a) and (b). Reports `merged=M/N`
     over adjacent visual-line pairs and a `runaway=` character share. It used to
     divide PDFKit *lines* by Vision *fragments*, which is not a percentage of
     anything: it read 35%–2533%, read **87% → 87%** across a change from no
     runaway line to a 2,139-character one, and read an identical 52% at two
     different `headroomFactor`s. Every figure it produced before T14 is void,
     including `HANDOFF.md`'s "modern print keeps 100%, 1920s-50s 87-93%".
   - `score-corpus` — properties (c) and (d) plus word retention. Its `words=`
     column always held. Its `off=` column did not: see the next bullet, and note
     that it now prints `SKIP` at exit 1 rather than `OK` over a document it
     measured nothing on.
   - `probe-text-offset` — where the runs sit relative to their boxes. It scanned
     upward from −1.2 and took the first hit, so it accepted the *lowest* step
     whose window still clipped the line's own glyphs. **This moved the median,
     not only the range as A6.1 recorded** — −0.10 → 0.00 on dense newsprint once
     the scan runs outward from zero. Every `off=` figure recorded before T14
     belongs to the old instrument.
   - `probe-line-edges` — the per-page drill-down that names failing lines. It
     read `pages[0].observations` whatever page it was given, so on page 2 of a
     real document it printed `line starts: 0/32` — a false *failure* — over a
     page holding five perfectly good lines.

   The fourth was found late and had been holding **by accident**. Vision splits
   one visual line into fragments side by side; nothing writes a space character
   between them, so PDFKit synthesises one from the geometric gap and stops
   below ~0.15 em. That gap existed only as slack left over from
   `minimumVertical` capping the font size — a constant chosen for something
   else. Widening runs to fix property three closed it, and words welded:
   `valuablestudy`. `reserveEms` now holds it open deliberately. Assume there is
   a fifth.
4. **`kCGPDFContextMediaBox` takes CFData, not NSValue.** An NSValue is silently
   ignored and every page inherits page 1's size.
5. **Test fixtures need ≥2 pages of differing size**, and at least one rotated
   page. Single-page fixtures are structurally blind to geometry bugs.

## Environment traps

- **Never run two suites at once, in any two worktrees.** `build/tests` has no
  bundle identifier, so `UserDefaults.standard` lands in a domain keyed by the
  process *name* — `~/Library/Preferences/tests.plist` — and **every worktree
  shares that one file**. A second suite's `resetPrefs()` removes every key and
  wipes the first one's settings mid-run. Measured: 882/883 → 877/879, two
  failures in the run-report block, because the other run cleared
  `writeRunReport` between this one setting it and the batch finishing.
  `Tools/mutate.py` says to stay sequential and blames *timing*; the real hazard
  is shared preferences, and it fails checks for reasons unrelated to load. This
  includes suites started by review agents you launched.
- **Backgrounded shell commands have essentially no `PATH`** — `basename`, `cut`,
  `timeout` fail silently and loops report bogus results. Use absolute paths.
- **A suite's log lags by up to 4 KB when redirected to a file** — `print` is
  fully buffered there, so `tail -f` looks stalled on a healthy run. Watch the
  process, not the log.
- **Watch for the suite with `pgrep -x tests`, not `pgrep -f build/tests`.** The
  `-f` form matches every *waiter* whose own command line contains the string,
  including itself, so a "is a suite running?" guard reports yes on a machine
  with no suite on it. Four such loops once sat waiting on each other while
  nothing ran, and the guard they fed refused to start the real run. The
  instrument was measuring itself — §3, in the shell rather than the code.
- **`nohup … &` reports success immediately** while the real work runs orphaned.
  Wait on the process; don't trust the exit code.
- Zotero locks `zotero.sqlite`; copy it before querying.
- Filenames here may contain non-breaking spaces (U+00A0). Glob, don't retype.
- The volume is case-insensitive: `tools/` and `Tools/` are the same directory.

## Verification discipline

When a measurement is surprising, suspect the instrument first. Several
"confirmed" findings in this project's history were artifacts: `difflib` autojunk
on repetitive text, a glob matching unrelated files, ImageMagick's `AE` exceeding
the pixel count, a probe counting short lines as failures. State plainly whether a
finding was verified by running code or only reasoned about.

Prefer editing with `Edit` over scripted text-slicing on source files. An
over-broad Python slice once deleted four functions from `Model.swift`; with no
version control at the time they had to be reconstructed from memory.

## Not committed

`testdocs/` — 1.2 GB of third-party copyrighted PDFs, 233 of them. `testdocs/manifest.tsv` and
`Tools/sample-zotero.py` let it be rebuilt from a Zotero library.
