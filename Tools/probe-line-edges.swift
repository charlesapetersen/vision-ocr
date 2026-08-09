import PDFKit
import Foundation
// For each recognised line: is its first word selectable, its last word, and does
// a whole-line probe return the whole line?
struct Box: Decodable { let x, y, width, height: Double }
struct Obs: Decodable { let boundingBox: Box; let text: String }
struct Pg: Decodable { let page: Int; let observations: [Obs] }

let pdf = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let pageIndex = Int(CommandLine.arguments[2])! - 1
let pages = try JSONDecoder().decode([Pg].self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
let page = pdf.page(at: pageIndex)!
let b = page.bounds(for: .mediaBox)
var leftOK = 0, leftMiss = 0, rightOK = 0, rightMiss = 0
for o in pages[0].observations where o.text.count > 12 {
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
}
print(String(format: "  line starts: %d/%d   line ends: %d/%d",
             leftOK, leftOK+leftMiss, rightOK, rightOK+rightMiss))
