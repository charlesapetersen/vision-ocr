# Ideas not yet committed to

Things worth considering, with what each would cost and what would have to be
true to justify it. Nothing here is scheduled — [TODO.md](TODO.md) is for work
that is decided. An idea that survives here for a while and keeps looking good is
a candidate for promotion; one that keeps being deferred for the same reason
should be deleted along with that reason.

The bar for this project is unusual and worth restating: it processes
irreplaceable archival material, so **a feature that could plausibly damage or
misrepresent a document is not worth its convenience.** Several entries below are
parked for exactly that reason.

---

## The gap to commercial OCR, ranked

*(written 2026-08-12, at 1.10.0, after the queue agreed that day was closed.
Asked as: what would it take to be as good as ABBYY? Grounded in what this app
verifiably does not do — each absence below was confirmed by grep, not
remembered.)*

The honest summary first: **this app is not behind on rigour.** It is validated
against a 232-document corpus through the shipped pipeline, its text layer beats
the obvious alternative 99.8% to 64% on word retention, and its per-page routing
matches what ABBYY's own output does — measured from 275 MRC files in the user's
library, 52 of 60 sampled produced by FineReader, and *they route per page
exactly as this does*. The gap is not quality of engineering. It is **layout
analysis**, and secondarily image preparation.

**That summary was written on argument, and the argument did not survive
measurement.** Both of the layout-analysis items below — deskew and columns —
were built or measured on 2026-08-13 and both were refused by their own numbers:
correcting skew *loses* text at every angle, and Vision already returns
multi-column pages in reading order with 0.19% of observations crossing a gutter.
The remaining gap is the engine's recognition of degraded type, which is the one
thing listed here that no work in this repository can close. Read the entries, not
this paragraph.

**1. ~~Recover the text already being lost (R39).~~ DONE — shipped in 1.10.1.**
Left in place because the ranking below was written against it and because *how*
it closed is the useful part. It did not close the way this entry proposed:
sending an explicit recognition DPI was measured over 52 documents and 4,140
pages and is **worse than Automatic at every value tried**, and worst in the
high-resolution band where this entry predicted it would win. The 3,046-against-924
page was real and the diagnosis drawn from it was wrong. The actual defect was
underneath — the DPI ceiling could not bind on Automatic, because it was compared
against a constant the code's own comment wrongly described as the engine's
default. `BUGS.md` R39.

**2. ~~Deskew~~ — DECLINED twice, measured 2026-08-12 and again 2026-08-13.**
Ranked second here on argument; the argument was wrong in both halves, and when
the one surviving version of it was actually built and measured it lost text. It is left in place rather
than deleted because the reasoning is the same shape as the "Vision can't read
sideways text" episode in `HANDOFF.md`, where a whole feature was built for an
inferred weakness that a direct test disproved.

*First half: does the recogniser care?* Mostly not. Rendering the same page at a
range of angles — one sampling at the angle, drawn through a rotated CTM, so
there is no resampling on one side of the comparison and not the other:

| degrees | 0 | 0.25 | 0.5 | 1.0 | 1.5 | 2.0 | 3.0 |
|---|---|---|---|---|---|---|---|
| Merriam 1913, 300 DPI, clean | 4,677 | 4,756 | 4,835 | 4,671 | 4,722 | 4,662 | 4,499 |
| Newsday 1973, 300 DPI | 3,326 | 3,327 | 3,327 | 3,328 | 3,324 | 3,319 | 3,329 |
| Clapp 1926, 200 DPI newsprint | 2,746 | 2,494 | 2,111 | 2,047 | 1,967 | 2,286 | 2,541 |
| Creative 1928, 200 DPI | 12,243 | 11,475 | 10,195 | 11,454 | 10,689 | 10,850 | 11,841 |

Clean material is flat. Degraded low-DPI newsprint loses up to 28% — but in a
**U-shape that recovers by 3°**, which is Vision's line grouping flipping between
interpretations, not blur. (The first version of this measurement compared a
pixel-exact 0° copy against interpolated rotations and was measuring its own
interpolation.)

*Second half: how skewed is the corpus?* Barely. A projection-profile estimator,
which plants a known angle and checks it recovers it on every run, over 176 of
the 232 documents and 633 pages:

| pages | share |
|---|---|
| below 0.25° — no measurable loss | **89.9%** |
| 0.25–0.5° | 7.0% |
| 0.5–1.5° — the worst band | **2.8%** |
| over 1.5° | 0.3% |

Median page skew is **0.10°**, p95 is 0.36°, and the worst document in the corpus
is a single 1881 letter at 2.00°. These are library scans from flatbed and
planetary scanners, and they are already straight.

*So the prize is roughly 0.5–1% of corpus characters*, concentrated in about 3%
of pages, and against that:

- **The estimator failed its own self-test on 55 of 232 documents** — 24%. An
  estimator that cannot validate itself on a quarter of the corpus must not be
  allowed to rotate archival pages.
- A wrong estimate on a page that was straight moves it *out* of the 0.1° flat
  zone and *into* the 0.5–1.5° worst band. The failure mode of this feature is
  causing the exact damage it exists to prevent.
- Rotating the published page alters the user's document, which is R13's
  territory.

**The one version worth keeping in mind** sidestepped the third objection
entirely: deskew *only the image handed to the recogniser*, and publish the page
exactly as scanned. The user's document is untouched, so there is no fidelity
question at all — it becomes purely a question of whether the estimate is right,
and the answer then was "on 76% of documents".

#### That version was built and measured on 2026-08-13. It is refused too, and this time the estimator was not the problem.

Both objections that survived the first pass were answered, and the feature still
lost:

**A better estimator was built and validated.** `Tools/score-skew.swift` carries
it. Baseline points are the bottom pixel of each vertical ink run — which reduces
a photograph to its outline instead of letting it shout over the caption — and
the projection is a shear rather than a rotation, so no angle costs a resampling.
It abstains rather than guessing. Validated by planting angles **in the pixels**,
not in its own point cloud: over 40 attempts on corpus pages, **100% correct when
it spoke**, median error **0.020°**, worst 0.110°, abstaining on 5. Against the
previous estimator's 24% silent failure rate, this is the instrument the first
attempt lacked.

*It also failed with the magnitude right and the sign inverted on the first run* —
every planted angle came back mirrored, which would have **doubled** every page's
skew rather than removing it. Caught only by the pixel-level plant. The 0.0°
control passed throughout, because zero has no sign: a control that proves
nothing, which is worth remembering next time one looks reassuring.

**The library was swept, not just the corpus.** A 1-in-16 sample of the user's
16,087 PDFs — 1,006 documents, 2,557 pages measured, 229 abstained:

| pages | share |
|---|---|
| below 0.25° | **95.6%** |
| 0.25–0.5° | 2.5% |
| 0.5–1.5° | 1.4% |
| over 1.5° | 0.4% |

Median 0.000°, p95 0.220°, worst 3.0°. **36 documents carry a page at 0.5° or
worse**, so crooked pages do exist — this is not a claim that they do not. It is
straighter than the 232-document corpus looked (89.9% below 0.25° there), which
is itself a mark against the old estimator.

**Then the 36 crooked documents were deskewed and re-recognised.** Characters
recovered, with the correction folded into the *render* so each side is sampled
from the vector source exactly once:

| measured skew | pages | before | after | delta | better/worse |
|---|---|---|---|---|---|
| < 0.25° (control) | 79 | 177,040 | 176,298 | **−0.42%** | 20/25 |
| 0.25–0.5° | 23 | 61,710 | 61,814 | **+0.17%** | 12/8 |
| 0.5–1.0° | 37 | 84,270 | 82,991 | **−1.52%** | 13/20 |
| ≥ 1.0° | 17 | 20,061 | 19,613 | **−2.23%** | 5/11 |

**Deskewing loses text, and loses more the more crooked the page is.** Subtracting
the control row as a floor still leaves −1.10% at 0.5–1.0° and −1.81% at ≥1.0°.
The corrections were *right* — the estimator re-run on each corrected page reports
a residual of ~0.000° — so this is not a correction that missed. Vision is simply
already robust to a degree of skew, and resampling glyph edges costs more than
aligning the baselines gains. That is the same shape as the angle table above,
where clean material was flat across every angle tried.

**One measurement in this was wrong on the way, in the direction that flattered
the feature's opponent.** The first run rotated the already-rendered bitmap, so
"before" was sampled once and "after" twice, and it charged the extra resampling
to deskew: −1.33% overall. Folding the rotation into the render moved the interim
to +0.26% and the full run to the table above. Both instruments agree on the
verdict; only one of them was measuring the right thing, and the agreement is not
what makes the answer trustworthy.

**And the thing that would have to change to collect even a positive result.** A
page recognised at a corrected angle returns boxes in the *rotated* frame, and the
published page is unrotated — so every observation would need mapping back, and a
line 200pt wide at 1° gains ~3.5pt of box height on a ~12pt line. That breaks
invariant 3's vertical non-overlap on exactly the pages the feature is for, unless
`SearchableWriter` gains a real rotation term. It places every run with a zero
rotation term today. That is the most delicate code in the project, with four
properties that fight each other and one of them found holding by accident. Not
for 0.5% of characters, and certainly not for −1.5%.

**Do not reopen this without a new argument.** Two independent estimators, a
library-wide distribution, and a like-for-like recovery measurement all point the
same way. What would change it: evidence that a *different* recogniser benefits,
or a document that is visibly crooked and demonstrably reads badly — in which case
measure that document, not the idea.
Despeckle and border removal were not measured and are not claimed either way.

**3. ~~Columns, reading order and tables~~ — DECLINED, measured 2026-08-13.**
There is no column model, and that part is true: the nearest thing is
`minimumColumnOverlap`, a *guard* that refuses a hyphen join when two lines do
not share a column, and `SearchableWriter.compose` draws observations in the
order Vision returned them and never sorts. So reading order really is inherited
whole.

**What was wrong is the next sentence — the one that said this makes copying a
two-column page produce interleaved nonsense.** It does not. This entry called it
"the single biggest functional difference from FineReader" and it was never
measured. `Tools/score-reading-order.swift` measures it four ways, and all four
say the same thing.

*Vision keeps columns to themselves.* Gutters detected from the **ink** rather
than from Vision's own output — deliberately, because bands derived from the
observations would file a page whose lines were welded across the gutter as
single-column and hide the only defect worth finding. Over 638 corpus pages, 59
with a real gutter: **5 observations of 2,674 cross one, 0.19%.**

*And it returns them in reading order.* Over 54 multi-column pages: median
interleaving **1.0**, where 1.0 is one hand-off per column break and perfect.
83.3% already ordered. 35 inversions within a column across 3,560 lines.

*Read directly, on a genuine two-column journal page* (Sanders 2001, Academy of
Management Journal): the running head, then the **whole left column top to
bottom, 57 observations in monotonic y order**, then the whole right column. One
hand-off. The text reads as continuous prose.

**The pages that score worst are pages that must not be touched.** Of the nine
scoring above 1.5, the top two are a four-column table in the 1956 NYSE report and
the third is a *table of contents* — titles on the left, page numbers on the
right. Vision reads each table row across, and each contents entry with its own
page number, which is **correct**: the row and the entry are the semantic units. A
column-wise sort would separate every heading from its number and every table cell
from its row. Both were read by rendering the page, which is the only way this
distinction is visible — the metric cannot tell a table from prose, and it was
built knowing that.

So the feature is not merely unnecessary, it is **net negative as specified**: the
work would buy nothing on the pages it was aimed at and damage tabular material,
which this corpus is full of. The one thing measurement does support is a *guard*:
if reordering is ever attempted, it must abstain on tables, and nothing in the
metric distinguishes them.

**What would reopen it**: a document where the extracted order is demonstrably
wrong — measure that document rather than the idea. Reading order coming out of a
different recogniser would also change the answer, since all of the above is a
property of Vision, not of this app.

**4, 5 and 6 — ARCHIVED 2026-08-13**, at the owner's decision, and recorded
rather than deleted so nobody re-proposes them as new. They were: *show uncertain
words instead of deleting them* (a review pass over low-confidence text, which is
what commercial tools do instead of thresholding); *structure tags*
(`/StructTreeRoot` and `/MarkInfo`, the accessibility half of what PDF/A was
declined for — searchable but not navigable); and *more export formats* (DOCX and
EPUB, both of which needed (3) first anyway, since an export without reading
order is worse than no export). None was refused on measurement; they are simply
not what this app is for. Do not reopen without a document that needs one.

**7. A watched folder or a command line.** The GUI batch is the only way in.
Cheap, and it is what turns this from an application into part of a workflow.
**The only live entry left on this list** — 1 is done, 2 and 3 are declined on
measurement, and 4–6 are archived.

**What is not closable, and should be said plainly.** Recognition of degraded
19th-century type, Fraktur, and heavy tabular material is the engine's, and the
engine is Vision. ABBYY's advantage there is decades of per-character classifiers
with dictionary feedback, and no amount of work in this repository changes it.
The decision recorded in HANDOFF — keep mac-ocr, do not reimplement Vision — is
also a decision to accept that ceiling. It is the right trade for this app's
purpose, but it is a ceiling, and anyone who needs Fraktur should be told to use
something else rather than sold a setting.

## Likely worth doing

### A per-page background factor — DECLINED after a second attempt
*(first attempt built and reverted 2026-08-11; second attempt measured and
refused 2026-08-12. BUGS.md R35 has both. Kept because the reason it failed the
second time is different from the first and worth not rediscovering.)*

**The second attempt is refused, and the prize was the smaller half of why.**
Re-measured on 320 layered pages after R38 — which removed the dense-text pages
that produced the first attempt's continuum — the detector is *still* a
continuum, largest gap 0.027 across the whole range. There is a low cluster, and
a threshold at 0.10 looked safe with Findlay's photographs nearly three times
above it.

Then the pages it fires on were read, as this entry has always said to do. The
largest single saving is a **photomicrograph of an integrated circuit** scoring
0.0932 — under the threshold — and 6x visibly softens its traces and destroys the
caption under it. Continuous tone is the wrong axis: a bimodal picture, which is
what line art, technical diagrams and engravings are, has almost none and reads
as paper.

And the prize is about **0.55% of the corpus** at a safe threshold, bounded by
roughly 1% even for a perfect detector, because every MRC background together is
only 5.0% of the output. The 1.74x below was the prize for destroying pictures.

A third attempt would need a signal for *detail worth preserving* — high-frequency
energy in the filled background — rather than for tone. The text below is the
first attempt's reasoning, kept intact.

A layered page whose background is paper rather than a picture can be shrunk far
harder for nothing — Photo detail is a promise about *photographs*, and such a
page has none for it to be about. The first attempt measured tone outside the
text regions, as the highest of 64 tiles, and it failed for a reason worth
knowing: fed the boxes the pipeline actually produces, the paper and picture
populations form a continuum with no gap. Vision does not box every line, and
text it leaves unboxed reads as background tone — correctly, since unboxed text
really is in the background and really would blur.

**Two things to carry into any second attempt.**

The prize is smaller than R35 first claimed. Its 1.74x ceiling was measured by
forcing 6x on every layered page including photographs, and a photograph at 6x
is destroyed. The honest prize is 1.74x *on paper-background pages only*.

And the signal has to be something other than tone-outside-text. The obvious
candidates, none tried: local variance in the filled background after the text
is lifted out (paper is flat, a halftone is not, and the fill makes the
comparison fair); or the fraction of the background that survives a heavy blur
unchanged; or simply whether the *source page* carried an embedded image at all,
which `Flattener.largestImage` already answers and which no amount of unboxed
text can confuse.

Judge any attempt by reading which pages it fires on, not by the aggregate — the
first one looked clean at 0.0000–0.0126 against 0.0955 on standalone boxes and
was a continuum on real ones.

### Make words hyphenated across a line break searchable — SHIPPED
*(requested and shipped 2026-08-11. Kept because the reasoning below is what the
shipped guards rest on.)*

A word broken over two lines is stored as Vision read it — `merito-` at the end
of one line and `cracy` at the start of the next — so searching the finished PDF
for `meritocracy` finds nothing. On archival material set in narrow columns that
is a lot of words, and they are disproportionately the long, specific ones people
actually search for.

**The trade is already decided by the person who asked for it:** search matters
more than selection fidelity here. Selecting across the break may hand back the
two halves separately, or the whole word on the first line and the tail again on
the second. That is acceptable; silently unfindable text is not.

Mechanisms, cheapest first:

- **Join in the text layer only.** Where a line ends in a hyphen and the next
  begins lower-case, write the joined word invisibly over the first fragment's
  ink and write the tail as it is. Search finds the whole word; extraction gains
  a duplicated tail. Smallest change, and the duplication is visible in
  `Tools/score-corpus.swift`'s word-retention column, so it can be measured
  rather than guessed at.
- **Join and suppress the tail.** No duplication, but the second half stops
  being selectable at all — which is a content-loss shape, and invariant 1 is
  unforgiving about those even when a user asked for it.
- **Both spellings.** Joined word *and* the two fragments, all invisible. Search
  finds everything; extraction gets the most noise.

**What makes this harder than it looks** is that it lands in `SearchableWriter`,
whose four properties already fight each other (CLAUDE.md invariant 3), and one
of them — runs keeping a gap from the next fragment on their own line — was found
to be holding *by accident*. A joined word is wider than the fragment it is drawn
over, so it pushes directly on the property that broke last time. Any attempt
needs all four probes re-measured before and after, not just the search result.

Not every trailing hyphen is a break, either: `well-known` at a line end is one
word already, and a rule that joins it produces `wellknown`, which is worse than
what we have. The usual discrimination is a dictionary check, which this app does
not have and should not grow; the cheap approximation is to join only when the
tail is lower-case and the joined form is not itself hyphenated elsewhere in the
document.

Shipped as **Settings ▸ Searchable PDF ▸ Find words broken across two lines**,
defaulting on, taking the first of the three mechanisms above: the joined word is
written over the head fragment and the tail is left where it is.

Two guards came out of measurement rather than design, and both matter:

- **Same column.** Joining by vertical adjacency alone produced `adminis+put`,
  `bipar+put`, `mi+appears` and `that+cerning` on real two-column pages — the
  next entry in reading order is often the next line of the *other* column at a
  similar height. Requiring the two spans to share 60% of the narrower one rules
  the class out; it cut 185 joins to 118 across eight documents and removed
  almost all of the wrong ones.
- **A left-margin test was tried and removed.** A continuation is mid-sentence
  and should sit on the margin, so requiring that looked principled — and changed
  nothing at all on the corpus, 118 joins before and after. An unmeasured
  constant that does nothing is what `ocrAllPages` was, so it is not in the tree.

Two wrong joins survive on one poor-quality page where Vision's own reading order
is wrong. They add noise; they remove nothing, which is what keeps this outside
invariant 1.

Invariant 3 re-measured across eight documents with 118 joins firing:
line-start, line-end, text offset, vertical overlap and word retention all
**identical** to the digit.

**Two cases it does not cover, both deliberate and both extendable.**

*Across a page break* is not implemented: `joiningHyphenatedWords` is called once
per page with only that page's lines, so the last line of one page cannot see the
first line of the next. `compose` does hold `byPage` for the whole document and
iterates in order, so it could look ahead — it simply does not.

*Across a column break* is actively refused by the same-column guard. A word
broken at the foot of one column and continued at the head of the next is a real
case in two-column setting, and it is excluded because the guard could not tell
it from the `adminis+put` failures the guard exists to stop.

**Cross-page now ships; cross-column stays out.** (First attempt built, measured
and reverted; second attempt found the actual bug and works.) The rule was the
stricter one — head at the foot of its column, tail at the head of a column to
its right, or at the top of the next page — and it was correct in the unit
tests, ten of them, including the mid-column pairs it had to keep refusing.

On real documents it produced nothing worth having:

| | joins |
|---|---|
| same column (shipped) | 342 |
| across a column | 2, **both wrong** — `that+that`, `provides+flags` |
| across a page | 0 |

**The first explanation offered for that was wrong, and the correction matters
more than the original claim.** The reverting commit said the case barely occurs
because typesetters avoid breaking a word across a page boundary. That was
inferred from three documents and 134 pages, and it is false.

Measured properly — 45 documents, 1,225 pages, counting pages whose lowest text
line ends in a hyphen — **29 pages do, 2.37% of them, spread across 11 of the 45
documents**. The three documents used for the original test contain **twelve**
such pages between them (7 of 69, 3 of 31, 2 of 30). The implementation found
none of the twelve.

So cross-page joining failed because the code was wrong, not because the case is
rare, and the revert should be read as "not yet working" rather than "not worth
having". A page in forty is a real rate on long documents, and the words broken
that way are the same long ones the same-column join exists for.

The cross-column half is a different verdict and the evidence points the other
way: it did not miss its cases, it admitted two and both were wrong. That is a
precision problem with no column detection behind it, and more corpus would add
wrong joins rather than right ones.

**What was actually wrong, found on the second attempt by doing exactly that.**
The code offered the next page's *topmost* line as the only continuation — and
the topmost thing on a page is the folio or the running head. The trace shows it
plainly: `reject: tail not lower-case (6130)` and
`reject: tail not lower-case (CONGRESSIONAL )`. Both refusals are correct; with
one candidate on offer the refusal ended the search instead of looking past the
furniture. Offering the next page's first three lines fixes it — each still put
through every guard, so the folio and the running head are still refused and the
body text underneath is found.

Result: **11 cross-page joins** against the ~12 opportunities the corpus
predicted for those documents, with same-page joins unchanged at exactly 342.
Invariant 3 identical across eight documents.

Where to start next time: instrument the *candidates*, not the joins. The
original attempt printed a line only when a join succeeded, so zero output read
as "no opportunities" when it meant "twelve opportunities, all rejected" — and
the rejection reason was never printed. Print, for every hyphenated line-end,
which candidates were considered and which guard turned each one away.

One thing the attempt did establish, and it is worth keeping: `edgeOfColumn` at
0.18 admitted nothing at all, because the deepest hyphenated line measured sat at
0.82 of the page and `1 - 0.18` is exactly 0.82. Page margins are larger than
they look. Any future attempt should set that constant from the measured depth of
the last text line, not from an estimate, and should judge itself by reading the
joins rather than by counting them — the aggregate scores did not move for the
good joins or the bad ones, and only the listing showed which was which.



### MRC layering for mixed pages — SHIPPED in 1.8.0
*(investigated and shipped 2026-08-11. `Tools/score-mrc.swift` is the prototype
the design came from and remains the way to re-measure it. Kept here rather than
deleted because the reasoning below is what the shipped defaults rest on.)*

Mixed Raster Content stores a page as three layers: a full-resolution 1-bit
stencil of the text (JBIG2), a background holding paper and pictures
(downsampled, JPEG or JPX), and a foreground holding ink colour. The reader
paints the background, then the foreground through the stencil as an `/SMask`.

**What the commercial tools actually do**, measured from 275 MRC files in the
user's own library — 52 of 60 sampled were produced by ABBYY FineReader: *they
route per page exactly as this app does.* Plain text pages go to 1-bit JBIG2 and
are not layered at all (8–23 KB/page); only pages that genuinely mix text with
pictures get three layers. Saval 2014, an illustrated book, is the inverse: 305
layered pages to 36 bilevel ones.

That kills the framing this was first considered under. MRC is **not** a
replacement for the 1-bit route and not a size win over it — on a 600-page text
book, MRC costs 55 KB/page against 1-bit's 48. It is a replacement for the single
large JPEG that *mixed* pages currently get, and there the measurement is strong:

**48 real picture pages from the corpus: 40,010 KB today, 8,069 KB as MRC —
4.96x.** Text in the reconstruction is visually indistinguishable from the
source at 1:1, and arguably crisper than today's JPEG, because the edges come
from a full-resolution stencil rather than a DCT quantiser.

**Segmentation was the blocker and it is solved.** Sauvola alone (k=0.34, window
dpi/4, following `internetarchive/archive-pdf-tools`) marks halftone dots as
text: the photograph on `Findlay_1992` p21 gets cut out of the background,
blur-filled, and repainted from a 3x downsample — **visibly smeared**, while the
text on the same page is perfect. A blind segmenter fails on exactly the pages
MRC exists for.

Confining the stencil to Vision's word boxes fixes it, and costs nothing:

| stencil | ratio | the photograph |
|---|---|---|
| Sauvola everywhere | 4.96x | smeared, streaked |
| **inside Vision's word boxes** | **5.15x** | intact |

Better on *both* axes, which is worth understanding rather than just banking: a
mask restricted to text has far fewer connected components, so it costs less as
JBIG2, and the background keeps the smooth picture content that it compresses
well. Boxes are padded by a quarter of their height — Vision's are tight around
the glyphs, and a stencil clipped to them files the ascenders and anti-aliased
edges off every character on the page.

A page where Vision finds no words at all falls back to no layering rather than
publishing a plate at a third of its resolution.

**The background downsample is the real quality knob**, and it is steep. On the
photograph page: 1x gives 1.15x compression, 2x gives 3.05x, 3x gives 4.72x.
Across 40 documents: 2x gives 3.28x, 3x gives 5.15x. At 3x the photograph is
intact but soft; at 2x it is close to today's.

Shipped as a setting rather than a decision made for the user — **Searchable PDF
▸ Photo detail**, defaulting to Balanced (2x). The pages this applies to are the
ones with pictures on them, so a default of Maximum would be a refusal to choose
rather than an answer, and R13's "fidelity wins" is satisfied by the fact that
Maximum is one click away and text is full resolution at every level.

The per-page alternative — choosing the factor from how much picture content
lies outside the text boxes — was built and reverted: no threshold separates the
two populations on the boxes the pipeline actually produces. **BUGS.md R35** has
the numbers, and the two findings that came out of it.

Note also that PSNR is useless here and says the opposite of the truth — it reads
20–29 dB for MRC against 37–42 dB for today's JPEG on pages where MRC looks
better, because it punishes a smoothed background and is blind to text edges
being exact. Judge this one by looking at pages.

**Pipeline order was the cost of shipping it, and it is paid.**
`flatten` runs before `mac-ocr`, so at the moment the layers would be built it
does not yet know where the words are. The prototype sidesteps this by running
the recogniser itself, once per page, which the app must not do — it already runs
`mac-ocr` over the whole document and paying for recognition twice is not a
trade worth making. So the page images have to be built in two stages: `flatten`
emits the picture pages as it does now, `mac-ocr` runs, and the MRC layers are
assembled afterwards from the boxes plus a re-render. That is a real change to
`Model.makeSearchablePDF`'s orchestration and to `JBIG2.assemble`, which grows
from one image XObject per page to three plus an `/SMask`.

Still worth doing properly rather than quickly. An MRC page that misplaces its
stencil damages the picture silently, which is invariant 1 territory, and the
failure is invisible to a page count. Remaining before it ships: the two-stage
pipeline; a corpus check that no page loses picture detail, judged by eye rather
than by PSNR; a default for the background downsample; and a decision on the
background codec, now settled against JPEG 2000 in R36.

### Per-page DPI control for picture pages — DECLINED
*(measured 2026-08-12. It would be a second knob for something Photo detail
already controls, and it would disagree with it on 71% of the pages it appears
to govern.)*

Photocopies routed to greyscale cost 720–920 KB/page. Fewer pages take that route
since R33 — cream paper was promoting whole books to the colour path, and the
corpus went from 24 RGB pages to 18 and from 520 bilevel to 523 — and fewer again
since R38. Capping their resolution would cut that substantially. **Parked
deliberately** — the decision recorded in `BUGS.md` R13 is that fidelity wins, and
a silent downscale is precisely the "publishing something plausible" that
invariant 1 forbids. It becomes worth doing as an *explicit setting* with a
measured default and a clear label, not as a default behaviour.

**Measured at `flatten`, over all 232 documents — 452 picture pages against 2,842
bilevel ones**, re-rendering each picture page at the capped scale and encoding
at the shipped quality, which is the operation a cap would perform rather than an
estimate of it:

| | picture-page bytes | saved |
|---|---|---|
| uncapped | 274.9 MB | — |
| 300 DPI | 240.5 MB | 12.5% |
| 200 DPI | 179.8 MB | 34.6% |
| 150 DPI | 144.4 MB | 47.5% |

**And that table is the wrong number, for the reason this register keeps
recording.** It measures the stage where `flatten` emits a JPEG — but MRC
layering runs *afterwards*, re-renders the page at full resolution, and replaces
that JPEG whenever the three layers come out smaller. Counted in the gate's own
output: **320 of the 449 picture pages in the finished corpus are MRC pages**,
across 49 documents. Only **129** are still the single JPEG a `flatten` cap would
govern.

So a cap in `flatten` would deliver roughly a quarter of the table above, and on
the other 71% of picture pages the resolution is already set by **Photo detail**,
which downsamples the MRC background by 2x or 3x. Two settings, presented as
independent, controlling the same property on overlapping and unstated subsets of
pages — that is a worse interface than the one knob that exists, whatever it
saves.

**If picture pages should be smaller, that belongs in Photo detail**, as a
further level or a wider range, measured on the final bytes rather than on
`flatten`'s intermediate. R34, R35 and R36 were each declined for measuring a
stage the pipeline goes on to override; this is the fourth, and the first one
caught before the code was written rather than after.

### Recognition language selection that reflects the machine — SHIPPED
*(shipped 2026-08-12. Kept because the premise recorded here was wrong, and the
correction is the reason the feature is worth more than the convenience it was
filed as.)*

`-l` took BCP-47 codes typed by hand. mac-ocr's `languages` subcommand lists what
the installed macOS actually supports, and the app never called it. A picker
populated from that list would stop users guessing at codes that ~~silently do
nothing~~ **fail the entire batch**.

That strikethrough is the finding. Measured: `mac-ocr` exits **64** with
`Unsupported recognition language: xx-XX`, per file, so a mistyped code does not
degrade the run — it produces no output at all, once for every document in it.

And the sharp edge nobody had looked for: **the two recognizers do not support
the same languages.** On macOS 26.6 the accurate one lists 30 and `--fast`
lists 6 — a strict subset. So ticking **Fast**, which reads as a
speed-for-accuracy trade, silently invalidates any of twenty-four languages
including Japanese, Russian, Chinese, Korean and Arabic, and turns a working
configuration into a batch where every file fails. Nothing in the app said so,
and no entry in this register had noticed.

Shipped as three things rather than one, because the picker alone would not have
caught the Fast case:

- **Settings ▸ Recognition ▸ Languages ▸ Add**, listing what this Mac has, by
  language name and code, respecting the Fast toggle and greying out codes
  already in the list.
- **A warning under the field** naming any code the current recognizer would
  refuse, and saying what will happen — recomputed with `fast`, so it appears the
  moment the toggle invalidates a language rather than on the next run.
- **A line at the top of the run log**, for the batch that was configured before
  anyone read the warning. It travels into the run report.

An empty language list means the probe failed, and is treated as "we do not
know" rather than "nothing is supported" — reporting every code as unsupported
because `mac-ocr` could not be resolved would be worse than saying nothing.

### A way to see what went wrong, after the fact — SHIPPED in 1.10.0
The log is in-memory and dies with the window. For a long batch over archival
material, a written run report — inputs, outputs, per-file outcome, the settings
used — is the difference between "something failed last night" and knowing which
document and why. Small to build, and it makes every future bug report better.

Shipped as `~/Library/Logs/VisionOCR/Run <stamp>.txt`, on by default, with a
Show Reports button under **Settings ▸ Behaviour**. Two things worth keeping from
building it: the report is the log *plus* the context the log lacks rather than a
second rendering of the same facts, because a second view that derives the same
state a second way is how U25 happened; and the settings it reports are
enumerated against `Prefs.Snapshot` with a `Mirror`, so a setting added to the
app and forgotten here fails the checks instead of quietly making every later
report wrong about how its documents were made.

### Retry the failures from a finished batch — SHIPPED in 1.10.0
A 78-document run where four files failed currently means re-dropping four files
by hand. The model already knows which they were.

Shipped as **Retry N Failed** in the results pane. It narrows the list to the
failures first so the window shows what is about to happen, takes their order
from `files` rather than from the `outcomes` dictionary, and goes through
`start()` so the C17 digital-text warning still applies. It is the seventh row in
the states-by-doors table.

## Plausible, with real caveats


### Preserving annotations
*(investigated 2026-08-12. Not shipped. The reasoning below was wrong in the
part that mattered, and the real blocker is somewhere else entirely.)*

The document outline now survives (R19). Annotations do not, and were explicitly
scoped out: links, highlights and form fields are a much larger surface, ~~each
with its own coordinate space to remap onto rebuilt pages~~. Worth reconsidering
if a real document turns up where the annotations matter more than the risk of
misplacing them.

**A real document turned up. Twenty-one of them.** Counted across all 232 corpus
documents: **117 carry annotations, 4,867 in total.** Most of that is platform
furniture — 3,991 `Link` annotations, and 96 documents carry nothing else, which
is what a JSTOR or ProQuest delivery wrapper leaves behind. But **21 documents
carry a reader's own marks**: 508 highlights, 176 underlines, 125 stamps, 31 ink
strokes, 16 sticky notes, 3 free text. Those are somebody's scholarship, and
this app currently discards them without a word.

**The recorded blocker is not real.** Measured on two annotated documents,
comparing each source page against the page this app produced for it:
**0 media-box mismatches, 0 rotation mismatches, and 0 pages whose crop box
differs from the media box.** There is no coordinate space to remap. The rebuild
already preserves the page box exactly, because `kCGPDFContextMediaBox` and
`JBIG2.Page.boxSize` were made to (invariant 4). Annotation rectangles can be
copied verbatim.

**The actual blocker is the writer.** `PDFDocument.write(to:)` re-encodes every
image stream in the file:

| | JBIG2 streams | bytes |
|---|---|---|
| our output | 15 | 839 KB |
| after PDFKit rewrites it | **0** | **2,260 KB (2.69x)** |

Every JBIG2 stream became Flate. On a second document, 13 JBIG2 streams became
Flate for 1.39x. So the one-line implementation — open our output with PDFKit,
copy the annotations across, save — undoes the compression the whole pipeline
exists for. The text layer and the outline survive it; the images do not.

**What a real attempt looks like**, now that both of those are known:

- The annotations have to be written by something that does not re-serialise the
  file. That means either extending `JBIG2.assemble`, which already hand-writes
  the page dictionaries and would grow an `/Annots` array, or a qpdf JSON pass.
  Either way the appearance streams (`/AP` → form XObjects) have to be copied
  with their resources and renumbered, which is object-graph work in exactly the
  code `JBIG2.swift`'s own header warns about.
- **Copy the markup subset, and report the rest.** Highlight, Underline,
  StrikeOut, Squiggly, Ink, Text, FreeText, Square and Circle are self-contained
  and page-local. Link needs destination remapping, Widget needs the AcroForm,
  and Popup needs its parent. Invariant 1 says an annotation that is dropped must
  be counted and named in the log, not silently lost — which is what happens
  today for all of them.
- `Stamp` did not copy even through PDFKit — 20 of 121 and 11 of 81 were refused,
  because a stamp is nothing but its appearance stream. It is the case that
  proves the `/AP` work is not optional.

Still not scheduled: it is a substantial piece of hand-written PDF on documents
where a misplaced highlight is a misrepresentation. But it is no longer parked
for a reason that does not hold, and the two measurements above are what a next
attempt should start from rather than repeat.


### Batch presets — SHIPPED
"Newspaper", "typescript", "photograph" as named bundles of the routing and
recognition settings. Cheap to build, but it should follow evidence: the corpus
already shows per-era differences, and presets ought to encode measured settings
rather than guesses.

Shipped as `Prefs.Preset` — Newspaper, Typescript, Photographs, Book scan — and
the condition above is what the implementation is built around: every value cites
where it came from, and **where nothing has been measured the preset leaves the
setting alone** rather than inventing a number to look complete. A preset writes
into the ordinary settings and keeps no "currently using preset X" state of its
own, because a setting that only looks live is what `ocrAllPages` turned into.

## Parked, with the reason

### PDF/A output — ARCHIVED
An obvious ask for an archival tool. It would mean embedding an ICC profile,
fully embedding fonts, and adding XMP metadata — and the text layer's font
handling would need re-examining, which is the most delicate part of the
codebase. Only worth it if something downstream actually requires PDF/A.

**Archived 2026-08-12. Not doing it.** Nothing downstream requires it, and the
cost is not the ICC profile or the XMP — it is that full font embedding forces
the text layer's font handling open, which is the most delicate code here
(invariant 3's four properties, one of which was found holding by accident).
That is a lot of exposure for a compliance badge nobody has asked for. The
output is already self-contained and the text-layer fonts are invisible.

Revisit only if a specific repository refuses a non-PDF/A deposit.


### Direct Vision instead of the mac-ocr subprocess — SHIPPED
*(archived twice, then done. Kept in full because the reasons for keeping the
dependency were good ones and the reason they stopped applying is specific.)*

Archived on 2026-08-12 with the note that "the only argument left is code
simplification, and it has to buy a fresh 232-document baseline to collect".
Shipped the same day, once that turned out to be false on both counts.

**What changed the verdict.** R39 — recognition being handed a resolution Vision
fails at, and a DPI ceiling that could not bind — existed *only* because the app
handed a PDF to something that re-rasterised it. The 200-megapixel limit that
whole apparatus negotiated around was mac-ocr's own guard, not Vision's: Vision
takes a 216-megapixel image without complaint. And the axis-aligned
`boundingBox` the CLI emits is a lossy view of the quadrilateral Vision returns,
which is why `SearchableWriter` places every run with a zero rotation term.

**And the baseline objection was answerable rather than fatal.** Both engines
over a stratified 52 documents and 4,140 pages: 9,211,704 characters against
9,254,956, **+0.47%**. 163,060 matched observations with no orientation
disagreement. That took an afternoon, not a fresh corpus.

**What it cost:** `Runner` from 918 lines to 426, the whole
`recogniserDPICeiling`/`engineAutoDPI` apparatus deleted, the mac-ocr argument
builders and streaming reader deleted with the checks that covered them, and the
Settings panel's binary-path field gone. **What it bought:** no bundled 2.4 MB
binary, nothing to install, no rasterisation this app does not control, and
access to per-word geometry (`VNRecognizedText.boundingBox(for:)`) which the CLI
never exposed and which is what the text layer wants next.

**Three options were got right by reading mac-ocr's source** rather than by
testing, each a silent divergence from what the corpus was measured with: EXIF
orientation, `automaticallyDetectsLanguage`, and `confidence` coming from the
observation rather than the top candidate. Prior art was cheaper than the
fixtures. MIT, Copyright (c) Hiroki Osame; the licence still ships and
`Recogniser.swift` carries the credit.

### Symbol-mode JBIG2
Compresses several times harder than the generic coding used now. **Never.** It
is the mechanism behind the Xerox scanners that silently swapped digits in
scanned documents, and jbig2enc's supposedly-lossless variant reports itself as
broken. For archival material this is disqualifying, not a trade-off.

### `--roi` region selection
mac-ocr supports it; without a visual region picker it is unusable, and with one
it is a substantial UI feature for a narrow benefit.

### Making the searchable-PDF text visible for debugging
Tempting for diagnosing layer geometry, but `Tools/probe-text-offset.swift` and
`probe-line-edges.swift` already answer those questions numerically, and a
"visible text" mode is a setting users would find and enable by accident.
