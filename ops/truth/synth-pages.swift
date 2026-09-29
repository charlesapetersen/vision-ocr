import Foundation
import CoreText
import CoreGraphics
// synth-pages <outdir>
// Writes truth-calibrate's synthetic born-digital pages: <layout>-<seed>.pdf, one US-letter page each,
// and beside it <layout>-<seed>.txt holding exactly the words drawn, in reading order. The testdocs
// corpus holds only two born-digital documents (9 pages), so these make up the ~30 the item asks for.
// Words come from /usr/share/dict, so the text has no sense to lean on: a conservative test of the reader.
let out = CommandLine.arguments.count == 2 ? CommandLine.arguments[1] : { print("usage: synth-pages <outdir>"); exit(2) }()

struct RNG { var s: UInt64; mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) } }
func words(_ f: String) -> [String] {
    ((try? String(contentsOfFile: f, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
}
let common = words("/usr/share/dict/connectives")
let web2 = words("/usr/share/dict/web2").filter { $0.count >= 3 && $0.count <= 8 && $0.first!.isLowercase }
let names = words("/usr/share/dict/propernames")

func prose(_ r: inout RNG, _ n: Int) -> String {
    var o: [String] = [], start = true
    for _ in 0..<n {
        var w: String
        switch r.int(10) {
        case 0...4: w = common[r.int(common.count)]
        case 5...8: w = web2[r.int(web2.count)]
        default: w = r.int(2) == 0 ? names[r.int(names.count)] : String(r.int(2000) + 1)
        }
        if start { w = w.prefix(1).uppercased() + w.dropFirst(); start = false }
        switch r.int(14) { case 0: w += ","; case 1: w += "."; start = true; case 2: w += ";"; default: break }
        o.append(w)
    }
    return o.joined(separator: " ") + "."
}
func attr(_ s: String, _ size: CGFloat) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("Times New Roman" as CFString, size, nil)])
}
/// Fills `rect` with prose at `size`, draws it, and returns the words that fit.
func column(_ ctx: CGContext, _ rect: CGRect, _ size: CGFloat, _ r: inout RNG) -> String {
    let s = attr(prose(&r, 900), size)
    let fs = CTFramesetterCreateWithAttributedString(s)
    let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
    CTFrameDraw(frame, ctx)
    let vis = CTFrameGetVisibleStringRange(frame)
    return (s.string as NSString).substring(with: NSRange(location: vis.location, length: vis.length))
}
func line(_ ctx: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat) {
    ctx.textPosition = CGPoint(x: x, y: y); CTLineDraw(CTLineCreateWithAttributedString(attr(s, size)), ctx)
}

let W: CGFloat = 612, H: CGFloat = 792, M: CGFloat = 60
let layouts = ["one", "two", "three", "table", "foot", "small"]
for layout in layouts {
    for seed in 1...4 {
        var r = RNG(s: UInt64(seed * 7919 + layouts.firstIndex(of: layout)! * 104729))
        let name = "\(out)/\(layout)-\(seed)"
        var box = CGRect(x: 0, y: 0, width: W, height: H)
        let ctx = CGContext(URL(fileURLWithPath: name + ".pdf") as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        var truth: [String] = []
        let body = CGRect(x: M, y: M, width: W - 2 * M, height: H - 2 * M)
        switch layout {
        case "one": truth.append(column(ctx, body, 11, &r))
        case "small": truth.append(column(ctx, body, 6.5, &r))
        case "two", "three":
            let n: CGFloat = layout == "two" ? 2 : 3, gap: CGFloat = 18
            let cw = (body.width - gap * (n - 1)) / n
            for i in 0..<Int(n) {
                truth.append(column(ctx, CGRect(x: body.minX + CGFloat(i) * (cw + gap), y: body.minY, width: cw, height: body.height),
                                    layout == "two" ? 10 : 8, &r))
            }
        case "foot":
            let notes = CGRect(x: body.minX, y: body.minY, width: body.width, height: 120)
            let main = CGRect(x: body.minX, y: notes.maxY + 20, width: body.width, height: body.height - 140)
            truth.append(column(ctx, main, 11, &r))
            ctx.move(to: CGPoint(x: body.minX, y: notes.maxY + 8)); ctx.addLine(to: CGPoint(x: body.minX + 150, y: notes.maxY + 8))
            ctx.setLineWidth(0.5); ctx.strokePath()
            var fn: [String] = []
            for k in 1...4 { fn.append("\(k) " + prose(&r, 28)) }
            let fs = CTFramesetterCreateWithAttributedString(attr(fn.joined(separator: "\n"), 7))
            let frame = CTFramesetterCreateFrame(fs, CFRange(location: 0, length: 0), CGPath(rect: notes, transform: nil), nil)
            CTFrameDraw(frame, ctx)
            let vis = CTFrameGetVisibleStringRange(frame)
            truth.append((fn.joined(separator: "\n") as NSString).substring(with: NSRange(location: vis.location, length: vis.length)))
        default: // table: a caption, a header row, 30 rows of a label and five figures
            var y = H - M - 12
            let cap = "Table \(seed + 1). " + prose(&r, 9)
            line(ctx, cap, M, y, 10); truth.append(cap); y -= 24
            let xs: [CGFloat] = [M, M + 170, M + 240, M + 310, M + 380, M + 450]
            let head = ["Item", "1931", "1932", "1933", "1934", "Total"]
            for (i, h) in head.enumerated() { line(ctx, h, xs[i], y, 9) }
            truth.append(head.joined(separator: " ")); y -= 6
            ctx.move(to: CGPoint(x: M, y: y)); ctx.addLine(to: CGPoint(x: W - M, y: y)); ctx.setLineWidth(0.5); ctx.strokePath(); y -= 14
            for _ in 0..<30 {
                var row = [web2[r.int(web2.count)].capitalized + " " + common[r.int(common.count)]]
                for _ in 0..<5 { row.append(r.int(3) == 0 ? String(format: "%.1f", Double(r.int(10000)) / 10) : String(r.int(90000) + 100)) }
                for (i, c) in row.enumerated() { line(ctx, c, xs[i], y, 9) }
                truth.append(row.joined(separator: " ")); y -= 17
            }
        }
        ctx.endPDFPage(); ctx.closePDF()
        try! truth.joined(separator: "\n").write(toFile: name + ".txt", atomically: true, encoding: .utf8)
    }
}
print("wrote \(layouts.count * 4) pages to \(out)")
