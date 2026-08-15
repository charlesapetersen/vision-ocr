import PDFKit
import Foundation
// For each line on ONE page, slide a thin probe vertically until it returns that
// line's own first word. The winning offset tells us how far our run sits from
// its box.
//
//     probe-text-offset <pdf> <page> <observations.json>
//
// Build the JSON with Tools/make-observations.swift.
//
// Two defects were fixed here, and the second one moved the number this tool
// exists to report:
//
// 1. A12.8 — it read `pages[0].observations` whatever page it was given, so on
//    page 2 of a real document it printed `no lines matched` while that page held
//    34 measurable lines. Blind on every page but the first.
//
// 2. A6.1 recorded the printed *range* as ~1.7% artifact and called the median
//    sound. **The median was not sound.** The scan ran `stride(from: -1.2,
//    through: 1.2)` and took the FIRST hit, so it started a line-height and a
//    fifth BELOW the box and accepted the lowest step whose window still clipped
//    this line's own glyphs — a systematic downward bias needing no neighbouring
//    line to explain it, on top of the recorded lock-on to a common word on the
//    row below. Measured, changing nothing but the scan order: Friedman_1962 p2,
//    34 lines, median −0.10 → 0.00; Williams_1958 p1, 83 lines, median −0.10 →
//    0.00. So the fix scans OUTWARD FROM ZERO — the nearest plausible position
//    wins rather than the lowest — and every `off=` figure recorded before this
//    commit belongs to the old instrument.
//
// A6.1 blames the lock-on on the anchor rather than the scan — a first word that
// repeats on the page (`the` alone accounted for 33 of 87 outliers) cannot say
// *which* line a probe found. That reading was tested and it is wrong, or at
// least redundant: refusing every line whose first word repeats, on top of the
// outward scan, changes **nothing**. Measured over four pages and 161 candidate
// lines, gate on versus gate off —
//
//     dense newsprint p1   27/124 vs 83/124 located   median 0.00 both, p5..p95 0.00..0.10 both
//     magazine p1           6/25  vs  9/25            median 0.00 both, range 0.00..0.00 both
//     magazine p2           1/3   vs  2/3             median 0.00 both
//     journal title p1      4/9   vs  6/9             median 0.00 both
//
// — identical medians, identical spreads, and the gate throws away between a
// third and two thirds of the sample. Scanning outward is the whole fix: a line's
// own glyphs are found at |step| ≈ 0 long before any neighbour a whole line-height
// away, so the anchor never gets the chance to be ambiguous. The count is still
// computed and printed, because it is the exposure a future reader would want if
// the median ever moves — but it does not gate the measurement. Shipping a rule
// that only shrinks the sample would be the same overreach this file is fixing.
struct Box: Decodable { let x, y, width, height: Double }
struct Obs: Decodable { let boundingBox: Box; let text: String }
struct Pg: Decodable { let page: Int; let observations: [Obs] }

guard CommandLine.arguments.count >= 4 else {
    FileHandle.standardError.write(Data(
        "usage: probe-text-offset <pdf> <page> <observations.json>\n".utf8))
    exit(2)
}
let pdf = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let pageNumber = Int(CommandLine.arguments[2])!
let pages = try JSONDecoder().decode([Pg].self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
guard let page = pdf.page(at: pageNumber - 1) else {
    FileHandle.standardError.write(Data(
        "  page \(pageNumber) is not in this PDF (\(pdf.pageCount) pages)\n".utf8))
    exit(1)
}
guard let reference = pages.first(where: { $0.page == pageNumber }) else {
    FileHandle.standardError.write(Data("""
      the observation JSON has no page \(pageNumber) \
    (it holds \(pages.map { String($0.page) }.joined(separator: ", ")))

    """.utf8))
    exit(1)
}
let b = page.bounds(for: .mediaBox)
let whole = page.string ?? ""

/// How many times `needle` occurs in the page's extracted text. One means the
/// probe hitting it has identified this line and no other.
func occurrences(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var from = haystack.startIndex
    while let r = haystack.range(of: needle, range: from..<haystack.endIndex) {
        count += 1
        from = r.upperBound
        if count > 1 { break }
    }
    return count
}

// Nearest first. On a tie the upward step wins, because the glyphs sit *above*
// the box bottom by `baselineFraction` — so if 0.0 misses, +0.1 is the physically
// likelier home than −0.1.
let steps = stride(from: -1.2, through: 1.2, by: 0.1)
    .map { ($0 * 10).rounded() / 10 }
    .sorted { (abs($0), -$0) < (abs($1), -$1) }

var offsets: [Double] = []
var considered = 0, ambiguous = 0, unplaced = 0
for o in reference.observations where o.text.count > 15 {
    let w = o.boundingBox.width * b.width, h = o.boundingBox.height * b.height
    let x = b.minX + o.boundingBox.x * b.width
    let boxBottom = b.maxY - o.boundingBox.y * b.height - h
    let firstWord = String(o.text.split(separator: " ").first ?? "").prefix(6)
    guard firstWord.count >= 3 else { continue }
    considered += 1
    if occurrences(of: String(firstWord), in: whole) != 1 { ambiguous += 1 }
    var best: Double?
    for step in steps {
        let r = CGRect(x: x, y: boxBottom + h * step, width: w * 0.2, height: h * 0.5)
        let s = page.selection(for: r)?.string ?? ""
        if s.contains(firstWord) { best = step; break }
    }
    if let best { offsets.append(best) } else { unplaced += 1 }
}
guard !offsets.isEmpty else {
    print("  page \(pageNumber): NOTHING LOCATED — \(considered) line(s) considered, "
          + "\(unplaced) not found. No median is reported, because a run that located "
          + "nothing is not a measurement.")
    exit(1)
}
offsets.sort()
func percentile(_ p: Double) -> Double {
    offsets[min(offsets.count - 1, max(0, Int((Double(offsets.count) - 1) * p + 0.5)))]
}
print(String(format: """
  page %d: %d of %d lines located; offset as a fraction of line height: \
median %.2f, p5..p95 %.2f...%.2f, range %.2f...%.2f
""", pageNumber, offsets.count, considered, percentile(0.5),
   percentile(0.05), percentile(0.95), offsets.first!, offsets.last!))
print("  (0.00 would mean our glyphs sit exactly on the box bottom; \(unplaced) not found; "
      + "\(ambiguous) of \(considered) had a first word that repeats on the page — measured "
      + "anyway, and gating on it was shown to change nothing)")
