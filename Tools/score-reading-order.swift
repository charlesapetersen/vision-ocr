// Is Vision's reading order actually wrong on multi-column pages?
//
//   score-reading-order [--pages N] [--verbose] <pdf>...
//
// **Nothing should be built for columns before this says something.**
// `FEATURES.md` item 3 asserts that copying a two-column page produces
// interleaved nonsense. Half of that claim is now verified by reading the code —
// `SearchableWriter.compose` draws observations in the order Vision returned
// them and never sorts, so reading order really is inherited whole. The other
// half, that the order is *wrong*, has never been measured on this corpus.
//
// This project has built a feature for an inferred weakness before. "Vision
// can't read sideways text" was concluded from a blank rebuild that turned out
// to be an off-canvas rendering bug, a whole feature was written for it, and a
// direct test then showed Vision reads all four orientations perfectly. The
// feature was deleted. Deskew went the same way, refused by its own numbers.
//
// **The metric needs no ground truth**, which is what makes it worth trusting:
//
//  - **Column bands** come from a coverage histogram of the observations' own
//    x-intervals. A gutter is a run of page width that no observation crosses.
//  - **Switches** counts how often consecutive observations, *in Vision's
//    returned order*, fall in different bands. A correctly ordered two-column
//    page switches exactly once, at the column break. An interleaved one
//    switches on nearly every line.
//  - **Interleaving** is switches ÷ (bands − 1). 1.0 is perfect. 20 means the
//    page is being read straight across the gutter.
//  - **Inversions** counts consecutive same-band pairs where the later
//    observation sits *above* the earlier one — order going backwards within a
//    single column, which no amount of column detection would excuse.
//
// Pages that are not multi-column are counted and reported separately rather
// than dropped: a sweep that silently keeps only the pages it understands is how
// the corpus came to be 65% material this app is not for (D1).
import Foundation
import PDFKit
import CoreGraphics

setvbuf(stdout, nil, _IOLBF, 0)

var pages = 3
var verbose = false
var gutter = false
var files: [String] = []
var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
    case "--pages": pages = Int(arguments.removeFirst()) ?? 3
    case "--verbose": verbose = true
    case "--gutter": gutter = true
    default: files.append(argument)
    }
}
guard !files.isEmpty else {
    fputs("usage: score-reading-order [--pages N] [--verbose] <pdf>...\n", stderr)
    exit(2)
}

/// A gutter has to be this wide, as a fraction of the page, to separate columns.
/// Wide enough that the space between words or a hanging indent is not a gutter.
let minimumGutter = 0.035
/// A band needs this many observations before it is a column rather than a
/// marginal note or a page number.
let minimumBandLines = 4
/// Ignore observations narrower than this — page numbers, stray marks.
let minimumWidth = 0.01

struct Band { let low: Double, high: Double }

/// Column bands, from the x-intervals the observations themselves occupy.
func bands(of observations: [SearchableWriter.Observation]) -> [Band] {
    let bins = 200
    var covered = [Bool](repeating: false, count: bins)
    for o in observations where o.boundingBox.width >= minimumWidth {
        let from = max(0, min(bins - 1, Int(o.boundingBox.x * Double(bins))))
        let to = max(0, min(bins - 1, Int((o.boundingBox.x + o.boundingBox.width) * Double(bins))))
        for i in from...to { covered[i] = true }
    }
    var out: [Band] = []
    var start: Int? = nil
    var gap = 0
    for i in 0..<bins {
        if covered[i] {
            if gap > 0, let s = start, Double(gap) / Double(bins) >= minimumGutter {
                out.append(Band(low: Double(s) / Double(bins),
                                high: Double(i - gap) / Double(bins)))
                start = i
            } else if start == nil {
                start = i
            }
            gap = 0
        } else if start != nil {
            gap += 1
        }
    }
    if let s = start {
        out.append(Band(low: Double(s) / Double(bins), high: 1.0))
    }
    return out
}

/// Which band an observation's centre falls in, or nil.
func band(of o: SearchableWriter.Observation, in bands: [Band]) -> Int? {
    let centre = o.boundingBox.x + o.boundingBox.width / 2
    for (i, b) in bands.enumerated() where centre >= b.low && centre <= b.high { return i }
    return nil
}

func samplePages(_ document: PDFDocument) -> [Int] {
    let count = document.pageCount
    guard count > 0 else { return [] }
    if count <= pages { return Array(0..<count) }
    return (0..<pages).map { 1 + $0 * (count - 2) / max(pages - 1, 1) }
        .map { min(max($0, 0), count - 1) }
}

// The shipped defaults, asked for rather than transcribed. This was a
// hand-written `Prefs.Snapshot(...)` literal, and it stopped compiling the moment
// the struct grew `preserveAnnotations` in `9684c3f` — so **this tool has not
// built since 2026-08-14**, verified by type-checking it at `9684c3f~1` where it
// does. C25's shape, found by `Tools/check-tools-compile.sh`, which exists because
// of C25. Every field `Recogniser.recognise` reads is identical either way:
// `fast` false, `languageCorrection` true, no languages, no custom words, no
// minimum height, confidence 0.
Prefs.register(migrate: false)
let settings = Prefs.Snapshot.current()

if gutter {
    // **Ground truth from the pixels, not from Vision's grouping.**
    //
    // The metric above has a hole, and it is the shape of hole this project
    // keeps falling into. Bands are derived from where the *observations* sit —
    // so if Vision reads straight across a gutter, its observations span both
    // columns, the coverage histogram has no gap, and the page is filed as
    // single-column. The one defect worth finding would be excluded from the
    // sample by the act of looking for it.
    //
    // So the layout is detected from the ink instead: a vertical strip of the
    // rendered page that almost no ink crosses is a gutter, whatever Vision
    // thinks. Then the question becomes direct and unmissable — **how many of
    // Vision's observations cross a gutter that is physically there?** A line
    // that spans two columns is text read across the page, and no reordering can
    // repair it because the two halves are already welded into one string.
    print("file\tpage\tgutters\tlines\tcrossing\tshare")
    var physicallyMulti = 0, singleColumn = 0
    var crossingTotal = 0, linesTotal = 0
    var worstPages: [(String, Int, Double)] = []
    for path in files {
        guard let document = Flattener.open(URL(fileURLWithPath: path), password: nil)
        else { continue }
        let name = (path as NSString).lastPathComponent
        for index in samplePages(document) {
            guard let page = document.page(at: index) else { continue }
            let box = Flattener.displayBox(of: page)
            let scale = 150.0 / 72.0
            let wide = (box.width * scale).rounded(), high = (box.height * scale).rounded()
            guard wide.isFinite, high.isFinite, wide >= 64, high >= 64,
                  wide * high <= Double(Flattener.maximumPageMegapixels) * 1_000_000,
                  let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                                  width: Int(wide), height: Int(high),
                                                  from: .cropBox)
            else { continue }
            let w = Int(wide), h = Int(high)
            let threshold = Flattener.otsuThreshold(of: grey)
            var ink = [Int](repeating: 0, count: w)
            for y in 0..<h {
                let row = y * w
                for x in 0..<w where grey[row + x] <= threshold { ink[x] += 1 }
            }
            guard let peak = ink.max(), peak > 0 else { continue }

            // A gutter: a run of columns almost no ink crosses, wide enough to
            // be a gutter rather than a word space, and away from the margins so
            // the blank edge of the sheet is not mistaken for one.
            let quiet = max(1, peak / 100)
            let minimumRun = Int(0.035 * Double(w))
            let margin = Int(0.12 * Double(w))
            var gutters: [(low: Int, high: Int)] = []
            var run = 0
            for x in 0..<w {
                if ink[x] <= quiet { run += 1 } else {
                    if run >= minimumRun {
                        let low = x - run, high = x
                        if low > margin && high < w - margin { gutters.append((low, high)) }
                    }
                    run = 0
                }
            }
            guard !gutters.isEmpty else {
                singleColumn += 1
                continue
            }
            physicallyMulti += 1

            guard let image = Recogniser.render(page, settings: settings),
                  let observations = try? Recogniser.recognise(image, settings: settings),
                  !observations.isEmpty
            else { continue }
            var crossing = 0
            for o in observations {
                let left = o.boundingBox.x * Double(w)
                let right = (o.boundingBox.x + o.boundingBox.width) * Double(w)
                // Crosses a gutter if it starts left of one and ends right of it.
                if gutters.contains(where: { left < Double($0.low) && right > Double($0.high) }) {
                    crossing += 1
                }
            }
            crossingTotal += crossing
            linesTotal += observations.count
            let share = Double(crossing) / Double(observations.count)
            worstPages.append((name, index + 1, share))
            print(String(format: "%@\t%d\t%d\t%d\t%d\t%.1f%%", name, index + 1,
                         gutters.count, observations.count, crossing, 100 * share))
        }
    }
    print("\n=== does Vision read across a physical gutter? ===")
    print("  pages with a real gutter   \(physicallyMulti)")
    print("  pages without one          \(singleColumn)")
    if linesTotal > 0 {
        print(String(format: "  observations crossing one  %d of %d (%.2f%%)",
                     crossingTotal, linesTotal,
                     100.0 * Double(crossingTotal) / Double(linesTotal)))
    }
    for (name, page, share) in worstPages.sorted(by: { $0.2 > $1.2 }).prefix(8) {
        print(String(format: "  worst: %@ p%d  %.1f%%", name, page, 100 * share))
    }
    print("""

  A share near zero means Vision keeps each column to itself, and the only
  question left is the order it returns them in — which the default mode
  measures. A large share means lines are being welded across the gutter, which
  reordering cannot fix and which is a much bigger piece of work.
""")
    exit(0)
}

if verbose { print("file\tpage\tbands\tlines\tswitches\tinterleaving\tinversions") }

var multiColumnPages = 0, singleColumnPages = 0, unreadable = 0
var interleavings: [Double] = []
var inversionsTotal = 0, multiColumnLines = 0
var worst: (name: String, page: Int, ratio: Double)? = nil

for path in files {
    guard let document = Flattener.open(URL(fileURLWithPath: path), password: nil) else {
        unreadable += 1
        continue
    }
    let name = (path as NSString).lastPathComponent
    for index in samplePages(document) {
        guard let page = document.page(at: index),
              let image = Recogniser.render(page, settings: settings),
              let observations = try? Recogniser.recognise(image, settings: settings),
              observations.count >= 8
        else { unreadable += 1; continue }

        let columns = bands(of: observations)
        // A band only counts as a column if enough lines live in it.
        let populated = columns.indices.filter { i in
            observations.filter { band(of: $0, in: columns) == i }.count >= minimumBandLines
        }
        guard populated.count >= 2 else {
            singleColumnPages += 1
            if verbose {
                print("\(name)\t\(index + 1)\t1\t\(observations.count)\t—\t—\t—")
            }
            continue
        }

        multiColumnPages += 1
        multiColumnLines += observations.count
        var switches = 0, inversions = 0
        var previous: (band: Int, y: Double)? = nil
        for o in observations {
            guard let b = band(of: o, in: columns), populated.contains(b) else { continue }
            if let p = previous {
                if p.band != b { switches += 1 }
                // Same column, and the next line is higher up the page.
                else if o.boundingBox.y < p.y - 0.005 { inversions += 1 }
            }
            previous = (b, o.boundingBox.y)
        }
        let ideal = max(populated.count - 1, 1)
        let ratio = Double(switches) / Double(ideal)
        interleavings.append(ratio)
        inversionsTotal += inversions
        if worst == nil || ratio > worst!.ratio { worst = (name, index + 1, ratio) }
        if verbose {
            print(String(format: "%@\t%d\t%d\t%d\t%d\t%.1f\t%d",
                         name, index + 1, populated.count, observations.count,
                         switches, ratio, inversions))
        }
    }
}

let sorted = interleavings.sorted()
print("\n=== reading order ===")
print("  multi-column pages   \(multiColumnPages)")
print("  single-column pages  \(singleColumnPages)")
print("  unreadable/too short \(unreadable)")
guard !sorted.isEmpty else {
    print("\n  No multi-column pages found. Either the sample is wrong or this")
    print("  corpus does not have the problem — check before concluding either.")
    exit(0)
}
print(String(format: "  interleaving: median %.1f   p95 %.1f   worst %.1f  (1.0 = perfect)",
             sorted[sorted.count / 2],
             sorted[min(sorted.count * 95 / 100, sorted.count - 1)], sorted.last!))
let clean = sorted.filter { $0 <= 1.5 }.count
print(String(format: "  pages already in reading order: %d of %d (%.1f%%)",
             clean, sorted.count, 100.0 * Double(clean) / Double(sorted.count)))
print("  inversions within a column: \(inversionsTotal) over \(multiColumnLines) lines")
if let worst { print("  worst page: \(worst.name) p\(worst.page) at \(String(format: "%.1f", worst.ratio))") }
print("""

  How to read this. A median near 1.0 means Vision already returns multi-column
  pages in reading order and item 3 should be declined on measurement, exactly as
  deskew was. A median well above 1.0 means the pages are being read across the
  gutter and a reading-order sort is worth building — but check `worst` by eye
  first, because a table and a two-column page look identical to this metric and
  only one of them wants reordering.
""")
