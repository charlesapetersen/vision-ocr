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

Prefs.register()
UserDefaults.standard.set(false, forKey: Prefs.openWhenDone)
if CommandLine.arguments.count > 3,
   let f = Double(CommandLine.arguments[3]) { SearchableWriter.headroomFactor = CGFloat(f) }
if CommandLine.arguments.count > 4,
   let v = Double(CommandLine.arguments[4]) { SearchableWriter.minimumVertical = CGFloat(v) }
if CommandLine.arguments.count > 5,
   let g = Double(CommandLine.arguments[5]) { SearchableWriter.reserveEms = CGFloat(g) }
guard let binary = Runner.resolveBinary() else { fail("no mac-ocr") }
guard let doc = PDFDocument(url: src), doc.pageCount > 0 else { fail("cannot open source") }

// Up to 3 pages spread through the document, skipping the cover.
let n = doc.pageCount
let wanted = n <= 3 ? Array(0..<n) : [min(1, n-1), n/2, min(n-1, n*3/4)]
let sample = PDFDocument()
for i in wanted { if let p = doc.page(at: i) { sample.insert(p, at: sample.pageCount) } }
let input = work.appendingPathComponent("in.pdf")
guard sample.write(to: input) else { fail("cannot write sample") }

let out = work.appendingPathComponent("out.pdf")
var outcome = "?"
var message = ""
let began = Date()
OCRModel.makeSearchablePDF(
    file: input, binary: binary, output: out,
    rebuild: true, rebuildMode: .auto, password: nil,
    control: RunControl(), progress: { _, _ in },
    report: { o, m in outcome = "\(o)"; message = m })
let seconds = Date().timeIntervalSince(began)
guard outcome == "succeeded" else { fail("pipeline \(outcome): \(message)") }
guard let result = PDFDocument(url: out) else { fail("output unreadable") }
guard result.pageCount == sample.pageCount else {
    fail("page count \(result.pageCount) != \(sample.pageCount)")
}

// Independent reference OCR of the finished file.
let refJSON = work.appendingPathComponent("ref.json")
let r = Runner.run(binary: binary, file: out, outputFolder: nil,
                   argumentsOverride: [out.path, "--format", "json", "-o", refJSON.path]
                       + Runner.recognitionArguments(),
                   register: { _ in })
guard r.succeeded, let data = try? Data(contentsOf: refJSON),
      let pages = try? JSONDecoder().decode([P].self, from: data) else {
    fail("reference OCR failed")
}

var startOK = 0, startTotal = 0, endOK = 0, endTotal = 0
var offsets: [Double] = [], overlaps = 0, overlapPairs = 0
var refWords = 0, gotWords = 0

for pg in pages {
    guard let page = result.page(at: pg.page - 1) else { continue }
    let b = page.bounds(for: .mediaBox)
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
            for step in stride(from: -1.2, through: 1.2, by: 0.1) {
                if probe(CGRect(x: x, y: bottom + h * step,
                                width: w * 0.2, height: h * 0.5)).contains(first) {
                    offsets.append(step); break
                }
            }
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
print([label, "OK", "\(sample.pageCount)p",
       "start=\(pct(startOK, startTotal))%", "end=\(pct(endOK, endTotal))%",
       String(format: "off=%+.2f", median),
       "overlap=\(overlaps)/\(overlapPairs)",
       "words=\(pct(gotWords, refWords))%",
       String(format: "%.0fs", seconds)].joined(separator: "\t"))
