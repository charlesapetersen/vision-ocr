# Work queue

Known work that is worth doing, ordered by what it protects. Defects live in
[BUGS.md](BUGS.md); speculative ideas live in [FEATURES.md](FEATURES.md). This
file is for work that is *decided* but not done.

Move an item to done by deleting it and recording the evidence in the commit and,
if it was a defect, in `BUGS.md`. An item that has sat here through two sessions
without being started should be re-examined: either it matters and should be
promoted, or it does not and should be deleted.

---

## What is actually left, as of 1.10.0

**Nothing open in `BUGS.md`.** What is left here is **one question that needs a
person** — whether the controls are named for VoiceOver — and **one feature
cycle**, R35's second attempt. Everything else is closed, and the closed items
are kept with their reasoning rather than deleted.

**Superseded, and worth saying so rather than quietly dropping.** This file used
to open with "re-run the 255-document library and diff against 1.7.0's figures".
That set cannot be reconstructed (Zotero holds 16,079 PDFs) and the baseline is
now the 232-document `testdocs` run through `Tools/score-gate.swift`, recorded in
`HANDOFF.md` with both columns. It also used to say the file was "empty of code
work", which R39 made false for as long as R39 was open.

**The VoiceOver announcements have been heard** (2026-08-09) and they work — U16
is closed in full and `BUGS.md` U8 has no remainder. That is *announcements*;
whether the individual controls carry names is the separate open question below.

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
