import PDFKit
import Foundation
// Per-file summary: pages, which pages carry embedded text, and page geometry.
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let doc = PDFDocument(url: url) else { print("\(path): CANNOT OPEN"); continue }
    let n = doc.pageCount
    var withText = 0, totalChars = 0
    for i in 0..<n {
        let s = doc.page(at: i)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !s.isEmpty { withText += 1; totalChars += s.count }
    }
    let bounds = doc.page(at: 0)?.bounds(for: .mediaBox) ?? .zero
    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    print("""
    \((path as NSString).lastPathComponent)
      pages: \(n)   pages with text: \(withText)   total chars: \(totalChars)
      page 1 mediabox: \(Int(bounds.width))x\(Int(bounds.height)) pt
      file size: \((size ?? 0)/1_048_576) MB   encrypted: \(doc.isEncrypted)
    """)
}
