import PDFKit
import Foundation
let src = URL(fileURLWithPath: CommandLine.arguments[1])
let label = CommandLine.arguments[2]
let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rt-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }
guard let doc = PDFDocument(url: src), doc.pageCount > 0 else { print("\(label)\tFAIL"); exit(0) }
let idx = Flattener.sampleIndices(count: doc.pageCount, wanted: 4)
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
//
// **C24 closed on 2026-08-17 and this guard stopped firing on the corpus.** `rebuildDPI`
// applies the policy to what the page *draws*, and extraction rewrites a page's
// `/Resources` to hold what it references — so an extracted page and its original measure
// the same now, and the three documents this refused (`AI 2027`, `Batzell`, `Sherman_1986`)
// all print rows. Measured both ways in that commit. **The guard stays**: it was never
// specific to C24's cause, it is cheap, and its `before` diagnostics are what showed the
// resolutions it called "drift" were the *correct* per-page ones all along — this tool was
// refusing its own right answers because production held a wrong one.
// A page it cannot compare is a refusal, not a pass. This note used to say that
// `idx` CAN repeat an index — at pageCount 5 it was `[1, 1, 2, 3]`, on 5 corpus
// documents — and that PDFKit duplicates the page so position and index still line
// up. Both true, and it was the wrong conclusion: the counts below are a *census*
// of how the sample routes, so a page counted twice is one document reported as
// four pages when three were looked at. `Flattener.sampleIndices` does not repeat
// (A12.8). Both expressions skip page 1 on a document over four pages — an earlier
// version of this note claimed otherwise, and it was written the wrong way round:
// the old `[1, n/3, n/2, n*3/4]` is 0-based, so its lowest index is page *two*.
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
