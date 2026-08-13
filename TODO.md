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

1.11.0 is **tagged but not published**, which is the first item. After that:
`FEATURES.md`'s two layout items were both built or measured and both refused, so
the feature backlog is down to item 7 (a watched folder or command line), which
nobody has asked for.

1. **Publish the 1.11.0 release.** The tag exists; the GitHub release does not.
   This is not tidiness — `Updater.releasesAPI` polls
   `/releases/latest`, so until a release exists **every user stays on 1.10.1 and
   is never offered 1.11.0**, which is the version with the throughput fix in it.
   Every previous release carries a `Vision OCR.dmg` asset and this one should
   too: `./build.sh --dmg` (which implies `--universal`, and runs its own
   verification — it mounts the image and executes every bundled helper under
   `env -i`, including `visionocr-recognise --version`), then `gh release create
   v1.11.0` with the CHANGELOG entry and that asset. Needs the owner's say-so:
   it offers an update to everyone running the app.

2. **The Zotero library sweep.** Explicitly the *last* thing, after all feature
   work, and probably its own session. Specified below. It was waiting on
   throughput, and throughput is now better than the figure it was waiting for.

## The engine's competence is guarded — done 2026-08-13

Deskew and columns were both refused because **Vision** is good at them, not
because this codebase is: `compose` never sorts, so reading order is inherited
whole, and recognition is flat across ±3° with the quads tilting to match. Neither
was held by anything. Six checks now hold both, over a generated two-column
fixture rasterised once from vector at whatever angle is asked for:

```
ENGINE ASSUMPTION: Vision returns the left column before the right
ENGINE ASSUMPTION: no line is welded across the gutter
ENGINE ASSUMPTION: a 2° page reads about as well as a straight one
ENGINE ASSUMPTION: the reported quads tilt with the page
```

The skew band is loose (80%) on purpose — line grouping flips between
interpretations, so a real page read −2.73% at +2.0° and +0.08% at +3.0°, and a
flaky check here would be worse than none. Both were watched failing: reversing
the observations fails the ordering check, and planting 6° fails the quad check at
a median of 6.10°.

**They are named ENGINE ASSUMPTION and say "the app did not change" in their
failure detail.** If one goes red, re-open the `FEATURES.md` entry and re-measure
with `Tools/score-reading-order.swift` and `Tools/score-skew.swift`; do not go
looking for a defect in `SearchableWriter`.

## The gate that released 1.11.0 — done 2026-08-13

**232 of 232, 0 failed, 232 outputs, 34,204,948 characters, 23 documents carrying
colour, 792 MB out, 48 minutes at concurrency 6.** Run with `VISIONOCR_HELPER`
pointed at a built helper, and the harness said so in its second line — read that
line before believing any future run's minutes, because a gate without a helper
measures the 187-minute configuration and looks exactly like a fast one.

The bar was 232/232, bytes unmoved from 792 MB, and minutes back near 75. All met;
the time beat the baseline because the helper is handed a bitmap rather than a PDF,
so nothing re-rasterises what this app already drew. The 23-character shortfall
against the previous run is unexplained and recorded in `BUGS.md` R46.

## The old specification, kept for the commands

**R40 is fixed** — `Helper/main.swift`, bundled as `visionocr-recognise`, one
helper process per file, compiling the app's own `Recogniser.recognise` so the
observations are identical by construction. `BUGS.md` R40 has the design, the
measurements behind every choice in it, and what is deliberately *not* covered.
The suite is at **790 checks** and green, including exact parity between the two
routes on both a 1-bit page and a colour JPEG page.

**What is left is one run**, and it is the only claim not yet backed by a
measurement:

```sh
mkdir -p /tmp/h && cp Tools/score-gate.swift /tmp/h/main.swift
swiftc -O -o /tmp/gate -target "$(uname -m)-apple-macos13.0" \
  $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
swiftc -O -o /tmp/visionocr-recognise -target "$(uname -m)-apple-macos13.0" \
  Sources/{Prefs,Runner,Recogniser,SearchableWriter,Flattener,JBIG2}.swift \
  Helper/main.swift
VISIONOCR_HELPER=/tmp/visionocr-recognise /tmp/gate testdocs /tmp/gateout
```

**Read its second line before believing its minutes.** The harness now prints
whether the run will actually use helpers, because a gate without one measures
the 187-minute configuration and looks exactly like a 75-minute one.

**The bar:** 232 of 232, characters and bytes unmoved from **34,204,971 / 792 MB**
— those are correctness and must not move at all — and the minutes back near
**75** from 187. Run it with **nothing else on the machine**: three timings during
R40's diagnosis were polluted by a suite or a mutation run sharing it, and the
run was deferred on 2026-08-13 for exactly that reason (a backup and another
project's build were live).

If the minutes come back and nothing else moved, tag 1.11.0 and lift the banner
at the top of `CHANGELOG.md`.

**A measured follow-up this leaves on the table, deliberately.** Pages *within*
one document parallelise at 1.0x in-process but would parallelise across helper
processes just as files do — so a single large book, which today gets no helper
at all, could go ~2.2x faster by splitting its page list across N of them. It was
not built because it needs a bound on helpers shared across the whole batch,
where today the count is `Prefs.concurrency` by construction and needs no pool.
Worth doing only if someone is waiting on single big books.

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
