# Known defects

Findings from an adversarial review (three parallel code reviews plus a 78-document
corpus run over the Zotero library). Every entry was verified by running code
unless marked *reasoned* or *unverified*.

Status: `OPEN` · `FIXED` · `WONTFIX` (with a reason)

**Five open, and three of them change content on the default route. R58 is `FIXED` but its
feature is deliberately unreleased** — the annotation transplant, after two adversarial rounds
that each found marks landing in the wrong place. The third round is unrun.

**C23 is the newest, and it was found by the release gate an hour after T9 taught the gate to
read pixels.** `JBIG2.assemble` writes no `/CropBox`, so on the default route the rebuilt copy
displays what the original's crop box hid — C13's own harm, at the one site C13's fix never
reached. 14 of 233 corpus documents, 577 of 16,987 pages, worst case a third of the sheet.

**R56 and R57 are in the app, on the default route.** R56: a pale line drawing is
**erased** by the 1-bit route, because it scores the same ink, tone and saturation as a
page with nothing on it but text — no routing signal has a term for the zone it sits in.
R57: a continuous-tone plate over a fifth of a page misses *both* routing gates at once
(ink 0.147 against 0.15, tone 0.102 against 0.12) and comes out a solid black blob that
swallows a line of text. Both were found by the adversarial fixtures in
`Tools/make-plate-fixtures.swift`, both are **rendered rather than argued**, and both
converge on the one unbuilt instrument `FEATURES.md` specifies: shape, not luminance. A
luminance signal was built for R56 and refused over four measured rounds. Neither is
fixed, and `TODO.md` item 1's size optimisation is refused until R56 closes, because it
would make R56 more common for a measured 8.2 KB a page.

**R54 and R55 are not in the app.** R54, a pooling bug in `Tools/sweep-zotero.py` that
makes its per-type medians and its "GB reclaimable" figure untrustworthy for 181
parentless attachments; it matters only when the library sweep runs, which is scheduled
last. And R55, `classify-source` calling an upright-scanner capture `photographed`,
which is the gate deciding what the corpus and the sweep are allowed to contain.

**R51–R53 came out of a review of R49 and R50's own diff and are all `FIXED`** — the
tenth round running in which reviewing the previous round's code found real defects in
it. One of them, R52, was a page stored at an eighth of the resolution its user had
explicitly asked to keep.

**R49** — a 568-page scan going in at 31 MB and out at **437 MB**,
because colour pages were the one kind that could not be layered — is `FIXED`, and
**R50** finishes the job: the file now lands at **35,379,516 bytes, 1.13x its
original**, down 12.4x, with a byte-identical text layer. R49's entry records a
detector fix that was built, measured and **refused** — the page's own luminance
histogram cannot tell tinted paper from a tinted plate — and R50 records the signal
that *does* work and why it was available all along. **U29** (the updates block was pasted
twice in the settings panel) and **U30** (the preset buttons gave no sign they had
done anything) were both reported by the user on 2026-08-13 and are both `FIXED`.

R41–R48 came out of an adversarial review of R40's own diff
and are all `FIXED` — the ninth round running in which reviewing the previous
round's code found real defects in it. R40 — batch throughput falling when
recognition came in-process, because Vision does not parallelise across concurrent
requests in one process — is `FIXED`: recognition runs in a helper process per file again,
and the helper compiles the app's own `Recogniser.recognise` so the observations
are identical by construction rather than by agreement. R39 is `FIXED`,
and the fix it originally proposed was measured and refuted before a different,
real defect was found underneath it. U23 and T8 close the fourth of the four ways this register
kept producing defects from its own fixes; the other three got controls in the
same round. The third review's five — R31, R32, T6, T7, H2 — are all
`FIXED`, and the round added three controls aimed at the *shapes* rather than
the instances: `Tools/fault-inject.sh` (execute the error branches),
`Tools/mutate.py`'s own repair (T7), and the sibling sweep in CONTRIBUTING 4b,
which immediately found a mount leak the review had missed.

That review covered the 868 lines the bundling and mutation work added after
1.3.0. Nine claims, **nine confirmed, none refuted** — the verifier built an `otool` shim and ran the real
scripts rather than reading them. Five of the nine are in code written the same
day, which is the third consecutive round to find that, and T6 is the third
consecutive round to add checks that cannot fail *while looking for checks that
cannot fail*.

T5 records the first mutation campaign: sixteen mutants
killed, six gaps found and closed, two survivors kept with reasons.

Two reviews ran against this codebase on 2026-08-09, the
second against the release the first produced. It found seven more defects, and
**five of the seven were in code or tests written during the first** — R29 is the
hole R24 left and then wrongly recorded as measured, R30 is U18 reaching for the
wall clock in a file that documents why not, U21 is U19's flag and U20's async
import interacting, and T4 is three checks from that round that could not fail.
This register has claimed for a year that every pass finds defects in the
previous pass's code. It demonstrated it twice in one evening.

C22, R29, R30, U21 and T4 are all `FIXED`, each with a check that was watched
failing first.

The eleven raised by the first 2026-08-09 review — C19, C20, C21, R23, R24, R25,
R26, R27, U18, U19, U20 — are `FIXED`, each with a test that was watched failing
first. Fourteen were claimed; a skeptic pass
that defaulted to refuting killed three, and those measurements are kept as R28
because they are worth more than the claims were.

Three of the eleven were a fix that stopped one line short of the code beside
it: U18 is U5's hazard still live, because the bound was placed after the call it
was meant to bound; R23 is R19's recursion bound missing from its mirror
function; R24 is an `Int` overflow trap inside R20's own crash guard. Fixing a
thing and fixing the thing next to it are still different acts.

**Three tests in this round did not bite when first written**, and each is
recorded where it happened rather than quietly corrected: R25's depth fixture
(CoreGraphics walks the shallower branch first, so the case cannot be built),
U20's timing bound (4,000 files walk faster than any threshold, so the property
had to be restated without the clock), and C20's selection probe (twice — one
fixed row missed a one-point run, then the scan ran into the neighbour's box).
A test written after the fix and never seen red is a test that proves nothing.

The four raised by the 2026-08-08 corpus run — C17, D1, D2 and D3 — are all closed, and
closing D1 meant replacing the corpus rather than re-wording a sentence. D2's
remainder became C18: the newspaper line-end weakness has a cause, a fix, and a
fourth text-layer property nobody knew was load-bearing. Everything else is `FIXED` or `WONTFIX` with a
reason. The run itself was clean (40/40, median 100% line-start); what it found
was that the *corpus* the project's headline figures rest on is mostly not scans,
and that the app quietly damages the material that makes up half of it. Full
write-up: [CORPUS-2026-08-08.md](CORPUS-2026-08-08.md).

Fixed in the first pass: C1, C2, C3, C4, C6, R1, R6, R7, R11.
Second and third passes — fixed from the original list: C7, R2, R3, R4, R5,
R7 (never actually fixed the first time), R8, R10, R12.
Found and fixed since: C8, C9, C10, C11, C12, C13, C14, C15, R14, R15, R16,
R17, R18, R19, R20, T1, T2, and U1–U7 in the interface.
Fixed for 1.0, clearing everything that had been left in `TODO.md`: C16, R21,
R22, T3, H1, and U13–U16. U8's remainder (announcements) landed as U16.
`WONTFIX` with the reasoning recorded: C5, R9, R13.

**Every adversarial pass over this codebase has found real defects in code
written during the previous one.** C13 and C14 came from C10 and C9, R17 from R2,
and a fourth pass over the outline work (R19) found eight more in code written
minutes earlier — including a destination-mapping error affecting the majority of
real bookmarks and an unbounded recursion that could kill an entire batch. That is
not an argument against changing things; it is the argument for
[CONTRIBUTING.md](CONTRIBUTING.md)'s review step, and for never treating a fix as
finished because it compiles.

Five entries turned out to be **wrong as written** — C5, R3's title, R7's
recorded fix, R9, and R21's whole diagnosis (SIGTERM already reached the process
group; it was the SIGKILL escalation that leaked, which is the opposite of where
the entry pointed) — so re-measure before you fix, and correct the entry when it
does not hold. R21 is the cleanest example in the register: the recorded fix was
a `posix_spawn` rewrite of the riskiest code in the project, and the measurement
turned it into two lines.

Update this file as items are fixed — including the evidence that they are.

---

## Correctness — loses or corrupts content

### C1 · Four silent `return`s in `draw()` drop whole lines — FIXED
**Fix:** `draw` now returns a reason instead of returning silently, `compose`
collects them and returns them (see C8 — they used to go into a static), and
`makeSearchablePDF` fails the run with the page, the text and the reason. The `0.1...400` band — the one that
discarded real table rows, rules and page numbers — clamps into range instead of
giving up, so those lines are placed rather than lost.
`Sources/SearchableWriter.swift`, in `draw(_:in:ceiling:font:into:)`.
Guards on `width > 0.5, height > 0.5`, `probeWidth > 0`, and
`widthSize > 0.1, widthSize < 400` each abandon a line with no log, no counter and
no error. The only integrity check in the pipeline is page count, so the loss is
undetectable by design.
Verified dropped: `I 3` in a 468pt column (widthSize 420.9), `—` and `_` over a
428pt box (rule and leader lines), a lone `1` in a 306pt box (550), a 2000-char
line (widthSize 0.44), text of only U+200B / U+200F / newline.

### C2 · `useJBIG2` silently overrides "Rebuild page images first" — FIXED
**Fix:** `wantJBIG2` now requires `rebuild`. Settings shows the JBIG2 toggle
whatever the rebuild setting, and the "keeps its old text layer" note appears only
when the rebuild really is off, where it is true.
`Sources/Model.swift` (`wantJBIG2` omits `rebuild`; `if mustStrip || wantJBIG2`).
With the rebuild toggle **off** and JBIG2 on (the default), pages are still
re-rendered and thresholded. Verified: an RGB gradient page went from
`rgb(161,80,160)` to `rgb(111,111,111)` — colour discarded against an explicit
setting. Compounded in `SettingsView`, which only shows the JBIG2 toggle *if*
`rebuildImages`, so the pref doing the overriding is unreachable, and prints
"Without the rebuild, an already-OCR'd PDF keeps its old text layer", which is
false whenever JBIG2 is available.

### C3 · Image inputs can never produce a searchable PDF — FIXED
**Fix:** `Flattener.wrapImage` wraps a dropped image as a one-page PDF (honouring
its DPI) before the pipeline runs. Verified: a PNG now yields a searchable PDF
whose text layer reads "A PNG dropped straight onto the app".
`Sources/Model.swift` (`PDFPageCount` → `PDFDocument(url:)`) and
`Flattener.flatten`. The drop box advertises "Images and folders work too" and
`supportedExtensions` accepts png/jpg/heic; mac-ocr's own `searchable-pdf` handles
images. Verified on a PNG that plain `mac-ocr` reads: fails with
"Could not read the rebuilt PDF to check it." or "Could not rebuild page images",
both of which blame the user's file.

### C4 · Duplicate observations double the text on a line — FIXED
**Fix:** `SearchableWriter.deduplicated` drops an observation repeating the same
text within one line height of an existing one — same words in the same place, not
merely the same words, so a running head repeating a body phrase still survives.
`Sources/SearchableWriter.swift`, `observations(fromJSONLines:)` /
`observations(fromJSONAt:)` merge duplicate page entries deliberately, and
`headroom`'s `gap > 0.5` ignores the twin. Two identical observations extract as
"text that appears twice text that appears twice".

### C5 · Right-to-left text is stored in visual order — WONTFIX
**The original entry was wrong, and the obvious fixes are worse than the defect.**

Re-measured through the real `compose`, six samples (pure Hebrew, pure Arabic,
RTL-then-two-LTR-runs, LTR-either-side-of-RTL, digits inside RTL, LTR control):

| extractor | result |
|---|---|
| PDFKit | **all six round-trip in logical order**, including the case the entry said was broken |
| poppler | correct on pure-RTL and pure-LTR; on *RTL-first mixed* lines the RTL run reads last |

So the claim "Hebrew followed by two LTR runs extracts with the LTR runs swapped"
does not reproduce under PDFKit at all. What is real is narrower: a
*geometry-driven* extractor reads an RTL-first mixed line in the wrong run order.

That is not fixable at the glyph level. `<hebrew> alpha beta` laid out with an RTL
base and `alpha beta <hebrew>` laid out with an LTR base produce **byte-identical
glyph placement** — same glyphs, same x to within 0.01 pt (measured). Nothing in
the content stream distinguishes them, so no extractor working from geometry can
recover which was meant.

Two candidate fixes were measured and rejected:

- `kCTTypesetterOptionForcedEmbeddingLevel: 0` — reverses the characters *within*
  every RTL run. Breaks all four RTL cases under both extractors.
- `NSParagraphStyle.baseWritingDirection = .leftToRight` — regresses PDFKit from
  6/6 to 4/6 and does not fix poppler.

The only mechanism that would work is `/ActualText` marked content, which
CoreGraphics' PDF context cannot emit; it would mean post-processing the file.

Crucially, the current placement is the *correct* one: CoreText puts the first
logical RTL run at the right, which is where the ink is, so the invisible run sits
over the words it belongs to and selection highlights the right region. Forcing
logical order left-to-right would move the text layer off the ink — breaking
invariant 3 ("runs span the ink") to satisfy one extractor.

Guarded by "right-to-left text" in `Tests/main.swift`: six samples composed through
the real writer and checked for logical-order round-trip, so a future change to
`draw` cannot silently start reversing RTL lines.

### C6 · stderr drain drops the real error message, and races — FIXED
**Fix:** the drain writes into a lock-protected box, so the read after the timeout
is synchronised and the message survives.
`Sources/Runner.swift`, `runStreaming`. `errorText` is written on a background
queue and read after `errDone.wait(timeout: .now() + 5)`; on timeout there is no
synchronisation. Reproduced: child exits 9 after writing to stderr while a
descendant holds the write end for 7s → `outcome=failed message=""`, and
ThreadSanitizer reports a data race at the assignment.

### C7 · MediaBox vs CropBox — FIXED *(was unverified; now settled by measurement)*
**Settled: mac-ocr renders the crop box.** Hand-built fixture, MediaBox 612x792
and CropBox (100,100)–(412,500), three words drawn — one inside the crop, two
outside. `mac-ocr --format json` reported `"width": 624, "height": 800` (the
312x400 crop at the 2x render scale) and recognised **only** the word inside the
crop. So Vision's normalised boxes come back relative to the crop box.

The app mapped them onto the media box, so on any page where the two differ every
observation was offset *and* rescaled. Measured on that fixture before the fix:
the run for a word whose ink sits at crop (50, 200) was placed at (97.8, 408.3) —
out by 48 pt across and 208 pt down, and the published page was 612x792 instead
of 312x400.

This is not a rare shape: **8 of the 78 corpus documents** carry a crop box that
differs from the media box on at least some pages (44 have no crop box at all, 26
set it equal). `Connelly` crops 154 pt off the height; `Frederick 1925` has a
landscape crop on portrait media.

**Fix — two boxes, deliberately kept apart.** The first attempt used the crop box
everywhere and *regressed* a real document: `Margalit_2013` (media 546x762, crop
504x720) fell from 100% to 90% line separation, because cropping the rebuild
throws away part of the sheet. The metric is deterministic — three repeats gave
174/192 every time — so that was a real regression, not noise.

- `Flattener.displayBox` — the **crop** box: what a viewer shows and what mac-ocr
  renders. `SearchableWriter.compose` uses it, so observations land where the
  recogniser found them.
- `Flattener.fullBox` — the **media** box: the whole sheet. `flatten` renders
  this, so a rebuild never silently discards what the crop excluded
  (invariant 1). `saturation` and `nativeDPI` match it, since they describe the
  page that actually gets written.

The two never disagree in a way that matters, because the rebuilt file carries
only a media box: when the recogniser and then `compose` look at *it*,
`displayBox` falls back to that same media box and all three agree. Worst
affected was the **non-rebuild** path, where mac-ocr sees the user's original.

`renderGrey` now takes the `CGPDFBox` it should draw, so the box a caller measures
with and the box it renders from cannot drift apart.

**Verified.** 8 checks in "crop box differing from media box"
(`Tests/main.swift`), including that words outside the crop survive the rebuild.
Reverting `displayBox` to the media box fails 3 of them. Invariant 3 re-measured:
line separation is **identical on all 12 sampled corpus documents** before and
after, including all three with differing boxes.

### C8 · Concurrent files erased each other's lost-line reports — FIXED
*(found in the second review, not in the original pass)*

`SearchableWriter.skipped` was a `static var`. `compose` cleared it on entry and
appended to it per line; `makeSearchablePDF` read it back after `compose`
returned. Files are OCR'd **concurrently** — the default is this Mac's
performance-core count — so the next file's `compose` reset the static before the
previous file's caller had looked at it.

The consequence is the exact failure invariant 1 exists to prevent: **a document
that lost lines was published as a clean success.**

Reproduced against the pre-fix code, 40 concurrent runs of each of two documents,
one losing 3 lines and one losing none:

| | correct | what happened |
|---|---|---|
| the losing file | always 3 | reported 0 **21 times**, 3 fourteen times, and 6/7/9 (another file's losses) five times |
| the clean file | always 0 | reported 3 **17 times**, plus 6/7/9 four times |

26 of 40 losing runs and 21 of 40 clean runs were misreported. One run of the same
harness died with SIGTRAP, which is what unsynchronised mutation of a shared
`Array` looks like when two appends realloc at once — so this was also a live
crash risk, not only a reporting fault.

**Fix:** `compose` returns `[SearchableWriter.Unplaced]` and the static is gone,
so the losses cannot outlive or escape the call that produced them.
`makeSearchablePDF` holds them in a local.

Guarded by "unplaced lines are reported per file" in `Tests/main.swift`: 80
concurrent composes, asserting the losing file always reports exactly its own 3
and the clean file never inherits any.

### C9 · A logo set the whole page's rebuild resolution — FIXED
*(found in the second review. The most destructive defect in this pass.)*

`Flattener.nativeDPI` reports the resolution implied by the largest image
embedded on a page, and `flatten` rebuilt at it. On a **born-digital** page the
largest image is a logo or a figure, not a scan — so the page was rasterised at
the logo's resolution and everything else on the sheet was annihilated. The page
count still matched, so the run reported success.

Measured across the corpus, 214 sampled pages: **84 report under 150 DPI and 35
under 72.** Worst cases, verified end to end through the real `flatten`:

| page | reported | rebuilt as | text on the page |
|---|---|---|---|
| `Beyond the Welfare State`, p6 | **1.9 DPI** | **16 x 23 px** (595x841 pt) | 1,846 chars |
| `Kelly - 1981`, p1 | 22.1 DPI | 188 x 243 px | 642 chars |

**Fix:** `Flattener.rebuildDPI(of:)` applies the policy that `nativeDPI` should
not: below `minimumPlausibleScanDPI` (150) the largest image is not the page's
scan, so fall back to 300. `nativeDPI` stays a plain measurement for the tools.
The asymmetry is the argument — treating a real 100 DPI scan as 300 upsamples it,
costing bytes and losing nothing; treating a logo's 1.9 DPI as the page's
resolution loses the page.

**Effect on the corpus — and a measurement trap.** By the line-separation *ratio*
this looks mixed (Hoffman 100%→94%, Cox 95%→92%). It is not. The ratio's
denominator is how much text Vision finds, and the floor makes it find far more:

| document | lines recognised before | after |
|---|---|---|
| `Hoffman - 1923` | **3** | **139** |
| `Connelly` | 112 | 120 |
| `Merriam_1959` | 193 | 207 |
| `Cox_1925` | 96 | 100 |

Three sampled pages of a 1923 book previously yielded *three lines of text*. Every
document recovers content; no document loses any. A falling percentage over a
46x larger denominator is the artifact class CLAUDE.md warns about.

Guarded by "a logo does not set the page's rebuild resolution" in
`Tests/main.swift`: a born-digital fixture whose only image is a 16 px logo,
checked end to end for its text surviving the rebuild.

### C10 · The published copy was cropped to the crop box — FIXED
*(found by the second review, in the C7 fix itself)*

C7 made `compose` publish pages at the **crop** box, because that is what
observations are normalised to. Correct for placing text, wrong for the file:
everything outside the crop was silently dropped from the user's copy, and the run
still reported success. On the non-rebuild path `visible` is the user's own
original, so that is their content disappearing — the exact shape invariant 1
forbids, introduced by a fix for a different bug.

**Fix:** the two concerns are now separated properly.

- The page is published at `Flattener.fullBox` (the media box), so the whole sheet
  survives.
- `SearchableWriter.cropRegion(of:on:)` works out where the crop box lands on that
  page, and observations are placed inside *that* sub-rectangle. `draw` adds the
  region's origin instead of assuming zero.

`cropRegion` derives the rectangle by putting the crop rect through the very
`getDrawingTransform` CoreGraphics uses for the media box, so `/Rotate` is handled
by the framework rather than by hand — hand-rolled quarter-turn arithmetic is what
previously drew pages off-canvas. A crop box larger than the media box is
intersected, per the PDF spec.

When the two boxes coincide — 44 of 78 corpus documents have no crop box at all,
26 more set it equal, and every rebuilt file carries only a media box — the region
is the whole page and the behaviour is byte-for-byte what it was.

Guarded by four checks in "crop box differing from media box": the published page
is media-sized, the words the crop excluded are still readable in the copy (by
re-OCRing it, not by trusting the text layer), the run lands on the ink in
full-page coordinates, and `cropRegion` reports the crop's true position.

### C15 · A multi-page TIFF was reduced to its first sheet — FIXED
*(found by the third review)*

`Flattener.wrapImage` read `CGImageSourceCreateImageAtIndex(source, 0, nil)` and
wrote exactly one PDF page. A container format can hold many images, and a
multi-page TIFF is the standard output of every sheet-fed archival scanner — so a
whole document was reduced to its cover page and **published as a success**,
because one page in was one page out and the page-count check compared the wrapped
PDF against itself.

This matters more as an OCR backend than it did as a drop box: an ingest pipeline
feeding scanner output straight in would lose all but the first sheet of every
document, silently.

**Fix:** `wrapImage` emits one page per image, each with its own media box as
CFData (sheets in one TIFF need not match, and an NSValue is silently ignored —
invariant 4). A sheet that cannot be decoded aborts the wrap and removes the
partial file rather than vanishing from the middle of a document.

Guarded by two checks: a 3-sheet TIFF of differing sizes becomes 3 pages, and each
keeps its own size rather than sheet 1's.

### C13 · The published copy displayed more than the original — FIXED
*(a regression introduced by C10, found by the third review)*

C10 moved the published page to the media box so nothing on the sheet was lost.
But `compose` wrote only `kCGPDFContextMediaBox`, so the output carried **no crop
box at all**: a page the original displayed at 420x250 came out displaying
612x792. Margin notes and running heads the viewer had been hiding became
visible — and because the recogniser only ever saw the crop (C7), that
newly-revealed ink carries no text layer. The result looked like a successful OCR
of a document that had grown unsearchable furniture.

**Fix:** `compose` writes both. Media box for what is *kept*, crop box for what is
*shown*, so the copy retains every mark and still looks like the original.

Note the two checks this needs are opposites, and the obvious one is wrong:
re-OCRing the published copy cannot prove the hidden ink survived, because
mac-ocr renders the crop and would only ever report what is displayed. The test
lifts the trim off a throwaway duplicate first, then OCRs.

### C14 · The DPI floor upsampled genuine low-resolution scans — FIXED
*(an over-correction in C9, found by the third review)*

C9's floor asked "is this DPI plausible for a scan?" when the question is "is this
image the page, or something sitting on it?" A low implied DPI has two causes and
the floor conflated them:

| | example | right answer |
|---|---|---|
| a logo on a born-digital page | 16 px wide, implies 1.9 DPI | ignore it, render at 300 |
| a genuine coarse scan | 1936 px wide, implies 72 DPI | trust it |

Rendering the second at 300 is pure upsampling — 4x the linear scale, **17x the
pixels**, no more detail — and with several files in flight that is the difference
between comfortable and gigabytes.

Measured over the corpus: of 84 sampled pages below the floor, **47 are logos
(16–96 px wide) and 37 are real 72 DPI scans (1936–2592 px wide)**. Nothing lands
in between, so the discriminator is not finely balanced.

**Fix:** `Flattener.largestImage` returns the pixel width alongside the DPI, and
`rebuildDPI` trusts a sub-floor resolution when the image is at least
`minimumScanPixelWidth` (600 px) — wide enough to be the page rather than a mark
on it. Exercised over all 4,992 corpus pages without a crash.

### C12 · A page the recogniser skipped published as a page with no text — FIXED
*(found by the second review)*

Nothing compared the recogniser's output to the document's page count.
`jsonLines` was used for progress and then decoded; a page mac-ocr never reported
simply had no entry in `byPage`, so it composed as a page with no text layer,
passed `produced == expected`, and published as a success. A silently untextable
page in the middle of a book — invisible to every other guard, because the page
itself is still there.

The distinction that makes this checkable: **mac-ocr emits one record per page
even when the page is blank.** Verified — a 3-page document with a blank middle
page yields three records, the middle one with an empty `observations` array. So
an empty array means "nothing on this page" and a *missing key* means "this page
was never recognised", and the two are not the same thing.

**Fix:** `SearchableWriter.missingPages(in:of:)` returns the page numbers with no
record at all, and `makeSearchablePDF` fails the run naming them rather than
publishing.

Guarded by "a skipped page is not mistaken for a blank one": a blank middle page
is not flagged, a missing one is, a truncated run reports every missing page, and
— end to end through the real `makeSearchablePDF` — a document with a genuinely
blank page still succeeds, so the guard is not worse than the bug.

### C11 · A dropped image was wrapped squashed, or sideways — FIXED
*(found by the second review)*

`Flattener.wrapImage`, two independent faults in four lines:

- **One resolution for both axes.** `kCGImagePropertyDPIWidth` was used for the
  height too, so an image recording different horizontal and vertical resolution
  came out squashed by the ratio between them. Not exotic: 200x100 dpi is a
  standard fax mode. Measured — a 400x400 px image at 200x100 dpi should wrap as
  144x288 pt and wrapped as **144x144**.
- **EXIF orientation ignored.** `CGImageSourceCreateImageAtIndex` returns the
  *stored* pixels, not the oriented ones, and nothing applied the tag. A phone
  photo shot in portrait is stored landscape with orientation 6, so it was wrapped
  as a landscape page with the text running up the side. Measured — a 600x300
  image tagged 6 wrapped as **600x300** where it should be 300x600.

Only affects dropped images, which the drop box advertises ("Images and folders
work too"), not PDFs.

**Fix:** both resolutions are read separately, and swapped when the orientation is
a quarter turn. The image is oriented through
`CIImage.oriented(_:)` rather than by composing the transform by hand —
hand-rolled quarter-turn arithmetic is exactly what drew rotated PDF pages
off-canvas once already, and this is one image, not a book.

Guarded by "wrapping a dropped image": four checks covering per-axis resolution,
orientations 6 and 8, and an untagged image being left alone. Reverting
`wrapImage` fails three of them.

---

### C16 · A short text layer published as a complete file — FIXED
`Sources/Model.swift`, the JBIG2 route. The pipeline's integrity check is
`produced == expected`, and on this route `produced` is the page count of the
images PDF `JBIG2.assemble` built — which comes from `encoded`, a list already
checked against `expected` two branches earlier. It cannot fail.

The text layer was checked by nothing. `qpdf --overlay` stamps as many layer
pages as it has onto the images and leaves the rest bare, so a layer that stopped
short produced a full-length, structurally valid PDF whose later pages simply had
no text — and it published as a success. This is invariant 1's exact shape: page
count is not sufficient verification, and a truncated-but-valid PDF opens fine.

Measured: a 2-page layer overlaid onto a 3-page images PDF yields 3 pages, and
every page-count assertion in the suite passes on it.

**Fix:** the composed layer's page count is checked against `expected` before
anything is merged — after a cancellation check, because `compose` returns a
short layer when it is interrupted and reporting the user's own Cancel as a
corrupt file is R14's mistake in a new place.

**Honest about the evidence:** the hazard is measured and the predicate is
tested ("a short text layer is caught"), but nothing in the suite drives the real
`makeSearchablePDF` into producing a short layer — on this route the layer's page
count comes from the same document `expected` does, so the only ways in are a
cancel (covered) or a future `compose` regression (which is what the guard is
for). Reasoned, not reproduced end to end.

### C17 · A born-digital PDF was silently degraded — FIXED
*(found by the 2026-08-08 corpus run; full write-up in
[CORPUS-2026-08-08.md](CORPUS-2026-08-08.md) §3 P1)*

Drop a born-digital PDF on the window in Searchable PDF mode and the defaults
rebuild its pages as images — discarding real, correct, embedded text — then
replace it with OCR of a rendering of that text. The run reports success.

Measured on three pages of `Jacobson_2004_Raising consumers.pdf`, which has no
page images at all:

| | before | after |
|---|---:|---:|
| characters | 6,237 | 6,128 |
| words | 1,031 | **938** |
| words in the output that existed in the original | — | **86.1%** |

About 9% of the words are gone, and roughly one in seven of those that remain is
an OCR artefact — `traditiona` for `traditional`. Verified by running code.

The app is behaving as designed: `rebuildImages` defaults on because *for a scan*
any existing text layer is a previous OCR pass that would double up. For a
born-digital file the premise inverts — the text that is there is better than
anything Vision will make from a picture of it. Nothing in the UI mentions this,
and it is not a rare input: **51% of this project's own corpus** is born-digital.

This is invariant 1's shape. The page count is right, the file opens, the text
looks plausible, and content was lost anyway.

**Fix: ask, and mean it.** Not a refusal — sometimes the embedded text *is* the
problem (a bad export, a mis-mapped font, a publisher's broken layer) and
re-OCRing is exactly what the user wants. So the capability stays and the
surprise goes.

`Flattener.hasDigitalText` samples pages through the document and answers yes
only when a majority carry real text **and** no page-sized image. That second
half is the whole test: an already-OCR'd *scan* has text too, and warning about
it would put a dialog in front of this app's main use case — so
`Flattener.pageIsAnImage` separates the two. Conservative by construction; a
false negative costs nothing but the warning, a false positive costs a question
nobody needed.

`OCRModel.start` runs that as a pre-flight before the batch — off the main
actor, because one `PDFDocument` open per file would freeze the window on a
78-file batch, which is U5's mistake with a different cause. Start shows
"Checking…" and is disabled meanwhile. If anything is flagged, an alert names
the files and offers **OCR Anyway / Skip Those / Cancel**, with a "Don't ask
again" suppression that writes `Prefs.warnDigitalText`; there is a matching
Settings toggle. Only the destructive path asks — Extract Text writes a new file
and leaves the input alone.

Guarded by "telling real digital text from an OCR layer" in `Tests/main.swift`,
whose load-bearing case is the third one: a scan that has already been OCR'd
must **not** be flagged. Verified in the VM against the running app — the alert
correctly flagged 1 of 2 files, nothing started until it was answered, and
"Skip Those" ran only the scan, logging "Skipped 1 file(s) that already had
selectable text; their own text is kept."

One thing this does not do: **Extract Text mode still re-OCRs a born-digital
PDF** rather than reading its text out. Nothing is destroyed there — the input is
untouched and the user gets a `.txt` that is merely worse than it could be — so
it is out of scope here and recorded in TODO.md.

### C18 · Line ends were unselectable on dense scans, and fixing it welded words — FIXED
*(the newspaper problem: the fix and the thing the fix broke, both measured)*

`Sources/SearchableWriter.swift`. Newspaper scans scored median 91% line-end
selectability against 100% for books, journals and reports, bottoming out at 71%
on one document — nearly a fifth of its lines could not be selected to the end.

**Cause.** One line in `draw`. When a line needs a large font to span its box but
sits close to its neighbours, the code caps the font size rather than squashing
further (`minimumVertical = 0.5`). Capping the size costs **width, not height** —
`size * vertical` is the same allowed glyph height either way — so the run comes
out 15–30% narrower than its box and its last words fall outside it. Measured
across 1,206 lines of 9 newspaper documents: **72% of misses were a run that
simply stopped short** (83 of 115), 19% vertical, 9% absent. Column-spanning
reference boxes, the obvious measurement artifact, accounted for 1 of 115.

The shipped comment justified the cap as costing "only highlight thickness". That
is what the measurement contradicts, and it is why this was worth reopening.

**And the trap.** Lowering the floor to 0.25 fixed line-end (28 documents better,
worst 71% → 91%) and cost word retention on 7 of 24 newspaper documents.
Investigated rather than accepted: the extracted **characters are identical** —
same multiset, nothing lost — but *word boundaries* go. `valuablestudy`,
`Londos,and`, `thatmeasurable`.

Vision splits one visual line of a column into fragments side by side, and
nothing writes a space character between them; each is its own `CTLineDraw`, and
PDFKit synthesises the space from the geometric gap, giving up below about
0.15 em. **That gap was never reserved.** It existed only as slack left over from
the size cap — a side effect of a constant chosen for an unrelated reason.
Widening the runs removed the slack, and the words met.

**Fix.** `rightLimit(for:among:in:)`, the mirror of `headroom`: `headroom` stops
runs colliding vertically, this stops them colliding horizontally. `draw` shrinks
the run to stop `reserveEms` (0.25 em) short of the nearest same-baseline
fragment to its right. Proportional, not absolute, because PDFKit's threshold is
proportional too — so 0.25 em clears it at every size. An absolute floor was
tried at 0.5, 2 and 4 pt and scored **identically to no floor at all** across 25
newspaper scans, so it is not in the code.

**Measured on the full 84-document scanned corpus, shipped vs fixed:**

| | shipped | fixed |
|---|---|---|
| line-end median / worst | 100% / **71%** | 100% / **91%** |
| words median / worst | 99% / 94% | **100% / 97%** |
| line-start | 100% / 91% | unchanged |
| text-layer offset | max 0.10 | **max 0.10 — unchanged** |

Line-end: 28 documents better, 1 worse. Words: **32 better, 0 worse** — better
than shipped, because the reserve also opens welds that were there all along.

**What that word figure is and is not.** `words=` is a raw token-count ratio
(extracted tokens / reference tokens), not an intersection, so it is a *net*
statement: welds and splits cancel, and a substitution or a reordering is
invisible to it. Two things were checked by hand because of that — the extracted
non-whitespace characters are an identical multiset before and after (nothing is
lost, only regrouped), and the *order* of extraction does change on some
multi-column pages, in both directions. Nothing in the corpus figures can see
reading order; if that ever matters, it needs its own metric.
`Tools/score-line-separation.swift` — compiled twice, once from each revision,
because it takes no argv for these constants — is **byte-identical before and
after on 8 newspaper documents**. That is the check that matters for invariant
3(b), and it is the only one that could have caught a regression there.

An earlier draft of this entry also cited "vertical overlap 1.33% unchanged".
That row has been removed: `score-corpus`'s overlap column is computed entirely
from the reference OCR of the rendered image and cannot respond to a text-layer
change at all. It was a tautology dressed as evidence. See D3.

**Why vertical merging cannot regress**, stated correctly: the drawn glyph height
is `min(wanted, 3 * widthSize)`. `minimumVertical` does not appear in it — in the
capping branch `size = wanted/minimumVertical` and `vertical` clamps back to
exactly `minimumVertical`, so the product is `wanted` for any floor. The reserve
only ever *reduces* `widthSize`, and height is monotone non-decreasing in it, so
runs can get shorter but never taller. (The first draft said "glyph height does
not change", which is true of `minimumVertical` and false of `reserveEms` when
`vertical` is already clamped at 3.0 — measured, 17.081 pt to 17.037 pt. Shorter,
so the conclusion holds; the reason did not.)

The one regression is `HarpersMagazine-1938-05` at 99% → 98% line-end,
deterministic on repeat, one line of 93 — the reserve shortening a run that does
have a right-hand neighbour. That is the trade working as designed.

**Evidence base widened first.** The corpus had 9 newspaper scans; 16 more were
sampled for this (`--types newspaperArticle --exclude-manifest`), and notably
**none of the 91 modern candidates survived the scanned gate** — recent newspaper
items in this library are all born-digital downloads. The measurements above are
over all 25.

Guarded by "adjacent fragments of one line keep their space" in `Tests/main.swift`,
which drives `compose` with hand-built observations because the failure needs two
fragments at a controlled distance and Vision's segmentation is not ours to
dictate. It bites: with `reserveEms` set to 0 the words weld, and that is checked
*first*, so a silently-ineffective guard cannot pass.

**This is the fourth property of the text layer**, and CLAUDE.md invariant 3 now
says so. It had been holding by accident for the life of the project.

### C19 · "Use Existing Text" silently writes an empty section for a page with no text — FIXED
*(2026-08-09 review; confirmed by reading the code and the routing that reaches it)*

`Sources/Model.swift:450`. `writeEmbeddedText` appends
`doc.page(at: i)?.string ?? ""` for every page. A page that yields nil — a scanned
plate in an otherwise born-digital book, or a page PDFKit cannot parse — becomes an
empty string, and in a `"\n\n"`-joined body that is indistinguishable from a page
break. The only guard is that the *whole* body is non-empty, so one page with text
is enough to publish the file and report `✓ used the PDF's own text; no OCR was
run`.

The routing makes this the expected shape rather than an exotic one.
`Flattener.hasDigitalText` samples at most four pages at `(i+1)*total/5` and needs
only `digital * 2 > sampled`, so a mostly-born-digital document with a scanned
appendix is flagged as digital; `askAboutDigitalText` then makes "Use Existing
Text" the **default** button whenever mode is `.text` and format is `.text`.

Invariant 1: the run drops content and reports nothing. Unlike the all-scan case
there is no `Failure.noTextFound` to catch it, because the other pages carry the
body past the guard.

The three tests at `Tests/main.swift:3408`, `:3416` and `:3423` cover an
all-digital round-trip, extracting twice, and an all-scan file failing loudly.
None uses a document where only *some* pages lack text.

**Fix:** `writeEmbeddedText` returns the 1-based numbers of the pages that
contributed nothing *and had something to contribute*, and the caller names them
in the log. The report is not only in the log: the output file carries

```
[page 4: image with no text layer — not OCR'd, re-run in Searchable PDF mode to read it]
```

where the page would have been. A log line is invisible to a script and to
anyone reading the `.txt` a week later, and the whole defect is that the artifact
looks complete. The gap is now in the artifact.

**A page with no text and no image is not reported.** `Flattener.pageIsAnImage`
is the discriminator, the same one C17 leans on: an empty leaf or a blank verso
is not a loss, and warning about those would train people to ignore the warning
that matters.

**The fix broke the all-scan refusal, and the existing test caught it.** With
markers in the body, `body.isEmpty` was never true again, so a pure scan stopped
throwing `noTextFound` and published a file of apologies — a new instance of
exactly this defect, introduced by its own fix, which is the pattern this
register keeps recording. The guard now tests whether any *real* text was
extracted, not whether the body is non-empty. `FAIL extracting from a scan fails
loudly rather than writing nothing` is what caught it.

Guarded by six checks built on a mixed fixture — three born-digital pages plus a
scanned plate appended — including one confirming `hasDigitalText` still flags
the file, since that is what makes this the default route and the silence
dangerous.

### C20 · `headroom` and `rightLimit` disagree about "the same line", crushing runs to sub-point height — FIXED
*(2026-08-09 review; measured on the corpus, not reasoned)*

`Sources/SearchableWriter.swift:618`. The two mirror functions classify a
neighbouring fragment by drawn-baseline distance using incompatible tests:

| | same-line test |
|---|---|
| `rightLimit` (651-652) | `abs(dBaseline) < min(myHeight, otherHeight) * 0.4` — ~3.6 pt for 9 pt text |
| `headroom` (617-620) | horizontal overlap `> 1` pt **and** `gap > 0.5` pt |

Everything in the band `0.5 pt < dBaseline < 0.4 * min(h)` satisfies both, so one
fragment pair is simultaneously shrunk by the reserve (correct, it is the same
line) and crushed by the ceiling (wrong, it is treated as a vertical neighbour).
The band is easy to land in: `drawnBaseline = boxBottom + 0.22 * h`, so two
fragments sharing one true baseline differ by `0.78 * descent` whenever one has a
descender and the other does not. C18's own overlap tolerance is what opens the
door — it established that Vision's boxes "routinely overlap by a point or two",
and overlaps in (1, 2] pt clear `headroom`'s `> 1` test.

Measured by replaying both functions over real recognition output for
`testdocs/magazineArticle/HarpersMagazine-1938-05-0019577.pdf` (10 pages): **eight
observations across four pages** have `headroom`'s `nearest` set by a neighbour
that `rightLimit` calls the same visual line. Worst case, "Ily names" against
"synonymous with highly" — boxes overlapping 1.91 pt, baselines 1.06 pt apart —
gives `ceiling = 1.06/1.5 = 0.71 pt` against a natural `height * 0.86` of 9.04 pt.
`draw` then caps the size at `0.71/0.25 = 2.83` against a `widthSize` near 10, so
the run is drawn at roughly a quarter of its box width and 0.71 pt tall.

That is invariant 3's third property — runs span the ink — and it is exactly the
line-end selectability C18 exists to protect. It hides from the corpus scores
because a run that short cannot weld two words together, so `words=` stays clean
and only the line-end column moves.

The existing guard cannot see it: "adjacent fragments of one line keep their
space" builds every fragment through `func frag` at a fixed `y: 0.30` and
`height: 0.022`, so every pair has `gap == 0` and `headroom` never participates.

**Fix:** one `isSameVisualLine` predicate, used by both functions. There were two
definitions and the band between them was classified as *both*; a single one
cannot disagree with itself. `sameLineBaselineFraction` (0.4 of the shorter box's
height) is `rightLimit`'s rule, kept because it is the measured one — the shorter
height, not the taller, is what stops a display numeral claiming a body line two
rows away.

**Measured over the whole 84-document corpus, before and after** — the gate
CONTRIBUTING requires for anything geometric, with the comparison binary built
from the previous commit:

| property | before | after |
|---|---|---|
| line-end selectability | mean 98.90 | **99.58** — 27 documents better, **0 worse** |
| line-start selectability | mean 99.69 | 99.69 — unchanged |
| word retention | mean 99.74 | 99.79 — 4 better, 0 worse |
| text-layer offset | median −0.10, max 0.10 | unchanged; one document moved |
| runs colliding vertically | 74 of 5,564 pairs | **74** — identical |

All four properties of invariant 3 hold, and the one the defect attacked improved
without costing any of the others. Biggest movers on line-end: 93→100, 94→100,
95→100. 84/84 still process.

**The unit test took three attempts to bite, and both failures are the kind this
register exists to record.**

1. The first probe measured selectable width at one fixed row. A crushed run is
   about a point tall, so the probe missed it entirely and reported `0.000` for
   the fixed build too — a check that fails in both directions is not a check.
   It scans rows now.
2. The second scanned x as far as `0.400`, but the *neighbour* fragment starts at
   `0.39755`. Any hit there is the neighbour's text, so the probe called the line
   fully covered however badly the first run was crushed. It stops at `0.390`.

With the guard removed, the finished check reports `selectable only to 0.135 of
the page; its box ends at 0.400` — the run reaching barely a ninth of its box.
Note that "the two words do not weld" passes either way, which is exactly the
self-concealment described above: a run that short cannot weld, so `words=` stays
clean and only line-end moves.

### C21 · A half-specified outline destination on a quarter-turned page keeps the fabricated coordinate — FIXED
*(2026-08-09 review; confirmed by tracing the transform both ways)*

`Sources/SearchableWriter.swift:397` and the mirror at `:494`. When PDFKit reports
only one member of a destination point — the `/FitH` case, which R19 measured at
276 against 80 fully-specified across the corpus — both `readOutline` and
`copyOutline` substitute `0` for the missing member, call `mapToOutput`, then keep
only the member that was originally specified.

That is sound while the transform is axis-aligned. At `/Rotate 90` and `/Rotate
270` it is not: `Flattener.fullBox` swaps the dimensions, so for MediaBox
`[0 0 612 792]` at 270 the transform is `(x,y) -> (792 - y, x)` and at 90 it is
`(x,y) -> (y, 612 - x)`. The kept axis is then computed **from the substituted
zero**, and the one coordinate the destination actually carried lands in the
member that gets discarded.

A `/FitH 700` bookmark on a 270-rotated plate page yields `moved = (92, 0)`, so
`top = 0` and the published bookmark is `/XYZ null 0 null` — the viewer scrolls to
the foot of the page, which is the symptom R19 fixed for the `/XYZ 0 0` case. The
heading's real output position, `x = 92`, was computed two lines earlier and
thrown away. At 90 the same substitution gives `top = 612`: benign-looking, and
equally unrelated to the source coordinate. The clamp at `:440-441` does not fire,
because 0 and 612 are both on the page.

Low severity only because it needs a rotated page *and* an outline entry pointing
into it. The three `mapToOutput` checks at `Tests/main.swift:1934-1962` all pass
fully-specified points, and the 90-degree one asserts only that the result stays
on the page; "half-specified destination keeps the half it has" at `:2062` hands
`JBIG2.assemble` a hand-built `OutlineItem` and never reaches `mapToOutput`.

**Fix:** `mapSingleAxis` asks the transform which output axis the specified
source axis actually drives — `x' = a·x + c·y + tx`, `y' = b·x + d·y + ty`, so a
source y contributes `c` to x' and `d` to y' — and keeps that one. The other
member stays unspecified rather than carrying a value derived from a substituted
zero. Under a quarter turn a `/FitH` becomes a horizontal destination, which is
what the geometry means. Both routes use it: `readOutline` and `copyOutline`.

Reproduced by putting the old rule back, and the numbers are exactly what the
diagnosis predicted:

```
FAIL /FitH on a 90-rotated page  — kept top=612.0, the real coordinate is x=700
FAIL /FitH on a 270-rotated page — kept top=0.0,   the real coordinate is x=92
```

`top=0.0` is `/XYZ null 0 null`: the foot of the page, which is the symptom R19
fixed for the `/XYZ 0 0` case, arriving again by a different route.

Nine checks, including two that hold the unrotated behaviour still — a `/FitH`
stays vertical and lands within 2 pt of where it did, and a `/FitV` stays
horizontal — because the risk in a change like this is fixing the quarter turns
by breaking the 90% of pages that are not turned at all.

No text-layer geometry was touched, so invariant 3's four properties are not in
play; the text-layer checks pass unchanged.

### C22 · `deduplicated` deletes a distinct line whose text repeats in a tightly-set row — FIXED
*(2026-08-09 second review; pre-existing, and the only unreported line-drop in the writer)*

`Sources/SearchableWriter.swift:640`. `deduplicated` drops an observation that
repeats an already-kept one's text within one line height **in both axes**:
`dx < h && dy < h`, where `h` is the candidate's own box height and `dy` is the
distance between the two boxes' tops — the row pitch.

So the test is satisfied by two *different rows* whenever the source is set
closer than its boxes are tall. That is not hypothetical: D3 measured 74 of 5,564
adjacent horizontally-overlapping pairs across the old corpus sitting at a pitch
below 0.6 x the upper box's height, in 23 of 84 documents — and the widened
corpus puts it at 295 of 14,782. `deduplicated`'s threshold is the looser
`pitch < 1.0 x height`, so it fires at least that often. The horizontal half is
free in an aligned column: identical text has identical width, so identical left
edges.

The drop happens in `compose` before `draw` is ever reached, so there is no
`Unplaced`, `skipped` stays empty, `produced == expected` holds, and the file
publishes as `.succeeded`. **Every other line-dropping path in the writer reports
its reason and fails the file. This one is silent** — invariant 1, in the one
place the register has never looked.

Measured on real Vision output: a 20-row table with `1,000` repeated loses 11-14
observations per page at leadings of 11 to 14 pt. In the corpus, `Casey_1954`
loses `61,511.92` and two rows reading `Stock option`.

The intent is sound and stays — C4 exists because `auto`'s partitioned pass
really does emit the same line twice, and that duplicate sits essentially on top
of its twin. The threshold is what is wrong.

**Fix:** the vertical test becomes `dy < h * duplicateBaselineFraction` (0.3).
A twin from the partitioned pass is co-located to within rounding, so the
tolerance only has to survive sub-point jitter; below 0.3 of a box height two
rows would have to overlap by seventy per cent, which is not typesetting. The
horizontal half keeps its full line height — that was always about telling a
running head from the body text under it, and it was never the problem.

Reproduced first, with four rows of a column repeating one figure at 12 pt
leading in 13 pt boxes: **kept 2 of 4**. Five checks now cover both directions —
the column survives, a 10 pt leading in a 13 pt box survives, and an exact twin,
a twin differing only by rounding, and a running head repeating a body phrase all
still behave as C4 requires.

**Corpus, all 232 documents:** 232/232 process, word retention mean 99.76 →
99.78 (4 better, 0 worse), line-end 99.55 → 99.56 (1 better, 0 worse),
line-start 99.71 → 99.72 (1 better, 0 worse). **Nothing regressed on any
measure.** The corpus is weak evidence *for* this fix rather than against it: it
samples three pages a document, so an aligned column of repeated figures is
rarely in the sample. The unit checks are the evidence that the defect is gone;
the corpus is the evidence that closing it broke nothing.

### C23 · C13 recurs on the default route: the rebuilt copy displays what the original hid — OPEN
*(found 2026-08-14 by the repaired release gate, minutes after T9 made it able to see pixels)*

**C13 is fixed in `compose`, and `compose` cannot fix it on any rebuild route.** C13's harm
was a published page carrying **no crop box at all**, so margin notes and running heads the
viewer had been hiding became visible — and because the recogniser only ever sees the crop
(C7), that revealed ink carries no text layer. Its fix made `compose` write both boxes:
"media box for what is *kept*, crop box for what is *shown*."

**But `compose` reads its boxes from `visible`, and on any rebuild route `visible` is the
rebuilt file, which has already lost the crop box.** `Flattener.flatten` writes
`kCGPDFContextMediaBox` and nothing else (`Flattener.swift:617`), so the crop box is gone
before `compose` is reached and its "write both" is writing the media box twice. The JBIG2
route then takes its geometry from `JBIG2.assemble` instead, whose page dictionary is one
hand-written line with no `/CropBox` at all:

```
<< /Type /Page /Parent 2 0 R /MediaBox [ 0 0 \(w) \(h) ] … >>      JBIG2.swift:284
```

**So every rebuild route reproduces C13, not only the JBIG2 one** — a first version of this
entry scoped it to `JBIG2.assemble`, which would have sent a maintainer past the Flate rebuild
where the same thing happens for a different reason. (`Flattener.swift:412` is the other
`beginPDFPage`, in `wrapImage`, and it is *not* affected: its input is a bare raster image,
which has no crop box to carry.) The non-rebuild route is the only one that keeps the crop box,
and it is the one C13's test covers.

C10's own entry records the property as harmless — "every rebuilt file carries only a media
box" — on the evidence that the boxes usually coincide. They do usually; the entry never asked
how often they do not.

**Rendered, not argued.** `Boltanski_2006_On justification`, page 23, through the shipped
pipeline at defaults:

```
             crop box            media box       darkness of what a reader sees
source       779x628 at (45,81)  1031x727 at 0   0.12349
output       1031x727 at (0,0)   1031x727 at 0   0.31320
```

The output's extra ink is the scanner's black gutter down the right and bottom edges of the
sheet, which the original's crop box hides. It is not lost content — it is *gained*
content, unsearchable, and 2.5x the page's ink. This is why the repaired gate reported 177
false blocking findings before it was told to read the media box on both sides: a third of
this document's sheet is a region the two files disagree about showing.

**How much of the corpus.** Measured over all 233 documents and 16,987 pages, counting a
page whose crop box hides more than 0.5% of its media box:

```
documents  14 of 233
pages     577 of 16,987
worst      34.7% of the sheet hidden   Boltanski   crop 779x628 of media 1031x727
then        8.8%  Canby_1929 · 7.4%  Zarifa_2008 · 6.6%  ppf_description
```

**Not fixed here.** The fix is a `/CropBox` carried through `Flattener.flatten`'s
`beginPDFPage` (so the Flate rebuild keeps it and `compose` has something real to copy) and
written into `JBIG2.assemble`'s page dictionary, in the rebuilt page's own coordinate space —
which means putting the source crop rect through the same transform
`SearchableWriter.cropRegion` uses, since the rebuild bakes `/Rotate` in and swaps the box.
That is a geometry change on the default route, it needs the invariant-3 probes and a corpus
run behind it, and C13's own entry records that the obvious check for it does not work:
re-OCRing the published copy cannot prove the hidden ink survived, because the recogniser
renders the crop and would only ever report what is displayed. The test has to lift the trim
off a throwaway duplicate first.

## Robustness and correctness of reporting

### R1 · jbig2 and qpdf children are never registered for cancellation — FIXED
**Fix:** `JBIG2.encode` and `JBIG2.overlay` take a `register` callback and
`makeSearchablePDF` passes `control.adopt`, so Cancel reaches the merge.
`Sources/JBIG2.swift`, `encode` and `overlay` build `Process` objects without
`control.adopt`. Cancel cannot interrupt them; on a large book the qpdf merge is
the slow step and Cancel appears dead for its duration. Quitting the app orphans
the child.

### R2 · `runStreaming`'s read loop cannot be interrupted — FIXED
`Sources/Runner.swift`. The loop exited only on stdout EOF, never checked
cancellation, and `terminate()` reaches only the direct child. Verified: a child
that exits immediately but leaves a `sleep 8` holding stdout, cancelled at 1.0s →
returned after 8.28s reporting success. A descendant that never exits left the
batch stuck on "Running…" with Cancel already spent. No SIGKILL escalation.

The second review found this is **three** unbounded waits on one path, not one:
the read loop, `process.waitUntilExit()` straight after it, and no escalation
anywhere.

**Fix:**
- The read loop uses `poll(2)` on a non-blocking descriptor with a 200 ms
  timeout, so it wakes regularly, notices the cancellation and abandons the pipe
  instead of waiting for a grandchild to close it.
- `Runner.wait(for:upTo:)` bounds the post-loop wait at 5 s.
- `Runner.stop(_:graceSeconds:)` escalates SIGTERM → SIGKILL. Descendants still
  are not reachable by PID, but killing the child closes its pipe ends, which is
  what unsticks the caller.
- A read interrupted by cancellation now returns `.cancelled` rather than
  inspecting an exit status that never arrived.

Guarded by "cancelling interrupts a wedged read" and "stop() escalates past a
child that ignores SIGTERM": the 8-second grandchild case now returns in under
3 s and reports cancelled, and a `trap '' TERM` child is killed rather than
waited out.

### R3 · `forgetToolPaths()` has no *production* caller — FIXED
*(the original title was wrong: it had two callers, both in `Tests/main.swift`,
which is why a grep looked like it disproved the entry)*

`Sources/Runner.swift`. A negative jbig2/qpdf lookup is cached for the session, so
following Settings' own "brew install jbig2enc qpdf" hint had no effect until
relaunch, while the checkbox still read on.

**Fix:** `SettingsView.onAppear` calls `Runner.forgetToolPaths()`. Opening
Settings is the right moment — it is where the install hint is read — and it costs
one login shell (~85 ms) once per open, not one per keystroke, which is the reason
the cache exists in the first place.

### R4 · Progress state keyed by file name — FIXED
`Sources/Model.swift` (`stages`, `inFlight`). Two inputs with the same name in
different folders shared a key. Verified at concurrency 2: `inFlight` held two
entries but `stages` one, fraction 0.25 where it should be ~0.5; and
`inFlight.removeAll { $0 == name }` dropped both when the first finished. The
` 2` disambiguation applied to output names was never disclosed in the log.

**Fix:** both are keyed by `URL` now — names are for display, identity is the
URL. `finish` removes the one file that finished. And a renamed output is stated:
the log adds "written as scan 2.ocr.pdf — another input claimed that name", so a
user with two `scan.pdf` inputs can tell which is which.

Display-and-reporting only: `finish` always ran once per file, so the batch could
not hang and `uniqueOutputs` already guaranteed distinct paths. Guarded by "two
inputs with the same name".

### R5 · Per-file settings re-read from `UserDefaults` on worker threads — FIXED
`Sources/Runner.swift` (`arguments`, `recognitionArguments`) and `Model.swift`
(`wantJBIG2`). `start()` deliberately snapshots settings on the main actor, but
these read them again per file off it. Settings changed mid-batch applied
unevenly.

One sub-claim in the original entry does not hold and is corrected here:
**"flipping mode mid-run" is not reachable.** The mode picker is
`.disabled(model.isRunning)` and `SettingsView` binds no control to it. The
reachable case is **text format**: the Settings sheet stays open during a run
(`ContentView` puts no `.disabled` on it), so switching Plain text → JSON
mid-batch writes JSON into the `.txt` path `uniqueOutputs` already reserved.
Password is likewise read twice by two different mechanisms, which can split one
file's own pipeline.

**Fix:** `Prefs.Snapshot` captures every per-file setting.
`OCRModel.start()` builds one on the main actor and threads it through
`Runner.arguments`, `recognitionArguments`, `jsonArguments`,
`jsonLinesArguments`, `Runner.run` and `makeSearchablePDF`/`wantJBIG2`. It
defaults to `.current()` so tools and tests stay terse, but the batch path always
passes one explicitly.

### R6 · `resetAll()` omits four keys — FIXED
**Fix:** all four added.
`Sources/SettingsView.swift`: `rebuildImages`, `rebuildMode`, `besideOriginal`,
`outputFolder`. "Reset to Defaults" cannot undo the rebuild mode.

### R7 · "Open output folder when finished" does nothing with "beside each original" — FIXED *(twice)*
`Sources/Model.swift`: skipped entirely when `destination == nil`.

**This was recorded as fixed in the first pass but the fix was never in the
code.** The second review caught it: `finishUp` still read
`if ok > 0, openWhenDone, let folder = destination`, and `destination` is
`besideOriginal ? nil : outputFolder` — nil in exactly the configuration the
setting is meant to cover. The entry described a fallback that did not exist.

**Fix (real this time):** `OCRModel.folderToReveal(destination:inputs:)` returns
the destination, or the first input's parent folder when there isn't one. Pulled
out of the closure so it can be tested without opening Finder windows; three
checks in "open-when-finished picks a folder in every configuration".

### R8 · `assemble` builds the whole PDF in memory — FIXED
`Sources/JBIG2.swift`. Peak memory ≈ output size (measured: 130 MB `Data` for
3000 pages), plus the current page's bytes, plus whatever a geometric realloc
near the end held twice.

**Fix:** `assemble` streams to a `FileHandle`, tracking a byte counter for the
xref offsets instead of measuring a growing `Data`. Only one page is in memory at
a time, so peak is bounded by the largest page rather than the whole document.
It also stages properly now: a partial file is removed on any throw, since a
truncated-but-valid PDF is precisely what invariant 2 forbids.

Measured, 1500 pages of 40 KB each → 58 MB output:

| | peak RSS growth | output | time |
|---|---|---|---|
| before | **63.1 MB** | 58.0 MB | 0.07 s |
| after | **3.4 MB** | 58.0 MB | 0.08 s |

18x less memory, and the two builds produce **byte-identical** files
(`cmp` clean; `qpdf --check` reports no errors).

### R9 · Picture-page JPEGs are held in scratch for the whole run — WONTFIX
*(the entry misdescribes the code; following it literally would corrupt output)*

`Sources/Model.swift`. The claim was that "only bilevel PNGs are deleted eagerly,
so the per-page discard optimisation is defeated for picture-heavy documents".

The asymmetry is real but it is not a defect. For a bilevel page the PNG is an
**intermediate** — `JBIG2.encode` turns it into a `.jbig2` stream and the PNG is
deleted, but the stream file itself is kept. For a picture page the `.jpg` **is**
the stream; there is no intermediate to delete. `JBIG2.assemble` reads every
stream at the end of the run, so deleting them early would produce a PDF with
missing pages. Both routes keep exactly one file per page.

The one genuinely reducible copy — the Flate rebuild holding the same bytes again
— is already deleted before `assemble` runs (`Model.swift`, right after the text
layer is composed). Peak scratch is therefore one stream file per page, which is
inherent to assembling at the end.

R8's streaming rewrite is the real memory win here, and it has landed.

### R10 · Each picture page's JPEG is encoded twice — FIXED
`Sources/Flattener.swift`: `jpegImage` for the PDF and `jpegData` for the file,
plus a discarded 1-bit threshold pass. `jpegImage` was itself encoding to JPEG
and decoding straight back, so the same buffer was encoded twice.

The scope is narrower than the title suggests, and worth recording: the double
encode only happened when `pngDirectory != nil` — i.e. JBIG2 enabled, mode
`.auto`, and the page classified as a picture.

The discarded threshold pass was justified in a comment as necessary because "its
ink coverage is what identifies a picture". That was wrong: `isPicture` reads the
**grey** buffer, not the bilevel image. The pass was pure waste on exactly the
pages that also pay for a JPEG.

**Fix:** `Flattener.jpeg(from:width:height:quality:)` encodes once and returns
both the bytes and an image over those same bytes — which also makes "the
compressed build and the fallback build are identical" true by construction
rather than by intention. And the picture decision is now made *before* anything
is rendered, so no bilevel image is built for a page that will not use one.

Measured on a 23-page report with 11 picture pages: 5.17 s → 4.85 s (~6%).
Documents with no picture pages are unchanged, as expected.

### R11 · Dead code: `Model.rebuild(_:mode:isCancelled:progress:)` — FIXED
**Fix:** removed.
No callers.

### R12 · `JBIG2.assemble([])` writes a structurally invalid PDF — FIXED
`qpdf --check` reports `ERROR: vector` while `assemble` reported success.
Unreachable from `makeSearchablePDF`; API robustness only — but "returns a file
nobody can open and calls it a success" is the shape invariant 1 forbids.

**Fix:** `assemble` throws `Failure.noPages` on an empty array and writes nothing.
Guarded by "assembling no pages is refused" in `Tests/main.swift`.

### R14 · Cancel on the JBIG2 route was reported as a failure — FIXED
*(found in the second review)*

`Sources/Model.swift`. Cancelling reaches the jbig2 and qpdf children as SIGTERM
(R1 made sure of that), so they exit 15 and `JBIG2.encode`/`overlay` throw. Both
`catch` blocks in `makeSearchablePDF` reported `.failed` — "jbig2 exited with code
15" — and returned before ever reaching the `control.isCancelled` guards below
them. `Runner` has always got this right for mac-ocr; the JBIG2 route did not, so
pressing Cancel on a large book produced a red failure line.

**Fix:** both catches check `control.isCancelled` first and report `.cancelled`.

### R15 · JBIG2 children were adopted and never released — FIXED
*(found by the third review; the most consequential backend defect in this pass)*

`Sources/Model.swift`. `adopt` appeared at four sites and `release` at two: the
per-page `JBIG2.encode` and the `JBIG2.overlay` never released. `RunControl` holds
a strong `Process`, which holds its `Pipe`, so the batch accumulated **one live
process and one pipe descriptor per page**, freed only when the batch ended.

Measured against the shipped code: +1 fd per page, exactly linear — 14/24/34/44/54
fds after 10/20/30/40/50 encodes, and flat at 54 once released. A
LaunchServices-launched app starts at `RLIMIT_NOFILE` 256 and Foundation raises it
to 2560 on the first `Process.run()`, so a batch dies at roughly **2,300 pages**.
This project's own corpus is 78 documents and **4,992 pages** — select all, drop,
Start, and descriptors run out around document 40, after which every remaining
file fails with "Bad file descriptor" and the bogus "The result had -1 pages".

Invariant 1 holds throughout — every path throws and is reported, and the
page-count guard blocks publication — so nothing damaged is published. It is a
throughput and reliability failure, not a content one.

**Fix:** `RunControl.adopting { register in … }` adopts whatever the body
registers and releases it on the way out, making the pairing structural rather
than a thing each call site must remember. Both JBIG2 sites use it.

Guarded by "adopting releases every child it takes": 50 children, asserting
nothing is still held.

### R16 · Extract Text mode could not be cancelled and could wedge — FIXED
*(found by the third review)*

R2 bounded every wait in `runStreaming` — and left `Runner.run`, which is the
whole Extract Text path and the app's **default mode**, with an unbounded
`readDataToEndOfFile()` followed by an unbounded `waitUntilExit()` and no
cancellation check at all. A child that ignored SIGTERM, or a descendant holding
stderr, wedged the worker permanently with Cancel already spent.

**Fix:** the same shape as `runStreaming` — `poll(2)` on a non-blocking
descriptor with a 200 ms timeout, a cancellation check each pass, a bounded wait
and `Runner.stop`'s SIGTERM→SIGKILL escalation. Guarded against a
`trap '' TERM; sleep 30` child: returns in under 5 s and reports cancelled.

### R17 · Reading `terminationStatus` after a best-effort wait could abort the process — FIXED
*(introduced by R2, found by the third review)*

`Process.terminationStatus` raises an ObjC exception when the child has not
exited, and an ObjC exception is not catchable from Swift — it terminates the
process. R2's `if !wait(for: process, upTo: 5) { stop(process) }` is best-effort
by construction, and the next line read the status regardless.

**Fix:** both `runStreaming` and `run` track whether the child actually exited and
report "mac-ocr stopped responding and could not be terminated" rather than
reading a value that does not exist. Related: a run the app killed itself printed
nothing to stderr and was reported as a bare failure with an **empty message**;
both paths now fall back to the exit code.

### R18 · A batch could plan to overwrite one of its own inputs — FIXED
*(found by the third review)*

`uniqueOutputs` guaranteed outputs were distinct from each other but not from the
**inputs**. Re-running a folder that already holds a previous run's results puts
both `scan.pdf` and `scan.ocr.pdf` in the batch, and `scan.pdf` claims
`scan.ocr.pdf` as its destination — a path another worker is concurrently reading.
At the default concurrency `publish` could replace that file mid-read.

**Fix:** `claimed` is seeded with every input path, so the collision resolves to
`scan 2.ocr.pdf`. Guarded by "no output overwrites another input in the same
batch".

### R19 · The document outline was dropped from the copy — FIXED
*(annotations deliberately out of scope)*

`compose` builds a fresh `CGContext` and reproduces each page with `drawPDFPage`,
which copies page **content** only. **11 of the 78 corpus documents carry an
outline**, and none of them kept it.

**Annotations are not copied and will not be.** Links, highlights and form fields
are a far larger surface, each with its own coordinate space to remap, and nothing
downstream depends on them.

> **Superseded 2026-08-14.** A reader's marks *are* carried now —
> `Sources/Annotations.swift`, behind *Keep highlights and notes*, off by default. The
> sentence above was right about the size of the surface and wrong about the conclusion:
> 9% of a working library carries somebody's marginalia, which made the sweep impossible
> rather than merely incomplete. It was also right about the coordinate space, and that
> is the part this entry deserves credit for — two review rounds found that the rebuilt
> page's space is *not* always the source's, and both defects were exactly the remapping
> this sentence predicted. See R58.

The two output routes need different mechanisms, because CoreGraphics cannot write
an outline at all:

- **Flate route** — `SearchableWriter.copyOutline` rebuilds it with PDFKit and
  writes a separate file, verified for page count before use, falling back to the
  composed file on any surprise. Losing an outline must never cost the user their
  OCR.
- **JBIG2 route** — written into the catalogue of the PDF `JBIG2.assemble`
  hand-writes, *before* the merge. `qpdf --overlay` keeps the base document's
  catalogue, and the assembled images PDF is that base, so the outline survives
  without anything re-reading or re-writing the file.

**Why the second route could not just use the first.** A PDFKit rewrite
re-encodes every image stream, and JBIG2 does not survive it. Measured on three
pages of `Toffler - 1980`: 374 KB carrying `/JBIG2Decode` became 467 KB with none
— extrapolating to roughly doubling a 600-page book. Writing the outline into the
assembled catalogue instead costs **nothing**:

| document | without an outline | with one | difference |
|---|---|---|---|
| `Toffler - 1980` | 383,128 B | 383,353 B | **+225 B** |
| `Caute 2003` | 101,592 B | 101,817 B | **+225 B** |

`/JBIG2Decode` present in every case. The cost is the outline objects themselves
and nothing else — 225 bytes for a one-entry outline, against +93,000 for the
PDFKit route on the same file.

*(An earlier version of this entry said "identical byte counts". That was a
rounding artefact of measuring in KB, caught by review. The measurement above is
in bytes.)*

`JBIG2.assemble` numbers the outline objects after the page objects so page
numbering is untouched, and `flatten` resolves `/First`, `/Last`, `/Prev`, `/Next`
and `/Count` in one depth-first pass — every one of those needs numbers that do
not exist until the whole tree is laid out. Titles go out as UTF-16BE hex when
they are not plain ASCII, because archival material is full of dashes and accents
that a Latin-1 literal would mangle. A destination past the end of the document is
dropped rather than written as a dangling reference.

Guarded by "the document outline survives OCR": 15 checks covering both routes,
labels, nesting, destinations, that JBIG2 is still present on the compressed
route, that the text layer is unharmed either way, and that a source with no
outline still publishes normally.

**A fourth review pass over this code found eight more defects in it** — the
outline work is hand-written PDF, which is the riskiest thing in the project, and
it did not survive contact with an adversarial reading:

- every `/Fit`, `/FitH` and `/XYZ null` destination was rewritten as `/XYZ 0 0`,
  landing the reader at the *bottom* of the page. PDFKit reports all three as
  `kPDFDestinationUnspecifiedValue` (3.4e38), which `isFinite` admits and the
  coordinate formatter then clamped to 0. **276 `/FitH` + 19 `/Fit` + 1 `/FitR`
  destinations across the corpus, against 80 with explicit coordinates** — so the
  majority of real bookmarks were wrong;
- destination-less entries were given a fabricated `/Dest` to page 1, once they
  started being kept;
- **destinations were copied verbatim into a page whose coordinate space the
  pipeline had rewritten.** Every page is republished derotated at the origin, so
  a `/Rotate 180` heading at (72, 700) belongs at (540, 92), and on a `/Rotate 90`
  page y=700 falls off a 612-tall box entirely. `mapToOutput` now sends the
  destination through the same `getDrawingTransform` the ink goes through, and
  clamps to the page rather than emitting an off-page destination a viewer would
  silently ignore;
- **`readOutline` recursed without bound.** ~1,200 levels exhausts a 512 KB
  `OperationQueue` worker stack, and a stack overflow is not catchable — a
  malformed or hostile PDF killed the process and every *other* file in the batch
  with it. Bounded at 32 levels (the corpus's deepest is 3) and 20,000 entries;
- `pdfString` emitted DEL (U+007F) raw into a string literal; `coordinate`
  guessed `"0"` instead of `null`; and `readOutline`'s keep-rule disagreed with
  `copyOutline`'s, so a blank-titled entry with a real destination was dropped on
  one route and kept on the other.

**Four things looked broken during this work and were not** — worth recording,
because each cost real time and every one was the instrument:

1. `qpdf --overlay` appeared to drop `/Outlines` from the catalogue. It does not;
   qpdf sorts dictionary keys, so `/Outlines` precedes `/Type`, and a regex
   anchored at `/Type /Catalog` cut it off. Ask `qpdf --show-object` instead.
2. The first outline probe "passed" by grepping the bytes for `/Title` — which
   finds orphaned objects just as happily as reachable ones. Reachability is the
   property that matters.
3. The pipeline test read `PDFDocument(url:)?.outlineRoot` without holding the
   document. `PDFOutline` does not own its document, so the tree collapsed to a
   childless root the moment the temporary was released — indistinguishable from a
   genuinely broken outline.
4. A standalone probe crashed with SIGTRAP and no output, which looked like a
   crash in `wrapImage`. It was `String(format:)` with `%@` and a Swift `String`,
   plus block-buffered stdout swallowing the prints before the fault.

### R20 · Three small robustness gaps — FIXED
*(third review; all three verified, all three now closed)*

- **The stderr drain thread could outlive `runStreaming`.** It sat in
  `readDataToEndOfFile()`, which returns only when every writer closes — including
  any grandchild that inherited stderr, the exact case the stdout loop exists to
  escape. Each cancelled file stranded a dispatch thread and a pipe. The drain now
  polls the same way the stdout loop does and is stopped by a `defer`, so it
  cannot outlive the call that started it.
- **`JBIG2.assemble` guessed US Letter for a bad page box.** `trim` substituted
  `"612"` for anything non-finite or out of range, so a page reporting a malformed
  `0x0` box produced an image page silently resized to Letter while the text layer
  kept the real geometry. `trim` returns nil now and `assemble` throws
  `badPageBox` — C12 and R12 both landed on refusing rather than guessing, and so
  does this.
- **`flatten` allocated `width * height` with no ceiling.** A Swift array that
  cannot be allocated is a **crash**, not a catchable error, so one enormous sheet
  took down every file in flight. It now refuses past `maximumPageMegapixels`
  (400) and names the page, its size and its DPI — a refusal rather than a
  downscale, per the R13 decision. 400 MP is ~19x the largest page in the corpus
  (21.5 MP) and a 33x44 inch sheet at 600 DPI, so it does not reject real archival
  material; measured across all 4,992 corpus pages, none exceed 100 MP.

### R21 · Cancel could not kill a grandchild — FIXED
*(and the entry that described it was wrong about why)*

`Sources/Runner.swift`. TODO.md recorded this as "SIGTERM then SIGKILL goes to
the direct child only; a grandchild holding a pipe survives", with the fix being
`posix_spawn` with `POSIX_SPAWN_SETPGROUP` — "a real piece of work". Reasoned,
not measured. Measuring it changed both halves.

Foundation **already** launches each child as its own process-group leader, and
a grandchild inherits that group:

```
child pid=31398  child pgid=31398  grandchild pgid=31398
```

And `Process.terminate()` signals the whole group, not the pid — a plain
`kill(pid, SIGTERM)` on the same fixture leaves the grandchild running, while
`terminate()` takes both down. So the co-operative case was never broken, and
the rewrite the entry called for was not needed.

The hole was the escalation, which is to say the one path that exists precisely
for children that do not co-operate. `kill(process.processIdentifier, SIGKILL)`
reaches one process. Measured on a child that traps SIGTERM and holds a
backgrounded `sleep`:

| | child | grandchild |
|---|---|---|
| old `stop` | killed | **survives**, reparented to launchd |
| new `stop` | killed | killed |

**Fix:** `Runner.processGroup(of:)` returns the child's group only when the child
really leads a group that is not ours — the `group == pid` test is what stops
`kill(-group)` from taking the app down with the batch, and if a future
Foundation stops making children group leaders it returns nil and `stop` falls
back to signalling the pid, which is what it did before. `stop` then SIGKILLs the
group rather than the pid, and sweeps the group once more on the way out, since a
descendant that ignored SIGTERM outlives a child that did not.

Guarded by "cancel reaches the whole process tree" in `Tests/main.swift`, which
checks the group structure before drawing conclusions from anything dying, and
proves the SIGTERM-trapping fixture leaks under the old code and not the new.

Two things left standing, both deliberate. The group is swept once more after a
child that *did* exit on SIGTERM, so there is a window — bounded by
`graceSeconds`, two seconds — in which a recycled group id could be signalled;
that needs on the order of 99,000 process spawns in two seconds, and the
alternative is leaving orphans. And `RunControl.cancel()` still calls
`terminate()` directly rather than `stop`, which is correct because
`terminate()` reaches the group: a child that ignores SIGTERM is then escalated
by whichever read loop notices the cancellation and calls `stop`.

### R22 · The stderr drain woke 5 times a second for the life of every run — FIXED
`Sources/Runner.swift`. R2 replaced `readDataToEndOfFile` with a `poll` loop —
correct, because that call waits for *every* writer to close and the writers
include any grandchild that inherited stderr. But the loop then woke every 200 ms
for the whole of each run purely to notice a stop flag, and at a dozen files in
flight that is sixty wakeups a second doing nothing.

**Fix:** a `DispatchSource` read source, which is idle until bytes arrive;
`cancel()` replaces the flag. Cancellation is asynchronous and the descriptor is
closed when the `Pipe` goes out of scope, so the defer cancels and then does a
`sync` barrier on the (serial) drain queue — a handler still in `read()` on a
closed descriptor is undefined behaviour, and that is the one way this change
could have been worse than what it replaced.

Partial stderr now survives a timeout, too: the old drain only published its text
once the loop ended, so a drain that had to be abandoned reported nothing.

### R13 · Poor photocopies cost ~720–920 KB/page — WONTFIX *(decided: fidelity)*
Pages that are 30–70% mid-tone route to greyscale, which is right for legibility
but expensive.

**Decision: fidelity wins. No DPI cap, no downscale.** Output is the artefact the
user keeps and this is an archival pipeline — a page is rendered at its own
resolution or not at all. The size cost is accepted. The same decision settles the
unbounded-allocation half of R20: `flatten` refuses an impossible page rather than
shrinking it.

Two corrections to the original entry, both from the second review:

- "the current quality-only lever" **does not exist**. `Flattener.jpegQuality` is
  a defaulted parameter (0.6) that no caller overrides and nothing in Settings
  reaches, so there was no user-facing size control to replace.
- The routing itself is not in question. `toneFraction > 0.12` sending photocopies
  to greyscale is correct — thresholding them destroys content, which is the
  mistake that produced the Otsu work in the first place.

An earlier attempt to measure the trade is recorded because the instrument was
wrong, which is this project's most repeated lesson: a harness that flattened each
document twice reported the "capped" build coming out *larger* (+46%, +102%),
because `Flattener` has no cap hook and the harness emulated one by rendering
every page through `Flattener.jpeg` — forcing greyscale onto the text pages the
real routing sends to 1-bit. It compared greyscale-everything against per-page
routing, not capped against uncapped.

### R23 · `copyOutline`'s `rebuild()` has neither bound its mirror has — FIXED
*(2026-08-09 review; confirmed by reading both functions side by side)*

`Sources/SearchableWriter.swift:480`. `readOutline.convert` is bounded twice over
— `depth < maximumOutlineDepth` (32) and a shared `budget = 20_000` — because, per
its own doc comment, ~1,200 levels exhausts the 512 KB OperationQueue worker stack
and "killed the whole process with SIGBUS, taking every other file in the batch
down with it and publishing nothing". `copyOutline`'s `rebuild()` is the mirror
function on the Flate route and has **neither**: it recurses once per level over
`node.numberOfChildren` with no depth parameter and no entry budget.

The asymmetry is self-concealing. `Model.swift:1129-1131` gates the call on
`!outline.isEmpty`, and `readOutline` satisfies that for a 4,000-level chain
precisely *by truncating it at 32* — so the truncation that hides the depth is
what licenses the unbounded pass. `copyOutline` then walks `src.outlineRoot`, the
untruncated tree.

A cyclic outline, the case `budget` exists for, does not terminate at all.

R19 bounded `readOutline` only; the adjacent bullet about the two routes
disagreeing is the keep-rule, not recursion. The suite already builds the
4,000-level fixture at `Tests/main.swift:1992` and hands it to `readOutline`
alone at `:2006` — `copyOutline` is never given a deep or cyclic outline.

**Fix:** `rebuild` takes a `depth` and shares `maximumOutlineDepth` and the same
20,000-entry budget as `convert`. The same two bounds, the same numbers, in the
mirror function that should always have had them.

Reproduced by handing the suite's existing 4,000-level fixture to `copyOutline`
instead of `readOutline`. Two things were needed to make it bite, and both are
why it went unnoticed:

- **On an `OperationQueue` worker**, because the 512 KB worker stack is what
  makes the depth fatal. The main thread's 8 MB survives it, so a test written
  the obvious way would have passed against the bug.
- **In a child process**, because a stack overflow is a signal, not an error. The
  suite re-runs its own binary with `--probe-deep-outline` and reads
  `terminationReason`.

With the bound removed: `terminationReason=2 status=10` — an uncaught SIGBUS,
which is precisely the failure R19's doc comment describes and which would take
every other file in the batch with it.

A further check confirms the deep fixture still passes Model's
`!readOutline(...).isEmpty` gate, so the path really is reachable, and one more
confirms the outline is still written — bounded, not abandoned. Losing a
pathological outline costs nothing; losing the batch costs everything in it.

No geometry code was touched, so invariant 3 is not in play here; "the outline
survives and the text layer is unharmed" passes unchanged.

### R24 · The megapixel guard's own `Int` arithmetic traps before it can refuse — FIXED
*(2026-08-09 review; the API assumption was tested, not assumed)*

`Sources/Flattener.swift:391`. R20 added `maximumPageMegapixels` so an impossible
page is refused rather than crashing the process and "taking every other file in
flight with it". But the guard computes `width * height` in signed `Int`, and
Swift **traps** on `Int` multiplication overflow — the trap fires before the
comparison it guards.

The dimensions are corruption- or attacker-controlled. `rebuildDPI` puts no upper
bound on the DPI it will trust (unlike `pageIsAnImage`, which caps at 1400 for
exactly this reason — but applies the cap to `largestImage`'s *return value*, so
it cannot protect the multiplication inside it), and the DPI comes from the
`/Width` integer declared in an image XObject dictionary, never cross-checked
against the stream.

Verified rather than assumed: a hand-built PDF declaring `/Width 4000000000
/Height 4000000000` is accepted by CoreGraphics — `CGPDFDictionaryGetInteger`
returns true with 4,000,000,000 for both keys, since `CGPDFInteger` is a 64-bit
long and nothing clamps — and PDFKit opens the file with a non-nil `pageRef`. So
`Flattener.open`, `page.pageRef` and `cgPage.dictionary` all succeed and the walk
reaches the stream dictionary, where `Int(w) * Int(h)` is 1.6e19 against an
`Int.max` of 9.22e18.

Three traps on the same input:

- `:833` `Int(w) * Int(h) > found.width * found.height` — reached from the C17
  pre-flight, which runs over every file when Start is pressed, so this one kills
  the batch before a single page is rendered.
- `:391` the guard itself. Independently reachable without `:833` tripping:
  `/Width 3500000000 /Height 1` gives a product that fits, `rebuildDPI` then
  reports ~4.1e8 DPI, and `width * height` inside the guard overflows.
- `:383-384` `Int(Double)` traps for a scaled dimension outside `Int`'s range.

An arithmetic-overflow trap is not a catchable `Failure`. This is R20's own
failure mode, inside R20's own fix.

**Fix**, in two layers rather than at each multiplication:

- **Reject the implausible where it is read.** `maximumDeclaredImageSide`
  (200,000 px — a 26-inch sheet at 7,700 DPI) bounds `/Width` and `/Height` in
  the XObject walk, along with `> 0`. A declaration past that is corruption or
  hostility, not a scan, and skipping it means no arithmetic downstream can
  overflow.
- **Decide in Double, convert once.** `flatten` computes the rendered size and
  the megapixel comparison in Double and converts only after the value is known
  to be in range. `safeInt` saturates instead of trapping for anything
  non-finite or out of `Int`'s range.

Guarded by five checks, all of which need a **child process** — a trap cannot be
caught in-process, and a check that asserts "this must not take the process
down" cannot be the thing that takes it down. The suite re-runs its own binary
with `--probe-hostile-page` and inspects `terminationReason`. Before: the two
overflow fixtures killed the child. After: all pass, and "a merely enormous page
is still refused, not rendered" holds the guard to its job.

Two things measured while fixing it, both worth keeping:

- ~~**An absurd `MediaBox` is not a route to the same trap.**~~ **This was
  wrong, and R29 is the defect it missed.** The claim rested on one fixture,
  `MediaBox [0 0 1e300 1e300]`, which `PDFDocument(url:)` does return nil for —
  but *because `1e300` is not valid PDF real syntax*, not because of its
  magnitude. The measurement tested the parser, not the guard. A plain-integer
  box is legal PDF and parses fine: `[0 0 100000 100000]`, `[0 0 15000000
  15000000]` and even `[0 0 1000000000000 1000000000000]` all open with a live
  `pageRef` and `bounds(for: .mediaBox)` reporting the declared size verbatim.
  `saturation` then sizes its own buffer from that raw box and traps. Recorded
  here rather than silently deleted: this is the fifth entry in this register to
  turn out wrong as written, and the failure mode was believing a single
  negative fixture.
- **The limit is now exact.** The old comparison floor-divided by a million
  first, so a page of 400,999,999 px counted as 400 MP and was allowed. It is
  now compared against `400 × 1_000_000` directly. The corpus's largest page is
  21.5 MP, so nothing real moves.

### R25 · `largestImage`'s Form XObject walk has a depth cap but no visited set — FIXED
*(2026-08-09 review; measured)*

`Sources/Flattener.swift:851`. `walk` recurses into every Form XObject's
`/Resources`, guarded only by `depth < 4`, and keeps no record of what it has
already visited. When several forms point at the same `/Resources` dictionary —
including the page's own, which some producers emit — the same dictionary is
re-walked once per referring form at every level: `N + N² + N³ + N⁴` block
invocations instead of `N`.

Measured: a PDF with 60 Form XObjects whose `/Resources` is an indirect reference
to the page's own dictionary blew past **4,000,000 callbacks** before the probe
was aborted, against the 61 entries the page actually contains (the closed form is
13,179,660 for N = 60). CoreGraphics resolves the indirect reference and hands
back the shared dictionary every time.

The depth cap bounds recursion but not breadth. `walk` runs once per page from
`rebuildDPI` inside `flatten`'s loop and on up to four pages per file in the
pre-flight, each callback doing a `String(cString:)` allocation, so a long
document stalls with the progress bar frozen and no way to tell it from a hang.

The register's only XObject entry is the opposite defect — `nativeDPI` *not*
recursing into forms — with no note of a sharing or cycle hazard. No test nests or
shares form resources.

**Fix:** `walk` records the shallowest depth at which it has walked each
`/Resources` dictionary and skips a repeat visit at the same depth or deeper.
Identity is the resolved dictionary pointer, which is safe here because
CoreGraphics resolves an indirect reference to the same pointer every time —
that is what makes the pruning work at all, and the fan-out check would still be
red if it did not.

Guarded by the 60-form fixture: **5.09 s before, under 2 s after**, for a page
with 61 real entries. A second check confirms the pruning does not cost the
answer — the image on that page is still found.

**Depth-awareness is reasoned, not measured, and that is worth being explicit
about.** Keying on identity alone is wrong in principle: a dictionary first
reached down a long chain has its own children cut off by the depth cap, and
marking it seen there would turn away a later, shallower path that could explore
them. I could not build a fixture that demonstrates it. In every arrangement
tried — varying the key names, and varying the object numbers the keys point at
— `CGPDFDictionaryApplyBlock` handed back the branch leading to the *shallower*
route first, which is precisely the order in which identity-only pruning is also
correct. The traversal was instrumented to confirm this rather than inferred from
the results.

So the two "reachable by two routes" checks in the suite are regression guards
against pruning losing an image; neither discriminates depth-aware from
identity-only. The depth key costs one `Int` per dictionary and removes the
question, which is why it is there. If someone later finds the fixture that
splits them, it belongs here.

### R26 · `pageTooLarge` tells the user to change a setting that cannot reach the rebuild — FIXED
*(2026-08-09 review; confirmed by grep — the setting genuinely is not wired here)*

`Sources/Flattener.swift:143`. The refusal reads "Set an explicit PDF render DPI
in Settings to process it at a lower resolution." No such control reaches this
code. `rg 'Prefs|UserDefaults|Snapshot' Sources/Flattener.swift` returns nothing,
`flatten` takes no DPI parameter, and the render resolution is always
`rebuildDPI(of: page)`, which reads only the page's own largest image.
`Prefs.pdfDPI` is consumed at exactly one place — `Runner.swift:185-186`, where it
becomes mac-ocr's `--pdf-dpi` for a recognition pass that `flatten` throws before
ever reaching.

The advice is convincing because the control exists and is even labelled "PDF
render DPI" in `SettingsView.swift:158-172`. It is inert. A user who follows it
gets a byte-identical refusal.

The refusal *itself* is deliberate and stays (R13: fidelity, no downscale). The
defect is that the one setting that does let the file through — turning off
"Rebuild page images first", which makes `mustStrip || wantJBIG2` false at
`Model.swift:915` so `flatten` never runs — is never mentioned.

No test touches `pageTooLarge`.

**Fix:** the message now names the control that works and explicitly kills the
one that does not — "turn off *Rebuild page images first* in Settings. The PDF
render DPI setting does not affect this step." The numbers stay; only the remedy
changed.

Checked before writing it, rather than swapping one wrong instruction for
another: `wantJBIG2 = rebuild && settings.useJBIG2 && …` at `Model.swift:904`,
so `rebuild` gates the JBIG2 route as well. Turning that one toggle off makes
both halves of `mustStrip || wantJBIG2` false and `flatten` never runs — the
advice is sufficient on its own, with no second step about JBIG2.

Three checks on `errorDescription`: the page, size and DPI are still named; the
render-DPI setting is not offered as the remedy; and the rebuild toggle is.

### R27 · An input named `text.pdf` fails every time, deterministically — FIXED
*(2026-08-09 review; the JBIG2 half confirmed, the Flate half refuted — see below)*

`Sources/Model.swift:917`. The rebuilt page images keep the input's own file name
inside the scratch directory, while the pipeline's intermediates use fixed
literals in that same directory: `staged.pdf`, `text.pdf`, `images.pdf`,
`outlined.pdf`. Nothing checks for the collision.

For an input called `text.pdf`, `visible` and `textLayer` are one path. `compose`
reads and writes it, the layer-page gate at `:1063-1068` passes, and then `:1073`
`try? FileManager.default.removeItem(at: visible)` **deletes the text layer it is
about to merge**. `JBIG2.overlay` hands qpdf a `--overlay` path that no longer
exists, qpdf exits non-zero, and the file is reported failed with a raw qpdf
message that has nothing to do with its contents. Also `Text.pdf` and `TEXT.pdf`,
since `NSTemporaryDirectory` sits on the case-insensitive system volume.

**The Flate `staged.pdf` variant was claimed and is refuted.** `compose` reads its
source through `Flattener.open`, and PDFKit buffers the whole file at init — a
66 MB PDF still parsed a fresh page correctly after being truncated to 9 bytes on
disk — so composing a file onto itself produces correct output, not a
plausible-but-wrong one. `images.pdf` and `outlined.pdf` are harmless too, because
`visible` is spent by the time either is written.

No test drives `makeSearchablePDF` with an input named after one of the four
literals.

**Fix:** the four fixed intermediates moved to a `work/` subdirectory of the
scratch. Nothing named after the user's file is ever written there, so no input
name can collide with one.

Separating them by *directory* rather than renaming them, because renaming only
moves the collision: the rebuild keeps the input's own name, and a dropped image
called `rebuilt.png` is wrapped to `rebuilt.pdf` in the same place. One boundary
kills the class; a better set of names would only shrink it.

Reproduced first, exactly as described:

```
FAIL an input named text.pdf still succeeds — Merging the text layer failed:
qpdf: open /var/folders/…/mac-ocr-gui-1F932633…/text.pdf: No such file or directory
```

The same run confirms R28's refutation of the Flate variant from the other side:
`staged.pdf`, `images.pdf` and `outlined.pdf` all passed before the fix as well
as after. Only `text.pdf` was ever broken.

Guarded by four checks, one per reserved name, each running the real
`makeSearchablePDF` on the JBIG2 route and then confirming the published file
has a text layer — a success that published a blank layer would otherwise look
identical. The image-input variant (`text.png` wrapped to `text.pdf`) is covered
by construction rather than by a check: the suite has no image fixture helper,
and after this change no wrapped image can land on an intermediate's path.

### R28 · Three claims from the 2026-08-09 review that did not survive — NO DEFECT
*(recorded because the measurements are worth more than the claims were)*

- **"Image inputs rebuild onto their own source."** The path collision is real:
  for an image input `wrapImage` writes `scratch/<stem>.pdf`, `file` is reassigned
  to it, and `rebuilt` resolves to the same path. The claimed harm rested on
  `PDFDocument(url:)` being lazily mapped, and it is not. A 66 MB PDF opened
  through PDFKit and then **truncated to 9 bytes on disk** still returned the
  correct text for page 40, never touched before the truncation. PDFKit buffers at
  init, so `flatten` renders every page from memory and writes a correct rebuild
  over its own source. Latent fragility — it breaks the day PDFKit switches to
  `NSDataReadingMappedIfSafe` — not a live defect. Worth a comment, not a fix.
- **"Extract Text destroys a previous good output on cancel"** (raised twice, by
  two different lenses). Refuted against the real mac-ocr 1.1.1. It does not open
  or truncate the `-o` destination while it works: with a sentinel already at the
  path, polling every 0.25 s showed it unchanged for the whole of a ten-second run
  and replaced in one step at completion; SIGTERM six seconds into a longer run
  left the sentinel byte-for-byte intact; `--format jsonl` behaves identically. The
  `createFileAtPath:contents:attributes:` symbol found by `strings` is that single
  end-of-run whole-buffer write, and one `write(2)` of a modest buffer to a local
  file is not interrupted by the SIGKILL `stop` sends two seconds after SIGTERM.

  The staging asymmetry is real, is recorded in ARCHITECTURE.md, and is not a
  defect on the evidence available: a successful re-run replacing the previous
  output is what `publish` does on the searchable path too.

### R29 · `saturation` allocates from the raw page box, outside every guard R24 added — FIXED
*(2026-08-09 second review; R24's own blind spot, and R24's disproof of it was wrong)*

`Sources/Flattener.swift:725`. R24 made `flatten`'s render sizing safe by
deciding in Double and refusing past 400 MP. That guard measures the **rendered**
size — `box x dpi/72` — not the page box. `Flattener.saturation` independently
re-derives its own buffer from the raw box at a fixed 40 DPI:

```swift
let w = max(Int(box.width * scale), 1), h = max(Int(box.height * scale), 1)
var buffer = [UInt8](repeating: 255, count: w * h * 4)      // no bound at all
```

The bypass is `rebuildDPI`: it returns the largest image's implied DPI whenever
that image is at least `minimumScanPixelWidth` (600 px), so a huge box carrying
a small image yields a *tiny* scale, the render is small, and R24's guard passes
— and then `saturation` sizes off the unscaled box.

Confirmed by running the repo's own `Flattener` unmodified against hand-built
files:

- `MediaBox [0 0 100000 100000]` with one 700x700 image: `largestImage` reports
  700 px, `rebuildDPI` returns 0.504, the render is 700x700 and clears the 400 MP
  guard — then peak RSS hits **274 MB** for a 490 KB page, which is the
  8000x8000x4 saturation buffer.
- `MediaBox [0 0 1000000000000 1000000000000]`: **exit 133, SIGTRAP**, and under
  lldb the stop is `frame #0 Flattener.saturation(of:)` — the `Int` overflow of
  `w * h * 4`. Uncatchable, so it takes the whole batch, which is verbatim the
  harm R24's own comment says the guard exists to prevent.

Reached only on the `.auto` route (`mode == .auto` gates `isPicture`), which is
the shipped default. **The R24 check never exercises it**: `--probe-hostile-page`
calls `flatten(..., mode: .blackAndWhite)`, so `saturation` is skipped and the
"absurd MediaBox" case has been passing without running the code it names.

**Fix:** the sizing moves into `thumbnailSize(for:)`, which refuses a
non-finite or empty box and caps the longest edge at `maximumThumbnailEdge`
(4,000 px, so the buffer cannot exceed 64 MB). A page would have to be 100
inches on a side at 40 DPI to be resized by that — past the 200-inch ceiling
PDF ≤1.5 puts on a page box at all — so no real document is affected. The probe
now runs **both** modes, so `.auto` and therefore `saturation` is actually
executed.

**How the checks divide, stated plainly because T4 is about exactly this.**
Reintroducing the bug makes one of the five fail, not all five, and that is
expected rather than a weakness:

- `a MediaBox whose thumbnail would overflow Int does not trap` is the
  discriminating one. With the raw sizing back it fails; the child dies on
  SIGTRAP inside `saturation`.
- `the routing thumbnail is bounded on a huge page`, the Letter and E-size
  checks and the degenerate-box check test `thumbnailSize`'s contract. They keep
  passing when the bug is reintroduced, because reintroducing it *bypasses* the
  helper rather than breaking it. They are there so the bound cannot be widened
  or the no-magnify rule broken without a red check.
- `…does not exhaust memory in the picture-routing thumbnail` passes either way
  on a machine that can absorb a 256 MB allocation. It is a boundary, not a
  guard, and is labelled as one in the source.

The link between the two — that `saturation` uses the helper — is carried by
the trap check alone. That is the honest description; a check asserting the call
directly would need the buffer size observable from outside.

### R30 · `askLoginShell`'s three-second bound is on the wall clock — FIXED
*(2026-08-09 second review; introduced by U18, against advice written in the same file)*

`Sources/Runner.swift:113`. U18's new poll loop bounds itself with
`Date().addingTimeInterval(3)` and `deadline.timeIntervalSinceNow`. Three hundred
lines below, `Runner.wait(for:upTo:)` uses `DispatchTime.now()`, and its doc
comment states the rule being broken here in as many words:

> Monotonic, not `Date()`. A wall clock goes backwards and forwards — an NTP
> step, or a laptop waking from sleep — and either direction is wrong here: a
> jump forward abandons a perfectly healthy child on its next iteration, and a
> jump back extends a wait that is supposed to be bounded.

Both halves apply, and the same function uses the monotonic form eight lines
later. A forward step breaks the loop with `sawEOF == false`, so a healthy shell
is killed and `locateTool` **memoises the absence for the session** — every later
`resolveBinary`, `JBIG2.encoder` and `JBIG2.merger` returns nil without
re-probing, silently downgrading every searchable run to the Flate route. A
backward step extends the bound that exists to keep the main thread responsive.

Low, and honestly so: the exposure window is the ~90 ms the call takes (measured
0.095 s for mac-ocr, 0.105 s for `ls`). It is a one-line defect in a file that
already documents the correct answer.

**Fix:** `DispatchTime.now() + 3`, with the remaining time from a new
`secondsUntil(_:)`. `Date()` no longer appears anywhere in `Runner.swift` outside
prose.

The helper exists rather than the arithmetic being inlined because
`DispatchTime` subtraction is **unsigned**, so the obvious expression underflows
past the deadline instead of going negative — turning "time is up" into "584
years left", which is worse than the wall clock ever was. Three checks cover it,
and removing the guard produces exactly that:

```
FAIL a deadline already past reports zero, not an underflow — 18446744072.709553
```

### R31 · A failed bundling audit leaves the broken helpers in the bundle, and the build says the opposite — FIXED
*(2026-08-09 third review; introduced same day by the 1.5.0 bundling)*

`Tools/bundle-libs.py:183` and `build.sh:141`. The audit runs *after* everything
has been copied and relocated. On failure it prints "still linked against
Homebrew" and returns 1 — and **removes nothing**. `build.sh` then swallows that
exit code with `|| { echo "    (not bundled — the app will look for them on
PATH)"; }` and carries on, signing the very binaries the script just declared
unusable.

The message is the exact inverse of what shipped. The tools *are* in the bundle,
and `locateTool` consults `bundledTool` **before** `/opt/homebrew/bin`, so the
app prefers the broken copy over a working Homebrew one. Neither screen catches
it: `isRunnable` is exists + not-a-directory + executable bit, and
`containsNativeSlice` only asks for an arm64 slice. A dyld-broken arm64 Mach-O
passes both.

Reproduced under execution, not read: with a no-op `install_name_tool` shim on
PATH the real script printed `still linked against Homebrew:` with 8 entries and
exited 1, and `find` showed both helpers, all 13 dylibs and all 17 licence files
still in `Contents/Resources`. Replaying build.sh's `||` handler and signing
block then printed `(not bundled — the app will look for them on PATH)` followed
by `Resources/jbig2 present after a "not bundled" build? YES`.

The consequence chain was traced the same way. `JBIG2.isAvailable` is a presence
test, so it is true; `wantJBIG2` is on by default; `JBIG2.encode` throws on a
non-zero exit and a dyld-aborted child exits 134; `Model.swift:1126` turns that
into `report(.failed, "Could not rebuild page images: …")` with no Flate
fallback. Every document on the searchable route fails, on a machine where 1.4.0
worked, with a build log that said the tools were not bundled.

One handler covers two very different exits: "the tool is not installed"
(benign, and what the message was written for) and "the audit failed" (fatal).

**Fix:** every `install_name_tool` return code is now checked instead of
discarded; on any failure the script **removes everything it copied** before
returning, so the bundle cannot be left holding rejected binaries; and it exits
**3** for an audit failure against **1** for "not installed", which `build.sh`
now distinguishes — 1 prints a note and continues, anything else stops the build.

Guarded by `Tools/fault-inject.sh relocate` and `build_continues`, which put a
no-op `install_name_tool` on `PATH` and run the real script. Written *before* the
fix, they reproduced both halves exactly: `exited 1 but left 15 copied file(s)
in the bundle` and `audit failure exited 1; build.sh treats 1 as benign`.

### R32 · The DMG verification's failure path can swallow its own diagnostic and leaves the rejected image — FIXED
*(2026-08-09 third review, plus one instance found by hand)*

`build.sh:229`. On a failed verification the else branch runs `hdiutil detach`
**before** printing why. `detach` returns 16 when Spotlight or Disk Arbitration
still holds a freshly-mounted volume (reproduced), and under `set -e` that kills
the script at that line: nothing is printed, and the build dies with a bare
non-zero status. The rejected disk image is also left on disk, looking
shippable.

The mount leak is not hypothetical: `Vision OCR.dmg` was found **still attached**
from the 10:33 build, with a stale mount point at
`/private/var/folders/…/tmp.9siZBblc8S`. Detaching it by hand is what surfaced
this.

**Fix:** the diagnostic is printed **before** the detach; the detach falls back
to `-force` and cannot abort the script; and a disk image that fails its own
verification is **deleted**, so nothing that looks shippable survives a failed
build. The success path got the same `-force` fallback.

**And the step turned out to be intermittently wrong, which only showed up by
using it.** One release build failed verifying `jbig2` from the image, on tools
that ran cleanly three times immediately afterwards: a freshly attached image is
not always ready to `exec` from the instant `hdiutil attach` returns. The check
now retries up to three times with a second between, and reports when it had to
— which it did on the very next build (`jbig2 needed 1 retry — the mount was not
ready`), confirming the race rather than leaving it a theory. A verification that
fails intermittently teaches people to re-run builds until they pass, which is
the opposite of its purpose.

Worth recording how nearly this was missed: the failing build's diagnostic was
filtered out by the `grep` being used to watch the build, because the success
line says "runs from the image" and the failure says "did **not** run from the
image". zsh then gave the pipeline `grep`'s exit status, so the surrounding
command carried on as though the build had worked. Filtering build output hides
exactly the line you need.

**The sibling sweep found one more, which the review had not reported.** Asking
"who else mounts without cleanup?" showed the mount point had no `trap`: any
failure between `hdiutil attach` and the detach leaks it, which is this same
defect reached by a different route. A `trap release_mount EXIT` now covers the
whole section, idempotently. Stated plainly — **no fault case exercises it**; a
contrived one would be worse than saying so. It is defence in depth found by a
grep, which is what CONTRIBUTING 4b is for.

Guarded by `Tools/fault-inject.sh detach_fails`. That case is worth reading as a
cautionary tale in its own right: **the first version could not fail.** It shimmed
only `detach`, so verification succeeded, the failure branch never ran, and the
check passed while testing nothing — the T6 shape, in a case written to prevent
exactly that. It now shims `attach` to yield an empty mount *and* `detach` to
fail, and against the unfixed code it reports `exited 16 with no diagnostic`.

### R33 · Cream paper promotes every text page to colour: 33 MB in, 709 MB out — FIXED
*(2026-08-11; reported from a user's own 600-page 1964 monograph)*

A scanned book went in at 33 MB and came out at **709 MB** — 21x, 600 pages,
every one of them a full-resolution three-channel JPEG at 1.18 MB. 706 MB of the
709 MB is image streams.

The pages are plain text. Measured across the book, **ink coverage 0.099–0.114**
(threshold 0.15) and **tone fraction 0.008–0.012** (threshold 0.12) — both
signals say "text" on every page, unambiguously. Only saturation fired, at
**0.078–0.089** against a threshold of 0.06, because the paper is cream.

Then the same number was charged twice, because one constant gated two
decisions: `isPicture` took the page off the 1-bit route, and
`shouldKeepColour` — reading the same `pictureSaturationThreshold` — promoted it
from one channel to three. Measured on five real pages from the book:

| mode | route | per page |
|---|---|---|
| Automatic, as shipped | RGB JPEG | 1,185 KB |
| Grayscale | grey JPEG | 322 KB |
| Black & white | 1-bit JBIG2 | **48 KB** |

24.7x. The 1-bit rendering was checked by eye and is clean — nothing about these
pages needed the picture route at all.

**The threshold could not be moved to fix it.** Over the corpus the six
wrongly-promoted text pages spanned saturation 0.061–0.113 and the eighteen
genuinely coloured pages spanned 0.061–0.303. The two populations overlap almost
exactly, because a mean cannot distinguish a faint tint spread over a whole sheet
from a strong colour in one corner of it. Any threshold that saves the text pages
loses real colour. This is worth stating because raising the constant was the
obvious fix and it is the wrong one.

**Fix:** `saturation` now white-balances the page to its own paper before
measuring — `paperColour` takes the mean of every pixel above
`paperLuminanceFloor`, and each channel is divided by it (von Kries, scaled so
the brightest channel is unchanged). Cream paper becomes neutral and scores
nothing; an illustration on that same cream page still scores, because it was
never the paper colour. A page with less than `minimumPaperFraction` of paper on
it is left uncorrected, so a full-bleed plate does not get its real cast
neutralised by a "paper" measured from the plate itself.

**Corpus, 642 pages over 232 documents:** saturation-only promotions 6 → 3,
RGB routes 24 → 18, 1-bit 520 → 523. Seven pages moved to a cheaper route and
none moved wrongly to a dearer one. One page did move grey → RGB —
`Ford_1941_Speech_` p2 — and that is correct: it carries handwritten blue-ink
corrections and a coloured stamp, which the yellowed paper had been masking. The
three remaining promotions were each opened and looked at; all three are
genuinely coloured (an 1881 handwritten ledger photographed in colour, and two
pages with coloured print).

Two mutants guard it. `const/paperLuminanceFloor` **survived its first run** —
dropping the floor to 10.0 makes every dark pixel count as paper, which defeats
`minimumPaperFraction` and lets the correction neutralise a real cast, and
nothing tested that. The full-bleed check now exists and both mutants are killed.

### R34 · JPEG 2000 for picture pages — WONTFIX *(decided: measured, it loses)*
Investigated because a library MRC scan of the same material was 6x smaller.
`Tools/score-picture-codec.swift` is the measurement; it stays in the tree
because the conclusion depends on it.

**Rejected on two independent grounds, both measured over 120 corpus picture
pages.**

First, **ImageIO's JPEG 2000 `compressionFactor` is a compression ratio, not a
quality target.** Its output is a near-constant 0.0725 bytes/pixel at q0.20
across pages of wildly different content, where JPEG's varies 37.6x with the
page as a quality-targeted encoder should. So one constant cannot hold fidelity
steady: pages land anywhere between 23 dB and 52 dB. At every rate tried,
88–98% of picture pages came out *below* the fidelity the app already ships,
median −10.7 to −19.1 dB. Under the only safe rule — take JPX only where it is
no worse *and* smaller — it wins on 3–12 pages in 120 and saves 0.1–1.6%.

Second, and the reason the investigation started from a false premise: the
document that motivated it was a library MRC scan **whose image layer was
already JPEG 2000**. Re-encoding JPX content with JPX reproduces its own
artifacts cheaply, so JPX looked far better than it is. Isolating that one
variable, same method, same encoder:

| source page | JPEG q0.60 | JPX q0.20 |
|---|---|---|
| source layer *is* JPX | 1395 KB / 42.90 dB | 899 KB / **+1.52 dB** |
| source layer is DCT | 1128 KB / 41.41 dB | 379 KB / **−9.91 dB** |
| source layer is DCT | 8431 KB / 40.86 dB | 2640 KB / **−11.27 dB** |

This is the project's most repeated lesson arriving in a new costume: the
instrument was measuring the source's codec, not the codec under test.

**The format is not what fails — Apple's encoder is.** With real rate control,
OpenJPEG at *matched* fidelity gets 373 KB against libjpeg's 736 KB, and 3,640 KB
against 5,450 KB, on those same unbiased pages. So JPEG 2000 is genuinely
1.5–2x better here and would need a bundled encoder to reach. That is a
different proposition from the one rejected above, and it belongs with the MRC
work in FEATURES.md rather than here.

The abandoned implementation is kept as
`~/Claude/Long term storage/Preserved Worktrees/vision-ocr-jpx-picture-pages-20260811-abandoned-wip.patch`
(moved there 2026-08-13 from `../`, to keep `~/Claude/` itself clean — the path has spaces, so quote it):
it was complete
and green at 626 checks, with red→green proven for every check and four mutants
killed, before the corpus said not to ship it.

### R35 · Per-page background downsample — WONTFIX *(twice: no threshold exists, and the signal is structurally blind to a whole class of picture)*

**Second attempt, 2026-08-12 — refuted again, for a new and better reason.** The
first verdict was reached before R38, which has since moved 66 of the corpus's
98 ink-only picture pages off the picture route. Those are dense-text pages, and
they are exactly where "unboxed text counts as background tone" came from — so
the continuum might have become a gap. Nobody had looked, and looking was cheap.

*It is still a continuum.* Re-measured on the pipeline's own boxes over **320
layered pages** (against 25 the first time), the detector runs smoothly from
0.000 to 1.000 with a largest gap anywhere of **0.027**. R38 did not separate the
populations.

*But there is now a low cluster*, and a threshold at 0.10 fires on 52 of the 320
with what looks like a wide margin — Findlay's photographs score 0.2865–0.5691,
nearly three times higher. That is where the first attempt would have stopped and
shipped.

**Reading which pages it fires on kills it.** The page with the single largest
saving — `_1963_Fairchild Camera` p4, 301 KB — is a **photomicrograph of an
integrated circuit**, and it scores **0.0932**: below the threshold, and shrunk
6x it is visibly degraded, the fine traces softening together and the caption
beneath it destroyed.

**The reason is structural, and it is not a threshold that can be tuned.** The
detector measures *continuous tone*, and a photomicrograph of a circuit is
essentially bimodal — black traces on white — so it has almost none, and reads as
indistinguishable from paper. Line art, technical diagrams, engravings and
high-contrast plates all sit in that class. This is R38's own finding seen from
the other side: low tone means a page is genuinely bimodal, which is exactly when
1-bit is lossless **for text** — and exactly when a *picture* is still full of
detail worth keeping. The two conclusions share a premise and diverge on what the
ink means.

**And the prize does not justify pushing further.** Measured properly this time:
every MRC background in the corpus together is **39.4 MB of a 792 MB output, 5.0%**.
A threshold at 0.10 saves 4.35 MB — **0.55% of the corpus** — and 0.05 saves
0.40%. Even a *perfect* detector is bounded by about 1%, because the safe
population is a fraction of a layer that is itself a twentieth of the output.
The first attempt's 1.74x was the prize for destroying pictures; this is the
prize for not destroying them, and it is not worth a rule that can misrepresent
an archival document.

**What a third attempt would need**, if the prize ever grows: a signal for
*detail worth preserving* rather than for continuous tone — high-frequency energy
in the filled background, which a photomicrograph has in abundance and flat paper
does not. Tone is the wrong axis, and no amount of tuning moves it onto the right
one.

---

#### The first attempt, 2026-08-11

Built, measured, reverted. The idea: Photo detail is a promise about
*photographs*, so a layered page whose background is only paper could be shrunk
much harder for free, and only pages carrying a picture need honour the setting.

**The measured ceiling is real and large.** Forcing every layered page to 6x
across seven documents: 6,150 KB → 3,535 KB, 1.74x. One document went from
792 KB — larger than its own 285 KB input — to 281 KB.

**But no threshold separates the two populations on real data.** The detector
measures continuous tone outside the text regions, as the highest of 64 tiles
rather than an average — averaging hides a postage-stamp photograph on a blank
sheet, which is the exact page that must not be shrunk. Measured standalone it
looked clean: paper-only pages 0.0000–0.0126, picture pages 0.0955 upward, a gap
of six times.

That gap was an artifact of the instrument. Fed the boxes the *pipeline* actually
produces, the same measure returns a continuum — 0.0206, 0.0279, 0.0474, 0.0482,
0.0512, 0.0992, … 0.6983 — with no gap anywhere. The standalone tool ran the
recogniser over a full-resolution PNG and got dense boxes; the pipeline runs it
once over the rebuilt document and gets fewer, so text Vision did not box counts
as background tone.

**And the detector is right to count it.** Unboxed text really is in the
background, and shrinking the background really would blur it. The signal is not
broken; there are simply few pages where every line is boxed. At a threshold safe
enough to never crush a photograph, it fired on **0 of 25** pages — all cost, no
benefit.

Two things worth keeping from the attempt:

- **The 6x ceiling is not what it looked like, and the correction matters for
  anyone reopening this.** The figure above was taken by forcing 6x on *every*
  layered page, photographs included — and rendered, a photograph at 6x is
  destroyed: on `Findlay_1992` p21 the trees, buildings and texture go to a
  blur, while the text stays perfect because it comes from the stencil. 57 KB
  at 2x against 21 KB at 6x, and the picture is no longer a photograph of a
  specific place.
  So 1.74x is **not** the prize for a working per-page rule. It is the prize for
  destroying pictures. A correct rule would apply 6x only where the background
  is paper, and would win 1.74x *on those pages alone* — worth having, but a
  smaller number than this entry first implied, and the smaller number is the
  one to justify the work against.
  Offering 6x as a user setting was considered on the strength of the original
  figure and **declined** once the page was looked at: FEATURES.md's bar is that
  a feature which could plausibly misrepresent a document is not worth its
  convenience. The scale stays at three levels.
- **The app can inflate an already-compact scan** — `Lipset_Luethy_1955`
  285 KB → 792 KB, `Marth_1982` 145 KB → 361 KB, `_1958_Executive Pay`
  442 KB → 797 KB. Rebuilding at native DPI and re-encoding loses to an input
  that was already efficiently compressed. That is its own defect and is not
  about layering; it wants measuring across the corpus before anything is done
  about it.

### R36 · Bundling OpenJPEG for the background layer — WONTFIX *(decided: 1.19x)*
R34 rejected ImageIO's JPEG 2000 because its `compressionFactor` is a ratio
rather than a quality target, and noted that OpenJPEG — which has real rate
control, including `-q` in dB — was **1.5–2x better than JPEG at matched
fidelity**. That number was the reason this stayed open. It does not survive
contact with the layer it would actually apply to.

The 1.5–2x was measured on *whole pages*, before MRC existed. A whole page is
grainy and high-frequency, which is where a wavelet beats a DCT. The MRC
background has had the text lifted out of it, the holes filled flat, and the
whole thing halved — it is smooth, and smooth is what DCT is already good at.

Measured on **ten real background layers** taken out of the pipeline, each
encoded as JPEG at the shipping quality and then by OpenJPEG at the lowest `-q`
that matched or beat that page's PSNR:

| | JPEG | OpenJPEG at matched fidelity |
|---|---|---|
| ten backgrounds | 496 KB | 418 KB |
| | | **1.19x** |

Two of the ten came out *larger* than JPEG (0.99x, 0.91x). The 1.19x is also
generous to OpenJPEG: the `-q` grid steps 2 dB, so the matched points overshoot
JPEG's fidelity by 0.1–1.9 dB and OpenJPEG is credited with bytes it spent on
quality JPEG never had.

The background is roughly 40–60% of a layered page, so 1.19x there is about
1.09x on the file. **Against that:** a third bundled helper and its dylib chain
through `Tools/bundle-libs.py`, another licence to carry, another
single-architecture binary for `containsNativeSlice` to police, a PDF 1.5 header
for `/JPXDecode`, and a new way for a page to fail. Not worth 9%.

The lesson is R34's, again and in the same session: a codec measurement is only
valid for the content it was taken on. Both times the number looked good on one
kind of image and evaporated on the kind that mattered.

### R37 · Small documents come out larger than they went in — FIXED *(reported, not compressed away)*
*(measured 2026-08-11, 40 corpus documents through `OCRModel.makeSearchablePDF`)*

**The figures first recorded here were from a biased sample and are corrected
below.** They came from a `head -40` of a `find` over `testdocs` — not a sample,
just whatever the filesystem enumerated first — and said "134.3 MB in, 75.0 MB
out, 1.79x, 15 of 40 grew". The first full-corpus run says **1,198 MB in,
1,039 MB out, 1.15x, and 91 of 232 grew (39%)**, with a worst case of **9.45x**
against the 2.26x quoted below. The diagnosis in this entry still holds for the
cases it examined; its scale never did, and it missed R38 entirely.

On the sampled cohort the app did what it says, and that split by input size is
still the shape of it:

| input | grew | that cohort, overall |
|---|---|---|
| under 300 KB | 3/4 | **1.43x larger** |
| 300 KB – 1 MB | 6/9 | **1.37x larger** |
| 1–5 MB | 5/17 | 1.92x smaller |
| over 5 MB | 1/10 | 1.93x smaller |

Worst cases: 110 KB → 249 KB over three pages (2.26x), 704 KB → 1,543 KB over 64
(2.19x), 747 KB → 1,495 KB over 46 (2.00x).

**Diagnosed, by elimination and then by measurement.**

*Not the text layer.* Splitting each output's bytes: on the worst case the text
layer is 29 KB of a 249 KB file. Growth is essentially all image bytes —
201 KB against an input of 110 KB.

*Not resolution.* `rebuildDPI` never exceeds `nativeDPI` on any of the 40
documents; nothing is upsampled.

*Not a missing warning.* `hasDigitalText` returns false on the growers, but
correctly — `pageIsAnImage` is true, because they are scans carrying an existing
OCR layer rather than born-digital files.

*Not a noisier threshold.* Rendered at the source's own DPI, our bilevel page
carries the same ink to three decimal places — **0.0974 against 0.0973** — and
the two are indistinguishable at 1:1.

**It is the encoder, and the difference is deliberate.** These inputs were
compressed with **symbol-mode JBIG2**, which pools repeated glyph shapes.
Measured on one page at 4300x6000: **17 KB theirs, 95 KB ours**. Symbol mode is
what this project refuses on purpose — it is the mechanism behind the Xerox
scanners that silently swapped digits, and FEATURES.md records that as `Never`.

So there is nothing here to fix by compressing harder: the only route to those
numbers is a compression that can alter digits in an archival document. What was
wrong was that it happened **silently**. `Model.sizeNote` now says so on the
finished run, with both figures and the reason. Threshold 1.25x, because a
searchable copy always costs something the original did not carry and reporting
every three per cent would be noise; the real cases ran 1.35x to 2.26x.

### R38 · Dense bilevel type is routed to the picture path — FIXED
*(found 2026-08-12 by the first full-corpus gate run; fixed 2026-08-12)*

Four documents come out of this app **larger than they went in, by multiples**:

| document | in | out | |
|---|---|---|---|
| `Boltanski_2006` | 16 MB | **156 MB** | **9.45x** |
| `Noble_1977` | 17 MB | 87 MB | 5.0x |
| `_1950_Comic` | 477 KB | 1,661 KB | 3.48x |
| `_1926_Clapp` | 540 KB | 1,730 KB | 3.20x |

**Cause.** Boltanski's source stores each 47 MP page as bilevel JBIG2 at ~150 KB
— 3.6 MB for the lot. Our output gives those pages a JBIG2 stencil **plus** a
13 MP greyscale DCT background at ~1.7 MB each, carrying nothing the stencil does
not already have. They reach the picture route on **ink coverage alone**, 0.26
against the 0.15 threshold, while the other two signals say text emphatically:
tone 0.013, saturation 0.0000. `isPicture` ORs its three signals, so one
overrides two.

`pictureInkThreshold` was calibrated on a corpus where "the only pages above 15%
were the two covers (100%) and a halftone map spread". Densely-inked bilevel type
at 26% was not in that corpus, and the constant has no way to tell it from a
plate.

**The fix.** Require corroborating tone before ink alone counts:
`pictureInkMinimumTone` at 0.03, gating the ink branch. Tone and saturation each
still route a page to pictures on their own, so the two cases the other
thresholds exist for — the tinted isobar figure, the pale-colour page — are
untouched; both of those fire on pages whose ink coverage is near zero.

The separation is measured, not assumed. Re-measured independently before
applying, over every ink-triggered page in the corpus:

| | tone |
|---|---|
| real pictures — Findlay p16/21/28/29/38/39, Black, Ehrenreich, Marth | **0.0709–0.1453** |
| dense bilevel type — the four inflating documents | **0.0007–0.0290** |

**The scale of the change is much larger than the specification said, and that
is the finding worth carrying.** The entry as written implied four documents.
A sampled sweep of all 232 — four pages each, 827 pages — says **148 pages route
to the picture path today, 98 of them on ink alone, and 66 of those 98 flip to
1-bit.** Whole documents move: `Noble_1977` has 361 picture pages and **all 361**
flip; `Boltanski_2006` has 203 and **201** flip, keeping only its two covers
(front tone 0.0527, back 0.1128). Roughly forty documents are affected, not four.
The spec's own validation had looked only at the pages it already suspected —
the same shape as R37's `head -40`, one entry later.

**Why 1-bit is safe here, checked by looking rather than argued.** The picture
route exists because thresholding destroys an *unresolved* halftone — one whose
dots have blurred into greys. Low tone means the page is genuinely bimodal, which
is exactly the case where 1-bit is lossless. Six pages spanning the risk space
were rendered both ways at 1:1 and compared:

- the three flipped pages with the **highest** tone, i.e. closest to the new
  boundary — `_1973_Other 67` p4 (0.0290, dense TV listings), `Riesman_1976` p3
  (0.0283, 600 DPI book type), `Merriam_1913` p1 (0.0275, 1913 newsprint
  columns): all pure text, all crisper at 1-bit than through the DCT;
- the **highest-ink** page in the corpus, `_1967_Fairchild` p2 at 0.9502 — a
  black cover, and the two renderings are indistinguishable;
- the two the specification named as riskiest, `_1950_Comic` p1 (line art with
  hatching, structure intact) and `Boltanski_2006` p68 (the "heavy ink" is
  largely gutter shadow across a 47 MP spread).

`Noble_1977` needs no page-by-page judgement: its maximum tone over 361 pages is
**0.0030**, and Otsu clamps to 90 on every one of them, which is the signature of
a source that is already pure bilevel. Thresholding it is close to the identity.

**The residual risk, named rather than left implicit.** A *small* photograph on
a dense text page contributes tone in proportion to its area, so one covering a
few per cent of the sheet can land under 0.03 and be thresholded. That page was
only ever protected by accident — it needed the surrounding text to be dense
enough to clear 0.15 ink, which ordinary text at 6–8% never does — so the change
narrows a protection that was incidental, not one that was designed. No page in
the corpus exhibits it; the gate run is what would catch one.

**Checks.** Four fixtures built from exact 8-bit grey values, a 2x2 over the
conjunction: heavy ink with no tone (text), with 2% tone (text), with 6% tone —
below `pictureToneThreshold`, so only the ink branch can route it — (picture),
and with 20% tone (picture, on tone alone). Plus both ends end-to-end through
`flatten`. `Tools/mutate.py` gained `logic/R38-ink-needs-tone`, which plants the
original defect rather than editing the constant: the T5 drift guard asserts the
literal 0.03 and would kill a constant mutant for free, proving nothing about
whether any code reads it. Killed, by three checks.

The fixtures had to set pixel bytes directly. The suite's existing dark-page
fixture asks `NSColor(calibratedWhite: 0.45)` for half the sheet and measures
`ink=0.0000` — the value it actually lands on is above the page's own Otsu split,
so that fixture reaches the picture route through *tone*, not ink, and is
unaffected by this change. That was predicted the other way round from
arithmetic, and the prediction was wrong; a fixture written for a threshold has
to control the number the threshold reads.

### R39 · The recogniser's DPI ceiling cannot bind on Automatic — FIXED
*(found 2026-08-12 after 1.10.0 shipped; the fix it proposed was measured and
refuted, and a different, real defect was found underneath it)*

**`Runner.recogniserDefaultDPI` is 300, and its doc comment said that is "the DPI
mac-ocr renders PDF pages at when told nothing". It is not.** `mac-ocr ocr
--help`:

```
--pdf-dpi <pdf-dpi>   PDF rendering DPI: 'auto' (default, derived from
                      embedded image resolution; falls back to 144)
```

The entry originally recorded this as a recognition-quality defect and proposed
sending the DPI explicitly. **That proposal was wrong, and the measurement that
refuted it is the more useful half of this entry.**

**What was measured.** A whole-document harness — flatten each document exactly
as the pipeline does, then recognise the rebuilt PDF several times, varying the
DPI through `Prefs.Snapshot` so it exercises `Runner.recognitionArguments` rather
than a replica. Over a **stratified sample of 52 documents and 4,140 pages**,
covering every band of rebuild resolution:

| setting | characters | vs Automatic | documents made worse |
|---|---|---|---|
| **Automatic** | **9,211,708** | — | — |
| 150 | 9,104,413 | −1.16% | 31 |
| 200 | 9,151,792 | −0.65% | 22 |
| 250 | 9,132,784 | −0.86% | 31 |
| 300 | 9,196,138 | −0.17% | 26 |
| 400 | 9,186,345 | −0.28% | 27 |

A *ceiling* — lower only, never raise, which is this codebase's own pattern — was
evaluated too and is also worse: −0.12% at 300, −0.08% at 400.

**Automatic wins, and it wins hardest exactly where the hypothesis said it would
lose.** In the `>450 DPI` band, every fixed value is worse than letting the
engine choose: 150 −1.12%, 200 −0.60%, 250 −0.69%, 300 −0.46%, 400 −0.29%.
`TROTMAN 1976` at 602 DPI reads 139,699 characters on Automatic and 136,603 at
an explicit 300. The `Boltanski_2006` page that started this — 3,046 characters
at 300 against 924 on Automatic — is a genuine tail case and not a rule, and one
page was never enough to change a default that governs every document.

**The real defect, found while measuring the wrong one.** `recogniserDPICeiling`
exists because mac-ocr refuses a page over 200 MP while this app rebuilds up to
400 (U25). On Automatic the flag was only sent when the ceiling fell **below
300**, because 300 was what the code believed the engine would otherwise use. A
sheet whose ceiling lands between 300 and its own resolution therefore got no
flag at all, and the engine rendered at the page's resolution and refused it.

Reproduced rather than argued: a 20 x 30 inch page carrying an image declaring
12,000 x 18,000 has a native 600 DPI and a ceiling of 565, and the app sent no
flag. mac-ocr:

```
Error: PDF page at 600 DPI would render to 216 megapixels (max 200 MP).
```

With the fix it sends `--pdf-dpi 565` and the page renders. **This is the case
U25 was written for and did not cover** — U25 fixed it for an explicitly chosen
DPI and left Automatic resting on the false claim about the engine.

**The fix.** `Flattener.engineAutoDPI(for:)` reports the resolution mac-ocr will
actually derive — the highest any page's largest image implies, nil for a
born-digital file where the engine falls back to 144. `recognitionArguments`
compares the ceiling against *that* on Automatic instead of against 300, and
clamps what it sends into mac-ocr's accepted 72–600, which is newly reachable
because a small page scanned at 1200 DPI can leave the lowered value above 600.

**Automatic is otherwise untouched, which the corpus requires.** Checked rather
than assumed: across all 232 documents, **zero** have an engine choice above
their ceiling, so the flag is sent for none of them and the 1.10.0 gate figures
still describe the output exactly. No gate re-run was needed, and that is a
stronger answer than one — it is a statement about every document rather than
about a total.

`Tools/mutate.py` gained `logic/R39-auto-vs-engine`, which restores the
comparison against the constant; killed by two checks. The doc comment on
`recogniserDefaultDPI` now says what the constant is actually for.

### R40 · Batch throughput fell when recognition came in-process — FIXED
*(found 2026-08-12 by the corpus gate, before 1.11.0 was released; fixed
2026-08-12 by putting recognition back into a process per file — see "The fix,
as built" at the end of this entry)*

**The gate is 187 minutes against a 75-minute baseline.** Everything else it
measures is unchanged or better — 232 of 232 succeeded, 0 failed, output
byte-identical at 792 MB, characters **up 0.16%** (34,204,971 against
34,148,681) — so this is throughput alone, and it is not a correctness fault.

**Measured, not inferred.** Like-for-like on the same 12 documents at the app's
own concurrency: **3 minutes through the mac-ocr subprocess, 5 through direct
Vision.** At concurrency 1 the same subset takes 8 minutes, so in-process
concurrency is buying 1.6x where the subprocess arrangement bought about three.

**The cause is that Vision recognition does not parallelise across concurrent
requests inside one process.** Thirty-six page images, one process:

| threads | time | speedup |
|---|---|---|
| 1 | 22.5s | — |
| 2 | 21.5s | 1.05x |
| 4 | 21.1s | 1.07x |
| 6 | 20.8s | **1.08x** |

One request already saturates whatever Vision uses; further requests queue. The
~3x that TECHNICAL.md attributes to running files concurrently came from mac-ocr
being **one process per file** — process-level parallelism, which threads cannot
recover.

**Two of my own claims were wrong on the way here, and both are the same
mistake.** A single-document head-to-head measured 37.2s direct against
mac-ocr's 39.8s and I reported "no regression" — that is the one configuration
where the difference cannot appear, because there is no concurrency in it. And
when the gate looked slow I proposed parallelising *pages within* a document;
measured, that is 1.0x, for exactly the reason above. Both were caught by
measuring the thing the pipeline actually does, which is this register's oldest
lesson.

**The fix, decided with the user: a pool of helper processes.** It is
deliberately not a return to mac-ocr — the helper takes a bitmap we rendered and
hands back observations, so there is no PDF handed over, no rasterisation we do
not control, no DPI negotiation, and the quads and per-word boxes the CLI could
never expose stay available.

---

#### The fix, as built

`Helper/main.swift` builds `visionocr-recognise`, bundled beside `jbig2` and
`qpdf`. It reads a manifest of page bitmaps, writes one JSON file of
observations per page, and prints each page's index as it finishes.

**It compiles the app's own `Recogniser.recognise`.** Not a copy — the same
source file, in the helper's file list in `build.sh`. Every character count in
the corpus baseline depends on the helper and the app doing identically the same
thing, and one implementation is the only way to guarantee that. The suite
checks it anyway, on both routes `flatten` can produce: **786 observations over
12 corpus pages and every observation on a 1-bit page and a three-channel JPEG
page match to the last digit** — text, confidence, and all four box components,
which are doubles that have been through JSON.

**One helper per document, not per page**, and that is a measurement rather than
a preference. A process costs ~0.03s to launch and Vision ~0.20s to answer its
first request — isolated on the same page in the same process: 1.400s, then
1.238s, 1.211s, 1.157s. Per page that 0.23s is 19% of a typical page and would
hand back a fifth of what this change is for; per document it is 0.23s against
minutes.

**The pool needs no pool.** `start()` already runs at most `Prefs.concurrency`
files at once and each holds at most one helper, so the process count *is* the
setting, by construction. `helperIsWorthIt` declines below two files or a
concurrency of one, where there is nothing to overlap with and the only effect
would be paying Vision's start-up twice.

**Process-level parallelism was re-measured before any of this was built**,
because the whole design rests on it and the evidence for it was mac-ocr's
history rather than a number: the same 12 page images take **14.00s in one
process and 6.28s across six — 2.23x**, against the 1.08x six threads buy inside
one process.

**The helper is never authoritative about failure.** Every way it can go wrong —
absent, unstartable, exits non-zero, goes silent, returns unparseable output,
returns *fewer pages than it was given* — throws, and the app recognises the
document itself and says so in the log. So the worst a bug in the helper can
cost is time; it cannot fail a file that would otherwise succeed, and it cannot
publish a document with pages missing. The one exception is cancellation, which
must not fall back: redoing the work in-process is the opposite of what the user
asked for, and a helper killed by a cancel exits non-zero, which is why the
cancellation is checked *before* the exit status.

Six of those paths are exercised by fake helpers in the suite rather than
reasoned about (CONTRIBUTING 4c), and the three that guard content were put back
as defects and watched to fail first: dropping `--confidence` from the argument
list, skipping a missing page result instead of refusing it, and a helper
returning one observation fewer than the app. Each was caught by exactly the
check written for it and nothing else moved.

**What is *not* covered, deliberately.** Extract Text and the no-rebuild route
still recognise in-process. Both render pages in memory, so a helper would have
to encode and write every page first; neither is the default, and neither is
what the corpus gate or the library sweep exercises. Recorded here rather than
left to be discovered.

**The register's own lesson, applied to the instrument.** `Tools/score-gate.swift`
now prints whether the run it is about to do will use helpers, because a gate
without one measures the 187-minute configuration while looking exactly like a
75-minute one. The first version of that line reported the helper as *available*
and said nothing about whether the batch would reach for it — which on a
one-document run is the wrong answer, and is the same class of mistake as the
three timings that were polluted while this entry was being written.

---

### R59 · `publish` failed onto another volume, and deleted a folder it was aimed at — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A2.1 and A2.3)*

`publish` is the one step that touches the user's disk, and invariant 2 is about exactly
this step. Two defects in eight lines.

**Every re-run of a batch onto another volume failed.** `replaceItemAt` requires both items
on one volume, and the staged file is always in `NSTemporaryDirectory()` — the boot volume.
So an output folder on an external drive or a network share worked the *first* time, when
`publish` took the `moveItem` branch (Foundation copies across devices), and failed every
time afterwards. Verified first-hand: `NSPOSIXErrorDomain 18` (`EXDEV`), surfacing as "The
file couldn't be saved in the folder", against the same call succeeding on the boot volume.
Correcting a setting and pressing Start again failed the entire batch, with a message
naming neither the cause nor a remedy. **Fixed** by moving the staged file to a sibling of
its *destination* first, so the atomic replacement is same-volume whatever volume that is;
a failed replacement puts the staged file back so a retry has something to publish.
Verified: three consecutive publishes onto an HFS+ RAM disk, each replacing the last, no
scratch left beside the file.

**And a folder at the destination was deleted, recursively, with success reported.**
`fileExists(atPath:)` is true for a directory and `replaceItemAt` then removes it. A folder
named like an output, holding a file, was destroyed. Nothing in the pipeline aims at a
directory — `uniqueOutputs` compares output paths against each other, never against what is
on disk — so this needed a coincidence, but silently deleting something that was never OCR
output is not a thing to leave to luck. **Fixed**: it refuses, and says the name.

**Also fixed, from A2.2: a cancel could be observed and the file published anyway.** The
last gate sat several seconds before `publish` on a long document — `copyOutline` is a full
PDFKit re-serialisation at ~13 ms a page, and the annotation transplant adds three qpdf
passes — and a cancel landing in that window published the file and reported **succeeded**.
Measured at 0.38 s on 19 pages, 0.73 s on 57, so about 7 s on a 568-page book. A check
immediately before `publish` does not shorten the window; it stops it ending in a publish.
The existing cancel test only cancelled *before* a run started, so the window was untested.

**Still open from the same finding:** `Recogniser.extract` checks cancellation only at the
top of each page and writes **straight to the user's destination with no staging**, so a
cancel during the last page finishes it, replaces the previous output, and then reports
`.cancelled`. The log says one thing and the disk says another. Text mode has no staging at
all, which is the real fix and a larger one. `REVIEW-2026-08-14.md` A2.2 carries it.

### R58 · Two review rounds on the annotation transplant, and both found marks in the wrong place — FIXED, third round unrun
*(2026-08-14. Recorded as one entry because the defects are one story: every single one
was an assumption about the PDF format that the feature's own checks could not see.)*

`Annotations.transplant` carries a reader's marks onto the rebuilt file. It was built
against `TODO.md`'s specification, verified on the document that specification cites —
**121 of 121 marks including all 20 stamps, 0 moved** — and then adversarially reviewed
twice. Each round rejected it, with numbers.

**Round one: the rebuilt page is not always in the source's coordinate space.**
`Flattener.boxSize` returns `CGRect(origin: .zero, …)` and swaps width and height for a
quarter-turn, so copying `/Rect` verbatim is only correct when the box already starts at
the origin and the page is not rotated.

| case | what happened | reach |
|---|---|---|
| offset media box | mark landed **24.7 pt low** — `Cohen_1990` p6, box `[0 -24.69 408 588]` | **105 of 233** documents |
| rotated page | mark landed **off the sheet, gone** — measured at 90° and 270° | 475 of 16,987 pages |

**Why the checks could not see it: they compared the copied `/Rect` against the source
`/Rect`.** That agrees with itself by construction — CONTRIBUTING §4b's shape, written
into the very feature whose specification demanded a rendered check *because* counting is
not enough. The offset is now corrected by translating every page-space geometry array;
rotation is **refused**, because correcting it means reaching every geometry array plus
each appearance stream's `/Matrix`, and no marked corpus document has a rotated page
carrying a mark.

Round one also found: image inputs failed the whole conversion (the call site passed the
original rather than the wrapped PDF, and qpdf cannot read a PNG); an inline `/Annots`
dictionary and a non-zero generation reference were both silently skipped, and a skipped
mark never entered `expected`, so no check could notice; `mapping[id] = nil` *removes* the
key in Swift rather than recording a failure; the three qpdf passes were unadoptable, so
Cancel could not reach them; and the report went to a status line cleared the instant the
file finished.

**Round two, on round one's fix, found four more — and this is the ninth consecutive
round in this register where reviewing the previous round's code found real defects in
it.**

- **`/Rotate` and `/MediaBox` are inheritable, and qpdf does not push them down** — its
  own header says `pushedinheritedpageresources: false`. So a document with `/Rotate 90`
  on its `/Pages` node sailed past the brand-new rotation refusal and had its marks copied
  into a swapped frame. Verified both ways on one page: on the page it threw, on the
  parent it carried. The offset box had the same hole.
- **Geometry behind an indirect reference was left in the old space.** The worst shape was
  an indirect `/QuadPoints` with a direct `/Rect`: a viewer draws text markup from
  `/QuadPoints`, so the highlight rendered 24.69 pt from the words it marked **while the
  rectangle check passed**. An indirect number inside a direct array *deformed* the
  rectangle instead of moving it.
- **The `failedStream` flag was dead code** — `return nil` executed before it was ever
  read — so a lost appearance stream published a stamp with an empty `/AP`, drawn as
  nothing, reported as carried. Found by fault injection, not by reading.
- **The adoption was unpaired: R15 verbatim, at a new site.** Measured at **204 open file
  descriptors for 200 documents**, linear, against Foundation's ceiling near 2,560 — so a
  sweep of the ~16,000-document library it exists for would have died an eighth of the way
  in. `Model.swift` carries that exact warning a few hundred lines above the call site.
- And the independent pixel checker was **inverted for offset boxes**: it measured the
  output through the *source's* rectangle, so it failed a correctly-carried mark and
  passed misplaced ones — on precisely the 105 documents it was most needed for.

**One measurement I reported was wrong, and the reason is worth keeping.** "Cohen offset
case: drift 0.001" was measured on a `pdf-extract-pages` extract, and **PDFKit normalises
the media box to the origin when it writes** — so the extract had lost the very property
under test. Extract with `qpdf --pages` when the geometry *is* the question. Re-measured
on the real page: `/Rect` 83.48 → 108.17 and `/QuadPoints` 108.64 → 133.33, both exactly
+24.69, drift 0.002.

**What holds now:** 858 checks; 121 of 121 on the specification's document; the offset case
correct on a file that still has its offset; rotation, inline annotations, non-zero
generations, unreadable geometry and lost appearance streams all refusing the document
rather than publishing it. Three properties are asserted directly against hand-built
object tables — `resolvesIndirectRectangles`, `resolvesInheritedPageAttributes`,
`translatesIndirectGeometry` — because **PDFKit cannot express any of the three cases**, so
no fixture in this repo can reach them. That is CLAUDE.md invariant 5's lesson arriving
from a new direction: a fixture is not blind only to what it omits, but to what its
*writer* cannot produce.

**Held for more work by owner decision, 2026-08-14.** A third round has not been run, and the
feature is **not** to go into a release until it has had one — two consecutive rounds each found
content-integrity defects, and the base rate says a third would too. It also needs the test
`REVIEW-2026-08-14.md` A8.1 names: **nothing currently proves the setting gates the feature**, so
if `if settings.preserveAnnotations` were inverted or deleted, all 23 checks here would still
pass. It is on `main`, off by default, and unadvertised.

### R56 · `isPicture` is blind to pale marks, and the 1-bit route erases them — OPEN
*(found 2026-08-13 building the adversarial fixtures TODO item 1's measurement asked
for. **In the app, on the default route, and it destroys content** — the only entry in
this register found by a fixture rather than by a document.)*

A page of type with a **pale line drawing** on it — luminance 200 on cream stock —
comes out of `Flattener.flatten` in Automatic mode with **the drawing gone**. Not
softened, not blurred: erased to paper, with the text beside it intact.
`Tools/make-plate-fixtures.swift` builds it, and the rendered before and after are
what this entry rests on.

**Why nothing notices.** The three routing signals read, against the same page with
nothing but text on it:

|  | ink | tone | sat |
|---|---|---|---|
| text only | 0.025 | 0.004 | 0.000 |
| **the same page + a pale drawing** | **0.025** | **0.004** | 0.001 |

Identical, and it is arithmetic rather than luck. Otsu lands at 130. `inkCoverage`
counts pixels *below* 130, and the drawing is at 200. `toneFraction` counts a band of
**±45 around** the threshold — [85, 175] — and 200 is above it. `saturation` is
measured against the page's own paper and the drawing is grey. So the drawing falls in
a **blind zone from `threshold + 45` up to the paper**, which on this page is luminance
175–247, and no signal has any term for it. `isPicture` returns false, the page is
thresholded, and every pixel above 130 becomes paper.

**This is invariant 1.** "Never lose content silently. Every path that can drop a
page, a line or a text layer must report it." Nothing is reported here, and the output
is a plausible page — which is the failure mode the invariant names as worse than a
loud one.

**How it went unseen for so long, which is the part worth keeping.** The case is
already in this register. R50 measured it — "a *pale* line drawing reads **0.0000**,
because Otsu puts light grey on the paper side and it is therefore not ink at all" —
and dismissed it in the next sentence: "Neither is alarming, because this only ever
changes *resolution*: the worst it can do is soften something, never remove it." That
is **true of R50 and false of `isPicture`**. R50's signal picks a downsample factor, so
its misses cost sharpness; the identical blind spot in `isPicture` picks a *codec*, and
1-bit has no way to express a pale mark. Two entries knew about the blind zone, each
reasoned about its own consequence, and nobody joined them. The lesson is not "measure
more" — it is that **the same miss is a different defect in front of a different
decision**, so a signal's known misses have to be re-examined against every caller,
not once.

**A luminance signal for it was built, measured over four rounds, and REFUSED. It
lives in `Tools/score-threshold-loss.swift`** — not in `Sources/`, because the app does
not use it and `Flattener` would be carrying dead code, which is the same call
`score-skew.swift` records for the deskew estimator. It carries a self-test that runs
on every invocation and pins each property below.

`contentLostToThreshold` is the fraction of the page that the threshold will call paper
while being too far below the paper's own level to be paper. Each round looked right
until the corpus was read, and the fixtures were reassuring in three of the four:

| round | change | fixture: text / halftone / **pale drawing** | corpus 1-bit pages |
|---|---|---|---|
| 1 | pale fraction, mean − 2sd | 0.0081 / 0.0166 / **0.0236** | continuum 0→0.0918, no gap; 24% of text pages above the fixture |
| 2 | exclude pale pixels *near ink* | 0.0000 / 0.0001 / **0.0158** | — |
| 3 | paper level from the **mode**, spread from the peak's clean upper side | 0.0000 / 0.0001 / **0.0182** | p50 0.0000, p90 0.0238, max 0.4232 |
| 4 | require the mark to be **thin** | 0.0000 / 0.0001 / **0.0180** | p50 0.0000, p90 0.0130, p95 0.0324, max 0.2577 |

Round 1's confound was **anti-aliased glyph edge**, which scales with how much type a
page carries — its top hits were dense text and a page of handwriting. Round 2 fixed
that: edge is always beside ink, and a drawing is surrounded by paper. Round 3 was
needed because a *large* pale area is part of the bright class, so it drags the mean
down and inflates the spread until it excludes itself. Round 4's target was the largest
remaining hit — a ProQuest metadata page whose **alternating grey table bands scored
0.4232**, and which at 1-bit loses the banding and **not one word**.

**What refuses it is round 4's remaining hits.** `Doermann_1967` p19, at 0.2577, is a
1967 typescript whose pale content is **show-through from the reverse of the sheet** —
thin, away from ink, and an artefact the threshold is *right* to erase. So the blind
zone holds three kinds of thing and luminance cannot separate them:

| what is in the blind zone | what should happen |
|---|---|
| a pale drawing | **keep it** — this is R56 |
| decorative table shading | losing it is harmless |
| show-through from the reverse | **losing it is desirable** |

The two commonest of the three are the two you want deleted, so any threshold here
decides the case it exists for wrongly. 9.1% of 1-bit corpus pages score above the
fixture, and the ones that do are mostly right as they are. **This is R35's refusal a
third time, from a new direction**, and it is recorded rather than tuned.

**What it converges on.** Both R56 and R57 now point at the same unbuilt instrument,
for independent reasons: shape. Drawing strokes are long and curved, show-through is
text-shaped blobs in rows, decorative shading is rectangles, and a blobbed plate is one
huge component. `FEATURES.md`'s spatial-signal entry proposed exactly this, and it now
has two defects arguing for it and four rounds of evidence that the cheap alternatives
do not work. It is still the remaining prize, and it still wants its own cycle.

**Nothing is shipped for this, and one thing is deliberately NOT shipped**: TODO item
1's size optimisation, which would move *more* text pages onto the 1-bit route using
`inkOutsideText` — whose recorded miss is precisely this pale drawing. That would turn a
latent defect into a common one for a measured 8.2 KB a page. Refused until R56 closes;
`TODO.md` has the arithmetic.

### R57 · a continuous-tone plate can miss both routing thresholds at once — OPEN
*(found 2026-08-13 alongside R56, from the same fixtures. **Realism not established** —
read the caveat.)*

The `tonal-plate` fixture — a smooth gradient with a dark subject on it, over the lower
third of a text page — routes to **1-bit**, and comes out a **solid black blob that
also swallows the last line of text above it**. Rendered, and it is exactly what
`pictureInkThreshold`'s own comment predicts: "a picture misrouted to 1-bit is
destroyed."

It misses both gates, narrowly and simultaneously: **ink 0.147 against 0.15**, **tone
0.102 against 0.12**, saturation 0.011 because the plate is grey. Neither constant is
wrong for what it was calibrated on — both were measured on pages a picture
*dominates* — and a plate covering a fifth of the sheet clears neither.

**The caveat, stated because it decides what to do.** This fixture is a *clean*
synthetic gradient, which is the case that minimises `toneFraction`: a real scanned
photograph carries grain, and grain is precisely what lands in the tone band. So the
fixture may be sitting in a gap that real material does not occupy, and that is the
same mistake R49 made twice in the other direction — "a plausible-looking gap on the
corpus and an overlap the corpus did not contain."

**So this is not fixed by moving a constant.** Raising `pictureInkThreshold` or
lowering `pictureToneThreshold` would re-open R38, whose measured cost was
`Boltanski_2006` going 16 MB → 156 MB (9.45x). What the case actually wants is the
signal FEATURES.md already specifies and this entry now has a second reason for: a
**connected-component** pass, where a solid blob is one large component and text is
thousands of small ones in rows.

**The band is not empty on real material.** Measured over 441 corpus pages, three sit
in it on the 1-bit route — `Ehrenreich_2000` p9 (ink 0.145, tone 0.106),
`HarpersMagazine-1938` p4 (0.139, 0.094) and p7 (0.143, 0.096) — and 71 pages are
within reach of one gate or the other. So the fixture is not sitting in a gap the corpus
lacks, which was the worry this entry was written with. Those three have **not** been
rendered and compared; that is the next step, and until it happens the honest statement
is that real pages occupy the band, not that they are being damaged.

R56's refused luminance signal is no help here either: requiring a mark to be *thin*
drops this fixture from 0.0931 to **0.0024**, because a tonal plate is precisely not
thin. Two defects, one instrument, and it is shape.

### R55 · `classify-source` calls an upright-scanner capture `photographed` — OPEN
*(found 2026-08-13 running the gate over the one document the owner asked to add to
the corpus; not in the app — it is the gate that decides what the corpus and the
sweep may contain)*

`classify-source` verdicts `photographed` when the median illumination gradient
exceeds 0.16. *Why?* (1954, National Foremen's Institute) comes back **0.169** and is
excluded — and it is a scan. **The owner's ruling, 2026-08-13: only hand-held
photographs are `photographed`.** An upright or planetary scanner capture is a scan.

**What the signal is actually measuring.** Not vignetting. The 3x3 paper-luminance
blocks are a smooth diagonal ramp, and the same ramp on every sampled page:

|  | left | centre | right |
|---|---|---|---|
| top | 182.5 | 193.3 | 201.2 |
| middle | 186.8 | 198.3 | 206.2 |
| bottom | 202.9 | 212.2 | 219.6 |

*(page 7; pages 4, 6 and 9 are within 1.5 of these, page 2 is brighter throughout)*

A hand-held frame is dark in the **corners** and bright in the centre, and it varies
frame to frame because the hands and the lamp move. This is monotonic corner to
corner, its centre block sits exactly between the extremes, and **five pages agree to
within 1.5 luminance levels** — a fixed light source off the axis of a fixed sensor.
Saturation is 0.041 (the classifier's own comment calls near-neutral the flatbed
tell), and the pages are rectilinear with no perspective and no page curl. Rendered
and read: an open booklet on an upright scanner.

Cropping the outer sixteenth — the inset `Flattener.inkOutsideText` already applies,
on the recorded grounds that a scan's platen edge and gutter shadow "is not content" —
takes the median from 0.169 to **0.124**, and the outer eighth takes it to 0.099. That
is *not* the diagnosis, though, and an earlier draft of this entry had it wrong: the
crop lowers the number only because a linear ramp's extremes live at its edges. The
gradient is across the whole sheet.

**What it costs, and why this is not a one-document curiosity.** The threshold is
doing a job nobody asked it to do: it separates *evenly lit* from *unevenly lit*, and
the owner's definition needs *hand-held* separated from *mechanical*. Those differ
exactly on upright-scanner material. Two consequences, neither yet measured:

- **The corpus gate has been excluding it.** `sample-zotero.py` keeps only `scanned`,
  so however much upright-scanner material the library holds, none of it has ever
  been drawn — and the corpus's stated property is "every one of them a scan".
- **The survey's 1,001 `photographed` files are not all photographs.** That figure
  splits Robinson-Montana (815) from Random Photograph (186) and is what puts both
  outside the sweep. Robinson-Montana's own metadata says Acrobat 11 image conversion
  and ImageMagick, which describes the wrapper and not the capture.

**The discriminator this suggests, unbuilt and unmeasured:** the *consistency* of the
gradient across sampled pages rather than its size. A rig repeats; hands do not. The
five pages here agree to 1.5 levels, and that is a number a hand-held set should not
be able to produce. **Do not change the threshold on this document alone** — it wants
the same treatment deskew and columns got: measure it over known hand-held material
(Random Photograph, 186 files, FineReader-made) against known mechanical material
before touching the gate that decides what everything else is allowed to measure.

*Why?* is in the corpus regardless, by the owner's ruling, with the anomaly recorded
in `testdocs/README.md` beside it.

### R54 · `sweep-zotero.py` pools 181 parentless attachments into one pseudo-type — OPEN
*(found 2026-08-13 reviewing the commit it arrived in; not in the app, and not urgent
— the library sweep it serves is scheduled last)*

The survey's `LEFT JOIN` onto the parent item leaves attachments with no parent
carrying a null item type, and they are then grouped together. **181 files** land in
that pseudo-type. The per-type median that the outlier test and the "GB reclaimable"
estimate are both computed from is therefore taken over heterogeneous material for
those files — which is exactly the pooling the tool's own comment says the item types
cannot survive.

It does not corrupt anything and it does not touch a document. It makes two numbers in
the survey wrong by an unknown amount for 181 of 15,901 attachments. Fix it before
step 2 of the sweep reads those numbers, not before the release.

### R53 · R50's own doc comment recorded one miss where there are two — FIXED
*(found 2026-08-13 reviewing R50's diff)*

`textPageInkOutsideThreshold` said "**The one case it misses**" and described only the
pale line drawing, while this register's R50 entry recorded two and
`Tests/main.swift` points *at that constant* as the place the second one — a flat
mid-luminance colour field — is written down. The comment was written before the
second miss was measured and was not brought forward with it.

Stale as such comments go, except for what the cross-reference is holding: it is the
reason the suite's picture fixture is deliberately *tonal* rather than flat. A future
reader simplifying that fixture back to a flat colour plate would produce a test that
asserts the limitation instead of the behaviour, and passes. **Fixed** by recording
both misses on the constant, with the measurement, and by saying on the fixture why
it is the shape it is.

### R52 · Photo detail = Maximum was silently overridden on any page read as text — FIXED
*(found 2026-08-13 reviewing R50's diff, before release)*

R50 shrinks a text page's tone layers with `max(callerFactor, 8)`, on the reasoning
that Photo detail governs photographs and a page with no photograph has none to
govern. That reasoning is right for three of the four levels and wrong for the fourth.

`PhotoDetail.maximum` is a factor of **1** and its blurb promises "photographs keep
every pixel". Under `max(1, 8)` a page the ink signal read as all-text was stored at
**an eighth of its resolution**, with no way to override it — and the signal has two
recorded misses, one of which (a pale line drawing, scoring 0.0000) is a picture read
as text. So the one setting a user picks *because* they care about every pixel was the
one setting that could lose them resolution on the case the signal gets wrong.

**Fixed** by honouring it: at a caller factor of 1 the text-page shrink does not
apply at all. This is `Flattener.Mode`'s existing doctrine — Black & white and
Grayscale are instructions, Automatic is the one that works out what the page needs —
applied to Photo detail, where Maximum is the instruction. The guard is deliberately
narrow: Balanced and below still shrink text pages, and a test holds both halves.

Reproduced first, both ways: with the guard removed the Maximum fixture stores a
1224-pixel-wide page at **153 pixels** and the two new checks fail, while the Balanced
check still passes.

### R51 · Colour layering's stated memory figure omitted its own output buffers — FIXED
*(found 2026-08-13 reviewing R49's diff)*

`statedColourMRCBytesPerPixel` was 19.0, and the accounting written on it — grey
render, RGBA render, stencil, region, inverse, the working plane and its filled copy,
and `fillHoles`'s transients — came to about 14, with the note that "the downsampled
layers are small by construction".

They are, at every Photo detail level except the one that matters. **`PhotoDetail.maximum`
is a factor of 1**, `downsample` returns its input unchanged, and the interleaved RGBA
background is then a **full-resolution 4 bytes a pixel** with `jpegRGB`'s 24-bit
representation another 3 on top. The real figure is **21**, not 14, and the constant
feeds `colourMRCBoundIsWithinTheRenderOne` — a guard, so understating it weakens the
thing it exists to check. At 100 MP the bound had ~4% headroom rather than the ~14% it
appeared to have, times the number of files in flight.

**Fixed** by correcting the arithmetic and the constant to **22.0**. The bound still
holds (100 MP x 22 = 2,200 against the render's 400 MP x 5.5 = 2,200), and colour
layering is additionally capped by `maximumColourPageMegapixels` before a page can be
a colour page at all. Found by reading the code rather than by running out of memory,
which is the good way to find it.

### R50 · The tone layers, not the stencil, were what kept a layered file large — FIXED
*(found 2026-08-13 by asking why R49's output was still 2.17x its original, when the
original also carries page colour and a text layer)*

**The accounting, over all 568 pages of the same book, against the Internet
Archive's own mixed-raster scan of it:**

| | 1-bit stencil (the text) | tone layers (paper and pictures) |
|---|---|---|
| the IA original | 21.74 MB (39.2 KB/page) | **4.26 MB** (3.8 KB each) |
| R49's output | 21.20 MB (39.6 KB/page) | **40.67 MB** (37.3 KB each) |

The stencil was already *better* than theirs and the text layer was already
identical. **The entire 36 MB of excess was the two tone layers**, and 36.4 of the
36.6 MB difference is accounted for by them alone — nothing else contributed.

**It is not the codec.** The obvious suspect is JPEG against the original's JPEG
2000, and re-encoding IA's own decoded layers as JPEG at the shipping quality does
look damning — their 852-byte background costs 18,609 bytes, their 4,914-byte
foreground costs 211,286. But R36 already measured OpenJPEG on ten *real* MRC
backgrounds at matched fidelity and got 1.19x, and both numbers are true at once:
IA is not matching fidelity. They spend **0.0013 bytes a pixel** on a background
where this app spends 0.024 — eighteen times more. Their background is a coarse
colour wash, and on a page of text that is all a background needs to be.

**So the fix is resolution, per page, and only where there is no picture.** A page
whose ink is all text has nothing in its tone layers worth full resolution:

| | background | foreground | page |
|---|---|---|---|
| 2x / 4x, which shipped | 36,383 B | 23,894 B | 99,130 B |
| 8x / 16x | 4,374 B | 3,108 B | **46,332 B** |

At which point the stencil is 81% of the page and the tone layers are 7.5 KB against
the Internet Archive's 5.8 — the right neighbourhood, rather than a number pushed
until it hurt.

**The signal, and why it was available all along.** `isPicture` runs *before*
recognition, so it has only the page's own histogram — and R49 established by
measurement that a histogram cannot separate text from a tinted plate. Layering runs
*after* recognition, where Vision's word boxes exist, so it can ask a structural
question instead of a statistical one: **ink that is not inside any recognised word
is not text.** It costs nothing; the boxes and the render are already in hand.

| | ink outside the words |
|---|---|
| text pages (`Blacks` 41, 163, 244, 520; a synthetic text page) | 0.0000–0.0003 |
| 91 real corpus pages, median | 0.017 |
| a line chart under a paragraph | 0.153 |
| a seal covering 1% of the sheet | 0.250 |
| a photograph covering 8% | 0.694 |
| full-page photogravure plates (`Blacks` 78, 300, 301, 303) | 0.971–0.993 |

**It is a threshold on a continuum, not a gap.** Across the 91 corpus pages the
values run smoothly from 0 to 0.97, and that is stated rather than dressed up. What
makes 0.08 shippable is that *both* ways of being wrong are mild — a page wrongly
held at fine resolution costs bytes and nothing else, and a page wrongly shrunk has
its figure **softened, never removed**. That is the difference from the three
signals refused before it, where being wrong meant thresholding a photograph to
1-bit or deleting it. The nearest hazard sits at 0.153, a factor of two above.

**What it misses**, recorded because it will come up. The signal is ink, so anything
whose luminance sits near the paper/ink boundary is invisible to it:

- a *pale* line drawing reads 0.0000, because Otsu counts light grey as paper;
- a **flat mid-luminance colour field** does too. Measured on a synthetic plate of
  flat red: it renders at luminance 96–111 while Otsu on that page lands at **106**,
  so half the plate is above the threshold and the page scores 0.0365. The suite
  builds a *tonal* plate for this reason, and the reason is written on the fixture so
  the next person does not "simplify" it back.

Neither is alarming, and the reason is that this rule only ever changes *resolution*.
The worst it can do is soften something; it cannot remove it. A flat colour field is
also the one thing that loses nothing to a downsample, so the second miss is
self-cancelling in the common case — what would actually suffer is a detailed colour
image with no dark tones in it, which is why the honest bound on this is "softens a
rare kind of plate", not "is always right".

Corroborating that bound: across the 232-document gate, **every photograph-heavy
document came out byte for byte identical**, so on real material the signal is not
firing where it should not.

**Measured end to end.**

```
                        in       R49 out        R50 out
Blacks in the City    31 MB    68 MB (2.17x)  35 MB (1.13x)
text layer                  1,458,486 B    1,458,486 B — identical, cmp clean
pages layered                    548 of 568     548 of 568
  at 8x / 16x                            0            522
  at 2x / 4x (pictures)                548              8
```

**The 232-document gate, which is where the safety is:** 232 of 232 succeeded,
0 failed, **721 MB against R49's 739 and the 1.11.0 baseline's 792**, characters
34,204,951 against 34,204,969, colour documents 23 either way. Per document,
**209 of 232 are unchanged and not one grew.**

**Every photograph-heavy document in the corpus came out byte for byte identical** —
`Ibson_2006_Picturing men` 19,144,682 both ways, `Noble_1977` 22,503,820, `Schwaller`
19,538,396, `Boltanski_2006` 25,565,129, and `Ehrenreich`, `Findlay`, `Marth` and a
1950 newspaper comic the same. `Countryman` moved 1.3%, on its text pages.

**And it fixes R49's underlying complaint for other documents too.** The documents
that shrank are the low-contrast typescripts and manuscripts the saturation detector
misroutes to the picture path: `Ford_1941_Speech` to 0.200 of its size,
`Atkinson_1939` 0.244, **`Riesman_1954` 7.32 MB to 1.98**, `Jane Stanford 1891`
0.330. Those are the same defect as R49 seen in the corpus, and layering them
properly costs them nothing.

### R49 · 31 MB in, 437 MB out — the one page kind that could not be layered — FIXED
*(reported by the user 2026-08-13 on `Blacks in the City`, an Internet Archive scan
of a 1971 monograph: 568 pages, **31,296,790 bytes in and 437,028,194 out, 14.0x**.
Black & white mode on the same file gives 25,284,288 — smaller than the original.)*

**What the file is.** The input is a mixed-raster IA scan: per page a low-resolution
JPX background, a full-resolution JPX foreground, and a 1-bit JBIG2 `/SMask` that
stencils one over the other. 55 KB/page. The output is one full-resolution
three-channel JPEG per page at quality 0.6 — **769 KB/page**, no layering.

**Why every page came out in colour.** The page renders with its paper at luminance
**128–175, maximum 173**. Nothing reaches `paperLuminanceFloor` (176), so
`paperColour` returns nil, the von Kries correction that exists for exactly this
kind of tinted stock never runs, and the grey-green cast of the paper is then read
as colour *on* the page: saturation **0.088–0.124** against a 0.06 threshold, on
every page sampled. One constant gates both `isPicture` and `shouldKeepColour`, so
the page lost the 1-bit route *and* gained two channels — the same double charge
recorded on `saturation(ofRGBA:)` for the 1964 monograph, arriving through a
different door. That fix was right; it was gated behind a paper detector this
document fails.

**Verified as the file, not the render.** `pdftoppm` and this app's own `renderGrey`
agree to within 2 levels on p41 (both mean 141, both max ≤ 174, both 0.0000 of the
page at or above 176), and both JPX decoders agree the background layer really is a
grey-green field at mean (149, 151, 136). The scan is exposed low. Rendering it is
not the defect — and my own first reading of two side-by-side renders as
*disagreeing* was wrong, corrected by measuring them.

**The fix is that colour pages can now be layered.** `Model.swift` excluded them —
*"A colour page is three channels and its layers have not been measured"* — and that
exclusion was the whole inflation, because the detector had routed every page into
exactly the case layering could not handle. `Flattener.mrcLayers(inColour:)` runs the
same decomposition per channel, reusing `fillHoles` and `downsample` unchanged so
their measured constants still hold, and `JBIG2.assemble` declares `/DeviceRGB` for
the two tone layers from a flag on **the layers**, not on the page: a colour page
whose colour render fails is layered in grey, and reading the page's flag would
declare three channels over one-channel streams and draw the sheet as noise.

Layering keeps the page's colour, keeps its text at full resolution in the stencil,
and `Model` already refuses it unless it is measurably smaller (`after < before`),
so this can only reduce a file.

**Measured end to end through `OCRModel.start()`**, not reasoned about:
**437,028,194 bytes to 67,859,061 — 6.44x** on the reported file, 568 of 568 pages,
548 of them layered and 20 declining it. The text layer is **byte-identical**
(1,458,486 bytes both ways, `cmp` clean), and the rendered page is
indistinguishable: mean RGB (141.1, 142.2, 129.1) layered against
(140.5, 141.7, 128.6) flat, same luminance percentiles to within 1 level. Per page
the three layers cost 110-129 KB against the single JPEG's 669 KB.

The output's structure is now the input's: a background at half resolution, a
foreground at a quarter, and a full-resolution 1-bit stencil over both — which is
what the Internet Archive original does, and it is a fair check on the shape of the
fix that the two agree. It is still 2.17x the original's 31 MB, and the remaining
gap is the tone layers: ours cost 78-91 KB a page where IA's cost 5.8 KB, because
JPEG 2000 on a near-flat field beats JPEG heavily. That is `FEATURES.md`'s R34/R36,
both already declined, and it is not what this entry changes.

**A detector fix was built, measured and refused — this is the part worth keeping.**
The obvious repair is to find the paper anyway: try the absolute floor, and on a page
where it finds nothing, take the bright class of the page's own Otsu split. It works
on this book (saturation 0.10 → 0.025, and 1,174 corpus pages sampled with **zero**
routing changes, because the fallback can only engage on 4 of them). It is still
wrong, and the reason is not a threshold that needs moving:

| | brightMean / darkMean | brightFraction |
|---|---|---|
| the book, low-key text (7 pages) | 3.002–3.458 | 0.896–0.924 |
| a flat sepia field with a dark subject on 12% of it | 2.917 | 0.880 |
| a flat ochre field with a dark subject on 10% of it | 2.459 | 0.900 |
| `Riesman_1954`, a genuinely low-contrast scan | 1.363–1.635 | 0.668–0.775 |
| the full-bleed sepia ramp the suite already guards | 1.157 | 0.511 |

A page of text and a tinted plate with a subject on it are **the same histogram**: a
large flat-ish tinted field with a dark minority. Both candidate discriminators put
the plates on the book's side of the line, and the implemented version was already
neutralising their colour — the very failure `paperLuminanceFloor` exists to prevent,
which the suite's gentler *ramp* fixture does not catch. What separates text from a
subject is **spatial** — many small marks in lines, against one connected region —
and nothing in the tonal signals sees it.

Two further traps found on the way, both instrument rather than code. The white point
is not a discriminator either: the corpus holds a document at **161** that must not be
corrected, *below* the 170–183 of the one that must. And normalising the *tone* signal
by the white point flips 9 corpus pages to 1-bit, among them three handwritten
manuscripts and a 1941 typescript — the destructive direction, and the reason
`pictureInkMinimumTone`'s own note says erring low is the safe way.

So the detector is untouched, deliberately — `Flattener` keeps the routing code it
had. A file may still be routed to colour when it did not need to be; it will now be
*layered* when that happens, which is the outcome that was missing.

**What would actually settle it** is a spatial signal — connected-component sizes over
the thresholded page, where text is thousands of small components and a subject is one
large one. That is the measurement the refused fix wanted and did not have, and it is
worth doing before anyone tries the paper detector again. `FEATURES.md` carries it.

### R48 · `sample-zotero.py` could not build its classifier — FIXED
*(found 2026-08-13 by running it; broken since the direct-Vision migration)*

`build_classifier` compiled a **hand-written list** of eight source files. The app
has more than eight, and the list went stale the moment it grew one: by the time
anyone ran it again the list was missing `Recogniser.swift`, `RunReport.swift` and
`Updater.swift`, and the compile failed with `cannot find 'RunReport' in scope`.

So the script that **rebuilds the test corpus** — the thing `HANDOFF.md` points at
for reconstructing `testdocs/`, which is not committed — had been unable to run
since before 1.11.0, and nothing said so because nothing ran it.

This is the defect `run_tests.sh` already fixed in its own copy, with the reason
written on it: *"It used to be a hand-written list, so a new file compiled into the
app (build.sh globs) and not into the suite — the checks would go green over code
they had never seen."* The same mistake, one directory over, found only because the
library sweep needed the classifier and actually invoked it.

**Fixed** by globbing `Sources/*.swift` less `App.swift`, matching `run_tests.sh`.
The sibling sweep (CONTRIBUTING 4b) asks who else hard-codes a source list:
`build.sh` globs for the app and lists explicitly for the helper — deliberately,
since the helper is a deliberate subset and a wrong entry there is a compile error
in `run_tests.sh` first — and every `Tools/` harness is invoked with its list on
the command line by whoever runs it, so there is no third copy to rot.

### R47 · A new check could have ended the suite instead of failing — FIXED
*(found 2026-08-13 reviewing the engine-assumption checks, before they were
committed; never ran in this state)*

The two-column fixture's guard called `exit(failures == 0 ? 0 : 1)` when the
fixture failed to recognise. That is top-level code in the middle of the file, so
it would have ended the **whole process** there — skipping every later check and
the final summary with them. The run would have reported a green exit over a few
hundred checks that never executed, which is worse than a red one and is the exact
shape of the "passed while testing nothing" failures this register keeps
collecting.

`guard` needs a way out and there is no function to return from, which is how the
`exit` got written. **Fixed** with a labelled `do` and `break assumptions`, so a
broken fixture costs one failed check and nothing else.

Recorded rather than quietly fixed for the same reason R42 is: a suite that can
stop early without saying so is an instrument that lies while passing, and this one
was introduced by the very change that exists to stop assumptions going unchecked.

### R46 · The helper's output was not byte-reproducible — FIXED
*(found 2026-08-13 while explaining a 23-character difference in the corpus gate)*

`JSONEncoder` was used without `.sortedKeys`, so it emitted each observation's
keys in an order that varies **between processes**. Two runs of the helper over
the same twelve page images produced twelve files that `cmp` reported as different
and whose decoded observations were identical to the last digit — same text, same
confidences, same four box components, same total byte count.

So nothing was wrong with the output, and that is the point: **the question could
not be asked.** "Is what this wrote the same as last time" is asked of everything
else this pipeline produces — the gate's own baseline is quoted as "output
byte-identical" — and the one new thing that writes a file could not answer it.
Found only because a 23-character gate delta sent me looking for
non-determinism, and this is what a search for non-determinism turned up instead.

**Fixed** with `encoder.outputFormatting = .sortedKeys`. It also means `cmp` is now
a usable instrument on helper output, which is how the next question of this shape
gets answered in one command.

**The 23 characters remain unexplained**, and are recorded rather than attributed.
Out of 34,204,971 that is 1 part in 1.5 million, with 232 of 232 succeeding and the
output unchanged at 792 MB. Everything directly comparable was exact: the two
routes agree to the last digit on every page tested, and two helper processes agree
on every page tested. What the count measures is PDFKit's extraction from the 232
published PDFs, so a difference of this size could sit in whitespace synthesis on a
single page. `Tools/score-gate.swift` now writes a per-document breakdown next to
the outputs, so the next comparison localises it in one `diff` instead of leaving a
total that says only that something moved somewhere.

### R41 · A run report could say recognition used helper processes when every file fell back — FIXED
*(found 2026-08-13 by reviewing R40's own diff)*

`recognitionInHelpers` was `useHelper && helperPath() != nil`, evaluated when the
report is written. That records the **intent**, not what happened. A helper that
is present but fails on every file — the exact case R40's fallback exists for —
produced a report reading `Recognition runs in: helper processes` over a batch
that ran entirely in-process at 2.5x the time.

The run report exists so that "something was slow last night" can be answered
afterwards, over material that may not be re-scannable. `settingsRows`' own doc
comment says a setting forgotten there makes every later report quietly wrong
about how its documents were produced; this was that, for the one property R40
added. Nothing was lost, but the report misdescribed the run.

**Fixed** by counting the fallbacks and reporting them: `helper processes`,
`helper processes — 3 file(s) fell back to the app`, or `the app itself`. The
callback that reports a fallback is now named `fellBack` rather than the general
`notice`, so a second use of the log channel cannot inflate the count — which is
the sibling this fix had to close, not just the instance.

### R42 · Two fault-injection checks judged one run and described another — FIXED
*(found 2026-08-13 in the same review; the checks were written the day before)*

Three of R40's helper-failure checks called `run(fakeHelper(...))` **twice** —
once in the condition and once in the detail message — so each launched two
processes and reported the second while judging the first. Worse, the `short` and
`garbled` cases passed *different scripts* to the two calls (one had `exit 0`, the
other did not). A case that ever became intermittent would print a message
describing a run that had not failed.

Not a product defect, and recorded anyway: this register's most repeated lesson is
that the instrument is wrong more often than the code, and a check that describes
the wrong run is an instrument that lies while passing. **Fixed** by running once
and reusing the result.

### R43 · `run_tests.sh` blamed the suite when the helper would not compile — FIXED
*(found 2026-08-13 in the same review)*

`run_tests.sh` builds `visionocr-recognise` after the test binary, under `set -e`.
A helper that does not compile aborted the script before a single check ran, and
the pre-commit hook reported **`TESTS FAILED — commit refused`**. The refusal is
right; the diagnosis names the wrong thing, and this project has lost time
repeatedly to a message that points away from the cause (R21 named the wrong
mechanism entirely). **Fixed**: the compile is checked explicitly and says that
the helper did not build and that the helper checks cannot run.

### R44 · The helper's stall bound did not cover a maximal first page — FIXED
*(found 2026-08-13 in the same review; reasoned from measurement, not reproduced)*

`helperStallSeconds` bounds silence, and `lastMoved` starts at launch — so the
bound also has to cover the **first** page, which is the slowest thing that can
happen before any progress arrives. It was 300s. Measured on this corpus,
recognition runs at roughly 0.36s per megapixel (a 4.9 MP book page in 1.77s), and
`Flattener.maximumPageMegapixels` lets a 400 MP page through: **~144s**, which is
under the bound but only by 2x, and the estimate is from ordinary book pages
rather than from a 400 MP sheet.

The consequence was mild — a killed helper falls back and the file still succeeds,
just slowly — which is why this is a bound raised on arithmetic rather than a
defect reproduced. **Fixed**: 900s, with the arithmetic recorded on the constant.
Being too generous costs only later detection of a genuinely wedged helper, and
cancelling already interrupts the wait; being too tight throws away a page that was
working.

### R45 · `alignmentScore` carried a `height` parameter nothing used — FIXED
*(found 2026-08-13 in the same review)*

`Tools/score-skew.swift`'s projection score took a `height` and never read it —
the bin range is derived from the sheared values themselves, deliberately, so the
shear cannot push points off the end of the histogram. A reader would reasonably
assume the bins were page-relative, which is the opposite of the property that
makes the score comparable across angles. Threaded through `estimate` and
`selfTest` as well. **Fixed**: removed from all three.

### R61 · Two declared-geometry conversions still trapped, on the default route — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A7.1 and A3.2. A7.1 is
the sibling A3.2's own §4b sweep missed — same function, four lines from the same guard.)*

`safeInt` exists in `Flattener` because **`Int(_:)` traps for a Double that is not finite or is
outside `Int`'s range**, and R24 is the entry that put it there. Two conversions 1,300 lines
below it were still bare, both on numbers descending entirely from what the file declares.

**A7.1 · `sauvolaMask(…, window: max(Int(dpi / 4), 3))`.** Verified end to end on shipped
defaults — rebuild on, jbig2 and qpdf present, Automatic, one recognised word, a tone wedge to
route the page to the picture path:

```
MediaBox [0 0 1e-14 1.3e-14], image declaring 8000x10400
dpi = 5.76e+19    wide = 8000  high = 10400   product 83.2 MP
flatten gate (<=400MP): true    mrc gate (<=100MP): true
flatten OK -> published 68,950 bytes;  mrcLayers -> EXIT 133 (SIGTRAP)
```

`Int(1.44e19)` against `Int.max` 9.22e18. **Both gates pass because `wide` reduces
algebraically to the declared `/Width`**, so any raster size is reachable at any box scale, and
the page renders as an ordinary sheet with visible ink that `qpdf --check` calls clean. R24's
recorded harm verbatim: uncatchable, and it takes every concurrent file in the batch with it.

**Fixed** by `sauvolaWindow(dpi:width:height:)`, which uses `safeInt` and clamps at **both**
ends. The upper clamp is the second half of the defect and is not cosmetic: at a merely large
DPI the window computed to 3.6e12, so Sauvola's radius covered the whole image and it silently
**degenerated into the single global threshold its own doc comment exists to avoid** — a page
thresholded as though `sauvolaMask` were `otsuThreshold`, with no error anywhere. The ceiling is
half the shorter side.

**And `sauvolaMask` now bounds its own radius**, because `let y1 = min(y + r + 1, h)` computes
`y + r + 1` *first*: an `r` that is merely large overflows there even when the conversion
succeeded. A caller reaching the function without going through the helper would trap inside it.
Its own invariant, enforced by itself.

**A3.2 · `textRegionMask` on a non-finite word box.** `Int((b.x - padX) * Double(w))` over
boxes that come from Vision. **Fixed**: each box's four fields are checked for finiteness and
the box is *skipped* — not clamped, because a box this arithmetic cannot describe is not a
region to include, and including the whole page would put a picture into the stencil, which is
the harm `textRegionMask` exists to prevent. The remaining conversions use `safeInt` and `&+`.

**Sibling sweep (CONTRIBUTING 4b), and it is the whole point of this entry.** The family is one
grep — five `Int(Double)` sites in `Flattener`:

| site | verdict |
|---|---|
| `flatten`'s `max(Int(wide), 1)` | **safe**: guarded by the megapixel check above it, in Double |
| `mrcLayers`' `max(Int(wide), 1)` | **safe**: same shape, `maximumMRCPageMegapixels` |
| `mrcLayers`' `Int(dpi / 4)` | **A7.1, fixed** |
| `textRegionMask`'s four | **A3.2, fixed** |
| `largestImage`'s `Int(w) * Int(h)` | **safe**: `maximumDeclaredImageSide` refuses first |

Two more from the same sweep, both closed here rather than argued about:

- **`textRegionMask` allocated before it checked.** `[Bool](repeating: false, count: w * h)` sat
  on the line *above* `guard w > 0, h > 0`. The guard is first now.
- **`bilevelImage` lacked the `grey.count` guard `greyPNG` and `jpegRGB` both have.**
  `grey[src + x]` indexes to `width * height - 1`, so a buffer shorter than its stated size read
  out of bounds instead of returning nil. No shipped caller mismatches; a missing guard in a
  family of three is R23's and R29's shape exactly.

**How it is tested, which is the part that took the thought.** A trap is uncatchable, so a check
that calls the hostile code cannot be in-process — it would take the suite down instead of
failing. The suite already has that mechanism for R24 (`--probe-hostile-page` re-runs the same
binary on one hostile file and the parent inspects how the child exited), and A7.1 needed a
second mode: `--probe-hostile-numbers` calls the two conversions directly with values a file can
produce and **prints markers**, because exit 0 alone would only prove nothing crashed while the
*behaviour* — an absurd box contributing nothing rather than the whole page — matters as much.
Driving it through `mrcLayers` on the real 8000x10400 fixture was tried and rejected: its
integral images are two `[Double]` of 83.2M entries, **1.3 GB**, and a child killed for memory
is indistinguishable from a child killed by the trap. Reachability is asserted separately and
in-process, because *reading* the DPI is safe and only converting it was not: the fixture's
`rebuildDPI` is checked to exceed 3.7e19, which is what puts `dpi / 4` past `Int.max`.

**Three corrections from the review of this diff, and the first one is the reason the review
happened.** The fix was written, staged and left uncommitted; reviewing it before committing
found that it **also changed the shipped Sauvola window**:

```
sauvolaWindow used  safeInt((dpi / 4).rounded())      <- as first written
the expression it replaced was  max(Int(dpi / 4), 3)  <- truncating
```

`safeInt` truncates, so `safeInt(dpi / 4)` is `Int(dpi / 4)` exactly for every in-range value
and the window is untouched. **`.rounded()` moves it by one pixel wherever `dpi / 4` lands on a
half** — about half of all pages — which is a silent edit to the 1-bit stencil on the default
route, bought for nothing, inside a fix for a trap. That is this project's own recurring shape:
a regression *inside* a fix for something else, which is what CONTRIBUTING's preamble is about.
It is now truncating, a check compares the window against the replaced expression over every
DPI from 72.0 to 600.0 in tenths, and `A7.1-sauvola-window-truncates` plants the rounding back.

The other two were cosmetic and are recorded because both are shapes this register already
carries: the new function was inserted *under* `sauvolaMask`'s doc comment, leaving the
integral-image note describing the wrong function (`sauvolaWindow` now has its own and
`sauvolaMask` has its back); and the new fixture's first check reused the label of R24's
existing `"the hostile fixture is a PDF the app will actually open"`, so two of 880 checks
printed the same line — U29's two-controls-one-name property, in the suite instead of the panel.

### R62 · `inkCoverage` divided one population by another — FIXED
*(found 2026-08-14; `REVIEW-2026-08-14.md` A7.2. Latent, and recorded anyway.)*

It walked all of `grey` and divided by `width * height`. Every sibling fraction in the file takes
numerator and denominator from one population. Told a 4,000-pixel buffer was 20x20 it returned
**10.0** — a coverage above 1 — and told a 100-pixel buffer was 20x20 it under-reported **4x**.

No shipped caller mismatches, so nothing is wrong in the app today. It is recorded and fixed
because of *which* constants a rescaled value would miscalibrate: `pictureInkThreshold` and
`pictureInkMinimumTone` are the two whose miscalibration destroyed content twice, and the next
caller to hand this a downsampled buffer — a tool, a future MRC path — would get a silently
rescaled fraction with no error. **Fixed**: it measures `min(grey.count, width * height)` pixels
and divides by that.

### R60 · Retry Failed publishes over a file the same batch deliberately kept off — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A5.1. **The most severe
finding in that sweep: content destruction, verified end to end, and shipped.**)*

`uniqueOutputs` keeps every output off **every input in the batch**, not merely off the other
outputs, precisely so that re-running a folder which already holds a previous run's results cannot
claim a name another worker is reading. `retryFailures` narrows `files` to the failures and `run`
re-resolves outputs from that narrowed list — **so the sibling that was doing the protecting is gone,
and the retry claims the name that was reserved away from it.** `publish` is atomic; it was atomic
onto the wrong file.

Sequence A, run end to end:

```
dir/scan.ocr.pdf   13,006 bytes, text "PRECIOUS ORIGINAL from the previous run"
dir/scan.pdf       arrives truncated
drop dir, save beside each original, Start
  scan.ocr.pdf -> dir/scan.ocr.ocr.pdf      OK
  scan.pdf                                  FAILS, unreadable
dir/scan.ocr.pdf still says PRECIOUS        <- uniqueOutputs did its job
replace dir/scan.pdf with a readable scan, press Retry Failed
  scan.pdf -> dir/scan.ocr.pdf              OK
dir/scan.ocr.pdf   7,268 bytes, "REPLACEMENT SCAN"   <- the user's file is gone
```

Any per-file failure that does not recur triggers it: a truncated download that completed, an
encrypted PDF once the password is entered, a full or unmounted destination — **or R59's `EXDEV`**,
which means the defect fixed that morning was a trigger for this one. The retry's log says nothing,
and `renamedOutputs` was empty on a retry, so even the "(renamed; another input claimed that name)"
note was absent. Invariant 1 and the spirit of invariant 2 both fail.

**The obvious fix does not work, and that was established by trying it.** Seeding the retry's
`claimed` set with the earlier attempt's `resolvedOutputs` failed its own test twice:

```
FAIL  a retry that carries the first attempt's outputs keeps its own path — scan.ocr.pdf
FAIL  a retry cannot publish over another input's finished output — scan 3.ocr.pdf vs a=scan.ocr.pdf
```

The first failure *is* the defect restating itself: in sequence A the protected path
(`dir/scan.ocr.pdf`) was an **input** of the earlier attempt, never one of its outputs, so carrying
outputs forward does not re-reserve it. The second is over-reservation: the retried file's *own*
previous slot is in that set, so it is pushed to a **third** name — and would be renamed again on
every retry.

**Fixed** by carrying both halves and giving one back. `uniqueOutputs` takes `alsoClaimed` (the
earlier attempts' inputs *and* outputs, accumulated as a set of paths so a third attempt still
remembers what the first reserved) and `releasing` (each retried input's own slot from the previous
attempt, so it is reused rather than renamed). An input of the *current* batch outranks a release,
because a path being read right now is the case the function exists for. The state lives in
`claimedByEarlierAttempts` and `previousOutputs`, and `continuesRetryChain` is what tells `run`
whether this batch continues the previous one's chain or begins a new one.

**A correction to the fix direction A5.1 recorded.** It says the state must be "cleared whenever the
user changes the file list — through both `add` overloads, `remove` and `clearFiles`". It must not
be: **clearing at a door reopens the defect whenever a retry follows the door.** Drop the folder,
have one file fail, add an unrelated file, press Retry Failed — the list changed, so the reservations
would be gone and the retry takes the protected name again. `remove` has the same hole with any third
file. The chain instead ends where a chain can actually end: at a **Start that is not a retry**,
which is also where `run` already clears `outcomes`, `stages` and the log. A `continuesRetryChain`
property rather than a parameter threaded through `start`, because `start` reaches `run` through five
branches and an async pre-flight, and a sixth branch added later would default to "a new chain" —
the safe direction for over-reserving and the *unsafe* direction for this defect. The three branches
that decline to run clear it.

**Not a defect, and worth writing down because it looks like one.** After a run, removing the
previous output from the list and pressing **Start** does replace it. That is the ordinary re-run:
`publish` has always replaced a previous run's output, and the file is that input's own output. What
made the retry case destruction is that the batch had just reserved the path *away* from the very
file that then took it.

**Sibling sweep (CONTRIBUTING 4b): who else runs a subset of a previous batch?** Nothing else does
today — `retryFailures` is the only narrowing door, and the other three (`add`, `remove`,
`clearFiles`) only ever change the list before a run. The shape to watch for is any future feature
that runs part of a list the app has already resolved outputs for; `alsoClaimed`/`releasing` is the
mechanism it should use.

### R63 · Cancelling a Plain Text run reports every in-flight file as **failed** — OPEN
*(found 2026-08-14 by the adversarial pass over R60's own diff — the eleventh round running in
which reviewing a round's code found a real defect near it. Verified by reading both sides.)*

The text route's `do`/`catch` in `run`:

```swift
try Recogniser.extract(from: file, to: target, …, isCancelled: { control.isCancelled })
if control.isCancelled { report(.cancelled, "Cancelled.") }
else { report(.succeeded, "") }
} catch {
    report(.failed, error.localizedDescription)      // <- no cancellation check
}
```

`Recogniser.extract` raises a cancel as `throw Failure.cancelled` — five sites do — so a user
Cancel lands in that `catch` and is recorded as a **failure**. The *success* path checks
cancellation two lines above; the failure path does not. The searchable route gets this right in
both of its catches, and its comment says why: "A cancellation surfaces here as a throw … and is
a cancellation rather than a broken file."

**The report contradicts itself**, which is what makes it worse than a wrong enum:
`Failure.cancelled.localizedDescription` is "Cancelled.", so the row shows a red ✗ and the tally
counts a failure while the message beside it says the run was cancelled. `problemCount` then
reports it, the results pane sorts it to the top as a problem, and **`canRetryFailures` offers to
retry work the user asked to stop** — a cancelled file is deliberately *not* a failed one
elsewhere in this model, which is asserted by "a cancelled file is not retried".

This is **R14's recorded shape** at the one site R14's sweep did not reach, and it sits with the
other text-route cancellation gap already open from A2.2: `extract` writes straight to the user's
destination with no staging, so a cancel during the last page finishes it, replaces the previous
output, and *then* reports. Both belong in one fix of the text route's cancel handling. Not fixed
here: R60's diff is about output-path reservation, and folding an unrelated route's cancel
semantics into it is how C13 and C14 were shipped inside other fixes.

**One asymmetry found reviewing this diff before merging it, recorded rather than changed.**
`uniqueOutputs` compares paths through `key()` — `standardizedFileURL.path.lowercased()` —
because area 5's own sound-list notes that `standardizedFileURL` is load-bearing here: a folder
walk yields `/private/var/…` where a drop of the same file yields `/var/…`. The new
`previousOutputs` map is the one place in the fix that does **not** normalise: it is
`[URL: URL]`, so `releasing = Set(batch.compactMap { previousOutputs[$0] })` is a lookup by
`URL`'s own `Hashable`, and two spellings of one path miss each other.

The consequence is bounded and is in the safe direction. A missed lookup means the retried file
does not get its own previous slot back, so it is pushed to `scan 2.ocr.pdf` and the rename is
announced through `renamedOutputs` — **over-reserving, which renames visibly; never
under-reserving, which is what destroys a file.** It is also not reachable today: `retryFailures`
builds its list from `outcomes`, whose keys are the same `URL` values `files` holds, so both
spellings cannot arise within one chain. Left alone because a check that bit it would have to
manufacture two spellings of one path through a real retry, and the direction it fails in is the
one this whole entry exists to stay on. **If a future door ever puts a re-spelled path into
`files` — a bookmark restore, a resumed batch read back from disk — key this map through `key()`
first.**

### R64 · The run report carried the document's own text — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A4.1. Highest
severity per line changed in the sweep.)*

The unplaced-lines failure message was built out of the recognised text itself —
`p\(page) "\(text.prefix(24))"`, up to three lines — and that message goes `report(.failed:)`
→ `log` → `RunReport.text`, which copies the log **verbatim** into
`~/Library/Logs/VisionOCR/Run <ts>.txt`. So up to **72 characters of the user's document,
with the page numbers to locate them by**, landed in a file whose own docstring calls it one
"that gets mailed to whoever is helping you". The report is written **by default**, and the
same string is spoken aloud.

**Fixed** by `OCRModel.unplacedSummary`, which reports the count, the pages and the reasons
and nothing else. Extracted into a function precisely so it can be asserted: the message used
to be built inline in the middle of `makeSearchablePDF`, where nothing could see it.

**Invariant 1 is untouched, and that is the part worth checking rather than asserting.** A
privacy fix that quietly stopped naming the loss would trade a leak for a silence, which is
the worse defect in this project's own ordering. The checks hold both halves: the count, both
page numbers, the reason and the `…` elision above three are each asserted present, and two
further checks assert the text is absent — one for whole words, one for the exact 24-character
prefix that shipped, because a check looking only for the full string would pass against the
defect.

**Verified by running.** With the shipped body restored the two absence checks go red and the
four presence checks stay green, and the failure detail prints the leak verbatim:
`p3 "Kaczynski to Ellsberg, 1" (no room)`. Mutant: `A4.1-unplaced-carries-text`.

**Sibling sweep (CONTRIBUTING 4b).** Every other interpolation into a `LogLine` was checked:
they carry file names, page numbers and byte counts, never recognised text.
`SearchableWriter.joiningHyphenatedWords` does print document text —
`reject: tail not lower-case (\(tail.prefix(14)))` — but only to **stderr** and only when
`JOIN_DEBUG` is set in the environment, so it reaches no file and no report. That is the shape
any future text logging should take, and `RunReport`'s docstring now says so.

**What stays in the report, now written down** rather than left to be rediscovered: absolute
paths of every input and output, every file name in the batch, the destination folder, the
custom-words list verbatim, and qpdf's stderr with its file-name prefixes. A user pasting a
report into a bug report leaks their short name, directory layout and every document name.
All of it earns its place — it is what makes the file worth having after an overnight batch —
so it is documented in `RunReport`'s own docstring instead of being trimmed. The password is
excluded and a check asserts it never appears. **Not fixed here, and still true: there is no
rotation and no cap — one report per batch, forever.**

### R65 · A retry declined at the alert left the batch gutted — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A5.2.)*

`retryFailures` narrows `files` to the failures and erases every verdict, and it has always
carried a put-back for the case where `start` then declines — with a comment saying why:
"reasoning about which refusals are possible is how U21 happened". **The put-back never ran.**
It was gated on `guard isCommitted`, and under the shipped defaults `start()` returns with
`isPreflighting` already true, so `isCommitted` is true, the guard passes, and
`retryFailures` reports success. Every refusal arriving *after* the pre-flight left:

```
Retry Failed -> pre-flight finds born-digital -> alert -> Cancel
log:      "Start cancelled — nothing was changed."     <- false
files:    [failed.pdf]      the sibling that succeeded is gone from the list
outcomes: 0                 every verdict erased
canRetryFailures: false     the record of what failed is unrecoverable
```

**Fixed** by holding the cleared state in `retryPutBack` and releasing it from
`abandonRetry()`, which is called from every path that declines after the narrowing: `start`'s
own first guard, the pre-flight's Cancel, and the Skip Those branch that leaves nothing to
run. `run()` drops it instead of restoring it, because a run really beginning is the one exit
that is not a decline.

**Those are exactly the paths that clear R60's `continuesRetryChain`, and that is the load
bearing part of this fix rather than a coincidence.** A retry chain continues if and only if a
run began, which is the same condition as "there is nothing to put back", so the two are
cleared together in one function and neither can acquire a new path without the other being
considered. R60's own entry had already had to enumerate those paths; this reuses that
enumeration instead of re-deriving it.

Everything the function clears is captured — `files`, `outcomes`, `stages` and `skipped` — so
the log's "nothing was changed" is true of the rows and the progress labels as well as of the
list.

**The check that existed for this could not fail.** `"…and puts the whole batch back"` drove
the *first* guard: with no destination `canRetryFailures` is false, so `retryFailures` returns
before it has narrowed anything, and the assertion compared a list nothing had taken away.
That is the eleventh un-failable check found in this project, and it was guarding the one
thing A5.2 is about. The new block drives the real path — a born-digital fixture, the
pre-flight, `digitalTextDecisionForTesting` returning `.cancel` — and **asserts the premise
first**: that the list really was narrowed to `[failed.pdf]` at the moment the alert went up,
so the restore below has something to restore. Mutant: `A5.2-cancel-puts-back`.

### R66 · The import interlock was a flag, so the first drop to land lowered it — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A5.3.)*

`isImporting` was a boolean set true by every `add` and false by every completion, so with two
drops in flight the **first** completion cleared it while the other walk was still going:

```
at the moment the small import lands: isImporting = false, canStart = true
Start -> batch total = 1
the large walk completes -> REFUSED, "a run is in progress"
```

and with a fast batch the walk instead lands *after* `finishUp`: **8,001 rows over "Done — 1 of
1 succeeded"**, which is U1 verbatim for the fourth time. **Fixed**: `importsInFlight` is a
count, incremented by `add` and decremented by each completion, and `isImporting` derives from
it. The decrement is `max(0,)` so a stray extra completion cannot drive it negative and leave
the interlock permanently *down* — the same failure one layer along.

**And the interlock was enforced only where the button is drawn.** `start()` never checked
`isImporting` at all, so it existed for `canStart` and for nothing else, and `clearFiles()` was
not interlocked either — measured 0 → 8,000 files after a Clear the user explicitly asked for.
Both now check it. U19 and U23 are the two entries about precisely this shape, and this is the
third.

**The test needed no race.** The review's scenario used an 8,000-file walk to make the window
observable by hand, but both `add` calls dispatch before either completion can run, so two
walks are in flight by construction; four small fixtures prove it. The assertion is
order-independent — *whichever* import lands first, one is still outstanding — so it cannot be
a flaky timing check. The three door checks each get their own model, because sharing one made
two of them pass for the wrong reason: `start()` got through, set `isRunning`, and `clearFiles`
then refused on the `isCommitted` guard it already had. A green check over an unguarded door,
decided by the defect in the check above it. Mutants: `A5.3-import-count`,
`A5.3-start-checks-importing`, `A5.3-clearFiles-importing`.

### R67 · One line in a login startup file cost JBIG2 for the whole session — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A9.1.)*

`askLoginShell` ran `$SHELL -lc "command -v jbig2"` and trimmed **all** of stdout — but
`zsh -lc` sources `.zshenv`, `.zprofile` and `.zlogin` onto that same stdout *first*:

| startup file | `locateTool` |
|---|---|
| quiet | the path |
| `echo "Last login: …"` | **nil** |
| an nvm version notice | **nil** |
| backgrounds a daemon | **nil** (no EOF, 3.00 s) |

The nil is then **memoised for the session** in `discovered`, so `JBIG2.isAvailable` goes
false, `wantsJBIG2` goes false, and **every page in every batch takes the Flate route at
roughly 3x the size** until the app is relaunched — while Settings shows its "Not installed"
hint, naming a remedy the user has already applied. The user's own dotfile, one `echo`, no
error anywhere.

**Fixed**: take the **last** line. `command -v` prints its answer after the startup files have
had their say. `isRunnable` still validates it, so the last line of pure chatter is refused
exactly as the whole blob was — which is the half worth checking, because "take the last line"
could otherwise replace one way of believing the wrong thing with another. Five checks: chatter
before a real path, a multi-line version-manager notice, chatter whose last line is not a tool,
chatter with no path at all, and the pre-existing unrunnable-path refusal.

**Not fixed, and now written down in the code**: `tcsh` and `csh` have no `-lc`, so this route
finds nothing for anyone whose `SHELL` is one of those. They fall back to the bundled tool and
the three standard prefixes, which covers every supported install. The daemon-backgrounding row
above is not a line-selection problem and is still handled by `captureBounded`'s bound.

Mutant: `A9.1-loginshell-last-line`.

### R68 · The report's JBIG2 row was the checkbox, not the route — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A9.2.)*

```
defaults, tools installed    report: on    wantsJBIG2() = true
Rebuild page images OFF      report: on    wantsJBIG2() = false
mode grayscale               report: on    wantsJBIG2() = false
tools not installed          report: on    wantsJBIG2() = false
```

**Three of four states reported "on" about a step that did not run**, and R67 reaches the
fourth invisibly. The difference is about 3x in file size, so the report was denying the one
thing a user would open it to check. `usedJBIG2` already existed as a local in
`makeSearchablePDF` and never left the function.

**This is R41's defect, one row below R41's fix.** R41 corrected the *recognition* row from the
configuration to the outcome, and added `recognitionFallbacks` to make it true rather than
intended. The row underneath kept the old shape. So the repo held an outcome-shaped and a
setting-shaped answer to the same question — `Runner.previewLines`, in the other file of this
same review area, gets it right — and the report took the setting.

**Fixed** the same way R41 was: `tookJBIG2Route`, a callback shaped exactly like `fellBack`,
counted into `Context.jbig2Files`, and the row reads

```
JBIG2 compression         on — 12 of 12 file(s)
JBIG2 compression         on, but no page took that route — the pages are Flate compressed, which is larger
JBIG2 compression         off
```

Counted **on the success path only**: a file that entered the route and then failed published
nothing, so counting it would make the report claim a compression no file on disk has.
`Context.jbig2Files` deliberately has **no default value**, so every construction site has to
supply it — R41 is what happens when one can be forgotten, and the compile error that came out
of adding it is the mechanism working.

Four checks, including the inverse row (a count cannot resurrect a setting that was off) and
the existing 4d enumeration that every `Snapshot` field maps to a row. Mutant:
`A9.2-jbig2-row-is-the-route`.

### R69 · Extract Text could be made to silently OCR a picture of good text — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A10.1.)*

The born-digital pre-flight applies in **Extract Text** as well — `couldReadInstead = mode ==
.text` — but the only control bound to `warnDigitalText` was drawn inside
`case .searchablePDF:` **and** `if rebuildImages`. Measured against the real `start()`:

```
TEXT mode, warn=on,  rebuild=on   -> alert fires
TEXT mode, warn=on,  rebuild=OFF  -> alert fires
TEXT mode, warn=off, ...          -> no
```

**The trigger.** Work in Extract Text. Drop a born-digital PDF, get the alert, tick **Don't
ask again**. From then on Extract Text silently OCRs a picture of text the file was carrying
perfectly well — the loss the alert's own wording puts at **9% of the words** — and **no
control in the panel can turn the question back on**, because the only one lives in the other
mode, under a toggle that mode does not have. The routes back were Reset to Defaults, or
switching mode, opening Settings, and switching back.

U19 and U23 are entries about a property enforced only in the view. **This is the inverse: a
live setting *hidden* by the view in a state where it still applies.** Both are fixed the same
way — `OCRModel.warnsAboutDigitalText(mode:rebuildImages:)`, one function, read by `start()`
and by the panel, so neither can hold a second opinion. The toggle moved out of the `switch`
and is guarded by that predicate.

**And the alert named a harm that cannot happen there.** "Rebuilding the pages as images
discards that text" is false for Extract Text, which rebuilds nothing and discards nothing —
`start()`'s own comment says so. A message describing destruction that is not on offer pushes
the user toward Cancel for a reason that does not exist, which is A3.3's shape in an alert
instead of an error. The wording is now mode-aware and keeps the 9% figure, which is the real
cost in both modes. *(A5.4 recorded this as a `json`/`jsonl` problem; it was wrong for every
Extract Text format, because `digitalTextWarning` took no mode at all.)*

Checks: the four-state table through the predicate, the panel-source check that the toggle is
inside that guard, the real `start()` driven in Extract Text with the rebuild **off** — the
state the review measured — and six on the two wordings. Mutants:
`A10.1-warn-applies-in-text`, `A10.1-alert-wording-by-mode`.

### R70 · "PDF render DPI" is inert on the default route and said otherwise — FIXED *(the panel)*
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A10.2.)*

Its only reader is `Recogniser.render`, reached only when `bitmaps` is empty — and with the
rebuild on, every page arrives as a bitmap from `flatten`, which takes no DPI at all:

| | Auto | 72 | 600 |
|---|---|---|---|
| chars, rebuild **on** | 1431 | **1431** | **1431** |
| chars, rebuild **off** | 1431 | 1407 | 1431 |

**Fixed as a caption, not a code change**, and the distinction matters: H1 deleted
`ocrAllPages` and `strategy` for being settings that did nothing, and this is not that — it is
live in Extract Text and in Searchable PDF with the rebuild off, i.e. in two of four states.
What was wrong was the panel asserting it unconditionally while `pageTooLarge`'s own error
text already said the setting "does not affect this step": the app holding two opinions about
one control. The help text now names the states it applies in, and a caption appears under the
stepper when the current state is not one of them.

### R71 · Two presets are byte-identical and one of them claimed otherwise — FIXED *(the prose)*
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A10.3.)*

Fingerprinted over every key a preset may write: **Newspaper and Book scan write exactly the
same eight values, and both equal `register()`'s own.** Typescript differs in one bit
(`languageCorrection`), Photographs in one (`photoDetail`). So of four buttons, two are
"restore the defaults" under names that say which material those defaults suit.

**The code is honest about this and the blurbs were not.** Newspaper promised it "keeps every
uncertain word, because a rough guess at a smudged word is still findable" — which is
`confidence = 0.0`, the registered default, and true of every other preset too. The class doc
already states the rule the code follows ("where nothing has been measured the preset leaves
the setting alone"), so the fix is the prose.

**Not fixed by inventing differences.** Giving Newspaper a distinct value to justify its blurb
would be calibrating a constant to make a sentence true, which is this register's own worst
recurring mistake.

**The check maintains itself.** The old guard compared **one key**, only Photographs against
Newspaper, so it said nothing about the other five pairs. The new property is: *a preset that
writes exactly the defaults has to say so in its blurb*, the way Book scan already did. Give
Newspaper a real distinct value later and the fingerprint stops matching, so the requirement
lifts on its own. Plus a check naming which pairs are identical, and an inverse row so it
cannot be satisfied by an `apply` that writes nothing. Mutant: `A10.3-newspaper-blurb`.

### R72 · The updater opened whatever URL the response body named — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A4.2.)*

`Updater.parse` accepted any `URL(string:)` for `html_url` and `ContentView` handed it straight
to `NSWorkspace.shared.open`. Verified against the real parser:
`file:///Applications/Calculator.app` accepted, `x-fake-handler://run?cmd=…` accepted,
`https://not-github.example/evil` accepted. So whoever controls the response body could make
the Download button open an arbitrary local file or any registered scheme handler.

**Fixed** by `isOfferableURL`: `https` only. Refused as `.unreadable` rather than
`.notAnOffer`, because a response this app cannot trust is a *failed* check — `notAnOffer`
would mean the endpoint answered and had nothing, which stops the retry (U25's
ninety-six-requests-a-day case).

**The host is deliberately not pinned, and that is a decision rather than an omission.** `https`
alone closes the two cases where opening the URL does something other than show a web page. A
host pin would additionally refuse `https://not-github.example/evil`, whose marginal harm over
publishing a malicious GitHub release page is nothing — an attacker who can rewrite this
response can rewrite the page it points at. Against that, a pin is a second place to edit if
the release page ever moves, and its failure mode is that updates stop being offered with no
error anywhere, which is the shape most of this register already is. Six checks, including the
inverse row that an ordinary `https` page is still offered and that the predicate is
scheme-based rather than host-based. Mutant: `A4.2-update-url-scheme`.

*(A4.2 also records that `release.notes` is parsed, unbounded at 200,000 characters, and never
displayed. Still true, still harmless, and still worth deleting when the notes get a surface.)*

### R73 · A NUL in *Languages* or *Custom words* aborted the whole app — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A13.1. The one real
defect in the area that came out **sound** on the strongest evidence in the sweep.)*

`Process.arguments` goes through `fileSystemRepresentation`, which raises
**`NSInvalidArgumentException`** for a string containing U+0000. An Objective-C exception is
not a Swift error, so the `do/catch` around `process.run()` does not catch it: SIGABRT, exit
134.

```
customWords has a NUL: false -> succeeded, published
customWords has a NUL: true  -> NSInvalidArgumentException, libc++abi: terminating (134)
```

`report` is never called and `fellBack` is never called, so `makeSearchablePDF`'s "the report
callback is called exactly once per file" is broken as well.

**The asymmetry is exact, and it is why this is worth a guard rather than a note.** The same
snapshot recognises perfectly *in-process*, and `useHelper` is `helperIsWorthIt` — so **a
one-file batch works and a two-file batch kills the app**. It also persists: `UserDefaults`
round-trips the NUL, so every multi-file batch aborts until the user finds and clears an
invisible character in a text field. Reachability is low and unproven at the UI — typing a NUL
is impossible, pasting is the route — but this is the one thing the file promises cannot
happen: `HelperFailure`'s docstring says "every case falls back", `helperName` says "the worst
a broken helper can cost is time", and `ARCHITECTURE` says "the helper is never authoritative
about failure". All three were false for the *launch*.

**Fixed** by refusing before the launch and falling back, which is what every other
`HelperFailure` does. Not sanitised: a NUL in a languages list is not a recognition setting the
user meant, and in-process recognition honours the same snapshot without launching anything.

**§4b made it a single-site fix.** Of five `Process.arguments` in `Sources/`, the other four
carry only paths and constants — and A4.3's password fix had already removed the second
free-text exposure.

**Fuzzing decided the scope.** 16 candidates in child processes: **only NUL does this.**
U+0085, U+2028, U+FFFF, a bare CR, ZWJ emoji, an RTL override and 256 KB arguments all launch;
a ≥1 MB list gives a *catchable* Swift error that already falls back correctly. So the guard is
two characters wide on purpose, and five inverse checks assert the others still reach the
helper — a guard that refused them would turn a crash into a permanent fallback to the slow
path, which is R40's 2.5x.

**Where the NUL sits decides which of two defects you get, and the review recorded only the
first.** Measured with a four-case probe against the real `Process.arguments`:

```
"en-US\0"        ran, exit 0     silently truncated to "en-US"
"\0"             ran, exit 0     silently became an empty argument
"Bolt\0Latour"   exit 134        uncaught NSException, SIGABRT
"\0en-US"        exit 134        likewise
```

So it raises **iff something follows the NUL**, and a NUL in the final position instead changes
the value the user asked for without saying so — a languages list quietly not being the one in
the text field. A13.1 said "a string containing U+0000" and that is true of the abort for most
placements but not all. Both are refused, because both are wrong: one kills the batch and the
other silently recognises with settings nobody chose. Five checks, one per placement.

**The mutant shows both halves at once, and finding that out corrected this entry.** The first
draft asserted that removing the guard makes the suite abort *instead of* failing a check. The
mutation log says otherwise:

```
FAIL a NUL at the end of languages is refused… — it succeeded, so the NUL reached Process.arguments
…
libc++abi: terminating due to uncaught exception of type NSException
exit=134
```

One red line from a truncating case, then the abort from an embedded one. Written down because
the wrong version of this sentence was already in the file, and reading the mutant's own saved
output is what replaced it. Mutant: `A13.1-nul-in-settings`.

### R74 · A document Vision read nothing from published as a silent success — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A13.2.)*

`recogniseDocument` records `[]` for a blank page so `missingPages` can tell a skip from a blank
(C12) — and nothing checked the *other* side: a document whose every page came back empty.

```
observations [1: 0, 2: 0]   missingPages []   -> succeeded, published, message=""   0 chars
```

Right for a genuinely blank scan. **Wrong for R56 and R57, both open and both on the default
route** — a pale drawing erased, or a page blobbed to solid black, produces exactly this
signature, and on a one-page document the user was told it succeeded and told nothing else.

**The sibling already answered this question.** `writeEmbeddedText` reports "N page(s) carry an
image with no text and were not read", with the comment "Invariant 1: this path can drop a
page, so it says which." Same question, answered in one route and not the other, which is C20's
shape.

**Fixed** as a note on success, not a failure: a blank page is a legitimate thing to find, and
refusing to publish would make an empty scan unprocessable. The note names the page count and
points at the two open routing defects, so a user seeing it has somewhere to go. Four checks,
including the inverse row that an ordinary document does **not** carry the note — without which
this would be noise on every run. Mutant: `A13.2-empty-document-says-so`.

### R75 · The manifest's newline guard missed every newline but one — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A13.3.)*

`unusablePaths` checked `contains("\n")`. A path *ending* in CR passed it, and in the joined
manifest that CR merges with the separator into a single Swift `Character` (`"\r\n"`), so the
helper's `split(separator: "\n")` does not split there — **3 paths sent, 2 lines parsed**.

**No content is lost**: the merged line names no file, the helper exits 4, and the app falls
back. But it is the *count* check that saves it, not the guard, and the guard's own comment says
it exists for the future in which "something hands the pipeline a page image named by the user"
— exactly the future in which it is insufficient. **Fixed**: `rangeOfCharacter(from: .newlines)`,
which is deliberately broader than the parser needs (it also refuses U+2028 and U+2029), because
the cost of over-refusing a path this app generates itself is nothing and the cost of
under-refusing one is a silently short list. Four checks, one per newline form. Mutant:
`A13.3-newline-guard-is-every-newline`.

### R63 · Cancelling a Plain Text run reported every in-flight file as failed — FIXED
*(found 2026-08-14, late, and **recorded nowhere until now** — see the note at the end of this
entry, which is the more useful half of it.)*

The Extract Text route caught everything and reported `.failed` with the error's description.
`Recogniser.extract` throws `Failure.cancelled` when the user cancels, and that error's
description is **"Cancelled."** So pressing Cancel put a red ✗ against every in-flight file,
with "Cancelled." given as the reason it *failed*:

```
outcome: failed    message: "Cancelled."
```

It is not only cosmetic. Those files are counted as failures in the run report, and they stay
in `failedFiles` — which is exactly what **Retry Failed** offers to re-run, so a cancel left the
user holding a batch that claims it broke.

**The searchable route already gets this right in seven separate places**, each with its own
comment saying why — R14: "a cancelled jbig2 child surfaces here as a throw, and is a
cancellation, not a broken file." The eighth site, on the other route, had none. **Fixed** by
making that rule a function, `OCRModel.outcome(for:cancelled:)`, so a ninth site cannot hold a
different opinion. Four checks, including the inverse row that a genuine failure during a
cancelled batch is still a failure — otherwise cancelling would paper over every broken file in
the run. Mutant: `R63-cancel-is-not-a-failure`.

**Where this entry came from, because it is a process finding as much as a defect.** R63 existed
as **one sentence of prose in an uncommitted `TODO.md`** and nothing else: no register entry, no
`REVIEW` entry, no evidence, no reproduction, nowhere in the repo or in any worktree. The
session that found it was cut off before writing it down. Everything else that session left
behind was recoverable from git in minutes; this was not recoverable at all, and had to be
reproduced from scratch to be fixed. **A defect that exists only as a sentence is a defect
nobody can act on** — the register entry is the artefact, not the observation.

### R76 · A cancelled text extraction still replaced the user's previous output — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A2.2, text half. The
searchable half is R59.)*

`Recogniser.extract` checks `isCancelled` only at the top of each **page**, so a cancel arriving
during the last page finished it and fell straight through to
`Data(body).write(to: target, options: .atomic)` — **the user's destination, with no staging and
no publish.** Verified end to end: a previous run's `.txt` replaced by the text of a run the user
had stopped.

```
cancel fires after the last page
before: "PRECIOUS OUTPUT from the previous run"
after:  "First page of the extraction test."      <- the cancelled run's output
```

**Invariant 2 says never write directly to the user's destination**, and this is the route that
does it. `.atomic` makes the replacement indivisible; it does not make it wanted. For the
single-page inputs this mode usually gets, the cancel window is the whole run.

**Fixed** by asking again immediately before the write, in `extract` rather than only in
`Model`: `extract` is what touches the file, and a caller that forgot to re-check would be back
to publishing a cancelled run. That is the same placement the searchable route uses for its own
publish. Three checks, including the inverse row that an uncancelled extraction still writes —
without which the guard would be satisfied by a route that never produces anything. Mutant:
`A2.2-text-cancel-before-write`.

*(A2.2's searchable half — the 0.38 s–7 s window between the last cancellation check and
`publish` — was closed by R59's `publishVerified` guard, and the review's own text says so.)*

### R77 · `stop` gave up on an exited child, stranding the grandchild — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A9.3, A9.5, A9.6.)*

**A9.3.** `Runner.stop` opened with `guard process.isRunning else { return }` — and an exited
child is *exactly* the case `captureBounded`'s own comment describes: "no EOF inside the bound
means something is still holding the pipe", which if it is not the child means the child has
finished and something it started has not. Once Foundation reaps the child, `getpgid` fails and
the group is unrecoverable, so the grandchild lives on with nothing referring to it. Verified: a
`sleep 30` outlived `stop` entirely, and a manual `kill(-pgid)` would have collected it.
`SettingsView` calls `forgetToolPaths()` on every appear, so this was **one stranded process per
tool name per Settings open**.

**Fixed** by reading the group while the child is certainly alive — at launch in
`captureBounded`, at adoption in `RunControl` — and passing it in, so `stop` can signal a group
it can no longer look up. PID reuse is the argument against signalling a group you cannot see;
it is bounded here because `knownGroup` is only ever passed within one capture window, and
`processGroup(of:)` only returns a group the child led.

**The check for this existed and asserted only `took < 5`.** The fixture *creates* the leak —
`(sleep 30 &) ; echo partial` — so the suite has been manufacturing a stranded process on every
run and calling it a pass. It now records the grandchild's own pid and asks `kill(pid, 0)`
whether it is still there, which is a question about that process rather than a pattern match
against the machine. Mutant: `A9.3-stop-collects-the-group`.

**A9.5.** `cancel`, `adopt` and `cancelAll` all sent a bare `terminate()` — no wait, no
escalation — so a child ignoring SIGTERM survived Cancel *and* quit, and `adopting`'s `defer`
then unregistered it: alive and unreferenced. R21 built the escalation and `ARCHITECTURE` claims
this path uses it; nothing called it. **Fixed**: SIGTERM to everything synchronously (immediate,
reaches the group, and it is what makes Cancel feel like Cancel), then `Runner.stop` **off the
main thread**, because `stop` waits per child and `cancel()` is called from the UI and from the
quit gate — doing it inline would trade an orphaned child for a frozen window, which is A9.6's
defect in a new place. On quit the escalation is best-effort by the same decision `cancelAll`
already records; the synchronous `terminate()` is what does the work there.

**A9.6.** `captureBounded` had **no byte cap**: bounded in time, unbounded in memory. Measured
with `cat /dev/zero` for the window, peak RSS went from 9 MB to **1,985 MB**. `drain`'s other
caller caps its accumulator explicitly and says why. **Fixed** with a 1 MB cap — four orders of
magnitude more than the longest legitimate answer, which is one absolute path — and the cap
*stops* the drain rather than truncating, because whatever is on the other end is not answering
the question asked.

Its bound was also applied twice in series plus `stop`'s grace, worst case `2 × seconds + 2`:
**7.98 s measured on the main thread**, and about 16 s of frozen UI with two tool names and
`forgetToolPaths()` per Settings appear. `stop` now gets `graceSeconds: 0.5` from here, since the
child has already had SIGTERM and its answer is being discarded anyway.

**Asserted through time, not memory.** The cap makes the drain stop when it trips, so a
five-second bound ends in well under five seconds. `ru_maxrss` is the instrument this project has
already been burned by (A3.1) and it would read a multi-phase suite as a sum of peaks. Mutant:
`A9.6-capture-byte-cap`.

### R78 · Four smaller reporting defects, one of which could destroy a report — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A9.4 and A9.7.)*

**A9.4 · the report claimed helper processes over a run that launched none.**
`recognitionInHelpers` was computed with no reference to `isSearchable`, and the text route calls
`Recogniser.extract`, a function with no helper parameter at all. `recognitionFallbacks` stays 0
because nothing fell back when nothing was tried, so the qualifier that would have made the row
honest never appeared either. **R41's own defect, restored inside R41's own row**, for a
different reason. Fixed at the call site *and* in `settingsRows`, which now treats Extract Text
as "the app itself" by construction — the row is a property of the route, and R41 is the entry
about a row that reported the configuration instead.

**A9.7 · `unusedPath` → `write` was time-of-check-to-time-of-use.** It asked whether a name was
free and then wrote to it, and an atomic write to a name taken in between *replaces* what is
there — which is the exact loss `unusedPath`'s own docstring exists to prevent, in an app that
runs concurrent workers and finishes batches in the same second. **Fixed** with
`O_CREAT | O_EXCL`, so the check and the use are one operation. The check that existed was
satisfied by ask-then-write; the new one drives **twelve concurrent writers** and requires twelve
distinct files. Mutant: `A9.7-report-name-is-exclusive`.

**A9.7 · the thousandth collision overwrote a report silently.** The bounded loop fell out and
wrote over `… 999.txt`. Now a refusal the caller has to report, because the report exists so an
overnight batch leaves a record and quietly destroying the previous one is the failure it was
built to prevent.

**A9.7 · `RunReport.duration` trapped on `1e19` and `.nan`** — the sixth bare `Int(Double)` in
the codebase, in the one file A7.3's grep did not cover, because that sweep was scoped to
`Flattener`. Now `safeInt`. Unreachable today; `elapsed` is a monotonic difference.

**A9.7 · cancelled files were named nowhere but the log**, while failures got a by-name block. So
after an overnight batch stopped part way, the report counted the cancellations in its summary
and left the reader to reconstruct which documents they were from the log's arrival order. They
are the files worth re-running, so they now get their own block — with the inverse check that it
is absent when nothing was cancelled.

*(A9.7's last item, "a positive memo survives deletion of the tool", is `locateTool`'s
memoisation being deliberate and documented; `forgetToolPaths` is the answer and Settings calls
it on every appear. Left alone.)*

### T11 · The skip census was a documented number, and three checks were gated behind a tool they do not use — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A11.5, A11.6, A11.7.
A11.2, A11.3 and A11.4 were fixed alongside A11.1 and are recorded in T10.)*

**A11.7 · the census.** `ARCHITECTURE.md` said the suite silently skipped "roughly **76**"
checks without jbig2/qpdf; before that it said "~18"; the true count at the time was **75 in
eight blocks**. A number in a document that was wrong by 57 and would go stale again with the
next gated check.

**Fixed by measuring instead of documenting.** `skipBlock(label:checks:because:)` records every
gated block that does not run, and the suite prints the census at the end of every run. Five of
the eight blocks previously skipped with **no `else` at all**, so they left no trace in the log
— a silent skip is now a contradiction in terms.

**And each block's figure is asserted on machines where the block does run**, so the number a
*toolless* run reports is one this suite has verified rather than one somebody counted by hand.
That mechanism paid for itself immediately: the figures written into this fix were counted by
hand as 16 and 13, the assertions came back **14 and 12**, and the register would otherwise have
carried two more wrong numbers. Static counting of `check(` lines over-counts, because some sit
in branches that do not all execute.

One skip message named the wrong dependency: "mac-ocr not resolvable
(`brew install jbig2enc qpdf`)" — a program removed in 1.11.0, with a remedy for a different
one, hiding twelve checks. Recognition is in-process now (R40), so an empty language list is a
property of the OS.

**A11.6 · the toolless run does not exit 0.** Measured **784/788, exit 1** — two ungated
preview checks, one deliberate, one hard-coded `false`. So on a fresh clone, before
`brew install jbig2enc qpdf`, **the pre-commit hook refuses every commit.** `ARCHITECTURE.md`
now says so. **Not re-measured in this session**, because both tools are installed on this
machine and removing them to check was not worth the risk to the user's system; the figure and
the exit code are the review's, and the way to confirm is a clone on a machine without them.

**A11.5 · three bound checks gated behind a tool they never call.** Four
arithmetic-over-constants checks sat inside `if JBIG2.isAvailable` while comparing two
constants and touching no external tool, so on a machine without the tools `mutate.py`'s
`const/maximumMRCPageMegapixels` mutant **had nothing that could kill it** and the log would
have recorded a survivor for the wrong reason. Moved out of the gate. A gated check is a check
that does not exist on somebody's machine.

`const/maximumColourPageMegapixels` was **not in the catalogue at all** — A11.5's third pair.
Its check already existed, ungated, so the mutant is what was missing; added rather than
duplicating the check.

And `if JBIG2.encoder != nil || true {` was a condition that is always true wearing the shape of
a skip. Nothing in that block runs jbig2 — it composes a text layer and reads it back — so a
reader counting gated blocks counted one that was not gated, and a reader wondering why a
hyphenation check needed a compression tool had no answer. Now a plain `do`.

### R79 · Five smaller defects, and a refusal that named the wrong remedy twice — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A3.3, A3.4, A4.3,
A4.5, A4.6.)*

**A3.3 · `pageTooLarge` named a remedy that does not work, and this is R26 recurring.** R26
rewrote this message because it named "PDF render DPI", a control with no effect on `flatten` —
`Flattener` reads nothing from `Prefs`. True, and the conclusion drawn from it was wrong: the
replacement remedy, turning the rebuild off, sends the page to `Recogniser.render`, which
applies **the same `rebuildDPI` and the same megapixel guard**, and `pdfDPIAuto` defaults to
true. Measured on a page declaring 2,100 DPI:

```
rebuild off, Page DPI = Automatic (the default) : still fails
rebuild off, Page DPI = 144                     : 1224x1584, works
```

So the advertised remedy changed the message and not the outcome, while the setting the message
explicitly disclaimed is the only one that helps. Both halves are named now, in the order they
have to be done.

**The check for this asserted the opposite, because it was R26's belief written down.** It
required that the message *not* point at the render-DPI setting. Replaced with checks that
require both halves — and, so it cannot drift back into prose, two that drive the real
`Recogniser.render`: Automatic returns nil on the oversized page, a fixed 144 DPI renders it.

**A3.4 · `jpegData` read past the end of its buffer.** `greyPNG` and `jpegRGB` both guard
`count >= w*h`; this did not, and a 16-byte buffer at 100×100 produced a valid 2,055-byte JPEG
from **9,984 bytes past the end of the array**. The framing that matters is A4.4's: not "it
traps" but **adjacent heap bytes get JPEG-encoded into the published page image** — memory
disclosure into the output document. Unreachable from today's three callers, all traced; the
function is `static` and already called from `Tools/`.

**A3.4 · `wrapImage` bounded a declared resolution only from below.** At 1.0001 DPI a 200×100 px
image became a 200×100 **inch** page and died at the megapixel gate quoting A3.3's ineffective
remedy; at 1e6 DPI it *succeeded* and published a 1/5000-inch page. Now clamped at both ends at
4,800 DPI — twice any flatbed's optical maximum, so past it is a declaration to disbelieve.

**A3.4 · two dead `if true {` conditionals** in `flatten`, and a comment saying "page 1's
*display* box" over code that uses `fullBox`. Given how much of `ARCHITECTURE.md` is about
keeping those two apart, one word worth fixing.

**A3.4 · `downsample` never samples the last `w mod f` columns**, and `JBIG2.assemble` stretches
the layer over the whole page box: 1,899 px at f=16 drops 11 columns, a **0.58% horizontal
stretch**. Only the tone layers, only where they are flat, so invisible — **documented rather
than fixed**, because sampling the ragged edge needs a partial-window mean and the layer it
affects is a blur by construction.

**A4.3 · a plaintext password "Reset to Defaults" could not reach.** `migrateFromPreviousName`
copied every key including `password` out of `com.cp1.VisionReaderGUI` and **never removed the
source**, while `resetAll` clears only the current domain. Anyone who set a password before the
rename kept a stale plaintext copy, readable with `defaults read`, and present in Time Machine
backups and APFS local snapshots. The migration now empties the old domain — every key, not just
the password, because a half-emptied domain is a second source of truth.

**A4.5 · a scratch directory leaked on one error path.** `recogniseViaHelper` put its
`defer { removeItem }` *below* the `createDirectory` that can throw, so a failure there left the
directory behind — and what survives in one, for an encrypted source, is qpdf's stream dump: the
document's content **decrypted**, in a file named after the document. The other two scratch roots
already order these correctly.

**A4.6 · `publish`'s rollback was `try?` — and this is my own code, from R59.** If the
same-volume `replaceItemAt` fails and the rollback fails too, a complete copy of the finished
document is left as an invisible, extension-less `.visionocr-publish-<UUID>` file beside the
user's output: same directory, same 0644, so no new audience, but invisible in Finder and it
would sync to Dropbox or iCloud unnoticed. Now a `Failure.cannotPublish` naming both problems
and the file to delete. A rollback that fails silently is the shape this function exists to
avoid.

### R80 · The updater could offer a downgrade, and Check Now gave no way to take it — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A10.4, A10.5, A10.6,
A5.4.)*

**A10.5 · a prerelease published without GitHub's flag was offered over the release it
precedes.** `isNewer` filters non-digits per component, so `v99.0.0-rc.1` parses as
`[99, 0, 0, 1]` and beats 99.0.0 — **a downgrade presented as an update**. `1.-1.0` parses as
`[1, 1, 0]` and beats `1.0.0` the same way. Now a tag must be purely dotted digits, and a tag
that is not is `.notAnOffer` rather than `.unreadable`: the endpoint answered and this app
understood it, and calling that a failed check would retry every fifteen minutes (U25).

**A10.4 · "Check Now" reported an update and then suppressed the only way to get it.** The panel
kept `r.version` and threw away `r.url`, and the banner — the sole surface with *What's New* and
*Download* — is set only from the non-forced `.task`, which returns immediately when `isDue()` is
false. A successful forced check then stamps the full 24-hour interval. So after any failed
automatic check (offline, 5xx, rate limit), Check Now read "99.0.0 is available" and gave no
link, no button and no banner — that session or for the next day. The panel keeps the URL now
and offers a Download link beside the status.

**A10.6 · Reset to Defaults un-skipped a version.** `skippedVersion` is in `allKeys`, and has to
be — the migration and the enumeration checks walk it — but it is a *record*, not a setting: the
user has already said "don't offer me 1.9.0 again". `Prefs.notASetting` names it and
`lastUpdateCheck` alongside, and the reset skips both. Made a constant rather than a literal in
the view precisely so it can be asserted, with an inverse check that it has not grown to swallow
real settings.

**A5.4 · the quit gate and the model disagreed about when a batch exists.** `App.swift` gated on
`RunControl.isAnyRunning`, and a `RunControl` does not exist until `run()` — so for the whole
committed-but-not-running window (Start pressed, born-digital scan going, alert possibly up) it
was **false**, and closing the window during "Checking…" quit the app with a batch the user had
started. Lost work rather than lost content, and C20's two-definitions shape. `isAnyCommitted`
counts pre-flights as well, and it is the one definition both sides read.

**A5.4 · `cancel()` was a silent no-op in those same states.** `control` does not exist yet, so
Cancel cancelled nothing — and the "Cancelling…" line it appended was then erased by `run()`'s
`log = []`, so the user pressed Cancel, saw a line appear, and watched the batch start anyway.
Not reachable from today's UI because the button is rendered only `if model.isRunning` — one
`if` in a view standing between this and a lie, which is exactly the shape U19 and U23 record.
`cancel()` now records the intent and `run()` honours it *before* it clears the log.

**A5.4 · `skipThem` assigned where `run` subtracts**, discarding every mark an earlier decision
had left, so a second Skip Those in one session forgot what the first had skipped. `formUnion`.

---
## The interface

The GUI got no review attention during the period when this was going to become
a headless backend. When that reversed, three adversarial passes over it found
fourteen defects — **two of them regressions introduced by the pass before**.

### U29 · The whole updates block is in Settings twice — FIXED
*(reported by the user 2026-08-13; confirmed by reading the source; fixed 2026-08-13)*

`SettingsView.swift` lines **453–488 and 489–524 are byte-identical** — 36 of 36
lines, after stripping. Not a stray duplicated toggle: the entire updates block is
pasted twice, comment and all. The "Check for new versions" toggle, its `.help`,
the "The only network request this app makes" caption, the **Check Now** button,
and the status row all appear a second time.

Both toggles bind `$checkForUpdates`, so they agree and nothing behaves wrongly —
which is why it survived. It is a paste, and the fix is to delete the second copy.

**The suite would not have caught it and still would not.** The accessibility
scanner checks that every control *carries* a name; nothing checks that no two
controls carry the *same* name. That check is the more valuable half of this
entry: a duplicated control is a paste error, and a settings panel is exactly
where one hides. Add it with the fix.

**Fixed** by deleting the second copy, and the check was added — the more valuable
half. `duplicateControlNames` reads each control's visible label, or the
`.accessibilityLabel` of one that has none, and requires no name to appear twice in
a file. Shown to bite before being trusted, in both directions: against the
pre-fix file it reports exactly `Check for new versions` and `Check Now`, and after
the deletion the two view files hold **41 named controls with no name used twice**.
The two scanners now share one `starters` list rather than each keeping a copy,
because a starter added to one and not the other would narrow one scan while the
other still looked thorough.

### U30 · The "Start from" preset buttons give no sign they did anything — FIXED
*(reported by the user 2026-08-13: "it's not clear what clicking any of the 'start
from' buttons does. They don't seem to stay clicked")*

`SettingsView.swift:286` — `Button(preset.label) { preset.apply() }`. The button
writes six or seven settings and returns. Nothing moves that the eye is on, no
control reports the change, and the only explanation is a `.help` tooltip, which
is mouse-only and unreachable by keyboard — the same objection U8 already recorded
against putting an explanation in a tooltip.

**They do not stay clicked on purpose, and that part should not change.**
`Prefs.Preset.apply` says why: a preset writes into the ordinary settings and
keeps no "currently using preset X" state, "because a setting that only looks live
is what `ocrAllPages` turned into." Sticky state would be a second source of truth
for values the panel below already owns, and it would go stale the moment anyone
touched one of them.

So the defect is **feedback, not state**. The button changed six settings and said
nothing. Options, cheapest first: say what happened in a line under the row
("Newspaper: 6 settings changed"); or briefly mark the rows whose values moved,
which also teaches what the preset *is*. Either keeps the settings as the single
source of truth.

Worth noting the shape: the reasoning behind the design was recorded, correct, and
still produced a control a user could not read. A decision being right is not the
same as it being legible.

**Fixed** the first way, and the state stayed out of it. `Preset.apply` now returns
the settings that **changed**, and the panel shows one line: *"Newspaper applied —
changed Photo detail, Uncertain text."*

Reporting what changed rather than what was written is the part worth keeping.
They differ, and the difference is the useful half: clicking **Book scan** on a
default panel writes seven settings and moves none of them, and *"your settings
already matched"* answers "did that do anything?" honestly, where a list of seven
untouched settings would not. A test applies a preset twice and requires the second
click to report nothing — which is the check that fails if this ever goes back to
reporting what it wrote.

**It is spoken as well as written.** A line in the panel is readable but not
announced, so on its own it answers the defect for the eye and leaves the button
exactly as silent for VoiceOver — half of U8's objection is that a tooltip cannot be
*reached*, not just that it is mouse-only. The button posts an
`announcementRequested` with the same sentence.

Two checks guard the line itself: every key a preset may write has a label (the
summary is built with `compactMap`, so a key without one is dropped in silence and
the feedback under-reports exactly as the button used to say nothing), and every
label is text `SettingsView` actually shows — a label that drifts from its control
sends the user looking for a setting that is not there, and the summary would still
read perfectly well.

Still no sticky state, and a check now holds that: after applying a preset, no
defaults key contains "preset".

### U1 · A green "40 of 40 succeeded" over a list of 43 files — FIXED
The batch-level version of invariant 1, and the worst of these.

`start()` freezes the batch (`let batch = files`), so files added during a run are
never enqueued. They sit in the list while the summary reports success; three
scans have no output anywhere on disk and nothing says so. The UI actively
solicited the mistake — the drop border highlighted, the header count
incremented, both reading as "accepted into the job in progress".

**Fixed twice.** The first attempt disabled the `Add…` button and stopped there,
leaving `.onDrop` unconditional and `OCRModel.add` unguarded — so the drop zone
and Finder's "Open With" still accepted files. The guard now lives in `add()`,
where all three routes meet, and a refused drop says so rather than doing nothing
visible.

### U2 · Quitting orphaned the OCR children — FIXED
A child of an exiting process is reparented to launchd, not killed, so mac-ocr,
jbig2 and qpdf kept running invisibly after a quit — on a large book, for
minutes. The app now asks, cancels every live batch, and waits briefly so each
run's `defer` clears its scratch directory.

The registry behind that prompt took three attempts, all caught by its own test:
a strong dictionary (leaked every control and its `Process` objects for the life
of the app, and `deinit` never ran), then `NSHashTable.weakObjects()` (no
Swift-weak semantics for a plain Swift class), then an explicit weak box.

### U3 · Closing the window mid-run left an invisible batch — FIXED
*(a regression from U2, one commit later)*

`applicationShouldTerminateAfterLastWindowClosed` returning an unconditional
`true` meant closing the window started a termination; choosing "Keep Running"
then left a windowless app with a batch that could not be cancelled or observed.
The app now only quits on last-window-close when idle, and
`applicationShouldHandleReopen` brings the window back.

### U4 · Settings accepted edits that could not apply — FIXED
A batch snapshots its settings (R5), so a mid-run change was silently ignored —
and switching the text format would have written JSON into the `.txt` path
`uniqueOutputs` had reserved. The panel now states that a run is in progress and
locks. Its tool re-probe is suppressed mid-run too, since workers are resolving
those same paths and it can block the main thread on a login shell.

### U5 · `askLoginShell` could freeze the app — FIXED *(the bound it added did not work; see U18)*
No timeout, on the main thread, from both `start()` and the Settings body. A
login shell that blocks — a slow network mount in a profile, an interactive
prompt, a wedged NFS home — froze the app with no way out. Bounded at three
seconds against a normal ~85 ms.

**The bound was placed after the blocking call and never fired.** The diagnosis
above is right and the remedy was in the wrong order; U18 records the measurement
and the real fix. Counting this as FIXED for a year is the argument for testing
the timeout rather than reading it.

### U6 · The progress bar showed a number nobody measured — FIXED
Extract Text, the default mode, reported a flat `0.5` for the whole of a
single-file run, so the bar sat at exactly half and read as a hang. `Runner.run`
is one blocking call; there is genuinely nothing to measure. A stage can now say
"working, no idea" and the bar goes indeterminate.

*(Also fixed twice: the first version applied to multi-file batches too,
discarding "3 of 8 done" — real information even when no single file can measure
itself.)*

### U7 · Five smaller ones — FIXED
- **"Save beside each original" stayed editable mid-run**, so the Output panel
  could describe somewhere the batch was not writing.
- **Dropping only unsupported files gave no feedback at all** — the notice lived
  inside the file list, which is exactly what does not appear when nothing was
  accepted.
- **The log never named the output path**, which with "beside each original"
  leaves no way to find the results of a partly-failed batch.
- **Files dropped on the Dock icon, or opened with "Open With", were silently
  discarded** — `Info.plist` has always advertised both document types.
- **"Reset to Defaults" could not reset the destination.** It removed the keys,
  but `OCRModel` owns those values in memory and wrote them straight back on the
  next change, undoing the reset for the next launch too.

### U8 · Accessibility — FIXED
A dedicated review pass (which took four attempts to run — it died on the
session limit three times) found the UI was largely opaque to VoiceOver.

Fixed: labels on the icon-only remove button, the mode picker, the drop zone,
the progress bar (with a value, so a running batch is no longer silent), the
Settings sliders, pickers, steppers, toggles and path field; `accessibilityHidden`
on the three decorative glyphs; the full path exposed on each file row rather
than living only in a mouse-only tooltip; a disabled Start that says *why*,
since a tooltip on a disabled control is unreachable by keyboard; and Cancel on
⌘.

**Outcome is no longer carried by colour alone.** `LogLine.spoken` gives
VoiceOver "Failed: ✗ scan.pdf" instead of an unannounced glyph.

What remains is in [TODO.md](TODO.md): no live-region announcements (VoiceOver
is told nothing *as* a batch progresses — the values are readable but not
spoken), and the real tab order has never been walked.

### U9 · A folder passed as the mac-ocr path — FIXED
`FileManager.isExecutableFile(atPath:)` returns **true for directories** — the
executable bit on a directory means "searchable" — verified: `/opt/homebrew/bin`
and `/Users/<name>` both report true.

So typing a folder into the mac-ocr path field passed validation, the panel
reported "Using this path instead of the automatic one", the command preview
showed a plausible `mac-ocr …`, and Start then failed **every file in the batch**
with "Could not launch mac-ocr". The "Choose…" button sets
`canChooseDirectories = false`; the text field was the unguarded route.

**Fix:** `Runner.isRunnable` requires a non-directory that is executable, used by
`resolveBinary`, the prefix scan and the login-shell fallback. The caption now
distinguishes the three ways a path can be wrong — nothing there, a folder, not
executable — instead of claiming a broken path is in use.

### U10 · The log could not be got out of the app — FIXED
`textSelection(.enabled)` was on each `Text` rather than the container, so a
drag could not span lines: extracting three failures from a 40-file log meant
copying them one at a time, and a keyboard user could not copy at all. Now on
the container, with a Copy button that takes the whole log.

Related, and the reason it matters: **"Clear" wiped the log as well as the file
list**, from a button in the file-list header. That log is the only record of
which files failed and where each output went, and clearing the list to queue
the next batch is a normal thing to do immediately after reading it. Split into
"Clear List" and "Clear Log".

### U11 · Layout at the minimum window size — FIXED
The mode picker's hard `frame(width: 240)` was the one unshrinkable element
making the action row overflow at the 520 pt minimum; it is now a range. The log
pane's fixed `frame(height: 130)` meant it could never be enlarged, so a 78-file
batch was watched through a slit in a tall window; it is now a minimum.

### U13 · The window could not be got back after closing it mid-run — FIXED
*(the last unverified item in the project, and it was the serious answer)*

`Sources/App.swift`. U3 stopped a mid-run window close from quitting the app and
left `applicationShouldHandleReopen` to bring the window back. It never did.

```swift
NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
```

A closed `WindowGroup` window survives in `NSApp.windows` but reports
`canBecomeMain == false` until something orders it front — so the filter matched
nothing, the handler was a no-op, and a batch the user had closed the window on
was unreachable for the rest of its run. No progress, no log, no Cancel. Exactly
the state U3 was written to prevent, reached by the route U3 installed.

Measured with `Tools/probe-window-reopen.swift`, which replicates the real
scene and delegate and runs both the old body and the new one:

| | windows known | visible | canBecomeMain |
|---|---|---|---|
| before close | 1 | true | true |
| after close | 1 | false | **false** |
| after the old body | 1 | false | false |
| after `showMainWindow` | 1 | **true** | **true** |

**Fix:** `AppDelegate.showMainWindow` drops the filter, preferring a main-capable
window when there is one and otherwise taking the first window that is not an
`NSPanel` — a sheet or alert ordered front would leave the batch just as
invisible. It also activates the app, and it is shared with a new **Window ▸
Vision Reader Window (⌘0)** command, which is the keyboard route back that did
not exist at all: File ▸ New Window is removed and there is no `Settings` scene,
so a Dock click was the only way in even when the Dock click worked.

### U17 · Every file opened from Finder spawned another window — FIXED
*(found by running the app, not by reading it — see "Verified on a running app")*

`Sources/App.swift`. The scene was a `WindowGroup`, and a `WindowGroup` is a
*template*: macOS instantiates it once per document handed to the app. So
selecting three scans in Finder and choosing Open With produced **four windows**,
on top of U7's delegate handler, which had already added all three files to every
window that existed. Measured in the VM, counting on-screen windows by pid:

| | before | after |
|---|---|---|
| bare launch | 1 | 1 |
| + open 3 files | **4** | 1 |
| + open 1 more | **5** | 1 |

Two consequences, and the first is the serious one:

1. **Each window had its own `OCRModel`.** Every window's list held all three
   files, and each had its own enabled Start button. Pressing Start in two of them
   ran two batches over the same inputs — and `uniqueOutputs` only de-conflicts
   *within* one batch, so both claimed `scan.ocr.pdf` and raced to write it. That
   is C8 and R18's class of defect, reachable by an ordinary Finder gesture.
2. **The batch was a property of a window**, so closing the window mid-run
   destroyed the model. The run itself survived — the queued operations hold the
   `RunControl` strongly — but became unobservable: `finish` never ran, so no log
   line, no summary, and reopening gave a blank window while the OCR ground on.
   U3 and U13 are both about that state; this was a third route into it.

**Fix:** `Window`, not `WindowGroup` — a single-instance scene, which is what
this app has always been (File ▸ New Window is removed, there is one Settings
sheet, `RunControl`'s registry is global, and the quit prompt speaks for the app).
The `OCRModel` moved up to the `App` as its `@StateObject` and is passed in, so
one model belongs to the process rather than to whichever window happens to
exist. ⌘0 now uses `openWindow(id:)`, which can rebuild a scene SwiftUI
destroyed; the delegate keeps the AppKit route because an `NSApplicationDelegate`
has no environment to read `openWindow` from.

### U14 · Three smaller interface defects — FIXED
- **`ignoredNotice` outlived what it described.** "Not added — a run is in
  progress" stayed in the header until the next add or Clear, long after the run
  ended — and on a batch the user then had no reason to touch, indefinitely. It
  now clears when the run does; the "N unsupported skipped" notice, which still
  describes the list as it stands, does not.
- **The command preview promised a destination the run would refuse.** On a
  fresh install it showed `-o '[dir]/[name].txt'` — beside each input — while
  `destinationReady` was false and Start was disabled, with the doc comment
  claiming it was "the exact command a run will use". It now says plainly that
  no output folder has been chosen and that Start will stay disabled.
- **The preview hard-coded `mac-ocr` and never mentioned JBIG2.** So the setting
  most likely to be wrong (the binary path, U9) could not be checked against the
  one panel that exists for checking settings, and the two further binaries the
  compression step shells out to were invisible. It shows the resolved binary
  now, and names `jbig2` and `qpdf` — or says they were not found and that the
  step will be skipped.

### U15 · `SettingsView` could not fit on a short display — FIXED
A hard `frame(width: 560, height: 660)` under a comment calling its ScrollView
"a safety net for short displays". The net was never reachable: the sheet could
not be shorter than 660 pt, so on a display that could not give it 660 pt the
fixed Done footer went off the bottom. Escape still dismissed, which is not
something a user should have to know. Now `minHeight: 360, idealHeight: 660,
maxHeight: 660`, so the ScrollView does the job it was there for.

**Verified on a real short display.** In the VM at 1024x640 the sheet comes up
560x**512** — shrunk below its 660 ideal — with the Done footer on screen and the
ScrollView carrying the overflow. Before the fix it could not be shorter than 660
on a 640 pt screen.

### U16 · Nothing was spoken as it happened — FIXED
U8 left this open: labels and values made the interface *readable* by VoiceOver,
but a batch could start, grind through eighty archival scans and finish in
silence. The values were there; nothing announced them.

**Fix:** `OCRModel.announce` posts `.announcementRequested` at the three moments
a sighted user gets for free — the batch starting, each file landing, and the
summary (at high priority, so it is not dropped in favour of whatever VoiceOver
is mid-sentence on). The per-file announcement is suppressed for the file that
ends the batch, since the summary follows a moment later; without that, a
single-file run said three things about one document.

### U22 · The first-launch instructions described a bypass macOS had removed — FIXED
*(2026-08-09, found by the user hitting it, which is how it should have been found sooner)*

`README.md`. Every release since the repo went public told a downloader to
**Control-click the app and choose Open**. macOS 15 removed that bypass for apps
that fail notarization, and on macOS 15 and later the dialog offers only *Move to
Trash* and *Done*. There is no Open button to click.

So the one instruction standing between a new user and a working app named a
control that does not exist, on every current version of macOS. Reported from a
macOS 26.6 machine.

Reproduced on our own build rather than taken on trust: a copy was given a
`com.apple.quarantine` attribute exactly as a browser sets it, and

- `spctl -a -t exec` → **rejected**
- `codesign -v --deep --strict` → **passes**

so the signature is sound and it is notarization that fails. Clearing the
attribute (`xattr -dr com.apple.quarantine`) and opening it launched the app with
no prompt at all, which confirms Gatekeeper enforces the verdict only on
quarantined files.

**Fix:** the README now describes the route that works — Done, then System
Settings ▸ Privacy & Security ▸ **Open Anyway**, then open again — and says
explicitly that the Control-click shortcut has been removed, because that
advice is everywhere and users will otherwise assume the app is broken. It also
notes that the Open Anyway line only appears just after a blocked attempt and
lapses after about an hour, which is the other way this looks broken when it is
not.

**Not notarizing is a decision, not an omission.** It would cost a paid
Developer ID, and it is the only remaining way to remove this step entirely.
Recorded here so the next person does not treat the dialog as a defect.

### U23 · `remove` and `clearFiles` were guarded only by the view — FIXED
*(2026-08-09, found by applying CONTRIBUTING 4b to U19 — the sibling sweep, one round after it was written)*

`Sources/Model.swift`. `add` carries an explicit note that its guard belongs in
the **model**, "because there are three ways in — the button, the drop zone, and
files handed over by Finder — and gating only the button left the other two
open." That was U1's lesson. `remove` and `clearFiles` mutate the same batch and
were guarded only by `.disabled(model.isCommitted)` in `ContentView`.

Not user-reachable today: the two buttons really are disabled, so the view
covers it. It is a latent defect rather than a live one, and worth fixing
anyway, because the model's own stated contract is that the guard lives here —
and the next door (a menu item, a shortcut, an Open-With handler, a future
scripting surface) would bypass a view modifier exactly as U1's drop zone did.

Both now refuse while `isCommitted` and return a `Bool` saying whether they
acted.

### T8 · The states-by-doors cross product, for the fourth way fixes cause bugs — FIXED
*(2026-08-09. The other three shapes got controls; this is the fourth.)*

The register's fourth mechanism is **two changes that are each correct alone**.
U19 introduced `isCommitted` and gated `add` on it. U20 added an async import
whose completion checks the same flag. Neither was wrong, and U21 happened
anyway: the property they both depended on — *from the click until the run ends,
the batch cannot change* — was written down nowhere, so each feature checked it
at its own moment, and a moment existed that neither had considered.

Reasoning about pairs of features does not scale and did not work. Enumerating
does. The suite now walks **every state from the click onwards × every door into
the batch**, which is finite, small, and indifferent to which two features
interact:

|            | add | remove | clearFiles |
|---|---|---|---|
| pre-flighting | ✓ | ✓ | ✓ |
| deciding      | ✓ | ✓ | ✓ |
| running       | ✓ | ✓ | ✓ |

Plus the inverse — all three doors must still *work* when nothing is committed —
because otherwise an app that did nothing at all would satisfy the table.

The **"deciding" row is the point**. U21 was a state that existed in behaviour
and in no flag; a table cannot enumerate a state nobody has named, so naming it
is forced by writing the table. Removing the two new guards turns six of the
twelve red.

The remaining structural improvement, recorded rather than done: `isRunning` and
`isPreflighting` are two booleans describing one lifecycle, which is four
representable states for three real ones. A single `phase` enum would make the
state space explicit and make a new state impossible to forget, since it would
not compile until placed. That is a refactor of live UI state and deserves its
own round with the GUI checks, not a footnote to this one.

### U24 · The file list said nothing about progress — FIXED
*(2026-08-09, asked for. Not a defect so much as an absence, recorded because the data was already there.)*

While a batch ran, the list showed names and nothing else. Progress was one
overall bar and a caption; per-file outcomes appeared only *after* the run, in a
pane that replaces the bar. On a 78-file batch that means the thing you are
watching tells you nothing about the sixty files already finished, and nothing
about which of them failed until it is over.

The model was already carrying everything needed. `inFlight` has the files being
worked on and `stages` has a per-file label — "Rebuilding page 29 of 372" — that
**nothing had ever displayed**. Only the outcome was missing.

Now: a status column (dotted circle / spinner / green tick / red triangle /
cancelled dash), the live stage under the name of any file in flight, and a
header that counts — "3 files · 1 done, 2 running". The remove buttons hide
rather than sit dead during a run.

Four shapes, not four colours: colour alone is not available to everyone, which
is why the log lines already carry glyphs (U8). Each row's accessibility value
is its status, so VoiceOver reads "…, in progress, Rebuilding page 29 of 372".

**The logic lives in the model, not the view.** `status(url:)` and
`statusDescription(url:)` are on `OCRModel` because `run_tests.sh` compiles the
views and never instantiates one — logic in a `View` body is logic no check can
reach, which is why U13, U15 and U17 all needed a VM to find. Ten checks cover
it, including that a file re-run after failing shows as *running* rather than
keeping its old cross.

Verified on screen, not only by compiling: a real three-document run, captured
mid-flight with two spinners and one tick, and again at the end with three
ticks.

### U25 · Three defects in one 255-file run — FIXED
*(2026-08-09, reported from a real batch of 255 documents. One screenshot, three
separate bugs, and the report itself is what made them visible.)*

The run finished, said **3 problems**, and there was one bad file. Everything
below came out of that.

**a. The count counted log lines, not files.** `problemCount` filtered
`log` for failures, and one failed file emits several — the failure, the
diagnostic, the "not written" note. So a single broadsheet reported as three
problems, and a user with one thing to fix went looking for three. It counts
files now: `outcomes.values.filter { $0 == .failed }.count`, which cannot exceed
the number of files by construction.

**b. Problems were wherever they happened to fall.** The report is the log in
order, so on a 255-file run the one failure sat somewhere around line 700 with
254 successes above it. Now `logFailuresFirst` puts failures at the top with the
rest following, and the pane scrolls to the first one when it appears. Ordering,
not filtering — the successes are still all there, underneath.

**c. The file itself: pages the recogniser refuses.** The real defect. The
document is a 63 MB scan of newspaper broadsheets — page 5 is **44.4 × 77
inches**. mac-ocr renders PDF pages at 300 DPI and refuses anything over 200
megapixels; that page is 308 MP, and page 2 is exactly the 250 MP quoted in the
error. The app rebuilds pages up to *400* MP, so it happily did all the rebuild
work and then handed the recogniser something it would not read. Every page,
lost, after the expensive part.

`Flattener.recogniserDPICeiling(for:)` now measures the largest page and returns
the DPI that fits — 236 for this document — and `recognitionArguments` takes the
lower of that and whatever was asked for.

Three things that took a second pass to get right:

- **The ceiling must belong to the document, not to a default.** The first
  version compared against 300 and returned nil when 300 was fine. A 30 × 40
  poster is 108 MP at 300 and 432 MP at 600, so with 600 explicitly chosen there
  was no ceiling to clamp with and the file failed anyway. It now reports the
  document's own limit and the caller decides whether it binds.
- **A ceiling only ever lowers.** Taking the minimum, never the ceiling
  outright, so a deliberately low DPI is not raised to meet a limit.
- **It applies to an explicitly chosen DPI too.** The first version deferred to
  one — "an explicit choice is theirs to get wrong". Wrong here: the cost is not
  a worse text layer, it is *no* text layer, which is invariant 1. One place
  decides the DPI now, so there is never a second `--pdf-dpi` for the engine's
  argument parser to break the tie on.

Verified end to end on the file itself, through `OCRModel.start()` and not just
the engine: at 300 DPI it reproduces the user's exact error after page 1; with
the ceiling it produces a 9-page searchable PDF carrying 73,946 characters,
first line "The Negro's Stake In America's Future".

**d. And the reason it looked hung.** Also from that screenshot: 254 of 255 done
with one broadsheet still grinding is 99.6% complete, and 99.6% of a progress bar
is a full progress bar. The heading said "1 running" and the bar said finished,
and the bar is what you read from across the room — so the app appeared to have
hung on a file that was working normally. `overallFraction` now holds back a
visible sliver until the batch is genuinely over.

Nine checks. Two of them were written wrong first and are worth recording: one
asserted `< 0.98` against a model whose `total` was 0 — green, and testing
nothing, the exact T6 shape — because `add()` refuses paths that do not exist;
the other multiplied a 30 × 40 page as 30 × 60 and failed a correct fix. Suspect
the instrument.

### U26 · Eight defects in the update checker and the progress UI — FIXED
*(2026-08-09, adversarial review of U24/U25's own code. The fourth round in a row
where a review of a fix found defects in it.)*

**The update check described the machine it ran on.** `Updater` is this app's
only network code, and the README promises the request sends nothing about you.
It sent two headers nobody wrote: CFNetwork fills in `User-Agent` with the app
build and the exact Darwin kernel version — the machine's precise macOS point
release — and `Accept-Language` from the user's `AppleLanguages` list, measured
changing to `he-IL,he;q=0.9` when that list changes. With the source IP, a stable
per-machine fingerprint, sent daily. Both are pinned to constants now.

**A failed check spent the whole day's allowance.** The clock was stamped before
the result was looked at, so one launch on a train used the day's only automatic
check — and someone whose first launch is reliably the offline one would never
be told about a fix at all. A failure now costs fifteen minutes; only a real
answer spends the interval.

**"Check Now" answered about the skip, not about reality.** A forced check ran
through `shouldAnnounce`, so after skipping 1.6.0 the button said "Up to date"
on a version visible on the releases page, and the skip could never be undone.
Forced checks compare versions and nothing else.

**Row state outlived the rows.** `remove` and `clearFiles` left `outcomes` and
`stages` behind, so a file dropped in again wore the previous run's green tick
before it had done anything. The required sibling sweep then found the third
per-file collection this fix had missed — `skipped`, which is reset when a run
*starts*, so a stale value showed in exactly the gap where someone is deciding
what to run. `renamedOutputs` and `resolvedOutputs` were checked and are clean:
both are replaced wholesale each run.

**A file that kept its own text had no status of its own.** It is not a success
and not a failure; it now has `FileStatus.skipped`, its own glyph, and the
VoiceOver phrasing "skipped — it kept its own text".

**Two checks that could not fail.** One "verified" a preference by asserting
against the constant it had just set; it reads `UserDefaults` now. The other
compared `Prefs.allKeys` to a hand-copied list in the test — a duplicate of the
thing under test, which agrees with it by construction and would keep agreeing
after a key was dropped. It greps the keys out of `Sources/Prefs.swift` instead.

**And eleven row-status checks that never ran the code they describe.** Every
one set `inFlight` and `outcomes` by hand. Recording could have stopped entirely
and all eleven would have stayed green. The real 8-file batch now asserts that
every row says "succeeded" when the summary does, and the list-editing checks
drive `remove` and `clearFiles` for real.

### U27 · Three defects in U25 and U26's own code — FIXED
*(2026-08-09, adversarial review of the branch before merging it. The fifth round
running where reviewing a fix found defects inside it. This is not bad luck; it is
what the process is for.)*

**The results pane stopped following the run at the moment it mattered.** U25's
own change: with failures listed first, the pane scrolled to the first problem
whenever there was one. On a 255-file run where file 3 fails, each of the
remaining 252 files appends a line and every one of them yanks the view back to
the top. The log becomes unreadable exactly when someone is watching it because
something went wrong. It follows the newest line while the run is going and
jumps to the problems when it ends — and the decision is a property on the
model, `logAnchor`, because a `View` body is the one place in this app no check
can reach.

**U26's skipped status could never appear.** `skipThem` sets `skipped` and then
calls `run`, whose first act is to clear every per-file collection — including
that one, two lines later. The glyph, the state and the VoiceOver phrasing were
all unreachable, and the eleven row-status checks set the state by hand, so
nothing noticed. `run` now subtracts the batch instead of emptying the set, and
a real two-file batch — one born-digital, one scanned, answered "Skip Those" —
asserts the skipped row says so afterwards while the other says "done".

**A prerelease made the updater poll ninety-six times a day.** `release(from:)`
returned nil both for a response it could not read and for one it read
perfectly that had nothing to offer, and `check` treats nil as failure — which
now means a fifteen-minute retry (U26). So a repo whose latest release happened
to be a prerelease would be checked every quarter hour, for ever, by an app
whose README promises one request a day. Parsing has three outcomes now, and
only the unreadable one is a failure.

### F1 · Automatic could see colour and threw it away — FIXED
*(2026-08-09, asked for. Recorded here rather than in FEATURES.md because the
part that made it a defect is that the information was already in hand.)*

The rebuild had three modes and none of them could produce a colour page:
`renderGrey` draws into a `CGColorSpaceCreateDeviceGray` context, so Automatic
chose between 1-bit and *grey*, Black & white was 1-bit, and Grayscale was grey.
Measured on a colour fixture: input saturation 0.25, output 0.0000 in all three.

What makes it worse than a missing feature: **saturation is one of the three
signals that route a page away from 1-bit in the first place.** The detector
looked at the page, correctly concluded "this has colour in it, thresholding
would destroy it" — and then rendered it grey. The one mode whose job is to work
out what a page needs had already worked it out and discarded the answer.

Automatic now keeps a colour page in colour. Black & white and Grayscale are
instructions rather than questions and still do exactly what they say.

Three things this touched that were not obvious from the change itself:

- **The JBIG2 merge hardcoded `/ColorSpace /DeviceGray`.** True of every stream
  it had ever written. A three-channel JPEG declared as one channel is not an
  error any reader reports — the page just draws as static. Checked both ways
  now, including that a page *not* marked colour still says `/DeviceGray`.
- **A colour render is four bytes a pixel where grey is one.** The existing
  400 MP page limit exists because a failed allocation crashes the process and
  takes every concurrent file with it, so colour gets a quarter of that budget
  and a page past it rebuilds grey exactly as it used to. Peak memory per page
  is unchanged. The bound is checked as a decision, not by allocating 100 MP.
- **`saturation` was being measured twice** on every illustrated page — once
  inside `isPicture`, once for this — so it is measured once and passed in.

Verified end to end on the shipped defaults, which is the path through the
JBIG2 merge: a colour scan in at 0.2536 saturation comes back at 0.2547 with
its text layer intact.

**Corpus effect, measured rather than argued about**, because the worry was
archival typescripts — yellowed paper has real saturation, and pages that were
grey JPEGs becoming colour ones would inflate exactly the material this app is
mostly used on. All 232 documents, 827 sampled pages, scored twice from two
builds differing only in this decision:

| | grey only | with colour |
|---|---|---|
| total | 300.1 MB | 301.8 MB (**+0.56%**) |
| per page | 354.4 KB | 356.4 KB |

3.4% of pages route to colour, across 5.2% of documents; the worst single
document grows 14.9%. **No document's 1-bit page count changed at all**, which
is the number that mattered: colour can only reach pages already routed to
JPEG, so the compression argument for plain text is untouched by construction
and now by measurement.

The worst-affected document is the case for the feature rather than against it
— an 1891 typescript whose four sampled pages all went colour. Its ink is faded
blue-black, its paper is cream, and there is an archivist's **red pencil "452"**
in the corner that every previous version rendered grey.

### U28 · Three defects in the colour work's own code — FIXED
*(2026-08-10, adversarial review of F1 and the confidence copy, asked for. Sixth
round running where reviewing a change found defects inside it.)*

**A predicate extracted "so the prose can be checked" that nothing checked.**
`willRebuild` was added to make the Settings panel's claim about *which* files
get rebuilt verifiable. Six checks asserted against it — and no production code
ever called it. `processOne` still evaluated its own copy of the condition, so
changing that copy would leave all six green while the panel went back to
lying. This is precisely U26's `Prefs.allKeys` shape: a duplicate of the thing
under test, agreeing with it by construction. `processOne` now calls it.

**The memory bound was right by luck and documented by a false derivation.**
The comment said "a colour render is four bytes a pixel where grey is one, so a
quarter of the page limit keeps peak memory unchanged", and BUGS.md and the
commit message repeated it. Both halves are wrong: the grey buffer is still
alive when the RGBA one is allocated, and both are copied again into a 24-bit
bitmap rep, a JPEG, and a decoded CGImage on the way into the PDF context.

Measured peak RSS on one 64.8 MP page, two builds differing only in the colour
decision: **356 MB grey, 1,261 MB colour** — 5.5 against 19.5 bytes per pixel, a
ratio of 3.5. The 100 MP bound survives review, but for a different reason than
the one recorded: it peaks near 1.95 GB, and a 400 MP grey page — which
`maximumPageMegapixels` has always permitted — peaks near 2.20 GB, so colour
cannot reach a high-water mark grey could not. Both measurements are now
constants and `colourBoundIsWithinTheGreyOne` checks the inequality, so raising
either limit without re-measuring fails.

**Nothing guarded the row stride.** `jpegRGB` packs RGBA into a 24-bit
`NSBitmapImageRep` at `bytesPerRow: width * 3`, which AppKit is free to ignore
and pad. It does not — verified at 417, 418, 419 and 421 px, none a multiple of
four — but a padded stride would skew every row progressively, and a sheared
page is still a coloured page, so every saturation check would have stayed green
while the output turned to diagonal mush.

The check written for it was **worthless twice before it worked**, which is the
part worth recording:

- Version one sampled two corners of a two-block pattern. A deliberately padded
  stride passed it: a one-pixel-per-row shear leaves a big red block still
  reddish in the top-left corner.
- Version two compared whole pages but used 24 narrow wedges, and read 20.6 on
  *correct* code — resampling a high-frequency pattern, not a shear. Six wide
  wedges read 4.3–6.2 correct against 111–113 sheared.

Also caught in review and not a defect: the probe that first read the rebuilt
pages as blank was sampling with the y-axis inverted — bitmap row 0 is the
visual top while CG's drawing origin is bottom-left. The originals sampled white
at the same coordinates, which is what said "instrument, not code".

### U12 · Settings input validation — NO DEFECT
Recorded because it was checked properly and found clean, which is worth knowing
next time someone wonders.

Negative or zero DPI, out-of-range confidence and an enormous min-text-height are
all *unreachable*: every numeric control is a bounded `Stepper` or `Slider` with
no typed entry, and `recognitionArguments` re-clamps DPI and gates height on
`> 0` anyway. Whitespace-only and comma-salad language codes are handled by
`splitList`. Clamping lives inside `arguments()`, which the live preview also
calls, so the preview and the run cannot diverge.

One wart, left alone: `splitList` splits custom words on spaces, so
"St Antony's College" becomes three `-w` flags. The help text says
space-separated and the preview shows it honestly, so the UI is not lying —
it is a limitation of the field, not a bug.

### U18 · `askLoginShell`'s three-second bound sits *after* the unbounded read — FIXED
*(2026-08-09 review; U5 recorded this as FIXED and the ordering was never checked)*

`Sources/Runner.swift:101`. U5 bounded the login-shell lookup "because this runs
on the main thread", and named the hazard exactly: a slow network mount in a
profile, an interactive prompt, a wedged NFS home. But:

```swift
let data = pipe.fileHandleForReading.readDataToEndOfFile()   // :101
if !wait(for: p, upTo: 3) { stop(p); return nil }            // :102
```

`readDataToEndOfFile()` blocks in `read(2)` until **every writer on the pipe
closes**. If the login shell never exits, it never returns, `wait` is never
reached, and `stop(p)` is never called. The three-second bound guards code that
only runs once the thing it was protecting against has already resolved itself.

The codebase states this hazard against itself twice and never applied it here:
R2's poll loop, and the comment at `Runner.swift:260-262` — "`readDataToEndOfFile`
is out — it returns only when every writer closes, and the writers include any
grandchild that inherited stderr". The grandchild variant applies here too: a
`.zshrc` that backgrounds anything inheriting stdout holds the write end open
after the shell itself exits.

Reached on the main actor from `OCRModel.start()` (`Model.swift:510`) and from the
Settings panel's body (`SettingsView.swift:284`, `:328`, `:340`, `:357`), so the
window stops redrawing and Cancel is unclickable. Force-quit is the only exit.
Because the call never returns, the memo cache is never written, so there is no
second chance on the next attempt either.

Reachable whenever mac-ocr, jbig2 or qpdf sits outside the three hard-coded
prefixes — nvm, asdf, a custom prefix. The negative cache at `:70-72` does not
help; it is populated after the read.

The `tool lookup` block in `Tests/main.swift` times cache hits and negative
caching only.

**Fix:** the read is now the same bounded, non-blocking `poll` loop this file
already uses for the child's stderr and for R2's stdout — the third place in
`Runner.swift` to need it. No EOF inside three seconds means something still
holds the pipe, so `stop(p)` takes the whole process group (which collects the
backgrounded grandchild too) and the lookup gives up.

Guarded by two checks that drive the real hazard through a real shell:
`SHELL` is pointed at a script that never exits, and at one that exits
immediately while a `sleep` it backgrounded keeps stdout open. Both hang the old
code — the lookup runs on a background queue with the test's own 20-second
timeout, because a suite that hangs is worse than one that fails. Before:
`FAIL … never returned` for both. After: both return in about three seconds. A
third check holds the normal path to under two seconds, so the bound cannot be
bought by making the ordinary case slow.

**A consequence worth knowing:** a shell that would have answered in four seconds
now yields nil, and `locateTool` caches that absence until `forgetToolPaths()`.
That is what U5 said the behaviour was; it is now actually true. The escape is
the explicit mac-ocr path in Settings.

### U19 · Every batch-mutating control stays live during the C17 pre-flight — FIXED
*(2026-08-09 review; this is U1 again, by a route U1's fix does not cover)*

`Sources/Model.swift:404`. `add()` refuses only while `isRunning`, and
`ContentView` gates Add…, Clear List, Remove, the mode picker and both destination
controls on `model.isRunning` alone (`:89`, `:116`, `:119`, `:147`, `:173`, `:190`,
`:217`).

C17 inserted an asynchronous pre-flight between the click on Start and the batch
existing: `start()` freezes `let candidates = files`, sets `isPreflighting = true`,
and dispatches a per-file `PDFDocument` scan to a global queue (`:534-539`).
`isRunning` is not set until `run()` at `:637`. Throughout that window the batch
contents are already frozen and the entire UI is unlocked. `canStart` was updated
for the new flag (`:376`); the guard in `add()` and the seven `.disabled(...)`
modifiers were not.

Under the registered defaults — mode `searchablePDF`, `rebuildImages` true,
`warnDigitalText` true — the pre-flight always runs, and C17 moved it off the main
actor precisely because it is slow enough to freeze a 78-file batch.

Three ways it bites, in the same window:

- Drop a fourth file: `add()` accepts it, the header says four, the batch runs
  three, and the summary reads "Done — 3 of 3 succeeded" over a list of four with
  no output on disk for the fourth. That is U1 verbatim.
- Press Clear List: the list empties, the frozen batch still runs, and outputs are
  published for files the user just removed.
- Untick "Save beside each original": `destinationReady` goes false, but `run()`
  reads the destination late (`:622`) and never re-checks it, so `uniqueOutputs`
  falls back to `folder ?? file.deletingLastPathComponent()` (`:815-816`) and the
  whole batch is written beside the originals, into a folder the user never chose.

C17's register entry says only that Start shows "Checking…" and is disabled. The
add-refusal test at `Tests/main.swift:1848-1867` fakes `m.isRunning = true`;
nothing exercises `isPreflighting`.

**Fix:** one `isCommitted` flag — `isRunning || isPreflighting` — used by
`add()`'s guard, by `canStart`, by the drop target, and by all seven
`.disabled(...)` modifiers, including the Settings sheet's `runInProgress`.
The bug was not any one of those sites; it was that C17 added a state and eight
separate places each had to remember it. One derived flag is the thing that
cannot be half-updated next time.

`run()` now re-checks `destinationReady` as well. The file list is frozen at the
click and the destination is read at `run()`, so the two halves of the batch
definition were taken at different moments: unticking "Save beside each original"
during the pre-flight left `destinationReady` false while `uniqueOutputs` fell
back to `file.deletingLastPathComponent()`, writing the whole batch beside the
originals and into no folder the user had chosen. It now refuses and says so.

Guarded by five checks that drive `isPreflighting` directly. Verified to bite by
putting the old `guard !isRunning` back: `FAIL a file offered during the
pre-flight is refused too` and `FAIL …and the list is unchanged — 2`.

Note that "Start stays disabled" passes either way — `canStart` was the one site
C17 *did* update, which is precisely why the rest went unnoticed.

### U20 · Dropping a folder walks it recursively on the main actor — FIXED
*(2026-08-09 review; the same class U5 and C17 already fixed elsewhere)*

`Sources/Model.swift:96`. `filesInFolder` builds a `FileManager.enumerator` over
the whole subtree, materialises every URL with `compactMap`, filters, and sorts
with `localizedStandardCompare` — the collated comparison, the expensive kind.
`collectInputFiles` additionally fetches `.isDirectoryKey` per top-level URL
(`:70`).

All of it runs on the main thread: `resolveDroppedURLs` delivers with
`group.notify(queue: .main)` (`:52`), `OCRModel` is `@MainActor` (`:232-233`), and
`add` calls `collectInputFiles` synchronously. The Add… panel reaches the same
code with `canChooseDirectories = true` (`ContentView.swift:383`), and the drop box
advertises "Images and folders work too".

`.skipsPackageDescendants` prunes bundles; nothing bounds depth or count. On a
scanned-archive folder of tens of thousands of files, or any folder on a mounted
share where each directory read is a round trip, the window stops redrawing, the
drop highlight stays lit, and nothing responds until the walk finishes — no
progress, no way to abort, because the main thread is what is blocked. On a
stalled mount it does not return.

U5 moved `askLoginShell` off the main thread and C17 moved the digital-text scan
off the main actor for exactly this reason. The import path never got the same
treatment. `Tests/main.swift:923-955` tests `collectInputFiles` for correctness
only — unsupported types, dedupe, folder expansion, ordering, case — never on a
large or slow tree.

**Fix:** `add(_:then:)` does the expansion on a background queue and returns
immediately; the completion lands on the main actor. All three ways in — the
drop box, Add…, and files handed over by Finder — use it. The synchronous `add`
stays for callers that already hold an expanded list, and for the tests.

The dedupe deliberately happens *after* the hop, against `self.files` as it
stands at that instant rather than against a snapshot taken before the walk, so
two overlapping drops cannot each miss the other's files. `isCommitted` is
re-checked there too: Start can have been pressed while the tree was being read.

**The obvious test does not work, and the reason is worth recording.** A timing
bound needs a tree slow enough to be slow on every machine, and 4,000 files walk
in well under any threshold such a check could use — with the walk deliberately
put back on the main thread, "returned in under 0.25 s" still passed. The
property is stated without the clock instead: *when the call returns, the list is
still empty*. No blocking implementation satisfies that at any speed. With the
blocking version restored it fails with `4000 files already listed`.

### U21 · `isCommitted` is cleared before the digital-text alert, so an in-flight import lands in a frozen batch — FIXED
*(2026-08-09 second review; U19's flag and U20's async import, interacting)*

`Sources/Model.swift:636`. `start()` freezes `let candidates = files`, runs the
pre-flight, then sets `isPreflighting = false` **before** calling
`askAboutDigitalText`, which puts up a modal `NSAlert`. For the whole time that
alert is on screen, `isRunning` is false and `isPreflighting` is false, so
`isCommitted` is false — and U20's `add(_:then:)` completion, whose only defence
is `guard !self.isCommitted`, happily appends to a batch that was decided before
the alert appeared.

The load-bearing assumption was checked rather than assumed: main-queue work
*does* run behind a modal alert. `NSModalPanelRunLoopMode` is in the main run
loop's mode set, a `DispatchQueue.main.async` block fires inside
`CFRunLoopRunInMode(.modalPanel)`, and — the real test — an `asyncAfter` block
scheduled before `runModal()` ran while the alert was up and dismissed it with
`NSApp.abortModal()`.

So: drop a 300-file folder, press Start, answer the alert, and the run processes
the one frozen file while the list shows 301. `finishUp` logs
**"Done — 1 of 1 succeeded"** over 301 rows with nothing on disk for 300 of them.
That is U1 for the third time, and the second time this evening.

`isImporting` was published by U20 precisely so the UI could know an import is in
flight, and **nothing reads it** — `grep -rn isImporting Sources Tests Tools`
returns the declaration, two writes and two test assertions. `canStart` does not
mention it, so Start is available while a folder is still being walked.

**Fix, in two parts.** `isPreflighting` is cleared by a `defer` at the end of the
completion, so it covers the decision and not merely the scan — four of the five
branches hand off to `run()`, which sets `isRunning` synchronously, so
`isCommitted` never dips false between them. And `canStart` now includes
`!isImporting`, which is what that flag was published for.

**The reason this shipped is that the decision step was untestable**, so there is
now a seam: `digitalTextDecisionForTesting` stands in for the modal `NSAlert`,
which a headless suite cannot drive. A check installs it, records `isCommitted`
at the moment the decision is asked for, and returns `.cancel`. Restoring the
early clear turns it red:

```
FAIL the batch is still committed when the alert goes up — isCommitted was Optional(false)
```

Adding a test seam to production code is a real cost. It is worth it here
because the alternative is an invariant that can only be checked by reading, and
this defect is what reading it produced.

Three further checks cover `canStart` against `isImporting`, and one confirms the
fixture is genuinely born-digital — without which the pre-flight takes the
`digital.isEmpty` branch and never reaches the alert, and the whole block would
have passed while testing nothing. It did exactly that on the first run: a
one-line fixture is not enough text for `hasDigitalText`, and the diagnostic
check is what caught it rather than a green suite.

---

## The corpus itself

Found by the 2026-08-08 run; see [CORPUS-2026-08-08.md](CORPUS-2026-08-08.md).

### D1 · The headline corpus figures rested on material this app is not for — FIXED
`testdocs/`, classified with `Tools/classify-source.swift`: **27 of 78 documents
are scans.** 40 are born-digital, 10 were photographed by hand, 1 has no page
image at all. The pattern is not random — `newspaperArticle` is 7/8 born-digital
(ProQuest and NYT downloads), `manuscript` is 6/8 born-digital because those
files are *finding aids* rather than images of a collection, and `letter` is 5/7
hand-photographed.

README, HANDOFF and CHANGELOG all cite "78/78 process successfully, median 100%
line-start and line-end selectability, median 0.00 offset, median 100% word
retention". That is true of those 78 files and much weaker than it reads as
evidence about OCR on scans: for two thirds of them the pipeline was either
reproducing text the file already had, or working on a photograph of a
manuscript.

**Fix: the corpus was replaced, not the sentence.** `Tools/sample-zotero.py` now
classifies every candidate and keeps only scans, and it drops `manuscript` and
`letter` outright — in a historian's library those are archival photographs and
finding aids, which are Archive Processor's job. It uses
`Flattener.pageIsAnImage`, the same function the app uses to decide whether it is
about to discard someone's digital text (C17), rather than a second copy of the
rule that would drift from the first the way `picture-signals` did (T2). New
flags: `--added-since`, `--exclude-manifest`, `--types`, and `--allow-any-kind`
for reproducing an old corpus, which says in its own help what it costs.

The rebuilt corpus is **84 documents, all 84 verified scans** (the gate rejected
275 born-digital, 23 photographed, 2 with no page image). Measured through the
shipped pipeline:

| | |
|---|---|
| processed | **84 / 84** |
| line-start selectability | median **100%**, p10 100%, worst 91% |
| line-end selectability | median **100%**, p10 93%, worst 71% |
| word retention | median **99%**, p10 99%, worst 94% |
| text-layer offset | median 0.10, max 0.10 |
| runs overlapping vertically | **1.33%** — 74 of 5,564 pairs, in 23 of 84 documents |

`testdocs/manifest.tsv` now carries each document's scores alongside its source,
so a regression can be traced to a document instead of a median.

**The medians did not move; the tail got worse, and that is the finding.**
Born-digital documents score perfectly — OCR of a clean rendering of digital text
is an easy problem — so they were holding every percentile up. Worst-case
line-end went from a documented 86–95% to a measured 71%.

### D2 · Line-end selectability has a worse tail than documented — FIXED *(the documentation)*
HANDOFF put the weak spot at "86–95% on 1920s–50s letters and typescripts". The
real floor is **71%**, on a scanned typescript collection; 84% on two 1920s–40s
newspaper clippings. The documented range was written from a corpus two thirds of
which could not fail (D1).

**What the failures actually are**, from probing every line of the document that
prompted this (81% at the time):

- **5 of 6 misses: the drawn run is narrower than the box the *reference* pass
  reports.** Probing from 60% of the width instead of 85% finds the text, so the
  run is present and simply stops short. Part of that is inherent to the
  measurement — the reference boxes come from a second, independent OCR pass over
  the finished file, and the two passes disagree at the margins about trailing
  punctuation and hyphens ("…against us.-").
- **1 of 6: vertical.** Vision's box was inflated by a superscript footnote
  marker, so `bottom + height * baselineFraction` put the baseline high relative
  to the ink, and only a probe allowed to look above and below the line found it.

**Documentation fixed, code deliberately not.** The mechanism is understood and
the cost of acting on it is not worth paying: `draw` is the function where three
properties fight each other and every past "improvement" broke one of them
(invariant 3). A run that stops slightly short shortens a highlight; a change
that makes runs overlap breaks line-by-line selection outright, which is worse.

**A wrong turn worth recording.** The first diagnosis was that the metric
penalises short lines — 15% of a 20 pt box is a 3 pt probe, narrower than a
glyph, and an unfiltered probe did report "97", "203" and "op. cit.," as
line-end failures. A fix was written for all three tools. It was then reverted:
`score-corpus`, `probe-line-edges` and `probe-line-coverage` **already** filter
`text.count > 12`, so the artifact was in the throwaway diagnostic, not in the
instruments. Re-measuring with the "fix" in place changed the score by zero,
which is what caught it.

### D3 · Source line tightness is measurable and untracked — FIXED *(now quoted, and correctly labelled)*
`score-corpus.swift` has always reported it and no headline figure ever quoted
it. Now measured across the whole corpus: **1.33% of adjacent line pairs are set
closer than their boxes — 74 of 5,564 — in 23 of 84 documents.**

**Corrected, and the correction matters more than the number.** This was first
written up here as "adjacent *runs* overlapping vertically", i.e. as a property
of the text layer this app writes, and cited as evidence that a
`SearchableWriter` change had not broken invariant 3(b). It is nothing of the
kind. Every value feeding it comes from `pg.observations` — the reference OCR,
which reads the rendered *image*. The text layer is invisible to it, so the
number **cannot move in response to any change to the writer**, and citing it
that way is circular. `Tools/README.md` called it "source line tightness" all
along; the misreading was introduced here, in this register, and is now fixed
along with a warning comment at the point of computation.

What it does measure — how tightly the material is set — is worth having: it is
the difficulty rating of the corpus. The metric for *our* runs is
`Tools/score-line-separation.swift`, and comparing it across a change needs two
separately-compiled binaries, one per revision.

## Verified on a running app

Four things could not be settled by reading or by the suite, and sat in `TODO.md`
saying so. They were run against the real app in a headless
[Tart](https://github.com/cirruslabs/tart) macOS VM — its own virtual display, so
nothing appears on anyone's screen, driven over VNC because VNC-injected input
bypasses the guest's TCC entirely. Procedure in [Tools/README.md](Tools/README.md).

| check | result |
|---|---|
| window recoverable after closing it mid-run | **passes** — the reopened window shows the live batch ("27% · 0 of 3 files · 1 running") with Cancel available, and ⌘0 restores it too |
| Settings on a display shorter than ~700 pt | **passes** — 560x512 at 1024x640, Done visible (U15) |
| keyboard tab order | **passes** — idle: Settings → mode picker → Start OCR → Add… → Clear List → remove-file → Save-beside, cycling; mid-run: Settings → Cancel → Copy, which is exactly the enabled set. Disabled controls are correctly skipped |
| VoiceOver announcements | **not run** — deliberately out of scope for this pass |

It found U17, which no amount of reading was going to find, and which is the most
serious interface defect in this register after U13.

**Three instruments lied before any of it worked**, which is the usual tax and is
worth writing down:

- The window-counting probe filtered `kCGWindowOwnerName` on `"VisionReader"`.
  The bundle name is `Vision Reader GUI` — with spaces — so it reported **zero
  windows while the app had four**, and the first reading of U13 was "the reopen
  does nothing". It filters by pid now.
- **The guest's virtiofs mount served a 90-minute-old `App.swift`.** A build off
  that stale copy looked exactly like "the fix does not work" — the fix was
  measured as ineffective before the mtimes were compared. Sources go over the
  guest agent now, not through the share.
- **A TCC prompt sat on the VM's screen stealing every keystroke.** The first tab
  walk produced a tidy, entirely fictitious three-stop cycle: it was Tab moving
  between the prompt's *Don't Allow* and *Allow* buttons.

## Test coverage

### T1 · No fixture satisfied invariant 5 — FIXED
*(found in the second review)*

CLAUDE.md invariant 5 requires a fixture with at least two pages of differing size
**and** at least one rotated page, because a uniform or single-page fixture is
structurally blind to the "every page inherits page 1's box" class of bug. No
fixture met it: `both.pdf` had two sizes but no rotation and only ever reached
`compose(drawImages: false)`; `rotated.pdf` was one page. Neither
`Flattener.flatten` nor `JBIG2.assemble` had ever seen a document with both
properties.

**Fix:** "mixed page sizes and rotation through the whole pipeline" — three pages
(612x792, 456x710, and 700x540 rotated 270°) through the real
`OCRModel.makeSearchablePDF`.

Two things had to be got right for it to bite, both worth recording:

1. **The rotated page's size was chosen so its *displayed* box is distinct.** The
   obvious 792x612 displays as 612x792 — exactly page 1's box — so a page that
   wrongly inherited page 1's size would have looked correct. 700x540 displays as
   540x700.
2. **The assertion compares pages to each other, not to an absolute position.**
   The first two attempts both passed with the bug reintroduced. A wrong layer box
   is not visible as a wrong *published* page size (those come from
   `JBIG2.assemble`, which reads the source geometry and is unaffected) nor as
   missing text; it shows up as drift, because `qpdf --overlay` scales the
   mis-sized layer onto the image page. And an absolute tolerance does not
   discriminate — there is a constant ~20 pt gap between a drawn baseline and the
   run's midY, so any tolerance loose enough to accept a correct build accepts the
   broken one too.

Both lines are drawn at half their own page's height, so their offsets must
agree. Measured, reverting `kCGPDFContextMediaBox` to an `NSValue`:

| | correct | with the bug |
|---|---|---|
| page 1 offset | +20.0 | +20.0 (page 1 is never wrong — it *is* page 1) |
| page 2 offset | +19.0 | **−15.6** |
| divergence | 1.0 pt | **35.6 pt** |

Also confirms invariant 4 is still live on macOS 26.6: an `NSValue` passed as
`kCGPDFContextMediaBox` is accepted and silently ignored, and all three pages come
back as page 1's size.

### T2 · `picture-signals` measured a page production never renders — FIXED
*(found by the second review)*

`Tools/picture-signals.swift` read `nativeDPI(of:) ?? 300` while `flatten` moved to
`rebuildDPI(of:)` in C9. The two differ on exactly the pages whose `nativeDPI` is
under the 150 floor — 84 of 214 sampled corpus pages — and the difference is large
enough to **invert the verdict**:

| Hoffman 1923, p12 | DPI | raster | ink | tone | verdict |
|---|---|---|---|---|---|
| the tool | 10.55 | 90x117 | 0.242 | 0.940 | **picture** |
| production | 300 | 2588x3330 | 0.078 | 0.013 | **text** |

`Margalit_2013` p4 flips the same way. Near the thresholds the tool biases both
signals toward "picture", which is the wrong direction for anyone calibrating
`pictureInkThreshold` or `pictureToneThreshold` — the two constants that decide
whether a page is destroyed by 1-bit thresholding.

Diagnostic only: nothing in the shipped app calls it and no user file is damaged.
It earns an entry because `Tools/README.md` points at this tool for exactly that
calibration, and CLAUDE.md's "suspect the instrument first" section exists because
this project has been burnt by bad instruments before.

**Fix:** the tool calls `Flattener.rebuildDPI`. `Tools/score-routing.swift` was
never affected — it calls the real `flatten`.

### T3 · Six paths had no coverage at all — FIXED
Every gap TODO.md listed under "Correctness and coverage", closed. None of them
found a new defect, which is worth recording as plainly as a defect would be:

- **Concurrent *searchable* runs.** The concurrency test ran in text mode, so the
  route C8's content-loss race lived on had no multi-file coverage. Two
  searchable files at once now assert both outputs are complete *and* carry their
  own document's text and not the other's — identical fixtures could not have
  shown the failure being looked for.
- **Encrypted PDFs and `--password`, end to end.** The paths existed and had
  never run. The fixture is checked for being genuinely locked, and unreadable
  without the password, before anything is concluded from the code that opens it.
  The wrong password fails loudly rather than publishing blank pages.
- **`rebuild: false`,** where C7 and C10 both bit. Two pages of differing size,
  per invariant 5, since this path takes its geometry from the source.
- **`makeSearchablePDF`'s failure and cancel branches** — a file that is neither
  PDF nor image, a binary that cannot be launched, and a pre-cancelled control
  that must report `.cancelled` and publish nothing.
- **`publish`,** which is the step that touches the user's disk and the subject
  of invariant 2. Both branches: a fresh destination, and replacing a previous
  run's output. It is now `internal` for the same reason `makeSearchablePDF` is.
- **Colour pages.** The dangerous case is not a photograph but a pale tint: pure
  yellow has luminance 226, so a tinted figure scores almost no ink, gets called
  text, and is thresholded to blotches — 99% of one real page was lost that way.
  The fixture is a saturated yellow figure with paler detail inside it, and the
  assertion is that the router sends it to JPEG rather than to 1 bit.

### T4 · Three checks written for 1.2.0 that cannot fail — FIXED
*(2026-08-09 second review. Three more of these, in one evening, after the round that added them was watching for exactly this.)*

Each was written to guard a 1.2.0 fix, each passes, and none of them can go red.

- **`Tests/main.swift:4448` — U18's "a real shell still answers promptly".** It
  times `Runner.locateTool("mac-ocr")`, but `locateTool` checks
  `/opt/homebrew/bin/` first and mac-ocr is there, so `askLoginShell` is never
  entered and the check times three `stat` calls. The other two checks in that
  block both drive the *failure* path via a name that does not exist. **Nothing
  in 418 checks reaches a successful login-shell lookup**, so the read
  accumulation and `sawEOF` latching that U18 newly wrote have no coverage at
  all — for exactly the population U18 was written for, whose mac-ocr is *not* in
  those three prefixes.
- **`Tests/main.swift:1981` — U20's "…on the main thread".** It evaluates
  `Thread.isMainThread` in the suite's own top-level scope, not inside the
  completion. `check` takes a plain `Bool`, so this is true before the completion
  runs, after it runs, and if it never runs. Deliver the completion on a global
  queue and it still passes.
- **`Tests/main.swift:1987` — U20's "the completion really did land later".** It
  compares two `Date()` samples taken in program order with three `check()` calls
  between them. `total > returnedAfter` is arithmetic, not evidence; a fully
  synchronous implementation satisfies it.

The register already carried three of these (T1's fixture, the crop-box test) and
round one added three more that had to be rewritten before they bit (R25, U20's
timing bound, C20's probe twice). The pattern is now unmistakable enough to name:
**a check written after the fix, and never watched failing, tends to assert
something adjacent to the property rather than the property.** The two U20
entries here were both written in the same sitting as a third that *is*
discriminating, so the discipline was applied unevenly within one block.

**Fixed, and each replacement was watched failing.**

- The main-thread check records `Thread.isMainThread` **inside the completion**
  and asserts the recorded value, so it is false if the completion never runs.
- "the completion really did land later" is replaced by "the completion had not
  arrived before the pump loop started", which sets a flag on the first pump
  iteration. Reverting `add(_:then:)` to the synchronous form turns it red —
  `returned in 0.169s, finished in 0.17s` — where the old arithmetic comparison
  passed.
- The login-shell block gains three checks that actually enter `askLoginShell`,
  by pointing `SHELL` at a script that echoes a real path and asking for a tool
  name that is in none of the three prefixes: one for a plain answer, one for a
  path **delivered in chunks with pauses**, which is what the rewritten
  accumulate-and-latch loop exists for, and one for an answer that is not
  runnable. Making the loop drop its accumulated tail turns the first two red.
  The old check is kept but renamed to what it measures — the prefix scan.

One honest note on the first: reverting to a *synchronous* completion still
passes it, and correctly so. A synchronous call from the main thread is on the
main thread; the property is delivery-on-main, and that is what it now tests.
The asynchrony is the second check's job.

### T5 · Six calibrated constants nothing checked, found mechanically — FIXED
*(2026-08-09. The first campaign of `Tools/mutate.py`, which exists because nine checks in this register could not fail.)*

Twenty-four mutants: each a calibrated constant moved far enough to change
behaviour, or a guard from a specific fix undone. **Sixteen killed, six survived
that should not have, two survived legitimately.**

The six gaps, all of the same shape — a value the doc comment calls *measured*,
with nothing asserting it:

| constant | moved to | what the register says it costs |
|---|---|---|
| `headroomFactor` | 1.5 → 0.95 | line selection 84-91% → 80-83% on archival material |
| `reserveEms` | 0.25 → 0 | adjacent words weld: `valuablestudy` — C18's fourth property |
| `pictureInkThreshold` | 0.15 → 0.9 | halftones thresholded to blotches |
| `minimumPlausibleScanDPI` | 150 → 10 | a logo's DPI taken for the page's — C14 |
| `fallbackRebuildDPI` | 300 → 72 | untrusted pages rebuilt at a quarter the resolution |
| `baselineFraction` | *killed* | (caught, by the fragment checks) |

**`reserveEms` is the one worth dwelling on.** C18's entry says: "It bites: with
`reserveEms` set to 0 the words weld, and that is checked *first*, so a
silently-ineffective guard cannot pass." That is true of the *mechanism* and
false of the *shipped value* — the check sets `reserveEms` itself before each
case, so it proves welding happens at 0 and says nothing about the default being
0.25. Someone could ship `reserveEms = 0` and the suite stays green. The C18
sentence was accurate about what it tested and misleading about what that
protected, which is T4's pattern in the project's most carefully documented
invariant.

**Fix:** a drift-guard block asserting each calibrated value, with the cost of
changing it in the failure message and a pointer to the tool that re-measures
it. Plus behavioural cover where it was cheap: a page whose only image is a logo
must rebuild at the fallback rather than at 14 DPI, and `safeInt` is now tested
where it lives — NaN, both infinities, past `Int`'s range — rather than only
through a caller that guards it first.

Stated plainly, because overclaiming here would be the same mistake again: **the
drift guard is not a behavioural test.** It cannot tell you 1.5 is the right
headroom factor. The corpus is what validates these values; this only stops one
of them moving in passing with a green suite as reassurance.

**Second campaign, after the third review's fixes: 27 mutants, 25 killed, two
survivors — the same two, both correct.** Every gap the first campaign found is
closed, and the catalogue grew by the two mutants T7's ambiguity had been hiding
plus two for the bundled-tool architecture check.

**Two survivors are correct and stay.** `maximumPageMegapixels` 400 → 40,000 is
a safety ceiling with deliberate slack, 19x the largest page in the corpus;
pinning it would assert a number rather than a property, and its *behaviour* is
already covered by the refusal check. `R25`'s depth-aware pruning survives for
the reason R25 already records — CoreGraphics walks the shallower branch first in
every arrangement tried, so the case cannot be built. The harness independently
confirming a limitation this register had already written down is the outcome
that gives the rest of it credibility.

**The harness was wrong twice before it was right, and both are recorded in its
own docstring.**

- It used `git worktree add --detach HEAD`, so it tested the last commit. It
  reported all six gaps as still-surviving against checks written to kill them
  that were sitting uncommitted three feet away — `453/453 passed` when the
  suite had 468 checks. It copies the working tree now, runs a baseline first,
  and flags any mutant whose run reports a different check count.
- Its "did not compile" test matched bare `error:`, so a mutant that **trapped
  at runtime** — printing `Fatal error: Double value cannot be converted to Int`
  — was scored INVALID rather than killed. Wrong in the direction that flatters
  the suite. It matches a compile-error pattern now.

A tool for detecting instruments that lie, lying twice in its first hour, is
the most on-brand thing this register contains.

### T6 · Three checks written for the bundling that cannot fail — FIXED
*(2026-08-09 third review. The third consecutive round to add checks of this kind while looking for them.)*

- **`Tests/main.swift:4767` — the fat branch is never reached.** Every fixture is
  a *thin* Mach-O, so the universal branch of `containsNativeSlice` — the one the
  bundled `mac-ocr` actually takes — has no coverage. Break the `fat_arch`
  stride or the `8 + i * stride` offset and the suite stays green while
  `bundledTool("mac-ocr")` returns nil on every Mac.
- **`Tests/main.swift:4835` — the precedence check passes either way.** It plants
  a probe in the bundle and asserts `locateTool` finds it, but the probe name
  exists nowhere else, so hoisting the Homebrew loop above `bundledTool` — a
  plausible refactor — cannot fail it.
- **`Tests/main.swift:4794` — the planted fixture is not verified.** The only
  check that kills the `bundle-arch-check` mutant copies a fixture with `try?`
  and returns `bundledTool(...) == nil`, which is also true when the copy silently
  failed. It reports green for the wrong reason.

### T7 · Two ways the mutation harness can report a clean result it has not earned — FIXED
*(2026-08-09 third review; the tool for finding unfalsifiable checks, twice unfalsifiable itself)*

- **The "matched exactly once" guard is vacuous.** `re.subn(..., count=1)` returns
  at most 1, so `if n != 1` only catches *zero* matches. A pattern matching two
  sites mutates the first and reports a normal verdict. This is live: the R23
  mutant's pattern matches `readOutline`'s bound **and** `copyOutline`'s identical
  one, so the log asserts coverage of a bound that has never been perturbed —
  and `copyOutline` is the mirror R23 exists because it was missing.
- **NOT-APPLIED counts as recorded.** `already_done()` treats any logged row as
  done, so a mutant whose pattern stops matching after a refactor is skipped
  forever. Every later run prints `26 mutants, 26 already recorded, 0 to run`
  and a clean bill of health for a catalogue it stopped applying.

**Fix:** count matches with `findall` *before* substituting and treat anything
other than exactly one as NOT-APPLIED, naming the count; and treat only
`SURVIVED`/`killed` as recorded, so NOT-APPLIED, INVALID and MISMATCH are retried
on the next run and listed loudly at the end under "NOT EVALUATED — no verdict,
not a clean result".

The first change immediately caught the live case it was written for:

```
[1/1] logic/R23-readOutline-bound   NOT-APPLIED   pattern matched 2 sites — ambiguous
```

The catalogue now carries **two** mutants there, anchored to their functions'
return types — `R19-readOutline-bound` and `R23-copyOutline-bound`. Both are
killed. Until now the log asserted this bound was covered while `copyOutline`'s
mirror had never been perturbed once, which is precisely the code R23 exists
because it was missing.

### H2 · leptonica ships with no licence, and the count cannot notice — FIXED
*(2026-08-09 third review; a compliance defect in a public download)*

`Tools/bundle-libs.py:104`. `copy_licences` adds a formula to `seen` *before*
looking for any licence file and returns `sorted(seen)`, so the reassuring
`licences for 12 package(s)` counts **formulae encountered**, not notices
written. A formula whose keg root holds no LICENSE/COPYING/COPYRIGHT contributes
nothing and is still counted. `LICENCE_NAMES` is defined at line 31 and never
used — the fallback the author intended is simply absent.

Measured: the shipped 1.5.0 bundle carries notices for **11** of the 12
formulae. Missing is **leptonica** — 2.2 MB of BSD-2-Clause code in
`Contents/Resources/lib/libleptonica.6.dylib`. Its Homebrew keg contains no
licence file at all (`find … -iname '*licen*' -o -iname '*copying*'` returns
nothing), which is why the copier found none.

BSD-2-Clause clause 2 requires reproducing the copyright notice in the materials
accompanying a binary redistribution, so every disk image since 1.5.0 has been
out of compliance — while the build printed a number that looked right and the
module docstring listed leptonica among the licences that travel with the
binaries.

The number is the real defect: it is structurally unable to drop when a notice
goes missing, so the next formula without one fails silently too.

**Fix:** `copy_licences` returns the formulae for which a notice was actually
**written**, plus those for which none was found; a formula in the closure with
no notice now **stops the build**. leptonica's BSD-2-Clause text — taken verbatim
from the project's own source, since its Homebrew keg genuinely has none — lives
in a `VENDORED_LICENCES` table so the gap is filled rather than tolerated.

The shipped image now carries 18 notice files covering all 12 packages, and the
count is of notices written rather than formulae seen. Guarded by
`Tools/fault-inject.sh missing_licence`, which failed against the code as
shipped in 1.5.0 — `leptonica is bundled with no licence notice`.

### H1 · Four pieces of housekeeping — FIXED
- **`ocrAllPages` and `strategy` deleted.** Flags of mac-ocr's `searchable-pdf`
  subcommand, which this app has never invoked — so they were settings that could
  not affect anything, carried through `Prefs.Snapshot`, reset by "Reset to
  Defaults", and written into every `UserDefaults` this app has ever touched.
  Decided: delete rather than keep as a record of the CLI surface. A dead setting
  that looks live is a trap, and the branch of `Runner.arguments` that emitted
  them went with them — `arguments` now builds the Extract Text command and
  nothing else, which is the only command it has ever really built.
  The measurement that chose `standard` over `auto` (8462 chars vs 7941, against
  7979 for the plain text output — auto's partitioned second pass double-emits on
  300 DPI book pages) is recorded here rather than lost with the default.
- **`baselineFraction`'s comment** pointed at a sweep in `Tests` that no longer
  exists. It now points at `Tools/probe-text-offset.swift`, which is what
  re-measures it, and records what the shipped value holds on the corpus.
- **`headroomFactor`'s prose read backwards** against the code — it said "lower
  means shorter glyphs" while `headroom` *divides* by it. The prose is fixed, not
  the code: inverting a corpus-calibrated constant to match a wrong sentence
  would have undone the measurement in the same comment.
- **`Flattener.jpegQuality`** was a defaulted parameter no caller ever overrode —
  a constant with extra steps, and one that had to be threaded through every call
  site to stay consistent. Now `Flattener.pictureJPEGQuality`.

### T9 · The release gate read the text layer, so a destroyed page image passed it — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A12.1, A12.6 and
A12.8. Every release figure in `HANDOFF.md` rested on this tool.)*

`Tools/score-gate.swift`'s own header names the requirement: *"Read the output PDFs at the
end, not just the outcome enum. Page count is not sufficient verification (invariant 1) and
neither is a success value; **a stream a reader cannot decode still opens as a page**."* What
it read was `PDFDocument(url:)?.string?.count` — **the text layer**, which `SearchableWriter`
draws itself and which is independent of the image underneath it. A requirement stated
correctly and then not implemented.

**Reproduced on this project's own outputs.** 400 bytes of `0x41` into the middle of each
image stream of a real gate output — `/Subtype /Image` only, so the embedded font and
therefore the text layer are untouched:

```
              pages   characters      qpdf --check
original        3       1862          clean
corrupted       3       1862          "No syntax or stream encoding errors found"
              2         1241
              2         1241
```

`pages`, `characters`, `outputs` and `colour` do not move. On the review's five-page sample,
48.3% / 48.8% / 52.7% / 50.8% / 84.3% of each page's rendered pixels had changed.

**Fixed: every page of every output is rendered and compared against the page it came from.**
Each output is paired with its input through `OCRModel.uniqueOutputs` — the run's own
function, not a guess from the names on disk, and cross-checked against the directory so a
drift between the two is a loud failure rather than an unverified corpus. Page counts are
compared with the input's. Then each page pair is reduced to a 28×28 ink grid and correlated.

**Three wrong instruments were built before one bit, which is the part worth keeping.**

1. **"A destroyed page renders as paper" is false.** The first version tested each output
   page for renders-as-paper, on the assumption that a stream a decoder chokes on draws
   nothing. Measured against the corruption above: mean ink **0.05973 → 0.37470**, no page
   blank, nothing reported, **exit 0**. A JBIG2 arithmetic decoder fed rubbish emits rubbish.
   A decode-error check fails for the same reason — no error is raised. So there is no
   instrument that can see this without the input.
2. **A darkness ratio would need a threshold nothing calibrates.** The rebuild legitimately
   changes every pixel — 1-bit binarisation, MRC layering, a different resolution. Grid
   *correlation* is used instead: it asks whether the ink is still in the same places, is
   scale- and offset-invariant, and so does not care that a 1-bit page is uniformly darker
   than its greyscale original. On the fixtures: **0.94338** clean against **−0.19759 …
   0.15363** corrupted, all five pages named, exit 1.
3. **The crop box was the wrong box, and calibrating on real documents is what found it.**
   A 36-document stratified run produced **177 release-blocking findings, every one false**,
   because the output's crop box was compared against the input's. That is CLAUDE.md's own
   sentence — media box for what is kept, crop box for what is shown — so a rebuilt page's
   crop box is its whole sheet while the source's is a window on it:
   `Boltanski p23  source crop 779x628 at (45,81) · output crop 1031x727 at (0,0)`. A
   correlation between two different regions is noise with a sign. Both sides now take the
   **media box**. Two synthetic fixtures had agreed to 0.94 and would have shipped it.
4. **The grid read paper tone, not ink, and the 1-bit route is *meant* to throw paper away.**
   With the boxes fixed, one blocking finding survived on 1,701 real pages, and it was
   wrong: `1954 - Why.pdf` p3 keeps every word legible and drops the grey of aged paper, and
   the raw grids correlate at **0.435**. Rendered and looked at, not argued about. Fixed by
   correlating **high-passed** grids as well — each cell minus its 5×5 local mean, which
   discards anything smoother than the window — and taking the larger of the two: the same
   pair reads 0.655 high-passed while the corrupted fixtures stay at 0.17–0.26.
5. **And that rescue then let a genuinely destroyed page through.** `doc-b p2`, image stream
   overwritten, scored raw −0.198 and high-passed **+0.510** — above the floor, reported
   instead of blocked. The high pass exists to forgive *paper removal*, which makes a page
   **lighter**; that page was **9.2x darker** than its input, against a measured legitimate
   maximum of 1.13x. So above 2x darker the raw correlation stands alone, and it fails on
   −0.198 as it should. Five of five corrupted pages block again.

**Calibration, stated as the numbers rather than as a claim.** Every legitimate page measured
sits at or above 0.655; every destroyed page at or below 0.261, with the darker-than-2x rule
in force:

```
                                       raw     high-passed  resemblance
  corrupted doc-b p2                  -0.198      0.510       -0.198   (9.2x darker)
  corrupted doc-a p1                  -0.189      0.196       -0.189
  corrupted doc-a p2                  +0.107      0.173       +0.107
  corrupted doc-a p3                  +0.154      0.261       +0.154
  corrupted doc-b p1                  +0.106      0.095       +0.106
  ------------------------------- the 0.45 floor ------------------------
  1954 - Why p3  grey paper whitened  +0.435      0.655       +0.655
  1947 magazine p3                    +0.764      0.738       +0.764
  AI 2027 p51                         +0.700      0.794       +0.794
  tonal-plate fixture (R57's page)    +0.924      0.811       +0.924
  Boltanski p23 (203-page book)       +0.995      0.980       +0.995
  clean fixture doc-a p1              +1.000      0.999       +1.000
```

A per-cell standard-deviation grid was measured too and is **worse**: it scores the corrupted
pages 0.387–0.599, because noise has texture.

**Final state on real material: 36 documents, 1,701 pages, 0 release-blocking, 3 reported,
exit 0** — and the corrupted pair still exits 1 on all five pages.

**A fade signal was added as an R56 detector, measured useless by the review of this diff, and
removed.** The idea was that a pale drawing erased by the 1-bit route is invisible to the
correlation — true, the text on the same page holds it at 0.993 — and would show up as ink
falling away with the layout unchanged. Measured through the shipped pipeline:

```
  pale-drawing fixture   the drawing IS erased    src 0.07178  out 0.02513  ratio 0.35009
  text-only fixture      nothing is damaged       src 0.07000  out 0.02515  ratio 0.35934
```

**0.9% apart.** What the ratio measures on the 1-bit route is the *paper tone the rebuild is
meant to discard* — 0.070 to 0.025 in both cases — not the drawing. No threshold between
0.35009 and 0.35934 means anything, which is the same confound `highPassed` exists for on the
correlation side.

**And the threshold as written could not have fired on the case it was for.** It was 0.35 with
a strict `<`, derived by hand-dividing the *rounded printout* — 0.0251 / 0.0718 = 0.34958 —
instead of the numbers the code computes. The fixture lands at 0.35009. So "the only signal in
the tool that can see R56" described a check sitting on the wrong side of its own measurement,
in an entry about checks that cannot fail. The darkness columns stay as a run-to-run drift
measure; nothing is named on them and no release is blocked by them. **`FEATURES.md`'s shape
signal remains the only thing that would see R56**, and `Tools/score-threshold-loss.swift`
remains the estimator built for it — so the priority claim was false as well.

**And the repaired gate immediately found a real defect on the default route: C23.**

**Also fixed in the same tool, from A12.6 and A12.8:**

- **It hung for ever on an empty run.** `if !isRunning && done > 0` was the only path to
  completion, so a mistyped corpus path waited indefinitely — indistinguishable from the
  hang requirement 1 exists to prevent, arriving through a door the header does not cover.
  Now: an empty corpus is refused with exit 2, and a batch that is neither committed nor
  progressing for two consecutive ticks reports the last six log lines and exits 3.
  `isCommitted` rather than `isRunning`, because the pre-flight opens every document and is
  minutes of legitimately not-running time.
- **The tallies never had to add up.** `succeeded + failed == documents` and
  `outputs == successes` are asserted now, and the enumerator no longer counts whatever was
  already in the directory: `documents 1 … outputs 2 characters 15187` was a previous run's
  leftovers reported as this run's products. A non-empty output directory is refused up
  front, because `uniqueOutputs` seeds its claimed set with the batch's *inputs* and not
  with the destination, so a second run into a used directory republishes over the first
  run's outputs and every byte comparison against "the previous run" becomes meaningless.
- **The colour count read only the first 4 MB** of each file, biasing it against exactly the
  picture-heavy documents most likely to carry colour. Whole file now. Still a syntax test:
  a `/DeviceRGB` inside a compressed object stream is invisible to it, so it stays a lower
  bound — just not one that shrinks with file size.

**A `--verify <corpus> <outputs>` mode was added, and it is the reason any of the above
could be tested.** The whole cause of A12.1 standing was that nothing had ever made this
tool's verification fail; a 78-minute run per attempt guarantees it stays that way.
Corrupting a real output and re-verifying takes seconds, and it is what caught instruments
1 and 3.

**What it does not catch, stated so nobody over-trusts it.** A partial *blob* — R57's shape —
is still indistinguishable from a legitimate rebuild here: the tonal-plate fixture scores
0.924 and 0.92x the ink, which is what a correct rebuild of that page also looks like. What
catches that is the per-page ink, resemblance and fade columns now written to
`per-document.tsv`, diffed against the previous run: the same mechanism, and the same reason,
as the per-document character column that localised a 23-character drift out of 34.2 million.

**Cost, and the first version of this paragraph flattered it.** The verification is serial and
renders two pages per output page. Measured on the 36-document calibration set: 1,701 output
pages verified in about 7 minutes against about 7 for the batch itself — so verification is
roughly **1:1 with the run**, not "half as much again". At 16,987 corpus pages, 9.99x the
calibration set, that is **over an hour** on top of the existing 78 minutes.

**Three more defects in this diff, found by the adversarial pass over it and fixed here:**

- **A run in which a document failed outright exited 0.** `failed` never produced a
  release-blocking entry, so only a tally *inconsistency* blocked — and successes plus failures
  equalling documents is perfectly consistent with a document the app could not convert.
  Measured: three documents, one unreadable, printed "failed 1" and exited **0**, so
  `gate testdocs /tmp/out && ship` shipped. Worse in the general case: if *every* document
  fails, the result block prints `worst page 1.00000` over a run that converted nothing. And it
  contradicted the tool's own exit 3, which blocks when the batch never *started*.
- **`per-document.tsv` was rewritten in place**, destroying the baseline this entry names as
  the only thing that localises a partial loss — **by the act of re-measuring**, including
  under `--verify`, which is nothing but a re-measurement. The empty-directory refusal did not
  protect it either: it counts PDFs, and keeping the tsv while deleting multi-gigabyte outputs
  is the plausible thing to do. Never overwritten now.
- **`--verify` with one path silently became a run**, with `"--verify"` as the corpus root, and
  a bare `gate` indexed out of range. Both print usage and exit 64.

**Two more from the same pass, both fixed here.** The blank test was
`spread == 0 || darkness < 0.004`, and the darkness half was wrong in both
directions: a sparse page of real text can sit under 0.004, and calling it blank
meant **its pixels were never compared at all** — destroyed to near-white over a
near-white source, the comparison was skipped rather than made. A page is flat when
it has no variation; whether that flat page is paper or a solid black sheet is what
`darkness` then says, and a flat *dark* page is now a failure rather than a silent
"blank". And grid cells that received no pixels were filled with a literal `0.0` in
**both** grids, putting perfectly-correlated points into every comparison — on a page
whose aspect ratio leaves rows of cells empty that inflates the correlation towards 1,
the one direction a gate must never drift. The comparison now intersects the two
coverage maps.

**Two things left open, stated rather than claimed closed.**

- **The resemblance figure is whole-page, and it dilutes.** A reviewer measured **0.52** on a
  page whose lower 55% was overwritten — above the floor, REPORTED rather than blocked. Four
  attempts to reproduce that number here failed (400 bytes mid-stream and a corrupted tail, on
  both a third-page-text and a full-sheet-text fixture; all four blocked), but the gap is real.
  **The obvious repair was built and reverted**: scoring a page as the worst of itself and its
  sixteen 7×7 regions gave **11 release-blocking findings on 36 real, undamaged documents**,
  against 0 for the whole-page figure on the same 1,701 pages — four of them regions too flat
  to correlate at all, where the high-passed residual of two nearly-blank quarter-pages was
  compared instead. A gate with eleven false blockers is worse than one with a known dilution.
  A real fix needs a region rule requiring raw structure on both sides, a floor calibrated on
  regions rather than inherited from the page, and a corpus run behind it.
- **The watchdog covers a run that never starts, and nothing else.** Once any document
  finishes, `done > 0` resets the counter, so a batch that stalls mid-run prints its progress
  line for ever — A12.6's hang in the one form still reachable. A stall bound over a corpus has
  to survive a single 64.84 MP page, and guessing one is how R44 happened.
### T10 · The tenth check that cannot fail — and it was invariant 2's only guardian — FIXED
*(found 2026-08-14 by the whole-codebase review; `REVIEW-2026-08-14.md` A11.1–A11.4. The
highest-value area of that sweep, established by four full suite runs against mutated
product code.)*

**CLAUDE.md invariant 2 had no working test at all.** In the block headed *"partial results
are never published"*, which exists for that invariant:

```swift
let published = outDir.appendingPathComponent("published.pdf")
check("the truncated file is not at the destination",
      !FileManager.default.fileExists(atPath: published.path))
```

`published.pdf` occurred **exactly twice in the 8,600-line file: that declaration and that
use.** Nothing ever wrote it. The block never called `makeSearchablePDF` and never called
`publish` — it called `compose` directly into `staged.pdf`. So it asserted that a path no code
in the test had ever named did not exist, under a label claiming to cover the page-count gate.

**Proved by mutation.** Deleting the gate the check claims to cover —

```swift
guard produced == expected else { report(.failed, "The result had \(produced) pages …"); return }
```

— left the suite at **862/862, exit 0**. The mechanism CLAUDE.md names *verbatim* ("stages
output and moves it into place **after verifying the page count**") could be deleted with a
green suite. Two more of that block's five checks carried no information either: one restated
a value asserted on the line above, and its comment said "a previous good output must survive
a later **failed run**" when no run happened between writing the file and checking it. **3 of
5.**

**Fixed, and the fix is a place rather than a check.** The verify-then-move pair is now one
named function, `OCRModel.publishVerified(_:expecting:to:)`, and the refusal's wording is one
function, `incompleteRefusal`, because there are two call sites — an early one that fails a
short result before the outline rewrite and the annotation transplant are paid for, and
`publishVerified` immediately before the user's disk is touched.

**And it is defence in depth, not the closing of a hole.** A first version of this entry said
"the file that actually lands was never the file that was checked". That is **false**, and an
adversarial review of this diff caught it: the outline branch only adopts `outlined` when
`PDFPageCount(outlined) == expected`, and the annotation branch re-reads `finished` and refuses
on `after != expected`. Every path to `publish` already verified what it was about to publish.
What the named function adds is a **single place the invariant lives**, which is what lets one
check drive it with a deliberately short file — and the register carrying an overstated claim
about its own fix is the shape four false entries here already have.

What the block now does, with the real functions:

- `incompleteRefusal` over a genuinely truncated compose, asserting the refusal exists, that
  it says "nothing was written", and that it names both counts. A11.8 recorded that **neither**
  of `makeSearchablePDF`'s refusal messages was asserted anywhere, so the wiring from
  predicate to reported sentence was untested in both directions.
- **The check A11.1 is about**: a good three-page output at the destination, a one-page
  staged file offered for publication, refusal, and the good file **byte-for-byte** intact
  afterwards. Byte comparison deliberately — the truncated file also opens and also has
  "some pages", so `fileExists` and a page count are both satisfied by the destroyed state
  the invariant exists to prevent.
- The inverse row, per CONTRIBUTING 4d: a complete result **does** publish, and is *moved*
  rather than copied. Without it an app that never writes anything satisfies the three checks
  above.
- **End to end through the real pipeline**: a run whose destination is a **folder** holding
  someone's file. It composes, reaches the new call site, throws at `publish`, reports
  `.failed` in the words the user sees, and the file inside is byte-for-byte intact. A
  directory is the one *reachable* way to fail at the publish step: nothing in the pipeline can
  produce a short staged file, which was established by trying — a cancel is caught before the
  gate, and PDFKit repairs a page tree that over-declares its `/Count` rather than handing back
  a nil page. So the page-count half is defence in depth, tested at its seam.
- **A pre-cancelled run reports `.cancelled`**, which makes T3's closing list true. It bites on
  the outcome and *only* on the outcome — and the first version of this block claimed otherwise.
  It asserted that a good file at the destination survived a pre-cancelled run, which holds for
  every possible implementation of `publishVerified`, because a pre-cancelled control makes
  recognition throw and the run returns before it composes anything. **An un-failable check,
  inside the fix for un-failable checks**, found by the adversarial pass over this diff and not
  by the author. It is the tenth entry in this register's own lesson: the instrument is wrong
  more often than the code, and most convincing when it agrees with you.

**T3's closing list is wrong in two places, and both are corrected by that last check.** It
records "**a pre-cancelled control that must report `.cancelled` and publish nothing**" as
closed. What is actually there is `check("a cancelled control refuses the work before it
starts", control.isCancelled)` — a property of `RunControl`, asserted without calling
`makeSearchablePDF` at all. And it records "**`rebuild: false`** … Two pages of differing
size, per invariant 5", which is A11.4:

- **the `rebuild: false` fixture never satisfied invariant 5.** Both pages came from
  `makeScannedPDF`, which hard-codes 612×792, so they were **the same size** — "a different
  size" was the *text drawn on the sheet*, mistaken for the sheet. The block had **no geometry
  assertion at all**, on the one route where C7 *and* C10 both bit. **Fixed**: three pages of
  three sizes with the last quarter-turned, built by the same `mixedPage` helper the
  invariant-5 block uses so the two fixtures cannot drift apart in what they mean by "a
  different size", plus a per-page display-box assertion and text checks on the narrow and the
  rotated page.

**Two more inert checks, from the same area:**

- **A11.2 · three doors-table rows could not fail, and U19's own recorded defect survived
  them.** `retryFailures cannot change a committed batch` used a one-file fixture and marked
  *that same file* failed, so the narrowing was the **identity map** and `files != before` was
  false whether the gate held or not. Mutating `canRetryFailures`' `!isCommitted` to
  `!isRunning` — U19's defect verbatim, and `mutate.py`'s own mutation applied to the seventh
  door — left the suite **862/862, exit 0**, while under it a retry in the pre-flighting and
  deciding states erased every verdict and silently narrowed a committed two-file batch to
  one. **Fixed**: the batch is two files, one failed and one not, so the narrowing is
  observable; `add` opens a *third* file, because adding a file the batch already holds would
  dedupe and go inert the same way. A quarter of CONTRIBUTING 4d's flagship control was
  decorative.
- **A11.3 · two checks whose condition was the literal `true`.**
  `check("nothing external has to resolve for start() to reach the pre-flight", true)`, twice.
  `git log -S` shows the mac-ocr removal replaced a real assertion — `Runner.resolveBinary()
  != nil` — with the literal, leaving a falsifiable label over nothing. **Deleted**, because
  the property is now true by construction: the pre-flight's only work is
  `Flattener.hasDigitalText`, which runs no program. This file handles this correctly
  elsewhere and says so — "Deleted rather than weakened into something that passes without
  testing anything."

**Suite count: 862 → 880.** Two deletions, twenty additions — four of them the
folder-destination end-to-end check that replaced the un-failable one.

---

## Fixed earlier in this review

Colour/pale illustrations destroyed by 1-bit thresholding · fixed threshold 186
wrong for non-white paper (now Otsu per page) · encrypted PDFs rendering blank ·
rotated pages published blank on the non-rebuild path · page silently dropped when
its image failed to write · `nativeDPI` not recursing into Form XObjects · `%g`
emitting invalid PDF numbers · xref offsets wrapping past 2 GB · `closePDF`
skipped on throw · undecodable recogniser lines publishing empty pages · dead
Strategy and "Re-OCR" settings and a wrong command preview · crashes reported as
cancellations · output names colliding on case alone · the `0.15` compression
floor welding table rows together · `headroom` comparing box bottoms instead of
baselines · whitespace-only observations drawn and inflated · height ceiling
tuned from the corpus (line separation 80% → 93%).
