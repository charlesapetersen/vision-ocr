# Work queue

Known work that is worth doing, ordered by what it protects. Defects live in
[BUGS.md](BUGS.md); speculative ideas live in [FEATURES.md](FEATURES.md). This
file is for work that is *decided* but not done.

Move an item to done by deleting it and recording the evidence in the commit and,
if it was a defect, in `BUGS.md`. An item that has sat here through two sessions
without being started should be re-examined: either it matters and should be
promoted, or it does not and should be deleted.

---

## Two standing decisions, 2026-08-14

- **No release until more of the recorded bugs are fixed.** 1.13.0 is deferred by the owner;
  R59's `publish` fixes ride along with whatever ships next rather than going out alone.
- **The annotation feature is held for more work** — see item 2 below. Off by default on `main`,
  unadvertised. **The A8.1 test is now done** (`BUGS.md` T13, and its mutant would have survived
  a green suite of 1,031 before it). The third adversarial review round is still outstanding, and
  `score-annotations` only became trustworthy on quarter-turned pages in T12 — which is the
  instrument that round needs.

## Start here

**[HANDOFF-2026-08-15.md](HANDOFF-2026-08-15.md)** first — what the overnight run fixed, what is
left in dependency order, and why the release was not cut. Then
**[HANDOFF-2026-08-14.md](HANDOFF-2026-08-14.md)** for the sweep's original fix order, the
environment traps, and the three invariant-3 instruments that cannot be trusted.
`REVIEW-2026-08-14.md` is the evidence behind both. None of the three is superseded by anything
below.

### Where the fix order got to

**Twenty-three of the sweep's findings are fixed and merged, and the suite is at 1037 checks.**
The list is in **[HANDOFF-2026-08-15.md](HANDOFF-2026-08-15.md)** — read that rather than a
summary here, because a summary in this file is what went stale twice in two days.

*(It said "Five of its top items are done… 916 checks" for most of 2026-08-15, written when that
was true and left behind by the fifteen commits after it. Before that, an earlier draft said R60
was merged when it was committed on an unmerged branch, and that R61/R62 were committed when they
were staged in a worktree under `/private/tmp`. **Ask git, not this file.** Both corrections are
in the hand-off, which is also where the list of things this project's own controls caught lives.)*

**What is left is three groups, and the first gates the third:**

1. **`A6.1` — the invariant-3 instruments.** Three of the four are compromised and the
   re-measurement procedure is **not executable as written**: two probes want a JSON shape
   nothing in `Tools/` produces any more, and `score-corpus` prints `OK` for a document it
   measured nothing on. Nothing in the text layer can be trusted until this is repaired.
2. **The rest of `Tools/`** — `A12.2` (four `manifest.tsv` rows describe a pipeline nothing
   runs), `A12.3` (`score-mrc`'s tone layers are 14–17x, which affects `FEATURES.md`'s 4.96x),
   `A12.4` (the corpus gate re-implements `pageIsAnImage`), and the rest of `A12.8`.
3. **`A1.2`, then `A1.1`, then `C23`** — that order, because A1.1's only viable fix triples the
   sliver population A1.2 is about. Plus `A1.3`, `A1.4`, `A2.4`, `A3.1` in its narrower form.

**`C23` is the release blocker**, and the only open finding with harm a user sees today: every
rebuild route publishes with no `/CropBox`, so the copy displays what the original hid — 14 of
233 documents, 577 of 16,987 pages, worst case a third of the sheet. Whether to ship the
twenty-three fixes without it is the owner's decision; the hand-off sets out both paths.

## What is actually left

**One thing, and it is not an optimisation: a shape signal for the picture detector.**
`FEATURES.md` has it. Everything else in the feature backlog is either shipped or
refused with its numbers, and **two open defects now depend on that one signal** — R56
(a pale drawing erased by the 1-bit route) and R57 (a tonal plate blobbed by it). It also
unblocks three things already refused for want of it: R35's per-page background factor,
R49's paper detector, and item 1 below.

**1.12.0 IS released** — tag `v1.12.0` at `0dcca38`, a universal `Vision OCR.dmg`, and a
GitHub release published 2026-08-14T01:56Z. This paragraph said the opposite for most of
a day, and the claim was repeated without being checked; `git tag | tail` reads
*lexically*, so v1.10.0, v1.11.0 and v1.12.0 sort **before** v1.4.0 and a tail shows none
of them. Ask the forge, not the prose. What it carries is R49 — a 568-page scan going in
at 31 MB and out at 437 MB, because colour was the one page kind that could not be
layered — and **R50**, which closed the rest: the file lands at **35,379,516 bytes, 1.13x
its original, down 12.4x**, with a byte-identical text layer and no setting to choose. The
232-document gate is **721 MB against 792 at 1.11.0**, 232 of 232, 209 documents
unchanged, none larger.

**1.11.0** was released the same day with a universal `Vision OCR.dmg`, which the
build's own verification exercised by mounting the image and running every bundled
helper under `env -i`, `visionocr-recognise --version` included.

**The order, agreed with the owner 2026-08-13 after 1.12.0's work:**

1. **Move `isPicture` after recognition — MEASURED AND REFUSED FOR NOW, 2026-08-13.**
   Not on its prize, which is real, but because building the instrument for it found
   **two content-destroying defects in the shipped routing** (`BUGS.md` R56 and R57),
   and this optimisation would make the worse of them more common.

   **The prize, measured, and TODO's own two numbers were wrong.** This entry said
   "about 4 MB over its original" while the old specification below said "a text page
   routed to 1-bit costs 44 KB where a layered one costs 46" — implying ~1 MB. Neither
   was measured at the published stage. `Tools/score-text-route.swift` now does, using
   `mrcLayers` for one route and Black & white `flatten` for the other, both shipped
   code. On `Blacks in the City`:

   | page | inkOutsideText | layered | 1-bit | delta |
   |---|---|---|---|---|
   | 41, 163, 244 (text) | 0.0000 | 45–54 KB | 38–46 KB | **−8.2 KB/page** |
   | 78, 300, 301, 303 (plates) | 0.971–0.993 | 88–109 KB | 7–15 KB | −81 to −97 KB |

   So **8.2 KB a page**, or ~4.3 MB over that book's 522 text pages — 12% of the
   finished file. The "44 vs 46 KB" line was simply stale; the stencil barely grows,
   so nearly the whole tone-layer cost is saved. The prize is worth having.

   **Why it is refused anyway.** The plate rows above are the hazard in plain sight:
   1-bit is 8x smaller there *because it destroys the photogravure*. The whole feature
   therefore rests on the discriminator, and it would use `inkOutsideText`, **whose two
   recorded misses are both pictures read as text** — a pale line drawing at 0.0000 and
   a flat mid-luminance plate at 0.0365. Under R50 those misses cost sharpness. Under a
   routing change they cost the picture. R56 is that miss, rendered: a pale drawing is
   **erased** by the current 1-bit route, and this optimisation would send more pages
   down it. Trading a latent content-destruction defect for 8.2 KB a page is the wrong
   way round.

   **What unblocks it** is R56, and R56 converges with R57 on one unbuilt instrument:
   shape, not luminance. A luminance signal for the blind zone was built and refused
   over four rounds — the numbers are in R56 and the estimator is in
   `Tools/score-threshold-loss.swift` with a self-test, so round five starts from
   round four. Once a page can be told to carry no picture *structurally*, this
   optimisation is a small change on top of it and should be taken.

2. **Preserve annotations through re-OCR — BUILT, VERIFIED, AND HELD FOR MORE WORK
   (owner decision, 2026-08-14).** It stays on `main`, off by default, and is **not** advertised
   in a release until it has had a **third adversarial review round** — rounds one and two each
   found marks landing in the wrong coordinate space. **The A8.1 test is done** (T13): two runs of
   the real `makeSearchablePDF` over one marked-up scan, and a mutant that unwires the guard is
   killed by them. The review round is the one precondition left. Do not treat it as done.
   `Sources/Annotations.swift`, behind *Keep highlights and notes* (off by default),
   between the outline step and `publish`. The full verification bar was met on
   `Hyman_2012_Rethinking the Postwar Corporation`, which is the document the
   specification cited for the case PDFKit could not do: **121 of 121 marks carried,
   including all 20 stamps**, every `/Rect` exactly equal, **0 of 121 moved** by
   `Tools/score-annotations.swift`, and 2.57 MB out against a 3.50 MB original. 15
   checks in the suite. **The sweep's annotation block is lifted.**

3. **Clickable footnote and endnote links.** `FEATURES.md` has it, recorded
   research-first. Deliberately *after* annotations: it is the same `/Link`-annotation
   object-graph plumbing, and doing it first means writing that twice.

4. **The Zotero library sweep.** Explicitly the *last* thing, after all feature work,
   and probably its own session. Specified below. Fix `BUGS.md` R54 before step 2
   reads the survey's per-type numbers.

**A watched folder or command line is dropped** — 2026-08-13, at the owner's
direction. It was `FEATURES.md` item 7 and nobody had asked for it.

**VoiceOver is closed** — 2026-08-13, at the owner's direction. Every control carries
a name and the one omission (the Photo detail picker) was fixed on 2026-08-12 with a
scanner that holds it; the suite now also refuses two controls sharing a name (U29).
What was never done is *hearing* it in the VM, and that is accepted rather than
outstanding.

## One document added to the corpus by hand — done 2026-08-13

*Why?*, anon., 1954, National Foremen's Institute — a pamphlet whose subheads and
cartoons are printed in **red ink**, requested by the owner as a test case for the
decision R49 and R50 both turned on: colour on paper that is not a photograph. The
corpus had no document of that kind that anyone picked deliberately. It is in as
`testdocs/book/1954 - Why.pdf` (attachment key `9232Z7B5`), **outside** the
stratified draw — its `book`/`old` bucket already held its 9 — and
`testdocs/README.md` says so.

It earns its place. Measured on its sampled pages, a text pamphlet routes to the
**picture** path on three of four, two different ways:

| page | ink | tone | sat | routed |
|---|---|---|---|---|
| 2 | 0.276 | 0.192 | **0.178** | picture, kept in **colour** |
| 6 | 0.094 | **0.164** | 0.043 | picture, greyscale |

The red ink alone clears `pictureSaturationThreshold`; the scan's 111 DPI, where
type is mostly anti-aliased edge, clears `pictureToneThreshold`. `score-corpus`:
`OK 3p start=99% end=99% off=-0.10 overlap=0/21 words=100%`, which moves no median
and no worst case. **The corpus is 233 documents; every byte and character total
quoted anywhere else is a 232-document figure and stays labelled as one.**

**It failed the gate, and the gate was wrong — `BUGS.md` R55.** `classify-source`
called it `photographed` on a 0.169 illumination gradient against a 0.16 threshold.
It is an upright-scanner capture: the gradient is a diagonal ramp that is the *same
on every page* to within 1.5 luminance levels, which is a fixed lighting rig and not
a pair of hands. **The owner narrowed the categorisation on 2026-08-13 — only
hand-held photographs are `photographed`** — and ruled this one a scan.

### What R55 leaves to do, and it is not small

The gate decides what the corpus and the sweep may contain, so this is not a
one-document curiosity:

- **Measure the consistency discriminator before touching the threshold.** A rig
  repeats and hands do not, so the per-page *agreement* of the gradient is the
  signal the owner's definition actually wants — not its size. Deskew and columns
  were both refused on measurement; this gets the same treatment, over known
  hand-held material (Random Photograph, 186 files, FineReader-made) against known
  mechanical material, before `classify-source` changes.
- **Then two populations need re-reading, not re-assuming.** `sample-zotero.py`
  keeps only `scanned`, so no upright-scanner material has ever been drawn into the
  corpus; and the survey's **1,001 `photographed` files** — the 815 Robinson-Montana
  and 186 Random Photograph — are outside the sweep on that verdict.

## 1. Preserving annotations through re-OCR — DONE 2026-08-14

Built as specified, with three deviations worth naming, and the specification is kept
below because its verification bar is the reason the feature is trustworthy.

**Deviations from the spec as written:**

- **`/Line` was added to the copied set.** It was missing from the list here, between
  `/Polygon` and `/PolyLine`, and the omission reads as accidental: an arrow drawn
  beside a paragraph is a reader's mark by any reading of the phrase.
- **`/Rect` can be an indirect reference**, which the spec did not anticipate and which
  the first implementation got wrong — two of fourteen annotations on page 11 of the
  spec's own example document carry theirs as `890 0 R`. The count check caught it (14
  found against 12 expected) because the unreadable ones were copied without being
  recorded. A rectangle that cannot be resolved now **fails the document** rather than
  being skipped, and `Annotations.resolvesIndirectRectangles` pins the resolver.
- **The rendered check compares centroids, not coverage.** A `/Highlight` is
  Multiply-blended, so its footprint legitimately shrinks over a 1-bit rebuild — the
  glyph pixels under it are pure black there and Multiply leaves them unchanged, where
  on the grey original their anti-aliased edges shift. Measured: 14 highlights at
  0.41–0.54 against 0.54–0.71, all correct. Comparing coverage called a perfect
  transplant a failure; comparing where the mark's ink sits does not. Opaque marks
  agreed to three decimals throughout.

**What it measured, on the spec's own example:** 121 of 121 marks carried including all
20 stamps, every rectangle exactly equal, 0 of 121 moved, 15 pages unchanged, 2.57 MB
against a 3.50 MB original.

**Still true and worth knowing:** transplanting twice carries the marks twice. The
transplant is defined against the original and cannot tell a mark it is about to copy
from one already copied, so the pipeline calls it exactly once per staged rebuild. A
test pins the number rather than leaving it to be discovered by a sweep that retries in
place.

### The specification, as written before it was built

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

## 2. The Zotero library sweep — step 1 done 2026-08-13, steps 2-4 pending

### What the survey found

`Tools/sweep-zotero.py` over the whole library, read-only. **15,901 attachments**:

| verdict | files |
|---|---|
| scanned | 9,106 |
| born-digital | 5,679 |
| photographed | 1,001 |
| no page image / unreadable | 115 |

Per-page cost, median over each kind: **scanned 83 KB/page** (36.3 GB across 9,106
files), **born-digital 23 KB/page** (9.3 GB across 5,679). Born-digital files are
*not* candidates at any size — re-OCR would replace good text with worse — but
they were measured because the size question was asked, and a handful are
extraordinary: five sit above 1.4 MB/page, the worst a 3-page document at
2,960 KB/page. Those are image-heavy exports, not scans, and want a different
tool.

Per-page median by item type, over scans only, is in the log; it ranges from
newspaperArticle at 286 KB/page down to thesis at 40.

**1,164 re-OCR candidates** — scanned, ≥3x their own item type's median, and
≥150 KB/page. They hold **11.6 GB** and would give back roughly **10.0 GB**. The
extremes are single-page newspaper clippings scanned at absurd resolution: the
worst is one page at 50 MB, 341x its type's median. By page count: 166 are 1 page,
653 are 2–10, 304 are 11–100, 41 are over 100.

### The split that decides the order

**108 of the 1,164 candidates carry a reader's own marks — 9.3%**, the same rate
as the library at large and as the corpus. So the sweep is **not** blocked in
full, only in part:

- **1,053 files, 10.2 GB held, ~8.9 GB reclaimable** — safe to sweep as soon as
  the mechanics of step 3 exist.
- **111 files, 1.3 GB held, ~1.1 GB reclaimable** — must wait for item 1.

*(That split was computed by matching basenames, and Zotero storage can hold the
same basename under two keys; the 108/111 discrepancy is roughly three such
collisions. Match on the full path when it matters.)*

### Robinson–Montana: archived and deleted — done 2026-08-13

**Complete. Do not re-propose it.** 668 items exported with Zotero's own
*Zotero RDF + Export Files*, packed as a 3.95 GB zip with a restore guide, a
field-level provenance dump and SHA-256 sums, and moved to cloud storage.
**666 items and 681 files then deleted from the library — 3.98 GB freed.** The
owner kept two by choice; both are in the archive as well.

Three things from it worth carrying:

- **The re-import was tested, not assumed** — imported into a throwaway Zotero
  library with its own data directory: 668 items, all types matching, 163 notes,
  **0 field values lost**, archival provenance intact. Collection membership does
  not survive a flat RDF import (230 collections), which is what the provenance
  dump is for.
- **Zotero's local API cannot do this.** Its `rdf_zotero` carries rich metadata
  but **no file references at all**, so an archive built from it would restore as
  records and empty stubs. The GUI exporter is the only faithful route.
- **`cp -al` plus an in-place write silently corrupts the source.** Staging the
  archive with hard links and then doctoring a manifest in a test copy rewrote the
  staged original through the shared inode, and the shipped zip carried a manifest
  whose every path read `/nonexistent/deleted-library/…`. The round-trip test
  *passed*, because the fake paths tripped the "originals are gone" fallback added
  an hour earlier, which verified by hash and reported success. **A safety net
  masked the defect it sat beside.** Caught only by diffing the zip against the
  working copy; the rebuild now asserts that equality before zipping.

### The photographed material splits cleanly in two

1,001 documents, 5.09 GB, and they are **not one population**. Split by when they
entered Zotero, which the PDF metadata confirms is also a split by *workflow*:

| | Robinson-Montana | Random Photograph |
|---|---|---|
| files | **815** | **186** |
| size | **4.18 GB** | **0.92 GB** |
| pages | 7,513 (median 4) | 2,308 (median 5) |
| per page | 583 KB | 416 KB |
| **unsearchable** | **801 (98%)** | 52 (28%) |
| added | 2013–14 only | 2015–2025, spread |
| made by | Acrobat 11 image conversion (560), ImageMagick 6.7.1 (88) | FineReader (100) |
| types | document 328, letter 191, book 137, journalArticle 121, manuscript 20 | book 53, journalArticle 52, document 29, newspaper 21 |

**Robinson-Montana** is one archival campaign: two years, one bulk image→PDF
pipeline, archival types (document, letter, manuscript), 26% of it undated, and
**98% of it cannot be searched at all** — 801 files, 4.14 GB. The long captures in
the library are all here: Cox Letters at 149pp, Robinson's correspondence at 122pp
twice, his notes at 112 and 99.

**Random Photograph** is what the name says — occasional captures over a decade,
mostly of *published* material (book and journalArticle excerpts, median 5 pages),
and **72% of it already has a text layer**. It is a much smaller opportunity.

Manifests: `robinson-montana-material.txt` and `random-photograph-material.txt`
beside the survey.

**Neither is a sweep candidate** — the sweep is about scans that are oversized for
their type, and these are excluded by the classifier by design. They are recorded
here because the survey found something the sweep was not looking for: **4.14 GB
and ~7,400 pages of a historian's archival photography that is invisible to
search.** That is a bigger prize than the 10 GB of disk the sweep reclaims, and it
is a different piece of work.

**Before anyone starts it, one honest gap**: every accuracy figure this project
quotes was measured on *scans*. `classify-source` excludes photographed material
from the corpus deliberately (D1), so there is **no measurement** of how this app
performs on hand-held photographs under archive lighting — and deskew, which would
have been the obvious lever, is refused. OCR a dozen of the Robinson papers and
look at them before committing to 801.

### Where the artifacts are

**Not in this repo** — they are paths into a private library and this repository
is public. `~/Claude/vision-ocr-sweep-2026-08-13/`: `survey.tsv` (all 15,901 rows),
`survey.log`, `candidates.txt`, `candidates-with-reader-marks.tsv`. Re-runnable
with `python3 Tools/sweep-zotero.py` in about 50 minutes.

### Steps 2-4, still to do

Step 2 is the review with the owner — done for the aggregate, not for the list.
Steps 3 and 4 are below and **nothing has been written to the library**.

## The original specification (steps 3 and 4)

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

2. [x] **Settle whether the controls are named for VoiceOver — done 2026-08-12**,
       and **closed as a question 2026-08-13** at the owner's direction. It is
       answerable from the source and was: one control was unnamed, the Photo detail
       picker, and it was fixed. Listening to it in the Tart VM was never done and is
       now accepted rather than outstanding. This entry said "then review and
       release" and outlasted two releases saying it, which is the shape of stale
       bookkeeping worth noticing.

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

- [ ] **The tab-order walk is still by hand.** *(Accepted 2026-08-13 with the rest
      of the VoiceOver question; left here because it is a real gap, not because it
      is queued.)* `Tools/vm-gui-check.sh` covers
      U13, U15 and U17 — nine checks, one command. The tab order is not in it:
      it needs `AppleKeyboardUIMode` set in the guest and reads focus rings out
      of pixel diffs between captures, which is a lot of machinery for a property
      that changes only when the view hierarchy does. Worth adding the next time
      the layout moves.
