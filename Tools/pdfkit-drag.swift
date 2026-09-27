// pdfkit-drag — how much of a drag selection down a column of text stays in it, as PDFKit (Preview) selects.
//
//   pdfkit-drag <pdf> [page=1] [verbose=0]
//
// Built for C39. Every character's position is a one-character selection,
// `page.selection(for: NSRange(i, 1)).bounds(for:)`. `characterBounds(at:)` is NOT used: on these files it
// falls out of step with `page.string` after the first line (on WSJ 1969, 7,319 of 7,375 characters), so
// every drag and cross figure C39 recorded before 2026-09-27 (`coldrag`, `colpara`, `drag2`) is void.
// No column finder either, because a newspaper page's articles do not share columns: a PDFKit line's
// successor is the nearest line below it that overlaps it by 0.6 of the narrower width, within 1.2 line
// heights, unless another line has it as its nearest below and lies nearer. Chains of successors are
// the page's columns of text. A page with no text reports no lines.
// For each chain of 6+ lines, one drag from its first line's first character to its last line's last
// (`selection(from:to:)`), and one over each run of PARA (6) lines; a selected character is "in" when it
// belongs to the dragged lines. A line "crosses" when it lies over lines of two chains of 6+ that stand side by side.
// Exit: 0 ok · 1 the PDF will not open · 2 usage.
import PDFKit
let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write("usage: pdfkit-drag <pdf> [page=1] [verbose=0]\n".data(using: .utf8)!)
    exit(2)
}
guard let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write("pdfkit-drag: cannot open \(args[1])\n".data(using: .utf8)!)
    exit(1)
}
guard let pageNumber = args.count > 2 ? Int(args[2]) : 1, pageNumber >= 1, pageNumber <= doc.pageCount else {
    FileHandle.standardError.write("pdfkit-drag: no such page\n".data(using: .utf8)!)
    exit(2)
}
let pageIndex = pageNumber - 1
let verbose = args.count > 3 && args[3] != "0"
let env = ProcessInfo.processInfo.environment
let para = Int(env["PARA"] ?? "6") ?? 6
guard let page = doc.page(at: pageIndex) else { exit(1) }
let s = (page.string ?? "") as NSString
let ws = CharacterSet.whitespacesAndNewlines
var posOf = [Int: CGRect]()
for i in 0..<s.length {
    let c = s.character(at: i)
    if let u = Unicode.Scalar(c), ws.contains(u) { continue }
    guard let one = page.selection(for: NSRange(location: i, length: 1)) else { continue }
    let r = one.bounds(for: page)
    if r.width > 0 && r.height > 0 { posOf[i] = r }
}
struct Line { var idx: [Int]; var rect: CGRect; var text: String }
var lines: [Line] = []
let box = page.bounds(for: .mediaBox)
for l in page.selection(for: box)?.selectionsByLine() ?? [] {
    var idx: [Int] = []
    for k in 0..<l.numberOfTextRanges(on: page) { let r = l.range(at: k, on: page); for i in r.location..<(r.location + r.length) where posOf[i] != nil { idx.append(i) } }
    guard !idx.isEmpty else { continue }
    var rect = posOf[idx[0]]!
    for i in idx { rect = rect.union(posOf[i]!) }
    lines.append(Line(idx: idx.sorted(), rect: rect, text: l.string ?? ""))
}
let heights = lines.map { $0.rect.height }.sorted()
let h = heights.isEmpty ? 10 : heights[heights.count / 2]
func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat { max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX)) }
// successor: nearest below, overlapping 60% of the narrower, gap within 1.2 h
var succ = [Int](repeating: -1, count: lines.count), pred = [Int](repeating: -1, count: lines.count)
var best = [Int](repeating: -1, count: lines.count)
for a in lines.indices {
    var bi = -1; var bg = CGFloat.infinity
    for b in lines.indices where b != a {
        let ra = lines[a].rect, rb = lines[b].rect
        guard rb.midY < ra.midY else { continue }
        let gap = ra.minY - rb.maxY
        guard gap > -0.4 * h && gap < 1.2 * h else { continue }
        guard overlap(ra, rb) >= 0.6 * min(ra.width, rb.width) else { continue }
        if gap < bg { bg = gap; bi = b }
    }
    best[a] = bi
}
// of the lines whose nearest below is b, b is the successor of the nearest
for b in lines.indices {
    var ai = -1; var ag = CGFloat.infinity
    for a in lines.indices where best[a] == b {
        let gap = lines[a].rect.minY - lines[b].rect.maxY
        if gap < ag { ag = gap; ai = a }
    }
    if ai >= 0 { succ[ai] = b; pred[b] = ai }
}
var chains: [[Int]] = []
for a in lines.indices where pred[a] < 0 {
    var c = [a]; var x = a
    while succ[x] >= 0 { x = succ[x]; c.append(x) }
    chains.append(c)
}
var chainOf = [Int](repeating: -1, count: lines.count)
for (k, c) in chains.enumerated() { for l in c { chainOf[l] = k } }
var lineOfIndex = [Int: Int]()
for (k, l) in lines.enumerated() { for i in l.idx { lineOfIndex[i] = k } }
func drag(_ from: Int, _ to: Int, _ members: Set<Int>) -> (Int, Int) {
    let a = lines[from].idx.first!, b = lines[to].idx.last!
    let pa = posOf[a]!, pb = posOf[b]!
    guard let sel = page.selection(from: CGPoint(x: pa.midX, y: pa.midY), to: CGPoint(x: pb.midX, y: pb.midY)) else { return (0, 0) }
    var n = 0, inside = 0
    for q in 0..<sel.numberOfTextRanges(on: page) {
        let r = sel.range(at: q, on: page)
        for i in r.location..<(r.location + r.length) where posOf[i] != nil {
            n += 1
            if let li = lineOfIndex[i], members.contains(li) { inside += 1 }
        }
    }
    return (n, inside)
}
var cSel = 0, cIn = 0, nChains = 0, cLines = 0
var wSel = 0, wIn = 0, wN = 0, wClean = 0
for c in chains where c.count >= para {
    nChains += 1; cLines += c.count
    let (n, i) = drag(c.first!, c.last!, Set(c))
    cSel += n; cIn += i
    var j = 0
    while j + para <= c.count {
        let win = Array(c[j..<(j + para)])
        let (a, b) = drag(win.first!, win.last!, Set(win))
        wSel += a; wIn += b; wN += 1; if a == b { wClean += 1 }
        if verbose && a != b { print(String(format: "  leak %.0f%%: %@ … %@", 100.0 * Double(b) / Double(max(a, 1)), String(lines[win.first!].text.prefix(40)), String(lines[win.last!].text.prefix(40)))) }
        j += para
    }
}
// crossing: a line lying over lines of two chains of 6+ that stand side by side, whichever chain it is in
let longChain = Set(chains.enumerated().filter { $0.element.count >= para }.map { $0.offset })
var crossing = 0
for (k, l) in lines.enumerated() {
    // narrower lines l covers by 3+ characters' width, in its row and the rows beside it
    let under = lines.indices.filter { m in
        m != k && longChain.contains(chainOf[m]) && abs(lines[m].rect.midY - l.rect.midY) < 2.2 * h
            && overlap(l.rect, lines[m].rect) >= 1.5 * h && lines[m].rect.width < 0.9 * l.rect.width
    }
    let sideBySide = under.contains { a in
        under.contains { b in
            chainOf[a] != chainOf[b]
                && overlap(lines[a].rect, lines[b].rect) < 0.3 * min(lines[a].rect.width, lines[b].rect.width)
        }
    }
    if sideBySide { crossing += 1; if verbose { print("  crossing: \(l.text.prefix(100))") } }
}
print(String(format: "page %d: %d lines, median height %.1f; %d chains of %d+ lines hold %d lines", pageIndex + 1, lines.count, h, nChains, para, cLines))
print(String(format: "  lines crossing two chains: %d", crossing))
print(String(format: "  chain drags: %.1f%% in (%d of %d chars)", cSel > 0 ? 100.0 * Double(cIn) / Double(cSel) : 0, cIn, cSel))
print(String(format: "  %d-line drags: %d of %d clean, %.1f%% in (%d of %d chars)", para, wClean, wN, wSel > 0 ? 100.0 * Double(wIn) / Double(wSel) : 0, wIn, wSel))
