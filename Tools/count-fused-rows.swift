// Counts the lines of a published page's text layer that join text from two printed columns,
// through PDFKit (C41's fused rows; `ocr-requeue`, 2026-10-14).
// usage: swiftc -O -o /tmp/cfr Tools/count-fused-rows.swift
//        /tmp/cfr <source.pdf> <published.pdf> [page=1] [examples=0; over 100 also prints the words]
// A line is PDFKit's characters between two line breaks of `page.string`. It crosses a gutter of
// the SOURCE when, 2.5 rows in from both its ends, columns of the source's 150 dpi render are paper
// (under 1/25 of their pixels inked, or a thin printed rule between paper) over the line and four
// rows above and below, at least half a row wide. It JOINS two columns when Vision, reading the
// source a quarter page either side of that gutter over the line's height, finds some of the
// line's words (4+ letters, near matches allowed) only on the left and some only on the right. A joined line is ONE RUN when the layer's letters run
// through the gutter (their gap there under half its width: one drawn run spans it, checked
// against the content stream on Kalispell), else TWO RUNS that PDFKit groups on one line.
// Prints `lines= joined= oneRun= twoRuns= crossNotJoined=`; CFR_DEBUG=<text> prints the column
// profile of the line holding <text>. A lower bound: a gutter narrower than half a row, or flecked
// with ink, is missed (Billings 1926's `Dr: Nich-lour inothers`, an 11 px gutter at 150 dpi).
import Foundation
import PDFKit
import CoreGraphics
import Vision

// Vision's reading of a part of the source page given as fractions, top-left origin, at 300 dpi
func read(_ fx0: CGFloat, _ fy0: CGFloat, _ fx1: CGFloat, _ fy1: CGFloat) -> String {
    autoreleasepool {
        let s: CGFloat = 300.0 / 72.0
        let rw = Int((fx1 - fx0) * sb.width * s), rh = Int((fy1 - fy0) * sb.height * s)
        guard rw > 8, rh > 8,
              let ctx = CGContext(data: nil, width: rw, height: rh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return "" }
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: rw, height: rh))
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -(sb.minX + fx0 * sb.width), y: -(sb.minY + (1 - fy1) * sb.height))
        sp.draw(with: .cropBox, to: ctx)
        guard let img = ctx.makeImage() else { return "" }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: img).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
}
// a word of the layer found among the source's, allowing the layer's misreads: 2 x the longest
// common subsequence over both lengths at least 0.75 (`inothers` for `mothers`)
func near(_ w: String, _ set: Set<String>) -> Bool {
    if set.contains(w) { return true }
    let a = Array(w)
    return set.contains { s in
        let b = Array(s)
        guard b.count >= 3, abs(a.count - b.count) <= a.count / 2 + 1 else { return false }
        return 2 * found(a, in: b) * Double(a.count) / Double(a.count + b.count) >= 0.75
    }
}
func letters(_ s: String) -> [Character] { s.lowercased().filter { $0.isLetter } }
// how much of `a` is found in order in `b`: the longest common subsequence over a's length
func found(_ a: [Character], in b: [Character]) -> Double {
    guard !a.isEmpty, !b.isEmpty else { return 0 }
    var prev = [Int](repeating: 0, count: b.count + 1)
    for x in a {
        var cur = [Int](repeating: 0, count: b.count + 1)
        for (j, y) in b.enumerated() { cur[j + 1] = x == y ? prev[j] + 1 : max(prev[j + 1], cur[j]) }
        prev = cur
    }
    return Double(prev[b.count]) / Double(a.count)
}

let a = CommandLine.arguments
guard a.count >= 3, let src = PDFDocument(url: URL(fileURLWithPath: a[1])),
      let pub = PDFDocument(url: URL(fileURLWithPath: a[2])) else { print("usage"); exit(2) }
let pageNo = a.count > 3 ? Int(a[3])! : 1
let examples = a.count > 4 ? Int(a[4])! : 0
let sp = src.page(at: pageNo - 1)!, pp = pub.page(at: pageNo - 1)!
let sb = sp.bounds(for: .cropBox), pb = pp.bounds(for: .cropBox)

// the source rendered at 150 dpi, grey
let scale: CGFloat = 150.0 / 72.0
let W = Int(sb.width * scale), H = Int(sb.height * scale)
var px = [UInt8](repeating: 255, count: W * H)
px.withUnsafeMutableBytes { buf in
    let ctx = CGContext(data: buf.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.scaleBy(x: scale, y: scale)
    sp.draw(with: .cropBox, to: ctx)
}
// row 0 of the buffer is the top of the page
func ink(_ x: Int, _ y: Int) -> Bool { px[y * W + x] < 140 }

// a published-page rect (PDF points) to source pixels, by fractions of each crop box
func toPx(_ r: CGRect) -> (x0: Int, x1: Int, y0: Int, y1: Int) {
    let fx0 = (r.minX - pb.minX) / pb.width, fx1 = (r.maxX - pb.minX) / pb.width
    let fy0 = 1 - (r.maxY - pb.minY) / pb.height, fy1 = 1 - (r.minY - pb.minY) / pb.height
    return (Int(fx0 * CGFloat(W)), Int(fx1 * CGFloat(W)), Int(fy0 * CGFloat(H)), Int(fy1 * CGFloat(H)))
}

// characters with bounds, in PDFKit lines
struct Ch { let c: Character; let r: CGRect }
let text = pp.string ?? ""
var lines: [[Ch]] = [[]]
// `characterBounds(at:)` does not index `string` (measured: "Lou" placed 0.06 page left of its
// selection); a one-character selection does
let ns = text as NSString
for i in 0..<ns.length {
    let c = Character(ns.substring(with: NSRange(location: i, length: 1)))
    if c == "\n" || c == "\r" { lines.append([]); continue }
    guard let sel = pp.selection(for: NSRange(location: i, length: 1)) else { continue }
    let r = sel.bounds(for: pp)
    if r.width <= 0 { continue }
    lines[lines.count - 1].append(Ch(c: c, r: r))
}
// PDFKit's character bounds are each glyph's ink, a space's height 0, so a row's height is
// taken from its letters' widths: 1.4 times the median, about the line pitch of body type
func em(_ r: [Ch]) -> CGFloat {
    let w = r.filter { !$0.c.isWhitespace }.map { $0.r.width }.sorted()
    return w.isEmpty ? 4 : 1.4 * w[w.count / 2]
}
// PDFKit's lines, cut only where a line steps to another row
var rows: [[Ch]] = []
for line in lines where !line.isEmpty {
    let sorted = line.sorted { $0.r.midX < $1.r.midX }
    let h = em(sorted)
    var cur: [Ch] = []
    for ch in sorted {
        if let last = cur.last(where: { !$0.c.isWhitespace }), !ch.c.isWhitespace, abs(ch.r.midY - last.r.midY) > 0.8 * h {
            rows.append(cur); cur = []
        }
        cur.append(ch)
    }
    if !cur.isEmpty { rows.append(cur) }
}

var oneRun = 0, twoRuns = 0, judged = 0, unconfirmed = 0
var shown = 0
for row in rows {
    let s = String(row.map { $0.c }).trimmingCharacters(in: .whitespaces)
    guard s.count >= 6 else { continue }
    judged += 1
    let u = row.dropFirst().reduce(row[0].r) { $0.union($1.r) }
    let hPt = em(row)
    let p = toPx(u)
    let h = max(4, Int(hPt / pb.height * CGFloat(H)))
    let wy0 = max(0, p.y0 - 4 * h), wy1 = min(H - 1, p.y1 + 4 * h)
    let n = wy1 - wy0 + 1
    let lo = max(0, p.x0 + (5 * h) / 2), hi = min(W - 1, p.x1 - (5 * h) / 2)
    guard hi - lo > 0 else { continue }
    // per column: 0 blank, 1 solid (a rule's column), 2 other
    var kind = [Int](repeating: 2, count: hi - lo + 1)
    for x in lo...hi {
        var k = 0
        for y in wy0...wy1 where ink(x, y) { k += 1 }
        kind[x - lo] = k <= max(1, n / 25) ? 0 : (k * 10 >= n * 7 ? 1 : 2)
    }
    // gutters: runs of blank columns, with solid runs no wider than a fifth of a row between blanks
    var x = 0, gutters: [(Int, Int)] = []
    while x < kind.count {
        guard kind[x] != 2 else { x += 1; continue }
        var e = x, blank = 0, ok = true
        while e < kind.count && kind[e] != 2 {
            if kind[e] == 0 { blank += 1 } else {
                var r = e; while r < kind.count && kind[r] == 1 { r += 1 }
                if r - e > max(1, h / 5) { ok = false }
            }
            e += 1
        }
        if ok && e - x >= h / 2 && blank * 3 >= h / 2 { gutters.append((x + lo, e + lo)) }
        x = e
    }
    if let dbg = ProcessInfo.processInfo.environment["CFR_DEBUG"], s.contains(dbg) {
        var prof = ""
        for x in lo...hi { var k = 0; for y in wy0...wy1 where ink(x, y) { k += 1 }; prof += k <= max(1, n / 50) ? "." : (k * 10 >= n * 7 ? "|" : (k * 10 < n ? "," : "#")) }
        print("DEBUG h=\(h) n=\(n) x=\(lo)-\(hi) gutters=\(gutters)\n\(prof)")
    }
    guard !gutters.isEmpty else { continue }
    // joined when some of the line's words are read from the source only left of a gutter, and
    // some only right of it, a quarter page either side over the line's height
    let words = Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 })
    let fy0 = CGFloat(max(0, p.y0 - h)) / CGFloat(H), fy1 = CGFloat(min(H, p.y1 + h)) / CGFloat(H)
    func srcWords(_ x0: CGFloat, _ x1: CGFloat) -> Set<String> {
        Set(read(max(0, x0), fy0, min(1, x1), fy1).lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
    }
    var joined: (gx: CGFloat, gapPt: CGFloat, gutterPt: CGFloat, l: [String], r: [String])? = nil
    for g in gutters where words.count >= 2 {
        let gx = CGFloat(g.0 + g.1) / 2 / CGFloat(W)
        let L = srcWords(gx - 0.25, CGFloat(g.0) / CGFloat(W)), R = srcWords(CGFloat(g.1) / CGFloat(W), gx + 0.25)
        let onlyL = words.filter { near($0, L) && !near($0, R) }, onlyR = words.filter { near($0, R) && !near($0, L) }
        guard !onlyL.isEmpty, !onlyR.isEmpty else { continue }
        // the layer's own gap there, between letters: a run drawn across the gutter spreads its
        // letters through it; two runs leave the gutter's paper between them
        let gpt = pb.minX + gx * pb.width
        let ink = row.filter { !$0.c.isWhitespace }
        let leftEnd = ink.filter { $0.r.midX < gpt }.map { $0.r.maxX }.max() ?? gpt
        let rightStart = ink.filter { $0.r.midX >= gpt }.map { $0.r.minX }.min() ?? gpt
        joined = (gx, rightStart - leftEnd, CGFloat(g.1 - g.0) / CGFloat(W) * pb.width, onlyL.sorted(), onlyR.sorted())
        break
    }
    guard let j = joined else { unconfirmed += 1; continue }
    let single = j.gapPt < 0.5 * j.gutterPt
    if single { oneRun += 1 } else { twoRuns += 1 }
    if shown < examples {
        shown += 1
        if examples > 100 { print("   L \(j.l)  R \(j.r)") }
        print((single ? "ONE-RUN " : "TWO-RUNS") + String(format: " gap=%.1f gutter=%.1f y=%.3f x=%.3f-%.3f at=%.3f  ", j.gapPt, j.gutterPt,
              1 - (u.midY - pb.minY) / pb.height, (u.minX - pb.minX) / pb.width, (u.maxX - pb.minX) / pb.width, j.gx) + s)
    }
}
print("lines=\(judged) joined=\(oneRun + twoRuns) oneRun=\(oneRun) twoRuns=\(twoRuns) crossNotJoined=\(unconfirmed)")
