import PDFKit
import Foundation

// Do the recognised lines survive as SEPARATE lines in the finished PDF?
//
//     score-line-separation <pdf> <label> [headroomFactor] [minimumVertical] [reserveEms]
//
// This is the metric that matches the reported bug: merged runs make a drag
// selection skip a line, and a runaway line makes a whole paragraph come out as
// one string.
//
// ## What this file used to do, and why none of its numbers can be kept
//
// It divided PDFKit **lines** by Vision **fragments**:
//
//     expected += observations.count            // fragments: 1.0–8.5 per visual line
//     extracted += page.string.split("\n").count // lines
//     ratio = 100 * extracted / expected
//
// Those are different populations, so the ratio is not a percentage of anything.
// Measured on the shipped binary: it reads 35%–2533% across the corpus; it read
// **87% → 87%** across a change from no runaway line at all to a 2,139-character
// one; it read 60% → 68% (improving) while the runaway-character share went
// 10.2% → 30.0% (worsening); and `Harpers-1938` reads an identical `161/308 52%`
// at `headroomFactor` 0.95 and 1.5, which is to say it is blind to the constant
// it takes as an argument. On a blank two-page PDF it printed
// `0/0 lines kept separate 0%` — total failure, reported over a document it
// measured nothing on, the same false-green shape from the other side.
//
// `HANDOFF.md`'s "modern print keeps 100%, 1920s-50s 87-93%" came from that
// ratio. Those figures belong to a retired instrument and are not comparable
// with anything this file now prints.
//
// ## What it does instead
//
// Group the reference fragments back into **visual lines** — using
// `SearchableWriter.isSameVisualLine`, the app's own predicate, not a second
// definition of it (C20's shape is two functions disagreeing about one idea) —
// and then ask the two questions the property is actually made of:
//
//  - **merged**: of the adjacent visual-line pairs sharing a column, how many did
//    PDFKit put into ONE extracted line? Zero is perfect. This is the drag
//    selection skipping a line, counted directly.
//  - **runaway**: what share of the extracted characters sit in lines longer than
//    the longest visual line the reference found *on that page*? An extracted line
//    longer than any single visual line on the sheet is, by construction, more
//    than one line welded together.
//
// Neither number needs a calibrated constant, which is deliberate: this file is
// being rewritten precisely because an unvalidated instrument was trusted, and
// shipping a fresh magic number inside that fix would be the same defect again.
// The runaway threshold is *derived* from the page's own typography. `longest`
// and `longestVisual` are printed raw beside it so the reader can see the
// derivation rather than take it on trust.
//
// A line is only judged when it can be identified in the extracted text by a
// token that occurs there exactly once — otherwise a "hit" cannot say *which*
// line was found. Unidentifiable lines are counted and printed as `skipped`, not
// quietly dropped.
//
// The self-test at the bottom runs on **every invocation** and exits 4 if it
// fails, the pattern `score-threshold-loss.swift` established. It includes the
// old defect as a pinned case: three side-by-side fragments per visual line, all
// five lines extracted correctly, where the retired ratio reads 5/15 = 33%.

// MARK: - The measurement, as a pure function the self-test can drive

struct VisualLine {
    let text: String
    let baseline: CGFloat      // in the page box's own space, y up
    let left, right: Double    // normalised, for the same-column test
    /// The fragments this line was folded from, left to right. Kept because
    /// property (d) — a run keeping a gap from the next fragment ON ITS OWN LINE
    /// — is a question about adjacent fragments, and the joined `text` has
    /// already answered it by putting a space there.
    var fragments: [String] = []
}

struct Separation {
    var visualLines = 0
    var mergedPairs = 0, judgedPairs = 0, skippedPairs = 0
    var runawayChars = 0, totalChars = 0
    var longestExtracted = 0, longestVisual = 0
}

/// A token identifying `text` inside `haystack`, or nil when none is unique.
///
/// Uniqueness is the whole point. `probe-text-offset`'s recorded artifact was an
/// anchor that was not unique — `the` alone accounted for 33 of 87 outliers — so
/// a hit told you a line had been found, not which one.
func anchor(for text: String, in haystack: String) -> String? {
    let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .map(String.init)
        .filter { $0.count >= 4 }
        .sorted { $0.count > $1.count }
    for w in words.prefix(8) {
        var hits = 0
        var from = haystack.startIndex
        while let r = haystack.range(of: w, range: from..<haystack.endIndex) {
            hits += 1
            from = r.upperBound
            if hits > 1 { break }
        }
        if hits == 1 { return w }
    }
    return nil
}

func score(visual: [VisualLine], extracted: [String]) -> Separation {
    var s = Separation()
    s.visualLines = visual.count
    s.totalChars = extracted.reduce(0) { $0 + $1.count }
    s.longestExtracted = extracted.map(\.count).max() ?? 0
    s.longestVisual = visual.map(\.text.count).max() ?? 0

    // An extracted line longer than the longest visual line on this page holds
    // more than one of them. Derived from the page, not chosen.
    if s.longestVisual > 0 {
        s.runawayChars = extracted.filter { $0.count > s.longestVisual }
            .reduce(0) { $0 + $1.count }
    }

    let page = extracted.joined(separator: "\n")
    let home: [Int?] = visual.map { line in
        guard let a = anchor(for: line.text, in: page) else { return nil }
        let hits = extracted.indices.filter { extracted[$0].contains(a) }
        return hits.count == 1 ? hits[0] : nil
    }

    // Top to bottom. `baseline` is in PDF space, so descending is downward.
    let order = visual.indices.sorted { visual[$0].baseline > visual[$1].baseline }
    for k in 0..<max(order.count - 1, 0) {
        let i = order[k], j = order[k + 1]
        let a = visual[i], b = visual[j]
        // Only lines sharing a column can be "the next line down". Two columns
        // side by side are correctly separated by a line break, and counting
        // them would measure the page's layout rather than the text layer —
        // A1.1's verification found 7 of 13 adjudicable weld cases were exactly
        // this, where refusing is the right answer.
        guard min(a.right, b.right) - max(a.left, b.left) > 0.02 else { continue }
        guard let hi = home[i], let hj = home[j] else { s.skippedPairs += 1; continue }
        s.judgedPairs += 1
        if hi == hj { s.mergedPairs += 1 }
    }

    return s
}

/// Property (d): adjacent fragments of ONE visual line that arrive with no
/// separator between them — `femalemember`.
///
/// Its own grouping, at its own scale, and that is the whole point. `score`
/// groups at `.shorter` because `merged` asks which *rows* ran together, and
/// every figure this file has published uses that grouping. A weld is a
/// question about two fragments of one row, and `SearchableWriter.rightLimit`
/// — the only thing that can open a gap between them — asks at `.taller`
/// (`BUGS.md` R82). Counting welds over the `.shorter` grouping makes this blind
/// to exactly the pairs R82 is about: measured, `___ 3.pdf` reported 0 welds
/// from that grouping while the extracted text of the same run held four.
func welds(in lines: [VisualLine], extracted: [String]) -> (welded: Int, pairs: Int) {
    let page = extracted.joined(separator: "\n")
    var welded = 0, pairs = 0
    for line in lines where line.fragments.count > 1 {
        for k in 0..<(line.fragments.count - 1) {
            let left = line.fragments[k].trimmingCharacters(in: .whitespacesAndNewlines)
            let right = line.fragments[k + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard left.count >= 3, right.count >= 3 else { continue }
            pairs += 1
            // The tail of one and the head of the other, searched in the whole
            // page rather than in the line the reference expected: a weld is
            // exactly the case where the pair did not land where it was put.
            if page.contains(String(left.suffix(6)) + String(right.prefix(6))) { welded += 1 }
        }
    }
    return (welded, pairs)
}

// MARK: - Self-test, on every invocation

func selfTest() {
    func fail(_ what: String, _ detail: String) -> Never {
        FileHandle.standardError.write(Data("SELF-TEST FAILED: \(what) — \(detail)\n".utf8))
        exit(4)
    }
    func line(_ text: String, at y: CGFloat, left: Double = 0.1, right: Double = 0.9)
        -> VisualLine {
        VisualLine(text: text, baseline: y, left: left, right: right)
    }
    let texts = ["Alpha quantities differ", "Bravo measurable outcomes",
                 "Charlie transverse motion", "Delta obligatory reading",
                 "Echo sustained argument"]
    let visual = texts.enumerated().map { line($1, at: CGFloat(700 - $0 * 12)) }

    // 1. Five lines out as five lines: nothing merged.
    let healthy = score(visual: visual, extracted: texts)
    guard healthy.judgedPairs == 4, healthy.mergedPairs == 0 else {
        fail("five separate lines merge nothing",
             "merged \(healthy.mergedPairs)/\(healthy.judgedPairs)")
    }

    // 2. The same five as ONE line: everything merged. The strict inequality is
    //    the direction proof — an instrument that cannot move is the defect this
    //    file is being rewritten for.
    let welded = score(visual: visual, extracted: [texts.joined(separator: " ")])
    guard welded.mergedPairs == 4, welded.mergedPairs > healthy.mergedPairs else {
        fail("welding five lines into one is detected",
             "merged \(welded.mergedPairs)/\(welded.judgedPairs) "
             + "vs healthy \(healthy.mergedPairs)")
    }

    // 3. A runaway line is seen, and the healthy case reports none.
    guard healthy.runawayChars == 0 else {
        fail("a healthy page has no runaway characters", "\(healthy.runawayChars)")
    }
    let runaway = String(repeating: "x", count: 2139)
    let withRunaway = score(visual: visual, extracted: texts + [runaway])
    guard withRunaway.runawayChars == 2139, withRunaway.longestExtracted == 2139 else {
        fail("a 2,139-character line is counted as runaway",
             "runaway \(withRunaway.runawayChars), longest \(withRunaway.longestExtracted)")
    }

    // 4. THE RETIRED DEFECT, pinned. Vision splits each visual line into three
    //    side-by-side fragments; the output is correct — five extracted lines.
    //    The old ratio read 5/15 = 33% and called that a failure. The grouping
    //    must put 15 fragments back into 5 visual lines, and the metric must read
    //    zero merged.
    let box = CGRect(x: 0, y: 0, width: 612, height: 792)
    var fragments: [SearchableWriter.Observation] = []
    for (row, text) in texts.enumerated() {
        let parts = text.split(separator: " ").map(String.init)
        for (column, part) in parts.enumerated() {
            fragments.append(SearchableWriter.Observation(
                boundingBox: SearchableWriter.BoundingBox(
                    x: 0.10 + Double(column) * 0.22,
                    y: 0.10 + Double(row) * 0.03,
                    width: 0.20, height: 0.016),
                text: part, confidence: 1.0))
        }
    }
    let grouped = visualLines(from: fragments, in: box)
    guard grouped.count == texts.count else {
        fail("side-by-side fragments group back into visual lines",
             "\(fragments.count) fragments became \(grouped.count) lines, wanted \(texts.count)")
    }
    let fromFragments = score(visual: grouped, extracted: texts)
    guard fromFragments.mergedPairs == 0, fromFragments.judgedPairs == 4 else {
        fail("a correct page built from fragments reports nothing merged",
             "merged \(fromFragments.mergedPairs)/\(fromFragments.judgedPairs)")
    }

    // 4b. PROPERTY (d), the one this file could not see until R82. Two fragments
    //     of one visual line, and the question is whether the extracted text put
    //     anything at all between them. Both directions, because a counter that
    //     only ever reports zero is the shape T12 fixed twice.
    let pair = VisualLine(text: "valuable study of it", baseline: 700,
                          left: 0.1, right: 0.9,
                          fragments: ["valuable", "study of it"])
    let spaced = welds(in: [pair], extracted: ["valuable study of it"])
    guard spaced.pairs == 1, spaced.welded == 0 else {
        fail("a spaced pair of fragments is not a weld",
             "welded \(spaced.welded)/\(spaced.pairs)")
    }
    let stuck = welds(in: [pair], extracted: ["valuablestudy of it"])
    guard stuck.welded == 1, stuck.pairs == 1 else {
        fail("`valuablestudy` is counted as a weld",
             "welded \(stuck.welded)/\(stuck.pairs)")
    }
    // A one-fragment line has no pair to weld, and must not invent one.
    let single = welds(in: [line("a whole line in one fragment", at: 700)],
                       extracted: ["a whole line in one fragment"])
    guard single.pairs == 0, single.welded == 0 else {
        fail("a line of one fragment offers no pair",
             "welded \(single.welded)/\(single.pairs)")
    }
    // The two scales really do group differently, or the weld count is being
    // taken over the same rows as `merged` and this file is blind again.
    let sheet = CGRect(x: 0, y: 0, width: 612, height: 792)
    func frag(_ t: String, x: Double, w: Double, y: Double, h: Double)
        -> SearchableWriter.Observation {
        SearchableWriter.Observation(
            boundingBox: SearchableWriter.BoundingBox(x: x, y: y, width: w, height: h),
            text: t, confidence: 1.0)
    }
    // R82's own fixture: `the female` / `member or ine known criminals`.
    let unequal = [frag("the female", x: 0.038793, w: 0.047414, y: 0.347384, h: 0.007279),
                   frag("member or ine", x: 0.086207, w: 0.181034, y: 0.348837, h: 0.002907)]
    guard visualLines(from: unequal, in: sheet, scale: .shorter).count == 2,
          visualLines(from: unequal, in: sheet, scale: .taller).count == 1 else {
        fail("the two scales group a real unequal-height pair differently",
             "shorter \(visualLines(from: unequal, in: sheet, scale: .shorter).count), "
             + "taller \(visualLines(from: unequal, in: sheet, scale: .taller).count)")
    }

    // 5. Degenerate: nothing to judge is nothing to judge, and the caller refuses.
    let empty = score(visual: [], extracted: [])
    guard empty.judgedPairs == 0, empty.visualLines == 0 else {
        fail("an empty page judges nothing", "\(empty)")
    }
}

/// Fold fragments into visual lines with the app's own predicate.
///
/// `SearchableWriter.isSameVisualLine` rather than a local approximation: the
/// writer and the instrument must not be able to disagree about what a visual
/// line is, or they are measuring different things and only one of them knows.
func visualLines(from observations: [SearchableWriter.Observation],
                 in box: CGRect,
                 scale: SearchableWriter.Scale = .shorter) -> [VisualLine] {
    let sorted = observations.sorted {
        SearchableWriter.drawnBaseline($0, in: box) > SearchableWriter.drawnBaseline($1, in: box)
    }
    // Against the CLOSEST open line, not the most recent one. Fragments of one
    // visual line do not share a baseline exactly — a fragment with a descender
    // sits about 0.78 x the height difference below one without, which is the band
    // C20 exists for — so sorting by baseline interleaves a fragment of the next
    // row between two of this row's. "Fold into the last line" would then start a
    // new line mid-row and count a merge that never happened.
    var lines: [[SearchableWriter.Observation]] = []
    for o in sorted {
        let here = SearchableWriter.drawnBaseline(o, in: box)
        var best: (index: Int, distance: CGFloat)?
        for (i, line) in lines.enumerated() {
            guard let rep = line.first,
                  SearchableWriter.isSameVisualLine(rep, o, in: box, scale) else { continue }
            let d = abs(SearchableWriter.drawnBaseline(rep, in: box) - here)
            if best == nil || d < best!.distance { best = (i, d) }
        }
        if let best { lines[best.index].append(o) } else { lines.append([o]) }
    }
    return lines.map { group in
        let ordered = group.sorted { $0.boundingBox.x < $1.boundingBox.x }
        return VisualLine(
            text: ordered.map(\.text).joined(separator: " "),
            baseline: SearchableWriter.drawnBaseline(ordered[0], in: box),
            left: ordered.map(\.boundingBox.x).min() ?? 0,
            right: ordered.map { $0.boundingBox.x + $0.boundingBox.width }.max() ?? 0,
            fragments: ordered.map(\.text))
    }
}

selfTest()

// MARK: - Running one document through the shipped pipeline

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write(Data("""
        usage: score-line-separation <pdf> <label> [headroomFactor] [minimumVertical] [reserveEms]

        The self-test above has passed. See CLAUDE.md invariant 3 for the procedure.

        """.utf8))
    exit(2)
}
let src = URL(fileURLWithPath: CommandLine.arguments[1])
let label = CommandLine.arguments[2]
let work = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ln-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }
Prefs.register(migrate: false); UserDefaults.standard.set(false, forKey: Prefs.openWhenDone)
if CommandLine.arguments.count > 3,
   let f = Double(CommandLine.arguments[3]) { SearchableWriter.headroomFactor = CGFloat(f) }
if CommandLine.arguments.count > 4,
   let v = Double(CommandLine.arguments[4]) { SearchableWriter.minimumVertical = CGFloat(v) }
if CommandLine.arguments.count > 5,
   let g = Double(CommandLine.arguments[5]) { SearchableWriter.reserveEms = CGFloat(g) }

func refuse(_ why: String) -> Never {
    print("\(label)\tSKIP\t\(why.replacingOccurrences(of: "\t", with: " "))")
    exit(1)
}

guard let doc = PDFDocument(url: src), doc.pageCount > 0 else { refuse("cannot open source") }
let idx = doc.pageCount <= 3 ? Array(0..<doc.pageCount) : [1, doc.pageCount/2, doc.pageCount*3/4]
let s = PDFDocument()
for i in idx { if let p = doc.page(at: i) { s.insert(p, at: s.pageCount) } }
let input = work.appendingPathComponent("in.pdf")
guard s.write(to: input) else { refuse("cannot write sample") }
let out = work.appendingPathComponent("out.pdf")
var outcome = "?", message = ""
OCRModel.makeSearchablePDF(file: input, output: out, rebuild: true,
    rebuildMode: .auto, password: nil, control: RunControl(), progress: { _, _ in },
    report: { o, m in outcome = "\(o)"; message = m })
guard outcome == "succeeded" else { refuse("pipeline \(outcome): \(message)") }
guard let res = PDFDocument(url: out) else { refuse("output unreadable") }

// Independent reference recognition of the finished file, through the same
// in-process path the app uses. This used to shell out to mac-ocr; the
// dependency is gone and `Recogniser` is the reference now.
guard let byPage = try? Recogniser.recogniseDocument(visible: out, bitmaps: [],
                                                     settings: .current())
else { refuse("reference recognition failed") }

var total = Separation()
// Property (d), counted for the first time by a committed instrument, and kept
// beside `total` rather than inside it: `score` does not compute these — `welds`
// does, over its own grouping — and a field on `Separation` that one of its two
// producers never sets is a confident zero waiting for the next reader.
var weldedTotal = 0, fragmentPairTotal = 0
for (number, observations) in byPage.sorted(by: { $0.key < $1.key }) {
    guard let page = res.page(at: number - 1) else { continue }
    let box = page.bounds(for: .mediaBox)
    let usable = observations.filter {
        !$0.text.trimmingCharacters(in: .whitespaces).isEmpty
    }
    let visual = visualLines(from: usable, in: box)
    // The reserve's own scale, for the weld count only — see `welds`.
    let rows = visualLines(from: usable, in: box, scale: .taller)
    let extracted = (page.string ?? "").components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    let one = score(visual: visual, extracted: extracted)
    let (welded, fragmentPairs) = welds(in: rows, extracted: extracted)
    total.visualLines += one.visualLines
    total.mergedPairs += one.mergedPairs
    total.judgedPairs += one.judgedPairs
    total.skippedPairs += one.skippedPairs
    total.runawayChars += one.runawayChars
    total.totalChars += one.totalChars
    weldedTotal += welded
    fragmentPairTotal += fragmentPairs
    total.longestExtracted = max(total.longestExtracted, one.longestExtracted)
    total.longestVisual = max(total.longestVisual, one.longestVisual)
}

// A6.1 (d), in this file's own form: printing `0/0 … 0%` over a document nothing
// was measured on is a verdict without a measurement. Refuse instead, and say
// which population was empty.
guard total.judgedPairs > 0 else {
    refuse("nothing judged: \(total.visualLines) visual line(s), "
           + "\(total.skippedPairs) pair(s) with no unique anchor")
}
print(String(format: "%@\tOK\tvisual=%d\tmerged=%d/%d (%.1f%%)\twelded=%d/%d\tskipped=%d\t"
                   + "runaway=%.1f%%\tlongest=%d\tlongestVisual=%d\tratio=%.1fx",
             label, total.visualLines, total.mergedPairs, total.judgedPairs,
             100 * Double(total.mergedPairs) / Double(total.judgedPairs),
             weldedTotal, fragmentPairTotal,
             total.skippedPairs,
             100 * Double(total.runawayChars) / Double(max(total.totalChars, 1)),
             total.longestExtracted, total.longestVisual,
             Double(total.longestExtracted) / Double(max(total.longestVisual, 1))))
