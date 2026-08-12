# Work queue

Known work that is worth doing, ordered by what it protects. Defects live in
[BUGS.md](BUGS.md); speculative ideas live in [FEATURES.md](FEATURES.md). This
file is for work that is *decided* but not done.

Move an item to done by deleting it and recording the evidence in the commit and,
if it was a defect, in `BUGS.md`. An item that has sat here through two sessions
without being started should be re-examined: either it matters and should be
promoted, or it does not and should be deleted.

---

**The VoiceOver announcements have now been heard** (2026-08-09) and they work —
the last item that could only be settled by a person at a real session. U16 is
closed in full, and `BUGS.md` U8 no longer has a remainder.

**Worth doing before the next release that touches `Flattener`** (added
2026-08-10, not started): re-run the 255-document library end to end and diff the
outcome against 1.7.0's — 255/255, 12.6M characters, 15 colour documents, peak
3.35 GB. The harness pattern is in `HANDOFF.md`; it takes 23 minutes and is the
only check that covers what the suite cannot. Nothing else here is code work.

**This file is otherwise empty of code work.** The 1.0 punchlist is closed (BUGS.md C16,
R21, R22, T3, H1, U13–U16), and the three interface questions that could only be
answered by a running app have been answered — in a headless VM, off-screen. They
passed, and the run found U17, which was worse than any of them.

## Out of the full-corpus gate run (2026-08-12)

The gate ran: **232 documents, 232 succeeded, 0 failed, 232 outputs**, 34.2M
characters, 23 documents carrying colour, **1,198 MB in → 1,039 MB out**, 78
minutes at concurrency 6. Nothing dropped, nothing failed — which is what the
gate exists to establish.

It also surfaced work. **None of the following is done.** The fix in the first
item was written, validated against the corpus and then reverted deliberately,
so what is below is a specification rather than a diff.

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

8. [ ] **R35, second attempt** — a per-page background factor that works. See
       FEATURES.md for what failed and the three untried signals; the
       `Flattener.largestImage` one sidesteps the failure mode rather than
       tuning around it. Review and release separately if it lands.

**Declined this session, with reasons recorded:** PDF/A, Direct Vision, a 6x
Photo detail level, cross-column hyphen joining, JPEG 2000 for picture pages
(R34), OpenJPEG for the background layer (R36).

## Smaller, and genuinely optional

- [x] **The tab order was walked on 2026-08-12** and it is sound: 22 stops
      through the settings sheet in visual order — Recognition, Searchable PDF,
      Behaviour — no trap, no unreachable control, and the four new preset
      buttons land where they read. Done locally by pressing Tab and reading
      `AXFocusedUIElement`, which needs no VM and no pixel diffing.

- [ ] **What that walk could not settle: whether the controls are named for
      VoiceOver.** Three different attribute reads gave three different answers —
      AppleScript's `description` returns the *role* description, `AXDescription`
      is absent on the toggles, and `AXAttributedDescription` came back while the
      probe was visibly failing to advance focus. So the question is open, not
      answered in either direction, and it should not be recorded as either.
      This is what the VM harness exists for, or a person with VoiceOver actually
      running for two minutes. Do not trust a scripted read of it: this file
      already records three instruments that lied about the interface, and this
      would have been a fourth.

- [ ] **The tab-order walk is still by hand.** `Tools/vm-gui-check.sh` covers
      U13, U15 and U17 — nine checks, one command. The tab order is not in it:
      it needs `AppleKeyboardUIMode` set in the guest and reads focus rings out
      of pixel diffs between captures, which is a lot of machinery for a property
      that changes only when the view hierarchy does. Worth adding the next time
      the layout moves.
