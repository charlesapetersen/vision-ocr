# Working in this repo

Vision OCR — macOS SwiftUI app that OCRs scanned PDFs through Apple's Vision
framework and writes its own searchable-PDF text layer. Recognition runs in a
helper process this repo builds (`Helper/main.swift` → `visionocr-recognise`),
compiling `Sources/Recogniser.swift` (and, as `build.sh`'s `HELPER_SOURCES` shows,
`Flattener.swift` and the rest of its closure with it) so the app and the helper cannot diverge —
BUGS.md R40 is why. `jbig2` and `qpdf` are the only other programs it runs.

**Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing anything** — branch,
failing test first, adversarial review of your own diff, and a pre-commit hook
that refuses a commit whose tests do not pass. It exists because this project has
repeatedly shipped regressions *inside fixes for other bugs*.

Then: [HANDOFF.md](HANDOFF.md) for the design rationale and the mistakes already
paid for, and [ARCHITECTURE.md](ARCHITECTURE.md) for the call path, the two page
boxes, and what the tests don't cover.

Planning lives in four files. [BUGS.md](BUGS.md) is the defect register — **four entries are open as
of 2026-08-20: `C27`, `C28`, `C29` and `C30`. `C26` is `FIXED`.** `C30` is the owner's second JSTOR
finding and the widest of them: whole blocks of clean body text get no text layer, and all four of this
project's text-layer instruments count only the words Vision returned, so `words=100%` is silent about it. `C29` is the owner's JSTOR finding — a
born-digital cover page rasterised and re-OCR'd because `hasDigitalText` votes per DOCUMENT and never
samples page 1 at all on a document of 5+ pages. `C26` and `C27` were found on one document after
`1.13.0` shipped; `C28` was opened out of C26's own campaign. `C26` lost
content at the DEFAULT Photo detail setting; `C27` discards spot colour and is fidelity rather
than loss. ⛔ **C26's CONSTANT HAS MOVED — `Flattener.textPageInkOutsideThreshold` is `0.045`, not
the `0.08` most of the register is written against, the owner's decision on a complete campaign,
shipped 2026-08-19.** The 16 corpus pages the sweep named keep their tone layers at the caller's
factor; nothing else moves, measured. ✅ **And the three pages C26 was opened on were RENDERED on
2026-08-20 and the drawings are back** — `verdict` reads `picture` where it read `all-text` and the
backgrounds are 612 px rather than 153 px, and at 1:1 the cartoons are whole and legible where they
were smudges. ⛔ **The verdict is the crops. Do not quote a ratio off that section**: its first draft
led with "5.7x / 6.3x / 5.7x the fine detail", and five blank rects of the same page measure 3.6x–14.2x
— the ratio tracks the downsample factor, not returned content, and the *control* was the worst
offender. What survives is absolute: the drawings read 11.99–12.35 against a blank-paper floor of
2.10–2.51 as shipped, and 1.87–2.16 at the old bar, which is that floor. The ink-fraction column is
worse still — it understates p6, the page the founding table called completely erased, because an 8x
blur keeps solid black while destroying every line. **What C26's close does NOT cover** is
`pageIsAllText()`'s second term, which still ships blind (`paleDrawing(pageMarks(…)).extent` = 0.00000
on p4 and p6, 0.00029 on p7, so no value of `paleDrawingThreshold` reaches them) — carried out as the
queue's `paledraw-term` triage item, and unmeasured. ⛔ **`C28` IS WHAT THAT FIX LEFT, and it is the invariant-1 half:
the 1-bit stencil is the *intersection* of the page's ink with Vision's word boxes
(`textRegionMask`, one production call site), so prose the recogniser missed is in neither the stencil
nor the text layer and survives only in a background stored at 1/8 on a page read as all text —
7 of the 13 pages C26 rendered lose whole lines of running prose or table data that way. ✅ **Something
reports it as of 2026-08-20** — that was the entry's question 5, invariant 1's other half, and it is
`FIXED`: the run report names every page published with the ink outside the recognised words stored at
an eighth, with that page's own fraction beside it, on the success path only and with **no bar on the
fraction** (the campaign proved the losers and non-losers interleave when sorted by it, and one
measured loser prints `0.0000`, so any filter drops a known loser). ⛔ It is a report and not a fix —
the pages are still degraded, and C28 stays OPEN on questions 3 and 4 (question 2 CLOSED 2026-08-21).
✅ **QUESTION 3 HAS ITS FIRST MEASUREMENT, 2026-08-21, AND A SHAPE TERM SEPARATES WHERE FIVE SCALARS
DID NOT** — `Tools/score-shape-term.swift` (new) counts **text lines** in the ink outside the
recognised words at the page's own type scale, calibrating on the stencil's own components, and over 13
labelled pages `lineN` is **≥ 1 on 6 of 6 pages that lose typeset content and 0 on 6 of 6 that lose
nothing**. 12 of 13; the miss is the page whose loss is a hand-drawn bracket, which a rule calibrated
on type reads 0 on — so anything built on this protects prose and table data and must say what it does
about the campaign's 6 hand-made marks. ⛔ Published as blindness *by construction*, and refuted the
same day by the picture run below: 17 and 11 groups on a pen ornament, so it is unreliable on hand-made
marks in **both** directions rather than blind to them. Its five numbers are ratios rather
than sizes, **written before any page was run and not adjusted after** (8 pages, then 5 held out).
⛔ **Not validated: 8 of the 73 plus 5 of the 16 C26's bar move rescued (so 5 of them are not degraded in production today), a labelled convenience sample, 4 of the 6 non-losers from one scan,
and no plate, halftone or line drawing in it at all** — which is exactly the class `textRegionMask`
exists to keep out, so "reads 0 on scanner edges" was not yet "reads 0 on a picture" — **measured the
same day, next paragraph, and it is not** — ✅ **and the convenience sample was replaced by the whole
73-page population later the same day; see the ✅ block below the 3b paragraph.** ⚠️ Read `lineN`
and never the share: the drawn bracket's `txtShare` 0.0173 sits *below* a non-loser's 0.0500 on the
same scan, which is the fifth scalar this entry has refused.
⛔ **QUESTION 3b IS MEASURED 2026-08-21 AND THE TERM ERRS IN BOTH DIRECTIONS** — ten picture pages,
`SHAPETERM-PICTURES-2026-08-21.tsv`. `lineN` is **≥ 1 on 6 of 10** and none of the six accepted groups
is type: halftone dots, photograph grain inside a plate whose real caption Vision *did* recognise (12
groups, none on the caption), a pen ornament's feather strokes (17 and 11), and 10,438 px of
page-wide-Otsu speckle in a grey endpaper reading mean 107.5 / sd 2.88 against a page Otsu of 107.
⛔ **The sharper half is the other direction — it reads 0 on TWO pages whose loss C26 measured at 1:1**:
`1954 - Why` p6 and p7, whose cartoons are 92% and 100% of their out-of-stencil ink and give 372 and 785
`textish` px that never reach four members on a baseline. The miss is the *grouping*
(`lineMinimumMembers` / `lineGapFactor`), not the component test — and **p4's one group is a HIT on the
lost cartoon**, `27x17+1121+685` inside the published `254x240+970+595`, not a false positive.
⛔ **So "blind to a hand-made mark by construction" is REFUTED**: measured, 0 on four hand-made marks
and firing on three, which is exactly the *"four blobs of a broken pen stroke"* case the last review
predicted. ✅ **`Tools/README.md` is corrected as of 2026-08-21**, riding along on the suite-paying
commit that measured the whole 73, with the settings blurb — ⚠️ and the debt was one file, not two:
`Tools/score-shape-term.swift`'s header never contained the phrase, so what it was actually owed was a
mention of 3b at all, which it now has. On `Wilcox` p2 the term is wrong both ways: 0 accepted pixels over the hand-lettered
"Harry W. Wilcox", 1,694 on the decoration. Four more scalars refused (`glyphN` interleaves 2,468-fires
against 2,255-does-not, so "too little recognised type to calibrate on" is **not** the mechanism;
`txtShare` again; absolute `linePx` 10,438 beats a real 7,533; `topLine` width 202 beats a real 95).
✅ **The bound holds for ONE of the two seams**: all ten are `barVerdict=picture`, so
`inkOut < 0.045 AND lineN == 0` never consults the term on them and the byte cost is zero — *derived
from the sweep's verdict column, not measured, because nothing is wired* — on a **1.10x** margin (0.0493
against 0.045). ⛔ **Under `textRegionMask` there is no bound, and that is the seam question 3's own
sentence names**: it runs unconditionally on every layered page (`Flattener.swift:2696`), so those six
pages would admit halftone dots and pen strokes into the 1-bit stencil, which is R57's failure mode.
⚠️ `lineShare` separates 22 of the **23** pages run so far (0.0002–0.0099 firing, 0.2332–0.9937 on
type-losers, 23.56x) and is **the seventh share in a register that has refused six** — `txtShare` with a
narrower numerator, post-hoc, denominator-driven, and it leaves **four known content-losers on the safe
side**.
✅ **THE CONVENIENCE SAMPLE IS GONE: the term was read over the WHOLE 73-page sub-bar population on
2026-08-21, constants unchanged, and QUESTION 4 GOT ITS FIRST PAGE-LEVEL BYTE PRICE OUT OF THE SAME
RUN** — `SHAPETERM-73-2026-08-21.tsv`, 73 rows in 22 documents, **65 of them never measured before**.
`lineN` ≥ 1 on **12 of 12 pages that lose typeset content** (8 of 8 out of sample, so the 6-of-6 was
not its sample), **1 of 4** losing only a hand-made mark, **0 of 6** degraded-but-legible and **3 of
51** that lose nothing. ⛔ **All three of those firings are the RIM of recognised type**, read at 1:1 —
glyph tops falling outside Vision's word boxes on lines that ARE in the text layer — so the candidate
was subtracting a *dilated* `region` before grouping.
⛔ **THAT CANDIDATE IS MEASURED 2026-08-21 — `SHAPETERM-RIM-2026-08-21.tsv`, the same 73 pages, one pass
over radii 1/2/3, all 27 shared columns reproducing the previous file on 73 of 73 — AND IT SPLITS INTO
TWO READINGS.** Type-losers firing / non-losers firing: r=0 **12/12, 3/51**; r=1 **12/12, 2/51**;
r=2 **11/12, 1/51**; r=3 **9/12, 1/51**. ⛔ **As a REPLACEMENT for the rule it is refused**: r=1 is the
only radius that keeps every real loss, and it clears two rims of the three while **adding one of its
own** — on `Xin Qu et al_2018` p28 the rim of a recognised `469.` is three accepted components at r=0,
one short of `lineMinimumMembers`, and a 1-px collar splits the middle one (`8x8` → `4x6` + `3x6`) into
four, which is the non-monotonicity the tool's own comment predicted before the run — ⚠️ `rim1N` is 2
there, so two groups are manufactured and only the larger was read. From r=2 it starts
destroying real losses (`Williams_1958` p1, then `Scott_TK` p3 and `Merriam_1913` p2 at r=3). The rim
that survives every radius is `Herbert Marks papers` p12, read at 1:1 at r=3 as 4-px flecks off the
tops of `Corp.` on a recognised ledger line (64 px, exactly `rim3Px`).
✅ **But as a SECOND CONDITION it is the best rule this campaign has measured**: `lineN >= 1 AND
rim1N >= 1` reads **12 of 12 type-losers and 1 of 51 non-losers**, on **14** pages rather than 16, and
p28 cannot enter because `lineN` is 0 there. The two pages it drops are both non-losers, so the wiring's
price can only fall from +2,362,625 B — a direction, not a number. ⚠️ **Three reasons it is a lead and
not a result**: it is post-hoc (a conjunction chosen after seeing these 73 pages, which is the objection
this entry raises against six shares); the hand-made bucket does not move (1 of 4 at every radius); and
⛔ **the rim columns have never been run on a picture page**, so 3b's `textRegionMask` finding is
untouched and that is the one run it needs next.
⚠️ A ratio-scaled collar does not rescue the replacement reading: `Scott_TK` p3 loses its last group at
**0.375x** its own `glyphH` (8) while p12 still fires at **0.6x** its own (5) — ⚠️ derived from radii
1-3; radii above 3 were not run. ⛔ **And the first draft of this got the mechanism wrong in five
files**: it said the collar "runs backwards", smallest type where the false positive is and largest
where the true positives are, which its own data refutes — `Scott_TK` p3 is destroyed at `glyphH` 8, the
second-smallest of the twelve, and `Herbert Marks` p11 is a real typeset loser at `glyphH` **5** that
fires at every radius, so "the smallest type" separates nothing. ⚠️ For the **local** variant this entry
prefers (exempt the text-shaped regions rather than refuse the page) a collar is worse than any boolean
shows: at r=1 `Scott_TK` p3 keeps 278 of 1,796 accepted line pixels and its largest group *moves* to a
different part of the page. ✅ **A signature DOES fire**
(`_1939_Former students` p6's only group is the cursive signature itself) — the **fourth** hand-made
mark the term is measured firing on, after `Wilcox` p2, `Wilcox` p6 and `1954 - Why` p4, and the
second on a page of measured loss (p4's group is a hit on its own lost cartoon). ⛔ **One of the three misses is not
the rule's**: `_1939_Former students` p2 has `outPx` **0** — the map is empty, which is the page-wide
Otsu's known blindness to pale pencil, upstream of any shape rule. ⛔ **And `linePx` is refused a second
time, harder**: `Jones et al_2010` p2 is a real loss at **147 px**, below all three false positives, so
no floor removes a rim without dropping a measured loss. **The price**: the wiring
(`inkOut < 0.045 AND lineN == 0`) refuses the shrink on **16 of 73** pages, **789,825 → 3,152,450 B,
+2,362,625 B, 3.99x**, with **15.5%** of the spend on pages that lose nothing — against the cheapest
page-wide bar rescuing the same 13 (`inkOut >= 0.0008`), which refuses **41 of 73**,
**1,915,380 → 8,117,445 B, +6,202,065 B, 4.24x, 58.5% of it on pages that do not lose content**. **38.1% of the bytes**, and the
first term in this campaign whose money mostly lands on pages that lose content. ⛔ **Not equal
protection**: the bar rescues **15 of 16** losers and the term **13** — the two extra are hand-made
marks costing +575,066 B — and **neither reaches `_1939_Former students` p2**. ⚠️ Bytes are at the
default Photo detail, page by page through `score-text-route`, and the *local* variant would be
cheaper, so +2,362,625 B is an upper bound. The `textRegionMask` seam is still unpriced and **nothing
is wired**.
✅ It also settles
`score-text-route`'s open instrument question, because it holds `region` itself so its map **is**
`inkOutsideText`'s set (asserted every row, exit 6 otherwise; `inkOut` reproduced
`INKBAR-2026-08-19.tsv` on all 13): the dumped stencil inflates the fraction **1.00x–3.17x**, the
published `Disk:3` dilation lands **0.721x–1.007x**, and ImageMagick's OTSU equals
`Flattener.otsuThreshold` on **13 of 13** pages over a 69-level range — so that recipe's published
0.56x–16.0x spread is bounded on pages with ink to divide by, and its extremes all sit on `inkOut`
0.0001–0.0051, a small-denominator candidate that is **not measured**. Nothing is wired: `Sources/` is
untouched, and question 4's byte price is still owed (the *area* a local exemption would keep is
0.12%–1.04% of the page on the six losers, which is not a byte figure and must not be quoted as one).
✅ **Question 2's 1/2 HALF IS MEASURED 2026-08-20 and it does NOT reproduce.** The 109 layered pages the
bar does *not* read as all text keep the caller's factor, which on the default Photo detail is **2**;
sixteen of them were rendered and read at 1:1, ten beside a 1/8 reference on the same rect, and **no
content loss was found at 1/2 in any window read** — including on the two pages where the same ink WAS
destroyed at 1/8 before the 2026-08-19 bar move. So this defect
stays bounded to the 73 pages at 8x/16x **on the default setting** instead of widening to 182, and the
entry's guess ("degraded but legible") is now measured on the default rather than assumed. 16 of 109 is
a sample (all 6 of the sub-bar pages, 2 of the 16 rescued, 8 of the other 87), read **one window a
page**.
⛔ **QUESTION 2'S 1/3 HALF IS MEASURED 2026-08-21 AND IT DOES REPRODUCE — so question 2 is CLOSED and
what remains of C28 is questions 3 and 4.** `PHOTODETAIL=maximum|balanced|smallest` was added to
`Tools/score-text-route.swift` (which had no way to vary the factor at all), the 16 pages C26's bar
move *rescued* — a different sixteen from the 1/2 sub-step's, overlap two — were rendered at
`PhotoDetail.smallest` too, and **`Xin Qu et al_2018` p20 loses the
correlation matrix's last column** — thirteen values legible in a 460 px background and unreadable in
the 307 px one, at zoom 8 `−0.130*` reading `−#.1##*`. Two more are degraded and still legible
(`_1973_CAR` p4's unrecognised prose lines; `Jones et al_2010` p12's table rule, darkest pixel 25 → 56
→ 136 against paper at ~250) and five read clean — all three `1954 - Why` cartoons, `Riesman - 1954`
p16's pen bracket, and a whole line of unrecognised typescript on `Atkinson_1939` p2. ⛔ **The term that
orders this population is the page's own rebuild resolution, not `inkOut` and not a difference map**:
the loser has the smallest source render of the sixteen (921 px) and ranks *sixth of sixteen* on the
1/2-against-1/3 difference, so that scalar is refused the way the out-of-stencil pixel count was.
⛔ **BUT THE RESOLUTION CLAIM ITSELF WAS RETRACTED BY THE REVIEW OF THAT DIFF, THE SAME DAY**: sorted
by source width the three clean `1954 - Why` pages (1,224 px) sit BETWEEN the two degraded ones (1,208
and 1,240), so width interleaves the verdicts exactly as `inkOut` does — a fourth refused scalar, not a
new ordering. What survives is existence plus mechanism: the one page that loses is the narrowest, and
307 px of background under 9-pt table type is why. And the quantity read was source pixel WIDTH, not
`rebuildDPI`. ⚠️ Also retracted there: **8 of the 16 have a 1:1 reading, not 16** (all sixteen were
rendered and are in the byte table; eight were looked at), and "the same 16 pages" as the 1/2 sub-step
is wrong — those were 6 sub-bar + 2 rescued + 8 others, these are all 16 rescued, overlap two.
⚠️ **A draft of that sub-step was on course to conclude "no loss at 1/3" off its first five pages**, all
of which are clean; picking the sixth by narrowness rather than by `inkOut` overturned it. Smallest
costs **0.6465x** the bytes of Balanced over the sixteen, and **the page that loses content saves the
LEAST** (17,705 B against 240,578 B on a page whose only out-of-stencil ink is a scanner edge).
✅ An all-text page is **byte-identical** at both settings, measured — `max(3,8)` is `max(2,8)` — which
is what bounds this to the 109 rather than the 182. ✅ **`PhotoDetail.smallest`'s user-facing blurb
promised that photographs at a third resolution *"look noticeably soft up close, though nothing is lost
from them"*, which that page makes false — the clause was DELETED 2026-08-21 (owner's call) and nothing
replaced it**, because a caveat about small print would itself need retracting if C28 is fixed.
`Sources/Prefs.swift` carries the reason beside it and `Tests/main.swift` pins the absence over all
three `PhotoDetail` cases, watched failing against the pre-fix string.
⛔ **AND THAT SUB-STEP'S OWN DRAFT TRIED TO RETRACT A CORRECT CLAIM OF THIS CAMPAIGN'S IN SIX PLACES,
and the adversarial review of its diff refuted it from the same page** — it measured stencil ink in one
rect of `Xin Qu et al_2018` p20's matrix (top-left, 0.98x, stencilled), concluded "thirteen values" was
misattributed, and would have had the next commit break a correct comment in `Flattener.swift`. The
matrix's LAST column reads stencil ink **0.0000** and holds 1,375 of that page's 6,233 out-of-stencil
map pixels: thirteen values, exactly as published. **A stencil-ink ratio is a claim about its rect, not
about the page.** The related trap is real and stays recorded — `fillHoles` leaves stencilled ink in the
background as a pale ghost, so a ghost's disappearance looks like a loss and a ghost-only rect looks
like safety.
**Back to the campaign:** eight more of the 73 beyond C26's thirteen were rendered 2026-08-20
(`78de7a2`) and 4 of the 8 lose content;
24 more the same day (`6818a0e`) and 2 of those; 20 more the same day (`72b866e`) and **8 of those
20**; and ✅ **the last 21 the same day and 2 of those — so ALL 73 ARE READ and 16 of the 73 lose
content**, 12 of them type and 5 a hand-made mark. The campaign stands at **86 pages rendered, 24
losing content, 19 of them type and 6 a hand-made mark** — ⚠️ **and those two no longer sum to the 24,
because `Atkinson_1939` p3 is in BOTH buckets as of 2026-08-21**: the shape term found two lines of
typescript on it that sub-step 1's inventory (a signature and a typed dash rule) never listed, and its
own two dumped backgrounds settle it — illegible at the shipped 8x, legible un-shrunk. The page counts,
16 and 24, do not move. ⚠️ This line read "21 pages
rendered, 12 losing content" while 45 had been read, because `6818a0e` did not update it; the total is
arrived at by addition over the sub-steps, not by re-measuring.** ⛔ **The last 21 put a loss where the bar cannot reach
it**: `Williams_1958_DEMOCRACY OR MERITOCRACY` p1 loses the words `their education,` and `but` at
`inkOut` **0.0023**, and `_1939_Former students` p2 loses a **pencilled annotation at an `inkOut` that
prints 0.0000**, where no legal `INKBAR` and no shippable bar exist — ⚠️ `barDelta same` at 1e-5 bounds
that page to [0, 1e-5) rather than proving it zero, and neither reading leaves a usable bar, because
the guard is a strict `<` and a bar of 0 makes `pageIsAllText()` false on all 16,987 pages — turning
the shrink off corpus-wide rather than on the 73 it currently reaches.
⚠️ A first draft of this line said "44 of the 73 sit
strictly below that and lose nothing" — the review of that diff refuted it from the entry's own
sub-step 2 table: `Jones et al_2010` p2 loses a word at 0.0008. Three figures it corrects: **25 of the
73**, not 27, are unreachable through the override seam (two pages print `0.0000` and flip anyway); the
page with the **highest** out-of-stencil fraction of the 21 loses nothing — a pale typescript whose
every glyph leaves the map a rim, at 11.65x its own `inkOut`; and that same page-wide Otsu **misses**
pale pencil on a shadowed sheet, which is how p2's loss was nearly filed as "nothing" and is the map's
one measured false negative. ⚠️ Two instrument traps recorded there: ImageMagick's `Disk:0` is
**radius 4**, not the identity (`-define morphology:showKernel=1` prints 9x9+4+4), and a
connected-component rect off the interior-cropped map is in a different coordinate frame from one off
the whole map — count the pixels in a rect before believing it names anything. Two measurements say the page-wide bar cannot be the answer: 32.4% of its byte cost
lands on two pages a reader cannot tell apart, and — measured 2026-08-19 over the committed
`INKBAR-2026-08-19.tsv` — **73 sampled pages in 22 documents are still shrunk 8x/16x at the new bar,
and 31 of the 73 are in six of the nine documents sub-step 4 rendered**. In `Broadhead - 1994`,
whose twelve sampled pages are all layered, p8 loses a line of body text at `inkOut` 0.0465 and is
rescued while its p10 sits 0.0024 lower and is not — ⛔ **and measured 2026-08-20 that pair is the bar
getting it RIGHT: p10 loses nothing.** ✅ **C28's first sub-step RAN that day: the eight
pages nearest the bar from below were rendered and 4 of the 8 LOSE CONTENT** — two lines of running
prose each on `Broadhead - 1994` p3 and `Jones et al_2010` p5, table figures / column heads / Roman
row labels on `Scott_TK` p3, and a handwritten signature on `Atkinson_1939` p3, all illegible as
shipped, all read at 1:1 and three of the four also checked against the stencil holding **0.0%–3.6%**
ink in those rects against 7.6%–15.4% on the adjacent lines that survive (`Scott_TK` is the one
without that second check). ⛔ **The headline is that NO VALUE OF THE CONSTANT SEPARATES THE EIGHT:
sorted by `inkOutsideText` they read lose / no / lose / no / no / lose / no / lose**, so the two sets
interleave — a bar low enough to protect all four losers protects all four non-losers too, and the
lowest of the eight loses two lines of prose while two of the four highest lose nothing. Within
`Broadhead - 1994` alone the fraction *does* order its eight rendered pages perfectly (missing p3 by
at most 0.00005), which is why the corpus-level argument rests on the interleaving rather than on
p8-vs-p10 — and note that `Atkinson_1939` p2-vs-p3 and `Jones` p12-vs-p5 are pairs in which **both**
pages lose something, so they say only that 0.045 sits too high in those scans; every actual inversion
among the eight is cross-document. ⚠️ A first draft concluded
"the useful bar is **per scan**"; the audit of that diff refuted it from the committed sweep — the
other three documents contributed **one rendered page each**, so no per-document window is computable
for them. ✅ **C28's SECOND sub-step ran the same day — the other 24 pages of the six read documents —
and the headline is that the loss reaches a THIRD of the way to zero**: `Jones et al_2010` p7 loses the
paper's **estimating equation** at `inkOut` **0.0137** (stencil ink **0.00%** in the rect against
15.59% on the prose line above) and its p2 loses the word "value." at **0.0008**, against a previous
lowest measured loser of 0.0353 — so "the pages near the bar" was never the population, and displayed
mathematics is a failure class the campaign had not seen. `Riesman - 1954` p20 loses a hand-drawn pen
line to a smear; five `Xin Qu` pages lose a footnote rule; the other 16 of the 24 lose nothing a reader
sees, `Broadhead - 1994`'s two lowest pages among them — so that document's window HOLDS at
[0.04415, 0.04495] while `Jones`'s is at most 0.0137, and protecting `Jones` p7 therefore protects
`Broadhead` p2/p4 as well at +379,584 B on two pages of thumbs. ⛔ **But the sharp result is
`Riesman - 1954`, which has NO window: its p18 at 0.0676 loses nothing while its p16 at 0.0565 loses a
hand-drawn bracket, so no bar orders that scan's own pages.** That within-document inversion is what
kills "the useful bar is per scan" outright, and it is the review of this diff's finding — the first
draft claimed "two documents with disjoint windows", which is true only of `Broadhead` against the
other four (`Jones` ∩ `Atkinson_1939` ∩ `CAR` ∩ `Xin Qu` is a non-empty (0.0016, 0.0137]). ⛔ **Two instrument facts from it.** (1) **11 of those
24 — and, measured over all four sub-steps, 25 of the 73 (not the 27 that PRINT `0.0000`; two of those
flip) — cannot be priced through the override seam at all**: `pageIsAllText` is a strict
`<` and `INKBAR` is refused outside (0,1), so a page whose `inkOut` is 0 has no legal bar below it, and
`barDelta` `same` is the test rather than the printed `0.0000` (`Riesman - 1954` p12 prints 0.0000 and
flipped). (2) The instrument that works on all of them is a **`ink AND NOT dilate(stencil)` map** off
the dump's own `-source.png` and `-stencil.png`, validated against `Broadhead - 1994` p3/p10 where it
NAMES the two lines sub-step 1 read by eye — and ⛔ its pixel COUNT discriminates nothing (the loser
15,431 px, the non-loser 15,727 px, flat across dilation radii), which is a scalar term refused for the
second time. ⛔ **Sub-step 3 then rendered the 20 highest-`inkOut` of those 41 and 8 of the 20 lose
content** — the sharp result being that the four pages of the 41 with the MOST ink outside the
recognised words lose nothing, while six between `inkOut` 0.0051 and 0.0165 lose content, so a
one-sided bar protects the wrong end of its own range first; ⚠️ and it *retracted* its own first
claim that the bar "overpays less" here, which compared 37.6% over 14 pages against two whole-sample
figures — like for like it is 54.2% against 57.4% and 56.6%, i.e. flat. ✅ **Sub-step 4 then rendered
the LAST 21 and 2 of the 21 lose content, so all 73 are read and 16 of the 73 lose content** — the
losers are `Williams_1958_DEMOCRACY OR MERITOCRACY` p1 at `inkOut` 0.0023 (two words of newspaper type)
and `_1939_Former students` p2 at an `inkOut` printing **0.0000** (a pencilled annotation), the second
being a page no usable bar reaches. Its 7 priceable pages cost +1,306,920 B at 4.46x with **65.5%
buying nothing**, the
worst overpay of the four. ⚠️ The "same scan, same recogniser" heuristic was tried on the 7 pages it
named and returned 1 of the 7.
⛔ **AND C28'S OWN RECIPE FOR THAT RENDER WAS A FALSE NEGATIVE, measured**: `INKBAR=0.08` on a page
*below* the shipped bar reads `all-text` on both sides and dumps two **byte-identical** backgrounds,
so the comparison the entry told a reader to make is a page against itself. The bar must be BELOW the
page's own `inkOut` (`INKBAR=0.02` covers all eight); the entry, the queue box, the tool's own header
and `Tools/README.md` all say so now. ⚠️ The corrected rule is that `INKBAR=0.08` reaches only
`inkOut` in **[0.045, 0.08)** — 17 sampled rows — and then only where `extent <= 0.05` and Photo
detail is not Maximum: the first fix said "at or above 0.045", which is wrong on the 87 pages at or
above 0.08, and the review of that diff sized it.
⚠️ A `-normalize`d whole-page view then misled **twice more** on that render — it called the whole of
`Atkinson_1939` p3's typescript and the whole of `Jones` p5's Pattern column lost, and 1:1 plus the
stencil's own ink fraction overturned both. And the premise the code states as fact — *"ink that is not inside any
recognised word is, by construction, not text"* — is measured false; both that comment and
`textRegionMask`'s now say so. Read `BUGS.md` C28, and C26's
`#### The constant moved` and `#### The rendered proof on the founding pages`, before touching any
of this; every "would" in its pricing sections is now a "does", and ⚠️ **`INKBAR=0.045` now exits 2
by design** ("equals the shipped bar, nothing to compare") — it is `INKBAR=0.08` that prices the old
behaviour, which also stops `Tools/sweep-ink-bar.py --bar 0.045` dead on document 1.
C27 is undecided: its population sweep has RUN — 10 pages of 441
in 7 documents, three of the eight real ones are colour PICTURES rather than spot colour, and two
carry no ink of their own.** A small line
drawing is erased on the picture path because `pageIsAllText()` shrinks the tone layers 8x and 16x
and the pale-drawing guard in front of that does not fire;
three of four drawings
in a 10-page booklet went, every word survived, and `1.13.0` shipped it hours earlier having been
cut against an empty register. **This sentence said the guard "needs 5% of the page to fire" and
C26 said those marks cover 0.2% — measured 2026-08-18, that 0.2% was a different function's
column, and the quantity the 5% bar actually reads is `0.00000` on the two pages that lose the
most.** So the guard finds no drawing-shaped mark at all there, and lowering `paleDrawingThreshold`
to any value protects neither page. **And measured 2026-08-18, `paleDrawing` was never the term to
look at: the drawings are INK** — 5,495 / 4,188 / 3,379 cells below their page's own Otsu, against
8 / 350 / 0 pale cells the guard is offered — so they are cut out of the stencil by
`textRegionMask` (correctly by its own lights, which is `C28`: it keeps only what was *recognised*),
left in the background, and the background is
what gets stored at 1/8. The term that decides those pages is `pageIsAllText()`'s **first** one:
`inkOutsideText` reads **0.0493–0.0660 against what was then a bar of 0.08**, so it saw them and let
them through, and unlike the pale term it *can* reach them — which is why 0.045 refuses all three.
**What moving that bar costs is measured as of
2026-08-18: at 0.045 all three pages are refused the shrink and go 65,477 -> 195,785 bytes, `2.99x`
on those three pages, `1.76x` across the document's five picture-route pages, all of it tone
layers.** (That second figure is there because the first was published as a *document* total and is
not one — five of the ten pages are already 1-bit and pay nothing. Corrected the same day by the
review of the diff that measured it.) The seam is
`Flattener.textPageInkOutsideThresholdOverride` — `nil` in the app, substituting the guard's
comparand rather than its verdict — and `INKBAR=0.08 Tools/score-text-route.swift` prices any
document with it (**`INKBAR=0.045` was the command until the constant moved there; it now exits 2**,
because a bar equal to the shipped one has nothing to compare). **⛔ But measured over the corpus 2026-08-19, that `2.99x` is the BEST case and is
retracted as a corpus figure.** `Tools/sweep-ink-bar.py` (which landed the same day — resumable per
document, 71 `--self-test` checks, 42 mutants watched failing) swept 233 documents in **105.6 min,
`ok=233`**, and the result is committed as **`INKBAR-2026-08-19.tsv`**, 2,129 measured page rows. The
population question is answered: the band `[0.045, 0.08)` holds **17 pages and 16 of them flip** —
**0.75%** of sampled pages, **18.0%** of the 89 that are shrunk today, spread over **10 documents of
233**. Those 16 cost **838,569 -> 3,804,222 B, +2,965,653 B, `4.54x`, 185,353 B/page** — **4.3x worse
per page** than the three pages the entry priced, which turn out to be ranks 1, 3 and 4 of the 16 when
sorted by cost. Corpus-wide that is **+8.19%** of the layered bytes on the 181 pages reaching the
layering decision, and per document — over that document's own *priced* pages, not its whole page
count — **1.21x to 3.60x**. ⚠️ **The corpus-scale figure is `+0.55%`, and getting there needs the
STRATIFIED estimate, not the obvious one**: `sampleIndices` takes up to 12 pages a document whatever
its length, and a page in a fully-sampled (short) document is **4.8x** likelier to move than a page in
a long one, which hold 98% of the corpus. Pooling the rate says ~130 pages and ~+24 MB and is **6x
high, retracted**; per-document it is **~21 pages of 16,987 and ~4.0 MB**, of which **8 pages and
1,489,670 B are exact** because 86 documents were sampled completely. R49 and R50 state **no**
growth-tolerance bar
(read 2026-08-19), so there is nothing to test it against; R50 was accepted on "not one grew", and
this grows ten documents while barely moving the corpus. ⛔ **The population is known AND so is the
benefit, measured 2026-08-19 — sub-step (4) ran and the other 13 pages were rendered at both bars.**
`INKDUMP=<dir>` on `Tools/score-text-route.swift` writes both tone-layer pairs from the same
`mrcLayers` call the byte columns come from, and the stencil being byte-identical at both bars makes
the two backgrounds the entire difference. **11 of the 13 lose something**, and ⛔ **the dominant case
is NOT a drawing**: **7 of the 13 lose whole lines of prose or table data and an 8th (one of them also losing a signature, 2026-08-21) loses a hand-drawn mark outright — 8 losing content outright** (and the four C28 sub-steps rendered 2026-08-20 cover the whole population — 8 + 24 + 20 + 21 = 73 pages, 4 + 2 + 8 + 2 = 16 losing content — so **86 pages rendered across the campaign, 24 losing content, 18 of them type**) — `Xin Qu et al_2018`
p20 loses thirteen values out of a Pearson correlation matrix, `_1973_Committee Against Racism_` p4
loses seven lines of prose — ✅ **both re-measured independently 2026-08-20 by C28's 1/2 render and both
hold** (p20's thirteen are the matrix's LAST column at stencil ink `0.0000`; three of p4's lines read
`0.0000–0.0012` against 1.18x–1.19x on three lines below them) — words Vision did not box, cut from the stencil by `textRegionMask` and
then destroyed at 1/8. **That makes C26 an invariant-1 defect rather than the fidelity complaint it
was opened as**, and only `Riesman - 1954` p16 (a hand-drawn margin bracket broken into blobs)
reproduces its founding failure mode. ⛔ **And the dearest page of the 16 buys nothing** —
`RIESMAN_1942` p10, +702,280 B and **6.47x**, whose only non-stencil ink is a pale scanner-edge
strip; with `Riesman - 1954` p18 that is **32.4% of the band's byte cost on pages a reader cannot
tell apart.** ⚠️ Two verdicts read off whole-page difference maps were WRONG and were overturned by
1:1 crops plus an ink-outside-the-stencil map — `-auto-level` amplifies the harmless `fillHoles`
residue into what looks like legible text. ✅ **The decision was the owner's (R55's precedent) and he
took it at a 2026-08-19 check-in: 0.045, on the arithmetic that ~4.0 MB of corpus output is a cheap
price for not destroying words. It shipped the same day.** This sentence said the decision was
outstanding until then. Read the entry's last section before touching any of it.
**The corpus
sweep both entries were blocked on ran the same day** — 441 pages, 233 documents,
`THRESHOLD-LOSS-2026-08-18.tsv` — and it sizes the `extent` bar's population (61 picture-route
pages: 2 protected, 22 under the bar, 37 at zero, and the cluster under the bar is led by the
show-through document R56 was refused four times for), **which the next day's measurement showed
is not C26's population** — C26 turns on `inkOutsideText`, and the sweep of *that* is the separate
`INKBAR-2026-08-19.tsv` run described above — while
**not** sizing C27, because a mean saturation cannot see concentrated
colour and C27's own measurement was a saturated-pixel fraction no tool here printed. **⛔ One prints
it as of 2026-08-19 and C27's sweep RAN the same day** — `Flattener.saturatedFraction` behind
`Tools/score-threshold-loss.swift`'s `satFrac`/`satFloor` columns (`SATFLOOR=n`, default 0.25), out of
the same thumbnail `sat` comes from, with nothing shipped reading it. It reproduces the entry's own
50-DPI red-pixel count on all seven pages that count covers — **0.93x to 1.49x, median 1.12x, over a
range from 0.1% to 24%, at `SATFLOOR=0.15`** (at the default 0.25 the same seven read 0.42x–1.08x, so
the floor always travels with the ratio) — and the twelve pre-existing columns reproduce `THRESHOLD-LOSS-2026-08-18.tsv`
digit for digit, `sat` included, which is what says the walk it was refactored onto did not move
production's number. Three things came out of it that the entry did not have: the two pages it never
measured are in the same population (`p8` is third of the ten); **it has a noise floor ABOVE the
smallest real marks** — ⚠️ **and that floor is one page's, not a constant: corrected below, a 1938
magazine scan reads 2.0%** — a page with no spot colour on it reads ~0.5% at a 0.15 floor and ~0.12% at
0.25, which is why `p1` (0.1% red by hand) ranks *below* `p3` (none), so marks at half a percent of a
sheet are outside what the column can see and the floor is a printed parameter rather than a constant;
and ⛔ **the mean gates the ROUTE as well as the colour, so two of this document's 1-bit pages hold as
much saturated ink as its picture pages and a third nearly does** — C9's "the same number charged twice", which
makes "a fraction instead of a mean" cost bytes on pages nobody was complaining about. ⛔ **The
441-page corpus sweep then RAN, 2026-08-19, and it is `SATFRAC-2026-08-19.tsv`** — 233 documents,
12.2 min of measured time in one session (so the sizing guess held: no detached driver needed), every
document `rc=0`, and the twelve pre-existing columns reproduce the previous day's file digit for digit
over all 441 rows. **428 of 441 pages are published in grey because they fail the 0.06 mean bar (401
of them with nothing measurable to lose), and 10 pages in 7 documents of 233 carry as much saturated
ink as the page the owner watched lose real red ink** — ~220 pages of 16,987 stratified, of which
none is exact and 68% is one 300-page document, so the sampled count is the measurement. ⛔ **That 10
is bounded both ways and it is not the result.** Three things are: (1) the
mean **mis-orders** colour rather than under-counting it — 24 discarded pages hold more saturated ink
than the least-coloured page that keeps its colour, 6 of the 13 kept pages hold less than the
most-coloured page that loses it (1.6x–27x), 58 of 5,564 pairs inverted; (2) **eight of the ten were
dumped and read by eye** (the other two are the owner's own verdicts) and **three of the eight real
ones are colour photographs or illustrations on pages of type** rather than spot colour, so the harm
is wider than the entry was opened for while staying fidelity *on the pages looked at*; (3) **two of
the ten carry no ink of their own** — a 1938 magazine scan reads 2.0% from a page-wide cast the paper
correction left standing, 48x what another page of the same scan reads, and a 1941 typescript's 4.08%
is 88% photographed surround from outside the sheet. **So the noise floor is per-page, no bar on the
fraction separates the populations either, and the single locality test first proposed would rank
that scan-border page top of the corpus — two terms, not one.** R56's lesson in a second place.
What remains: those two terms measured separately, the byte price of keeping the colour, and
separating the one number that gates both `isPicture` and `shouldKeepColour`. ⚠️ And one instrument fact from that run:
`saturation(of:)` is **not a pure function of the page** — read cold it differs from read after a
full-resolution render of the same page (`1954 - Why` p7: 0.02831 vs 0.03033), production renders grey
first, and so must anything that wants to reproduce these numbers.
`C26`, `C27` and `C28` each
carry the numbers, the retractions and what is left. It is **not** R56 — that fix is intact and
works on the other
route. **`Tools/score-gate.swift` cannot see this class**, by its own source, so do not read a
green gate as covering it. **C24 is `FIXED`**, both halves. A page that draws no
XObject at all no longer takes another page's plate resolution (85 pages over 3 documents,
structural, no threshold, 0 route changes), and **the 45 pages that draw a *different*
image than the shared dictionary holds were closed the same day** — `rebuildDPI(of:)` applies
the shipped policy to `drawnLargestImage`, the corpus gate ran, and **exactly 45 pages of
16,987 change resolution**, page-for-page the 45 the earlier sweep named. Retention against
those pages' own embedded text is **+8 words of 3,025** over the 7 that have one; bytes fall
**25% / 81% / 3%** by document. Three things in that commit are worth knowing before you
touch this area. (a) **The gate's own instrument had to be repaired first**:
`score-drawn-images`'s `shippedRebuildDPI` column compared production against the drawn walk,
so once production *became* the drawn walk it would have read `same` on all 16,987 rows — a
tool measuring itself, §3 in a tool rather than in the shell. (b) **`score-routing` was
refusing rows for three documents, not the two this register kept saying**, and its "drift"
diagnostics were the *correct* per-page resolutions all along — it was refusing its own right
answers because production held a wrong one. (c) **One row is named as an unsettled
surprise**: `Sherman_1986` p1 moves 219 → 182 recognised words on a **0.38%** resolution
change, non-monotone (the 300 fallback reads 224, above both), with only 14 words of embedded
text so nothing can grade it. **`pageIsAnImage` was deliberately not wired** — 2 pages would
flip, and it feeds D1's corpus gate, which is R55's territory. **What led up to that close
is measured as of 2026-08-17** — read the entry's `C24b` and `C24's wiring` sections before
planning anything there: `Flattener.drawnLargestImage` and `Tools/score-drawn-images.swift` report
what a page actually draws, the 45 are **39 smaller and 6 wider** (which retires the
observation the entry carried without a cause — both walks pick by *area* and report
*width*), and the constant the entry wanted recalibrated faces **three** pages. **It gets all
three right, measured 2026-08-17, so the blocker is retired**: `Tools/score-rebuild-dpi.swift`
rendered `Batzell` p22 both ways and it retains **92.8%** of its own 291 words at 70.6 DPI
against **94.2%** at the 369.6 it accidentally gets today, for **87% fewer bytes** — so
"rendering a page of type at 70 DPI is C9 again" was reasoned and is **false**, corrected in
the four places it was published. Note too that *counting characters*, which the entry asked
for, reads **1,960–1,962 across every resolution from 70.6 to 369.6** — a 0.1% spread against
word retention's 1.4 points — so it would have said "no difference" while being right by
accident; word retention against the page's own embedded text is what moves. (This sentence
said a flat "1,961 at every resolution" until 2026-08-17; three of those six rows are 1,960 or
1,962, and `BUGS.md` had it right while the two summaries flattened it.)
**The override seam is mutation-tested as of 2026-08-17, and it found an ELEVENTH check that could
not fail** — read `BUGS.md`'s `### The override seam, mutated` before trusting that block. Both
mutants are killed, but the column that matters is *how many checks object*:
`logic/C24-override-nil-means-fallback` — `nil` from the closure read as "use the fallback"
rather than "no opinion about this page" — is killed by **exactly one** check, and that check did
not exist in `c8855f6`. Against the nine checks that commit shipped the count was **zero**, so the
nearer wrong reading would have survived while the register recorded the seam as pinned. The
fixture is why: the only page it declines is the one whose shipped answer already *is* the
fallback, so every row agreed with the wrong implementation by accident.
That was the last thing standing before the wiring, and the wiring closed the entry the same
day; its `C24's wiring` section is the gate run and the close. Read that
section's review subsection too — it found **a
tenth check that could not fail** and a bare form resolving its resource names in the page's
scope rather than its invoker's, and it is where to look before believing that
`CGPDFContentStreamGetResource` searches the parent chain: measured, it does not, after a
comment in this repo said it did. **The mutant campaign is done as of 2026-08-17 — all five
killed**, so none of those five checks is one that cannot fail; its `### The campaign`
subsection also records that `mutate.py`'s startup estimate was **4.85x** low (267 min
announced as 20-55; four documents rounded that to "4x", "five", "four" and "a factor of
four" before anyone divided it), that a mutation run's cost tracks **machine contention rather
than the suite's size**, and that two of `mutation-log.tsv`'s cheapest rows are `exit 133`
crashes rather than fast suites. **The estimate now reads the log and has a `--self-test`,
and it is still 4.22x low out of sample** — the campaign section's own "negative control"
was in-sample and is relabelled; read that before quoting the startup line as a forecast.
Its self-test's coverage figure is **21 of 26 mutations killed, measured** and re-derivable
from `SELFTEST-MUTANTS-2026-08-17.tsv`; it read "12 of 14" from reasoning for a few hours,
and one of the twelve it missed was another check unable to fail — and the review of the
fix caught a second, where `run` did not act on the guard the checks pinned. **R55 is `WONTFIX`** as of 2026-08-17: the measurement campaign was run and the
owner closed it on the arithmetic — the gate's over-exclusion costs the sweep about 80
candidates and 0.7 GB against 1,164 and ~10 GB, and loosening it would admit the hand-held
photographs D1 exists to keep out. **R56 and R57 —
the pale drawing erased and the tonal plate blobbed — are `FIXED` as of 2026-08-16** by a
shape signal in `Flattener`, on the sixth attempt and the second signal class; read both
entries before touching the routing, because four luminance rounds and two shape rounds
were refused before the one that worked, and the term that closed R56 is not a threshold
on how pale a mark is but on **where it is**. **C23 — the rebuilt copy displaying what the original's crop box
hid — is `FIXED`, and there is no release blocker.** Read its entry before touching the crop
box anywhere: the fix the entry itself proposed is wrong in two measured ways, the first fix
this project shipped for it gave up JBIG2 compression it did not have to, and the crop box now
goes on **after** the qpdf merge — where `--update-from-json` replaces a page object rather than
merging into one, which turned a 7,391-byte page into 391 bytes with `qpdf --check` calling it
healthy.
Read its header before planning anything. Update it in the same commit as any fix.
Dated measurement records live beside them — `CORPUS-2026-08-08.md`, `CORPUS-2026-08-09.md`,
`CORPUS-2026-08-15.md` + `.tsv` and `MRC-2026-08-15/`, plus the dated corpus sweeps
`THRESHOLD-LOSS-2026-08-18.tsv`, `INKBAR-2026-08-19.tsv` and `SATFRAC-2026-08-19.tsv` (this list had
omitted all three; the review of C27's sweep counted that as the third such omission), plus the
targeted `GUTTER-CENSUS-2026-08-20.tsv`, `SHAPETERM-PICTURES-2026-08-21.tsv`,
`SHAPETERM-73-2026-08-21.tsv` and `SHAPETERM-RIM-2026-08-21.tsv` — and are
evidence for one run, not
claims about the present. **The corpus is 230 scans, not 233**: `CORPUS-2026-08-15.md` is
the gate re-run after T17, and it names the two documents the app itself calls
born-digital.
[TODO.md](TODO.md) is decided-but-undone work, [FEATURES.md](FEATURES.md) is ideas
with their costs and the reasons some are parked,
[RESEARCH-2026-08-16.md](RESEARCH-2026-08-16.md) is what other tools do about the
problems this register keeps re-deriving — the extractor thresholds that bound
`reserveEms`, Tesseract's two-knob text layer, and the qpdf option C23 was refused
without reading —
[RESEARCH-shape-signals.md](RESEARCH-shape-signals.md) is the same question asked of
MRC segmentation, and it is the file that corrected the picture detector's analysis
resolution by 4x and established that **nobody separates a pale drawing from
show-through**, and
[REVIEW-2026-08-14.md](REVIEW-2026-08-14.md) is the standing record of a
whole-codebase review sweep, including findings not yet fixed and areas not yet
covered. **[HANDOFF-2026-08-17.md](HANDOFF-2026-08-17.md) is where to start** — it was written
when R56 and R57 had just closed and named `R55` and `C24` as what was left; `R55` is
`WONTFIX` and `C24` is `FIXED`, both on 2026-08-17, so the register is empty — then
[HANDOFF-2026-08-16.md](HANDOFF-2026-08-16.md), then
[HANDOFF-2026-08-15-night.md](HANDOFF-2026-08-15-night.md), then
[HANDOFF-2026-08-15-evening.md](HANDOFF-2026-08-15-evening.md), then
[HANDOFF-2026-08-15-day.md](HANDOFF-2026-08-15-day.md), which has the corrections this
project's own review document got wrong. ⛔ Its process note *"Work serially. Do not fan out
to subagents"* is **WITHDRAWN as of 2026-08-16.** Subagents are wanted: `Task`, `Agent` and
`Workflow` are all permitted, and an adversarial review agent over a finished diff before
committing is expected rather than optional. Ignore that paragraph wherever you meet it — in
that hand-off or any older one. The only remaining limit is the session's own budget, and
that every subagent must be told **not to run the suite**. Then
[HANDOFF-2026-08-15.md](HANDOFF-2026-08-15.md) for the twenty-three fixes that landed
overnight, and [HANDOFF-2026-08-14.md](HANDOFF-2026-08-14.md) for the original fix order
and what is deliberately withheld from release.

*(This paragraph read "nothing open" for a day after four entries were opened, which
is exactly the sentence a new reader trusts most. If you close or open an entry,
correct it here in the same commit — it is the only way this line has ever stayed true.)*

Install the hook once per clone:

```sh
git config core.hooksPath .githooks
```

## Commands

```sh
./build.sh            # build -> build/VisionOCR.app
./build.sh --install  # + install to /Applications
./run_tests.sh        # 1,200 checks measured 2026-08-21; 8-45 min depending on machine load, real OCR
                      # measured 474 s quiet -> 2,719 s under the C24b campaign. Never size a
                      # timeout off one sample: ops/autonomous/README.md keeps the ledger.
```

Never report a change as working without `./run_tests.sh` passing. Add a test that
fails without the fix.

## Invariants — breaking these has destroyed user content before

1. **Never lose content silently.** Every path that can drop a page, a line or a
   text layer must report it. Page count is not sufficient verification; a
   truncated-but-valid PDF opens fine. Prefer failing loudly over publishing
   something plausible.
2. **Build into scratch, publish only on success.** `makeSearchablePDF` stages
   output and moves it into place after verifying the page count. Never write
   directly to the user's destination — a cancel mid-write once overwrote a good
   file with a truncated one.
3. **The text layer must satisfy four properties at once**: word spacing survives
   extraction, runs don't overlap vertically, runs span the ink, and **runs keep
   a gap from the next fragment on their own line**. Each has been broken by a
   fix to another. Re-measure all of them after any change to `SearchableWriter`.
   The instruments were repaired in `BUGS.md` T14 — before that, **all four were
   compromised and the procedure would not run**. The procedure:

   ```sh
   Tools/make-observations <finished.pdf> obs.json   # produce the reference
   Tools/probe-line-edges  <finished.pdf> <page> obs.json
   Tools/probe-text-offset <finished.pdf> <page> obs.json
   Tools/score-corpus      <source.pdf> <label> [headroomFactor] [minimumVertical] [reserveEms]
   Tools/score-line-separation <source.pdf> <label> [same three]
   Tools/score-run-width   <source.pdf> <label> [--worst N] [--pages N]
   ```

   **There are three shells on one rect, and two instruments beside them.**
   `probe-line-edges` builds the same rect as `score-corpus`'s `start=`/`end=`
   columns, character for character, and agrees with them on 48 of 48 documents;
   it is kept because it *names* the lines that fail, and `score-corpus` only
   counts them. `probe-line-coverage` is a third shell on that same rect.
   Counting them as independent is how "four instruments" became a sentence
   nobody could act on.

   `score-line-separation` and `score-run-width` are the two that ask different
   questions. **`score-run-width` was added for R81** and is the only one that can
   see it: the rect asks whether *anything* is selectable at a line's right-hand
   end, and over a run drawn at 5% of its box the answer comes from the line
   above. It asks the writer instead — how wide it drew this run, and how much of
   the height it wanted the ceiling left it — over every fragment on the page.

   What each one is for, and what it used to get wrong:

   - `score-line-separation` — properties (a) and (b). Reports `merged=M/N`
     over adjacent visual-line pairs and a `runaway=` character share. It used to
     divide PDFKit *lines* by Vision *fragments*, which is not a percentage of
     anything: it read 35%–2533%, read **87% → 87%** across a change from no
     runaway line to a 2,139-character one, and read an identical 52% at two
     different `headroomFactor`s. Every figure it produced before T14 is void,
     including `HANDOFF.md`'s "modern print keeps 100%, 1920s-50s 87-93%".
   - `score-corpus` — properties (c) and (d) plus word retention. Its `words=`
     column always held. Its `off=` column did not: see the next bullet, and note
     that it now prints `SKIP` at exit 1 rather than `OK` over a document it
     measured nothing on.
   - `probe-text-offset` — where the runs sit relative to their boxes. It scanned
     upward from −1.2 and took the first hit, so it accepted the *lowest* step
     whose window still clipped the line's own glyphs. **This moved the median,
     not only the range as A6.1 recorded** — −0.10 → 0.00 on dense newsprint once
     the scan runs outward from zero. Every `off=` figure recorded before T14
     belongs to the old instrument.
   - `probe-line-edges` — the per-page drill-down that names failing lines. It
     read `pages[0].observations` whatever page it was given, so on page 2 of a
     real document it printed `line starts: 0/32` — a false *failure* — over a
     page holding five perfectly good lines.

   The fourth was found late and had been holding **by accident**. Vision splits
   one visual line into fragments side by side; nothing writes a space character
   between them, so PDFKit synthesises one from the geometric gap and stops
   below ~0.15 em. That gap existed only as slack left over from
   `minimumVertical` capping the font size — a constant chosen for something
   else. Widening runs to fix property three closed it, and words welded:
   `valuablestudy`. `reserveEms` now holds it open deliberately. Assume there is
   a fifth.
4. **`kCGPDFContextMediaBox` takes CFData, not NSValue.** An NSValue is silently
   ignored and every page inherits page 1's size.
5. **Test fixtures need ≥2 pages of differing size**, and at least one rotated
   page. Single-page fixtures are structurally blind to geometry bugs.

## Environment traps

- **Never run two suites at once, in any two worktrees.** `build/tests` has no
  bundle identifier, so `UserDefaults.standard` lands in a domain keyed by the
  process *name* — `~/Library/Preferences/tests.plist` — and **every worktree
  shares that one file**. A second suite's `resetPrefs()` removes every key and
  wipes the first one's settings mid-run. Measured: 882/883 → 877/879, two
  failures in the run-report block, because the other run cleared
  `writeRunReport` between this one setting it and the batch finishing.
  `Tools/mutate.py` says to stay sequential and blames *timing*; the real hazard
  is shared preferences, and it fails checks for reasons unrelated to load. This
  includes suites started by review agents you launched.
- **Backgrounded shell commands have essentially no `PATH`** — `basename`, `cut`,
  `timeout` fail silently and loops report bogus results. Use absolute paths.
- **A suite's log lags by up to 4 KB when redirected to a file** — `print` is
  fully buffered there, so `tail -f` looks stalled on a healthy run. Watch the
  process, not the log.
- **Watch for the suite with `pgrep -x tests`, not `pgrep -f build/tests`.** The
  `-f` form matches every *waiter* whose own command line contains the string,
  including itself, so a "is a suite running?" guard reports yes on a machine
  with no suite on it. Four such loops once sat waiting on each other while
  nothing ran, and the guard they fed refused to start the real run. The
  instrument was measuring itself — §3, in the shell rather than the code.
- **`nohup … &` reports success immediately** while the real work runs orphaned.
  Wait on the process; don't trust the exit code.
- Zotero locks `zotero.sqlite`; copy it before querying.
- Filenames here may contain non-breaking spaces (U+00A0). Glob, don't retype.
- The volume is case-insensitive: `tools/` and `Tools/` are the same directory.

## Verification discipline

When a measurement is surprising, suspect the instrument first. Several
"confirmed" findings in this project's history were artifacts: `difflib` autojunk
on repetitive text, a glob matching unrelated files, ImageMagick's `AE` exceeding
the pixel count, a probe counting short lines as failures. State plainly whether a
finding was verified by running code or only reasoned about.

Prefer editing with `Edit` over scripted text-slicing on source files. An
over-broad Python slice once deleted four functions from `Model.swift`; with no
version control at the time they had to be reconstructed from memory.

## Not committed

`testdocs/` — 1.2 GB of third-party copyrighted PDFs, 233 of them. `testdocs/manifest.tsv` and
`Tools/sample-zotero.py` let it be rebuilt from a Zotero library.

⚠️ **Two tools in `Tools/` WRITE `argv[2]`, so a glob could destroy a corpus document** —
`pdf-extract-pages testdocs/*/*.pdf` *would have* opened document 1, overwritten document 2,
dropped the other 231 paths silently and printed `extracted 0 pages` on exit 0. Nobody ran it:
it was latent, and the destruction was measured on scratch fixtures (**710,796 B -> 809 B**,
2026-08-20), never on the corpus. **`BUGS.md` T19 is `FIXED`**: both refuse now,
`Tools/fault-inject.sh argv_writers` holds the refusals, and `OVERWRITE=1` is how to mean it on
`pdf-extract-pages`. The **six** tools that read `argv[2..]` as a label or a page number
mis-measure rather than destroy and are still open as the queue's `argv-shape`.
