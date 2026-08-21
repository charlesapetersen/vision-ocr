# Picking this up cold

Read this, then [ARCHITECTURE.md](ARCHITECTURE.md) for the call path, then
`BUGS.md`. Between them you should not need any prior session.

## What this is

**Vision OCR** — a small SwiftUI app that OCRs scanned PDFs through Apple's
Vision framework and writes its own searchable-PDF text layer. Drag PDFs onto the
window, pick an output folder, click Start. Two modes: extract text, or produce a
searchable PDF. Recognition happens in a helper process of the app's own
(`visionocr-recognise`), for the reason R40 records; `jbig2` and `qpdf` are the
only other programs it runs, and both ship inside the bundle.

## The one non-obvious design decision

**This app does its own recognition and writes its own searchable PDF.**

It used to shell out to [mac-ocr](https://github.com/privatenumber/mac-ocr) for
the recognition half. That dependency was deliberate, defended twice, and
archived twice — and then removed, because the reasons for keeping it stopped
being true. Both halves of the history are worth having.

**Why the text layer was always ours.** mac-ocr's own `searchable-pdf` writer has
two defects that made it unusable here: it adds its layer *on top of* any
existing one, so re-OCRing an already-OCR'd scan yields doubled text (measured:
2,683 → 5,401 characters); and it positions each word as a separate run without
real space characters, so extractors must infer word gaps and miss many. Word
accuracy against the same recognition was 64% (PDFKit) and 27% (poppler); this
app's layer gets 99.8% and 97%.

**Why the recognition became ours too.** The archived entry said the only
remaining argument was code tidiness. That was wrong, and two things settled it:

- **R39 was a defect that existed only because of the handover.** `flatten`
  rendered every page to a `CGImage`, wrote them into a PDF, and handed that PDF
  to a process that re-opened and re-rasterised it at a resolution we did not
  control. `recogniserDPICeiling`, `engineAutoDPI` and half of U25 were about
  negotiating with a rasteriser we were already doing the work of, and the
  200-megapixel refusal they negotiated around was **mac-ocr's, not Vision's** —
  Vision accepts a 216-megapixel image without complaint.
- **The geometry was being thrown away.** mac-ocr emits an axis-aligned
  `boundingBox`; Vision returns a quadrilateral, and per-character ranges on
  request. `SearchableWriter` places every run with a zero rotation term because
  a rotated one cannot be derived from a rectangle, and every one of invariant
  3's calibrated constants exists because the writer is fitting a string into a
  box rather than following measured characters.

**How the switch was justified**, since the objection was always that every
corpus figure had been measured through mac-ocr. Both engines were run over a
stratified 52 documents and 4,140 pages: **9,211,704 characters against
9,254,956, +0.47%.** Geometry was checked separately and mattered more — Vision
reports boxes bottom-left, this codebase is top-left, and a wrong flip gives a
layer that extracts perfectly and highlights the wrong line. **163,060 matched
observations, no orientation disagreement** that survives matching on text unique
to its page.

**Three of the request's options came from reading mac-ocr's source**, not from
testing, and each was a silent divergence from what the baseline was measured
with: EXIF orientation is read and passed to the handler;
`automaticallyDetectsLanguage` is set to `languages.isEmpty` (leaving it unset is
not leaving it alone); and `confidence` is the *observation's*, not the top
candidate's. MIT, Copyright (c) Hiroki Osame — the licence still travels in
`Contents/Resources/mac-ocr-LICENSE` for that reason, and `Recogniser.swift`
carries the credit.

**What is left of the subprocess machinery, and why.** `jbig2` and `qpdf` are
still children, so `Runner` still finds them on a PATH a Finder-launched app does
not have, refuses one built for the wrong architecture, and keeps the bounded
read that cannot hang the main thread. It went from 918 lines to 426. The bug
class did not vanish with the dependency — C6, R2, R3, R16, R17, R21, R22, U18
and R30 were all subprocess faults — but the long-running, streaming,
cancellable one is gone, and that is where the complexity was.

## Build, test, run

```sh
./build.sh            # -> build/VisionOCR.app
./build.sh --install  # also install to /Applications
./build.sh --run      # install and launch
./run_tests.sh        # 1,196 checks measured 2026-08-21; 8-45 min depending on load (it runs real OCR)
```

Requirements: macOS 13+ and the Xcode command line tools. **Nothing else** —
recognition is Vision, called from a helper this repo builds
(`visionocr-recognise`, from `Helper/main.swift`), and that helper plus `jbig2`
and `qpdf` are bundled into the app and travel in `Contents/Resources`. **Intel is
supported, with a caveat** — the bundled compressors are arm64-only and
`Runner.containsNativeSlice` makes them invisible rather than failing at `exec`, so an
Intel Mac falls through to Homebrew (`brew install jbig2enc qpdf`) exactly as before;
without them the compression step is skipped and files come out roughly three times
larger. This paragraph said "Intel is not supported", which `README.md`, `TECHNICAL.md`
and `build.sh`'s own comment all contradict.

`run_tests.sh` builds the helper too and points the suite at it with
`VISIONOCR_HELPER`. Without that the helper checks would pass over a helper that
does not compile, which is the same shape of blindness the `Sources/*.swift` glob
in that script exists to prevent.

**Never rebuild while someone is running `build/VisionOCR.app`.** `build.sh`
rewrites and re-signs that bundle in place, and macOS kills any process running
from it with `SIGKILL (Code Signature Invalid)` the moment it needs to page in
something that no longer matches the signature. This cost a whole debugging
session on 2026-08-10: a 255-file batch died three minutes in, the user
reasonably reported it as "half the PDFs failed", and the same files all passed
on retry. The only trace is in `~/Library/Logs/DiagnosticReports/` — the app
itself leaves no crash report, but its helpers do:

```
08:36:39  SIGKILL (Code Signature Invalid)  Invalid Page
    path: .../VisionOCR.app/Contents/Resources/jbig2
```

If someone wants to test while you work, install a separate copy with
`./build.sh --install` and leave `/Applications/VisionOCR.app` alone. And if a
batch fails in a way you cannot reproduce, check those reports before believing
the failure was real.

## Where the risk lives

Three files hold nearly all the subtlety. Everything else is plumbing.

- **`Sources/SearchableWriter.swift`** — places the invisible text. Three
  properties must hold *simultaneously*, and each of the three has been broken by
  a fix to another: word spacing must survive extraction; runs must not overlap
  vertically (or Preview merges lines and drag-selection skips one); runs must
  span the ink (or the highlight stops mid-line). Width is set by font *size*,
  height by a *vertical* squash in the text matrix — that separation is what makes
  all three possible at once. Don't "simplify" it without re-measuring all three.
- **`Sources/Flattener.swift`** — re-renders pages, and decides per page between
  1-bit, grey and (since 1.7.0) colour. Three signals route that decision: ink
  coverage, continuous tone, and saturation. The colour path is the newest and
  least worn: it is bounded by `maximumColourPageMegapixels`, whose value is
  **measured, not derived** (colour peaks at 19.5 bytes per pixel against grey's
  5.5 — re-measure if the encoding path changes), and it is the only path that
  produces a three-channel JPEG, which `JBIG2.assemble` must declare
  `/DeviceRGB`. A colour stream labelled `/DeviceGray` renders as static and no
  reader reports it. That decision has destroyed content twice: once because a
  fixed threshold of 186 is wrong for any paper that isn't bright white (now Otsu
  per page), once because ink coverage is *blind to pale colour* — pure yellow has
  luminance 226, so a tinted figure scored ~0% ink and was thresholded to blotches,
  losing 99% of the page.
- **`Sources/JBIG2.swift`** — hand-writes a PDF embedding JBIG2/JPEG streams.
  xref offsets and `/Length` values are computed by hand; be careful.

## Lessons that cost real time

- **Every adversarial review finds real defects in the code of the review before
  it — six rounds running as of 2026-08-10, without exception.** Round four found
  eight defects in round three's work; the review of those found three more; the
  review of *those* found three more again, one of which was a predicate extracted
  specifically so a claim could be checked, asserted against by six checks, and
  called by no production code — a duplicate of the thing under test, agreeing
  with itself by construction. **Budget a review round after every fix round, and
  expect it to find something.** The corollary is that "I fixed it and the tests
  pass" is not the end of the work; it is the middle.
- **Test the whole function, not its parts.** A regression broke *every* run for a
  while because the tests covered `Flattener`, `JBIG2` and `SearchableWriter`
  separately, and my end-to-end "verification" used a hand-written replica of the
  pipeline that omitted the very guard that was failing. `OCRModel.makeSearchablePDF`
  is deliberately internal so tests can call the real thing.
- **`kCGPDFContextMediaBox` needs CFData, not NSValue.** An NSValue is accepted and
  silently ignored, leaving every page with page 1's size. This bit both PDF
  writers, weeks apart in effect: in a book whose pages vary the text layer got the
  wrong shape, qpdf scaled it, and the text drifted down by up to a full line.
- **Single-page fixtures hide page-geometry bugs.** With one page, page 1 *is* the
  page, so any "inherits page 1's box" bug vanishes. Always include a page whose
  size differs from page 1's.
- **Verify a diagnosis before believing it.** "Vision can't read sideways text" was
  inferred from a blank rebuild that was actually an off-canvas rendering bug. A
  whole feature got built for it before a direct test showed Vision reads all four
  orientations fine. The feature was deleted.
- **Watch out for measurement artifacts.** Several "confirmed" findings this
  project were bugs in the measurement: `difflib`'s autojunk silently destroying a
  similarity score on repetitive text, a glob picking up unrelated renders,
  ImageMagick's `AE` metric exceeding the pixel count, a probe that counted every
  legitimately short line as a failure. When a number is surprising, check the
  instrument first — and when it is *unsurprising*, check the sample. The
  headline accuracy figures were quoted for months off a corpus that was 65%
  material this app is not for, and nothing about the numbers looked wrong (D1).

### Four ways I was wrong about the same question in one session (2026-08-13)

R49 and R50 are a single question — *is there a picture on this page?* — asked four
times. It is worth reading the sequence rather than only the answer, because three of
the four looked right at the point where it would have been tempting to ship.

1. **A relative paper floor.** Find the paper on a low-key scan by taking the bright
   class of its own Otsu split. Zero routing changes across 1,174 corpus pages, and
   the fallback could only engage on 4 of them. It was still wrong: **synthesised
   adversarial plates** — a flat ochre field with a dark subject on 10% of it — score
   2.46 against the low-key text page's 3.00, and the version I had already written
   was neutralising their colour. *The corpus showed a clean gap that did not exist,
   because the corpus did not contain the adversary.*
2. **The white point.** Cannot discriminate: the corpus holds a document at 161 that
   must **not** be corrected, below the 170–183 of the one that must.
3. **Rate-distortion — measure the harm of shrinking.** A 5 dB gap on the first four
   pages, and a complete overlap across 91 real corpus pages (text median 27 dB,
   photographs 25–35). The reason is worth keeping: **PSNR punishes losing grain**,
   and losing grain is exactly the loss nobody minds. The metric could not tell "lost
   paper texture" from "lost picture". A refinement that excluded the stencilled
   pixels changed the median by 0.4 dB — the glyphs are only ~8% of a page.
4. **Ink outside the recognised words.** Works, and is nearly free. **The reason the
   first three failed is that they were all statistics of the page, taken where only
   the histogram was available.** This one is structural and is taken after
   recognition. It is still a threshold on a *continuum*, not a gap, and it ships on
   a different argument: both directions of being wrong are mild.

**What to take from it.** Two things. Synthesise the adversarial case — the corpus is
not adversarial, and twice in one session it certified a separation that a
hand-built counter-example destroyed. And when a signal fails, ask *what it is
actually measuring* before reaching for a threshold: attempts 1 and 3 both failed for
a nameable reason, and the name is what pointed at attempt 4.

Also, for the record, two instrument failures inside this work: a nearest-neighbour
upsampler made the error non-monotonic in the downsample factor and I nearly read that
as a property of the pages; and a backgrounded shell loop silently processed **8 of 99
pages** because `pdfinfo` and `cut` are not on the PATH there — which `CLAUDE.md`
warns about in as many words.

## How to work the bug list

`BUGS.md` is the record: each entry has its location, the input that triggers it,
the consequence, and whether it was verified by running code or only reasoned
about.

**Four entries are open as of 2026-08-20: `C27`, `C28`, `C29` and `C30`. `C26` is `FIXED`** — `C29` being the owner's JSTOR finding, a born-digital cover page rasterised to 1-bit and re-OCR'd because `hasDigitalText` votes per DOCUMENT and, on any document of 5+ pages, never samples page 1 at all — a small line drawing erased on the picture path at the default Photo detail setting, opened hours after `1.13.0` shipped and on a document the release gate had already passed. It is not R56. Its constant moved 2026-08-19 and on 2026-08-20 the three pages it was opened on were rendered and the drawings are back: `verdict` `picture` where it read `all-text`, backgrounds 612 px rather than 153 px, and at 1:1 the cartoons whole and legible where they were smudges. ⛔ The close rests on those crops, not on a ratio — the section's first draft led with "5.7x/6.3x/5.7x the fine detail" and blank paper on the same page measures 3.6x–14.2x, so the ratio tracks the downsample and not the content; read the absolute figures and their measured blank-paper floor instead. Read C26's last two sections, and read the note below about what this gate can and cannot see. **`C28` was opened 2026-08-19 out of C26's own campaign** and is the invariant-1 half of it: the 1-bit stencil is the intersection of the page's ink with Vision's word boxes, so prose the recogniser missed is in neither the stencil nor the text layer and is stored at 1/8 on a page read as all text — 7 of the 13 pages C26 rendered lose whole lines of prose or table data that way. **FOUR C28 sub-steps ran on 2026-08-20 and they cover the whole population: 8 + 24 + 20 + 21 = 73 still-shrunk pages rendered, of which 4 + 2 + 8 + 2 = 16 lose content — so all 73 are read, 16 of the 73 lose content (11 type, 5 hand-made), and the campaign stands at 86 pages rendered, 24 losing content, 19 of them type and 6 a hand-made mark, one page in both buckets (2026-08-21).** (⚠️ This sentence read "21 pages rendered and 12 losing content" while 45 had been read; two sub-steps did not update it. The total is addition over the sub-steps, not a re-measurement.) **And the headline is that the signal the bar reads does not order the loss, in three escalating forms.** Sub-step 1 (`78de7a2`): sorted by `inkOutsideText` the eight pages nearest the bar interleave, so no value of the bar separates them, while `extent` separates them perfectly in the WRONG direction. Sub-step 2 (`6818a0e`): the loss reaches `inkOut` **0.0137** (a paper's estimating equation) and **0.0008** (a word), a third of the way to zero, and the pixel *count* of ink outside the stencil discriminates nothing (loser 15,431 px, non-loser 15,727 px). Sub-step 3: over the twenty highest-`inkOut` pages left, the eight losers span [0.0051, 0.0165], with **four non-losers above that span, six below and two inside**, so **the four pages of the 41 carrying the MOST ink outside the recognised words are the first four a one-sided bar protects and not one of them loses anything** — the steepest-ratio of them, `1976 - Regis McKenna Papers` p4, is **+350,632 B at 7.89x** for platen strips and a staple shadow. ⚠️ Two things that sub-step's own review made it retract: the "six below" half is a **selection effect** (all six came from two documents completed for convenience; the twelve pages the stated rule chose read `n n n n L L n n L L L L`, four non-losers above every loser and none below), and its claim to have weakened this entry's "the bar overpays" half compared **37.6% over 14 pages against two whole-sample figures** — like for like it is **54.2%** against 57.4% and 56.6%, i.e. flat. It is also not the *dearest* page that buys nothing: `Doermann_1967` p21 costs 10,833 B more and does lose content. Sub-step 4 (the last 21, the lowest-`inkOut` of the 73): **2 of 21 lose content** — the words `their education,` and `but` on `Williams_1958_DEMOCRACY OR MERITOCRACY` p1 at `inkOut` **0.0023**, and a **pencilled annotation on `_1939_Former students` p2 at an `inkOut` that prints 0.0000**, a page no legal `INKBAR` and no shippable bar can reach, which is the entry's sharpest evidence that it is independent of the bar (⚠️ stated exactly: `barDelta same` at 1e-5 bounds it to [0, 1e-5) rather than proving it zero, and neither reading leaves a usable bar — the guard is a strict `<`, so at exactly 0 only a bar of 0 protects it and that un-shrinks every page). ⚠️ A first draft of this sentence said "44 of the 73 sit strictly below that and lose nothing"; the review of the diff refuted it from the entry's own sub-step 2 table, where `Jones et al_2010` p2 loses a word at 0.0008. It corrects three of this entry's figures: **25 of the 73**, not 27, cannot be priced through the override seam (two print `0.0000` and flip anyway); the page with the **highest** out-of-stencil fraction of the 21 loses nothing at 11.65x its own `inkOut` (a pale typescript whose every glyph leaves the map a rim); and the same page-wide Otsu **misses** pale pencil on a shadowed sheet, its one measured false negative, which is how p2 was nearly filed as "nothing". ⚠️ And it records two instrument traps: `Disk:0` is radius 4 and not the identity, and a connected-component rect off the interior-cropped map is in a different coordinate frame from one off the whole map — a slip that produced a confident reading 200 px from any flagged ink until a direct pixel count in the rect caught it. C26's own constant moved (0.08 -> 0.045, shipped 2026-08-19) and still leaves 73 sampled pages shrunk, which is why the stencil is its own entry rather than a footnote to the bar. **Both C26 and C27 were re-measured on 2026-08-18 and C26's diagnosis changed**: the entry had quoted `score-threshold-loss`'s `lost` column as the number under `paleDrawingThreshold`'s 5% bar, and those are two different functions — the quantity the bar reads is `paleDrawing(pageMarks(…)).extent`, which is **0.00000** on the two pages that lose their drawing, so no value of the constant protects them. ⚠️ This then read "and the fix has to be in what `pageMarks`/`paleDrawing` *find*", and that is not where the fix came from: C26 closed at `pageIsAllText()`'s **first** term instead. The second term still ships blind, unmeasured, and is carried as the queue's `paledraw-term` triage item. The corpus sweep both entries were blocked on ran the same day (`THRESHOLD-LOSS-2026-08-18.tsv`, 441 pages, 233 documents): it sizes C26 — 61 picture-route pages, 2 protected, 22 under the bar, 37 at zero — and, measured, does **not** size C27, because a mean saturation cannot see concentrated colour. **`C24` was open before it and is `FIXED`**, both halves:
a page that draws no XObject at all no longer takes another page's plate resolution, and the 45
pages that draw a *different* image than the shared dictionary holds now take their own, after a
corpus gate that moved exactly those 45 of 16,987 for **+8 matched words of 3,025** and 25-81%
fewer bytes on the three documents. Read the entry's `C24's wiring` section — the gate's own
instrument had to be repaired first, and one row (`Sherman_1986` p1) is named as an unsettled
surprise. Everything else is `FIXED` or `WONTFIX`
with its reasoning recorded, including three decisions that went against the obvious fix:
C5, R9 and R13. `TODO.md` holds the decided-but-undone work, and `REVIEW-2026-08-14.md`
holds a whole-codebase review sweep with findings not yet fixed and areas not yet covered.

*(This paragraph said "Four entries are open, and two of them destroy content on the default
route", naming R56, R57, R54 and R55, for a day after all four closed — R54/R56/R57 `FIXED`,
R55 `WONTFIX` on the owner's arithmetic 2026-08-17. It is the same failure `CLAUDE.md`
confesses to about its own status line, and for the same reason: a sentence a new reader
trusts most, in a file nothing checked. `ops/autonomous/check-staleness.sh` now checks it —
it is what caught this — so correct it here in the same commit as any status change.)*

For each: reproduce it with a harness from `Tools/` first, fix, re-measure, then
update the entry in `BUGS.md` with the fix and its evidence. Run `./run_tests.sh`
before committing, and add a test that fails without the fix.

Two things the second pass learned the hard way, both worth carrying forward:

- **An entry can be wrong.** C5 did not reproduce as written, R7 was recorded as
  fixed with a fix that was never in the code, R9 described the opposite of what
  the code does, R3's title said "no caller" when it had two, and R21 named the
  wrong mechanism entirely — it blamed `terminate()` for not reaching the process
  group when `terminate()` does reach it, and the actual leak was in the SIGKILL
  escalation. Re-measure before you fix, and correct the entry when it is wrong.
  R21 is the one to remember: its recorded fix was a `posix_spawn` rewrite of the
  most defect-prone code in the project, and thirty lines of measurement replaced
  it with two.
- **A percentage can fall while the thing improves.** The DPI floor (C9) took
  Hoffman's line-separation score from 100% to 94% — because the score's
  denominator went from 3 recognised lines to 139. Check the absolute counts
  before believing a regression.
- **Measure the premise before building on it, even when the register is sure.**
  R40's fix rests entirely on separate *processes* parallelising where threads do
  not, and the evidence for that was mac-ocr's history rather than a number. It
  cost one command to check — 12 page images, 14.00s in one process against 6.28s
  across six, 2.23x — and the whole design would have been void if the answer had
  been 1.0x. The same run also settled the shape of the thing: a process pays
  ~0.23s before it can recognise anything, which is 19% of a page and nothing at
  all of a document, and that is the entire reason the helper is per-file rather
  than per-page.
- **An instrument that reports availability instead of use is not an
  instrument.** The gate's new "recognition:" line first printed that a helper
  *existed*, which on a one-document run is the wrong answer — `helperIsWorthIt`
  declines below two files, so it would have said "helper processes" over a run
  that used none. It reports the decision now. The 187-minute configuration and
  the 75-minute one are indistinguishable from a gate's output otherwise, which
  is precisely how a 2.5x regression reached a release candidate.

## Where things stand

**1.12.0 is released**, tagged and on GitHub with its DMG, gate and all — and its
release notes carry an appended known-issues section, because **two of the four open
defects are in the app on the default route**. R56: a pale drawing is *erased* rather
than softened. R57: a continuous-tone plate over about a fifth of a page can come out a
solid black blob. Both are in 1.11.0 and earlier too; Grayscale mode is unaffected. R54
and R55 are in the tooling (`sweep-zotero.py`, `classify-source`) rather than the app.

**1.12.0 in one line: a 568-page scan that went in at 31 MB and out at 437 MB now
comes out at 35 MB, with a byte-identical text layer.** R49 and R50 are the two
halves of that and both are worth reading before touching `Flattener`. R51–R53 came
out of reviewing their diff — the tenth consecutive round in which reviewing the
previous round's code found real defects in it, and one of them (R52) was storing a
page at an eighth of the resolution its user had explicitly asked to keep.

**The one thing to understand about the size work**, because it will shape the next
piece: `isPicture` runs *before* recognition and therefore has only the page's own
luminance histogram, and R49 established by measurement that a histogram **cannot**
separate text from a tinted plate — a flat ochre plate with a dark subject on it
scores identically to a page of type on every tonal signal tried. R50 sidestepped it
rather than solving it, by asking a *structural* question at a later point in the
pipeline where Vision's word boxes exist: ink that is not inside any recognised word
is not text. That signal is 0.0000 on text pages and 0.971–0.993 on plates, and it
cost nothing to compute. ⛔ **That premise is FALSE as stated and `C28` was opened on it
(2026-08-19): measured over 13 corpus pages, the ink outside the recognised words was
running prose or table data on 7 of them.** **`C28` sub-step 1, 2026-08-20: eight further pages
were rendered and 3 of the 8 lost prose or table data, a 4th a handwritten signature** — ⚠️ **and that
4th page, `Atkinson_1939` p3, was measured 2026-08-21 to lose two lines of typescript as well, so it is
4 of the 8 losing type and the signature is the extra rather than the whole of it.**
⚠️ **No running total is kept here, deliberately.** The first version of this sentence carried one
("21 pages rendered, 10 losing prose or table data") and it was stale within two hours, because C28
kept adding sub-steps underneath it — `CLAUDE.md` records the same failure on its own copy of that
figure. The current total lives in `CLAUDE.md`'s C28 paragraph and in `BUGS.md` C28, which move in
the same commit as the work; a design-rationale file is the wrong place for a number that is still
moving, and dated sub-step findings are what belongs here. The signal is still the best one available
there and R50 is still `FIXED` — what is wrong is the justification, and the consequence
is that marks the recogniser missed are stored at 1/8 on a page this signal calls all
text. ✅ **That consequence is REPORTED as of 2026-08-20 (`55b650b`)** — `MRCLayers.shrunkAsAllText`
carries the decision and `OCRModel.shrunkTextPageSummary` names every page the shrink was applied to in
the run log, which the run report copies. It reports what was DONE to the page rather than a verdict
about its content, because of the 73 corpus pages that take the shrink 16 lose content and 57 do not,
and no scalar term measured here separates them. The shrink itself is unchanged and `C28` stays open on
its remaining questions — **which as of 2026-08-21 are 3 and 4 only, because question 2 closed**: the
same loss does not reproduce at 1/2 (16 pages, 2026-08-20) and **does at 1/3** (the same 16, 2026-08-21)
— `Xin Qu et al_2018` p20's correlation matrix is legible in the 460 px background Balanced gives it and
unreadable in the 307 px one `PhotoDetail.smallest` gives it, two more pages degrade and five read
clean. ⛔ **And the term that orders that population is the page's own rebuild resolution, not
`inkOut`**: the loser has the smallest source render of the sixteen and ranks SIXTH of sixteen on a
1/2-against-1/3 difference map, so that scalar is refused too — ⛔ **and the review of that diff
retracted the resolution framing as well, the same day**: sorted by source width the three clean pages
sit BETWEEN the two degraded ones, so width interleaves the verdicts exactly as `inkOut` does. What
survives is existence plus mechanism (the loser is the narrowest; 307 px of background under 9-pt table
type), the quantity read was source pixel WIDTH and not `rebuildDPI`, and **8 of the 16 have a 1:1
reading, not 16** — a fourth refused scalar in this area.
Smallest costs 0.6465x the bytes of Balanced over the sixteen while **the page that loses content saves
the LEAST of them**, which is C28's "the same bar overpays" in a second mechanism.
✅ **And question 3 has its first measurement, 2026-08-21: a term that is NOT a scalar separates.**
`Tools/score-shape-term.swift` counts the **text lines** in the ink outside the recognised words, at
the page's own type scale — component height and stroke width against the medians of *the stencil's
own* components, and four of them tiling a baseline make a line. Over 13 labelled pages the count is
≥ 1 on 6 of 6 pages that lose typeset content and 0 on 6 of 6 that lose nothing, and the crops say the
largest group *is* the lost text: sub-step 1's two prose lines on `Broadhead - 1994` p3 and on
`Jones et al_2010` p5, a named display line on `Scott_TK` p3, eleven of the thirteen matrix values on
`Xin Qu` p20. So the answer to "is there a term at all" is yes, and it is the shape one R56's lesson
predicted — the fifth scalar (`txtShare`) is refused in the same table, because a drawn bracket reads
below a non-loser on its own scan. ⛔ **Two things that must travel with it.** The rule is **blind to a
hand-made mark by construction** (measured 1 of 1; the campaign has 6), so anything built on it
protects prose and table data and must say so rather than implying "content". And the sample contains
**no plate, halftone or line drawing at all**, so the second half of question 3's own sentence —
*without admitting pictures* — is not measured; that is 3b. The same run also settled
`score-text-route`'s open instrument question (the shell map's 0.56x–16.0x spread against
`inkOutsideText`): with `region` in hand rather than a dilated stencil the map **is** the guard's set,
the stencil substitution inflates it 1.00x–3.17x, a 7x7 square stand-in for `Disk:3` correction lands
0.721x–1.007x, and ImageMagick's OTSU equals `Flattener.otsuThreshold` on 13 of 13 pages — so that
spread is bounded wherever there is ink to divide by. And it corrected the register from the crops:
`Atkinson_1939` p3 loses **typescript** that sub-step 1's inventory did not list, which puts one page
in both of the campaign's buckets.
`PHOTODETAIL=` on `Tools/score-text-route.swift` is the seam that made question 2b measurable: before it
the tool could only measure the default, and its self-test now pins the fact that the default *is*
Balanced — something every row of `INKBAR-2026-08-19.tsv` silently depends on and nothing in the tree
stated. ⚠️ A first version of this paragraph — written in a session whose work was
stranded and never landed — cited `OCRModel.textOnlyShrinkSummary`, which does not exist: that session
and the one that finally landed the item implemented it under different names, so the paragraph was
re-checked against the tree rather than copied. **The remaining prize is moving `isPicture` itself after
recognition**, which is why it is now first in `TODO.md`.

**The order of work, agreed with the owner 2026-08-13:**

1. ~~Move `isPicture` after recognition~~ — **measured and refused 2026-08-13.** The
   prize is real (8.2 KB a page, ~4.3 MB and 12% on the R49 book) but it would route
   *more* pages to 1-bit using `inkOutsideText`, whose recorded miss **is** R56. Blocked
   on the shape signal in `FEATURES.md`; `TODO.md` item 1 has the arithmetic.
2. ~~Preserve annotations through re-OCR~~ — **built and verified 2026-08-14.**
   `Sources/Annotations.swift`, behind *Keep highlights and notes* (off by default).
   121 of 121 marks carried on the specification's own document including all 20 stamps,
   0 moved. **The sweep's annotation block is lifted.** `BUGS.md` R58 — and note it is
   deliberately **not in a release**: two adversarial rounds each found marks landing in
   the wrong coordinate space, and a third has not been run.
3. **Clickable footnote and endnote links** — not started. Same `/Link` object-graph
   plumbing as the annotation transplant, so it should reuse `Annotations.swift`.
4. **The Zotero library sweep** — last, and fix R54 before step 2 reads its numbers.

**Dropped or closed by decision, not by neglect:** a watched folder or command line
is dropped; the VoiceOver question is closed (every control is named and the one
omission was fixed — what was never done is *hearing* it in the VM, and that is
accepted). Do not re-open either as though it were an oversight.

The sweep's survey has run — 15,901 attachments, **1,164 re-OCR candidates holding
11.6 GB, about 10 GB reclaimable**, artifacts in
`~/Claude/vision-ocr-sweep-2026-08-13/` and deliberately outside this public repo.
**Nothing has been written to the library.** **108 of those candidates carry a reader's
own marks** and re-OCR used to discard them without a word — which is why annotations
came first, and they have now landed, so that block is lifted for all of them. (The
108-vs-111 discrepancy in the older figures is about three basename-vs-path collisions;
`TODO.md` carries the explanation.) Two operational facts before
anything is written: **Zotero sync is configured** and 22,676 attachments carry a
`storageHash`, so replacing files behind Zotero's back means a bulk re-upload and
a sync conflict can put the server's copy back over the new one; and Zotero is
usually running.

`FEATURES.md` holds **two live ideas**: the spatial signal for the picture detector
(half-answered by R50, and the open half is priority 1 above) and clickable footnote
links. Everything else is shipped, archived, or declined on measurement: deskew twice,
columns once, per-page background factor twice, JPEG 2000 twice, and the refusals are
*held* by checks rather than remembered (see "the engine's competence" below). The
suite is at **1,196 checks** (measured 2026-08-21) and it **needs nothing installed
to run** — the mac-ocr dependency is gone.

**Two of this app's qualities are Vision's, not this codebase's**, and that is
worth knowing before reading either refusal. `compose` never sorts, so reading
order is inherited whole; and recognition is flat across ±3° with the reported
quads tilting to match, so there is nothing for a deskew step to win. Six checks
named `ENGINE ASSUMPTION` now hold both. **If one of those goes red, this app
probably did not break** — an assumption about the recogniser stopped holding, and
the answer is to re-open the `FEATURES.md` entry and re-measure with
`Tools/score-reading-order.swift` and `Tools/score-skew.swift`, not to go looking
for a defect in `SearchableWriter`.

**The released version is 1.12.0**, tagged 2026-08-13 — see "Where things stand" above.
The paragraph below is kept for **1.11.0's** gate figures, which are the ones the
direct-Vision migration and R40's fix were measured against. The gate that released it:
**232 of 232, 0 failed, 34,204,948 characters, 792 MB, 48 minutes** — against a
75-minute baseline and the 187 that held the release back, and measured on a busy
machine, so 48 is a ceiling on the time rather than a best case.

**One thing in that run is unexplained and is recorded, not waved at**: the
character count is 23 lower than the previous gate's, out of 34.2 million. Every
direct comparison of the two recognition routes is exact to the last digit, and
two helper processes agree byte for byte. `BUGS.md` R46 has what was checked; the
gate now writes a per-document breakdown so the next comparison localises a
difference of this size instead of leaving a total.

**How R40 was fixed, in one paragraph.** Recognition runs in a helper process
per file again — `Helper/main.swift`, built as `visionocr-recognise` and bundled
beside `jbig2` and `qpdf`. It is **not** the mac-ocr dependency returning: it is
handed bitmaps this app rendered rather than a PDF, so R39 cannot come back, and
it **compiles the app's own `Recogniser.recognise`** rather than reimplementing
it, which is the only reason the corpus baseline still describes the pipeline.
It is never authoritative about failure — absent, broken, silent, or returning
fewer pages than it was given, every one of those falls back to recognising
in-process and says so in the log, so the worst a helper bug can cost is time.
`BUGS.md` R40 has the measurements behind every choice, including why it is one
helper per *document* (Vision's first request in a process costs ~0.20s; per page
that is 19%, per document it is nothing) and why there is no pool object (at most
`Prefs.concurrency` files run at once and each holds at most one helper, so the
process count is the setting, by construction).

**1.10.0 closed the queue agreed on 2026-08-12.** Four items shipped — R38, the
written run report, the language picker, retry-the-failures — and three were
settled by measurement rather than by code: the picture-page DPI cap
(**declined**: it would govern 129 of 449 picture pages, and Photo detail already
governs the other 320), annotations (**not shipped**, but the recorded blocker
was disproved and the real one found), and the full-corpus gate (**run**, twice).
Only item 8, R35's second attempt, is left, and it was always its own cycle.

**The 2026-08-12 queue is now closed in full, including item 8.** R35's second
attempt was measured and refused: still a continuum over 320 layered pages, and
the page a "safe" threshold would have shrunk hardest is a photomicrograph of an
integrated circuit that reads as paper because it is bimodal. The prize was
0.55% of the corpus. **Three features were declined on measurement in this
session and none on argument** — the picture-page DPI cap, deskew, and R35 —
which is the pattern worth carrying: each had a sound case, and each was refused
by a number or by looking at a page.

**1.10.1 closed R39, and the way it closed is the point.** The entry proposed
sending an explicit recognition DPI instead of letting mac-ocr choose. Measured
over 52 documents and 4,140 pages, that is *worse at every value tried* — and
worst in the high-resolution band where it was predicted to win. The real defect
was underneath: the DPI ceiling could not bind on Automatic because it was being
compared against a constant that the code's own comment wrongly described as the
engine's default. The lesson generalises past this entry: of the four things
attempted after 1.10.0, three were refused by measurement and the one that
shipped was not the fix that had been written down.

**The lesson the 2026-08-12 session kept relearning, in its sharpest form.**
Twice in the direct-Vision work I reported a conclusion from a measurement that
could not have shown the effect: "no throughput regression", from a
single-document comparison with no concurrency in it; and "parallelising pages
will fix it", when pages within a document parallelise at 1.0x. Both were caught
by measuring the thing the pipeline actually does. Add to that an EXIF fixture I
declared impossible to build because `sips` and `mdls` do not report the tag —
the reader the app uses saw it perfectly — and an accessibility "defect" that was
a label four lines below the ten-line window I read. **The instrument is wrong
more often than the code, and it is most convincing when it agrees with you.**

**Earlier that same session, six separate times**, a measurement was wrong and the
wrong conclusion was nearly recorded as fact. They are all the same shape and worth reading as one lesson:

- A codec looked 1.5–2x better because it was measured on whole pages rather
  than on the background layers it would actually encode (R36); and earlier,
  because the source page's own layer was already in that codec (R34).
- A per-page detector looked cleanly separable because it was fed boxes from a
  standalone tool rather than the ones the pipeline produces (R35).
- Cross-page hyphen joining looked unnecessary because the instrumentation
  printed successes rather than candidates, so twelve rejected opportunities
  read as none.
- `edgeOfPage` at 0.18 admitted nothing because the boundary landed exactly on
  the measured depth of a last line — a guessed constant, not a measured one.
- Two mutants survived while appearing to test something: one fixture's columns
  overlapped *negatively*, so any non-negative floor refused them; one test
  bypassed the wiring that the constant actually controlled.
- An accessibility read gave three different answers from three attributes,
  the last while the probe was failing to advance focus.

The pattern: **the instrument agreed with the hypothesis, so it was not
questioned.** CONTRIBUTING 3 already says to suspect the instrument; what this
session adds is that the moment to suspect it hardest is when it tells you what
you expected.

**1.7.0** is tagged and released with a DMG.

**The last release was verified against the whole library, not just the suite.**
**The baseline is the 232-document `testdocs` run** — the corpus is now 233, and the
column figures below are deliberately *not* restated for it: a document added on
2026-08-13 cannot change what four earlier runs measured. Produced by
`Tools/score-gate.swift`, which is the harness to use — see its header for why a
serial one is worthless:

```
                      pre-R38    at 1.10.0    at 1.11.0    at 1.12.0
documents                 232          232          232          232
succeeded / failed      232/0        232/0        232/0        232/0
outputs                   232          232          232          232
characters         34,167,177   34,148,681   34,204,948   34,204,951
carrying colour            23           23           23           23
1,198 MB in ->        1,039 MB       792 MB       739 MB       721 MB
                       (1.15x)      (0.66x)      (0.62x)      (0.60x)
minutes at conc. 6         78           75           48           51
```

**Read 1.12.0's column per document, not just in total.** The total moved 792 → 721
MB, but the useful fact is the distribution: **209 of the 232 documents are
byte-for-byte identical, not one is larger**, and every photograph-heavy document —
`Ibson_2006_Picturing men` at 19,144,682 both ways, `Noble_1977`, `Schwaller`,
`Boltanski`, `Ehrenreich`, `Findlay`, `Marth` — is unchanged to the byte. The 23 that
shrank are the low-contrast typescripts the picture detector misroutes:
`Ford_1941_Speech` to 0.200 of its size, `Riesman_1954` from 7.32 MB to 1.98. A
corpus total would have hidden all of that, which is why the gate writes
`per-document.tsv`.

*(The 51 minutes is not comparable to 1.11.0's 48: that run shared the machine with
a second gate and several probes. Colour layering does genuinely cost about 2.5x grey
layering per layered page, which matters for an hours-long sweep and not for one
file.)*

**The output is now smaller than the input, where it used to be larger.** That
is R38: 247 MB, a quarter of the corpus, was greyscale backgrounds under JBIG2
stencils that carried nothing the stencil did not already have.

**The 18,496 characters (0.054%) are not a loss of text, and the direction is
not uniform.** Pages that moved from a grey JPEG to 1-bit are recognised from a
different rendering, so per-document counts move both ways: measured on the same
binary before and after, a 1926 broadsheet gained 1,012 characters (+36.5%) and
a 1950 comic page lost 51 (−1.9%), while documents whose routing did not change
— Findlay, Ehrenreich — are identical to the character.

Run it before any release that touches `Flattener`, `SearchableWriter` or
`JBIG2`. It is the only evidence that covers what the suite cannot, and both
1.8.0 and 1.9.0 shipped without it — the run that finally happened found R38, a
document inflating 9.45x.

**One thing the gate log shows that is not yet explained.** Several hundred
`Error (NNNN): Unexpected EOF in JBIG2 stream` lines appear during a run, ~2 per
affected page. It is **not** introduced by R38 — the same message appears in a
sampled routing sweep taken before the change was applied — and it does not
damage the output: `Boltanski_2006`, the most affected document, renders 203 of
203 pages with ink on them, and rendering both its source and its output
directly produces no such message. It is emitted somewhere in the pipeline that
reads a JBIG2-bearing *input*, and it has not been pinned down further. Worth
knowing before someone spends a session on it believing it is new.

*Do not diff those figures against the 1.7.0 ones below.* They are different
corpora: 232 `testdocs` documents against 255 from the Zotero library, and that
255-document set is not reconstructable (the library holds 16,079 PDFs). The
1.7.0 line is kept as history, not as a comparison.

**1.7.0's run, for the record.** 255 documents through `OCRModel.start()` at the
app's own default concurrency: 255 succeeded, none failed, 12.6 million
characters recovered, 23 minutes, peak RSS 3.35 GB. Fifteen came back with
colour. Two pages across the whole set render blank, and both are blank in the
original.

Things you would otherwise have to rediscover:

**The environment this was verified on.** macOS 26.6, Swift 6.3.3, `qpdf` 12.3.2,
`jbig2enc` present (the binary is called `jbig2`, not `jbig2enc` — `JBIG2.encoder` looks
for the former). No `mac-ocr`: it was removed in 1.11.0 and recognition is this app's own
Vision helper. The corpus is **1.2 GB, 233 documents** — 232 from the stratified draw plus
one added by hand — of which 11 carry an outline.

**How to measure anything.** Every tool in `Tools/` compiles against the real
sources — see `Tools/README.md`. A full corpus score is:

```sh
mkdir -p /tmp/h && cp Tools/score-corpus.swift /tmp/h/main.swift
swiftc -O -o /tmp/score -target "$(uname -m)-apple-macos13.0" \
  $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
find testdocs -name '*.pdf' -print0 | while IFS= read -r -d '' d; do
  /tmp/score "$d" "$(basename "$d" .pdf)"; done
```

`$(ls Sources/*.swift | grep -v App.swift)` rather than a hand-kept list, deliberately:
the enumerated version in this file omitted four sources and had not compiled for four
releases. `App.swift` is the only exclusion, because its `@main` collides with a tool's
top-level code.

That takes 20–40 minutes and is the strongest evidence available. It last ran
**232/232 OK**, median 100% line-start and line-end, median **0.10** offset, median 100%
word retention — `testdocs/manifest.tsv` holds the per-document rows and is the authority.
*(This said 78/78 and 0.00 offset, from the pre-2026-08-09 corpus.)*

**For a before/after on anything geometric**, make the comparison binary first:
`git worktree add -q --detach /tmp/before <commit>`. You will want it, and
reconstructing "before" afterwards is disproportionately annoying.

**Suspect the instrument first — it is right more often than not.** In the
2026-08-10 session alone: a corpus probe read every rebuilt page as blank (the
y-axis was inverted — a bitmap's row 0 is the visual *top*, while CG's drawing
origin is bottom-left, and the *originals* sampled white at the same coordinates,
which is what gave it away); a `strings` grep said a fix was missing from a
shipped binary (Swift does not emit `static func` names as strings — use `nm`,
and the same grep missed a literal because the em dash did not survive the
shell); a shell probe silently tested nothing because **zsh arrays are
1-indexed**, so `${files[0]}` is empty; and a page-similarity check read 20.6 on
*correct* code purely from resampling a high-frequency fixture. Before believing
a measurement, run it against a known-good input and check it says so.

**Four probes of mine crashed or lied during one session**, all the same few
causes. If a probe misbehaves, check these before suspecting the code:
`String(format:)` with `%@` or `%s` and a Swift `String` crashes; stdout is
block-buffered so a crash swallows your prints (`setvbuf(stdout, nil, _IOLBF, 0)`,
or write to stderr); `PDFDocument(url:)?.outlineRoot` without holding the document
reads back empty because `PDFOutline` does not own its document; and `qpdf` sorts
dictionary keys, so a regex anchored at `/Type` misses everything before it.

**That one genuinely unverified thing has been settled, and the answer was the
bad one.** The window could *not* be recovered after closing it mid-run:
`applicationShouldHandleReopen` looked for a window that `canBecomeMain`, and a
closed SwiftUI window reports false for exactly that until something orders it
front — so a Dock click restored nothing and a running batch was unreachable.
Fixed (BUGS.md U13), reproducible with `Tools/probe-window-reopen.swift`, and
there is a ⌘0 command now as well. The general lesson is the one this project
keeps relearning: an item filed as "an open question needing thirty seconds"
was a live content-reachability bug, and it sat there because nobody spent the
thirty seconds.

What is left unverified is only what needs a person at a running app — the tab
order, how the announcements sound, and the Settings sheet on a short display.
`TODO.md` lists all of it with what to do about each.

## Corpus

`testdocs/` holds **233 documents, 230 of them scans** — the gate that drew it was asking
its own question rather than the app's, and `BUGS.md` T17 is that; two of the 233 are
documents `Flattener.hasDigitalText` calls born-digital, 9 pages of 16,987, named in
[CORPUS-2026-08-15.md](CORPUS-2026-08-15.md). This sentence said "every one of them a
scan" for a week. 232 come from the
stratified draw (8 item types x 4 eras; widened from 84 in 2026-08 by dropping an
arbitrary five-year recency bound — 79% of the new material is older and none of the
figures moved) **plus one added by hand on 2026-08-13** at the owner's request: a
1954 pamphlet printed in red ink, which is the corpus's only deliberately chosen
instance of colour on paper that is not a photograph, and which routes to the
picture path on three of its four sampled pages. **Every gate figure in this file is
a 232-document figure** and stays labelled as one; `testdocs/README.md` has that
document's own scores and the `classify-source` anomaly (R55) that came with it. Used to measure the searchable pipeline across books, newspapers,
magazines, journals, theses and reports, old and new. **It is not committed** —
it is third-party copyrighted material. `testdocs/manifest.tsv` records what was
sampled *and each document's scores*; `Tools/sample-zotero.py` rebuilds an
equivalent corpus from a Zotero library. See `Tools/README.md` for what each
metric means.

**Every candidate is classified before it is sampled, and only scans are kept.**
That gate is new, and it exists because the corpus this replaced was
**27 scans out of 78** — 40 born-digital, 10 photographed by hand — while the
project quoted its accuracy figures off it (BUGS.md D1). Item type says what a
document *is* and nothing about how the PDF was made.

Current state, measured through the shipped pipeline over the **232-document** draw
*(the figures below were 84-document ones for several releases — the corpus was widened
on 2026-08-09 and this paragraph was not)*:

**232/232 process successfully**, median 100% line-start and line-end selectability
(worst 91% and 91%), median 100% word retention (worst 97%), median 0.10 text-layer
offset (max 0.10). Source line tightness — how much of this material is set closer than
its own line boxes — is **2.00% (295 of 14,782 adjacent pairs)**; that is a difficulty
rating for the corpus, **not** a measure of our text layer, which is what
`score-line-separation` is for. It is higher than the old figure because the wider draw
reaches further back into tightly-set printing. See BUGS.md D3, and
`testdocs/README.md`, which is the authority.

**The tail is worse than the old corpus implied, and that is the point.**
Born-digital documents score perfectly — OCR of a clean rendering of digital
text is easy — so they flattered every percentile. On real scans the floor is
what to watch: line-end 91% on the worst document, word retention 97%. Both were
worse (71% and 94%) until C18, which found that runs on dense newsprint were
being drawn 15-30% narrower than their boxes. If you are chasing a regression,
compare against the per-document rows in `manifest.tsv`, not against the
medians.

## Note on history

The repository starts at the point everything above was already true; the work
predates version control. One consequence is recorded honestly: `makeSearchablePDF`,
`uniqueOutputs`, `publish` and the `finishUp` property were accidentally deleted by
an over-broad edit and **reconstructed from memory**, verified only by the test
suite passing (330/330) and by real-document runs. They deserve a closer read than
code that was merely edited.
