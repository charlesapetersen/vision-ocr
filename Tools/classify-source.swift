// Is this PDF a *scan* — the thing this app is for — or something else?
//
// `sample-zotero.py` stratifies by item type and era, which says nothing about
// how the pages were produced. A library holds three kinds of PDF and only one
// of them is this app's job:
//
//   scanned      a flatbed or sheet-feeder image of a printed page. OCR is the
//                whole point.
//   born-digital exported from a word processor or printed to PDF from a
//                browser. It already has real text; running OCR over it is at
//                best a no-op and at worst replaces good text with worse.
//   photographed shot by hand in an archive. Skewed, unevenly lit, often in
//                colour. A different problem, handled elsewhere.
//
// Usage:  classify-source <pdf> [more.pdf …]
// Output: one TSV row per file —
//         verdict, pages, sampled, charsPerPage, maxImagePx, medianDPI,
//         saturation, illumination-gradient, path
//
// The signals, and why these:
//
//   maxImagePx / DPI  A scanned page IS one big image. Born-digital pages have
//                     no raster at all, or a small figure. `Flattener.largestImage`
//                     already walks nested Form XObjects, which matters: scanner
//                     drivers routinely bury the scan one level down, and missing
//                     that reads a real scan as textual.
//   charsPerPage      Distinguishes a born-digital page from a scan that carries
//                     an OCR layer only in combination with the above — an
//                     already-OCR'd scan has both text and a big image, and is
//                     still a scan.
//   saturation        A flatbed scan of print is near-neutral even in colour
//                     mode. A phone photo carries a colour cast.
//   illumination      Nine-block luminance spread. A scanner lights the platen
//                     evenly; a hand-held photo has vignetting and page shadow,
//                     and that gradient is the most reliable single tell.
import AppKit
import Foundation
import PDFKit

/// Spread of mean luminance across a 3x3 grid, as a fraction of the brightest
/// block. Near zero for a scanner; a hand-held photo rarely comes in under 0.15.
func illuminationGradient(_ grey: [UInt8], width: Int, height: Int) -> Double {
    guard width > 30, height > 30 else { return 0 }
    var means: [Double] = []
    for by in 0..<3 {
        for bx in 0..<3 {
            let x0 = bx * width / 3, x1 = (bx + 1) * width / 3
            let y0 = by * height / 3, y1 = (by + 1) * height / 3
            var sum = 0.0, n = 0
            // Only paper, not ink: ink coverage varies by block for reasons that
            // have nothing to do with lighting, and averaging it in turns a
            // dense page into a false positive.
            for y in stride(from: y0, to: y1, by: 2) {
                for x in stride(from: x0, to: x1, by: 2) {
                    let v = Double(grey[y * width + x])
                    if v > 140 { sum += v; n += 1 }
                }
            }
            if n > 50 { means.append(sum / Double(n)) }
        }
    }
    guard let hi = means.max(), let lo = means.min(), hi > 0, means.count >= 6 else { return 0 }
    return (hi - lo) / hi
}

struct PageSignals {
    var chars: Int
    var imagePixels: Int
    var dpi: Double
    var saturation: Double
    var illumination: Double
}

func signals(_ page: PDFPage) -> PageSignals {
    let chars = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).count
    var imagePixels = 0
    var dpi = 0.0
    if let largest = Flattener.largestImage(of: page) {
        dpi = largest.dpi
        imagePixels = largest.pixelWidth
    }
    let box = Flattener.fullBox(of: page)
    let scale = 60.0 / 72.0
    let w = max(Int(box.width * scale), 1), h = max(Int(box.height * scale), 1)
    let grey = Flattener.renderGrey(page, box: box, scale: scale, width: w, height: h) ?? []
    return PageSignals(
        chars: chars, imagePixels: imagePixels, dpi: dpi,
        saturation: Flattener.saturation(of: page),
        illumination: grey.isEmpty ? 0 : illuminationGradient(grey, width: w, height: h))
}

func median(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    return s[s.count / 2]
}

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
        print("unreadable\t0\t0\t0\t0\t0\t0.000\t0.000\t\(path)")
        continue
    }
    if doc.isLocked {
        print("encrypted\t\(doc.pageCount)\t0\t0\t0\t0\t0.000\t0.000\t\(path)")
        continue
    }

    // Sample through the document, not the first pages: front matter is the
    // least representative part of a scanned book, and a title page is often
    // the one page that IS clean.
    let total = doc.pageCount
    let wanted = min(5, total)
    let indices = (0..<wanted).map { total <= 5 ? $0 : ($0 + 1) * total / (wanted + 1) }
    var rows: [PageSignals] = []
    for i in indices {
        if let page = doc.page(at: i) { rows.append(signals(page)) }
    }
    guard !rows.isEmpty else {
        print("unreadable\t\(total)\t0\t0\t0\t0\t0.000\t0.000\t\(path)")
        continue
    }

    let charsPerPage = rows.map { Double($0.chars) }.reduce(0, +) / Double(rows.count)
    let maxImage = rows.map(\.imagePixels).max() ?? 0
    let medianDPI = median(rows.map(\.dpi))
    let sat = median(rows.map(\.saturation))
    let illum = median(rows.map(\.illumination))

    // A scanned page is one big image. 900 px across is about 110 DPI on a
    // Letter page — below that it is a figure or a logo, not the page itself.
    let pageIsAnImage = maxImage >= 900 && medianDPI >= 72 && medianDPI <= 1400

    let verdict: String
    if !pageIsAnImage {
        // No raster the size of a page. Either born-digital, or a text-only
        // export. Either way there is nothing here to recognise.
        verdict = charsPerPage > 200 ? "born-digital" : "no-page-image"
    } else if illum > 0.16 || (sat > 0.10 && illum > 0.10) {
        verdict = "photographed"
    } else {
        verdict = "scanned"
    }

    print(String(format: "%@\t%d\t%d\t%.0f\t%d\t%.0f\t%.3f\t%.3f\t%@",
                 verdict, total, rows.count, charsPerPage, maxImage, medianDPI,
                 sat, illum, path))
}
