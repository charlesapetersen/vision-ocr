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

`FEATURES.md`'s two layout items were both built or measured and both refused, so
the feature backlog is down to item 7 (a watched folder or command line), which
nobody has asked for.

**1.11.0 is published** — released 2026-08-13 with a universal `Vision OCR.dmg`,
which the build's own verification exercised by mounting the image and running
every bundled helper under `env -i`, `visionocr-recognise --version` included.
`Updater.releasesAPI` now returns it, so users on 1.10.1 are offered the upgrade.

1. **Preserve annotations through re-OCR.** Newly promoted 2026-08-13 and
   specified below. **The library sweep is blocked on it**: 9% of the library
   carries a reader's own marks and re-OCR discards every one without a word, so
   the sweep either skips a tenth of the library or destroys somebody's
   scholarship. Neither is acceptable.

2. **The Zotero library sweep.** Explicitly the *last* thing, after all feature
   work, and probably its own session. Specified below. It was waiting on
   throughput, and throughput is now better than the figure it was waiting for.

## 1. Preserving annotations through re-OCR (decided, specified, not started)

Promoted out of `FEATURES.md` on 2026-08-13. That entry has the history and the
corpus counts; this is what to build.

### Why it is now blocking

Measured over a 1-in-16 sample of the library — 1,006 documents:
**91 carry a reader's own mark (9.0%), 4,903 marks in total**, the heaviest single
file holding 227. That extrapolates to roughly **1,400 files**. It matches the
corpus rate exactly (21 of 232, 9.1%), so it is a property of this library rather
than of a sample.

The rebuild drops every one of them. Until this exists, any file with marks has to
be excluded from the sweep by hand.

### What is already measured — do not re-derive these

1. **PDFKit is not the route, and this is now a number rather than an assertion.**
   `PDFDocument.write(to:)` over this app's own JBIG2 output inflates it:
   Hayek 35.42 → 144.68 MB (4.08x), Boltanski 24.38 → 82.89 (3.40x),
   Countryman 25.30 → 57.91 (2.29x), Schwaller 33.52 → 50.88 (1.52x). Text is
   preserved to the character, so the whole loss is size — and size is the entire
   point of the sweep. `FEATURES.md` recorded this as the blocker and was right;
   it was worth measuring because the *previous* blocker in that entry was wrong.

2. **qpdf is size-safe.** A plain `qpdf in.pdf out.pdf` round-trip of a
   25,565,129-byte JBIG2 output gives back **25,565,129 bytes**. The JBIG2 streams
   survive a qpdf rewrite — which is already why the pipeline can merge the text
   layer with `qpdf --overlay` *after* compression.

3. **qpdf's JSON is size-safe too, and is the editing surface.**
   `--json-output=2 --json-stream-data=file --json-stream-prefix=…` then
   `--json-input` reproduces the same 25,565,129 bytes. For a 203-page book the
   JSON is 437 KB with 820 stream files. qpdf therefore does the object plumbing,
   the streams and the xref — which is exactly the "substantial piece of
   hand-written PDF" that `FEATURES.md` called the cost, and it is not needed.

4. **No coordinate remapping.** Measured in the earlier investigation: 0 media-box
   mismatches, 0 rotation mismatches, 0 pages whose crop box differs from the
   media box. The rebuild preserves the page box exactly because
   `kCGPDFContextMediaBox` is set per page (invariant 4). Page *i* of the output
   is page *i* of the source.

5. Copying `/AP` directly should beat PDFKit on the case PDFKit failed — **stamps,
   20 of 121 refused**, because a stamp is nothing but its appearance stream.

### The mechanism

- `qpdf --json-output=2 --json-stream-data=file` over both the staged output and
  the original input.
- For each source page's `/Annots`, copy the **transitive closure** into the
  output's object table under fresh IDs: the annotation dictionary, its `/AP`
  (the `/N`, `/D`, `/R` sub-dictionaries and their form XObjects), each form's
  `/Resources`, and everything those reference.
- Rewrite every reference inside a copied object to its new ID.
- Append the new IDs to the output page's `/Annots`, creating it if absent.
- `qpdf --json-input` to rebuild.

### The hard parts, named so they are not discovered late

- **The closure must be transitive and cycle-safe.** `/Popup` points at an
  annotation that points back through `/Parent`. Track visited objects by source
  ID. A reference whose target was not copied must be **removed**, never left
  dangling.
- **Stream data lives in separate files** under `--json-stream-data=file`; a
  copied stream needs its file carried across and its `datafile` key repointed.
- **Object IDs collide between the two documents.** Renumber everything copied;
  never reuse a source ID.
- **`/P` (the annotation's page back-reference)** must point at the *output's*
  page object.
- **Do not copy `Widget`.** Form fields are not a reader's marks and they drag in
  the whole `/AcroForm` graph. A deliberate exclusion, and it must be reported.
- **`Link` is platform furniture** — 3,991 of the corpus's 4,867 annotations, left
  behind by JSTOR and ProQuest wrappers. v1 drops them, and says how many.

**v1 copies a reader's own marks and nothing else**: Highlight, Underline,
StrikeOut, Squiggly, Text, FreeText, Ink, Stamp, Square, Circle, Polygon,
PolyLine, Caret, FileAttachment. **Every annotation not copied is reported by type
and page** — invariant 1 applies to a reader's marks as much as to a line of text.

### The verification bar, which is the part not to cut

- **Count**: every mark of a copied type in the source appears in the output, per
  page. A shortfall fails the file and nothing is published.
- **Geometry**: each copied mark's `/Rect` matches the source's. The page boxes
  are identical, so assert *exact* equality and find out rather than allowing a
  tolerance that hides a systematic shift.
- **Rendered.** The pages carrying marks, drawn from source and from output at the
  same scale and compared. A highlight forty points low passes both checks above
  and misrepresents somebody's scholarship. This is the check that makes the
  feature defensible; without it, do not ship.
- **Size**: the output must still be smaller than the input, or the sweep has no
  reason to touch the file at all.
- A fixture carrying at least one of every copied type, **including a Stamp** —
  the case PDFKit could not do, and therefore the one most likely to be wrong.

### Where it goes

A step between `JBIG2.overlay` and `publish`, taking the staged file and the
original input. **It must be able to fail without failing the document**: if the
transplant cannot be verified, publish nothing and report it, because a file whose
marks were silently dropped is worse than a file left alone. For the sweep, an
unverifiable transplant means that candidate is skipped and listed.

Behind a setting, default off for ordinary runs — it costs two qpdf passes and
only matters when the input has marks — and forced on for the sweep.

### What would make this unnecessary

Nothing found. Unlike deskew and columns this is **not** waiting on a measurement
that might refuse it; the measurements above all say it is buildable. It is
ordinary work with an unusually high verification bar, because the failure mode is
misrepresenting a reader's own marks on a document that may not be re-scannable.

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

## 2. The Zotero library sweep (deferred, last — blocked on item 1)

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
