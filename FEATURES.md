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

## Likely worth doing

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

**Both were built, measured and reverted on 2026-08-11.** The rule was the
stricter one — head at the foot of its column, tail at the head of a column to
its right, or at the top of the next page — and it was correct in the unit
tests, ten of them, including the mid-column pairs it had to keep refusing.

On real documents it produced nothing worth having:

| | joins |
|---|---|
| same column (shipped) | 342 |
| across a column | 2, **both wrong** — `that+that`, `provides+flags` |
| across a page | 0 |

The precondition data explains it. Instrumenting the candidate test rather than
the outcome, one Congressional report offered **six** hyphenated line-ends in the
whole document and **none of them at the foot of a page**. That is not a bug: a
typesetter avoids breaking a word across a page boundary, so the case the feature
exists for barely occurs. And joining across a column without real column
detection — which this does not have — finds the wrong line.

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

### Per-page DPI control for picture pages
Photocopies routed to greyscale cost 720–920 KB/page. Fewer pages take that route
since R33 — cream paper was promoting whole books to the colour path, and the
corpus went from 24 RGB pages to 18 and from 520 bilevel to 523 — but the figure
itself still holds for the pages that genuinely land there. Capping their resolution
would cut that substantially. **Parked deliberately** — the decision recorded in
`BUGS.md` R13 is that fidelity wins, and a silent downscale is precisely the
"publishing something plausible" that invariant 1 forbids. It becomes worth doing
as an *explicit setting* with a measured default and a clear label, not as a
default behaviour. Needs the cap to exist inside `flatten` before it can be
measured honestly (the first attempt to measure it produced a broken instrument).

### Recognition language selection that reflects the machine
`-l` takes BCP-47 codes typed by hand. mac-ocr's `languages` subcommand lists
what the installed macOS actually supports, and the app never calls it. A picker
populated from that list would stop users guessing at codes that silently do
nothing.

### A way to see what went wrong, after the fact
The log is in-memory and dies with the window. For a long batch over archival
material, a written run report — inputs, outputs, per-file outcome, the settings
used — is the difference between "something failed last night" and knowing which
document and why. Small to build, and it makes every future bug report better.

### Retry the failures from a finished batch
A 78-document run where four files failed currently means re-dropping four files
by hand. The model already knows which they were.

## Plausible, with real caveats

### Direct Vision instead of the mac-ocr subprocess
Measured and written up in `HANDOFF.md`: mac-ocr is one invocation per file, and
~2,430 of 2,960 non-UI lines are already ours. Calling `VNRecognizeTextRequest`
directly would delete most of `Runner.swift`, remove the `PATH`-discovery
problem, skip a redundant rasterise round-trip, and eliminate the bug class that
produced C6, R2, R3, R16 and R17 — all subprocess-management faults, none of them
OCR faults.

**Decided against for now, and the case got weaker on 2026-08-09.** The strongest
argument for it was never code tidiness — it was that using this app required
installing Homebrew, then Node, then an npm package, in a Terminal. Bundling the
`mac-ocr` binary into the app removed that entirely, for an hour's work and no
change to the recogniser, so **every corpus figure stayed valid**. Doing it the
other way would have invalidated all 232 documents' measurements and made every
subsequent difference an open question: ours, or Vision's?

What remains is the code-simplification argument, which is real — it would delete
most of `Runner.swift` and the bug class behind C6, R2, R3, R16, R17, U18 and R30,
all subprocess faults and none of them OCR faults — but it now has to justify a
fresh 232-document baseline on its own. Keeping mac-ocr also means someone else
tracks Vision's revisions and language lists.

Revisit if mac-ocr stops being maintained, or if a Vision feature we want is not
exposed through it.

### Preserving annotations
The document outline now survives (R19). Annotations do not, and were explicitly
scoped out: links, highlights and form fields are a much larger surface, each
with its own coordinate space to remap onto rebuilt pages. Worth reconsidering if
a real document turns up where the annotations matter more than the risk of
misplacing them.

### PDF/A output
An obvious ask for an archival tool. It would mean embedding an ICC profile,
fully embedding fonts, and adding XMP metadata — and the text layer's font
handling would need re-examining, which is the most delicate part of the
codebase. Only worth it if something downstream actually requires PDF/A.

### Batch presets
"Newspaper", "typescript", "photograph" as named bundles of the routing and
recognition settings. Cheap to build, but it should follow evidence: the corpus
already shows per-era differences, and presets ought to encode measured settings
rather than guesses.

## Parked, with the reason

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
