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
of 2026-08-20: `C27`, `C28`, `C29` and `C30`. `C26` is `FIXED`, and TWO of the four are `HALF FIXED` —
`C28` on 2026-08-22 when its shape term was WIRED into `pageIsAllText()`, and `C29` on 2026-08-25 when the
born-digital page stopped being rasterised.** `C30` is the owner's second JSTOR
finding and the widest of them: whole blocks of clean body text get no text layer, and all four of this
project's text-layer instruments count only the words Vision returned, so `words=100%` is silent about it.
⛔ **C30's FORK IS SETTLED ON THE BLOCK IT WAS OPENED ON as of 2026-08-22 — page 1's void is RECOGNISER
RECALL and not the writer** (`C30-FORK-2026-08-22.tsv`, adopted out of a stranded worktree): the published
layer holds **2,101** word boxes against **2,002** words in 235 observations from a fresh run, so
document-wide the writer publishes *more* than the recogniser returns, and the five named missing strings
read **0 in the observations and 0 in the published layer**. ✅ **AND PAGE 5, THE ONE EXCEPTION, IS
SETTLED THE SAME WAY AS OF 2026-08-23 — the fork is closed on the whole document and C30 is ONE
mechanism, not two** (`C30-PAGE5-2026-08-23.tsv`, `#### Page 5, settled 2026-08-23`). Three consecutive
whole-document recognitions are **byte-identical**, so run variance on this path is **0.0000** — which
also re-labels page 1's 0.0143, whose three members are three different *paths* (published, PDF-render,
PNG) and not three runs. The shipped output reproduces from today's build on all nine measure columns of
both pages. ⛔ **98 of page 5's 146-row gap is ONE 115-px observation whose entire text is the nonsense
word `ASSAME`** — remove it and the fresh page-5 `bareShare` goes 0.2470 → **0.3866** and the gap
0.1825 → **0.0429**, 2.995x page 1's rather than 12.729x, so `bareShare` credits a BOX and not a READING.
Only **46** rows, three lines, are a band where the layer is genuinely worse — the ceiling on BAND-VISIBLE
loss is three lines, not the ten this file used to say — ⛔ and it is only band-visible loss: at
`VOID_MIN_ROWS` 20 against a ~13-row line pitch, ONE dropped line raises no band, so scattered
single-line drops are not bounded at all — and the published layer holds a line
(`PROVIDING FACTS AND FIGURES FOR COLLECTIVE BARGAINING-THE`, verified at 1:1) that no fresh observation
contains **and whose words — `COLLECTIVE`, `BARGAINING`, `PROVIDING`, `FACTS`, `FIGURES`, `CONTROLLER` —
are absent from page 5's fresh text altogether**, so no regrouping and no hyphen join can produce it.
⛔ **Do NOT restate that as "a writer can only remove": the review of this diff refuted that maxim from
`SearchableWriter.swift:889-892`, where `joiningHyphenatedWords` rewrites an observation's text and may
take a word from the NEXT page.** The substring absence is what carries the claim, not the maxim.
⛔ **The finding worth more than the verdict: production
recognises `Flattener.flatten`'s REBUILT BITMAPS (`Model.swift:1919`/`:1922`; the bitmap arm is measured
to have run rather than `Recogniser.swift:141`'s render fallback, because `pdfimages` reads `jbig2` on
all six pages) while `make-observations`
recognises a plain render of the source page, so EVERY instrument C30 has used measures a different
image than the app does** — same 3307x4409 geometry, different pixels. ⚠️ Not claimed: that the writer
drops nothing (the pipeline's own observations were not captured; replicating the recognition step is the
`alltext-replica` mistake; and `deduplicated`, `SearchableWriter.swift:706-733`, is a removing path
nothing here measured), and "byte-identical" is three runs of one build on one machine.
⛔ **And the loss is a property of the IMAGE HANDED TO ONE REQUEST, not of the type**: over the
same pixels at the same 400 dpi, page 1's bottom half goes from **84.81% bare to 8.61% — 9.85x less —
purely by being its own request**, and the two halves return **1.88x** the words the whole page does.
⚠️ Three things it does NOT settle: no crop size is established as sufficient (recall keeps improving as the
request shrinks — a gradient, not a threshold), it is **one document and one page** for the scope
experiment, and the *why* is untested — if the mechanism is a working-resolution downscale inside
`VNRecognizeTextRequest` then **"render at a higher DPI" is refuted in advance** while tiling is not, and
`Recogniser` has no tiling seam. C30 stays **OPEN**: the fork is not the fix.
✅ **BUT IT HAS AN INSTRUMENT IN THE TREE AS OF 2026-08-25 — `Tools/score-text-voids.swift`, the tool
`#### What a fix has to satisfy` had asked for since 2026-08-22, and the first C30 measurement taken on the
pixels production actually recognises** (`BUGS.md` C30 `#### The instrument, in Tools/ as of 2026-08-25`,
`C30-VOIDS-2026-08-25.tsv`). Rows of ink divided by rows of ink no word box covers, so the numerator is
unreachable from the observation list and a page can fail it while `words=` reads 100% — group 5 of its
13-group `--self-test` is that property as a check rather than a claim. ⛔ **Quote the page-derived column,
never the shares**: `inkRows` reproduces `C30-FORK-2026-08-22.tsv`'s at **0.9913x-1.0007x on 6 of 6 pages**
across a different rasteriser and 4x the resolution, and page 1's longest inked-and-unboxed run is **683**
rows at 400 dpi = **170.75** at 100 dpi against the fork's **171**, this entry's founding headline through a
different image. The recognition-derived shares diverge **0.7767x-1.7077x**, and that divergence is C30's
own finding rather than a defect. ✅ **That it recognises PRODUCTION's image is measured, not architectural**:
its word count equals the published layer's box count **exactly on 4 of 6 pages** (296 / 445 / 279 / 421) and
the `make-observations` plain render's on **0 of 6**, off by 8 to 47 there. ⛔ **It also settled which definition the register has been quoting, off
the fork file's header rather than by inference**: that file's `bareShare` is `inkRowsInVoid / inkRows`,
which is this tool's `voidShare` and NOT its `bareShare` — the two files' names do not line up, so both
definitions are printed. ⛔ **And one thing does not port, measured: `Flattener.otsuThreshold` clamps to
`[90, 230]` and `artefact.py`'s does not**, so the shipped one reads 90 where the reference reads 0 on a
two-valued buffer — same argmax, the clamp is the whole difference, and the two select the same pixels only
*because* the buffer is bimodal, i.e. on a `.bilevel` page and not a `jpeg` one. ⚠️ Nothing in `Sources/`
moved and no page gained a text layer, and this measures a box's *presence* and never the string under it.
✅ **AND THE TILING CANDIDATE IS PRICED AS OF 2026-08-25, ON ALL SIX PAGES RATHER THAN ONE HALF OF ONE**
(`BUGS.md` C30 `#### The crop experiment, in Tools/ as of 2026-08-25`, `C30-TILES-2026-08-25.tsv`, 24 rows):
`TILES=n` runs the same page as `n` horizontal bands, each its own request, lifts the boxes back into the
page's frame and scores the union against the same ink with the same constants — so the fork's
**phenomenon** is reproducible from the tree for the first time. ⚠️ Not its headline: that was a *half-page*
figure (84.81% → 8.61%) and this tool has no half-page mode, so nobody can get those two numbers from it. Over the six pages the void goes **5,561 bare rows → 404 at
eight bands, 13.76x fewer**, **4 of 6** pages reading 0, words **2,080 → 3,577**. ⛔ **It is NOT monotone in
the band count and no band count is established as sufficient**: `TILES=4` is worse in aggregate than
`TILES=2` (2,487 against 1,663) and p3 reads **918 → 0 → 255 → 216** over 1/2/4/8, so "a gradient, not a
threshold" is too kind — it is not even ordered. ⚠️ On p6 at four bands the tiled arm returns **fewer**
observations than the whole page (49 against 50) while returning **more** words (511 against 421), so that
row is fewer boxes carrying more text and **not** "tiling loses boxes outright", which the review of this
diff refuted from the same row. ⛔ **The padding is a confound the row counts cannot see, and it is not small**: `coveredRows` pads every
box by 8 rows top and bottom, and the tiled arm has 175 more boxes, which bounds padding's share of the
5,157-row improvement at **54.3%** — so the row columns alone do not say the recovery is box extent.
✅ **What does is content**: words per observation is flat (8.63 whole against 8.60 at eight
bands), and the new `TILETEXT=<dir>` dump gives **752** distinct 4+-character tokens gained against **146**
lost, gained > lost on **6 of 6** pages, with `CONTROLLER` — one of the six words page 5's section names —
returned by the tiled arm and by no whole-page recognition. ⚠️ Two corrections it forces: five of those six
words ARE in the whole-page recognition of production's bitmap, so *"absent from page 5's fresh text
altogether"* is a fact about the **plain-render** path and not about the page; and ⛔ **dense clean synthetic
type does NOT reproduce the void** — three generated single-column pages at 400 dpi, **em** sizes
**41.7 / 33.3 / 27.8 px** giving line pitches of 52.1 / 40.0 / 31.9 against this document's ~52, so two of
the three are denser and the first is the same; `obsN` equal to the drawn line count on **3 of 3** and
`bareRows` **0** — so the fixture bullet's own prescription is refused and the
ingredient is unknown. ⚠️ Still not a fix: `Recogniser` has no tiling seam, a seam cuts the lines that
straddle it (so these are a floor on the benefit), whether the gain is the band's area or its shape is
untested (bands run 1.47:1 / 2.95:1 / 5.89:1 on page 1's 3307x4488 sheet and 1.50 / 3.00 / 6.00 on the
other five, which are 4409 tall), and the time cost of `n` requests a page is unmeasured. ⚠️ `TILES=1` is
blind to the remap — at one band the scale is 1.0 — so what pins that arithmetic is the tool's group 13 and
not the run-path control. `C29` is the owner's JSTOR finding — a
born-digital cover page rasterised and re-OCR'd because `hasDigitalText` votes per DOCUMENT and never
samples page 1 at all on a document of 5+ pages. ✅ **It has a FIXTURE as of 2026-08-23 and today's wrong
answer is PINNED** — `Tests/main.swift`'s `makeBornDigitalCoverPDF`, and `BUGS.md` C29
`#### The fixture, and today's answer PINNED`. The cover page reads **302** characters and
`pageIsAnImage` **false** while all eight scans clear the same 120-character bar, so **the character count
decides nothing** and the whole verdict rests on a sample of `[1, 3, 5, 7]`; over counts 1-400 index 0
appears only at **1, 2, 3 and 4**. ⛔ **The `PINNED` checks assert the WRONG answer on purpose** — a
fixture red on arrival refuses every later commit through the hook — so the routing change was the
**second of two commits**, and ⛔ **all four pins were re-worded when (A) landed and NOT ONE of the four
assertions moved** — the first two are about the pre-flight warning, which the routing never consults, and
the last two are about `flatten` called with no `passThrough` set, which is still the contract and is now the
negative control. The routing's evidence is new opt-in rows beside them plus a one-token sabotage. ⚠️ Not a complaint about `sampleIndices`: the suite's
existing "a partial sample skips page 1" check stays right, and the defect is deciding a per-page question
with a document-wide majority. ✅ **AND THE LOSS IS NO LONGER SILENT AS OF 2026-08-25 — the run report names
every born-digital page a rebuild rasterised** (`BUGS.md` C29 `#### The report, SHIPPED`; C28 question 5's
shape, closed the same way while its entry stayed open). `hasDigitalText(in:)` now votes through an
extracted `Flattener.pageHasDigitalText`, and the watch-it-fail run that cuts the raster term out of it reds
**two pre-existing `PINNED` checks** — which is the evidence the extraction is wired into the product and
not the dead duplicate `willRebuild`'s comment warns about. ⛔ **The population is 42 documents and 392
pages of 16,987, not the one this entry was opened on** (`C29-CORPUS-2026-08-25.tsv`), **28 of the 42 fire
on exactly one page** — and the dominant real shape is a **repository download sheet** (HeinOnline, SSOAR, a
library metadata cover) rather than JSTOR's, five firings read at 1:1 and all five true positives.
`hasDigitalText` reads **false on 38 of the 42**, so on those the report is the only thing that mentions it.
⛔ **The corpus also found a SECOND mechanism the entry did not have**: `Schwaller` is **167 born-digital
pages of 300 — a real majority — and still reads `false`**, because its four-page sample votes **2–2** and
`digital * 2 > sampled` is strict, so a tie loses; a genuinely mixed document therefore votes for the answer
that hides the defect. That is the tie-break's fault, not the sampling's, ⚠️ **it is still unfixed, and after
(A) it decides only the WARNING** — nothing about what gets rasterised. ⚠️ **That commit was the report and
NOT the fix**; the routing change was bigger than the queue's "one commit" assumed, because five `Tools/`
files read `RebuiltPage.Content` (four of them exhaustively) — ⛔ though its other reason,
"`JBIG2.assemble` cannot express a page with no image stream", turned out **not** to be the blocker.
✅ **THAT ROUTING HALF IS RE-SCOPED AS OF 2026-08-25, ON A MEASURED PREMISE** (`BUGS.md` C29
`#### The routing half, RE-SCOPED`): **`CGContext.drawPDFPage` copies a born-digital page into a new PDF with
its text intact character for character** — 302 chars, exact string equality, over **three** hops, against
**0** from the same helper's rasterising arm — so the Flate route can carry a passthrough page with the
operator `SearchableWriter.compose` already runs on every page it publishes (`SearchableWriter.swift:296`).
Four `ENGINE ASSUMPTION` checks pin it, and the one-token sabotage reds **exactly three of the four**
(`1256/1259`), the raster control staying green because it rasterises either way — predicted before the run.
⛔ **The JBIG2 sentence above is TRUE AND NOT THE BLOCKER**: the JBIG2 arm is guarded by
`encoded.count == bitmaps.count` (`Model.swift:2174-2175`) whose `else` at `:2376` **is** the Flate route, so
a mixed document falls back by arithmetic with no new guard. The blocker is `Recogniser`, which keys its work
list and its results by array position (`:146`, `:163`) and whose `imageURL(of:)` returns a non-optional URL
out of a two-case switch (`:336`). ⛔ **And the third `Content` case costs 20 sites that pattern-match the
enum, of which the 8 exhaustive `switch`es are the SAFE half** — but only **one** of the 12
`if case`/`guard case` sites is genuinely silent, `Tools/score-text-route.swift:713`, printing
`already 1-bit` for a passthrough page into a TSV this register quotes; **five of the twelve red at run
time**, and a draft's claim about `Tests/main.swift:3049`/`:5752` was refuted by the review of that diff
(`:5752` labels a third case *bilevel* and is a detail string printed only on failure; `:3049` feeds a
condition and goes red). ⛔ **Do NOT add a page-index field "to be safe": positional keying is CORRECT
today**, because `flatten` throws rather than skips and its only path to a short array, **given a
`pngDirectory`**, is a cancellation `Model` returns on — a field added before the commit that creates the gap
is a seam with no caller, the shape C28 rejected. ⛔ **And "skips the page" is not "records `[]`":**
`SearchableWriter.missingPages` is `byPage[$0] == nil` and a non-empty result **refuses the whole document**
(`Model.swift:2120`), while `byPage.values.allSatisfy(\.isEmpty)` (`:2151`) would print a false *"no text was
found"* on an all-passthrough document. So the routing half is **two** commits, (A) the Flate passthrough and
(B) the JBIG2 route. ⛔ **Quote
the byte DELTA, never the ratio** — 31,223 B on nine pages, 0.981x, against a first draft's 0.739x off a
3-page variant: the delta is one page's arm and the ratio is dominated by page count.
✅ **(A) SHIPPED 2026-08-25 AND C29 IS NOW `HALF FIXED` — the born-digital page is COPIED THROUGH and keeps
its exact text** (`BUGS.md` C29 `#### (A) SHIPPED`): a third `RebuiltPage.Content` case carrying no URL, a
`passThrough: Set<Int>` on `flatten`, and `makeSearchablePDF` asking `Flattener.digitalTextPages` **before**
the rebuild rather than after it, so one value both routes and reports. The fixture's cover page reads its
**302 characters, character for character equal to the source's**, where it read 0, and the eight
already-OCR'd scans are still rasterised. ⛔ **The defect that mattered was in `Recogniser` and not in
`flatten`**: it keyed results by position in the *image* list, so one page without a bitmap would have put
every later page's text one page out on a file whose page count is right — the work list now carries page
numbers, both arms (in-process **and** the helper's remap) are checked with a per-page witness in the
fixture's own ink, and a passthrough page is recorded as an **empty** entry rather than left absent.
`JBIG2.assemble` needed no change, exactly as the re-scope predicted. ⛔ **The decision to quote: `passThrough`
is DATA with a default of `[]`, not a predicate `flatten` evaluates itself** — so ~30 existing call sites in
`Tests/` and `Tools/`, and every committed measurement taken through one, are unchanged by construction; the
rejected option (deriving it inside `flatten`, which would need no argument in production) is more honest
about the wiring and has an unmeasured blast radius, because several test fixtures ARE vector-text pages with
no page-sized raster. ⚠️ **And that is the cost: no check can see the literal argument at `Model`'s call
site** — a build that computed the set and passed `[]` would be green, since nothing runs a document
end-to-end through `makeSearchablePDF` (the queue's `mrc-endtoend`, and the same gap the report's own
channel-to-report wiring has). ⛔ **Two things (A) does NOT reach**: **(B)**, whose byte cost is still
unmeasured and which also discards a whole `jbig2enc` pass the `onPage` closure already paid for; and the
**120-character bar**, under which a short born-digital page is still rasterised and is now named by
**neither** report line — the routing was supposed to make that trade measurable and it is not measured.
⚠️ Rotation is measured for /Rotate 90 only, the crop box is a code-identity argument rather than a
measurement, and none of the corpus's 42 affected documents has been run through a passthrough. ⚠️ One
further limit carried forward: an
*already-OCR'd* scan's text layer is also replaced and deliberately is **not** reported, which is a
judgement made in the quiet direction. ⚠️ One instrument trap came out of the fixture commit:
`Flattener.flatten`'s returned array
is appended to only inside `if let pngDirectory`, so a call without one rebuilds every page and returns
`[]` — read the destination document, not `pages.count`. `C26` and `C27` were found on one document after
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
the pages were still degraded — ⚠️ but as of **2026-08-22 all five of its questions
are MEASURED** (question 2 closed 2026-08-21; question 4's last seam priced 2026-08-22), so what was left
of this entry was **the decision and the wiring**, not another measurement.
✅ **BOTH WERE TAKEN 2026-08-22 AND C28 IS NOW `HALF FIXED`** — read `#### THE DECISION` and
`#### The wiring, SHIPPED` before touching any of it. The shape term is a **third refusal condition in
`pageIsAllText()`**, after the ink fraction and the pale-drawing terms, so it is only ever evaluated on
the pages that would otherwise be shrunk 8x. ⛔ **The seam is the LAYERING one and the argument is the
DIRECTION OF FAILURE, not the price**: `bgFactor = allText ? max(caller, 8) : caller`, so a term that
only ever makes the verdict false can only ever store a page at *more* resolution — its worst case is
bytes and it cannot lose content on any page at any setting. The 1,020x cheaper stencil widening was
**rejected** for failing the other way in three measured directions (R57's blob on `Wilcox` p2's pen
ornament on a page that loses nothing; **50.03%** of the protection rather than all of it; and it
*lowers* `inkOutsideText`, pushing every page toward the very all-text verdict it is meant to fix), and
the `lineN >= 1 AND rim1N >= 1` conjunction was rejected as post-hoc whose only benefit here is bytes on
two pages that lose nothing. ⛔ **The negative control is what to quote**: two binaries differing in
exactly the third term put the fixture's background at **153 px against a ceiling of 154** without it and
**612 px** with it, and the same PDF with one more word box reads **153 / shrunk on both** — so the flip
is the term's, not the fixture leaving the all-text class. ⚠️ **What keeps it OPEN**: it rescues **13 of
the 16** measured losses and leaves three hand-made marks, one of which (`_1939_Former students` p2,
`outPx` **0**) no value of any constant here can reach, because the page-wide Otsu is blind to pale
pencil upstream of the map. It buys **no searchability** — the words are still not in the text layer,
which is `C30`'s ground. ⛔ **And two things it does NOT claim.** (1) The mutant campaign was **not
run**: three mutants were added (catalogue 97 → **100**, all three verified APPLIED, not NOT-APPLIED)
and a scoped run was a baseline suite plus 44-58 min a mutant. ✅ **ALL THREE HAVE NOW BEEN RUN AND ALL
THREE ARE `killed`** — `const/shapeRunHigh` and `logic/C28-alltext-ignores-shape` on 2026-08-23, and
`const/lineMinimumMembers` on 2026-08-24 by **five** checks — the only kill in the log that reaches C28's
term *and* its wiring (⚠️ **not** the widest, which a first draft claimed and this diff's own sweep
refuted: `logic/C24-unknown-is-not-no` announces six): the term's two counts go 1 → 0 and the wiring's three
`FAIL` lines are byte-identical to `alltext-ignores-shape`'s, the two arriving from the two ends of
`return groups == 0` (`#### lineMinimumMembers RUN through mutate.py`). ⚠️ **No mutant asks the LOWERING
direction and it is unmeasured** — lowering is the two-sided trade this entry keeps naming, `lineGapFactor`
has no catalogue entry at all, and a draft of this claimed the run "pins the constant only upward", which
overstates what a raising mutant establishes. ⛔ **And that run retires the estimator claim three sessions
published: 479 s against a startup line reading "roughly 100-116 minutes", 14.5x HIGH**, because
`estimate_minutes` spans the five newest log rows and all five were clamped-era **when it printed that
line** — the mirror of C24b's 4.22x-low reading. ⚠️ It does **not** self-heal gradually: the high end is
`max(window)`, so it stays put until the last clamped row leaves: with this run's own row in the window it
already prints **8-116**, and over the next FOUR scoped runs the high end reads **116 / 114 / 114 / 8** — the
drop lands ON the fourth, not after it (measured twice, by driving `estimate_minutes` over the log with
post-clamp rows appended; a draft wrote the sequence as 116/116/114/114 in a sentence that framed it as the
next four, which implies five). Deliberately not patched. ⛔ **THE FOUR-RUN FORM HOLDS ONLY FOR ONE-MUTANT
RUNS, BECAUSE THE HEALING IS COUNTED IN ROWS, corrected 2026-08-25**: `ESTIMATE_SAMPLE` is 5 rows, not 5
runs, so the two-mutant `depth-cap` run aged **two** clamped rows at once and the window is already
`[3407, 3415, 246, 227, 244]` — the next 1-mutant run prints ~`8-114`, the high end reaches single digits
after **two more mutant rows**, and the drop therefore lands on the THIRD run from there rather than the
fourth. ⚠️ Sooner, not later: a draft called the published sequence "one run short", which is the wrong
direction. That run read **14.8x** high (`12-174` printed, **705 s** measured), the third reading of this
estimator and the second in the same direction; ⚠️ its LOW end came within 5%, which is new but is **not**
evidence the window has healed — that figure was printed from the *pre-run* window, whose one post-clamp
row happened to be the `min`. ⛔ **Using the tool also found the SIBLING of the truncation
defect the run before it fixed**: `run()` capped the objecting-check *list* at `fails[:3]`, so a row killed
by five named three, and it was already live — **five earlier rows had lost 10 names** (the count was right
in all five, so no number in the log is wrong; which checks is what is gone, and none of the 10 is
recoverable from the tree). `killed_detail` keeps them all; two self-test checks, 36 → **38**, both watched
failing at `[:3]` and the second also at a merely raised `[:6]`. (2) **No corpus sweep was re-run**, so
"12 of 12 type-losers" is still the tool's 2026-08-21 figure — what is new is a **port check**:
`Tools/score-shape-term.swift` now calls the shipped `Flattener.textLineGroupsOutsideText` on its own
surfaces on every measured page, prints `port agreed on N` and **exits 7** on disagreement, because every
figure C28 published came from the tool's copy and what ships is a port. ✅ **It was RUN on corpus pages
and reads `port agreed on 5`** — `Jones et al_2010` p2/p3/p5/p7/p9, the term firing on three of them, and
`lineN` reproducing `SHAPETERM-73-2026-08-21.tsv` digit for digit (**1 / 0 / 4 / 3 / 0**), so the tool has
not drifted either. ⚠️ Five pages of 73, in one document. ⚠️ That check's `--self-test`
half **could not fail** in its first version — it reused a fixture whose single out-of-region block can
never reach `lineMinimumMembers`, so both copies read 0 and agreed trivially, and a port sabotaged to
`return 0` passed the whole self-test. Found by building the sabotage and running it (CONTRIBUTING 4a);
it has its own five-mark fixture now and the sabotage goes red. That is the tenth check in this
project's history that could not fail.
✅ **THE OWED FIXTURE EXISTS AS OF 2026-08-22 AND `shapeRunHigh` IS NO LONGER A KNOWN SURVIVOR** — read
`#### The owed fixture`. Nothing shipped moves; this is `Tests/main.swift`, `Tools/mutate.py` and two
comments. Every non-type-shaped fixture the suite had was **one 8-connected component**, and one
component can never reach `lineMinimumMembers` = 4, so the **grouping** was doing all the refusing and the
constant read the same at every value — which is why `mutate.py` carried it saying so and naming the
fixture it wanted (*"four short solid dashes on a baseline"*). Three now exist, calibrated at an asserted
`glyphHeight` **25.0** / `glyphRun` **5.0**: four 5x30 strokes are **1 group** (the positive control), four
20x30 are **0** (`shapeRunHigh`), four 5x120 are **0** (`shapeHeightHigh`, added to the catalogue, 100 →
**101**). ⛔ **The pair to quote is the two refusals carrying the SAME out-of-region ink by construction**
— 4x20x30 and 4x5x120 are both 2,400 px, both `inkOut` 0.0205 — **while the control that fires has a
quarter of it**, so nothing about quantity separates the refused pages and quantity is *inverted* against
the one that fires. ✅ **Both mutants were watched failing and each fixture is attributable to ONE
constant**: at `shapeRunHigh` = 99.0 the wide one goes 0 → 1 and the tall one stays 0; at
`shapeHeightHigh` = 99.0 the reverse. ⛔ **"Watched failing" there was a BINARY, not a red check**: at the
time neither had been run through `mutate.py` (a scoped run is a baseline suite plus ~45 min a mutant), the
probe carried its own copy of **both** the fixture builder and the surface construction, and `mutate.py`'s
`--self-test` never touches `CONSTANTS` — so what the suite adds is that the type scale and all three
`inkOut` values are asserted **in bands**, and a geometry that drifted away from the probe's reports
itself.
✅ **`shapeRunHigh` IS A RED CHECK AS OF 2026-08-23 — RUN through `mutate.py` and `killed`, 3,475 s,
`1246/1247 passed`, by EXACTLY ONE `FAIL` line** (`#### shapeRunHigh RUN through mutate.py`;
`Tools/mutation-log.tsv`). ⛔ **The one is the point, not the kill**: that single objecting check did not
exist before `6d0caa1`, committed 00:10:53 the SAME day, which is what "known survivor" meant — the same
shape as C24's override seam, read the other way round. ⛔ **Its claimed GREEN yield was three checks and
is PART-RETRACTED as of 2026-08-24 down to one** — the too-tall check could not move (5-px bars, `medianRun`
5, already under the shipped bar of 10; it stays refused by its height at both values) and `c28GroupsBar` is
still refused by the *shape* rule at a bar of 495, so neither says what it was credited with; only
**`c28GroupsC26`** does, its `medianRun` 30 being accepted at 99.0 so that `lineMinimumMembers` is what
refuses it. The pair's attribution is unharmed — it rests on the two **reds**, this run's and 2026-08-24's,
not on a green. ⛔ **A THIRD was drafted and RETRACTED by the review of that diff, and it is the
lesson**: the calibration check's green is NOT evidence, because `c28Calibration` never reads this
constant — it enters that check only through the detail string — so the row was an eleventh check that
could not fail, written into the section about the tenth. ✅ **`shapeHeightHigh` IS A RED CHECK TOO AS OF
2026-08-24, so the pair is measured from the suite's side in BOTH directions and nothing in the owed-fixture
material is probe-only** (`#### shapeHeightHigh RUN through mutate.py`): `3.0` → `99.0` is `killed`,
**3,415 s**, `1246/1247 passed`, by **exactly one** `FAIL` — the too-tall fixture's — while the too-wide
check stays green, which is the mirror image of `shapeRunHigh`'s run. Six catalogued-and-never-run mutants
→ **five**, → **four** with the wiring mutant below, → **three** with this one, → **two** with
`const/lineMinimumMembers` on 2026-08-24, → **ZERO** with `depth-cap`'s pair on 2026-08-25 (C24
`#### Both caps RUN through mutate.py`) — so that six is fully discharged. ⚠️ It was never the census:
**25** catalogue entries still have no row at all, and they are the queue's `mutants-never-run` as of the
same day.
⛔ **It has NO informative green either, and the review of its own diff RETRACTED both the run had claimed
in advance — this is the lesson of the third scoped run and it corrects the FIRST as well** (the second,
`alltext-ignores-shape`, claimed no green yield at all). The test a green
must pass is not "could this check move in principle" but **"does the mutant change this check's input at
all"**. A monotonicity argument answers only the first: `shapeHeightHigh` has one call site and is absent
from the calibration filter, so the *accepted set* is monotone in it, and `textLines`' greedy `minY`
banding off each band's **last** member does make the group **count** non-monotone — but raising the
ceiling from `3 × glyphHeight` = **75 px** to **2,475 px** can only admit a component taller than 75 px,
and on both fixtures credited (four 20×30 and four 5×30) every component is **30 px** tall and the map is
nothing but those bars. Identical input, identical count, cannot fail. ⛔ **And the same argument
part-retracts the run above**: of the three greens it credited, the too-tall check could not move (its
bars' `medianRun` 5 was already under the shipped bar of 10) and `c28GroupsBar` is still refused by the
*shape* rule at 99.0, so only **`c28GroupsC26`** ever showed the grouping refusing anything —
`Tests/main.swift:2270-2275` said so before either run. ⚠️ **What survives both retractions**: the kills,
the objecting-check counts, the costs, and the attribution, which rests on the two **reds** across two
runs and never needed a green. Two greens are worth naming as unable to fail: `c28Calibration` again, and
the border check, whose 900-px bar would clear the 2,475-px ceiling but is refused twice upstream — by
`interiorWindow` and the term's `guard outside > 0`, and by a `medianRun` of 40 against a run bar of 10. ⛔ **And the run's own fix**: `Tests/main.swift` carried *"This one is not about the
term at all… Nothing the shape rule does can make it red"* on the line **after** the check the run measured
as the sole killer — true of the ink check below it, false of the one above — so the sentence now names its
check. The runs' own output is NOT in the tree
(`Tools/mutation-out/` is gitignored and overwritten per run, so the quoted `FAIL` line is the durable
copy), and the estimator's high end held this time (**6,541 s** lock-measured against "budget the 115") —
and on the two scoped runs after it, **6,463 s** and **6,567 s**, so it held **three times running**.
⛔ **THE FOURTH BROKE IT IN THE OTHER DIRECTION AND "three times running" IS NO LONGER THE CLAIM TO QUOTE**:
`const/lineMinimumMembers`, 2026-08-24, took **479 s** against a startup line reading "roughly 100-116
minutes" — **14.5x HIGH** — because `1dbaafd` removed the 16.2x clamp while the estimator's window was still
five clamped-era rows. So the estimator has now been **4.22x low** (C24b) and **14.5x high** (this) off the
same five-row window: a rate read off history is wrong in whichever direction history has just moved, and
the tool's own rule — read the startup line, never a figure in prose — is what both failures argue for.
It self-heals as post-clamp ROWS push the clamped ones out of its five-row
window — not as *runs* pass, since a two-mutant run ages two at once — and was deliberately not patched.
✅ **AND THE WIRING ITSELF IS A RED CHECK AS OF 2026-08-23 — `logic/C28-alltext-ignores-shape` RUN and
`killed`, 3,407 s, `1244/1247 passed`, by EXACTLY THREE `FAIL` lines** (`#### C28-alltext-ignores-shape RUN
through mutate.py`). All three checks were added by `fbf6d87`, the commit
that shipped the wiring — where `shapeRunHigh`'s arrived a commit later and C24's seam had none — ⛔ **but a
draft called that "the headline" and the review of it refuted the framing: a mutant planting back the defect
a commit fixed is killed by that commit's checks BY CONSTRUCTION, because CONTRIBUTING requires the failing
test first.** ⛔ **And do not quote the `153 wide of 1224, ceiling 154` as the probe and the suite agreeing
about the term** — 153 is `1224 / textPageBackgroundDownsample` and the ceiling is that plus one, so any
shrunk page of that width prints the pair; the mutant's applied-ness is instead measured from the compiler
(`'groups' was never used`). ⛔ **It has NO
green yield, said in advance rather than retracted afterwards**: `return true` is one-sided, so the only
checks it can falsify are those asserting a page reaching term 3 is not all text, and the two that look
most like yield cannot fail — the `inkOutsideText` assertion (that field is assigned *before* term 1's
guard, verified by reading the source) and the positive control (the mutant forces what it asserts, so the
pair's own guard is never exercised). ⚠️ All three failures sit on **one** fixture, and the universal over
the other 1,244 is an argument with the near misses read, not an inspection — "did not fail", not "cannot".
⛔ **And the run found a
defect in `mutate.py` by using it**: the row recorded the first check as the bare tag `C28`, because `run()`
split each `FAIL` line at the **first** `" — "` — a separator inside **38 of 1,236** check descriptions —
damaging **7 of the log's 83 rows** (a first draft said 2, from a detector that could only see a truncation
leaving a bare tag). ⛔ **`FAIL a — b` is AMBIGUOUS, so the fix is to keep the whole line and not to split
at all**; the draft's `rsplit` was refuted from two real call sites. Six self-test checks (30 → **36**), the
first three measured mutually redundant and recorded as such, **both rejected parses watched failing**; this
run's row repaired byte-identically to what the fixed tool writes, the other six not repairable. Sibling
sweep: nothing else splits on that separator. ⛔ **But that sweep asked about the SPLIT and not about the
FIELD, and the field had a second truncation — found 2026-08-24 by the next run**: `run()` also capped the
objecting-check *list* at `fails[:3]`, so a row killed by five named three. Already live, swept over all
**84** rows: **five earlier rows lost 10 names** (`A4.2-update-url-scheme`, `R82-reserve-taller-scale`,
`R23-copyOutline-bound`, `C24-unknown-is-not-no`, `C24-override-ignored`). ✅ The COUNT is right in every
one, so each row states its own incompleteness and no number in the log is wrong; which checks is what is
gone, and none of the 10 is recoverable from the tree. `killed_detail` keeps them all; **two** self-test
checks (36 → **38**), both watched failing at `[:3]` and the second also at a merely raised `[:6]`, which
is what makes it non-redundant.
⚠️ The calibration check is a **mirror** of the term's own calibration step: it pins the fixture
and is blind to a change in the calibration itself, which is `interiorWindow`'s recorded hazard with its
remedy unavailable (the term does not expose what it calibrated on).
✅ **AND THE SIBLING WAS FIXED IN THE SAME COMMIT — it is the sharper of the two.**
`Tools/score-shape-term.swift`'s **port check**, the gate comparing its copy of the five functions against
the shipped ones on every measured page, had a fixture of five 3x10 marks against a 3x10 calibration — the
**middle** of every band — so loosening the tool's own `shapeRunHigh`, `shapeHeightHigh` or
`shapeHeightLow` left both copies at one group and the self-test passed over a drifted port, in the file
every published C28 figure came from. **Three** refused baselines were added, one per constant (four 8x10
on run, four 3x36 on the height ceiling, four 3x3 on the floor) plus **two complementary guards** — the
group count pinned at exactly **1** and the map's component count at **17**. ⛔ Both, because neither
catches the other's failure: the count is blind to a baseline clipped from an end (still four components)
and the exact-1 is what catches a baseline that started being *accepted*. A first draft had `< 1` and 13
and the second review refuted both from a worked example. ✅ Run **four** ways: shipped
`self-test ok (10 checks)`, exit 0; the tool's `shapeRunHigh` = 99.0, `shapeHeightHigh` = 99.0 and
`shapeHeightLow` = 0.0 each exit **5** on a port divergence. All three passed before. ⚠️ The printed count
stays **10** on purpose — the guards went inside group 10, and that literal counts groups. ✅ **And `score-mrc`'s `--self-test`, named as the
sharpest thing owed because it asserts this same verdict on a real-Vision-boxes fixture and is gated by
nothing, is GREEN** — measured, exit 0. ⛔ **But green by CONSTRUCTION, not by measurement**:
`selftest-alltext`'s `inkOutsideText` is **exactly 0.0**, so the term's own `guard outside > 0` answers 0
before it labels anything and cannot change at any value of any of the five constants. That fixture pins
the guard's FIRST term, is silent about the second, and is blind to the third. ⚠️ `shapeMinimumArea` stays
unpinned on a **narrower** argument than a first draft of this gave: at its shipped value, in
`textShaped`, an 8-connected component's area is at least its height and the height test already demands
`h ≥ shapeHeightLow * glyphHeight`, so above a median glyph of **8 px** the area guard is satisfied before
it is asked — but that is conditional on the 8 px (72-DPI corpus scans can fall under it), it says nothing
about *raising* the constant, and the constant is separately live in the term's **calibration** filter,
which these fixtures do run through, so whether they would kill such a mutant is **unmeasured**.
⛔ **THAT COMMIT LANDED AS `6d0caa1` ON 2026-08-23, SUITE `1,223/1,223`, AND THE ADVERSARIAL REVIEW OF ITS
OWN DIFF REFUTED THREE OF ITS CLAIMS — one of them a real defect that is now the queue's
`alltext-replica`.** ⛔ **The sibling sweep said "two answers, both addressed" and there were THREE**:
`Tools/score-text-route.swift:678` replicated `pageIsAllText()` with **two terms against the shipped
guard's three**, so the instrument read `all-text` on exactly the sub-bar pages the wired shape term
refuses — **wrong in the direction that HIDES C28**, and `sweep-ink-bar.py` inherited it. ⚠️ No published
figure moves (every committed TSV pre-dates the wiring), and it was the **third** repair of that one `let`.
✅ **FIXED 2026-08-23, AND THE THIRD REPAIR IS NOT A THIRD CLAUSE — the tool reads
`Flattener.MRCLayers.shrunkAsAllText` back instead of deciding for itself; read `#### The replica retired`.**
The replica survives only as the answer on a page that never layered and as a cross-check whose
disagreement the run prints. ⛔ **Measured on `Ford_1941_Speech_.pdf`, all six sampled pages, two binaries
differing in exactly this tool: p6 goes `all-text` → `picture` and p1–p5 do not move**, and `verdict` is
the only one of the thirteen fields that differs on any row — the label moved and nothing else, because the
bytes were always production's. ⚠️ Do not call that "twelve columns": `page` is the row key and three bar
columns are the literal `-` with no `INKBAR` set, so **eight carry information**, and there are three bar
columns rather than four. The flip is term 3's alone, from the row's own columns (`inkOut` 0.0056 against a
bar of 0.045, `extent` 0.01498 against 0.05). ⚠️ p1 is the sharper control: it is labelled `loses` too and
does **not** move, because its loss is a hand-made mark at `lineN` 0. ⛔ **The aggregate was the larger
lie**: `6 of them read all-text: layered 436,633 B` → `5 … 224,977 B`, so **211,656 B — 48.5%** — belonged
to a page production does not shrink, in the summary line `Tools/README.md` points at as pricing TODO item
1 (⚠️ whose own cited 8.2 KB/page that cell already records as unreproducible, C25). ⚠️ **48.5% is a
six-page sample's number, not the corpus's** — the un-shrunk page necessarily dominates such an aggregate —
and no corpus version exists. ⛔ **And the priced-bar per-page cost was out by exactly 2x while the row
beside it said otherwise**: `INKBAR=0.0005` over p4/p6 read `2 of 2 … 100,626 B/page` and now reads `1 of
2 … 201,252 B/page`, because p6 is `picture` at both bars and its own `barDelta` printed `same` in the same
output, so one unchanged delta was divided by two pages instead of one. ⚠️ A draft said "out by 3.2x" from
5.76/1.79; the review refused it as a ratio of ratios over two different sets. The absolute delta is
identical (+201,252 B) — `layeredAtBar` was always production's bytes. ✅ A six-row `layeringVerdict` table
exits **5**, was watched failing against a sabotage of its second `return` (the `nil` guard left intact),
and asserts its own case count; ⛔ **but it pins the RESOLVER and not the column — reintroduce the
historical defect at the call site and all six rows still pass**, which is said in place rather than
papered over, and nothing in the suite can catch a fourth drift. ⚠️ **The `REPLICA-DISAGREES` tripwire is
now noisy on C28's own population** — the replica cannot mirror the shape term, so a disagreement is
*expected* on the 16 of 73, and a first draft offered one such firing as proof the dead-seam detector
survived when the override was demonstrably alive in that run; the new `VERDICT` / `VERDICT-AT-BAR` stderr
lines are what tell the two apart. It also had to be deliberately kept on the replica's own pair or it
would have compared production with itself. ✅ Sibling sweep: nobody else replicates the guard —
`score-mrc` asserts the constant on fixtures and already reads production's factor back,
`score-threshold-loss` says outright it cannot print this verdict, `score-shape-term`'s `verdict` is a
status string, and `sweep-ink-bar.py` only consumes the column (`--self-test` run, 71 checks green — a
no-op control, since the diff does not touch it), which is why the divergence goes to stderr and to the
prose summary rather than into the field it matches with an exact `== "all-text"`: verified by reading that
parser, which breaks at the first blank line and reads stderr only on the config exits.
The other two are prose: the 3 × 3 baseline is **not** in the rim check's scene (that check has
its own `rimMap`; the real cause is its own 2 × 6 stubs shrinking to 2 × 3 under the r=3 collar), and the
below-bar check is **not** a reachability guard (every new check reaches the shipped code directly —
three through `c28Groups`, three through `c28InkOut`, one through `c28Calibration` — so
`pageIsAllText()`'s term 1 gates nothing and what the check buys is fixture realism).
✅ **BOTH CODE COMMENTS ARE CORRECTED AS OF 2026-08-23 — the queue's `c28-comment-fixes` landed, so the
register and the comments agree again — AND IT WAS SIX CLAIMS RATHER THAN THREE**, seven if the header's
two retracted figures are counted apart. The three the review had named, plus three the sibling sweep found
in `BUGS.md` and `2de4e50` had not reached. The first of those three: it said a larger `mrcBoxPadding`
"would split each bar in two", where the mechanism is **truncation** (the padded region grows down onto
the bar's top and can never be strictly inside a bar running on to row 1383). A third code comment went
with them —
`Tests/main.swift`'s "at 5 × 200 the bar starts three rows INSIDE the region", which is the wrong direction
and cannot be the mechanism, since a bar starting inside could only be truncated and never split. The row
ranges are now derived in place rather than asserted (bars land in top-down rows `[1384 − h, 1384)`, so
1264 at h=120 and **1184** at h=200 against a padded region of 1187-1259), and ⛔ **the corrected rim
mechanism is MEASURED rather than reasoned**: three binaries one `let` apart put the rim failure on the rim
scene's own stubs with the 3 × 3 baseline emptied out. The other two the sweep found are both in
`BUGS.md`: its **file header** still carried two of `#### The replica retired`'s retracted draft figures
("twelve other columns", where eight carry information, and "out by 3.2x", where the per-page cost is out
by exactly 2x) — the load-bearing summary stale while three other copies, this file among them, were
right — and its own account of the reachability claim said "all seven checks call
`textLineGroupsOutsideText` through `c28Groups`", which is loose in exactly the place that claim is about.
⚠️ **The review of this diff refuted two of its own corrections**: "the fourth instance in this section"
was a claim ordinal masquerading as an instance count (there are **two**, both fixed), and the follow-up
that missed them is `2de4e50` on **2026-08-23**, not 2026-08-22 — the text it missed did not exist until
`6d0caa1` the same morning. Comment- and document-only: nothing shipped moves and no check was added or
removed.
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
⛔ **the rim columns had not been run on a picture page.**
⛔ **THAT RUN HAPPENED 2026-08-21 AND THE COLLAR DOES NOT MOVE A SINGLE COUNT ON A PICTURE PAGE** —
`SHAPETERM-PICTURES-RIM-2026-08-21.tsv`, the same ten pages and constants, from the same binary as the
73-page rim sweep, with all **23** shared columns plus `verdict` byte-identical to
`SHAPETERM-PICTURES-2026-08-21.tsv` on **11 of 11** rows (⚠️ and that file came from a binary with **no
rim sweep in it at all**, which is what makes this additivity control span a real code change — so
"the same binary" is exactly what it is *not*). `rim1N == rim2N == rim3N == lineN` on **10 of 10** pages
and the **largest** accepted-line rect is identical at every radius (⚠️ the tool prints one rect per
page, the largest by area; on `Wilcox` p2 a non-largest group did change), so **`lineN >= 1 AND
rim1N >= 1` fires on the same 6 of 10** the shipped r=0 rule does: **zero** of the five picture false
positives removed, and the two false negatives on `1954 - Why` p6/p7 (cartoons whose destruction C26
measured) unchanged at 0. A 3-px collar removes **4 accepted-line pixels of 16,294 — 0.02% — and all
four are on one page** (`Wilcox` p2, 1,694 → 1,690). ⚠️ **What "10 of 10" carries**: four of the ten
read `lineN` 0, where a collar can only be tested for *manufacture*, so the removal question is asked
on the six that fire and exactly one of those six moves.
⛔ **The mechanism is structural, not a property of this sample**: the collar is
`dilate(region, r) \ region` with a `(2r+1)`-**square** kernel, so it can only reach a mark within `r`
px (Chebyshev) of a padded word box's boundary — which is what a rim IS and what a halftone dot in the
middle of a plate is not. Two internal controls: the collar is **live** in this run (on `Wilcox` p2 the
removed set reads `1x11+2596+1538`, `2x11+2596+1538`, `3x12+2596+1537` — **left edge pinned at `x` 2596,
widening by exactly one pixel per radius**, the signature of a `region` rectangle whose last true column
is 2595, and ⚠️ *not* the interior blanking, whose bounds on that 3,642-px-wide page are x ∈ [227,
3415)), and it is **not idle for want of a `region` to dilate** (`1954 - Why` p4 has `glyphN` 2,468 and
`inkOut` 0.0540, so `1 - inkOut` puts the padded region over **94.6%** of its interior ink, and its
accepted group is unchanged in count, area *and* rect at r=1/2/3, because the group is in the middle of
the drawing). ⚠️ Not settled: the collar's effect on the **map**
rather than on accepted lines is not printed, so "0 accepted-line pixels removed" is not "0 map pixels
removed" on the **nine** pages whose columns did not move; radii above 3 are still unrun; the sample is
still 3 true plates of 10 and the seam is ~181 layered pages of which the collar has now been asked
about 83; and the `textRegionMask` seam was **unpriced when this was written** — ✅ **it is priced as of
2026-08-22, see the block below, and it is 1,020x cheaper than the layering seam** — this sub-step made
it no cheaper. ⚠️ The
**local** variant is no way out either: a per-group exemption trusting the collar would still admit
16,290 of 16,294 accepted-line pixels on these ten.
✅ **THE SUB-BAR POPULATION IS INVENTORIED FOR PICTURES 2026-08-22 AND IT HOLDS NO PRINTED PLATE** —
`SUBBARPIX-2026-08-22.tsv`, the same 73 pages plus 7 controls, rendered one page per PNG at
`pdftoppm -scale-to 1400` and read by **two independent passes**, the second framed to over-flag. **0
printed plates and 0 printed figures over the 73, and the largest non-text mark anywhere in the
population is ≤3% of a page** — that pair is what survives every boundary choice, and is the claim to
quote. Beyond it: ≥3 small printed devices (a script masthead with stippled ornament bands, a
`Digitized by Google` scan wordmark, a Great Northern Railway roundel), ≥1 page that is itself a colour
photograph, ≥7 with reader pen marks, ≤62 with nothing. ⚠️ **Those four are FLOORS, not a census**: only
the 17 flagged pages are author-verified and the review of this diff found four undercounts by reading
`none` rows; and `Riesman - 1954` p20, a register-known content loss, sits in the `none` bucket while a
fainter caret on p24 sits in `annot`. ⚠️ **The two passes are not equals** — they disagree on 9 of 73,
every one pass 1 saying `none`; pass 1 flagged 2 pages against pass 2's 11, so **read pass 2**. Both found
**6 of 6** positive controls. ⛔ **Three of 3b's four false-positive substrates are absent from the 73 and
THE FOURTH IS NOT**: halftone dots, pen-ornament strokes and printed photograph grain occur nowhere, but
continuous tone does — `1976 - Regis McKenna Papers` p4 is a colour photograph of a memo on a desk whose
`txtN` is **45** and `txtShare` **0.2157**, so the component test accepts a fifth of its out-of-stencil
map and only `lineN = 0` refuses it. ⛔ **So the bound is the GROUPING, not the component test**, and a
printer's-ornament rect says the same: map 666 px, accepted components **664**, grouped **0** (⚠️ the
`-textish.png` mask *paints* 666 because it paints `bbox ∩ map`; 664 is the accepted set, and "all 666"
was a first draft caught by the review). `lineMinimumMembers` / `lineGapFactor` are **the same two
constants** 3b named for the term's false negatives on C26's cartoons (`textish` 372 and 785 px, 0
groups), and `lineMinimumMembers = 4` already costs three of `Xin Qu` p20's thirteen values — so relaxing
it is a measured two-sided trade, not a fix. ⚠️ **There is no plate control below 40% of a page**, so "0
plates" means "no plate the size of the three plate controls"; ~3% is the smallest control, **not** an
instrument floor (pass 2 found marks at 1%). ⛔ **And it corrected a description of this campaign's**:
`Gitlin_2000` p1's "photograph frame" is a ProQuest *"Blocked due to copyright"* placeholder box —
**there is no photograph on that page** — corrected in the **two** places it was published; the page's
verdict (loses nothing) does not move. Nothing wired, no tool added: reproducible from an `awk` filter on
`INKBAR-2026-08-19.tsv`, one `pdftoppm` per page and `score-shape-term`'s `SHAPEDUMP`.
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
cheaper, so +2,362,625 B is an upper bound. **Nothing is wired.**
✅ **AND THE `textRegionMask` SEAM IS PRICED 2026-08-22 — the last thing under this entry unpriced at
any scale, so all five of its questions now have a measurement.** `WIDENBYTES=1` on
`Tools/score-shape-term.swift` hands production's own `mrcLayers` **one synthetic box per accepted line
group** (it reads `boxes` only to refuse an empty list and to build `textRegionMask`, so nothing in
`Sources/` moves and there is no second override seam). Over the **same 16 pages** the layering wiring
refuses: **789,825 → 792,140 B, +2,315 B, 1.0029x** against **+2,362,625 B** — **0.098%, 1,020x
cheaper** — **2.12%** of the spend on pages that lose nothing against 15.5%, and **6 of the 16 get
CHEAPER** because `fillHoles` hands the background a smoother image (stencil +4,391 B, tone layers
−2,076 B, measured). Per document: the same **~18.42 pages for +2,728 B** against +2,694,515 B, which is
**0.068% of C26's shipped ~4.0 MB**. ⛔ **But it is NOT the same protection, and that is the sharpest
thing in the section**: refusing the shrink keeps the whole background, protecting all **73,370**
out-of-stencil ink pixels on those 16 pages, while the widening admits only the accepted groups —
**36,709 px, 50.03%** of them, per page 5.4% to 96.9%, and **24.1%** on `Scott_TK` p3, a measured
content-loser. **Quote the coverage beside the ratio: 1,020x cheaper at half the coverage.**
✅ The positive control is at 1:1 and two-sided: `Jones et al_2010`
p7's **estimating equation** is blank white in the shipped stencil and fully legible in the widened one
for **+369 B** — ⚠️ **the benefit is read at 1:1 on 1 of the 13 losers**; the other twelve have only a
stencil that grew. A cross-tool control rides with it: `shipBytes` is byte-identical to
`SHAPETERM-BYTES-2026-08-21.tsv`'s `layered` on **16 of 16** rows. ⚠️ It spans two binaries, two
processes and the encoders' determinism — **not** `mrcLayers`, `textRegionMask` or `JBIG2`, which are
the same shipped code in both; a first draft called it "the strongest control in this campaign" and the
review refused that. ⛔ **Cheap in bytes is not cheap in correctness.** The same run
measured the other half: on `1881 - Harry Wilcox` p2 the widening turns a pen ornament into a hard-edged
1-bit blob (**R57's failure mode**, on a page that loses nothing, +2,078 B), 4 of the 10 picture pages
admit ink at all, and — the hazard worth more than the price — **a widened region lowers
`inkOutsideText`, so widening moves every page TOWARD the all-text verdict that shrinks backgrounds
8x**: `1954 - Why` p4 reads 0.0540 → **0.0524** against a bar of 0.045 — ⚠️ this widening bought 0.0016 and
the bar is 0.0074 away (⚠️ published as 0.0079 until 2026-08-22, a subtraction slip: `0.0524 - 0.0450` is
0.0074, and 0.0079 is the gap of the same page **without** the collar, at 0.0529), so flipping it needs
~5x this effect and ~7x without the collar, and the picture page nearest the bar
(`1954 - Why` p6 at 0.0493) has `lineN` 0 and cannot move at all. A more generous rule
re-destroys the cartoon C26's bar move rescued. ⚠️ It buys no searchability (a synthetic box carries no
string; `SearchableWriter` still has nothing to draw), 26 pages at Balanced only, and the 57 non-firing
sub-bar pages cost 0 **by construction** rather than by measurement (✅ 2 of the 57 measured 2026-08-22,
`wAdd` 0 and `dTot` 0 — see `WIDEN-LAYERS-2026-08-22.tsv`). `WIDEN-STENCIL-2026-08-22.tsv`;
**nothing is wired.**
✅ **`mrcBoxPadding`'s 25% COLLAR IS PRICED OUT OF THAT FIGURE AS OF 2026-08-22** — a stranded attempt
from the same base commit unioned the **same bounding rects** into `region` without going through a
`BoundingBox`, so the collar is the only difference and the pair isolates it: **+2,259 B, 1.00286x** over
the same 16 pages against +2,315 B, with the shipped side byte-identical row by row on all 24 shared
rows across two binaries. **The collar is 2.42% of the price on text pages and 22.26% on the 6 firing
picture pages**, and the mechanism is measured rather than asserted: the collar alone contributes
**40.7%–85.4%** of the admitted stencil ink on the four picture pages that admit any, against
**0.0%–8.9%** on the sixteen. ⛔ **Three things bound that: it is NOT an independent implementation**
(same tool, same `mrcLayers`/`textRegionMask`/`fillHoles`/JBIG2, one step different — a first draft
called it "the strongest control" and that superlative was refused here yesterday for this exact
reason); **76.7% of the 22.26% is two pages of one document**, and of those 6 pages `SUBBARPIX` says 2
are plates, 2 drawings, 1 `none` and 1 is absent from that file; and ⛔ **the LARGER inflation is not
the collar's and neither route escapes it** — `wAdd`, the rect's contribution outside the shipped
region, is **1.90x–12.94x** the accepted pixels. ✅ **It splits the delta by LAYER, which isolates the
`fillHoles` saving the landed section's own review refused as unisolated** — ⚠️ for the UNPADDED
widening; the objected-to "47% of the stencil's growth" is the landed run's pooled figure and that run's
own split stays unmeasured — : stencil +4,303 B dearer on
**16 of 16**, background −2,076 B cheaper on **16 of 16**, foreground +32 B — and on the picture pages
the largest term is the **foreground**, +3,071 B, 1.91x the stencil's, which is what "the tone delta
goes the other way" was. ⚠️ 4 of these 16 have a falling total against the padded run's 6: **different
widenings, do not merge the counts.** ✅ It reads `shrunkAsAllText`, `backgroundWidth` and
`inkOutsideText` back from production instead of inferring or recomputing them — the free controls that
review said were left on the table — so the all-text hazard is a measured 0 over 26 rows rather than a
string proxy, on n = 2 for the recomputation. ⛔ **And "an upper bound" holds on the REGION, not on the
bytes**: the padded `wideInkOut` is lower on 11 of 22 firing rows and equal on 11, never higher, but page
by page the padded route is **cheaper on 7 of 22**. ⛔ **The seam it used is REJECTED and `Sources/`
still does not move**: `Tools/score-shape-term.swift`'s own header is the decision against a new
override beside `textPageInkOutsideThresholdOverride`, and with the tool half superseded the seam would
have had no caller. ⚠️ No new measurement was made — a comparison of two artefacts sharing **24 of the
26 rows each carries**. `WIDEN-LAYERS-2026-08-22.tsv`.
✅ **THE CORPUS FIGURE IS MEASURED 2026-08-21 and it is question 4's last owed number at the LAYERING
seam** — `Tools/stratify-corpus.py` (new; `--control` asserts eleven of C26's published band figures
off the committed sweep before it is asked anything new, of which **five are estimator-sensitive** and
six are input-file facts, and ⚠️ its `5.96x` was never published — the register says "6x"; `--self-test`
54 checks, seven mutants watched failing; **the pre-commit hook runs it** — it greps staged
`Tools/*.py` for a `--self-test` flag, which `check-tools-compile.sh` alone does not).
Per document over all **16,987** pages: **~127 are still shrunk 8x/16x and
~19 of them lose content, 0.11% of the corpus.** The shape term's wiring refuses **~18 of the ~127**
for **+2,694,515 B** and rescues **~14.7 of the ~19**; the cheapest page-wide bar refuses **~60** for
**+8,289,863 B** and rescues **~17.9**. ✅ The per-page byte table behind that was
never committed and now is — `SHAPETERM-BYTES-2026-08-21.tsv`, 41 rows — and **both published totals
reproduce digit for digit** along with both ratios and both
overpay shares, `barVerdict=picture` and a byte-identical stencil on 41 of 41. ⚠️ That binary is
byte-identical in source to the one that produced the originals, so it is a determinism re-run rather
than a control across a code change; the real independent control is that `layered` equals
`INKBAR-2026-08-19.tsv`'s on 41 of 41 rows. **Both prices are
incremental to C26's shipped ~4.0 MB**, so the term's wiring is **two thirds of a fix this project has
already decided it could afford** and the page-wide alternative is **2.1x C26's whole bill**.
⛔ **Three pairs of figures published above do not survive the scaling.** The term/bar ratio is
**30.9%** of pages and **32.5%** of bytes corpus-wide against the sampled **39.0%** and **38.1%** — the
term gets *cheaper* relative to the bar, because the bar's largest contributor (`Xin Qu et al_2018`, 6
sampled rows of 12 in a 32-page document, 26.8% of its estimate) is a document the term never fires on.
The share of the spend that buys nothing goes the other way, **15.5% → 18.0%** for the term and
**58.5% → 61.0%** for the bar. And the
pooled-over-stratified factor is **not a constant**: 4.58x / 5.48x / 6.57x / 6.93x over four arms of
one population, so C26's 5.96x is its band's number and must never be used as a correction factor —
**a ratio is a claim about its own set**, the same lesson as the stencil-ink ratio and the
`-normalize`d difference map, and the same mistake this section's own draft made when it explained the
byte ratio with `Xin Qu et al_2018`'s **page** share (26.8% of pages, 8.9% of bytes). ⚠️ The
estimator's one assumption — that a document's unsampled pages behave like its sampled ones — is
nowhere measured, which is why the **exact** subtotal is printed beside every estimate: all 41 pages
were measured, the scaling adds **2.42 pages and 12.3% of the bytes** to the term's arm, and 47.9% of
its byte estimate needs no assumption about an unsampled page at all.
✅ It also settles
`score-text-route`'s open instrument question, because it holds `region` itself so its map **is**
`inkOutsideText`'s set (asserted every row, exit 6 otherwise; `inkOut` reproduced
`INKBAR-2026-08-19.tsv` on all 13): the dumped stencil inflates the fraction **1.00x–3.17x**, the
published `Disk:3` dilation lands **0.721x–1.007x**, and ImageMagick's OTSU equals
`Flattener.otsuThreshold` on **13 of 13** pages over a 69-level range — so that recipe's published
0.56x–16.0x spread is bounded on pages with ink to divide by, and its extremes all sit on `inkOut`
0.0001–0.0051, a small-denominator candidate that is **not measured**. Nothing is wired: `Sources/` is
untouched. ✅ Question 4's byte price is owed no longer — the layering seam 2026-08-21, the
`textRegionMask` seam 2026-08-22 — and note the *area* a local exemption would keep is
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
flip, and it feeds D1's corpus gate, which is R55's territory.
⛔ **DO NOT "RECONCILE" THE TWO WALKS' DEPTH CAPS — `drawnLargestImage` refuses at
`s.depth < 3` and `largestImage` at `depth < 4`, and those are two numbers for ONE reach
ON A CHAIN WHOSE FORMS EACH CARRY THEIR OWN `/Resources`**, because they count in different
frames: forms *entered* against resource *dictionaries* counted from the page's own at 0.
There both see an image inside three nested forms and neither sees a fourth, so raising
either *creates* the divergence such a change is always proposed to remove — which is why
the 2026-08-17 decision to set the drawn cap to `< 4` was retracted the next day.
✅ **That equality was prose until 2026-08-23 and is now MEASURED**
(`#### The two caps, and the chain they are equal on`): nine checks over pages 11-14 of
`shared-resources.pdf`, one chain of four nested forms entered at three levels, so the object
refused on one page is *found* on the next. ⛔ **AND MEASURING IT FOUND THE SCOPE — a chain
of BARE forms is where the two are NOT equal, the drawn walk being strictly the narrower**:
a form with no `/Resources` costs the drawn walk a level and the dictionary walk nothing
(that walk does not descend it and loses nothing, since the names live in the invoker's
dictionary it already scanned). Page 14 measures it — `largestImage` **1800 px**,
`drawnLargestImage` **`.noImage`** — and because `rebuildDPI` routes `.noImage` to the
fallback rather than to `largestImage` the way it routes `.unreadable`, **that page rebuilds
at 300 instead of its own 211.8 DPI, discarding a resolution that WAS read.** The gap grows
with the number of bare forms, so **no pair of caps closes it**, which is a reason to leave
both alone rather than to raise either. ⚠️ **Latent**: `c17b3f3`'s byte-identical 16,987-page
sweep says no corpus page has the shape, but that is one cap over one corpus and says nothing
about `largestImage`'s `< 4`, never moved over it — the decision is the queue's
`bare-form-reach`, and C24 is **not** reopened. Found by the adversarial review of the diff
that added the fixture, which had asserted equal reach unconditionally in `Flattener`'s own
comment. ⛔ **The corpus can never be the instrument here** — `< 4` and `< 3` are
byte-identical over all 16,987 pages, so the sweep that decision prescribed as its own
verification was guaranteed to pass while proving nothing about the only case at issue.
⚠️ Two mutants were catalogued with it (101 → **103**), both verified to match uniquely by
hand. ✅ **BOTH ARE RUN AND `killed` AS OF 2026-08-25, so the one-token sabotage binary is no
longer the evidence** (`#### Both caps RUN through mutate.py`): the drawn cap by **six**
objecting checks, the dictionary cap by **three**, 227 s and 244 s, **705 s** end to end with
the baseline, kill sets predicted by name and in order before the run started. ⛔ **DO NOT
QUOTE THE 6-AGAINST-3 AS A PRODUCT FACT — a draft did and the review of that diff refuted it
twice by counting.** It is **four** rows red under the drawn cap alone against one under the
dictionary cap, and only **two** of the nine reach `rebuildDPI(of:)` at all. And the reason
those two cannot move under the dictionary cap — `rebuildDPI(of:)` routes `.noImage` to
`rebuildDPI(from: nil)` and only `.unreadable` to `largestImage` — is true of **that seam and
not of the product**: ⛔ **`Flattener.pageIsAnImage` reads `largestImage` with NO drawn walk in
front of it** (`Flattener.swift:304-307`), from `Model.swift:886`'s text-extraction skip marker
and from `hasDigitalText`, which is C29's own vote — and on page 13 the dictionary mutant takes
`largestImage` `nil` → 1200 px at 141.18 DPI, flipping that predicate **false → true**.
**Nothing pins `pageIsAnImage` on pages 11-14, so the three is a COVERAGE BOUNDARY**, carried
as a ⚠️ on `bare-form-reach` and deliberately not fixed in the same commit as the log rows that
count three. ✅ Page 14's two rows were *reasoned* by the 2026-08-23 section and are now
**watched**; the dictionary mutant had never been built at all, and its count of three is
confirmed — ⚠️ which three, that record never named. ⚠️ Two of the nine are red under
**neither**: the premise row reads `drawsAnyXObject`, which has no depth guard in either
direction, and page 12's control has nothing below `/FD` for a fourth level to admit (a
*narrowing* mutant reaches page 12 and not the premise — and one is catalogued and killed,
`logic/C24b-form-not-followed`, against a draft here that said none was). ⛔ **And the joint-+1
claim the absolute-width rows exist for is not graded and is one third REFUTED** — `mutate.py`
applies one mutant at a time, page 12's 2400 row is green under each cap separately and would
be green under a joint +1, so **two** of the three widths would go red rather than three.
Nothing shipped moved — two comments, checks and a fixture, plus a
2026-08-25 repair to one failure-detail string that printed only the drawn walk's answers on
the row comparing both, which is why the dictionary mutant's `FAIL` line came out
byte-identical to a passing build's.
**What led up to C24's close
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
`SHAPETERM-73-2026-08-21.tsv`, `SHAPETERM-RIM-2026-08-21.tsv`,
`SHAPETERM-PICTURES-RIM-2026-08-21.tsv`, `SHAPETERM-BYTES-2026-08-21.tsv` and
`SUBBARPIX-2026-08-22.tsv`, `WIDEN-STENCIL-2026-08-22.tsv`, `WIDEN-LAYERS-2026-08-22.tsv`,
`C30-FORK-2026-08-22.tsv`, `C30-PAGE5-2026-08-23.tsv`, `C29-CORPUS-2026-08-25.tsv`,
`C30-VOIDS-2026-08-25.tsv` and `C30-TILES-2026-08-25.tsv` — and are
evidence for one run, not
claims about the present. ⛔ **FIVE of these have no instrument in the tree at all, and all five say so by
decision rather than by neglect** (it was four until 2026-08-25, when `C29-CORPUS-2026-08-25.tsv` — a
per-page walk of all 16,987 corpus pages for C29's report, whose probe is at
`$STATE/c29-instrument/corpus.swift` with the one-page diagnostic `page.swift` beside it — made it five, for
the same reason C30's two are outside: the committed-tool version wants a `--self-test` and a printer
discipline, and a `Tools/` commit pays the full suite): `GUTTER-CENSUS-2026-08-20.tsv`, whose poppler+python
reimplementation was deliberately not committed (`18fae9e`); `C30-FORK-2026-08-22.tsv` **and
`C30-PAGE5-2026-08-23.tsv`**, whose throwaway
Python pass is at `$STATE/c30-instrument/` with a README carrying its inputs' sha256s, because the tool
version C30 asks for wants a `--self-test` and a `Tools/` commit pays the full suite (the page-5 pass is
`page5.py` there, and it `exec`s `artefact.py`'s own function block rather than copying it, so the two
cannot drift — which also means it is unreproducible from the tree for the same reason its parent is);
and `WIDEN-LAYERS-2026-08-22.tsv`, which
came from a `Flattener` override seam C28 rejected — its own header says so, and the seam survives only
outside the tree as
`$STATE/rescue/REJECTED-not-on-main-vo-20260822-014509-85956.patch.bak`. ⚠️ **`SUBBARPIX-2026-08-22.tsv`
is deliberately NOT in that count** and a reader will reach for it: it added no tool either, but it is
reproducible from tools that ARE committed — an `awk` filter on `INKBAR-2026-08-19.tsv`, one `pdftoppm` a
page and `score-shape-term`'s `SHAPEDUMP`. The five named above are reproducible from nothing in the
tree, which is the line this count draws. ⚠️ **`C30-VOIDS-2026-08-25.tsv` and `C30-TILES-2026-08-25.tsv`
are NOT in that count either and a
reader scanning for `C30-*` will assume they are**: both come from `Tools/score-text-voids.swift`, whose
`--self-test` is **13** groups, so the count stays **five** while the list
grows. That also spends the reason the other two are outside: the tool version C30 was asking for now
exists, so a future C30 measurement has no excuse to be unreproducible from the tree — and the tiles file
is that rule being kept, since it re-measures the fork's own headline through committed code. ⚠️ A first draft called
`WIDEN-LAYERS-2026-08-22.tsv` "the one file here whose instrument is not in this repository"; the review of
that diff found `GUTTER-CENSUS-2026-08-20.tsv` in the same list, and `C30-FORK-2026-08-22.tsv` made it
three later the SAME DAY, 2026-08-22 — so this count has been wrong twice in one day, went to **four** on
2026-08-23 with `C30-PAGE5-2026-08-23.tsv` and to **five** on 2026-08-25 with
`C29-CORPUS-2026-08-25.tsv`, and is worth
re-deriving from the list rather than read. **The corpus is 230 scans, not 233**: `CORPUS-2026-08-15.md` is
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
./run_tests.sh        # 1,275 checks measured 2026-08-25 (this commit's own hook); ~225 s measured 2026-08-24, real OCR
                      # ⚠️ EVERY FIGURE ABOVE 700 s IN THIS REPO IS CLAMPED-ERA. Until 2026-08-24
                      # the daemon's plist set ProcessType=Background (darwin-bg, E-cores, inherited
                      # by every child) and run_tests.sh passed no -O: together 16.2x. 3,643 s ->
                      # 225 s, same commit, same 1,247 checks. The old spread -- 474 s quiet,
                      # 2,719 s under C24b, 4,191 s on 6d0caa1 -- was mostly WHO LAUNCHED IT, not
                      # load. Full account: ops/autonomous/com.visionocr.autonomous.plist.
                      # Read $STATE/suite-timings.tsv for rows dated after 2026-08-24; earlier ones
                      # are not comparable.
                      # Never size a
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
