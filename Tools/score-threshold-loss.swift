// How much would the 1-bit route erase from this page, and does anything notice?
//
// Built for BUGS.md R56: `isPicture`'s three signals share a blind zone — brighter
// than `threshold + 45`, darker than the paper — and a pale drawing sitting in it is
// counted by none of them, so the page is thresholded and the drawing is **erased**
// rather than softened. `Tools/make-plate-fixtures.swift` builds the fixture; this
// prints the three shipped signals, the route they produce, and a candidate fourth
// signal beside them.
//
// **The candidate signal lives here and not in `Sources/`, deliberately.** It was
// measured over the corpus in four rounds and **refused** — R56 has the numbers. The
// app does not use it, so putting it in `Flattener` would be dead code, which is the
// same call `score-skew.swift` records for the deskew estimator. It is kept because
// the next attempt should start from round five, not round one, and because the four
// properties below are what each round cost.
//
// It carries a **self-test that runs on every invocation** and refuses to measure
// anything if it fails. That is not ceremony: the skew estimator's own self-test
// caught a sign error, and two of the four properties here were added *because* a
// version without them produced a plausible corpus distribution and a wrong answer.
//
// ⚠️ **`lost` IS NOT THE QUANTITY ANY SHIPPED DECISION READS, AND C26 MISREAD IT AS
// ONE.** `lost` is the refused luminance candidate above. What R56 actually shipped is
// a *shape* signal — `Flattener.paleDrawing(pageMarks(…)).extent`, the largest
// drawing-shaped mark's bounding box as a share of the sheet — and that is the number
// `paleDrawingThreshold` (0.05) is compared against, in `isPicture` for a ROUTE and
// again in `mrcLayers`' `pageIsAllText()` for a RESOLUTION. C26 quoted this tool's
// `lost` column as "the 5% bar sees 0.17%–0.32%", which is two different functions
// either side of one comparison. So `extent` and `cover` are printed here beside
// `lost`: the shipped signal, at the resolution and threshold production uses, so the
// bar and the number under it are the same kind of thing.
//
// What this tool still **cannot** print is `pageIsAllText()`'s verdict. That guard has
// a first term, `inkOutsideText(…) < textPageInkOutsideThreshold`, which needs the
// page's Vision text boxes, and nothing here runs OCR. `extent` is the second term and
// the one C26 is about; use `Tools/score-mrc.swift`'s `bgF`/`fgF` columns to see
// whether the whole guard fired.
//
// ⚠️ **And on C26's own pages the first term is the one that decides** — measured
// 2026-08-18, `inkOutsideText` reads 0.0493–0.0660 against what was then a bar of 0.08
// (0.045 since 2026-08-19, which refuses all three) while `extent`
// is 0.00000, so a reader who has only this tool's output is looking at the term that
// passes vacuously. `Tools/score-text-route.swift` and `Tools/score-mrc.swift` both
// print the first term, because both run Vision; this tool and one of those together
// are what settled C26 sub-step 2, and this one could not have done it alone.
//
// Two ways the printed `extent` is the RESOLUTION decision's number exactly and the
// ROUTE decision's only nearly, both found by the review of the commit that added it and
// both bounded rather than fixed:
//
//   * The loop below mirrors `mrcLayers` — `fullBox`, `rebuildDPI`, `.mediaBox`, the same
//     rounding, `otsuThreshold` of that render — so at `pageIsAllText()` it is character
//     for character right. `isPicture`'s call reaches `paleDrawing` through
//     `renderDPI(of:pixelWidth:)` = `w · 72 / box.width` instead, which differs from
//     `rebuildDPI` by under 0.05 DPI at these sizes and can only change an answer where
//     `dpi / markCellsPerInch` lands on a rounding boundary or a component's height sits
//     exactly on `typeCeilingInches × dpi`. Measured on `1954 - Why.pdf` the two are both
//     111.2727 and `extent` is identical.
//   * The megapixel guard below is `maximumPageMegapixels` (400), the bound on rendering.
//     `mrcLayers` refuses to layer above `maximumMRCPageMegapixels` (100). So a page
//     between the two gets a row here for a decision production never takes. No corpus
//     page is affected — the largest page in the 233-document corpus is **64.84 MP**,
//     measured, and recorded beside `maximumColourMRCPageMegapixels` in
//     `Sources/Flattener.swift`. ⛔ **The margin on the layering bound is 1.54x, which is
//     not "room to spare".**
//     ⛔ **This line quoted `cells` as a pixel count, 16.87x low, and C27's own review
//     caught it on 2026-08-26 — in the file that PRINTS the column.** It said *"the
//     widest `cells` in `THRESHOLD-LOSS-2026-08-18.tsv` is 3.84 M (3,844,260), i.e. 3.8
//     megapixels, far under either bound"*. `cells` is neither the page's pixels nor even
//     its area: it is an analysis-grid count over `Flattener.interiorWindow` divided by
//     `factor`, and that window drops `w/16` and `h/16` each side, so `cells × factor²`
//     is 0.766 of `wide * high`. A tool must not read its own column as a quantity it is
//     not — CONTRIBUTING §3. ⚠️ The FIRST correction here, 2026-08-19, was a *different*
//     error in the same sentence: it said 2.85 M, which was the file's FIRST DATA ROW and
//     not its largest, and 40 of its 441 rows exceed it. C27's register entry and the
//     autonomous queue carried that one too and were corrected with it. Two corrections
//     to one clause, both about which number it was reading.
//
//   mkdir -p /tmp/h && cp Tools/score-threshold-loss.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/score-threshold-loss -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/score-threshold-loss testdocs/*/*.pdf
//   /tmp/score-threshold-loss --pages 41,78 "book.pdf"
//
// PAGES=n samples n pages per document (default 2, spread through it).
// SATFLOOR=n is C27's, and it is the only knob here about colour: what counts as a
// saturated pixel when asking how much of a page carries ink of its own colour
// (default 0.25, refused outside 0…1). It sets the `satFrac` column and **the eight
// mask-term columns beside it**, and is printed on every row.
// SATRUNS=n is the run limit `Flattener.shapeComponents` truncates the mask at (default
// its shipped 8,000,000, refused below 1 and refused unparseable). Nothing needs it to
// measure: it exists so the tool's refusal on a truncated mask can be RUN —
// `SATRUNS=1 … one.pdf` exits 6 on the first page that CARRIES COLOUR — rather than
// reasoned about, which is CONTRIBUTING 4c. ⛔ Not "any page": a page whose mask is
// entirely below the floor yields no runs at all, so `shapeComponents` returns `[]`
// rather than `nil` and the row prints. See the guard's own comment below.
//
// ⚠️ **C27's TWO MASK TERMS are the last eight columns, added 2026-08-26.** The entry's
// `#### ⛔ And the ten pages were LOOKED AT` proposed ONE signal — a locality or
// largest-connected-region test — and the review of that diff refuted it from the dumped
// masks: `Ford_1941` p5's largest component holds 88.2% of its counted pixels in one
// border ring, so a locality test alone ranks the page it exists to reject top of the
// corpus. The two terms it asked for instead are **outside the sheet**
// (`edgeN`/`edgeShare`/`sheetFrac`) and **locality** (`satN`/`topPx`/`topShare`/
// `topRun`), with `satPx` beside them so every share has its numerator. Read `MaskTerms`
// for what each one is and for the false positive `edgeShare` cannot see. ⛔ **No bar is
// proposed on any of them**: this entry has refused six single scalars.
//
// ⚠️ **This tool is C27's population instrument as well as C26's**, and the two
// questions read different columns. C26 is about the 1-bit route erasing a mark;
// C27 is about a bar on the page's MEAN saturation, which spot colour cannot reach.
// ⚠️ **Which bar depends on the question, since C27 (c) split them 2026-08-26:** the
// red being DISCARDED is `colourSaturationThreshold`, the page being off the picture
// route at all is `pictureSaturationThreshold`, and both are 0.06 today, so every
// figure below reads the same either way. Measured, `1954 - Why.pdf` keeps its
// red on 1 page of 10, and its discarded pages score `sat` 0.039-0.043 against 0.06
// while 3-4% of each sheet is saturated red ink. `sat` is that mean; `satFrac` is the
// share of the page above `satFloor`. The entry's own point is that no value of the
// constant separates two-ink sheets from tinted grey scans **on the mean**, because
// over the corpus that statistic is one continuum with a 0.004-wide gap either side
// of 0.06 — so the column to sweep for C27 is `satFrac`, and `sat` is only there to
// say which side of the shipped bar the page fell.
import AppKit
import Foundation
import PDFKit

// MARK: - The candidate signal, with the four properties it took to get here

/// How much of the page the 1-bit route would erase: marks too pale to be ink, which
/// are therefore rendered as paper.
///
/// **Refused as a routing signal (R56), and the reason is what to read first.** The
/// blind zone holds three kinds of thing, and luminance cannot tell them apart:
/// a pale drawing (must be kept), decorative table shading (harmless to lose) and
/// **show-through from the reverse of the sheet** (which you actively want gone). The
/// two commonest pale things in the corpus are the two you want deleted, so a
/// threshold here cannot be set without deciding the one case it exists for wrongly.
///
/// The four rounds, each of which looked right until the corpus was read:
///
/// 1. **Pale fraction, mean-and-2-sd paper level.** A continuum from 0 to 0.0918 over
///    385 1-bit corpus pages, no gap, 24% of ordinary text pages scoring above the
///    fixture that loses its whole drawing. Its top hits were dense type and a page
///    of handwriting, because it was counting anti-aliased glyph edge.
/// 2. **Exclude pale pixels near ink** (`inkNear`). Edge is always beside ink; a
///    drawing is surrounded by paper. Fixtures went from a 1.4x separation to 150x —
///    text 0.0000, halftone 0.0001, pale drawing 0.0158.
/// 3. **Paper level from the mode, spread from the peak's clean upper side.** The mean
///    is unusable: a large pale area is part of the bright class, so it drags the mean
///    down and inflates the spread until it excludes itself. A solid pale block over a
///    fifth of a synthetic sheet defeated round 2 outright.
/// 4. **Require the mark to be thin** (`paperNear`). Without it the largest corpus hit
///    was a ProQuest metadata page's alternating grey table bands at **0.4232** — and
///    rendered at 1-bit, every word survives and only the banding goes. Thinness cut
///    it to 0.0596, which is *still* above the fixture, because a band's edges are
///    thin. And it correctly drops the solid tonal plate to 0.0024, which is why R57
///    needs connected components rather than this.
///
/// What killed it was round 4's remaining hits: `Doermann_1967` p19 at 0.2577 is a
/// 1967 typescript whose pale content is show-through from the reverse page — thin,
/// away from ink, and an artefact the threshold is right to remove.
func contentLostToThreshold(_ grey: [UInt8], width w: Int, height h: Int,
                            threshold: UInt8) -> Double {
    guard w > 0, h > 0, grey.count >= w * h else { return 0 }
    let mx = w / 16, my = h / 16
    let x1 = max(w - mx, mx + 1), y1 = max(h - my, my + 1)
    let rows = my..<min(y1, h), cols = mx..<min(x1, w)

    // Property 3: the paper's level is its mode, not its mean.
    var histogram = [Int](repeating: 0, count: 256)
    var n = 0
    for y in rows {
        let row = y * w
        for x in cols where grey[row + x] >= threshold {
            histogram[Int(grey[row + x])] += 1; n += 1
        }
    }
    guard n > 0 else { return 0 }
    var paper = Int(threshold), best = -1
    for v in Int(threshold)..<256 where histogram[v] > best { best = histogram[v]; paper = v }
    // The paper's noise, from the side of its peak pale content cannot reach.
    var above = 0, counted = 0
    for v in paper..<256 { above += histogram[v] * (v - paper); counted += histogram[v] }
    let spread = counted > 0 ? Double(above) / Double(counted) : 0
    // A floor, because a perfectly flat synthetic page has no spread at all.
    let limit = Double(paper) - max(3 * spread, 4)
    guard limit > Double(threshold) else { return 0 }

    // An edge is a fixed number of microns wide, not of pixels.
    let reach = max(Int((Double(min(w, h)) / 700.0).rounded()), 1)
    let stride1 = w + 1
    var inkSum = [Int32](repeating: 0, count: stride1 * (h + 1))
    var paperSum = [Int32](repeating: 0, count: stride1 * (h + 1))
    for y in 0..<h {
        var inkRun: Int32 = 0, paperRun: Int32 = 0
        let row = y * w, above = y * stride1, here = (y + 1) * stride1
        for x in 0..<w {
            let v = Double(grey[row + x])
            if v < Double(threshold) { inkRun += 1 }
            if v >= limit { paperRun += 1 }
            inkSum[here + x + 1] = inkSum[above + x + 1] + inkRun
            paperSum[here + x + 1] = paperSum[above + x + 1] + paperRun
        }
    }
    func any(_ sums: [Int32], _ x: Int, _ y: Int, within r: Int) -> Bool {
        let x0 = max(x - r, 0), x1 = min(x + r + 1, w)
        let y0 = max(y - r, 0), y1 = min(y + r + 1, h)
        return sums[y1 * stride1 + x1] - sums[y0 * stride1 + x1]
             - sums[y1 * stride1 + x0] + sums[y0 * stride1 + x0] > 0
    }

    var lost = 0, total = 0
    for y in rows {
        let row = y * w
        for x in cols {
            total += 1
            let v = Double(grey[row + x])
            guard v >= Double(threshold), v < limit else { continue }
            guard !any(inkSum, x, y, within: reach) else { continue }   // property 2
            if any(paperSum, x, y, within: reach * 2) { lost += 1 }     // property 4
        }
    }
    return total > 0 ? Double(lost) / Double(total) : 0
}

// MARK: - C27's two mask terms

/// The two terms C27's dumped masks asked for, taken over the **same pixels `satFrac`
/// counts** and never over a second render.
///
/// `BUGS.md` C27 `#### ⛔ And the ten pages were LOOKED AT` proposed one signal — "a
/// locality or largest-connected-region test" — and the review of that diff refuted it
/// from the masks themselves: `Ford_1941` p5's largest component holds **88.2%** of its
/// counted pixels in one border ring, against 44.7% on `Schwaller` p101 and 7.6% on
/// `1954 - Why` p7, so a locality test *alone* ranks the page it exists to reject top
/// of the corpus and the weakest real page nearly last. What the pictures said instead
/// is that there are **two** problems and they want two terms:
///
///   * **Outside the sheet.** `Ford_1941` p5 is a photograph of a sheet on a darker
///     surround and 88% of its counted pixels lie outside the paper; C26's
///     `RIESMAN_1942` p10 is the same artefact charged against the other decision. The
///     cheap form of "outside the sheet" is *connected to the border of the render*,
///     which is the phrase that section already uses for it. `edgeShare` is that
///     share, `edgeN` how many components carry it, and `sheetFrac` is `satFrac` with
///     them discarded.
///   * **Locality.** `HarpersMagazine-1938-05` p4 carries no ink of its own and reads
///     2.0% — a page-wide cast of ~1,290 components whose largest is **6 px**. A mark
///     is one region; a cast is thousands of specks. `satN`, `topPx`, `topShare` and
///     `topRun` are that.
///
/// ⛔ **Neither is proposed as a bar.** This entry has refused six single scalars and
/// both constants it is about are means; these are measurements, and the whole point of
/// measuring them *separately* is that the one-signal version was refuted.
///
/// ⚠️ **`edgeShare` is a proxy and it is not the sheet's edge.** A real mark that runs
/// to the trim — a bleed rule, a red band printed off the page — is border-connected
/// too and is discarded by this term. That is a false positive this tool cannot tell
/// from a scan surround, and the negative control for it is `sheetFrac` beside
/// `satFrac` on a page whose colour is interior: on those two the columns are equal.
struct MaskTerms {
    /// Pixels above the floor — `satFrac`'s own numerator, recomputed here so the two
    /// can be checked against each other rather than trusted.
    let satPx: Int
    /// 8-connected components of those pixels.
    let satN: Int
    /// How many of them touch the render's border, and how many pixels they hold.
    let edgeN: Int, edgePx: Int
    /// The largest component by area: its pixels, and the median of its own row runs
    /// (`ShapeComponent.medianRun`, the stroke-width proxy — 2-6 px on a stem of type).
    let topPx: Int, topRun: Int
    /// The denominator both fractions are taken over: the thumbnail's pixel count.
    let pixels: Int

    var fraction: Double { pixels > 0 ? Double(satPx) / Double(pixels) : 0 }
    /// `satFrac` with every border-connected component discarded.
    var sheetFrac: Double { pixels > 0 ? Double(satPx - edgePx) / Double(pixels) : 0 }
    var edgeShare: Double { satPx > 0 ? Double(edgePx) / Double(satPx) : 0 }
    var topShare: Double { satPx > 0 ? Double(topPx) / Double(satPx) : 0 }
}

/// Both terms from one walk of the thumbnail, through production's own
/// `forEachSaturation` and `shapeComponents`.
///
/// **One walk and production's correction, for the reason `saturatedFraction`'s doc
/// comment already gives**: the von Kries correction exists once, and a second copy of
/// it in a tool is R23's and R29's shape exactly. So this builds the mask from the
/// values that function yields, in raster order, and hands it to the same component
/// routine `pageMarks` uses.
///
/// `nil` — refuse, do not default — on either of the two ways this can fail to describe
/// the page: a walk that did not cover it (`forEachSaturation` guards the buffer length
/// itself and returns having yielded nothing, which would otherwise leave an all-false
/// mask reading as *"no colour on this page"*, the most plausible-looking wrong answer
/// available to a sweep whose whole question is which pages carry colour), and
/// `shapeComponents` exceeding `runLimit`. `runLimit` is threaded through so the second
/// branch can be *executed* rather than reasoned about — CONTRIBUTING 4c.
func maskTerms(ofRGBA buffer: [UInt8], width: Int, height: Int, above floor: Double,
               runLimit: Int = Flattener.maximumShapeRuns) -> MaskTerms? {
    let pixels = width * height
    guard pixels > 0 else {
        return MaskTerms(satPx: 0, satN: 0, edgeN: 0, edgePx: 0, topPx: 0, topRun: 0,
                         pixels: 0)
    }
    var mask = [Bool](repeating: false, count: pixels)
    var seen = 0
    Flattener.forEachSaturation(ofRGBA: buffer, width: width, height: height) {
        if $0 > floor, seen < pixels { mask[seen] = true }
        seen += 1
    }
    guard seen == pixels else { return nil }
    guard let comps = Flattener.shapeComponents(mask, width: width, height: height,
                                                x0: 0, y0: 0, x1: width, y1: height,
                                                runLimit: runLimit)
    else { return nil }
    var satPx = 0, edgeN = 0, edgePx = 0, topPx = 0, topRun = 0
    for c in comps {
        satPx += c.area
        // `minX == 0` means a run starts at column 0, i.e. the component holds a pixel
        // there — so for these four the bounding box touching the border and the
        // component touching it are the same statement, exactly, and not a bound.
        if c.minX == 0 || c.minY == 0 || c.maxX == width - 1 || c.maxY == height - 1 {
            edgeN += 1
            edgePx += c.area
        }
        if c.area > topPx {
            topPx = c.area
            topRun = c.medianRun
        }
    }
    return MaskTerms(satPx: satPx, satN: comps.count, edgeN: edgeN, edgePx: edgePx,
                     topPx: topPx, topRun: topRun, pixels: pixels)
}

// MARK: - One columns array, one row printer

/// CONTRIBUTING §5: a tool that prints a TSV gets one `columns` array and one `row(…)`
/// printer with the width asserted. Counting tab escapes by eye has put the wrong
/// number of fields under a header in this repo three times — T14's SKIP row, T15's
/// `score-mrc` (which `REVIEW-2026-08-14.md` calls A12.3) and T18's two — and one of
/// those sat beside a comment that reasoned the count out and got it wrong. This file
/// used to print a hand-written header string and a hand-written `String(format:)`
/// carrying seven tab escapes under an eight-name header, so adding a column meant
/// editing both and agreeing with yourself.
///
/// `cells` and `factor` are printed because `extent` cannot be read on its own. It is
/// `widest / marks.cells` with `widest` an integer count of cells, so on the page C26
/// turns on — 887,616 cells — five decimals resolve no finer than 4.4 of them, and the
/// question there is whether `extent` is *small* or *exactly zero*, which are two
/// different defects with two different fixes. With `cells` beside it the numerator is
/// recoverable; `factor` says what reduction `pageMarks` actually took the marks at,
/// which is the divisor in `paleDrawing`'s own size ceiling.
///
/// The last seven are C26 sub-step 2's columns, and they exist because `extent` being
/// zero says the guard found nothing without saying *why*. `paleDrawing` keeps
/// components **taller than** a quarter inch, so what decides that page is the height
/// of the tallest thing in each mask:
///
///   * `paleC` / `paleTall` — the layer `paleDrawing` actually reads, and its ceiling.
///   * `besideInk` — pale cells property 2 threw away for touching ink. A crossing into
///     ink breaks the stroke's pale trace by itself, because an ink cell is not a pale
///     one; property 2 then widens each break by a cell on either side. The column
///     says how much of the pale layer that rule is removing, which on a scan of type
///     is most of it.
///   * `inkTall` / `unionTall` — the tallest component of `ink`, and of `ink ∪ pale`.
///   * `bandOnly` / `bandTall` — the tallest component of the pale **band**, and of
///     `ink ∪` that band. The band is the pale layer before property 2 removed the
///     cells beside ink.
///
/// **Read `bandOnly` for the band and `bandTall` only as a pair with `inkTall`.**
/// `bandTall` is `tallestComponent(ink ∪ band)`, so it is bounded below by `inkTall`
/// and a large value can be nothing but a tall ink component somewhere else on the
/// page — measured on `1954 - Why.pdf` p4 it reads 189 where `inkTall` is 187 and
/// `bandOnly` is 14, so the band's own contribution to that 189 is two cells of height
/// on somebody else's component. The first version of this doc claimed the column
/// separated "the band bridges the pale fragments" from "the stroke is genuinely
/// broken in the render", and it cannot; `bandOnly` was added by the review of that
/// commit's diff because that is the column that can. `unionTall` is the same shape
/// over production's own two masks and nothing reconstructed — and note it can be cut
/// by property 2 too, since a suppressed cell is removed from `pale` and is not `ink`,
/// so it is a hole in the union.
///
/// **`satFrac` and `satFloor` are C27's**, and they are the only columns here that say
/// anything about *colour* rather than about the 1-bit route. `sat` is
/// `Flattener.saturation`'s mean over the page, the number BOTH saturation bars
/// (`pictureSaturationThreshold` for the route and, since 2026-08-26,
/// `colourSaturationThreshold` for the colour — 0.06 each) are compared against;
/// reaching it takes something like 6% of the sheet in
/// saturated ink (C27 reasoned "roughly 8%" before this column existed; measured on ten
/// real pages it is nearer 6% — `Flattener.saturatedFraction`'s doc comment has the
/// arithmetic), so a two-ink pamphlet whose red subheads and rules come to 3-4% scores
/// 0.039-0.043 and is published in grey. `satFrac` is the fraction of the same
/// thumbnail's pixels whose paper-corrected saturation is above `satFloor` — the
/// statistic C27 says the decision should be taken on — and both come from **one**
/// `Flattener.saturationThumbnail` render, so `sat` here is production's own number
/// rather than a second calibration of it.
///
/// `satFloor` is on every row because it is a parameter of the measurement and not of
/// the page. `sweep-ink-bar.py` records a resume at a different `INKBAR` mixing two
/// measurements into one file; a floor that exists only in the invoking shell is that
/// defect waiting for its second run. `SATFLOOR=n` sets it, default 0.25.
///
/// **The last eight are C27's TWO MASK TERMS**, added 2026-08-26 and documented on
/// `MaskTerms` above: `satPx` (`satFrac`'s own numerator, so a reader can recover the
/// count), `satN`/`topPx`/`topShare`/`topRun` (locality — a mark is one region, a
/// page-wide cast is thousands of specks), and `edgeN`/`edgeShare`/`sheetFrac`
/// (outside the sheet — `satFrac` with every border-connected component discarded).
/// They come **after** `satFloor` deliberately: appending leaves the 21 columns
/// `THRESHOLD-LOSS-2026-08-18.tsv` and `SATFRAC-2026-08-19.tsv` hold at the same field
/// indices, so both files stay readable by the same `cut -f` and the earlier figures
/// stay checkable against a new run. `tsv-header-drift` is the queue item about the
/// other direction.
let columns = ["document", "page", "otsu", "ink", "tone", "sat", "lost",
               "extent", "cover", "cells", "factor", "route",
               "paleC", "besideInk", "paleTall", "inkTall", "unionTall",
               "bandOnly", "bandTall", "satFrac", "satFloor",
               "satPx", "satN", "topPx", "topShare", "topRun",
               "edgeN", "edgeShare", "sheetFrac"]

// MARK: - Where the pale layer's cells went (C26 sub-step 2)

/// The tallest connected component of a cell mask, in cells, at `paleDrawing`'s own
/// component floor — production's `markComponents`, not a second implementation of it.
/// Zero when nothing clears the floor.
func tallestComponent(_ mask: [Bool], width w: Int, height h: Int) -> Int {
    guard w > 0, h > 0, mask.count >= w * h else { return 0 }
    return Flattener.markComponents(mask, width: w, height: h)
        .reduce(0) { max($0, $1.height) }
}

/// Both layers as one mask. Used only to ask whether a mark that is fragmented in
/// `pale` is continuous once the cells `ink` took are put back.
func unionMask(_ a: [Bool], _ b: [Bool]) -> [Bool] {
    guard a.count == b.count else { return a }
    var out = a
    for i in 0..<b.count where b[i] { out[i] = true }
    return out
}

/// The pale **band** as cells: in `[threshold, paperLimit]`, reduced exactly as
/// `pageMarks` reduces — a cell is in the band if any pixel in it is. This is the pale
/// layer *before* property 2 takes the cells beside ink, and `bandTall` is the column
/// that decides C26 sub-step 2: whether a stroke that arrives in `pale` as fragments
/// was continuous in the render.
///
/// ⚠️ **Replica, and one grey level wide.** Production tests `Double(v) < limit`;
/// only `Int(limit)` survives on `Marks`, so this uses `v <= paperLimit`, which is the
/// same set except for cells whose only band pixels sit on exactly that level. It is
/// therefore a superset of production's band by at most one level — never a subset,
/// which is what a height question needs. The exact count of what property 2 removed
/// is `Marks.paleBesideInk`, measured inside `pageMarks`; the two are printed side by
/// side by `--dump` so the gap is visible rather than assumed.
func bandMask(_ grey: [UInt8], width w: Int, height h: Int, threshold: UInt8,
              marks: Flattener.Marks) -> [Bool] {
    let rw = marks.width, rh = marks.height, f = max(marks.factor, 1)
    guard rw > 0, rh > 0, grey.count >= w * h, w > 0, h > 0 else { return [] }
    // `pageMarks`'s own inset and its own `guard r? < r?` skip, rather than
    // `origin + cells * factor`. Two reasons, both from the review of this diff: that
    // product overflows for a `factor` near `Int.max`, which `pageMarks` uses `safeInt`
    // to survive (A7.1); and where `cells` was floored to 1 on a page narrower than one
    // cell it reaches `factor` pixels past the inset production stops at.
    let mx = w / 16, my = h / 16
    let cx1 = max(w - mx, mx + 1), cy1 = max(h - my, my + 1)
    var band = [Bool](repeating: false, count: rw * rh)
    for y in marks.originY..<min(cy1, h) {
        let ry = (y - marks.originY) / f
        guard ry < rh else { continue }
        let row = y * w, base = ry * rw
        for x in marks.originX..<min(cx1, w) {
            let rx = (x - marks.originX) / f
            guard rx < rw else { continue }
            let v = grey[row + x]
            if v >= threshold, Int(v) <= marks.paperLimit { band[base + rx] = true }
        }
    }
    return band
}

/// `--dump <dir>`: one composite image per measured page, at the cell resolution the
/// decision is actually taken at.
///
///   black  ink            — below Otsu
///   red    pale, kept     — what `paleDrawing` gets to look at
///   blue   pale, dropped  — in the pale band, not ink, and touching ink (property 2)
///   white  paper
///
/// ⚠️ **The blue class is the tool's arithmetic, not production's mask.** Production
/// tests `Double(v) < limit` and only the floored `limit` survives on `Marks`, so this
/// uses `v <= paperLimit` and can differ by the cells sitting on exactly that level.
/// It is a picture, and the number beside it — `besideInk`, counted inside `pageMarks`
/// — is the measurement. `--dump` prints both counts to stderr so a reader can see how
/// far apart they are before trusting the blue.
func dumpMarks(_ band: [Bool], marks: Flattener.Marks, to url: URL) -> String {
    let rw = marks.width, rh = marks.height
    guard rw > 0, rh > 0, marks.ink.count >= rw * rh, marks.pale.count >= rw * rh,
          band.count >= rw * rh
    else { return "no cells" }
    var dropped = 0
    var rgb = [UInt8](repeating: 255, count: rw * rh * 3)
    for i in 0..<(rw * rh) {
        let p = i * 3
        if marks.ink[i] { rgb[p] = 0; rgb[p + 1] = 0; rgb[p + 2] = 0 }
        else if marks.pale[i] { rgb[p] = 220; rgb[p + 1] = 30; rgb[p + 2] = 30 }
        else if band[i] { rgb[p] = 40; rgb[p + 1] = 90; rgb[p + 2] = 230; dropped += 1 }
    }
    guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: rw, pixelsHigh: rh, bitsPerSample: 8,
            samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: rw * 3, bitsPerPixel: 24),
          let plane = rep.bitmapData
    else { return "no bitmap" }
    // A padded row stride would shear the image rather than overflow the buffer, which
    // is the kind of wrong picture a reader believes. Asked rather than assumed.
    guard rep.bytesPerRow == rw * 3 else {
        return "row stride \(rep.bytesPerRow), not \(rw * 3)"
    }
    rgb.withUnsafeBufferPointer { plane.update(from: $0.baseAddress!, count: rgb.count) }
    guard let png = rep.representation(using: .png, properties: [:]),
          (try? png.write(to: url)) != nil
    else { return "not written" }
    return "\(url.lastPathComponent): blue \(dropped) cells (tool, v <= paperLimit) "
         + "against besideInk \(marks.paleBesideInk) (pageMarks)"
}

/// Every string `dumpMarks` returns that is not a written file. Kept as one list so a
/// caller cannot decide a failure was fine: `--dump` that quietly writes nothing and
/// exits 0 is this tool's own silent-success defect wearing a second hat.
let dumpFailures = ["no cells", "no bitmap", "not written"]

/// Returns `nil` rather than trapping, so the self-test can prove it still refuses a bad
/// width. A printer that accepts any width is the defect above wearing a helper's name.
func row(_ fields: [String]) -> String? {
    fields.count == columns.count ? fields.joined(separator: "\t") : nil
}

// MARK: - Self-test, on every run

func selfTest() -> [String] {
    var failures: [String] = []
    func expect(_ name: String, _ ok: Bool, _ detail: String) {
        if !ok { failures.append("\(name) — \(detail)") }
    }
    let W = 80, H = 80
    // A page of type, with anti-aliased edge around every stroke.
    var type = [UInt8](repeating: 250, count: W * H)
    for y in 10..<20 { for x in 8..<72 { type[y * W + x] = 20 } }
    for y in 30..<40 { for x in 8..<72 { type[y * W + x] = 20 } }
    for y in [9, 20, 29, 40] { for x in 8..<72 { type[y * W + x] = 190 } }
    let typeLoss = contentLostToThreshold(type, width: W, height: H, threshold: 128)
    expect("type alone loses nothing", typeLoss < 0.001, String(format: "%.4f", typeLoss))

    // The same page with a thin pale mark on it, away from any ink.
    var pale = type
    for y in stride(from: 50, to: 74, by: 4) { for x in 16..<64 { pale[y * W + x] = 200 } }
    let paleLoss = contentLostToThreshold(pale, width: W, height: H, threshold: 128)
    expect("a pale mark away from ink counts", paleLoss > 0.01,
           String(format: "%.4f vs type %.4f", paleLoss, typeLoss))

    // Property 2, pinned on its own: the same pale pixels count alone and not as edge.
    var asEdge = [UInt8](repeating: 250, count: W * H)
    var alone = [UInt8](repeating: 250, count: W * H)
    for y in 20..<60 {
        for x in 20..<60 {
            asEdge[y * W + x] = (x % 2 == 0) ? 20 : 200
            alone[y * W + x] = (x % 2 == 0) ? 250 : 200
        }
    }
    let edgeLoss = contentLostToThreshold(asEdge, width: W, height: H, threshold: 128)
    let aloneLoss = contentLostToThreshold(alone, width: W, height: H, threshold: 128)
    expect("pale beside ink is edge, not content", edgeLoss < 0.001,
           String(format: "%.4f", edgeLoss))
    expect("…and the same pixels alone are content", aloneLoss > 0.05,
           String(format: "%.4f alone vs %.4f as edge", aloneLoss, edgeLoss))

    // Property 4: a solid pale panel is not a mark; its thin edge may count, its
    // interior must not.
    var panel = [UInt8](repeating: 250, count: W * H)
    for y in 20..<60 { for x in 20..<60 { panel[y * W + x] = 200 } }
    let panelLoss = contentLostToThreshold(panel, width: W, height: H, threshold: 128)
    expect("a solid pale panel is mostly not counted", panelLoss < aloneLoss / 2,
           String(format: "%.4f panel vs %.4f the same area as strokes",
                  panelLoss, aloneLoss))

    // Property 3: a large pale area must not redefine what paper is.
    expect("a large pale area does not excuse itself", panelLoss > 0,
           String(format: "%.4f", panelLoss))

    // The TSV's shape, pinned. The header and every row come from one `columns` array
    // through one printer; what has to hold is that the printer still *refuses* a width
    // that does not match, because that is the check a helper silently loses.
    expect("a row of the header's width prints", row(columns) != nil,
           "\(columns.count) fields refused")
    expect("a short row is refused", row(Array(columns.dropLast())) == nil,
           "\(columns.count - 1) fields accepted")
    expect("a long row is refused", row(columns + ["extra"]) == nil,
           "\(columns.count + 1) fields accepted")

    // C26 sub-step 2's columns, on a page built to be the thing they have to tell
    // apart: one continuous pale stroke, 60 cells tall, with two ink cells sitting on
    // it where the line happens to darken past Otsu.
    //
    // **The crossing is what fragments the stroke, not property 2** — an ink cell is
    // not a pale one, so the break exists before the suppression runs; property 2 then
    // widens it by a cell on each side, 20 + 38 becoming 19 + 37. The first version of
    // this comment credited property 2 with the fragmentation, and the review of the
    // diff that added it worked the fixture through by hand and found otherwise. The
    // `paleBesideInk` check below is therefore the only one of these that tests
    // property 2 at all; the height checks test the crossing.
    var stroke = [UInt8](repeating: 250, count: W * H)
    for y in 10..<70 { stroke[y * W + 40] = 200 }
    for y in 30..<32 { stroke[y * W + 40] = 20 }
    let sm = Flattener.pageMarks(stroke, width: W, height: H, threshold: 128, dpi: 150)
    let sBand = bandMask(stroke, width: W, height: H, threshold: 128, marks: sm)
    let sPaleTall = tallestComponent(sm.pale, width: sm.width, height: sm.height)
    let sBandTall = tallestComponent(unionMask(sm.ink, sBand),
                                     width: sm.width, height: sm.height)
    expect("factor 1, so a cell is a pixel and the heights are readable",
           sm.factor == 1, "factor \(sm.factor)")
    // Exactly two: the stroke is one cell wide, so the only pale cells 8-adjacent to
    // the two ink cells are the ones directly above and below them.
    expect("property 2 took cells, and says how many", sm.paleBesideInk == 2,
           "\(sm.paleBesideInk), expected 2")
    expect("the stroke reaches `pale` in fragments", sPaleTall == 37,
           "tallest pale component \(sPaleTall) of a 60-cell stroke, expected 37")
    expect("…and the band it came from is continuous once the ink is put back",
           sBandTall == 60, "tallest ink ∪ band component \(sBandTall), expected 60")
    // `bandOnly` is the column that can attribute height to the band rather than to
    // some ink component elsewhere: here the band alone is still two fragments, and
    // 38 rather than 37 is exactly property 2's cell on each side.
    expect("…while the band alone is still cut where the stroke crossed into ink",
           tallestComponent(sBand, width: sm.width, height: sm.height) == 38,
           "\(tallestComponent(sBand, width: sm.width, height: sm.height)), expected 38")
    expect("the band is never smaller than the layer it is the before-picture of",
           sBand.count == sm.pale.count
               && sBand.indices.allSatisfy { !sm.pale[$0] || sBand[$0] },
           "\(sBand.count) band cells against \(sm.pale.count) pale, "
               + "or a kept pale cell is outside the band")
    // …and the height helper is not simply agreeing with everything: a mask with
    // nothing in it has no tallest component, and one solid block is its own height.
    expect("an empty mask has no component",
           tallestComponent([Bool](repeating: false, count: W * H),
                            width: W, height: H) == 0, "non-zero")
    var block = [Bool](repeating: false, count: W * H)
    for y in 10..<25 { for x in 10..<14 { block[y * W + x] = true } }
    expect("a 15-cell block measures 15",
           tallestComponent(block, width: W, height: H) == 15,
           "\(tallestComponent(block, width: W, height: H))")

    // Degenerate pages: no divide by zero, no answer out of range.
    for (name, buffer) in [("blank", [UInt8](repeating: 255, count: W * H)),
                           ("all ink", [UInt8](repeating: 10, count: W * H))] {
        let v = contentLostToThreshold(buffer, width: W, height: H, threshold: 128)
        expect("a \(name) page is 0", v == 0, String(format: "%.4f", v))
    }

    // C27's two columns, on the pair of sheets `sat` cannot tell apart. One pixel in
    // 32 at full saturation (a red subhead on white paper) against a uniform mid-tone
    // cast: the same mean, exactly, and both below `colourSaturationThreshold`, so
    // the two-ink sheet is published in grey along with the cast one. (⛔ The COLOUR
    // bar and not the route's, corrected 2026-08-26 with C27 (c)'s split: "published
    // in grey" is `shouldKeepColour`'s answer, and `isPicture` has two other signals,
    // so being under the route bar does not give it. The two are equal today, so no
    // number here moves — CONTRIBUTING §2, the same correction as the suite's copy.)
    // If `satFrac`
    // ever stops separating them the column is measuring nothing, and a sweep of 233
    // documents taken with it would be 233 plausible rows — so this refuses to
    // measure rather than print them. Every number is exact in binary
    // (1/32 = 0.03125, (128 - 124) / 128 = 0.03125), so these are `==` and not `abs`.
    func rgba(_ r: UInt8, _ g: UInt8, _ b: UInt8, count: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count * 4)
        for _ in 0..<count { out.append(contentsOf: [r, g, b, 255]) }
        return out
    }
    var spot = rgba(255, 0, 0, count: 32)
    spot.append(contentsOf: rgba(255, 255, 255, count: 992))
    let cast = rgba(128, 124, 124, count: 1024)
    let spotMean = Flattener.saturation(ofRGBA: spot, width: 32, height: 32)
    let castMean = Flattener.saturation(ofRGBA: cast, width: 32, height: 32)
    expect("the mean cannot tell two ink from a cast", spotMean == castMean,
           String(format: "spot %.6f, cast %.6f", spotMean, castMean))
    expect("…and refuses the colour on both", spotMean <= Flattener.colourSaturationThreshold,
           String(format: "%.5f vs %.2f", spotMean, Flattener.colourSaturationThreshold))
    let spotFrac = Flattener.saturatedFraction(ofRGBA: spot, width: 32, height: 32,
                                               above: 0.25)
    let castFrac = Flattener.saturatedFraction(ofRGBA: cast, width: 32, height: 32,
                                               above: 0.25)
    expect("satFrac separates them", spotFrac == 0.03125 && castFrac == 0,
           String(format: "spot %.5f, cast %.5f", spotFrac, castFrac))
    // …and it is a share of the sheet, so a page of nothing but ink is 1 and not more.
    let inkOnly = rgba(255, 0, 0, count: 1024)
    let allInk = Flattener.saturatedFraction(ofRGBA: inkOnly, width: 32, height: 32,
                                             above: 0.25)
    expect("satFrac is a fraction of the page", allInk == 1.0,
           String(format: "%.5f", allInk))
    // Saturation is (hi - lo) / hi and cannot exceed 1, so nothing is above a floor of
    // 1. This is the case that separates `> floor` from `>= floor`, and the tool refuses
    // such a floor by name rather than printing the empty column it would produce.
    expect("no pixel is above a floor of 1",
           Flattener.saturatedFraction(ofRGBA: inkOnly, width: 32, height: 32,
                                       above: 1.0) == 0, "something was")
    // The walk both statistics come from yields EVERY pixel, zeros included. Neither
    // published number would move if it skipped them — the mean adds a zero and the
    // fraction divides by the pixel count either way — so this is the only check that
    // can see it, and a statistic that is not a mean (a median, a histogram) would be
    // wrong without it.
    //
    // ⚠️ **The fixture needs PURE BLACK pixels in it and the first version had none.**
    // The skip is `if hi > 0`, where `hi` is the brightest channel and not the
    // saturation: pure red is `hi = 255` and is yielded either way, so a sheet of red
    // ink on white paper cannot see the difference. Measured — a hand-built
    // `skip-zeros` mutant of `forEachSaturation` **survived this check** until the 32
    // black pixels below were added — another of this repo's checks that could not fail,
    // caught the same way as the rest of them (BUGS.md C27 has the mutant table).
    var withBlack = rgba(255, 0, 0, count: 32)
    withBlack.append(contentsOf: rgba(0, 0, 0, count: 32))          // black type
    withBlack.append(contentsOf: rgba(255, 255, 255, count: 960))   // paper
    var walked = 0.0, walkedCount = 0
    Flattener.forEachSaturation(ofRGBA: withBlack, width: 32, height: 32) {
        walked += $0; walkedCount += 1
    }
    // Against `withBlack`'s OWN mean: the two fixtures happen to share a mean, and a
    // check that leans on that coincidence asserts less than its label says.
    let blackMean = Flattener.saturation(ofRGBA: withBlack, width: 32, height: 32)
    expect("the walk yields every pixel, black type included",
           walkedCount == 1024 && walked / 1024 == blackMean && blackMean == 0.03125,
           "\(walkedCount) pixels, " + String(format: "%.6f vs %.6f", walked / 1024,
                                              blackMean))
    // `pixels > 0` and not the length check is the load-bearing guard: the length is
    // guarded identically inside the walk, so only this can see 0.0 / 0.0 = NaN.
    expect("a zero-size buffer is 0 rather than NaN",
           Flattener.saturatedFraction(ofRGBA: [], width: 0, height: 0, above: 0.25) == 0,
           "not 0")
    // And the paper correction is still in the walk: cream stock is a real 0.106 per
    // pixel uncorrected, and the whole point of `saturation` is that it reads 0 here.
    // Without this a sweep would report every cream-paper scan in the corpus as coloured
    // — the 709 MB monograph, again, and from the tool this time.
    let cream = Flattener.saturation(ofRGBA: rgba(245, 237, 219, count: 1024),
                                     width: 32, height: 32)
    expect("cream stock corrects to no colour at all", cream < 0.0001,
           String(format: "%.6f", cream))

    // C27's TWO MASK TERMS, on the shapes the dumped masks named. Every fixture is a
    // 32x32 sheet of white paper with red pixels on it, so the floor and the paper
    // correction are the same ones the column above was just checked with, and every
    // asserted fraction is exact in binary (36/1024, 160/1024) — so these are `==`.
    func sheet(_ set: (Int, Int) -> Bool) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: 1024 * 4)
        for y in 0..<32 {
            for x in 0..<32 where set(x, y) {
                let i = (y * 32 + x) * 4
                out[i] = 255; out[i + 1] = 0; out[i + 2] = 0
            }
        }
        return out
    }
    func mark6(_ x0: Int, _ y0: Int) -> (Int, Int) -> Bool {
        { x, y in x >= x0 && x < x0 + 6 && y >= y0 && y < y0 + 6 }
    }
    func terms(_ buffer: [UInt8], _ label: String) -> MaskTerms {
        guard let t = maskTerms(ofRGBA: buffer, width: 32, height: 32, above: 0.25) else {
            failures.append("mask terms refused the \(label) fixture")
            return MaskTerms(satPx: -1, satN: -1, edgeN: -1, edgePx: -1, topPx: -1,
                             topRun: -1, pixels: 1024)
        }
        return t
    }
    // The pair this term exists for. 36 single specks against one 6x6 mark: the SAME
    // `satFrac`, exactly, and the same relationship to every bar that could be set on
    // it — which is `HarpersMagazine-1938-05` p4 (a page-wide cast of ~1,290
    // components, largest 6 px, no ink of its own) against a real mark, in 1,024
    // pixels. If these two ever stop separating, the locality columns measure nothing
    // and a corpus run taken with them is a page of plausible rows.
    // The two buffers are HOISTED and not re-typed at their second use below. The
    // review of this diff found the first version building each of them twice — once
    // for `terms(…)` and again, character for character, for the `saturatedFraction`
    // control — which is `score-shape-term`'s recorded hazard exactly: two inline
    // copies held in sync by hand, so the control compares two buffers rather than two
    // walks of one.
    let castBuffer = sheet { x, y in x % 4 == 2 && y % 4 == 2 && x < 24 && y < 24 }
    let ringBuffer = sheet { x, y in
        x == 0 || x == 31 || y == 0 || y == 31 || mark6(10, 10)(x, y)
    }
    let speckled = terms(castBuffer, "scattered cast")
    let mark = terms(sheet(mark6(10, 10)), "interior mark")
    expect("satFrac cannot tell a cast from a mark",
           speckled.satPx == 36 && mark.satPx == 36
           && speckled.fraction == mark.fraction,
           "\(speckled.satPx) vs \(mark.satPx) px, "
           + String(format: "%.7f vs %.7f", speckled.fraction, mark.fraction))
    expect("locality can", speckled.satN == 36 && speckled.topPx == 1
                           && mark.satN == 1 && mark.topPx == 36,
           "cast \(speckled.satN) comps / top \(speckled.topPx), "
           + "mark \(mark.satN) comps / top \(mark.topPx)")
    // The stroke-width proxy travels with it: a speck's own row run is 1 px, a 6x6
    // mark's is 6. This is the column that says a cast is not thin type.
    expect("topRun is the largest component's own run",
           speckled.topRun == 1 && mark.topRun == 6,
           "\(speckled.topRun) vs \(mark.topRun)")
    // ⛔ And the T, because every fixture above is a SQUARE or a 1x1 speck, where
    // `medianRun`, `width` and `height` are all the same integer — so `topRun` could
    // have been the component's width or its height and the check above would still
    // pass. Found by the review of this diff. This T has a 6-wide bar over a 1-wide
    // stem: runs [6, 1, 1, 1, 1], median **1**, against width 6, height 6 and area 11,
    // so it separates `medianRun` from all three at once.
    let tee = terms(sheet { x, y in
        (y == 20 && x >= 8 && x < 14) || (x == 10 && y >= 21 && y < 26)
    }, "T-shaped mark")
    expect("topRun is the median RUN and not the component's width, height or area",
           tee.satN == 1 && tee.topPx == 11 && tee.topRun == 1,
           "\(tee.satN) comps, top \(tee.topPx) px, run \(tee.topRun)")
    // Outside the sheet. A border ring plus the same interior mark: `satFrac` counts
    // both, `sheetFrac` counts only the mark — and it lands on the mark-only fixture's
    // own `satFrac`, which is the identity that says the term subtracts the ring and
    // nothing else. The two SHARE columns are asserted here too: the ring is both the
    // border-connected set and the largest component, so `edgeShare` and `topShare`
    // are the same 124/160 — and until the review of this diff neither column was read
    // by any check at all, in a file where five committed rows exercise their
    // divide-by-zero guard.
    let ringed = terms(ringBuffer, "border ring plus mark")
    expect("a border ring is counted by satFrac and discarded by sheetFrac",
           ringed.satPx == 160 && ringed.edgeN == 1 && ringed.edgePx == 124
           && ringed.sheetFrac == mark.fraction && ringed.fraction != ringed.sheetFrac
           && ringed.edgeShare == Double(124) / Double(160)
           && ringed.topShare == Double(124) / Double(160),
           "\(ringed.satPx) px, \(ringed.edgeN) edge comps, \(ringed.edgePx) edge px, "
           + String(format: "sheet %.7f vs mark %.7f, edgeShare %.7f, topShare %.7f",
                    ringed.sheetFrac, mark.fraction, ringed.edgeShare, ringed.topShare))
    // ⛔ The blank sheet, which is the case the two share columns' `satPx > 0` guards
    // exist for and the one no check reached before this diff was reviewed. It is not
    // hypothetical: FIVE of `C27-MASKTERMS-2026-08-26.tsv`'s 50 rows read `satPx` 0, so
    // relaxing either guard to `>=` publishes `nan` in two columns on real pages while
    // every other check here stays green.
    let blank = terms(sheet { _, _ in false }, "blank paper")
    expect("a page with no colour reads 0 in every share rather than nan",
           blank.satPx == 0 && blank.satN == 0 && blank.edgeN == 0
           && blank.topPx == 0 && blank.topRun == 0
           && blank.fraction == 0 && blank.sheetFrac == 0
           && blank.topShare == 0 && blank.edgeShare == 0,
           "\(blank.satPx) px, \(blank.satN) comps, "
           + String(format: "top %.7f edge %.7f sheet %.7f",
                    blank.topShare, blank.edgeShare, blank.sheetFrac))
    // `topPx` is the LARGEST component and not the first one found. A speck at row 2
    // and a 6x6 mark at row 10 come back in raster order, so `comps.first` reads 1
    // here and `max` reads 36 — the ring fixture above cannot see this, because there
    // the largest component is also the first.
    let late = terms(sheet { x, y in (x == 5 && y == 2) || mark6(10, 10)(x, y) },
                     "speck before mark")
    // `topShare` is asserted HERE and not only on the ring, because on the ring the
    // largest component IS the border-connected set — `topPx == edgePx == 124` — so a
    // `topShare` that returned `edgeShare`'s expression would pass there. On this
    // fixture they are 36/37 and 0.
    expect("topPx is the largest component, not the first",
           late.satN == 2 && late.topPx == 36 && late.topRun == 6
           && late.topShare == Double(36) / Double(37) && late.edgeShare == 0,
           "\(late.satN) comps, top \(late.topPx) px, run \(late.topRun), "
           + String(format: "topShare %.7f edgeShare %.7f", late.topShare,
                    late.edgeShare))
    // All four border clauses, one side at a time, with the inset as the negative
    // control. An off-by-one in any of them — `maxX == width` rather than `width - 1` —
    // reads as "nothing touches the border" on that side and silently promotes a scan
    // surround into `sheetFrac`.
    for (name, x0, y0, want) in [("left", 0, 10, 1), ("right", 26, 10, 1),
                                 ("top", 10, 0, 1), ("bottom", 10, 26, 1),
                                 ("inset by one", 1, 1, 0)] {
        let t = terms(sheet(mark6(x0, y0)), name)
        expect("a mark on the \(name) border is \(want == 1 ? "" : "not ")border-connected",
               t.satPx == 36 && t.edgeN == want
               && t.sheetFrac == (want == 1 ? 0 : mark.fraction),
               "\(t.satPx) px, \(t.edgeN) edge comps, "
               + String(format: "sheet %.7f", t.sheetFrac))
    }
    // The control the sweep itself runs on every row: these components are the pixels
    // `satFrac` counted, so their total area over the page is that fraction. Two
    // independent walks of one buffer, and the tool exits 6 if they ever disagree.
    for (name, t, buffer) in [("cast", speckled, castBuffer),
                              ("ring", ringed, ringBuffer)] {
        let published = Flattener.saturatedFraction(ofRGBA: buffer, width: 32,
                                                    height: 32, above: 0.25)
        expect("the \(name) fixture's components are satFrac's own pixels",
               t.fraction == published,
               String(format: "%.7f vs %.7f", t.fraction, published))
    }
    // Both refusals, executed. A buffer too short for the page yields nothing at all
    // from `forEachSaturation`, which would otherwise leave an all-false mask reading
    // as a page with no colour on it; a run limit the mask exceeds is
    // `shapeComponents`' own truncation, and `runLimit` is a parameter so this branch
    // runs rather than being reasoned about (CONTRIBUTING 4c).
    expect("a buffer too short for the page is refused, not read as colourless",
           maskTerms(ofRGBA: [1, 2, 3], width: 32, height: 32, above: 0.25) == nil,
           "something was measured")
    expect("a mask over the run limit is refused",
           maskTerms(ofRGBA: sheet { x, y in x % 4 == 2 && y % 4 == 2 },
                     width: 32, height: 32, above: 0.25, runLimit: 1) == nil,
           "something was measured")
    // ⚠️ What this last one pins is the two `pixels > 0` ternaries on `fraction` and
    // `sheetFrac` — relax either to `>=` and it goes red on a NaN. It does NOT pin the
    // early return above them: delete that `guard` and the walk still yields nothing,
    // `seen == 0 == pixels` passes, `shapeComponents` returns `[]` on its own `w > 0`
    // guard, and the answer is identical. Said here rather than papered over, because
    // `thumbnailSize` floors both dimensions at 1, so a zero-size page is unreachable
    // from this tool's own call path and the early return is belt-and-braces by
    // decision. Found by the review of this diff.
    let empty = maskTerms(ofRGBA: [], width: 0, height: 0, above: 0.25)
    expect("a zero-size page is 0 rather than NaN or nil",
           empty?.satPx == 0 && empty?.fraction == 0 && empty?.sheetFrac == 0,
           empty == nil ? "nil" : String(format: "%.7f", empty!.fraction))
    return failures
}

let failures = selfTest()
guard failures.isEmpty else {
    FileHandle.standardError.write(Data(
        ("self-test failed; measuring nothing:\n  " + failures.joined(separator: "\n  ")
         + "\n").utf8))
    exit(4)
}

// MARK: - Measure

var argv = Array(CommandLine.arguments.dropFirst())
var explicitPages: [Int] = []
if let i = argv.firstIndex(of: "--pages"), i + 1 < argv.count {
    explicitPages = argv[i + 1].split(separator: ",").compactMap { Int($0) }
    argv.removeSubrange(i...(i + 1))
}
var dumpDir: URL?
if let i = argv.firstIndex(of: "--dump"), i + 1 < argv.count {
    dumpDir = URL(fileURLWithPath: argv[i + 1], isDirectory: true)
    argv.removeSubrange(i...(i + 1))
}
let perDoc = Int(ProcessInfo.processInfo.environment["PAGES"] ?? "") ?? 2
// `PAGES=0` used to reach `(1...0)`, which traps: "Range requires lowerBound <=
// upperBound", from an environment variable. Refuse it by name instead of dying
// with a message about ranges.
if perDoc < 1 {
    FileHandle.standardError.write(Data("PAGES must be at least 1 (got \(perDoc))\n".utf8))
    exit(2)
}
// C27's floor. Saturation is `(hi - lo) / hi`, so it lives in 0…1: a floor of 0 counts
// every pixel that is not perfectly neutral — on an anti-aliased scan that is most of
// them — and a floor of 1 or more counts none, whatever is on the page. Either produces
// a column of plausible numbers that answers a different question than the one asked,
// which is the failure `PAGES=0` above is refused for. Refuse by name instead.
let satFloor = Double(ProcessInfo.processInfo.environment["SATFLOOR"] ?? "") ?? 0.25
if !(satFloor > 0 && satFloor < 1) {
    FileHandle.standardError.write(Data(
        ("SATFLOOR must be above 0 and below 1 (got \(satFloor)); saturation is "
         + "(hi - lo) / hi, so 0 counts every anti-aliased pixel and 1 counts none\n").utf8))
    exit(2)
}
// The run limit `Flattener.shapeComponents` truncates at, exposed so the refusal above
// it can be RUN from the command line rather than reasoned about — which is exactly why
// the branch needs a seam if it is ever to execute.
// ⛔ **`SATRUNS=1` refuses a page that CARRIES colour and NOT "any document"** — the
// first draft of this comment said any, and the review of this diff traced it out:
// `shapeComponents` trips the limit only inside its run-finding loop, and above that
// sits `guard !runs.isEmpty else { return [] }`, so a page whose mask is entirely below
// the floor yields zero runs, returns an empty list rather than `nil`, and prints a
// complete row. Five of `C27-MASKTERMS-2026-08-26.tsv`'s own 50 rows are that shape
// (`satPx` 0), so the counterexample is in this tool's own artefact.
// ⚠️ It is a measurement knob and not a route: on a page with colour a limit below the
// shipped one exits 6 rather than printing, so it cannot quietly put a truncated column
// in a file — and `shapeComponents` returns `nil` or the whole list, never a partial
// one, which is what makes that guarantee the list's and not this comment's.
// ⚠️ **Do not reason the shipped 8,000,000 out of one page's size.** A draft here said
// "a ~40 DPI thumbnail is ~150,000 pixels, so its runs cannot exceed half that"; that is
// letter-at-40-DPI, and `maximumThumbnailEdge` is 4,000, so a thumbnail can be 16 M
// pixels and an alternating field of one is 8 M runs — the limit exactly, not 50x clear
// of it. This file's own rows recover denominators of 1.5 M to 3.2 M pixels
// (`satPx / satFrac`), 10x-21x that draft's figure. C27's noise-floor lesson in a second
// place: one page's number is not a bound.
// ⛔ An unparseable value is REFUSED here where `PAGES` and `SATFLOOR` fall back,
// deliberately: those two have a printed column saying which value produced the file and
// this has none, so `SATRUNS=1O` would run normally and read as *"the refusal did not
// fire"* — the one thing this knob exists to rule out.
let satRunsRaw = ProcessInfo.processInfo.environment["SATRUNS"]
if let raw = satRunsRaw, Int(raw) == nil {
    FileHandle.standardError.write(Data(
        ("SATRUNS is not a number (got \(raw)); it is the run limit `shapeComponents` "
         + "truncates at, and it has no column, so a typo would read as the refusal "
         + "not firing rather than as a bad value\n").utf8))
    exit(2)
}
let satRuns = Int(satRunsRaw ?? "") ?? Flattener.maximumShapeRuns
if satRuns < 1 {
    FileHandle.standardError.write(Data(
        ("SATRUNS must be at least 1 (got \(satRuns)); it is the run limit "
         + "`shapeComponents` truncates at, and 0 refuses every page that carries "
         + "colour\n").utf8))
    exit(2)
}

print(columns.joined(separator: "\t"))
// A corpus sweep that measured nothing must not exit 0. `testdocs/` is not committed, so
// from an `auto/` worktree `testdocs/*/*.pdf` matches no PDF at all — measured
// 2026-08-18, bash left the pattern unexpanded and this tool took it as one path, opened
// nothing, printed its header and **exited 0**, which reads exactly like a clean run in a
// log. CLAUDE.md records the
// same fix on `score-corpus`, which "now prints SKIP at exit 1 rather than OK over a
// document it measured nothing on"; CONTRIBUTING 4b's sibling sweep is why it is here
// too. Counted rather than inferred from the row count, because a caller may be piping.
var opened = 0, measured = 0
for path in argv {
    let url = URL(fileURLWithPath: path)
    guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { continue }
    opened += 1
    let label = url.deletingPathExtension().lastPathComponent
    let total = doc.pageCount
    let indices: [Int] = explicitPages.isEmpty
        ? Flattener.sampleIndices(count: total, wanted: perDoc)
        : explicitPages.map { $0 - 1 }
    for i in indices {
        guard let page = doc.page(at: i) else { continue }
        // rebuildDPI, not nativeDPI: this has to be the resolution `flatten` actually
        // renders at, or the verdict describes a page nothing produces.
        // picture-signals.swift records what that mistake looked like.
        let box = Flattener.fullBox(of: page)
        let dpi = Flattener.rebuildDPI(of: page)
        let scale = dpi / 72.0
        let w = max(Int((box.width * scale).rounded()), 1)
        let h = max(Int((box.height * scale).rounded()), 1)
        guard Double(w) * Double(h) <= Double(Flattener.maximumPageMegapixels) * 1_000_000,
              let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                              width: w, height: h, from: .mediaBox)
        else { continue }
        let t = Flattener.otsuThreshold(of: grey)
        let ink = Flattener.inkCoverage(of: grey, width: w, height: h, threshold: t)
        let tone = Flattener.toneFraction(of: grey, threshold: t)
        // One thumbnail, two statistics of the same pixels (C27). `sat` is what
        // `isPicture` and `shouldKeepColour` read — the same render `saturation(of:)`
        // would have taken, through the same function — and `satFrac` is the fraction
        // of those pixels that carry real colour. Measuring the fraction on a second
        // render at another resolution would compare two calibrations, and the mean is
        // the one the constant was set against.
        //
        // A thumbnail that could not be rendered is REFUSED rather than defaulted. `sat`
        // has always answered 0 on that path through `saturation(of:)`, and 0 is the most
        // plausible-looking wrong answer available to a sweep whose whole question is
        // which pages carry colour: `sat 0.000  satFrac 0.00000` reads as a page with no
        // ink of its own on it. This tool already exits 6 rather than print a row it
        // cannot stand behind (the band-mask guard below), and `renderGrey` has already
        // succeeded on this page above, so a failure here is an anomaly and not a
        // property of the document.
        guard let thumb = Flattener.saturationThumbnail(of: page) else {
            FileHandle.standardError.write(Data(
                ("no colour thumbnail for \(label) p\(i + 1) though the page rendered; "
                 + "measuring nothing rather than calling it colourless\n").utf8))
            exit(6)
        }
        let sat = Flattener.saturation(ofRGBA: thumb.buffer, width: thumb.width,
                                      height: thumb.height)
        let satFrac = Flattener.saturatedFraction(ofRGBA: thumb.buffer, width: thumb.width,
                                                 height: thumb.height, above: satFloor)
        // C27's two mask terms, over the SAME thumbnail and the same floor — never a
        // second render, for the reason `saturationThumbnail`'s own doc comment gives.
        guard let terms = maskTerms(ofRGBA: thumb.buffer, width: thumb.width,
                                    height: thumb.height, above: satFloor,
                                    runLimit: satRuns) else {
            FileHandle.standardError.write(Data(
                ("no mask terms for \(label) p\(i + 1) though the thumbnail rendered "
                 + "(\(thumb.width)x\(thumb.height), run limit \(satRuns)); measuring "
                 + "nothing rather than printing a page with no colour on it\n").utf8))
            exit(6)
        }
        // The control, on every row rather than once in the self-test: these components
        // ARE the pixels `satFrac` counted, so their total area over the page is that
        // fraction, bit for bit — two walks of one buffer through two production
        // functions, and the same integers over the same denominator. A divergence
        // means the mask and the column have stopped describing one population, which
        // is the whole premise of measuring the terms here instead of on a second
        // render, so it refuses rather than prints.
        guard terms.fraction == satFrac else {
            FileHandle.standardError.write(Data(
                ("mask terms and satFrac disagree on \(label) p\(i + 1): "
                 + String(format: "%.7f from %d px against %.7f", terms.fraction,
                          terms.satPx, satFrac) + "\n").utf8))
            exit(6)
        }
        let lost = contentLostToThreshold(grey, width: w, height: h, threshold: t)
        // The shipped shape signal, from the same grey buffer at the same threshold and
        // the same dpi `mrcLayers` computes — it renders `fullBox` at `rebuildDPI` from
        // the media box exactly as the loop above does, so `extent` here is the number
        // `pageIsAllText()` compares against `paleDrawingThreshold`. `cover` is the ink
        // of every drawing-shaped mark; the route reads `extent`, and R56 records why
        // deciding on `cover` was wrong.
        let marks = Flattener.pageMarks(grey, width: w, height: h, threshold: t, dpi: dpi)
        let pale = Flattener.paleDrawing(marks, dpi: dpi)
        let picture = Flattener.isPicture(page, grey: grey, width: w, height: h,
                                          threshold: t, saturation: sat)
        // C26 sub-step 2: what the pale layer looked like before `paleDrawing`'s
        // height ceiling refused all of it.
        let paleC = marks.pale.reduce(0) { $0 + ($1 ? 1 : 0) }
        let paleTall = tallestComponent(marks.pale, width: marks.width,
                                        height: marks.height)
        let inkTall = tallestComponent(marks.ink, width: marks.width,
                                       height: marks.height)
        let unionTall = tallestComponent(unionMask(marks.ink, marks.pale),
                                         width: marks.width, height: marks.height)
        let band = bandMask(grey, width: w, height: h, threshold: t, marks: marks)
        // A band that came back the wrong size would make `bandOnly` read 0 and
        // `bandTall` fall back to `inkTall` through `unionMask`'s guard — two plausible
        // numbers from a failure. Refuse instead.
        guard band.count == marks.pale.count else {
            FileHandle.standardError.write(Data(
                ("band mask is \(band.count) cells against \(marks.pale.count) pale on "
                 + "\(label) p\(i + 1); measuring nothing rather than guessing\n").utf8))
            exit(6)
        }
        let bandOnly = tallestComponent(band, width: marks.width, height: marks.height)
        let bandTall = tallestComponent(unionMask(marks.ink, band),
                                        width: marks.width, height: marks.height)
        if let dir = dumpDir {
            try? FileManager.default.createDirectory(at: dir,
                                                     withIntermediateDirectories: true)
            let name = "\(label)-p\(i + 1)-marks.png"
                .replacingOccurrences(of: "/", with: "_")
            let note = dumpMarks(band, marks: marks,
                                 to: dir.appendingPathComponent(name))
            FileHandle.standardError.write(Data(("  " + note + "\n").utf8))
            if dumpFailures.contains(note) || note.hasPrefix("row stride") {
                FileHandle.standardError.write(Data(
                    "--dump wrote no image; exiting rather than reporting a clean run\n".utf8))
                exit(6)
            }
        }
        guard let line = row([label, "p\(i + 1)", String(Int(t)),
                              String(format: "%.3f", ink),
                              String(format: "%.3f", tone),
                              String(format: "%.3f", sat),
                              String(format: "%.4f", lost),
                              String(format: "%.5f", pale.extent),
                              String(format: "%.5f", pale.coverage),
                              String(marks.cells), String(marks.factor),
                              picture ? "picture" : "1-bit",
                              String(paleC), String(marks.paleBesideInk),
                              String(paleTall), String(inkTall), String(unionTall),
                              String(bandOnly), String(bandTall),
                              String(format: "%.5f", satFrac),
                              // %.5f and not %.2f: `SATFLOOR=0.001` is accepted and would
                              // print as `0.00`, and 0.999 as `1.00` — both of them values
                              // this tool refuses by name. A column that exists to say
                              // which floor produced the file must not round two accepted
                              // floors onto a refused one.
                              String(format: "%.5f", satFloor),
                              // C27's two mask terms. `satPx` is an integer count and
                              // not a fraction on purpose: `satFrac` at %.5f cannot
                              // resolve one pixel of a 150,000-pixel thumbnail, and
                              // `topPx`/`topShare` are meaningless without the
                              // numerator they are shares of — the same argument
                              // `cells` and `factor` are printed for above.
                              String(terms.satPx), String(terms.satN),
                              String(terms.topPx),
                              String(format: "%.5f", terms.topShare),
                              String(terms.topRun),
                              String(terms.edgeN),
                              String(format: "%.5f", terms.edgeShare),
                              String(format: "%.5f", terms.sheetFrac)])
        else {
            FileHandle.standardError.write(Data(
                "row width does not match the \(columns.count) columns\n".utf8))
            exit(5)
        }
        print(line)
        measured += 1
        fflush(stdout)
    }
}

if measured == 0 {
    FileHandle.standardError.write(Data(
        ("measured nothing: \(argv.count) argument(s), \(opened) opened as a PDF, "
         + "0 pages rendered — check the paths, and that `testdocs/` is where you think "
         + "it is (it is not committed, so a worktree does not have it)\n").utf8))
    exit(3)
}
