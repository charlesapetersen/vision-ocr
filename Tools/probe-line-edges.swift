import PDFKit
import Foundation
// For each recognised line on ONE page: is its first word selectable, its last
// word, and which lines fail?
//
//     probe-line-edges <pdf> <page> <observations.json>
//
// Build the JSON with Tools/make-observations.swift.
//
// NOT an independent fourth instrument, whatever CLAUDE.md used to say. Its rect
// arithmetic is character-identical to `score-corpus`'s own `start=`/`end=`
// columns, and on page 1 the two agree on 48 of 48 documents. Keep it for the one
// thing `score-corpus` cannot do — **naming** the lines that fail, so a drop from
// 100% to 91% is a list of lines rather than a number to go hunting for. Writing a
// second, genuinely-independent definition of "the end of the line is selectable"
// is C20's shape, and this project has paid for that twice.
//
// A6.1 + A12.8: it used to read `pages[0].observations` whatever page it was
// asked for, so on page 2 of a real document it probed page 1's observations
// against page 2's geometry and printed `line starts: 1/1  line ends: 1/1` over a
// page holding 40 lines. That is not redundancy, it is a T12 false green — a 40x
// under-measurement wearing a clean 100%. Hence the page match below, and hence
// the refusal: a run that judged nothing must not print a percentage.
struct Box: Decodable { let x, y, width, height: Double }
struct Obs: Decodable { let boundingBox: Box; let text: String }
struct Pg: Decodable { let page: Int; let observations: [Obs] }

guard CommandLine.arguments.count >= 4 else {
    FileHandle.standardError.write(Data(
        "usage: probe-line-edges <pdf> <page> <observations.json>\n".utf8))
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
// The observations' own `page` field, not their index: the producer numbers from
// 1 and a caller may hand over a JSON covering a subset of the document.
guard let reference = pages.first(where: { $0.page == pageNumber }) else {
    FileHandle.standardError.write(Data("""
      the observation JSON has no page \(pageNumber) \
    (it holds \(pages.map { String($0.page) }.joined(separator: ", ")))

    """.utf8))
    exit(1)
}
let b = page.bounds(for: .mediaBox)
var leftOK = 0, leftMiss = 0, rightOK = 0, rightMiss = 0
for o in reference.observations where o.text.count > 12 {
    let w = o.boundingBox.width * b.width
    let h = o.boundingBox.height * b.height
    let x = b.minX + o.boundingBox.x * b.width
    let y = b.maxY - o.boundingBox.y * b.height - h
    func probe(_ r: CGRect) -> String {
        page.selection(for: r)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    let head = probe(CGRect(x: x, y: y, width: w * 0.15, height: h))
    let tail = probe(CGRect(x: x + w * 0.85, y: y, width: w * 0.15, height: h))
    if head.isEmpty { leftMiss += 1 } else { leftOK += 1 }
    if tail.isEmpty { rightMiss += 1 } else { rightOK += 1 }
    if head.isEmpty {
        print("  line start NOT selectable: \(o.text.prefix(46))")
    }
    if tail.isEmpty {
        print("  line end NOT selectable:   \(o.text.prefix(46))")
    }
}
let judged = leftOK + leftMiss
guard judged > 0 else {
    print("  page \(pageNumber): NOTHING JUDGED — \(reference.observations.count) "
          + "observation(s), none over 12 characters. No percentage is reported, "
          + "because a run that measured nothing is not a run that passed.")
    exit(1)
}
print(String(format: "  page %d, %d lines: line starts %d/%d   line ends %d/%d",
             pageNumber, judged, leftOK, judged, rightOK, judged))
