# page-kind-handwriting — round notes

## 2026-10-15 — session 1 (Opus 5.5, medium)

hw-pages: `HW-PAGES-2026-10-15.tsv`. Truth set: all 100 page images of Archive Suite's OCR truth set
(99 with a transcription; p038 has none) copied to `$STATE/hw-sample/truth-set/`; none is in the photo
sample. 19 handwritten and 2 mixed (3,170 words by whitespace, 3,027 scored), 50 typewritten, 29 printed. Held out: 15 of the 286
Handwritten-tagged photos (seeded draw; 284 of the 286 are Glazer papers), all handwriting by looking, in
`$STATE/hw-sample/held-out/`. The tool's input lists are in `$STATE/hw-sample/lists/`.

hw-detect: `Recogniser.handSignals(of:image:)` and `isHandwritten`, not yet called by the pipeline.
Measured with `Tools/score-page-hand` (the no-rebuild route's reading, as `score-page-kind`), result in
`HW-DETECT-2026-10-15.tsv`. What was tried, by running earlier builds of the tool:
- Vision's confidence separates nothing: 13 of the 19 handwritten pages had no word on a line under 0.5.
  Its dictionary share overlaps (a hand 0.56-0.85 of words, type down to 0.62).
- The ink does. Inside each read line, Otsu's marks a quarter of the line's thickness or more: a joined
  hand has 1.5-3 letters a mark where type has about 1, and a hand's feet wander off a fitted baseline
  where type's do not. p015 (printed capitals on squared paper) needed the residual from that line;
  a page median of the step alone left it with the type.
- Rejected: area-weighted medians (a typed page's headings and tables outweigh its text), line-by-line
  voting (a joined line of three marks steps less than its letters suggest), digits left out (hw04 and
  hw10, mostly handwritten figures, had too few lines of letters to judge).
- Review (subagent): no check pinned the plain-step clause (added: a hand leaping off its line a letter
  in three); quarter-turns are normalised; steps are taken off the fitted line, so type photographed
  aslant does not step by its slope (a fixture fails without it); 150 lines a page at most; non-finite
  boxes skipped. Turns 2 and 3 now have fixtures. Nine mutants checked red, one check each.
- Not yet measured: the rebuilt bitmaps production reads (`fitOn`, often 1-bit). Re-measure when wired.
- Result: truth 18 of 19 handwritten (p048 missed: a typed sheet beside the letter fills a quarter of the
  frame and most of its lines), mixed 1 of 2 (p009, typed with notes, not called), held-out 14 of 15 (hw04,
  one line of letters among figures, missed), photo sample 8 of 8 handwriting rows; none of 79 typed or
  printed truth pages, 55 other photo-sample rows or 152 page-kind pages. A separate verifier: all PASS.

hw-measure: `HW-MEASURE-2026-10-15.tsv`. Missed per 1,000 truth words on the 19 handwritten pages (2,825
scored words, whole page, as a bag): Vision 561, PaddleOCR-VL 454, Falcon-OCR 409; on the 2 mixed pages
257 / 228 / 223. Falcon-OCR beats Vision by 152 per 1,000, the clear margin the item asked for, so the dialog
step goes ahead. On four pages (p050, p054, p094, p096) all three readers return the same words: both
arrangements put the model's words only on lines Vision found, and there Vision found almost none (p094 950
per 1,000 missed). That is a limit of align and regions on handwriting, not of either model.

QUESTION FOR THE OWNER (the item asked for it): Archive Suite's panel on 16 of these pages has small chat
models missing 7-9% of words (Qwen3.5 9B 7.7%, Gemma 4 31B 7.8%, Qwen3.6 27B 6.6%) against Vision's 57%. On
this repo's measure Vision misses 56% too, and the best shipped reader, Falcon-OCR, 41%: far behind them.
Should a handwriting page's reader be one of those models (not approved, so not added), or a whole-page
arrangement that does not depend on Vision's lines?

## 2026-10-15 — session 2, hw-settings (Opus 5.5, medium)

Wired: `PageKind.handwriting`, its pair through Prefs, the helper's arguments, the run report and the dialog
(fourth kind; Falcon-OCR align, PaddleOCR-VL regions; figures from HW-MEASURE, labelled a small sample that
counts missed words only). Rule: a newspaper wins over handwriting, handwriting over a photograph; a paste-up's
ink is never judged. Rejected: the photograph's reader for a photographed letter (27-34 per 1,000 on print,
409-561 on a hand). Detection runs only when handwriting would be read otherwise (`handwritingApart`).
Re-measured on the app's own route (`REBUILD=1 Tools/score-page-hand`, `HW-SETTINGS-2026-10-15.tsv`):
- On the rebuilt bitmaps the app reads (a photo's page is a re-lit JPEG), the detector lost p015 and hw08
  (truth 17/19, held-out 13/15) and called p080 (printed) and xm02 (a clipping) handwritten. With the
  production reading's lines over a plain render of the source, p015 and hw08 came back; p080 stayed, at a
  plain step of 0.060. So `flatten` now leaves that render (`.ink.jpg`, on the rebuilt sheet, only with
  handwriting read apart, not for paste-ups) and the plain-step clause moved 0.06 -> 0.1 (the least hand
  needing it steps 0.315; every hand under 0.1 passes the second clause).
- Rejected: judging the re-lit bitmap (the misses above); lowering `joined` to 0.5 for hw08 (calls pk33).
Figures note: PaddleOCR-VL's 3.3 s a page on handwriting is HW-MEASURE's wall less the harness's start-up,
reasoned, against 8.5 s on photographs; it read every page (its words differ from Vision's).
Accurate mode: an unset handwriting choice is Vision, as photographs' is, and the dialog says so; rejected
inheriting the other documents' reader, which the dialog's picker cannot show.
Result, the app's route on the final code (`HW-SETTINGS-2026-10-15.tsv`, 332 pages): truth 18 of 19 handwritten
routed to the handwriting reader (p048), held-out 14 of 15 (hw04), no typed, printed or other page of any set.
ux-regression 0 worse, 0 better (53 pages, 40 documents; accurate rows set the handwriting reader too). Built
app holds the dialog's four kinds. Review (subagent): the ink render was on the crop box while the page is the
whole sheet (fixed: flatten's own box and render, and an ink image off the page's shape is not used); paste-ups
no longer get one. Independent DONE WHEN check: all PASS; it found the 29 photo-sample extras unmeasured on the
app's route, now measured (none called). Suite 2,112/2,112.
