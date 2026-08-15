// What would it actually save to route an all-text page off the layered route and
// onto the 1-bit one?
//
// TODO.md item 1 ("move `isPicture` after recognition") is priced in two places
// with two different numbers. One says a 568-page book "carries tone layers on 522
// pages that a correctly-routed book would not carry at all — the remaining 4 MB
// over the original". The other says "a text page routed to 1-bit costs 44 KB where
// a layered one costs 46". The first is the cost of the tone layers; the second is
// the *net* difference, and they disagree by about 4x, because a whole-page Otsu
// stencil is bigger than the Sauvola stencil confined to Vision's word boxes. The
// tone layers you stop paying for are partly re-spent on a fatter stencil.
//
// This measures the published bytes, per page, both ways, using the shipped code
// for each:
//
//   layered   `Flattener.mrcLayers` (so R50's all-text shrink applies exactly as it
//             ships) + `JBIG2.encode` of its stencil + the two tone JPEGs.
//   1-bit     `Flattener.flatten` in **Black & white** mode over the same single
//             page — which is what a correctly-routed page costs, by definition —
//             + `JBIG2.encode` of the PNG it writes.
//
// Neither number is reconstructed here. The reason `bilevelImage` is not called
// directly is that it is file-private, and reproducing its bit packing in a tool is
// the divergence this directory's README warns about; driving `flatten` costs one
// extra render and cannot drift.
//
// It also prints `inkOutsideText`, which is R50's signal and the one a routing
// decision after recognition would have to use, so the pages where the two routes
// are close can be read against how confidently the page is text at all.
//
//   mkdir -p /tmp/h && cp Tools/score-text-route.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/score-text-route -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/score-text-route "<pdf>" [page…]        # 1-indexed; default: a spread
//
// Needs jbig2 on PATH — without it there is no size question to answer, and it
// says so rather than reporting halves.
import AppKit
import CoreGraphics
import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(Data("usage: score-text-route <pdf> [page…]\n".utf8))
    exit(2)
}
let src = URL(fileURLWithPath: args[1])
guard let jbig2 = JBIG2.encoder else {
    FileHandle.standardError.write(Data("jbig2 not found; nothing to measure\n".utf8))
    exit(3)
}
Prefs.register(migrate: false)
let settings = Prefs.Snapshot.current()

let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("textroute-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

guard let doc = PDFDocument(url: src), doc.pageCount > 0 else {
    FileHandle.standardError.write(Data("cannot open \(src.path)\n".utf8))
    exit(1)
}
let requested = args.dropFirst(2).compactMap { Int($0) }
let pages: [Int] = requested.isEmpty
    ? (1...min(12, doc.pageCount)).map { $0 * doc.pageCount / 13 }.filter { $0 > 0 }
    : requested

func bytes(_ url: URL) -> Int { (try? Data(contentsOf: url).count) ?? 0 }

/// One page, alone in its own PDF, because both routes below take a document.
func isolate(_ index: Int) -> URL? {
    guard let page = doc.page(at: index - 1) else { return nil }
    let one = PDFDocument()
    one.insert(page, at: 0)
    let url = work.appendingPathComponent("p\(index).pdf")
    return one.write(to: url) ? url : nil
}

print("page\troute\tsat\ttone\tinkOut\tlayered\t1bit\tdelta\tverdict")
var totalLayered = 0, totalBilevel = 0, counted = 0
var allTextLayered = 0, allTextBilevel = 0, allTextPages = 0

for index in pages {
    guard let single = isolate(index), let page = doc.page(at: index - 1) else { continue }

    // A12.2. Isolating the page can change the resolution the rebuild renders it
    // at — `largestImage` walks a `/Resources` that 4 of 208 multi-page corpus
    // documents share across every page, so the whole file and the extract answer
    // differently. This tool is *cited* as pricing TODO item 1 at 8.2 KB a page —
    // cited rather than responsible, because C25 records that no committed version of
    // this file has ever compiled — and a row measured at the wrong resolution would
    // not be that page's price either. qpdf --pages does
    // not help; `BUGS.md` C24 records why the app-side repair has no threshold to
    // stand on.
    if let isolated = PDFDocument(url: single)?.page(at: 0) {
        let before = Flattener.rebuildDPI(of: page)
        let after = Flattener.rebuildDPI(of: isolated)
        if abs(before - after) > 0.5 {
            // Eight dashes, not nine: the header lost its `toneOut` column in
            // this same commit. A SKIP row wider than its header shifts every
            // column from `layered` rightward, which is a reporting defect
            // arriving inside a fix for a reporting defect.
            print(String(format: "p%d\t-\t-\t-\t-\t-\t-\t-\t"
                         + "SKIP isolation moved the rebuild DPI %.0f->%.0f (A12.2)",
                         index, before, after))
            continue
        }
    }

    // --- what the app does today, at this page's own routing decision ---
    let autoDir = work.appendingPathComponent("auto\(index)")
    try? FileManager.default.createDirectory(at: autoDir, withIntermediateDirectories: true)
    guard let auto = try? Flattener.flatten(single, to: work.appendingPathComponent("a\(index).pdf"),
                                            mode: .auto, pngDirectory: autoDir),
          let first = auto.first else { continue }
    let route: String
    var isColour = false
    switch first.content {
    case .bilevel: route = "bilevel"
    case .jpeg: route = first.isColour ? "colour" : "grey"; isColour = first.isColour
    }
    // A page already on the 1-bit route is not what this is about.
    guard case .jpeg(let jpegURL) = first.content else {
        print("p\(index)\t\(route)\t-\t-\t-\t-\t-\t-\t-\talready 1-bit")
        continue
    }

    // --- the signals, and the boxes a post-recognition decision would use ---
    let box = Flattener.fullBox(of: page)
    let dpi = Flattener.rebuildDPI(of: page)
    let scale = dpi / 72.0
    let w = max(Int((box.width * scale).rounded()), 1)
    let h = max(Int((box.height * scale).rounded()), 1)
    guard let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                          width: w, height: h, from: .mediaBox) else { continue }
    let threshold = Flattener.otsuThreshold(of: grey)
    let tone = Flattener.toneFraction(of: grey, threshold: threshold)
    let sat = Flattener.saturation(of: page)

    // Recognise the bitmap the app publishes, not a re-render of the page: the
    // whole point of R40 is that those are the same pixels.
    var boxes: [SearchableWriter.BoundingBox] = []
    if let source = CGImageSourceCreateWithURL(jpegURL as CFURL, nil),
       let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
       let observations = try? Recogniser.recognise(image, settings: settings) {
        boxes = observations.map { $0.boundingBox }
    }
    let region = Flattener.textRegionMask(boxes, width: w, height: h)
    let inkOut = Flattener.inkOutsideText(grey, region: region, width: w, height: h,
                                          threshold: threshold)
    // `Flattener.toneOutsideText` was printed in a `toneOut` column here and
    // **has never existed in any commit of this repository** — `git log -S` over
    // all history finds it in this file and nowhere else. So this tool has not
    // compiled since the line was added, in the R56/R57 commit, while its own
    // header carries the build command that fails and three documents cite it as
    // the way to re-measure. See `BUGS.md` C25.
    //
    // Removed rather than implemented: the tool's stated principle is that it
    // drives shipped code so it cannot drift, and there is no shipped signal for
    // continuous tone outside the recognised words. Adding one to `Flattener` for
    // a tool's benefit would put dead code on the app's side, which is the call
    // `score-skew` and `score-threshold-loss` both already record.
    let allText = inkOut < Flattener.textPageInkOutsideThreshold

    // --- layered, exactly as it ships ---
    var layered = 0
    if !boxes.isEmpty,
       let layers = Flattener.mrcLayers(for: page, boxes: boxes, into: work,
                                       stem: "m\(index)", inColour: isColour) {
        let stencil = work.appendingPathComponent("m\(index).jbig2")
        if (try? JBIG2.encode(png: layers.mask, to: stencil, using: jbig2)) != nil {
            layered = bytes(stencil) + bytes(layers.background) + bytes(layers.foreground)
        }
    }
    // Layering declining is a real answer: the page keeps its single JPEG.
    if layered == 0 { layered = bytes(jpegURL) }

    // --- 1-bit, via the shipped Black & white route ---
    let bwDir = work.appendingPathComponent("bw\(index)")
    try? FileManager.default.createDirectory(at: bwDir, withIntermediateDirectories: true)
    var bilevel = 0
    if let bw = try? Flattener.flatten(single, to: work.appendingPathComponent("b\(index).pdf"),
                                       mode: .blackAndWhite, pngDirectory: bwDir),
       case .bilevel(let png)? = bw.first?.content {
        let stream = work.appendingPathComponent("b\(index).jbig2")
        if (try? JBIG2.encode(png: png, to: stream, using: jbig2)) != nil {
            bilevel = bytes(stream)
        }
    }
    guard layered > 0, bilevel > 0 else {
        print("p\(index)\t\(route)\tencode failed")
        continue
    }

    totalLayered += layered; totalBilevel += bilevel; counted += 1
    if allText { allTextLayered += layered; allTextBilevel += bilevel; allTextPages += 1 }
    print(String(format: "p%d\t%@\t%.3f\t%.3f\t%.4f\t%d\t%d\t%+d\t%@",
                 index, route, sat, tone, inkOut, layered, bilevel,
                 bilevel - layered, allText ? "all-text" : "picture"))
}

print("")
guard counted > 0 else { print("no picture-route pages measured"); exit(0) }
print("\(counted) picture-route pages: layered \(totalLayered) B, 1-bit \(totalBilevel) B, "
      + String(format: "delta %+d B (%.0f B/page)",
               totalBilevel - totalLayered,
               Double(totalBilevel - totalLayered) / Double(counted)))
if allTextPages > 0 {
    print("\(allTextPages) of them read all-text: layered \(allTextLayered) B, "
          + "1-bit \(allTextBilevel) B, "
          + String(format: "delta %+d B (%.0f B/page)",
                   allTextBilevel - allTextLayered,
                   Double(allTextBilevel - allTextLayered) / Double(allTextPages)))
    print("negative delta = 1-bit is smaller = the prize; positive = the route it "
          + "already takes is cheaper")
}
