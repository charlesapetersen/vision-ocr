import PDFKit
import Foundation
// For each line, slide a thin probe vertically until it returns that line's own
// first word. The winning offset tells us how far our run sits from its box.
struct Box: Decodable { let x, y, width, height: Double }
struct Obs: Decodable { let boundingBox: Box; let text: String }
struct Pg: Decodable { let page: Int; let observations: [Obs] }
let pdf = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let page = pdf.page(at: Int(CommandLine.arguments[2])! - 1)!
let pages = try JSONDecoder().decode([Pg].self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
let b = page.bounds(for: .mediaBox)
var offsets: [Double] = []
for o in pages[0].observations where o.text.count > 15 {
    let w = o.boundingBox.width * b.width, h = o.boundingBox.height * b.height
    let x = b.minX + o.boundingBox.x * b.width
    let boxBottom = b.maxY - o.boundingBox.y * b.height - h
    let firstWord = String(o.text.split(separator: " ").first ?? "").prefix(6)
    guard firstWord.count >= 3 else { continue }
    var best: Double?
    // Offsets as a fraction of the line height, from well below to well above.
    for step in stride(from: -1.2, through: 1.2, by: 0.1) {
        let r = CGRect(x: x, y: boxBottom + h * step, width: w * 0.2, height: h * 0.5)
        let s = page.selection(for: r)?.string ?? ""
        if s.contains(firstWord) { best = step; break }
    }
    if let best { offsets.append(best) }
}
offsets.sort()
if offsets.isEmpty { print("  no lines matched"); exit(0) }
let median = offsets[offsets.count/2]
print(String(format: "  %d lines located; offset as fraction of line height: median %.2f, range %.2f...%.2f",
             offsets.count, median, offsets.first!, offsets.last!))
print("  (0.00 would mean our glyphs sit exactly on the box bottom)")
