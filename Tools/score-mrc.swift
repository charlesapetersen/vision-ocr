// What MRC would actually cost on the pages this app sends down the picture
// route, measured rather than argued about.
//
// Why this exists: a library MRC scan of the same material can be several times
// smaller than what this app produces, and the obvious conclusions about why are
// wrong in both directions. An earlier attempt compared MRC against single-layer
// JPEG 2000 on a page whose source layer was *already* JPEG 2000 and concluded
// they tied; they do not (BUGS.md R34). This tool renders each page once and
// builds every candidate from that one buffer, so nothing here can be an
// artefact of what codec the source happened to use.
//
// What the commercial tools do, for reference — measured from 275 MRC files in a
// real library, 52 of 60 sampled produced by ABBYY FineReader: they route per
// page exactly as this app does. Plain text pages go to 1-bit JBIG2 and are not
// layered at all; only pages that genuinely mix text with pictures get the three
// layers. So MRC is not a replacement for the 1-bit route — it is a replacement
// for the single big JPEG that mixed pages currently get.
//
//   mkdir -p /tmp/h && cp Tools/score-mrc.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/score-mrc -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/score-mrc testdocs/**/*.pdf
//
// Per picture page: what the app ships today, and what the three layers cost,
// with the reconstruction's PSNR against the same source buffer so the size is
// not read without the fidelity beside it.
import AppKit
import CoreGraphics
import Foundation
import PDFKit

// Layer parameters follow internetarchive/archive-pdf-tools, which produced two
// of the exemplars on hand: Sauvola with a dpi/4 window, background downsampled
// 3x, foreground 3x, holes filled from their surroundings before downsampling.
let sauvolaK = 0.34
let bgDownsample = 3
let fgDownsample = 3

/// Sauvola's local threshold: t(x) = m(x) * (1 + k * (s(x)/128 - 1)).
///
/// Local, not global. Otsu picks one threshold for the whole sheet, which is
/// right for deciding *whether* a page is a picture and wrong for cutting text
/// out of one — on a page that is half photograph, the photograph drags the
/// global threshold until the text either bloats or disappears. Computed over
/// integral images so the window size costs nothing.
func sauvolaMask(_ grey: [UInt8], width w: Int, height h: Int, window: Int) -> [Bool] {
    let n = w * h
    var sum = [Double](repeating: 0, count: (w + 1) * (h + 1))
    var sq = [Double](repeating: 0, count: (w + 1) * (h + 1))
    for y in 0..<h {
        var rs = 0.0, rq = 0.0
        for x in 0..<w {
            let v = Double(grey[y * w + x])
            rs += v; rq += v * v
            sum[(y + 1) * (w + 1) + x + 1] = sum[y * (w + 1) + x + 1] + rs
            sq[(y + 1) * (w + 1) + x + 1] = sq[y * (w + 1) + x + 1] + rq
        }
    }
    let r = max(window / 2, 1)
    var mask = [Bool](repeating: false, count: n)
    for y in 0..<h {
        let y0 = max(y - r, 0), y1 = min(y + r + 1, h)
        for x in 0..<w {
            let x0 = max(x - r, 0), x1 = min(x + r + 1, w)
            let area = Double((y1 - y0) * (x1 - x0))
            let s = sum[y1 * (w + 1) + x1] - sum[y0 * (w + 1) + x1]
                  - sum[y1 * (w + 1) + x0] + sum[y0 * (w + 1) + x0]
            let q = sq[y1 * (w + 1) + x1] - sq[y0 * (w + 1) + x1]
                  - sq[y1 * (w + 1) + x0] + sq[y0 * (w + 1) + x0]
            let mean = s / area
            let sd = max(q / area - mean * mean, 0).squareRoot()
            if Double(grey[y * w + x]) < mean * (1 + sauvolaK * (sd / 128.0 - 1)) {
                mask[y * w + x] = true
            }
        }
    }
    return mask
}

/// Fill the pixels under `holes` from their surroundings, so the layer has no
/// hard edges where the other layer will cover it. Hard edges are the whole
/// problem: a background with black text cut out of it as sharp holes costs more
/// to compress than the background with the text still in it.
func fill(_ src: [UInt8], holes: [Bool], width w: Int, height h: Int,
          radius: Int, passes: Int = 3) -> [UInt8] {
    var out = src, live = holes
    var rad = radius
    for _ in 0..<passes {
        var next = out
        var still = live
        for y in 0..<h where live[y * w ..< (y + 1) * w].contains(true) {
            for x in 0..<w where live[y * w + x] {
                var acc = 0, cnt = 0
                var dy = -rad
                while dy <= rad {
                    let yy = y + dy
                    if yy >= 0 && yy < h {
                        var dx = -rad
                        while dx <= rad {
                            let xx = x + dx
                            if xx >= 0 && xx < w && !live[yy * w + xx] {
                                acc += Int(out[yy * w + xx]); cnt += 1
                            }
                            dx += max(rad / 3, 1)
                        }
                    }
                    dy += max(rad / 3, 1)
                }
                if cnt > 0 { next[y * w + x] = UInt8(acc / cnt); still[y * w + x] = false }
            }
        }
        out = next; live = still
        if !live.contains(true) { break }
        rad *= 2
    }
    // Anything still unreached (a hole larger than the widened radius) takes the
    // page mean rather than staying at its original ink value.
    if live.contains(true) {
        var t = 0, c = 0
        for i in 0..<(w * h) where !holes[i] { t += Int(out[i]); c += 1 }
        let m = UInt8(c > 0 ? t / c : 255)
        for i in 0..<(w * h) where live[i] { out[i] = m }
    }
    return out
}

/// Box-average downsample by an integer factor.
func downsample(_ src: [UInt8], width w: Int, height h: Int, by f: Int)
    -> (pixels: [UInt8], width: Int, height: Int) {
    guard f > 1 else { return (src, w, h) }
    let nw = max(w / f, 1), nh = max(h / f, 1)
    var out = [UInt8](repeating: 0, count: nw * nh)
    for y in 0..<nh {
        for x in 0..<nw {
            var acc = 0, cnt = 0
            for dy in 0..<f {
                let yy = y * f + dy
                if yy >= h { continue }
                for dx in 0..<f {
                    let xx = x * f + dx
                    if xx >= w { continue }
                    acc += Int(src[yy * w + xx]); cnt += 1
                }
            }
            out[y * nw + x] = UInt8(cnt > 0 ? acc / cnt : 255)
        }
    }
    return (out, nw, nh)
}

/// Bilinear, because that is what a PDF viewer does with a downsampled image.
/// Nearest-neighbour was the first version and it understated MRC badly: it puts
/// 3x3 blocks of flat tone behind the text and the error lands entirely in the
/// background, which is the one layer MRC deliberately treats as cheap.
func upsample(_ src: [UInt8], width sw: Int, height sh: Int, toWidth w: Int, toHeight h: Int)
    -> [UInt8] {
    var out = [UInt8](repeating: 255, count: w * h)
    guard sw > 0, sh > 0, w > 0, h > 0 else { return out }
    for y in 0..<h {
        let fy = (Double(y) + 0.5) * Double(sh) / Double(h) - 0.5
        let y0 = max(Int(fy.rounded(.down)), 0), y1 = min(y0 + 1, sh - 1)
        let wy = fy - Double(y0)
        for x in 0..<w {
            let fx = (Double(x) + 0.5) * Double(sw) / Double(w) - 0.5
            let x0 = max(Int(fx.rounded(.down)), 0), x1 = min(x0 + 1, sw - 1)
            let wx = fx - Double(x0)
            let a = Double(src[min(y0, sh - 1) * sw + x0]), b = Double(src[min(y0, sh - 1) * sw + x1])
            let c = Double(src[y1 * sw + x0]), d = Double(src[y1 * sw + x1])
            let top = a + (b - a) * wx, bot = c + (d - c) * wx
            out[y * w + x] = UInt8(max(0, min(255, (top + (bot - top) * wy).rounded())))
        }
    }
    return out
}

func greyPNG(_ pixels: [UInt8], width w: Int, height h: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
        samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceWhite, bytesPerRow: w, bitsPerPixel: 8) else { return nil }
    if let d = rep.bitmapData {
        pixels.withUnsafeBytes { d.update(from: $0.bindMemory(to: UInt8.self).baseAddress!,
                                          count: w * h) }
    }
    return rep.representation(using: .png, properties: [:])
}

func psnr(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return -1 }
    var s = 0.0
    for i in 0..<a.count { let d = Double(a[i]) - Double(b[i]); s += d * d }
    let m = s / Double(a.count)
    return m == 0 ? .infinity : 10 * log10(255 * 255 / m)
}

let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mrc-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

/// JBIG2 bytes for a 0/255 mask, via the bundled encoder.
func jbig2Bytes(_ mask: [Bool], width w: Int, height h: Int) -> Int? {
    guard let enc = JBIG2.encoder else { return nil }
    var px = [UInt8](repeating: 255, count: w * h)
    for i in 0..<(w * h) where mask[i] { px[i] = 0 }
    guard let png = greyPNG(px, width: w, height: h) else { return nil }
    let p = tmp.appendingPathComponent("m.png"), o = tmp.appendingPathComponent("m.jbig2")
    guard (try? png.write(to: p)) != nil else { return nil }
    try? JBIG2.encode(png: p, to: o, using: enc)
    return (try? Data(contentsOf: o).count)
}

var totals = (now: 0, mrc: 0, pages: 0)
print("file\tpage\tpx\tnowKB\tmaskKB\tbgKB\tfgKB\tmrcKB\tratio\tmrcPSNR\tnowPSNR")
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let doc = Flattener.open(url, password: nil) else { continue }
    let idx = doc.pageCount <= 4 ? Array(0..<doc.pageCount)
                                 : [doc.pageCount / 3, doc.pageCount / 2, doc.pageCount * 3 / 4]
    for i in idx {
        guard let page = doc.page(at: i) else { continue }
        let box = Flattener.fullBox(of: page)
        let dpi = Flattener.rebuildDPI(of: page)
        let scale = dpi / 72.0
        let wd = (box.width * scale).rounded(), ht = (box.height * scale).rounded()
        guard wd.isFinite, ht.isFinite, wd >= 1, ht >= 1,
              wd * ht <= 60_000_000 else { continue }
        let w = max(Int(wd), 1), h = max(Int(ht), 1)
        guard let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                              width: w, height: h, from: .mediaBox)
        else { continue }
        let t = Flattener.otsuThreshold(of: grey)
        let sat = Flattener.saturation(of: page)
        guard Flattener.isPicture(page, grey: grey, width: w, height: h,
                                  threshold: t, saturation: sat) else { continue }

        // What ships today for this page.
        guard let now = Flattener.jpegData(from: grey, width: w, height: h,
                                           quality: Flattener.pictureJPEGQuality)
        else { continue }

        let mask = sauvolaMask(grey, width: w, height: h, window: max(Int(dpi / 4), 3))
        guard let maskBytes = jbig2Bytes(mask, width: w, height: h) else { continue }

        let inv = mask.map { !$0 }
        let bgFull = fill(grey, holes: mask, width: w, height: h, radius: 10)
        let (bg, bw, bh) = downsample(bgFull, width: w, height: h, by: bgDownsample)
        let fgFull = fill(grey, holes: inv, width: w, height: h, radius: 3)
        let (fg, fw, fh) = downsample(fgFull, width: w, height: h, by: fgDownsample)

        let q = Flattener.pictureJPEGQuality
        guard let bgD = Flattener.jpegData(from: bg, width: bw, height: bh, quality: q),
              let fgD = Flattener.jpegData(from: fg, width: fw, height: fh, quality: q)
        else { continue }
        let mrc = maskBytes + bgD.count + fgD.count

        // Reconstruct the way a reader would: background, then foreground
        // painted through the stencil.
        let bgUp = upsample(bg, width: bw, height: bh, toWidth: w, toHeight: h)
        let fgUp = upsample(fg, width: fw, height: fh, toWidth: w, toHeight: h)
        var recon = bgUp
        for j in 0..<(w * h) where mask[j] { recon[j] = fgUp[j] }

        // And what today's JPEG actually reconstructs to, for a fair comparison.
        var nowRecon = grey
        if let src = CGImageSourceCreateWithData(now as CFData, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            var b = [UInt8](repeating: 0, count: w * h)
            b.withUnsafeMutableBytes { buf in
                CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                          bitmapInfo: CGImageAlphaInfo.none.rawValue)?
                    .draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            nowRecon = b
        }

        // MRC_DUMP=<dir> writes the reconstruction and today's output side by
        // side. Numbers alone cannot settle this one: PSNR punishes a smoothed
        // background and is blind to text edges being exact, which is precisely
        // the trade MRC makes. Look at the pages.
        if let dump = ProcessInfo.processInfo.environment["MRC_DUMP"], totals.pages < 3 {
            let stem = "\(url.deletingPathExtension().lastPathComponent.prefix(24))-p\(i + 1)"
            for (name, px) in [("mrc", recon), ("now", nowRecon), ("src", grey)] {
                if let d = greyPNG(px, width: w, height: h) {
                    try? d.write(to: URL(fileURLWithPath: dump)
                        .appendingPathComponent("\(stem)-\(name).png"))
                }
            }
        }

        totals.now += now.count; totals.mrc += mrc; totals.pages += 1
        print(String(format: "%@\t%d\t%dx%d\t%d\t%d\t%d\t%d\t%d\t%.2fx\t%.2f\t%.2f",
                     url.lastPathComponent, i + 1, w, h, now.count / 1024,
                     maskBytes / 1024, bgD.count / 1024, fgD.count / 1024, mrc / 1024,
                     Double(now.count) / Double(max(mrc, 1)),
                     psnr(grey, recon), psnr(grey, nowRecon)))
        fflush(stdout)
    }
}
print("\n=== \(totals.pages) picture pages ===")
if totals.pages > 0 {
    print("today: \(totals.now / 1024) KB   MRC: \(totals.mrc / 1024) KB   "
          + String(format: "%.2fx smaller", Double(totals.now) / Double(max(totals.mrc, 1))))
}
