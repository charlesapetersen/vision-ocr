# Vision OCR — technical notes

For the plain-language introduction, see [README.md](README.md). This file is the
detail that used to live there: building, how the searchable text layer is
constructed and why not the obvious way, what has been measured, and what the
tests cover.

## Requirements

- macOS 13 or later
- Xcode command line tools (to build)
- nothing extra, to build a disk image. This used to require `mac-ocr` so its binary
  could be bundled; **mac-ocr is gone** — recognition is Vision, called from a helper
  this repo builds (`Helper/main.swift` → `visionocr-recognise`), which runs **in its own
  process per file** whenever the batch has something to overlap (`helperIsWorthIt`:
  more than one file, more than one at a time). That is R40, and getting recognition
  *out* of process is the whole point of it. There is no engine binary to resolve, and no
  Settings path for one.

  What `build.sh --dmg` does bundle is that helper plus `jbig2` and `qpdf`, into
  `Contents/Resources`, and it verifies them by mounting the finished image and running
  each one under `env -i`. Its refusals are slice verification (`lipo -archs`), the
  `bundle-libs.py` audit, and that mounted-image check.

  At runtime `Runner.locateTool` resolves `jbig2` and `qpdf` in this order: the app's own
  bundled copy, then `/opt/homebrew/bin`, `/usr/local/bin` and `/opt/local/bin`, then a
  login shell. The bundled copy sits first deliberately — it is the version the corpus
  figures were measured against. (A GUI app launched from Finder doesn't inherit your
  shell's `PATH`, which is why the search exists at all.)

- `jbig2enc` and `qpdf` for the compression route, bundled the same way by
  `Tools/bundle-libs.py` — but they are not self-contained, so their dylib
  closure is walked and rewritten to `@loader_path`.
  `jbig2` links leptonica and its image codecs, `qpdf` links libqpdf and
  OpenSSL, so the script walks the dependency closure, copies it to
  `Contents/Resources/lib`, and rewrites every install name to `@loader_path`.
  It fails the build rather than shipping something that still points at
  `/opt/homebrew`, and it strips any `LC_RPATH` into Homebrew so the bundle
  cannot behave differently on a machine that happens to have it.

  **These are single-architecture**, because Homebrew builds for the machine it
  is on: an image built on Apple Silicon carries arm64-only copies.
  `Runner.containsNativeSlice` reads the Mach-O header, so on an Intel Mac the
  bundled copies are invisible and the search falls through to Homebrew exactly
  as before. Without them the app takes the Flate route and writes larger files.

## Build

```sh
./build.sh              # build into ./build (VisionOCR.app), this arch only
./build.sh --install    # build, then install to /Applications
./build.sh --run        # build, install, and launch
./build.sh --universal  # build for arm64 and x86_64
./build.sh --dmg        # package build/Vision OCR.dmg to hand to someone else
```

`--dmg` implies `--universal`: a disk image goes to Macs we know nothing about,
and a single-slice binary handed to the wrong one doesn't warn, it just refuses
to open. The build verifies both slices are present with `lipo -archs` rather
than assuming the compile did what was asked, and verifies the image with
`hdiutil verify` rather than assuming it wrote cleanly.

The app is ad-hoc signed and unsandboxed, so it can write wherever you point it.
Ad-hoc signing is also why a downloaded copy trips Gatekeeper — there is no paid
Developer ID behind it. See the README's first-launch note.

## How searchable PDFs are built

Not with a ready-made searchable-PDF writer. Two problems made the obvious one
(mac-ocr's) unusable for
re-OCRing an already-OCR'd scan:

1. **It adds its text layer on top of any existing one.** `--ocr-all-pages`
   forces recognition but doesn't remove the old layer, so copied text comes out
   doubled (measured on a book page: 2,683 → 5,401 characters, every line twice).
2. **Its layer loses word spacing.** It positions each word as its own run
   without emitting real space characters, so extractors must infer word gaps
   from geometry and often miss them.

So the app does this instead, for any input that already contains text:

1. **Rebuild the pages as images** at the scan's native resolution, which is what
   removes the old text layer. 1-bit by default — for scanned text that is
   ~110 KB/page against ~1 MB/page as JPEG, and OCR of the rebuilt pages differs
   from OCR of the untouched original by 0.13% of characters. Grayscale is
   available for pages with photographs.
2. **Recognise with Vision** (`VNRecognizeTextRequest`, revision 3), on the
   page bitmaps step 1 produced:
   Vision returns one observation per line, with the full line text and correct
   spaces.
3. **Write the text layer here**, one invisible run per line with the spaces
   intact, sizing the font so its natural width matches the line's bounding box.

Sizing the font rather than stretching the text matrix matters: stretching
widens every inter-glyph gap, and once a gap crosses an extractor's threshold it
inserts a space *inside* a word ("accomplished" → "accom plished").

Word-level extraction accuracy against the same recognition, three pages of a
300 DPI book scan:

| text layer | PDFKit | poppler |
|---|---|---|
| `mac-ocr searchable-pdf`, measured before it was dropped | 63.8% | 27.0% |
| this app | **100%** | **95.5%** |

The remaining poppler gap is its own gap heuristics on a handful of lines.

## Measured on real scans

Over **232 scanned documents** from a personal Zotero library — 8 item types × 4
eras, every one verified to be an actual scan rather than a born-digital export:

| | |
|---|---|
| process successfully | 232 / 232 |
| line-start selectability | median 100% (mean 99.71, worst 91%) |
| line-end selectability | median 100% (mean 99.55, worst 91%) |
| word retention | median 100% (mean 99.76, worst 97%) |
| text-layer offset | median 0.10, max 0.10 |
| source line tightness | 2.00% of adjacent line pairs set closer than their boxes |

The corpus was widened from 84 on 2026-08-09, and the reason is worth stating:
the original draw was capped at attachments added in the previous five years,
which is arbitrary, and it left the majority of the library ineligible. Removing
the cap brought in 148 documents, 79% of them older than that window. **The
figures did not move** — the new material scores within 0.05 of the old on every
measure. See [CORPUS-2026-08-09.md](CORPUS-2026-08-09.md).

The worst cases are 1920s–40s newspaper clippings and scanned typescript, which
is what you would expect — and they were worse still (71% and 94%) until C18
found that runs on dense newsprint were drawn 15–30% narrower than the lines they
sat on. The corpus this replaced was only 35% scans, and the
figures it produced were correspondingly flattering — see
[CORPUS-2026-08-08.md](CORPUS-2026-08-08.md).

A note on `--ocr-strategy`, kept because it explains why `deduplicated` exists.
Earlier versions of this file claimed the app set it to `standard`; it never did,
and it never could — that flag belonged to a CLI subcommand this app never
invoked. Recognition has always run under Vision's own behaviour, and now runs
under it directly. The two settings that carried those flags were deleted in 1.0;
they had been settings that could not affect anything.

That is also why `SearchableWriter.deduplicated` exists — and why it is now **inert**.
`auto`'s partitioned pass could emit the same line twice (measured on a book page: 8,462
characters against 7,941), and that pass was a mac-ocr CLI behaviour which no longer
runs. Measured on 2026-08-14 over 233 corpus documents × 3 pages: it removes **zero**
observations. `ARCHITECTURE.md` is right that deleting it would break nothing; this
paragraph used to say the opposite, and the two files contradicted each other on
precisely the question "can I delete this".

## Throughput

Files are OCR'd concurrently, defaulting to this Mac's performance-core count.
Vision parallelises within a page, but
that still leaves headroom. Measured on an M3 Pro (6P+6E):

| | 24 × 1-page | 4 × 15-page |
|---|---|---|
| one at a time | 18.4s | 31.1s |
| 4 at once | 7.1s | 10.4s |
| 6 at once | 5.6s | 10.4s |
| 12 at once | 5.1s | 10.5s |
| all files in one CLI call, when there was a CLI | 12.5s | 29.9s |

So ~3× for free, flattening at the performance-core count — the efficiency cores
add almost nothing. Lower the setting if OCR is competing with other work.
(The last row is why batching every file into one call was never worth it; with
recognition in process there is no per-file startup left to recover.)

The other levers, same corpus, both in Settings: `--fast` is ~2.6× faster for
~1.7% character error (it misread standalone `1` as `I`), and lowering the
render DPI helps only marginally on clean scans. Both were measured on
synthetic, clean text — real scans with skew and noise will fare worse,
especially under `--fast`.

Deliberately left out: region-of-interest recognition, which needs a visual
region picker to be usable at all.

## Settings, in full

`⌘,` or the gear button. Defaults match Vision's own, so an untouched panel
behaves the way the framework does unaided. The panel shows a live preview of
what a run will actually do.

**Recognition** (both modes) — fast recognizer, language correction, recognition
languages (BCP-47), minimum confidence, PDF render DPI, ignore-small-text
threshold, custom vocabulary, and a password for encrypted PDFs.

**Extract text** — plain text, JSON (with bounding boxes and confidence), or
JSON Lines.

**Searchable PDF** — whether to rebuild the page images first, in black and white
or greyscale or automatically per page, and whether to compress them with JBIG2.

**Behaviour** — how many files to OCR at once, open the output folder when
finished.

## Tests

```sh
./run_tests.sh
```

1,185 checks at C26's bar move (2026-08-19), and anywhere from about a minute and a half to about forty depending on what else the
machine is doing, because it runs real OCR rather than mocking it. Every run through
`ops/autonomous/test-lock.sh` records its own duration and the load average beside it, so the
spread is a fact you can look up rather than one you have to rediscover.
It builds image-only PDFs and puts them through the actual pipeline — including
`OCRModel.makeSearchablePDF`, which is deliberately internal so the tests exercise
the real function rather than a replica of it.

Covered: recognition settings reaching the request, drop-box filtering and the
Finder drop decode, word spacing and line separation in the text layer,
right-to-left round-tripping, per-page geometry with mixed sizes and rotation,
crop boxes, colour pages, encrypted input, the JBIG2 route, both output routes
with and without the rebuild, cancellation reaching a whole process tree,
concurrency in both modes, and that a partial result is never published.

It needs nothing installed. Without `jbig2enc`/`qpdf` it still exits 0 while skipping the
compression checks, so a green run on a machine without them means less than it
looks.

## Layout

| Path | |
|---|---|
| [Sources/App.swift](Sources/App.swift) | entry point |
| [Sources/ContentView.swift](Sources/ContentView.swift) | main window: drop box, destination, progress, log |
| [Sources/SettingsView.swift](Sources/SettingsView.swift) | settings panel |
| [Sources/Model.swift](Sources/Model.swift) | file list, drop decoding, batch run, `makeSearchablePDF` |
| [Sources/Recogniser.swift](Sources/Recogniser.swift) | calls Vision, and writes Extract Text output |
| [Sources/Runner.swift](Sources/Runner.swift) | finds `jbig2` and `qpdf`, and the process handling they need |
| [Sources/Prefs.swift](Sources/Prefs.swift) | persisted settings, their defaults, and the per-batch snapshot |
| [Sources/Flattener.swift](Sources/Flattener.swift) | re-renders pages; decides 1-bit vs greyscale per page |
| [Sources/SearchableWriter.swift](Sources/SearchableWriter.swift) | places the invisible text layer |
| [Sources/JBIG2.swift](Sources/JBIG2.swift) | JBIG2 compression and the hand-written image PDF |

The last three hold nearly all the subtlety — see
[ARCHITECTURE.md](ARCHITECTURE.md).
