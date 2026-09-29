import Foundation
import Vision
import ImageIO
// vision-read <image.png>...
// Vision's reading of the reader's own page image, for the cross-check in procedure.md step 4: one
// recognised line per output line. Revision 3, accurate, language correction on: the
// app's defaults. It is Vision on a plain render, not the app's pipeline (CLAUDE.md, last trap).
// Given several images (a page's crops), reads each in turn: Vision scales a large page down, and on a
// 300 dpi newspaper page it read 1,047 of the 3,315 words the reader found (Raskin p1).
let a = CommandLine.arguments
guard a.count >= 2 else { print("usage: vision-read <image.png>..."); exit(2) }
for path in a.dropFirst() {
    autoreleasepool {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("cannot read \(path)"); exit(1) }
        let req = VNRecognizeTextRequest()
        req.revision = VNRecognizeTextRequestRevision3
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
        // Vision's own result order, which follows columns; a sort by row would interleave them.
        for o in req.results ?? [] { if let s = o.topCandidates(1).first?.string { print(s) } }
    }
}
