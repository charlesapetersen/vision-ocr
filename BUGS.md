# Known defects

Findings from an adversarial review (three parallel code reviews plus a 78-document
corpus run over the Zotero library). Every entry was verified by running code
unless marked *reasoned* or *unverified*.

Status: `OPEN` · `FIXED` · `WONTFIX` (with a reason)

**Nothing is open.** Every entry is `FIXED` or `WONTFIX` with a reason. The four
raised by the 2026-08-08 corpus run — C17, D1, D2 and D3 — are all closed, and
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

---

## The interface

The GUI got no review attention during the period when this was going to become
a headless backend. When that reversed, three adversarial passes over it found
fourteen defects — **two of them regressions introduced by the pass before**.

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

### U5 · `askLoginShell` could freeze the app — FIXED
No timeout, on the main thread, from both `start()` and the Settings body. A
login shell that blocks — a slow network mount in a profile, an interactive
prompt, a wedged NFS home — froze the app with no way out. Bounded at three
seconds against a normal ~85 ms.

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

### U8 · Accessibility — MOSTLY FIXED
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
