import Foundation
import CoreGraphics
import ImageIO
// cut-crops <page.png> <outdir> [max=2000]
// Cuts a page image into crops that cover all of it, none over <max> px on a side, for the reader in
// procedure.md. Cuts go in the widest white run of rows (or columns) found in the pixels, never from
// Vision's layout, so a block Vision skips is still covered. Where a region has no white run to cut in,
// the cut goes through the least-inked row or column and the two crops overlap by 150 px. Writes
// c01.png... and crops.tsv (name x y w h overlap) in page pixels.
let a = CommandLine.arguments
guard a.count >= 3, let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("usage: cut-crops <page.png> <outdir> [max]"); exit(2) }
let maxSide = a.count > 3 ? Int(a[3])! : 2000
let W = img.width, H = img.height, overlap = 150
var px = [UInt8](repeating: 255, count: W * H)
let g = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
g.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))  // row 0 of px is the top of the image
func ink(_ x: Int, _ y: Int) -> Bool { px[y * W + x] < 160 }

/// Picks a cut in [lo, hi) along one axis: the middle of the widest run of empty lines, else the emptiest line.
func cut(_ lo: Int, _ hi: Int, _ count: (Int) -> Int) -> (at: Int, white: Bool) {
    var best = (len: 0, mid: -1), run = 0, least = (n: Int.max, at: lo)
    for i in lo..<hi {
        let c = count(i)
        if c < least.n { least = (c, i) }
        if c == 0 { run += 1; if run >= best.len { best = (run, i - run / 2) } } else { run = 0 }
    }
    return best.len >= 8 ? (best.mid, true) : (least.at, false)
}
var crops: [(CGRect, Bool)] = []
func split(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ ov: Bool) {
    let tall = h > maxSide
    guard tall || w > maxSide else { crops.append((CGRect(x: x, y: y, width: w, height: h), ov)); return }
    let (start, len) = tall ? (y, h) : (x, w)
    let (at, white) = cut(start + len / 4, start + min(maxSide - overlap / 2, len * 3 / 4)) { i in
        var n = 0
        if tall { for c in x..<(x + w) where ink(c, i) { n += 1 } } else { for r in y..<(y + h) where ink(i, r) { n += 1 } }
        return n
    }
    let o = white ? 0 : overlap / 2
    if tall { split(x, y, w, at - y + o, ov || !white); split(x, at - o, w, y + h - at + o, ov || !white) }
    else { split(x, y, at - x + o, h, ov || !white); split(at - o, y, x + w - at + o, h, ov || !white) }
}
split(0, 0, W, H, false)
try? FileManager.default.createDirectory(atPath: a[2], withIntermediateDirectories: true)
var tsv = "name\tx\ty\tw\th\toverlap\n"
for (i, (r, ov)) in crops.enumerated() {
    let name = String(format: "c%02d.png", i + 1)
    // CGImage.cropping takes top-left-origin pixel rects, matching px.
    let c = img.cropping(to: r)!
    let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "\(a[2])/\(name)") as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d, c, nil); CGImageDestinationFinalize(d)
    tsv += "\(name)\t\(Int(r.minX))\t\(Int(r.minY))\t\(Int(r.width))\t\(Int(r.height))\t\(ov ? "yes" : "no")\n"
}
try! tsv.write(toFile: "\(a[2])/crops.tsv", atomically: true, encoding: .utf8)
print("\(crops.count) crops, \(crops.filter { $0.1 }.count) overlapping")
