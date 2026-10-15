# photo-pdf-size — round notes

## 2026-10-14 — pps-route (Opus 5.5, medium)

Reproduced with a copy of `Tools/score-gate.swift` whose corpus also takes image files, built from
origin/main 07736de: `00187 — Baker.JPG` published at 831,199 B (the owner's Vision file, to the byte),
one 1936x2592 colour JPEG on a 1936x2592 pt page. With Falcon-OCR, 830,376 B, also the owner's figure.

THE CAUSE, two defects, both found by running code:
- `makeSearchablePDF`'s layering pass opened `Flattener.open(inputFile, …)`. For an image input that is
  the JPEG, which PDFKit cannot open, so `source` was nil and the whole loop was skipped: no image input
  was ever layered. Now `file`, the wrapped PDF (the annotation transplant had the same fix already).
- The image was wrapped to `scratch/<name>.pdf`, which is the path the rebuild writes (`rebuilt`), so
  `flatten` truncated its own source as it wrote. That is why every image input reported "the original's
  page numbers and title could not be carried across" (seen on all five images tried). Now wrapped into
  `work/input/`.

THE SIZE. A camera writes 72 dpi. `Flattener.cameraResolution`: an image whose TIFF dictionary names a
Make or Model, declaring 72 dpi or nothing, is fitted to a US Letter sheet in its own orientation, never
below 72 dpi. Baker: 1936x2592 pt (27x36 in) -> 591.6x792 pt at 235.6 ppi; ABBYY assumed 290 ppi
(482x644 pt). Rejected: finding the paper's edge (needs Vision's document segmentation, and the size
would then depend on the framing); A4 (3% larger on the long side, the same to a reader); fitting every
72-dpi image, which would also cover photos whose EXIF a messaging app stripped but would move
screenshots too. An EXIF-stripped photo keeps the 72-dpi page size and is still layered (82 KB below).

AFTER (Photo detail smallest, which is the owner's setting, and balanced, the default, give the same
bytes, because the page passes `pageIsAllText()` and both factors rise to 8):
| input | before | after | words (pdftotext) |
|---|---|---|---|
| Baker, Vision | 831,199 B, 1936x2592 pt | 78,643 B, 591.6x792 pt | 463 / 463 |
| Baker, Falcon-OCR | 830,376 B | 77,810 B | 465 / 465 |
| Baker, EXIF stripped, PNG | 831,199 B, 1936x2592 pt | 82,347 B, 1936x2592 pt | 463 / 463 |
| Mintzberg p1 as a 72-dpi JPEG with camera tags | 23,727 B, 2360x1795 pt | 23,747 B, 792x602 pt | 23 / 23 |
| the same untagged, at 72 dpi / at 200 dpi | 23,306 / 23,316 B | unchanged, sizes unchanged | 23 / 23 |
Layers on Baker: a 1936x2592 JBIG2 stencil at 236 ppi (37.6 KB), a 29 ppi background (10.7 KB), a
15 ppi foreground (3.4 KB), and a mark layer at 79 ppi (4.9 KB). Looked at through PDFKit at 2.5x: the
type is legible and a little heavier than the photo; the signature is softer. That trade is pps-ladder's
question, not this step's.
Checked: suite 1998/1998; `ux-regression.sh` 0 worse, 0 better over 53 pages and 40 documents; four of
the new checks go red with the three fixes taken out; a separate verifier passed layering, page size,
bytes, word counts and PDFKit findString (executives 3, Marshall 1, treatise 2, before and after).
Next: pps-ladder. Baker sits at about 78 KB at both shipped Photo detail steps, so the ladder needs steps
that the all-text rule does not override (the stencil's resolution, the background factor on accepted pages).

## 2026-10-14 — pps-ladder (Opus 5.5, medium)

Published from a scratch copy of `Sources/` (not committed) in which `textPageBackgroundDownsample` and
`textPageForegroundDownsample` read `PPS_BG`/`PPS_FG`; Photo detail balanced, so each step is the factor
set. Steps 1/2..1/8 with the foreground at twice the background: 244,910 / 148,616 / 112,950 / 87,482 /
78,643 B, 463 words each; Maximum is 813,098 B. The stencil is the same at every step, so the type does
not change; the signature and the paper do. 60 KB needs a smaller stencil (ours 37.6 KB at 236 ppi,
ABBYY's 23 KB at 290). Files and crops: `$STATE/photo-size-ladder/` (third-party, not committed).
Recommended 1/4 in `PHOTO-SIZE-DECISION-2026-10-14.md`; the question is under RUN.md's NEEDS OWNER.
For pps-ship: the factors are applied in `mrcLayers` (`bgFactor`/`fgFactor`), on pages `pageIsAllText()`
accepts; an image-input step needs a way to tell `mrcLayers` the page came from an image file.

## 2026-10-14 — the content floor for photos (Opus 5.5, medium; pps-owner-pick still open)

Tried 1406877 on five owner archive photos (iPad, 72 dpi, Make/Model; `$STATE/photo-sample-pps/`), before
(07736de) -> after (default settings): clipping 1,573,114 -> 408,190 B; table 889,646 -> 48,136; handwritten
855,787 -> 46,220 and 986,943 -> 53,741; 1922 letter 856,162 -> 221,144. Words and findString unchanged on all.
But at 8/16 two lose content, seen in 2x PDFKit crops: the table's faint digits break ("1979-80" -> "1?79-6?",
"BS" -> "8S", the rule under the header gone) and a pencil sheet on the handwritten card is a smudge. The
stencil drops those strokes (uneven light), and a 29 ppi background cannot carry them. Ladder on those two:
2/4 171,146 / 195,086 B; 3/6 94,896 / 109,064; 4/8 70,630 / 81,387; 8/16 48,136 / 53,741. Legible at 4/8 and
finer, not at 8/16. Shipped: `mrcLayers(fromImage:)` caps an image input's all-text factors at
`imagePageBackgroundDownsample`/`imagePageForegroundDownsample` = 4/8 (Baker 79 -> 113 KB). It is a floor for
content, not the owner's pick; 1/2 or 1/3 remain open. Rejected: camera images only (an EXIF-stripped photo
has the same light), and fixing the stencil's threshold for photos (larger change; the background suffices).
