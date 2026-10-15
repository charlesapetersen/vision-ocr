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
// REBUILD=1 takes the app's route instead (hw-settings): the page is rebuilt as `makeSearchablePDF`
// rebuilds it (`Flattener.flatten`, the stored rebuild mode, photographs looked for) and read by
// `recognisePage(at:)` with a reader set for handwriting and another for every other kind, two
// scripts that say which of them was run; `call` is the reader production chose, and the signal
// columns are blank.
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
let rebuild = ProcessInfo.processInfo.environment["REBUILD"] == "1"
let ran = scratch.appendingPathComponent("ran.txt")
func script(_ name: String) -> String {
    let url = scratch.appendingPathComponent(name)
    try? "#!/bin/sh\necho \(name) >> '\(ran.path)'\nprintf 'x\\n' > \"$2\"\n"
        .write(to: url, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url.path
}
var routed = settings
routed.modelArrangement = .align
routed.modelReader = script("other.sh")
routed.handModelArrangement = .align
routed.handModelReader = script("hand.sh")
let mode = Flattener.Mode(rawValue: Prefs.store.string(forKey: Prefs.rebuildMode) ?? "") ?? .auto
for row in list.split(whereSeparator: \.isNewline) where !row.hasPrefix("#") {
    let f = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 4, let n = Int(f[2]), n >= 1 else {
        FileHandle.standardError.write(Data("unreadable row: \(row)\n".utf8)); exit(2)
    }
    measured += 1
    autoreleasepool {
        var url = URL(fileURLWithPath: f[1])
        let camera = url.pathExtension.lowercased() != "pdf" && Flattener.cameraExposed(
            CGImageSourceCreateWithURL(url as CFURL, nil)
                .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] })
        if url.pathExtension.lowercased() != "pdf" {
            guard let wrapped = Flattener.wrapImage(url, into: scratch) else {
                print("\(f[0])\t\(f[3])\tunread"); unread += 1; return
            }
            url = wrapped
        }
        if rebuild {
            // One page, rebuilt alone, as a one-page document of it would be.
            guard let doc = PDFDocument(url: url), let page = doc.page(at: n - 1) else {
                print("\(f[0])\t\(f[3])\tunread"); unread += 1; return
            }
            let one = PDFDocument(), single = scratch.appendingPathComponent("page.pdf")
            one.insert(page, at: 0)
            let pngs = scratch.appendingPathComponent("pages-\(f[0])")
            try? FileManager.default.createDirectory(at: pngs, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: ran)
            guard one.write(to: single),
                  let bitmaps = try? Flattener.flatten(
                      single, to: scratch.appendingPathComponent("rebuilt.pdf"), mode: mode, pngDirectory: pngs,
                      passThrough: Set(Flattener.digitalPageRoutes(in: single).passThrough),
                      findPhotographs: routed.photographsApart, cameraExposed: camera,
                      findHandwriting: routed.handwritingApart),
                  let first = bitmaps.first else { print("\(f[0])\t\(f[3])\tunread"); unread += 1; return }
            // A born-digital page is copied through, never recognised, so never judged.
            guard let image = Recogniser.imageURL(of: first) else { print("\(f[0])\t\(f[3])\tkept"); return }
            guard (try? Recogniser.recognisePage(at: image, settings: routed, onModelFallback: { _, _ in })) != nil
            else { print("\(f[0])\t\(f[3])\tunread"); unread += 1; return }
            // HANDIMAGES=1: the signals on each bitmap `flatten` left beside the page.
            if ProcessInfo.processInfo.environment["HANDIMAGES"] == "1",
               let lines = try? Recogniser.recognisePage(at: image, settings: settings, onModelFallback: { _, _ in }) {
                let names = ((try? FileManager.default.contentsOfDirectory(atPath: pngs.path)) ?? []).sorted()
                    .filter { [".png", ".jpg"].contains(where: $0.hasSuffix) } + ["render"]
                for name in names {
                    // `render`: the source page as the no-rebuild route renders it.
                    guard let bitmap = name == "render" ? PDFDocument(url: single)?.page(at: 0)
                            .flatMap({ Recogniser.render($0, settings: settings) })
                            : CGImageSourceCreateWithURL(pngs.appendingPathComponent(name) as CFURL, nil)
                            .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) else { continue }
                    let s = Recogniser.handSignals(of: lines, image: bitmap)
                    FileHandle.standardError.write(Data(([f[0], name, "\(bitmap.width)x\(bitmap.height)",
                        "bpc \(bitmap.bitsPerComponent)", Recogniser.isHandwritten(s) ? "hand" : "-", "\(s.lines)",
                        String(format: "%.2f", s.lettersPerMark), String(format: "%.3f", s.footJitter),
                        String(format: "%.4f", s.footResidual), String(format: "%.2f", s.joined)]
                        .joined(separator: "\t") + "\n").utf8))
                }
            }
            let readers = (try? String(contentsOf: ran, encoding: .utf8)) ?? ""
            let hand = readers.contains("hand.sh")
            if hand != (f[3] == "hand") { wrong += 1 }
            print([f[0], f[3], hand ? "hand" : readers.contains("other.sh") ? "-" : "none",
                   "", "", "", "", "", f[1], f[2]].joined(separator: "\t"))
            try? FileManager.default.removeItem(at: pngs)
            fflush(stdout)
            return
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
