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
(ef91b9d; the one retried page from a370d11, which changed nothing under Sources), one page at a time, resumable
(`layout-compare.sh status|start`), done 09:01.

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
`bugs/C41.md`): no detector's regions remove them; 18 / 24 / 23 of the 35 / 37 / 36 one-run rows are held by no
region, and 29-30 of them sit where a one-run row already was with no regions at all (4-7 a detector are new after
reading, the alignment's doubled hyphen fragments among them).
PaddleOCR-VL reading the regions, same pages [measured]: wrong or missing 0.2183 with YOLO's regions (a cut of 26%
on Vision alone), 0.2253 with PP's (24%), 0.2161 with heron's (27%); find 0.91 / 0.91 / 0.92; app seconds a page
66 / 63 / 76 (heron's torch start and its more numerous regions); peak 2.6 / 2.6 / 2.5 GB. Heron is 52 wrong words
in 24,867 better than YOLO and PP 200 worse; page by page heron and YOLO trade places by a few words, PP loses on
the dense scans (s46 1923 against 1841 / 1800).

Falcon-OCR reading the regions [measured]: wrong or missing 0.2135 with YOLO's regions (a cut of 28%), 0.2206 with
PP's (26%), 0.2116 with heron's (29%); find 0.92 / 0.91 / 0.92; app seconds 79 / 82 / 105; peak 3.5 / 3.4 / 3.9 GB.
Heron is 46 wrong-or-missing words in 24,867 better than YOLO and PP 177 worse. Heron's first run of s47 (`___ 4.pdf`, a
small page every other combination read in 11-45 s) failed: Falcon ran past the app's 600 s on one of heron's 42 regions,
twice (1,206 s); run again alone an hour later the same page read in 64 s, so the loop was not repeatable (the first
attempt is kept in `runs-superseded/`).

RECOMMENDATION: keep DocLayout-YOLO. With Vision reading the regions the three detectors are equal; with either
model reader heron gains 0.2 points of wrong or missing words (46-53 words in 24,867) for 10-26 s more a page (its
torch runtime starts in every call and it cuts more regions), 92 MB more to download, a torch and transformers
runtime the app does not ship, and one page Falcon could not finish at the first try; PP-DocLayoutV3 loses 0.7 points
with either model at about the same time as YOLO. The fit test's coverage gap (YOLO 0.43 of Kalispell's and the comic's ink, heron
0.93 / 0.89) did not become words. Those pages have no transcript; on the proxy C41's sessions used, the share of a
page's words in `/usr/share/dict/words` through PDFKit's `page.string` [measured, scratch tool], the detectors are
level: Kalispell 0.769 alone, 0.794 / 0.795 / 0.795 with PaddleOCR-VL on YOLO's / PP's / heron's regions and 0.795 /
0.795 / 0.796 with Falcon; the comic 0.833, 0.845 / 0.845 / 0.846 and 0.847 / 0.846 / 0.850; Billings 0.790, 0.815 /
0.818 / 0.820 and 0.815 / 0.819 / 0.821; October 1960 0.847, 0.859 / 0.856 / 0.858 and 0.859 / 0.858 / 0.859. The
arrangement mends only Vision's lines inside a region, so ink outside every region keeps Vision's reading rather than
losing it, which is why coverage mattered less than the fit test suggested. Nothing to queue for a switch. The fused rows are not the regions' (C41); the fix,
cutting a Vision line where it crosses two regions before alignment, is the parked `c41-newspaper-scans` item as
ocr-requeue re-scoped it (ESTIMATE 1-2 sessions), which this measurement supports: 14-18 of the 35-37 one-run rows lie
on a boundary between two of YOLO's or heron's regions. It stays parked: the owner parked it on 2026-10-14, and
parked items come back by the owner's hand, so the question whether to queue it again is under RUN.md's NEEDS OWNER
(2026-10-16). The DONE WHEN check (a subagent, against the raw runs) passed the table, C41's answer, the notes, lc-run
and lc-fused, and found the two overstatements corrected above (the rows held by no region, and the few rows made
after reading).

Fit test [measured, `/tmp/lc-fit`, 300 dpi renders]: every detector detects in under a second a page on the CPU
(heron 0.3-0.6 s at 640 px, PP 0.3-1.0 s, YOLO 0.4-0.7 s); peak RSS heron 1.0-1.4 GB, YOLO 0.6-1.2 GB, PP 0.3-0.8 GB.
Ink inside text regions (each script's own measure): YOLO 0.43 on Kalispell and 0.44 on the comic, where heron
reads 0.93 and 0.89 and PP 0.71 and 0.57; the other pages 0.80-1.00 for all three. Heron returns exactly 300
detections on the comic and Helena 1941 at 0.3: RT-DETR keeps its 300 best (box, label) pairs, so a box can come
twice under two labels (237 and 241 distinct boxes there) and boxes over 0.3 beyond the 300th are cut, on dense
broadsheets. Heron's `picture` boxes are the advertisements and the photograph, with their text blocks boxed
separately inside them, so dedupe-regions.py drops them as it drops PP's `image` (the diff review caught that it
did not; before the fix a kept picture box absorbed 21-27 text boxes on the comic and Helena 1941).
