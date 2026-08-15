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

Planning lives in four files. [BUGS.md](BUGS.md) is the defect register — **five
entries are open and three of them change content on the default route**: R56 (a pale
drawing is erased, not softened), R57 (a tonal plate can come out a black blob) and
C23 (the rebuilt copy displays what the original's crop box hid — C13 recurring
through `JBIG2.assemble`, which writes no `/CropBox`; 14 of 233 corpus documents).
Read its header before planning anything. Update it in the same commit as any fix.
[TODO.md](TODO.md) is decided-but-undone work, [FEATURES.md](FEATURES.md) is ideas
with their costs and the reasons some are parked, and
[REVIEW-2026-08-14.md](REVIEW-2026-08-14.md) is the standing record of a
whole-codebase review sweep, including findings not yet fixed and areas not yet
covered. **[HANDOFF-2026-08-14.md](HANDOFF-2026-08-14.md) is where to start** — it
has the fix order, what is deliberately withheld from release, and which
instruments not to trust.

*(This paragraph read "nothing open" for a day after four entries were opened, which
is exactly the sentence a new reader trusts most. If you close or open an entry,
correct it here in the same commit.)*

Install the hook once per clone:

```sh
git config core.hooksPath .githooks
```

## Commands

```sh
./build.sh            # build -> build/VisionOCR.app
./build.sh --install  # + install to /Applications
./run_tests.sh        # 880 checks, 2-4 min; runs real OCR, needs nothing installed
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
   fix to another. Re-measure all of them after any change to `SearchableWriter` —
   **but fix an instrument first, because three of the four named here cannot
   currently be trusted** (`REVIEW-2026-08-14.md` A6.1, measured over 233 documents):

   - `Tools/score-line-separation.swift` divides PDFKit *lines* by Vision
     *fragments* and **can move opposite to the property it names** — 87% to 87%
     across a change from no runaway line to a 2,139-character one.
   - `Tools/probe-line-edges.swift` is behaviourally identical to `score-corpus`'s
     own `start=`/`end=` columns on 48 of 48 documents, so the four instruments are
     really three.
   - `Tools/probe-text-offset.swift`'s printed *range* is ~1.7% artifact (it locks
     onto a common word on the line below); its median is sound.
   - the `words=` column of `Tools/score-corpus.swift` is the one that holds — but
     `score-corpus` prints `OK` for a document it measured nothing on.

   And **the procedure is not executable as written**: two of those probes take a
   JSON of observations that nothing in `Tools/` produces any more.

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

- **Backgrounded shell commands have essentially no `PATH`** — `basename`, `cut`,
  `timeout` fail silently and loops report bogus results. Use absolute paths.
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
