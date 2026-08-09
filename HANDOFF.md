# Picking this up cold

Read this, then [ARCHITECTURE.md](ARCHITECTURE.md) for the call path, then
`BUGS.md`. Between them you should not need any prior session.

## What this is

**Vision OCR** — a small SwiftUI front end for
[mac-ocr](https://github.com/privatenumber/mac-ocr), which runs OCR through Apple's
Vision framework. Drag PDFs onto the window, pick an output folder, click Start.
Two modes: extract text, or produce a searchable PDF.

## The one non-obvious design decision

**mac-ocr is used for recognition only. This app writes the searchable PDF itself.**

mac-ocr's own `searchable-pdf` writer has two defects that made it unusable here:

1. It adds its text layer *on top of* any existing one, so re-OCRing an
   already-OCR'd scan yields doubled text (measured: 2,683 → 5,401 characters).
2. Its layer positions each word as a separate run without real space characters,
   so extractors must infer word gaps and miss many. Word-level accuracy against
   the same recognition was 64% (PDFKit) and 27% (poppler); this app's layer gets
   99.8% and 97%.

So the searchable pipeline is: rebuild pages as images (which is what removes an
old text layer) → recognise with `mac-ocr --format jsonl` → write the invisible
text layer here → compress with jbig2enc → merge with `qpdf --overlay`.

### How much of mac-ocr is left, and why we keep it

**One invocation per file, and nothing else.** `mac-ocr <file> --format jsonl`
plus recognition flags. Of its three subcommands we use one; `searchable-pdf` has
zero call sites by design, which makes `--ocr-strategy` and `--ocr-all-pages` dead
(they belong to that subcommand), along with `languages`, `--merge`, `--roi` and
the `--image-*` family. Everything else — the page rebuild, the routing, the text
layer, the compression, the assembly, the verification — is ours: roughly 2,430 of
the 2,960 non-UI lines, with `Runner.swift` the only part that exists because we
shell out.

That thinness is worth knowing, because it invites a tempting idea: mac-ocr is
itself a thin CLI over Vision, we already rasterise pages ourselves, and calling
`VNRecognizeTextRequest` directly would delete most of `Runner.swift`, remove the
`PATH`-discovery problem, skip a redundant rasterise round-trip, and eliminate a
whole bug class — **C6, R2, R3, R16, R17, R21 and R22 were all
subprocess-management faults, not OCR ones.** That is seven of them now, which is
the strongest argument on this side of the question.

**Decided: don't.** Keeping mac-ocr means someone else tracks Vision's revisions,
language lists and API churn, and the current arrangement is validated across the
84-document corpus. The dependency is thin enough to be a choice rather than a
constraint, and the choice is to keep it — provided it stays maintained and stays
out of our way. Revisit only if it stops being either.

## Build, test, run

```sh
./build.sh            # -> build/VisionOCR.app
./build.sh --install  # also install to /Applications
./build.sh --run      # install and launch
./run_tests.sh        # 357 checks, ~2-4 minutes (it runs real OCR)
```

Requirements: macOS 13+, Xcode command line tools, and

```sh
npm install -g mac-ocr        # required
brew install jbig2enc qpdf    # optional: compression. Falls back silently.
```

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
  1-bit and greyscale. That decision has destroyed content twice: once because a
  fixed threshold of 186 is wrong for any paper that isn't bright white (now Otsu
  per page), once because ink coverage is *blind to pale colour* — pure yellow has
  luminance 226, so a tinted figure scored ~0% ink and was thresholded to blotches,
  losing 99% of the page.
- **`Sources/JBIG2.swift`** — hand-writes a PDF embedding JBIG2/JPEG streams.
  xref offsets and `/Length` values are computed by hand; be careful.

## Lessons that cost real time

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

## Where things stand

Everything in `BUGS.md` is `FIXED` or `WONTFIX`, and `TODO.md` holds no code work
— only four things that need a person in front of a running app. `FEATURES.md` is
ideas. The suite is at 357 checks, `main` is pushed, and 1.1.0 is tagged.

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

`testdocs/` holds **84 documents, every one of them a scan** (8 item types x 4
eras) used to measure the searchable pipeline across books, newspapers,
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
