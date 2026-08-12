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

- [ ] **R38 — dense bilevel type is routed to the picture path and inflates
      catastrophically.** Four documents come out *bigger*: `Boltanski_2006`
      **16 MB → 156 MB (9.45x)**, `Noble_1977` 17 MB → 87 MB (5.0x),
      `_1950_Comic` 3.48x, `_1926_Clapp` 3.20x.

      *Cause.* Boltanski's source stores each 47 MP page as bilevel JBIG2 at
      ~150 KB. Our output gives those pages a JBIG2 stencil **plus** a 13 MP
      greyscale DCT background at ~1.7 MB, carrying nothing the stencil does not
      already have. They reach the picture route on **ink coverage alone** —
      0.26 against the 0.15 threshold — while the other two signals say text
      emphatically: tone 0.013, saturation 0.0000. `isPicture` ORs its three
      signals, so one overrides two.

      *Fix, validated but not applied.* Require corroborating tone before ink
      alone counts: add `pictureInkMinimumTone` (0.03) and gate the ink branch
      on it. Measured separation across the corpus's ink-triggered pages — real
      pictures **0.071–0.145** (Findlay's photograph, Black, Ehrenreich, Marth),
      dense bilevel type **0.0017–0.0247** (all four inflating documents). The
      threshold sits in the gap. Confirmed by re-running the classifier: those
      four move to 1-bit, the picture pages all stay pictures.

      *Why it is safe, checked rather than argued.* The picture route exists
      because thresholding destroys an **unresolved** halftone. Low tone means
      the page is genuinely bimodal, which is exactly when 1-bit is lossless.
      The two riskiest pages — a newspaper comic and a title spread — were
      rendered at 1-bit and are clean. Boltanski's 96%-ink cover keeps its
      picture routing (tone 0.0527) either way.

      Wants: failing test first, a mutant on the new constant, a corpus re-run
      confirming those four shrink and nothing else moves, and a `BUGS.md`
      entry.

- [ ] **R37's scale is wrong and should be corrected in the same pass.** It says
      "134.3 MB in, 75.0 MB out, 1.79x" and "15 of 40 grew". That was a
      `head -40` of a `find`, not a sample. The full corpus is **1.15x**, with
      **91 of 232 grown (39%)** and a worst case of 9.45x rather than 2.26x. The
      entry's *diagnosis* — symbol-mode JBIG2 in the inputs — still holds for the
      cases it examined. Its scale does not, and R38 is a second and larger cause
      it missed.

- [ ] **Decide what the baseline is.** The 1.7.0 figures come from a
      255-document library set that cannot be reconstructed from the repo
      (Zotero holds 16,079 PDFs). Either adopt the 232-document `testdocs` run
      as the new baseline and record it in `HANDOFF.md`, or rebuild the 255 from
      `testdocs/manifest.tsv` and `Tools/sample-zotero.py` first. Until then,
      "23 minutes" and "78 minutes" are not comparable and neither are the
      character counts.

- [ ] **Promote the concurrent gate harness into `Tools/`.** A serial loop over
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

1. [ ] **Finish the full-corpus gate.** A 232-document run through
       `OCRModel.makeSearchablePDF` was started and did not finish before the
       session ended; the harness is `scratchpad/big/main.swift`, rebuilt with
       the usual `Tools/` pattern, and it prints succeeded/failed, characters,
       colour documents and bytes.
       **It is 232 documents from `testdocs`, not the 255-document library set
       the 1.7.0 figures come from** — that set is not reconstructable from the
       repo (Zotero holds 16,079 PDFs), so the numbers are comparable in kind
       and not directly diffable. Either accept that and record a new baseline,
       or reconstruct the 255 from `testdocs/manifest.tsv` and
       `Tools/sample-zotero.py` first. This is the gate 1.8.0 and 1.9.0 both
       shipped past.

2. [ ] **Settle whether the controls are named for VoiceOver**, then review and
       release. See the open item below — use the Tart VM (`archive-gui-runner`,
       present and stopped) and `Tools/vm-gui-check.sh`, not a scripted
       accessibility read from the host.

3. [ ] **Per-page DPI control for picture pages.** FEATURES.md has the entry and
       BUGS.md R13 the constraint: it becomes worth doing as an *explicit
       setting* with a measured default and a clear label, never as a default
       behaviour.

4. [ ] **A written run report.** The log is in-memory and dies with the window.
       Cheapest item here and every later bug report improves because of it.

5. [ ] **Recognition language picker** populated from `mac-ocr languages`, which
       the app never calls, instead of hand-typed BCP-47 codes.

6. [ ] **Retry the failures from a finished batch.**

7. [ ] **Preserving annotations.**

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
