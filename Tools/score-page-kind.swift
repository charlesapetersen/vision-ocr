import Foundation
import PDFKit

// score-page-kind <list.tsv>: ocr-newspaper-detect's measure. Each row of the list is
// `id <TAB> file <TAB> page <TAB> label`, a PDF page or an image (page 1); this
// recognises the page as the no-rebuild route does (`Recogniser.recognisePage` and
// `fittedToGutters` on `Recogniser.render`'s plain render, not `Flattener.flatten`'s
// rebuilt bitmap, nor the rebuild route's finer and grey readings) and
// prints one row per page: its size in points (0 for an image), whether `Flattener.mosaic` calls it a
// paste-up, `Recogniser.pageShape`'s signals, `Recogniser.pageKind`'s call and the label.
// Reads only; writes nothing but stdout.

Prefs.register(migrate: false)
let settings = Prefs.Snapshot.current()
guard CommandLine.arguments.count == 2,
      let list = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8) else {
    FileHandle.standardError.write(Data("usage: score-page-kind <list.tsv>\n".utf8)); exit(2)
}
print(["id", "label", "call", "wPt", "hPt", "mosaic", "lines", "wideW", "file", "page"]
      .joined(separator: "\t"))
for row in list.split(separator: "\n") where !row.hasPrefix("#") {
    let f = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 4, let pageNumber = Int(f[2]) else { continue }
    autoreleasepool {
        let url = URL(fileURLWithPath: f[1])
        var image: CGImage?, size = CGSize.zero, mosaic = false
        if let doc = PDFDocument(url: url) {
            // A page the PDF does not have is unread, not its first page decoded as an image.
            if let page = doc.page(at: pageNumber - 1) {
                image = Recogniser.render(page, settings: settings)
                size = Flattener.displayBox(of: page).size
                mosaic = Flattener.mosaic(of: page) != nil
            }
        } else if pageNumber == 1 {
            image = Recogniser.loadImage(at: url)
        }
        // The no-rebuild route's lines, gutters fitted, as `recogniseDocument` hands them on.
        guard let image, let read = try? Recogniser.recognisePage(image, settings: settings) else {
            print("\(f[0])\t\(f[3])\tunread"); return
        }
        let lines = Recogniser.fittedToGutters(read, of: image)
        let s = Recogniser.pageShape(of: lines)
        let call = Recogniser.pageKind(shape: s, pasteUp: mosaic).rawValue
        print([f[0], f[3], call, String(format: "%.0f", size.width), String(format: "%.0f", size.height),
               mosaic ? "1" : "0", "\(s.lines)", String(format: "%.3f", s.wideWidth),
               f[1], f[2]].joined(separator: "\t"))
        fflush(stdout)
    }
}
