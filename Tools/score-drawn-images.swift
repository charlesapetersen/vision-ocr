// C24's open half: what does each page **draw**, against what its `/Resources` reaches?
//
// `Flattener.largestImage` walks the page's resource dictionary, and 4 of the corpus's 208
// multi-page documents share one dictionary across every page. The structural half closed
// in 2026-08-16 — a page that invokes no XObject at all now has no image — and **45 pages
// remain that invoke a *different* image than the shared dictionary holds**, so they still
// take a neighbour's plate resolution. This tool is what measured them: **39 smaller and 6
// wider**, and the entry's word for all 45 was "smaller". See the `wider` note below.
//
// Restricting the walk to the invoked names is structural and needs no threshold, which is
// why `Flattener.drawnLargestImage` exists. This header said it needed a constant
// recalibrated first: `minimumScanPixelWidth = 600` separated 47 logos of 16–96 px from 37
// page-sized scans of 1936–2592 px, measured against each document's **maximum**, and C24's
// first repair sent `Batzell` p22 from 369.6 DPI to **70.6** because that page's own figure
// is 600 px wide. It then said "rendering a page of type at 70 DPI is C9 again", **which was
// reasoned and is measured false** — `Tools/score-rebuild-dpi.swift`, C24 2026-08-17: p22 at
// 70.6 DPI retains 92.8% of its own words against 94.2% at 369.6, and the constant judges
// all three of the pages it faces correctly. No recalibration is wanted; the population
// below is still what a corpus gate run needs to read.
//
// **This produces the population that constant would actually face.** One row per page, no
// rendering and no OCR, so it is metadata-speed. The policy applied to the drawn
// measurement is `Flattener.rebuildDPI(from:)` itself — the shipped three branches, not a
// copy of them, because T15 is what a drifting copy costs.
//
//   mkdir -p /tmp/d && cp Tools/score-drawn-images.swift /tmp/d/main.swift
//   swiftc -O -o /tmp/drawn -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/d/main.swift
//   /tmp/drawn testdocs/*/*.pdf > drawn.tsv
//
// Rows stream in **input order**, one document at a time, because the census's own diff
// recipe was wrong for exactly the opposite reason: it streamed in completion order while
// its header claimed input order, and the `diff` it prescribed reported 5,370 changed lines
// over 210 changed pages. Nothing here is concurrent, so the order is the argument order.
//
// The interesting query is the last column:
//
//   awk -F'\t' 'NR>1 && $12!="agree"' drawn.tsv | cut -f12 | sort | uniq -c
//   awk -F'\t' 'NR>1 && $12=="smaller"' drawn.tsv          # C24's open population
//
// and the recalibration question is the drawn pixel width of every page whose drawn DPI
// falls below `minimumPlausibleScanDPI`:
//
//   awk -F'\t' 'NR>1 && $9!="-" && $9+0 < 150' drawn.tsv | cut -f1,2,8,9
import Foundation
import PDFKit

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else {
    FileHandle.standardError.write(
        Data("usage: score-drawn-images <pdf> [pdf …]   (one row per page, TSV on stdout)\n".utf8))
    exit(2)
}

// One printer over one array. Counting tab escapes by eye has put the wrong number of
// fields under a header three times here — T14's SKIP row, A12.3's `score-mrc`, T18's two.
let columns = ["document", "page", "drawsAny",
               "dictWidth", "dictDPI", "shippedRebuildDPI",
               "drawnKind", "drawnWidth", "drawnDPI", "drawnRebuildDPI",
               "policyMoves", "verdict"]

func row(_ fields: [String]) {
    precondition(fields.count == columns.count,
                 "row has \(fields.count) fields against \(columns.count) columns")
    print(fields.joined(separator: "\t"))
}

print(columns.joined(separator: "\t"))

func dpi(_ v: Double?) -> String { v == nil ? "-" : String(format: "%.1f", v!) }

var totals: [String: Int] = [:]
var pagesSeen = 0
var documentsSeen = 0

for path in args {
    let url = URL(fileURLWithPath: path)
    guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
        FileHandle.standardError.write(Data("skip \(path): unreadable\n".utf8))
        continue
    }
    documentsSeen += 1
    let name = url.deletingPathExtension().lastPathComponent
    for i in 0..<doc.pageCount {
        guard let page = doc.page(at: i) else {
            FileHandle.standardError.write(Data("skip \(name) p\(i + 1): unreadable page\n".utf8))
            continue
        }
        pagesSeen += 1

        let draws = Flattener.drawsAnyXObject(page)
        let dict = Flattener.largestImage(of: page)
        let shipped = Flattener.rebuildDPI(of: page)
        let drawn = Flattener.drawnLargestImage(of: page)

        var kind = "", drawnWidth = "-", drawnDPI = "-"
        var drawnRebuild: Double
        switch drawn {
        case .unreadable:
            kind = "unreadable"
            // What a caller must do with "could not tell": the `/Resources` answer.
            drawnRebuild = shipped
        case .noImage:
            kind = "none"
            drawnRebuild = Flattener.rebuildDPI(from: nil)
        case let .largest(d, w):
            kind = "largest"
            drawnWidth = String(w)
            drawnDPI = String(format: "%.1f", d)
            drawnRebuild = Flattener.rebuildDPI(from: (dpi: d, pixelWidth: w))
        }

        // The verdict compares the two *measurements*; `policyMoves` compares what the
        // shipped policy does with each. They are different questions, and C24's structural
        // half is the case where the first moved and the second did not on 0 pages of 128.
        //
        // **`wider` is not an anomaly, and reading it as one is how C24 came to carry an
        // observation without a cause.** Both walks pick the largest image by *area* and
        // then report its *width*, so the drawn subset's winner can be wider than the whole
        // dictionary's. `AI 2027` p4 draws only `/Im5`, 3000x1011 — while the dictionary's
        // largest by area is `/Im52`, 2929x2370. Neither walk has missed a candidate. The
        // entry's proposed cause was the `walkedAt` memo; that was tested and refuted, and
        // this is what was actually happening.
        //
        // **The drawn answer is asked about first, and the order is the whole correctness of
        // this column.** It read `case (nil, _)` first, which filed every page whose
        // dictionary walk found nothing as `noDictImage` *whatever the drawn walk said* — and
        // an unresolvable name is most likely on exactly such a page, so the `unreadable`
        // count was "unreadable pages that also had a dictionary image" while the register
        // quoted it as the number of pages this could not read. Found by the review of this
        // diff. On the 16,987-page corpus it changed no row — all 285 `noDictImage` pages
        // report `drawnKind=none` — so the count it published was right by luck rather than
        // by construction.
        let verdict: String
        switch (dict, drawn) {
        case (_, .unreadable):
            verdict = "unreadable"
        case (nil, .noImage):
            // Both walks agree there is nothing here. C24's structural half made this the
            // common case: `largestImage` now returns nil on a page that invokes no XObject.
            verdict = "noDictImage"
        case (_, .noImage):
            verdict = "drawsNoImage"
        case (nil, .largest):
            // The drawn walk found an image the dictionary walk did not. **0 pages of 16,987**
            // — named rather than folded into `noDictImage`, because folding it is the defect
            // above and because a caps disagreement between the two walks would land here.
            verdict = "drawnOnly"
        case let (d?, .largest(_, w)):
            if w == d.pixelWidth { verdict = "agree" }
            else if w < d.pixelWidth { verdict = "smaller" }
            else { verdict = "wider" }
        }
        totals[verdict, default: 0] += 1

        row([name, String(i + 1),
             draws == nil ? "unknown" : (draws! ? "yes" : "no"),
             dict == nil ? "-" : String(dict!.pixelWidth), dpi(dict?.dpi), dpi(shipped),
             kind, drawnWidth, drawnDPI, dpi(drawnRebuild),
             abs(drawnRebuild - shipped) < 0.05 ? "same" : "moves",
             verdict])
    }
    fflush(stdout)
}

// To stderr, so the TSV on stdout stays a TSV.
var summary = "\n\(documentsSeen) documents, \(pagesSeen) pages\n"
for (verdict, n) in totals.sorted(by: { $0.value > $1.value }) {
    // Padded in Swift rather than with `%-14s`, which needs a C string and therefore a
    // force-unwrapped `utf8String` — a crash in the summary of a completed sweep.
    let label = verdict.padding(toLength: max(14, verdict.count), withPad: " ",
                                startingAt: 0)
    summary += "  \(label) \(String(format: "%6d", n))\n"
}
FileHandle.standardError.write(Data(summary.utf8))
