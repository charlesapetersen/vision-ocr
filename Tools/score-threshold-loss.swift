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
// 2026-08-18, `inkOutsideText` reads 0.0493–0.0660 against a bar of 0.08 while `extent`
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
//     page is affected — the widest `cells` in `THRESHOLD-LOSS-2026-08-18.tsv` is 2.85 M.
//
//   mkdir -p /tmp/h && cp Tools/score-threshold-loss.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/score-threshold-loss -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/score-threshold-loss testdocs/*/*.pdf
//   /tmp/score-threshold-loss --pages 41,78 "book.pdf"
//
// PAGES=n samples n pages per document (default 2, spread through it).
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
let columns = ["document", "page", "otsu", "ink", "tone", "sat", "lost",
               "extent", "cover", "cells", "factor", "route",
               "paleC", "besideInk", "paleTall", "inkTall", "unionTall",
               "bandOnly", "bandTall"]

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
        let sat = Flattener.saturation(of: page)
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
                              String(bandOnly), String(bandTall)])
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
