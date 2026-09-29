# truth-calibrate — working status

2026-09-29, first session (medium effort, started at 94% of the usage window, so no subagents). The app
half is measured and committed in `TRUTH-CALIBRATE-2026-09-29.tsv`. The reader half has not been run.

- `testdocs/` holds only two born-digital documents (`CORPUS-2026-08-15.tsv`): Canby 1929 (4 pages)
  and Davis 2005 (4 usable; p5 has no text layer). The other 24 pages are synthetic (`synth-pages.swift`):
  six layouts (one, two and three columns, a table, footnotes, 6.5 pt small type), four seeds each. Their
  words come from `/usr/share/dict` and carry no sense, which makes this a conservative test of the reader.
- Tools: `render-page` (PDFKit render), `img2pdf`, `make-scans.sh` (clean: 300 dpi grey on grey paper;
  hard: 150 dpi, 1-bit, 0.8° skew, JPEG q20), `cut-crops` (≤2,000 px crops cut in white space), and
  `score-words.py` (order-sensitive `wer` and order-free `bag`). ImageMagick's PDF writer made pages that
  rendered blank in PDFKit, which is why `img2pdf` exists. Build with `swiftc -O <tool>.swift -o <bin>`.
- The app was run with `score-gate` (Tools/score-gate.swift and the helper built from 246f3d5). The clean
  and hard outputs share a directory: `<name>.ocr.pdf` is clean and `<name> 2.ocr.pdf` is hard, checked
  by image width (2550 against 1275).
- **Product finding, measured (unverified cause):** on a clean 300 dpi scan of a plain ruled table, the app's
  text layer lacks 27–35% of the number cells (e.g. `70255`, `177.3`). They are missing, not misread, and
  the table is fully legible (checked by eye). PDFKit reads the synthetic source itself at 0% error. This
  bears on C51 (marked FIXED). Hard 6.5 pt type loses ~21%. `truth-read` should queue both.
- Order-sensitive `wer` on the real pages (27–32% clean) is mostly reading order: `bag` is 2.7–3.7%.
  PDFKit's order for the born-digital source is not a reading order either, so compare `bag` there.

## Next session (subagents allowed once the window is under 85%)

1. For each of the 64 scans: `render-page <scan> 1 400 page.png`, then `cut-crops page.png <dir>`, then
   one reader subagent with the READER prompt from `procedure.md`, given only the crop paths. Readers
   only look at images, so several may run at once. Record each one's usage.
2. Cross-check against Vision's reading (the app output's text) and, for real pages, the source layer; fresh
   CHECK readers on each differing word.
3. Score each transcript with `score-words.py` against `truth/`, fill the `reader_*` columns, and apply
   the fitness rule (reader error ≤ ¼ of the app's or < 0.2%, no skipped line). Scratch is
   `/private/tmp/tc.ugTW` (scans, truth, app texts). Rebuild from the tools if /tmp was cleared.
