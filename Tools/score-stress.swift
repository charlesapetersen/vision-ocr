import PDFKit
import Foundation

// score-stress — one row per page of a published PDF, for `corpus-stress`.
//
//   score-stress <source.pdf> <output.pdf>        TSV rows on stdout, no header
//   score-stress --header                         the header line
//
// Reads only what a reader gets: the output through PDFKit (the lines a drag
// selection walks, as `pdfkit-lines` does) and the output's own pixels. Nothing
// here consults Vision's observations, so a line the app dropped cannot vanish
// from the measure along with the text.
//
// Columns, per page:
//   route       the output page's images, `filter/bpc` joined by `+`, `none` for
//               a page with no image (a born-digital page kept as it was)
//   lines chars PDFKit's selectable lines and characters
//   ink         share of the page's pixels that are ink (output, 100 dpi, lum < 128,
//               outer 3% of each side left out)
//   bare        share of that ink outside every selectable line's box
//   bareText    the same over ink in text-like 0.25 in cells only (ink density
//               0.02-0.40), so a photograph or a solid rule counts for little.
//               This is the "text not selectable" column; `bare` is its ceiling.
//   gutter      x of a blank vertical strip with ink on both sides, 25-75% of the
//               width, in points; `-` when the page has none or is rotated
//   cross       selectable lines whose box spans that gutter
//   flips       times consecutive lines in PDFKit's order change side of it
//   srcColour outColour  share of pixels with chroma > 60 (of 255), 50 dpi, in the
//               source and in the output; colour lost reads as srcColour >> outColour
//
// Blind spots, stated: `bareText` counts ink as covered when any line box sits over
// it, so a garbled line reads as covered; the gutter test finds at most one gutter;
// the chroma bar is above aged paper's tint (20-40) but below faint coloured ink.
//
// Build: swiftc -O -o /tmp/score-stress Tools/score-stress.swift
// Exit: 0 ok · 1 a PDF will not open · 2 usage.

let header = "page\troute\tlines\tchars\tink\tbare\tbareText\tgutter\tcross\tflips\tsrcColour\toutColour"

func fail(_ s: String, _ code: Int32) -> Never {
    FileHandle.standardError.write("score-stress: \(s)\n".data(using: .utf8)!)
    exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())
if args == ["--header"] { print(header); exit(0) }
guard args.count == 2 else { fail("usage: score-stress <source.pdf> <output.pdf> | --header", 2) }
guard let src = PDFDocument(url: URL(fileURLWithPath: args[0])) else { fail("cannot open \(args[0])", 1) }
guard let out = PDFDocument(url: URL(fileURLWithPath: args[1])) else { fail("cannot open \(args[1])", 1) }

/// The page's images as `filter/bpc`, sorted, including those inside form XObjects.
func route(_ page: CGPDFPage) -> String {
    guard let dict = page.dictionary else { return "?" }
    var found: [String] = []
    images(in: dict, into: &found, depth: 0)
    return found.isEmpty ? "none" : found.sorted().joined(separator: "+")
}

func images(in owner: CGPDFDictionaryRef, into found: inout [String], depth: Int) {
    guard depth < 4 else { return }
    var res: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(owner, "Resources", &res), let res else { return }
    var xobjs: CGPDFDictionaryRef?
    guard CGPDFDictionaryGetDictionary(res, "XObject", &xobjs), let xobjs else { return }
    var local: [String] = []
    CGPDFDictionaryApplyBlock(xobjs, { _, obj, _ in
        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(obj, .stream, &stream), let stream,
              let sd = CGPDFStreamGetDictionary(stream) else { return true }
        var sub: UnsafePointer<Int8>?
        guard CGPDFDictionaryGetName(sd, "Subtype", &sub), let sub else { return true }
        if String(cString: sub) == "Form" {
            images(in: sd, into: &local, depth: depth + 1)
            return true
        }
        guard String(cString: sub) == "Image" else { return true }
        var filter = "raw"
        var name: UnsafePointer<Int8>?
        var arr: CGPDFArrayRef?
        if CGPDFDictionaryGetName(sd, "Filter", &name), let name {
            filter = String(cString: name)
        } else if CGPDFDictionaryGetArray(sd, "Filter", &arr), let arr, CGPDFArrayGetCount(arr) > 0,
                  CGPDFArrayGetName(arr, CGPDFArrayGetCount(arr) - 1, &name), let name {
            filter = String(cString: name)
        }
        var bpc: CGPDFInteger = 0
        _ = CGPDFDictionaryGetInteger(sd, "BitsPerComponent", &bpc)
        var mask = false
        _ = CGPDFDictionaryGetBoolean(sd, "ImageMask", &mask)
        local.append("\(filter.replacingOccurrences(of: "Decode", with: ""))/\(mask ? 1 : Int(bpc))")
        return true
    }, nil)
    found += local
}

/// RGBA pixels of a page in unrotated page space, row 0 at the top.
func render(_ page: CGPDFPage, dpi: CGFloat) -> (px: [UInt8], w: Int, h: Int, box: CGRect)? {
    let box = page.getBoxRect(.mediaBox)
    let s = dpi / 72
    let w = max(1, Int(box.width * s)), h = max(1, Int(box.height * s))
    guard w * h < 60_000_000 else { return nil }
    var px = [UInt8](repeating: 255, count: w * h * 4)
    let ok = px.withUnsafeMutableBytes { buf -> Bool in
        guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        return true
    }
    return ok ? (px, w, h, box) : nil
}

func colourShare(_ page: CGPDFPage) -> Double {
    guard let r = render(page, dpi: 50) else { return -1 }
    var n = 0
    for i in stride(from: 0, to: r.px.count, by: 4) {
        let a = r.px[i], b = r.px[i + 1], c = r.px[i + 2]
        if Int(max(a, b, c)) - Int(min(a, b, c)) > 60 { n += 1 }
    }
    return Double(n) / Double(r.w * r.h)
}

func f(_ x: Double) -> String { String(format: "%.4f", x) }

/// `STRESS_OVERLAY=<dir>` writes each page as a PNG: the render, with line boxes
/// tinted blue and ink outside them painted red. For looking, not for measuring.
func overlay(_ px: [UInt8], ink: [Bool], covered: [Bool], w: Int, h: Int, to url: URL) {
    var o = px
    for p in 0..<(w * h) {
        if ink[p] && !covered[p] { o[p * 4] = 255; o[p * 4 + 1] = 0; o[p * 4 + 2] = 0 }
        else if covered[p] && !ink[p] { o[p * 4] = o[p * 4] / 4 * 3; o[p * 4 + 1] = o[p * 4 + 1] / 4 * 3 }
    }
    o.withUnsafeMutableBytes { buf in
        guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let img = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}

for i in 0..<out.pageCount {
    guard let page = out.page(at: i), let cg = page.pageRef else { continue }
    let rotated = page.rotation % 180 != 0
    let lines = (page.selection(for: page.bounds(for: .mediaBox))?.selectionsByLine() ?? [])
        .map { ($0.bounds(for: page), ($0.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) }
        .filter { !$0.1.isEmpty }
    let chars = lines.reduce(0) { $0 + $1.1.count }
    var cols = [route(cg), "\(lines.count)", "\(chars)"]

    if let r = render(cg, dpi: 100) {
        let s = 100.0 / 72
        var ink = [Bool](repeating: false, count: r.w * r.h)
        var inkN = 0
        // The outer 3% on each side is left out: scan borders and gutter shadow
        // are dense black there and are never text a reader wants.
        let mx = r.w * 3 / 100, my = r.h * 3 / 100
        for y in my..<(r.h - my) {
            for x in mx..<(r.w - mx) {
                let o = (y * r.w + x) * 4
                let lum = (299 * Int(r.px[o]) + 587 * Int(r.px[o + 1]) + 114 * Int(r.px[o + 2])) / 1000
                if lum < 128 { ink[y * r.w + x] = true; inkN += 1 }
            }
        }
        // Line boxes in pixels, padded by half the line's height on every side:
        // the writer sizes a run to its line pitch, not to the glyphs' extent, so
        // ascenders and descenders stand outside a tight box.
        var covered = [Bool](repeating: false, count: r.w * r.h)
        for (b, _) in lines {
            let pad = b.height
            let x0 = max(0, Int((b.minX - r.box.minX - pad / 2) * s))
            let x1 = min(r.w, Int((b.maxX - r.box.minX + pad / 2) * s) + 1)
            let y0 = max(0, Int((r.box.maxY - b.maxY - pad / 2) * s))
            let y1 = min(r.h, Int((r.box.maxY - b.minY + pad / 2) * s) + 1)
            guard x0 < x1, y0 < y1 else { continue }
            for y in y0..<y1 { for x in x0..<x1 { covered[y * r.w + x] = true } }
        }
        var bare = 0
        for p in 0..<(r.w * r.h) where ink[p] && !covered[p] { bare += 1 }
        if let dir = ProcessInfo.processInfo.environment["STRESS_OVERLAY"] {
            overlay(r.px, ink: ink, covered: covered, w: r.w, h: r.h,
                    to: URL(fileURLWithPath: dir).appendingPathComponent("p\(i + 1).png"))
        }
        let cell = 25
        var textInk = 0, textBare = 0
        for cy in stride(from: 0, to: r.h, by: cell) {
            for cx in stride(from: 0, to: r.w, by: cell) {
                var n = 0, nb = 0, area = 0
                for y in cy..<min(r.h, cy + cell) {
                    for x in cx..<min(r.w, cx + cell) {
                        area += 1
                        let p = y * r.w + x
                        if ink[p] { n += 1; if !covered[p] { nb += 1 } }
                    }
                }
                let d = Double(n) / Double(area)
                if d > 0.02 && d < 0.40 { textInk += n; textBare += nb }
            }
        }
        cols += [f(Double(inkN) / Double(r.w * r.h)),
                 f(inkN > 0 ? Double(bare) / Double(inkN) : 0),
                 f(textInk > 0 ? Double(textBare) / Double(textInk) : 0)]

        // A gutter: the widest run of columns, 25-75% across, with ink in at most
        // 0.5% of the rows between the page's first and last inked rows, at least
        // 0.15 in wide, with inked columns on both sides.
        var gutterX: Double? = nil
        if !rotated, inkN > 0 {
            var top = r.h, bottom = 0
            var colInk = [Int](repeating: 0, count: r.w)
            for y in 0..<r.h { for x in 0..<r.w where ink[y * r.w + x] {
                colInk[x] += 1; top = min(top, y); bottom = max(bottom, y) } }
            let span = max(1, bottom - top)
            let empty = { (x: Int) in Double(colInk[x]) <= 0.005 * Double(span) }
            var best = (start: 0, len: 0), run = 0
            for x in (r.w / 4)..<(3 * r.w / 4) {
                run = empty(x) ? run + 1 : 0
                if run > best.len { best = (x - run + 1, run) }
            }
            let leftInk = colInk[0..<best.start].reduce(0, +)
            let rightInk = colInk[min(r.w, best.start + best.len)...].reduce(0, +)
            if best.len >= 15, leftInk > inkN / 10, rightInk > inkN / 10 {
                gutterX = r.box.minX + (Double(best.start) + Double(best.len) / 2) / s
            }
        }
        if let g = gutterX {
            let cross = lines.filter { $0.0.minX < g - 4 && $0.0.maxX > g + 4 }.count
            var flips = 0
            var last: Bool? = nil
            for (b, _) in lines where !(b.minX < g - 4 && b.maxX > g + 4) {
                let left = b.midX < g
                if let l = last, l != left { flips += 1 }
                last = left
            }
            cols += [String(format: "%.0f", g), "\(cross)", "\(flips)"]
        } else {
            cols += ["-", "-", "-"]
        }
    } else {
        cols += ["-", "-", "-", "-", "-", "-"]
    }
    let sc = src.page(at: i)?.pageRef.map(colourShare) ?? -1
    cols += [f(sc), f(colourShare(cg))]
    print("\(i + 1)\t" + cols.joined(separator: "\t"))
    fflush(stdout)
}
if src.pageCount != out.pageCount {
    FileHandle.standardError.write("score-stress: page count \(src.pageCount) -> \(out.pageCount)\n"
        .data(using: .utf8)!)
}
