import PDFKit
import Foundation
let src = URL(fileURLWithPath: CommandLine.arguments[1])
let label = CommandLine.arguments[2]
let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rt-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }
guard let doc = PDFDocument(url: src), doc.pageCount > 0 else { print("\(label)\tFAIL"); exit(0) }
let idx = doc.pageCount <= 4 ? Array(0..<doc.pageCount) : [1, doc.pageCount/3, doc.pageCount/2, doc.pageCount*3/4]
let s = PDFDocument()
for i in idx { if let p = doc.page(at: i) { s.insert(p, at: s.pageCount) } }
let input = tmp.appendingPathComponent("in.pdf"); _ = s.write(to: input)
// A12.2. Extraction can change the resolution the rebuild renders at, because
// `largestImage` walks a `/Resources` that 4 of 208 multi-page corpus documents
// share across every page. `BUGS.md` T2's closing line — "score-routing was never
// affected, it calls the real flatten" — is true of the DPI *policy* and false of
// the DPI *value* on those documents. Say so rather than print a KB/page figure
// measured at a resolution production would not have used. qpdf --pages gives the
// same wrong answer; this is not fixable in the tool.
// A page it cannot compare is a refusal, not a pass. Note `idx` CAN repeat an
// index — at pageCount 5 it is [1, 1, 2, 3], which is 5 corpus documents — and
// PDFKit duplicates the page rather than dropping it, so position and index still
// line up. Verified on two of those five.
var drift: [String] = []
guard let extracted = PDFDocument(url: input), extracted.pageCount == idx.count else {
    print("\(label)\tFAIL\tthe sample did not survive the write"); exit(1)
}
for (position, index) in idx.enumerated() {
    guard let a = doc.page(at: index), let b = extracted.page(at: position) else {
        print("\(label)\tFAIL\tcannot compare page \(index + 1)"); exit(1)
    }
    let before = Flattener.rebuildDPI(of: a), after = Flattener.rebuildDPI(of: b)
    if abs(before - after) > 0.5 {
        drift.append(String(format: "p%d %.0f->%.0f", index + 1, before, after))
    }
}
if !drift.isEmpty {
    print("\(label)\tSKIP\textraction changed the rebuild resolution (A12.2, BUGS.md C24): "
          + drift.joined(separator: " "))
    exit(1)
}
let pngs = tmp.appendingPathComponent("p")
try? FileManager.default.createDirectory(at: pngs, withIntermediateDirectories: true)
let pages = (try? Flattener.flatten(input, to: tmp.appendingPathComponent("o.pdf"),
                                    mode: .auto, pngDirectory: pngs)) ?? []
var bi = 0, gs = 0, col = 0, bytes = 0
for p in pages {
    switch p.content {
    case .bilevel(let u): bi += 1; bytes += (try? Data(contentsOf: u).count) ?? 0
    case .jpeg(let u):
        if p.isColour { col += 1 } else { gs += 1 }
        bytes += (try? Data(contentsOf: u).count) ?? 0
    }
}
print("\(label)\tbilevel=\(bi) greyscale=\(gs) colour=\(col)\t\(bytes/max(pages.count,1)/1024) KB/page\tbytes=\(bytes)\tpages=\(pages.count)")
