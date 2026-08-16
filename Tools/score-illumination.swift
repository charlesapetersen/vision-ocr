// R55: is the illumination gradient *consistent* across a document's pages?
//
// `classify-source` calls a document `photographed` when its median 3x3 illumination
// gradient exceeds 0.16, and R55 records the owner's ruling that only **hand-held**
// photographs are `photographed` — an upright or planetary scanner capture is a scan.
// The threshold cannot express that, because it separates *evenly lit* from *unevenly
// lit* and the ruling needs *hand-held* separated from *mechanical*.
//
// The entry proposes the discriminator and does not measure it: **a rig repeats and
// hands do not.** `Why?` (1954), the document that opened R55, has five sampled pages
// whose nine block means agree to within 1.5 luminance levels. This measures that
// agreement over two populations.
//
//   mkdir -p /tmp/h && cp Tools/score-illumination.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/illum -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/illum scanned testdocs/*/*.pdf
//   tr '\n' '\0' < list.txt | xargs -0 /tmp/illum handheld
//
// `<label>` names the population and is copied into column 1, so two runs concatenate.
// **Use `xargs -0`, not `xargs -d`** — BSD xargs has no `-d`, and the first run of this
// silently measured nothing and printed a header, which is the shape of failure this
// repo's environment notes are full of.
//
// What it found, 2026-08-16, is in BUGS.md R55: no mechanical scan in 204 exceeds
// 0.0373, so this rules a flatbed *out*; it does not rule hand-held *in*, because
// `illuminationGradient` averages pixels above 140 and on a nearly black page those are
// content rather than paper. The highest score in the whole survey set is a full-bleed
// magazine advertisement.
//
// The gradient itself is `classify-source`'s function, character for character, so the
// column named `gradient` here is the column that decides the verdict there. Copying it
// is the one thing this file does that it should not have to: `illuminationGradient` is
// top-level code in a tool, so it cannot be imported. If it moves into `Sources/`, delete
// this copy — BUGS.md T15 is what a drifting copy costs.
import AppKit
import Foundation
import PDFKit

func illuminationBlocks(_ grey: [UInt8], width: Int, height: Int) -> [Double]? {
    guard width > 30, height > 30 else { return nil }
    var means: [Double] = []
    for by in 0..<3 {
        for bx in 0..<3 {
            let x0 = bx * width / 3, x1 = (bx + 1) * width / 3
            let y0 = by * height / 3, y1 = (by + 1) * height / 3
            var sum = 0.0, n = 0
            for y in stride(from: y0, to: y1, by: 2) {
                for x in stride(from: x0, to: x1, by: 2) {
                    let v = Double(grey[y * width + x])
                    if v > 140 { sum += v; n += 1 }
                }
            }
            means.append(n > 50 ? sum / Double(n) : -1)
        }
    }
    return means.contains(-1) ? nil : means
}

func gradient(_ blocks: [Double]) -> Double {
    guard let hi = blocks.max(), let lo = blocks.min(), hi > 0 else { return 0 }
    return (hi - lo) / hi
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: r55 <label> <pdf> [pdf …]\n".utf8)); exit(2)
}
let label = args[0]

let columns = ["population", "document", "pages", "gradient", "repeatability",
               "worstBlock", "meanLevel"]
print(columns.joined(separator: "\t"))

for path in args.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { continue }
    let name = url.deletingPathExtension().lastPathComponent
    // The same sample `classify-source` takes.
    let indices = Flattener.sampleIndices(count: doc.pageCount, wanted: 5)
    var perPage: [[Double]] = []
    for i in indices {
        guard let page = doc.page(at: i) else { continue }
        let box = Flattener.fullBox(of: page)
        guard box.width > 0, box.height > 0 else { continue }
        // A small fixed render: this is a lighting question, not a detail one, and a
        // fixed size makes documents comparable whatever they were scanned at.
        let w = 600, h = max(Int(600 * box.height / box.width), 1)
        guard let grey = Flattener.renderGrey(page, box: box,
                                              scale: CGFloat(w) / box.width,
                                              width: w, height: h, from: .mediaBox),
              let blocks = illuminationBlocks(grey, width: w, height: h) else { continue }
        perPage.append(blocks)
    }
    guard perPage.count >= 3 else {
        FileHandle.standardError.write(
            Data("skip \(name): only \(perPage.count) of \(indices.count) pages measured\n".utf8))
        continue
    }

    let gradients = perPage.map(gradient).sorted()
    let medianGradient = gradients[gradients.count / 2]

    // **Repeatability.** Each page's nine blocks are divided by that page's own
    // brightest, so overall exposure drops out and only the *shape* of the lighting
    // remains. Then, per block position, the spread of that shape across pages. A rig
    // produces the same shape every time and this is near zero; hands move between
    // frames and it is not.
    var spreads: [Double] = []
    for b in 0..<9 {
        let values = perPage.compactMap { page -> Double? in
            guard let hi = page.max(), hi > 0 else { return nil }
            return page[b] / hi
        }
        guard values.count >= 3 else { continue }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +)
            / Double(values.count)
        spreads.append(variance.squareRoot())
    }
    guard !spreads.isEmpty else { continue }
    let repeatability = spreads.reduce(0, +) / Double(spreads.count)
    let worst = spreads.max() ?? 0
    let level = perPage.flatMap { $0 }.reduce(0, +) / Double(perPage.count * 9)

    print([label, name, String(perPage.count),
           String(format: "%.4f", medianGradient),
           String(format: "%.4f", repeatability),
           String(format: "%.4f", worst),
           String(format: "%.1f", level)].joined(separator: "\t"))
    fflush(stdout)
}
