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

#### Why, and it is the part that should stop this being proposed a third time: **Vision already handles skew itself.**

Measured on a two-column journal page, each angle rendered once from the vector
source so no row pays for a second resampling:

| planted | characters | vs 0° | the quad angle Vision reports |
|---|---|---|---|
| −3.0° | 5,203 | +0.02% | **−2.93°** |
| −2.0° | 5,204 | +0.04% | **−1.94°** |
| −1.0° | 5,206 | +0.08% | −0.75° |
| 0.0° | 5,202 | — | 0.00° |
| +1.0° | 5,203 | +0.02% | **+0.71°** |
| +2.0° | 5,060 | −2.73% | **+2.05°** |
| +3.0° | 5,206 | +0.08% | **+3.01°** |

Two facts, and it is the pair that matters. **Recognition is flat across ±3°** —
the two dips are not monotonic in angle, so they are line-grouping interpretation
flipping rather than degradation; 3° reads as well as 0°. **And the quads come back
rotated with the page**, tracking the planted angle to within ~0.07°:
`VNRecognizedTextObservation` is a `VNRectangleObservation` with four corners, and
those corners tilt. It is not tolerating skew by accident, it is working in the
page's own frame.

So there is nothing left for a deskew step to win. The baselines are already found
at their real angle, and all a rotation can add is a resampling of the glyph edges
— which is precisely the cost that grows with angle in the table above this one.

*What this does not establish* is the implementation: whether Vision rotates
internally or its line-finding is rotation-invariant cannot be told apart from
outside, and is not worth telling apart. Either way the skew is handled before this
app could help. `Tools/score-skew.swift` carries the instrument if someone wants to
re-run it against a future OS.
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

**3. ~~Columns, reading order and tables~~ — DECLINED 2026-08-13, and REOPENED FOR MEASUREMENT
2026-08-20 on this entry's own stated trigger. Read the reopen note at the end before the body.**
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

#### REOPENED 2026-08-20 — that trigger is met, and the 0.19% has a threshold hole

**The document.** `Hughes - The Knitting of Racial Groups in Industry.pdf` (JSTOR, *American
Sociological Review* 11:5, 1946; in `~/Downloads`, **not** in `testdocs/`). Its rebuilt text layer
welds the columns, and this is quoted from the content stream rather than inferred — one `Tm`, one
`TJ`:

```
BT 10.69533 0 0 7.795851  50.37037 606.0698 Tm
[ (t)(i)(o)(n)… (w)(o)(rk )(w)(e)(l)(l)( )(t)(o)(- )(p)(l)(o)(ye)(s )(so)(rt)… ] TJ
```

`"…work well to-"` is the LEFT column's hyphenated line end; `"ployes sort themse…"` is the RIGHT
column's line. One string, one position. The **input** reads `"work well together."` in the same
place — JSTOR's own OCR columnises this page correctly — so the rebuild is a regression against the
file it was given. `pdftotext` on the output interleaves the columns visibly; on the input it does
not. ⚠️ The suite's `ENGINE ASSUMPTION: no line is welded across the gutter` is GREEN over its
generated fixture, whose gutter is 52 pt of 612 = **8.5%** and is justified in its own comment as
*"far wider than any word space"*. This article's gutter is roughly a wide word space. ✅ **A second
fixture at 2.5% was added 2026-08-26 and it WELDS — see "The weld is PINNED IN THE SUITE" below**, so this
paragraph is no longer the only thing saying the 8.5% figure is why that check holds.

**Why the corpus number did not see it — and this is the actionable part.**
`Tools/score-reading-order.swift`'s ink test requires a quiet run of `0.035 * width` (**3.5%**), and a
page with no qualifying gutter is counted `singleColumn` and `continue`d — **dropped from both halves
of the 0.19% before any observation is examined**. A census over the corpus, sampling 3 interior pages
per document (644 pages of 233 documents, against the Swift run's 638), found:

| widest interior quiet band | pages |
|---|---|
| ≥ 3.5% — counted | **43** |
| 3.0–3.5% — dropped | 8 |
| 2.5–3.0% — dropped | 9 |
| 2.0–2.5% — dropped | 10 |

So **27 pages across 18 corpus documents carry a real but sub-threshold gutter — a blind spot ~63% the
size of the counted population.** They are the expected material: `Kristol_1962_SOCIAL SCIENCES AND
LAW`, `Freud_Fetishism`, `WITTE_1978_Democracy, Authority and Alienation in Work`, `Berle_1940`,
`Canby_1929`, `Kazin_1955`, `Hyman_2012`, `Maclean_2008`, `Jones et al_2010`. **The class is already
in the corpus; it is not being counted.** `Jones et al_2010` is one of the documents C26's campaign
rendered, so it has been read by eye for a different defect while being filed single-column here.

⛔ **THE CENSUS ABOVE IS A REIMPLEMENTATION AND IS NOT AUTHORITATIVE.** It mirrors the ink test in
poppler + Python (render grey at 150 DPI, Otsu, per-column ink, `quiet = peak/100`, `minimumRun`
3.5%, 12% margins) so that it needed no `swiftc` build, and it disagrees with the Swift tool on the
counted population — **43 against the recorded 59**. ✅ **RECONCILED 2026-08-26 — the gap is PAGE
SELECTION, and on the same pages the two implementations agree on 635 of 644. See "The instrument
reconciled" below.** Of the three candidates named here, `samplePages` is nearly the whole gap and the
box is exactly three pages; the Otsu clamp is refuted; ⚠️ **`renderGrey` was never varied and is the
leading surviving candidate for the six pages nothing explains** — no rasteriser was swapped, so this
sentence must not be read as clearing it. Treat 27 as an order of magnitude, not a count — the tool
reads **28 sub-threshold pages in 21 documents** over its own population. The census itself is committed as `GUTTER-CENSUS-2026-08-20.tsv` (644 rows) so the
43-vs-59 gap could be worked rather than re-derived, which is what happened. Its script is
deliberately NOT committed: a file in `Tools/` owes a `--self-test` and staging one runs the full
suite, which is 45-90 minutes bought for a screening script that the Swift tool is meant to replace.
⚠️ **That reason is now spent** — the tool carries the screening mode itself (`--census`, with a
self-test, 2026-08-26), so the Python pass never needs reproducing.

⛔ **AND THE DECLINE'S STRONGEST FINDING STILL STANDS: a column-wise sort is net negative.** The
worst-scoring pages are a four-column table and a table of contents, where reading ACROSS is correct,
and nothing in the metric distinguishes a table from prose. So what is reopened is the
**measurement**, not the feature. A weld also cannot be repaired by reordering — the halves are
already one string — so if a fix is ever warranted it is upstream, in how the page is handed to the
recogniser, not a sort applied afterwards.

#### The weld is PINNED IN THE SUITE as of 2026-08-26 — a generated page reproduces it

`gutter-floor`'s sub-step 0, which the owner put ahead of the sweep. `Tests/main.swift`'s engine-assumption
block — the one whose 8.5% fixture the ⚠️ above is about — now carries a **second fixture at a 2.5%
gutter**, from one generator called twice with the gutter as its only argument, and **at 2.5% Vision welds**:
**7 of 15 observations span the gutter**, the longest reading
`The first column begins here and The second column sits beside the`, against **0 of 23** at 8.5% from the
same generator. So the JSTOR article's failure is not a property of that scan — a clean, generated,
**107-word** page (19 justified lines in two columns) at a plausible journal gutter reproduces it.

⛔ **It is pinned as an `ENGINE ASSUMPTION`, i.e. green BECAUSE the engine welds.** There is no fix to pair
a red assertion with (the remedy is declined, and upstream rather than a sort), and a red suite refuses
every commit that stages code — `Sources/`, `Helper/`, `Tests/`, `Tools/`, `build.sh`, `run_tests.sh` —
through `.githooks/pre-commit`. So the check records where the engine's competence ends. ⚠️ **It goes RED
the day Vision STOPS welding, and that is not "re-open item 3" — item 3 is already reopened** (2026-08-20,
above); a red means the reopen note has lost its trigger and the decline can be re-affirmed on a fresh
measurement. The check's own failure detail says so, and says the suite is not broken.

**Seven checks, two of them `ENGINE ASSUMPTION`s, and exactly ONE of the seven is green because the engine
welds.** The other six are a fixture that rendered, a fixture that is calibrated, and a control:
- The gutter is **measured off the rendered pixels** rather than computed from the text positions —
  **0.0253 against a layout 0.0250, which is one pixel of quantisation** (15.3 pt at 200 dpi is 42.5 px of
  1700 and the quiet run reads 43). ⛔ A draft credited that to glyph side bearings and the review of this
  diff refuted it by arithmetic: Courier's bearings would have put it near 0.028. The point survives
  unchanged — reading it off the pixels is what makes a font substitution report itself, and a substituted
  face moves the inked gutter clean out of the `[0.020, 0.030]` band because the column width is computed
  from an assumed 0.6-em advance.
- A second calibration asserts every justified line **fits its column** (longest 33 of 33), which is what
  catches a word too long to wrap — `justifyLines` emits such a word whole and it would push ink into the
  gutter.
- A non-vacuity floor on **both** arms, because a page with no text welds nothing and because the character
  comparison below needs a real denominator.
- The 8.5% arm is the **negative control**: same pool, same face, same recogniser, one argument apart, so at
  this pool the gutter is what flips the outcome. ⚠️ It is *not* evidence that nothing else does — the
  paragraph below has a second pool that welded at 3.5%.
- And the last one is what a character count can and cannot see: **569 welded characters against 561
  clean**, so a weld does not shrink the text, it rearranges it. ⛔ **Its first form —
  `narrow.chars >= wide.chars * 0.9` — COULD NOT FAIL**, because a weld *adds* a joining space, so the
  welded arm holding at least as much text as the clean one is what the mechanism guarantees; the review of
  this diff caught it. It is two-sided now (the arms must be *close*), and it reds in both directions.
  ⚠️ **It is not isolated either**: the 3.5% arm reads **557** characters with **zero** crossings, below the
  welded arm's 569, so character count moves ±15 across these widths independently of welding. What the row
  does say is that no count of characters or of retained words can *localise* a weld — the corpus gate could
  only ever see unlocalisable drift (R46) — and that the one instrument which names them is
  `score-reading-order --gutter`, which is what sub-steps 1-3 are for.

✅ **WATCHED FAILING TWICE, on DISJOINT pairs, each predicted by name before its run.** (A) the narrow arm
given the wide gutter: **1341/1343**, red on the narrow calibration (0.0853 against the aimed 0.0253) and on
the weld assumption (0 crossings). (B) the wide arm given the narrow gutter: **1341/1343**, red on the wide
calibration and on the wide control (7 crossings where it demands 0). Suite **1,336 → 1,343**. ⚠️ Three of
the seven were not watched red — the two fixture floors and the character row — and are stated as such
rather than implied; the character row's first version is the one the review proved could not fail at all.

⛔ **DO NOT READ A THRESHOLD OFF IT.** Over six widths the crossing count reads **0 / 0 / 7 / 7 / 9 / 9** at
8.5% / 3.5% / 2.94% / 2.5% / 2.0% / **1.47%**, so the boundary sits between 3.5% and 2.94% *here*. Three
things bound that. ⚠️ **The 9 is a CEILING, not a gradient**: the columns wrap to 10 and 9 lines on a shared
baseline grid, so only **9 pairs share a y** and only 9 observations can ever span the gutter — 2.0% and
below are saturation, and the suite prints that ceiling in the check's own detail. ⛔ An earlier word pool at
the **same geometry** welded 2 observations at 3.5% and only 5 of 20 at 2.5%, and was not monotone in the
gutter at all — so both the boundary and the count move with the TEXT; only the existence of a weld is
stable, and it was byte-identical over three consecutive runs of one pool. ⚠️ **And the provenance: all six
rows are a scratch probe's**, compiled from this worktree's own `Sources/` (so `Recogniser.recognise` is
literally the same code) and **not in the tree**. What the SUITE has measured is the two committed widths,
both out of the sabotage runs above: 8.5% → 23 observations, 0 crossings, inked 0.0853, and 2.5% → 7
crossings, inked 0.0253 — agreeing with the probe's rows digit for digit on every figure either one prints.
The 15-observation and 569/561 character figures are the probe's alone until this commit's own hook runs.
⚠️ It is one generated page in a monospaced face, justified both sides so that a single number can describe
the gutter at all; nothing here measures a proportional face and nothing here measures a corpus page.
**Sub-steps 1-3 are untouched: no rate has been re-run and the 0.19% stands exactly as published.**

#### The instrument reconciled as of 2026-08-26 — the 43-against-59 gap is PAGE SELECTION

`gutter-floor`'s sub-step 1. `Tools/score-reading-order.swift` grew a `--census` mode — the ink test
alone, one row per sampled page, Vision never asked — and a `--pages-from <tsv>` knob that takes the
pages to score from the census file's own first two columns. That is what holds page selection fixed
while two implementations of one test are compared, and it turns an unexplained gap into three
numbers. `GUTTER-RECONCILE-2026-08-26.tsv` (644 rows, the census's own pages) and
`GUTTER-SAMPLED-2026-08-26.tsv` (641 rows, the tool's own sampling) are both committed. Neither run
asks Vision, so neither is a crossing measurement — **the 0.19% is untouched and sub-step 3 has
nothing new to report to the owner yet.**

⛔ **THE GAP IS WHICH PAGES, NOT WHICH IMPLEMENTATION, AND THE PAGE SETS BARELY MEET.** `samplePages`
takes page 2, the middle and **the last page**; the census took quarter, half and three-quarter depth —
`floor(count * k / 4)` for k = 1, 2, 3, which reproduces its own rows on **232 of its 233 documents**,
so that rule is a verified inference and not a guess. Over the 233 documents the two sets are
**645 pages against 644 sharing only 133 — 20.6%** — with **153 of the 233 documents sharing not one
page**, and 46 of the 47 documents of three pages or fewer have identical sets, because there
`samplePages` takes every page. On a 69-page document the two sets are 2/35/69 against 17/34/51.
⚠️ **The 645-against-644 is a CHOSEN set against a SCORED one and the census probably chose 645 too**:
its one exception to the rule is `1935_Title Page.pdf`, where it holds pages 1 and 2 and the rule wants
1, 2 and 3 — and p3 is one of the four pages this tool found no ink on. So the likely honest pair is 645
chosen either way, 644 scored against 641, with the census dropping silently where the tool names. So:

| run | pages | qualifying gutters |
|---|---|---|
| the census, poppler + Python | 644 | **43** |
| this tool, `--pages-from` the census | 644 | **44** |
| this tool, its own `samplePages(3)` | 641 scored, 4 no ink | **60** |
| the recorded `--gutter` run, undated above | 638 | **59** |

**One page of implementation, sixteen of page selection** — ⚠️ that one is a NET: the gross is nine
page-level disagreements, five where this tool counts a gutter and four where the census does. Page for
page over the 644, the two agree on
**635 (98.60%)**; the widest-interior-quiet-run fraction has a median absolute difference of **0.0000**,
a mean of 0.0011, and **619 of 644 pages agree within 0.005**. The tool's own sampling reproduces the
recorded run to **60 against 59** gutter pages over **641 against 638** scored — ⚠️ across an unknown
interval, since the recorded run is undated in this file and the tool then stopped compiling on
2026-08-14, so what that pair says is that the recorded figure reproduces, not how far it has travelled.
The four pages this run found no ink on are named on stderr rather than dropped
(`1935_Title Page` p3, `Clark_The graphic rating scale` p2, `Noble_1977` p2, `_1985_Issue 2` p29).
⚠️ The same run logged three `Unexpected EOF in JBIG2 stream` errors from the renderer, which name no
page, so whether they are these pages is not established.

⛔ **Of the nine disagreements, the box explains THREE and nothing else explains the other six.**
`pdftoppm` renders the **media** box unless it is given `-cropbox`, and this tool renders
`Flattener.displayBox` — the crop box with `/Rotate` applied. On `Boltanski_2006` the two differ, and
by a lot: media 1031x727 pt against crop 779x628, so the Python pass was reading a third more sheet.
Its p50/p101/p152 read **0.0000** there and 0.0456-0.0511 here (measured with `pdfinfo -box`); the
other six disagreeing pages have **identical** media and crop boxes, so the box is three pages and
only three. ⛔ **The Otsu clamp is REFUTED as a mechanism for these nine**: `Flattener.otsuThreshold`
clamps to `[90, 230]` where a reference implementation may not — a difference this project has recorded
elsewhere — but over these 644 pages the threshold runs **103 to 216, median 151, and NOT ONE page sits
at either bound**, so it cannot have caused any of the nine. ⚠️ **It is NOT "the clamp is unreachable on
this corpus", and this diff's own second artefact refutes that wider reading**: in
`GUTTER-SAMPLED-2026-08-26.tsv` one page of the 641 — `Levy and Temin - 2007` p66, a page whose tallest
ink column is its full height — reads exactly **90**. Sparseness is not a common cause either: the four
pages where the census sees a gutter and this tool sees none have tallest-ink-column counts of **147,
265, 328 and 1583** against a corpus median of **367.5**, spanning the distribution. So **six of nine
are unattributed** — 0.93% of the pages, within a 1.40% disagreement rate, and one page of the counted
total. ⚠️ And a large
fraction delta does not imply a disagreement: `Henry Morgenthau papers` p50 differs by 0.0471 and both
runs still call it a gutter, because on a page with several wide bands "the widest" can be a different
band.

✅ **The blind spot survives the reconciliation, and the 27 decomposes cleanly into two steps.**
Sub-threshold interior bands of 2.0-3.5%: the census's own file reads **27 pages in 18 documents,
62.8% of its 43** — the reopen note's figure, re-derived from the committed rows. This tool on **the
same 644 pages** reads **29 in 20 (65.9% of 44)**, and on its own population **28 in 21 (46.7% of
60)**. So **27 → 29 is implementation and 29 → 28 is page selection**, and the ratio moves mostly
because the denominator does. ⚠️ The earlier draft of this paragraph called 27-in-18 "the census page
set's figure", which hides the only implementation-side delta measured for this band class; the review
of this diff caught it. Both readings agree that the class is real and of the same order as half the
counted population. The bands over the tool's own 641: **60 counted, 5 at 3.0-3.5%, 13 at 2.5-3.0%, 10
at 2.0-2.5%, 553 under 2.0%.**

⚠️ **What this does NOT do.** It measures no crossing, so it neither confirms nor moves the 0.19%: the
`--census` mode skips recognition on purpose, because recognising 644 pages to measure a threshold on
pixels is a cost with no answer in it. Sub-step 2 still has to run `--gutter` with the floor lowered,
and the new `widestSpan` column is there so it can find the sub-threshold band on a page without
rendering it again. Both passes are one machine, one build, at 150 DPI; a third pass over the census's
pages came back **byte-identical**, so the measure is deterministic on this path — ⚠️ that third pass is
not committed, so it is a claim about a run rather than something a reader can re-derive from the tree.

⛔ **THE ADVERSARIAL REVIEW OF THIS DIFF FOUND NINE THINGS, AND TWO OF THEM WERE IN THE ARTEFACTS OR THE
TOOL RATHER THAN IN THE PROSE.** (1) `heightPx` was printed as `Int(displayBox.height * 150 / 72)`,
which truncates where the render `.rounded()`s: it disagreed with the height actually measured on **40
of 100 sampled rows** (`w5093` p48, 1639 printed against 1640 rendered). Both artefacts were
regenerated. (2) The unconditional self-test read the caller-mutable global `pages`, so
**`--pages 4` reddened a check about `--pages 3` and refused to measure anything** — the sampler now
takes `take:` as a parameter and the self-test pins both 3 and 4. (3) `--pages-from` was read, validated
and then ignored by `--gutter`, which is the mode sub-step 2 wants: both that and `--census --gutter`
now exit 2. (4) `owed` was seeded from every row of the list rather than from the documents passed, so a
one-document spot check printed a correct TSV and exited 4 owing 641 pages. (5) The summary block was
inside the TSV, where every other committed `*.tsv` here is pure rows; it goes to stderr. (6) Pointing
the ink test at `minimumGutter` looked like removing a duplicate constant and was not — that constant
gates the OBSERVATION-coverage gap in `bands`, so sub-step 2's *"lower the floor to 0.02"* would have
silently moved every `switches`/`interleaving`/`inversions` figure the default mode prints. The ink test
has its own `inkGutterFloor` now, equal by coincidence and documented as such. (7) One self-test clause
could not fail (`widestSpan != nil` where `widestInterior != 0` already says it) and another was green
with the guard it pinned deleted (`samplePages(count: 0)`); both replaced. (8) The `quiet = peak / 100`
tolerance was unpinned — every fixture was 40 rows deep, so `quiet` was the `max(1, …)` floor and any
divisor passed; a 400-row fixture with 2-pixel and 3-pixel specks now pins it. (9) One check was written
without the `else` its six siblings have, so it went green whenever the ink test returned nil.

#### The two bands MEASURED as of 2026-08-26 — the uncounted class crosses 2.47x as often, and it is still under half a percent

`gutter-floor`'s sub-step 2, and the first crossing measurement this feature has had since the
undated run that produced the 0.19%. `Tools/score-reading-order.swift` gained `INKFLOOR=<fraction>`,
which substitutes the ink test's floor **for the run only**, and `--gutter` went from **six columns to twelve** so
that one sweep answers both halves: `wideGutters` / `narrowGutters` / `band` / `crossWide` /
`crossNarrow` / `widestFrac`, the last being the census's own column arriving in this mode for the
first time. ⚠️ `share` keeps its name and changes meaning — it is the band's OWN crossing share now,
not `crossing / lines`, and the `worst` list sorts on it. Both artefacts are committed —
`GUTTER-BANDS-2026-08-26.tsv` (91 rows, `INKFLOOR=0.02`) and `GUTTER-BANDS-SHIPPED-2026-08-26.tsv`
(58 rows, the control at the shipped floor). All 233 documents, `samplePages(3)`, 645 pages
attempted and 641 scored — the four unscored are `1935_Title Page` p3, `Clark_The graphic rating
scale` p2, `Noble_1977` p2 and `_1985_Issue 2` p29, the same four sub-step 1 named — 135 s and 106 s.
⚠️ Every page the sweep declines is counted and named on stderr, and that stderr is not committed.

⛔ **THE TWO RATES.**

| band | pages | observations | crossing its own gutter | rate |
|---|---|---|---|---|
| **wide** — carries a gutter the shipped 3.5% floor counts | 58 | 2,728 | **5** | **0.18%** |
| **narrow** — qualifies only at the lowered 2.0% floor | 33 | 2,210 | **10** | **0.45%** |

✅ **The wide band reproduces the published figure**: this file's *"5 observations of 2,674 cross
one, 0.19%"* against **5 of 2,728, 0.18%** — the same COUNT of five, on a population 54 observations
larger, across an interval this file does not date. ⚠️ **Not "the same five crossings"**: the earlier
run's per-page rows were never committed (which is the gap `--census` was built to close), so whether
the two runs' crossing pages coincide is not established and cannot now be. ⛔ **And the blind spot does NOT overturn the
decline.** The uncounted class crosses **2.47x as often and twice as many times in absolute terms**,
which is the finding, but 0.45% is still under half a percent — and the decline's *strongest*
argument was never the rate: it is that the worst-scoring pages are a four-column table and a table
of contents, where reading across is correct, and nothing in the metric distinguishes them. That is
untouched. ⚠️ Those are the **interleaving** metric's worst pages, a different list from this
section's, which is ordered by crossing share; do not read the two as one ranking. **The decision is the owner's (sub-step 3) and these are the numbers it rests on.**

⛔ **Read `crossWide`, never `crossing`, and the control is what says why.** Lowering the floor ADDS
narrow gutters to a wide-band page's list, so that page's `crossing` at 0.02 is not what it was at
0.035. The same sweep at the shipped floor reads the wide band **58 pages / 2,728 observations / 5
crossings — identical on all three — and row for row identical on all 58 rows** in `file`, `page`,
`lines` and `crossWide`, while `crossing ANY` reads **5 against the lowered floor's 6**. So the
confound is real, measured rather than reasoned, and it is exactly **one observation on one page**:
`Nogales oral history.pdf` p46 is a wide-band page whose only crossing is of a narrow gutter that
exists only because the floor moved. ⚠️ `crossing` is also not the sum of the two: on `w7787.pdf`
p30 and `w7787 2.pdf` p30 one observation spans a wide gutter **and** a narrow one.

✅ **The accounting closes exactly, against the previous sub-step's committed artefact.** 93 pages
carry a qualifying gutter at 0.02 = 58 wide + 33 narrow + **2 that returned no observations**
(`Hyman_2012` p15 and `NAYLOR_Arthur E.pdf` p2, both named on stderr with their band, both wide;
⚠️ "no observations" and not "Vision returned nothing" — the guard's first clause is the RENDER, where
Vision is never asked). So wide 58 + 2 = **60**, which is `GUTTER-SAMPLED-2026-08-26.tsv`'s own
`withGutter`. ⛔ **And the narrow 33 must be decomposed with EXACT fractions, not the artefact's
printed ones**: 29 pages have a widest-run fraction in [0.020, 0.035), **minus** `NAYLOR_Arthur E.pdf`
p134 which the gutter test puts in the wide band, **plus 5** whose fraction is 0.0194-0.0199 while
their run still clears `Int(0.02 × width)` (`Gowan and Demos - 1964` p2, `NAACP Pt. 15 Ser. A` p65,
`Riesman_1964` p12, `Bullitt_1959` p5, `Part Two` p18) — 29 − 1 + 5 = 33, and 59 + 1 = 60 on the other
side. ⚠️ **The reopen note's "27 in 18" and the sub-step-1 table's 28 are counts off a PRINTED 4-dp
column**; a first draft of this paragraph wrote "28 + 5 = 33", which is arithmetic no reader can
reproduce, and the adversarial review of this diff caught it. `minimumRun` truncates, so the counted
set is slightly wider than any fraction band.

⛔ **THAT RECONCILIATION FOUND A DEFECT IN THIS DIFF'S OWN BAND KEY, one page wide.** The band was
first written as `widestFraction >= inkGutterFloor` and the wide set then came out **57** against the
census's 60 rather than 58. The missing page is `NAYLOR_Arthur E.pdf` p134: a **45-px** quiet run on
a **1286-px** page, where `Int(0.035 × 1286)` = 45 accepts it — so the shipped floor **does** count
that page — while 45/1286 = **0.034992** is below 0.035 and the fraction called it narrow. The band
key is now *"does it carry a gutter the shipped floor would have found"*, which is what makes
`crossWide` over the wide band the shipped floor's own answer, and self-test group 8 pins that exact
arithmetic on a synthetic 1286-px page. ⚠️ The 4-decimal `widestFrac` column **prints `0.0350` for
that page**, so the two keys cannot be told apart by reading the artefact — only by the `band`
column.

⛔ **FOUR limits on the narrow band's 0.45%, and the second is the one that could change a
decision.** (1) The 10 crossings sit on **8** of the 33 pages; 25 have none. (2) ⛔ **The headline is
10% sensitive to one near-blank page, and the mechanism is the lowered floor re-admitting a word
space.** `Friedman_1962` p2 is 788x1200 px with a tallest ink column of **25**, so
`quiet = max(1, peak / 100)` degenerates to its floor of 1; its "gutter" is **20 px**, and the 3.5%
floor exists precisely so that *"the space between words or a hanging indent is not a gutter"*. Vision
returned **one** observation there and it crosses, giving a `share` of 100.0% and the top of the
`worst` list. **Drop that page and the narrow band reads 9 of 2,209 = 0.407%, a ratio of 2.22x rather
than 2.47x.** So read the counts, not the share — and note that the confound demonstration above rests
on a sparse page too (`Nogales oral history.pdf` p46, tallest ink column 39 of 1,650 rows, 5
observations). (3) ⛔ **The generated fixture and the corpus
disagree by two orders of magnitude, and that is the question sub-step 3 hands over unanswered.**
Sub-step 0's page welds **7 of 15 observations (47%)** at a 2.5% gutter; corpus pages in the same
fraction band weld **0.45%**. The leading mechanism candidate is that the fixture is monospaced and
justified both sides, so **every** line's gap equals the quiet run the ink test finds, where a real
ragged column's typical gap is wider than its narrowest — which would make the fixture the worst case
for a given quiet-run width rather than a representative one. ⚠️ **Not measured**: no em-relative or
per-line gutter figure exists for any corpus page. ⛔ **And do NOT write "the sheet size is not the
difference"** — a first draft did, off the fact that 2.5% of 612 pt and 2.5% of 1275 px at 150 DPI are
the same 15.3 pt, which only says a percentage is scale-free *within one sheet*. The 91 measured
gutter pages run **704 to 2,124 px** wide, so 2.5% of the sheet is **8.45 pt on one and 25.49 pt on
another** — a 3.0x spread in the absolute gap, and absolute gap is exactly what a word space is
measured in. That is unexamined, not excluded.

⚠️ **And the document that reopened this item cannot be re-measured**: `Hughes - The Knitting of
Racial Groups in Industry.pdf` is not in `testdocs/` and is no longer in `~/Downloads` on this
machine (checked 2026-08-26). Every number above is corpus material; the founding page is evidence
from a file nothing here can now open.

⚠️ Provenance: one machine, one build, `PhotoDetail` defaults, 150 DPI for the ink test and
`Recogniser.render`'s own resolution for recognition. The tool's `--self-test` is **8** groups and
ran on both sweeps; **five** one-token sabotages were watched failing, each red set predicted by name
first — the floor parameter wired back to the constant reds two clauses; `isWide` pointed at 0.02 reds
one (⚠️ that pair is **nested, not disjoint**); `isWide` with a strict `>` reds **exactly** the
45-of-1286 clause, which is what makes that fixture load-bearing; `widestFraction` divided by the
height reds four; and `minimumRun` rounding instead of truncating reds **only** the 45-of-1300 clause.
⛔ **The last two are the adversarial review's, and they earned their keep.** The height sabotage
reddened a clause first written `widestFraction >= inkGutterFloor` — 0.06 against 0.035, which a
height-divided 1.5 passes — so it was close to unfalsifiable and is pinned at 0.06 exactly now; and the
1300-px fixture exists because 0.035 × 1286 = 45.01, where truncation and rounding agree, so the
mechanism the band key rests on had **no** witness at all. ⚠️ Still not asserted: that
`INKFLOOR` cannot move the self-test. With the knob unset `runFloor` and `inkGutterFloor` are equal, so
an `isWide` reading `runFloor` would leave a bare `--self-test` green; only running the knob catches
it, and the pre-commit hook does not run this file's self-test.

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

### A spatial signal for the picture detector — SHIPPED 2026-08-16
*(specified 2026-08-13 out of R49; R50 answered the easier half the same day; the
**harder half — `isPicture` itself — landed 2026-08-16** and closed `BUGS.md` R56 and
R57. Everything below is kept because the entry predicted the answer three days before
it was built, and because two of the things it predicted turned out to be wrong.)*

**What shipped, in three lines.** `Flattener.pageMarks` reduces the render to two
binary masks at 150 cells to the inch — ink, and the pale marks the threshold will
erase. `Flattener.largeMarkTone` measures the *existing* `pictureToneThreshold` inside
each large ink component instead of over the sheet, which is R57.
`Flattener.paleDrawing` finds pale marks that are taller than type, not solid,
**and have none of this page's own type inside them**, which is R56.

**Where this entry was right.** Shape is the answer and the histogram is not; the
adversarial fixtures were essential and the corpus alone would never have produced
them; and it wanted its own cycle rather than being bolted onto a size fix.

**Where it was wrong, and both matter for the next thing like it.**

1. **"A connected-component pass over the routing thumbnail … cheap, since the
   thumbnail is about 210x350."** The 40 DPI thumbnail is far below the floor. Every
   implementation surveyed normalises to a fixed reference resolution before applying
   any constant — Leptonica to 300 then 150, ScanTailor to 300, Haneda & Bouman to 300
   — and Leptonica's own halftone mask documents "assumed to be 150 to 200 ppi" and
   "this is not intended to work on small thumbnails". At 40 DPI a 10 pt glyph is
   5.5 px, below the minimum component size the MRC literature will look at. The
   shipped signal runs at 150 cells to the inch off the full render, and a first draft
   at 75 was already measurably worse. `RESEARCH-shape-signals.md` §7.
2. **"Shape does [separate them]: strokes are long and curved, show-through is
   text-shaped blobs in rows."** Half true, and the wrong half was load-bearing. Real
   show-through does *not* stay text-shaped at any usable reduction — it merges into
   components taller than a line and emptier than a block, measured on `Ibson_2006` and
   `Doermann_1967`. Size and fill could not separate it from a drawing. What separated
   them was not shape at all but **place**: show-through lies *in* the page's own type,
   because it is the reverse page's type set to the same measure, and a figure sits
   where the type is not.

**And a third thing the survey found which this entry could not have.** No published
method separates a pale drawing from show-through. Leptonica names bleed-through as a
*failure mode* of its own threshold selector rather than a case it handles, and puts
line art on the text side of its photo detector. The one mechanism that would in
principle do it is DjVu's per-blob coding-cost comparison, and no constants for it are
published. So the term that closed this is not something the field already had, and it
should be held to that standard: its recorded miss is in `BUGS.md` R56, with the page
that produces it named.

**It is no longer an optimisation. R56 and R57 are content-destruction defects in the
shipped routing, and this is what closes both.** R56: a pale line drawing scores the
same ink, tone and saturation as a blank text page, so `isPicture` says text and the
1-bit route **erases** it — rendered, not argued. R57: a continuous-tone plate over a
fifth of a page misses `pictureInkThreshold` (0.147 vs 0.15) and `pictureToneThreshold`
(0.102 vs 0.12) simultaneously and comes out a solid black blob that swallows a line of
text.

**A luminance signal was tried for R56 and refused over four rounds** — the table is in
`BUGS.md` R56 and the estimator is in `Tools/score-threshold-loss.swift` with a
self-test. It fails for a reason that is itself an argument for shape: the blind zone
holds pale drawings (keep), decorative shading (harmless to lose) and **show-through
from the reverse of the sheet** (desirable to lose), and no luminance statistic
separates those. Shape does: strokes are long and curved, show-through is text-shaped
blobs in rows, shading is rectangles, and a blobbed plate is one enormous component.

Also settled, so the next attempt does not re-derive it: **`TODO.md` item 1's size
optimisation is refused until this exists** — it would route more text pages to 1-bit
using `inkOutsideText`, whose recorded miss *is* R56 — and its prize is now measured at
**8.2 KB a page** (≈4.3 MB, 12%, on `Blacks in the City`), not the 4 MB and 1 MB that
entry claimed in two different places. `Tools/score-text-route.swift` measures it.

`Tools/make-plate-fixtures.swift` builds the six adversarial pages this all rests on —
pale drawing, flat mid-luminance colour, tonal plate, coarse halftone, text-only and
red-ink text. The corpus does not contain them, which is what this entry said from the
start.

**What R50 settled.** Choosing the *background resolution* does not need a picture
detector at all. It happens after recognition, so it can ask whether any ink falls
outside the recognised words — a structural question, not a statistical one — and
text pages score 0.0000 against 0.971–0.993 for plates. That took the reported file
from 68 MB to 35 MB with every photograph-heavy corpus document byte-for-byte
unchanged. `BUGS.md` R50 has it.

**What is still open** is the harder half, and R50 does not touch it: `isPicture`
itself, which decides between the 1-bit route and the picture route, still runs
*before* recognition and so still has only the histogram. That is the decision R49
could not fix and R35 could not fix, and it is the one that would take this file
below its original rather than 13% above it — a text page routed to 1-bit costs
44 KB where a layered one costs 46, but a *correctly* routed book would not be
carrying tone layers on 522 pages at all. Moving `isPicture` after recognition, or
giving it the connected-component signal below, is the remaining prize.

---

The three picture signals — ink coverage, tone fraction, saturation — are all
**histogram** statistics, and R49 established by measurement that a histogram
cannot answer the question they are being asked. A page of text and a tinted plate
with a subject on it are the same histogram:

| | brightMean / darkMean | brightFraction |
|---|---|---|
| low-key text page (`Blacks in the City`) | 3.002–3.458 | 0.896–0.924 |
| flat sepia field, dark subject on 12% | 2.917 | 0.880 |
| flat ochre field, dark subject on 10% | 2.459 | 0.900 |

What tells them apart is **shape**: thresholded text is thousands of small
components of similar height, arranged in rows; a subject is one or a few large
ones. A connected-component pass over the routing thumbnail would give component
count, a median bounding-box size, and how well the boxes line up into rows —
cheap, since the thumbnail is about 210x350.

**What it would unlock.** Two things this repo has already refused for want of it:

1. **R49's paper detector.** A scan exposed low (paper at luminance 148, nothing
   above 176) has its tinted paper read as colour on the page, and the correction
   that exists for tinted stock never runs. The fix is to find the paper anyway;
   the reason it was refused is that "the bright class is paper" cannot be
   distinguished from "the bright class is a plate" tonally. With a shape signal it
   can, and the fallback becomes safe.
2. **R35's per-page background factor**, refused twice because "tone is
   structurally blind to bimodal pictures" — a photomicrograph scoring 0.0932 sits
   inside the text population. That is the same blindness from the other side.

**Do not do it as part of a size fix.** R49 tried, and the detour cost more than
the fix that shipped. It wants its own cycle, its own corpus pass over the 449
picture pages, and a threshold sitting in a gap that has been *looked at* rather
than assumed — the two histogram discriminators tried in R49 both had a
plausible-looking gap on the corpus and an overlap the corpus did not contain.
Synthesise the adversarial cases; the corpus alone will not produce them.

---

## The order of work for this, decided 2026-08-16 — and what it actually produced

**All four steps were carried out on 2026-08-16 and the signal shipped.** The order was
right and it is worth keeping as a pattern, but the *content* of two steps was wrong,
so read the outcome beside each one:

| step | what it said | what happened |
|---|---|---|
| 0 | re-read the four refused rounds sceptically | **Paid for itself, but not the way it expected.** R56's luminance refusal is sound — `Doermann_1967` p19 was rendered and its pale content really is show-through. What the re-read found instead was that **R57's caveat was wrong**: its three named corpus pages had never been looked at, and one of them is a photograph coming out as a black blob. |
| 1 | write the acceptance test first | **Did what it was for.** Six fixture checks in the suite plus `Tools/score-routing-census.swift`, which names every corpus page that moves. Both halves bit: the first draft of the pale signal passed the fixtures and moved 228 pages of `Himanen_2001`, and only the census could see that. |
| 2 | check `Flattener.inkOutsideText` against the two fixtures — "if it holds the build mostly disappears" | **Refuted, and it was already known to be.** `inkOutsideText`'s signal is *ink*, and R50's own doc comment records that a pale drawing reads 0.0000 there. The hypothesis could not have held. It cost ten minutes to confirm rather than the hour budgeted. |
| 3 | one scoped read of DjVu's separator, then connected components | **The read was worth far more than the build.** DjVuLibre turns out to contain no separator at all, and the useful sources were Leptonica and ScanTailor. It corrected the resolution by 4x and supplied the negative result — *nobody separates a pale drawing from show-through* — that stopped a fifth round being spent looking for a published answer. `RESEARCH-shape-signals.md`. |

The original text of the four steps follows.

Four rounds have been refused here, and the owner's constraint is explicit: no more
fixes that do not work. So the next attempt is bounded in advance, and the first two
steps are both cheap enough to produce a verdict rather than a session.

`RESEARCH-2026-08-16.md` establishes that this is **not an open problem** — it is MRC
segmentation, standardised as ITU-T T.44 and implemented openly in DjVu since 1996 —
and that the field's answer is connected components and stroke geometry, which is the
signal class this entry has been specifying and the one none of the four refused rounds
measured. All four measured luminance aggregates over a whole page.

**1 · Write the acceptance test first, before any signal exists.** The fixtures are
already built and already rendered rather than argued: `Tools/make-plate-fixtures.swift`
produces the pale drawing and the tonal plate that are R56 and R57. The bar:

  - both fixtures route correctly, and
  - **no routing decision changes on the corpus** — `Tools/score-routing` over
    `testdocs/`, compared page by page against a run from the commit before.

A signal that fixes the fixtures and moves corpus pages is not a fix, it is a
different set of defects. This step costs an hour and it is what turns the fifth
attempt into a bounded experiment instead of a fifth refusal.

**2 · Then check what is already in the tree, before building anything.**
`Flattener.inkOutsideText` computes *ink that falls outside every recognised word box*,
using Vision's own boxes as the text mask. That is a structural signal, it is already
measured (text pages 0.0000 against 0.971–0.993 for plates, per R50), and it is
currently asked only about background resolution. **R56's pale drawing and R57's tonal
plate are both ink outside every text box.** Whether it separates the two fixtures is
**unverified** — it is a hypothesis, stated here so the next person tests it rather
than believing it — but it is an hour's work and if it holds, most of this entry
becomes unnecessary.

The catch to check while doing it: `isPicture` runs *before* recognition and
`inkOutsideText` needs the word boxes, so using it here means moving the routing
decision after recognition, which the section above already names as the remaining
prize. That is a real restructuring, not a free win.

**3 · Only if step 2 fails: one scoped read, then build.** DjVu's separator is the
canonical open implementation; the standard features are component count, the median
and spread of component bounding boxes, fill ratio, and a stroke-width estimate. Half
a session with a specific question, not a survey. Then the build — a two-pass
connected-component labelling over the routing thumbnail is ~200 lines and the
thumbnail is already about 210x350.

**0 · And before any of it, re-read the four refused rounds sceptically.** C23's
refusal was written on 2026-08-15 and corrected the same day: it claimed there was
nowhere to put a crop box, which was a statement about qpdf's documentation made
without reading qpdf's documentation to the end. This register has a long history of
"confirmed" findings that were measurement artefacts (CONTRIBUTING §3), and four
refusals in a row is exactly the pattern that deserves one sceptical pass before a
fifth attempt is designed around them.

### A glyphless font and a second knob for the text layer — NOT STARTED, costed 2026-08-16

**The idea.** Stop fitting the run's width with its font size. Set the font size from the ink
height, fit the width with a horizontal scale, and delete the vertical squash. Two independent
knobs instead of one doing both jobs.

**Why it is here.** `RESEARCH-2026-08-16.md` §2: this is what Tesseract's PDF renderer does, and
the font size cancels out of its width arithmetic entirely. Our design couples the two — the font
size fits the width, which forces the glyphs to the wrong height, and **the vertical squash
exists only to undo that**. Invariant 3's "four properties that fight each other" is largely a
description of that coupling. Properties (b) and (c) are not naturally in tension; they are in
tension because one constant is being asked to satisfy both. C18, C20, R81 and R82 are all in the
neighbourhood of it.

**Why it is not a small change, and why the obvious version of it fails.** Our own `draw` comment
already records the attempt: *"Fitting width by stretching x instead exaggerates the gaps."* That
is not a superstition — §1 of the research file explains it. Stretching a **real** font
horizontally scales its side bearings too, so a natural 0.1 em inter-glyph gap becomes 0.15 em at
150% and crosses poppler's `minWordBreakSpace`, splitting words: `accom plished`.

Tesseract escapes it because its font is **glyphless and fixed-pitch** — every character exactly
half the font size wide, no side bearings, so a uniform stretch creates no gap an extractor can
find. **The glyphless font is not a detail of the design; it is what makes the two knobs safe.**

So the change is a package:

1. embed a glyphless fixed-pitch CID font (Tesseract's `pdf.ttf` is Apache-2.0; or generate one)
2. width fit by horizontal scale rather than font size
3. delete the vertical squash and `minimumVertical` with it
4. re-run the whole invariant-3 procedure, because every recorded figure in the register belongs
   to the current geometry

**Cost.** Item 1 is the risky one — a hand-built CID font with `/Identity-H`, a `ToUnicode` CMap
and a `CIDToGIDMap`, in a project whose contributing guide names hand-written PDF as the risky
kind. Tesseract's own notes record that Acrobat rejects `CIDToGIDMap` entries of 0 and Ghostscript
considers the font invalid for its purposes. Items 2 and 3 are small. Item 4 is a corpus campaign.

**What would have to be true first.** A measurement nobody upstream has: whether a glyphless
fixed-pitch layer actually extracts *better than ours* **in PDFKit**, which is Preview, Quick
Look and Spotlight and is the only extractor our users have. Every PDFKit datapoint in six years
of Tesseract and OCRmyPDF discussion is a screenshot. We have `score-run-width` and `welded=` and
could answer it properly on a fixture built both ways, before touching `SearchableWriter`.

**Not recommended yet, and not refused.** The prerequisite measurement is cheap; the package is
not. Do the measurement first.

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

**74 sampled picture pages from the 233-document corpus: 88,972 KB today,
20,364 KB as three layers — 4.37x**, and the app publishes the smaller of the two
per page, which on this sample is MRC on all 74. Measured 2026-08-15 with
`score-mrc` calling `Flattener.mrcLayers` rather than a copy of it. Text in the
reconstruction is visually indistinguishable from the source at 1:1, and arguably
crisper than today's JPEG, because the edges come from a full-resolution stencil
rather than a DCT quantiser.

*(**The figure this replaces should not be requoted: "48 real picture pages from the
corpus: 40,010 KB today, 8,069 KB as MRC — 4.96x."** Two things are wrong with it,
and the second is the instructive one. It is not reproducible — the corpus has grown
from that sample to 74 sampled picture pages. And **its ratio is the blind row of the
table below**: 40,010 / 8,069 = 4.958, and the table's own "Sauvola everywhere" row
is 4.96x. The sentence quoted the segmenter this entry rejects as visibly smeared as
the measurement of the segmenter it ships. It also came from the instrument
`BUGS.md` T15 was about, which overstated the layered total by **43%** on the pages
that reach R50's shrink. Same 72 pages, that instrument against this one: today
61,181 → 62,306 KB, layered 18,759 → 13,115 KB, 3.26x → 4.75x — and it had dropped
two further pages entirely, including the corpus's largest at 64.84 MP, on a 60 MP
gate belonging to neither of the app's two bounds. Those two pages are 26.0 MiB, 30%
of the 74 sampled pages' present-day total.)*

**Segmentation was the blocker and it is solved.** Sauvola alone (k=0.34, window
dpi/4, following `internetarchive/archive-pdf-tools`) marks halftone dots as
text: the photograph on `Findlay_1992` p21 gets cut out of the background,
blur-filled, and repainted from a 3x downsample — **visibly smeared**, while the
text on the same page is perfect. A blind segmenter fails on exactly the pages
MRC exists for.

Confining the stencil to Vision's word boxes fixes it, and costs nothing:

| stencil | stencil bytes, all 74 pages | page total, 26 comparable pages | the photograph |
|---|---|---|---|
| Sauvola everywhere | 4,930.8 KB | 3.25x vs today | smeared, streaked |
| **inside Vision's word boxes** | **3,699.2 KB** (1.33x smaller) | **3.48x vs today** | intact |

*(Re-measured 2026-08-15. **Two columns rather than one, and that is the point of the
correction.** `MRC_BLIND=1` differs from the shipped route in three ways, not one:
no confinement, no R50 shrink — the signal needs the text region blind mode discards
— and grey layers on every page, because the colour interleave lives inside
`mrcLayers`. So a whole-sample page total compares three changes at once. The
stencil column is the one that compares everywhere, since the stencil is what
confinement acts on; the page-total column is restricted to the 26 grey pages where
R50 does not fire, which is the only subset where the two runs differ in exactly one
way.)*

*(**A number this file carried for an afternoon was wrong and it is worth saying how.**
The first version of this correction read "confinement is 1.35x better, not 1.04x" and
called the old pair an order-of-magnitude understatement. 1.35x was the whole-sample
page total — 84% of which is R50's shrink, not confinement. On the comparable subset
it is **1.07x**, so the retired 4.96x/5.15x pair was right in magnitude all along and
only the headline sentence quoting the blind row was wrong. Caught by an adversarial
review of the diff that introduced it, which is the third time in three days that a
correction to this project's own measurements has needed correcting.)*

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
Re-measured 2026-08-15 over the same 74 corpus picture pages with the repaired
instrument, which is the first time the three settings have been swept with R50's
all-text shrink in place:

| Photo detail | factor | as published | vs today | pages where one JPEG wins |
|---|---|---|---|---|
| Maximum | 1x | 83,435 KB | 1.07x | **31 of 74** |
| **Balanced** (default) | 2x | 20,364 KB | **4.37x** | 0 |
| Smallest files | 3x | 13,363 KB | 6.66x | 0 |

*(Supersedes "across 40 documents: 2x gives 3.28x, 3x gives 5.15x", which came from
the mirrored instrument. At 3x the photograph is intact but soft; at 2x it is close
to today's.)*

**Two things in that table are worth more than the ratios.** `PhotoDetail.maximum`
is a factor of 1, which sets `keepEveryPixel` and so suppresses R50's shrink
everywhere — deliberately, because R52 was a page stored at an eighth of the
resolution its user had explicitly asked to keep. The consequence, unmeasured until
now, is that **at Maximum three layers cost more than one image on 42% of the
picture route**, and the app keeps the JPEG on each of those pages. That
`after < before` rule was written as a precaution; this is the measurement that
shows it doing real work.

And **Balanced and Smallest files are byte-identical on any all-text page**: the
shrink is a floor, `max(2, 8)` and `max(3, 8)` are both 8, so the setting can only
move the 36 of 74 sampled pages that carry a genuine picture. Measured directly on the
self-test fixture — `MRC_BG=2` and `MRC_BG=3` both give 15.4 KB.

*(This sweep is over **picture pages only**, so it is not the denominator the Settings
blurbs use — those speak about whole files, most of whose pages are text going to
1-bit. Neither number contradicts the other; they are answers to different
questions.)*

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


### Preserving annotations — BUILT 2026-08-14; everything below predates it

> **Superseded.** Built as `Sources/Annotations.swift`, behind *Keep highlights and
> notes*, off by default: 121 of 121 marks carried on the specification's own document
> including all 20 stamps, 0 moved. `BUGS.md` R58 has the evidence and the three things
> the specification did not anticipate. **It is deliberately not in a release yet** —
> two adversarial rounds each found marks landing in the wrong coordinate space, and a
> third has not been run.
>
> Two sentences below are now false and would mislead: *"this app currently discards
> them without a word"* — it carries them, and reports by type what it left behind — and
> *"the Zotero sweep is blocked on it"*, which is lifted. Where the text says "TODO.md
> item 1" it means annotations; TODO's ordered item 1 is now `isPicture`.

*(investigated 2026-08-12. Not shipped at the time. The reasoning below was wrong in the
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

**Promoted to `TODO.md` on 2026-08-13, and the cost turned out to be smaller than
this entry assumed.** Three things settled it:

- **The library needs it.** 91 of a 1,006-document sample carry a reader's own
  mark — **9.0%, 4,903 marks**, one file holding 227 — which is ~1,400 files.
  Identical to the corpus rate (9.1%), so it is the library, not the sample. The
  Zotero sweep is blocked on it: without this it either skips a tenth of the
  library or destroys scholarship.
- **The recorded blocker is real, and now a number.** `PDFDocument.write(to:)`
  over this app's own JBIG2 output inflates it 1.52x–4.08x — Hayek 35.42 →
  144.68 MB, Boltanski 24.38 → 82.89. Text survives to the character; only size
  is lost, and size is the whole point of the sweep.
- **But qpdf is not PDFKit.** A plain qpdf round-trip of that same 25,565,129-byte
  output returns **25,565,129 bytes**, and so does a full
  `--json-output=2` / `--json-input` round-trip. So the object graph can be edited
  with qpdf doing the objects, the streams and the xref — and "a substantial piece
  of hand-written PDF", which is what this entry called the cost, is not needed at
  all.

The mechanism, the named hard parts, the v1 scope and the verification bar are in
`TODO.md` item 1. The bar is the point: a highlight forty points out of place is a
misrepresentation that no count would catch, so the pages carrying marks get
rendered and compared.


### Clickable footnote and endnote links
*(raised 2026-08-13. **Research first, and not started.** What follows is one
hour of looking, recorded so the next hour does not repeat it.)*

Make a footnote marker in the body clickable, so a reader lands on the note in the
backmatter. For a historian reading a scanned monograph this is the difference
between following an argument and losing it, and no OCR tool does it.

**Mechanically it is an annotation, which this project is about to learn how to
write anyway.** A footnote link is a `/Link` annotation with a `/Dest` pointing at
a page and position. That is the *same machinery* as `TODO.md` item 1, annotation
preservation — and the two measurements that unblock that unblock this: PDFKit's
`write(to:)` inflates our JBIG2 output 1.5x–4.1x and is unusable, while qpdf
round-trips byte-identically and its JSON is editable. **Do item 1 first.** It
builds the object-graph plumbing this needs, and doing them in the other order
means writing that plumbing twice.

**Prior art, local, and better than expected.** The suite already has both halves
the owner suspected:

- `ArchiveProcessor/macOS/Sources/ArchiveProcessor/OCR/LLMTextClient.swift` is
  already the multi-route abstraction — Local Agent CLI, then an
  OpenAI-compatible gateway, then a direct provider (Anthropic, Gemini, Mistral,
  OpenAI), with an explicit precedence order. It was itself extracted from four
  byte-identical duplicated call paths, so extracting it again is a known move.
- **`packages/ArchiveCore` already is the shared library** the owner wondered
  about creating — it has `Corpus`, `Links`, `PDF`, `Tags` and `Thumbnails`
  modules. `LLMTextClient` simply has not been moved into it yet. (`Links` is
  durable links to archive items, not PDF-internal links — different thing, same
  word.)

**Prior art, external: thin.** A search turned up manual routes (Acrobat's
Tools ▸ Edit PDF ▸ Link, drawn by hand per link), authoring-side solutions that
generate links before the PDF exists (InDesign, Word's References menu), and
generic PDF libraries that can *write* a link once you know both endpoints. **No
tool that finds footnote pairs in a scanned book.** That is the interesting part
and it appears to be unclaimed.

**Does it need an LLM? Genuinely unclear, and worth an hour before assuming yes.**
Split the problem:

- *Finding markers in the body* looks geometric, not semantic. A superscript is a
  small glyph on a raised baseline, and this app already has per-observation boxes
  and font sizes — it is better placed than a generic tool to spot one. A regex on
  the text alone would drown in page numbers and dates; the geometry is what
  disambiguates.
- *Finding the notes* is a section-detection problem: a run of pages of
  small type beginning `1.` or `1 `, usually under a heading.
- **The mapping is the hard part**, and it is where an LLM might earn its place.
  Notes usually restart at 1 per chapter, so marker 7 in chapter 3 must find the
  seventh note under "Chapter 3" — which needs to know where chapters begin. The
  outline helps when there is one (11 of the corpus's 78 documents had one).
  Whether heuristics get most of the way is exactly what the research hour is for.

**What would make it worth building**: a measurement of how many books in the
library actually have separated notes *and* a detectable chapter structure. If it
is 15%, this is a curiosity; if it is most monographs, it is the most useful thing
on this list. Nobody has counted, and `Tools/` is the place to count it.

**What would sink it**: a wrong link is worse than no link. A reader sent to note
7 of the wrong chapter has been misinformed by the tool, silently, in a document
they trust. Whatever the mechanism, it needs the same shape of verification the
annotation work has — sample, render, and look — plus an abstention path, because
a book whose structure cannot be read confidently should get no links at all
rather than plausible ones.

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
