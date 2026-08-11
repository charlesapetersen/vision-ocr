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

### MRC layering for mixed pages — measured at 4.96x, blocked on segmentation
*(investigated 2026-08-11; `Tools/score-mrc.swift` is the prototype and the
measurement)*

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

**What blocks it is segmentation, and the prototype shows exactly how.** Sauvola
thresholding (k=0.34, window dpi/4, following `internetarchive/archive-pdf-tools`)
marks halftone dots as text. The photograph on `Findlay_1992` p21 is then cut out
of the background, blur-filled, and painted back from a 3x-downsampled
foreground: **visibly smeared**, while the text on the same page is perfect. A
naive segmenter does not fail gracefully on the exact pages MRC exists for.

Note also that PSNR is useless here and says the opposite of the truth — it reads
20–29 dB for MRC against 37–42 dB for today's JPEG on pages where MRC looks
better, because it punishes a smoothed background and is blind to text edges
being exact. Judge this one by looking at pages.

**The way through is already in the app.** archive-pdf-tools drives its mask from
hOCR — it uses the OCR result to know where text is. This app has the same signal
and better: Vision returns word bounding boxes, which `SearchableWriter` already
consumes to place the text layer. Restricting the stencil to inside those boxes
leaves photographs wholly in the background, untouched, which is precisely the
failure above. The cost is pipeline order — `flatten` currently runs before
`mac-ocr`, so the layers would have to be built in a second pass once the
recognition is back, or the routing decision deferred.

Worth doing, and worth doing properly rather than quickly: an MRC page that
misplaces its stencil damages the picture silently, which is invariant 1
territory. Prerequisites, in order: OCR-driven masking; a corpus check that no
page loses picture detail; and a decision on the background codec, since R34
found ImageIO's JPEG 2000 unusable and OpenJPEG 1.5–2x better than JPEG at
matched fidelity, which would mean bundling it.

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
