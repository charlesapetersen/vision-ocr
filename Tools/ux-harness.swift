import PDFKit
import Vision
import AppKit
import Foundation

// ux-harness — a published PDF against its source, measured the way a reader meets it in Preview.
//
//   ux-harness <source.pdf> <output.pdf> <outdir> [pages=all]   pages: `5`, `5-6`, `1,3,5-7`
//   ux-harness --header                                          the two header lines
//
// PDFKit and CoreGraphics are the only renderers and text readers here. Poppler is not evidence of what
// Preview shows (BUGS.md C38: C31 was closed on a poppler render). Every page is drawn with
// `PDFPage.draw(with: .cropBox, to:)`, and the reference for what the page SAYS is Vision reading the
// SOURCE's render at 3x (216 dpi), whole and in overlapping bands, never the output's text layer, so a line the app dropped cannot vanish
// from the reference along with the text.
//
// Writes `<outdir>/pages.tsv` and `<outdir>/document.tsv` (header plus rows, also printed on stdout), and
// the renders as `<outdir>/renders/p<N>-{src,out}-{1x,2x}.png` so any page can be looked at.
//
// Per page (`pages.tsv`); a column is `-` when the page has too little text for it to mean anything:
//   refWords   words Vision reads in the source at 3x: the reference
//   leg1 leg2  legibility. Of the reference words, how many Vision reads in the OUTPUT's render at 1x (2x),
//              divided by how many it reads in the SOURCE's render at the same scale. 1.00 = as legible.
//   inkRatio   pixels darker than 128 at 2x, output over source: strokes as solid as the source's
//   inkLum     mean luminance of those pixels, output minus source: positive = greyer strokes
//   srcCol     share of the source's 1x pixels that are coloured (chroma > 60 of 255)
//   colKept    of those pixels, the share still coloured (chroma > 30) in the output, allowing 1 px of shift
//   find       of up to 30 reference words (5+ letters), the share `PDFDocument.findString` finds on this
//              page with a hit whose bounds lie over that word in the source
//   cols       columns: chains of 5+ reference lines, each over the next
//   inside     worst column: share of the drag's selected area inside the column (column drag leaks out)
//   cover      worst column: share of the column's lines the drag selects
//   overInk    worst column: share of the drag's line boxes that lie over a reference line
//   prec recall  worst column: share of the copy's words that a reading of the page (the source's three,
//              or either document's 1x/2x render) reads at that line's place / share of the words two
//              source readings agree on in the column that the copy has
//   wer        word error rate of the drags' `string` against the reference lines in each column, over all
//              columns; each column against the best of Vision's readings of the source at 2x, 3x and 4x
//   splits welds  words split by a stray space / two reference words welded into one, in the drags' text
//   echoes     a word followed by its own tail, "practices tices": a line-end hyphenation written whole on
//              the first line with the continuation kept on the next
//   hyph       line-end hyphens in the reference kept as "xx- yy" in the copy (join missed), of all seen
//   midBreaks  line breaks inside a sentence in the copy, over all line breaks
//   geom       `ok`; `size` when the displayed page (crop box, rotation applied) differs from the source's,
//              which is red; `rotation` (/Rotate differs) and `origin` (a box moved), which are not
//   msSrc msOut  PDFKit render time at 1x, milliseconds
//   flags      the red reasons, `-` when green
//
// A page is red when (thresholds set on the owner's reports and the green sample, `Tools/ux-harness-selftest.sh`):
//   legibility  leg1 or leg2 < 0.75                   faint     inkRatio < 0.60 or inkLum > 40
//   colour      srcCol >= 0.0005 and colKept < 0.50    find      find < 0.80
//   selection   inside < 0.90 or cover < 0.90 or overInk < 0.80
//   copy        prec < 0.80                            geometry  the displayed page's size
//   unmeasured  a Vision request failed on one of the page's renders
// `wer` and `recall` are reported and never red: against a reference read by Vision they are noisy
// (good pages read 0.02-0.30 and 0.84-0.98). `prec` put Raskin at 24a8f6a at 0.63 and every green page
// at 0.89 or more; the owner's other reports are drags that leave their column, and `inside` has them.
//
// Per document (`document.tsv`): pages, bytes, open time, whether PDFDocument opens and `qpdf --check`
// is clean, outline entries, page labels, links, other annotations and the document title, each output
// against source. Red: `open`, `qpdf`, `pages`, `outline`, `labels`, `links`, `annots`, `title`.
//
// Blind spots, stated: the reference is Vision's reading of the source, so a word Vision misreads in the
// source is a "miss" in every column; columns are found only where Vision read 5+ stacked lines, and a
// page with `cols` 0 has had neither selection nor copy measured, whatever its flags say; a real
// compound's hyphen joined away ("well- known" copied "wellknown") is not told from a right join; the
// legibility proxy is a machine reader, and a person reads worse type than Vision does at 1x.
//
// Cost: about 8 s a page on an M-series Mac, nearly all of it seven Vision readings (three of the source,
// banded, for the reference; four of the 1x/2x renders). A corpus run wants a page sample per document.
// `findString` searches the whole document once per sampled word, so long documents cost more.
// UX_VERBOSE=1 prints each column's drag, the lines it missed or took from outside, the reference and
// copied words, and each Find miss, on stderr. UX_REFSCALE sets the reference render's scale (default 3).
//
// --truth <dir>: also score the page against the truth set (`ops/truth/procedure.md`), where `<dir>` is a
// document's directory under `$STATE/truth/` holding `p<N>/transcript.txt`; pages without one are not
// scored. Each such page prints a `TRUTH` row after its own and writes `<outdir>/truth.tsv`:
//   trWords contested scored  the transcript's words (line-end hyphens joined), those not scored (contested
//              by the check, the second reader or the re-read of `truth-words.tsv`, or `[?]`), and the body
//              words scored
//   right wrong missing added  a drag down each of the transcript's COLUMNS (3+ body lines), from its first
//              line's start to its last line's end, and each other body line's own box, aligned word by word
//              with the transcript; contested words and figure text in a column are free either way
//   splits welds hyph  words split by a stray space, two words welded, a line-end hyphen the copy did not join
//   copyErr    (wrong + missing + added) / scored          find  of up to 30 transcript words (5+ letters)
//              the share `findString` finds with a hit over the word on this page; the sample is fixed by the
//              transcript, so the re-read's contested words drop out of it without moving the others, and a
//              word with punctuation inside it is not searched
//   order      of adjacent columns, how many follow each other in the page's text layer; reported, never
//              red: a footnote at a column's foot is read before or after the next column (Hughes p2)
//   fig hand   figure text and handwriting, apart: words a selection over each line holds, of all
//   visMiss    share of the scored words missing from Vision's reading of the source (the page's
//              `vision.txt`, a plain render); layerMiss  the same for the output's whole text layer
//   pairs      crop pairs written: the page at 1x, and each OBJECTS element at 2x, as `pairs/p<N>-<k>-A.png`
//              and `-B.png`, output and source in an order `pairs-key.tsv` (outside `pairs/`) holds and the judge is not told;
//              `pairs/p<N>-elements.txt` is the judge's checklist. A Swift tool cannot call a model: the
//              session gives each page's pairs to a judge subagent.
//   elInk elCol  of the OBJECTS elements whose source box holds 50+ dark (luminance < 128) or coloured
//              pixels at 2x, the least share of them the output keeps: no model, so the same every run
//   tflags     `tcopy` copyErr > 0.05, `tfind` find < 0.80, `tink` elInk < 0.50, `tcolour` elCol < 0.50
//              (set on `Tools/ux-harness-selftest.sh`'s pages)
// `truth-words.tsv` lists every wrong, missing and unfound word with its box in the transcript's pixels,
// for the blind re-read on a tight crop that must confirm a word before it counts against the app
// (`ops/truth/reread.py`; a word it does not confirm goes into `contested-harness.tsv`).
// Blind spots: the transcript's boxes are the reader's estimates, and a word's box is estimated from its
// character offset; a copy that joins a real compound split at a line end is scored right.
//
// Build: swiftc -O -o /tmp/ux-harness Tools/ux-harness.swift
// Self-test: Tools/ux-harness-selftest.sh (the owner's reports go red, a sample of good pages stays green)
// Exit: 0 every page and the document green (and, with --truth, every TRUTH row) · 1 something red ·
// 2 usage or a PDF will not open.

let pageHeader = "page\trefWords\tleg1\tleg2\tinkRatio\tinkLum\tsrcCol\tcolKept\tfind\tcols\tinside\tcover\toverInk\twer\tprec\trecall\tsplits\twelds\techoes\thyph\tmidBreaks\tgeom\tmsSrc\tmsOut\tflags"
let docHeader = "pages\tbytes\topenMs\topen\tqpdf\toutline\tlabels\tlinks\tannots\ttitle\tflags"
let truthHeader = "page\ttrWords\tcontested\tscored\tright\twrong\tmissing\tadded\tsplits\twelds\thyph\tcopyErr\tfind\torder\tfig\thand\tvisMiss\tlayerMiss\tpairs\telInk\telCol\ttflags"

func fail(_ s: String, _ code: Int32) -> Never {
    FileHandle.standardError.write("ux-harness: \(s)\n".data(using: .utf8)!)
    exit(code)
}

var args = CommandLine.arguments
if args.count == 2 && args[1] == "--header" { print(pageHeader); print(docHeader); exit(0) }
var truthDir: URL? = nil
if let k = args.firstIndex(of: "--truth") {
    guard k + 1 < args.count else { fail("--truth needs a directory", 2) }
    truthDir = URL(fileURLWithPath: args[k + 1])
    guard FileManager.default.fileExists(atPath: truthDir!.path) else { fail("no truth directory \(args[k + 1])", 2) }
    args.removeSubrange(k...(k + 1))
}
guard args.count >= 4 else {
    fail("usage: ux-harness [--truth <dir>] <source.pdf> <output.pdf> <outdir> [pages]  |  ux-harness --header", 2)
}
let srcURL = URL(fileURLWithPath: args[1]), outURL = URL(fileURLWithPath: args[2])
let outDir = URL(fileURLWithPath: args[3])
let verbose = ProcessInfo.processInfo.environment["UX_VERBOSE"] == "1"   // per-column detail on stderr
let refScale = CGFloat(Double(ProcessInfo.processInfo.environment["UX_REFSCALE"] ?? "") ?? 3)
try? FileManager.default.createDirectory(at: outDir.appendingPathComponent("renders"), withIntermediateDirectories: true)

// MARK: - Rendering, as Preview draws

struct Raster {
    let w: Int, h: Int
    let px: [UInt8]   // RGBA
    func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {   // y from the top
        let i = (y * w + x) * 4
        return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]))
    }
}

func displaySize(_ page: PDFPage) -> CGSize {
    let b = page.bounds(for: .cropBox)
    return (page.rotation % 180 == 0) ? b.size : CGSize(width: b.height, height: b.width)
}

func render(_ page: PDFPage, scale: CGFloat) -> (CGImage, Raster, Double) {
    let size = displaySize(page)
    let W = max(1, Int((size.width * scale).rounded())), H = max(1, Int((size.height * scale).rounded()))
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    ctx.scaleBy(x: scale, y: scale)
    let t0 = Date()
    page.draw(with: .cropBox, to: ctx)
    let ms = Date().timeIntervalSince(t0) * 1000
    let img = ctx.makeImage()!
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let px = Array(UnsafeBufferPointer(start: data, count: W * H * 4))
    return (img, Raster(w: W, h: H, px: px), ms)
}

func savePNG(_ img: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    if let d = rep.representation(using: .png, properties: [:]) {
        try? d.write(to: outDir.appendingPathComponent("renders").appendingPathComponent(name))
    }
}

// MARK: - Reading, with Vision

struct Word { let text: String; let box: CGRect }          // box normalised, origin bottom-left
struct Line { let words: [Word]; let box: CGRect; let text: String }

/// Vision over the whole image, then over overlapping horizontal bands, keeping every whole-image line and
/// each band line that does not overlap one already kept. A whole-page request drops clean blocks of type
/// on these scans (BUGS.md C30); a reference with holes in it would count the copy's words as invented.
/// Bands of 600 px advancing by 400: at 3x a line is 20-40 px, so every line lies whole inside some band.
func readBanded(_ img: CGImage) -> [Line]? {
    guard var kept = read(img) else { return nil }
    let H = img.height, W = img.width
    guard H > 900 else { return kept }
    var y0 = 0
    while y0 < H {
        let y1 = min(H, y0 + 600)
        if let band = img.cropping(to: CGRect(x: 0, y: y0, width: W, height: y1 - y0)) {
            let fy = CGFloat(H - y1) / CGFloat(H), fh = CGFloat(y1 - y0) / CGFloat(H)
            func up(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: fy + r.minY * fh, width: r.width, height: r.height * fh) }
            guard let lines = read(band) else { return nil }
            let bandH = CGFloat(y1 - y0)
            for l in lines {
                // a line the band's inner edge cuts is read in part; the next band reads it whole
                if y0 > 0, (1 - l.box.maxY) * bandH < 15 { continue }
                if y1 < H, l.box.minY * bandH < 15 { continue }
                let box = up(l.box)
                let clash = kept.contains { k in
                    let i = k.box.intersection(box)
                    return !i.isNull && i.width * i.height > 0.3 * min(k.box.width * k.box.height, box.width * box.height)
                }
                if !clash { kept.append(Line(words: l.words.map { Word(text: $0.text, box: up($0.box)) }, box: box, text: l.text)) }
            }
        }
        if y1 == H { break }
        y0 += 400
    }
    return kept
}

/// nil when Vision fails, so a page it could not read is `unmeasured`, never green by default.
func read(_ img: CGImage) -> [Line]? {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    do { try VNImageRequestHandler(cgImage: img, options: [:]).perform([req]) } catch { return nil }
    var lines: [Line] = []
    for obs in req.results ?? [] {
        guard let cand = obs.topCandidates(1).first else { continue }
        let s = cand.string
        var words: [Word] = []
        var i = s.startIndex
        while i < s.endIndex {
            while i < s.endIndex, s[i].isWhitespace { i = s.index(after: i) }
            guard i < s.endIndex else { break }
            var j = i
            while j < s.endIndex, !s[j].isWhitespace { j = s.index(after: j) }
            if let b = try? cand.boundingBox(for: i..<j)?.boundingBox {
                words.append(Word(text: String(s[i..<j]), box: b))
            }
            i = j
        }
        lines.append(Line(words: words, box: obs.boundingBox, text: s))
    }
    return lines
}

/// A word as compared: lower case, letters and digits only; empty for punctuation.
func norm(_ s: String) -> String {
    String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
}
func tokens(_ s: String) -> [String] {
    s.split(whereSeparator: { $0.isWhitespace }).map { norm(String($0)) }.filter { !$0.isEmpty }
}

/// How many of `ref`'s words (a multiset) appear in `got`.
func matched(_ ref: [String], _ got: [String]) -> Int {
    var bag: [String: Int] = [:]
    for w in got { bag[w, default: 0] += 1 }
    var n = 0
    for w in ref where (bag[w] ?? 0) > 0 { bag[w]! -= 1; n += 1 }
    return n
}

func editDistance(_ a: [String], _ b: [String]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count), cur = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        cur[0] = i
        for j in 1...b.count {
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
        }
        swap(&prev, &cur)
    }
    return prev[b.count]
}

// MARK: - Geometry
// Every measure works in DISPLAY space: points on the page as shown, rotation applied, origin bottom
// left, so a line runs left to right and the next line is below it on a rotated page too. PDFKit's
// calls take and give PAGE space, and are converted at the call.

func toDisp(_ page: PDFPage, _ r: CGRect) -> CGRect {   // Vision's normalised box -> display points
    let size = displaySize(page)
    return CGRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
}
func pageToDisp(_ page: PDFPage, _ r: CGRect) -> CGRect { r.applying(page.transform(for: .cropBox)) }
func dispToPage(_ page: PDFPage, _ r: CGRect) -> CGRect { r.applying(page.transform(for: .cropBox).inverted()) }
func dispToPage(_ page: PDFPage, _ p: CGPoint) -> CGPoint { p.applying(page.transform(for: .cropBox).inverted()) }

// MARK: - Measures

func f2(_ x: Double?) -> String { x.map { String(format: "%.2f", $0) } ?? "-" }
func f4(_ x: Double?) -> String { x.map { String(format: "%.4f", $0) } ?? "-" }

func inkStats(_ r: Raster) -> (count: Int, lum: Double) {
    var n = 0, sum = 0.0
    for y in 0..<r.h { for x in 0..<r.w {
        let (R, G, B) = r.rgb(x, y)
        let l = 0.299 * Double(R) + 0.587 * Double(G) + 0.114 * Double(B)
        if l < 128 { n += 1; sum += l }
    } }
    return (n, n > 0 ? sum / Double(n) : 0)
}

func raster(_ img: CGImage) -> Raster {
    let W = img.width, H = img.height
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
    return Raster(w: W, h: H, px: Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: W * H * 4)))
}

func colour(_ s: Raster, _ o: Raster) -> (share: Double, kept: Double?) {
    // over the area both renders cover: a crop box within 1 pt can round to a pixel more or less
    let W = min(s.w, o.w), H = min(s.h, o.h)
    func chroma(_ r: Raster, _ x: Int, _ y: Int) -> Int { let (R, G, B) = r.rgb(x, y); return max(R, G, B) - min(R, G, B) }
    var n = 0, kept = 0
    for y in 0..<H { for x in 0..<W where chroma(s, x, y) > 60 {
        n += 1
        var best = 0
        for dy in -1...1 { for dx in -1...1 {
            let xx = x + dx, yy = y + dy
            if xx >= 0, yy >= 0, xx < W, yy < H { best = max(best, chroma(o, xx, yy)) }
        } }
        if best > 30 { kept += 1 }
    } }
    return (Double(n) / Double(W * H), n > 0 ? Double(kept) / Double(n) : nil)
}

/// Columns: chains of reference lines, each line's successor the nearest line below that overlaps it by
/// 0.7 of the wider width within 2.5 line heights (centre to centre). In display space.
func columns(_ lines: [CGRect]) -> [[CGRect]] {
    let order = lines.indices.sorted { lines[$0].midY > lines[$1].midY }
    var next = [Int?](repeating: nil, count: lines.count), hasPrev = [Bool](repeating: false, count: lines.count)
    for i in order {
        let a = lines[i]
        var best: Int? = nil, bestD = CGFloat.infinity
        for j in lines.indices where j != i {
            let b = lines[j]
            guard b.midY < a.midY else { continue }
            let ov = min(a.maxX, b.maxX) - max(a.minX, b.minX)
            // 0.7 of the WIDER line: a heading or a fragment across the gutter spans two columns, and
            // with 0.6 of the narrower it chained them, so the "column" was both and its drag selected
            // nothing (Hughes p5). A paragraph's short last line is skipped; the chain goes past it.
            guard ov >= 0.7 * max(a.width, b.width) else { continue }
            let d = a.midY - b.midY
            guard d <= 2.5 * max(a.height, b.height) else { continue }
            if d < bestD { bestD = d; best = j }
        }
        if let b = best, !hasPrev[b] { next[i] = b; hasPrev[b] = true }
    }
    var chains: [[CGRect]] = []
    for i in order where !hasPrev[i] {
        var c: [CGRect] = [], k: Int? = i
        while let kk = k { c.append(lines[kk]); k = next[kk] }
        if c.count >= 5 { chains.append(c) }
    }
    return chains
}

func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

/// Does selected line box `b` select reference line `l`? Half of `l`'s width, and half the shorter
/// height: Vision sometimes reads two printed lines as one box, and that box's middle lies between them.
func selects(_ b: CGRect, _ l: CGRect) -> Bool {
    min(b.maxY, l.maxY) - max(b.minY, l.minY) >= 0.5 * min(b.height, l.height) &&
        min(b.maxX, l.maxX) - max(b.minX, l.minX) >= 0.5 * l.width
}

// MARK: - Truth (--truth)
// A truth page is `ops/truth/procedure.md`'s output: `<dir>/p<N>/transcript.txt` (`x y w h<TAB>text` per
// printed line in page pixels, then `COLUMNS:` and `OBJECTS:`), `meta.txt` (`px=WxH`), and the contested
// words, `contested-second.tsv` where the second reader wrote one, else `contested.tsv`, and with either
// `contested-harness.tsv`, the words the blind re-read did not confirm (`ops/truth/reread.py`), all by
// index into the transcript's words with line-end hyphens joined as `contest.py` joins them.

// `reread`: contested by the blind re-read alone (`contested-harness.tsv`), not by the transcript's own lists
struct TWord { let text: String; let line: Int; let kind: String; let joined: Bool; var contested: Bool; let px: CGRect; var reread = false }
struct TLine { let px: CGRect; let text: String; let kind: String }
struct TPage { var lines: [TLine] = []; var words: [TWord] = []; var columns: [CGRect] = []
               var objects: [(px: CGRect, desc: String)] = []; var pxW = 0.0, pxH = 0.0 }

func firstBox(_ s: String) -> CGRect? {
    let ns = s as NSString
    guard let m = try! NSRegularExpression(pattern: #"([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)"#)
        .firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
    let v = (1...4).map { Double(ns.substring(with: m.range(at: $0)))! }
    return CGRect(x: v[0], y: v[1], width: v[2], height: v[3])
}

func loadTruth(_ dir: URL) -> TPage? {
    guard let tr = try? String(contentsOf: dir.appendingPathComponent("transcript.txt"), encoding: .utf8),
          let meta = try? String(contentsOf: dir.appendingPathComponent("meta.txt"), encoding: .utf8),
          let r = meta.range(of: #"px=\d+x\d+"#, options: .regularExpression) else { return nil }
    var t = TPage()
    let wh = meta[r].dropFirst(3).split(separator: "x")
    t.pxW = Double(wh[0])!; t.pxH = Double(wh[1])!
    // lines split and matched as Python's universal newlines and `re` do, so indices agree with `contest.py`
    let lineRE = try! NSRegularExpression(pattern: #"(?s)^\s*([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s*\t(.*)$"#)
    let markRE = try! NSRegularExpression(pattern: #"^\s*(\[(fig|table|hand)\]\s*)+"#)
    var section = "lines"
    for raw in tr.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") {
        if raw.hasPrefix("COLUMNS:") { section = "columns"; continue }
        if raw.hasPrefix("OBJECTS:") { section = "objects"; continue }
        if section == "columns" { if let b = firstBox(raw) { t.columns.append(b) }; continue }
        if section == "objects" {
            let low = raw.trimmingCharacters(in: .whitespaces).lowercased()
            // scanner borders, dust and the paper tint are not content, wherever the line says `ignore`
            if low.hasPrefix("paper") || low.split(whereSeparator: { $0.isWhitespace })
                .contains(where: { $0.trimmingCharacters(in: .punctuationCharacters) == "ignore" }) { continue }
            if let b = firstBox(raw), b.width > 0, b.height > 0 { t.objects.append((b, raw)) }
            continue
        }
        let ns = raw as NSString
        guard let m = lineRE.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else { continue }
        let v = (1...4).map { Double(ns.substring(with: m.range(at: $0)))! }
        var text = ns.substring(with: m.range(at: 5)), kind = "body"
        // `[table]` is body text: a reader copies a table. Figure text and handwriting are scored apart.
        if let mm = markRE.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) {
            let mark = (text as NSString).substring(with: mm.range)
            kind = mark.contains("[fig]") ? "fig" : mark.contains("[hand]") ? "hand" : "body"
            text = (text as NSString).substring(from: mm.range.length)
        }
        t.lines.append(TLine(px: CGRect(x: v[0], y: v[1], width: v[2], height: v[3]), text: text, kind: kind))
    }
    // words, each with a box estimated from its character offset in the line (as `xcheck.py` does), and a
    // line-end hyphen joined to the next line's first word exactly as `contest.py` joins it, so the
    // contested indices name the same words
    for (li, l) in t.lines.enumerated() {
        let ch = Array(l.text), L = Double(max(ch.count, 1))
        var i = 0
        while i < ch.count {
            while i < ch.count, ch[i].isWhitespace { i += 1 }
            guard i < ch.count else { break }
            var j = i
            while j < ch.count, !ch[j].isWhitespace { j += 1 }
            let wd = String(ch[i..<j])
            let box = CGRect(x: l.px.minX + l.px.width * Double(i) / L, y: l.px.minY,
                             width: max(l.px.width * Double(j - i) / L, 10), height: l.px.height)
            if let prev = t.words.last, prev.text.range(of: #"\w-$"#, options: .regularExpression) != nil,
               l.px.minY > t.lines[prev.line].px.minY, let c = wd.first, c.isLetter || c.isNumber {
                t.words[t.words.count - 1] = TWord(text: String(prev.text.dropLast()) + wd, line: prev.line, kind: prev.kind,
                                                   joined: true, contested: false, px: prev.px)
            } else {
                t.words.append(TWord(text: wd, line: li, kind: l.kind, joined: false, contested: false, px: box))
            }
            i = j
        }
    }
    let second = dir.appendingPathComponent("contested-second.tsv")
    let cf = FileManager.default.fileExists(atPath: second.path) ? second : dir.appendingPathComponent("contested.tsv")
    // rows split at any newline: "\r\n" is one Character in Swift, so a split at "\n" alone keeps a CRLF file whole
    for row in ((try? String(contentsOf: cf, encoding: .utf8)) ?? "").split(whereSeparator: { $0.isNewline }) {
        if let k = Int(row.split(separator: "\t").first ?? ""), k >= 0, k < t.words.count { t.words[k].contested = true }
    }
    // a word the reader could not read is not scored either
    for k in t.words.indices where t.words[k].text.contains("[?]") { t.words[k].contested = true }
    // the words the blind re-read did not confirm, each named after its index: a transcript changed since the
    // re-read moves every later index, so a row naming another word stops the run rather than leave out the
    // wrong words in silence
    let hf = dir.appendingPathComponent("contested-harness.tsv")
    for row in ((try? String(contentsOf: hf, encoding: .utf8)) ?? "").split(whereSeparator: { $0.isNewline }) {
        let f = row.split(separator: "\t", omittingEmptySubsequences: false)
        guard let k = Int(f.first ?? ""), k >= 0, k < t.words.count else { continue }
        if f.count > 1, String(f[1]) != t.words[k].text {
            FileHandle.standardError.write("ux-harness: \(hf.path): word \(k) is \"\(t.words[k].text)\" in the transcript, \"\(f[1])\" here; run the re-read again\n".data(using: .utf8)!)
            exit(2)
        }
        if !t.words[k].contested { t.words[k].reread = true }
        t.words[k].contested = true
    }
    return t
}

func pxToDisp(_ t: TPage, _ page: PDFPage, _ r: CGRect) -> CGRect {
    let s = displaySize(page), sx = s.width / t.pxW, sy = s.height / t.pxH
    return CGRect(x: r.minX * sx, y: s.height - r.maxY * sy, width: r.width * sx, height: r.height * sy)
}

/// Word-level alignment of a copy against the truth. An optional truth word (contested, or figure text
/// inside a column) costs nothing matched to anything or left out, and is not counted either way.
func alignCopy(_ ref: [(w: String, opt: Bool)], _ got: [String]) -> (right: Int, wrong: [(Int, String)], missing: [Int], added: Int) {
    let n = ref.count, m = got.count
    var d = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
    for j in 0...m { d[0][j] = j }
    if n > 0 { for i in 1...n {
        d[i][0] = d[i - 1][0] + (ref[i - 1].opt ? 0 : 1)
        if m > 0 { for j in 1...m {
            let sub = ref[i - 1].opt || ref[i - 1].w == got[j - 1] ? 0 : 1
            d[i][j] = min(d[i - 1][j - 1] + sub, d[i - 1][j] + (ref[i - 1].opt ? 0 : 1), d[i][j - 1] + 1)
        } }
    } }
    var i = n, j = m, right = 0, added = 0
    var wrong: [(Int, String)] = [], missing: [Int] = []
    while i > 0 || j > 0 {
        let opt = i > 0 && ref[i - 1].opt
        if i > 0, j > 0, d[i][j] == d[i - 1][j - 1] + (opt || ref[i - 1].w == got[j - 1] ? 0 : 1) {
            if !opt { if ref[i - 1].w == got[j - 1] { right += 1 } else { wrong.append((i - 1, got[j - 1])) } }
            i -= 1; j -= 1
        } else if i > 0, d[i][j] == d[i - 1][j] + (opt ? 0 : 1) {
            if !opt { missing.append(i - 1) }
            i -= 1
        } else { added += 1; j -= 1 }
    }
    return (right, wrong, missing, added)
}

/// A copy's tokens with a word split by a stray space mended (`valu able`), and two words welded into one
/// (`valuablestudy`) cut apart, each counted; `hyph` counts the splits that are a line-end hyphen the copy
/// did not join. Judged against the truth words of the same stretch, as the reference measures do.
func mend(_ got: [String], _ ref: [String], joined: Set<String>) -> (tokens: [String], splits: Int, welds: Int, hyph: Int) {
    let refSet = Set(ref)
    var pairs: [String: (String, String)] = [:]
    for k in ref.indices.dropLast() where !refSet.contains(ref[k] + ref[k + 1]) { pairs[ref[k] + ref[k + 1]] = (ref[k], ref[k + 1]) }
    var out: [String] = [], splits = 0, welds = 0, hyph = 0, i = 0
    while i < got.count {
        let a = got[i]
        if i + 1 < got.count, refSet.contains(a + got[i + 1]), !(refSet.contains(a) && refSet.contains(got[i + 1])) {
            out.append(a + got[i + 1])
            if joined.contains(a + got[i + 1]) { hyph += 1 } else { splits += 1 }
            i += 2; continue
        }
        if !refSet.contains(a), let (x, y) = pairs[a] { out += [x, y]; welds += 1; i += 1; continue }
        out.append(a); i += 1
    }
    return (out, splits, welds, hyph)
}

// Red, on the truth: set on the owner's reports and the green pages (`Tools/ux-harness-selftest.sh`)
let truthCopyMax = 0.05, truthFindMin = 0.80, truthElInkMin = 0.50, truthElColMin = 0.50
var truthRows: [String] = []
var truthWordRows: [String] = []
var pairKeyRows: [String] = []

/// The truth measures of one page, or nil when the truth directory has no transcript for it.
func truthPage(_ p: Int, _ sp: PDFPage, _ op: PDFPage, _ out: PDFDocument, _ pairs: [(CGImage, CGImage, CGFloat)]) -> String? {
    guard let dir = truthDir?.appendingPathComponent("p\(p)"), let t = loadTruth(dir) else { return nil }
    var flags: [String] = []
    let body = t.words.indices.filter { t.words[$0].kind == "body" }
    let scoredIdx = body.filter { !t.words[$0].contested && !norm(t.words[$0].text).isEmpty }
    // each body line in the first listed column holding its centre; the rest are loose
    var lineCol: [Int?] = t.lines.map { l in
        // the reader's column boxes are drawn by eye: a column's last line can hang below its box
        t.columns.firstIndex { $0.insetBy(dx: -l.px.height, dy: -l.px.height).contains(CGPoint(x: l.px.midX, y: l.px.midY)) }
    }
    // A "column" of one or two body lines (a running head, a footer, a caption) is scored line by line: a
    // drag along a running head selected the whole column below it on Hughes p5, because the page number
    // at the head's end follows the column in the text layer, and that is not a column drag's question.
    for c in t.columns.indices where t.lines.indices.filter({ lineCol[$0] == c && t.lines[$0].kind == "body" }).count < 3 {
        for li in t.lines.indices where lineCol[li] == c { lineCol[li] = nil }
    }
    var right = 0, added = 0, splits = 0, welds = 0, hyph = 0
    var fails: [(Int, String, String)] = []   // word index, kind, what the copy has there
    func score(_ idx: [Int], _ text: String, _ label: String) {
        if verbose { FileHandle.standardError.write("p\(p) truth \(label): \(text.replacingOccurrences(of: "\n", with: "|"))\n".data(using: .utf8)!) }
        let ref = idx.map { (w: norm(t.words[$0].text), opt: t.words[$0].contested || t.words[$0].kind != "body" || norm(t.words[$0].text).isEmpty) }
        let joined = Set(idx.filter { t.words[$0].joined }.map { norm(t.words[$0].text) })
        let m = mend(tokens(text), ref.map { $0.w }, joined: joined)
        splits += m.splits; welds += m.welds; hyph += m.hyph
        let a = alignCopy(ref, m.tokens)
        right += a.right; added += a.added
        for (k, g) in a.wrong { fails.append((idx[k], "wrong", g)) }
        for k in a.missing { fails.append((idx[k], "missing", "")) }
    }
    // A line scored alone: the text over its box, grown three quarters of a line up and down and a quarter
    // line each side, and of that each line of text whose nearest transcript line, of those over it, is this
    // one. The middle half of the box alone held nothing when the text or the box sat a third of a line off
    // (Wilson 1975 p1: 18 words in the layer, all counted missing); a fixed band in its place took the line
    // above too where the text sits a third of a line low (Leland p5). A drag along the line takes the column
    // below Hughes p5's running head, as the comment above says, and one begun outside the box took the end of
    // a line in the next column across a narrow gutter (Leland p5, Delton p1).
    let lineBoxes = t.lines.map { pxToDisp(t, op, $0.px) }
    func lineText(_ li: Int) -> String {
        // a line's height is its box's narrow side when the box runs up the page (handwriting along a margin)
        let r = lineBoxes[li], h = r.height > max(3 * r.width, 50) ? r.width : r.height
        guard let sel = op.selection(for: dispToPage(op, r.insetBy(dx: -h / 4, dy: -h * 0.75))) else { return "" }
        return sel.selectionsByLine().filter { s in
            let b = pageToDisp(op, s.bounds(for: op))
            let over = lineBoxes.indices.filter { lineBoxes[$0].minX < b.maxX && lineBoxes[$0].maxX > b.minX }
            return over.min { abs(lineBoxes[$0].midY - b.midY) < abs(lineBoxes[$1].midY - b.midY) } == li
        }.compactMap { $0.string }.joined(separator: "\n")
    }
    // (a) Copy: a drag down each column, from its first line's start to its last line's end. Where that line's
    // box reaches into a column box beside it, the drag stops at its own column's edge: Kelly 2014 p3's last
    // line in one column is boxed 31 px into the next, and a drag ended there ran on through that column (316
    // words added). A column box drawn narrower than a headline it holds is no reason to cut the headline.
    var colTokens: [[String]] = []
    let colBoxes = t.columns.map { pxToDisp(t, op, $0) }
    for c in t.columns.indices {
        let ls = t.lines.indices.filter { lineCol[$0] == c && t.lines[$0].kind == "body" }
        let idx = t.words.indices.filter { lineCol[t.words[$0].line] == c }
        if !idx.isEmpty { colTokens.append(idx.filter { !t.words[$0].contested && t.words[$0].kind == "body" }.map { norm(t.words[$0].text) }.filter { !$0.isEmpty }) }
        guard let f = ls.first, let l = ls.last else { continue }
        let a = lineBoxes[f], b = lineBoxes[l], box = colBoxes[c]
        let beside = colBoxes.indices.filter { $0 != c }.map { colBoxes[$0] }
        let leftIn = beside.contains { $0.maxX <= box.minX && $0.maxX > a.minX && $0.minY < a.maxY && $0.maxY > a.minY }
        let rightIn = beside.contains { $0.minX >= box.maxX && $0.minX < b.maxX && $0.minY < b.maxY && $0.maxY > b.minY }
        let sel = op.selection(from: dispToPage(op, CGPoint(x: (leftIn ? max(a.minX, box.minX) : a.minX) + 1, y: a.midY)),
                               to: dispToPage(op, CGPoint(x: (rightIn ? min(b.maxX, box.maxX) : b.maxX) - 1, y: b.midY)))
        score(idx, sel?.string ?? "", "column \(c + 1)")
    }
    // body lines in no column, each selected alone
    for li in t.lines.indices where lineCol[li] == nil && t.lines[li].kind == "body" {
        score(t.words.indices.filter { t.words[$0].line == li }, lineText(li), "loose line \(li + 1)")
    }
    // figure text and handwriting, apart: the share of each line's words a selection over it holds
    var apart: [String: (Int, Int)] = ["fig": (0, 0), "hand": (0, 0)]
    for li in t.lines.indices where t.lines[li].kind != "body" {
        let w = t.words.indices.filter { t.words[$0].line == li && !t.words[$0].contested }.map { norm(t.words[$0].text) }.filter { !$0.isEmpty }
        let (r0, n0) = apart[t.lines[li].kind]!
        apart[t.lines[li].kind] = (r0 + matched(w, tokens(lineText(li))), n0 + w.count)
    }
    let scored = scoredIdx.count
    let wrongN = fails.filter { $0.1 == "wrong" }.count, missN = fails.filter { $0.1 == "missing" }.count
    let copyErr: Double? = scored >= 20 ? Double(wrongN + missN + added) / Double(scored) : nil

    // (b) Find: up to 30 words of 5+ letters, each must have a hit on this page over the word. The sample is
    // drawn before the re-read's contested words come out, so contesting a word never moves another pick and
    // every word sampled is one the re-read was given. A word with punctuation inside it (`high-school`,
    // `Women's`) is then left out too: the search is for its letters alone, which a correct layer lacks.
    var findShare: Double? = nil
    let cand = body.filter { k in
        let w = t.words[k], n = norm(w.text)
        return (!w.contested || w.reread) && !w.joined && n.count >= 5 && n.allSatisfy { $0.isLetter }
    }
    let sample = cand.count < 5 ? [] : stride(from: 0, to: cand.count, by: max(1, cand.count / 30)).prefix(30).map { cand[$0] }
        .filter { k in !t.words[k].contested && t.words[k].text.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).allSatisfy { $0.isLetter } }
    if sample.count >= 5 {
        var ok = 0
        for k in sample {
            let w = pxToDisp(t, op, t.words[k].px), line = pxToDisp(t, op, t.lines[t.words[k].line].px)
            // the box is estimated from a character offset, so it is widened along the line
            let zone = w.insetBy(dx: -max(3 * w.height, 0.15 * line.width), dy: -w.height)
            let hits = out.findString(norm(t.words[k].text), withOptions: [.caseInsensitive])
            if hits.contains(where: { h in
                guard h.pages.contains(where: { out.index(for: $0) == p - 1 }) else { return false }
                let hb = pageToDisp(op, h.bounds(for: op))
                return zone.contains(CGPoint(x: hb.midX, y: hb.midY))
            }) { ok += 1 } else { fails.append((k, "find", "")) }
        }
        findShare = Double(ok) / Double(sample.count)
    }

    // (c) Column order: where each column's first three words first appear in the page's text
    let pageTok = tokens(op.string ?? "")
    var pos: [Int] = []
    for c in colTokens where c.count >= 4 {
        let g = Array(c.prefix(3))
        if let at = pageTok.indices.dropLast(2).first(where: { Array(pageTok[$0..<($0 + 3)]) == g }) { pos.append(at) }
    }
    if verbose { FileHandle.standardError.write("p\(p) truth order: \(pos)\n".data(using: .utf8)!) }
    let inOrder = pos.count < 2 ? 0 : (1..<pos.count).filter { pos[$0] > pos[$0 - 1] }.count
    let order = pos.count < 2 ? "-" : "\(inOrder)/\(pos.count - 1)"

    // how far Vision's reading of the source render, and the output's whole text layer, are from the truth
    let truthTok = scoredIdx.map { norm(t.words[$0].text) }
    let visTok = tokens((try? String(contentsOf: dir.appendingPathComponent("vision.txt"), encoding: .utf8)) ?? "")
    let visMiss: Double? = scored >= 20 && !visTok.isEmpty ? 1 - Double(matched(truthTok, visTok)) / Double(scored) : nil
    let layerMiss: Double? = scored >= 20 ? 1 - Double(matched(truthTok, pageTok)) / Double(scored) : nil

    if (copyErr ?? 0) > truthCopyMax { flags.append("tcopy") }
    if (findShare ?? 1) < truthFindMin { flags.append("tfind") }

    // every failure, with its box in the transcript's pixels, for the blind re-read before it counts
    for (k, kind, g) in fails {
        let w = t.words[k]
        truthWordRows.append("\(p)\t\(k)\t\(kind)\t\(w.text)\t\(g)\t\(Int(w.px.minX)) \(Int(w.px.minY)) \(Int(w.px.width)) \(Int(w.px.height))")
    }

    // EVERYTHING ELSE: the page and each listed object as a crop pair, source and output in an order the
    // judge is not told (`pairs-key.tsv` holds it). The order is fixed by page and object, so a rerun
    // writes the same pairs.
    let pdir = outDir.appendingPathComponent("pairs")
    try? FileManager.default.createDirectory(at: pdir, withIntermediateDirectories: true)
    var list = ["0\twhole page"]
    var elInk: Double? = nil, elCol: Double? = nil
    let items = [(CGRect?.none, "whole page")] + t.objects.map { (Optional(pxToDisp(t, op, $0.px)), $0.desc) }
    for (k, item) in items.enumerated() {
        let (sImg, oImg, sc) = k == 0 ? pairs[0] : pairs[1]
        var crop = CGRect(x: 0, y: 0, width: sImg.width, height: sImg.height)
        if let r = item.0 {
            let H = displaySize(op).height
            crop = CGRect(x: r.minX * sc - 8, y: (H - r.maxY) * sc - 8, width: r.width * sc + 16, height: r.height * sc + 16)
                .intersection(CGRect(x: 0, y: 0, width: min(sImg.width, oImg.width), height: min(sImg.height, oImg.height)))
        }
        guard !crop.isNull, crop.width >= 2, crop.height >= 2,
              let sc2 = sImg.cropping(to: crop.integral), let oc2 = oImg.cropping(to: crop.integral) else { continue }
        var h = UInt64(p) &* 0x9E3779B97F4A7C15 ^ UInt64(k) &* 0xC2B2AE3D27D4EB4F
        h ^= h >> 29; h = h &* 0xBF58476D1CE4E5B9; h ^= h >> 32
        let outIsA = h & 1 == 0
        func save(_ img: CGImage, _ name: String) {
            if let d = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) { try? d.write(to: pdir.appendingPathComponent(name)) }
        }
        save(outIsA ? oc2 : sc2, "p\(p)-\(k)-A.png"); save(outIsA ? sc2 : oc2, "p\(p)-\(k)-B.png")
        // each listed element, with no model: the share of its dark ink and of its coloured pixels the
        // output keeps, where the source's box holds enough of either to judge
        if k > 0 {
            let s = raster(sc2), o = raster(oc2)
            let si = inkStats(s).count, oi = inkStats(o).count
            if si >= 50 { let r = min(Double(oi) / Double(si), 1); elInk = min(elInk ?? r, r) }
            let c = colour(s, o)
            if let kept = c.kept, c.share * Double(s.w * s.h) >= 50 { elCol = min(elCol ?? kept, kept) }
        }
        pairKeyRows.append("\(p)\t\(k)\t\(outIsA ? "A" : "B")\t\(item.1)")
        if k > 0 { list.append("\(k)\t\(item.1)") }
    }
    try? (list.joined(separator: "\n") + "\n").write(to: pdir.appendingPathComponent("p\(p)-elements.txt"), atomically: true, encoding: .utf8)
    if (elInk ?? 1) < truthElInkMin { flags.append("tink") }
    if (elCol ?? 1) < truthElColMin { flags.append("tcolour") }

    let fa = apart["fig"]!, ha = apart["hand"]!
    let figCell: String = fa.1 > 0 ? "\(fa.0)/\(fa.1)" : "-"
    let handCell: String = ha.1 > 0 ? "\(ha.0)/\(ha.1)" : "-"
    let contestedN = t.words.filter { $0.contested }.count
    var cells: [String] = [String(p), String(t.words.count), String(contestedN), String(scored), String(right)]
    cells += [String(wrongN), String(missN), String(added), String(splits), String(welds), String(hyph)]
    cells += [f4(copyErr), f2(findShare), order, figCell, handCell, f4(visMiss), f4(layerMiss)]
    cells += [String(items.count), f2(elInk), f2(elCol), flags.isEmpty ? "-" : flags.joined(separator: ",")]
    return cells.joined(separator: "\t")
}

// MARK: - Main

guard let src = PDFDocument(url: srcURL) else { fail("cannot open \(args[1])", 2) }
let t0 = Date()
let out = PDFDocument(url: outURL)
let openMs = Date().timeIntervalSince(t0) * 1000

func pageList(_ spec: String?, _ n: Int) -> [Int] {
    guard let spec = spec, spec != "all" else { return Array(1...max(1, n)) }
    var r: [Int] = []
    for part in spec.split(separator: ",") {
        let ends = part.split(separator: "-").compactMap { Int($0) }
        if ends.count == 1 { r.append(ends[0]) } else if ends.count == 2, ends[0] <= ends[1] { r += Array(ends[0]...ends[1]) }
    }
    return r.filter { $0 >= 1 && $0 <= n }
}

var anyRed = false
var pageRows: [String] = []

if let out = out {
    let pages = pageList(args.count > 4 ? args[4] : nil, min(src.pageCount, out.pageCount))
    if pages.isEmpty { fail("no page of `\(args.count > 4 ? args[4] : "all")` is in both documents", 2) }
    for p in pages {
        guard let sp = src.page(at: p - 1), let op = out.page(at: p - 1) else { continue }
        var flags: [String] = []

        // Seven Vision readings, most of a page's time. Run side by side they took as long (155% CPU
        // either way), so they run one after another.
        let (sHi, _, _) = render(sp, scale: refScale)
        let (s4i, _, _) = render(sp, scale: 4)
        let (s1i, s1r, msS) = render(sp, scale: 1), (o1i, o1r, msO) = render(op, scale: 1)
        let (s2i, s2r, _) = render(sp, scale: 2), (o2i, o2r, _) = render(op, scale: 2)
        for (img, name) in [(s1i, "src-1x"), (o1i, "out-1x"), (s2i, "src-2x"), (o2i, "out-2x")] { savePNG(img, "p\(p)-\(name).png") }
        let jobs: [(CGImage, Bool)] = [(sHi, true), (s2i, true), (s4i, true), (s1i, false), (o1i, false), (s2i, false), (o2i, false)]
        var readings = [[Line]](repeating: [], count: jobs.count)
        var failed = false
        for k in jobs.indices {
            if let r = jobs[k].1 ? readBanded(jobs[k].0) : read(jobs[k].0) { readings[k] = r } else { failed = true }
        }
        if failed { flags.append("unmeasured") }
        let ref = readings[0]
        // copy is scored against the best of three readings: one Vision reading of a scan is unstable
        // (Briefer p5: 236 to 481 words at 2x-5x), and a copy that is really wrong is wrong against all
        let otherRefs = [readings[1], readings[2]]
        let refWords = ref.flatMap { $0.words.map { norm($0.text) } }.filter { !$0.isEmpty }
        let enough = refWords.count >= 20

        var leg: [Double?] = []
        for (sRead, oRead) in [(readings[3], readings[4]), (readings[5], readings[6])] {
            let sm2 = matched(refWords, sRead.flatMap { tokens($0.text) })
            let om2 = matched(refWords, oRead.flatMap { tokens($0.text) })
            leg.append(enough && sm2 >= 10 ? Double(om2) / Double(sm2) : nil)
        }
        if leg.contains(where: { ($0 ?? 1) < 0.75 }) { flags.append("legibility") }
        let s1: Raster? = s1r, o1: Raster? = o1r, s2: Raster? = s2r, o2: Raster? = o2r

        let si = inkStats(s2!), oi = inkStats(o2!)
        let inkRatio: Double? = si.count > 500 ? Double(oi.count) / Double(si.count) : nil
        let inkLum: Double? = si.count > 500 && oi.count > 0 ? oi.lum - si.lum : nil
        if (inkRatio ?? 1) < 0.60 || (inkLum ?? 0) > 40 { flags.append("faint") }

        let col = colour(s1!, o1!)
        if col.share >= 0.0005, (col.kept ?? 1) < 0.50 { flags.append("colour") }

        // find
        var findShare: Double? = nil
        let candidates = ref.flatMap { $0.words }.filter { w in
            let n = norm(w.text); return n.count >= 5 && n.allSatisfy { $0.isLetter }
        }
        if candidates.count >= 5 {
            let step = max(1, candidates.count / 30)
            let sample = stride(from: 0, to: candidates.count, by: step).prefix(30).map { candidates[$0] }
            var ok = 0
            for w in sample {
                let box = toDisp(op, w.box)
                let pad = box.height * 0.5
                let hits = out.findString(norm(w.text), withOptions: [.caseInsensitive])
                if hits.contains(where: { h in
                    guard h.pages.contains(where: { out.index(for: $0) == p - 1 }) else { return false }
                    let hb = pageToDisp(op, h.bounds(for: op))
                    return box.insetBy(dx: -pad, dy: -pad).contains(CGPoint(x: hb.midX, y: hb.midY))
                }) { ok += 1 } else if verbose {
                    FileHandle.standardError.write(String(format: "p%d find miss %@ at x%.0f y%.0f, %d hits\n", p, w.text, box.midX, box.midY, hits.count).data(using: .utf8)!)
                }
            }
            findShare = Double(ok) / Double(sample.count)
            if findShare! < 0.80 { flags.append("find") }
        }

        // selection and copy, per column
        let refLines = ref.map { toDisp(op, $0.box) }
        let chains = columns(refLines)
        var inside: Double? = nil, cover: Double? = nil, overInk: Double? = nil, precision: Double? = nil, recall: Double? = nil
        var werNum = 0, werDen = 0, splits = 0, welds = 0, echoes = 0, hyphMiss = 0, hyphAll = 0, mid = 0, breaks = 0
        let refSet = Set(refWords)
        // every reading's lines in display space, for judging a copied line where it lies
        // (pairs per reading, not a map keyed by box: two readings of one image give identical boxes)
        let allReadings: [[(box: CGRect, words: [String])]] = readings.map { reading in
            reading.map { (toDisp(op, $0.box), tokens($0.text)) }
        }
        for chain in chains {
            let first = chain.first!, last = chain.last!
            let colRect = chain.reduce(CGRect.null) { $0.union($1) }
            let h = chain.map { $0.height }.sorted()[chain.count / 2]
            // cover asks about the drag, so a line with no text under it at all (a void, or type inside a
            // picture) is left out: `find` and the voids instruments own that question. A column with no
            // text under any line (a diagram's stacked labels) is left out whole, for the same reason.
            let withText = chain.filter { l in
                !(op.selection(for: dispToPage(op, l))?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if withText.isEmpty { continue }
            // a drag over lines that have text, selecting nothing: worst on every count
            guard let sel = op.selection(from: dispToPage(op, CGPoint(x: first.minX + 1, y: first.midY)),
                                         to: dispToPage(op, CGPoint(x: last.maxX - 1, y: last.midY))),
                  !(sel.string ?? "").isEmpty else {
                inside = 0; cover = 0; overInk = 0; precision = 0
                continue
            }
            let lineBoxes = sel.selectionsByLine().map { pageToDisp(op, $0.bounds(for: op)) }.filter { area($0) > 0 }
            let total = lineBoxes.reduce(0) { $0 + area($1) }
            let grown = colRect.insetBy(dx: -h, dy: -h * 0.5)
            let inArea = lineBoxes.reduce(0) { $0 + area($1.intersection(grown)) }
            let ins = total > 0 ? Double(inArea / total) : 0
            let cov = Double(withText.filter { l in
                lineBoxes.contains { b in
                    selects(b, l)
                }
            }.count) / Double(withText.count)
            let over = lineBoxes.isEmpty ? 0 : Double(lineBoxes.filter { b in
                refLines.contains { $0.insetBy(dx: -h * 0.5, dy: -h * 0.5).contains(CGPoint(x: b.midX, y: b.midY)) }
            }.count) / Double(lineBoxes.count)
            inside = min(inside ?? 1, ins); cover = min(cover ?? 1, cov); overInk = min(overInk ?? 1, over)
            if verbose {
                let t = (sel.string ?? "").replacingOccurrences(of: "\n", with: "|")
                FileHandle.standardError.write(String(format: "p%d col x%.0f-%.0f y%.0f-%.0f lines %d inside %.2f cover %.2f over %.2f  %@\n",
                    p, colRect.minX, colRect.maxX, colRect.minY, colRect.maxY, chain.count, ins, cov, over,
                    String(t.prefix(160))).data(using: .utf8)!)
                for l in withText where !lineBoxes.contains(where: { b in
                    selects(b, l)
                }) {
                    FileHandle.standardError.write(String(format: "    missed x%.0f-%.0f y%.0f-%.0f  %@\n", l.minX, l.maxX, l.minY, l.maxY,
                        (op.selection(for: dispToPage(op, l))?.string ?? "").replacingOccurrences(of: "\n", with: "|")).data(using: .utf8)!)
                }
                for b in lineBoxes where area(b.intersection(grown)) < 0.5 * area(b) {
                    FileHandle.standardError.write(String(format: "    outside x%.0f-%.0f y%.0f-%.0f  %@\n", b.minX, b.maxX, b.minY, b.maxY,
                        (op.selection(for: dispToPage(op, b))?.string ?? "").replacingOccurrences(of: "\n", with: "|")).data(using: .utf8)!)
                }
            }

            // the reference text of this column, in order: every reference line inside it, not only the
            // chain's, which skips a paragraph's short last line and would count its words as insertions
            func inColumn(_ reading: [Line]) -> [Line] {
                reading.filter { l in
                    let r = toDisp(op, l.box); return grown.contains(CGPoint(x: r.midX, y: r.midY))
                }.sorted { toDisp(op, $0.box).midY > toDisp(op, $1.box).midY }
            }
            let chainLines = inColumn(ref)
            let text = sel.string ?? ""
            let got = tokens(text)
            var refTok = chainLines.flatMap { tokens($0.text) }
            var best = editDistance(refTok, got)
            for other in otherRefs {
                let t = inColumn(other).flatMap { tokens($0.text) }
                let d = editDistance(t, got)
                if t.count >= 20, Double(d) / Double(t.count) < Double(best) / Double(max(1, refTok.count)) { best = d; refTok = t }
            }
            werNum += best; werDen += refTok.count
            // precision: copied words that some reading of the source has in this column (a misread, or a
            // line from the next column, is not); recall: words two readings agree on, found in the copy
            let readings = ([chainLines] + otherRefs.map(inColumn)).map { Set($0.flatMap { tokens($0.text) }) }
            let union = readings.reduce(Set<String>()) { $0.union($1) }
            let stable = union.filter { w in readings.filter { $0.contains(w) }.count >= 2 }
            // Precision is judged line by line, where the words are: each selected line's words against
            // what the readings that cover it read there. Vision drops different lines at every scale and
            // band (Briefer p1: a clean paragraph absent from all three source readings), so a page-wide
            // vocabulary has holes, and the copy's right words fell into them. A reading counts for a line
            // when its lines over it span 0.8 of the line's width; a line no reading covers is not judged.
            // Each word counts as often as the best reading has it, so a line copied twice is not precise.
            // Where the text sits is selection's question; this one is whether the words are right.
            var judged = 0, right = 0
            for ls in sel.selectionsByLine() {
                let b = pageToDisp(op, ls.bounds(for: op))
                let lineTok = tokens(ls.string ?? "")
                guard area(b) > 0, !lineTok.isEmpty else { continue }
                var best: Int? = nil
                for reading in allReadings {
                    // centre within the line's box: a merged two-line box, or the line above, is not this line
                    let over = reading.filter { e in
                        let r = e.box
                        return abs(r.midY - b.midY) <= 0.5 * b.height && r.height <= 1.6 * b.height &&
                            min(r.maxX, b.maxX) > max(r.minX, b.minX)
                    }
                    let span = over.reduce(CGFloat(0)) { $0 + max(0, min($1.box.maxX, b.maxX) - max($1.box.minX, b.minX)) }
                    guard span >= 0.8 * b.width else { continue }
                    let there = over.flatMap { $0.words }
                    best = max(best ?? 0, matched(lineTok, there))
                }
                guard let m = best else { continue }
                judged += lineTok.count; right += m
                if verbose && m < lineTok.count {
                    FileHandle.standardError.write("    WRONG \(m)/\(lineTok.count)  \(ls.string ?? "")\n".data(using: .utf8)!)
                }
            }
            if judged >= 20 { precision = min(precision ?? 1, Double(right) / Double(judged)) }
            if stable.count >= 20 {
                recall = min(recall ?? 1, Double(stable.intersection(Set(got)).count) / Double(stable.count))
            }
            if verbose {
                FileHandle.standardError.write("    REF \(refTok.joined(separator: " "))\n    GOT \(got.joined(separator: " "))\n".data(using: .utf8)!)
            }
            for i in got.indices.dropLast() {
                let a = got[i], b = got[i + 1]
                if refSet.contains(a + b) && !(refSet.contains(a) && refSet.contains(b)) { splits += 1 }
                // a line-end word written whole with its continuation kept: "practices tices"
                if b.count >= 3, a.count > b.count, a.hasSuffix(b), !refSet.contains(b) { echoes += 1 }
            }
            // a hyphen join across a line end is right, so it is not a weld
            var joins = Set<String>()
            for (k, l) in chainLines.enumerated() where k + 1 < chainLines.count {
                if let a = l.words.last?.text, a.hasSuffix("-"), let b = chainLines[k + 1].words.first?.text {
                    joins.insert(norm(a) + norm(b))
                }
            }
            let refPairs = Set(refTok.indices.dropLast().map { refTok[$0] + refTok[$0 + 1] })
            welds += got.filter { !refSet.contains($0) && !joins.contains($0) && refPairs.contains($0) }.count
            for (k, l) in chainLines.enumerated() where k + 1 < chainLines.count {
                guard let lastW = l.words.last?.text, lastW.hasSuffix("-"), lastW.count > 2,
                      let nextW = chainLines[k + 1].words.first?.text else { continue }
                hyphAll += 1
                let stem = norm(lastW), rest = norm(nextW)
                let g = text.replacingOccurrences(of: "\n", with: " ").lowercased()
                if g.range(of: "\(stem)- \(rest)") != nil || g.range(of: "\(stem) - \(rest)") != nil { hyphMiss += 1 }
            }
            let chars = Array(text)
            for (k, c) in chars.enumerated() where c == "\n" {
                breaks += 1
                let prev = chars[..<k].last { !$0.isWhitespace }
                if let pc = prev, !".:;!?-\u{2014}\"\u{201D}".contains(pc) { mid += 1 }
            }
        }
        if (inside ?? 1) < 0.90 || (cover ?? 1) < 0.90 || (overInk ?? 1) < 0.80 { flags.append("selection") }
        let wer: Double? = werDen >= 20 ? Double(werNum) / Double(werDen) : nil
        if (precision ?? 1) < 0.80 { flags.append("copy") }

        var geom: [String] = []
        // Red only for what a reader sees: the page's displayed size. A page drawn sideways under /Rotate 90
        // is published upright under /Rotate 0 at the same displayed size, and a box moved with its content
        // (JSTOR's y=-8 media boxes, published from 0: Hughes) looks the same; both are noted, not red.
        // Content turned the wrong way at the same size is caught by legibility, find and selection,
        // which all compare against the source's display.
        let sd = displaySize(sp), od = displaySize(op)
        if abs(sd.width - od.width) >= 1 || abs(sd.height - od.height) >= 1 { geom.append("size"); flags.append("geometry") }
        if sp.rotation != op.rotation { geom.append("rotation") }
        let sm = sp.bounds(for: .mediaBox), om = op.bounds(for: .mediaBox)
        let sc = sp.bounds(for: .cropBox), oc = op.bounds(for: .cropBox)
        if abs(sm.minX - om.minX) >= 1 || abs(sm.minY - om.minY) >= 1 ||
            abs((sc.minX - sm.minX) - (oc.minX - om.minX)) >= 1 || abs((sc.minY - sm.minY) - (oc.minY - om.minY)) >= 1 {
            geom.append("origin")
        }

        if !flags.isEmpty { anyRed = true }
        let row = [String(p), String(refWords.count), f2(leg[0]), f2(leg[1]), f2(inkRatio),
                   inkLum.map { String(format: "%.0f", $0) } ?? "-", f4(col.share), f2(col.kept), f2(findShare),
                   String(chains.count), f2(inside), f2(cover), f2(overInk), f2(wer), f2(precision), f2(recall), String(splits), String(welds), String(echoes),
                   "\(hyphMiss)/\(hyphAll)", "\(mid)/\(breaks)", geom.isEmpty ? "ok" : geom.joined(separator: "+"),
                   String(format: "%.0f", msS), String(format: "%.0f", msO),
                   flags.isEmpty ? "-" : flags.joined(separator: ",")].joined(separator: "\t")
        pageRows.append(row)
        print(row)
        if truthDir != nil, let tr = truthPage(p, sp, op, out, [(s1i, o1i, 1), (s2i, o2i, 2)]) {
            truthRows.append(tr)
            if !tr.hasSuffix("\t-") { anyRed = true }
            print("TRUTH\t" + tr)
        }
        fflush(stdout)
    }
}

// MARK: - Document

func outlineCount(_ o: PDFOutline?) -> Int {
    guard let o = o else { return 0 }
    var n = 0
    for i in 0..<o.numberOfChildren { if let c = o.child(at: i) { n += 1 + outlineCount(c) } }
    return n
}
func annots(_ d: PDFDocument) -> (links: Int, other: Int, labels: [String]) {
    var l = 0, o = 0, labels: [String] = []
    for i in 0..<d.pageCount {
        guard let pg = d.page(at: i) else { continue }
        labels.append(pg.label ?? "")
        for a in pg.annotations { if a.type == "Link" { l += 1 } else { o += 1 } }
    }
    return (l, o, labels)
}
func qpdfClean(_ url: URL) -> String {
    let qpdf = ["/opt/homebrew/bin/qpdf", "/usr/local/bin/qpdf"].first { FileManager.default.isExecutableFile(atPath: $0) }
    guard let q = qpdf else { return "absent" }
    let t = Process()
    t.executableURL = URL(fileURLWithPath: q)
    t.arguments = ["--check", url.path]
    t.standardOutput = FileHandle.nullDevice
    t.standardError = FileHandle.nullDevice
    do { try t.run() } catch { return "absent" }
    t.waitUntilExit()
    return t.terminationStatus == 0 ? "clean" : "exit\(t.terminationStatus)"
}
func bytes(_ u: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? Int) ?? 0 }

var dflags: [String] = []
let sa = annots(src)
var cells: [String]
if let out = out {
    let oa = annots(out)
    let q = qpdfClean(outURL)
    if q.hasPrefix("exit") { dflags.append("qpdf") }
    if src.pageCount != out.pageCount { dflags.append("pages") }
    let so = outlineCount(src.outlineRoot), oo = outlineCount(out.outlineRoot)
    if so != oo { dflags.append("outline") }
    if sa.labels != oa.labels { dflags.append("labels") }
    if sa.links != oa.links { dflags.append("links") }
    if sa.other != oa.other { dflags.append("annots") }
    let st = src.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? ""
    let ot = out.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? ""
    if !st.isEmpty && st != ot { dflags.append("title") }
    cells = ["\(src.pageCount)>\(out.pageCount)", "\(bytes(srcURL))>\(bytes(outURL))", String(format: "%.0f", openMs),
             "yes", q, "\(so)>\(oo)", sa.labels == oa.labels ? "same" : "differ", "\(sa.links)>\(oa.links)",
             "\(sa.other)>\(oa.other)", st == ot ? "same" : "differ"]
} else {
    dflags.append("open")
    cells = ["\(src.pageCount)>-", "\(bytes(srcURL))>\(bytes(outURL))", "-", "no", "-", "-", "-", "-", "-", "-"]
}
if !dflags.isEmpty { anyRed = true }
let docRow = (cells + [dflags.isEmpty ? "-" : dflags.joined(separator: ",")]).joined(separator: "\t")
print("DOC\t" + docRow)
try? ([pageHeader] + pageRows).joined(separator: "\n").appending("\n")
    .write(to: outDir.appendingPathComponent("pages.tsv"), atomically: true, encoding: .utf8)
try? [docHeader, docRow].joined(separator: "\n").appending("\n")
    .write(to: outDir.appendingPathComponent("document.tsv"), atomically: true, encoding: .utf8)
if truthDir != nil {
    try? ([truthHeader] + truthRows).joined(separator: "\n").appending("\n")
        .write(to: outDir.appendingPathComponent("truth.tsv"), atomically: true, encoding: .utf8)
    try? (["page\tidx\tkind\tword\tcopy\tpx"] + truthWordRows).joined(separator: "\n").appending("\n")
        .write(to: outDir.appendingPathComponent("truth-words.tsv"), atomically: true, encoding: .utf8)
    try? (["page\telement\toutput\twhat"] + pairKeyRows).joined(separator: "\n").appending("\n")
        .write(to: outDir.appendingPathComponent("pairs-key.tsv"), atomically: true, encoding: .utf8)
}
exit(anyRed ? 1 : 0)
