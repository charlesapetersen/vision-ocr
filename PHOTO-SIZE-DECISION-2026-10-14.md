# Photo size decision: which compression step for a phone photo of a page (photo-pdf-size, pps-ladder)

**For the owner.** Pick one of the five steps below for image inputs (phone photos and other dropped images).
Today's app (1406877 and later) publishes Baker at step 1/8, 79 KB. Before 1406877 it was 831 KB.

The files and the crops are on this Mac, not in the repository, because the letter is not ours to publish:
`~/.local/state/visionocr-autonomous/photo-size-ladder/`

- `Baker-step-bg<N>-<bytes>B.pdf`: the five published files. Open them in Preview to compare.
- `crops/<passage>-ladder.png`: one passage cut from the source photo and from each step, stacked top to
  bottom, rendered at 2x through PDFKit (what Preview uses). The passages are `body` (seven lines of the
  letter), `signature` ("Sincerely yours" and the signed name), `header` (the "Mr. John S. Baker --2" line)
  and `margin` (the text showing through from the next sheet at the right-hand edge).

## The steps

Measured 2026-10-14 by publishing `00187 — Baker.JPG` through the production pipeline, with the background
and foreground factors set for each step in a scratch build. Every step keeps the same 1-bit type stencil
(1936x2592 at 236 ppi, 37.6 KB) and the same text layer: 463 words by pdftotext.

| step | bytes | paper (background) | ink colour (foreground) | signature, by eye at 2x |
|---|---|---|---|---|
| 1/2 | 244,910 | 968x1296, 118 ppi | 59 ppi | as the photo |
| 1/3 | 148,616 | 645x864, 79 ppi | 39 ppi | a little softer and paler |
| **1/4** | **112,950** | 484x648, 59 ppi | 29 ppi | softer, every stroke there |
| 1/6 | 87,482 | 322x432, 39 ppi | 20 ppi | paler, still readable |
| 1/8 (today) | 78,643 | 242x324, 29 ppi | 15 ppi | palest, still readable |

For reference: Photo detail Maximum gives 813,098 B (the paper kept at full size); ABBYY's file is 53 KB.

## What changes from step to step, and what does not

- **The typed text looks the same at every step.** It is drawn through the stencil, so the background
  step does not touch it. At 2x, it is heavier than in the photo, and a few letters have filled in ("m" in
  "my" and "man"), but every word reads. The owner said ABBYY's file was "a little unreadable", and it
  uses the same kind of 1-bit type mask. If the app's type is ever found too heavy, the fix is the stencil's
  threshold, not this choice of step.
- **What the step changes is everything that is not type**: the paper's tone and the signature. At 1/2 the
  signature matches the photo. Below that it gets gradually softer and paler.
- **There is no 60 KB step.** The stencil alone is 37.6 KB, and the background is only 10.7 KB at 1/8. To go
  lower, the stencil would have to shrink (ABBYY's is 23 KB at 290 ppi). That would be separate work.
- **This page has no type smaller than the typewriter's.** The header line is the smallest type on it.

## Recommendation: 1/4, 113 KB

It is less than half the 250 KB ceiling and 7x smaller than the old 831 KB. It keeps every stroke of the
signature, which on a photographed letter is often the reason to keep the image at all. Going down to 1/8
saves another 34 KB and gives a visibly paler signature. Going up to 1/2 doubles the file for a difference
that only shows at 2x.

The step would apply to image inputs only (pps-ship). Scanned PDFs keep today's rule.

## Update, 2026-10-14 evening: 1/6 and 1/8 lose content on other photos, so 1/4 now ships as the floor

Tried on five of the owner's archive photos (a clipping, a table, two handwritten pages, a 1922 letter). At 1/8,
what shipped with pps-route, a table's faint typewriter digits broke ("1979-80" drew as "1?79-6?", "BS" as
"8S") and a sheet of pencil figures became a grey smudge: uneven light leaves those strokes out of the stencil,
and only the background holds them. At 1/4 both read (table 70.6 KB, pencil page 81.4 KB). So image inputs
now take 1/4 as the most their all-text background is shrunk. The owner can still pick 1/2 or 1/3; 1/6 and 1/8
are off the table. Crops: `$STATE/photo-sample-pps/ladder/`.
