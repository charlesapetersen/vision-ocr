import PDFKit
import Foundation
// render-page <pdf> <page 1-based> <dpi> <out.png>
// Renders one page through PDFKit, as Preview draws it, to an 8-bit grey PNG on white.
// Used for the reader's page image and as the first step of make-scans.sh.
let a = CommandLine.arguments
guard a.count == 5, let n = Int(a[2]), let dpi = Double(a[3]) else {
    FileHandle.standardError.write("usage: render-page <pdf> <page> <dpi> <out.png>\n".data(using: .utf8)!); exit(2)
}
guard let doc = PDFDocument(url: URL(fileURLWithPath: a[1])), let page = doc.page(at: n - 1) else {
    FileHandle.standardError.write("cannot open page \(n) of \(a[1])\n".data(using: .utf8)!); exit(1)
}
let box = page.bounds(for: .cropBox)
let rotated = page.rotation % 180 != 0
let wPt = rotated ? box.height : box.width, hPt = rotated ? box.width : box.height
let w = Int((wPt * dpi / 72).rounded()), h = Int((hPt * dpi / 72).rounded())
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
ctx.scaleBy(x: dpi / 72, y: dpi / 72)
page.draw(with: .cropBox, to: ctx)
let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[4]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
guard CGImageDestinationFinalize(dest) else { exit(1) }
print("\(w)x\(h)")
