# Working in this repo

Vision OCR is a macOS SwiftUI app that OCRs scanned PDFs through Apple's Vision framework and writes
its own searchable-PDF text layer. Recognition runs in a helper process this repo builds
(`Helper/main.swift` → `visionocr-recognise`), which compiles `Sources/Recogniser.swift`, `Flattener.swift`
and the rest of their closure, so the app and the helper cannot diverge (`BUGS.md` R40). `jbig2` and
`qpdf` are the only other programs it runs.

The file's earlier long form, with per-entry campaign notes, is at `docs/history/CLAUDE-2026-09-24.md`.
Nothing in it is required reading; open it only to answer a specific question about past work.

## What matters here

The goal is a better app for the people who use it: more of each page's text selectable and correct,
nothing lost, smaller files. Work that changes what the app does outranks work on the project's own
instruments, documents and scripts. A measurement is worth taking when its answer changes what gets
built; when it would not, record the doubt in one line and move on. The history in `BUGS.md` shows what
happens otherwise: C28's campaign ran a month past its fix, grew to 732 KB, and changed no code.

Write short. A register update is a few paragraphs, not a new essay; a commit body is under about fifteen
lines. State a finding once, in the place that owns it, and do not restate old corrections.

## Where things live

- `BUGS.md` — the defect register's index (240 KB): each entry's heading line, with the entry itself in
  `bugs/<TAG>.md`. Read one with `ops/autonomous/bugs-entry.sh <TAG>` and write in its file; a status change
  goes in both the file's first line and the index line, which `check-queue-coherence.sh` holds equal. A new
  entry is a file plus its index line. Open entry: C57. C41's work moved to Archive Suite
  (`W42.c41-newspaper-scans`) on 2026-10-16; its entry here is history.
- `ops/autonomous/QUEUE.md` — the work order for autonomous sessions. Its queue is done (owner, 2026-10-16); only the three permanent owner holds remain.
  No autonomous sessions run here: the engine is stopped and new work goes to Archive Suite. The
  `ops/autonomous/` scripts stay in place for the merge into Archive Processor.
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
`Sources/ Helper/ Tests/ Tools/make-plate-fixtures.swift build.sh run_tests.sh`, type-checks staged tools
and shell scripts (a commit of other tools alone skips the suite), and
lets anything else through in seconds.

## Commands

```sh
./build.sh            # build -> build/VisionOCR.app
./build.sh --install  # + install to /Applications
./run_tests.sh        # 2,137 checks, no skips
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
   Figures recorded before `BUGS.md` T14 came from broken instruments and are
   void. The procedure:

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

   What each one measures:

   - `score-line-separation` — properties (a) and (b). Reports `merged=M/N`
     over adjacent visual-line pairs and a `runaway=` character share.
   - `score-corpus` — properties (c) and (d) plus word retention (`words=`,
     `off=`). It prints `SKIP` at exit 1 over a document it measured nothing on.
   - `probe-text-offset` — where the runs sit relative to their boxes, scanning
     outward from zero.
   - `probe-line-edges` — the per-page drill-down that names the failing lines on
     the page it is given.

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

- **Heavy work takes the machine-wide lock shared with Archive Suite**: `ops/autonomous/mac-heavy-lock.sh run
  --label L -- <cmd>` (`status` shows the holder). The suite through `test-lock.sh`, the gate's build and
  `run-guarded.sh` already do. Wrap any other long build, VM run or corpus job in it too; one-page checks don't need to.
  When the Agent Manager's `bin/heavy-lock` is installed, the helper hands every call to it (`ops/autonomous/README.md`).

- **Run every suite through `ops/autonomous/test-lock.sh run`, and never two in
  one worktree.** Two in one worktree share `build/`; the lock makes the second
  wait. Each run has its own settings domain (`local.visionocr-tests.<pid>`),
  report and temporary directories, and `test.lock` holds one entry per worktree,
  so suites in two worktrees compile side by side and queue for the machine-wide
  heavy lock, which runs one suite's checks at a time.
- **Backgrounded shell commands have essentially no `PATH`** — `basename`, `cut`,
  `timeout` fail silently and loops report bogus results. Use absolute paths.
- **A suite's log lags by up to 4 KB when redirected to a file** — `print` is
  fully buffered there, so `tail -f` looks stalled on a healthy run. Watch the
  process, not the log.
- **Watch for the suite with `pgrep -x tests`, not `pgrep -f build/tests`.** The
  `-f` form matches every *waiter* whose own command line contains the string,
  including itself, so a "is a suite running?" guard reports yes on a machine
  with no suite on it.
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

## Owner review sessions

Owner, 2026-10-15: before any session the owner runs by hand (a guided session, an acceptance pass, a review
sheet), judge whether it is the right time, by reading the open work rather than checking that the blockers are
ticked. It is not time while a known defect would get in the way, or while queued work is about to change what
the review looks at. If it is not time, name what it waits for, block the item on that, and report it (no
decision). Authority: `~/Claude/CLAUDE.md`, "Owner review sessions".

## Not committed

`testdocs/` — 1.2 GB of third-party copyrighted PDFs, 233 files and **232 distinct documents** (`report/w7787.pdf` has a
byte-identical twin). `testdocs/manifest.tsv` and
`Tools/sample-zotero.py` let it be rebuilt from a Zotero library.

⚠️ **Two tools in `Tools/` write `argv[2]`, so a glob could destroy a corpus document.** Both refuse
(`BUGS.md` T19); `Tools/fault-inject.sh argv_writers` holds the refusals, and `OVERWRITE=1` is how to
mean it on `pdf-extract-pages`. The six tools that read `argv[2..]` as a label or a page number
mis-measure a glob rather than destroy.

More traps that have each cost real time:

- **macOS bash is 3.2**: `"${ARRAY[@]}"` under `set -u` on an empty array is fatal, and `wait -n` does
  not exist. zsh does not word-split an unquoted `$(...)`.
- **Never run `./build.sh` while `build/VisionOCR.app` might be open** — it re-signs in place and macOS
  kills the running app.
- **A commit that runs the suite cannot be run in the foreground from an agent's Bash tool**, which caps
  at 10 minutes. Write the message to a file, run `git commit -F` in the background with an explicit
  `PATH`, and wait until the sha moves.
- **Never wrap `git commit` in `ops/autonomous/test-lock.sh`** — the hook takes the same lock and the
  commit deadlocks against itself.
- **PDFKit normalises the media box**, and `qpdf --pages` gives the same wrong answer for
  `largestImage`/`rebuildDPI`.
- **Production recognises `Flattener.flatten`'s rebuilt bitmaps**, while `Tools/make-observations`
  recognises a plain render of the source page. An instrument built on the latter measures a different
  image than the app does.
