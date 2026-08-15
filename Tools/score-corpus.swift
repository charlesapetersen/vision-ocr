import AppKit
import PDFKit
import Foundation

// Scores one document through the shipped searchable-PDF pipeline.
// Output: one TSV line of metrics, or an error row. Reference boxes come from an
// independent OCR pass over the finished file, so the pipeline isn't grading
// itself with its own numbers.
struct B: Decodable { let x, y, width, height: Double }
struct O: Decodable { let boundingBox: B; let text: String }
struct P: Decodable { let page: Int; let observations: [O] }

let src = URL(fileURLWithPath: CommandLine.arguments[1])
let label = CommandLine.arguments[2]
let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("score-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

func fail(_ why: String) -> Never {
    print("\(label)\tFAIL\t\(why.replacingOccurrences(of: "\t", with: " "))")
    exit(0)
}

Prefs.register(migrate: false)
UserDefaults.standard.set(false, forKey: Prefs.openWhenDone)
if CommandLine.arguments.count > 3,
   let f = Double(CommandLine.arguments[3]) { SearchableWriter.headroomFactor = CGFloat(f) }
if CommandLine.arguments.count > 4,
   let v = Double(CommandLine.arguments[4]) { SearchableWriter.minimumVertical = CGFloat(v) }
if CommandLine.arguments.count > 5,
   let g = Double(CommandLine.arguments[5]) { SearchableWriter.reserveEms = CGFloat(g) }
guard let doc = PDFDocument(url: src), doc.pageCount > 0 else { fail("cannot open source") }

// Up to 3 pages spread through the document, skipping the cover.
let n = doc.pageCount
let wanted = n <= 3 ? Array(0..<n) : [min(1, n-1), n/2, min(n-1, n*3/4)]
let sample = PDFDocument()
for i in wanted { if let p = doc.page(at: i) { sample.insert(p, at: sample.pageCount) } }
let input = work.appendingPathComponent("in.pdf")
guard sample.write(to: input) else { fail("cannot write sample") }

// A12.2. Pulling pages into a fresh `PDFDocument` can change the resolution the
// rebuild renders them at, because `Flattener.largestImage` walks the page's
// `/Resources` — and 4 of 208 multi-page corpus documents give **every page one
// shared dictionary**, so in the whole file it answers "the largest image
// anywhere" and in the extract it answers "the largest image this page kept".
// Measured, production against this tool's own sample:
//
//     Batzell - Free Labor   p2   3142x4066 -> 2550x3300   1.52x in pixel area
//     AI 2027                p2   2929x4142 -> 1290x1824   5.16x
//     Kelly_2014             p1   2092x2664 -> 3359x4277   0.39x
//
// `qpdf --pages` does **not** avoid it — measured, it produces the identical
// wrong answer, so the usual "use qpdf when geometry is the question" does not
// apply here. And the divergence is not the tool's fault to fix: `BUGS.md` C24
// records that the app is answering a per-page question with a document-wide
// number, and why the obvious repair has no threshold to stand on.
//
// So the row says so. A measurement taken at a resolution production would not
// use is not this document's row, and printing it as one is how four
// `manifest.tsv` rows came to describe a pipeline nothing runs.
// Checked here, before the pipeline runs, and enforced immediately below: there is
// no point spending a full OCR pass on a row that is going to be refused.
//
// A page it cannot compare is a refusal, not a pass. The guard cannot reach that
// today — `wanted` holds no duplicates and no out-of-range index, for either arm
// of its expression — but "the check quietly did nothing" is the shape this
// project keeps paying for, and a `continue` here would be it.
var resolutionDrift: [String] = []
guard let extracted = PDFDocument(url: input) else { fail("cannot re-open the sample") }
guard extracted.pageCount == sample.pageCount else {
    fail("the sample lost pages on write: \(extracted.pageCount) of \(sample.pageCount)")
}
for (position, index) in wanted.enumerated() {
    guard let original = doc.page(at: index), let copy = extracted.page(at: position) else {
        fail("cannot compare page \(index + 1) against extracted position \(position + 1)")
    }
    let before = Flattener.rebuildDPI(of: original)
    let after = Flattener.rebuildDPI(of: copy)
    if abs(before - after) > 0.5 {
        resolutionDrift.append(String(format: "p%d %.0f->%.0f", index + 1, before, after))
    }
}
guard resolutionDrift.isEmpty else {
    print([label, "SKIP", "\(sample.pageCount)p",
           "extraction changed the rebuild resolution, so this row would not describe "
           + "the shipped pipeline (A12.2, BUGS.md C24): "
           + resolutionDrift.joined(separator: " ")].joined(separator: "\t"))
    exit(1)
}

let out = work.appendingPathComponent("out.pdf")
var outcome = "?"
var message = ""
let began = Date()
OCRModel.makeSearchablePDF(
    file: input, output: out,
    rebuild: true, rebuildMode: .auto, password: nil,
    control: RunControl(), progress: { _, _ in },
    report: { o, m in outcome = "\(o)"; message = m })
let seconds = Date().timeIntervalSince(began)
guard outcome == "succeeded" else { fail("pipeline \(outcome): \(message)") }
guard let result = PDFDocument(url: out) else { fail("output unreadable") }
guard result.pageCount == sample.pageCount else {
    fail("page count \(result.pageCount) != \(sample.pageCount)")
}

// Independent reference recognition of the finished file, in process. This used
// to shell out to mac-ocr for a second opinion; with the dependency gone the
// reference is `Recogniser` reading the published PDF back, which is still an
// independent read of the *output* rather than a reuse of the observations that
// produced it — that independence is the point, not the process boundary.
guard let byPage = try? Recogniser.recogniseDocument(visible: out, bitmaps: [],
                                                    settings: .current()) else {
    fail("reference recognition failed")
}
let pages = byPage.sorted { $0.key < $1.key }
    .map { (page: $0.key, observations: $0.value) }

var startOK = 0, startTotal = 0, endOK = 0, endTotal = 0
var offsets: [Double] = [], overlaps = 0, overlapPairs = 0
var refWords = 0, gotWords = 0
var offsetAmbiguous = 0, offsetUnplaced = 0

/// How many times `needle` occurs in `haystack`, stopping at two.
///
/// Reported, not enforced. A6.1 blames the offset artifact on a non-unique anchor
/// (`the` alone accounted for 33 of 87 outliers); measured over four pages and 161
/// lines, refusing every line whose first word repeats changes the median, the
/// p5..p95 and the range by nothing at all while discarding a third to two thirds
/// of the sample. The scan order is the whole fix. This count is kept because it
/// is the exposure a reader would want if the number ever moves.
func occurrences(of needle: String, in haystack: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var from = haystack.startIndex
    while let r = haystack.range(of: needle, range: from..<haystack.endIndex) {
        count += 1
        from = r.upperBound
        if count > 1 { break }
    }
    return count
}

// Nearest first, then outward. The old scan started at −1.2 and took the first
// hit, so it accepted the *lowest* step whose window still clipped this line's
// own glyphs — a systematic downward bias with no neighbouring line needed to
// explain it. Measured, changing nothing else: median −0.10 → 0.00 on two real
// pages. On a tie the upward step wins, because the glyphs sit above the box
// bottom by `baselineFraction`.
let offsetSteps = stride(from: -1.2, through: 1.2, by: 0.1)
    .map { ($0 * 10).rounded() / 10 }
    .sorted { (abs($0), -$0) < (abs($1), -$1) }

for pg in pages {
    guard let page = result.page(at: pg.page - 1) else { continue }
    let b = page.bounds(for: .mediaBox)
    let whole = page.string ?? ""
    let lines = pg.observations.filter { $0.text.count > 12 }
    for o in lines {
        let w = o.boundingBox.width * b.width, h = o.boundingBox.height * b.height
        let x = b.minX + o.boundingBox.x * b.width
        let bottom = b.maxY - o.boundingBox.y * b.height - h
        guard w > 2, h > 2 else { continue }
        func probe(_ r: CGRect) -> String {
            page.selection(for: r)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        startTotal += 1; endTotal += 1
        if !probe(CGRect(x: x, y: bottom, width: w * 0.15, height: h)).isEmpty { startOK += 1 }
        if !probe(CGRect(x: x + w * 0.85, y: bottom, width: w * 0.15, height: h)).isEmpty { endOK += 1 }
        // Where does this line's own text actually sit?
        let first = String(o.text.split(separator: " ").first ?? "").prefix(6)
        if first.count >= 3 {
            if occurrences(of: String(first), in: whole) != 1 { offsetAmbiguous += 1 }
            var found = false
            for step in offsetSteps {
                if probe(CGRect(x: x, y: bottom + h * step,
                                width: w * 0.2, height: h * 0.5)).contains(first) {
                    offsets.append(step); found = true; break
                }
            }
            if !found { offsetUnplaced += 1 }
        }
    }
    // Vertical overlap between horizontally-overlapping lines.
    //
    // NOT A MEASURE OF THIS APP'S TEXT LAYER. Every value here comes from
    // `pg.observations` — the reference OCR, which reads the rendered *image*.
    // The text layer is invisible, so this number cannot respond to any
    // SearchableWriter change, and quoting it as "our runs don't overlap" is
    // circular. It says how tightly the SOURCE is set, which is why the manifest
    // calls it source line tightness. The metric for the text layer is
    // Tools/score-line-separation.swift, and comparing it before and after needs
    // two separately-compiled binaries — one from each revision.
    let sorted = lines.sorted { $0.boundingBox.y < $1.boundingBox.y }
    for i in 0..<max(sorted.count - 1, 0) {
        let a = sorted[i], c = sorted[i+1]
        let aL = a.boundingBox.x, aR = aL + a.boundingBox.width
        let cL = c.boundingBox.x, cR = cL + c.boundingBox.width
        guard min(aR, cR) - max(aL, cL) > 0.02 else { continue }
        overlapPairs += 1
        let gap = (c.boundingBox.y - a.boundingBox.y) * b.height
        if gap < a.boundingBox.height * b.height * 0.6 { overlaps += 1 }
    }
    refWords += pg.observations.flatMap { $0.text.split(separator: " ") }.count
    gotWords += (page.string ?? "").split(whereSeparator: { $0 == " " || $0 == "\n" }).count
}

offsets.sort()
let median = offsets.isEmpty ? Double.nan : offsets[offsets.count/2]
func pct(_ a: Int, _ b: Int) -> String { b == 0 ? "-" : String(Int(100.0*Double(a)/Double(b))) }

// A6.1 (d): this printed the literal `OK` on any run that reached the end, so a
// document whose reference read nothing came out as
// `OK 2p start=-% end=-% off=nan words=-%` — a pass, in dashes, over no
// measurement at all. That is the false-green shape T12 fixed twice elsewhere
// (`score-annotations` skipping every mark and exiting 0; `mutate.py` reporting a
// clean bill for four mutants it never applied), and it is the one this file
// itself is meant to catch in the pipeline.
//
// Two populations, deliberately named apart, because they are different faults
// and only one of them is the instrument's:
//
//  - no reference LINES over 12 characters → nothing to probe. Either the page
//    genuinely holds no running text, or the reference OCR has collapsed. A6.2
//    found three corpus documents whose reference read has collapsed outright.
//  - no reference WORDS at all → the reference read nothing, full stop, and the
//    `words=` column — the one column A6.1 says still holds — has no denominator.
//
// A SKIP does not exit 0. T12's rule: a skip that exits 0 is a pass wearing a
// different word.
var missing: [String] = []
if startTotal == 0 { missing.append("no reference line over 12 characters") }
if refWords == 0 { missing.append("the reference read no words at all") }
guard missing.isEmpty else {
    print([label, "SKIP", "\(sample.pageCount)p",
           "measured nothing: \(missing.joined(separator: "; "))",
           "reference observations=\(pages.reduce(0) { $0 + $1.observations.count })",
           "output characters=\(result.string?.count ?? 0)",
           String(format: "%.0fs", seconds)].joined(separator: "\t"))
    exit(1)
}
print([label, "OK", "\(sample.pageCount)p",
       "start=\(pct(startOK, startTotal))%", "end=\(pct(endOK, endTotal))%",
       offsets.isEmpty ? "off=-" : String(format: "off=%+.2f", median),
       "offn=\(offsets.count)/\(offsets.count + offsetAmbiguous + offsetUnplaced)",
       "overlap=\(overlaps)/\(overlapPairs)",
       "words=\(pct(gotWords, refWords))%",
       String(format: "%.0fs", seconds)].joined(separator: "\t"))
