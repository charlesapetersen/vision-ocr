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
//
//   score-reading-order [--pages N] [--verbose] <pdf>...   reading order
//   score-reading-order --gutter <pdf>...                  ink test + Vision
//   score-reading-order --census [--pages-from <tsv>] <pdf>...   ink test only
//   score-reading-order --self-test
//
// ## `INKFLOOR`, and the band the 0.19% never counted
//
// `gutter-floor`'s sub-step 2. The ink test's floor is `inkGutterFloor` = 3.5% of
// the page width, and a page whose widest quiet run falls short of it has no
// gutter, is counted `singleColumn` and is `continue`d — **out of both halves of
// `FEATURES.md`'s 0.19% before one observation is read**. The census counted that
// class, and the count depends on which key you ask with: over this tool's own 641
// pages, **33** carry a gutter at 0.02 that the shipped floor refuses against
// **60** it counts, while by exact fraction the 2.0-3.5% band is **29** against 59
// at or above. ⛔ Never pair a fraction-derived count with a gutter-test one — the
// printed 4-dp column gives a third answer, 28, and the difference is one real
// page.
//
// `INKFLOOR=<fraction>` substitutes the floor for the run only, so one sweep at
// 0.02 counts both classes, and every row carries the band it belongs to plus
// crossing counted **against that band's own gutters**:
//
//   band          `wide` if the page carries a gutter the SHIPPED floor would
//                 have found, else `narrow`. ⛔ NOT `widestFrac >=
//                 inkGutterFloor`: `minimumRun` truncates, so the two differ on a
//                 real corpus page and the fraction version undercounted the wide
//                 band by one. See `wideBandPage` and self-test group 8.
//   crossWide     observations spanning a qualifying gutter at least
//                 `inkGutterFloor * width` wide.
//   crossNarrow   observations spanning one narrower than that.
//   share         ⛔ the band's OWN crossing share — `crossWide / lines` on a wide
//                 page and `crossNarrow / lines` on a narrow one. The six-column
//                 version printed `crossing / lines` under this same name, so a
//                 row of an older run does not mean what a row of this one does.
//                 The `worst` list is sorted on it and therefore changed with it.
//   widestFrac    the widest interior quiet run with NO floor applied — the same
//                 quantity `GUTTER-SAMPLED-2026-08-26.tsv`'s
//                 `widest_interior_quiet_frac` holds, so the two files are
//                 comparable column to column. ⚠️ It is printed to 4 dp, which is
//                 not enough to re-derive `band` from it.
//
// ⛔ **Why crossing is split by the GUTTER and not only by the page.** Lowering
// the floor ADDS narrow gutters to a wide-band page's list, so that page's
// `crossing` at 0.02 is not what it was at 0.035 and a single column cannot be
// compared with the published figure. `crossWide` can: a wide-band page's wide
// gutters are exactly the gutters the shipped floor would have found, so
// `crossWide` summed over the wide band **is** the 0.035 answer, and the narrow
// band's own number is `crossNarrow` over the narrow band. Both come out of one
// run; the alternative was two runs whose page sets are disjoint by band.
//
// ⚠️ The band boundary is the SHIPPED constant and the counting floor is the
// override, which is why the two are separate values. `INKFLOOR` is refused
// outside (0, 0.5), refused ABOVE the shipped floor (which would drop pages the
// wide band is defined to hold), and refused in the default mode, whose bands come
// from the observations and never call the ink test — but ALLOWED with
// `--self-test`, because setting it and running one is the only way to show from
// the command line that it moves no assertion. ⚠️ `--census` DOES honour it
// and its TSV has no floor column, so a lowered-floor census is indistinguishable
// from a shipped-floor one in the file — the floor is on stderr only. `--gutter` is
// inferable, because a shipped-floor run has `narrowGutters` 0 on every row.
//
// ## `--census`, and the 43-against-59 gap it exists to close
//
// `FEATURES.md` item 3 says *"over 638 corpus pages, 59 with a real gutter"* from
// a `--gutter` run, and its reopen note says a poppler+Python mirror of the same
// ink test scored **43** over 644 pages — a gap nobody could work, because the
// mirror's output was committed (`GUTTER-CENSUS-2026-08-20.tsv`) and this tool's
// per-page output was not: `--gutter` prints a row only for a page it calls
// multi-column, so a page the two runs disagree about is invisible in exactly the
// direction that matters.
//
// So `--census` prints a row for **every sampled page** — the census file's own
// four column names, so `cut -f1-4` compares them directly — and skips Vision
// entirely, because the disagreement is about the ink test and recognising 644
// pages to measure a threshold on pixels is a cost with no answer in it.
// `--pages-from <tsv>` then takes the pages to score from column 2 of that same
// file, keyed on the basename in column 1, which is what holds page selection
// fixed while the two implementations are compared. Without it the shipped
// `samplePages` choice applies, which is the control that re-derives the 59.
//
// ⚠️ **The two knobs answer different questions and mixing them proves nothing.**
// `--pages-from` compares the ink tests. Default sampling compares the sampling.
// The recorded gap is not one number's worth of drift; page selection alone can
// account for a gap of this size, because `samplePages` takes page 2, the middle
// and **the last page** while the census took quarter, half and three-quarter
// depth (`floor(count * k / 4)`, verified against its own rows on 232 of its 233
// documents). Pin: `samplePages(count: 69, take: 3)` is `[1, 34, 68]` 0-based —
// 1-based 2, 35, 69 — against the census's 17, 34, 51 on the same document.
// Self-test group 6.
//
// The ink test is now ONE function, `gutters(inGrey:width:height:floor:)`,
// called by
// `--gutter` and `--census` both. It was inline in the `--gutter` branch, and a
// census mode that carried its own copy would be measuring a replica of the
// instrument it is trying to check — `alltext-replica`'s mistake, which this
// project has now paid for three times.
//
// Exit codes: 0 ok · 2 usage, **including a malformed `INKFLOOR`** · 3 it measured
// no pages (the silent-success defect `score-corpus` and `score-threshold-loss`
// both had — refused by `--census` and, since sub-step 2, by `--gutter` as well) ·
// **4 a `--pages-from` row named a page this run never scored** — a document that
// has moved or a page past the end would otherwise make a short run look like
// agreement · 5 a failed self-test · 6 a `--gutter` row whose field count does not
// match its header. ⚠️ **6 is UNREACHABLE from the command line** — the only
// caller passes a literal array, so it fires on an edit rather than on input, and
// nothing watches it fail. It is here because counting tab escapes by eye has put
// the wrong field count under a header three times in this repo (T14, A12.3, T18)
// and this mode went from six columns to twelve in one diff.
//
// The self-test runs on **every** invocation, which is the majority
// pattern here (`score-text-route:476-478`: "cheap enough to be unconditional")
// and matters more than usual for this file, because the pre-commit hook runs
// `--self-test` for staged `Tools/*.py` only.
import Foundation
import PDFKit
import CoreGraphics

setvbuf(stdout, nil, _IOLBF, 0)

var pages = 3
var verbose = false
var gutter = false
var census = false
var pagesFrom: String? = nil
var selfTestOnly = false
var files: [String] = []
var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
    case "--pages": pages = arguments.isEmpty ? 3 : (Int(arguments.removeFirst()) ?? 3)
    case "--verbose": verbose = true
    case "--gutter": gutter = true
    case "--census": census = true
    case "--pages-from": pagesFrom = arguments.isEmpty ? nil : arguments.removeFirst()
    case "--self-test": selfTestOnly = true
    default: files.append(argument)
    }
}

/// A gutter has to be this wide, as a fraction of the page, to separate columns.
/// Wide enough that the space between words or a hanging indent is not a gutter.
/// ⚠️ This one gates the gap in the OBSERVATIONS' x-coverage, in `bands`.
let minimumGutter = 0.035
/// The same fraction, of the same page width, but on a different quantity: a run
/// of rendered PIXEL columns almost no ink crosses. ⛔ **Numerically equal to
/// `minimumGutter` by coincidence, and kept separate deliberately** — a first
/// draft pointed the ink test at `minimumGutter` and called it "two copies of one
/// constant", which would have made sub-step 2's *"lower the floor to 0.02"*
/// silently move every `switches`/`interleaving`/`inversions` figure the default
/// mode prints. The review of that diff caught it.
let inkGutterFloor = 0.035
/// The floor this RUN counts against: `INKFLOOR` if it is set and legal, else the
/// shipped constant. ⛔ Two values rather than one mutable constant, deliberately.
/// `inkGutterFloor` stays the shipped 3.5% because it is what the `wide`/`narrow`
/// band boundary means, and because `gutters(...)`'s floor parameter defaults to
/// it — so the self-test, which never passes the parameter, cannot be moved by an
/// environment variable. That is `samplePages`' `take` lesson in a second place:
/// a knob read from the global inside a function the self-test also calls makes
/// `INKFLOOR=0.02` red a check about 3.5% and refuse to measure anything.
let runFloor: Double = {
    guard let raw = ProcessInfo.processInfo.environment["INKFLOOR"] else {
        return inkGutterFloor
    }
    guard let value = Double(raw), value > 0, value < 0.5 else {
        fputs("score-reading-order: INKFLOOR=\(raw) is not a fraction in (0, 0.5)\n",
              stderr)
        exit(2)
    }
    // ⛔ ABOVE the shipped floor is refused, not clamped. `band` and `isWide` are
    // defined at `inkGutterFloor`, so a higher run floor drops pages that DO have
    // a gutter the shipped floor counts: `crossWide` over the wide band would
    // silently stop being the shipped floor's answer, and `narrowGutters` would be
    // empty on every row while the summary still printed a narrow band. Found by
    // the adversarial review of this diff, which had the header claiming the
    // identity unconditionally.
    guard value <= inkGutterFloor else {
        fputs("score-reading-order: INKFLOOR=\(raw) is above the shipped floor "
              + "\(inkGutterFloor); the band split is defined there, so a higher "
              + "floor would drop pages the wide band is supposed to hold\n", stderr)
        exit(2)
    }
    // Read and then quietly ignored is what this file refuses for `--pages-from`
    // and `--census --gutter`, and the default reading-order mode never calls
    // `inkTest` at all — its bands come from the observations. Same rule.
    // ⚠️ `selfTestOnly` is ALLOWED through, and it is not a courtesy: the only
    // way to demonstrate from the command line that `INKFLOOR` cannot move a
    // self-test assertion is to set it and run one. A first version of this guard
    // refused it and turned that demonstration into an exit 2.
    guard gutter || census || selfTestOnly else {
        fputs("score-reading-order: INKFLOOR applies to --gutter and --census; "
              + "the default mode's bands come from the observations, not the "
              + "ink\n", stderr)
        exit(2)
    }
    return value
}()
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

/// Which pages of a document of this length get sampled, 0-based.
///
/// Separated from the document so the self-test can pin the arithmetic: this
/// function is half of `FEATURES.md`'s 43-against-59 gap, and nothing had ever
/// asserted what it returns. Note the shape — page 2, then evenly to **the last
/// page**, which is not the same population as "three interior pages".
/// ⛔ `take` is a PARAMETER and not the global `pages` on purpose: the self-test
/// pins this arithmetic and runs on every invocation, so reading the global would
/// make `--pages 4` red a check about `--pages 3` and refuse to measure anything.
/// The review of this diff found exactly that.
func samplePages(count: Int, take: Int) -> [Int] {
    guard count > 0 else { return [] }
    if count <= take { return Array(0..<count) }
    return (0..<take).map { 1 + $0 * (count - 2) / max(take - 1, 1) }
        .map { min(max($0, 0), count - 1) }
}

func samplePages(_ document: PDFDocument) -> [Int] {
    samplePages(count: document.pageCount, take: pages)
}

/// Wanted pages by document basename, 1-based, from a TSV whose first column is
/// a file name and whose second is a page number. Any row whose second column is
/// not a positive integer is skipped, which is how the header line is skipped
/// without naming it.
func parsePageList(_ lines: [String]) -> [String: Set<Int>] {
    var out: [String: Set<Int>] = [:]
    for line in lines {
        let fields = line.components(separatedBy: "\t")
        guard fields.count >= 2, let page = Int(fields[1]), page > 0 else { continue }
        out[fields[0], default: []].insert(page)
    }
    return out
}

/// The ink test's answer for one page.
struct Gutters {
    /// The Otsu threshold this page's ink was counted against, and the tallest
    /// column of ink. Printed because they are how a disagreement with another
    /// implementation of this test gets attributed to something: `Flattener`'s
    /// Otsu clamps to `[90, 230]` and a reference implementation's may not, and
    /// `quiet` is `peak / 100`.
    let otsu: UInt8
    let peak: Int
    /// Interior quiet runs at or above the floor: the gutters the shipped test
    /// counts. `[low, high)` in pixel columns.
    let qualifying: [(low: Int, high: Int)]
    /// The widest interior quiet run in pixels **with the floor not applied**, 0
    /// when there is none. This is `GUTTER-CENSUS-2026-08-20.tsv`'s
    /// `widest_interior_quiet_frac` column, and printing it is what makes a
    /// lowered floor derivable from a finished run rather than needing another.
    let widestInterior: Int
    /// Where that widest run is, `[low, high)` in pixel columns, or nil. Printed
    /// because a sub-threshold band is no use to the crossing question unless
    /// something says where on the page to look for observations spanning it.
    let widestSpan: (low: Int, high: Int)?
    /// The pixel dimensions the ink was actually counted over. ⛔ `height` is
    /// carried rather than re-derived at the print site: the first draft printed
    /// `Int(displayBox.height * 150 / 72)`, which TRUNCATES where the render
    /// `.rounded()`s, and disagreed with the rendered height on 40 of 100 sampled
    /// rows (`w5093` p48: 1639 printed against 1640 rendered). The review of this
    /// diff caught it in a committed artefact.
    let width: Int
    let height: Int
    var widestFraction: Double { width > 0 ? Double(widestInterior) / Double(width) : 0 }
}

/// Is a qualifying gutter wide enough that the SHIPPED floor would have counted
/// it? One implementation, two callers — the `--gutter` branch and the self-test —
/// and the same expression `gutters` uses for `minimumRun`, integer truncation
/// included, so a gutter is `wide` exactly when a default-floor run would have
/// found it at all.
func isWide(_ gutter: (low: Int, high: Int), width w: Int) -> Bool {
    (gutter.high - gutter.low) >= Int(inkGutterFloor * Double(w))
}

/// The ink test, over a rendered grey page. **One implementation, two callers** —
/// see the header. Nil means the page carried no ink at all.
///
/// ⛔ `floor` is a PARAMETER defaulting to the shipped constant, not a read of
/// `runFloor`. The self-test calls this twelve times without it and twice with an
/// explicit floor, so `INKFLOOR=0.02` moves what a RUN counts and cannot move what
/// the self-test asserts. ⚠️ **The blind spot in that design**: if `isWide` or this
/// default were changed to read `runFloor`, the two globals are EQUAL when
/// `INKFLOOR` is unset, so no clause would move and a bare `--self-test` would stay
/// green. Nothing here asserts the invariance itself — the self-test cannot see the
/// environment — so it is watched only by running the knob.
func gutters(inGrey grey: [UInt8], width w: Int, height h: Int,
             floor: Double = inkGutterFloor) -> Gutters? {
    guard w > 0, h > 0, grey.count >= w * h else { return nil }
    let threshold = Flattener.otsuThreshold(of: grey)
    var ink = [Int](repeating: 0, count: w)
    for y in 0..<h {
        let row = y * w
        for x in 0..<w where grey[row + x] <= threshold { ink[x] += 1 }
    }
    guard let peak = ink.max(), peak > 0 else { return nil }

    // A gutter: a run of columns almost no ink crosses, wide enough to be a
    // gutter rather than a word space, and away from the margins so the blank
    // edge of the sheet is not mistaken for one.
    let quiet = max(1, peak / 100)
    let minimumRun = Int(floor * Double(w))
    let margin = Int(0.12 * Double(w))
    var qualifying: [(low: Int, high: Int)] = []
    var widest = 0
    var widestSpan: (low: Int, high: Int)? = nil
    var run = 0
    for x in 0..<w {
        if ink[x] <= quiet { run += 1 } else {
            // ⚠️ A run reaching the last column is never flushed — there is no
            // inked column left to flush it — and that cannot cost a gutter,
            // for TWO independent reasons: the flush never happens, and such a
            // run would fail `high < w - margin` anyway for every width whose
            // margin is at least one pixel (every page, the render guard
            // refusing under 64 px). ⛔ The flush is the operative one, measured
            // rather than reasoned: cutting interiority out of this condition
            // leaves the self-test's blank-to-the-edge case green and reds only
            // the case whose last column is inked. A first draft of this comment
            // gave the interiority reason alone.
            let low = x - run, high = x
            if run > 0 && low > margin && high < w - margin {
                if run > widest { widest = run; widestSpan = (low, high) }
                if run >= minimumRun { qualifying.append((low, high)) }
            }
            run = 0
        }
    }
    return Gutters(otsu: threshold, peak: peak, qualifying: qualifying,
                   widestInterior: widest, widestSpan: widestSpan,
                   width: w, height: h)
}

/// Render a page grey at 150 DPI and run the ink test on it. Nil means the page
/// could not be rendered or carried no ink — counted, never dropped silently.
/// ⛔ This is the ONE place `runFloor` reaches the ink test, and both measuring
/// modes go through it, so nothing else has to remember to pass it.
func inkTest(_ page: PDFPage) -> Gutters? {
    let box = Flattener.displayBox(of: page)
    let scale = 150.0 / 72.0
    let wide = (box.width * scale).rounded(), high = (box.height * scale).rounded()
    guard wide.isFinite, high.isFinite, wide >= 64, high >= 64,
          wide * high <= Double(Flattener.maximumPageMegapixels) * 1_000_000,
          let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                          width: Int(wide), height: Int(high),
                                          from: .cropBox)
    else { return nil }
    return gutters(inGrey: grey, width: Int(wide), height: Int(high), floor: runFloor)
}

/// Everything here is arithmetic on synthetic pixels, so it is unconditional.
func selfTest() -> [String] {
    var bad: [String] = []
    let w = 1000, h = 40

    /// A page of full-height ink columns, `gap` left blank. Ink is 0, paper 255,
    /// which puts Otsu inside its shipped `[90, 230]` clamp either way.
    func fixture(blank: Range<Int>, speck: Int? = nil) -> [UInt8] {
        var grey = [UInt8](repeating: 255, count: w * h)
        for y in 0..<(h / 2) {
            for x in 0..<w where !blank.contains(x) { grey[y * w + x] = 0 }
        }
        if let speck { grey[speck] = 0 }
        return grey
    }

    // 1. A 6% interior gap is a gutter, and its bounds and width are exact.
    if let g = gutters(inGrey: fixture(blank: 400..<460), width: w, height: h) {
        if g.qualifying.count != 1 || g.qualifying.first?.low != 400
            || g.qualifying.first?.high != 460 {
            bad.append("6% gap: \(g.qualifying) not one gutter at [400, 460)")
        }
        if g.widestInterior != 60 || abs(g.widestFraction - 0.06) > 1e-9 {
            bad.append("6% gap: widest \(g.widestInterior) px / \(g.widestFraction)")
        }
        if g.widestSpan?.low != 400 || g.widestSpan?.high != 460 {
            bad.append("6% gap: widest span \(String(describing: g.widestSpan))")
        }
    } else { bad.append("6% gap: the ink test found no ink") }

    // 2. ⛔ THE CENSUS'S WHOLE SUB-THRESHOLD CLASS AS A CHECK. A 2.5% gap is
    //    refused as a gutter and is still REPORTED as the widest interior quiet
    //    run — so the sub-threshold pages `FEATURES.md` calls a blind spot are
    //    refused by the floor and not missed by the detector, and a lowered floor
    //    is derivable from a finished census without a second run. ⚠️ Do not put a
    //    count in this comment: it has read 27 (the census's 644 pages by printed
    //    fraction), and the same class is 29 by exact fraction and 33 by the
    //    gutter test over this tool's own 641.
    if let g = gutters(inGrey: fixture(blank: 400..<425), width: w, height: h) {
        if !g.qualifying.isEmpty {
            bad.append("2.5% gap: \(g.qualifying.count) gutters, expected none")
        }
        // ⚠️ The fraction is in the detail string because it is half the condition:
        // a sabotage dividing `widestFraction` by the height reddened this clause
        // with a message reading "widest 25 px, expected 25", which names the half
        // that was right. Its sibling six lines up already printed both.
        if g.widestInterior != 25 || abs(g.widestFraction - 0.025) > 1e-9 {
            bad.append("2.5% gap: widest \(g.widestInterior) px / "
                       + "\(g.widestFraction), expected 25 and 0.025")
        }
        // Sub-step 2 needs to know WHERE the band a lowered floor would count is.
        if g.widestSpan?.low != 400 || g.widestSpan?.high != 425 {
            bad.append("2.5% gap: widest span \(String(describing: g.widestSpan))")
        }
    } else { bad.append("2.5% gap: the ink test found no ink") }

    // 3. A wide gap inside the 12% margin is neither a gutter nor a widest run —
    //    interiority gates BOTH columns, so `widest` can never report a margin.
    // ⚠️ Not also asserting `widestSpan == nil` here: `widest` and `widestSpan`
    // are assigned together under `run > widest`, which `run == 0` cannot enter,
    // so `widest == 0` ⟺ `widestSpan == nil` and the second clause would restate
    // the first. The review of this diff caught it as such.
    if let g = gutters(inGrey: fixture(blank: 20..<110), width: w, height: h) {
        if !g.qualifying.isEmpty || g.widestInterior != 0 {
            bad.append("margin gap: \(g.qualifying.count) gutters, widest "
                       + "\(g.widestInterior), expected 0 and 0")
        }
    } else { bad.append("margin gap: the ink test found no ink") }

    // 4a. A quiet run that reaches the right margin is not a gutter however
    //     wide, and here the LAST column is inked, so the run is flushed and
    //     interiority is what refuses it. This is the case a sabotage can red.
    if let g = gutters(inGrey: fixture(blank: 500..<(w - 1)), width: w, height: h) {
        if !g.qualifying.isEmpty || g.widestInterior != 0 {
            bad.append("edge gap: \(g.qualifying.count) gutters, widest "
                       + "\(g.widestInterior), expected 0 and 0")
        }
    } else { bad.append("edge gap: the ink test found no ink") }

    // 4b. Blank all the way to the last column: the never-flushed run named in
    //     `gutters`. ⚠️ Refused TWICE OVER, so no one-token change to that
    //     condition can red this row — cutting interiority out leaves it green,
    //     measured. It is a pin on documented behaviour rather than a watched
    //     red, and it is here because the day someone adds a trailing flush the
    //     interiority test is all that stands between a blank right-hand third
    //     of a sheet and a "gutter".
    if let g = gutters(inGrey: fixture(blank: 500..<w), width: w, height: h) {
        if !g.qualifying.isEmpty || g.widestInterior != 0 {
            bad.append("trailing gap: \(g.qualifying.count) gutters, widest "
                       + "\(g.widestInterior), expected 0 and 0")
        }
    } else { bad.append("trailing gap: the ink test found no ink") }

    // 5. `quiet = max(1, peak / 100)` is a tolerance, not a demand for white: one
    //    speck of ink in the gutter does not close it, and a full column does.
    let specked = fixture(blank: 400..<460, speck: 5 * w + 430)
    if let g = gutters(inGrey: specked, width: w, height: h) {
        if g.qualifying.count != 1 {
            bad.append("specked gutter: \(g.qualifying.count) gutters, expected 1")
        }
    } else {
        // Without this `else` the whole clause goes green whenever the ink test
        // returns nil, while its six siblings red — the review of this diff
        // found it as the one case here written without one.
        bad.append("specked gutter: the ink test found no ink")
    }
    var closed = fixture(blank: 400..<460)
    for y in 0..<(h / 2) { closed[y * w + 430] = 0 }
    if let g = gutters(inGrey: closed, width: w, height: h) {
        if g.qualifying.count != 0 || g.widestInterior != 30 {
            bad.append("closed gutter: \(g.qualifying.count) gutters, widest "
                       + "\(g.widestInterior), expected 0 and 30")
        }
    } else { bad.append("closed gutter: the ink test found no ink") }

    // 5b. The tolerance itself, not just its floor. Every fixture above is 40
    //     rows deep, so `peak` is 20 and `quiet` is `max(1, 0)` — the FLOOR, and
    //     `peak / 100` could be any divisor without a red. At 400 rows `peak` is
    //     200 and `quiet` is 2, so a 2-pixel column is still quiet and a 3-pixel
    //     one is ink that splits the gutter into two sub-floor halves. The review
    //     of this diff found the divisor unpinned.
    let tall = 400
    func deepFixture(specks: Int) -> [UInt8] {
        var grey = [UInt8](repeating: 255, count: w * tall)
        for y in 0..<(tall / 2) {
            for x in 0..<w where !(400..<460).contains(x) { grey[y * w + x] = 0 }
        }
        for i in 0..<specks { grey[i * w + 430] = 0 }
        return grey
    }
    if let g = gutters(inGrey: deepFixture(specks: 2), width: w, height: tall) {
        if g.peak != 200 || g.qualifying.count != 1 {
            bad.append("2-px speck at quiet=2: peak \(g.peak), "
                       + "\(g.qualifying.count) gutters, expected 200 and 1")
        }
    } else { bad.append("2-px speck: the ink test found no ink") }
    if let g = gutters(inGrey: deepFixture(specks: 3), width: w, height: tall) {
        if !g.qualifying.isEmpty || g.widestInterior != 30 {
            bad.append("3-px speck at quiet=2: \(g.qualifying.count) gutters, "
                       + "widest \(g.widestInterior), expected 0 and 30")
        }
    } else { bad.append("3-px speck: the ink test found no ink") }

    // 6. ⛔ HALF OF THE 43-AGAINST-59 GAP. `samplePages` takes page 2, the
    //    middle and THE LAST PAGE — 1-based 2, 35, 69 on a 69-page document,
    //    against the census's 17, 34, 51 on the same one. Two page sets, not one
    //    disagreement, and this is the assertion that says so.
    let sampled = samplePages(count: 69, take: 3)
    if sampled != [1, 34, 68] {
        bad.append("samplePages(69): \(sampled) not [1, 34, 68]")
    }
    // A document SHORTER than the sample takes every page. ⚠️ Count 2 rather
    // than count 3, because deleting the `count <= take` branch still returns
    // every page at count 3 and would leave this green — at count 2 the general
    // formula returns [1, 1, 1] instead. Count 0 was asserted here and is worse
    // still: it is `[]` with or without its own guard.
    if samplePages(count: 2, take: 3) != [0, 1] {
        bad.append("samplePages(2): \(samplePages(count: 2, take: 3)) not every page")
    }
    if samplePages(count: 3, take: 3) != [0, 1, 2] {
        bad.append("samplePages(3): \(samplePages(count: 3, take: 3)) not every page")
    }
    // The global `pages` must not reach that arithmetic, or `--pages 4` reds a
    // check about `--pages 3` and the tool refuses to measure anything.
    if samplePages(count: 69, take: 4) != [1, 23, 45, 68] {
        bad.append("samplePages(69, take: 4): \(samplePages(count: 69, take: 4))")
    }

    // 7. `--pages-from` parsing: the header skipped by its unparseable page
    //    number rather than by position, tabs, and a repeated page collapsed.
    let parsed = parsePageList(["file\tpage\tqualifying_gutters",
                                "a.pdf\t17\t0", "a.pdf\t34\t1", "a.pdf\t17\t0",
                                "b b.pdf\t2\t0", "c.pdf\tnot a page\t0"])
    if parsed["a.pdf"] != [17, 34] || parsed["b b.pdf"] != [2]
        || parsed["c.pdf"] != nil || parsed["file"] != nil || parsed.count != 2 {
        bad.append("parsePageList: \(parsed.mapValues { $0.sorted() })")
    }

    // 8. ⛔ THE LOWERED FLOOR, AND THE BAND SPLIT IT MAKES NECESSARY.
    //    `INKFLOOR` is the knob sub-step 2 runs on, and a knob wired to nothing
    //    is the shape this project has shipped: the pair below is two-sided, so
    //    a `floor` parameter that stopped reaching `minimumRun` reds here.
    if let g = gutters(inGrey: fixture(blank: 400..<425), width: w, height: h,
                       floor: 0.02) {
        if g.qualifying.count != 1 || g.qualifying.first?.low != 400
            || g.qualifying.first?.high != 425 {
            bad.append("2.5% gap at floor 0.02: \(g.qualifying) not one at [400, 425)")
        }
    } else { bad.append("2.5% gap at floor 0.02: the ink test found no ink") }
    // The same fixture at the shipped floor, so the row above is a difference the
    // knob makes and not a property of the fixture. (Group 2 asserts this too, on
    // the census's behalf; here it is the negative control of a pair.)
    if let g = gutters(inGrey: fixture(blank: 400..<425), width: w, height: h),
       !g.qualifying.isEmpty {
        bad.append("2.5% gap at the shipped floor: \(g.qualifying.count) gutters")
    }

    // ⛔ A page can be in the WIDE band and still carry a narrow gutter, which is
    //    why crossing is counted per gutter and not per page: lowering the floor
    //    adds the 25-px run to this page's list, so its `crossing` at 0.02 is not
    //    what it was at 0.035 while its `crossWide` is.
    var twoGaps = [UInt8](repeating: 255, count: w * h)
    for y in 0..<(h / 2) {
        for x in 0..<w where !(400..<425).contains(x) && !(600..<660).contains(x) {
            twoGaps[y * w + x] = 0
        }
    }
    if let g = gutters(inGrey: twoGaps, width: w, height: h, floor: 0.02) {
        let widths = g.qualifying.map { $0.high - $0.low }
        let wide = g.qualifying.map { isWide($0, width: w) }
        if widths != [25, 60] || wide != [false, true] {
            bad.append("two gaps at floor 0.02: widths \(widths), wide \(wide), "
                       + "expected [25, 60] and [false, true]")
        }
        // The widest run with NO floor applied, which is
        // `GUTTER-SAMPLED-2026-08-26.tsv`'s column, so the two files' band
        // populations mean the same thing. ⚠️ The FRACTION is pinned exactly and
        // not as `>= inkGutterFloor`: the inequality was the first version and it
        // is 0.06 against 0.035, which nothing plausible falsifies — a width/height
        // swap in `widestFraction` would read 1.5 and pass it. 0.06 catches that.
        if g.widestInterior != 60 || abs(g.widestFraction - 0.06) > 1e-9 {
            bad.append("two gaps: widest \(g.widestInterior) px / "
                       + "\(g.widestFraction), expected 60 and 0.06")
        }
    } else { bad.append("two gaps at floor 0.02: the ink test found no ink") }
    // At the shipped floor the same page carries the wide gutter ALONE — which is
    // what makes `crossWide` over the wide band the shipped floor's own answer.
    if let g = gutters(inGrey: twoGaps, width: w, height: h) {
        if g.qualifying.map({ $0.high - $0.low }) != [60]
            || g.qualifying.map({ isWide($0, width: w) }) != [true] {
            bad.append("two gaps at the shipped floor: \(g.qualifying)")
        }
    } else { bad.append("two gaps at the shipped floor: the ink test found no ink") }

    // ⛔ THE BOUNDARY THAT SEPARATES THE TWO CANDIDATE BAND KEYS, and it is a real
    //    corpus page rather than a hypothetical: `NAYLOR_Arthur E.pdf` p134 is a
    //    45-px quiet run on a 1286-px page. `minimumRun` TRUNCATES, so
    //    `Int(0.035 * 1286)` = 45 accepts it and the shipped floor counts the
    //    page, while 45/1286 = 0.034992 is below 0.035 and a fraction test calls
    //    it narrow. The band key is the gutter test, not the fraction — this is
    //    the clause that says so, and it was found by reconciling a finished run
    //    against `GUTTER-SAMPLED-2026-08-26.tsv` and coming up one page short.
    let odd = 1286
    var boundary = [UInt8](repeating: 255, count: odd * h)
    for y in 0..<(h / 2) {
        for x in 0..<odd where !(1049..<1094).contains(x) { boundary[y * odd + x] = 0 }
    }
    if let g = gutters(inGrey: boundary, width: odd, height: h) {
        if g.qualifying.map({ $0.high - $0.low }) != [45] {
            bad.append("45 px of 1286 at the shipped floor: \(g.qualifying), "
                       + "expected one run of 45")
        }
        if g.qualifying.map({ isWide($0, width: odd) }) != [true] {
            bad.append("45 px of 1286: isWide false, so the shipped floor would "
                       + "not have counted a page it does count")
        }
        if !(g.widestFraction < inkGutterFloor) {
            bad.append("45 px of 1286: widestFraction \(g.widestFraction) is not "
                       + "below \(inkGutterFloor) — the two band keys no longer "
                       + "disagree and this clause has stopped testing anything")
        }
    } else { bad.append("45 px of 1286: the ink test found no ink") }

    // ⛔ THE TRUNCATION ITSELF, which the clause above does NOT pin: 0.035 x 1286
    //    is 45.01, so `Int()` and `.rounded()` both give 45 and a change from one
    //    to the other is invisible there. 0.035 x 1300 is 45.5, where truncation
    //    accepts a 45-px run and rounding refuses it. The adversarial review of
    //    this diff found that hole — the fixture was on the >=/> boundary and in
    //    the MIDDLE of the truncate/round band.
    let odd2 = 1300
    var trunc = [UInt8](repeating: 255, count: odd2 * h)
    for y in 0..<(h / 2) {
        for x in 0..<odd2 where !(600..<645).contains(x) { trunc[y * odd2 + x] = 0 }
    }
    if let g = gutters(inGrey: trunc, width: odd2, height: h) {
        if g.qualifying.map({ $0.high - $0.low }) != [45]
            || g.qualifying.map({ isWide($0, width: odd2) }) != [true] {
            bad.append("45 px of 1300: \(g.qualifying) / "
                       + "\(g.qualifying.map { isWide($0, width: odd2) }) — "
                       + "Int(0.035 * 1300) = 45 must accept a 45-px run, and a "
                       + "rounding form giving 46 must not")
        }
    } else { bad.append("45 px of 1300: the ink test found no ink") }
    return bad
}

let selfTestFailures = selfTest()
if !selfTestFailures.isEmpty {
    fputs("score-reading-order: self-test FAILED\n  "
          + selfTestFailures.joined(separator: "\n  ") + "\n", stderr)
    exit(5)
}
if selfTestOnly {
    print("score-reading-order: self-test ok (8 groups)")
    exit(0)
}
guard !files.isEmpty else {
    fputs("""
    usage: score-reading-order [--pages N] [--verbose] <pdf>...
           score-reading-order --gutter <pdf>...
           score-reading-order --census [--pages-from <tsv>] <pdf>...
           score-reading-order --self-test

    """, stderr)
    exit(2)
}

// Two knobs that would otherwise be read and then quietly ignored. `--census`
// wins over `--gutter` in the branch order below, and `--pages-from` is only
// consulted by the census branch — so a run that mixes them looks honoured and
// measures something else. Both found by the review of this diff.
if census && gutter {
    fputs("score-reading-order: --census and --gutter are different runs; "
          + "pick one\n", stderr)
    exit(2)
}
if pagesFrom != nil && !census {
    fputs("score-reading-order: --pages-from applies to --census only\n", stderr)
    exit(2)
}

/// The pages of one document to score: whatever `--pages-from` asked for, else
/// the shipped sample.
var requestedPages: [String: Set<Int>]? = nil
if let pagesFrom {
    guard let text = try? String(contentsOfFile: pagesFrom, encoding: .utf8) else {
        fputs("score-reading-order: cannot read \(pagesFrom)\n", stderr)
        exit(2)
    }
    let list = parsePageList(text.components(separatedBy: "\n"))
    guard !list.isEmpty else {
        fputs("score-reading-order: \(pagesFrom) named no pages\n", stderr)
        exit(2)
    }
    requestedPages = list
}

func pageIndices(_ document: PDFDocument, named name: String) -> [Int] {
    guard let requestedPages else { return samplePages(document) }
    guard let wanted = requestedPages[name] else { return [] }
    return wanted.sorted().map { $0 - 1 }.filter { $0 >= 0 && $0 < document.pageCount }
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

if census {
    // The ink test alone, one row per sampled page, Vision never asked. The
    // first four column NAMES are `GUTTER-CENSUS-2026-08-20.tsv`'s so that
    // `cut -f1-4` puts the two implementations side by side; the rest are what a
    // disagreement needs in order to be attributable to something.
    print("file\tpage\tqualifying_gutters\twidest_interior_quiet_frac"
          + "\twidthPx\theightPx\twidestPx\twidestSpan\totsu\tpeakInk\tgutterSpans")
    var scored = 0, noInk = 0, withGutter = 0, unopened = 0, notRequested = 0
    // ⛔ Seeded from the documents actually PASSED, not from every row of the
    // list: seeding from the whole list made `--pages-from <the 233-document
    // census> one.pdf` print a correct one-document TSV and then exit 4 owing
    // 641 pages, so a spot check on one file was impossible. The review of this
    // diff found it. The converse — a document passed but absent from the list —
    // is counted as `notRequested` rather than vanishing.
    var owed: Set<String> = []
    if let requestedPages {
        let passed = Set(files.map { ($0 as NSString).lastPathComponent })
        for (name, wanted) in requestedPages where passed.contains(name) {
            for p in wanted { owed.insert("\(name)\t\(p)") }
        }
    }
    for path in files {
        let name = (path as NSString).lastPathComponent
        guard let document = Flattener.open(URL(fileURLWithPath: path), password: nil)
        else { unopened += 1; continue }
        let wanted = pageIndices(document, named: name)
        if wanted.isEmpty && requestedPages != nil { notRequested += 1 }
        for index in wanted {
            guard let page = document.page(at: index) else { continue }
            guard let ink = inkTest(page) else {
                noInk += 1
                fputs("no ink: \(name) p\(index + 1)\n", stderr)
                continue
            }
            scored += 1
            owed.remove("\(name)\t\(index + 1)")
            if !ink.qualifying.isEmpty { withGutter += 1 }
            let spans = ink.qualifying.map { "\($0.low)-\($0.high)" }.joined(separator: ",")
            let widest = ink.widestSpan.map { "\($0.low)-\($0.high)" } ?? "-"
            print(String(format: "%@\t%d\t%d\t%.4f\t%d\t%d\t%d\t%@\t%d\t%d\t%@",
                         name, index + 1, ink.qualifying.count, ink.widestFraction,
                         ink.width, ink.height,
                         ink.widestInterior, widest, Int(ink.otsu), ink.peak,
                         spans.isEmpty ? "-" : spans))
        }
    }
    // ⛔ The summary goes to STDERR, so the TSV redirected out of this mode is
    // PURE ROWS like every other committed `*.tsv` here — the census file it is
    // meant to be `cut -f1-4`'d against among them. A first draft printed it to
    // stdout and put a prose block inside the artefact.
    fputs("\n=== ink test census ===\n", stderr)
    fputs("  pages scored               \(scored)\n", stderr)
    fputs("  with a qualifying gutter   \(withGutter)\n", stderr)
    fputs("  no ink / would not render  \(noInk)\n", stderr)
    fputs("  documents that would not open \(unopened)\n", stderr)
    fputs("  documents passed but not in the list \(notRequested)\n", stderr)
    fputs("  page selection             "
          + (requestedPages == nil ? "samplePages(\(pages))" : "--pages-from") + "\n", stderr)
    fputs(String(format: "  floor counted against      %.4f%@\n", runFloor,
                 runFloor == inkGutterFloor ? "" : " INKFLOOR"), stderr)
    // Invariant 1's discipline in an instrument: a run that scored fewer pages
    // than it was asked for would otherwise read as agreement with whatever it
    // is being compared against.
    if !owed.isEmpty {
        fputs("score-reading-order: \(owed.count) requested page(s) never scored, "
              + "first: \(owed.sorted().prefix(5).joined(separator: " | ")) — "
              + "the rows above are INCOMPLETE\n", stderr)
        exit(4)
    }
    guard scored > 0 else {
        fputs("score-reading-order: measured no pages\n", stderr)
        exit(3)
    }
    exit(0)
}

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
    // ⛔ One `columns` array and one printer, with the width asserted —
    // CONTRIBUTING's rule for a tool that prints a TSV. Counting tab escapes by
    // eye has put the wrong number of fields under a header three times here
    // (T14, A12.3, T18), and this mode went from six columns to twelve.
    let columns = ["file", "page", "gutters", "wideGutters", "narrowGutters",
                   "widestFrac", "band", "lines", "crossing", "crossWide",
                   "crossNarrow", "share"]
    func row(_ fields: [String]) {
        guard fields.count == columns.count else {
            fputs("score-reading-order: \(fields.count) fields under "
                  + "\(columns.count) columns\n", stderr)
            exit(6)
        }
        print(fields.joined(separator: "\t"))
    }
    print(columns.joined(separator: "\t"))

    /// One band's running totals. `own` is crossing counted against **that band's
    /// own gutters** — see the header: it is the only column comparable across
    /// floors, because lowering the floor adds narrow gutters to a wide page's
    /// list and moves `any`.
    struct Tally { var pages = 0, lines = 0, own = 0, any = 0 }
    var wideBand = Tally(), narrowBand = Tally()
    var physicallyMulti = 0, singleColumn = 0
    // Invariant 1's discipline in an instrument, and the sibling of the census's
    // `owed`: every page this mode declines to measure is counted and named,
    // because a run that quietly skipped half the corpus reads as a low crossing
    // rate. All four of these were bare `continue`s.
    var unopened = 0, noPage = 0, noInk = 0, unrecognised = 0
    var worstPages: [(String, Int, String, Double)] = []
    for path in files {
        let name = (path as NSString).lastPathComponent
        guard let document = Flattener.open(URL(fileURLWithPath: path), password: nil)
        else {
            unopened += 1
            fputs("would not open: \(name)\n", stderr)
            continue
        }
        for index in samplePages(document) {
            guard let page = document.page(at: index) else {
                noPage += 1
                fputs("no page: \(name) p\(index + 1)\n", stderr)
                continue
            }
            guard let ink = inkTest(page) else {
                noInk += 1
                // "or would not render": `inkTest` returns nil for six distinct
                // reasons — a non-finite box, either dimension under 64 px, over
                // `maximumPageMegapixels`, `renderGrey` nil, and `gutters`' own
                // buffer and zero-peak guards — and this counter collapses them.
                // The census branch's label already said so; this one said "no
                // ink", which names one of the six.
                fputs("no ink / would not render: \(name) p\(index + 1)\n", stderr)
                continue
            }
            let w = ink.width
            let gutters = ink.qualifying
            guard !gutters.isEmpty else {
                singleColumn += 1
                continue
            }
            physicallyMulti += 1
            let wideGutters = gutters.filter { isWide($0, width: w) }
            let narrowGutters = gutters.filter { !isWide($0, width: w) }
            // ⛔ The page's band is "does it carry a gutter the SHIPPED floor
            // would have found", not `widestFraction >= inkGutterFloor`. The two
            // are not the same test and the corpus separates them: `minimumRun`
            // truncates, so on `NAYLOR_Arthur E.pdf` p134 a 45-px run of a
            // 1286-px page clears `Int(0.035 * 1286)` = 45 while 45/1286 =
            // 0.034992 is below 0.035. The fraction called that page narrow and
            // the shipped floor counts it — found by reconciling this run's band
            // sets against `GUTTER-SAMPLED-2026-08-26.tsv` and off by one page.
            // This definition is what makes `crossWide` over the wide band the
            // shipped floor's own answer. Self-test group 8.
            let wideBandPage = !wideGutters.isEmpty

            guard let image = Recogniser.render(page, settings: settings),
                  let observations = try? Recogniser.recognise(image, settings: settings),
                  !observations.isEmpty
            else {
                unrecognised += 1
                // The band is named here, not just the page: without it the band
                // page counts do not add up to `pages with a real gutter` and a
                // reader cannot tell which band lost the page.
                // NOT "Vision returned nothing": the first clause of the guard
                // is `Recogniser.render` returning nil, where Vision is never
                // asked at all.
                fputs("no observations (render or recognition): \(name) p\(index + 1) "
                      + "(\(wideBandPage ? "wide" : "narrow") band)\n", stderr)
                continue
            }
            var crossing = 0, crossWide = 0, crossNarrow = 0
            for o in observations {
                let left = o.boundingBox.x * Double(w)
                let right = (o.boundingBox.x + o.boundingBox.width) * Double(w)
                // Crosses a gutter if it starts left of one and ends right of it.
                func spans(_ list: [(low: Int, high: Int)]) -> Bool {
                    list.contains { left < Double($0.low) && right > Double($0.high) }
                }
                if spans(gutters) { crossing += 1 }
                if spans(wideGutters) { crossWide += 1 }
                if spans(narrowGutters) { crossNarrow += 1 }
            }
            let own = wideBandPage ? crossWide : crossNarrow
            var tally = wideBandPage ? wideBand : narrowBand
            tally.pages += 1
            tally.lines += observations.count
            tally.own += own
            tally.any += crossing
            if wideBandPage { wideBand = tally } else { narrowBand = tally }

            let share = Double(own) / Double(observations.count)
            let band = wideBandPage ? "wide" : "narrow"
            worstPages.append((name, index + 1, band, share))
            row([name, "\(index + 1)", "\(gutters.count)", "\(wideGutters.count)",
                 "\(narrowGutters.count)",
                 String(format: "%.4f", ink.widestFraction), band,
                 "\(observations.count)", "\(crossing)", "\(crossWide)",
                 "\(crossNarrow)", String(format: "%.2f%%", 100 * share)])
        }
    }
    // ⛔ To STDERR, so the TSV redirected out of this mode is PURE ROWS like the
    // census's and every other committed `*.tsv` here. It was on stdout with a
    // prose block after it, which is the defect the review of sub-step 1 found in
    // the census branch and fixed there only.
    func report(_ line: String) { fputs(line + "\n", stderr) }
    report("\n=== does Vision read across a physical gutter? ===")
    report(String(format: "  floor counted against      %.4f%@ (shipped %.4f)",
                  runFloor, runFloor == inkGutterFloor ? "" : " INKFLOOR",
                  inkGutterFloor))
    report("  pages with a real gutter   \(physicallyMulti)")
    report("  pages without one          \(singleColumn)")
    report("  documents that would not open \(unopened)")
    report("  pages absent / no ink or render \(noPage) / \(noInk)")
    report("  pages with no observations \(unrecognised)")
    func band(_ name: String, _ t: Tally, _ own: String) {
        report("  --- \(name) ---")
        report("  pages / observations       \(t.pages) / \(t.lines)")
        guard t.lines > 0 else { return }
        report(String(format: "  crossing an OWN (%@) gutter %d of %d (%.2f%%)",
                      own, t.own, t.lines,
                      100.0 * Double(t.own) / Double(t.lines)))
        report(String(format: "  crossing ANY gutter        %d of %d (%.2f%%)",
                      t.any, t.lines, 100.0 * Double(t.any) / Double(t.lines)))
    }
    // ⚠️ Read the OWN line against `FEATURES.md`'s 0.19%, never ANY: at a lowered
    // floor ANY counts gutters the published run never had. The band names are
    // the gutter test, not a fraction comparison — see `wideBandPage`.
    band("wide band: carries a gutter the SHIPPED floor counts", wideBand, "wide")
    band("narrow band: qualifies only at the LOWERED floor", narrowBand, "narrow")
    for (name, page, band, share) in worstPages.sorted(by: { $0.3 > $1.3 }).prefix(8) {
        report(String(format: "  worst: %@ p%d (%@)  %.1f%%", name, page, band,
                      100 * share))
    }
    report("""

  A share near zero means Vision keeps each column to itself, and the only
  question left is the order it returns them in — which the default mode
  measures. A large share means lines are being welded across the gutter, which
  reordering cannot fix and which is a much bigger piece of work.
""")
    // The silent-success defect `score-corpus` and `score-threshold-loss` both
    // had, and which the census branch already refuses. ⚠️ Narrower than the
    // census's, which keys on ROWS PRINTED: this keys on pages the ink test
    // reached, so an all-single-column corpus, or one whose every gutter page
    // fails recognition, still exits 0 over a header-only TSV. Those cases are
    // visible in the counters above rather than in the status.
    guard physicallyMulti + singleColumn > 0 else {
        fputs("score-reading-order: measured no pages\n", stderr)
        exit(3)
    }
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
