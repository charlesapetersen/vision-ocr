import PDFKit
import Foundation

// How much of its own box does each run actually cover? Property (c), counted.
//
//     score-run-width <pdf> <label> [--worst N] [--pages N]
//
// `REVIEW-2026-08-14.md` A1.2: a whole line can be drawn at 5% of its box width
// because a same-visual-line "neighbour" starts a couple of points right of its
// LEFT edge, `rightLimit` accepts it, and the run is shrunk to nothing. Nothing
// reports it — the characters are all in the content stream, so search still
// works and `Unplaced` stays empty, while a click past the first tenth of the
// line highlights some other line.
//
// The three existing instruments cannot see it:
//
//   - `score-corpus`'s `end=` column, `probe-line-edges` and
//     `probe-line-coverage` are one idea in three shells (T14) — probe the
//     right-hand 15% of the line's box and ask whether *anything* is selectable
//     there. A sliver leaves that rectangle over the line ABOVE, whose run does
//     reach it, so the probe comes back non-empty and the page scores clean.
//   - `score-line-separation` counts merged lines, not run widths.
//
// So this one asks the writer directly. It does not re-derive the arithmetic:
// `SearchableWriter.prepared` builds the same list `compose` draws,
// `SearchableWriter.rightLimit` picks the same neighbour, and
// `SearchableWriter.placement` returns the same `Run` `draw` draws. A second copy
// of any of those three is C20's shape — two definitions of one idea, drifting —
// and this project has paid for it twice (C20 itself, then the "one visual line"
// the old score-line-separation kept for itself).
//
// ## Which route this measures
//
// The **direct** route: the file given is the file composed over, which is what
// the app does when Rebuild page images is off, and what Extract Text does. On
// the default route `compose` runs over the rebuilt copy, whose page rasters are
// re-rendered at `Flattener.rebuildDPI`, so Vision sees a slightly different
// image and the fragment geometry is not identical. The counts below are for the
// direct route and the row says so, because T17 is in the register for a tool
// that measured a route the app does not take while reading as though it had.
//
// ## Reading the row
//
//   frags      placements the writer made (refused ones are counted separately)
//   limited    how many had a same-visual-line neighbour shorten them
//   sliver15   runs drawn under 15% of their own box — the A1.2 population
//   sliver50   under 50%
//   minshare   the narrowest run on the sampled pages, as a share of its box
//   crushed    runs under half their box width AND under half the height they
//              wanted — C20's symptom, a pair given both treatments at once
//   minheight  the most-squashed run, as a share of the height it wanted
//   room*      percentiles of (neighbour's left edge - my left edge) / my box
//              width, over the limited runs. This is the quantity a guard on
//              "a neighbour that leaves me no usable width" would threshold, and
//              the percentiles are printed so the threshold can be read off a
//              distribution rather than chosen.

// MARK: - The census, as a pure function the self-test can drive

struct Census {
    var pages = 0
    var frags = 0, limited = 0, refused = 0
    var shares: [Double] = []      // drawn advance / box width, per placed run
    var heights: [Double] = []     // drawn glyph height / the height it wanted
    var rooms: [Double] = []       // (rightLimit - left) / box width, per limited run
    /// Runs both narrowed by a neighbour and squashed by the ceiling — C20's
    /// symptom, which is the cost side of A1.1's `.taller` reserve scale.
    var crushed = 0
    /// The narrowest runs, worst first: share, room, text, box width in points.
    var worst: [(share: Double, room: Double, text: String, boxWidth: Double)] = []

    var sliver15: Int { shares.filter { $0 < 0.15 }.count }
    var sliver50: Int { shares.filter { $0 < 0.50 }.count }
    var minShare: Double { shares.min() ?? .nan }
    var minHeight: Double { heights.min() ?? .nan }

    mutating func merge(_ other: Census) {
        pages += other.pages; frags += other.frags
        limited += other.limited; refused += other.refused
        crushed += other.crushed
        shares += other.shares; heights += other.heights; rooms += other.rooms
        worst = (worst + other.worst).sorted { $0.share < $1.share }
    }
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let sorted = values.sorted()
    let i = Int((p / 100.0 * Double(sorted.count - 1)).rounded())
    return sorted[min(max(i, 0), sorted.count - 1)]
}

/// One page's census, from the observations the writer would draw.
///
/// `prepared` and `rightLimit` and `placement` are the app's own; this function
/// is only the loop around them and the arithmetic of a percentage.
func census(of raw: [SearchableWriter.Observation], nextPage: [SearchableWriter.Observation],
            in region: CGRect, font: CTFont) -> Census {
    var c = Census()
    c.pages = 1
    let lines = SearchableWriter.prepared(raw, nextPage: nextPage, in: region)
    for (position, observation) in lines.enumerated() {
        let limit = SearchableWriter.rightLimit(for: position, among: lines, in: region)
        // The REAL ceiling, from the app's own `headroom`, not an unbounded one.
        // The first version of this file passed `.greatestFiniteMagnitude` and
        // argued it could only understate — true for the width, and it made the
        // tool blind to C20's symptom, which is a run losing both directions at
        // once. Measuring what the app draws is never the harder defence.
        let ceiling = SearchableWriter.headroom(for: position, among: lines, in: region)
        switch SearchableWriter.placement(of: observation, in: region, ceiling: ceiling,
                                          rightLimit: limit, font: font) {
        case .refused:
            c.refused += 1
        case .placed(let run):
            c.frags += 1
            c.shares.append(Double(run.widthShare))
            c.heights.append(Double(run.heightShare))
            if run.widthShare < 0.5 && run.heightShare < 0.5 { c.crushed += 1 }
            if run.limitedByNeighbour {
                c.limited += 1
                c.rooms.append(Double((limit - run.left) / run.boxWidth))
            }
            c.worst.append((Double(run.widthShare),
                            run.limitedByNeighbour
                                ? Double((limit - run.left) / run.boxWidth) : .infinity,
                            observation.text, Double(run.boxWidth)))
        }
    }
    c.worst = c.worst.sorted { $0.share < $1.share }
    return c
}

// MARK: - One row, one printer

let header = ["label", "status", "pages", "frags", "limited", "sliver15", "sliver50",
              "minshare", "crushed", "minheight", "roommin", "roomp1", "roomp5", "roomp50",
              "seconds"]
let columnCount = 15

/// The only place a row is assembled. Anything else is counting dashes by eye.
///
/// Declared above the self-test that checks it, because top-level code runs in
/// order and a function reading a `let` declared further down is a compile error
/// here, not a runtime surprise.
func row(_ columns: [String]) -> String {
    precondition(columns.count == columnCount,
                 "score-run-width: \(columns.count) columns, header has \(columnCount)")
    return columns.joined(separator: "\t")
}

// MARK: - Self-test, on every invocation

func fail(_ what: String, _ detail: String) -> Never {
    FileHandle.standardError.write(Data("score-run-width self-test FAILED: \(what) — \(detail)\n".utf8))
    exit(4)
}

func selfTest() {
    let box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
    func obs(_ text: String, x: Double, width w: Double,
             y: Double = 0.30, height h: Double = 0.016) -> SearchableWriter.Observation {
        SearchableWriter.Observation(
            boundingBox: SearchableWriter.BoundingBox(x: x, y: y, width: w, height: h),
            text: text, confidence: 1.0)
    }

    // 1. THE DIRECTION PROOF, and it does not go through `rightLimit`: given a
    //    limit a couple of points right of the run's own left edge, the writer
    //    draws a sliver and this instrument must report one. Driving `placement`
    //    directly is deliberate — if the fix for A1.2 makes `rightLimit` refuse
    //    that neighbour, this case still has to bite, or the instrument loses the
    //    ability to see the defect it was built for on the day it is fixed.
    let wide = obs("a sixty character line of newspaper body text set solid", x: 0.10, width: 0.4319)
    switch SearchableWriter.placement(of: wide, in: box, ceiling: .greatestFiniteMagnitude,
                                      rightLimit: 0.10 * 612 + 3.62, font: font) {
    case .refused(let why): fail("a sliver is placed, not refused", why)
    case .placed(let run):
        guard run.widthShare < 0.15 else {
            fail("a neighbour 3.62 pt right of the left edge draws a sliver",
                 String(format: "share %.4f, wanted under 0.15", run.widthShare))
        }
        guard run.limitedByNeighbour else {
            fail("a sliver knows it was limited by a neighbour", "limitedByNeighbour false")
        }
    }

    // 2. A healthy page reports no slivers. Three fragments of one visual line,
    //    boxes touching — the ordinary newspaper case, which must not be counted
    //    as a defect.
    //
    //    Touching rather than merely close, so the first two are really shortened
    //    by the reserve and the case exercises the limited path at all: with the
    //    neighbour a few points PAST the box edge there is more room than box,
    //    `allowed < width` is false and nothing is limited. That is not a defect
    //    — it is the reserve costing nothing — but it would make this a check
    //    over a path it never entered.
    let healthy = [obs("that", x: 0.100, width: 0.055),
                   obs("measurable by standardised", x: 0.155, width: 0.300),
                   obs("methods of assessment", x: 0.455, width: 0.250)]
    let clean = census(of: healthy, nextPage: [], in: box, font: font)
    guard clean.frags == 3, clean.sliver15 == 0, clean.sliver50 == 0 else {
        fail("three ordinary side-by-side fragments are not slivers",
             "frags \(clean.frags), <15% \(clean.sliver15), <50% \(clean.sliver50), "
             + String(format: "min %.3f", clean.minShare))
    }
    guard clean.limited == 2 else {
        fail("the first two of three touching fragments are limited by their neighbour",
             "limited \(clean.limited) of 3 — the third has no neighbour; if the first "
             + "two are not limited, this case proves nothing")
    }

    // 3. The ceiling can only shrink a run, never widen it. The row above passes
    //    an unbounded ceiling; this is the check that says what that costs.
    switch SearchableWriter.placement(of: healthy[2], in: box, ceiling: 1.0,
                                      rightLimit: .greatestFiniteMagnitude, font: font) {
    case .refused(let why): fail("a squashed run is still placed", why)
    case .placed(let squashed):
        switch SearchableWriter.placement(of: healthy[2], in: box,
                                          ceiling: .greatestFiniteMagnitude,
                                          rightLimit: .greatestFiniteMagnitude, font: font) {
        case .refused(let why): fail("an unbounded run is placed", why)
        case .placed(let free):
            guard squashed.widthShare <= free.widthShare + 1e-9 else {
                fail("a ceiling never widens a run",
                     String(format: "%.4f with a 1 pt ceiling vs %.4f without",
                            squashed.widthShare, free.widthShare))
            }
        }
    }

    // 4. Nothing measured is not a clean bill. An empty page must produce an
    //    empty census, and the caller below turns that into a SKIP at exit 1 —
    //    T12's rule, twice over in this repo: a skip that exits 0 is a pass
    //    wearing a different word.
    let nothing = census(of: [], nextPage: [], in: box, font: font)
    guard nothing.frags == 0, nothing.shares.isEmpty, nothing.minShare.isNaN else {
        fail("an empty page measures nothing", "\(nothing.frags) fragments")
    }

    // 5. The row and its header have the same number of fields. Counting tab
    //    escapes by eye has put the wrong number of fields under a header three
    //    times in this project (T14, A12.3, T18).
    guard header.count == columnCount else {
        fail("the header has \(columnCount) columns", "it lists \(header.count)")
    }
    // Written out rather than `header.map`, which would agree with itself
    // whatever either of them said.
    let sample = row(["1", "2", "3", "4", "5", "6", "7", "8",
                      "9", "10", "11", "12", "13", "14", "15"])
    guard sample.components(separatedBy: "\t").count == columnCount else {
        fail("a row has \(columnCount) fields",
             "\(sample.components(separatedBy: "\t").count)")
    }
}

selfTest()

// MARK: - Running one document

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("""
        usage: score-run-width <pdf> <label> [--worst N] [--pages N]

        The self-test above has passed. Columns:
        \(header.joined(separator: "\t"))

        """.utf8))
    exit(2)
}
let src = URL(fileURLWithPath: CommandLine.arguments[1])
let label = CommandLine.arguments[2]
var worstWanted = 0, pagesWanted = 3
var argument = 3
while argument < CommandLine.arguments.count {
    let flag = CommandLine.arguments[argument]
    let value = argument + 1 < CommandLine.arguments.count
        ? Int(CommandLine.arguments[argument + 1]) : nil
    switch flag {
    case "--worst": worstWanted = value ?? 10
    case "--pages": pagesWanted = value ?? 3
    default:
        FileHandle.standardError.write(Data("score-run-width: unknown option \(flag)\n".utf8))
        exit(2)
    }
    argument += 2
}

func skip(_ why: String) -> Never {
    print(row([label, "SKIP"] + Array(repeating: "-", count: columnCount - 3)
              + [why.replacingOccurrences(of: "\t", with: " ")]))
    exit(1)
}

Prefs.register(migrate: false)
UserDefaults.standard.set(false, forKey: Prefs.openWhenDone)

let began = Date()
guard let doc = Flattener.open(src, password: nil), doc.pageCount > 0 else {
    skip("cannot open source")
}
// `Flattener.sampleIndices`, not a fifth copy of the page stride: T18 found five
// of them in Tools/, two of which measured one page twice.
let indices = Flattener.sampleIndices(count: doc.pageCount, wanted: pagesWanted)
let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("rw-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

// Recognised as one document, so the observations are numbered the way `compose`
// numbers them and a page's continuation candidates are its real successor's.
let sample = PDFDocument()
for i in indices { if let p = doc.page(at: i) { sample.insert(p, at: sample.pageCount) } }
let input = work.appendingPathComponent("in.pdf")
guard sample.write(to: input) else { skip("cannot write the sampled pages") }
guard let reopened = PDFDocument(url: input) else { skip("cannot re-open the sample") }
guard let byPage = try? Recogniser.recogniseDocument(visible: input, bitmaps: [],
                                                     settings: .current()) else {
    skip("recognition failed")
}

let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
var total = Census()
for number in 1...max(reopened.pageCount, 1) {
    guard let page = reopened.page(at: number - 1) else { continue }
    // The region `compose` normalises to: the crop box as it lands on the
    // published page, through the app's own function.
    let pageBox = CGRect(origin: .zero, size: Flattener.fullBox(of: page).size)
    let region = SearchableWriter.cropRegion(of: page, on: pageBox)
    total.merge(census(of: byPage[number] ?? [], nextPage: byPage[number + 1] ?? [],
                       in: region, font: font))
}

guard total.frags > 0 else {
    skip("measured nothing: \(total.pages) page(s) produced no placed run "
         + "(\(total.refused) refused)")
}

if worstWanted > 0 {
    for w in total.worst.prefix(worstWanted) {
        FileHandle.standardError.write(Data(String(
            format: "  share %6.2f%%  room %8.4f  box %6.1f pt  %@\n",
            w.share * 100, w.room, w.boxWidth, String(w.text.prefix(60))).utf8))
    }
}

func f(_ v: Double) -> String { v.isNaN ? "-" : String(format: "%.4f", v) }
print(row([label, "OK", "\(total.pages)", "\(total.frags)", "\(total.limited)",
           "\(total.sliver15)", "\(total.sliver50)", f(total.minShare),
           "\(total.crushed)", f(total.minHeight),
           f(percentile(total.rooms, 0)), f(percentile(total.rooms, 1)),
           f(percentile(total.rooms, 5)), f(percentile(total.rooms, 50)),
           String(format: "%.0f", Date().timeIntervalSince(began))]))
