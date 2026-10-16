# hw-qwen notes

## 2026-10-15 — round 1, session 1 (Opus 5.5, medium): hw-coverage, hw-panel, qw-place

hw-coverage (`HW-COVERAGE-2026-10-15.tsv`). The truth has no word positions, so a subagent counted lines by eye
over Vision's boxes from the app's own route: 503 lines, 392 covered, 64 partial, 47 missed; about 82% of words
inside a box. Weak pages: p094 (blurred photo, 25%), p050 (45%), p054 (50%). A pixel measure of ink inside the
boxes was taken too and is not usable (dark backgrounds count as missed ink, faint pencil as none). Coverage
caps a reader of Vision's lines near 180 missed per 1,000, past the pick's 20-point window (116), so it alone
rules Kraken out of the pick; Kraken also read the lines it had worse than Vision did (666 against 561). For
the owner, not run: Kraken's own baseline segmenter (`kraken segment -bl`) would lift the cap, not the reading.

hw-panel (`HW-PANEL-2026-10-15.tsv`), missed per 1,000 on 2,825 handwritten words, added words beside it
(bar: 204, 793): Qwen3.5-9B 91 / 312; LightOnOCR-3-4B 96 / 264 (NARA's prompt 92 / 359); Churro 3B 152 / 6,602
(p096 looped to 12,000 tokens; without that loop it would pass the bar, but at about 119 it is still more than 20
behind the pick, reviewer's estimate); Kraken PP-OCRv6 666 / 1,277, on production's own Vision line boxes. The scorer
reproduces HW-MEASURE's Vision rows exactly. Pick: LightOnOCR-3-4B, empty prompt (the card's; other prompts are
out of distribution, and NARA's adds 95 words for 4 fewer missed). Within 20 of Qwen, so the smaller and faster:
5.16 GB, a median 17.8 s a page, 7,613 MB peak (Qwen 5.98 GB, 31.8 s, 8,743 MB). Apache-2.0, so the Churro
licence question does not arise. LightOnOCR's MLX build (prithivMLmods 8bit/) runs under the lab's mlx-vlm 0.7.4
as it is: the model is Qwen3.5's architecture.
- Its peak is over ModelGuard's default 5 GB cap, so qw-build's dialog has to say it needs the memory setting
  at 8 GB or more. Rejected: raising the default for it.
- Instrument note: Kraken's first run took the boxes from the finished PDF's text layer, whose heights the
  writer caps and offsets; crops clipped the glyphs (707). Rerun on `recognisePage(at:)`'s observations: 666.
- Kraken in one process grew to a 17.5 GB footprint over 21 pages; one process a page peaks at 3.8 GB.
- Lab: dropped the weights of four rejected bake-off builds (Gemma 4 12B, Qwen3-VL-8B, olmOCR-2, Chandra oQ8;
  23.3 GB, all on the Hub) to fit the 50 GB limit; lab now 44 GB with Qwen3.5-9B and LightOnOCR-3-4B kept.

qw-place (`HW-PLACE-2026-10-15.tsv`). Threshold: align cannot place a reader when under 90% of the truth words
it reads reach the finished PDF. It was written after Qwen's align run (placed 65%) was known, though before
LightOnOCR's; the item asked for it before measuring. Through the app's align (every reader a script handing
back the saved reading), LightOnOCR places 65% of its words and keeps 71% of the truth words it read (96 -> 367
missed); Qwen the same (91 -> 365). Find, 21 pages: 922 of 1,405 distinct truth words, Vision alone 585. Pages Vision barely found keep almost nothing (p094 7%, p096 16%). So handwritten
pages get the text page, as THE TEXT PAGE says. One option for later, not tried: LightOnOCR's `grounding` prompt
returns a box per block, which the `replace` arrangement could take; the item asks for align or the text page.

Next: qw-build. The reader for the handwriting kind (download size 5.16 GB, its memory need), the text page
on by default for handwritten pages only, ux-regression with the mode off and on. Found while scoping it:
- The app's runtime (mlx-vlm 0.7.4, as the lab's) imports `mlx_vlm.models.qwen3_5`, which LightOnOCR-3 loads
  as; a full read through `Runtime/bin/python3` and read-model.py is not yet tried. No new runtime expected.
- The build is `prithivMLmods/LightOnOCR-3-4B-MLX`, files under `8bit/` (revision e93084acf44a380776866b23b122f48fe47cab7f
  in the lab's cache). `ModelDownloads` pins each file by path, size and SHA-256 at a revision, so `8bit/…` paths
  fit its plan; read-model.py then has to load the snapshot's `8bit/` directory, not the repo id. Settings the
  card gives: empty prompt, longest side 2048 px, 4096 tokens, thinking off (the template's default).
- Archive Suite's text page, read only: `SPEC/tag-format.md` §"2-page PDF structure"; `PDFGenerator.makeTextPage`
  (`ArchiveProcessor/macOS/Sources/ArchiveProcessor/OCR/PDFGenerator.swift` ~255-410): Georgia 11 pt body, page
  height max(792, text height + margins), one page, never overflowing.
- `makeSearchablePDF` checks the page count it publishes (`Model.swift`, `pageCount: expected`); a text page
  changes the expected count, and invariant 1 needs a check that each handwritten page's text page is there.

## 2026-10-15 — round 1, session 2 (Opus 5.5, medium): qw-build

LightOnOCR-3 is a fifth reader, `lightonocr-3`, on handwritten pages only (align route), its download the repo's
`8bit/` folder pinned by size and SHA-256 (hashes taken from the lab's copy, LFS hashes checked against the Hub; the
app's installer was not run over the 5 GB, only its plan checked). It runs in the app's own runtime unchanged
(mlx-vlm 0.7.4), loaded by the folder's path, the card's empty prompt, 2,048 px, 4,096 tokens. Memory 7.6 GB, so it is
offered only with the limit at 8 GB or more; no speed check after its download (no handwritten sample pages).

The text page. With `handTextPage` on (default), a handwritten page read by a whole-page reader (LightOnOCR-3, and
Falcon-OCR too) keeps Vision's own layer and the reading goes on the page after it: Archive Suite's layout (612 pt
wide, Georgia 11, as tall as the text, a header naming the original page), inserted by one `qpdf --pages` pass after
the page labels are carried, each text page read back through PDFKit. PaddleOCR-VL (regions) adds none. Off, the
words go through align. A mixed file: each handwritten page is followed by its text page, every other page as before.
- Through the app (`HW-BUILD-2026-10-15.tsv`): 19 of 21 pages got a text page (p048, p009 not judged handwritten);
  99 missed per 1,000 on the 18 handwritten pages with one, against the panel's 96; Find 1,238 of 1,405 (align 922).
- Known: p049's reading ends with a model note ("Note: The handwritten text contains some unclear ..."), published as
  text. One page of 19; not stripped (any rule for it would be a guess).
- Known: a source with page labels gives a text page an empty label (qpdf's `{/St n}`), as C48 records for splices.
- `score-gate` knows a text page by its width and header; `ux-regression.sh` takes `VISIONOCR_UX_TEXT_PAGE=0|1`.
- ux-regression with the text page on and off (`VISIONOCR_UX_TEXT_PAGE=1`, `=0`): 0 worse, 0 better, 53 pages, 40
  documents, each; its quality columns and byte counts identical between the two. Its set has no page judged
  handwritten, so it shows the change leaves other pages alone, not the text page itself.
- Diff review: the read-back compared letters in order and failed a document in Devanagari (PDFKit gives vowel signs
  in drawn order); now a sorted bag. The text page now gets `modelText` (control tokens, tags, Markdown marks out).
  Left: a reading cut at 4,096 tokens is published as read, unreported (as align's is); the run's notes number pages
  by the original, so in a file with text pages they point early; the detector now runs on every page when the same
  whole-page reader is chosen for handwriting and the rest, since the text page sets handwriting apart.
