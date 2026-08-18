// Every page of a corpus, the route `Flattener` sends it down, and the shape
// statistics behind that route. One row a page.
//
// **This is the acceptance test for a routing change, and it exists because the
// alternative is an aggregate.** `score-routing` samples four pages a document and
// prints three counts; that answers "did the totals move" and cannot answer "which
// page changed", which is the only question worth asking of a detector that has been
// refused four times for moving the wrong pages. FEATURES.md's order of work names
// this as step 1 and says why: *a signal that fixes the fixtures and moves corpus
// pages is not a fix, it is a different set of defects.*
//
// It reads each page **from the document it is in**, never from an extracted copy, which is
// what made it comparable with production while C24 was open: `rebuildDPI` read the shared
// `/Resources` then, so a census that extracted its pages would have reported a resolution
// production did not use (A12.2, and `score-routing` refused rows for exactly this reason).
// **C24 closed 2026-08-17** — `rebuildDPI` applies the policy to what the page draws, and
// extraction rewrites a page's `/Resources` to hold what it references, so the two now agree
// and `score-routing`'s three refused documents print rows. Reading in place stays right for
// its own reasons: it is what the census's before/after diffs were taken with, and nothing
// here should depend on PDFKit's rewriting being faithful.
//
// **Every number below comes from `Flattener`'s own functions.** This file computes
// nothing the app does not compute; it only arranges the answers in columns. An
// earlier draft carried its own labelling, its own reduction and its own pale-mask
// construction, and they were already drifting from the versions that shipped —
// BUGS.md T15 is what that costs (five divergences in one tool, not all in the same
// direction, so the errors did not cancel).
//
//   mkdir -p /tmp/h && cp Tools/score-routing-census.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/census -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/census testdocs/*/*.pdf > before.tsv
//   … change the detector …
//   /tmp/census testdocs/*/*.pdf > after.tsv
//   diff <(cut -f1,2,8 before.tsv) <(cut -f1,2,8 after.tsv)
//
// `JOBS=n` sets the document concurrency (default 6, the app's own). `PAGES=n` samples
// n pages a document through `Flattener.sampleIndices` instead of walking all of them —
// for a quick look, **not** for an acceptance run, and the header row says which was
// asked for so a sampled file cannot be mistaken for a census.
//
// `draw` is what the route is decided on — the largest drawing-shaped pale mark, as a
// share of the sheet — and `drawink` is the ink of *every* such mark, which is what the
// first version decided on and which under-counts a thin-stroked chart. The last four
// columns sweep `maximumInkUnderADrawing` over 0.02/0.05/0.10/1.00 in the one pass,
// because choosing that constant is the expensive question and a full census is half an
// hour. `ink100` is the term switched off entirely, which is what the first attempt at
// this signal did and what `Doermann_1967`'s show-through defeated.
//
// A page it cannot measure gets a row saying so rather than no row: a census with a
// silent hole in it is how a routing change hides. Every row is buffered and printed
// in **input order** after the last worker finishes, so two runs diff cleanly — the
// first version streamed each document as it completed, which is *concurrency* order,
// and the `diff` prescribed above then reported 5,370 changed lines over 210 changed
// pages. The last line is `# complete: N/N documents, R rows`; a run without it did
// not finish, and its absence is the only way to tell.
import AppKit
import Foundation
import PDFKit

// MARK: - Self-test, on every run
//
// `score-threshold-loss` earns its keep this way and so does `score-skew`. The
// functions under test are `Flattener`'s, so this is a check on the app rather than
// on the tool — which is the point: a labelling with a union-find in it is exactly
// the code that reports a plausible number while being wrong.

func selfTest() -> [String] {
    var failures: [String] = []
    func expect(_ name: String, _ ok: Bool, _ detail: String) {
        if !ok { failures.append("\(name) — \(detail)") }
    }
    let W = 40, H = 40
    // Two disjoint squares.
    var two = [Bool](repeating: false, count: W * H)
    for y in 2..<8 { for x in 2..<8 { two[y * W + x] = true } }
    for y in 20..<26 { for x in 20..<26 { two[y * W + x] = true } }
    let c2 = Flattener.markComponents(two, width: W, height: H)
    expect("two squares are two components", c2.count == 2, "\(c2.count)")
    expect("a solid square fills its box", c2.allSatisfy { abs($0.fill - 1) < 0.001 },
           c2.map { String(format: "%.3f", $0.fill) }.joined(separator: " "))
    expect("each square is 6 cells tall", c2.allSatisfy { $0.height == 6 },
           c2.map { "\($0.height)" }.joined(separator: " "))

    // A U: 8-connected round the bend, and one component either way. This is the case
    // a labelling gets wrong by merging through the row above rather than through the
    // union-find.
    var u = [Bool](repeating: false, count: W * H)
    for y in 10..<20 { u[y * W + 10] = true; u[y * W + 19] = true }
    for x in 10..<20 { u[19 * W + x] = true }
    let cu = Flattener.markComponents(u, width: W, height: H)
    expect("a U is one component", cu.count == 1, "\(cu.count)")
    expect("…and does not fill its box", (cu.first?.fill ?? 1) < 0.4,
           String(format: "%.3f", cu.first?.fill ?? -1))

    // A diagonal, which only 8-connectivity joins.
    var diag = [Bool](repeating: false, count: W * H)
    for i in 0..<20 { diag[(i + 5) * W + (i + 5)] = true }
    expect("a diagonal is one 8-connected component",
           Flattener.markComponents(diag, width: W, height: H).count == 1,
           "\(Flattener.markComponents(diag, width: W, height: H).count)")

    // A comb: labels created left to right and joined by a later row, which is the
    // merge direction the first pass cannot see.
    var comb = [Bool](repeating: false, count: W * H)
    for x in stride(from: 4, to: 36, by: 2) { for y in 4..<12 { comb[y * W + x] = true } }
    for x in 4..<36 { comb[12 * W + x] = true }
    expect("a comb joined at its base is one component",
           Flattener.markComponents(comb, width: W, height: H).count == 1,
           "\(Flattener.markComponents(comb, width: W, height: H).count)")

    expect("an empty mask has no components",
           Flattener.markComponents([Bool](repeating: false, count: W * H),
                                    width: W, height: H).isEmpty, "not empty")

    // The masks, on a synthetic page at a known resolution. 300 DPI, so the reduction
    // factor is 2, a cell is 2 px, and the quarter-inch ceiling is 37.5 cells.
    let PW = 1200, PH = 1200
    let dpi = 300.0
    var grey = [UInt8](repeating: 250, count: PW * PH)
    for band in stride(from: 100, to: 400, by: 36) {          // rows of type
        for y in band..<(band + 18) {
            for x in 100..<1100 where (x / 21) % 2 == 0 { grey[y * PW + x] = 20 }
        }
        for y in [band - 2, band + 18] {                       // anti-aliased edge
            for x in 100..<1100 where (x / 21) % 2 == 0 { grey[y * PW + x] = 200 }
        }
    }
    let clean = Flattener.pageMarks(grey, width: PW, height: PH, threshold: 128, dpi: dpi)
    expect("the page's ink is ink", clean.ink.filter { $0 }.count > 200,
           "\(clean.ink.filter { $0 }.count) ink cells")
    expect("its anti-aliased edge is not pale content",
           clean.pale.filter { $0 }.count == 0,
           "\(clean.pale.filter { $0 }.count) pale cells on a page of type alone")
    expect("a page of type alone has no drawing on it",
           Flattener.paleDrawing(clean, dpi: dpi).extent == 0,
           String(format: "%.4f", Flattener.paleDrawing(clean, dpi: dpi).extent))
    expect("…and nothing big enough to ask about its tone",
           Flattener.largeMarkTone(clean, grey: grey, width: PW, height: PH,
                                   threshold: 128) == 0,
           String(format: "%.4f",
                  Flattener.largeMarkTone(clean, grey: grey, width: PW, height: PH,
                                          threshold: 128)))

    func drawing(_ page: [UInt8]) -> Double {
        Flattener.paleDrawing(
            Flattener.pageMarks(page, width: PW, height: PH, threshold: 128, dpi: dpi),
            dpi: dpi).extent
    }
    // A long pale stroke, well below the paper: a drawing.
    var stroke = grey
    for i in 0..<600 { for d in 0..<4 { stroke[(500 + i / 2) * PW + 300 + i + d] = 190 } }
    expect("a long pale stroke is a drawing", drawing(stroke) > 0,
           String(format: "%.4f", drawing(stroke)))
    // The same stroke four levels below the paper: not a mark at all. This is the
    // Himanen case, and without `minimumMarkContrast` it scored as a drawing.
    var faint = grey
    for i in 0..<600 { for d in 0..<4 { faint[(500 + i / 2) * PW + 300 + i + d] = 246 } }
    expect("…and one you can barely see is not", drawing(faint) == 0,
           String(format: "%.4f", drawing(faint)))
    // A pale filled block is shading, not a drawing.
    var block = grey
    for y in 700..<1000 { for x in 200..<1000 { block[y * PW + x] = 190 } }
    expect("a pale filled block is not a drawing", drawing(block) == 0,
           String(format: "%.4f", drawing(block)))

    // And the tone question, on a mark large enough to be asked about: a smooth ramp
    // reads as tone, a solid rectangle of the same size does not.
    var ramp = grey, solid = grey
    for y in 600..<1100 {
        for x in 200..<1000 {
            ramp[y * PW + x] = UInt8(20 + (x - 200) * 200 / 800)
            solid[y * PW + x] = 20
        }
    }
    let rampTone = Flattener.largeMarkTone(
        Flattener.pageMarks(ramp, width: PW, height: PH, threshold: 128, dpi: dpi),
        grey: ramp, width: PW, height: PH, threshold: 128)
    let solidTone = Flattener.largeMarkTone(
        Flattener.pageMarks(solid, width: PW, height: PH, threshold: 128, dpi: dpi),
        grey: solid, width: PW, height: PH, threshold: 128)
    expect("a large tonal mark reads as tone", rampTone > Flattener.pictureToneThreshold,
           String(format: "%.4f", rampTone))
    expect("…and a solid one of the same size does not",
           solidTone < Flattener.pictureToneThreshold,
           String(format: "%.4f solid vs %.4f ramp", solidTone, rampTone))
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

let env = ProcessInfo.processInfo.environment
let jobs = max(Int(env["JOBS"] ?? "") ?? 6, 1)
let sampled = Int(env["PAGES"] ?? "") ?? 0
if sampled < 0 {
    FileHandle.standardError.write(Data("PAGES must be positive\n".utf8))
    exit(2)
}
// The two constants whose value is the open question, swept in the one pass because
// a full census is half an hour. The shipped pair is repeated in the `draw` column.
let inkUnders: [Double] = [0.02, 0.05, 0.10, 1.00]

let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else {
    FileHandle.standardError.write(Data("usage: census <pdf> [pdf …]\n".utf8))
    exit(2)
}

let columns = ["document", "page", "dpi", "otsu", "ink", "tone", "sat", "route",
               "comps", "biggest", "inkshare", "bigtone", "paper", "palecells",
               "draw", "drawink", "ink02", "ink05", "ink10", "ink100"]
print(columns.joined(separator: "\t"))
print("# pages=\(sampled == 0 ? "all" : String(sampled)) jobs=\(jobs)"
      + " cells/in=\(Flattener.markCellsPerInch) contrast=\(Flattener.minimumMarkContrast)")
fflush(stdout)

func row(_ fields: [String]) -> String {
    precondition(fields.count == columns.count,
                 "row has \(fields.count) fields against \(columns.count) columns")
    return fields.joined(separator: "\t")
}

let queue = DispatchQueue(label: "out")
let group = DispatchGroup()
let slots = DispatchSemaphore(value: jobs)
var done = 0
// Held by input position and printed after the last worker, **not** streamed as each
// document finishes. Streaming is what the first version did, and the header above it
// claimed the opposite: documents came out in *completion* order, so the `diff` this
// file prescribes reported **5,370 changed lines over 210 changed pages** — a 25x
// fabricated difference, in the one instrument whose whole purpose is naming the pages
// that moved. Found by the review of the diff that added it.
var byDocument = [[String]](repeating: [], count: paths.count)

for (position, path) in paths.enumerated() {
    slots.wait()
    group.enter()
    DispatchQueue.global().async {
        defer { slots.signal(); group.leave() }
        let url = URL(fileURLWithPath: path)
        let label = url.deletingPathExtension().lastPathComponent
        var lines: [String] = []
        defer {
            queue.sync {
                byDocument[position] = lines
                done += 1
                FileHandle.standardError.write(
                    Data("\(done)/\(paths.count) \(label)\n".utf8))
            }
        }
        // One dash column per measurement, so a row that measured nothing still has
        // the header's width. Counting tabs by eye has put the wrong number of fields
        // under a header three times here (CONTRIBUTING §5).
        func blank(_ page: String, _ dpi: String, _ why: String) -> String {
            row([label, page, dpi, "-", "-", "-", "-", why]
                + [String](repeating: "-", count: columns.count - 8))
        }
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
            lines.append(blank("-", "-", "UNREADABLE"))
            return
        }
        let indices = sampled == 0
            ? Array(0..<doc.pageCount)
            : Flattener.sampleIndices(count: doc.pageCount, wanted: sampled)
        for i in indices {
            guard let page = doc.page(at: i) else {
                lines.append(blank("p\(i + 1)", "-", "NOPAGE"))
                continue
            }
            let box = Flattener.fullBox(of: page)
            let dpi = Flattener.rebuildDPI(of: page)
            let scale = dpi / 72.0
            let wide = (box.width * scale).rounded(), high = (box.height * scale).rounded()
            guard wide.isFinite, high.isFinite, wide >= 1, high >= 1,
                  wide * high <= Double(Flattener.maximumPageMegapixels) * 1_000_000 else {
                lines.append(blank("p\(i + 1)", String(format: "%.0f", dpi), "TOOLARGE"))
                continue
            }
            let w = max(Int(wide), 1), h = max(Int(high), 1)
            guard let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                                  width: w, height: h, from: .mediaBox) else {
                lines.append(blank("p\(i + 1)", String(format: "%.0f", dpi), "NORENDER"))
                continue
            }
            let t = Flattener.otsuThreshold(of: grey)
            let ink = Flattener.inkCoverage(of: grey, width: w, height: h, threshold: t)
            let tone = Flattener.toneFraction(of: grey, threshold: t)
            let sat = Flattener.saturation(of: page)
            let picture = Flattener.isPicture(page, grey: grey, width: w, height: h,
                                              threshold: t, saturation: sat)
            // The render's own resolution, not `rebuildDPI` again — the same
            // derivation `isPicture` makes, so these columns describe the decision
            // rather than a second opinion about it.
            let renderDPI = Flattener.renderDPI(of: page, pixelWidth: w)
            let marks = Flattener.pageMarks(grey, width: w, height: h,
                                            threshold: t, dpi: renderDPI)
            let inkComponents = Flattener.markComponents(marks.ink, width: marks.width,
                                                         height: marks.height)
            var biggest = 0.0, biggestInk = 0
            var totalInk = 0
            for c in inkComponents {
                totalInk += c.area
                let boxShare = Double(c.width * c.height) / Double(max(marks.cells, 1))
                if boxShare > biggest { biggest = boxShare }
                if c.area > biggestInk { biggestInk = c.area }
            }
            let bigTone = Flattener.largeMarkTone(marks, grey: grey, width: w, height: h,
                                                  threshold: t)
            var sweep: [String] = []
            for u in inkUnders {
                sweep.append(String(format: "%.4f",
                                    Flattener.paleDrawing(marks, dpi: renderDPI,
                                                          maximumInkInBox: u).extent))
            }
            lines.append(row([
                label, "p\(i + 1)", String(format: "%.0f", dpi), String(Int(t)),
                String(format: "%.4f", ink), String(format: "%.4f", tone),
                String(format: "%.4f", sat), picture ? "picture" : "1-bit",
                String(inkComponents.count),
                String(format: "%.4f", biggest),
                String(format: "%.4f", totalInk > 0
                       ? Double(biggestInk) / Double(totalInk) : 0),
                String(format: "%.4f", bigTone),
                String(marks.paperLimit),
                String(marks.pale.filter { $0 }.count),
                String(format: "%.4f", Flattener.paleDrawing(marks, dpi: renderDPI).extent),
                String(format: "%.4f", Flattener.paleDrawing(marks, dpi: renderDPI).coverage)]
                + sweep))
        }
    }
}
group.wait()
var rows = 0
for lines in byDocument { for l in lines { print(l); rows += 1 } }
// A trailer, because a census truncated by a full disk, a dropped shell argument or a
// worker that died is otherwise indistinguishable from a complete one — invariant 1's
// "truncated but valid" shape, arriving in the instrument instead of in a PDF. Read it
// before believing a diff: a run that did not finish has no `# complete` line at all.
print("# complete: \(done)/\(paths.count) documents, \(rows) rows")
if done != paths.count {
    FileHandle.standardError.write(
        Data("census: \(done) of \(paths.count) documents completed\n".utf8))
    exit(1)
}
