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
