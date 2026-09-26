# Working in this repo

Vision OCR is a macOS SwiftUI app that OCRs scanned PDFs through Apple's Vision framework and writes
its own searchable-PDF text layer. Recognition runs in a helper process this repo builds
(`Helper/main.swift` → `visionocr-recognise`), which compiles `Sources/Recogniser.swift`, `Flattener.swift`
and the rest of their closure, so the app and the helper cannot diverge (`BUGS.md` R40). `jbig2` and
`qpdf` are the only other programs it runs.

This file was cut from 308 KB to the rules on 2026-09-24. The old file, including its 2,850-line
planning paragraph of per-entry campaign notes, is at `docs/history/CLAUDE-2026-09-24.md`. Nothing in
it is required reading; open it only to answer a specific question about past work.

## What matters here

The goal is a better app for the people who use it: more of each page's text selectable and correct,
nothing lost, smaller files. Work that changes what the app does outranks work on the project's own
instruments, documents and scripts. A measurement is worth taking when its answer changes what gets
built; when it would not, record the doubt in one line and move on. The history in `BUGS.md` shows what
happens otherwise: C28's campaign ran a month past its fix, grew to 732 KB, and changed no code.

Write short. A register update is a few paragraphs, not a new essay; a commit body is under about fifteen
lines. State a finding once, in the place that owns it, and do not restate old corrections.

## Where things live

- `BUGS.md` — the defect register (2 MB). Read one entry with `ops/autonomous/bugs-entry.sh <TAG>`;
  never read the file whole. Open entries: C28 (back in the queue 2026-09-25 as
  `c28-first-principles`).
- `ops/autonomous/QUEUE.md` — the work order for autonomous sessions, and a short one on purpose.
- `CHANGELOG.md` — `## Unreleased` holds user-visible changes awaiting the next release.
- `ARCHITECTURE.md` — the call path and where the risk sits. `CONTRIBUTING.md` — the change process
  for interactive work; autonomous sessions follow `ops/autonomous/resume-prompt.txt` where the two
  differ. `TODO.md`, `FEATURES.md` — decided-but-undone work and
  feature notes. `HANDOFF.md` and the dated handoffs (`HANDOFF-2026-08-17.md`, `HANDOFF-2026-08-16.md`,
  `HANDOFF-2026-08-15-night.md`, `HANDOFF-2026-08-15-evening.md`, `HANDOFF-2026-08-15-day.md`,
  `HANDOFF-2026-08-15.md`, `HANDOFF-2026-08-14.md`) are history for a human, not instructions.
- Dated `*-2026-*.tsv` files at the root are measurement evidence cited by `BUGS.md` entries.

Install the hook once per clone:

```sh
git config core.hooksPath .githooks
```

The hook runs the full suite (about 5 minutes) when a staged path matches
`Sources/ Helper/ Tests/ Tools/ build.sh run_tests.sh`, type-checks staged tools and shell scripts, and
lets anything else through in seconds.

## Commands

```sh
./build.sh            # build -> build/VisionOCR.app
./build.sh --install  # + install to /Applications
./run_tests.sh        # 1,435 checks, no skips
```

The count on the `./run_tests.sh` line stays undated and current, because `check-staleness.sh` reads it
as its reference. Update it from your own run when you add checks.

Never report a change as working without `./run_tests.sh` passing. Add a test that fails without the fix.

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

`testdocs/` — 1.2 GB of third-party copyrighted PDFs, 233 files and **232 distinct documents** (`report/w7787.pdf` has a
byte-identical twin). `testdocs/manifest.tsv` and
`Tools/sample-zotero.py` let it be rebuilt from a Zotero library.

⚠️ **Two tools in `Tools/` WRITE `argv[2]`, so a glob could destroy a corpus document** —
`pdf-extract-pages testdocs/*/*.pdf` *would have* opened document 1, overwritten document 2,
dropped the other 231 paths silently and printed `extracted 0 pages` on exit 0. Nobody ran it:
it was latent, and the destruction was measured on scratch fixtures (**710,796 B -> 809 B**,
2026-08-20), never on the corpus. **`BUGS.md` T19 is `FIXED`**: both refuse now,
`Tools/fault-inject.sh argv_writers` holds the refusals, and `OVERWRITE=1` is how to mean it on
`pdf-extract-pages`. The **six** tools that read `argv[2..]` as a label or a page number
mis-measure rather than destroy; that item is in the archived queue, not offered.

More traps that have each cost real time:

- **macOS bash is 3.2**: `"${ARRAY[@]}"` under `set -u` on an empty array is fatal, and `wait -n` does
  not exist. zsh does not word-split an unquoted `$(...)`.
- **Never run `./build.sh` while `build/VisionOCR.app` might be open** — it re-signs in place and macOS
  kills the running app.
- **A commit that runs the suite cannot be run in the foreground from an agent's Bash tool**, which caps
  at 10 minutes. Write the message to a file, run `git commit -F` in the background with an explicit
  `PATH`, and poll until the sha moves. Ending a turn kills background jobs, so poll to completion.
- **Never wrap `git commit` in `ops/autonomous/test-lock.sh`** — the hook takes the same lock and the
  commit deadlocks against itself.
- **PDFKit normalises the media box**, and `qpdf --pages` gives the same wrong answer for
  `largestImage`/`rebuildDPI`.
- **Production recognises `Flattener.flatten`'s rebuilt bitmaps**, while `Tools/make-observations`
  recognises a plain render of the source page. An instrument built on the latter measures a different
  image than the app does.
