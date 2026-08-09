import PDFKit
import Foundation
// Reads only the PDF's embedded text layer — no OCR involved.
for path in CommandLine.arguments.dropFirst() {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
        print("\(path): cannot open"); continue
    }
    let text = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let name = (path as NSString).lastPathComponent
    print("\(name): \(text.isEmpty ? "<NO EMBEDDED TEXT>" : text.replacingOccurrences(of: "\n", with: " / "))")
}
