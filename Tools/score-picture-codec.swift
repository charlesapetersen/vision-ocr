// What a picture page costs under each codec, and what it costs in fidelity.
//
// This is the measurement behind BUGS.md R34, which rejected JPEG 2000 for
// picture pages. It stays in the tree because the conclusion depends on it and
// because the next person to have the same good idea should be able to re-run it
// rather than re-derive it.
//
// The question is not "which codec is smaller" — JPEG 2000 is smaller at every
// rate — but "which rate is small *without being worse than what the app already
// ships*". R13 settled that fidelity wins on this material.
//
// The answer it gave: ImageIO's `compressionFactor` for JPEG 2000 is a
// compression ratio, not a quality target, so no single value holds fidelity
// steady across pages, and 88–98% of picture pages come out below the shipping
// JPEG's PSNR. Encoding is done here rather than through `Flattener` precisely
// because `Flattener` has no JPEG 2000 route and should not grow one.
//
//   swiftc -O -o build/score-picture-codec \
//     $(ls Sources/*.swift | grep -v App.swift) Tools/score-picture-codec.swift
//   build/score-picture-codec testdocs/**/*.pdf
//
// Per picture page it prints the JPEG size and PSNR, then the same for each
// candidate JPX quality, all measured against the *same* grey buffer — rendered
// once and encoded many times, so no difference here can come from the render.
//
// The instrument's own weakness, stated because CONTRIBUTING §3 is right about
// this: PSNR is not perception. It is used here only to establish "no worse than
// before", which is a comparison between two encodes of one buffer, and is the
// one job PSNR is actually sound for. It is not evidence that a given rate looks
// good — that came from 1:1 crops.
import AppKit
import Foundation
import PDFKit
import CoreGraphics

/// JPEG 2000 bytes for a grey buffer. Local to this tool: the app has no JPEG
/// 2000 route, and R34 is the reason it does not.
func jpxData(from grey: [UInt8], width: Int, height: Int, quality: Double) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceWhite, bytesPerRow: width, bitsPerPixel: 8)
    else { return nil }
    if let dest = rep.bitmapData {
        grey.withUnsafeBytes { dest.update(from: $0.bindMemory(to: UInt8.self).baseAddress!,
                                           count: width * height) }
    }
    return rep.representation(using: .jpeg2000, properties: [.compressionFactor: quality])
}

/// Both sweeps R34 quotes, in one run.
///
/// It shipped carrying only the second of them, which meant re-running it could
/// not reproduce the register's own figures — the "88–98% of pages come out
/// below the shipping fidelity" line comes from the low rates, and the
/// "1.19x on real background layers" comparison from the high ones.
let candidates: [Double] = [0.08, 0.10, 0.13, 0.16, 0.20, 0.30, 0.40, 0.50, 0.60]

/// Peak signal-to-noise between the source buffer and a re-decoded encode.
/// Infinity for an identical buffer, which never happens with a lossy codec but
/// would otherwise print as a divide-by-zero.
func psnr(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return -1 }
    var sum = 0.0
    for i in 0..<a.count {
        let d = Double(a[i]) - Double(b[i])
        sum += d * d
    }
    let mse = sum / Double(a.count)
    return mse == 0 ? .infinity : 10 * log10(255 * 255 / mse)
}

/// Decode an encoded stream back to an 8-bit grey buffer of known size, so the
/// comparison is against pixels rather than against the encoder's own opinion.
func decodeGrey(_ data: Data, width: Int, height: Int) -> [UInt8]? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    var out = [UInt8](repeating: 0, count: width * height)
    out.withUnsafeMutableBytes { buf in
        guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return out
}

var totalJPEG = 0, pagesSeen = 0
var totalJPX = [Double: Int]()
var worstDelta = [Double: Double]()          // min(jpx PSNR - jpeg PSNR) per rate
for q in candidates { totalJPX[q] = 0; worstDelta[q] = .infinity }

print("file\tpage\tpx\tjpegKB\tjpegPSNR\t" +
      candidates.map { String(format: "q%.2fKB\tq%.2fdB", $0, $0) }.joined(separator: "\t"))

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let doc = Flattener.open(url, password: nil) else { continue }
    // Sample rather than sweep: the corpus is 232 documents and the point is the
    // distribution of picture pages, not every one of them.
    let idx = doc.pageCount <= 6
        ? Array(0..<doc.pageCount)
        : [1, doc.pageCount / 3, doc.pageCount / 2, doc.pageCount * 3 / 4]
    for i in idx {
        guard let page = doc.page(at: i) else { continue }
        let box = Flattener.fullBox(of: page)
        let scale = Flattener.rebuildDPI(of: page) / 72.0
        let wide = (box.width * scale).rounded(), high = (box.height * scale).rounded()
        guard wide.isFinite, high.isFinite, wide >= 1, high >= 1,
              wide * high <= Double(Flattener.maximumPageMegapixels) * 1_000_000
        else { continue }
        let w = max(Int(wide), 1), h = max(Int(high), 1)
        guard let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                              width: w, height: h, from: .mediaBox)
        else { continue }

        // Only the pages that actually take this route. A text page would be
        // 1-bit and its codec cost is not the question.
        let threshold = Flattener.otsuThreshold(of: grey)
        let sat = Flattener.saturation(of: page)
        guard Flattener.isPicture(page, grey: grey, width: w, height: h,
                                  threshold: threshold, saturation: sat),
              !Flattener.shouldKeepColour(mode: .auto, saturation: sat,
                                          pixels: wide * high)
        else { continue }

        guard let jpeg = Flattener.jpegData(from: grey, width: w, height: h,
                                            quality: Flattener.pictureJPEGQuality),
              let jpegBack = decodeGrey(jpeg, width: w, height: h)
        else { continue }
        let jpegPSNR = psnr(grey, jpegBack)
        totalJPEG += jpeg.count; pagesSeen += 1

        var cells: [String] = []
        for q in candidates {
            guard let jpx = jpxData(from: grey, width: w, height: h, quality: q),
                  let back = decodeGrey(jpx, width: w, height: h) else {
                cells.append("-\t-"); continue
            }
            let p = psnr(grey, back)
            totalJPX[q]! += jpx.count
            worstDelta[q] = min(worstDelta[q]!, p - jpegPSNR)
            cells.append(String(format: "%d\t%.2f", jpx.count / 1024, p))
        }
        print("\(url.lastPathComponent)\t\(i + 1)\t\(w)x\(h)\t\(jpeg.count / 1024)"
              + String(format: "\t%.2f\t", jpegPSNR) + cells.joined(separator: "\t"))
        fflush(stdout)
    }
}

print("\n=== \(pagesSeen) picture pages ===")
guard pagesSeen > 0 else { exit(0) }
print(String(format: "JPEG @%.2f: %d KB total, %d KB/page",
             Flattener.pictureJPEGQuality, totalJPEG / 1024, totalJPEG / 1024 / pagesSeen))
for q in candidates {
    // The worst page is what the constant has to satisfy, not the average: an
    // average that clears the bar while one plate falls below it is exactly the
    // silent degradation this is meant to rule out.
    print(String(format: "JPX  @%.2f: %d KB total, %d KB/page, %.2fx smaller, worst page %+.2f dB vs JPEG%@",
                 q, totalJPX[q]! / 1024, totalJPX[q]! / 1024 / pagesSeen,
                 Double(totalJPEG) / Double(max(totalJPX[q]!, 1)),
                 worstDelta[q]!, worstDelta[q]! >= 0 ? "  <- no page worse" : ""))
}
