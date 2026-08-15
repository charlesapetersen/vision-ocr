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
let perDoc = Int(ProcessInfo.processInfo.environment["PAGES"] ?? "") ?? 2
// `PAGES=0` used to reach `(1...0)`, which traps: "Range requires lowerBound <=
// upperBound", from an environment variable. Refuse it by name instead of dying
// with a message about ranges.
if perDoc < 1 {
    FileHandle.standardError.write(Data("PAGES must be at least 1 (got \(perDoc))\n".utf8))
    exit(2)
}

print("document\tpage\totsu\tink\ttone\tsat\tlost\troute")
for path in argv {
    let url = URL(fileURLWithPath: path)
    guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { continue }
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
        let picture = Flattener.isPicture(page, grey: grey, width: w, height: h,
                                          threshold: t, saturation: sat)
        print(String(format: "%@\tp%d\t%d\t%.3f\t%.3f\t%.3f\t%.4f\t%@",
                     label, i + 1, Int(t), ink, tone, sat, lost,
                     picture ? "picture" : "1-bit"))
        fflush(stdout)
    }
}
