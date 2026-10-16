# layout-compare notes

## 2026-10-16 — session 1 of round 1 (Fable 5.1, max; engine-assigned)

The measurement runs through the lab's hybrid harness, so the app's own region alignment and readers are what is
measured and only the detector changes: `reader-regions.sh` takes `VISIONOCR_LAYOUT=yolo|pp|heron`,
`layout-regions.py` gained `--model heron` (docling-layout-heron, RT-DETRv2, transformers + torch in the lab's
venv-surya; 164 MB, Apache-2.0, 640 px, conf 0.3 by the lab's coverage criterion: 0.839 of Helena 1941's ink
against 0.721 at the model card's 0.6), and `hybrid-run.sh` takes another job's sample and combinations
(`layout-compare.sh`, `layout-combos.tsv`, `layout-sample.tsv`) and keeps each run's regions, readings and page
image in `keep/`. `layout-fit.sh` is the fit test; `fused-regions.py` places each fused row in a detector's regions.

Pages: the 11 newspaper pages of OCR-SAMPLE-2026-10-04 and C41's four other scans (c01 Billings 1926, c02 Kalispell
1939, c03 the comic, c04 October 1960; Helena 1941 is s30), which have no truth transcript and are published for
the fused-row count only. Combinations, cheapest first: vision-off, then each detector's regions read by Vision,
PaddleOCR-VL, Falcon-OCR (150 runs). Job: `$STATE/ocrlab/layout`, started 02:20 from the worktree's tools
(ef91b9d), one page at a time, resumable (`layout-compare.sh status|start`).

The heavy lock: Archive Suite's engine sessions queued builds, test scripts and half-hour VM test runs behind every
release (the lock is first come first served, `~/.local/state/mac-heavy.log`), so the job's first page took fifteen
minutes to get its turn and the second would have too. `hybrid-run.sh` now holds the lock per group of combinations
(`HYBRID_HOLD=group`: one reader's three detectors, 20-60 min a hold, giving it back whenever a suite is queued,
since the suite takes the same lock) and skips the lock for a batch whose pages are all done. Restarted 03:30 and
again after the diff review (below); nothing done is lost, a page with a status is not run again.

Vision reading the regions, the 11 scored pages (24,867 truth words) [measured, `LAYOUT-COMPARE-2026-10-16.tsv`]:
wrong or missing 0.2963 alone; 0.2654 with YOLO's regions, 0.2665 with PP's, 0.2655 with heron's (a cut of a tenth
for all three, within 0.001 of each other); find 0.85 alone, 0.87 / 0.85 / 0.86; app seconds a page 26 alone,
37 / 38 / 40. With Vision as the reader the arrangement is the gain and the detector is not. Fused rows (lc-fused,
`bugs/C41.md`): no detector's regions make or remove them; 21-26 of the 35-37 one-run rows are held by no region.
PaddleOCR-VL and Falcon-OCR reading the regions: the job's second and third holds (below, when they land).

Fit test [measured, `/tmp/lc-fit`, 300 dpi renders]: every detector detects in under a second a page on the CPU
(heron 0.3-0.6 s at 640 px, PP 0.3-1.0 s, YOLO 0.4-0.7 s); peak RSS heron 1.0-1.4 GB, YOLO 0.6-1.2 GB, PP 0.3-0.8 GB.
Ink inside text regions (each script's own measure): YOLO 0.43 on Kalispell and 0.44 on the comic, where heron
reads 0.93 and 0.89 and PP 0.71 and 0.57; the other pages 0.80-1.00 for all three. Heron returns exactly 300
detections on the comic and Helena 1941 at 0.3: RT-DETR keeps its 300 best (box, label) pairs, so a box can come
twice under two labels (237 and 241 distinct boxes there) and boxes over 0.3 beyond the 300th are cut, on dense
broadsheets. Heron's `picture` boxes are the advertisements and the photograph, with their text blocks boxed
separately inside them, so dedupe-regions.py drops them as it drops PP's `image` (the diff review caught that it
did not; before the fix a kept picture box absorbed 21-27 text boxes on the comic and Helena 1941).
