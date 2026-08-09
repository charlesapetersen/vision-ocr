import PDFKit
import Foundation
// Do the recognised lines survive as SEPARATE lines in the finished PDF?
// This is the metric that matches the reported bug: merged runs make a drag
// selection skip a line.
struct B: Decodable { let x, y, width, height: Double }
struct O: Decodable { let boundingBox: B; let text: String }
struct P: Decodable { let page: Int; let observations: [O] }
let src = URL(fileURLWithPath: CommandLine.arguments[1])
let label = CommandLine.arguments[2]
let work = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ln-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }
Prefs.register(); UserDefaults.standard.set(false, forKey: Prefs.openWhenDone)
if CommandLine.arguments.count > 3,
   let f = Double(CommandLine.arguments[3]) { SearchableWriter.headroomFactor = CGFloat(f) }
guard let binary = Runner.resolveBinary(), let doc = PDFDocument(url: src), doc.pageCount > 0
else { print("\(label)\tFAIL"); exit(0) }
let idx = doc.pageCount <= 3 ? Array(0..<doc.pageCount) : [1, doc.pageCount/2, doc.pageCount*3/4]
let s = PDFDocument()
for i in idx { if let p = doc.page(at: i) { s.insert(p, at: s.pageCount) } }
let input = work.appendingPathComponent("in.pdf"); _ = s.write(to: input)
let out = work.appendingPathComponent("out.pdf")
var ok = false
OCRModel.makeSearchablePDF(file: input, binary: binary, output: out, rebuild: true,
    rebuildMode: .auto, password: nil, control: RunControl(), progress: { _, _ in },
    report: { o, _ in ok = (o == .succeeded) })
guard ok, let res = PDFDocument(url: out) else { print("\(label)\tFAIL"); exit(0) }
let js = work.appendingPathComponent("r.json")
_ = Runner.run(binary: binary, file: out, outputFolder: nil,
    argumentsOverride: [out.path, "--format", "json", "-o", js.path] + Runner.recognitionArguments(),
    register: { _ in })
guard let d = try? Data(contentsOf: js),
      let pages = try? JSONDecoder().decode([P].self, from: d) else { print("\(label)\tFAIL"); exit(0) }
var expected = 0, extracted = 0
for pg in pages {
    guard let page = res.page(at: pg.page - 1) else { continue }
    expected += pg.observations.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.count
    extracted += (page.string ?? "").components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
}
let ratio = expected == 0 ? 0 : 100 * extracted / expected
print("\(label)\t\(extracted)/\(expected) lines kept separate\t\(ratio)%")
