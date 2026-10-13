# Vision, PaddleOCR-VL and Falcon-OCR side by side: results and the settings table, 2026-10-13

This is for the owner (`ocr-compare-report`), for the choice in `ocr-hybrid-approve`. It decides nothing. It follows
the owner's approach of 2026-10-12: the accurate mode offers Vision, PaddleOCR-VL 1.6 4-bit and Falcon-OCR bf16, the
user picks which reads each kind of page from a table of measured speed and accuracy, and the app tells the kinds
apart by itself. The owner's aim was to "fully compare Vision, PaddleOCR, Falcon-OCR, and make sure we're getting
real advantages and providing users with a real sense of the differences."

The figures come from `OCR-COMPARE-2026-10-13.tsv` and its `-pages.tsv`: every reader in every arrangement that suits
it, run through the app on the 67-page sample (11 newspaper pages, 56 others) on the night of 2026-10-12, all 458
runs published, none failed. They were measured by running code on this Mac. The per-page counts below (how many
pages a reader made better or worse) were counted from the pages file for this document. The times for a whole
book or newspaper are worked out from the per-page means, not timed. Where something is reasoned rather than
measured, the text says so.

## How to read the figures

- **Wrong or missing**: the share of the truth transcript's words that a reader copies wrong or cannot copy at all.
  Lower is better. **Cut** is how much smaller that share is than Vision's alone on the same pages.
- **Copy**: (wrong + missing + added) / words, lower is better. It also punishes words the layer holds that the
  transcript does not.
- **Find**: the share of words a search finds, higher is better.
- **Time** is the app's own time a page, model calls included, against Vision reading the whole page.
- **Peak memory** is the memory guard's largest sample of the model's processes. The app's own Vision memory is in
  no figure.
- Vision on regions' memory is the layout model's, 612 MB at most; it runs for about 3 s, so the guard often
  missed it (2 MB on newspapers), and that figure is a floor.
- **Download** is the weights on disk. Every model also needs a runtime, about 0.8 GB for the lab's Python and MLX
  as it stands, until `ocr-integrate-engine` packages one; a packaged runtime may differ.
- The arrangements: **whole** (Vision reads the page, as the app does now), **regions** (DocLayout-YOLO cuts the
  page into layout regions, the reader reads each, and its words go into Vision's lines), **align** (the model
  reads the whole page and its words go into Vision's lines), **fill** (the model reads only the lines Vision
  skipped or was unsure of).

## 1. Each reader in its best arrangement

### Books, articles and other print (56 pages, 25,414 words)

| Reader | Best arrangement | Wrong or missing | Cut | Copy | Find | Time | Peak memory | Download |
|---|---|---|---|---|---|---|---|---|
| Vision | whole | 304 (1.20%) | - | 0.039 | 0.989 | 3.4 s | - | none |
| Vision | regions | 278 (1.09%) | 0.09 | 0.054 | 0.985 | 2.0x | 0.6 GB (layout model) | 72 MB |
| PaddleOCR-VL | regions | 183 (0.72%) | 0.40 | 0.036 | 0.992 | 3.9x | 2.4 GB | 682 MB + 72 MB |
| Falcon-OCR | align | 161 (0.63%) | 0.47 | 0.034 | 0.993 | 4.1x | 3.9 GB | 1.0 GB |

Falcon-OCR on regions comes close to its align (0.66%, cut 0.44, 4.2x) but needs more memory (4.9 GB) and the
layout model, so align is its print arrangement. PaddleOCR-VL has no whole-page arrangement: it caps its input near
one megapixel, so a whole page is read at a fraction of its scan. Fill, with either model, cuts 0.07 at 1.2x.

How evenly the gain falls, page by page against Vision alone: Falcon align is better on 25 of the 56 pages and
worse on 5; PaddleOCR-VL regions better on 23 and worse on 8; Vision on regions better on 17 and **worse on 15**.
No page carries the models' gain: the most any one page gives is 22 words of Falcon's 143.

### Newspapers (11 pages, 24,867 words)

| Reader | Best arrangement | Wrong or missing | Cut | Copy | Find | Time | Peak memory | Download |
|---|---|---|---|---|---|---|---|---|
| Vision | whole | 7,368 (29.6%) | - | 2.18 | 0.85 | 23 s | - | none |
| Vision | regions | 6,600 (26.5%) | 0.10 | 2.21 | 0.87 | 1.4x | 0.6 GB (layout model) | 72 MB |
| PaddleOCR-VL | regions | 5,428 (21.8%) | 0.26 | 2.12 | 0.91 | 2.6x | 2.5 GB | 682 MB + 72 MB |
| Falcon-OCR | regions | 5,309 (21.3%) | 0.28 | 2.11 | 0.92 | 2.9x | 3.7 GB | 1.0 GB + 72 MB |

Neither model reads a whole newspaper page: earlier tests found it makes them loop or trips the memory guard. Fill
cuts 0.05-0.07 at 1.5-1.6x.

Both models are better than Vision on all 11 pages, and worse on none. Vision on regions is better on 8 and worse
on 3, the worst a clipping (s41, 83 -> 106 words wrong or missing). Most of every reader's gain comes from the six
whole broadsheet pages, where Vision misses the most: PaddleOCR-VL's three largest gains are 616, 385 and 341 words.

Copy cannot separate the readers on newspapers. Every reader's layer holds about twice as many words as the
transcripts (47,000 to 49,000 "added" against 24,867 scored, measured), so the figure is above 2 for all of them
and moves by less than 5% between the region readers. Why the transcripts hold so few of the page's words was not looked into
for this document.

## 2. Where a model gives no real advantage over Vision

- **Vision on regions, off newspapers: no advantage.** It cuts 9%, makes 15 of 56 pages worse, adds words
  (688 -> 1,081) so that Copy gets worse (0.039 -> 0.054), and doubles the time. Leave it out of the print choices.
- **Fill, with either model, on either kind: no real advantage.** A cut of 5-7% does not pay for a download and a
  runtime. Vision gives almost all of its misreads full confidence, so fill sends the model very few lines.
- **PaddleOCR-VL against Falcon-OCR: little difference between them.** On newspapers they are within half a point of
  each other; PaddleOCR-VL is a little faster (2.6x against 2.9x), uses less memory (2.5 GB against 3.7 GB) and
  downloads less. Off newspapers Falcon-OCR is a little more accurate (0.63% against 0.72%) at about the same time,
  with more memory. A user offered both would be choosing between near-equals; the real difference is between
  either model and Vision.
- **Both models against Vision: a real advantage on both kinds.** On print they halve the misread words, from
  about 12 in 1,000 to about 6 or 7, at four times the time. On newspapers they cut about a quarter, from about 30
  in 100 to about 22, at under three times the time, and make no page worse.

## 3. Should Vision on regions become the standard newspaper route?

**Recommended: no, not as the standard. Offer it in the accurate mode as the newspaper reader for a user who
downloads no model.**

- It does help newspapers a little: 10% fewer words wrong or missing, Find 0.85 -> 0.87, at 1.4x the time and no
  model, only the 72 MB layout model.
- But it makes 3 of 11 newspaper pages worse, one by 28%, and the gain is about two fifths of what either model gives.
- The app has no layout model in it today. Packaging DocLayout-YOLO in the app (Core ML or another form the helper
  loads) is part of `ocr-integrate-engine` for the model routes. Done for that, Vision on regions comes nearly free;
  done for Vision alone, it is a lot of building for a tenth (reasoned, not measured: the packaging has not been
  sized).
- The lab's larger whole-page-against-regions gap (NewsBench 1-CER 0.304 -> 0.741) scored the region crops' text
  alone. Here the region words only mend Vision's lines and the layer keeps Vision's placement, which is likely why
  the gain is so much smaller (reasoned, not measured).

The option rejected: making Vision on regions the standard for every newspaper page with the accurate mode off. It
would make the default route slower and worse on some pages for a small gain, and tie the default to a layout model
the plain app does not otherwise need.

## 4. The detector's misreads, both ways

From `ocr-newspaper-detect` (`PAGE-KIND-2026-10-12.tsv`, 152 pages; section 4 of `OCR-HYBRID-DECISION-2026-10-12.md`):

- **Print called a newspaper: 0 of 105** (0 of 56 in the sample, 0 of 49 outside). The nearest miss is the
  Congressional Record, 0.209 of the page against the 0.2 edge.
- **Newspaper called print: 6 of 47** (4 of 11 in the sample, 2 of 36 outside). All six are clippings, one article
  cut to a page. All 36 whole newspaper pages were called newspapers.

What the misreads cost, from this run's pages: the four sample clippings called print would go to the print reader.
Vision is what reads them today. On regions the two models read three of them better (s17 26 -> 14, s40 9 -> 0,
s41 83 -> 46 or 49) and the fourth the same (s44 78 -> 73). Falcon align, the print reader, was not run on them,
since it was not run on newspaper pages at all, so what a user who picks Falcon for print would get on a clipping is
unmeasured. The error that would hurt, a broadsheet sent whole to a model, did not happen.

## 5. What each reader costs a user

Worked out from the per-page means on this Mac (3.4 s for Vision on a print page, 23 s on a newspaper page), not
timed as whole documents. Five of the 11 newspaper pages are clippings, so a newspaper of whole broadsheet
pages would take longer than the figures say:

| Reader | A 300-page book | A 20-page newspaper |
|---|---|---|
| Vision | about 17 minutes | about 8 minutes |
| Vision on regions | about 34 minutes | about 11 minutes |
| PaddleOCR-VL | about 66 minutes | about 20 minutes |
| Falcon-OCR | about 69 minutes | about 23 minutes |

Download, once: PaddleOCR-VL 0.75 GB with the layout model, Falcon-OCR 1.0 GB (1.07 GB with the layout model, which
its newspaper arrangement needs), and the shared runtime, about 0.8 GB as it stands. Memory at the slider's default
of 5 GB: everything fits. Falcon-OCR's largest peak, 4.9 GB, was on print regions, which is not its print
arrangement; on align it peaked at 3.9 GB. At 4 GB both still fit in their best arrangements, PaddleOCR-VL
with 1.5 GB to spare and Falcon-OCR with 0.1 to 0.3 GB, too little to rely on.

## 6. The table the settings would show (draft)

In words a user reads. The accuracy figures are ours, measured on our sample, and ship with the app; the speed
column is ours until the user's own timing run replaces it. "Words wrong or missing" is out of every 1,000 words.

**Newspapers**

| Reader | Words wrong or missing, of 1,000 | Speed | Memory | Download |
|---|---|---|---|---|
| Vision (built in) | about 296 | about 23 seconds a page | no extra | none |
| Vision with layout regions | about 265 | about 1.4 times as long | about 0.6 GB | 72 MB |
| PaddleOCR-VL | about 218 | about 2.6 times as long | needs 2.5 GB | 0.75 GB |
| Falcon-OCR | about 214 | about 2.9 times as long | needs 3.7 GB | 1.1 GB |

**Books, articles and everything else**

| Reader | Words wrong or missing, of 1,000 | Speed | Memory | Download |
|---|---|---|---|---|
| Vision (built in) | about 12 | about 3 seconds a page | no extra | none |
| PaddleOCR-VL | about 7 | about 4 times as long | needs 2.4 GB | 0.75 GB |
| Falcon-OCR | about 6 | about 4 times as long | needs 3.9 GB | 1.0 GB |

A line under both tables: "The models also need a shared component, about 0.8 GB, downloaded once. Measured on 67
pages of our own sample; your documents may differ."

Vision on regions appears only in the newspaper table, by section 2. Whether the newspaper table offers both models
or one is the owner's choice (section 2: they are near-equals there).

## 7. For the owner

What this changes in `ocr-hybrid-approve`'s question: both models give a real advantage over Vision on both kinds
of page, and neither gives much over the other. Fill gives none, and Vision on regions a little, on newspapers
only. Nothing here is chosen.
