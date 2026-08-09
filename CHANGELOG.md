# Changelog

Notable changes, newest first. Dates are release dates.

This project keeps its defect history in [BUGS.md](BUGS.md) with the evidence for
each fix; entries below cite those identifiers rather than repeating the
measurements.

**The app was called Vision Reader GUI until 1.1.0.** Entries below that version
use the old name, and deliberately have not been rewritten — a changelog that
edits its own history is worth less than one that reads slightly awkwardly. Where
an older entry mentions "Window ▸ Vision Reader Window", the menu item is now
"Window ▸ Vision OCR Window"; nothing else moved.

## 1.2.0 — 2026-08-09

**Eleven defects, from an adversarial review of 1.1.0.** Four finders over all
nine source files, then a skeptic pass that defaulted to refuting. Fourteen
claims, eleven survived; the three that did not are kept as BUGS.md R28, because
what killed them is worth more than they were — PDFKit buffers a document at
init (a 66 MB PDF still parsed page 40 correctly after being truncated to nine
bytes on disk), and mac-ocr does not touch its `-o` destination until one write
at the very end.

**Scans with a page the app could not read no longer publish quietly** (C19).
"Use Existing Text" appended an empty string for every page with no text layer,
and in a page-break-joined file that is invisible — a 300-page book with a
30-page scanned appendix published 270 pages with a green tick. Those pages are
now named in the log and marked in the file itself, at the point where they
would have been. A blank leaf is still not reported as a loss.

**Line ends on dense scans, again** (C20). `headroom` and `rightLimit` disagreed
about what counts as one visual line, and a fragment pair in the band between
their two answers was shrunk *and* crushed at once — worst case a run drawn
0.71 pt tall against a natural 9.04. Over the 84-document corpus, line-end
selectability goes from a mean of 98.90 to **99.58 with 27 documents better and
none worse**, while line-start, word retention, text-layer offset and vertical
collisions are all unchanged. There is one definition of "the same line" now.

**Three crashes that took the whole batch with them.** The megapixel guard added
in 1.0 to prevent a crash overflowed `Int` and trapped inside itself (R24); the
outline copier had neither of the bounds its mirror function has, so a deeply
nested outline was a SIGBUS (R23); and a page whose forms share one resources
dictionary made the image scan do 13 million lookups where 61 would do (R25).

**Smaller, but each one bit every time it happened.** A file named `text.pdf`
failed deterministically, because it collided with the pipeline's own scratch
name (R27). The "page too large" refusal told you to change a setting that
cannot affect it (R26). Dropping a folder walked the whole tree on the main
thread, so a big or network-mounted folder froze the window with no way out
(U20). Files could still be added, and the output folder still changed, during
the pre-flight — after the batch had been frozen — which brought back the "3 of
3 succeeded" over a list of four that U1 was supposed to have ended (U19). And
the login-shell lookup's three-second timeout sat *after* the call it was meant
to bound, so a wedged shell still hung the app for ever (U18).

**Bookmarks on sideways pages** land in the right place: a half-specified
destination on a quarter-turned page kept the coordinate it had invented rather
than the one it was given, sending the reader to the foot of the page (C21).

418 checks, up from 357.

## 1.1.0 — 2026-08-08

**Renamed to Vision OCR.** The old name described the window; the new one
describes the job. Everything moved with it: the app is `VisionOCR.app` with the
display name *Vision OCR*, the bundle identifier is `com.cp1.VisionOCR`, the
window and the Window-menu item read "Vision OCR", and the repository is
`vision-ocr`.

**Your settings come with you.** A bundle identifier *is* the preferences
domain, so a rename moves it — and without a migration this release would have
silently reset everyone's output folder, language list and mac-ocr path while
claiming to change nothing but a name. `Prefs.migrateFromPreviousName` carries
them over once, gated on an explicit marker that "Reset to Defaults" cannot
clear (or the next launch would re-import the old values over the reset).

The first version of that migration never ran: it was gated on "does this domain
have a `mode` yet", and `object(forKey:)` searches the *registration* domain too,
so once `register()` has run every key looks present. The test caught it. That
test is the only reason this works.

**There is a disk image now** — `./build.sh --dmg` produces `Vision OCR.dmg`,
with the app and a drag-to-Applications target, verified with `hdiutil verify`
rather than assumed. There was never one before; the request to rename it is what
surfaced that.

**The disk image is universal.** `--dmg` implies a new `--universal`, which builds
arm64 and x86_64 and `lipo`s them together; the build then checks both slices are
really there. Until now `build.sh` compiled for `uname -m` only, so the image
would have been arm64-only — and an Intel Mac given a single-slice binary does
not warn, it just refuses to open, which from the other end is indistinguishable
from a corrupt download.

**README is for people who want to use the app**, not build it. Installation,
the Gatekeeper first-launch dance, and what the modes do; the build instructions,
the text-layer design, the measurements and the test inventory moved to
[TECHNICAL.md](TECHNICAL.md) intact.

Also: `Prefs.allKeys` is now the single list of keys this app owns, read by the
migration, by "Reset to Defaults" and by the test harness. There were three
copies, and R6 — a reset that silently omitted four keys — is what that costs.

357 checks.

## 1.0.4 — 2026-08-08

**Newspaper scans: line ends are selectable now** (C18). On dense newsprint the
worst document had nearly a fifth of its lines unselectable to the end. The cause
was one line in `draw`: when a line needs a large font to span its box but sits
close to its neighbours, the code capped the font size — and capping the size
costs *width*, not height, so runs came out 15–30% narrower than the lines they
sat on. 72% of the misses were exactly that.

Fixing it uncovered a fourth property of the text layer that had been holding
**by accident**. Vision splits one visual line of a column into fragments side by
side, and nothing writes a space character between them — PDFKit synthesises it
from the geometric gap and gives up below ~0.15 em. That gap existed only as
slack left over from the size cap. Widening the runs closed it and words welded:
`valuablestudy`, `thatmeasurable`. `reserveEms` now holds it open deliberately,
and CLAUDE.md's invariant 3 says "four properties", not three.

Measured over the 84-document scanned corpus:

| | shipped | now |
|---|---|---|
| line-end worst | **71%** | **91%** |
| word retention median / worst | 99% / 94% | **100% / 97%** |
| documents improved / harmed (line-end) | — | 28 / 1 |
| documents improved / harmed (words) | — | **32 / 0** |
| line-start, text-layer offset | — | unchanged |
| line separation (`score-line-separation`) | — | **byte-identical** |

**An adversarial review caught four real defects in the first version of this
fix**, all verified by running code, all fixed before release: the reserve was
budgeted against the pre-shrink font size, so a one-character fragment kept 21%
of its width; `rightLimit` compared box bottoms instead of drawn baselines, so a
display numeral treated a body line two rows away as its neighbour; a 0.5 pt
tolerance was a cliff that silently dropped the reserve when Vision's boxes
overlapped by more than two pixels; and `reserveEms` was non-monotonic as a
calibration knob.

**It also caught a claim in our own documentation that was circular.** The
"vertical overlap unchanged" figure quoted as evidence here and in BUGS.md is
computed entirely from the reference OCR of the rendered *image*. The text layer
is invisible to it, so it cannot respond to a `SearchableWriter` change at all.
`Tools/README.md` had always called it "source line tightness"; the misreading
was introduced in the previous release's write-up and is corrected in D3, in the
README, in HANDOFF, and with a warning at the point of computation. The evidence
for invariant 3(b) is `score-line-separation`, compiled once per revision.

Also in this release: **Searchable PDF is the first button and the default**, and
the window no longer shows the pipeline's steps while running — just a progress
bar and one line. The per-file outcomes still appear afterwards, because that is
the only place a failure is visible. 350 checks.

## 1.0.3 — 2026-08-08

**The corpus was wrong, so it was replaced.** The accuracy figures this project
has quoted for months came from 78 documents of which only 27 were scans — 40
were born-digital and 10 were photographs of manuscripts. Nothing about the
numbers looked wrong, which is the point: born-digital documents score perfectly,
because OCR of a clean rendering of digital text is an easy problem, and they
were holding every percentile up.

`Tools/sample-zotero.py` now classifies every candidate and keeps only scans,
using the same `Flattener.pageIsAnImage` the app uses to decide whether it is
about to discard someone's text — one rule, not two that drift. `manuscript` and
`letter` are excluded outright as Archive Processor's material. New flags:
`--added-since`, `--exclude-manifest`, `--types`, and `--allow-any-kind` for
reproducing an old corpus, which says in its help what that costs.

Rebuilt: **84 documents, all 84 verified scans** (the gate rejected 275
born-digital, 23 photographed). Through the shipped pipeline:

| | |
|---|---|
| processed | 84 / 84 |
| line-start selectability | median 100%, worst 91% |
| line-end selectability | median 100%, worst 71% |
| word retention | median 99%, worst 94% |
| text-layer offset | median 0.10, max 0.10 |
| runs overlapping vertically | 1.33% (74 of 5,564 pairs) |

The medians did not move. The tail got worse and is now true: worst-case line-end
was documented as 86–95% and is 71%. `testdocs/manifest.tsv` carries each
document's scores, so a regression traces to a document rather than a median, and
the overlap figure is published for the first time (D3) — it is the number that
would show a `SearchableWriter` change breaking line-by-line selection.

**Extract Text reads the text that is already there.** C17 fixed the destructive
path; this is the other half. Given a born-digital PDF, Extract Text offers "Use
Existing Text" instead of OCRing a picture of it. Plain text only — `json` and
`jsonl` are Vision's observation schema, and a text layer has no bounding boxes
to put in them.

Also: `explicitOutputDir` deleted — a correct, tested override that nothing
shipping ever called. 330 checks.

## 1.0.2 — 2026-08-08

**Asks before it discards text it cannot replace** (C17). Dropping a
born-digital PDF into Searchable PDF mode used to rebuild its pages as images —
throwing away real embedded text — and replace it with OCR of a picture of that
text, reporting success. Measured on three pages of one such book: 1,031 words
became 938, and only 86.1% of the output's words existed in the original.

It is not refused, because sometimes the embedded text is itself the problem — a
bad export, a mis-mapped font, a publisher's broken layer — and re-OCRing is
exactly what is wanted. What goes is the surprise. A pre-flight flags inputs
whose text sits on no page-sized image (which is what separates real digital text
from an OCR layer over a scan) and offers **OCR Anyway / Skip Those / Cancel**,
with "Don't ask again" and a matching Settings toggle. Only the destructive path
asks; Extract Text writes a new file and leaves the input alone.

The load-bearing case is the one that must *not* warn: a scan that has already
been OCR'd has text too, and stopping to ask about it would put a dialog in front
of this app's main use case. Tested, and verified against the running app in the
VM — 1 of 2 files flagged, nothing started until the alert was answered, and
"Skip Those" ran only the scan.

Found by a corpus run over a fresh sample of real scans, which also found that
**only 27 of the 78 documents in the project's own corpus are scans** — see
[CORPUS-2026-08-08.md](CORPUS-2026-08-08.md). 325 checks.

## 1.0.1 — 2026-08-08

Ran the app for real. The three interface properties that 1.0.0 shipped as
"unverified" were checked against the running app in a headless
[Tart](https://github.com/cirruslabs/tart) macOS VM — its own virtual display, so
nothing on anyone's screen, driven over VNC. All three pass. The pass also found
a defect worse than any of them.

- **Every file opened from Finder spawned another window** (U17), each with its
  own `OCRModel`. Counting on-screen windows by pid: a bare launch gave 1, opening
  three files gave **4**, opening a fourth gave **5** — and every one of them
  listed all the files with its own enabled Start button. Press Start in two and
  two batches race to write the same `scan.ocr.pdf`, because `uniqueOutputs` only
  de-conflicts *within* a batch. That is C8 and R18's class of defect, reachable
  by an ordinary Finder gesture. A `WindowGroup` is a template that macOS
  instantiates once per document; this app has one window by design, so it is a
  single-instance `Window` now, with the `OCRModel` owned by the app rather than
  by whichever window happens to exist — which also means a batch survives its
  window instead of being silently orphaned by a close.
- **The window really does come back after a mid-run close** (U13), showing the
  *live* batch — "27% · 0 of 3 files · 1 running", Cancel available — by both the
  Dock-click event and Window ▸ Vision Reader Window (⌘0).
- **Settings really does fit a short display** (U15): 560x512 on a 1024x640
  screen, Done footer on screen, the ScrollView carrying the overflow.
- **The tab order reaches everything.** Idle: Settings → mode picker → Start OCR
  → Add… → Clear List → remove-file → Save beside each original, cycling.
  Mid-run: Settings → Cancel → Copy — exactly the enabled set, with every
  disabled control correctly skipped.

Still not verified: the VoiceOver announcements have never been *heard*. See
[TODO.md](TODO.md).

Three instruments lied before any of this worked, and they are written down in
BUGS.md because that is the reusable part: a window probe matching
`kCGWindowOwnerName` against `"VisionReader"` when the bundle name is
`Vision Reader GUI`, which reported zero windows while the app had four; a
virtiofs mount serving a 90-minute-old `App.swift`, so the build under test was
not the code under test; and a TCC prompt quietly eating every keystroke, which
produced a clean and entirely fictitious tab-order result.

## 1.0.0 — 2026-08-08

First tagged release. The app already worked before this point — the repository
begins at a commit where the pipeline, the corpus and most of the design
decisions were in place — so this release is not "it now does something", it is
"it now does it reliably enough to depend on, and says so when it cannot".

### What it does

Drag scanned PDFs (or images, or folders) onto the window, choose a destination,
and get either extracted text or a searchable PDF: a visually identical copy with
an invisible, selectable text layer. Recognition is Apple's Vision framework via
the `mac-ocr` CLI; **the searchable-PDF writer is this app's own**, because
mac-ocr's doubles text on re-OCR and loses word spacing. See
[HANDOFF.md](HANDOFF.md) for why.

Measured over a 78-document corpus spanning ten item types and four eras:
78/78 process successfully, median 100% line-start and line-end selectability,
median 0.00 text-layer offset, median 100% word retention.

*(Added 2026-08-08: only 27 of those 78 documents are scans — 40 are
born-digital and 10 were photographed by hand. The figures are true of the
files and weaker evidence about OCR on scanned print than they read as. See
[CORPUS-2026-08-08.md](CORPUS-2026-08-08.md).)*

### Content-loss fixes

The defects that could publish a damaged document while reporting success — the
class this project cares about most.

- **Concurrent files erased each other's lost-line reports** (C8). A shared static
  meant a document that lost lines was published as a clean success; reproduced at
  21 of 40 runs, with an unsynchronised-array crash as a bonus.
- **Pages rebuilt at a logo's resolution** (C9, C14). A born-digital page carrying
  1,846 characters rebuilt as a 16×23 pixel image. The correction distinguishes a
  logo from a genuine coarse scan by pixel width, so real 72 DPI scans are no
  longer upsampled 17× either.
- **mac-ocr renders the crop box, not the media box** (C7, C10, C13). Settled by
  measurement; the whole geometry chain now agrees, the published copy keeps the
  entire sheet, and it still displays exactly as the original did.
- **A page the recogniser skipped published with no text** (C12), invisible to
  every other check because the page itself was still there.
- **Multi-page TIFFs were reduced to their first sheet** (C15) — the standard
  output of every sheet-fed archival scanner.
- **Dropped images were wrapped squashed or sideways** (C11): one DPI axis used
  for both, and EXIF orientation ignored.

### Reliability

- **A file-descriptor leak killed long batches** (R15). One descriptor per page,
  never released, so a batch died at roughly 2,300 pages — against a corpus of
  4,992.
- **Cancel now works** (R2, R14, R16, R17). The read loops are interruptible and
  bounded, SIGTERM escalates to SIGKILL, the JBIG2 route reports cancellation as
  cancellation rather than failure, and a run that cannot be stopped says so
  instead of crashing on an unread exit status.
- **Cancel reaches grandchildren** (R21). `Process.terminate()` already signalled
  the whole process group; the SIGKILL escalation did not, so the one case
  escalation exists for — a child that ignores SIGTERM — was the one case that
  left a descendant running, reparented to launchd, holding its pipe. The
  recorded fix for this was a `posix_spawn` rewrite of the riskiest code in the
  project; measuring it first turned it into two lines.
- **A short text layer could publish as a complete file** (C16). On the JBIG2
  route the page-count check compared the images PDF against a count derived from
  the same list, so it could not fail, and `qpdf --overlay` leaves unmatched pages
  bare — a full-length, valid PDF with no text on its later pages. The composed
  layer is checked before anything is merged.
- **Peak memory for assembly dropped 18×** (R8), from output-sized to one page,
  with byte-identical output.
- The stderr drain is idle rather than waking five times a second for the life of
  every run (R22), and partial stderr now survives a timeout instead of being
  discarded.
- **A batch could overwrite one of its own inputs** (R18) when re-run over a
  folder containing previous results.
- Settings are snapshotted once per batch instead of re-read per file (R5), and
  progress is keyed by URL so two files with the same name no longer collide (R4).

### Fidelity

- **Document outlines survive OCR** (R19), on both output routes, for the 225
  bytes the outline objects themselves occupy — written into the assembled
  catalogue before the merge rather than through a rewrite that would have added
  93 KB to the same file by destroying its JBIG2 compression.
- **Right-to-left text was re-measured and left alone** (C5). The reported defect
  did not reproduce, and every candidate fix was worse; the reasoning and the
  measurements are recorded rather than the change.
- **Fidelity beats file size** (R13). No DPI cap, no silent downscale; a page
  renders at its own resolution or the run refuses and says why.

### The interface

The GUI briefly stopped being the product — this was going to become a headless
OCR backend — and got no review attention while that was true. That decision was
reversed, and an adversarial pass over the front end found these.

- **Quitting mid-run orphaned the OCR children.** A child of a process that exits
  is reparented to launchd rather than killed, so mac-ocr, jbig2 and qpdf kept
  running invisibly. The app now asks, then stops them.
- **The Settings panel accepted edits that could not apply.** A batch snapshots
  its settings, so a mid-run change was silently ignored — and changing the text
  format would have written JSON into a reserved `.txt` path. The panel now says
  a run is in progress and locks.
- **The file list could contradict the run.** `Add…` stayed enabled during a
  batch, so the summary could say "3 of 3 succeeded" with five files on screen.
- **`Save beside each original` could describe the wrong destination** mid-run.
- **Dropping only unsupported files gave no feedback at all** — the notice lived
  in a list that does not appear when nothing was accepted.
- **Extract Text pinned the progress bar at exactly 50%** for a whole single-file
  run, which reads as a hang. There is nothing to measure there, so the bar is
  indeterminate rather than showing an invented number.
- **The log never said where output went**, which with "beside each original"
  leaves no way to find the results of a partly-failed batch.
- **Accessibility**: labels and values across the window and the Settings panel,
  outcome exposed to VoiceOver instead of carried by colour, the full path on
  each file row, a disabled Start that says why, and Cancel on ⌘. Progress is
  also *spoken* now (U16) — the batch starting, each file landing, and the
  summary — rather than merely readable if you go and read it.
- **The window could not be recovered after closing it mid-run** (U13). This is
  the worst of the interface defects and it was hiding as an open question. The
  reopen handler looked for a window that `canBecomeMain`, and a closed SwiftUI
  window reports false for exactly that until something orders it front — so the
  handler did nothing, and a running batch was unreachable: no progress, no log,
  no Cancel. Measured with `Tools/probe-window-reopen.swift`. There is now also a
  **Window ▸ Vision Reader Window (⌘0)** command, the keyboard route back that
  never existed.
- **The command preview told two lies** (U14): it showed a plausible destination
  on a fresh install where Start was disabled, and it hard-coded the name
  `mac-ocr` while never mentioning the two further binaries the compression step
  shells out to — so the setting most likely to be wrong could not be checked
  against the panel that exists for checking settings.
- **"Not added — a run is in progress" outlived the run** (U14), and the Settings
  sheet could not fit on a short display (U15).
- **A folder could be set as the mac-ocr path.** `isExecutableFile` returns true
  for directories, so it validated, claimed to be in use, and then failed every
  file in the batch.
- **The log could not be got out of the app** — selection could not span lines,
  so extracting three failures from a 40-file log meant copying them one at a
  time. It also had no Copy button, and "Clear" wiped it along with the file
  list.

### Verification

- The suite went from 141 checks to 308, and now compiles the view sources so a
  UI-only break cannot pass a green run.
- Six paths that had no coverage at all now have it (T3): concurrent *searchable*
  batches, encrypted PDFs end to end, the non-rebuild route, `makeSearchablePDF`'s
  failure and cancel branches, `publish`, and colour pages. None of them turned up
  a new defect, which is recorded as plainly as a defect would be.
- Dead settings deleted rather than kept as a record of the CLI surface (H1):
  `ocrAllPages` and `strategy` were flags of a subcommand this app has never
  invoked, and a dead setting that looks live is a trap.
- A fixture finally satisfies invariant 5 — differing page sizes *and* rotation,
  through the real pipeline (T1). It took three attempts to make it actually
  detect the bug it exists for.
- `Tools/picture-signals.swift` measures the page production renders, not a
  different one (T2).
- [CONTRIBUTING.md](CONTRIBUTING.md) and a pre-commit hook now enforce the
  process — branch, failing test first, adversarial review — because **every
  review pass over this codebase has found real defects in code written during
  the previous one.** Three of the fixes above were regressions from other fixes
  in the same session, and a pass over the outline work found eight more in code
  written minutes earlier, including an unbounded recursion that could take down
  a whole batch.
- Planning is durable now: [TODO.md](TODO.md) for decided work and
  [FEATURES.md](FEATURES.md) for ideas with their costs and the reasons some are
  parked.

### Known limitations

- Annotations are not carried into the copy; outlines are. Deliberate — see R19.
- `mac-ocr` must be installed separately. `jbig2enc` and `qpdf` are optional and
  the app falls back silently without them, which also means a green test run on a
  machine lacking them means less than it looks.
- Four things could not be settled without a person in front of a running app:
  the keyboard tab order, how the VoiceOver announcements sound over a 78-file
  batch, whether the Settings sheet shrinks on a display shorter than about
  700 pt, and the reopen fix on the real app rather than the probe. Three of them
  were answered in 1.0.1.
