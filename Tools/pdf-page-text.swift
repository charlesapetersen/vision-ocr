import PDFKit
import Foundation
// Reads one page's embedded text straight from the full document.
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let n = Int(CommandLine.arguments[2])!
print(doc.page(at: n - 1)?.string ?? "")
