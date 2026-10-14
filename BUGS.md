# Known defects

Findings from an adversarial review (three parallel code reviews plus a 78-document
corpus run over the Zotero library). Every entry was verified by running code
unless marked *reasoned* or *unverified*.

Status: `OPEN` · `FIXED` · `WONTFIX` (with a reason)

**2 open (2026-10-14): `C41` and `C57`; `C56` closed `FIXED` 2026-10-14. `C27` closed `FIXED` 2026-09-25, and `C28` was `HALF FIXED` as of 2026-08-22, its
shape term WIRED into `pageIsAllText()` as a third refusal condition once all five of its questions were
measured. `C29` closed `FIXED` 2026-09-25.**
✅ **`C28`'s ONE REMAINING MEASUREMENT IS TAKEN AS OF 2026-09-02 AND IT IS THE MOVE THE ENTRY CALLS *"the
outcome worth aiming at"*** (`#### The bar priced against the term`, `C28-BARPILOT-2026-09-02.tsv`, no
sweep): of the **16** sampled pages a `textPageInkOutsideThreshold` of 0.08 would newly admit, the shape
term refuses **9** at `barDelta same`, so the move is worth **1,648,035 B** where it was worth
**2,965,653 B** before the term — **44.4% retained for free** — and the term refuses **7 of 7** pages in that band that
lose running prose or table data. ✅ **AND IT IS SCALED TO THE CORPUS AS OF 2026-09-10, WITH THE OWED
1:1 READING TAKEN AND `7 of 7` SETTLED** (`#### The same question at corpus scale, and the owed
reading`; no sweep, no new artefact, three runs of `Tools/stratify-corpus.py` over committed files).
⛔ **Per document the move is worth ~2.5 MB over ~10.50 pages of 16,987 where this register has been
quoting C26's ~4.0 MB over ~21 pages, and 44.4% is NOT the corpus retention — that is 36.3%, so the
sampled figure overstates what the term holds by 1.22x**, because the admitted pages concentrate in one
25-page document sampled 12 deep. `Riesman - 1954` p16's *"trailing text lines"* read legibly in the
**composited** page at BOTH bars — ⛔ **the first draft argued that from the stencil alone and the
review of that diff refuted it, the stencil being the foreground's `/SMask` and the same file on both
arms** — so the wider `7 of 8` reading is refuted, on the composite.
⛔ **58.3% of what the move recovers lands on the two pages this entry
already calls free, and 22.2% re-destroys content** — **89.2% free on the exact, no-scaling subtotal** —
so the numbers do not point one way; **no bar is
recommended and the value stays the owner's.** `C28` remains `HALF FIXED` — this prices a decision rather
than taking one, and 17 sampled rows in 10 documents of 233 is **not** a corpus figure.
✅ **AND C28's OTHER STANDING PRODUCT QUESTION — the TWO-SIDED GROUPING TRADE, the pair the entry names
more often than anything in it — IS PRICED AS OF 2026-09-20** (`#### The two-sided grouping trade,
PRICED`, `C28-GROUPING-2026-09-20.tsv`, 75 rows in 23 documents, five arms, nothing in `Sources/` moved).
⛔ **Two findings invert the entry's own framing.** (1) **`lineGapFactor` is INERT AT THE DECISION**:
3.0 → 6.0 moves the group count on 4 of 75 rows and in BOTH directions — `Herbert Marks` p11 goes 1 → **2**
at a *wider* bar, the greedy banding's non-monotonicity measured on a real page for the first time — and
**not one of the four crosses the 0/≥1 boundary**, so 16 pages fire either way for the same
**+2,362,625 B** and the same 15.5%. The trade is one-sided on this population. (2) **Relaxing the
grouping buys NOTHING for the class the term exists for**: all **12 of 12** typeset-content losers already
fire at the shipped pair. Lowering the member floor 4 → 2 newly rescues **2** hand-made marks and **one of
C26's two cartoons**, and newly refuses **6** pages that lose nothing, for **+1,753,917 B** — spend
1.742x, overpay **15.5% → 37.5%**. ⛔ Both cartoons sit ABOVE the shipped bar (`inkOut` 0.0660 and 0.0493
against 0.045), so term 1 already refuses them and the term is never consulted there today; the rescue
bites only in the bar-raise scenario `#### The bar priced against the term` priced. ⛔ **No value is
proposed — the owner's, as on 2026-08-19.** ✅ The `ship` arm reproduces this entry's published
+2,362,625 B and 15.5% exactly, and the port check ran **ARMED on 75 of 75** rows because the two
constants were made DEFAULT ARGUMENTS rather than the disarm the queue box expected.
✅ **AND THAT STEP'S ONE OWED READING IS TAKEN 2026-09-20 — the ornament's own rect, and the answer is the
reassuring one: its ornament band's 664 accepted PIXELS, in THREE components, STILL GROUP INTO ZERO
at a member floor of 3 and of 2**
(`#### The ornament's own rect at a relaxed floor`; nothing in `Sources/` moved, no artefact added).
⛔ **The instrument was BLIND first and that is worth more than the verdict**: `SHAPEDUMP` and `GROUPING=`
shipped a day apart and never met, so a dumping run under `GROUPING=` wrote **7 files, all of them the
SHIPPED arm's** — one `-<tag>-lines.png` per arm now, **7 → 9**, and `Tools/fault-inject.sh shape_dump`
goes **3 rows → 6** with `GROUPING=`'s two owed refusals, each new row watched reddening ALONE.
⛔ **And it corrects the sentence the trade was argued from: `#### Are there PICTURES in the sub-bar 73?`
blames the two grouping constants JOINTLY for this rect and it is `lineGapFactor` ALONE** — gaps of 289
and 230 px against a bar of 24, so no member floor ≥ 2 can group a singleton there, and admitting the
ornament needs **`3:36.125`, 12.04x** the shipped 3.0. ⛔ **The ⛔ above is RETRACTED IN PART by the
review of that diff and both halves are kept: the rect holds THREE components, so the shipped floor of
4 refuses it at EVERY gap factor too — each constant alone refuses, NEITHER alone admits, the pair must
move together.** What survives unqualified: *"lowering it to 3 would admit 666 px of ornament"* is
measured **false**, it admits 0, and so does 2.
⛔ **AND THE SIBLING RECT THAT OWED FOLLOWED 2026-09-20 AND THE CORRECTION DOES NOT GENERALISE — IT
INVERTS** (`#### The footer rect, and the device in it reaches nothing`; nothing in `Sources/` moved,
no tool added, no artefact written). On `Scott_TK` p3's footer strip it is **`lineMinimumMembers`
ALONE**: the two components the `2:3` arm admits sit **3** px apart against the same 24-px bar, so
lowering the member floor alone to 2 admits them at the SHIPPED gap factor, while at the shipped
floor of 4 no gap factor admits anything there. ⛔ **The finding worth more: the device in that rect
reaches the map NOT AT ALL, so the entry's *"second device rect"* does not exist and the population
is ONE.** The `Digitized by Google` wordmark is ink by the page's own Otsu — **1,321** px below 149
on `Scott_TK` p3, **1,581** below 136 on `Merriam_1913` p2 — and **0** map px on **2 of 2**, because
the map is `ink AND NOT region` and it is inside `region` (⚠️ boxes *plus* `textRegionMask`'s
0.25-of-height collar; that it is a box and not a collar is reasoned from the padding arithmetic, and
what needs no argument is that the term is never asked about it). The strip's 208 px are four bands in
its top 50 rows and at 1:1 every one is this page's own lost **table matter** — dotted leaders and
numerals; the 48 px the `2:3` arm admits are the two glyphs of the table value **`31`**. ⚠️ No verdict moves — the page fires at the shipped pair already
(`lineN` 6) — so what the floor costs here is coverage inside a page the term already protects, and
that is unpriced. ⛔ **One instrument trap out of it: `-textish.png` is a faithful component list at
the shipped floor and is NOT one at a floor of 2** — a single **1-px** painted fragment
(`1x1+731+622`) manufactures a whole extra group and 27 px at `2:3` and nothing at `4:3` or `3:3`.
✅ **AND THE THIRD MECHANISM THOSE READINGS TURNED UP — the shape term being blind to the outer
sixteenth of every page — IS MEASURED OVER THE WHOLE POPULATION 2026-09-20, AND THE SIGN INVERTS**
(`#### The blanked border, MEASURED over the whole population`, `C28-WINDOW-2026-09-20.tsv`, the same
75 rows in 23 documents; two appended columns on `Tools/score-shape-term.swift`, nothing in `Sources/`
moved). ⛔ **The blanked border holds a HIGHER share of the unboxed ink on the 51 pages that lose
NOTHING than on the 16 that lose content — median 0.9584 against 0.4079** — because that border is
where the platen edge, the gutter shadow and the page trim are, all unboxed by construction, which is
what `interiorWindow` exists for. ⛔ **The queue box prescribed ONE column and one cannot answer**:
most of `outWinPx` is *recognised* type on a page whose type runs to the margin, so `outWinMapPx` —
the subset `region` does not cover — is the half that is about the term. ✅ **TWO of the sixteen are
REFUTED outright, which is the one thing the column does decisively** — `_1958_Executive Pay` p3 and
p5 read **0** against 44,896 and 43,243 px of border ink. ⛔ **A draft said FIVE and the review of
that diff refuted three: 24, 96 and 280 px are small, not zero, and `Jones et al_2010` p2's whole
in-window map is 155 px with a confirmed one-word loss in it.** ⛔ **And the other fourteen are not
candidates in proportion to the number, because `1976 - Regis McKenna Papers` p4 loses nothing and
reads 82.42% of its whole ink out there: the column refutes border involvement and cannot establish
it without a reading.**
✅ **AND ANOTHER MEMBER OF THE §4b ATTRIBUTION CLASS IS READ 2026-09-21 AND IT HOLDS —
`Jones et al_2010` p12's `1029x10+106+206` IS its table rule, and the `min` is carried by 1,026 pixels
rather than one** (⛔ **no ordinal: a draft said *"the third"* and *"the first to hold"*, and both are
refuted by the boxes above — the 59 px held and the drawing rects' claims stood, so of the four
answered members exactly one, `Scott_TK` p3's footer, inverted**) (`#### The same loss at 1/3 …`'s `##### The table rule's own rect, READ PER ROW AND
PER COLUMN`; nothing in `Tools/` or `Sources/` moved, no artefact written). The band's ten source rows
mean `255 / 255 / 255 / 255 / 255 / 152.2 / 25.5 / 40.5 / 168.2 / 255`, so it holds one object and
five clear rows above it; on the darkest row, **y=212**, min 25 = median 25 = p90 25 and **1,026 of
1,029 columns** sit within 10 levels of the min, in **one contiguous run x 107…1132** — the three that
do not are the rect's own overhang. ✅ The published **25 / 56 / 136** reproduces (8-bit `25 / 57 /
136`; the review's own full readings are 25 / **56.9819** / 136.45, so 56 is truncated and 57 rounded).
⛔ **The instrument problem is real but it is a DIFFERENT one: the 1/2 figure swings 24–60 over five
ImageMagick resize filters and 57-against-64 between `-resize 1240x1647!` and `-resize 200%`** (a
one-row phase shift, 620x823 doubling to 1646 against a 1647-row source), where 1/3 reads 118–136 and
is spec-invariant. ⛔ **And that section's instrument-facts bullet NAMES THE WRONG FILTER: the bare
`-resize` default is `Mitchell`, sha256-identical over the whole upsample, not the Lanczos its
*"kinder of the two"* argument rests on** — default 57 against Triangle 60 against Lanczos 35, so it
is barely kinder rather than notably so. ⚠️ The `Xin Qu` p20 verdict does **not** move with it. ✅ **The conclusion survives and the reason is measured: 1/3 keeps 60.2% of 1/2's
contrast by band-min and 60.5% by darkest-row mean, and those agreeing to 0.3 points is what says the
`min` is representative** — paper taken from the band's own y=206 (255.0 / 254.7 / 255.0, so the
register's "~250" is pessimistic). ✅ *"Continuous at both factors"* becomes a number: **1,028 of 1,029
columns below 200, longest run 1,028, at every factor.** ⛔ **The one clause that falls is *"thinner"*:
in the UPSAMPLED frame the bullet is written in, the rule is WIDER at 1/3 at every mean threshold it
has rows at** — over the RECT, 250/240/220/200/180 give `1/2` 7/6/4/4/4 against `1/3` 8/7/7/6/5, and
over a 30-row window y=196-225 (wider on purpose: the falloff already leaves the rect at both
factors) 8/6/4/4/4 against 10/8/7/6/5, same sign at all five either way — ⛔ **while the
STORED frame must not be quoted, because it is confounded by pixel pitch AND by the threshold (3-vs-2
raw rows at 250–220, 1-vs-2 at 200–180; normalised, 6-vs-6 then 2-vs-6) and the first draft of this
paragraph quoted the one threshold in it that favoured the conclusion.** *"Greyer"* is right and sharp:
rows under a mean of 100 go **2 → 2 → 0** upsampled and **2 → 1 → 0** stored. The mechanism is PHASE,
the same ink straddling two stored rows at 3x where it concentrated in one at 2x. ⚠️ One rect, one
page; **three** members are untouched (the six densest bands, `140x205+1660+2125`, and
`Riesman - 1954` p16's `900x150+300+2440`, which the step's own sibling sweep added to the class) —
⛔ **THAT COUNT IS ONE AS OF 2026-09-21 AND IT WAS ALREADY STALE WHEN WRITTEN DOWN HERE A SECOND TIME**:
the six bands were read the next day (`##### The two control bands, READ`, which corrected the same
sentence at the limits line and missed this copy of it) and the p16 rect the day after
(`##### The peak-contrast figure, MEASURED`), leaving `140x205+1660+2125` alone. ⛔ **And the p16 read
is the one that INVERTED: its `~250 paper` is nowhere in its own rect (0 source px above 200), where
p12's band reads 255.0 / 254.7 / 255.0 and `~250` is pessimistic — the same phrase, opposite errors,
because one rect's paper was read and the other's assumed.**
✅ **AND p16's OTHER RECT — the BRACKET, `200x260+400+1690` — WAS READ THE SAME DAY, WHICH LEAVES THIS
ENTRY WITH NO WHOLLY QUALITATIVE CLAIM** (`##### The bracket rect, READ ON THREE ARMS`): the mark's
ink falls **842 → 202-208** while the stencilled type in the SAME crop falls **3,747 → 3,561, 5.0%**,
and tick B reads **0 px in 0 components** against 47 on every recipe two independent runs tried.
⛔ **Two findings outrank the confirmation. The rect is NOT background-only** — 3,561 stencil px split
cleanly at column 95, refuting that step's own written prediction — **and THE STENCIL IS A FLOOR**:
`ink \ stencil` goes **225 → 186 → 149 → 0**, so at the bar the type zone's ink IS the stencil set and
the bracket is that one mechanism with its floor at zero, not a second one. ⚠️ **Its `1/3` and `1/8`
bracket-zone cells are recipe-dependent** (three recipes, 202 / 202 / 214 against a published 208) —
the queue's `c28-composite-recipe` — ⛔ **while its spine window, which the adoption first called
*"unreconstructible"*, was solved by the adversarial review of that same diff: 186 rows at rect rows
10..195, unique, and it is the stated *"padded 2 px"* that is wrong, not the 186.** And
⛔ **the 10-row band does not hold the whole rule TODAY, not merely at some further step**: the
falloff already spills past y=215 at both downsampled factors — y=216 reads 246.1 at 1/2 and 225.9 at
1/3, y=217 249.5 — ⛔ **and not past its FIRST row, which a draft said: y=206 reads 255.0 / 254.7 /
255.0, clean paper at every factor, and at 1/3 the first inked row is 208.**
✅ **`C27` HAS NO BOUNDED WORK LEFT AS OF 2026-08-26 — (c) SHIPPED, and its queue box is `[hold] needs:
owner`** (`#### The split, SHIPPED`). `Flattener.colourSaturationThreshold` is the colour decision's own
bar, 0.06, **equal to `pictureSaturationThreshold` so no page's output moves**; the two decisions can move
independently for the first time. ⛔ **No failing test is possible for a no-op split and that is said in
place**: the evidence is a mutant PAIR whose kill sets are **5 and 11 checks intersecting in exactly one**
— the equality check, which reads both constants. ⛔ **The finding worth more than the split: (b)'s
+93.0 KB / 1.048x is NOT a price for this bar** — four of those 13 pages read a mean saturation of
0.000–0.002, one reads 0.000 against a strict `>`, so no legal value reaches them — **and there is a floor
of ~0.008 under any useful value**, below which every cream-paper text page is re-promoted to three
channels (the 709 MB monograph's mechanism).
✅ **THE WINDOW BETWEEN IS MEASURED AS OF 2026-08-28 AND THE RECOMMENDATION IS TO LEAVE 0.06 ALONE**
(`#### The window, MEASURED`, from three committed artefacts with no new sweep). **It is not empty — 12 of
441 sampled pages are picture-route with `sat` in (0.008, 0.06] — and it is not usable**: the six pages
worth reaching are ranks **6-11 of 12** on the very statistic the bar reads, so **no value admits one of
them without admitting all five collateral pages above it**, and the top boundary is a **tie at `sat`
0.041** between `Stanford_1891` p2 (14 saturated components, under this entry's own noise band) and
`1954 - Why` **p7**, one of the owner's own red-ink verdicts. Best case **6 real of 11
(54.5%)** at `b` in [0.012, 0.022]; by bytes **85.6% of the spend buys no colour over the whole window**
(+50.1 KB on the six worth reaching against +297.7 KB on the six that come along; 85.3% at the recommended
band, and the two must not be printed beside each other), and ⛔ **77.7% of the whole window's cost is
TWO collateral pages whose all-text verdict FLIPS** (`bgF` 8→2), which is C28's ground and not colour's —
**0 of the six real pages flip.** ✅ **The discriminator that works is already in the tree: of all 48 grey
picture-route pages only 7 have `satFrac >= 0.01326` and exactly the 6 eye-read real ones fire — 0 false
positives over 48.** ⛔ **The tempting form of that — "agrees on 12 of 12 window pages" — is a check that
CANNOT FAIL and was caught in draft**: the threshold is the argmin of the positive class and
`sheetFrac <= satFrac` puts every unread negative out of its reach. ⚠️ Sampled corpus at `PAGES=2`, **do not
scale it**.
⛔ **THE TWO PAGES THAT MEASUREMENT NAMED AS ITS OWN RISK WERE READ 2026-08-28 AND ONE OF THEM IS REAL, SO
FIVE OF ITS FIGURES MOVE AND THE RECOMMENDATION FIRMS** (`#### The two unread window pages, READ`, the
queue's `colour-window-dump`). **`Glazer_2002` p1 carries a printed red masthead rule (one component,
297 px, stroke width 51) and the red "THE NEW REPUBLIC" brand banner in knockout type (four components,
142 px) — 439 of its 758 counted pixels, and it is published GREY today**; the other 319 px across 65
components are chroma fringe on the black display type, which is the mechanism this entry's first draft
attributed to `HarpersMagazine` p4 and the review refuted **there**. **`Stanford_1891` p3 is brown foxing on
the paper** — its two largest components, 725 of 795 counted pixels, and not one counted pixel on the
typescript — **a THIRD artefact class that is on the sheet AND in one region, so `sheetFrac` keeps it and
`topPx`/`topRun` read it as a mark**: 397 px at stroke width 11, 3.2x this register's own `topPx >= 124`
mark floor, which is therefore refuted as a mark test on a reading. What moves: the curve's `b = 0.011`
row **50.0% → 58.3%**, the headline **54.5% at [0.012, 0.022] → 58.3% at [0.008, 0.012)**, the spend share
**85.6% → 83.4%**, the two flipped pages **90.8% → 93.1% of the collateral**, and *"six of the eight
real-colour pages are reachable"* → **seven of the nine**. ⛔ **The `0 false positives over 48` becomes a
false NEGATIVE and cannot be repaired**: the same bar fires on the same six, and reaching the seventh needs
0.00550, which admits `Stanford_1891` p3 (0.00770) and `Atkinson_1939` p3 (0.00577) — **the real page sits
BELOW both artefacts that reaching it costs**, so `sheetFrac`'s published **2.96x** margin is **1.23x**.
✅ **RECOMMENDATION UNCHANGED AND FIRMER: leave 0.06 alone** — ⛔ **but `0.02` is no longer the number to
want** (it misses the confirmed red page); the replacement is **~0.011**, which is 1.4x the ~0.008 floor
against 0.02's 2.5x, so the fallback is worse placed rather than better. ⚠️ **Three of the five collateral
pages are still unread and `Atkinson_1939` p3 is the one that matters**, because it is what fires at the
repaired bar. The entry
is still OPEN because the pamphlet still loses its red; what remains is the owner's number.
✅ **`C29`'s routing half (A) SHIPPED 2026-08-25** — `#### (A) SHIPPED`. A third `RebuiltPage.Content` case
carrying no URL, a `passThrough: Set<Int>` on `flatten`, and `makeSearchablePDF` asking
`Flattener.digitalTextPages` **before** the rebuild instead of after it: the fixture's cover page comes out
with its **302 characters, character for character equal to the source's**, where it read 0. ⛔ **The defect
that mattered was not in `flatten` but in `Recogniser`**, which keyed its results by position in the *image*
list — one page without a bitmap would have shifted every later page's text onto the page before it, on a
file whose page count is right; the work list now carries page numbers and a passthrough page is recorded as
an **empty** entry rather than left absent, because `missingPages` refuses a whole document over a gap.
`JBIG2.assemble` needed no change: `encoded.count == bitmaps.count` fails and the Flate fallback was already
there. ⛔ **BOTH OF (A)'s NAMED GAPS MOVED ON 2026-08-25 — `#### (B) MEASURED`.** The literal argument at
`Model`'s call site **is** pinned now: six checks run a document end-to-end through `makeSearchablePDF` on a
document with a born-digital page — the thing no earlier end-to-end check used — read the **published** file,
and go red on a build that computes the set and passes `[]` (`1278/1280`, two `FAIL` lines, predicted). And
**(B) is measured on a real corpus document run both ways** — `1954 - Why.pdf`, **1,375,847 B** on the Flate
route against **439,686 B** on JBIG2, **+936,161 B, 3.13x**, of which ⛔ **90.8% is the LOST MRC
RE-LAYERING and not the compression** (production's own `Layered 5 picture pages, saving 830 KB` against the
Flate arm's nothing), so the decision is that **the fallback is not the answer**; the `qpdf --empty --pages` splice is
demonstrated at **456,171 B** with nine `JBIG2Decode` streams surviving. ⛔ **Do not quote the generated
fixture's 1.34x** — sparse synthetic type understates this 2.3x. ✅ **(B) SHIPPED THE SAME DAY —
`#### (B) SHIPPED`**: `JBIG2.Page.Stream` gains a `.passthrough` case so `encoded` stays DENSE (a short array
would have layered one page's word boxes onto another's pixels — `(A)`'s `Recogniser` defect in a second
place), `assemble` REFUSES such a page rather than skipping it, `JBIG2.splice` interleaves it back out of the
user's own file, and `overlay` takes a page list passed as BOTH `--from` and `--to` so the spliced page is
never stamped and never wrapped in the form XObject C23 measured translating a cropped page by (50, 96).
⛔ **Two refusals: an OUTLINE (`--empty --pages` drops the `/Outlines` tree) — 16 of the 42 affected
corpus documents — and a READER'S MARK on the passthrough page, which is a
REGRESSION guard and not a byte one: measured, the splice carries `/Annots` and the `/Highlight` behind it, so
the transplant would add a second copy and then refuse the whole document.** Fixture 49,425 B on both arms
before, **44,970 against 49,425** after; suite **1,281 -> 1,314**.
✅ **BOTH REFUSALS ARE PRICED ON THE POPULATION AS OF 2026-08-26 AND THE ANSWER IS 22 OF 42, NOT THE 26 THIS
FILE PUBLISHED — the two are DISJOINT, 16 with an outline and 4 with a mark**
(`Tools/score-annot-marks.swift`, `C29-MARKS-2026-08-26.tsv`,
`#### The population re-measured, 2026-08-26`). ⛔ **The `/Annots`-count clause the re-measurement was
opened for fires on 0 of the 392 born-digital pages** — `rawAnnots == surfacedN` on 392 of 392 — so the
figure moved for the ORDINARY reason, a real highlight on a born-digital page in 4 documents. ✅ The outline
column reproduces the published 16 through PDFKit where the original used `qpdf`. ⛔ **`/Link`'s exclusion is
what makes the fix reach anything: 776 of the 830 annotations on those pages are links.**
⛔ **THAT REFUSAL'S PREDICATE ANSWERED "NO MARKS" WHERE IT COULD NOT SEE, and its seven review findings are
WORKED as of 2026-08-26 — `#### The seven review findings, WORKED`.** `Annotations.anyCopiableMark` read
`false` on a file PDFKit could not open at all, which sends it to the splice where a missed mark is copied
twice and `transplant` **refuses the whole document**; every "cannot tell" about a page it reached answers
`true` now, costing bytes instead of output. ⚠️ **NOT a product defect: both branches are unreachable from
today's pipeline**, because a non-empty passthrough set is proof `Flattener.open` succeeded — R31/R32/H2, and
a first draft's *"the user gets no file at all"* is retracted. ⛔ **AND ONE OF THE TWO "REFUTATIONS BY
MEASUREMENT" THE WORK SHIPPED WITH WAS ITSELF WRONG — asserted as an `ENGINE ASSUMPTION` that was RED ON A
CLEAN BUILD.** A locked document reports `pageCount` 1 and surfaces **NO** annotations, and its page dictionary
is out of reach, so the raw `/Annots` count is **-1**: the draft's sabotage had left the `>= 0` blindness guard
in place and read its `true` as *"the loop ran"*. ✅ The conclusion survives on a measured footing — cut the
`isLocked` line and the suite is **1336/1336**, so nothing can watch it fail — and the second refutation holds
with its arithmetic fixed: **five of fifteen** `copiedSubtypes` have no `PDFAnnotationSubtype` constant, not
four of fourteen, `/Squiggly` among them, and `/Polygon` is the only one measured. ⛔ **And `--empty --pages`
DOES keep `/PageLabels`, qpdf 12.3.2**, so "no document-level structure" was an overstatement — corrected in
**six occurrences across five files**, the sixth being this file's own statement of the refusal, which the
strand's file-counting sweep missed. Four checks that **could not fail** are replaced (two of them found on the
adoption: the password control and the raw reader's ordinary answer), and the passthrough page goes through
real qpdf at a MIDDLE and a LAST position for the first time. Suite **1,314 -> 1,336**, no skips. What is still
untouched is the **120-character bar**, under which a short
born-digital page is rasterised and no report line names it.
✅ **`C29` has the FIXTURE it said it needed first, as of 2026-08-23, and today's wrong answer is PINNED**
(`#### The fixture, and today's answer PINNED`): a nine-page JSTOR shape whose cover page reads 302
characters and is not a page-sized image, whose other eight pages ALL clear the 120-character bar so the
character count decides nothing, and whose sample is `[1, 3, 5, 7]` — index 0 appearing only at page
counts 1-4 over a 400-count sweep. ⛔ **All four pins were re-worded to statements by (A) and NOT ONE of the
four assertions moved** — the routing's evidence is new opt-in rows beside them; read the routing section.
✅ **AND IT HAS A REPORT AS OF 2026-08-25, so the loss is no longer silent** — `#### The report, SHIPPED`.
The run report names every page that was born digital and got rasterised anyway; `hasDigitalText(in:)` now
votes through an extracted per-page `pageHasDigitalText`, and run A of the watch-it-fail pair reds two
**pre-existing `PINNED` checks**, which is what says the extraction is wired into the product rather than a
dead duplicate. ⛔ **The population is 42 documents and 392 pages of 16,987, not this entry's one**
(`C29-CORPUS-2026-08-25.tsv`), `hasDigitalText` is `false` on **38 of the 42**, and the corpus turned up a
**second mechanism**: `Schwaller` is 167 born-digital pages of 300 and still reads `false`, because its
sample votes 2–2 and `digital * 2 > sampled` loses ties. It was the report and not the fix; the fix is (A),
above, and that tie-break is still unfixed — it decides the **warning** and no longer decides what gets
rasterised.
✅ **AND THE ROUTING HALF IS RE-SCOPED AS OF 2026-08-25, ON A MEASURED PREMISE** — `#### The routing half,
RE-SCOPED`. `CGContext.drawPDFPage` copies a born-digital page into a new PDF with its text intact
**character for character** (302 chars, exact string, over three hops) where the rasterising arm of the same
helper reads **0**, and four `ENGINE ASSUMPTION` checks pin it. ⛔ **The JBIG2 blocker is not where the
report's map put it**: the JBIG2 arm is guarded by `encoded.count == bitmaps.count`
(`Model.swift:2174-2175`) whose `else` **is** the Flate route, so a mixed document falls back by arithmetic
and `JBIG2.assemble` need not change in the first commit. The real blocker is `Recogniser`, which keys its
work list and its results by array position (`:146`, `:163`) and whose `imageURL(of:)` returns a
non-optional URL. ⛔ **And the third `Content` case costs 20 sites that pattern-match the enum, of which the
8 exhaustive `switch`es are the SAFE half** — but only **one** of the 12 `if case`/`guard case` sites is
genuinely silent, `Tools/score-text-route.swift:713`, which would print `already 1-bit` for a passthrough
page into a TSV this register quotes — ⛔ **wrong: there are TWO, `Tools/score-shape-term.swift`'s own
`guard case .jpeg` being the same shape with the same string, found when (A) was written** (⚠️ cited as
`:1172` until 2026-08-26, when `shapedump-exit` added 17 lines to that file's header and moved it — a line
number in prose is a fact about a revision) — ; **five of the twelve red at run
time** and a draft's claim about
`Tests/main.swift:3049`/`:5752` was refuted by the review of this diff. ✅ **Every prediction in that section
held when (A) was written**, including the one silent site, which is now two verdicts.
**Back to C28**, whose shape term this paragraph interrupted: it rescues **13 of the 16** measured content
losses, and its failure direction is bytes rather than
content: `bgFactor = allText ? max(caller, 8) : caller`, so a term that only ever refuses the verdict can
only ever store a page at *more* resolution. What keeps it open is three hand-made marks, one of them
(`_1939_Former students` p2, `outPx` **0**) unreachable from this seam at any value of any constant,
because the page-wide Otsu is blind to pale pencil upstream of the map. Read `#### THE DECISION` for why
the layering seam and not the 1,020x cheaper stencil widening, then `#### The wiring, SHIPPED` for the
negative control — two binaries one term apart, the fixture's background **153** px against a ceiling of
154 without the term and **612** px with it, and the same page with that word recognised shrunk on both —
and for the one thing it does **not** claim: no corpus sweep was re-run, so "12 of 12" is still the
tool's 2026-08-21 figure, now with a live port check over it. ✅ **`#### The owed fixture` (2026-08-22)
then closed the two things that wiring left behind, changing no shipped behaviour**: `shapeRunHigh` is no
longer a known-survivor mutant — the fixture `mutate.py` itself asked for now exists, three ways, with a
positive control — and `score-mrc`'s ungated `--self-test` is **green under the third term but green by
construction**, because its all-text fixture's `inkOutsideText` is exactly 0.0 and the term cannot reach
it at any value of any constant. ✅ **And that fixture is a RED CHECK as of 2026-08-23, not a probe's
reading** — `#### shapeRunHigh RUN through mutate.py`: the mutant is `killed`, 3,475 s, `1246/1247 passed`,
by **exactly one** `FAIL` line, the check `6d0caa1` added at 00:10 the same day. **Two** claims of the
section above go from argued to measured off the *green* checks in the same run (the too-tall fixture, the
two grouping fixtures) — ⛔ a third was drafted off the calibration check and **retracted** by the review of
this diff, because that check cannot fail at any value of this constant. ✅ **AND SO IS THE OTHER HALF OF
THE PAIR AS OF 2026-08-24 — `#### shapeHeightHigh RUN through mutate.py`**: `const/shapeHeightHigh`
(`3.0` → `99.0`) is `killed`, 3,415 s, `1246/1247 passed`, by **exactly one** `FAIL` line, the too-tall
fixture's — so nothing in the owed-fixture material is probe-only any more, and six mutants this entry and
`depth-cap` catalogued and never ran, now **three**. ⛔ **It has NO informative green either, and the
review of its own diff had to retract both I claimed in advance**: a monotonicity argument bounds which way
a check can move and says nothing about whether the mutant changes its input at all, and raising a ceiling
from 75 px to 2,475 px changes nothing on two fixtures whose every component is 30 px tall. ⛔ **The same
argument part-retracts the yield of the run above** — of its three credited greens only `c28GroupsC26`'s
was ever evidence; see that section's part-retraction. The kills, the objecting-check counts, the costs and
the attribution all stand.
✅ **THE WIRING ITSELF IS A RED CHECK AS OF 2026-08-23 — `#### C28-alltext-ignores-shape RUN through
mutate.py`**: `logic/C28-alltext-ignores-shape` (`return groups == 0` → `return true`) is `killed`, 3,407 s,
`1244/1247 passed`, by **exactly three** `FAIL` lines, and **all three were added by `fbf6d87`, the commit
that shipped the wiring** — the first of this entry's three mutants whose behaviour change shipped with its
own biting checks, where `shapeRunHigh`'s came a commit later and C24's seam had none. The first failure
prints `153 wide of 1224, ceiling 154`, the same two numbers as the by-hand control in `#### THE DECISION`.
⛔ **It has NO green yield and that is stated in advance rather than retracted**: `return true` is one-sided,
so the only checks it can falsify are the three, and the two that most look like yield (the `inkOutsideText`
assertion, whose field is set *before* term 1's guard; the positive control, which the mutant forces) are
named there as unable to fail. ⚠️ All three sit on **one** fixture. ⛔ **And the run found a defect in
`mutate.py`**: it recorded the first check as the bare tag `C28`, because `run()` split each `FAIL` line at
the **first** `" — "` — a separator inside **38 of 1,236** check descriptions — damaging **7 of the log's
83 rows**, of which a first draft found 2 because its detector could only see a truncation leaving a bare
tag. ⛔ **`FAIL a — b` is ambiguous, so the fix is to keep the whole line and NOT to split**: the draft's
`rsplit` was refuted by the review from two real call sites (a name whose own separator is last, called with
no detail; 22 details that carry one). Six self-test checks (30 → **36**), the first three measured
mutually redundant and said so in place, both rejected parses watched failing. This run's row is repaired
byte-identically to what the fixed tool writes; the other six cannot be, though five of their names are
recoverable from the tree. Four of the six catalogued-and-never-run mutants were left after that run, from
five — ✅ **three after `#### shapeHeightHigh RUN through mutate.py`, and TWO after
`#### lineMinimumMembers RUN through mutate.py`, both 2026-08-24; the two left are `depth-cap`'s and
nothing in this entry's own material is unrun.** ✅ **AND ZERO AFTER `C24`'s
`#### Both caps RUN through mutate.py`, 2026-08-25 — that six is now fully discharged**, both
`depth-cap` mutants `killed` (227 s by six objecting checks, 244 s by three) in **705 s** end to end for a
baseline and both. ⚠️ **The dictionary cap's three is 2026-08-25's and is now FOUR**: that run's own
finding was that the three was a *coverage boundary* — `Flattener.pageIsAnImage` flipping on fixture
page 13 with nothing pinning it — and `#### The coverage boundary, CLOSED` closed it on 2026-08-26 with
one check and a `--rerun` (292 s by six, 289 s by four, 875 s end to end, baseline **1,343 → 1,344**). ⚠️ **That does NOT empty the catalogue**: 25 entries still had no row at all — **21 from
2026-08-30**, when `const/textPageInkOutsideThreshold`, `logic/C26-inkbar-override-ignored`,
`logic/C26-inkbar-nil-refuses-the-page` and `logic/A11.1-publishVerified-gate` became the first four
worked off, `killed` by six, four, eleven and three, leaving coverage at **83 of 104** — ⛔ **`84 of 105`
and the census still **21** as of 2026-09-10, when `const/lineGapFactor` was ADDED and run in one session,
so the numerator and the denominator moved together and the census did not move at all: C28
`#### The grouping's other constant`; **`85 of 106`** and the census **still 21** as of 2026-09-11, when
`const/lineGapFactor-raised` did the same thing a second time — C28
`#### The gap term's own fixture`** — ⛔ **and `88 of 109` with the census **still 21** by the end of
2026-09-11, three more add-and-run steps having done the same thing three more times:
`const/shapeHeightLow-lowered` (`#### The height floor's own fixture`), `const/shapeMinimumArea`
(`#### The area floor's own fixture`, which logged TWO rows, a `SURVIVED` and a `killed`) and
`const/lineMinimumMembers-lowered` (`#### The member floor's other direction`). This sentence sat at
`85 of 106` through the first two of those, which is the drift it warns about happening to itself —
re-derive the pair from `mutate.py`, never from here** — (T5
`#### The first never-run mutant`,
`#### The seam's other end`, `#### The seam's second and last`, `#### Invariant 2's own gate`) — they are
owned by the queue's own `mutants-never-run` item as of **2026-08-25** (⚠️ this read
*"as of the same day"* and the 2026-08-30 insertion broke the referent), and this six was always C28's and
`depth-cap`'s share rather than the census. ⛔ **That last run found the SIBLING of the truncation
above, in the same field**: `run()` also capped the *list* at `fails[:3]`, so a row killed by five named
three. It was already live — swept over all **84** rows, **five earlier rows lost 10 names** — the count
was right in every one, and the fix keeps them all (`killed_detail`, two more self-test checks, 36 →
**38**, both watched failing at `[:3]`, and the raised-cap `[:6]` watched failing too). ⛔ **And that run's
own cost retires "the estimator's high end has held": 479 s against a startup line reading "roughly 100-116
minutes" — 14.5x HIGH**, because `estimate_minutes` spans the five newest log rows and all five were
clamped-era. The mirror of C24b's 4.22x-low reading, from the same window; it self-heals as those rows age
out and is **not** patched. ⚠️ **The healing is counted in ROWS, not in runs, so the four-run form
published that day holds only for one-mutant runs**: 2026-08-25's two-mutant run aged two clamped rows at
once, leaving the window `[3407, 3415, 246, 227, 244]`, so the drop lands on the third run from there
rather than the fourth. That run read **14.8x** high — the third reading of this estimator and the second
in the same direction. ✅ **THE WINDOW IS CLEAR AS OF 2026-08-26** — `[246, 227, 244, 292, 289]`, no
clamped row left — and 2026-08-25's *"single digits after two more mutant rows"* holds in substance: a
1-mutant run's high is **9.73 min**, printed `10` by rounding. Its arithmetic was off the surviving rows'
max of 246 and the two rows that arrived are dearer than every row they joined, so it was 1.5 min low.
⛔ **The fourth reading, 11.7x high (`11-171` over 875 s), is the LAST CLAMPED-ERA one and not a reading
of the clear window** — the startup line prints before the run, and its own span says `227-3415 s`. Re-run
over the clear window the same job estimates **11-15** against 14.6 measured. **No live reading from a
clear window exists yet.**
✅ **`#### The replica retired` (2026-08-23) then repaired the instrument the wiring broke, and it too
changes nothing in `Sources/`**: `Tools/score-text-route.swift` had a hand-written copy of
`pageIsAllText()` two terms deep against the shipped guard's three, so it printed `all-text` on exactly
the sub-bar pages this entry exists for — **wrong in the direction that hides C28**. It now reads
`MRCLayers.shrunkAsAllText` back from production. Measured on `Ford_1941_Speech_.pdf`: **p6 flips
`all-text` → `picture` and p1–p5 do not**, every other column byte-identical on 6 of 6 rows; the
all-text aggregate falls **436,633 → 224,977 B** (48.5% of it was a page production never shrinks); and
the priced-bar per-page cost was out by **exactly 2x** (100,626 → **201,252 B/page**) while the `barDelta`
column beside it read `same`.
⛔ **THIS HEADER CARRIED TWO OF THAT SECTION'S OWN RETRACTED DRAFT FIGURES UNTIL 2026-08-23**, found by
the sibling sweep of `c28-comment-fixes` and corrected here: it said "twelve other columns", which the
section itself refuses — `page` is the row key and three bar columns are the literal `-` with no `INKBAR`
set, so **eight** carry information — and it said "out by **3.2x**", a ratio of ratios (5.76/1.79) over
two different sets that the review of `0707699`'s own diff refused, where the figure to quote is the
per-page cost at 2x. **Three** other copies were already right — the section below, `CLAUDE.md` and
`Tools/README.md` — so this summary was the only stale one, which is the failure mode this header is most
prone to and the reason its own instructions say to move it in the same commit.
✅ **`C30`'s FORK IS CLOSED ON THE WHOLE DOCUMENT as of 2026-08-23 — page 5, the one page
`#### The fork, settled 2026-08-22` did not settle, settles the same way page 1 did, so C30 is ONE
mechanism and not two.** `#### Page 5, settled 2026-08-23` and `C30-PAGE5-2026-08-23.tsv`: three
consecutive whole-document recognitions are **byte-identical** (run variance **0.0000**, which also
re-labels page 1's 0.0143 — that spread is three different *paths*, not three runs), the shipped output
reproduces from today's build on all nine measure columns of both pages, **98 of page 5's 146-row gap is
one 115-px observation whose entire text is `ASSAME`** (sensitivity: remove it and the gap falls
0.1825 → **0.0429**, 2.995x page 1's rather than 12.729x), and the published layer holds a line that no
fresh observation contains **and whose words are absent from page 5's fresh text altogether**, so no
regrouping or hyphen join can have produced it. ⚠️ **A partial writer drop on top of that is NOT
excluded** — the pipeline's own observations were never captured, and `deduplicated` is a removing path
nothing here measured; what moved is the ceiling, from "order of ten lines" to **three**. ⛔ **The finding
worth more than the verdict:
production recognises `Flattener.flatten`'s REBUILT BITMAPS (`Model.swift:1919`/`:1922`, and `pdfimages`
reads `jbig2` on all six pages, so the bitmap arm demonstrably ran rather than
`Recogniser.swift:141`'s render fallback) while
`make-observations` recognises a plain render, so every instrument C30 has used measures a different
image than the app does.** C30 stayed open until **2026-09-25**, when it was FIXED (see the entry): the fork was not the fix, and **23** lines of clean 1951
type on page 5 have no text layer over them at all — **13** of them missed by *both* paths.
✅ **AND IT HAS AN INSTRUMENT IN THE TREE AS OF 2026-08-25 — `Tools/score-text-voids.swift`, the tool
`#### What a fix has to satisfy` has asked for since 2026-08-22 and the first C30 measurement taken on the
pixels production actually recognises** (`#### The instrument, in Tools/ as of 2026-08-25`,
`C30-VOIDS-2026-08-25.tsv`). It divides rows of ink by rows of ink no word box covers, so its numerator is
unreachable from the observation list and a page can fail it while `words=` reads 100% — group 5 of its
13-group `--self-test` is that property as a check, not a claim. ⛔ **Quote its page-derived column and not
its shares**: `inkRows` reproduces `C30-FORK-2026-08-22.tsv`'s at **0.9913x-1.0007x on 6 of 6 pages** across
a different rasteriser and 4x the resolution, and page 1's longest inked-and-unboxed run is **683** rows at
400 dpi = **170.75** at 100 dpi against the fork's **171** — this entry's founding headline, reproduced
through a different image. The recognition-derived shares diverge **0.7767x-1.7077x** and that divergence is
C30's own finding rather than a defect.
✅ **AND THE TILING CANDIDATE IS PRICED AS OF 2026-08-25, ON ALL SIX PAGES INSTEAD OF ONE HALF OF ONE**
(`#### The crop experiment, in Tools/ as of 2026-08-25`, `C30-TILES-2026-08-25.tsv`): `TILES=n` recognises
the same page as `n` horizontal bands and scores the union against the same ink, and over the six pages the
void goes **5,561 bare rows → 404 at eight bands, 13.76x fewer**, with **4 of 6** pages reading 0 and words
**2,080 → 3,577**. ⛔ **But it is NOT monotone and no band count is sufficient**: `TILES=4` is worse in
aggregate than `TILES=2` (2,487 against 1,663), p3 reads **918 → 0 → 255 → 216** over 1/2/4/8, and on p6 at
four bands the tiled arm returns **fewer** observations than the whole page. ✅ The recovery is text and not
stretched boxes — words per observation is flat (8.63 whole against 8.60 at eight bands) and the new
`TILETEXT=` dump shows **752** distinct 4+-character tokens gained against **146** lost, gained > lost on
6 of 6 pages. ⛔ **Dense clean synthetic type does NOT reproduce the void** — three generated pages at 400
dpi, glyph 41.7/33.3/27.8 px, `obsN` equal to the drawn line count on 3 of 3 — so the fixture bullet's own
prescription is refused and the ingredient is still unknown. ⚠️ Still an instrument: nothing in `Sources/`
moved, `Recogniser` has no tiling seam, and the time cost of `n` requests a page is unmeasured.
✅ **AND THAT SECTION'S OWN OWED DEBT IS DISCHARGED THE SAME DAY — the tool's refusals are WATCHED**
(`#### The tool's refusals, WATCHED as of 2026-08-25`): `Tools/fault-inject.sh text_voids`, **8 rows**,
`8 passed, 0 failed`, the FOURTH Swift tool of the thirty-two in `Tools/` whose own refusals any case
exercises.
⛔ **The finding is worth more than the green: with the two new terms cut out of the exit-7 condition the
tool still PRINTS `⛔ 2 TEXT DUMPS FAILED TO WRITE` and exits 0** — a loud diagnostic under a green status,
which every caller that keys on the status reads as success. Two one-token sabotages, `6 passed, 2 failed`
each on **disjoint** pairs, both predicted by name before the run. ⚠️ Exit 7's third branch
(`bands.isEmpty`) is **unreachable from the command line** rather than unwatched — `bandRanges` returns `[]`
only for a height of 0, reasoned off the guards and not measured — and the band row asserts which arm fired
so a green row cannot be the wrong one. ⚠️ Exits **6** and **3** still have no row, the band row depends on
Vision refusing a ≤2-px dimension rather than on anything in this repo, and `fault-inject.sh` is in no hook.
⛔ **The sibling sweep found the same headline LIVE in `Tools/score-shape-term.swift` — it printed
`⚠️ dump missing …` and exited 0 on a failed `SHAPEDUMP` write** (6 is identity and 7 is the port check), in
the tool every published C28 figure came from. ✅ **FIXED 2026-08-26 as the queue's `shapedump-exit`: it is
exit 4 now** — borrowed from `score-text-route`'s `INKDUMP` rather than invented, tested last so 6 and 7
still win, and watched failing at `2 passed, 1 failed` by `fault-inject.sh shape_dump`'s three rows (C28
`#### The instrument's own missing exit, FIXED 2026-08-26`, where the negative control — identical rows, an
identical summary and seven sha256-identical PNGs across the two binaries — is why no published C28 figure
moves). ⛔ **And the review of that diff found a second, older defect in the same file: exits 6 and 7 had
been leaking the scratch `work` directory since 2026-08-22, because a top-level `exit` does not run the
`defer` that owns it.** All three go through `stop(_:)` now. ⚠️ And the sweep's own first draft had every one of four sibling exit codes wrong — read
the section, not a summary.
⛔ **One thing does not port and
it was measured: `Flattener.otsuThreshold` clamps to `[90, 230]` and `artefact.py`'s does not**, so the
shipped function reads 90 where the reference reads 0 on a two-valued buffer — same argmax, the clamp is the
whole difference, and it selects the same pixels only *because* the buffer is bimodal, i.e. on a `.bilevel`
page and not a `jpeg` one.
**`C26` is `FIXED` as of 2026-08-20** — its constant moved 2026-08-19
(`textPageInkOutsideThreshold` 0.08 -> 0.045, the owner's decision on a complete campaign, so the 16
corpus pages the sweep named keep their tone layers at the caller's factor) and the next day the
three pages it was opened on were **rendered and the drawings are back**:
`verdict` reads `picture` where it read `all-text`, the backgrounds are 612 px rather than 153 px,
and at 1:1 the cartoons are whole and legible where they were smudges. ⛔ **The verdict is those
crops, not a ratio.** This paragraph led with "fine-detail energy is 5.7x / 6.3x / 5.7x what the old
bar published, against a body-text control where both backgrounds are identically blank" until
2026-08-20, and it is retracted: blank rects on the same page measure **3.6x–14.2x**, that control
being the worst of them, so the ratio tracks the downsample factor rather than returned content.
What holds is absolute — the drawings read **11.99–12.35** against a measured blank-paper floor of
**2.10–2.51** as shipped, and **1.87–2.16** at the old bar, which is that floor. See C26's
`#### The rendered proof on the founding pages` — and note that the ink-fraction column *understates*
p6 badly (32% of its ink lost against 84% on p4 and p7), because an 8x
blur keeps solid black while destroying every line. `C27` was found on the same document as C26,
hours after `1.13.0` shipped; `C28` was opened out of C26's own campaign on 2026-08-19. `C27` is
fidelity rather than content loss — spot colour discarded because the bar is on the page's mean
saturation — and it is a separate mechanism from C26 with a separate constant; neither fix
addresses the other. ⚠️ **What C26's fix left, and what `C28` is:** 32.4% of its byte
cost lands on two pages a reader cannot tell apart — so a page-wide threshold is a blunt instrument
rather than the answer — and, measured 2026-08-19 over the committed sweep, **73 sampled pages in 22
documents are still shrunk 8x/16x at the new bar**, seven of the eight nearest of them in the three
documents already proven to be losing lines of prose on other pages. ⛔ **Those eight were
RENDERED 2026-08-20 and 4 of the 8 lose content** — two lines of prose each on `Broadhead - 1994` p3
and `Jones et al_2010` p5, table figures and column heads on `Scott_TK` p3, a handwritten signature on
`Atkinson_1939` p3 — and **no value of the constant separates them**: sorted by `inkOutsideText` the
eight read lose / no / lose / no / no / lose / no / lose, so the two sets interleave and a bar low
enough to protect all four losers protects all four non-losers too. The *lowest* of the eight loses
two lines of prose and two of the four highest lose nothing. Within `Broadhead - 1994` alone the
fraction does order its eight rendered pages perfectly, missing p3 by at most 0.00005 — so
`p8`-against-`p10`, which this paragraph used to offer as the bar being arbitrary, is the bar getting
that pair right; the argument now rests on the interleaving across documents instead, and on
`Atkinson_1939` p2-vs-p3 and `Jones` p12-vs-p5, where the fraction is wrong.
57.4% of what un-shrinking those eight would cost lands on the four that lose nothing.
⛔ **And the other 24 of the 31 in the six read documents were RENDERED the same day, which moves the
population a third of the way to zero**: `Jones et al_2010` p7 loses the paper's **estimating
equation** at `inkOut` **0.0137** and its p2 loses a word at **0.0008**, against a previous lowest
measured loser of 0.0353 — so "the pages near the bar" was never the population, and **27 of the 73
print `0.0000`** and, measured over all four sub-steps, **25 of them** cannot be priced through the
override seam at all (no legal `INKBAR` is below 0; two of the 27 flip anyway).
`Broadhead - 1994`'s two lowest pages lose nothing, so its window holds at [0.04415, 0.04495] while
`Jones`'s is at most 0.0137 — **two documents that each order their own pages, with disjoint windows**,
and 94.7% of the 13 priced pages' +1,566,676 B buys nothing a reader would miss. ⛔ **20 more were
rendered the same day — the twenty highest-`inkOut` of what was left — and 8 of those 20 lose
content**: three lines of 1958 magazine prose over two pages, a line and a word of 1930s
typescript, a word of 1913 body text, a page folio, a signature, a pencilled annotation and a
hand-inked margin number. The headline there is that **the four pages of the 41 with the most ink
outside the recognised words lose nothing at all**, while six pages between `inkOut` 0.0051 and 0.0165
lose content — so a bar protects the wrong end of its own range first. ✅ **The last 21 were rendered
the same day, so the population is CLOSED: all 73 read, and 16 of the 73 lose content, 12 of them type
and 5 a hand-made mark.** 2 of the last 21 lose something a reader needs — the words
`their education,` and `but` on `Williams_1958_DEMOCRACY OR MERITOCRACY` p1 at `inkOut` **0.0023**, and
a pencilled annotation on `_1939_Former students` p2 at an `inkOut` that **prints `0.0000`**, a page no
*usable* bar reaches — read the ⚠️ below `#### The other 24…` for why "prints 0.0000" is the strongest
statement the seam supports, and `#### The last 21…` for why neither reading of it leaves a usable bar.
⚠️ Three figures the entry was carrying are corrected by that render:
**25 of the 73**, not 27, cannot be priced through the override seam (two pages print `0.0000` and flip
anyway); the page with the **highest** out-of-stencil ink fraction of the 21 — 11.65x its own
`inkOut` — loses nothing, because on a pale typescript the map's page-wide Otsu catches a rim the
stencil's Sauvola mask does not; and that same global Otsu **misses** pale pencil on a shadowed
photographed sheet, which is how p2's loss was nearly filed as "nothing". **The campaign total is 86
pages rendered, 24 losing content, 19 type and 6 hand-made — with one page in both buckets, so those
two no longer sum to the 24** (corrected 2026-08-21; see the question-3 paragraph below).
✅ **C28's question 5 is FIXED 2026-08-20 — the run report now names every page it published with the
ink outside the recognised words stored at an eighth**, with that page's own fraction beside it, on
the success path only and with **no bar on the fraction**: the four sub-steps proved the losers and
the non-losers interleave when sorted by it, and one measured loser prints `0.0000`, so any filter
would drop a page known to lose content. C28 stays OPEN — ⚠️ but as of **2026-08-22 all five of its
questions are MEASURED**, question 4 at both of its seams (layering 2026-08-21, `textRegionMask`
2026-08-22), and **nothing is wired**, so what is left of the entry is the decision and the wiring. ⛔ The report is a report and not a fix: it says
which pages were degraded, it does not stop them being degraded.
✅ **And question 4 now has a CORPUS figure at the layering seam, 2026-08-21** — per document over all
16,987 pages, **~127 pages are still shrunk 8x/16x and ~19 of them lose content, 0.11% of the
corpus**. The shape term's wiring refuses **~18 of the ~127** for +2,694,515 B and rescues **~14.7 of
the ~19**; the cheapest page-wide bar refuses **~60** for +8,289,863 B and rescues **~17.9**. So the
term is **30.9%** of the bar's pages and **32.5%** of its bytes, against the 39.0% and 38.1% these 41
sampled rows read. `#### The corpus figure` is the measurement.
✅ **AND THE `textRegionMask` SEAM IS PRICED 2026-08-22, which was the last thing under this entry
unpriced at any scale — so question 4 is measured at BOTH seams and every one of this entry's five
questions now has a measurement.** Letting the accepted line groups into the 1-bit stencil costs
**789,825 → 792,140 B, +2,315 B, 1.0029x over the same 16 pages** the layering-seam wiring refuses for
+2,362,625 B — **0.098%**, 1,020x cheaper — with **6 of the 16 getting CHEAPER** (`fillHoles` hands the
background a smoother image, recovering 47% of the stencil's growth) and **2.12%** of the spend on pages
that lose nothing against 15.5%. Per document: **the same ~18.42 pages for +2,728 B** against
+2,694,515 B, **0.068% of C26's shipped ~4.0 MB**. The positive control is at 1:1 —
`Jones et al_2010` p7's estimating equation is blank in the shipped stencil and fully legible in the
widened one, for +369 B (`WIDEN-STENCIL-2026-08-22.tsv`, `#### The price at the textRegionMask seam`).
⛔ **Cheap in bytes is not cheap in correctness, and the same run measured both halves**: on
`1881 - Harry Wilcox` p2 the widening turns a pen ornament into a hard-edged 1-bit blob — R57's failure
mode on a page that loses nothing — and because a widened region lowers `inkOutsideText`, the widening
moves every page TOWARD the all-text verdict that shrinks backgrounds 8x (`1954 - Why` p4 goes
0.0540 → 0.0524 against a bar of 0.045, so a more generous rule re-destroys the cartoon C26's bar move
rescued). **Nothing is wired**; `Sources/` is untouched.
✅ **AND `mrcBoxPadding`'s 25% COLLAR IS PRICED OUT OF THAT FIGURE AS OF 2026-08-22** — a stranded
attempt from the same base commit unioned the same bounding rects into `region` **without** the collar,
so the pair isolates it: over the same 16 sub-bar pages **+2,259 B against +2,315 B, so the collar is
2.42%** of the price where the wiring would be judged, and **22.26%** over the 6 firing picture pages,
where the harm is. ⚠️ Not an independent implementation — the same tool, one step different — and both
ratios are claims about small sets (76.7% of that 22.26% is two pages of one document). ✅ **It splits
the delta by LAYER, which isolates the `fillHoles` saving its own section's review refused as
unisolated**: stencil +4,303 B **dearer on 16 of 16**, background −2,076 B **cheaper on 16 of 16**,
foreground +32 B — and on the picture pages the largest term is the **foreground**, +3,071 B, 1.91x the
stencil's. ⚠️ 4 of these 16 have a falling total, against the padded run's 6; the two counts belong to
different widenings and must not be merged. ✅ It reads `shrunkAsAllText`, `backgroundWidth` and
`inkOutsideText` back from production rather than inferring or recomputing them, so the all-text hazard
is a measured 0 over 26 rows instead of a string proxy. ⛔ **The seam it used is REJECTED and `Sources/`
still does not move** — `main` already documents the decision against a new override there, and with the
tool half superseded it would have no caller. ⚠️ It also corrects the hazard arithmetic above:
`0.0524 - 0.0450` is **0.0074**, not the 0.0079 first published.
`WIDEN-LAYERS-2026-08-22.tsv`, `#### The same price without the collar`.
The other item that was left, the population of sub-bar pages carrying a picture, is measured: **0 printed
plates and 0 printed figures over the 73**, the largest non-text mark ≤3% of a page, two independent reads
each finding 6 of 6 positive controls (`SUBBARPIX-2026-08-22.tsv`, `#### Are there PICTURES in the sub-bar
73?`). ⛔ **But the bound is the GROUPING, not the component test, and one page of continuous tone shows
it plainly**: `1976 - Regis McKenna Papers` p4 is a colour photograph of a memo and the component test
accepts `txtN` **45** components / **21.6%** of its out-of-stencil map, refused only by `lineN = 0`; in a
printer's-ornament rect on another page the map holds 666 px and the accepted components **664** of them,
grouped **0**. So `lineMinimumMembers` / `lineGapFactor` carry the whole of it — the same two constants
behind the term's false negatives on C26's cartoons, which makes relaxing them a two-sided trade.
✅ **Question 2's 1/2 half is MEASURED 2026-08-20 and the loss does NOT reproduce there** — 16 of the
109 layered pages the bar does not read as all text were rendered and read at 1:1, ten of them beside a
1/8 reference on the same rect, and **no content loss was found at 1/2 in any window read**, including
on the two pages where the same ink WAS destroyed at 1/8 before the 2026-08-19 bar move. That bounds this entry to the 73 pages at
8x/16x rather than 182 **on the default setting** — see the next paragraph, which is why that
qualifier is now there. 16 of 109 is a
sample, and the base is **one window a page**.
⛔ **QUESTION 2'S 1/3 HALF IS MEASURED 2026-08-21 AND IT DOES REPRODUCE.** `PHOTODETAIL=` was added to
`Tools/score-text-route.swift` (the tool measured the default and had no way to vary it), the same 16
pages were rendered at `PhotoDetail.smallest` as well, and **`Xin Qu et al_2018` p20 loses the
correlation matrix's last column** — thirteen values legible at a 460 px background and unreadable at
307 px, at zoom 8 `−0.130*` reading `−#.1##*`. Two more are degraded and legible (`_1973_CAR` p4's
prose lines; `Jones et al_2010` p12's table rule, darkest pixel 25 → 56 → 136 against paper at ~250)
and five read clean, including all three `1954 - Why` cartoons and `Riesman - 1954` p16's pen bracket.
⛔ **The term that orders it is the page's own rebuild resolution, not `inkOut` and not a difference
map** — the loser has the smallest source render of the sixteen and ranks SIXTH of sixteen on the
1/2-against-1/3 difference, so that scalar is refused. ⚠️ **A draft of that sub-step was on course to
conclude "no loss at 1/3" off its first five pages**, all of which are clean; choosing the sixth by
narrowness rather than by `inkOut` overturned it. Smallest costs **0.6465x** the bytes of Balanced over
the sixteen and **the page that loses content saves the LEAST of them** (17,705 B, against
240,578 B on a page whose only out-of-stencil ink is a scanner edge). ✅ An all-text page is
byte-identical at both settings, measured — `max(3,8)` is `max(2,8)` — which is what bounds this to the
109 rather than the 182.
✅ **QUESTION 3 HAS ITS FIRST MEASUREMENT, 2026-08-21, AND A SHAPE TERM SEPARATES WHERE FIVE SCALARS
DID NOT.** `Tools/score-shape-term.swift` (new) counts the **text lines** in the ink outside the
recognised words, at the page's own type scale — a component is type-shaped against the median height
and stroke of *the stencil's own components*, and ≥ 4 of them tiling a baseline make a line. Over 13
labelled pages the count is **≥ 1 on 6 of 6 pages measured to lose typeset content and 0 on 6 of 6
that lose nothing** — 12 of 13, the odd one being the page whose loss is a hand-drawn bracket, which a
rule calibrated on type reads 0 on. ⛔ That was published as blindness *by construction* and the picture
run refuted it hours later: the term fires 17 and 11 groups on a pen ornament. Five numbers, all ratios rather than sizes,
**written before any page was run and not adjusted after**: 8 pages first, then 5 held out. ⛔ **It was
not validated on that sample** — 8 of the 73 plus 5 of the 16 C26's bar move rescued (so 5 of them are not degraded in production today), a labelled convenience sample, 4 of its 6 non-losers from one scan,
and **no plate, halftone or line drawing in it at all**, which is exactly what `textRegionMask` exists
to keep out — **measured the same day, next sentence, and it does not read 0 there**. ✅ **The
convenience sample was replaced by the whole 73-page population later the same day and the type half
went 6 of 6 to 12 of 12; see two paragraphs down.** ✅ **And the missing class turns out not to be a gap
in the sample but a fact about the population: inventoried 2026-08-22, the 73 hold 0 plates and 0 drawn
figures**, so no sample drawn from them could have contained one. ⚠️ Read `lineN` and not the share: the drawn bracket's `txtShare` (0.0173) sits *below* a
non-loser on the same scan (0.0500), so a bar on the share inverts that pair — a sixth refused scalar.
⛔ **QUESTION 3b IS MEASURED 2026-08-21 AND THE TERM ERRS IN BOTH DIRECTIONS** — ten picture pages,
`SHAPETERM-PICTURES-2026-08-21.tsv`, `#### The same shape term on PICTURES`. `lineN` is **≥ 1 on 6 of
10** and none of the six accepted groups is type: halftone dots, photograph grain inside a plate whose
real caption Vision *did* recognise (12 groups, none on the caption), a pen ornament's feather strokes
(17 and 11), and 10,438 px of page-wide-Otsu speckle in a featureless grey endpaper straddling the
threshold by ±3 levels. ⛔ **But the sharper half is the other direction: it reads 0 on two pages whose
loss C26 measured at 1:1** — `1954 - Why` p6 and p7, whose drawings are 92% and 100% of their pages'
out-of-stencil ink and yield 372 and 785 `textish` px that never reach four members on a baseline. So
the miss is `lineMinimumMembers`/`lineGapFactor`, not the component test — ⛔ **on p6 that is a
statement about 56% of that RECT's drawing ink and the other 44% is a THIRD mechanism, `inkOutsideText`'s
interior window, which `textLineGroupsOutsideText` blanks out of the map; measured 2026-09-20 at
3,513 px of the 7,980 inside C26's own eye-chosen rect — ⚠️ **that rect is the denominator, not "the
drawing"** — against 1.45% on p7** (`#### The other two drawing rects, SUBTRACTED`), where the
clipped body text in both rects contributes **0** map px and **0** painted `textish` px, so the
subtraction that question was opened for is ZERO on all three pages — and **p4's single group is a
hit on the lost cartoon** (`27x17+1121+685` lies inside the published `254x240+970+595`), not a false
positive — ✅ **READ AT 8x AND CONFIRMED 2026-09-20, where until then the evidence was CONTAINMENT
ALONE inside a rect published as holding clipped body text**: the four members are the figure's hand
(2) and two leaf strokes of the flying book (2), all ink by the page's own Otsu of 139, and the clipped
body text in that rect contributes **0 map px** — measured per row, because the type is inside `region`
and the map is `ink AND NOT region` (`#### The cartoon's own 59 pixels, READ`). ⛔ **But the
group is a band across TWO drawn objects 14 px apart against a 27 px bar, so the hit is the ink's and
not a stroke the term recognised; and the `textish px` figures quoted here and in 3b's own per-rect
table are the dumped PNG's PAINTED counts — 477 / 372 / 785 against the tool's own `txtPx` of
444 / 357 / 761, ⚠️ **and the 785 is an IN-RECT count against a WHOLE-PAGE denominator: p7's page
reads 792, so like for like the gap is 4.1%, measured 2026-09-20.** ⛔ **"Blind to a hand-made mark
by construction" is therefore REFUTED** — measured, it reads 0
on four hand-made marks and fires on three — exactly the *"four blobs of a broken pen stroke"* case the
previous section's own review named as the one to try. On `Wilcox` p2 it is wrong both ways: 0 accepted
pixels over the hand-lettered *"Harry W. Wilcox"*, 1,694 on the decoration. Four more scalars refused
(`glyphN` — so "too little type to calibrate on" is **not** the mechanism — plus `txtShare` again,
absolute `linePx`, `topLine` width). ✅ **The bound holds for ONE of the two seams**: all ten are
`barVerdict=picture`, so `inkOut < 0.045 AND lineN == 0` never consults the term on them and the byte
cost is zero — derived from the sweep, not measured, and on a **1.10x** margin (0.0493 against 0.045).
⛔ **Under `textRegionMask`, which is the seam question 3's own sentence names, there is no bound**: it
runs unconditionally on every layered page (`Flattener.swift:2696`), so those six pages would put
halftone dots and pen strokes into the 1-bit stencil — R57's failure mode. ⚠️ `lineShare` separates 22
of the **23** pages the term has been run on, and it is **the seventh share in a register that has
refused six**: post-hoc, denominator-driven, and it leaves four known content-losers on the safe side.
✅ **THE TERM IS NOW VALIDATED OVER ITS WHOLE POPULATION, 2026-08-21, AND QUESTION 4 HAS ITS FIRST
PAGE-LEVEL BYTE PRICE** — `SHAPETERM-73-2026-08-21.tsv`, `#### The same shape term over ALL 73`. All
**73** sub-bar pages, 22 documents, constants unchanged, **65 of them never measured before**:
`lineN >= 1` on **12 of 12** pages that lose typeset content (8 of 8 out of sample), **1 of 4** that
lose only a hand-made mark, **0 of 6** degraded-but-legible, and **3 of 51** that lose nothing. ⛔ **All
three of those firings are the RIM of recognised type** — glyph tops outside Vision's word boxes on
lines that are in the text layer, read at 1:1 — so the candidate fix was subtracting a *dilated*
`region` before grouping. ⛔ **THAT FIX WAS TRIED THE SAME DAY OVER THE SAME 73 AND IT SPLITS IN TWO** —
`SHAPETERM-RIM-2026-08-21.tsv`, `#### The rim fix, MEASURED`. Type-losers firing / non-losers firing:
r=0 **12/12, 3/51**; r=1 **12/12, 2/51**; r=2 **11/12, 1/51**; r=3 **9/12, 1/51**. ⛔ **As a REPLACEMENT
for the rule it is refused**: r=1 is the only radius that keeps every real loss, and it clears **two**
rims of the three while **adding one of its own** — on `Xin Qu et al_2018` p28 the rim of a recognised
`469.` is three accepted components at r=0, one short of `lineMinimumMembers`, and a 1-px collar splits
the middle one (`8x8` -> `4x6` + `3x6`) into four. From r=2 it destroys real losses. The rim that
survives every radius is `Herbert Marks papers` p12, still the rim at r=3. ✅ **But as a SECOND
CONDITION it is the best rule this campaign has measured**: `lineN >= 1 AND rim1N >= 1` reads **12 of 12
type-losers and 1 of 51 non-losers**, on 14 pages rather than 16 — ⚠️ post-hoc and hand-made bucket
unmoved at 1 of 4. ⛔ **And it buys NOTHING at the other seam, measured 2026-08-21 over the same ten
picture pages**: `rim1N == rim2N == rim3N == lineN` on 10 of 10, so the conjunction fires on the same
**6 of 10** the r=0 rule does — a 3-px collar removes 4 accepted-line pixels of 16,294 there, all four
on one page — because the collar can only reach a mark within `r` px of a recognised word box and a
halftone dot in the middle of a plate is not one. `#### The conjunction on a PICTURE page`.
⚠️ A ratio-scaled collar does not rescue the replacement reading either: `Scott_TK` p3 loses its last
group at 0.375x its own `glyphH` while p12 still fires at 0.6x its own. ✅ **And a signature DOES fire**: `_1939_Former students`
p6's only accepted group is the cursive signature itself, the third refutation of "blind by
construction" and the first on a page of measured loss. ⛔ **One of the three misses is not the rule's**:
`_1939_Former students` p2 has `outPx` **0**, so the map is empty and the shape rule is asked about no
pixels. **The price**: the wiring refuses the shrink on **16 of 73** pages for **+2,362,625 B**
(3.99x, 15.5% of it on pages that lose nothing) against the cheapest page-wide bar rescuing the same
13, which refuses **41 of 73** for **+6,202,065 B** (4.24x, **58.5%** of it on pages that do not lose content) — **38.1% of the
bytes** — ⛔ but that bar rescues **15 of 16** losers where the term rescues 13, the two extra being
hand-made marks costing +575,066 B. ⚠️ Bytes are at the default Photo detail, page by page. ✅ **The
`textRegionMask` seam is priced 2026-08-22 at +2,315 B over the same 16 pages — 0.098% of this —
but it admits only 50.03% of those pages' out-of-stencil ink, so it is not the same protection**; see
`#### The price at the textRegionMask seam`. Nothing is wired.
✅ The same tool settles `score-text-route`'s open instrument question, because it holds `region`
itself and its map therefore *is* `inkOutsideText`'s set (asserted on every row, exit 6 otherwise;
`inkOut` reproduced the committed sweep on all 13): substituting the dumped stencil inflates the
fraction **1.00x–3.17x**, a 7x7 SQUARE stand-in for the published `Disk:3` (which is 29 cells, not 49 — see the review note) lands **0.721x–1.007x**, and ImageMagick's
OTSU is identical to `Flattener.otsuThreshold` on **13 of 13** pages, over a 69-level range — so that recipe's
0.56x–16.0x spread is bounded on pages with ink to divide by, and the extremes all sit on `inkOut`
0.0001–0.0051 (a small-denominator candidate, unmeasured). ⛔ **And it corrected this register from the
crops: `Atkinson_1939` p3 loses two lines of TYPESCRIPT** the sub-step-1 inventory did not list
(illegible at the shipped 8x, legible un-shrunk), so that page is in both buckets and the campaign's
split is **19 type and 6 hand-made over 24 pages with one page in both**, not the exclusive 18 + 6
that appears above and elsewhere. The page count, 24, does not move.
⛔ **And that sub-step's own draft tried to RETRACT a
correct claim of this campaign's in six places — the adversarial review of its diff refuted it from the
same page.** It read one rect of `Xin Qu et al_2018` p20's matrix (top-left values, stencil-over-source
ink 0.98x — stencilled) and concluded "thirteen values" was misattributed; the matrix's **last** column
reads stencil ink **0.0000** and holds 1,375 of that page's 6,233 out-of-stencil map pixels. Thirteen
values, exactly as published, all six edits reverted. **A stencil-ink ratio is a claim about its rect,
not about the page.**
⚠️ **And the recipe C28 gave for the sub-step renders was a false negative** — `INKBAR=0.08` compares a
sub-bar page with itself (byte-identical backgrounds, measured); the bar must be *at or below* the
page's own `inkOut`, and where that is 0 the instrument is instead an `ink AND NOT dilate(stencil)` map
off the dump, validated against a known losing/non-losing pair. So the question C26's
campaign surfaced (*why is recognised-page prose dropped from the stencil at all*) is now its own
entry, **`C28`** — the stencil is the intersection of the page's ink with Vision's word boxes, and
that premise is written in `inkOutsideText`'s doc comment as a fact ("ink that is not inside any
recognised word is, by construction, not text") which sub-step 4 measured false on 7 of 13 pages.
Read `#### The constant moved` and the section after it at the
foot of C26 before touching any of it. Opened 2026-08-17,
hours after `1.13.0` was cut against an empty register — a small line drawing on a page the code
correctly reads as all text is erased on the picture path, because the guard that would protect it
does not fire. **Measured 2026-08-18, the guard's second term was never the one to look at: the
drawings are INK, not pale marks** (5,495 / 4,188 / 3,379 cells below the page's own Otsu, against
8 / 350 / 0 pale cells `paleDrawing` gets to see), and the term that decides these pages is
`pageIsAllText()`'s **first** one — `inkOutsideText` reads **0.0493–0.0660 against what was then a
bar of 0.08** (0.045 since 2026-08-19, which is what refuses all three). That term *can* reach them,
which the pale one cannot. **This line said "the guard needs
the mark to cover 5% of the page and these cover 0.2%" until 2026-08-18, and the 0.2% was the
wrong column** — measured, the quantity the 5% bar reads (`paleDrawing(…).extent`) is **0.00000**
on the two worst pages, so the guard's search finds nothing rather than finding something too
small, and no value of that constant would protect them.
The corpus sweep both entries were waiting on ran the same day: **441 pages, 233 documents**, and
it sizes the population of the `extent` bar (61 picture-route pages: 2 protected, 22 under the
bar, 37 at zero) while **not** sizing C27's, because a mean cannot see concentrated colour.
**⛔ C27's own instrument exists as of 2026-08-19 and its sweep RAN the same day** — the column that
can see concentrated colour is `satFrac` on `Tools/score-threshold-loss.swift` (`Flattener`'s
`saturatedFraction`: the share of the page above `satFloor`, out of the same thumbnail `sat` itself
comes from). It reproduces the entry's independent 50-DPI red-pixel count on all 7 pages of
`1954 - Why` that count covers — **0.93x to 1.49x, median 1.12x, across a range from 0.1% to 24%**,
at `SATFLOOR=0.15` — and the two pages that count never measured are now measured. It also **found a
cost the entry does not carry**: the mean gates the ROUTE as well as the colour, one number charged
twice as in C9, so **3 pages of this document that are 1-bit today (p5, p8, p9) hold as much
saturated ink as the picture-route pages** and a fraction-based signal inside `isPicture` moves their
route and their bytes, not just their colour.
**The corpus sweep is `SATFRAC-2026-08-19.tsv`** — 233 documents, 441 pages, 12.2 min, every
document `rc=0`, with the 12 columns of `THRESHOLD-LOSS-2026-08-18.tsv` reproducing digit for digit
over all 441 rows. **428 of 441 pages are published in grey because they fail the 0.06 mean bar —
though 401 of those have nothing measurable to lose — and 10 pages in 7 documents of 233 carry as
much saturated ink as the page the owner watched lose real red ink**, ~220 pages of 16,987
stratified. That 10 is bounded **both** ways (two of the ten carry no ink of their own; the bar sits
above the smallest real marks), and the sweep's three real results are not the count. (1) **The mean
MIS-ORDERS colour rather than merely under-counting it**: 24 discarded pages hold more saturated ink
than the least-coloured page that keeps its colour, 6 of the 13 kept pages hold less than the
most-coloured page that loses it (1.6x–27x), 58 of 5,564 pairs inverted. (2) ⛔ **Eight of the ten
were dumped and read by eye** (the other two are the owner's own verdicts), and **three of the eight
real ones are colour photographs or illustrations on pages of type rather than spot colour** — so
the harm is wider than the entry's framing while staying fidelity *on the pages looked at*.
(3) ⛔ **Two of the ten carry no ink of their own**: a 1938 magazine scan reads 2.0% from a page-wide
cast the paper correction left standing — 48x what another page of the same scan reads — and a 1941
typescript's 4.08% is **89.0%** photographed surround from outside the sheet — ⛔ **89.0% is `edgeShare`,
the border-connected share; the **88%** this sentence carried until 2026-08-28 is `topShare`, the largest
component's 0.88223, a different set, and `#### The two mask terms, MEASURED` corrected exactly that
conflation on 2026-08-26 without reaching this copy or the two in `CLAUDE.md` and `QUEUE.md`.** **So no bar on `satFrac`
separates the populations, and neither does the single locality test first proposed here: measured,
that would rank the scan-border page top of the corpus.** Two terms, not one — R56's lesson in a
second place. ✅ **AND BOTH TERMS ARE MEASURED AS OF 2026-08-26, in `Tools/score-threshold-loss.swift`'s
last eight columns and `C27-MASKTERMS-2026-08-26.tsv`** (50 rows: the 40 pages above the noise band plus
10 same-scan controls, all 21 pre-existing columns reproducing `SATFRAC-2026-08-19.tsv` digit for digit
on 50 of 50). ⛔ **"Two terms, not one" is now a measurement rather than an inference: each term
separates exactly the artefact it was proposed for and NEITHER separates both** — `sheetFrac` puts
`Ford_1941` p5 at 0.00448 against a floor of 0.01326 over the eight real-colour pages (2.96x — ⛔ **1.23x
from 2026-08-28**, over NINE real pages, and at that floor it admits `Stanford_1891` p3 (read as foxing) and `Atkinson_1939` p3 (UNREAD): `#### The two unread
window pages, READ`) and is
blind to `HarpersMagazine` p4 (`edgeN` 0, unmoved); `topPx` puts `HarpersMagazine` p4 at 6 px against a
floor of 124 (20.7x) and is useless on `Ford_1941` p5, whose largest component is 55,743 px — ⛔ **and that
124-px floor is refuted as a MARK test 2026-08-28 by a 397-px brown paper stain with a stroke width of 11**.
The
ordering improves — 68 of 104 real-against-already-keeping pairs inverted under `satFrac`, **27 of 104**
(⛔ **80 of 117 and 35 of 117 from 2026-08-28** over NINE real pages: both degrade, and 2.51x becomes 2.29x)
under `sheetFrac` — ⚠️ but it does not reach zero, no bar is proposed, and this entry's own published
*"0.49%"* for `Ford_1941` p5 was computed from the LOCALITY figure while stated as the outside-the-sheet
one (`sheetFrac` is 0.00448).
✅ **AND THE BYTE PRICE IS MEASURED THE SAME DAY — C27's item (b), `C27-COLOURBYTES-2026-08-26.tsv` and
C27 `#### The byte price, MEASURED`: keeping the colour costs +93.0 KB over 13 pages, `1.048x`, which is
CHEAPER in proportion than the `1.080x` the colour this app already keeps costs on 11 pages of the same
population.** ⛔ **Its larger finding is about C28 rather than C27: the colour decision changes the word
boxes Vision returns on 21 of 30 pages and flips `pageIsAllText()`'s verdict on 6 of them**, moving the
background factor between /8 and /2 — so 80.4% of the naive +475.0 KB aggregate is that flip and not the
colour, and quoting the naive figure overstates (b) by 5.1x.
✅ **AND (b)'s SWIFT REVIEW SAID *REJECT* ON TWO BLOCKERS; ALL FIVE ARE WORKED 2026-08-26 —
`#### Five more from the SWIFT review of that diff, WORKED`.** ⛔ **One real defect: `MRC_PAGES=1,1,1`
DOUBLE-COUNTED, under the sampling comment that denies exactly that** — measured on a pre-fix binary over
`1954 - Why.pdf`, `MRC_PAGES=4,4,4` prints `3 picture pages`, `today 809 KB`, `as published 199 KB`
against `MRC_PAGES=4`'s 1 page / 269 KB / 66 KB, so A12.8's `score-text-route` defect in a second tool. A
repeat is refused now (exit 2), the parse returns THREE cases (`ok`/`malformed`/`repeated(Int)`) so twelve
self-test checks can reach it and can say *which guard* refused, and `fault-inject.sh`'s `mrc_refuses`
gains **eight** rows, `10 passed, 0 failed` — which discharges (b)'s own recorded debt.
⛔ **The other four were false statements, and the load-bearing one stood in THREE places**: *"`MRC_COLOUR`
changes the colour decision and nothing else"*, contradicted by the very run beside it. ⚠️ Also a missing
arm label on the summary block, and a megapixel reassurance quoting `cells` where the bound reads pixels —
**16.87x low: the measured largest corpus page is 64.84 MP against a bar of 100**, so "no corpus page is
over it" holds and "none is near it" does not.
✅ Negative control: the two binaries are byte-identical over `MRC_PAGES=2,4,7`, so no published figure
moves.
⛔ **THE WORK WAS ADOPTED FROM A STRANDED WORKTREE AND CORRECTED ON THE WAY IN, and the two corrections are
worth more than the five fixes.** (i) The strand's own fix for the megapixel figure **repeated the class of
error it was correcting** — 1.31x low, in the reassuring direction, under a §3 banner — by reconstructing
`max(cells × factor²)` = 49.59 MP where `cells` counts `interiorWindow` (0.766 of the area) and
`Sources/Flattener.swift` records the real 64.84 MP twenty lines from the constant; the §4b sweep it owed
then found the same sentence live in `Tools/score-threshold-loss.swift`, **the tool that prints the
column**. (ii) One shared refusal message left a sabotage swapping the repeat guard for
`numbers.allSatisfy { $0 >= 2 }` with **all eight fault rows and all twelve table rows green** — the
eleven-times-recorded shape of a check credited with more than it asserts. Both fixed and re-measured
before the commit.
Read C27's `#### The population, swept`, `#### ⛔ And the ten pages were LOOKED AT` and
`#### The two mask terms, MEASURED` before
planning anything here; the constant is untouched and nothing shipped reads the fraction.
**⚠️ That is no longer C26's population**: the term C26 turns on is `inkOutsideText`, and the sweep
of *that* is a separate run — it is `INKBAR-2026-08-19.tsv`, below. **What was measured 2026-08-18 is
what C26's proposed fix costs on the document it was found on: at a bar of 0.045 all three
erased-drawing pages are refused the shrink and go 65,477 -> 195,785 bytes, `2.99x` on those three,
`1.76x` across the document's five picture-route pages** (the other five are already 1-bit and pay
nothing — the first version of this line called the three-page sum a document total, which it is not).
**⛔ And measured 2026-08-19 over the corpus, that 2.99x is the BEST case and is retracted as a corpus
figure**: `Tools/sweep-ink-bar.py` swept 233 documents in 105.6 min (`ok=233`, committed as
`INKBAR-2026-08-19.tsv`, 2,129 measured page rows) and the band `[0.045, 0.08)` holds **17 pages, 16
of which flip** — 0.75% of sampled pages, 18.0% of the 89 that are shrunk today, over 10 documents of
233. Those 16 cost **838,569 -> 3,804,222 B, +2,965,653 B, 4.54x, 185,353 B/page** — 4.3x worse per
page than this document's three, which are ranks 1, 3 and 4 of the 16 sorted by cost. That is
**+8.19%** of the layered bytes on the 181 pages that reach layering and **1.21x to 3.60x** per
document, but only **~+0.55%** of corpus output — **~21 pages of 16,987 and ~4.0 MB**, 8 pages of it
exact. ⚠️ **The obvious extrapolation says ~130 pages and ~+24 MB and is 6x high, retracted the same
day**: the sweep takes 12 pages a document whatever its length, so pooling its per-page rate applies
short documents' rate (4.8x higher) to the long documents holding 98% of the corpus. R49/R50 state
**no** growth-tolerance bar (read 2026-08-19), so there is nothing to test that against; what R50 was
accepted on was "not one grew", and this grows ten documents while barely moving the corpus.
**⛔ The population is known AND so is the benefit, measured 2026-08-19: the other 13 pages were
rendered at both bars and 11 of them lose something.** `INKDUMP` on `Tools/score-text-route.swift`
writes both tone-layer pairs from the same call the byte columns come from, and the stencil being
byte-identical at both bars makes the two backgrounds the whole difference. **7 of the 13 lose whole
lines of prose or table data, and an 8th a hand-drawn mark** — `Xin Qu` p20 loses thirteen values out of a Pearson correlation
matrix, `_1973_Committee Against Racism_` p4 loses seven lines — 2 more lose graphic rules and word
fragments, 1 blurs a pencil mark, and **2 lose nothing a reader would see**. ⛔ **So C26 is an
invariant-1 defect, not the fidelity complaint the entry was opened as**: the dominant case is not a
drawing but prose Vision failed to box, cut from the stencil and then destroyed in the background.
⛔ **And the dearest page of the 16 is one of the two that buy nothing** — `RIESMAN_1942` p10 at
+702,280 B and 6.47x, whose only non-stencil ink is a pale scanner-edge strip; with `Riesman - 1954`
p18 that is **32.4% of the band's byte cost on pages a reader cannot tell apart.** ✅ **The decision
was the owner's, R55's precedent, and he took it at a 2026-08-19 check-in: the bar is 0.045, on the
arithmetic that ~4.0 MB of corpus output is a cheap price for not destroying words.** It shipped the
same day; the entry's `#### The constant moved` section is the diff, the suite's flipped checks and
what was watched failing, and the section after it is the render that closed the entry on 2026-08-20.
This line said the decision was outstanding until then. `C26`, `C27` and `C28` each carry
the numbers and the retractions. It is **not** R56, whose fix is
intact and whose mechanism is the other route; read C26 before touching either. **The release gate
cannot see this class and says so in its own source**, so a green gate is not evidence about it.
**C24 closed 2026-08-17** — read the paragraph
beginning "**C24 is now `FIXED`**" below before trusting that sentence, and correct this line
in the same commit as any entry you open. This file has published "nothing open" while four
entries were open, and it has published "one open" while that one was closed. **R56 and R57
are `FIXED`** as of 2026-08-16 — the pale drawing erased and the tonal plate blobbed, the
two entries that had been waiting on a shape signal since 2026-08-13. It exists now:
`Flattener.pageMarks`, `largeMarkTone` and `paleDrawing`, on the sixth attempt and the
second signal class, and the term that closed R56 is not a threshold on how pale a mark
is but on **where it is**. Read both entries before touching the routing — four
luminance rounds and two shape rounds were refused first, and the corpus section in R57
states plainly the acceptance bar this did *not* meet. **R55 is `WONTFIX`** as of 2026-08-17 — it was in `Tools/` rather than the app, the
measurement campaign it wanted was run, and the owner closed it on the arithmetic: the
gate's over-exclusion costs the sweep roughly 80 candidates and 0.7 GB against 1,164 and
~10 GB, the corpus half is solved by adding upright-scanner documents by hand, and
loosening the gate would admit the hand-held photographs D1 exists to keep out. **C24 is now
`FIXED`**, opened 2026-08-15, half fixed 2026-08-16 and **closed 2026-08-17**: `largestImage`
answered "the largest image in this document" to a question
about *this page*, so on the 3 corpus documents whose pages share one `/Resources` a page
that draws nothing at all was rebuilt at another page's plate resolution — **85 pages,
measured 2026-08-16 by scanning content streams for `Do`**. Two repairs were built and
both were wrong, and neither the structural half nor the close needed the threshold the third
would have wanted. **The second half was measured 2026-08-16 and
is narrower than the entry assumed**: `Flattener.drawnLargestImage` reports what a page
actually draws, the 45 pages are 39 smaller plus **6 wider** — which retires the
observation the entry carried without a cause, since both walks pick by *area* and report
*width* — and the constant the entry wanted recalibrated faces **three** pages. **It judges all
three of them right, measured 2026-08-17**, which retired the blocker: `Batzell` p22 at its own
70.6 DPI retains **92.8%** of its 291 words against **94.2%** at the 369.6 it was accidentally
getting, for **87% fewer published bytes** — so "rendering a page of type at 70 DPI is C9 again"
was reasoned, is **false**, and has been corrected in the four places it was published.
`minimumScanPixelWidth` needed no recalibration. **Then the wiring landed the same day and
the gate ran**: `rebuildDPI(of:)` reads the drawn walk, **exactly 45 pages of 16,987 change
resolution** and they are page-for-page the 45 the earlier sweep named, retention against
those pages' own embedded text is **+8 words of 3,025** over the 7 that have one, and bytes
fall 25% / 81% / 3% by document. The instrument had to be repaired first — its
`shippedRebuildDPI` column would have become a copy of the column it was compared against,
a tool measuring itself — and one row is named as a surprise nothing settles: `Sherman_1986`
p1 moves 219 → 182 recognised words on a **0.38%** resolution change, non-monotone, with no
ground truth to grade it. The review of that measurement
found **a check that could not
fail** — the fixture had no page that reached the guard one of its own mutants edits — and a
bare form resolving its names against the page rather than its invoker; both fixed, with
the 16,987-row sweep byte-identical before and after. **Its mutant campaign was run
2026-08-17 and killed all five**, which is what says those five checks can fail; it also cost
**4.85x** the estimate `mutate.py` printed, so that estimate now reads the tool's own log
instead of two hardcoded constants and `mutate.py` has a `--self-test` for the first time —
though a follow-up the same day found that fix is still **4.22x low out of sample**, that the
section's own "negative control" on it was in-sample, and that its self-test coverage figure
(21 of 26 mutations killed, not the 12 of 14 first written) had been reasoned rather than run.
`SELFTEST-MUTANTS-2026-08-17.tsv` is the audit. **R81, R82 and
R83 are the text layer's three, all `FIXED` on 2026-08-15**: a line drawn at 5% of its width
because a second reading of its own ink counted as the next fragment; words welding when one
fragment of a line is much shorter than the next; and the small ones from areas 2, 3 and 13,
including two memory constants that described a phase that was not the peak. **R54 was `FIXED`
before them** as of 2026-08-15 — with a correction to its own two numbers, and a fix
aimed at the eight *real* item types that had the same defect rather than only the pseudo-type
it named. **R58 is `FIXED` but its
feature is deliberately unreleased** — the annotation transplant, after two adversarial rounds
that each found marks landing in the wrong place. The third round is unrun.

**C23 was found by the release gate an hour after T9 taught the gate to read pixels**, and is
`FIXED`. The rebuilt copy displayed what the original's crop box hid — C13's own harm, at the one
site C13's fix never reached; 16 of 233 corpus documents, 627 of 16,987 pages, worst case a third
of the sheet. Read its entry before touching the crop box anywhere: the obvious fix is wrong in
two different ways, both measured.

**R56 and R57 were in the app, on the default route, and are `FIXED`.** R56: a pale
line drawing was **erased** by the 1-bit route, because it scored the same ink, tone and
saturation as a page with nothing on it but text. R57: a continuous-tone plate over a
fifth of a page missed *both* routing gates at once (ink 0.147 against 0.15, tone 0.102
against 0.12) and came out a solid black blob. Both were found by the adversarial
fixtures in `Tools/make-plate-fixtures.swift` and both were **rendered rather than
argued** — and R57's "realism not established" caveat turned out to be hiding a credited
art photograph and 87 more pages in one thesis. Both are closed by the shape signal
`FEATURES.md` specified three days earlier, and the two entries carry what that
specification got wrong as well as what it got right. `TODO.md` item 1's size
optimisation was refused until R56 closed; it is now unblocked in principle and has not
been re-measured.

**R55 is not in the app**: `classify-source` calling an upright-scanner capture
`photographed`, which is the gate deciding what the corpus and the sweep are allowed to
contain. **R54 was its neighbour and is now `FIXED`** — a pooling bug in
`Tools/sweep-zotero.py` that made its per-type medians and its "GB reclaimable" figure
untrustworthy. It mattered only when the library sweep runs, which is scheduled last, and
the measurement behind the fix found the same defect in eight real item types.

**R51–R53 came out of a review of R49 and R50's own diff and are all `FIXED`** — the
tenth round running in which reviewing the previous round's code found real defects in
it. One of them, R52, was a page stored at an eighth of the resolution its user had
explicitly asked to keep.

**R49** — a 568-page scan going in at 31 MB and out at **437 MB**,
because colour pages were the one kind that could not be layered — is `FIXED`, and
**R50** finishes the job: the file now lands at **35,379,516 bytes, 1.13x its
original**, down 12.4x, with a byte-identical text layer. R49's entry records a
detector fix that was built, measured and **refused** — the page's own luminance
histogram cannot tell tinted paper from a tinted plate — and R50 records the signal
that *does* work and why it was available all along. **U29** (the updates block was pasted
twice in the settings panel) and **U30** (the preset buttons gave no sign they had
done anything) were both reported by the user on 2026-08-13 and are both `FIXED`.

R41–R48 came out of an adversarial review of R40's own diff
and are all `FIXED` — the ninth round running in which reviewing the previous
round's code found real defects in it. R40 — batch throughput falling when
recognition came in-process, because Vision does not parallelise across concurrent
requests in one process — is `FIXED`: recognition runs in a helper process per file again,
and the helper compiles the app's own `Recogniser.recognise` so the observations
are identical by construction rather than by agreement. R39 is `FIXED`,
and the fix it originally proposed was measured and refuted before a different,
real defect was found underneath it. U23 and T8 close the fourth of the four ways this register
kept producing defects from its own fixes; the other three got controls in the
same round. The third review's five — R31, R32, T6, T7, H2 — are all
`FIXED`, and the round added three controls aimed at the *shapes* rather than
the instances: `Tools/fault-inject.sh` (execute the error branches),
`Tools/mutate.py`'s own repair (T7), and the sibling sweep in CONTRIBUTING 4b,
which immediately found a mount leak the review had missed.

That review covered the 868 lines the bundling and mutation work added after
1.3.0. Nine claims, **nine confirmed, none refuted** — the verifier built an `otool` shim and ran the real
scripts rather than reading them. Five of the nine are in code written the same
day, which is the third consecutive round to find that, and T6 is the third
consecutive round to add checks that cannot fail *while looking for checks that
cannot fail*.

T5 records the first mutation campaign: sixteen mutants
killed, six gaps found and closed, two survivors kept with reasons.

Two reviews ran against this codebase on 2026-08-09, the
second against the release the first produced. It found seven more defects, and
**five of the seven were in code or tests written during the first** — R29 is the
hole R24 left and then wrongly recorded as measured, R30 is U18 reaching for the
wall clock in a file that documents why not, U21 is U19's flag and U20's async
import interacting, and T4 is three checks from that round that could not fail.
This register has claimed for a year that every pass finds defects in the
previous pass's code. It demonstrated it twice in one evening.

C22, R29, R30, U21 and T4 are all `FIXED`, each with a check that was watched
failing first.

The eleven raised by the first 2026-08-09 review — C19, C20, C21, R23, R24, R25,
R26, R27, U18, U19, U20 — are `FIXED`, each with a test that was watched failing
first. Fourteen were claimed; a skeptic pass
that defaulted to refuting killed three, and those measurements are kept as R28
because they are worth more than the claims were.

Three of the eleven were a fix that stopped one line short of the code beside
it: U18 is U5's hazard still live, because the bound was placed after the call it
was meant to bound; R23 is R19's recursion bound missing from its mirror
function; R24 is an `Int` overflow trap inside R20's own crash guard. Fixing a
thing and fixing the thing next to it are still different acts.

**Three tests in this round did not bite when first written**, and each is
recorded where it happened rather than quietly corrected: R25's depth fixture
(CoreGraphics walks the shallower branch first, so the case cannot be built —
⛔ **the SECOND clause falls as of 2026-08-29 and the first does not: the case IS
buildable, and the fixture's failure to bite is the fixture's own fault rather than
CoreGraphics's, because the yield order reads an entry's POSITION and the fixture
varies the two keys' NAMES. On both of its members the shallower route genuinely is
yielded first — so "walks the shallower branch first" is confirmed there and
"cannot be built" is refuted. See R25 `#### It belongs here`**),
U20's timing bound (4,000 files walk faster than any threshold, so the property
had to be restated without the clock), and C20's selection probe (twice — one
fixed row missed a one-point run, then the scan ran into the neighbour's box).
A test written after the fix and never seen red is a test that proves nothing.

The four raised by the 2026-08-08 corpus run — C17, D1, D2 and D3 — are all closed, and
closing D1 meant replacing the corpus rather than re-wording a sentence. D2's
remainder became C18: the newspaper line-end weakness has a cause, a fix, and a
fourth text-layer property nobody knew was load-bearing. Everything else is `FIXED` or `WONTFIX` with a
reason. The run itself was clean (40/40, median 100% line-start); what it found
was that the *corpus* the project's headline figures rest on is mostly not scans,
and that the app quietly damages the material that makes up half of it. Full
write-up: [CORPUS-2026-08-08.md](CORPUS-2026-08-08.md).

Fixed in the first pass: C1, C2, C3, C4, C6, R1, R6, R7, R11.
Second and third passes — fixed from the original list: C7, R2, R3, R4, R5,
R7 (never actually fixed the first time), R8, R10, R12.
Found and fixed since: C8, C9, C10, C11, C12, C13, C14, C15, R14, R15, R16,
R17, R18, R19, R20, T1, T2, and U1–U7 in the interface.
Fixed for 1.0, clearing everything that had been left in `TODO.md`: C16, R21,
R22, T3, H1, and U13–U16. U8's remainder (announcements) landed as U16.
`WONTFIX` with the reasoning recorded: C5, R9, R13.

**Every adversarial pass over this codebase has found real defects in code
written during the previous one.** C13 and C14 came from C10 and C9, R17 from R2,
and a fourth pass over the outline work (R19) found eight more in code written
minutes earlier — including a destination-mapping error affecting the majority of
real bookmarks and an unbounded recursion that could kill an entire batch. That is
not an argument against changing things; it is the argument for
[CONTRIBUTING.md](CONTRIBUTING.md)'s review step, and for never treating a fix as
finished because it compiles.

Five entries turned out to be **wrong as written** — C5, R3's title, R7's
recorded fix, R9, and R21's whole diagnosis (SIGTERM already reached the process
group; it was the SIGKILL escalation that leaked, which is the opposite of where
the entry pointed) — so re-measure before you fix, and correct the entry when it
does not hold. R21 is the cleanest example in the register: the recorded fix was
a `posix_spawn` rewrite of the riskiest code in the project, and the measurement
turned it into two lines.

Update this file as items are fixed — including the evidence that they are.

---

## Correctness — loses or corrupts content

### C1 · Four silent `return`s in `draw()` drop whole lines — FIXED

### C2 · `useJBIG2` silently overrides "Rebuild page images first" — FIXED

### C3 · Image inputs can never produce a searchable PDF — FIXED

### C4 · Duplicate observations double the text on a line — FIXED

### C5 · Right-to-left text is stored in visual order — WONTFIX

### C6 · stderr drain drops the real error message, and races — FIXED

### C7 · MediaBox vs CropBox — FIXED *(was unverified; now settled by measurement)*

### C8 · Concurrent files erased each other's lost-line reports — FIXED

### C9 · A logo set the whole page's rebuild resolution — FIXED

### C10 · The published copy was cropped to the crop box — FIXED

### C15 · A multi-page TIFF was reduced to its first sheet — FIXED

### C13 · The published copy displayed more than the original — FIXED

### C14 · The DPI floor upsampled genuine low-resolution scans — FIXED

### C12 · A page the recogniser skipped published as a page with no text — FIXED

### C11 · A dropped image was wrapped squashed, or sideways — FIXED

### C16 · A short text layer published as a complete file — FIXED

### C17 · A born-digital PDF was silently degraded — FIXED

### C18 · Line ends were unselectable on dense scans, and fixing it welded words — FIXED

### C19 · "Use Existing Text" silently writes an empty section for a page with no text — FIXED

### C20 · `headroom` and `rightLimit` disagree about "the same line", crushing runs to sub-point height — FIXED

### C21 · A half-specified outline destination on a quarter-turned page keeps the fabricated coordinate — FIXED

### C22 · `deduplicated` deletes a distinct line whose text repeats in a tightly-set row — FIXED

### C23 · C13 recurs on the default route: the rebuilt copy displays what the original hid — FIXED

### C24 · `largestImage` answers a document-wide question, so one page's plate sets another page's rebuild resolution — FIXED

## C24b, the second half, measured — 2026-08-16 (it was open when this was written)

**The measurement now exists and it is smaller than the entry assumed.**
`Flattener.drawnLargestImage` resolves every `Do` the content stream issues, following
forms by scanning their own content streams, and reports the largest image the page
**actually draws**. It was wired into nothing on this date — `rebuildDPI` still read
`largestImage` — because what closed this half was a decision about one page, and that page
is named below. `rebuildDPI` reads this walk as of 2026-08-17.
`Tools/score-drawn-images.swift` is the instrument: one row per page, no rendering, all
16,987 pages in **74 to 93 seconds** over three timed runs — the first draft of this
paragraph said "under a minute", which no run here has managed.
`DRAWN-2026-08-16.tsv` beside this file is the evidence — the 45 rows that move plus the 3
unreadable ones, cut from a 16,987-row sweep, and **reproduced byte-identically from an
independent second run** before anything below was believed. Like every dated record here
it is one run, not a claim about the present.

Over all 233 documents and 16,987 pages:

| the drawn walk against the `/Resources` walk | pages |
|---|---|
| agree | 16,654 |
| the dictionary walk found no image at all | 285 |
| **the page draws a *smaller* image than the dictionary holds** | **39** |
| **the page draws a *wider* one** — see below, this is not a defect | **6** |
| a `Do` this could not resolve, so "could not tell" | 3 |

**The entry's 45 is right as a total and wrong as a description.** 39 + 6 = 45, and the
six are not "smaller". They are `AI 2027` pages 4, 8, 10, 11, 15 and 54.

**Which retires the observation this entry recorded without a cause.** The entry says a
filtered prototype reported a *larger* image than the shipped walk on six pages of
`AI 2027`, that the proposed cause was the `walkedAt` memo, and that the cause was tested
and refuted — leaving the observation standing with no explanation. The cause is that
**both walks pick the largest image by *area* and then report its *width***. A subset's
largest-by-area can be the wider of two. Verified by listing every image in the page's
`/Resources`: `AI 2027` p4 draws only `/Im5`, **3000x1011** (area 3.03 M), while the
dictionary's largest by area is `/Im52`, **2929x2370** (area 6.94 M). Neither walk misses
a candidate. The entry's single pages of `Kazin_1955`, `Intellectual History Newsletter`,
`Zipkin_2000` and `UN-OCred` do **not** reproduce and were the prototype's own.

A check asserting the obvious invariant — a subset cannot answer larger — would have
passed on every page of the suite's fixture and been wrong about the corpus. The seventh
page of `shared-resources.pdf` is a 4000x100 strip in a dictionary whose largest by area
is the 3000x4000 plate, so the fixture now carries the shape rather than the assumption.

**The 45 pages are three documents, and `Sherman_1986` is a third nobody had named**:
`AI 2027` 38, `Sherman_1986` 5, `Batzell` 2. `Sherman_1986`'s five move by a hair —
419.0 DPI to 417.4, 416.8, 411.2, 418.1, 413.1 — because each page draws a plate a few
pixels narrower than the document's widest.

**And the blocker is one page, not a population.** The entry says the next step is
`minimumScanPixelWidth` "recalibrated against the per-page population rather than the
document-wide one". Measured, that population is **three pages**, because the constant is
only consulted when the DPI falls below `minimumPlausibleScanDPI` and 42 of the 45 land
above it:

```
Batzell  p9   1254 px   147.5 DPI   width >= 600 -> trusted at 147.5   plausible for a scan
Batzell  p22   600 px    70.6 DPI   width >= 600 -> trusted at  70.6   suspected THE DEFECT
AI 2027  p1    245 px    29.6 DPI   width <  600 -> fallback 300       correct
```

So the constant faces three pages, and the one it was *suspected* of getting wrong sits
**exactly on its own boundary value of 600**. That is a much narrower question than
recalibration: what should a page whose only drawn image is 600 px wide be rebuilt at?
Answering it wants `Batzell` p22 rendered both ways and its characters counted — not a
new threshold, and **not a guess**. The two refused repairs are still refused for their
own reasons; nothing here rehabilitates them.

## C24b's blocker, measured — 2026-08-17: the constant is right about all three

**It was rendered both ways, and the row above marked `THE DEFECT` is not one.** The claim
being tested — this entry's, `Sources/Flattener.swift`'s and
`Tools/score-drawn-images.swift`'s, in the same words in all three — was *"Rendering a page
of type at 70 DPI is C9 again."* **It is false, and the sentence has been corrected in every
place it appeared.** C9 was a 595x841 pt page whose largest image implied 1.9 DPI, rebuilt
as a **16 x 23 pixel** image: the page was gone. `Batzell` p22 at its own 70.6 DPI is
600 x 776 px, and it recognises.

`Tools/score-rebuild-dpi.swift` is the instrument. It drives the shipped pipeline —
`Flattener.rebuildDPIOverride` substitutes the resolution and `flatten`, `mrcLayers` and
`Recogniser.render` all read the one function it hooks — then counts what comes back out of
the **published** file, not off Vision's observations, so the figures compare with this
entry's own before/after table. Every candidate resolution is computed by shipped code:
`rebuildDPI(of:)` for `shipped`, `rebuildDPI(from:)` over `drawnLargestImage`'s answer for
`drawn`, `fallbackRebuildDPI` for `fallback`. `REBUILD-DPI-2026-08-17.tsv` beside this file
is the run.

**And the measure the entry asked for was not evidence.** "Count the characters"
reads **1,961 at 70.6 DPI, 1,961 at 300 and 1,961 at 369.6** — three *different* strings of
identical length, which the tool prints a hash per row to make visible — and 1,960 / 1,962 /
1,962 at 96 / 150 / 200. The character count on this page is flat across a 5x resolution
change and moves only once recognition collapses outright. What moves is **word retention
against the page's own embedded text**: p22 is born-digital, so the layer the rebuild
rasterises away *is* the ground truth, and the multiset intersection of it with the
published text is a real accuracy figure rather than a volume figure.

```
Batzell p22   truth 291 words                          route  bytes    chars  retained
  drawn      70.6 DPI    600 x 776 px   0.5 MP         grey    51,302   1961   92.8%  (270/291)
  fallback  300.0 DPI   2550 x 3300 px  8.4 MP         grey   308,760   1961   93.8%  (273/291)
  shipped   369.6 DPI   3142 x 4066 px 12.8 MP         grey   407,556   1961   94.2%  (274/291)
  ---- three more points on the same axis ----
            200.0 DPI   1700 x 2200 px  3.7 MP         grey   175,696   1962   93.8%  (273/291)
            150.0 DPI   1275 x 1650 px  2.1 MP         grey   117,661   1962   93.1%  (271/291)
             96.0 DPI    816 x 1056 px  0.9 MP         grey    68,374   1960   94.2%  (274/291)
  ---- negative controls, both below the constant's reach ----
             50.0 DPI    425 x 550 px   0.2 MP         grey    40,230   1415   60.5%  (176/291)
             30.0 DPI    255 x 330 px   0.1 MP         grey    21,370    215    3.4%   (10/291)
```

**Trusting the page's own 70.6 DPI costs no difference this instrument can resolve, and
saves 87% of the published bytes** — 51 KB against 408 KB, which is 12.6% of them. Read the
whole axis and not the first three rows: retention over 70.6–369.6 DPI is a **non-monotone
92.8%–94.2%**, and **96 DPI ties the 369.6 maximum** at the same 274 of 291 words while
beating 150, 200 and 300. So 1.4 points is inside this instrument's spread and "70.6 costs
four words" would be reading noise as a cost. What the axis *does* say is where the floor
is: two steps further down, retention goes to 60.5% and then 3.4%. The negative controls are
also what say the instrument can fail at all.

**The other two pages are right too, and one of them is right in the direction nobody
checked.**

```
Batzell p9    truth 382 words                          route  bytes    chars  retained
  drawn     147.5 DPI   1254 x 1623 px  2.0 MP      bilevel    41,026   2615   93.5%  (357/382)
  fallback  300.0 DPI   2550 x 3300 px  8.4 MP      bilevel    63,727   2665   93.2%  (356/382)
  shipped   369.6 DPI   3142 x 4066 px 12.8 MP      bilevel    72,161   2641   94.5%  (361/382)

AI 2027 p1    truth 27 words                           route  bytes    chars  retained
  drawn =
  fallback  300.0 DPI   2480 x 3508 px  8.7 MP      bilevel    19,652    174   85.2%   (23/27)
  shipped   354.3 DPI   2929 x 4142 px 12.1 MP      bilevel    20,956    186   85.2%   (23/27)
  ---- negative control: what the constant refuses ----
            29.6 DPI     245 x 346 px   0.1 MP      bilevel    12,102    100   33.3%    (9/27)
```

`Batzell` p9 at its own 147.5 DPI **beats the 300 fallback** — 357 words against 356 — so
upsampling a coarse page buys nothing here, which is the asymmetry `minimumPlausibleScanDPI`
was argued from, holding in the one place it had never been measured. And `AI 2027` p1 is
where the constant earns its keep: refusing that page's 29.6 DPI is worth **14 of its 27
words**.

**So `minimumScanPixelWidth` needs no recalibration, and the answer to "what should
`Batzell` p22 render at" is its own 70.6 DPI — which is what the shipped policy already
says.** The next step for this half was the wiring alone: `drawnLargestImage` into
`rebuildDPI`, behind a corpus gate run, moving 45 pages — and it landed the same day, in
`## C24's wiring` below. Nothing in *this* section changed a route, a resolution or a
published byte — `rebuildDPIOverride` is `nil` in the app and no setting reaches it, which
the suite asserts before it sets it and again after it clears it.

**And "right about all three" is right on a criterion, which is worth naming.** On p9 and on
`AI 2027` p1 the constant's decision wins on retention alone. On p22 it does not: 92.8%
against the declined fallback's 93.8% is a point *down*, inside the spread but not above it,
and what makes it the right call is 87% fewer bytes for it. Whether that trade is acceptable
is a judgement about `fallbackRebuildDPI` and **not** a measurement; the figures are here so
it can be made on them rather than asserted. What *is* measured is that no threshold change
is required — the review of this diff is what insisted on the distinction.

**Verified by running code, not reasoned about**: 14 pipeline runs over 3 pages of 2
documents — 15 candidate labels, two of which are one resolution on `AI 2027` p1 and are run
once — each a full `OCRModel.makeSearchablePDF` on the page plus a `flatten` for the route
and the raster; the whole TSV reproduced from a second independent invocation with every
figure identical; the two-arm override asserted at all three doors — **the positive arm only**,
34 of 34 green in an extracted single-section probe; and both negative controls. **Not run: the
negative arm, and the mutant.** Neutering the hook to watch the nine new checks go red was
attempted twice and both attempts died in the rebuild at the 10-minute tool ceiling, so those
checks are *believed* able to fail and not *known* to be — the reasoning is that door 1's two
rows kill each other's failure modes, but this register's rule is that only `mutate.py` settles
it. `logic/C24-override-ignored` is in the catalogue for exactly that — the pattern matches
`Flattener.swift` exactly once and it is a behaviour change rather than a compile error — but a
scoped campaign is a full suite per verdict and it had not been spent. **That was the first
thing to do here, and `### The override seam, mutated` below is what happened when it was.**
*(This paragraph was two near-identical copies of itself until 2026-08-17, disagreeing on
whether the cost was "~45 minutes" or "~45 minutes per verdict" while a paragraph six below
gave a measured 37 — an unfinished edit, left immediately after the sentence naming the next
step. It now states no duration at all: every duration in this thread has been a reading of
the machine's load, and the campaign section carries the measured ones.)*
**The straight-line clear now has a `defer` behind it**, added 2026-08-17: `check()` does not
exit on failure, so nothing leaked, but a hook left set would have re-rendered every later
section of the suite at the probe resolution — a whole-suite failure whose cause sits 200 lines
above the first red row. The explicit clear and its assertion stay; the `defer` removes the
class rather than the instance. **Still not asserted structurally**: `mrcLayers`' door reads
`backgroundWidth`, whose downsample factor is chosen by an R56/R57 shape signal that is
itself DPI-dependent — so if that signal ever answers differently at 90 and 180 DPI, the row
fails naming the override instead of the signal.

**What was still true when this section was written.** `score-routing` refused the rows for
`Batzell` and `AI 2027`; the four `manifest.tsv` rows were still the old wrong numbers; and
wiring the drawn walk into `rebuildDPI` still needed a corpus gate run, because it changes
what the default route renders on 45 pages. That run is the next section.

**Five mutants**, because this walk's whole claim is that it needs no constant and a
constant mutant can reach none of it: `logic/C24b-form-not-followed` (repair 2's blind
spot: a form's own content stream never scanned), `logic/C24b-bare-form-resources` (forms
followed only when they carry `/Resources`), `logic/C24b-scope-does-not-descend` (the
scoping defect below), `logic/C24b-no-image-is-not-unknown` and
`logic/C24b-unresolved-name-is-not-nothing` (T14's rule, once in each direction).
`python3 Tools/mutate.py --only C24b` is what says whether these checks can fail; each
verdict costs a full suite, and that is **about 37 minutes measured** on this machine —
timed twice, 20:31→21:08 standing alone and 21:42→22:19 inside the pre-commit hook — rather
than the "2 to 4 minutes" `mutate.py`'s own header claimed and the "3-6 min" four of this
project's documents claimed until 2026-08-16. A five-mutant campaign is therefore about
four hours, which is why it is a separate piece of work and not a step in the commit that
added the mutants. **That campaign was run on 2026-08-17; `### The campaign` below is its
result**, and the "about four hours" predicted here came in at 4h27m — an **under**-estimate
by 27 minutes, which is the same direction every other figure in this thread got wrong and
the direction that section itself calls the one that gets an unattended session killed
mid-campaign. This sentence read "the first estimate in this thread that erred in the safe
direction" until 2026-08-17, with the sign backwards.

**The suite is 1,141 checks with no skips**, measured by this work's own pre-commit run —
1,137 before the four checks page 8 and page 9 brought.

Three pages of `Astin__The Challenge of Open Admissions` are the "could not tell" case in
the wild — a `Do` naming something the page's resource chain does not hold. The walk
reports `.unreadable` there and a caller keeps the `/Resources` answer, which is the
direction that costs bytes rather than detail.

### The override seam, mutated — 2026-08-17, both killed, and the second one settles the review's finding

Run scoped as `python3 Tools/mutate.py --only C24-override`, against a **green baseline of 1,152
checks**. Two mutants, two verdicts, and the second is the point of the exercise:

| mutant | verdict | cost | killing checks |
|---|---|---|---|
| `logic/C24-override-ignored` | **killed** | 3,453 s | **5** |
| `logic/C24-override-nil-means-fallback` | **killed** | 3,014 s | **1** |

**Read the last column, not the verdict column.** The first mutant neuters the hook entirely and
five separate rows object, which only says the seam is read at all. The second is the *nearer*
wrong implementation — `override(page) ?? fallbackRebuildDPI`, i.e. `nil` from the closure taken
as "use the fallback" rather than "no opinion about this page" — and **exactly one** check kills
it: *"…and a declined page keeps its OWN answer, not the fallback"*.

That check does not exist in `c8855f6`. So against the nine checks this block shipped with, the
count would have been **zero**: the mutant would have SURVIVED, and the register would have gone
on recording those nine as pinning a seam that one of the two obvious wrong readings walked
straight through. The review called that *the eleventh check in this register that could not
fail*, and it reasoned its way there from the fixture — `quiet`'s own shipped answer already IS
`fallbackRebuildDPI`, so it is the one page the closure declines and every row agreed with the
wrong reading by accident. **`mutate.py` has now settled it, which is this register's rule.** The
finding was right, and it was right for the stated reason.

⚠️ **What this does NOT say.** The campaign was run in the worktree that already carried the new
check, so "would have survived against c8855f6" is an inference from the killing-check count
plus that check's absence there — a *measured* count and a *checked* absence, but not a run of
the mutant against `c8855f6`'s own `Tests/main.swift`. That run would cost another full suite and
was not spent. It is the honest reading, recorded rather than rounded up.

**On the cost — and this is the first estimate in this thread that nearly held.** `test-lock.sh`
recorded the whole campaign as one row: **8,882 s** (2 h 28 m), completing 10:01:10 at loadavg
**5.92**, the highest in the ledger. That decomposes as a baseline of **2,415 s** plus the 3,453 s
and 3,014 s above. The tool announced *"roughly 131-136 minutes … Budget the 136"*, i.e. 8,160 s,
so it came in **1.09x low — about 9% under the figure it told the reader to budget.**

⚠️ **That deserves stating plainly, because this thread has trained the opposite expectation.**
The same estimator is recorded above as **4.85x** low and, out of sample, **4.22x** low. It is
now the version that *reads `mutation-log.tsv`* rather than reasoning from a remembered suite
duration, and on this campaign it was nearly right. One good sample does not retire the warning —
the 4.22x row was itself out-of-sample and the estimate still carries no term for contention —
but "budget its high end and then some" was, this once, exactly enough. Note also that the
highest loadavg in the ledger produced neither the fastest nor the slowest per-suite cost, which
is the ledger's standing point: **the loadavg column does not order the durations.**
`Tools/mutation-log.tsv` has both mutant rows; `$STATE/suite-timings.tsv` has the campaign row.

### What the review of this diff found, and one of them was a check that could not fail

Two rounds: an agent with an adversarial brief, then the findings tested by running code
rather than argued about. **Every one of the four below was in code written the same day**,
and the register's own habit is what caught them — recompute the arithmetic, and reach the
guard before believing the check on it.

- **`logic/C24b-no-image-is-not-unknown` could not have been killed.** Reaching
  `guard state.width > 0 else { return .noImage }` needs a page that invokes an XObject
  (so the early `drawsAnyXObject == false` return does not fire), resolves every name it
  invokes, and still ends with no image — a page whose only `Do` is a *form that draws no
  image*. The fixture had no such page: all seven either returned early or ended with a
  width, so the mutant would have SURVIVED against a green suite. **Verified by building
  the walk and running it over the missing page before writing the check** —
  `drawsAnyXObject=true`, `drawn=noImage`, which is the line the mutant edits. Page 8 of
  `shared-resources.pdf` is that page. Nine checks in this register could not fail; this
  would have been the tenth, and it was written by the same session that added the mutant
  meant to catch exactly this.
- **A bare form resolved its names against the page instead of its invoker.** PDF gives a
  form with no `/Resources` of its own the scope of the stream that *invoked* it. The walk
  fell back to the page's dictionary, which is the same thing only when the page is the
  invoker — true of every bare form in the fixture and, as it turns out, of every one in
  the corpus. Page 9 tells them apart: a bare form nested inside a form that carries its
  own `/Resources`, both scopes defining `/Ix`, where the invoker's is 1500 px and the
  page's is the 3000 px plate. **Measured 3000 before the fix and 1500 after.** The scope
  now descends and is restored on the way out, and `logic/C24b-scope-does-not-descend`
  removes that descent.
- **And the obvious repair for it was wrong, which is why it was run rather than reasoned
  about.** The comment being fixed asserted that `CGPDFContentStream` "searches its
  parent", so passing the form's own stream dictionary would let the chain inherit. It does
  not: `CGPDFContentStreamGetResource` does not search the parent for a name absent from
  the dictionary it was handed, and that version measured **`.unreadable` on both page 5
  and page 9** — it would have blinded the walk on precisely the nested scans repair 2 died
  on. A review finding's first fix is not automatically right; this register has now said
  that three times (C23, R57's ink gate, here).
- **The instrument's verdict column was ordered wrong.** `case (nil, _)` came first, so any
  page whose dictionary walk found nothing was filed `noDictImage` *whatever the drawn walk
  answered* — and an unresolvable name is likeliest on exactly such a page, so the
  published "3 unreadable" was really "unreadable pages that also had a dictionary image"
  while this entry quoted it as the number of pages the walk could not read. **On this
  corpus it changed no row** — all 285 `noDictImage` pages report `drawnKind=none`, checked
  by cross-tabulating the two columns — so the number was right by luck. Fixed by asking
  the drawn answer first, and `drawnOnly` now names the case the old order hid: the drawn
  walk finding an image the dictionary walk did not, **0 pages of 16,987**.
- **The two walks disagreed about how deep to look**, which is a confound in the one
  instrument built to isolate a single variable. `largestImage` refuses depth 4 and so sees
  images listed three form-levels down; the drawn walk entered a form whenever
  `s.depth < 4`, which is a fourth level. An image drawn there would have read as a
  drawn-versus-dictionary difference caused by the caps rather than by the page. Now `< 3`.
  Nothing in the corpus nests that deep: **`< 4` and `< 3` produce byte-identical sweeps.**
- **The memo could not stay keyed on the form stream alone** once the scope descends,
  because the same bare form reached from two scopes is two different measurements and the
  second was being skipped. Keyed on the (stream, scope) pair, and taken *after* the scope
  is resolved rather than before, so what may be skipped is exactly what was already
  answered. Its comment also imported R25's 5.09 s figure, which belongs to `largestImage`
  and its dictionary-keyed memo; corrected to claim the shape and not the measurement.

**The negative control for all of it: the 16,987-row sweep is byte-identical before and
after**, so every number above this section stands as measured, and the corpus contains no
page that any of these three code fixes moves. Two of them were found by reasoning about
shapes the corpus does not have — which is the argument for the hand-written fixture, since
nothing in `testdocs/` would ever have failed.

### The campaign, run 2026-08-17 — all five killed, and the tool's own estimate was wrong by 4x

`ops/autonomous/test-lock.sh run --label mutants-C24b -- python3 Tools/mutate.py --only C24b`,
started 22:46:47 on 2026-08-16 and finished 03:13:46 on 2026-08-17 — **4h27m end to end**.
**Baseline 1,141 checks, green**, which is the number the section above predicted. Verdicts as
`mutation-log.tsv` records them, with the killing check counts:

```
logic/C24b-form-not-followed                killed  2700 s  3 checks
logic/C24b-bare-form-resources              killed  2693 s  2 checks
logic/C24b-scope-does-not-descend           killed  2661 s  1 check   <- the review's bare-form fix
logic/C24b-no-image-is-not-unknown          killed  2719 s  1 check   <- needs page 8 to be reachable
logic/C24b-unresolved-name-is-not-nothing   killed  2621 s  1 check
```

The five mutant runs are 13,394 s of that; the baseline is not timed into the log, so by
subtraction it was about 2,600 s including the rsync — consistent with the others, as it
should be, since it is the same suite.

**All five killed, so none of the five checks is a check that cannot fail.** That is the
gate this half of C24 had not been through, and the one that mattered most is
`logic/C24b-no-image-is-not-unknown`: the review above found it **unreachable by any page
of the fixture**, added page 8 of `shared-resources.pdf` to reach it, and predicted that
without page 8 the mutant would have SURVIVED a green suite. It is killed, so page 8 does
reach the guard. Note also that `logic/C24b-scope-does-not-descend` was killed by **exactly
one check** — the one the review's bare-form finding added — so that finding's fix is now
load-bearing by machine rather than by argument.

**And the campaign falsified the estimate the tool printed before starting it.** `mutate.py`
announced *"5 mutants … roughly 20-55 minutes"* and then ran for 4h27m — **out by 4.85x on
the high end** (267 min against 55) and 13.4x on the low, in the direction that gets an
unattended session killed mid-campaign. Four documents rounded that to "4x", "five", "four"
and "a factor of four" before anyone divided it; 4.85x is the measured figure. The startup line
was two hardcoded constants, `len(todo) * 4` to `len(todo) * 11` minutes, sitting under a
comment that described itself as *"a RANGE read off this tool's own log, not a constant"* —
so the comment was true of the intent and false of the code, and nothing could tell the
difference because nothing outside `run()` could call it. Fixed in this commit, and the
fix has three parts, none of which is a new constant:

- **It reads the log.** `logged_seconds()` parses the per-run durations; `estimate_minutes()`
  takes min and max over the newest `ESTIMATE_SAMPLE` (5) rows. The whole log is the wrong
  window — it reaches back to a smaller suite on a quieter machine.
- **It counts the baseline.** The baseline is a full suite run, it happens on every campaign,
  and the old arithmetic omitted it, so even a correct per-run figure understated every
  campaign by one whole suite.
- **It says which number to budget**, because the range is wide and the high end is the
  useful one.

**The check on the fix is a consistency check, not a negative control — this section
called it one and that was wrong.** Run against the completed log the fixed arithmetic
predicts 262-272 minutes for a five-mutant campaign against the 267 this one took, and it
could not have come out otherwise: the window it samples **is** this campaign's own five
rows, so it is min/max over the very numbers being predicted. An in-sample fit is a sanity
check on the plumbing and no evidence at all that the estimate works.

**The out-of-sample number is the one that matters, and it is not good.** Driven over the
log as it stood when the campaign started — `git show 1935d05~1:Tools/mutation-log.tsv`, 74
rows, newest five 471-632 s (this said `HEAD:`, which is the *post*-campaign log and
reproduces the in-sample 262-272 instead — a recipe that did not reproduce, in the paragraph
arguing for re-derivable over quotable) — the fixed estimator says **47-63 minutes against the 267 that
followed: 4.22x low.** The hardcoded line it replaced said 20-55, which is **4.85x low** on
the same run. So the fix removes a stale *constant* and makes the tool read its own data;
it does **not** make the estimate survive a change in load, and the two errors are within
15% of each other. Measured 2026-08-17 by importing `logged_seconds` and
`estimate_minutes` and feeding them the pre-campaign log — run, not reasoned about. Two
consequences worth carrying:

- `ops/autonomous/resume-prompt.txt` tells a session to *"read the estimate the tool prints
  at startup, not any number written here"*. Still better than a stale constant, but it is
  advice to read a number that was 4.22x low the one time it has been checked out of
  sample. The startup line now says that about itself, in the line a caller actually reads.
- Nothing in the log can fix it, because the term that moved is not in the log. The
  contention paragraph below is the same finding from the other end.

Over the whole catalogue of 89 the estimator now says **65.5-68 hours** (3,931-4,078
minutes); this section said "66-68" off the same run, rounding the low end up. The 77
durations it reads out of 79 rows are 79 minus the two `exit 133` crashes described below.

**`mutate.py` now has a `--self-test`, which it did not before** — the tool the entire
mutation gate runs through had none, while `.githooks/pre-commit` has run one for any staged
`Tools/*.py` that carries the flag since T18. **29 checks** — 19 in `1935d05`, ten more in the
follow-up below; this said 25, which was neither figure. And **two of them were watched
failing against the old arithmetic before the fix went in** ("got 20-55 min" is the
self-test reproducing the real campaign's own wrong sentence).

**Then every guard was mutated one at a time, and this section's first answer — "12 of 14
mutations killed, two survivors" — was written from reasoning rather than from a run. The
run says 21 of 26** — and it took three passes to get there, because each round of review
enumerated mutations the previous round had not thought of (12 of 14, then 16 of 20, then 18
of 22, then this). The denominator growing is what an honest one does; the first figure was
wrong in both halves. Every mutation, its verdict and the checks that killed it are in
`SELFTEST-MUTANTS-2026-08-17.tsv` (26 rows, 7 columns), so the count is re-derivable instead
of quotable — including the two mutations that are only a defect **as a pair**, which the
first version of that file omitted and so made a real check look like a check that kills
nothing. What the run found, in order
of how much it mattered:

- **`estimate_window`'s check could not fail.** This register's running count of these is
  itself inconsistent — a 2026-08-14 entry calls one "the eleventh", `CLAUDE.md` calls a
  2026-08-16 one "a tenth" — so this adds one rather than claiming an ordinal. It asserted
  `estimate_window(secs) == [80, 632, 283, 2700, 2693]` over a `secs` exactly
  `ESTIMATE_SAMPLE` long, and at that length `seconds[-5:]`, `list(seconds)`, `seconds[:5]`
  and `seconds[-6:]` are the *same list*. All three wrong windows survived. **A fixture whose
  length equals the constant under test cannot see a window at all**, which is the general
  shape and worth more than the instance: the check now feeds six rows.
- **The same defect was then reproduced, in this commit, minutes later.** The two new
  `startup_line` checks were first written against the same five-row `secs`, so
  `min(window)` → `min(seconds)` survived them for exactly the reason above. Caught by
  re-running the harness rather than by reading the diff. Both now feed six rows.
- **`int(f[2])` → `float(f[2])` survived.** The existing "non-integer seconds field" check
  feeds `"n/a"`, which is not a float either. A `"45.5"` row is what separates them.
- **Two survivors are survivors for a better reason than the review that found them
  supposed.** A 2026-08-17 review reported `ABORTED_DETAIL.match` → `.search` and dropping
  the pattern's `^` as uncovered. Measured, **each alone is a behavioural no-op**: `.search`
  on a `^`-anchored pattern can only match at position 0, and `.match` anchors there
  whatever the pattern says — anchored-match, anchored-search and bare-match all answer
  identically on both a mid-string and a leading detail. Only *both at once* reads a detail
  that merely mentions the abort shape as an abort, and the new "mentions the abort shape"
  check kills that pair. Redundancy, not blindness.

The four remaining survivors are all no-ops of that kind and are named in `logged_seconds`'s
docstring rather than left to look like coverage: admitting `"NOT-APPLIED"` to the timed
verdicts changes nothing because those rows carry seconds=0, dropping the header-row guard
changes nothing because a header's verdict field is the literal `"verdict"`, and the abort
pair above. Each is kept as belt to another's brace.

**Two things the campaign settled that were not about C24 at all**, and both were found by
suspecting the instrument:

- **The per-run cost is not a function of the suite's size.** These five runs came in at
  ~2700 s against ~630 s for the R56/R57 mutants recorded **that same morning** — 09:47,
  committed 09:59 in `41815b9`, about thirteen hours before this campaign started at 22:46,
  and *not* "the evening before" as this entry, `mutate.py`'s header and
  `ops/autonomous/vision-ocr-autonomous.sh` all said until 2026-08-17. The clock is not
  bookkeeping here: quiet-morning against loaded-overnight is the entire argument, and
  dating the cheap rows to the evening puts both readings in the same half of the day and
  garbles it. That jump sits on top of a catalogue that grew by four checks (1,137 → 1,141)
  in between, and four checks do not do that, so the
  header's old sentence — "it grows every time the suite does" — was keyed on the wrong
  variable. **That much is measured; the cause is not.** The session that ran the campaign
  reported `ps -r` showing OneDrive at ~50% of a core and CrashPlanService at ~24% — *its*
  observation, not re-made here — and the suite is single-core bound at ~96%, so contention
  for that core is the plausible term and a 1-minute load average an insufficient covariate
  for it, since neither process moves loadavg much. Filed as an inference with its evidence,
  not as a finding: the controlled experiment has not been run. It bears on any timeout sized
  off `$STATE/suite-timings.tsv`, which has **three rows**, not the one this entry first said
  and not the two its first correction said: `474 s @ loadavg 3.47`, this campaign's
  `16,012 s @ 2.39` — which is **six suite runs, ~2,669 s each**, not one run, and quoting the
  campaign total as a duration is the same instrument error twice — and `2,552 s @ 4.20` from
  the follow-up commit's own hook. Ordered by duration those load averages read 3.47, 2.39,
  4.20: **the column does not order the durations.** One pair points the way load would
  predict and one points the other way, which is why `ops/autonomous/README.md`'s "a 5x swing
  from load alone" is retracted there. The swing is real (474 s against ~2,669 s is 5.6x);
  the 1-minute load average is not a sufficient covariate for it.
- **Two rows in `mutation-log.tsv` are not durations.** `logic/R24-safeInt-finite` at 80 s
  and `logic/R30-monotonic-underflow` at 89 s are `exit 133` — SIGTRAP, crashes 80 and 89
  seconds in respectively (this entry said "80 seconds in" of both),
  correctly scored as kills. They were the log's two cheapest rows, so they had become
  the published floor of its per-run range, including in `mutate.py`'s own header. A crash is
  not a fast suite. `logged_seconds` excludes them by their detail column, and that exclusion
  is one of the twelve killed mutations.

**The sibling sweep, since a stale duration claim is a pattern and not an instance.**
`Tools/` holds four Python tools. `sample-zotero.py` and `sweep-zotero.py` already carry
`--self-test`; `mutate.py` does now; **`bundle-libs.py` still does not**, and it is the one
place left where the T18 gate would bite — it parses `otool -L` output in `dependencies()`,
which is exactly the "a parser that accepts a malformed row" shape `py_compile` cannot see.
Not fixed here: it is a build-time tool on a different path, nothing in this campaign
touched it, and bundling an unrelated tool's first self-test into a mutation-campaign commit
is how this register got C13. It is named so the next sweep does not have to rediscover it.
Separately, `--list` reported **89 mutants** when this was written, not the 84 that
`ops/autonomous/resume-prompt.txt` and `vision-ocr-autonomous.sh` both asserted in the present
tense — the C24b five had been added without either being updated. Both corrected here, along
with the "~55 HOURS" figure they carried: at the then-measured ~45 min per mutant the full
catalogue was nearer **65 hours**, so that number was about right by luck and wrong in its
reasoning. ⚠️ **Both figures are clamped-era and neither is current**: `1dbaafd` took a 16.2x
clamp off the suite on 2026-08-24 and the next scoped run measured **246 s** a mutant, so the
catalogue is ~7 h — which is this paragraph's own lesson landing on this paragraph. **And the same defect immediately recurred**: by `d83ddc5`, hours later, `--list`
printed **91** while six files still said 89 — measured 2026-08-17 by running it on that
commit. C24's wiring takes it to **94**. A count asserted in prose goes stale the next time
anyone adds a tuple, which has now happened three times (84 → 89 → 91 → 94); the durable
form is `python3 Tools/mutate.py --list | tail -1`, and every one of those six sites now says
so instead of carrying a number.

**And the sweep for the crash-as-duration finding was not finished when it was written.**
`80-632 s` was still published as this suite's duration range in five files after the entry
above established that its floor is an `exit 133` crash: `ops/autonomous/vision-ocr-autonomous.sh`,
`ops/autonomous/test-lock.sh` (twice), `ops/autonomous/tests/prove-test-lock.sh`,
`ARCHITECTURE.md`, and `ops/autonomous/README.md`'s ledger. All six sites corrected on
2026-08-17 to **416-632 s**, which is what 2026-08-16's morning mutation runs recorded (the
seven rows `41815b9` added are 416/473/471/475/631/623/632, and the earlier morning commits
`2cf2370` and `12acd38` add nothing below 469) — the 80 s and 89 s rows are the two crashes
and belong to an older, smaller suite besides. **The first attempt at this correction wrote
471-632 and was wrong in the same way as the thing it corrected**: 471 is `min()` of the
*estimator's newest-five window*, a window boundary relabelled as a measurement. Caught by
review, from the log; the review is why six files do not now publish a second invented floor.
`test-lock.sh`'s second site had the *clock* right where three other documents had it wrong
("the morning's mutation runs"), which is how the right date was recoverable at all.
Two of those files are sized off that range — `test-lock.sh`'s wait budget and
`prove-test-lock.sh`'s expectation — so the floor being a crash is not a cosmetic matter
there: a timeout derived from 80 s is derived from a suite that died.

**What this does not do: it does not touch `Sources/`.** No route changes, no resolution
changes, no sweep to re-run — the negative control above still stands unmodified, and C24
was HALF FIXED for the reason it already was when this section was written. Both remaining
sub-steps were unchanged: decide what `Batzell` p22 should render at, then wire the drawn
walk into `rebuildDPI` behind a corpus gate run. **The first was done in `c8855f6`; the
second is the next section, and it closes the entry.**

## C24's wiring, measured — 2026-08-17: the gate ran, and the entry is closed

**`rebuildDPI(of:)` applies the shipped policy to `drawnLargestImage`.** The policy is
untouched — the same three branches, the same two constants — and what changed is which
measurement it judges. `.unreadable` keeps the `/Resources` answer, which is T14's rule one
level up from the walk that already obeys it; `.noImage` takes the fallback; `.largest` takes
the drawn DPI and the drawn pixel width. Six lines.

**Exactly 45 pages change resolution and 16,942 do not**, measured over all 16,987 corpus
pages, and they are the *same* 45 the 2026-08-16 sweep named — `diff` of the two page lists
is empty. `AI 2027` 38, `Sherman_1986` 5, `Batzell` 2. `DRAWN-2026-08-17.tsv` beside this
file is the cut, and the sweep was reproduced **byte-identically from a second independent
invocation** before any of it was believed.

**The instrument had to be repaired before it could be the gate, and the repair is the
interesting part.** `Tools/score-drawn-images.swift` printed `rebuildDPI(of:)` in a column
called `shippedRebuildDPI` and compared it against its own reading of the drawn walk. That
was a real comparison until the wiring landed and would have become a **tautology** after
it: production *is* the drawn walk now, so the column would have equalled `drawnRebuildDPI`
on all 16,987 rows and `policyMoves` would have read `same` everywhere — a tool reporting
"the wiring changed nothing" while measuring itself. §3 in a tool rather than in the shell.
So column 6 is now `dictRebuildDPI`, holding `rebuildDPI(from: largestImage(of:))` — the old
body verbatim — and `rebuildDPI(of:)` moved to a new last column with an assertion beside
it: **production matched the drawn arm on all 16,987 pages**, printed every run whichever way
it goes, and a mismatch exits 1.

**And the anchor is a record that predates the change.** `DRAWN-2026-08-16.tsv` was produced
by the *old* production path, before this dispatch existed. Its `shippedRebuildDPI` column
equals the new sweep's `dictRebuildDPI` on **48 of 48** rows it holds, and its verdict
totals are identical (agree 16,654 · noDictImage 285 · smaller 39 · wider 6 · unreadable 3).
So "45 move" is a diff against a measurement, not this tool agreeing with itself.

**What the 45 pages cost, over 12 of them driven through the shipped pipeline.**
`Tools/score-rebuild-dpi.swift` renders one page at each candidate resolution and counts
what comes out of the **published** file; where the page is born-digital its own embedded
text is the ground truth, so `retained` is an accuracy figure and not a volume figure.
`REBUILD-DPI-WIRING-2026-08-17.tsv` is this run and `REBUILD-DPI-2026-08-17.tsv` is
`Batzell`'s two from the blocker campaign.

```
                      before -> after       retained (of the page's own words)   bytes
AI 2027  p2     354.3 -> 156.0 DPI    95.2% (414/435) -> 93.8% (408/435)   72,359 ->  45,144
AI 2027  p16    354.3 -> 219.8        89.6% (346/386) -> 92.5% (357/386)   68,795 ->  45,786
AI 2027  p47    354.3 -> 299.5        94.8% (423/446) -> 97.8% (436/446)   69,998 ->  61,948
AI 2027  p66    354.3 -> 266.1        96.4% (406/421) -> 96.9% (408/421)  298,908 -> 205,236
AI 2027  p4     354.3 -> 362.9        91.3% (606/664) -> 90.7% (602/664)   88,032 ->  91,770
   five pages                         +16 matched words of 2,352            598,092 -> 449,884  (-24.8%)

Batzell  p9     369.6 -> 147.5        94.5% (361/382) -> 93.5% (357/382)   72,161 ->  41,026
Batzell  p22    369.6 ->  70.6        94.2% (274/291) -> 92.8% (270/291)  407,556 ->  51,302
   two pages                          -8 matched words of 673              479,717 ->  92,328  (-80.8%)

Sherman  p1     419.0 -> 417.4        no truth: 219 -> 182 recognised words  85,328 ->  78,142
Sherman  p2     419.0 -> 416.8        no truth: 414 -> 455                  102,254 ->  99,187
Sherman  p3     419.0 -> 411.2        no truth: 535 -> 537                  101,917 ->  98,078
Sherman  p4     419.0 -> 418.1        no truth: 514 -> 517                   98,025 ->  95,122
Sherman  p5     419.0 -> 413.1        no truth: 523 -> 523                   96,981 ->  99,259
   five pages                          +9 recognised words                  484,505 -> 469,788  (-3.0%)
```

**Read the graded rows and the ungraded ones differently, because they are different
claims.** On the seven pages with an embedded text layer, retention against it is
**+16 words on `AI 2027`'s five and −8 on `Batzell`'s two**, net +8 of 3,025 — flat, with
p16's +11 and p47's +13 the largest single moves and both *upward*. That is the accuracy
figure. `Sherman_1986` is a scan whose text layer is 14 words on a title page, so there is
no truth to grade and the numbers are **volume**: more recognised words may be more type or
more mush, and this instrument cannot tell.

**`Sherman_1986` p1 is where it is worth being careful, and it is the surprise this gate
turned up.** A **0.38%** resolution change — 419.0 to 417.4 DPI, 13 pixels of 3,464 — moves
its recognised word count by **−17%**, 219 to 182. Suspecting the instrument first: the runs
are deterministic (same page, same resolution, same raster) and the whole TSV reproduced, so
this is a real difference between two rasters and not measurement noise. What it is *not* is
evidence of loss: the page's 14-word embedded layer is retained in full at every resolution
tried, and at the **300** fallback it reads **224 words — above both** — so word count is
non-monotone in resolution on that page and 419.0 was not a maximum it fell off. The four
other `Sherman` pages move +41, +2, +3 and 0. **Named rather than smoothed over**: it is the
one row in this gate that a different instrument could reasonably call a regression, and
nothing here settles it.

**The trade, stated as a criterion and not as a win.** Bytes fall on 13 of the 12 pages'
14 measured arms and rise on two (`AI 2027` p4, `Sherman` p5), for **−25%, −81% and −3%** by
document. Accuracy is flat. What makes the change right is not the bytes: it is that the
resolution those 45 pages had was **another page's plate**, and reading the page's own drawn
image is correct whatever the byte count does. The bytes are why nobody has to weigh it.

**Not wired: `pageIsAnImage`.** It asks a different question — is this page a raster — and
feeds `Model`'s text-extraction skip marker, `Flattener.hasDigitalText` and
`Tools/classify-source.swift`, which is D1's corpus gate and therefore R55's territory.
Applying its predicate to both columns of the 16,987-row sweep, wiring the drawn walk there
would flip **exactly 2 pages**: `Batzell` p22 (600 px, under its 900 floor) and `AI 2027` p1
(245 px). Both carry embedded text, so neither reaches `Model`'s marker branch. It is left
because it moves a gate the owner closed on its own arithmetic, **not** because it is
unaffected — CONTRIBUTING §4b's second option, taken deliberately.

**Nine checks, and all four wrong readings of the six lines were put back by hand and
watched.** Each replacement went into a scratch copy of `Sources/` and through an extracted
single-section probe (43 checks, 85 s, its own `UserDefaults` domain — the technique
`c8855f6` left behind):

```
the old dispatch, `from: largestImage(…)`        3 rows red   the 600 px, logo and empty-form pages
`.unreadable` -> `from: nil`                     1 row red    the /Nope page
`.noImage`    -> `from: largestImage(…)`         1 row red    the empty-form page
`.largest`'s width invented (`Int.max`)          3 rows red   the logo page + two C9 rows on born.pdf
the fix as written                               0 rows red   43/43
```

All three are in the catalogue as `logic/C24-rebuild-reads-dictionary`,
`-unreadable-is-nothing` and `-width-invented`, so `mutate.py` keeps saying it. **A scoped
`--only C24-rebuild` run has NOT been spent** — that is a baseline suite plus ~45 min per
verdict — so these are *known* able to fail by the probe and *not yet* confirmed by the
tool; the probe mutates the same file with the same replacement text and runs the same
checks, so the gap is coverage of the rest of the suite, not of these rows.

**A tenth fixture page came with the wiring, and the reason is the trap this register keeps
paying for.** `shared-resources.pdf` page 10 draws a 400 px logo while the shared dictionary
reaches the 3000 px plate: 47 DPI, under `minimumPlausibleScanDPI` *and* under
`minimumScanPixelWidth`, so the policy must **refuse** it. Every one of the nine pages before
it ends in a resolution the policy *trusts*, so on all nine a wiring that handed the policy
the drawn DPI with an invented width answers identically — the row asserting that the drawn
*width* reaches the policy would have been green while asserting nothing. *The first version
of this paragraph went further and said page 10 was the only thing in the suite reaching that
branch; the invented-width mutant then took three rows red, two of them C9 rows on
`born.pdf`, whose 16 px logo reaches it too. What `born.pdf` cannot see is the wiring — its
dictionary holds only that logo, so both walks agree and either dispatch answers 1.9 DPI.*
Corrected from the mutant's own output.

**`score-routing`'s refused rows came back — and there were three documents, not the two
this entry has been saying.** Run both ways, against the reverted `Sources/` and against the
fix:

```
before   AI-2027       SKIP  extraction changed the rebuild resolution: p15 354->363  p43 354->156
         Batzell       SKIP                                            p22 370->71
         Sherman_1986  SKIP    p2 419->417  p3 419->411  p4 419->418  p5 419->413
after    AI-2027       bilevel=3 greyscale=1 colour=0   306 KB/page   bytes=1,255,305  pages=4
         Batzell       bilevel=3 greyscale=1 colour=0   118 KB/page   bytes=  485,618  pages=4
         Sherman_1986  bilevel=4 greyscale=0 colour=0   231 KB/page   bytes=  949,360  pages=4
```

**And read the `before` diagnostics, because they are the entry's own thesis in one line.**
The resolution extraction "drifted" to is *exactly* the drawn answer every time — p43 to
156.0, p22 to 70.6, `Sherman`'s four to 417/411/418/413. Extraction rewrites a page's
`/Resources` to hold what the page references, so an extracted page has always been measured
the way this fix now measures an unextracted one. `score-routing` was not drifting; it was
right, and it was refusing its own correct rows because production disagreed. That is what
A12.2 filed as a tool defect and what the head of this entry says it is not.
*(A12.2's SKIP rows and this entry both name "`Batzell` and `AI 2027`". `Sherman_1986` was a
third and nobody had run it — the sentence was written from the 45-page population, where its
five pages move by ≤1.6 DPI, and `score-routing`'s threshold is 0.5.)*

**Verified by running code**: two independent 16,987-page sweeps, byte-identical, 45 moves
and 0 divergences between production and the drawn arm; the 45 page-for-page equal to
2026-08-16's; column 6 equal to the pre-change record on 48 of 48 rows; 30 pipeline runs
over 10 pages plus the blocker campaign's 3; four hand-built mutants each watched red on
exactly the rows written for them and the fix watched green at 43/43; the
`pageIsAnImage` flip count computed over the sweep rather than eyeballed. **Reasoned, not
run**: nothing in this section — and where a number could not be graded (`Sherman_1986`'s
five) it is labelled `no truth` rather than presented as accuracy.

---

The original entry, which is about the other half, follows unchanged.

A12.2 says three tools extract their sample into a fresh `PDFDocument`, that extraction
"destroys the sharing" of a `/Resources` dictionary, and that `largestImage` therefore
answers differently than in production. The three measured rows reproduce exactly:

```
Batzell - Free Labor   p2   production 3142x4066   tool 2550x3300   1.52x
AI 2027                p2   production 2929x4142   tool 1290x1824   5.16x
Kelly_2014             p1   production 2092x2664   tool 3359x4277   0.39x
```

**But the tool is nearer right than production is.** Every page of `Batzell` points at
`/Resources 438 0 R` — one dictionary, listing four images including a 3142x1408 plate —
and pages 1 and 2 **draw no images at all** (`Do` count 0 in both content streams). They
were still rebuilt at 369.6 DPI rather than the 300 fallback, because `largestImage` walks
`/Resources` and takes the largest thing in it. `Kelly_2014` p1 is the same shape: no `Do`
in any of its eight content streams, and a 2092 px image in a dictionary its three pages
share. This is **C9's harm from the other side** — C9 was a logo *on the page* setting the
page's resolution, and the floor it added cannot see this one because the number comes out
too high rather than too low.

**`qpdf --pages` does not avoid it.** The hand-off's standing advice is to use qpdf when
geometry is the question, because PDFKit normalises the media box. Measured here, qpdf
gives the **identical** wrong answer on all three documents — it is not a PDFKit artefact,
so that remedy does not apply.

**Two repairs were built and both were wrong.** Kept because the second one is the
argument for leaving this open.

1. *Count only XObjects the page draws*, found by scanning the content stream for `Do`.
   130 pages over 4 documents move, which is the right population — and `Batzell` p22 goes
   from 369.6 DPI to **70.6**, because that page's own figure is 600 px wide and
   `minimumScanPixelWidth` reads 600 px as "this image *is* the page, and it is a coarse
   scan — trust it". That constant separates 47 logos of 16–96 px from 37 page-sized scans
   of 1936–2592 px and records that "nothing lands in between"; it was calibrated against
   the document-wide maximum, so a mid-sized figure on a page of type was never in its
   population. **This paragraph then said "rendering a text page at 70 DPI is C9 again",
   and that was reasoned rather than measured. It is false** — see the 2026-08-17 section:
   p22 at 70.6 DPI retains 92.8% of its own words against 94.2% at 369.6. The repair is
   still refused, on the coverage-threshold argument below and not on this page.
2. *Also require the image to be drawn across the sheet.* This needs the CTM, which needs
   `q`/`Q`/`cm` tracked through the content stream — and then it rejected **113 of 114
   pages of `Lyons oral history`**, a real scan, because the unit-square rule is an
   **image** rule. `Lyons` draws `q/Fg Do Q`: a Form XObject with `/BBox [0 0 612 792]` at
   the identity CTM, whose scale is 1.0 and which covers the whole sheet. Gating forms on
   that number rejects every page whose scan sits one level down inside a form, which is
   what scanner drivers routinely produce. Fixed by gating images on coverage and merely
   following forms, after which 246 pages over 16 documents move.

**And then the threshold has nowhere to stand.** Coverage measured over all 16,987 corpus
pages, as the fraction of the media box each drawn image spans:

| coverage | pages |
|---|---|
| draws no XObject at all | 284 |
| 0.00–0.20 | 43 |
| 0.20–0.40 | 53 |
| 0.40–0.50 | 55 |
| 0.50–0.60 | 71 |
| 0.60–0.80 | 153 |
| 0.80–0.95 | 179 |
| **0.95–1.05 — the sheet** | **16,148** |
| >1.05 | 1 |

16,148 pages — 95.1% of all of them, 96.7% of the 16,703 that draw anything — sit at "the
image is the sheet", and the 554 below are spread evenly with **no gap anywhere in
[0, 0.95]**. So any coverage threshold is chosen, not measured, and `FEATURES.md` and R49
both record what that costs: "a plausible-looking gap on the corpus and an overlap the
corpus did not contain", twice. Refused on that basis rather than tuned.

*(The first version of this table said "draws nothing | 3" and summed to 16,706 against a
corpus of 16,987, because the sweep that produced it dropped every page with no drawn
XObject instead of counting it — and this entry's own prose says Batzell has 51 such pages.
Caught by the review of this diff. The "no gap" conclusion is unaffected: the missing
bucket sits outside [0, 0.95] entirely.)*

**One thing this entry claimed and should not have.** An earlier draft said a *second*
defect had been surfaced — that `walkedAt`, the shallowest-depth memo inside
`largestImage`, makes the walk miss images depending on traversal order, because the
filtered prototype reported a **larger** image than the shipped walk on six pages of
`AI 2027` and single pages of `Kazin_1955`, `Intellectual History Newsletter`,
`Zipkin_2000` and `UN-OCred`. **That cause was tested and is wrong.** The review of this
diff reimplemented `largestImage` with no memo at all, same depth cap and recursion,
validated against the nested form in `Lyons`, and diffed it against the shipped walk over
all 16,987 pages: **0 differences, in either direction.** The memo removes no candidate
anywhere in the corpus. The larger answers were the prototype's, not the shipped walk's,
and the observation is recorded here without a cause rather than with a wrong one — which
is the mistake this register has made four times.

**What the tools do instead, and it is the honest half of A12.2.** `score-corpus`,
`score-routing` and `score-text-route` now compare `rebuildDPI` on the original page
against the extracted one and **refuse the row** when they differ, naming the pages and
the numbers:

```
Batzell  SKIP  3p  extraction changed the rebuild resolution, so this row would not
                   describe the shipped pipeline (A12.2, BUGS.md C24):
                   p2 370->300  p28 370->300  p41 370->300
```

That is the T14 pattern: an instrument that knows when it is not measuring what it claims.
It does not make the four `manifest.tsv` rows right — it stops them being produced. **The
rows for the four affected documents should be regenerated once C24 closes**, and until
then they are the old, wrong numbers.

**`BUGS.md` T2's closing line is wrong as written** and A12.2 is right about that:
"`score-routing` was never affected — it calls the real `flatten`" is true of the DPI
*policy* and false of the DPI *value* on these four documents. Corrected in T2.

**What closing this needs**, in order: a discriminator for "this image is the page" that is
not a coverage threshold — the drawn rectangle against the *crop* box rather than the media
box is the obvious next thing to measure, since a scan bled to the trim would read below 1.0
against the sheet; then `minimumScanPixelWidth` recalibrated against the per-page population
rather than the document-wide one; then the `walkedAt` defect above; then a corpus gate run,
because this changes what the default route renders.

*(**Three of those four are now answered or void, 2026-08-16** — see the C24b section
above, and prefer it to this paragraph. The drawn walk needs no discriminator at all,
because restricting to the names the page invokes is a fact about the content stream; the
"recalibration" is one page at the constant's own boundary rather than a population; and
the `walkedAt` defect does not exist — its symptom was area-versus-width, verified on the
document it was observed in. The corpus gate run is the one item that stands.)*

#### The two caps, and the chain they are equal on — 2026-08-23

**The entry stays `FIXED`. Nothing shipped changes behaviour here**: `drawnLargestImage`'s
`case "Form"` still refuses at `s.depth < 3` and `largestImage`'s inner `walk` still refuses
at `depth < 4`. What changes is that the claim *"those are two numbers for one reach"* stops
being a sentence — and, in the course of measuring it, **stops being true unconditionally.**
This section is the queue's `depth-cap` item and the owner's decision of 2026-08-18,
executed, plus one correction to the decision itself.

**Why it was owed.** The mismatch has been "noticed" and nearly changed on a premise that
was wrong about the case it was argued over. The 2026-08-17 decision — *set the drawn cap
to `< 4`* — rested on a latent divergence, *"a page nesting images four levels deep would
get a different answer depending on which path it took"*, retracted the next day on the
control flow: the two walks count in **different frames**. `largestImage` counts resource
*dictionaries*, starting at the page's own at `walk(resources, depth: 0)` and refusing
`depth 4`. `drawnLargestImage` counts *forms entered* — `guard s.depth < 3` at
`Flattener.swift:3653`, then `s.depth += 1` at `:3684` before the form's body is scanned. On
a chain whose forms each carry their own `/Resources`, both therefore see an image listed in
the resources of **three nested forms** and neither sees one a level deeper. There, `< 4` on
the drawn walk would let it enter a fourth form and see an image the dictionary walk cannot
— **creating** the divergence the change was proposed to remove.

⛔ **AND THAT EQUALITY IS A PROPERTY OF THAT CHAIN, NOT OF THE TWO CONSTANTS. On a chain of
BARE forms the two reaches are not equal, the drawn walk is strictly the narrower, and the
retracted premise's shape is real.** A form carrying no `/Resources` of its own resolves its
names against the scope that invoked it. The dictionary walk therefore **does not descend it
and loses nothing** — the image is listed in the invoker's dictionary, which that walk has
already scanned — while the drawn walk **must** follow the `Do` operators wherever they sit
and spends a level on every form it enters, bare or not. So each bare form in a chain narrows
one walk and not the other. **The gap grows with the number of bare forms, so no pair of caps
closes it**, which is a reason to leave both alone rather than a reason to raise either:
`< 4` would only move the boundary to five bare forms.

**Measured, page 14 of the fixture** — four bare levels over an 1800 px image:
`largestImage` answers **1800 px**, `drawnLargestImage` answers **`.noImage`**.
⛔ **And it costs the product, which is the sharper half.** `rebuildDPI(of:)` routes
`.unreadable` to `largestImage` and `.noImage` to `rebuildDPI(from: nil)`, so the 1800 px
answer the dictionary walk is holding is **discarded** and the page rebuilds at
`fallbackRebuildDPI` = 300 instead of its own 211.8 DPI. 1800 px clears both
`minimumScanPixelWidth` (600) and `minimumPlausibleScanDPI` (150), so this is a resolution
the policy would have trusted, not one it would have refused anyway — the check asserts that
second clause rather than leaving it to the reader.

⛔ **Found by the adversarial review of THIS diff, and the draft it reviewed had committed the
unconditional claim to `Flattener`'s own comment** — the same failure mode as the
`make-observations.swift` comment this very commit corrects, in the same commit. Both caps'
comments now carry the scope and point at each other, so neither can be "reconciled" alone.

⚠️ **Latent, not a measured victim** — ⛔ **and "the bound is weak" is RETRACTED for the DRAWN cap
as of 2026-08-26, because a direct one exists: `#### The corpus census, MEASURED` counts the
nesting itself and reads `formDepth` max **1** and `bareDepth` max **0** over the **16,984** pages
of 16,987 it speaks for, so the corpus is THREE levels short of the refusal point rather than
merely observed not to move.** ⛔ **It is NOT retracted for `largestImage`'s `< 4`, and a draft of
this paragraph claimed the census "covers both caps at once" three lines above the sentence that
refutes it.** `formNesting` installs one callback, `"Do"`, so it measures only chains a page
DRAWS; the dictionary walk descends `/Resources` whether the form is drawn or not — which is
exactly the reason given below for `c17b3f3`'s sweep not covering it, and it applies verbatim to
the census. What the census bounds for that cap is its reach **restricted to drawn images**
(`n <= 3` implies `r <= 3`), which is a narrower and true claim. Caught by the adversarial review
of the adopting diff, in `Sources/Flattener.swift`'s own comment as well as here. What the
paragraph used to rest on, kept as the record of why a
sweep could not answer this: `c17b3f3` moved the drawn cap from `< 4` to `< 3` and its
16,987-page sweep was byte-identical, which no page with exactly four bare levels could have
been. That was **one cap over one corpus**, and it said nothing about `largestImage`'s `< 4`,
which has **still never been moved over the corpus at all** — nor could that sweep stand in for
it, since the dictionary walk reads `/Resources` whether or not the form is drawn. So these rows
**pin the behaviour rather than bless it**, and the decision of whether to fix it was the
queue's `bare-form-reach`, **closed `WONTFIX` 2026-08-26**. It is not reopened as a defect:
nothing measured loses anything, and the page a reader would have to construct to be harmed does
not exist in 16,987 of them.

⛔ **The corpus can never be the instrument for the equal half either.** This entry's own
comment records `< 4` and `< 3` producing byte-identical sweeps, so the verification the
2026-08-17 decision prescribed for itself was **guaranteed to pass whatever the caps said**.
A fixture is the only thing that can see any of this, which is `A1.3`'s precedent in this
same suite: it already carries *"both outline walks truncate at the same depth"* because that
mirror-walk pair really did truncate at different depths. **Equal reach recorded only in
prose is what let this be re-litigated into a wrong decision once already.**

**The fixture: pages 11-14 of `shared-resources.pdf`.** Pages 11-13 are ONE chain of four
nested resource-carrying forms — page → `/FA` → `/FB` → `/FC` → `/FD`, where `FC` draws a
1200 px image and `FD` a 2400 px one — **entered at three different levels by three pages**.
That is what makes each refusal attributable to the cap rather than to the fixture: *the
object refused on one page is found on the next, unchanged*. Page 14 is a separate chain of
four **bare** forms over an 1800 px image, and is the counterexample above.

| page | enters at | third level holds | fourth level holds | dict walk | drawn walk |
|---|---|---|---|---|---|
| 11 | `/FA` | `FC`'s 1200 px | `FD`'s 2400 px | **1200** | **1200** |
| 12 | `/FB` | `FD`'s 2400 px | — | **2400** (wins on area) | **2400** |
| 13 | `/FW`, a wrapper above `/FA` | — | `FC`'s 1200 px | **nil** | **`.noImage`** |
| 14 | `/FP1`, all four bare | — | `/ImE`'s 1800 px | **1800** | **`.noImage`** |

Page 13's fourth-level cell is the one to read twice: the image refused there is the *same
object page 11 finds*, one level further from the page, which is what makes its `nil` the
cap's and not an empty chain's. Page 14's is the same image its own dictionary walk returns.

**Nine checks run on that**, and three design points in them are worth more than the rows.
(1) **Three of the nine name an absolute width** — the two 1200 rows and the 2400 row —
because agreement alone is satisfied by both caps moving together: under a joint +1 the
agreement row stays **green** and those three go red. That is the whole reason the widths are
there, and it is simulated rather than asserted. (2) **The agreement row spans pages 11-13
and deliberately NOT page 14**, because the invariant is false there; the scope is the
finding. (3) **The premise row gates nothing — it reports.** What it buys is the non-vacuity
of the two *absence* rows (pages 13 and 14), where without it `.noImage` could mean "nothing
drawn" rather than "too deep to reach"; the rows asserting 1200 and 2400 could not be
satisfied by an early return at all. ⚠️ It is **not** a reachability guard, and saying so is
this register's own retraction of exactly that overclaim for `C28` one commit earlier.
`logic/C24b-no-image-is-not-unknown` is why the shape is worth stating at all: page **8** of
this fixture is the page that kills it and the seven before it could not.

⚠️ **One reading of shipped behaviour is pinned without being endorsed.** Pages 13 and 14
both draw an XObject and `drawnLargestImage` returns `.noImage` rather than `.unreadable`,
because the depth guard returns without setting the flag. On page 13 it costs nothing —
`largestImage` is `nil` there too, so both arms of `rebuildDPI` reach the fallback either way
— and page 14 is precisely where it stops costing nothing. That is why the two are separate
rows rather than one.

**The sabotage, run 2026-08-23 — WATCHED FAILING, and four of the seven rows it could reach
go red.** A
binary one token from the shipped one (`s.depth < 3` → `< 4`, i.e.
`logic/C24-drawn-cap-reaches-further` applied by hand) was built and run to the end of this
block, and it reports:

```
FAIL …and the drawn walk answers the same width from the same page
     — largest(dpi: 282.35, pixelWidth: 2400)
FAIL C24 — both walks reach exactly as far as each other on all three
     — largest(282.35, 2400) / largest(282.35, 2400) / largest(141.18, 1200)
FAIL C24 — a page whose every image is four forms down reads as no image
     — nil / largest(dpi: 141.18, pixelWidth: 1200)
FAIL …and it rebuilds at the fallback rather than at a resolution nobody read — 141.2
                                             (375 checks reached, 371 ok, 4 FAIL)
```

Read the third line: on page 13 the sabotaged drawn walk reaches `FC`'s 1200 px while
`largestImage` still answers `nil` — **the two walks disagreeing, printed**, which is the
outcome the fixture exists to make visible. And the fourth is the divergence reaching the
product: 141.2 DPI where the shipped build takes the 300 fallback.
**The three rows that stay green are the three that should**: the premise, the
`largestImage`-only row (the dictionary cap was not touched), and the negative control, where
2400 is the answer at both caps. ⚠️ **Scope of this run, stated exactly.** It was built before
page 14 existed, so it witnesses the pages 11-13 rows and **not** page 14's two; under the
same sabotage those would also go red (the drawn walk would enter the fourth bare form and
return 1800), but that is **reasoned, not watched**. And the second mutant,
`C24-dictionary-cap-reaches-further`, was **not** built here — the correctness review of this
diff simulated it against the code and puts three rows red, `largestImage`-side, which is
consistent with the arithmetic above but is not a run.

**Two mutants, catalogue 101 → 103**, one per cap and a matched set:
`logic/C24-drawn-cap-reaches-further` (`s.depth < 3` → `< 4`) and
`logic/C24-dictionary-cap-reaches-further` (`depth < 4` → `< 5`). ✅ Both `find` strings were
checked **unique** in `Sources/Flattener.swift` by hand, so neither will be reported
NOT-APPLIED — `mutate.py --self-test` never touches `OPERATORS`, so nothing automated asserts
that. ✅ **BOTH ARE RUN AND `killed` AS OF 2026-08-25 — read `#### Both caps RUN through
mutate.py` below**, which supersedes this paragraph's ⚠️: they are graded rows in
`mutation-log.tsv` (227 s / 6 objecting checks and 244 s / 3), the drawn cap's page-14 pair is
watched rather than reasoned, and the dictionary cap — never built at all when this was
written — reddens exactly the three rows that diff's review simulated. ⚠️ The "~45 min a
mutant" this paragraph budgeted was clamped-era arithmetic; the pair cost **705 s end to end**,
baseline included.

⛔ **GROWING THE FIXTURE BROKE A CHECK ABOUT SOMETHING ELSE, AND THE SUITE IS WHAT CAUGHT IT
— after two adversarial reviews of the same diff did not.** The `rebuildDPIOverride` block
200 lines below asserted `flattened.count == 10`, a literal copy of this fixture's length
kept nowhere near the fixture, so pages 11-14 turned *"`flatten` renders every overridden
page at that resolution"* red: `[2550, 765, 765, …]`, fourteen entries where it wanted ten.
The row's actual subject — every page but the declined one moving to the override, and that
one staying on the 300 fallback — was **satisfied throughout**; only the count was wrong. It
reads `sd.pageCount` now. ⚠️ Worth knowing *why* both reviews missed it: both were aimed at
the new block, and one was told explicitly not to re-check fixture arithmetic. **A fixture
shared by unrelated checks is a coupling that neither a diff-scoped review nor a
fixture-scoped one sees.** The length was the only such literal in the block — swept.

**The sibling sweep.** ⛔ *Who else recurses with a bound, and who else carries a copy of
either walk?* (a) **There is no third PDF-content walk**: `CGPDFScannerCreate`,
`CGPDFContentStreamCreate` and `CGPDFDictionaryGetDictionary` appear in
`Sources/Flattener.swift` and nowhere else in the tree. (b) **No tool carries a copy** —
`Tools/score-drawn-images.swift` calls `Flattener.drawsAnyXObject`, `.largestImage`,
`.drawnLargestImage` and `.rebuildDPI(from:)` directly, which is why nothing there goes out
of step, and it is the T15 shape this project pays for when a tool reimplements instead.
(c) **The one other bounded recursion in `Sources/` is this section's own precedent** —
`SearchableWriter.swift:412` and `:581`, both `guard depth < maximumOutlineDepth`, already
pinned by the `A1.3` check. Nothing else is affected.

**The comments.** `drawnLargestImage`'s `case "Form"` comment used to justify `< 3` by
*instrument symmetry* — the drawn-versus-dictionary sweep isolating one variable — and to
say that if the walk were ever wired into `rebuildDPI` the cap *"wants re-measuring then"*.
`c17b3f3` did that wiring on 2026-08-17 and revisited neither. It now states the
frame-of-reference difference first, because that is what makes two numbers legible and stops
another reader "noticing" the mismatch, gives the honest production reason — **three levels
is what shipped** — and carries the bare-form exception beside it. `largestImage`'s guard
gained the reciprocal note, including that it is the **wider** of the two and that raising it
widens rather than equalises.
⚠️ **This entry's own copy of the expired justification is left standing on purpose.** The
2026-08-16 bullet in `### What the review of this diff found` still reads *"The two walks
disagreed about how deep to look, which is a confound in the one instrument built to isolate
a single variable"*, and `git grep -n depth BUGS.md` reaches it before this section. It is
a true record of what that review found and why `< 3` was chosen **then**; it is not the
current reason, and this sentence is the pointer that says so rather than an edit to history.

#### Both caps RUN through mutate.py — 2026-08-25

**The entry stays `FIXED` and nothing shipped moves.** What changes is that the two mutants
catalogued with the section above stop being *catalogued* and become *graded*: the sabotage
binary recorded there is no longer the evidence, and the paragraph that said so has been
rewritten in place rather than left to be superseded from here. Both are `killed`:

| mutant | seconds | mutant suite | objecting checks |
|---|---|---|---|
| `logic/C24-drawn-cap-reaches-further` (`s.depth < 3` → `< 4`) | **227** | `1241/1247` | **6** |
| `logic/C24-dictionary-cap-reaches-further` (`depth < 4` → `< 5`) | **244** | `1244/1247` | **3** |

Baseline **1,247 green**; **705 s end to end** for the baseline and both mutants, wrapped in
`test-lock.sh run` so the row is in `$STATE/suite-timings.tsv` (`mutants 705 0 2.77`), which
leaves ~234 s for the baseline and the tool's own restore-and-rebuild overhead. Neither is
`NOT-APPLIED`, so both `find` strings are still unique — the hand check recorded above held.
`coverage: 76 → 78 of 103`; entries with no row at all **27 → 25**; survivors still **2**.

⛔ **THE KILL SETS WERE PREDICTED BY NAME, IN ORDER, AND IN COUNT BEFORE THE RUN STARTED**, from
the fixture's object graph and from reading `rebuildDPI(of:)` — six rows for the drawn cap and
three for the dictionary cap, with both suite tallies. The prediction is
`$STATE/PREDICTION-2026-08-24-capmutants.md` — ⚠️ **outside the tree, so this claim is not
reproducible from any commit**, the same standing caveat this file carries for
`C30-FORK-2026-08-22.tsv` and `GUTTER-CENSUS-2026-08-20.tsv`; what a reader can check is the
file's mtime, 23:50:29, against a run that started ≈23:50:34. It reproduced exactly, including
the two derived DPI values (**141.18** on page 13
and **211.76** on page 14) and the observation that page 14's failing row prints
`211.8 vs 211.8` — both of its operands equal, because the row fails on its *first* clause.
⚠️ A prediction that lands is worth less than one that does not, and this section's yield is
the two paragraphs below rather than the confirmation.

**What is genuinely new against the 2026-08-23 sabotage binary**, which was built before page
14 existed and reached seven rows of nine:

* **Page 14's two rows are now watched rather than reasoned.** That section says of them
  *"under the same sabotage those would also go red… but that is reasoned, not watched"*. They
  do: at `s.depth < 4` the drawn walk enters the fourth **bare** form, resolves `/ImE` in the
  invoker's scope and answers `.largest(dpi: 211.76, pixelWidth: 1800)` where it answered
  `.noImage`, and `rebuildDPI(of:)` goes 300 → **211.8**. So the bare-form finding's own
  mechanism — a bare form costs the drawn walk a level — is confirmed from the opposite
  direction: give that walk the level back and the divergence closes on this chain.
* **The dictionary mutant had never been built at all.** Its rows were *simulated* by that
  diff's correctness review (*"puts three rows red, `largestImage`-side… but is not a run"*).
  The **count** is confirmed at three; ⚠️ that record never named which three, so "the same
  three" is not a claim the tree can check.

**The asymmetry, stated from the two logs rather than from the call graph.** Of the nine rows:
**four** are red under the drawn cap alone (the page-11 drawn-width row, page 13's `rebuildDPI`
row, and page 14's two), **one** under the dictionary cap alone (the page-11 dictionary-width
row), **two** under both (the agreement row and page 13's absence row), and **two** under
neither. ⛔ **A first draft of this section said "the three rows only the drawn cap reddens are
the three that reach `rebuildDPI`", and the review of the diff refuted it by counting: it is
FOUR rows, and only TWO of the nine reach `rebuildDPI` at all** (`Tests/main.swift:4812` and
`:4858`). The other two of the four are the page-11 width row — simply the drawn-side mirror of
the dictionary-side one — and page 14's part-company row, which stays green under the
dictionary cap for a reason that has nothing to do with the seam: the bare chain resolves
`/ImE` at `depth 0`, so that walk never wanted a deeper cap.

⛔ **AND THE SHARPEST THING THE RUN FOUND IS THAT THE THREE IS A COVERAGE BOUNDARY, NOT A
PRODUCT FACT — `largestImage` HAS A SECOND PRODUCTION CONSUMER WITH NO DRAWN-WALK GATE, AND IT
FLIPS ON THIS FIXTURE.** The draft argued that a loosened dictionary cap cannot reach the
product, because `rebuildDPI(of:)` routes `.noImage` to `rebuildDPI(from: nil)` and only
`.unreadable` to `largestImage` (`Flattener.swift:3280-3282`) — true of that seam, and it is
**not the only one**. `Flattener.pageIsAnImage` (`Flattener.swift:304-307`) reads `largestImage`
directly, with no drawn walk in front of it, and is called from `Model.swift:886` — the
text-extraction skip marker, invariant-1 territory — and from `Flattener.hasDigitalText`
(`:386`), which is **C29's own routing vote**. On page 13 the dictionary mutant takes
`largestImage` from `nil` to `(dpi: 141.18, pixelWidth: 1200)`, which clears every one of
`pageIsAnImage`'s bars, so that predicate goes **false → true** on a fixture page — and
**nothing in the suite pins `pageIsAnImage` on pages 11-14**, which is the only reason the kill
set is three rather than four. ⚠️ Deliberately **not** fixed in this commit: adding that row
would change the objecting-check count the two log rows record without a re-run, which is the
staleness this file charges for elsewhere. It is carried as a ⚠️ on the queue's
`bare-form-reach`, whose subject — `rebuildDPI` discarding a resolution the dictionary walk
read — is the same discard from the other side.
✅ **CLOSED 2026-08-26 and the kill set IS four — read `#### The coverage boundary, CLOSED`
below.** The row exists, both mutants were re-run, and the sibling sweep the close paid for
narrows this paragraph: the third reader of `largestImage`, `nativeDPI(of:)`, is also ungated by
the drawn walk but has **no production caller**, so `pageIsAnImage` is the whole of the
exposure and one check is the whole of the coverage.

⚠️ **TWO of the nine rows are red under neither mutant, and that was said in advance rather
than explained afterwards.** The 2026-08-24 rule — the test is not "could this row move" but
"does the mutant change this row's input" — puts both beyond reach of a *loosening* cap mutant:
the premise row reads `drawsAnyXObject`, which has its own scanner and no depth guard at all
(`Flattener.swift:3364-3391`), and the page-12 negative control already reaches `/FD` at the
third level with **nothing below it**, so a fourth level admits no object on that page and both
walks return the same 2400 either way. Neither is a gap: the premise reports (it buys the
absence rows their non-vacuity) and page 12 is the control whose staying green is what makes
page 11's refusal the cap's. ⛔ **A draft added "a *narrowing* mutant would redden both; none is
catalogued", and the review refuted both halves**: `logic/C24b-form-not-followed`
(the tuple with id `C24b-form-not-followed`) narrows this very `find` string to `s.depth < 0` and is `killed` at
`mutation-log.tsv:75`, and the premise row cannot be reddened by a cap mutant in **either**
direction — `drawsAnyXObject` has no depth guard, which is this paragraph's own stated reason
one clause earlier. Page 12's control is the one a narrowing mutant reaches.

⛔ **The design point about the three absolute-width rows is NOT graded by this run — and one
third of it is REFUTED.** The claim is about a **joint** +1 — *"under a joint +1 the agreement
row stays green and those three go red"* — and `mutate.py` applies one mutant at a time with a
restore between, so nothing here exercises the joint case. What the run does establish is that
**page 12's 2400 row is green under each cap separately**, and since the two mutants touch
disjoint functions and that row ANDs one answer from each, it is green under a joint +1 too:
page 12 has nothing below `/FD` for a fourth level to admit, so **two of the three widths would
go red and the third would not.** The `Tests/main.swift` comment is corrected to say two.
⚠️ Under each cap **alone** the agreement row is itself red, on both pages 11 and 13 — stronger
for attribution, and a different sentence from the joint claim.

⛔ **USING THE INSTRUMENT FOUND A ONE-SIDED FAILURE DETAIL ON THE ROW THAT COMPARES TWO
THINGS.** `C24 — both walks reach exactly as far as each other on all three` printed the
**drawn** walk's three answers alone, so the dictionary mutant's `FAIL` line read
`largest(dpi: 141.1764705882353, pixelWidth: 1200) / largest(dpi: 282.3529411764706, pixelWidth: 2400) / noImage`
— **identical to the string a build with the shipped cap would have produced**, because the
walk that moved was the one the detail did not name. (Not "what the passing build prints":
`check()` prints a detail only on failure, so the passing build prints no detail at all — a
distinction the first draft of this paragraph lost while being *about* byte-identity.) A reader
handed that line learns that the row failed and nothing about why. It now prints
`p11 dict=… drawn=…` for each of the three, watched failing by hand under the same mutant
before the wording was kept: `/tmp` is not durable, so the line read was
`FAIL … — p11 dict=2400 drawn=largest(dpi: 141.1764705882353, pixelWidth: 1200) / p12 dict=2400
drawn=largest(dpi: 282.3529411764706, pixelWidth: 2400) / p13 dict=1200 drawn=noImage`, in a
suite that ended `1244/1247` with those three FAILs and no others. A `--rerun` was rejected: it
would append a duplicate verdict row and move the estimator's window for a diagnostic change.
⚠️ **So the two rows this run appended to `mutation-log.tsv` carry the PRE-REPAIR detail for
that one name**, and a re-run from this tree will differ on it. Nothing else in either row
moves; it is recorded here because the log is this project's durable copy of a `FAIL` line and
the alternative was a duplicate row. ✅ **A re-run happened on 2026-08-26 — forced by a changed
check count rather than by this — and the prediction held: the two newer rows carry the repaired
form. The duplicate rows this paragraph was avoiding now exist, and the later pair is current.**
⚠️ Sibling sweep: this block's other eight rows each print the quantity their own condition
reads, and the two absence rows already print both walks. The shape is worth watching for
elsewhere — a detail string that names one side of an equality — but nothing else in this
MARK block has it.

⚠️ **The startup estimate, third data point and a correction to a published sequence.** It
printed *"roughly 12-174 minutes… Budget the 174"* for a **705 s** run: the LOW end came within
5% (738 s floor against 705 s measured, the run beating it because all three suites ran under
the window's cheapest row) and the high end was **14.8x** high, the same direction and
magnitude as 2026-08-24's 14.5x. ⚠️ **The usable floor is not evidence that the window has
healed** — it was printed from the *pre-run* window `[3014, 3475, 3407, 3415, 246]`, which held
exactly one post-clamp row, and that row happened to be the `min`. A draft credited it to
"three post-clamp rows now in the window", which is a window that has produced no reading yet.
⛔ **And the healing sequence published that day — *"over the next FOUR scoped runs the high end
reads 116 / 114 / 114 / 8"* — assumed one mutant per run: a two-mutant run ages TWO rows out of
the five-row window at once, so this run consumed two of its four steps and the drop now lands
on the THIRD run from here rather than the fourth.** `ESTIMATE_SAMPLE` is 5 **rows**, not 5
runs; the window is now `[3407, 3415, 246, 227, 244]`, the next 1-mutant run prints ~`8-114`,
and the high end reaches single digits once **two more mutant rows** exist — ⛔ **corrected in
place 2026-08-26: two arrived, they are dearer than every row they joined, and the printed high
is `10` over an underlying 9.73 min; see `#### The coverage boundary, CLOSED`** — however they are
distributed — one more two-mutant run would do it alone. ⚠️ A first draft called the published
sequence "one run short", which is the wrong direction: it was right for the runs it assumed,
and this run made the drop arrive *earlier*. ⚠️ **Five copies of the four-run form survive this
commit** (`CLAUDE.md:238`, `QUEUE.md`'s cost table and its C28 (a) box, `mutate.py:76-77` and
`ops/autonomous/README.md`) — a draft claimed they had all been corrected in two files, and
they are corrected in place instead, because a false sibling-sweep claim is the shape this
register logs against itself most often.

⚠️ **Scope, stated exactly.** Two mutants of one pair on one machine, one run each; `killed`
is this suite's verdict and not a claim that no other suite would let them through. Nothing in
`Sources/` or `Helper/` changed — the only code edit is the failure-detail string above, which
no check asserts on.

#### The coverage boundary, CLOSED — 2026-08-26

**The row the section above named and deliberately did not write now exists, and the dictionary
cap's kill set is 3 → 4.** One check in `Tests/main.swift`, at the end of the bare-form block:

```
C24 — pageIsAnImage answers off the dictionary walk on all four
    [p11, p12, p13, p14].map(Flattener.pageIsAnImage) == [true, true, false, true]
```

No executable line in `Sources/` or `Helper/` moved; `nativeDPI`'s doc comment gained one sentence,
for the reason two paragraphs below. Baseline **1,343 → 1,344 green**.

| mutant | seconds | mutant suite | objecting checks | against 2026-08-25 |
|---|---|---|---|---|
| `logic/C24-drawn-cap-reaches-further` | **292** | `1338/1344` | **6** | count unchanged (227 s → 292 s) |
| `logic/C24-dictionary-cap-reaches-further` | **289** | `1340/1344` | **4** | **3 → 4** (244 s → 289 s) |

⚠️ **The block is now TEN rows and every section dated before today counts nine.** The split those
sections give becomes **four** red under the drawn cap alone, **two** under the dictionary cap alone
(the page-11 dictionary-width row and this one), **two** under both, **two** under neither — so
*"four rows against one"*, wherever it appears, is **four against two** from 2026-08-26. The
occurrences inside dated narrative were left as that run's record rather than rewritten; the one
statement about the block **as it stands**, `Tests/main.swift`'s "three of the ten rows name an
absolute width", was corrected in place.

⛔ **The new row is WATCHED FAILING, and by the mutant the boundary was found with rather than
by a hand sabotage.** Its `FAIL` line reads
`p11=true dict=2400 p12=true dict=2400 p13=true dict=1200 p14=true dict=1800` — **p13 is the
only column that moves**, `false` → `true`, which is the flip `#### Both caps RUN through
mutate.py` measured with no check objecting. **875 s end to end**, wrapped in `test-lock.sh run`
(`mutate-capreach 875 0 4.92`), `--rerun` because the count changed.

⛔ **Both counts were PREDICTED BY NAME AND IN COUNT BEFORE THE RUN, INCLUDING THE ONE THAT DOES
NOT MOVE**, and the negative is the more useful half: `pageIsAnImage` never calls
`drawnLargestImage`, so the drawn cap cannot reach it and its six had to stay six. It did.
⚠️ The prediction was written to `/tmp` — outside the tree, the same standing caveat this
section already carries for its predecessor — so what a reader can check is the table.

⛔ **AND THE COLUMN THAT IS WATCHED IS ENTAILED BY A ROW THAT WAS ALREADY THERE — say this before
quoting the 3 → 4.** `pageIsAnImage` opens `guard let largest = largestImage(of: page) else
{ return false }`, and `C24 — a page whose every image is four forms down reads as no image`
already pins `largestImage(of: allTooDeep) == nil`. So p13's `false` is a strict consequence of
an existing assertion, and the two rows red **beside each other** in the same kill set: the
fourth objection is a second objection to a fact already objected to. **What the row buys that
nothing else does is p14 and the two DPI bars — and neither is watched.** The 3 → 4 is real
bookkeeping and is not four independent facts.

⚠️ **Only p13 is MEASURED as able to fail; p11, p12 and p14 are pinned and reasoned.** Under the
dictionary mutant p11's *input* moves (dict 1200 → 2400) and its answer does not — both widths
clear all **three** of `pageIsAnImage`'s bars (`pixelWidth >= 900`, `dpi >= 72`, `dpi <= 1400`) —
which is the 2026-08-24 rule read from the other side: a mutant that changes a row's input does
not thereby make that column able to fail. What p14 buys is the shape nothing else catches:
putting the drawn walk in front of `pageIsAnImage`, one of the two fix shapes the queue's
`bare-form-reach` prices, would red p14 alone (`true` → `false`), and **no catalogued mutant asks
that question**. Named rather than credited, the way `shapeHeightHigh`'s greens were.

⛔ **The finding worth more than the row is the sibling sweep, and it BOUNDS the exposure.**
`Sources/` reads `largestImage` in exactly three places (CONTRIBUTING §4b; `Flattener.swift`
`:305`, `:3479`, `:3542`). `rebuildDPI(of:)` reads it only from the `.unreadable` arm, i.e.
behind the drawn walk, which is correct. **`nativeDPI(of:)` reads it with no drawn walk in front
of it and has NO PRODUCTION CALLER AT ALL** — `Tests/main.swift` and two tool comments are the
whole of it — so the "second consumer" the section above found is the *only* production
predicate with this exposure, and one row is the whole of the coverage **on this fixture**
(`pageIsAnImage` is pinned in seven other places in the suite, on other documents).
⛔ **Bounds, not narrows** — it went from "at least one, total unknown" to "exactly one", and
nothing got smaller; a draft of this section wrote "narrows" and the review of this diff refused
it — ⚠️ **and it is a grep snapshot with nothing keeping it true**, so `nativeDPI`'s doc comment now says in place that it has no production
caller and that adding one re-opens this. That clause is the only edit in `Sources/`, and it is
the durable half of this close: the row pins `pageIsAnImage`, and nothing pins the *count* of
ungated readers.

✅ **It also discharges the ⚠️ this section left about its own log rows.** Those two rows carried
the **pre-repair** one-sided detail for `both walks reach exactly as far as each other on all
three`, because the repair landed in the same commit as the run that recorded them. The
`--rerun` re-recorded both names and the new rows carry the repaired `p11 dict=… drawn=…` form:
under the dictionary mutant, `p11 dict=2400 drawn=largest(dpi: 141.1764705882353, pixelWidth:
1200) / … / p13 dict=1200 drawn=noImage`, which a shipped build could not print. ⚠️ The log now
holds **two rows per name**; the later pair is current, and `coverage: 78 of 103` does not move.

✅ **THE WINDOW IS CLEAR FOR THE FIRST TIME — `[246, 227, 244, 292, 289]`, no clamped-era row left
— AND THE PUBLISHED HEALING FORECAST IS RIGHT IN SUBSTANCE AND WRONG ONLY IN ITS NUMBER.** That
section forecast *"the high end reaches single digits once two more mutant rows exist"*. Two now
do, and a 1-mutant run **prints `8-10`** — but the underlying high is **9.73 min**, which is
single digits, shown as `10` only by `startup_line`'s `:.0f`. ⛔ **So do not write "REFUTED": what
is wrong is the forecast's arithmetic, not its claim.** It was computed off the *surviving* rows'
max of 246 (→ 8.2 min) and the two rows that arrived are **dearer than every row they joined**
(292 and 289 against 227, 244 and 246), so the real figure is 1.5 min higher and crosses the
rounding boundary. A prediction about a window cannot be made from the half of it that already
exists. ⚠️ Measured by driving `estimate_minutes` over the log from this tree, not by a run.
⛔ **AND THE 11-171 LINE IS NOT A READING OF THAT CLEAR WINDOW — a draft of this section said it
was, in three files, and the review of this diff refuted it from the line's own text.** The
startup line is printed *before* the run, and its span reads `(227-3415 s each)`: it came from
`[3407, 3415, 246, 227, 244]`, two clamped rows still in. So this is the **fourth** reading of
the estimator and the last of the clamped era, **11.7x** high (171 min against a measured 875 s
= 14.6 min) — third in that direction after 14.5x and 14.8x. ⛔ **The one arithmetic available on
the cleared window points the OTHER way**: re-estimating this same run from
`[246, 227, 244, 292, 289]` gives **11-15 min** against 14.58 measured, a high end within
**0.2%**. **No live reading has yet been taken from a clear window, and it is owed.**
⚠️ **Nor is "the first time the low end has been wrong" true, and a draft said that too**:
2026-08-24 printed a *floor* of 100 min over a 479 s (7.98 min) run — **12.5x** high — which is
worse than anything here. What is new is the opposite: `11-171` is the first printed range that
**contains** the measurement at all (100-116 and 12-174 both sat entirely above their runs).
⚠️ Finally, **292 s is this day's suite and not this row's cost**, which a draft left as "not
established": `$STATE/suite-timings.tsv` has seven clean full-suite runs on 2026-08-26 at
**281-300 s** — including `pre-commit 2512 300` twenty-four minutes before this run and before
this check existed — against 2026-08-25's 227-246 s at 1,247 checks. Suite growth accounts for
it.

#### The corpus census, MEASURED — the bare-form shape is on 0 of 16,987 pages, and the corpus is three form levels short of being able to hold it — 2026-08-26

The queue's `bare-form-reach` asked for **a measurement and not a fix**, and this is it.
`Tools/score-drawn-images.swift` gained a form-nesting census — three appended columns,
`formDepth` / `bareDepth` / `nestVerdict` — and it ran over all **233 documents and 16,987
pages** in **23 s** (metadata speed; no rendering, no OCR). `DRAWN-CENSUS-2026-08-26.tsv`.

**The answer, and it is zero on both terms rather than one:**

| column | corpus |
|---|---|
| `formDepth` (forms entered along the deepest chain) | **0 on 16,268 pages, 1 on 716.** Nothing deeper on any page the census speaks for. |
| `bareDepth` (bare forms along the chain with the most) | **0 on all 16,984 measured pages.** Not one bare form in the corpus. |
| `nestVerdict` | `flat` 16,268 · `withinCap` 716 · `partial` 3 · **`diverges` 0 · `capRefused` 0 · `bothBlind` 0** |

⚠️ **The denominator of the two maxima is 16,984, not 16,987**, because the sweep excludes
`partial` rows from both histograms and the maxima on those 3 pages are **floors** by the tool's
own definition. Say "16,984 measured" and not "all 16,987": a draft said the latter in this
section's opening line and in **both** `Sources/Flattener.swift` comments, all three corrected on
the adoption. The harm claim is still safe on those 3 — they read `drawnKind=unreadable`, which
`rebuildDPI` already routes to `largestImage` — but the *structural* claim is not.

⛔ **Quote the two-term form, not "no page has the shape".** The divergence needs `n >= 4`
**and** `n - b <= 3`, so it needs both a chain of four forms and at least one bare form in it.
The corpus's maxima are **1** and **0**. So it is not one measurement away from the shape: the
deepest page in 16,987 is **three form levels short** of the drawn cap's refusal point — the
guard refuses the FOURTH form entered and the corpus maximum is **one** — and a divergence needs
those same three levels *plus* a bare form, on a term whose corpus maximum is zero. ⚠️ **A draft
of this section said "two levels short" in four files and it was wrong**: the third form in a
chain is entered (`s.depth` is 2 at that point, and `2 < 3`), so the refusal needs `formDepth 4`
and 4 − 1 = 3. Caught by re-deriving it from the guard rather than from the sentence. That is a
stronger bound than
the one this entry has been carrying, which was `c17b3f3`'s byte-identical sweep of the
**drawn** cap — one cap, and silent about `largestImage`'s `< 4`, which has still never been
moved over the corpus and now does not need to be.

**THE DECISION: `WONTFIX`, and `bare-form-reach` closes on this number.** Two reasons, and
the second is the one that decides it:

1. The shape is absent from the corpus on both of its terms, with the margins above.
2. **No CORPUS page exercises the one-line fix, and `.unreadable` is load-bearing elsewhere.**
   The queue box priced it as returning `.unreadable` rather than `.noImage` when the depth
   guard is what stopped the walk, which routes the page to `largestImage` — which already has
   the answer. But `formDepth` is 1 at most, so **the drawn walk's `s.depth < 3` guard never
   fires on any corpus page**: the fix would change nothing over 16,987 pages, so this corpus
   offers no evidence that it helps a real document. And `.unreadable` is load-bearing elsewhere
   (T14's "an instrument that knows when it is not measuring"), so overloading it to mean "the
   cap stopped me" trades a measured nothing for an unmeasured something.

   ⛔ **THE FIRST DRAFT OF THIS REASON OVERSTATED IT IN ALL FOUR FILES AND THE REVIEW OF THE
   ADOPTING DIFF REFUTED IT TWICE — the correction is worth more than the reason.** (i) It said
   *"there is no page on which to measure that it helps and none on which to measure that it
   harms"*, and the second half is **false**: `shared-resources.pdf` page 14 IS the shape, is in
   the tree, and the suite already pins today's answer on it — so a change here **could** be
   gated, on the fixture. The true claim is "no *corpus* page", i.e. no evidence about real
   documents. (ii) Worse, the harm half **runs the other way**: the guard fires iff
   `formDepth >= 4`, which is 0 corpus pages, so corpus harm is *provably empty* rather than
   merely unmeasured — an argument **for** the change, not against it. (iii) And "the
   seam-with-no-caller shape C28 rejected" is **misapplied**: what C28 rejected was a field with
   **no caller at all**; this guard has a caller and simply is not exercised by this corpus.
   Unexercised is not dead. So reason 1 plus `.unreadable`'s other duty carries the decision on
   its own, and reason 2 no longer claims to be decisive.

⚠️ **What that does NOT say.** The shape is constructible and PDF-legal — `shared-resources.pdf`
page 14 is it, and the suite pins today's answer there (1800 px read and discarded, the page
rebuilding at the 300 fallback), so that pin stays as the record of what a file outside this
corpus would get. It is 233 documents and one corpus. And this measures **structure**: it says
no page has the nesting, not that no page loses resolution for some other reason.

##### The instrument, and what pins it

⚠️ **The census is a SECOND implementation of `drawnLargestImage`'s traversal, not a call into
it** — neither shipped walk exposes its depths, and adding an accessor to `Flattener` for an
instrument is a seam with no caller. Same `CGPDFOperatorTable`, same
`formResources ?? inherited ?? streamDict` scope rule, same `/Width` plausibility guards; it
differs in exactly two ways, both the point — no `depth < 3`, and it counts instead of
measuring a width. The memo is keyed on `(stream, scope, depth, bare)` rather than production's
`(stream, scope)`, because this walk wants **maxima** where production wants a first answer: a
stream already scanned at depth 2 must still be scanned when a longer path arrives at depth 3,
or `formDepth` understates itself. Bounded all the same, at `censusDepthBound²` visits per pair.
✅ **And the maxima cannot be understated by the memo, read on the adoption**: both `max`
assignments happen *before* the `seen.insert` guard, so a memo-skipped visit still records its own
depth and bare count.

⛔ **THE TWO COLUMNS ARE INDEPENDENT MAXIMA OVER ALL OF THE PAGE'S CHAINS, AND THE VERDICT IS NOT —
which is why this section's rule is stated in `n` and `b` and must never be restated in the column
names.** `score-drawn-images.swift:262-263` takes `max` of `formDepth` and of `bareDepth`
separately, while `divergent` is decided at the image site from that chain's own
`n = s.depth, r = s.depth - s.bare` (`:250-253`). So `formDepth - bareDepth` need not be any
chain's `r`: a page with `formDepth` 5 down one chain and `bareDepth` 1 down another reads
`5 - 1 = 4` and can still hold a divergence. **Only the first term screens soundly**, because
`formDepth` genuinely is an upper bound on every chain's `n` — and it is the term the corpus
refuses on (max **1**), so the `WONTFIX` above is unaffected and no figure moves. ⚠️ **`CLAUDE.md`
and the queue box DID restate it in the columns and were corrected on the adoption, 2026-08-26** —
the load-bearing summaries wrong while this section was right, which is the drift this register
has caught four times before. The columns are reported as description; the verdict column is the
answer.

✅ **A 46-check `--self-test` over nine built pages, and it runs on EVERY invocation** — so a
sweep cannot be taken from a build whose model has drifted. Every page asserts the census
**and** `largestImage` **and** `drawnLargestImage`, which is the pairing that makes it a gate
rather than the census agreeing with itself. The table brackets both walks' boundaries from
both sides: p7 (`n=3, b=3`) and p6 (`n=4, b=4`) are one structural step apart and the drawn
walk answers the first and not the second; p9 (`r=3`) and p5 (`r=4`) do the same for the
dictionary walk; **p5 is the negative control at the same `formDepth` of 4 with no bare form**,
where `r = 4` and neither walk reaches — so `formDepth >= 4` alone is not the divergence and
the rows say which term does the work; and p8 is a second positive at `b = 2` rather than 4,
which is why the verdict is `n - b <= 3` and not "every form in the chain is bare".

⛔ **Watched failing five ways, every count predicted before the run, and TWO of the five are
sabotages of `Sources/Flattener.swift` itself** — which is what earns the claim that the table
pins production's caps and not the census's model of them:

| sabotage | red |
|---|---|
| census does not enter a bare form (the dictionary walk's rule) | **12** checks, on p4/p6/p7/p8 |
| census `n >= 4` → `n >= 5` | **3**, on p5/p6/p8 |
| census `r <= 3` → `r <= 4` | **1**, p5 — the negative control |
| **`Flattener.largestImage`'s `depth < 4` → `< 5`** | **1**, p5's dictionary answer, nothing → 1200 |
| **`Flattener.drawnLargestImage`'s `s.depth < 3` → `< 4`** | **3**, p5/p6/p8's drawn answers |

All five exit **4**, and all five reds above were **re-run on fresh binaries on the adoption**
and reproduce check for check on the named pages. ⛔ **The "other arm stayed green" half is
RETRACTED as evidence**: `formNesting` never calls `largestImage` or `drawnLargestImage`, and the
three census sabotages edit the tool file only, so neither green can move at any value of
anything — a check whose *input* the sabotage does not touch. That is the retraction this register
published for `shapeHeightHigh` ("the test a green must pass is not *could this check move in
principle* but *does the mutant change this check's input at all*"), being made a second time.
**The attribution rests on the five reds and never needed a green.**

✅ **`Tools/fault-inject.sh drawn_census`, 5 rows, `5 passed, 0 failed`** — the **fifth** Swift
tool of the 32 whose own refusals any case exercises, after `score-mrc`, `pdf-extract-pages`,
`make-observations` and `score-text-voids`. Its two load-bearing rows are the production-cap
sabotage above and one asserting the self-test gates the **sweep** path: a sabotaged build run
over a real PDF must exit 4 **with nothing on stdout**, because a build that exited 4 *after*
printing the TSV header would satisfy an exit-code-only row while having emitted a truncated
sweep that looks like a sweep — invariant 1's shape in an instrument.

⛔ **Exit 5 has no row and cannot get one, said in place rather than counted as covered.** It
fires when a page reads `diverges` while `largestImage` found nothing, i.e. when the census's
model of the dictionary walk's reach is wrong — and every sabotage that produces that also reds
the self-test, which runs first and exits 4 (the `r <= 4` row above is exactly such a sabotage,
and it exits 4). So it is a backstop for a corpus shape the nine fixture pages do not have, and
reaching it needs a page nobody in the tree can build. ⛔ **It also asserted nothing on this
sweep**: its antecedent is the set of `diverges` rows, which is empty, so the run's
`every diverges row had a dictionary answer, on all 16987 pages` line is **vacuously true** and
must not be read as a control. Exit 1 (production disagreeing with the drawn arm) is
pre-existing and equally unwatched; it printed `matched the drawn arm on all 16987 pages`, which
is not vacuous. ⛔ **And exit 5 guards the HARMLESS direction**: it looks for
`diverges && dict == nil`, whereas the arithmetic's real failure mode is
`bothBlind && dict != nil` (see the `r = n - b` upper-bound correction above), which is
unguardable because a `bothBlind` page may legitimately hold a shallow image.

##### Six more gaps in the instrument, named by the adversarial review of the adopting diff

Recorded, not fixed. None of them moves the corpus result; all six are about what the table
would notice if the census drifted.

1. ⛔ **`partial` and `capRefused` are asserted by NO check and no fault row.** Enumerated
   against the `expected` table: `flat` (p1, p2), `withinCap` (p3/p4/p7/p9), `bothBlind` (p5),
   `diverges` (p6/p8) — two of the six verdicts have no fixture. `partial` is the one **3
   published corpus rows carry**, and it is the gate that excludes them from both histograms.
2. ⛔ **`censusDepthBound` = 8 has no check at any value.** Sabotaged to `2` it would red three
   verdicts; sabotaged to `80` it reds nothing.
3. ⚠️ **Fault row 5 is weaker than "the only thing pinning where the columns land" claims.** Its
   fixture page reads `formDepth 1 / bareDepth 1`, so a sabotage swapping the *emission order*
   of those two fields leaves it green — both are 1 — and the self-test is blind to emission
   order entirely, reading struct fields rather than the row. The row also reads `NR==2`, so
   renaming the three header entries reds nothing, and `precondition(fields.count ==
   columns.count)` cannot see either. A second fixture page with a resource-carrying form
   (`1 / 0`) would close it for one field pair.
4. ⚠️ **Two of the 46 checks are entailed by a neighbour**: `bareDepth <= formDepth` always, so
   p1's and p2's `bareDepth is 0` cannot fail unless the `formDepth` check on the same page also
   fails. That is precisely what the preceding commit (`bee2db1`) named about its own row, being
   true again one commit later.
5. ⚠️ **`flat` conflates "draws no form" with "the content stream yielded nothing".** `partial`
   is set only inside the `Do` callback and at the depth bound, so a page whose stream tokenises
   to nothing reads `formDepth 0, partial false` → `flat`, against the positive claim that
   "0 means the page draws no form at all". Production keeps that distinction on purpose
   (`.unreadable` against `.noImage`). Not realised here — all 719 census-file rows read
   `drawsAny=yes` — but the 16,268 `flat` pages are unaudited for it.
6. ⚠️ The self-test leaks its temp directory when it fails: the `defer` that removes it is not
   run by `exit(4)`, so a `fault-inject drawn_census` run leaves three `drawn-census-<pid>`
   directories in `NSTemporaryDirectory()`.

##### The controls, and one instrument defect found by hitting it

✅ **Columns 1-13 are byte-identical across the two binaries either side of this diff** over all
16,987 rows — the tool built from `HEAD` and the tool built from this working tree, run over the
same corpus. So the appended columns moved nothing, and the pre-existing summary reproduces
C24's own published figures exactly: **39 `smaller`, 6 `wider`, 285 `noDictImage`, 3
`unreadable`**. ✅ And `DRAWN-2026-08-16.tsv`'s column 6 — taken by the *old* production path
before C24's wiring existed — equals this run's `dictRebuildDPI` on **48 of 48** rows.

✅ Two internal consistency readings: the **3** `partial` rows are exactly the 3 `unreadable`
pages, same document (`Astin__The Challenge of Open Admissions`), so nothing reads `partial` for
want of depth; and the **719** `formDepth >= 1` pages include **`Lyons oral history` at 114 of 114**,
which is what `drawnLargestImage`'s own doc comment says that document is (its scan one level
down inside a form) — an independent confirmation the census finds real nesting where the
register already said it is.

⛔ **One defect in this work, found by running it, and it was the instrument.** The fault row
asserting "exactly one check red" read **2** and reported a defect that was its own: a bare
`grep -c 'FAIL'` also matches the tool's `SELF-TEST FAILED: 1 of 46 checks` summary line.
Anchored to `^  FAIL`. ⚠️ And a second gap named rather than closed: the column-order sabotage
(swapping the three appended fields) leaves the self-test **green** — it calls `formNesting`
directly and never goes through `row(...)` — and reds only the fault case's inverse row. So
that row is the **only** thing pinning where the census columns land.

**Sibling sweep.** ⛔ `Tools/score-drawn-images.swift` is the **only** file in `Tools/` that
re-implements a `CGPDFOperatorTable` walk (`git grep -l CGPDFOperatorTable` finds it and
`Sources/Flattener.swift`, nothing else), so the drift hazard this section is careful about is
unique to this file and the self-test is its whole gate. Six tools read `largestImage` or
`drawnLargestImage`, all of them consuming the answer rather than asking about structure, and
none moves because nothing in `Sources/` changed. ⚠️ **The sweep's own finding, which belongs to
the queue's `tsv-header-drift` and is not fixed here**: **ten** tools carry the
`fields.count == columns.count` width check, which asserts the **width** and not the
**order** — `CONTRIBUTING.md` §5's row says "with the width asserted", accurately — and the only
thing anywhere that pins order is a fault-inject row, which now exists for exactly one of the
ten. ⛔ **A draft of this sentence said "twelve tools carry the `precondition(…)` idiom" and BOTH
halves were wrong, counted on the adoption 2026-08-26**: `git grep -c` reads **10** files, one
occurrence each, and **2 of the 10 are not a `precondition` at all** —
`score-reading-order.swift:884` is a `guard … else` and `score-threshold-loss.swift:527` a
ternary returning `nil`, which is a *refusal* rather than a trap and therefore not even the same
failure mode. The count was written rather than grepped, in the sibling-sweep paragraph whose
other two counts were both grepped and both hold. ⚠️ **And "twelve" is a real number of a
different set, which is why the two must be said apart**: the *width-asserting* population is
**12** — the ten above plus `score-mrc.swift:617` (a ternary over `cells`, which the `fields`
grep misses) and `score-run-width.swift:146`, whose `precondition(columns.count == columnCount)`
asserts the **header against a literal** rather than a row against the header, a different
assertion again. Ten is the denominator for "exactly one of them has a fault row"; twelve is the
denominator for "asserts width, not order".

### C25 · `score-text-route` has never compiled, and three documents cite it as the evidence — FIXED

### C26 · A small line drawing is erased on the PICTURE path, because the page it sits on is correctly read as all text — FIXED (the bar moved 2026-08-19; the founding pages were RENDERED 2026-08-20 and the drawings are back. The wider stencil question is `C28`)

### C27 · Spot colour cannot reach a mean-saturation bar, so one pamphlet keeps its red ink on 1 page of 10 — FIXED 2026-09-25 (a second way to keep colour, `sheetFrac > 0.01`, beside the unchanged 0.06 mean bar; misses `Glazer_2002` p1 by design)

### C28 · The stencil is confined to Vision's word boxes, so ink the recogniser missed is stored at an eighth of the page — FIXED 2026-10-06 (dark unboxed ink goes into the stencil, pale marks into a mark layer at 1/3; the shape term stays)

### C29 · A born-digital cover page is rasterised and re-OCR'd, and `hasDigitalText` never even looks at it — FIXED

### C30 · Whole blocks of clean body text get no text layer, and every instrument that could see it starts from the words Vision returned — FIXED 2026-09-25, by recognising the page again in overlapping bands wherever one request leaves a void

### C31 · A page C27 now keeps in colour prints its body text in a blotchy, washed-out fill, because the layered route's foreground layer mixes paper into the ink — FIXED 2026-09-25

### C32 · Pages whose only colour is red headings are published black and white, so a pamphlet loses its heading colour on most of its pages — FIXED

### C33 · Blocks of text still cannot be selected after C30: some pages keep whole uncovered blocks, and on others the lines exist but PDFKit drops or garbles them — FIXED

### C34 · The text layer is written across the page row by row, so selection jumps between columns, and some Vision lines span the gutter — FIXED

### C35 · Some already-OCR'd files come out several times larger than they went in — FIXED

### C36 · Text that reads sideways on the published page, including landscape pages under `/Rotate`, gets a text layer laid flat and squashed to about 1.5 pt, so it can be found but not selected where it is printed — FIXED

### C37 · Scans that arrive as 1-bit JBIG2 are re-encoded at up to 2.5x the bytes — FIXED

### C38 · Text on layered pages is illegible in Preview: PDFKit draws the text stencil at the foreground image's resolution, and C31's fix was checked in poppler, which does not — FIXED 2026-09-26

### C39 · A large newspaper page is rebuilt at 125 ppi from a 300 ppi source, and its text layer is misread, crosses columns and cannot be selected — FIXED *(split 2026-09-27: drag selection `WONTFIX`, whole-page scans' reading moved to C41; read strip by strip since `9555c8a`; reopened 2026-09-26; a layered page's type published at its mask's resolution 2026-09-27; drag selection closed `WONTFIX` on a sound instrument, and a raised 1-bit page's words read at its type's resolution, 2026-09-27)*

### C40 · On Hughes p5 four rows still join the two columns, above and below a figure — FIXED

### C41 · Whole-page scans of small-town newspapers are read far below their print: misread words and rows fused across columns — OPEN

### C42 · A page whose crop box is not centred on its media box gets its text layer shifted off the ink, 81 pt on a two-page book spread — FIXED

### C43 · The born-digital verdict is wrong both ways: narrow-strip scans are passed through unread, and pages with a full-width image strip or a figure are rasterised — FIXED 2026-09-28

### C44 · Copied text repeats the tail of every word hyphenated at a line end: "difference ference" — FIXED

### C45 · A reader's own highlights, underlines and notes are dropped at default settings, and nothing says so — FIXED 2026-09-28

### C46 · Vision's automatic language detection writes Arabic into English pages' text layers, and one such run traps PDFKit on a click — FIXED 2026-09-28

### C47 · Outputs come out larger than their sources on already-compact scans: JBIG2 re-encoded and JPX layers turned into JPEG — FIXED 2026-09-29

### C48 · Page labels and the document title are lost — FIXED 2026-09-29

### C49 · Colour that carries meaning on a mostly black page is lost: chart series turn one grey, a pink notice vanishes — FIXED 2026-09-29

### C50 · Typewritten and low-resolution pages are misread more than the source's own reading allows — FIXED 2026-09-29

### C51 · Lines and table cells are still missing from the text layer after C33, so they cannot be selected or found — FIXED 2026-09-28

### C52 · A drag down one column still jumps into the next partway down — FIXED 2026-10-12

### C53 · Single lines and line tails on clean print are missing from the text layer, and nothing says so — FIXED

### C54 · Pale typewriting on layered pages is published broken and faded — FIXED

### C55 · Some runs are drawn below their ink, so a drag over the line copies the line above — FIXED 2026-10-06 (fix 15fb588, 2026-10-05; `___ 2` p1's ad column accepted)

### C56 · Pages that arrive 1-bit, or are re-gridded, come out with heavier type than the source — FIXED 2026-10-14

### C57 · Old print and newspapers are read with more words wrong or missing than the approved on-device models leave — OPEN

## Robustness and correctness of reporting

### R1 · jbig2 and qpdf children are never registered for cancellation — FIXED

### R2 · `runStreaming`'s read loop cannot be interrupted — FIXED

### R3 · `forgetToolPaths()` has no *production* caller — FIXED

### R4 · Progress state keyed by file name — FIXED

### R5 · Per-file settings re-read from `UserDefaults` on worker threads — FIXED

### R6 · `resetAll()` omits four keys — FIXED

### R7 · "Open output folder when finished" does nothing with "beside each original" — FIXED *(twice)*

### R8 · `assemble` builds the whole PDF in memory — FIXED

### R9 · Picture-page JPEGs are held in scratch for the whole run — WONTFIX

### R10 · Each picture page's JPEG is encoded twice — FIXED

### R11 · Dead code: `Model.rebuild(_:mode:isCancelled:progress:)` — FIXED

### R12 · `JBIG2.assemble([])` writes a structurally invalid PDF — FIXED

### R14 · Cancel on the JBIG2 route was reported as a failure — FIXED

### R15 · JBIG2 children were adopted and never released — FIXED

### R16 · Extract Text mode could not be cancelled and could wedge — FIXED

### R17 · Reading `terminationStatus` after a best-effort wait could abort the process — FIXED

### R18 · A batch could plan to overwrite one of its own inputs — FIXED

### R19 · The document outline was dropped from the copy — FIXED

### R20 · Three small robustness gaps — FIXED

### R21 · Cancel could not kill a grandchild — FIXED

### R22 · The stderr drain woke 5 times a second for the life of every run — FIXED

### R13 · Poor photocopies cost ~720–920 KB/page — WONTFIX *(decided: fidelity)*

### R23 · `copyOutline`'s `rebuild()` has neither bound its mirror has — FIXED

### R24 · The megapixel guard's own `Int` arithmetic traps before it can refuse — FIXED

### R25 · `largestImage`'s Form XObject walk has a depth cap but no visited set — FIXED

### R26 · `pageTooLarge` tells the user to change a setting that cannot reach the rebuild — FIXED

### R27 · An input named `text.pdf` fails every time, deterministically — FIXED

### R28 · Three claims from the 2026-08-09 review that did not survive — NO DEFECT

### R29 · `saturation` allocates from the raw page box, outside every guard R24 added — FIXED

### R30 · `askLoginShell`'s three-second bound is on the wall clock — FIXED

### R31 · A failed bundling audit leaves the broken helpers in the bundle, and the build says the opposite — FIXED

### R32 · The DMG verification's failure path can swallow its own diagnostic and leaves the rejected image — FIXED

### R33 · Cream paper promotes every text page to colour: 33 MB in, 709 MB out — FIXED

### R34 · JPEG 2000 for picture pages — WONTFIX *(decided: measured, it loses)*

### R35 · Per-page background downsample — WONTFIX *(twice: no threshold exists, and the signal is structurally blind to a whole class of picture)*

### R36 · Bundling OpenJPEG for the background layer — WONTFIX *(decided: 1.19x)*

### R37 · Small documents come out larger than they went in — FIXED *(reported, not compressed away)*

### R38 · Dense bilevel type is routed to the picture path — FIXED

### R39 · The recogniser's DPI ceiling cannot bind on Automatic — FIXED

### R40 · Batch throughput fell when recognition came in-process — FIXED

### R59 · `publish` failed onto another volume, and deleted a folder it was aimed at — FIXED

### R58 · Two review rounds on the annotation transplant, and both found marks in the wrong place — FIXED, third round unrun

### R56 · `isPicture` is blind to pale marks, and the 1-bit route erases them — FIXED

### R57 · a continuous-tone plate can miss both routing thresholds at once — FIXED

### R55 · `classify-source` calls an upright-scanner capture `photographed` — WONTFIX *(decided by the owner 2026-08-17, on the measurement below)*

### R54 · `sweep-zotero.py` pools 181 parentless attachments into one pseudo-type — FIXED

### R53 · R50's own doc comment recorded one miss where there are two — FIXED

### R52 · Photo detail = Maximum was silently overridden on any page read as text — FIXED

### R51 · Colour layering's stated memory figure omitted its own output buffers — FIXED

### R50 · The tone layers, not the stencil, were what kept a layered file large — FIXED

### R49 · 31 MB in, 437 MB out — the one page kind that could not be layered — FIXED

### R48 · `sample-zotero.py` could not build its classifier — FIXED

### R47 · A new check could have ended the suite instead of failing — FIXED

### R46 · The helper's output was not byte-reproducible — FIXED

### R41 · A run report could say recognition used helper processes when every file fell back — FIXED

### R42 · Two fault-injection checks judged one run and described another — FIXED

### R43 · `run_tests.sh` blamed the suite when the helper would not compile — FIXED

### R44 · The helper's stall bound did not cover a maximal first page — FIXED

### R45 · `alignmentScore` carried a `height` parameter nothing used — FIXED

### R61 · Two declared-geometry conversions still trapped, on the default route — FIXED

### R62 · `inkCoverage` divided one population by another — FIXED

### R60 · Retry Failed publishes over a file the same batch deliberately kept off — FIXED

### R63 · Cancelling a Plain Text run reported every in-flight file as **failed** — FIXED

### R64 · The run report carried the document's own text — FIXED

### R65 · A retry declined at the alert left the batch gutted — FIXED

### R66 · The import interlock was a flag, so the first drop to land lowered it — FIXED

### R67 · One line in a login startup file cost JBIG2 for the whole session — FIXED

### R68 · The report's JBIG2 row was the checkbox, not the route — FIXED

### R69 · Extract Text could be made to silently OCR a picture of good text — FIXED

### R70 · "PDF render DPI" is inert on the default route and said otherwise — FIXED *(the panel)*

### R71 · Two presets are byte-identical and one of them claimed otherwise — FIXED *(the prose)*

### R72 · The updater opened whatever URL the response body named — FIXED

### R73 · A NUL in *Languages* or *Custom words* aborted the whole app — FIXED

### R74 · A document Vision read nothing from published as a silent success — FIXED

### R75 · The manifest's newline guard missed every newline but one — FIXED

### R76 · A cancelled text extraction still replaced the user's previous output — FIXED

### R77 · `stop` gave up on an exited child, stranding the grandchild — FIXED

### R78 · Four smaller reporting defects, one of which could destroy a report — FIXED

### T11 · The skip census was a documented number, and three checks were gated behind a tool they do not use — FIXED

### R79 · Five smaller defects, and a refusal that named the wrong remedy twice — FIXED

### R80 · The updater could offer a downgrade, and Check Now gave no way to take it — FIXED

### R81 · A whole line drawn at 5% of its width, because a second reading of its own ink counted as the next fragment — FIXED

### R82 · Words weld when one fragment of a line is much shorter than the next — FIXED

### R83 · The small ones from areas 2, 3 and 13, and two constants that described the wrong phase — FIXED

### T12 · Two instruments that reported clean over things they had not measured — FIXED

### T14 · All four invariant-3 instruments were compromised, and the procedure would not run — FIXED

### T13 · Nothing proved the annotation setting was wired to anything — FIXED

### T15 · `score-mrc` mirrored the layering instead of calling it, and the five drifts did not all push the same way — FIXED

### T16 · Nothing checked that a tool compiles, and two had not since the annotation transplant — FIXED

### T17 · The corpus gate linked the app's page test and then computed its own — FIXED

### T18 · Five copies of "sample pages through a document", two of which measured one page twice — FIXED

### T19 · The two tools that write argv[2], where a shell glob puts a corpus document — FIXED

### T20 · T16 added a shell arm to the tool checker and left the hook's selector at `swift|py`, so it had never run at commit time — FIXED

### T21 · The hook could not check itself, and the sweep behind it could not see three scripts the hook runs — FIXED

## The interface

The GUI got no review attention during the period when this was going to become
a headless backend. When that reversed, three adversarial passes over it found
fourteen defects — **two of them regressions introduced by the pass before**.

### U29 · The whole updates block is in Settings twice — FIXED

### U30 · The "Start from" preset buttons give no sign they did anything — FIXED

### U1 · A green "40 of 40 succeeded" over a list of 43 files — FIXED

### U2 · Quitting orphaned the OCR children — FIXED

### U3 · Closing the window mid-run left an invisible batch — FIXED

### U4 · Settings accepted edits that could not apply — FIXED

### U5 · `askLoginShell` could freeze the app — FIXED *(the bound it added did not work; see U18)*

### U6 · The progress bar showed a number nobody measured — FIXED

### U7 · Five smaller ones — FIXED

### U8 · Accessibility — FIXED

### U9 · A folder passed as the mac-ocr path — FIXED

### U10 · The log could not be got out of the app — FIXED

### U11 · Layout at the minimum window size — FIXED

### U13 · The window could not be got back after closing it mid-run — FIXED

### U17 · Every file opened from Finder spawned another window — FIXED

### U14 · Three smaller interface defects — FIXED

### U15 · `SettingsView` could not fit on a short display — FIXED

### U16 · Nothing was spoken as it happened — FIXED

### U22 · The first-launch instructions described a bypass macOS had removed — FIXED

### U23 · `remove` and `clearFiles` were guarded only by the view — FIXED

### T8 · The states-by-doors cross product, for the fourth way fixes cause bugs — FIXED

### U24 · The file list said nothing about progress — FIXED

### U25 · Three defects in one 255-file run — FIXED

### U26 · Eight defects in the update checker and the progress UI — FIXED

### U27 · Three defects in U25 and U26's own code — FIXED

### F1 · Automatic could see colour and threw it away — FIXED

### U28 · Three defects in the colour work's own code — FIXED

### U12 · Settings input validation — NO DEFECT

### U18 · `askLoginShell`'s three-second bound sits *after* the unbounded read — FIXED

### U19 · Every batch-mutating control stays live during the C17 pre-flight — FIXED

### U20 · Dropping a folder walks it recursively on the main actor — FIXED

### U21 · `isCommitted` is cleared before the digital-text alert, so an in-flight import lands in a frozen batch — FIXED

## The corpus itself

Found by the 2026-08-08 run; see [CORPUS-2026-08-08.md](CORPUS-2026-08-08.md).

### D1 · The headline corpus figures rested on material this app is not for — FIXED

### D2 · Line-end selectability has a worse tail than documented — FIXED *(the documentation)*

### D3 · Source line tightness is measurable and untracked — FIXED *(now quoted, and correctly labelled)*

## Verified on a running app

Four things could not be settled by reading or by the suite, and sat in `TODO.md`
saying so. They were run against the real app in a headless
[Tart](https://github.com/cirruslabs/tart) macOS VM — its own virtual display, so
nothing appears on anyone's screen, driven over VNC because VNC-injected input
bypasses the guest's TCC entirely. Procedure in [Tools/README.md](Tools/README.md).

| check | result |
|---|---|
| window recoverable after closing it mid-run | **passes** — the reopened window shows the live batch ("27% · 0 of 3 files · 1 running") with Cancel available, and ⌘0 restores it too |
| Settings on a display shorter than ~700 pt | **passes** — 560x512 at 1024x640, Done visible (U15) |
| keyboard tab order | **passes** — idle: Settings → mode picker → Start OCR → Add… → Clear List → remove-file → Save-beside, cycling; mid-run: Settings → Cancel → Copy, which is exactly the enabled set. Disabled controls are correctly skipped |
| VoiceOver announcements | **not run** — deliberately out of scope for this pass |

It found U17, which no amount of reading was going to find, and which is the most
serious interface defect in this register after U13.

**Three instruments lied before any of it worked**, which is the usual tax and is
worth writing down:

- The window-counting probe filtered `kCGWindowOwnerName` on `"VisionReader"`.
  The bundle name is `Vision Reader GUI` — with spaces — so it reported **zero
  windows while the app had four**, and the first reading of U13 was "the reopen
  does nothing". It filters by pid now.
- **The guest's virtiofs mount served a 90-minute-old `App.swift`.** A build off
  that stale copy looked exactly like "the fix does not work" — the fix was
  measured as ineffective before the mtimes were compared. Sources go over the
  guest agent now, not through the share.
- **A TCC prompt sat on the VM's screen stealing every keystroke.** The first tab
  walk produced a tidy, entirely fictitious three-stop cycle: it was Tab moving
  between the prompt's *Don't Allow* and *Allow* buttons.

## Test coverage

### T1 · No fixture satisfied invariant 5 — FIXED

### T2 · `picture-signals` measured a page production never renders — FIXED

### T3 · Six paths had no coverage at all — FIXED

### T4 · Three checks written for 1.2.0 that cannot fail — FIXED

### T5 · Six calibrated constants nothing checked, found mechanically — FIXED

### T6 · Three checks written for the bundling that cannot fail — FIXED

### T7 · Two ways the mutation harness can report a clean result it has not earned — FIXED

### H2 · leptonica ships with no licence, and the count cannot notice — FIXED

### H1 · Four pieces of housekeeping — FIXED

### T9 · The release gate read the text layer, so a destroyed page image passed it — FIXED

### T10 · The tenth check that cannot fail — and it was invariant 2's only guardian — FIXED

## Fixed earlier in this review

Colour/pale illustrations destroyed by 1-bit thresholding · fixed threshold 186
wrong for non-white paper (now Otsu per page) · encrypted PDFs rendering blank ·
rotated pages published blank on the non-rebuild path · page silently dropped when
its image failed to write · `nativeDPI` not recursing into Form XObjects · `%g`
emitting invalid PDF numbers · xref offsets wrapping past 2 GB · `closePDF`
skipped on throw · undecodable recogniser lines publishing empty pages · dead
Strategy and "Re-OCR" settings and a wrong command preview · crashes reported as
cancellations · output names colliding on case alone · the `0.15` compression
floor welding table rows together · `headroom` comparing box bottoms instead of
baselines · whitespace-only observations drawn and inflated · height ceiling
tuned from the corpus (line separation 80% → 93%).
