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
