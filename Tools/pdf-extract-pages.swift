import PDFKit
import Foundation
// extract <src> <dest> <page1based>...
let src = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = URL(fileURLWithPath: CommandLine.arguments[2])
guard let doc = PDFDocument(url: src) else { exit(1) }
let outDoc = PDFDocument()
for a in CommandLine.arguments.dropFirst(3) {
    guard let i = Int(a), let p = doc.page(at: i - 1) else { continue }
    outDoc.insert(p, at: outDoc.pageCount)
}
outDoc.write(to: dest)
print("extracted \(outDoc.pageCount) pages")
