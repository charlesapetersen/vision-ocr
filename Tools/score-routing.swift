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
