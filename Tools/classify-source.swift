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
// Three kinds, and **five verdicts plus two refusals**, because the three kinds are
// a statement about documents and a verdict is a statement about what was measured:
//
//   textual        no page-sized raster in the sample and real text, yet
//   no-page-image  neither text nor a page raster — a plate book, a form, a fax
//                  cover. Both mean "not this app's material" and both are named
//                  rather than merged into `born-digital`, because merging them is
//                  what hides a disagreement with the shipped rule (see below).
//   unreadable / encrypted  the two refusals. Rows, not silence.
//
// Usage:  classify-source <pdf> [more.pdf …]
// Output: one TSV row per file, ELEVEN fields, path last —
//         verdict, pages, sampled, imagePages, digitalText, charsPerPage,
//         maxImagePx, medianDPI, saturation, illumination-gradient, path
//
// Every row goes through `row(…)` for one reason: an early return printing a
// different number of fields than the header promises is a defect this project
// has now shipped twice (a SKIP row with 10 fields under a 9-column header,
// T14; `score-mrc` with 12 under 11, A12.3). One printer, one field count.
//
// **The two page questions are the app's own functions, not a copy of them.**
// `Flattener.pageIsAnImage` is asked of each sampled page, and
// `Flattener.hasDigitalText` of the document. A12.4 is what the copy cost: this
// file used to compute `maxImage >= 900 && medianDPI >= 72 && medianDPI <= 1400`
// where `maxImage` was a **max over five pages** and `medianDPI` a **median over
// those pages** — so one page's raster combined with another page's DPI to pass a
// test no single page passed, and the gate whose whole purpose is D1 admitted the
// two corpus documents the shipped app puts a "this file already has digital
// text" modal in front of.
//
// The signals, and why these:
//
//   imagePages        `Flattener.pageIsAnImage`, per sampled page. A scanned page
//                     IS one big image; born-digital pages have no raster at all,
//                     or a small figure. That function already walks nested Form
//                     XObjects, which matters: scanner drivers routinely bury the
//                     scan one level down, and missing that reads a real scan as
//                     textual. `maxImagePx` and `medianDPI` are still printed, but
//                     as *description* now, not as the test — and with `imagePages`
//                     and `sampled` beside them, a stricter majority or all-pages
//                     rule can be recomputed from a saved run. The rule here is
//                     *any* sampled page, and the body says what measuring the
//                     stricter one cost.
//   digitalText       `Flattener.hasDigitalText`, verbatim. This is the D1
//                     question — "would the app warn the user before rebuilding
//                     this?" — and it is asked first, because a document the app
//                     calls born-digital is not corpus material whatever its
//                     rasters look like.
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
    /// `Flattener.pageIsAnImage` for *this* page. The whole of A12.4: the
    /// question is per-page, and answering it from cross-page aggregates
    /// invented a document no page resembled.
    var isImage: Bool
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
    let isImage = Flattener.pageIsAnImage(page)
    let box = Flattener.fullBox(of: page)
    let scale = 60.0 / 72.0
    let w = max(Int(box.width * scale), 1), h = max(Int(box.height * scale), 1)
    let grey = Flattener.renderGrey(page, box: box, scale: scale, width: w, height: h) ?? []
    return PageSignals(
        chars: chars, isImage: isImage, imagePixels: imagePixels, dpi: dpi,
        saturation: Flattener.saturation(of: page),
        illumination: grey.isEmpty ? 0 : illuminationGradient(grey, width: w, height: h))
}

func median(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    return s[s.count / 2]
}

/// The one printer. Every row — including the two that give up before measuring
/// anything — comes through here, so the field count cannot drift from the
/// header by way of a `print` in an early return.
func row(verdict: String, pages: Int = 0, sampled: Int = 0, imagePages: Int = 0,
         digitalText: Bool = false, charsPerPage: Double = 0, maxImagePx: Int = 0,
         medianDPI: Double = 0, saturation: Double = 0, illumination: Double = 0,
         path: String) {
    print(String(format: "%@\t%d\t%d\t%d\t%@\t%.0f\t%d\t%.0f\t%.3f\t%.3f\t%@",
                 verdict, pages, sampled, imagePages, digitalText ? "yes" : "no",
                 charsPerPage, maxImagePx, medianDPI, saturation, illumination, path))
}

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
        row(verdict: "unreadable", path: path)
        continue
    }
    if doc.isLocked {
        row(verdict: "encrypted", pages: doc.pageCount, path: path)
        continue
    }

    // Sample through the document, not the first pages: front matter is the
    // least representative part of a scanned book, and a title page is often
    // the one page that IS clean. `Flattener.sampleIndices` rather than a copy of
    // the stride — this file used to carry its own, byte-identical to the app's,
    // and being byte-identical is not the same as being the same (A12.8 found two
    // tools whose copies had drifted into repeating a page).
    let total = doc.pageCount
    let indices = Flattener.sampleIndices(count: total, wanted: 5)
    var rows: [PageSignals] = []
    for i in indices {
        if let page = doc.page(at: i) { rows.append(signals(page)) }
    }
    guard !rows.isEmpty else {
        row(verdict: "unreadable", pages: total, path: path)
        continue
    }

    let charsPerPage = rows.map { Double($0.chars) }.reduce(0, +) / Double(rows.count)
    let maxImage = rows.map(\.imagePixels).max() ?? 0
    let medianDPI = median(rows.map(\.dpi))
    let sat = median(rows.map(\.saturation))
    let illum = median(rows.map(\.illumination))

    // **Any sampled page, not a majority of them, and this is measured rather
    // than chosen.** A majority rule was built first, on the reasoning that it
    // mirrors `hasDigitalText`'s own `digital * 2 > sampled`. Over the 233-document
    // corpus it rejected 7 documents the old cross-page test admitted. Two of the
    // seven are the two the shipped `hasDigitalText` names — asked below, and
    // decisive — so the majority rule removed **no** non-scan that question misses.
    // Of the other five, four are scans:
    //
    //   `full chapter.pdf` is a ~100 DPI scan whose page rasters straddle the
    //   900 px bar, 810 to 987 px across. This tool's five-page sample landed on
    //   four pages *under* the bar; `hasDigitalText`'s four-page sample, a
    //   different stride through the same book, landed on four *over* it. Same
    //   document, opposite verdicts, by sample luck at a threshold.
    //   `Glazer_2002` and `Zipkin_2000` are two-page scans — where a majority
    //   means *both* pages — whose second page is a 460–816 px blank, and
    //   `_1973_Other 67` is a four-page clipping with two.
    //
    // The fifth, `Schwaller`, is genuinely mixed: 2 of 5 sampled pages are 2,640 px
    // plates and 2 draw no image at all, which is what `BUGS.md` C24 found from the
    // other direction. So the majority rule's cost is at least four scans and its
    // gain is nothing. `imagePages` and `sampled` are both printed, so a majority
    // or all-pages rule can be recomputed from a saved run without re-rendering the
    // library — `CORPUS-2026-08-15.tsv` is such a run.
    let pageImages = rows.filter(\.isImage).count

    // The app's own question, asked first. A document the shipped app calls
    // born-digital is not this app's material however its rasters read — that is
    // D1, and it is the reason this gate exists at all.
    let digitalText = Flattener.hasDigitalText(in: doc)

    let verdict: String
    if digitalText {
        verdict = "born-digital"
    } else if pageImages == 0 {
        // Not one sampled page is a page-sized raster, yet the app would not
        // warn. Two different things, kept apart rather than both called
        // "born-digital": `textual` carries real text (a digital export the
        // shipped rule's stricter sample or its 120-character floor missed),
        // `no-page-image` carries neither text nor a page raster (a plate book, a
        // form, a fax cover). Both are rejected by every consumer; naming them
        // separately is what makes a disagreement with `hasDigitalText` visible
        // instead of merged into it. Neither occurs in the 2026-08 corpus — every
        // one of its 233 documents has at least one page-sized raster in the
        // sample — and both occur in a library, which is what this gate is for.
        verdict = charsPerPage > 200 ? "textual" : "no-page-image"
    } else if illum > 0.16 || (sat > 0.10 && illum > 0.10) {
        verdict = "photographed"
    } else {
        verdict = "scanned"
    }

    row(verdict: verdict, pages: total, sampled: rows.count, imagePages: pageImages,
        digitalText: digitalText, charsPerPage: charsPerPage, maxImagePx: maxImage,
        medianDPI: medianDPI, saturation: sat, illumination: illum, path: path)
}
