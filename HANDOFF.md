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
./run_tests.sh        # 799 checks, ~2-4 minutes (it runs real OCR)
```

Requirements: macOS 13+ and the Xcode command line tools. **Nothing else** —
recognition is Vision, called from a helper this repo builds
(`visionocr-recognise`, from `Helper/main.swift`), and that helper plus `jbig2`
and `qpdf` are bundled into the app and travel in `Contents/Resources`. Intel is
not supported: the bundled compressors are arm64-only and
`Runner.containsNativeSlice` makes them invisible rather than failing at `exec`.

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

## How to work the bug list

`BUGS.md` is the record: each entry has its location, the input that triggers it,
the consequence, and whether it was verified by running code or only reasoned
about.

**Nothing is open.** Every entry is `FIXED` or `WONTFIX` with its reasoning
recorded, including three decisions that went against the obvious fix: C5, R9
and R13. `TODO.md` holds one thing that needs a person (the VoiceOver
announcements have never been *heard*) and one optional idea.

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

Everything in `BUGS.md` is `FIXED`, `WONTFIX` or `NO DEFECT` — R40 closed on
2026-08-13, and R41–R48 with it, every one of them found by reviewing that work
rather than by a test failing. **1.11.0 is released**, gate and all.

`TODO.md` holds two pieces of work, in order: **preserve annotations through
re-OCR**, then the **Zotero library sweep**. Plus one thing that needs a person in
front of a running app.

The sweep's survey has run — 15,901 attachments, **1,164 re-OCR candidates holding
11.6 GB, about 10 GB reclaimable**, artifacts in
`~/Claude/vision-ocr-sweep-2026-08-13/` and deliberately outside this public repo.
**Nothing has been written to the library.** Annotations come first because
**108 of those candidates carry a reader's own marks** and re-OCR discards them
without a word — but that is 9%, so 1,053 files can be swept before annotation
preservation lands and 111 have to wait for it. Two operational facts before
anything is written: **Zotero sync is configured** and 22,676 attachments carry a
`storageHash`, so replacing files behind Zotero's back means a bulk re-upload and
a sync conflict can put the server's copy back over the new one; and Zotero is
usually running.

`FEATURES.md` is down to **one live idea** — a watched folder or command line.
Everything else is shipped, archived, or declined on measurement: deskew twice,
columns once, and both refusals are now *held* by checks rather than remembered
(see "the engine's competence" below). The suite is at **799 checks** and it
**needs nothing installed to run** — the mac-ocr dependency is gone.

**Two of this app's qualities are Vision's, not this codebase's**, and that is
worth knowing before reading either refusal. `compose` never sorts, so reading
order is inherited whole; and recognition is flat across ±3° with the reported
quads tilting to match, so there is nothing for a deskew step to win. Six checks
named `ENGINE ASSUMPTION` now hold both. **If one of those goes red, this app
probably did not break** — an assumption about the recogniser stopped holding, and
the answer is to re-open the `FEATURES.md` entry and re-measure with
`Tools/score-reading-order.swift` and `Tools/score-skew.swift`, not to go looking
for a defect in `SearchableWriter`.

**The released version is 1.11.0, tagged 2026-08-13.** The direct-Vision
migration and R40's fix both shipped in it. The gate that released it:
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
**The baseline is the 232-document `testdocs` run.** Produced by
`Tools/score-gate.swift`, which is the harness to use — see its header for why a
serial one is worthless:

```
                        2026-08-12, pre-R38    2026-08-12, at 1.10.0
documents                            232                      232
succeeded / failed                 232/0                    232/0
outputs                              232                      232
characters                    34,167,177               34,148,681
documents carrying colour             23                       23
1,198 MB in ->                  1,039 MB                   792 MB
                                 (1.15x)                  (0.66x)
minutes at concurrency 6              78                       75
```

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

**The environment this was verified on.** macOS 26.6, Swift 6.3.3, `mac-ocr`
1.1.1, `qpdf` 12.3.2, `jbig2enc` present (the binary is called `jbig2`, not
`jbig2enc` — `JBIG2.encoder` looks for the former). The corpus is 302 MB, 78
documents, 4,992 pages, 11 of which carry an outline.

**How to measure anything.** Every tool in `Tools/` compiles against the real
sources — see `Tools/README.md`. A full corpus score is:

```sh
mkdir -p /tmp/h && cp Tools/score-corpus.swift /tmp/h/main.swift
swiftc -O -o /tmp/score -target "$(uname -m)-apple-macos13.0" \
  Sources/Prefs.swift Sources/Runner.swift Sources/Flattener.swift \
  Sources/SearchableWriter.swift Sources/JBIG2.swift Sources/Model.swift \
  Sources/ContentView.swift Sources/SettingsView.swift /tmp/h/main.swift
find testdocs -name '*.pdf' -print0 | while IFS= read -r -d '' d; do
  /tmp/score "$d" "$(basename "$d" .pdf)"; done
```

That takes 20–40 minutes and is the strongest evidence available. It last ran
78/78 OK, median 100% line-start and line-end, median 0.00 offset, median 100%
word retention.

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

`testdocs/` holds **232 documents, every one of them a scan** (8 item types x 4
eras; widened from 84 in 2026-08 by dropping an arbitrary five-year recency
bound — 79% of the new material is older and none of the figures moved) used to measure the searchable pipeline across books, newspapers,
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

Current state, measured through the shipped pipeline over all 84:

**84/84 process successfully**, median 100% line-start and line-end
selectability, median 100% word retention, median 0.10 text-layer offset (max
0.10). Source line tightness — how much of this material is set closer than its
own line boxes — is 1.33% (74 of 5,564 adjacent pairs, in 23 documents); that is
a difficulty rating for the corpus, **not** a measure of our text layer, which is
what `score-line-separation` is for. See BUGS.md D3.

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
