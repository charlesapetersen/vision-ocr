# truth-calibrate — working status

**Done 2026-09-29 (second session).** The procedure is `procedure.md` v2; the evidence is
`TRUTH-CALIBRATE-2026-09-29.tsv`, whose per-page block holds the reader half.

- Scans: `make-scans.sh` (clean: 300 dpi grey on grey paper; hard: 150 dpi, 1-bit, 0.8° skew, JPEG q20).
  The app half was measured on all 64 scans (first session). The reader was run on 16: one page of each of
  the eight layouts, clean and hard. Cross-checked: five of them, 386 words.
- **Fit, measured on one page per kind:** every synthetic layout (one, two, three columns, table,
  footnotes, 6.5 pt), clean and hard, and the real magazine page (Davis) hard. Reader fair loss 0-0.66%
  against the app's 0-30.8%, no skipped line; without any check it is 0-1.22%, which passes too. Davis
  clean fails as written (0.22% against 0.45%) and is passed on a waiver: both lost words are one scorer
  artefact (`jour-` at a column end) that the app loses too.
- **Real book (Canby) is not calibrated:** its "born-digital" layer is old OCR (`ERACE`, `gUINN 1::`,
  `no` for 110), so it cannot be the truth. The reader's transcript matches the page by eye.
  `testdocs/` has no other born-digital book page. **So in `truth-set`, old-book pages (real books, not
  magazines) are scored only for lost lines and blocks**, until a book page with a correct layer is found
  and measured.
- **v1's cross-check was harmful** and v2 changes it: a check never replaces a word, it only contests it.
  Tiny degraded type is contested heavily (6.5 pt hard: 144 of 900 words; its 0.66% is over the 756 left), so `truth-set` should report
  the contested share next to every score.
- Product findings for `truth-read` (measured; the reader read each of these tables with no error):
  clean ruled tables lose 27% of their words from the app's layer and hard ones 31%. 6.5 pt hard type
  loses 18%. The one-column *clean* scan loses 3.9% against 0.4% for its hard scan, which is backwards
  and unexplained.
- Tools, all in this directory: `render-page`, `img2pdf`, `cut-crops`, `synth-pages` (swiftc -O),
  `score-words.py`, `xcheck.py` (transcript text; reader-vs-Vision spots), `wordcrops.py` (word crops from
  ink gaps), `apply-check.py` (applies checks, v1 or `V2=1`, and the fair score).

# truth-set — working status

The list is `TRUTH-PAGES-2026-09-29.tsv` at the root (`make-list.py`, fixed seed; 215 pages). Its status
column is filled by `page-status.py`, which also prints the contested rate by route. Per page, with
`swiftc -O` builds of `render-page`, `cut-crops`, `vision-read` and `Tools/pdf-page-text.swift` (as
`page-text`) in one bin directory:

1. `prep-page.sh <bin> <document> <page>` (one at a time: it renders and runs Vision).
2. One reader subagent per page, given the READER prompt, the crop list and the crop command (the
   `brief.txt` it writes); many may run at once.
3. `spots-page.sh <page-dir>`, then shuffle every page's `check/<idx>.png` into briefs of about 40 with the
   CHECK prompt, one check subagent each, writing `path<TAB>reading` to `chk-*.out`.
4. `finish-page.sh <page-dir> <checks-dir> <reader-tokens>`, which deletes the page image and crops.
   A page with no transcript goes in `$STATE/truth/none.tsv` with its reason.

Measured cost, batch 1 (21 owner pages of the regression set, 2026-09-29): readers 34-50k tokens a page,
99k for the newspaper page; checks 33-38k per 40 words; the batch used about 32% of the five-hour window,
so a session holds about 40 pages from a fresh window.

**Batch 1 (b1), 2026-09-29:** 20 of 21 pages done, 11,015 words, 57 contested (0.52%); without the
newspaper page 7,826 words, 10 contested (0.13%). Contested rate by route (`page-status.py`): dct 0/182,
jbig2 3/3,910 (0.08%), layered 5/1,929 (0.26%), no-image 1/435 (0.23%), unknown 48/4,202 (1.14%;
Raskin's newspaper page is 47 of them). **Next:** batch 2 = the 8 selftest pages (Why 3, 4, 7; Briefer 2,
5, 6; Hughes 2, 8) and the testdocs pages of the regression set, then the draws in list order; Hughes p3
again; `prep-page.sh` needs `TESTDOCS=/Users/cp1/Claude/vision-ocr/testdocs` when run from a worktree.

- **The grey render hides colour.** `render-page` draws grey, so the OBJECTS lists name every coloured
  heading "dark grey" (Why p5). Kinds and boxes stand; `truth-harness` should take colour from the source's
  pixels inside each object's box, not from the list.
- **Vision on a full page misses most of a newspaper** (Raskin p1, 300 dpi: 1,047 words against the
  reader's 3,315) and half of Briefer p1 and p3 (273 of 631, 302 of 664) — both on a plain render, not the
  app's pipeline. `vision-read` over the crops finds them; noted for `truth-read`, not measured on the app.
- The content filter blocked the reader's output on Hughes p3 twice.
- The contested rate is high on dense newsprint (Raskin) partly from the instrument: where the ink gaps do
  not match the line's word count, `wordcrops.py` cuts the nearest gap, often the word beside the spot.
  Those crops are contested 14 of 41 times against 17 of 182. Safe (the word is not scored), not fixed.
