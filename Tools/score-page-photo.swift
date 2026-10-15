// score-page-photo <list.tsv>: pk-photo-detect's measure. Each row of the list is
// `id <TAB> file <TAB> page <TAB> label`, a PDF page or an image (page 1). Prints one row per
// page: whether the image file's tags name a camera (`Flattener.cameraExposed`), the
// signals `Recogniser.photoSignals` takes from the page (rendered through PDFKit at 200 dpi,
// capped at 3,000 px, for the columns only), and the call `Flattener.photographed` makes as the
// app makes it, an image wrapped as `makeSearchablePDF` wraps it: on the pixels alone and on
// the page as a whole. Writes nothing but stdout and a scratch directory it removes. Exit 1 when a page is called against its label, 2 when the list is
// unreadable or empty. Built with `Sources/` (see the README's recipe).
import Foundation
import ImageIO
import PDFKit

guard CommandLine.arguments.count == 2,
      let list = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8) else {
    FileHandle.standardError.write("usage: score-page-photo <list.tsv>\n".data(using: .utf8)!); exit(2)
}

func render(_ page: PDFPage) -> CGImage? {
    let box = page.bounds(for: .cropBox)
    let rotated = page.rotation % 180 != 0
    let w = rotated ? box.height : box.width, h = rotated ? box.width : box.height
    let s = min(200.0 / 72, 3000 / max(w, h, 1))
    let pw = max(1, Int(w * s)), ph = max(1, Int(h * s))
    guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
    ctx.scaleBy(x: s, y: s)
    page.draw(with: .cropBox, to: ctx)
    return ctx.makeImage()
}

let scratch = FileManager.default.temporaryDirectory
    .appendingPathComponent("score-page-photo-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
print("id\tlabel\tcamera\tpaper_level\tcast_spread\tborder_dark\tfalloff\tnoise\tpixels_call\tcall")
var wrong = 0, measured = 0
for line in list.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
    let f = line.split(separator: "\t", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
    guard f.count >= 4, let n = Int(f[2]), n >= 1, ["photo", "scan", "digital"].contains(f[3]) else {
        FileHandle.standardError.write("unreadable row (want id, file, page >= 1, photo|scan|digital): \(line)\n"
            .data(using: .utf8)!); exit(2)
    }
    measured += 1
    autoreleasepool {
        // As the app judges a page: an image is wrapped as `makeSearchablePDF` wraps it, its tags
        // read from the file, and the page judged by `Flattener.photographed`.
        var url = URL(fileURLWithPath: f[1]), camera = false
        if url.pathExtension.lowercased() != "pdf" {
            camera = Flattener.cameraExposed(CGImageSourceCreateWithURL(url as CFURL, nil)
                .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] })
            guard let wrapped = Flattener.wrapImage(url, into: scratch) else {
                print("\(f[0])\t\(f[3])\tERROR"); wrong += 1; return
            }
            url = wrapped
        }
        let doc = PDFDocument(url: url)
        guard let page = doc?.page(at: n - 1), let image = render(page) else {
            print("\(f[0])\t\(f[3])\tERROR"); wrong += 1; return
        }
        let box = Flattener.fullBox(of: page)
        let s = Recogniser.photoSignals(of: image)
        let pixels = Flattener.photographed(page, box: box, cameraExposed: false)
        let call = Flattener.photographed(page, box: box, cameraExposed: camera)
        if call != (f[3] == "photo") { wrong += 1 }
        print([f[0], f[3], camera ? "yes" : "-", String(format: "%.0f", s.paperLevel),
               String(format: "%.1f", s.castSpread), String(format: "%.3f", s.borderDark),
               String(format: "%.3f", s.falloff), String(format: "%.2f", s.noise),
               pixels ? "photo" : "-", call ? "photo" : "-"].joined(separator: "\t"))
        fflush(stdout)
    }
}
FileHandle.standardError.write("\(wrong) of \(measured) page(s) called against their label\n".data(using: .utf8)!)
try? FileManager.default.removeItem(at: scratch)
if measured == 0 { exit(2) }
exit(wrong == 0 ? 0 : 1)
