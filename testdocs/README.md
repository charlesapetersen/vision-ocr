# Test corpus

**232 documents, every one of them a scan**, sampled from the Zotero library and
stratified into 32 buckets: 8 item types x 4 eras (pre-1960, 1960-1999, 2000+,
undated), up to 6 per bucket where the library has them. 1.2 GB.

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

## Where it currently stands

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
