import PDFKit
import Foundation
let src = URL(fileURLWithPath: CommandLine.arguments[1])
let label = CommandLine.arguments[2]
guard let doc = PDFDocument(url: src) else { exit(0) }
let idx = doc.pageCount <= 3 ? Array(0..<doc.pageCount) : [1, doc.pageCount/2]
for i in idx {
    guard let page = doc.page(at: i) else { continue }
    let box = Flattener.fullBox(of: page)
    // rebuildDPI, not nativeDPI: flatten renders at the former, and on the 84 of
    // 214 sampled corpus pages whose nativeDPI is under the 150 floor the two
    // differ enough to invert the verdict. Measured on Hoffman 1923 p12 — tool
    // 10.55 DPI, tone 0.940, "picture"; production 300 DPI, tone 0.013, "text".
    // An instrument that disagrees with the thing it measures is worse than none.
    let dpi = Flattener.rebuildDPI(of: page)
    let scale = dpi / 72.0
    let w = max(Int(box.width * scale), 1), h = max(Int(box.height * scale), 1)
    guard let grey = Flattener.renderGrey(page, box: box, scale: scale, width: w, height: h,
                                     from: .mediaBox)
    else { continue }
    let s = Flattener.pictureSignals(page, grey: grey, width: w, height: h)
    print("  p\(i+1) ink=\(String(format: "%.3f", s.ink)) tone=\(String(format: "%.3f", s.tone)) sat=\(String(format: "%.3f", s.sat)) otsu=\(s.threshold)")
}
