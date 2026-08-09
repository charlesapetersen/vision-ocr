# Test corpus

**84 documents, every one of them a scan**, sampled from the Zotero library and
stratified into 32 buckets: 8 item types x 4 eras (pre-1960, 1960-1999, 2000+,
undated), 3 per bucket where the library has them. 397 MB.

**Only scans.** `Tools/sample-zotero.py` classifies every candidate and keeps
the ones whose pages are actually images of paper; building this corpus it
rejected 275 born-digital PDFs, 23 shot by hand, and 2 with no page image at all.
`manuscript` and `letter` are excluded as item types — in this library those are
archival photographs and finding aids, which are Archive Processor's material.

That gate is why this corpus exists. The one it replaced had no gate, and was
**27 scans out of 78**: 40 born-digital, 10 photographed. The project quoted its
accuracy figures off it for months, and nothing about them looked wrong, because
born-digital documents score perfectly — OCR of a clean rendering of digital text
is an easy problem. See BUGS.md D1 and ../CORPUS-2026-08-08.md.

## Where it currently stands

84/84 process successfully · median 100% line-start and line-end selectability
(worst 91% and 91%) · median 100% word retention (worst 97%) · median 0.10
text-layer offset, max 0.10 · source line tightness 1.33% (74 of 5,564 adjacent
pairs set closer than their boxes, in 23 documents — a property of the material,
not of the text layer this app writes).

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
