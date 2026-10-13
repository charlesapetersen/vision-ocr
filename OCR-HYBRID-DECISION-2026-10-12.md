# Which better reader, if any, should the app use? Results and options, 2026-10-12

This is for the owner to decide (`ocr-hybrid-pick`; the owner's words of 2026-10-08: "Require that I be informed of
the results, given a number of options, and approve next steps"). Nothing here has been chosen. The figures come from
`OCR-HYBRID-2026-10-12.tsv` (every route run through the app on the 67-page sample) and `OCR-BITS-2026-10-11.tsv`
(each model at two bit widths). Both were measured by running code on this Mac. The download sizes are measured
from the weights on disk. Where a figure is an estimate rather than a measurement, the text says so.

## The rule the routes were scored against

A route passes if it does all three of these:

- it cuts the words wrong or missing by at least a third, on old print or on newspapers;
- it takes no more than three times as long per page as Vision alone;
- it stays under 12 GB of memory on this Mac.

## 1. Results

**No route passes the rule as it stands.** Off newspapers, the routes that make the cut are four or more times
slower than Vision. On newspapers, the routes that are fast enough cut about a quarter of the errors, short of a
third.

The four ways of using a model (from `ocr-hybrid-proto`):

- **align**: the model reads the whole page, and its words go into Vision's lines.
- **replace**: the model's own text blocks are used, and Vision's lines are kept only where the model has none.
- **fill**: the model reads only the lines Vision skipped or was unsure of.
- **regions**: newspapers are cut into layout regions with DocLayout-YOLO, the model reads each region, and its
  words go into Vision's lines.

### Books, articles and other print (56 pages, 25,414 words scored)

Vision alone gets 304 words wrong or missing (1.20%) and takes 3.5 s a page.

| Route | Wrong or missing | Cut | Time vs Vision | Peak memory | Download |
|---|---|---|---|---|---|
| Chandra OCR 2 oQ8, replace | 132 (0.52%) | 0.57 | 19.6x (68 s) | 9.8 GB | 4.8 GB |
| Falcon-OCR bf16, align | 161 (0.63%) | 0.47 | **4.0x (14 s)** | 4.5 GB | 1.0 GB |
| Chandra OCR 2 oQ8, align | 169 (0.66%) | 0.44 | 16.1x (56 s) | 8.1 GB | 4.8 GB |
| LightOnOCR-2 8-bit, align | 180 (0.71%) | 0.41 | 4.1x (14 s) | 8.9 GB | 1.4 GB |
| any of the three, fill | 282 (1.11%) | 0.07 | 1.2-1.5x | 1.5-6.2 GB | as above |

What the table leaves out:

- **Chandra replace makes copied text worse.** It has the most words right, but the words it adds rise from 852 to
  4,024, and its Copy error goes from 0.046 to 0.164 (lower is better). Why has not been looked into. The other
  routes leave Copy as it was, or a little better: Falcon align scores 0.041.
- **Fill is cheap but barely helps.** Vision gives almost all of its misreads full confidence, so fill sends the
  model very few lines: 23 crops over 93 owner pages (`hp-fill`'s measurement in `QUEUE.md`).
- **Find.** The share of words a search finds rises from 0.989 to 0.993 with Falcon align.

### Newspapers (11 pages, 24,867 words scored)

Vision alone gets 7,368 words wrong or missing (29.6%) and takes 24 s a page.

| Route | Wrong or missing | Cut | Time vs Vision | Peak memory | Download |
|---|---|---|---|---|---|
| Falcon-OCR bf16, regions | 5,309 (21.3%) | 0.28 | 2.8x (68 s) | 3.9 GB | 1.0 GB + 72 MB |
| PaddleOCR-VL 1.6 4-bit, regions | 5,428 (21.8%) | 0.26 | 2.4x (60 s) | 2.5 GB | 682 MB + 72 MB |
| LightOnOCR-2 8-bit, regions | 5,465 (22.0%) | 0.26 | 5.3x (131 s) | 10.2 GB | 1.4 GB + 72 MB |
| Chandra OCR 2 oQ8, regions | 5 of 11 pages failed | (0.29 on 6) | 18.8x | 7.1 GB | 4.8 GB + 72 MB |
| any of the three, fill | about 7,000 | 0.04-0.05 | 1.6-3.8x | 1.6-6.2 GB | as above |

The 72 MB is the DocLayout-YOLO layout model. On every newspaper page that Chandra's reading failed, a call to
the model ran into the 540-second limit on one reading (`ocr-hybrid-run`'s record in `QUEUE.md`), so the app failed the page rather than publish only part of it. Find
rises from 0.85 to 0.92 with Falcon regions. Align and replace were not run on whole newspaper pages: earlier
tests found that a whole newspaper page makes the models loop, or trips the memory guard.

### Not run, by design

- Falcon replace and LightOnOCR replace: neither model writes boxes for text.
- Regions off newspapers: regions is the newspaper arrangement.

### Time on this Mac

The times are the app's own, per page, on a quiet machine. Here is what they mean for a whole document:

- **A 300-page book:** about 17 minutes with Vision alone, and about 70 minutes with Falcon align.
- **A 20-page newspaper:** about 8 minutes with Vision alone, and about 23 minutes with Falcon regions.

These two figures are reasoned from the per-page means, not timed.

### The build each memory limit would use

Peak memory is the guard's figure, for the whole reading process. The memory-limit setting would choose from the
builds listed for its limit.

- **4 GB.** Newspapers: PaddleOCR-VL regions (2.5 GB), or Falcon regions (3.9 GB, with only 0.1 GB to spare).
  Other pages: fill only (Falcon 1.5 GB, LightOnOCR 2.0 GB). Falcon align needs 4.5 GB, so it does not fit.
- **5-6 GB.** Falcon-OCR bf16 for everything: align off newspapers (4.5 GB) and regions on them (3.9 GB).
- **7-8 GB.** As at 5-6 GB. Chandra oQ4 also fits here: 6.3 GB for whole pages in the bits run. In that run it
  missed 0.51% of words, against 0.49% for oQ8, in 73-82% of oQ8's time. Chandra oQ4 was not run through the
  app, so its figures for replace and align here (about 7.5 GB, and about 15x Vision's time) are estimates.
- **9-12 GB.** Chandra oQ8 replace (9.8 GB) or align (8.1 GB), LightOnOCR-2 8-bit align (8.9 GB) and regions
  (10.2 GB). None of these does better than Falcon on every count. Chandra replace has the most words right but
  is 20 times slower and makes Copy worse. LightOnOCR is as fast as Falcon off newspapers (4.1x against
  4.0x), but on newspapers it is nearly twice as slow (5.3x against 2.8x). It also needs twice the memory and
  cuts fewer errors.

Between 5 GB and 12 GB, one model, Falcon-OCR bf16, is the best choice at every limit. Giving it more memory buys
nothing that is worth having.

## 2. Options

**A. Adopt nothing, and the queue goes on as before.**

- What it gives: no new downloads, no slower mode, and nothing more to maintain. The work on the other defects
  (C41, C52, C56) goes ahead.
- What it costs: the measured gain is left unused. That is about half the misread words on ordinary print, and a
  quarter on newspapers.
- What happens next: `ocr-integrate-*` and `ocr-requeue` are ticked as "adopt nothing", and nothing is built.

**B. Falcon-OCR alone, as an opt-in accurate mode that is off by default.** Off newspapers it uses align, and on
newspapers it uses regions.

- What it gives: 47% fewer words wrong or missing on ordinary print, 28% fewer on newspapers, and better Find on
  both.
- What it costs:
  - a download of about 1.9 GB: 1.1 GB for Falcon and the layout model, and 0.8 GB for the lab's Python and MLX
    runtime as it stands (both measured on disk; a runtime packaged for the app may differ);
  - memory: about 4.5 GB at its peak, so it runs from the 5 GB step up;
  - time: 4x Vision's on ordinary print and 2.8x on newspapers.
- Against the rule: it misses on two counts. It is slower than the rule allows off newspapers (4.0x against 3x),
  and on newspapers it cuts 0.28 against the 0.33 required.
- Building it: one model to integrate, not three, and the memory-limit setting has little to choose.
- **This is the cheapest route close to the rule. None meets it.**

**C. Newspapers only: PaddleOCR-VL regions, opt-in.** Every other page keeps Vision.

- What it gives: 26% fewer errors on newspapers.
- What it costs: a 0.75 GB download (and the runtime), 2.5 GB of memory, and 2.4x Vision's time on newspapers.
  It runs at every limit from 4 GB up.
- Against the rule: like Falcon regions, it is inside the rule on time and memory, but it falls short on the
  cut, 0.26 against 0.33. It is the smallest and fastest region reader, and Falcon cuts slightly more (0.28).
- What it leaves out: ordinary print gets nothing. The app does not tell newspaper pages from the rest by itself.
  The nearest thing it has is the user's choice of the Newspaper preset, and B and D need the same split.

**D. B, plus Chandra OCR 2 as a choice at 9 GB and above.** This is the owner's 2026-10-02 picture: a choice of
models under the memory setting.

- What it gives: the most words right off newspapers, a 57% cut.
- What it costs: 20x Vision's time, a 4.8 GB download, and Copy 3.6 times worse. Chandra also failed 5 of 11
  newspaper pages at the time limit.
- Building it: it needs a second model integrated, and the fix for its added text first.

## 3. Recommendation

**Recommended: B.** Falcon-OCR bf16 is the best reader on every count measured except one: Chandra replace has
slightly more words right, and pays heavily for it in time and in Copy. Off newspapers it is the fastest of the routes that
make a real cut, and on newspapers it is within 0.4x of PaddleOCR-VL's time. One model covers every memory limit from 5 GB, which keeps the integration to the one model the evidence
supports.

B misses the rule, by 4.0x against 3x on time off newspapers and by 0.28 against 0.33 on the newspaper cut. The
rule was set before anything had been measured. A mode that is off by default and chosen for accuracy can
reasonably cost four times Vision's time. But it is the owner's rule, so approving B means relaxing it, and that
should be said plainly.

If the owner wants the rule kept as it is, A is the honest answer. C is the narrow alternative if only newspapers
matter.

Not offered as options (the recommendation's reasons, not decisions):

- **Fill, with any model.** It is fast, but it cuts errors by 4-7%. That is too small for a download and a second
  runtime.
- **LightOnOCR-2.** It is as fast as Falcon off newspapers, but nearly twice as slow on them, needs twice the
  memory, and cuts fewer errors.

## 4. Telling newspaper pages apart (`ocr-newspaper-detect`, added 2026-10-12)

The options above lean on the user labelling newspapers. The app can now tell them itself, page by page, from
what it already has before any model runs: whether the page is a paste-up of scanned strips (`Flattener.mosaic`),
and the shape of Vision's own reading. A page is called a newspaper when it is a paste-up, when it holds 600
lines or more, or when it holds 200 or more and its widest lines (the widest tenth) reach less than a fifth of
the page, which is five columns or more. `Recogniser.pageKind`; nothing calls it yet, and it changes no setting.

Measured on 152 pages (`PAGE-KIND-2026-10-12.tsv`): the 67 of the sample, and 85 more (the other newspapers in
the corpus, C39's Raskin and C41's 1960 page, NewsBench's 19 pages, the first two pages of each magazine,
the Congressional Record).

- **Print called a newspaper: 0 of 105** (56 in the sample, 49 outside). The closest is the Congressional
  Record, three columns at 0.209 of the page and 340 lines, against the edge at 0.2. That margin is thin.
- **Newspaper called print: 6 of 47** (4 of 11 in the sample, 2 of 36 outside). All six are clippings, one
  article cut to a page in two to four wide columns, which is what print looks like. Every whole newspaper page
  was called a newspaper, 36 of 36, NewsBench's 19 included. The widest one under 600 lines reaches 0.182.

So the error that matters, a broadsheet sent whole to a model, did not happen. A clipping read as print goes to
the print route, which is how Vision reads it now. On the sample's four, regions read better (fewer words wrong
or missing: Falcon 14 against Vision's 26 on s17), but no whole-page model has been measured on them.

Page size was not used. Women's Wear Daily of 1947 is a full newspaper page scanned at A4, filed in Zotero as a
magazine; clippings come on letter paper; NewsBench's pages are photographs with no size. The figures come from
the no-rebuild route's reading of a plain render. The app reads the rebuilt bitmap, which gives slightly
different lines.
