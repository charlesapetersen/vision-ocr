# Test corpus

**233 documents, every one of them a scan**: 232 sampled from the Zotero library
and stratified into 32 buckets — 8 item types x 4 eras (pre-1960, 1960-1999,
2000+, undated), up to 6 per bucket where the library has them — **plus one added
by hand**, which is outside the draw and described below. 1.2 GB.

Widened from 84 on 2026-08-09 by removing an arbitrary five-year recency bound
on the draw; 79% of the new material predates it, reaching back to 2013. The
figures did not move — see [../CORPUS-2026-08-09.md](../CORPUS-2026-08-09.md),
which is the answer to "do these numbers describe the app or the sample".

**Only scans.** `Tools/sample-zotero.py` classifies every candidate and keeps
the ones whose pages are actually images of paper; the two draws behind this
corpus rejected 704 born-digital PDFs, 63 shot by hand, and 6 with no page image
at all.
`manuscript` and `letter` are excluded as item types — in this library those are
archival photographs and finding aids, which are Archive Processor's material.

That gate is why this corpus exists. The one it replaced had no gate, and was
**27 scans out of 78**: 40 born-digital, 10 photographed. The project quoted its
accuracy figures off it for months, and nothing about them looked wrong, because
born-digital documents score perfectly — OCR of a clean rendering of digital text
is an easy problem. See BUGS.md D1 and ../CORPUS-2026-08-08.md.

## The one document added by hand

`book/1954 - Why.pdf` — *Why?*, anon., 1954, National Foremen's Institute (Zotero
attachment key `9232Z7B5`), added 2026-08-13 at the owner's request. Its `book`/`old`
bucket already held its 9, so this is an addition **outside the stratified draw**
and not a 10th sample; `sample-zotero.py` will not produce it.

It is here because the corpus had **no document anyone picked deliberately** for
the decision R49 and R50 both turned on: colour on paper that is not a photograph.
This one is a 1954 pamphlet whose subheads and cartoons are printed in red ink, and
it exercises that routing three ways at once — measured, on its sampled pages:

| page | ink | tone | sat | routed |
|---|---|---|---|---|
| 2 | 0.276 | 0.192 | **0.178** | picture, **kept in colour** |
| 6 | 0.094 | **0.164** | 0.043 | picture, greyscale |

The red ink alone clears `pictureSaturationThreshold` (0.06), and the scan's own
resolution — 111 DPI, where type is mostly anti-aliased edge — clears
`pictureToneThreshold` (0.12). So a text pamphlet routes to the picture path on
three of its four sampled pages. That is the `isPicture` case TODO item 1 is about,
and this document is the fixture for it.

**Its `classify-source` verdict is `photographed`, and that verdict is wrong.**
The gate reads a median illumination gradient of 0.169 against a 0.16 threshold.
The document is an upright-scanner capture of an open booklet, and the gradient is
a smooth diagonal ramp — 182 at top-left to 219 at bottom-right, centre exactly
between — that is **the same on every sampled page**, which is a fixed lighting rig
rather than a hand-held frame. Saturation is 0.041, and the pages are rectilinear
with no perspective or page curl. Ruled a scan by the owner on 2026-08-13, with the
categorisation narrowed to *hand-held* photographs; `BUGS.md` R55 carries what that
means for the gate and for the survey's 1,001 "photographed" files.

## Where it currently stands

The figures below are the **232-document** run; the hand-added document scores
`start=99% end=99% off=-0.10 overlap=0/21 words=100%`, which moves no median and no
worst case, but the byte and character *totals* quoted elsewhere are 232-document
figures and stay labelled as such.

232/232 process successfully · median 100% line-start and line-end selectability
(worst 91% and 91%) · median 100% word retention (worst 97%) · median 0.10
text-layer offset, max 0.10 · source line tightness 2.00% (295 of 14,782 adjacent
pairs set closer than their boxes — a property of the material, not of the text
layer this app writes, and higher than before because the wider draw reaches
further back into tightly-set printing).

`manifest.tsv` lists type, era, local file, the Zotero item key, and the measured
result for each document. The key, not the source path: the manifest is committed
and a home directory full of someone's reading has no business in a public repo.
`--exclude-manifest` still works, and still accepts an older path-form manifest.

## What was measured

Only **3 pages per document** (one near the front, one mid, one three-quarters
through) are used, so a run over the whole corpus takes minutes rather than hours.
Each document goes through the shipped `makeSearchablePDF`, and the finished file
is then **independently re-OCR'd** to get reference boxes — the pipeline is not
graded against its own numbers.

Columns in `manifest.tsv`:

- `line_starts` / `line_ends` — fraction of recognised lines whose first/last
  15% is selectable. Catches a text layer that is offset or too narrow.
- `offset` — median vertical displacement of the text layer, in line heights.
  0.00 means the text sits on the ink.
- `overlap_pairs` — how many horizontally-overlapping line pairs sit closer than
  0.6 line heights **in the source**. A property of the document, not a defect:
  high values mark tightly-set material that is hard to lay text over.
- `words` — word retention against what Vision recognised.

A separate check counts how many recognised lines survive as *separate* lines in
the output. That is the one that matters for drag-selection, and the one that
degrades on tightly-set archival material — modern print keeps 100%, 1920s-50s
letters and typescripts 87-93%.
