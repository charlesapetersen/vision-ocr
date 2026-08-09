# How it fits together

The call path, where the risk sits, and what the tests do and don't cover.
Read [HANDOFF.md](HANDOFF.md) first for *why* the design is what it is, and
[CLAUDE.md](CLAUDE.md) for the invariants. This file is the map.

~3,400 lines of Swift in [Sources/](Sources/), a 2,300-line test script in
[Tests/main.swift](Tests/main.swift), 13 measurement tools in [Tools/](Tools/).

Line numbers below were correct when written and drift with every edit — they are
a hint, not an address. Search for the symbol name.

## From a dropped file to a published PDF

Text mode and searchable mode diverge completely; only the first three steps are
shared.

1. **Drop** — [`resolveDroppedURLs`](Sources/Model.swift#L18) turns Finder's
   bookmark blobs into URLs, [`collectInputFiles`](Sources/Model.swift#L49)
   expands folders, filters by `supportedExtensions` and dedupes by standardized
   path.
2. **Start** — [`OCRModel.start()`](Sources/Model.swift#L234), on the main actor:
   resolves `mac-ocr`, sizes an `OperationQueue` from `Prefs.concurrency`, builds
   a [`Prefs.Snapshot`](Sources/Prefs.swift#L105) of every per-file setting,
   reserves collision-free paths with
   [`uniqueOutputs`](Sources/Model.swift#L391), records which of those had to be
   renamed, installs the `finishUp` closure, and enqueues one operation per file.
3. **Per file**, on a worker thread. Text mode stops here:
   [`Runner.run`](Sources/Runner.swift#L389) hands mac-ocr the user's destination
   path directly — **no staging**, unlike the searchable path.

Searchable mode continues, in a scratch directory under `NSTemporaryDirectory()`,
from [`makeSearchablePDF`](Sources/Model.swift#L438):

4. **Wrap** an image input as a one-page PDF
   ([`Flattener.wrapImage`](Sources/Flattener.swift#L125)); everything below is
   PDF-shaped.
5. **Rebuild** — [`Flattener.flatten`](Sources/Flattener.swift#L206). Per page:
   [`fullBox`](Sources/Flattener.swift#L403) →
   [`rebuildDPI`](Sources/Flattener.swift#L636) → `renderGrey` →
   [`otsuThreshold`](Sources/Flattener.swift#L464) →
   [`isPicture`](Sources/Flattener.swift#L525) → a 1-bit PNG or a greyscale JPEG.
   This is what removes an old text layer. The `onPage` callback runs
   [`JBIG2.encode`](Sources/JBIG2.swift#L75) immediately and deletes the PNG, so
   bitmaps don't accumulate.
6. **Recognise** — [`Runner.runStreaming`](Sources/Runner.swift#L199) with
   `--format jsonl`. One page per line as it arrives; that stream is the only
   progress signal a 200-page book gives.
7. **Write the layer** —
   [`SearchableWriter.compose`](Sources/SearchableWriter.swift#L123), via
   [`deduplicated`](Sources/SearchableWriter.swift#L267),
   [`headroom`](Sources/SearchableWriter.swift#L291) and
   [`draw`](Sources/SearchableWriter.swift#L328). Returns the lines it could not
   place.
8. **Compress and merge**, when jbig2 and qpdf are present:
   `JBIG2.assemble` hand-writes an image-only PDF — including the source's
   outline, since `qpdf --overlay` keeps the base document's catalogue — and
   `JBIG2.overlay` merges the text layer onto it. Otherwise `compose` draws text
   over images straight into the staged file and `SearchableWriter.copyOutline`
   adds the outline afterwards.
9. **Three gates, then publish** — not cancelled, `produced == expected` pages,
   and no unplaced lines. Only then
   [`publish`](Sources/Model.swift#L420) moves the staged file into place.
10. [`finish`](Sources/Model.swift#L702) → `finishUp` when `completed == total`.

## Two page boxes, deliberately kept apart

The single most confusable thing in the codebase, and the source of C7.

| | box | who uses it | why |
|---|---|---|---|
| [`displayBox`](Sources/Flattener.swift#L388) | **crop** | `compose` | What a viewer shows, and — measured — what mac-ocr renders. Observations come back relative to it. |
| [`fullBox`](Sources/Flattener.swift#L403) | **media** | `flatten` | The whole sheet. A rebuild that kept only the crop would silently discard what lies outside it. |

They never disagree destructively, because the rebuilt file carries only a media
box: when the recogniser and then `compose` look at *it*, `displayBox` falls back
to that same media box and all three agree. `renderGrey` takes the `CGPDFBox` it
should draw, so the box a caller measures with and the box it renders from cannot
drift apart.

## Where the risk concentrates

1. **[`SearchableWriter.draw`](Sources/SearchableWriter.swift#L328)** — three
   properties must hold at once (word spacing survives extraction, runs don't
   overlap vertically, runs span the ink) and each has been broken by a fix to
   another. Width comes from font *size*, height from a *vertical squash* in the
   text matrix; that separation is the whole trick. Re-measure all three after any
   change (invariant 3).
2. **Page-count verification is weak by construction.** `produced == expected`
   cannot see a page that rendered blank, or a text layer shorter than the images
   on the JBIG2 route. A recogniser that skipped a page *is* now caught, by
   `SearchableWriter.missingPages` (C12) — mac-ocr emits a record per page even
   when blank, so a missing record is a skip. Anything else that can drop content
   still needs its own report: that is invariant 1, and it is what C1, C8, C9 and
   C12 were all about.
3. **[`JBIG2.assemble`](Sources/JBIG2.swift#L113)** hand-writes a PDF: xref
   offsets and `/Length` values computed by hand, now streamed to a `FileHandle`.
   `%010ld` not `%010d` (offsets wrap past 2 GB), and `trim` for numbers because
   `%g` emits invalid PDF.
4. **Routing in [`isPicture`](Sources/Flattener.swift#L525)** has destroyed content
   twice — a fixed threshold on non-white paper, and ink coverage being blind to
   pale colour. Three signals now feed it, and the tone and saturation ones exist
   because coverage alone was wrong.
5. **Cancellation crosses four process boundaries** — mac-ocr, jbig2, qpdf, and any
   grandchild holding a pipe. `Runner.stop` escalates SIGTERM → SIGKILL, and both
   reach the child's *process group*, which Foundation makes it the leader of —
   so descendants do go down with it (R21). `kill(pid, …)` would reach one
   process; that was the leak.

## The pipeline without the UI

The OCR pipeline is separable from the UI, which is how every tool in
[Tools/](Tools/) and the whole test suite drive it. Verified, not assumed — these
six build as a library with no view sources present at all:

```sh
swiftc -O -emit-library -o libocr.dylib \
  -target "$(uname -m)-apple-macos13.0" \
  Sources/Prefs.swift Sources/Runner.swift Sources/Flattener.swift \
  Sources/SearchableWriter.swift Sources/JBIG2.swift Sources/Model.swift
```

`Model.swift` does import SwiftUI and `OCRModel` is a `@MainActor
ObservableObject`, but the pipeline entry point is `nonisolated` and does not
need the actor. (`run_tests.sh` compiles the two view files as well — that is for
compile coverage of the UI, not because the pipeline needs them.)

The entry point is
[`OCRModel.makeSearchablePDF`](Sources/Model.swift#L438), which is `nonisolated`
and deliberately internal-not-private so callers can drive the real function:

```swift
OCRModel.makeSearchablePDF(
    file: input, binary: macOCRPath, output: destination,
    rebuild: true, rebuildMode: .auto, password: nil,
    settings: .current(),          // or a Prefs.Snapshot you build yourself
    control: RunControl(),         // cancellation; one per batch
    progress: { label, fraction in ... },
    report:   { outcome, message in ... })
```

Embedding it in another application was considered and **declined** — Archive
Processor produces a different kind of PDF, so there was nothing to integrate.
The separability is still worth keeping: it is what lets the measurement harnesses
call the real functions rather than a replica, which is the discipline that caught
several defects here.

If something ever does drive it directly, these are the things that would bite:

- **It reads `UserDefaults`.** `Prefs.Snapshot.current()` does, and so does
  `Runner.resolveBinary()`. Build a `Snapshot` explicitly rather than relying on
  the defaults domain if the host has its own configuration.
- **Concurrency is the caller's.** `makeSearchablePDF` is blocking and
  thread-safe with respect to other calls — that is what C8 fixed — so run it on
  whatever queue you like. `Prefs.maxConcurrency` and `Prefs.defaultConcurrency`
  are only advice.
- **One `RunControl` per batch, and it is what Cancel talks to.** Its
  `adopting {}` helper exists because an unpaired `adopt` leaked a file
  descriptor per page (R15).
- **Failure is reported, never published.** Three gates guard `publish`, and the
  `report` callback is called exactly once per file with `.succeeded`, `.failed`
  or `.cancelled`. A `.failed` always carries a message (R17).
- **`Runner.resolveBinary()` shells out** to a login shell if `mac-ocr` is not in
  the three standard prefixes, and memoises the result. Call
  `Runner.forgetToolPaths()` if the host installs tools mid-session.

## What the tests don't cover

357 checks, 2–4 minutes, real OCR. The gaps listed here through 1.0 — the failure
and cancel branches, `publish`, encrypted PDFs, `rebuild: false`, `previewLines`,
concurrent *searchable* runs, and colour pages — are all covered now (BUGS.md
T3). What remains:

- **`otsuThreshold` / `inkCoverage` / `toneFraction` are not tested in
  isolation.** They are exercised through `flatten` and through the colour
  fixture, which is where they matter, but a calibration change would not be
  caught by a unit assertion because there isn't one.
- **Nothing drives the real `makeSearchablePDF` into producing a short text
  layer** (C16). The guard's predicate and the hazard it defends against are both
  tested; the wiring between them is reasoned.
- **The four interface questions that need a running app** — tab order, how the
  VoiceOver announcements actually sound, the Settings sheet on a short display,
  and the reopen fix outside its probe. See [TODO.md](TODO.md).
- Deleting `deduplicated` breaks nothing, because the recognition path doesn't
  emit the duplicates it exists to remove.

The suite exits 0 without jbig2/qpdf installed, silently skipping ~18 checks — so
"all green" on a machine without them means less than it looks.

It does now compile `ContentView.swift` and `SettingsView.swift`, even though
nothing instantiates a view, so a change that breaks only the UI fails the test
run rather than surviving to `./build.sh`. `App.swift` stays out — its `@main`
collides with the test script's top-level code.

## Things that will mislead you

- **`headroomFactor` is inverse.** *Higher* means shorter glyphs — `headroom`
  divides the measured gap by it. The comment used to say the opposite; if you
  find prose anywhere claiming "lower means shorter", it is wrong, and the thing
  to correct is the prose. Aligning the code to that sentence would invert a
  corpus-calibrated constant and cost line separation everywhere.
- **`Runner.arguments` builds the Extract Text command and nothing else.** There
  is no searchable-PDF form and there should not be one: mac-ocr's
  `searchable-pdf` subcommand has zero call sites here by design, so a builder
  for it would describe a command nothing runs and nothing keeps honest. The
  settings that only that subcommand takes — `ocrAllPages`, `strategy` — were
  deleted for 1.0 (H1).
- **`Flattener.pictureJPEGQuality` is a constant, not a setting** (0.6). Nothing
  in Settings reaches it, so there is no user-facing size control for picture
  pages. R13 decided that is fine: the policy is fidelity, so `flatten` refuses a
  page it cannot render rather than shrinking it.
- **`explicitOutputDir` has no production caller.** `Runner.arguments` takes it
  and the tests exercise it; the batch path passes `explicitOutputFile` instead.
  See TODO.md.
- **The outline is carried by two different mechanisms, on purpose.** The Flate
  route rebuilds it with PDFKit; the JBIG2 route writes it into the assembled
  catalogue before the qpdf merge, because a PDFKit rewrite would re-encode the
  image streams and lose the compression (R19).
- The volume is case-insensitive, so `tools/` and `Tools/` are the same directory.
