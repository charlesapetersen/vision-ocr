// C24, closed: what does each page **draw**, against what its `/Resources` reaches?
//
// `Flattener.largestImage` walks the page's resource dictionary, and 4 of the corpus's 208
// multi-page documents share one dictionary across every page. The structural half closed
// on 2026-08-16 — a page that invokes no XObject at all now has no image — and **45 pages
// invoked a *different* image than the shared dictionary holds**, so they took a neighbour's
// plate resolution. This tool is what measured them: **39 smaller and 6 wider**, and the
// entry's word for all 45 was "smaller". See the `wider` note below.
//
// **The wiring landed on 2026-08-17 and this tool is the gate that measured it.**
// `Flattener.rebuildDPI(of:)` now applies the shipped policy to `drawnLargestImage`, so
// `dictRebuildDPI` below is what production did *before* that commit and `shippedRebuildDPI`
// is what it does now. `policyMoves` is therefore a before/after diff in one sweep, and over
// the corpus it reads `moves` on exactly the 45 and `same` on the other 16,942. Two things
// follow for a reader:
//
//   * `dictRebuildDPI` is `rebuildDPI(from: largestImage(of:))` — the old body verbatim, not
//     a re-derivation. This column used to hold `rebuildDPI(of:)`, which was the same thing
//     until the wiring landed and would have become a copy of `drawnRebuildDPI` after it: a
//     tool comparing production against itself, printing `same` on all 16,987 rows and
//     reading as "the wiring changed nothing".
//   * the anchor is `DRAWN-2026-08-16.tsv`, produced by the *old* production path before the
//     change existed. Its `shippedRebuildDPI` column equals this one's `dictRebuildDPI` on
//     every row it holds, which is what makes the diff a measurement rather than this tool
//     agreeing with itself.
//
// Restricting the walk to the invoked names is structural and needs no threshold, which is
// why `Flattener.drawnLargestImage` exists. This header said it needed a constant
// recalibrated first: `minimumScanPixelWidth = 600` separated 47 logos of 16–96 px from 37
// page-sized scans of 1936–2592 px, measured against each document's **maximum**, and C24's
// first repair sent `Batzell` p22 from 369.6 DPI to **70.6** because that page's own figure
// is 600 px wide. It then said "rendering a page of type at 70 DPI is C9 again", **which was
// reasoned and is measured false** — `Tools/score-rebuild-dpi.swift`, C24 2026-08-17: p22 at
// 70.6 DPI retains 92.8% of its own words against 94.2% at 369.6, and the constant judges
// all three of the pages it faces correctly. No recalibration was wanted.
//
// One row per page, no rendering and no OCR, so it is metadata-speed. The policy applied to
// both measurements is `Flattener.rebuildDPI(from:)` itself — the shipped three branches,
// not a copy of them, because T15 is what a drifting copy costs.
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
//   awk -F'\t' 'NR>1 && $12=="smaller"' drawn.tsv          # the population C24 moved
//
// and the wiring's own gate is column 11 against the dated record that predates it:
//
//   awk -F'\t' 'NR>1 && $11=="moves"' drawn.tsv | wc -l    # expect 45
//   awk -F'\t' 'NR>1 {print $1"\t"$2"\t"$6}' drawn.tsv     # must match DRAWN-2026-08-16's $6
//
// `minimumScanPixelWidth` is consulted on every page whose drawn DPI falls below
// `minimumPlausibleScanDPI` — **820 of the corpus's 16,987**, measured 2026-08-17, so this
// query is not the small one an earlier draft of this comment assumed:
//
//   awk -F'\t' 'NR>1 && $9!="-" && $9+0 < 150' drawn.tsv | cut -f1,2,8,9    # 820 pages
//
// The three the *wiring* put in front of it are that query narrowed to the rows that move —
// `Batzell` p9 and p22 and `AI 2027` p1, and C24 renders all three both ways:
//
//   awk -F'\t' 'NR>1 && $11=="moves" && $9!="-" && $9+0 < 150' drawn.tsv    # 3 pages
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
// Column 6 was `shippedRebuildDPI` and held `rebuildDPI(of:)`. Renamed with C24's wiring:
// production now *is* the drawn walk, so leaving it there made columns 6 and 10 the same
// number by construction. `dictRebuildDPI` keeps the comparison — and keeps this sweep
// comparable with `DRAWN-2026-08-16.tsv`, whose column 6 was that same policy over that same
// walk, taken before the change.
let columns = ["document", "page", "drawsAny",
               "dictWidth", "dictDPI", "dictRebuildDPI",
               "drawnKind", "drawnWidth", "drawnDPI", "drawnRebuildDPI",
               "policyMoves", "verdict", "shippedRebuildDPI"]

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
/// Pages where `rebuildDPI(of:)` disagreed with this tool's own reading of the drawn walk.
/// Must be empty; a non-empty list is the sweep refusing to be believed.
var divergences: [String] = []

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
        // The old body of `rebuildDPI(of:)`, verbatim — what production answered before C24's
        // wiring landed, so column 11 is a real before/after and not this tool comparing
        // production against itself.
        let dictRebuild = Flattener.rebuildDPI(from: dict)
        // And what production answers now. Asserted equal to `drawnRebuild` below rather than
        // assumed: a tool that recomputes the policy it is grading has to say so out loud.
        let shipped = Flattener.rebuildDPI(of: page)
        let drawn = Flattener.drawnLargestImage(of: page)

        var kind = "", drawnWidth = "-", drawnDPI = "-"
        var drawnRebuild: Double
        switch drawn {
        case .unreadable:
            kind = "unreadable"
            // What a caller must do with "could not tell": the `/Resources` answer.
            drawnRebuild = dictRebuild
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

        // **Production must equal the drawn arm on every page**, and a mismatch is a defect in
        // `rebuildDPI` or in this tool's copy of the three-case switch. Collected rather than
        // asserted, so a divergence is reported with the page that has it instead of taking
        // the sweep down 12,000 rows in.
        if abs(shipped - drawnRebuild) >= 0.05 { divergences.append("\(name) p\(i + 1)") }

        row([name, String(i + 1),
             draws == nil ? "unknown" : (draws! ? "yes" : "no"),
             dict == nil ? "-" : String(dict!.pixelWidth), dpi(dict?.dpi), dpi(dictRebuild),
             kind, drawnWidth, drawnDPI, dpi(drawnRebuild),
             abs(drawnRebuild - dictRebuild) < 0.05 ? "same" : "moves",
             verdict, dpi(shipped)])
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
// The self-check, printed whichever way it went. A sweep that says nothing about it reads as
// a pass, and "production agrees with the drawn walk on every page" is the claim the wiring
// rests on — so it is stated, with the count, every run.
if divergences.isEmpty {
    summary += "  rebuildDPI(of:) matched the drawn arm on all \(pagesSeen) pages\n"
} else {
    summary += "  ** \(divergences.count) page(s) where rebuildDPI(of:) DISAGREED with the "
        + "drawn arm: \(divergences.prefix(10).joined(separator: ", "))"
        + (divergences.count > 10 ? " …" : "") + "\n"
}
FileHandle.standardError.write(Data(summary.utf8))
if !divergences.isEmpty { exit(1) }
