# Work queue

Known work that is worth doing, ordered by what it protects. Defects live in
[BUGS.md](BUGS.md); speculative ideas live in [FEATURES.md](FEATURES.md). This
file is for work that is *decided* but not done.

Move an item to done by deleting it and recording the evidence in the commit and,
if it was a defect, in `BUGS.md`. An item that has sat here through two sessions
without being started should be re-examined: either it matters and should be
promoted, or it does not and should be deleted.

---

## What is actually left

Two pieces of work, in this order, both decided with the user:

1. **R40 — put recognition in a pool of helper processes.** The only thing
   standing between `main` and a 1.11.0 release. Specified below.
2. **The Zotero library sweep.** Explicitly the *last* thing, after all feature
   work, and probably its own session. Specified below.

**One question still needs a person and does not block either**: whether the
controls *sound* right under VoiceOver. That no control is anonymous is settled
and guarded by a check; hearing it is not the same claim.

## 1. R40 — recognition in helper processes (decided, not started)

`BUGS.md` R40 has the measurements. The short version: **Vision does not
parallelise across concurrent requests inside one process** — 1.08x at six
threads on thirty-six page images — so the ~3x that batch concurrency used to buy
came from mac-ocr being one process per file. The corpus gate is 187 minutes
against 75, with correctness unchanged.

**What to build.** A small helper executable, ours, bundled beside `jbig2` and
`qpdf`. It takes a page bitmap and the recognition settings, and returns
observations. `Recogniser` keeps its current API and grows a pool of N helpers,
N being the existing `Prefs.concurrency`.

**Why this is not a return to mac-ocr**, and the distinction is the whole point:

- It is handed a **bitmap we rendered**, not a PDF. Nothing re-rasterises
  anything, so R39 cannot come back and `recogniserDPICeiling` stays deleted.
- The protocol is ours, so the quads and per-word boxes
  (`VNRecognizedText.boundingBox(for:)`) that the CLI never exposed remain
  available — which is what the text layer wants next.
- It is a pure function: image in, observations out. No streaming, no progress
  parsing, no cancellation mid-stream. The subprocess bug class that produced C6,
  R2, R3, R16, R17, R21, R22, U18 and R30 is mostly about the *long-running
  streaming* child, and this is not one.

**What it must keep from what exists.** The in-process path stays as the fallback
for a single file and for when the helper cannot be found, because a missing
helper must degrade rather than fail (the JBIG2 route's precedent). The settings
enumeration check must cover the helper's argument encoding the way it now covers
the request. `Runner.captureBounded` is the bounded-read to reuse rather than
writing a fourth copy.

**How to know it worked.** The gate, at 232 documents: characters and bytes must
not move from 34,204,971 / 792 MB, and the time must come back toward 75 minutes.
Measure with **nothing else running** — three of this session's timings were
polluted by a test suite or a mutation run sharing the machine, which is how the
1.7x was first mistaken for 2.5x and how a single-document comparison was
mistaken for "no regression" at all.

## 2. The Zotero library sweep (deferred, last)

Agreed 2026-08-12 as the final task, after all feature work, probably its own
session. The user's own library, 16,079 PDFs.

- **Find files larger than they should be** for their page count and item type.
  R37 and R38 are the background: symbol-mode JBIG2 in the *inputs* makes some
  sources tiny, and dense bilevel type used to inflate catastrophically. The
  measure wants to be per-page bytes against the item type, not raw size.
- **Re-OCR and replace those files**, moving the originals into a folder in
  `~/Downloads` for the user to check before anything is discarded. Nothing is
  deleted.
- **Separate the photographed items from the scanned ones**, and produce a
  spreadsheet of those — name, item type, file size — for review rather than
  acting on them. `Tools/classify-source.swift` already exists for exactly this
  distinction and is what the corpus gate uses to keep photographs out.
- Throughput is why this waits for R40: at 1.7-2.5x, a library this size is hours
  of avoidable difference.

## Out of the full-corpus gate run (2026-08-12) — all closed

The gate ran: **232 documents, 232 succeeded, 0 failed, 232 outputs**, 34.2M
characters, 23 documents carrying colour, **1,198 MB in → 1,039 MB out**, 78
minutes at concurrency 6. Nothing dropped, nothing failed — which is what the
gate exists to establish. It also surfaced work, and that work is now done:

- [x] **R38 — done 2026-08-12.** `pictureInkMinimumTone` (0.03) gates the ink
      branch; `BUGS.md` R38 is `FIXED` and carries the evidence. The
      specification here said "four documents"; the sweep says **66 of the 98
      ink-only picture pages across the corpus flip**, `Noble_1977` entirely and
      `Boltanski_2006` but for its two covers. Six pages spanning the risk space
      were compared at 1:1 before it landed.

- [x] **R37's scale was already corrected in `BUGS.md`** — the entry opens by
      saying the `head -40` figures were a biased sample and gives the
      full-corpus ones (1,198 MB → 1,039 MB, 1.15x, 91 of 232 grown, worst case
      9.45x). Nothing left to do here.

- [x] **Baseline decided 2026-08-12: the 232-document `testdocs` run**, recorded
      in `HANDOFF.md`. The 1.7.0 figures are kept as history and are explicitly
      not comparable — different corpus, and the 255-document set cannot be
      reconstructed. Superseded text follows for the reasoning.

- [x] ~~**Decide what the baseline is.**~~ The 1.7.0 figures come from a
      255-document library set that cannot be reconstructed from the repo
      (Zotero holds 16,079 PDFs). Either adopt the 232-document `testdocs` run
      as the new baseline and record it in `HANDOFF.md`, or rebuild the 255 from
      `testdocs/manifest.tsv` and `Tools/sample-zotero.py` first. Until then,
      "23 minutes" and "78 minutes" are not comparable and neither are the
      character counts.

- [x] **Promoted 2026-08-12 as `Tools/score-gate.swift`**, with the reasoning
      below in its header so nobody rediscovers it.

- [x] ~~**Promote the concurrent gate harness into `Tools/`.**~~ A serial loop over
      `makeSearchablePDF` projected **9.1 hours**; driving `OCRModel.start()` at
      the app's own concurrency did the same work in **78 minutes**. The serial
      version measures a configuration the app never runs and its timing number
      is worthless. Two things the harness must keep: `warnDigitalText` off, or
      the digital-text modal hangs a headless run forever; and reading the
      output PDFs at the end rather than trusting the outcome enum.

## The queue, in the order it was decided (2026-08-12)

Agreed with the user at the end of the 2026-08-12 session. Items 1–2 are gates on
the next release; 3–7 are the feature backlog promoted out of FEATURES.md; 8 is
its own cycle.

1. [x] **The full-corpus gate ran, twice** — once to establish the baseline
       (2026-08-12, before R38) and once against this release. The harness is
       `Tools/score-gate.swift`. Second run: **232 documents, 232 succeeded,
       0 failed, 232 outputs, 34.15M characters, 23 colour, 1,198 MB in →
       792 MB out (0.66x), 75 minutes.** Recorded in `HANDOFF.md`.

2. [ ] **Settle whether the controls are named for VoiceOver**, then review and
       release. See the open item below — use the Tart VM (`archive-gui-runner`,
       present and stopped) and `Tools/vm-gui-check.sh`, not a scripted
       accessibility read from the host.

3. [x] **Per-page DPI control for picture pages — declined 2026-08-12**, with
       the measurement in FEATURES.md. It would govern only 129 of the 449
       picture pages in the finished corpus; the other 320 are MRC pages whose
       resolution **Photo detail** already sets. Two settings for one property,
       disagreeing on 71% of the pages either appears to control. If picture
       pages should be smaller, that belongs in Photo detail.

4. [x] **A written run report — shipped 2026-08-12.**
       `~/Library/Logs/VisionOCR`, on by default.

5. [x] **Recognition language picker — shipped 2026-08-12**, and it found more
       than a convenience: an unsupported code fails every file in the batch,
       and Fast supports 6 languages against the accurate recognizer's 30.

6. [x] **Retry the failures from a finished batch — shipped 2026-08-12.**

7. [x] **Preserving annotations — investigated 2026-08-12, not shipped.** 21 of
       232 corpus documents carry a reader's own marks, so the case for it is
       real; the recorded blocker (coordinate remapping) is not — 0 box
       mismatches. The actual blocker is that `PDFDocument.write(to:)`
       re-encodes every JBIG2 stream. FEATURES.md has the numbers and the route
       a real attempt would take.

8. [x] **R35, second attempt — measured and refused 2026-08-12.** Re-measured
       after R38 on 320 layered pages (25 the first time): still a continuum,
       largest gap 0.027. A threshold at 0.10 looked safe until the pages it
       fires on were read — the largest saving is a photomicrograph of an
       integrated circuit scoring 0.0932, and 6x degrades it visibly. Tone is
       structurally blind to bimodal pictures. The prize is 0.55% of the corpus,
       bounded near 1% even for a perfect detector. `BUGS.md` R35 has it.

**Declined this session, with reasons recorded:** PDF/A, Direct Vision, a 6x
Photo detail level, cross-column hyphen joining, JPEG 2000 for picture pages
(R34), OpenJPEG for the background layer (R36).

## Out of 1.10.0, found after it shipped — closed

- [x] **R39 — done 2026-08-12.** Not the fix the entry proposed. Sending an
      explicit DPI was measured over 52 documents and 4,140 pages and is
      **worse** than Automatic at every value tried, including as a ceiling, and
      worse most clearly in the high-DPI band where it was predicted to win. The
      real defect underneath was that the ceiling could not bind on Automatic at
      all, because it was compared against an assumed engine default of 300;
      a 20x30 inch sheet at 600 DPI was handed to an engine that refuses it.
      Fixed, reproduced first, and **zero of 232 corpus documents change**, so
      the 1.10.0 gate figures still stand.

## Smaller, and genuinely optional

- [x] **The tab order was walked on 2026-08-12** and it is sound: 22 stops
      through the settings sheet in visual order — Recognition, Searchable PDF,
      Behaviour — no trap, no unreachable control, and the four new preset
      buttons land where they read. Done locally by pressing Tab and reading
      `AXFocusedUIElement`, which needs no VM and no pixel diffing.

- [x] **Settled 2026-08-12, and not the way it was framed.** The question was
      "are the controls named for VoiceOver", and it had defeated three runtime
      attribute reads. It is answerable from the source, which is not a scripted
      read of the interface: a control either carries a name or it does not, and
      only two constructs leave one without — `labelsHidden()`, which hides the
      label from VoiceOver as well as from the eye, and a `Button` whose label is
      a bare `Image(systemName:)`, from which SwiftUI derives nothing.

      **One control was unnamed: the Photo detail picker.** Every other picker in
      `SettingsView` carries a label; that one was an omission, not a decision.
      Fixed, with a check that scans both view files and requires every control
      of those two shapes to carry a name.

      **A second "finding" was mine, not the code's.** The per-file remove button
      was reported unnamed and was not — its `.accessibilityLabel` sits four
      lines below the ten-line window that was read, after `.disabled` and
      `.opacity`. That is the fourth instrument to mislead about this interface
      and the first one that was simply me not reading far enough. The scanner
      that replaced it attributes each modifier chain to its own control, which
      is what the ten-line window failed to do.

      **What this does not establish is how any of it sounds.** It establishes
      that no control is anonymous, which is the part that was in doubt. Hearing
      it still wants a person or the VM.

- [ ] **The tab-order walk is still by hand.** `Tools/vm-gui-check.sh` covers
      U13, U15 and U17 — nine checks, one command. The tab order is not in it:
      it needs `AppleKeyboardUIMode` set in the guest and reads focus rings out
      of pixel diffs between captures, which is a lot of machinery for a property
      that changes only when the view hierarchy does. Worth adding the next time
      the layout moves.
