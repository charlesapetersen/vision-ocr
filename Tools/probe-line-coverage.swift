import PDFKit
import Foundation
// Precise coverage: for every recognised line, probe the right-hand 15% of that
// line's own bounding box. A short line is no longer counted as a failure.
struct Box: Decodable { let x, y, width, height: Double }
struct Obs: Decodable { let boundingBox: Box; let text: String }
struct Pg: Decodable { let page: Int; let observations: [Obs] }

let pdf = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let pages = try JSONDecoder().decode([Pg].self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
var ok = 0, miss = 0
for pg in pages {
    guard let page = pdf.page(at: pg.page - 1) else { continue }
    let b = page.bounds(for: .mediaBox)
    for o in pg.observations where o.text.count > 12 {
        let w = o.boundingBox.width * b.width
        let h = o.boundingBox.height * b.height
        let x = b.minX + o.boundingBox.x * b.width
        let yTop = o.boundingBox.y * b.height
        let y = b.maxY - yTop - h
        let probe = CGRect(x: x + w * 0.85, y: y, width: w * 0.15, height: h)
        let sel = page.selection(for: probe)?.string?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if sel.isEmpty { miss += 1 } else { ok += 1 }
    }
}
let total = ok + miss
print(String(format: "  %d/%d lines reach their own right edge (%.0f%%)",
             ok, total, total > 0 ? 100.0*Double(ok)/Double(total) : 0))
