# The shape signal: what the field actually does to decide text vs picture

Research conducted 2026-08-16. Every claim below carries a provenance marker:

- **`[source]`** — read in the actual code or standards text, quoted or paraphrased from it, with file and function named. Repos were cloned at HEAD on 2026-08-16.
- **`[paper]`** — read in the published PDF, section named.
- **`[inference]`** — my reasoning from a source, not something a source says. Treat as a hypothesis.
- **`[unverified]`** — I could not get to a primary source. Do not implement from this.

Repos read: `github.com/DanBloomberg/leptonica`, `github.com/tesseract-ocr/tesseract`, `github.com/barak/djvulibre`, `github.com/agl/jbig2enc`, `github.com/4lex4/scantailor-advanced`, `github.com/ocrmypdf/OCRmyPDF`.

---

## Summary

**The field does not classify pages. It segments them, and the page-level answer is a by-product.** Every working system found here — Leptonica, Tesseract, jbig2enc, ScanTailor, DjVu, and the MRC research line — produces a *pixel-level or region-level mask* separating text from non-text, and then reads whatever page-level fact it needs off that mask (Leptonica returns `htfound`, a boolean "is the halftone mask non-empty"; jbig2enc checks `pcount < 100` on each of the two resulting layers). Nobody computes a scalar per page and thresholds it. That is not a stylistic preference: the four independent implementations converge on the same architecture — **a texture/solidity seed computed at a heavy reduction, morphologically reconstructed into a mask computed at a lighter reduction** — because a seed alone is unreliable and a full-resolution analysis is too expensive. The reduction is a seed generator, never the decision surface.

**The specific signal is not stroke geometry either, and this was a surprise.** The premise that "the field's answer is connected components and stroke geometry" is only half right. Connected components, yes, everywhere. But the discriminating *statistic* is almost never a shape statistic. Leptonica's halftone detector is a **solidity** test (does a 5×5 region survive a rank-4 threshold-reduction cascade at 37.5 ppi). ScanTailor's is a **local-gradient-minimum** test (is there any flat pixel within a 35×35 window at 300 dpi). Tesseract's is a **small-blob density** test (how many sub-font-size blobs per font-size-squared grid cell). DjVu's per-blob decision is an **MDL coding-cost comparison**, and the AT&T papers say so in plain words. The current state of the art in MRC segmentation (Haneda & Bouman 2011) classifies each connected component on a 4-D feature vector of **edge depth and external colour uniformity** — with no size, aspect ratio, fill ratio or stroke width in it at all. Shape statistics do appear (Leptonica's `pixDecideIfText`, Tesseract's perimeter²/16·area), but as *filters on an already-segmented mask*, not as the primary signal. Two consequences for this project: the 210×350 / 40 DPI thumbnail is below the floor at which any of this works and cannot be the input (§7), and the specific discrimination asked for in §6 — pale line drawing vs show-through vs table shading — is **not solved by anybody**; Leptonica names bleed-through explicitly as the case where its threshold selector gives up.

---

## 1. DjVuLibre's foreground/background separator

### 1.1 It is not in DjVuLibre. `[source]`

There is no image-based foreground/background separator anywhere in the open-source DjVuLibre tree.

- `tools/csepdjvu.cpp` takes **already-separated** input. Its own header comment: *"File `csepdjvu.cpp` demonstrates a complete back-end encoder that takes separated files as input… Each page contains the following components: A run-length encoded file representing the foreground… An optional PPM image representing the background."* The separation happened upstream, outside DjVuLibre. `[source: djvulibre/tools/csepdjvu.cpp, doc comment]`
- `tools/djvudigital` is a shell script that shells out to `gsdjvu` — a patched Ghostscript with a `djvusep` output device. `[source: djvulibre/tools/djvudigital, lines ~146-168, 440-455]` That path separates at the **PostScript rendering** level: it knows a mark is text because it came from a text operator in a page description language, not because it looked at pixels. This is not applicable to scanned input.
- `grep -rn -i "segment\|separat" libdjvu/*.cpp` returns only unrelated hits (IFF chunk handling, message catalogues, URL parsing). `NEWS` mentions "Fixed djvumake mask separation feature" — that is splitting an already-encoded file, not computing a mask. `[source]`

The real separator lived in LizardTech's proprietary "DjVu Document Express" encoder and was never released. **This is a genuine negative result: DjVuLibre cannot be used as a reference implementation for this problem.**

### 1.2 What the papers say the separator was `[paper]`

Two AT&T papers describe it, and both say plainly that phase one is **colour clustering, not shape**.

LeCun, Bottou, Haffner et al., *"DjVu: a Compression Method for Distributing Scanned Documents in Color"* (1998), §3 "The DjVu Encoder":

> "The main ideas behind the foreground/background separation algorithm are the following. The image is partitioned into square blocks of pixels. A clustering algorithm finds the two dominant colors within each block. Then, a relaxation algorithm ensures that neighboring blocks assign similar colors to the foreground and the background. After this phase, each pixel is assigned to the foreground if its color is closer to the foreground cluster prototype than to the background cluster prototype. A subsequent phase cleans up and filters foreground components using a variety of criteria."

`[paper: yann.lecun.com/exdb/publis/pdf/lecun-98c.pdf, §3]`

Haffner, Bottou, Howard, LeCun, *"DjVu: Analyzing and Compressing Scanned Documents for Internet Distribution"* (ICDAR 1999), §4 "The Foreground/Background Separation", says what that "variety of criteria" is — and it is **not a shape classifier**, it is a minimum-description-length coding-cost comparison:

> "This hierarchical color clustering algorithm attempts to retain as much information as possible about the original image while quantizing the colors on two levels only… **the separation algorithm may erroneously put highly-contrasted pieces of photographs in the foreground.** A variety of filters must be applied…
>
> The main filter is designed to be as general as possible and avoids heuristics that would have to be tuned on hundreds of different kinds of documents. Since the goal is compression, the problem is to decide, for each foreground blob found by the previous algorithm, whether it is preferable to actually code it as foreground or as background. Two competing strategies are associated with data-generating models. Using a Minimum Description Length (MDL) approach, the preferred strategy is the one that yields the lowest overall coding cost…
>
> To code the blob as part of the 'smooth' background only requires a background model. To code the blob as a piece of foreground that sticks out of the background requires a foreground model, a background model and a mask model. The background model assumes that the color of a pixel is the average of the colors of the closest background pixels that can be found up and to the left… The foreground model assumes that the color of a blob is uniform… the model we use tends to favor horizontal and vertical boundaries.
>
> In summary, in the main filter, the background model allows a slow drift in the color, whereas the foreground model assumes the color to be constant in a connected component. This difference is critical to break the symmetry between the foreground and the background."

`[paper: yann.lecun.com/exdb/publis/pdf/haffner-99.pdf, §4]`

There is a third filter: *"Occasionally, the text segmented by the separation algorithm will appear inverted in the foreground image (as holes of a large connected component). Another filter detects those occurrences and corrects them."* `[paper: ibid.]`

**Order of operations, then:** (1) block-wise 2-colour clustering; (2) inter-block relaxation on the cluster prototypes; (3) per-pixel nearest-prototype assignment; (4) connected components on the resulting foreground; (5) per-blob MDL cost comparison, foreground-model (constant colour) vs background-model (slowly drifting colour) plus mask-boundary cost; (6) inverted-text correction.

**No thresholds are published.** Block size, cluster count, relaxation weights, noise model (the paper says Gaussian or Laplacian, "identical covariances… preferable") — none of these are given numerically in the open literature. `[unverified]`

Two further sources exist that I could **not** extract: the full JEI 1998 paper (`leon.bottou.org/publications/pdf/jei-1998.pdf`) and the ISMM 2002 paper Haffner/Bottou/LeCun/Vincent, *"A general segmentation scheme for DjVu document compression"* (`leon.bottou.org/publications/pdf/ismm-2002.pdf`). Both are dvips output with Type 3 bitmap fonts and custom per-font encodings and no ToUnicode maps; `pdftotext` returns scrambled bytes for the first and nothing at all for the second. I partially decoded the JEI abstract by known-plaintext alignment (confirming it matches the short paper) but the body uses a second font with a different encoding. **If more detail on DjVu's segmentation is wanted, ISMM 2002 is the paper to get, and it will need OCR or a manual read.** `[unverified]`

### 1.3 The useful part for this project

The MDL framing is directly transferable and is a much better fit to this project's problem than a shape classifier. DjVu is not asking "is this a picture"; it is asking, *per blob*, "**does representing this as bilevel-plus-flat-colour cost more or less than representing it as smooth background?**" That is the same question as "will thresholding destroy this", asked in units of bits instead of units of shape. `[inference]`

---

## 2. Leptonica's page segmentation

This is the richest vein and the most directly portable. All line numbers from `src/` at HEAD.

### 2.1 `pixGetRegionsBinary()` — `src/pageseg.c:124` `[source]`

Doc: *"pixs: 1 bpp, assumed to be 300 to 400 ppi"*. Hard floor `MinWidth = MinHeight = 100` pixels (`pageseg.c:95-96`, with the comment *"These functions are not intended to work on very low-res images"*); below that it logs an error and returns 1.

Order of operations:

```
pixr    = pixReduceRankBinaryCascade(pixs, 1, 0, 0, 0)   /* 2x, "to 150-200 ppi" */
pixhm2  = pixGenerateHalftoneMask(pixr, &pixtext, &htfound, ...)
pixtm2  = pixGenTextlineMask(pixtext, &pixvws, &tlfound, ...)
pixtb2  = pixGenTextblockMask(pixtm2, pixvws, ...)
pixtbf2 = pixSelectBySize(pixtb2, 60, 60, 4, L_SELECT_IF_EITHER, L_SELECT_IF_GTE, NULL)
                                          /* drop components with BOTH w and h < 60 */
/* expand each mask 2x back to full res */
pixhm   = pixExpandReplicate(pixhm2, 2) OR pixSeedfillBinary(NULL, pixhm, pixs, 8)
pixtm   = pixDilateBrick(pixExpandReplicate(pixtm2, 2), 3, 3)
pixtb   = pixDilateBrick(pixExpandReplicate(pixtbf2, 2), 3, 3)
```

Note the last step for the halftone mask: after expanding, it **seedfills the expanded mask into the full-resolution image** and ORs the result, so the final halftone mask follows the actual component boundaries at full resolution rather than the blocky 2×-expanded ones.

### 2.2 `pixGenerateHalftoneMask()` — `src/pageseg.c:315` — the core detector `[source]`

Doc: *"pixs: 1 bpp, assumed to be 150 to 200 ppi"*, *"This is not intended to work on small thumbnails."*

```c
/* Compute seed for halftone parts at 8x reduction */
pix1  = pixReduceRankBinaryCascade(pixs, 4, 4, 0, 0);   /* 4x further reduce; → 37.5 ppi */
pix2  = pixOpenBrick(NULL, pix1, 5, 5);                 /* 5x5 opening at 37.5 ppi */
pixhs = pixExpandReplicate(pix2, 4);                    /* back to 150 ppi */

/* Compute mask for connected regions */
pixhm = pixCloseSafeBrick(NULL, pixs, 4, 4);            /* 4x4 closing at 150 ppi */

/* Fill seed into mask to get halftone mask */
pixd  = pixSeedfillBinary(NULL, pixhs, pixhm, 4);

pixZero(pixd, &empty);  if (phtfound && !empty) *phtfound = 1;
*ppixtext = pixSubtract(NULL, pixs, pixd);
```

**Rank semantics matter.** `pixReduceRankBinary2(pixs, level)`: *"The rank threshold specifies the minimum number of ON pixels in each 2×2 region of pixs that are required to set the corresponding pixel ON in pixd."* `[source: src/binreduce.c:213-215]` So level 4 = **all four subpixels must be ON**; level 1 = any one. The cascade from a 300 ppi original is therefore `1, 4, 4` → 8× → **37.5 ppi**, i.e. one permissive step (preserve thin strokes at 150 ppi) followed by two strictly-AND steps that only solid black areas survive. The 5×5 opening at 37.5 ppi then requires a **solid black square of about 0.13 inch** to seed.

That is the whole halftone detector. It is a solidity/texture measure, not a shape measure.

Bloomberg & Vincent's own write-up of the same algorithm gives the intent and one extra fact — that the *existence* question can be answered by the seed alone: *"Starting with a 300 ppi image containing 8×10⁶ pixels, do a cascade of four 2x rank reductions… using levels 1 and 4 followed by 4 and 3… A final 5x5 erosion yields the result, and a test for fg pixels gives the answer. This is a computationally inexpensive procedure, taking only 1 msec on a standard 3 GHz processor!"* `[paper: Bloomberg & Vincent, "Document Image Applications", research.google.com/pubs/archive/36668.pdf, §2.1]` (Note the paper's levels `1,4,4,3` differ slightly from the code's `1,4,4`; the code is authoritative.)

The same section describes the clipping mask's design goal, which is the part that is easy to get wrong: *"The clipping mask is designed to connect pixels in each halftone region (so that even a single seed pixel will fill it entirely), but not to form a bridge to any pixels in non-halftone regions."*

### 2.3 `pixGenTextlineMask()` — `src/pageseg.c:396` `[source]`

Input 150–200 ppi, halftone pixels already removed, image should be deskewed.

```c
pix1   = pixInvert(NULL, pixs);                          /* background becomes fg */
pix2   = pixMorphCompSequence(pix1, "o80.60", 0);        /* large open: big white areas */
pixSubtract(pix1, pix1, pix2);
pixvws = pixMorphCompSequence(pix1, "o5.1 + o1.200", 0); /* vertical whitespace mask */

pix1   = pixMorphSequence(pixs, "c30.1", 0);             /* close chars/words into lines */
pixd   = pixSubtract(NULL, pix1, pixvws);                /* reopen column gutters */
pixOpenBrick(pixd, pixd, 3, 3);                          /* noise removal */
```

The `o80.60` step exists specifically to stop the whitespace mask from breaking text lines at large interline gaps; the comment says it must be *"bigger than the separation between columns"* horizontally and *"bigger than the separation between textlines"* vertically. At 150 ppi, 80×60 px = 0.53″ × 0.4″.

### 2.4 `pixGenTextblockMask()` — `src/pageseg.c:486` `[source]`

```c
pix1 = pixMorphSequence(pixs, "c1.10 + o4.1", 0);                       /* join lines vertically */
pix2 = pixMorphSequenceByComponent(pix1, "c30.30 + d3.3", 8, 0, 0, 0);  /* solidify per-cc */
pixCloseSafeBrick(pix2, pix2, 10, 1);
pix3 = pixSubtract(NULL, pix2, pixvws);
pixd = pixSelectBySize(pix3, 25, 5, 8, L_SELECT_IF_BOTH, L_SELECT_IF_GTE, NULL);
```

The `pixMorphSequenceByComponent` trick is worth noting: *"By closing separately, we can use a large Sel without danger of joining separate regions."* `[paper: Bloomberg & Vincent §2.1]`

### 2.5 `pixDecideIfText()` — `src/pageseg.c:1926` — the page-level boolean `[source]`

This is the closest thing in Leptonica to what this project wants. It lives in `pageseg.c` (not `classapp.c`) under the header *"Decision: text vs photo"*.

Preparation: `pixPrepare1bpp(pixs, box, 0.1, 300)` — crop 10 % off each side, and **scale to 300 ppi**. `pixPrepare1bpp` (`pageseg.c:2326`) for depth > 1 does `pixConvertTo8` → `pixCleanBackgroundToWhite(pix, NULL, NULL, 1.0, 70, 160)` → `pixThresholdToBinary(pix, 200)`. If the source resolution is unset it warns and assumes 300.

Then it removes table rules with a hit-miss transform before doing anything else, because otherwise a table reads as a picture:

```c
/* 11 x 81 Sel: vertical column of 81 hits at x=5, origin (40,5);
   MISSes at (row,col) = (20,0),(20,10),(40,0),(40,10),(60,0),(60,10)  */
pix3 = pixHMT(NULL, pix1, sel1);
pix4 = pixSeedfillBinaryRestricted(NULL, pix3, pix1, 8, /*xmax*/5, /*ymax*/1000);
pix5 = pixXor(NULL, pix1, pix4);
```

The comment explains why a hit-miss rather than a plain vertical opening: *"if we only opened with a vertical line of hits, we would remove solid regions of pixels that are not text or vertical lines."* Result: *"this should identify tables as text."*

Then smear to text lines and count components:

```c
pix6  = pixMorphCompSequence(pix5, "c30.1 + o15.1 + c60.1 + o2.2", 0);
pixFindThreshFgExtent(pix6, 400, NULL, &h);   /* bottom of the significant region */
boxa1 = pixConnComp(pix6, NULL, 8);
```

**The decision rule, verbatim from the code comment, followed by the code:**

> The following conditions at 300 ppi must be satisfied if the image is text:
> 1. There are no components that are wider than 400 pixels **and** taller than 175 pixels.
> 2. The second longest component is at least 60 % of the (possibly cropped) image width. This catches images that don't have any significant content.
> 3. Of the components that are at least 40 % of the length of the longest (n2), at least 80 % of them must not exceed 60 pixels in height.
> 4. The number of those long, thin components (n3) must equal or exceed a minimum that scales linearly with the image height.
>
> Most images that are not text fail more than one of these conditions.

```c
maxw    = width of the 2nd widest box                    /* not the widest */
boxa3   = boxes with width >= 0.4 * maxw;      n2 = count(boxa3)
boxa4   = boxa3 with height <= 60;             n3 = count(boxa4)
boxa5   = boxes with width > 400 AND height > 175;  big_comp = (count != 0)
ratio1  = maxw / w
ratio2  = n3 / n2
minlines = MAX(2, h / 125)
*pistext = !(big_comp || ratio1 < 0.6 || ratio2 < 0.8 || n3 < minlines)
```

`h/125` at 300 ppi is one line per 0.42 inch — i.e. "at least as many text lines as would fit at 30 pt leading".

**Documented limitation, and it is exactly this project's problem** (`pageseg.c:1918`):

> "(5) If `%box` is null and pixs contains both text lines and line art, this function might return `%istext == true`."

That is the only place in Leptonica that mentions line art in a segmentation context. `pixDecideIfText` is a *text-page detector*, not a picture detector, and it is explicitly documented as unreliable on mixed text + line-art pages.

### 2.6 `pixDecideIfTable()` — `src/pageseg.c:2178` `[source]`

Relevant because decorative table shading is one of this project's confusers, and because it shows the same architecture at a lower resolution.

- Doc: *"any depth, any resolution >= 75 ppi"*, *"Most of the processing takes place at 75 ppi."*
- **First it checks for an image and bails**: `pixPrepare1bpp(pixs, box, 0.1, 175)` → `pixGenerateHalftoneMask` → `if (htfound) { *pscore = 0; return; }` with the note *"Images have arbitrary content and would be likely to trigger this detector, so they are checked for first."*
- Then at 75 ppi (after a 2×2 dilation and a `pixDeskewBoth`): horizontal fg lines `"o100.1 + c1.4"` (count `nhb`), vertical fg lines `"o1.100 + c4.1"` (count `nvb`), lines removed, noise removed with `"c4.1 + o8.1"`, then invert and `"r1 + o1.100"` (→ 37.5 ppi) selecting components with width ≥ 5 for vertical **whitespace** lines (count `nvw`).
- Score: `nhb>1` +1, `nvb>2` +1, `nvw>3` +1, `nvw>6` +1. *"Setting the condition for finding a table at score >= 2 works well, except for false positives on kanji and landscape text."*

### 2.7 `pixConformsToRectangle()` — `src/pix5.c:866` `[source]`

Directly relevant to "is this a solid decorative rectangle". The doc comment is a useful piece of engineering reasoning in its own right:

> "There are several ways to test if a connected component has an essentially rectangular boundary, such as:
> a. Fraction of fill into the bounding box
> b. Max-min distance of fg pixel from periphery of bounding box
> c. Max depth of bg intrusions into component within bounding box
>
> The weakness of (a) is that it is highly sensitive to holes within the c.c. The weakness of (b) is that it can have arbitrarily large intrusions into the c.c. Method (c) tests the integrity of the outer boundary of the c.c., with respect to the enclosing bounding box, so we use it."

Implementation: invert, `pixExtractBorderConnComps(pix, 4)`, clear a border of width `dist` on all four sides, test `pixZero`. Conforming ⇔ no background path from outside penetrates more than `dist` pixels. Wrapped per-component by `pixFindRectangleComps(pixs, dist, minw, minh)` at `src/pix5.c:788`.

**Note the explicit rejection of fill ratio.** This project should not use fill-ratio-into-bbox as a rectangularity test; Bloomberg tried it and documented why it fails.

### 2.8 `pixFindPageForeground()` — `src/pageseg.c:1137` `[source]`

Not a text/picture decision — it is border-noise removal and cropping. Included because the question asked. Binarise at `threshold` (~128), scale 0.5, seed = `"o1.2 + c9.9 + o3.3"` OR `"o50.1"` OR `"o1.50"`, seedfill into the binarised image, `pixRemoveBorderConnComps`, then `"c50.50"` and take the largest 8-cc to locate the main text block; erase `erasedist` (20–30 at 2× reduction) from any edge that is more than `mindist` (~70 at 2× reduction) from that block.

### 2.9 Stroke width `[source]`

Leptonica has **two** stroke-width facilities, and neither is used in page segmentation.

`pixStrokeWidthTransform(pixs, color, depth, nangles)` — `src/runlength.c:102`. A true SWT: *"The dest Pix is 8 or 16 bpp, with the pixel values equal to the stroke width in which it is a member… This chooses, for each dest pixel, the minimum of sets of runlengths through each pixel"* over `nangles ∈ {2,4,6,8}` directions (2 → {0°,90°}; 4 → {0,45,90,135}; 6 → {0,30,60,90,120,150}; 8 → 22.5° steps). Runtime scales linearly with `nangles − 2`. It is a general image operator; nothing in `pageseg.c` calls it.

`pixFindStrokeWidth(pixs, thresh, tab8, &width, &nahisto)` — `src/strokes.c:124`. Averages two estimates:
- **Method 1**: `width1 = fgPixelCount / strokeLength`, where `pixFindStrokeLength` returns *"half the number of fg boundary pixels"* (`src/strokes.c:75`). So `width1 = 2·area / perimeter`. Documented bias: *"the computed width is a bit smaller than the average width"* because of the end caps.
- **Method 2**: distance transform (`pixDistanceFunction(pixs, 8, 8, L_BOUNDARY_BG)`), histogram of distances, walk down from the largest bucket to the largest `i` with `N(d=i)/N(d=1) > thresh` (*"typically about 0.15"*), then `width2 = 2·(i − 1 + ratio + extra)`.
- Result `(width1 + width2)/2`.

The file header says what it is for: *"These operations are intended to operate on a single text character, to regularize the stroke width… character matching by correlation, as used in the recog application, can often be improved by pre-processing both template and character images to a fixed stroke width."* **It is a normalisation tool for template matching, not a text/picture discriminator.**

---

## 3. What Tesseract does

Tesseract runs **two** non-text detectors and ORs them.

### 3.1 `ImageFind::FindImages()` — `src/textord/imagefind.cpp:247` — the Leptonica path `[source]`

```c
if (width/2 < kMinImageFindSize || height/2 < kMinImageFindSize) return empty;  /* 100 */
pixr    = pixReduceRankBinaryCascade(pix, 1, 0, 0, 0);              /* 2x */
pixht2  = pixGenerateHalftoneMask(pixr, nullptr, &ht_found, ...);   /* Leptonica, §2.2 */
if (!ht_found) return empty;
pixht   = pixExpandReplicate(pixht2, 2);
pixht  |= pixSeedfillBinary(nullptr, pixht, pix, 8);

/* Eliminate lines and bars that may be joined to images */
pixfinemask   = pixReduceRankBinaryCascade(pixht, 1, 1, 3, 3);  pixDilateBrick(..., 5, 5);
pixreduced    = pixReduceRankBinaryCascade(pixht, 1, 1, 1, 1);
pixreduced2   = pixReduceRankBinaryCascade(pixreduced, 3, 3, 3, 0);  pixDilateBrick(..., 5, 5);
pixcoarsemask = pixExpandReplicate(pixreduced2, 8);
pixcoarsemask &= pixfinemask;  pixDilateBrick(..., 3, 3);
pixmask = pixExpandReplicate(pixcoarsemask, 16);
pixht  &= pixmask;
```

Then `ConnCompAndRectangularize` (`imagefind.cpp:201`) runs `pixConnComp(pix, pixa, 8)` on the mask and calls `pixNearlyRectangular` (a Tesseract-local function, `imagefind.cpp:130`) on each component. If a component has a sharp gradient in row/column occupancy on all four sides, it is replaced by the clean rectangle — *"it indicates a probably rectangular image with unwanted bits merged on, so clip to the approximate rectangle."*

Constants (`imagefind.cpp:40-47`):

| constant | value | meaning |
|---|---|---|
| `kMinRectangularFraction` | 0.125 | occupancy below this = outside the rectangle |
| `kMaxRectangularFraction` | 0.75 | occupancy above this = inside the rectangle |
| `kMaxRectangularGradient` | 0.1 | allowed transition width as a fraction of the side ("about 6 degrees" of skew) |
| `kMinImageFindSize` | 100 | min side, and the reduced image must also clear it (so ≥ 200 px at full res) |

### 3.2 `CCNonTextDetect` — `src/textord/ccnontextdetect.{h,cpp}` — the line-drawing path `[source]`

This is the one that matters for §6. Class comment (`ccnontextdetect.h:28-30`):

> "The CCNonTextDetect class contains grid-based operations on blobs to create a full-resolution image mask **analogous yet complementary to `pixGenHalftoneMask` as it is better at line-drawings, graphs and charts.**"

This is the only place in any of the code read here that explicitly claims to handle line drawings, and it is worth understanding exactly what it does, because it is **not** a shape test on the drawing — it is a **small-blob density** test.

**Grid size = the estimated font size.** `CCNonTextDetect nontext_detect(gridsize(), bleft(), tright())` (`colfind.cpp:168`), where the ColumnFinder is constructed with `static_cast<int>(to_block->line_size)` (`pagesegmain.cpp:329`), and `line_size` is documented in `blobbox.h:784` as *"a lower-bound estimate of the font size in pixels"*, produced by `Textord::filter_noise_blobs` (`tordmain.cpp:289`). **All of this detector's constants are therefore in units of font size, not DPI** — the one scale-adaptive scheme found in this survey.

**Threshold**: `max_noise_count_ = kMaxSmallNeighboursPerPix * gridsize * gridsize` where `kMaxSmallNeighboursPerPix = 1.0/32` (`ccnontextdetect.cpp:32, 60`). At a 30 px font size that is ~28.

**Which blobs count as noise.** Every medium blob is inserted into the noise grid unless it passes *both*:
```c
double perimeter_area_ratio = blob->cblob()->perimeter() / 4.0;
perimeter_area_ratio *= perimeter_area_ratio / blob->enclosed_area();   /* = (p/4)^2 / A */
if (blob->GoodTextBlob() == 0 || perimeter_area_ratio < kMinGoodTextPARatio)  /* 1.5 */
    InsertBBox(...);            /* noise grid */
else
    good_grid.InsertBBox(...);  /* good text */
```
Comment: *"Min ratio of perimeter²/16·area for a 'good' blob… We consider a square to have unit ratio, where A=(p/4)², hence the factor of 16. Digital circles are weird and have a minimum ratio of pi/64, not the 1/(4pi) that you would expect."* `[source: ccnontextdetect.cpp:51-56]`

`GoodTextBlob()` (`blobbox.cpp:224`) returns the count (0–4) of side neighbours with a matching stroke width that are not across a rule line. Stroke width matching (`blobbox.cpp:313`, `MatchingStrokeWidth`):
```c
h_tolerance = horz_stroke_width_ * fractional_tolerance + constant_tolerance;
v_tolerance = vert_stroke_width_ * fractional_tolerance + constant_tolerance;
p_tolerance = area_stroke_width  * fractional_tolerance + constant_tolerance;
```
with `kStrokeWidthFractionTolerance = 0.125`, `kStrokeWidthTolerance = 1.5` px (`strokewidth.cpp:49,54`; CJK gets 0.25 / 2.0). The fallback `area_stroke_width_ = 2.0f * area / cblob()->perimeter()` (`blobbox.h:494-495`) — the same formula as Leptonica's method 1.

**Density and the mask.** `ComputeNoiseDensity` sums noise-blob counts over a 3×3 grid-cell neighbourhood (`NeighbourhoodSum()`), then two corrections:
- if the cell overlaps the Leptonica photo mask, add `kPhotoOffsetFraction * max_noise_count_` = 0.375 × threshold — *"used to bias the decision towards non-text, rather than supplying a definite decision"*;
- if a cell is over threshold but contains a good-text blob **and** its own original count times `kOriginalNoiseMultiple = 8` is still under threshold, zero it (the noise came from neighbours, not from here).

`pix = noise_density_->ThresholdToPix(max_noise_count_)` is the mask. Then blobs are deleted from the layout by two rules (`MarkAndDeleteNonTextBlobs`): the blob's box is mostly over threshold in the density grid, **or** it overlaps too many smaller blobs:

| constant | value | comment in source |
|---|---|---|
| `kMaxLargeOverlapsWithSmall` | 3 | large blob overlapping this many small blobs → image |
| `kMaxMediumOverlapsWithSmall` | 12 | *"Larger than for large blobs as medium blobs may be complex Chinese characters"* |
| `kMaxLargeOverlapsWithMedium` | 12 | *"set higher to allow for drop caps"* |

If the blob's box has any zero-density cell in it, the blob's **outline** is rendered into the mask rather than its bounding box — *"There is a danger that the bounding box may overlap real text."*

**This is why it works on line drawings.** A line drawing decomposes, under connected-component analysis, into many small fragments whose stroke widths do not match their neighbours' — high noise density. A halftone plate does the same thing but is also solid enough to trip Leptonica's seed. Text does not, because glyphs have matching stroke widths and pass the perimeter²/16·area ≥ 1.5 test. `[inference, from the source's own design comments]`

### 3.3 Blob size classification `[source]`

`Textord::filter_noise_blobs` (`tordmain.cpp:289`), defaults from `textord.cpp:146-152`:

| constant | default | use |
|---|---|---|
| `textord_max_noise_size` | 7 px | `bbox.height() < 7` → noise list |
| `textord_noise_area_ratio` | 0.7 | `enclosed_area >= 0.7 · w · h` → small list (i.e. **too solid to be a glyph**) |
| `textord_initialx_ile` | 0.75 | `initial_x` = 75th percentile of blob heights |
| `textord_initialasc_ile` | 0.90 | ascender estimate percentile |
| `textord_width_limit` | 8 | `max_x = 8 · initial_x` |
| `textord_min_linesize` | 1.25 | final `line_size` multiplier |

Size bands, from `initial_x` and `CCStruct::{kDescenderFraction, kXHeightFraction, kAscenderFraction} = {0.25, 0.5, 0.25}` (`ccstruct.h:31-33`):
```
max_y = ceil(initial_x * (0.25 + 0.5 + 2*0.25) / 0.5) = 2.5 * initial_x   /* above → large */
min_y = floor(initial_x / 2)                                              /* below → small */
max_x = 8 * initial_x                                                     /* wider → large */
```

**Note `textord_noise_area_ratio = 0.7`**: a component whose ink fills ≥ 70 % of its bounding box is treated as non-text *regardless of size*. That is the cheapest single "this is a solid blob" test in any of the code read here.

---

## 4. jbig2enc, OCRmyPDF, ScanTailor

### 4.1 jbig2enc `[source]`

`-s / --symbol-mode` is purely a **coding mode** (text region with a symbol dictionary vs generic region coder). It contains no "is this page suitable for bilevel" logic. Related flags: `-t <threshold>` classification threshold for the symbol coder, `-w <weight>`, `-r/--refine`, `-a/--auto-thresh`. `[source: src/jbig2.cc:61-79]` Binarisation is local (Sauvola-style) by default: *"Local BW thresholding is the default. However, if global BW thresholding is requested, use its default threshold."* (`jbig2.cc:368-373`).

What **is** there, and it is the most directly relevant code found in this entire survey, is `-S` / `-j`: *"remove images from mixed input and save separately"* / *"write images from mixed input as JPEG"*. The implementation is `segment_image()` at `src/jbig2.cc:139`, credited in the source: **"Thanks to Dan Bloomberg for this."**

```c
static const char *segment_mask_sequence     = "r11";
static const char *segment_seed_sequence     = "r1143 + o4.4 + x4";  /* maybe o6.6 */
static const char *segment_dilation_sequence = "d3.3";

pixmask4 = pixMorphSequence(pixb, "r11", 0);              /* 4x reduce, rank 1,1 */
pixseed4 = pixMorphSequence(pixb, "r1143 + o4.4 + x4", 0);/* 16x reduce rank 1,1,4,3;
                                                             4x4 open; expand 4x → 4x red. */
pixsf4   = pixSeedfillBinary(NULL, pixseed4, pixmask4, 8);
pixd4    = pixMorphSequence(pixsf4, "d3.3", 0);
pixd     = pixExpandBinaryPower2(pixd4, 4);               /* → full res */

pixSubtract(pixb, pixb, pixd);      /* binary layer loses the graphics */
if (fg pixel count of pixd < 100) return NULL;            /* no graphics on this page */
if (fg pixel count of pixb < 100) { destroy pixb; }       /* no text on this page */
pixRasteropFullImage(pixd1, piximg1, PIX_SRC | PIX_DST);  /* graphics layer = grey/colour */
```

The doc comment states the contract exactly: *"after this routine has been run: (a) the input binary image contains only text, and is NULL if there is no text, and (b) the returned color-or-grayscale image contains only the graphics, and is NULL if there is no graphics."*

Note the seed cascade here is `1,1,4,3` → **16× reduction (18.75 ppi from 300)** with a 4×4 opening, versus Leptonica's `1,4,4` → 8× (37.5 ppi) with a 5×5 opening. Same architecture, different tuning; the two permissive steps first preserve strokes longer before the strict AND steps winnow.

**This is the code this project is actually looking for.** It is a page splitter, not a page classifier, and the two `< 100` pixel-count checks are the entire page-level decision.

### 4.2 OCRmyPDF — negative result `[source]`

**OCRmyPDF never decides between bilevel and greyscale.** Its JBIG2 path only touches images that are *already* 1 bpc:

```python
if (pim.bits_per_component == 1
        and filtdp[0] != Name.JBIG2Decode
        and jbig2enc.available()):
```
`[source: src/ocrmypdf/optimize.py:141-189, extract_image_jbig2]`, and the docstring on `extract_images_jbig2` is *"Extract any bitonal image that we think we can improve as JBIG2."* It re-encodes existing bilevel images more efficiently. It has no analysis that would produce a bilevel image from a greyscale one and no per-page routing. Nothing to learn here.

### 4.3 ScanTailor Advanced — a genuinely different algorithm `[source]`

ScanTailor's "mixed" mode picture detection is **greyscale morphology**, not connected components. `OutputGenerator::Processor::detectPictures(const GrayImage& input300dpi)` — `src/core/filters/output/OutputGenerator.cpp:1994`:

```cpp
stretched     = stretchGrayRange(input300dpi, 0.01, 0.01);
eroded        = erodeGray(stretched, QSize(3, 3), 0x00);
dilated       = dilateGray(stretched, QSize(3, 3), 0xff);
grayRasterOp<CombineInverted>(dilated, eroded);   /* grayGradient = dilate - erode */
grayGradient  = dilated;

marker        = erodeGray(grayGradient, QSize(35, 35), 0x00);   /* min gradient in 35x35 */
seedFillGrayInPlace(marker, grayGradient, CONN8);               /* grey reconstruction */
reconstructed = marker;
invert(reconstructed);
holesFilled   = seedFillGrayInPlace(createFramedImage(...), reconstructed, CONN8);
if (higherSearchSensitivity) return stretchGrayRange(holesFilled, 5.0, 0.01);
return holesFilled;
```

The caller `estimateBinarizationMask` (`OutputGenerator.cpp:1839`) **rescales to 300 dpi first** (`to300dpi(trimmedImage.size(), m_dpi)`), runs `detectPictures`, then thresholds:

```cpp
const BinaryThreshold threshold(48);
pictureAreas = scaleToGray(pictureAreas, sourceSubRect.size());
return BinaryImage(pictureAreas, threshold);
```

The contrast-stretch step has a revealing comment: *"We stretch the range of gray levels to cover the whole range of [0, 255]. We do it because we want text and background to be equally far from the center of the whole range. **Otherwise text printed with a big font will be considered a picture.**"*

**What the detector actually measures:** the 35×35 grey erosion of the morphological gradient is *"the minimum local contrast anywhere within a 0.117-inch window."* Text always has some flat, gradient-zero pixel within 35×35 at 300 dpi (interline gap, intra-glyph white). Continuous tone does not. `[inference, from the operation's structure — ScanTailor has no comment explaining the intent]`

Rectangularisation (`RECTANGULAR_SHAPE` mode) is `findRectAreas(mask, WHITE, sensitivity)` — `OutputGenerator.cpp:751` — which builds per-scanline runs, joins any two rectangles whose boxes overlap when both are enlarged by `overlap = 16` px, iterating to a fixed point, then trims each rectangle using `criterium = area.width() * (sensitivity/100)`. Default `m_sensitivity = 100`, `m_pictureShape = FREE_SHAPE`, `m_higherSearchSensitivity = false` (`PictureShapeOptions.cpp:10`).

**Auto-detection is off by default in the sense that matters**: `PictureShape` defaults to `FREE_SHAPE`, and `processPictureZones` (`OutputGenerator.cpp:2362`) skips `estimateBinarizationMask` entirely if the shape is `OFF_SHAPE`.

---

## 5. Component statistics and their published values

This is the requested table. **Every row is from a primary source and the source is named.** Where a value is scale-dependent I have given the resolution it is defined at, because none of these numbers mean anything without it.

### 5.1 Per-component statistics

| statistic | definition | published values | source |
|---|---|---|---|
| **fill ratio** (ink / bbox area) | `pixFindAreaFraction` = fg / (w·h) | **≥ 0.7 ⇒ not text** (moved to the "small/solid" list before size analysis) | Tesseract `textord_noise_area_ratio = 0.7`, `textord.cpp:148`, used at `tordmain.cpp:313` `[source]` |
| **perimeter / area** | `pixFindPerimToAreaRatio` = boundary fg px / total fg px | *"always ≤ 1.0; if the average distance of a fg pixel from the nearest bg pixel is d, this has a value ~1/d"* — i.e. **≈ 1/stroke-half-width** | Leptonica `pix5.c`, doc note (3) `[source]` |
| **perimeter / size** | `pixFindPerimSizeRatio` = 0.5·boundary / (w+h) | **π/4 ≈ 0.785** for a circle; **≈ 1.0** for a rectangle with a smooth boundary; **≫ 1.0** for dendritic / fractal-like components | Leptonica `pix5.c`, doc notes (2)(3) `[source]` |
| **perimeter² / 16·area** | `(p/4)² / A` | **≥ 1.5 required for a "good text" blob**; unit ratio = square; digital circle minimum = π/64 | Tesseract `kMinGoodTextPARatio = 1.5`, `ccnontextdetect.cpp:56, 91-93` `[source]` |
| **rectangularity** | max depth of bg intrusion from the bbox boundary; conforms ⇔ no bg path penetrates > `dist` px | binary; caller supplies `dist`, `minw`, `minh`. Fill ratio and max-min distance are **explicitly rejected** as alternatives | Leptonica `pixConformsToRectangle`, `pix5.c:830-905` `[source]` |
| **stroke width (area)** | `2·area / perimeter` | used as the fallback estimate when directional widths are unavailable | Tesseract `blobbox.h:494-495`; same formula as Leptonica `pixFindStrokeWidth` method 1, `strokes.c:151-153` `[source]` |
| **stroke width (distance transform)** | largest distance bucket `i` with `N(i)/N(1) > thresh`; `w = 2(i − 1 + ratio + extra)` | `thresh` *"typically about 0.15"* | Leptonica `pixFindStrokeWidth`, `strokes.c:107-121` `[source]` |
| **stroke width match** | \|w₁ − w₂\| ≤ w₁·f + c | **f = 0.125, c = 1.5 px** (Latin); f = 0.25, c = 2.0 (CJK) | Tesseract `kStrokeWidthFractionTolerance`, `kStrokeWidthTolerance`, `strokewidth.cpp:49,54`; applied in `MatchingStrokeWidth`, `blobbox.cpp:313-327` `[source]` |
| **component height bands** | from `initial_x` = 75th percentile of blob heights | noise `< 7 px`; small `< initial_x/2`; large `> 2.5·initial_x` or `w > 8·initial_x` | Tesseract `filter_noise_blobs`, `tordmain.cpp:289-357` + `ccstruct.h:31-33` `[source]` |
| **minimum meaningful component** | — | **< 6 pixels ignored**, *"because they are nearly invisible at 300 dpi resolution"* | Haneda & Bouman 2011, §III `[paper]` |

### 5.2 Page-level / region-level statistics

| statistic | definition | published values | source |
|---|---|---|---|
| **a *large* component** | on the text-line-smeared image at 300 ppi | **w > 400 AND h > 175** ⇒ page is not text (single sufficient condition) | Leptonica `pixDecideIfText`, `pageseg.c:2039-2041` `[source]` |
| **row alignment** (cheap) | smear `"c30.1 + o15.1 + c60.1 + o2.2"` at 300 ppi, then: 2nd-widest component must be ≥ 60 % of page width; ≥ 80 % of the components at least 40 % as wide as that must be ≤ 60 px tall | `ratio1 ≥ 0.6`, `ratio2 ≥ 0.8` | Leptonica `pixDecideIfText`, `pageseg.c:2033-2048` `[source]` |
| **number of text lines** | count of long, thin components | **≥ max(2, h/125)** at 300 ppi | Leptonica `pixDecideIfText`, `pageseg.c:2047` `[source]` |
| **small-blob density** | count of small/noise blobs in a 3×3 neighbourhood of font-size grid cells | **> gridsize²/32** ⇒ non-text; photo-mask overlap adds 0.375× that | Tesseract `kMaxSmallNeighboursPerPix`, `kPhotoOffsetFraction`, `ccnontextdetect.cpp:32,50,60` `[source]` |
| **overlap count** | how many smaller blobs a blob's box majorly overlaps | large-over-small **> 3**; medium-over-small **> 12**; large-over-medium **> 12** | Tesseract `ccnontextdetect.cpp:35,40,44` `[source]` |
| **halftone solidity** | survives `1,4,4` rank-reduction cascade to 37.5 ppi then a 5×5 opening | binary; ⇒ seed for reconstruction | Leptonica `pixGenerateHalftoneMask`, `pageseg.c:333-346` `[source]` |
| **local flatness** | min of the 3×3 grey morphological gradient over a 35×35 window at 300 dpi, grey-reconstructed, inverted, holes filled | binarise at **48/255** | ScanTailor `detectPictures` + `estimateBinarizationMask`, `OutputGenerator.cpp:1994, 1881` `[source]` |
| **table evidence** | at 75 ppi: horizontal fg lines, vertical fg lines, long vertical whitespace runs | `nhb>1`, `nvb>2`, `nvw>3`, `nvw>6`, one point each; table at score ≥ 2 | Leptonica `pixDecideIfTable`, `pageseg.c:2284-2292` `[source]` |
| **word gap** | number of cc after successive dilations with a horizontal 2×1 Sel; take the iteration minimising the *change* in cc count | at 300 ppi in the worked example: characters join at dilation 5, minimum difference at **7**; *"For efficiency, this can typically be done at a resolution of about 150 ppi"* | Bloomberg & Vincent §2.4, Figure 7 `[paper]` |

### 5.3 The MRC research line's answer, which contradicts the premise `[paper]`

Haneda & Bouman, *"Text Segmentation for MRC Document Compression"*, IEEE TIP 20(6), 2011 — the current published state of the art for exactly this problem — is a two-stage algorithm, **COS** then **CCC**.

**COS (Cost Optimized Segmentation)** is block-wise, and its four per-block classes are literally the decision this project is trying to make, taken locally instead of globally:

> "Notice that for each block, the four possible values correspond to four possible changes in the block's segmentation: **original, reversed, all background, or all foreground.**"

Per block: pick the colour axis with largest variance, threshold to minimise total subclass variance (Otsu's criterion by another name), then globally minimise
```
cost = sqrt(total subclass variance / block std)  +  α·(horizontal mismatch in overlap)
                                                   +  β·(vertical mismatch in overlap)
                                                   +  γ·(fraction of block classified foreground)
```
by dynamic programming over rows of blocks, iterated (*"typically converges within 20 iterations"*). Block sizes: finest layer **32×32** at 300 dpi; the three-layer multiscale run used **36×36** at the coarsest. The last term *"is used to ensure that most of the area of image is classified as background."*

Their training loss is asymmetric in the same direction as this project's: *"the missed detections are generally more serious than false detections, so we used a value of [γ] which more heavily weighted miss detections."*

**CCC (Connected Component Classification)** then refines it — and **here is the finding that matters most for §5**:

> "The feature vector for the connected components extracted in the CCC algorithm is a **4-D vector**… Two of the components describe **edge depth** information, while the other two describe **pixel value uniformity**… the edge depth is defined as the Euclidean distance between RGB values of neighboring pixels across the component boundary… The terms describe uniformity of the **outer** pixels… only outer pixel values were examined for the uniformness because we found that inner pixel values of the connected components extracted by COS are mostly uniform even for nontext components."

The four features are: mean of edge depth, std of edge depth, range of outer pixel values (95th − 5th percentile), std of outer pixel values. The augmented vector adds only the component centre's (x, y) at 300 dpi, used for the MRF neighbourhood. **There is no size, aspect ratio, fill ratio, stroke width or shape descriptor anywhere in it.** Classification is MAP under a Gaussian-mixture data model with a pairwise MRF prior penalising label disagreement between nearby similar components.

There is also a cheap, concrete inverted-text fix worth stealing:

> "we first detect foreground components that contain **more than eight interior background components (holes)**. In each case, **if the total number of interior background pixels is less than half of the surrounding foreground pixels**, the foreground and background assignments are inverted."

`[paper: engineering.purdue.edu/~bouman/software/Text-Seg/tip30.pdf, §II-A/B, §III, Appendix]`

### 5.4 RLSA (Wong, Casey & Wahl 1982) — could not verify `[unverified]`

The structure is well attested: horizontal and vertical run-length smoothing with separate thresholds, AND the two results, additional short horizontal smoothing, connected-component the blocks, then classify each block on (block height H, eccentricity ΔX/ΔY, black-pixel-to-area ratio, and mean horizontal black run length R = black count / horizontal transition count), comparing H and R against the running means of the blocks already believed to be text. **I could not obtain the paper and therefore cannot give the constants** (the commonly repeated C = 300 horizontal / 500 vertical at 240 dpi, and the classification coefficients, are not verified here). Do not implement RLSA constants from memory or from blog posts.

What *is* verifiable is that Leptonica considers RLSA superseded by its own approach: *"do a horizontal closing followed by a smaller horizontal opening. This can leave pixels within text lines as solid fg rectangles, separated vertically by bg pixels, and pixels within halftone regions as solid fg. This is the essence of an early morphological approach called RLSA. A vertical opening can then remove the text lines, leaving the halftone mask. We now show a somewhat more accurate method for page segmentation."* `[paper: Bloomberg & Vincent §2.1]`

### 5.5 What "alignment into rows" costs, cheaply

Three published options, in increasing cost:

1. **Postl's differential projection** — `S(θ) = Σᵢ (pᵢ(θ) − pᵢ₋₁(θ))²`, where `pᵢ` is the fg pixel count on scanline i. *"This is effective because, when the page is aligned, most of the signal comes from a relatively small fraction of scanlines; namely, those at the base and x-height of the text lines. **Halftone pixels contribute little to such a differential signal.**"* Peak half-width ≈ 1/(textline width in px); at 300 ppi with a 1500 px line, ~0.04°. Confidence measure: ratio of max to min score in the binary-search region, plus a threshold on the min score normalised by `h·w²`. `[paper: Bloomberg & Vincent §2.2]` **This is the cheapest row-alignment statistic in the literature and it is explicitly documented as insensitive to halftones.**
2. **The `pixDecideIfText` smear-and-count rule** (§5.2 above) — needs a binary image at 300 ppi and one connected-component pass.
3. **Docstrum** (O'Gorman 1993, IEEE PAMI 15(11):1162) — k-nearest-neighbour angle and distance histograms over component centroids. Cited by Haneda & Bouman as reference [5]. Not read here. `[unverified]`

---

## 6. The specific hard cases

### 6.1 Pale line drawing vs show-through vs decorative table shading — **nobody solves this**

I looked specifically and found no source that separates these three. What I found instead:

**(a) Leptonica knows about the failure and documents it twice.**

`pixDecideIfText` note (5): *"If `%box` is null and pixs contains both text lines and line art, this function might return `%istext == true`."* `[source: pageseg.c:1918]`

`pixThresholdByConnComp` note (5): *"If there is no global threshold that distinguishes foreground text from background (e.g., **weak text over a background that has significant variation and/or bleedthrough**), this returns 1, which the caller should check."* `[source: binarize.c, doc note 5]` **This is the only mention of bleed-through in any of the code surveyed, and it appears as a named failure mode, not as a case that is handled.**

**(b) Leptonica's own photo detector puts line art on the *text* side, not the picture side.** `pixDecideIfPhotoImage` (`src/compare.c:2579`) first calls `pixDecideIfText` and returns immediately if it says text. Then it tiles the image into an n×n grid (default n = 3, adjusted so subimages stay under 2:1 aspect), takes a grey histogram per tile with the 255 bucket zeroed and the max normalised to 255, computes the inter-tile root variance, and applies:

```c
numaGetSumOnInterval(narv,  50, 150, &sum1);
numaGetSumOnInterval(narv, 200, 230, &sum2);
isphoto = (sum1 / sum2 > thresh);           /* default thresh = 1.3 */
```
with the comment: *"For photos, the root variance has a larger weight of values in the range [50 … 150] compared to [200 … 230], than text or line art. **For the latter, most of the variance between tiles is in the lightest parts of the image, well above 150.**"* `[source: compare.c:2656-2673]`

So Leptonica's position is: **line art belongs with text.** That is not wrong for this project either — a line drawing *should* go to the bilevel layer. The project's failure mode is that the drawing is erased by the threshold, which is a threshold problem, not a classification problem. Note also that this *is* a luminance statistic, but a **tiled inter-histogram variance** one, which is structurally different from the four page-wide aggregates already refused: it measures how much the tone distribution *differs between regions of the page*, not what the page-wide distribution looks like.

**(c) Tesseract's `CCNonTextDetect` is the only code that claims line drawings** (`ccnontextdetect.h:30`, quoted in §3.2), and it works by small-blob density and stroke-width-neighbour agreement — which would fire on show-through just as readily, since show-through fragments are also small blobs with mismatched stroke widths. `[inference]`

**(d) A per-blob MDL / coding-cost test is the only published mechanism that would in principle discriminate.** DjVu's filter asks whether coding the blob as constant-colour foreground plus a mask boundary is cheaper than letting the smoothly-drifting background model absorb it. A pale line drawing's strokes are locally constant and long — cheap as foreground. Show-through is diffuse, low contrast and follows the paper's own drift — cheap as background. Table shading is a large flat region — very cheap as background. **This is exactly the discrimination the project needs, and DjVu makes it by cost, not by shape.** No constants are published, and I have no evidence that it actually works on these three cases. `[inference from §1.2]`

**(e) The only shape statistic I can see that would separate a pale line drawing from show-through is stroke continuity**: a drawn line yields components with a stroke-length-to-stroke-width ratio in the hundreds (Leptonica's `pixFindStrokeLength` = half the boundary pixel count, divided by `pixFindStrokeWidth`), whereas show-through yields glyph-sized blobs with a ratio in the tens, and table shading yields components that pass `pixConformsToRectangle`. **No source proposes this. It is my construction and it is untested.** `[inference]`

### 6.2 "At what threshold" vs "whether to threshold at all" — this *is* addressed

Two sources treat this directly, and they are the most immediately actionable findings in this report.

**Leptonica `pixThresholdByConnComp()` — `src/binarize.c:995`** `[source]`

The doc comment lays out the physics:

> "When the binarization threshold is varied, the numbers of c.c. identify four regimes:
> (a) For low thresholds, text is broken into small pieces, and the number of c.c. is large, with the 4 c.c. significantly exceeding the 8 c.c.
> (b) As the threshold rises toward the optimum value, the text characters coalesce and there is very little difference between the numbers of 4 and 8 c.c, which both go through a minimum.
> (c) Above this, the image background gets noisy because some pixels are thresholded to foreground, and the numbers of c.c. quickly increase, with the 4 c.c. significantly larger than the 8 c.c.
> (d) At even higher thresholds, the image background noise coalesces as it becomes mostly foreground, and the number of c.c. drops quickly."

Implementation and defaults:
```c
start = 80; end = 200; incr = 10;         /* threshold sweep */
thresh48 = 0.01;  threshdiff = 0.01;      /* normalized difference thresholds */
mincounts = 500;                          /* min 4-cc at `start` or it gives up */

for (thresh = start; thresh <= end; thresh += incr)
    { n4 = count 4-cc; n8 = count 8-cc; }

firstcount4 = n4 at start;
for each i > 0:
    diff48 = (count4 - count8) / firstcount4;
    diff4  = |prevcount4 - count4| / firstcount4;
    if (diff48 < thresh48 && diff4 < threshdiff) { found = TRUE; break; }

if (!found) return 1;                     /* NO GLOBAL THRESHOLD EXISTS */
globthresh = start + i * incr;
```

Colour input is reduced with `pixConvertRGBToGrayMinMax(pix, L_CHOOSE_MAX)` — the max channel, not luminance. An optional `pixm` mask lets you white out known non-text regions first.

**This gives the project two things it has been missing.** First, a threshold chosen to *minimise broken and merged characters simultaneously*, rather than to maximise between-class variance (Otsu), which is the right objective when the downstream consumer is a bilevel layer. Second — and this is the part that answers the question as asked — **an explicit, principled "there is no good threshold, do not binarise" return value**, whose stated cause is exactly this project's confuser set (weak text, variable background, bleed-through).

**Haneda & Bouman's COS** does the same thing at block granularity: each 32×32 block independently chooses among original / reversed / all-background / all-foreground, with a global consistency cost. *"All background"* is precisely "do not binarise this region." `[paper: §II-B]`

**ITU-T T.44 says nothing about it, and says so.** §1 Scope: *"The method of image segmentation is beyond the scope of this Recommendation; segmentation is left to manufacturers' implementation."* `[source: ITU-T Rec. T.44 (01/2005), §1]` T.44 specifies only the three-layer structure (mask, background, foreground), the permitted coders per layer, and the stripe/marker syntax. **There is no algorithm in the standard.** Anyone citing "MRC / T.44" as prior art for a segmentation method is citing the file format.

---

## 7. The resolution caution — 40 DPI is below the floor

**This is the most important negative finding in the report, and it is unambiguous across every source.**

### 7.1 Every implementation normalises to a fixed reference DPI before applying its constants `[source]`

| code | what it does first | reference DPI |
|---|---|---|
| Leptonica `pixDecideIfText` | `pixPrepare1bpp(pixs, box, 0.1, 300)` — **rescales to 300 ppi** | 300 |
| Leptonica `pixDecideIfTable` | `pixPrepare1bpp(..., 175)` for the image check, then `pixPrepare1bpp(..., 0.05, 75)` | 175, then 75 |
| Leptonica `pixGetRegionsBinary` | doc: *"assumed to be 300 to 400 ppi"*; reduces 2× to *"150–200 ppi"* | 300 → 150 |
| Leptonica `pixGenerateHalftoneMask` | doc: *"assumed to be 150 to 200 ppi"* | 150 |
| ScanTailor `estimateBinarizationMask` | `to300dpi(trimmedImage.size(), m_dpi)` then `scaleToGray` — **rescales to 300 dpi** | 300 |
| Haneda & Bouman | all block sizes and the ≥ 6 px component floor quoted at 300 dpi | 300 |
| Tesseract `CCNonTextDetect` | *no DPI normalisation* — grid size = `line_size`, the estimated font size in pixels | scale-adaptive |

Tesseract is the sole exception, and the exception proves the rule: it avoids DPI-locking only by measuring the font size first and expressing every constant as a multiple of it. That option is not open to a detector running on a fixed-size thumbnail, because measuring the font size *is* the connected-component analysis.

**If this project runs any of these constants at 40 DPI, they are wrong by a factor of 7.5.** A `c30.1` closing designed for 150 ppi becomes a 30-pixel closing at 40 DPI, which is 0.75 inch — it will weld the entire page into one component.

### 7.2 The reductions in the literature are seed generators, never decision surfaces `[source]`

The 37.5 ppi in `pixGenerateHalftoneMask` and the 18.75 ppi in jbig2enc's `r1143` look superficially like "the algorithm runs at 40 DPI". They do not. In both cases the low-resolution image is a **seed** that is then expanded and **reconstructed into a mask computed at a higher resolution** (`pixSeedfillBinary(NULL, pixhs, pixhm, 4)` where `pixhm = pixCloseSafeBrick(pixs, 4, 4)` at 150 ppi). The reconstruction is what makes the mask follow real component boundaries. `pixGetRegionsBinary` then does a *second* reconstruction of the expanded mask into the full-resolution image (`pageseg.c:182-183`).

The one thing you genuinely can read off the seed alone is the boolean *"is there an image on the page"* — Bloomberg's Figure 1 procedure, *"a test for fg pixels gives the answer… 1 msec"* `[paper: §2.1]`. That is a **coarse existence test for solid dark regions**, and nothing more. It will not see a pale line drawing, because a pale line drawing does not survive a rank-4 cascade at any threshold that also rejects background.

### 7.3 Hard floors, and what the thumbnail would and would not pass `[source]`

- Leptonica: `MinWidth = MinHeight = 100` px, enforced in `pixGetRegionsBinary`, `pixGenerateHalftoneMask`, `pixGenTextlineMask`, `pixGenTextblockMask`, `pixCropImage`, `pixFindPageForeground`. Comment: *"These functions are not intended to work on very low-res images."* `pixGenerateHalftoneMask` adds: *"This is not intended to work on small thumbnails."*
- Tesseract: `kMinImageFindSize = 100`, applied to `width/2` and `height/2`, so ≥ **200 px** per side at full res.
- Haneda & Bouman: components under **6 pixels** discarded as *"nearly invisible at 300 dpi"* — 6 px at 300 dpi is 0.02 inch. At 40 DPI an entire 10 pt glyph is about 5.5 px tall, i.e. **smaller than the smallest thing that state-of-the-art MRC segmentation is willing to look at.** `[paper]`

A 210×350 thumbnail passes the raw pixel-count floors — but that floor exists to guard against degenerate images, not to certify that 210×350 is enough. Every doc comment attached to it states a DPI assumption that a 40 DPI thumbnail violates.

### 7.4 One thing the thumbnail *is* usable for `[inference]`

A rank-4 threshold reduction cascade requires all four sub-pixels ON at each step. Box-area-averaging a greyscale render down to 37.5–40 DPI and then thresholding *near black* is an approximation of the same operation, since the average of a 2×2 is dark only if most of it is dark. So the 210×350 thumbnail could serve as a **cheap existence test for solid dark regions** — Bloomberg's Figure-1 question — and thereby as a *pre-filter* that decides which pages are worth the full-resolution analysis. It cannot be the decision, because (a) it has no reconstruction stage, (b) it cannot see pale ink at all, and (c) at 40 DPI adjacent glyphs merge so no component statistic on it means what its name says. **This paragraph is reasoning by analogy from the rank-reduction semantics; no source says it.**

---

## 8. What this project should implement

### 8.1 The framing change that has to come first

**Stop trying to compute a page-level scalar.** Every one of the four refused rounds, and the "shape signal" as posed, assumes there is a number per page that separates text pages from picture pages. Nothing in the field computes one. What the field computes is a **mask**, and then reads booleans off it — `htfound` (Leptonica), `pcount < 100` on each layer (jbig2enc), mask coverage per zone (ScanTailor). The page-level route falls out: if the non-text mask covers a meaningful fraction of the page, that fraction goes to JPEG and the rest goes to JBIG2; if it covers nothing, the whole page is bilevel; if it covers nearly everything, the whole page is JPEG. **The mask is what makes the continuum go away**, because a mask is spatially local and the confusers are not spatially coextensive.

This also dissolves the failure mode in the brief. A pale line drawing that is erased by thresholding is not a page-classification error; it is a *threshold* error, and §8.3 addresses it separately from §8.2.

### 8.2 Recipe A — the region mask (port of Bloomberg's morphology)

**Resolution: 300 DPI (or whatever the render is), reduced by the code itself. Not the 40 DPI thumbnail.**

1. Binarise the full-resolution greyscale render at the per-page Otsu threshold you already have. (This is provisional; §8.3 may replace it.)
2. `R2 = rankReduce(binary, level=1)` → 150 ppi.
3. **Halftone seed**: `seed = expand(open5x5(rankReduce(rankReduce(R2, 4), 4)), 4)`. The two level-4 steps take you to 37.5 ppi; the 5×5 opening at 37.5 ppi requires a solid black square of ~0.13 inch.
4. **Clipping mask**: `clip = closeSafe(R2, 4, 4)` at 150 ppi.
5. `htMask2 = seedfill(seed, clip, conn=4)`. `htFound = !isEmpty(htMask2)`.
6. `htMask = expand(htMask2, 2) OR seedfill(expand(htMask2,2), fullResBinary, conn=8)` — the second reconstruction is what makes the mask follow real boundaries.
7. `textPixels = R2 − htMask2`.
8. Optional, if column/line structure is wanted: textline mask `"c30.1"` minus a vertical-whitespace mask built by `"o80.60"` then `"o5.1 + o1.200"`, then `open3x3`.

Then: `pictureFraction = |htMask| / |page|`. Route per region, not per page.

Consider jbig2enc's tuning as an alternative to step 3 if Leptonica's is too eager or too shy: seed `"r1143 + o4.4 + x4"` (16× reduction, 4×4 opening) against mask `"r11"` (4× reduction), dilate `"d3.3"`, expand 4×. It is the same algorithm at a different operating point, and it is the one that ships in the tool closest to this job.

**Sanity checks that come free:** `|htMask| < 100` fg pixels ⇒ no graphics. `|textPixels| < 100` ⇒ no text. (jbig2enc `jbig2.cc:158-176`.)

### 8.3 Recipe B — the threshold decision, which is the actual fix for pale drawings

Run this **instead of** taking Otsu on faith, on the full-resolution greyscale (or on the greyscale with `htMask` already whited out, which `pixThresholdByConnComp` supports via its `pixm` argument):

1. For `t = 80, 90, …, 200`: binarise at `t`, count 4-connected components `n4(t)` and 8-connected components `n8(t)`.
2. If `n4(80) < 500`, abstain — not enough signal.
3. Let `f = n4(80)`. Find the first `t` where `(n4(t) − n8(t))/f < 0.01` **and** `|n4(t−10) − n4(t)|/f < 0.01`.
4. **If such a `t` exists**: that is the threshold. Binarise there. It is chosen to minimise broken and merged characters simultaneously, which is the right objective for a JBIG2 layer.
5. **If no such `t` exists**: the page has no global threshold. **Do not binarise it. Route to greyscale JPEG.**

Step 5 is the signal the project has been looking for, and it is a *boolean with a mechanism*, not a point on a continuum. Leptonica names its causes as "weak text over a background that has significant variation and/or bleed-through" — which is the confuser set exactly.

Cost is 13 binarisations and 26 connected-component passes at full resolution. If that is too expensive, run it at 150 ppi (the count *ratios* are what matter, not the absolute counts) — but re-derive `mincounts = 500` if you do, since it scales with area. `[inference]`

### 8.4 Recipe C — the per-region filters, applied to Recipe A's components

Only if A and B leave ambiguity. Ordered cheapest first:

1. **Solid blob**: `inkPixels / (w·h) ≥ 0.7` ⇒ not text. (Tesseract `textord_noise_area_ratio`.)
2. **Big blob**: on the text-line-smeared binary at 300 ppi, any component with `w > 400 AND h > 175` ⇒ page region is not text. (Leptonica `pixDecideIfText` condition 1 — the single strongest one.)
3. **Rectangular decoration**: `pixConformsToRectangle`-equivalent — invert, flood from the border 4-connected, clear a `dist`-px frame, test empty. Use `dist ≈ 3` at 150 ppi. Conforming + large + fill ratio near 1 ⇒ table shading, not a drawing. **Do not use fill ratio alone**; Bloomberg documents why it fails on components with holes.
4. **Row structure**: Postl's differential projection `S(θ) = Σᵢ(pᵢ − pᵢ₋₁)²` on the region. Halftones contribute almost nothing to it; text and show-through both peak sharply. Cheap (one pass, no CC), and it is the one row-alignment measure a source explicitly certifies as halftone-insensitive.
5. **Text-line count**: after `"c30.1 + o15.1 + c60.1 + o2.2"` at 300 ppi, require ≥ `max(2, h/125)` components that are ≥ 40 % of the second-widest component's width and ≤ 60 px tall, with the second-widest ≥ 60 % of page width and ≥ 80 % of the wide ones being short.

Suggested first-pass constants, all from §5.1–5.2 at their stated resolutions: fill ratio 0.7; perimeter²/16·area ≥ 1.5 for a text-like component; stroke-width match tolerance `0.125·w + 1.5 px`; small-blob density > `fontSize²/32` per 3×3 font-size cells; big component `w>400 ∧ h>175` at 300 ppi; `ratio1 ≥ 0.6`, `ratio2 ≥ 0.8`, `minlines = max(2, h/125)`.

### 8.5 If a greyscale-only path is wanted, use ScanTailor's, not a luminance aggregate

`stretchGrayRange(0.01, 0.01)` → `grad = dilate3x3 − erode3x3` → `marker = erodeGray(grad, 35×35)` → `greyReconstruct(marker, grad)` → invert → fill holes → threshold at **48/255**. **At 300 dpi.** It needs no binarisation and no connected components, and the contrast-stretch first step is specifically there to stop large display type reading as a picture. Its weakness, by construction, is that it will call a smooth pale wash a picture and a coarsely-screened halftone text-like. `[inference on the weaknesses]`

### 8.6 The resolution rule, stated once

**Run the decision at 300 DPI, or at a rank-reduction of the 300 DPI binary that the code performs itself. Do not run it on the 40 DPI thumbnail.** The thumbnail's only defensible use is as a pre-filter — a Bloomberg Figure-1 existence test for solid dark regions, to skip the expensive analysis on obviously-clean pages. Any constant in this report used at 40 DPI is wrong by 7.5×, and at 40 DPI a 10 pt glyph is smaller than the minimum component size the MRC literature is willing to consider.

### 8.7 What this will not be able to distinguish

Stated plainly, because these are the cases that will come back:

1. **A pale line drawing from show-through, when both survive or both die at the same threshold.** No source in this survey solves it. Leptonica names bleed-through as the case where its threshold selector returns failure. Recipe B will correctly refuse to binarise such a page — which converts a silent content-destroying error into a "keep it as JPEG" error. That is the right failure direction but it is not a discrimination.
2. **A coarsely-screened halftone from a stipple or hatch drawing.** Leptonica's rank-4 seed fires on both; both are locally solid at 37.5 ppi. Tesseract's small-blob density fires on both.
3. **Text rendered inside a photograph.** DjVu claims to get this right (Haffner et al. Figure 2 shows OCR recovering "STEREO SOUND SOOTHER" off a product photo) because colour clustering is local and shape-free. The morphological pipeline in Recipe A will bury such text under the halftone mask.
4. **Which of two adjacent regions the boundary belongs to.** Every mask here is dilated at the end (`d3.3`, 3×3, 5×5) precisely because the boundaries are not accurate; the tools accept a few pixels of over-coverage rather than risk clipping.
5. **Anything at all on a page whose text is not roughly horizontal.** `pixDecideIfText` note (3): *"Text is assumed to be in horizontal lines."* Leptonica, Tesseract's textline logic and Bloomberg's whole pipeline all assume a deskewed, horizontally-set page.

---

## Sources

Code, cloned at HEAD 2026-08-16:
- [github.com/DanBloomberg/leptonica](https://github.com/DanBloomberg/leptonica) — `src/pageseg.c`, `src/pix5.c`, `src/binarize.c`, `src/compare.c`, `src/strokes.c`, `src/runlength.c`, `src/binreduce.c`, `src/pixafunc1.c`, `src/seedfill.c`
- [github.com/tesseract-ocr/tesseract](https://github.com/tesseract-ocr/tesseract) — `src/textord/imagefind.cpp`, `src/textord/ccnontextdetect.{h,cpp}`, `src/textord/strokewidth.cpp`, `src/textord/colfind.cpp`, `src/textord/tordmain.cpp`, `src/textord/textord.cpp`, `src/ccstruct/blobbox.{h,cpp}`, `src/ccstruct/ccstruct.h`, `src/ccmain/pagesegmain.cpp`
- [github.com/barak/djvulibre](https://github.com/barak/djvulibre) — `tools/csepdjvu.cpp`, `tools/djvudigital`, `libdjvu/`
- [github.com/agl/jbig2enc](https://github.com/agl/jbig2enc) — `src/jbig2.cc`
- [github.com/4lex4/scantailor-advanced](https://github.com/4lex4/scantailor-advanced) — `src/core/filters/output/OutputGenerator.cpp`, `src/core/filters/output/PictureShapeOptions.cpp`
- [github.com/ocrmypdf/OCRmyPDF](https://github.com/ocrmypdf/OCRmyPDF) — `src/ocrmypdf/optimize.py`

Papers and standards:
- LeCun, Bottou, Haffner et al., *DjVu: a Compression Method for Distributing Scanned Documents in Color* — [yann.lecun.com/exdb/publis/pdf/lecun-98c.pdf](http://yann.lecun.com/exdb/publis/pdf/lecun-98c.pdf)
- Haffner, Bottou, Howard, LeCun, *DjVu: Analyzing and Compressing Scanned Documents for Internet Distribution*, ICDAR 1999 — [yann.lecun.com/exdb/publis/pdf/haffner-99.pdf](http://yann.lecun.com/exdb/publis/pdf/haffner-99.pdf)
- Bottou, Haffner, Howard, Simard, Bengio, LeCun, *High Quality Document Image Compression with DjVu*, JEI 7(3):410–425, 1998 — [leon.bottou.com/papers/bottou-98](https://leon.bottou.com/papers/bottou-98) (PDF text not extractable)
- Haffner, Bottou, LeCun, Vincent, *A General Segmentation Scheme for DjVu Document Compression*, ISMM 2002 — [leon.bottou.org/papers/haffner-2002](https://leon.bottou.org/papers/haffner-2002) (**not read — PDF text not extractable; this is the paper to get if more DjVu detail is needed**)
- Bloomberg & Vincent, *Document Image Applications* — [research.google.com/pubs/archive/36668.pdf](https://static.googleusercontent.com/media/research.google.com/en//pubs/archive/36668.pdf)
- Haneda & Bouman, *Text Segmentation for MRC Document Compression*, IEEE TIP 20(6):1611–1626, 2011 — [engineering.purdue.edu/~bouman/software/Text-Seg/tip30.pdf](https://engineering.purdue.edu/~bouman/software/Text-Seg/tip30.pdf)
- Cheng, Bouman & Allebach, *Multiscale Document Segmentation*, IS&T 1997 — [engineering.purdue.edu/~bouman/publications/pdf/ist97.pdf](https://engineering.purdue.edu/~bouman/publications/pdf/ist97.pdf)
- ITU-T Recommendation T.44 (01/2005), *Mixed Raster Content (MRC)* — [itu.int/rec/T-REC-T.44](https://www.itu.int/rec/T-REC-T.44)
- Wong, Casey & Wahl, *Document Analysis System*, IBM J. Res. Develop. 26:647–656, 1982 — **not obtained**; constants unverified
- Bhowmik, Sarkar, Nasipuri, Doermann, *Text and non-text separation in offline document images: a survey*, IJDAR 21:1–20, 2018 — [doi.org/10.1007/s10032-018-0296-z](https://link.springer.com/article/10.1007/s10032-018-0296-z) — **abstract only, paywalled**
