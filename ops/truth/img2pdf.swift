import Foundation
import CoreGraphics
import ImageIO
// img2pdf <image> <dpi> <out.pdf>
// Wraps one image as a one-page, image-only PDF sized from its pixels at <dpi>. ImageMagick's own PDF
// writer is not used: without Ghostscript it wrote a page PDFKit sized wrongly and rendered blank.
let a = CommandLine.arguments
guard a.count == 4, let dpi = Double(a[2]),
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    FileHandle.standardError.write("usage: img2pdf <image> <dpi> <out.pdf>\n".data(using: .utf8)!); exit(2)
}
var box = CGRect(x: 0, y: 0, width: Double(img.width) * 72 / dpi, height: Double(img.height) * 72 / dpi)
let ctx = CGContext(URL(fileURLWithPath: a[3]) as CFURL, mediaBox: &box, nil)!
ctx.beginPDFPage(nil); ctx.draw(img, in: box); ctx.endPDFPage(); ctx.closePDF()
