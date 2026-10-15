import Foundation
import ImageIO
import PDFKit

// score-page-hand <list.tsv>: page-kind-handwriting's measure. Each row of the list is
// `id <TAB> file <TAB> page <TAB> label`, a PDF page or an image (page 1), label `hand` or
// anything else. An image is wrapped as `makeSearchablePDF` wraps it; the page is recognised as
// the no-rebuild route does (`Recogniser.render`, `recognisePage`, `fittedToGutters`, as
// `score-page-kind`), and this prints `Recogniser.handSignals` of that reading and
// `Recogniser.isHandwritten`'s call. Writes nothing but stdout and a scratch directory it
// removes. Exit 1 when a page is called against its label or cannot be read (an `unread` row),
// 2 when the list is unreadable or empty.
// Built with `Sources/`.

Prefs.register(migrate: false)
let settings = Prefs.Snapshot.current()
guard CommandLine.arguments.count == 2,
      let list = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8) else {
    FileHandle.standardError.write(Data("usage: score-page-hand <list.tsv>\n".utf8)); exit(2)
}
let scratch = FileManager.default.temporaryDirectory
    .appendingPathComponent("score-page-hand-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
print(["id", "label", "call", "lines", "letters_per_mark", "foot_jitter", "foot_residual", "joined", "file", "page"]
      .joined(separator: "\t"))
// HANDLINES=<file>: one row a measured line (`Recogniser.HandLine`: id, label, letters, marks,
// foot jitter, foot residual, text), for tuning the rule.
let perLine: FileHandle? = ProcessInfo.processInfo.environment["HANDLINES"].flatMap {
    FileManager.default.createFile(atPath: $0, contents: nil)
    return FileHandle(forWritingAtPath: $0)
}
var wrong = 0, unread = 0, measured = 0
for row in list.split(whereSeparator: \.isNewline) where !row.hasPrefix("#") {
    let f = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 4, let n = Int(f[2]), n >= 1 else {
        FileHandle.standardError.write(Data("unreadable row: \(row)\n".utf8)); exit(2)
    }
    measured += 1
    autoreleasepool {
        var url = URL(fileURLWithPath: f[1])
        if url.pathExtension.lowercased() != "pdf" {
            guard let wrapped = Flattener.wrapImage(url, into: scratch) else {
                print("\(f[0])\t\(f[3])\tunread"); unread += 1; return
            }
            url = wrapped
        }
        guard let page = PDFDocument(url: url)?.page(at: n - 1),
              let image = Recogniser.render(page, settings: settings),
              let read = try? Recogniser.recognisePage(image, settings: settings) else {
            print("\(f[0])\t\(f[3])\tunread"); unread += 1; return
        }
        let lines = Recogniser.fittedToGutters(read, of: image)
        let s = Recogniser.handSignals(of: lines, image: image)
        let hand = Recogniser.isHandwritten(s)
        if hand != (f[3] == "hand") { wrong += 1 }
        if let perLine {
            for l in s.measured {
                perLine.write(Data("\(f[0])\t\(f[3])\t\(l.letters)\t\(l.marks)\t"
                    .appending(String(format: "%.3f\t%.4f\t", l.footJitter, l.footResidual))
                    .appending(lines[l.index].text.replacingOccurrences(of: "\t", with: " ") + "\n").utf8))
            }
        }
        print([f[0], f[3], hand ? "hand" : "-", "\(s.lines)", String(format: "%.2f", s.lettersPerMark),
               String(format: "%.3f", s.footJitter), String(format: "%.4f", s.footResidual),
               String(format: "%.2f", s.joined), f[1], f[2]].joined(separator: "\t"))
        fflush(stdout)
    }
}
FileHandle.standardError.write(Data("\(wrong) of \(measured) page(s) called against their label, \(unread) unread\n".utf8))
try? FileManager.default.removeItem(at: scratch)
if measured == 0 { exit(2) }
exit(wrong == 0 && unread == 0 ? 0 : 1)
