// What does one page actually recognise at, if it were rebuilt at some other resolution?
//
// Built for BUGS.md C24's open half, whose blocker is **one page and not a population**.
// 45 corpus pages draw a different image than their shared `/Resources` dictionary holds,
// and `Tools/score-drawn-images.swift` measured what the shipped policy would do with each:
// 42 of the 45 land above `minimumPlausibleScanDPI` and are unaffected, and the three that
// reach `minimumScanPixelWidth` include `Batzell` p22, whose only drawn image is **exactly
// 600 px wide** — the constant's own boundary value — so it is trusted at **70.6 DPI**. The
// entry, `Flattener.drawnLargestImage` and `Tools/score-drawn-images.swift` all called that
// "C9 again", in the same words, none of them from a measurement. This tool is the
// measurement, and it says **the constant is right**: 92.8% of the page's own 291 words at
// 70.6 DPI against 94.2% at 369.6, for 87% fewer published bytes.
//
// This is that instrument, and it is general: `<pdf> <page>` prints one row per candidate
// resolution, every candidate derived from shipped code rather than typed in.
//
//   shipped   `Flattener.rebuildDPI(of:)` — what production does today.
//   drawn     `Flattener.rebuildDPI(from:)` over `drawnLargestImage`'s answer — what
//             production would do with the drawn walk wired in and the constant unchanged.
//   fallback  `Flattener.fallbackRebuildDPI` — what the drawn walk plus a constant raised
//             above this page's width would do.
//
// **It drives the shipped pipeline, it does not reproduce it.** `Flattener` reads nothing
// from `Prefs` — the rebuild resolution is always the page's own — and the "PDF render DPI"
// setting governs the *non*-rebuild route only, so there was no existing way to ask this.
// `Flattener.rebuildDPIOverride` is the seam; `flatten`, `mrcLayers` and
// `Recogniser.render` all read the function it hooks, so all three move together. The
// override is cleared after every candidate, and it cannot reach a helper process, so
// `useHelper` stays false (its default).
//
//   mkdir -p /tmp/rd && cp Tools/score-rebuild-dpi.swift /tmp/rd/main.swift
//   swiftc -O -o /tmp/score-rebuild-dpi -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/rd/main.swift
//   /tmp/score-rebuild-dpi "testdocs/journalArticle/Batzell - Free Labor….pdf" 22
//   /tmp/score-rebuild-dpi book.pdf 22 96 150     # extra candidates, appended
//
// **Characters are counted out of the published file, not off Vision's observations**, so
// the figure is comparable with C24's own before/after table — that one is also extraction
// from the finished PDF, and the text layer can weld or drop what recognition found
// (invariant 3). A resolution that recognises well and publishes badly is not a resolution
// this page wants.
//
// Two self-checks refuse to measure rather than mislead, both learned here:
//
//   * the single page is pulled into a fresh document, which **can change what
//     `largestImage` answers** — 4 of 208 multi-page corpus documents share one `/Resources`
//     across every page (A12.2). That does not matter while the override is in force, but
//     the *boxes* would matter, so both are compared against the original page and a
//     mismatch is a refusal.
//   * the override is only believed if the raster it produced is the size it implies.
//     A hook nothing consults would otherwise print three identical rows and read as
//     "resolution makes no difference here".
import AppKit
import Foundation
import PDFKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, let pageNumber = Int(args[1]), pageNumber >= 1 else {
    FileHandle.standardError.write(Data(
        "usage: score-rebuild-dpi <pdf> <page> [extra-dpi …]   (TSV on stdout)\n".utf8))
    exit(2)
}
let source = URL(fileURLWithPath: args[0])
// Refused, not dropped. `compactMap(Double.init)` over argv reads `96 1o0` as "measure 96",
// silently, and the row that never appears is indistinguishable from a resolution that was
// never asked for — invariant 1's shape in an instrument.
let extra: [Double] = args.dropFirst(2).map {
    guard let dpi = Double($0), dpi > 0, dpi.isFinite else {
        FileHandle.standardError.write(Data(
            "REFUSED: '\($0)' is not a positive DPI. Extra arguments are resolutions.\n".utf8))
        exit(2)
    }
    return dpi
}

// One printer over one array. Counting tab escapes by eye has put the wrong number of
// fields under a header three times here — T14's SKIP row, A12.3's `score-mrc`, T18's two.
let columns = ["document", "page", "candidate", "dpi", "pixelWidth", "pixelHeight",
               "megapixels", "route", "bytes", "characters", "words", "textSHA", "vsSource",
               "truthWords", "matched", "retained"]

func row(_ fields: [String]) {
    precondition(fields.count == columns.count,
                 "row has \(fields.count) fields against \(columns.count) columns")
    print(fields.joined(separator: "\t"))
}

func refuse(_ why: String) -> Never {
    FileHandle.standardError.write(Data("REFUSED: \(why)\n".utf8))
    exit(1)
}

/// Twelve hex digits of the published text, so two rows that differ by no character can be
/// seen to be the same string rather than inferred to be from an equal count.
func shortSHA(_ text: String) -> String {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325          // FNV-1a, 64-bit
    for byte in Array(text.utf8) {
        h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
    }
    return String(format: "%012llx", h & 0xffff_ffff_ffff)
}

/// Ignoring whitespace, because a text layer's line breaks are a writer decision and two
/// resolutions that recovered the same words differ in them routinely.
func same(_ a: String, _ b: String) -> Bool {
    func squash(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
    return squash(a) == squash(b)
}

func words(_ s: String) -> [String] {
    s.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isNewline }).map(String.init)
}

/// How many of the truth's words the candidate got back, as a multiset intersection.
///
/// **A character count cannot tell type from garbage, and on this page it does not even
/// try.** The first version of this tool printed only `characters`, and read 1,961 at
/// 70.6 DPI, 1,961 at 300 and 1,961 at 369.6 — three different strings (the hashes
/// differ) of identical length. Equal counts were nearly the whole answer and none of the
/// evidence: Vision emitting 1,961 characters of mush would print the same figure.
///
/// A multiset intersection is the measure and not `difflib`-style similarity, deliberately:
/// this project has already been misled once by an autojunk heuristic on repetitive text.
/// Garbage words simply fail to match, and a word the page holds twice is credited twice.
///
/// Punctuation is left attached and case is folded, so `retained` is a floor rather than an
/// estimate — `truth,` and `truth` count as different words, which costs the candidate and
/// never flatters it.
func retention(truth: [String], got: [String]) -> (matched: Int, total: Int) {
    guard !truth.isEmpty else { return (0, 0) }
    var pool: [String: Int] = [:]
    for w in got { pool[w, default: 0] += 1 }
    var matched = 0
    for w in truth where (pool[w] ?? 0) > 0 {
        pool[w]! -= 1
        matched += 1
    }
    return (matched, truth.count)
}

Prefs.register(migrate: false)
UserDefaults.standard.set(false, forKey: Prefs.openWhenDone)

guard let doc = PDFDocument(url: source), doc.pageCount > 0 else {
    refuse("cannot open \(source.path)")
}
guard pageNumber <= doc.pageCount, let page = doc.page(at: pageNumber - 1) else {
    refuse("page \(pageNumber) of a \(doc.pageCount)-page document")
}
let name = source.deletingPathExtension().lastPathComponent

/// **The page's own embedded text — the ground truth, where there is one.** `Batzell` p22
/// is a page of type carrying a figure, so it already has a text layer, and that layer is
/// what the rebuild rasterises away and Vision then has to find again. Two different jobs
/// come out of it: `retained` grades each candidate against it, and `vsSource` is the
/// tripwire for the failure where the published text turns out to *be* it — a rebuild that
/// quietly did not happen would print three identical rows and read as "resolution makes no
/// difference on this page".
let sourceText = page.string ?? ""
let truth = words(sourceText)
if truth.isEmpty {
    FileHandle.standardError.write(Data((
        "note: this page carries no embedded text, so there is no ground truth and "
        + "`retained` will be a dash. A character count alone cannot tell type from mush.\n"
    ).utf8))
}

// The three candidates, each from the shipped code that would produce it.
let shipped = Flattener.rebuildDPI(of: page)
let drawn = Flattener.drawnLargestImage(of: page)
var candidates: [(String, Double)] = [("shipped", shipped)]
switch drawn {
case .unreadable:
    FileHandle.standardError.write(Data(
        "note: the drawn walk could not read this page, so there is no drawn candidate\n".utf8))
case .noImage:
    candidates.append(("drawn", Flattener.rebuildDPI(from: nil)))
case let .largest(d, w):
    FileHandle.standardError.write(Data(String(
        format: "note: drawn largest image %d px, %.1f DPI\n", w, d).utf8))
    candidates.append(("drawn", Flattener.rebuildDPI(from: (dpi: d, pixelWidth: w))))
}
candidates.append(("fallback", Flattener.fallbackRebuildDPI))
candidates += extra.map { (String(format: "extra-%.1f", $0), $0) }

// A candidate that duplicates one already queued is dropped rather than measured twice —
// on a page whose drawn answer *is* the fallback the two are one candidate, and printing
// two identical rows would read as agreement between two different renders.
var queued: [(String, Double)] = []
for c in candidates where !queued.contains(where: { abs($0.1 - c.1) < 0.05 }) {
    queued.append(c)
}

let work = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("rebuild-dpi-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

// The page on its own, so a candidate costs one page and not a book.
let single = PDFDocument()
single.insert(page, at: 0)
let input = work.appendingPathComponent("in.pdf")
guard single.write(to: input) else { refuse("cannot write the single-page input") }
guard let reopened = PDFDocument(url: input), reopened.pageCount == 1,
      let extracted = reopened.page(at: 0) else {
    refuse("the single-page input lost its page on write")
}
// A12.2's hazard, checked rather than assumed. The resource walk may answer differently in
// the extract and that is harmless here — the override replaces it — but a box that moved
// would change the raster, the crop mapping and every character below.
let boxesBefore = (Flattener.fullBox(of: page), Flattener.displayBox(of: page))
let boxesAfter = (Flattener.fullBox(of: extracted), Flattener.displayBox(of: extracted))
guard abs(boxesBefore.0.width - boxesAfter.0.width) < 0.01,
      abs(boxesBefore.0.height - boxesAfter.0.height) < 0.01,
      abs(boxesBefore.1.width - boxesAfter.1.width) < 0.01,
      abs(boxesBefore.1.height - boxesAfter.1.height) < 0.01 else {
    refuse("extraction moved the page box: media \(boxesBefore.0.size) -> \(boxesAfter.0.size), "
           + "display \(boxesBefore.1.size) -> \(boxesAfter.1.size)")
}

print(columns.joined(separator: "\t"))

// A row of dashes is not a measurement. `score-corpus` printed `OK` at exit 1 over a document
// it measured nothing on (T14) and that is the bug being avoided here, so the count is kept
// rather than inferred from the output: a wrapper doing `tool … >> corpus.tsv && echo OK`
// must not record a header and four failures as evidence.
var measured = 0

for (label, dpi) in queued {
    Flattener.rebuildDPIOverride = { _ in dpi }
    defer { Flattener.rebuildDPIOverride = nil }

    // The route and the raster, from the shipped rebuild rather than from arithmetic.
    let probe = work.appendingPathComponent("probe-\(label).pdf")
    let pngs = work.appendingPathComponent("png-\(label)")
    try? FileManager.default.createDirectory(at: pngs, withIntermediateDirectories: true)
    var route = "?"
    var pixels = (0, 0)
    do {
        let rebuilt = try Flattener.flatten(input, to: probe, mode: .auto, pngDirectory: pngs)
        guard let only = rebuilt.first, rebuilt.count == 1 else {
            refuse("\(label): the rebuild produced \(rebuilt.count) pages for one page")
        }
        pixels = (only.pixelWidth, only.pixelHeight)
        switch only.content {
        case .bilevel: route = "bilevel"
        case .jpeg: route = only.isColour ? "colour" : "grey"
        }
    } catch {
        // The reason goes to stderr and the row says only "failed". A message in a
        // measurement column is how T14's SKIP row came to sit under the wrong header.
        FileHandle.standardError.write(Data(
            "\(label): rebuild failed: \(error.localizedDescription)\n".utf8))
        row([name, String(pageNumber), label, String(format: "%.1f", dpi),
             "-", "-", "-", "failed", "-", "-", "-", "-", "-", "-", "-", "-"])
        continue
    }

    // The override is only believed if the raster is the size it implies. `flatten` renders
    // the whole sheet, so the media box is the one to check.
    let implied = (boxesBefore.0.width * dpi / 72.0).rounded()
    guard abs(Double(pixels.0) - implied) <= 1 else {
        refuse("\(label): asked for \(dpi) DPI, which implies \(Int(implied)) px across a "
               + "\(boxesBefore.0.width) pt sheet, and the rebuild produced \(pixels.0) px. "
               + "The override did not reach the render.")
    }

    let out = work.appendingPathComponent("out-\(label).pdf")
    var outcome = "?", message = ""
    OCRModel.makeSearchablePDF(
        file: input, output: out,
        rebuild: true, rebuildMode: .auto, password: nil,
        control: RunControl(), progress: { _, _ in },
        report: { o, m in outcome = "\(o)"; message = m })
    guard outcome == "succeeded" else {
        FileHandle.standardError.write(Data(
            "\(label): pipeline \(outcome): \(message)\n".utf8))
        row([name, String(pageNumber), label, String(format: "%.1f", dpi),
             String(pixels.0), String(pixels.1),
             String(format: "%.1f", Double(pixels.0 * pixels.1) / 1e6), route,
             "-", "-", "-", "-", "-", "-", "-", "-"])
        continue
    }
    let bytes = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? nil
    let text = PDFDocument(url: out)?.page(at: 0)?.string ?? ""
    let got = words(text)
    let (matched, total) = retention(truth: truth, got: got)
    row([name, String(pageNumber), label, String(format: "%.1f", dpi),
         String(pixels.0), String(pixels.1),
         String(format: "%.1f", Double(pixels.0 * pixels.1) / 1e6), route,
         bytes.map(String.init) ?? "-", String(text.count), String(got.count),
         shortSHA(text), same(text, sourceText) ? "same" : "differs",
         total == 0 ? "-" : String(total),
         total == 0 ? "-" : String(matched),
         total == 0 ? "-" : String(format: "%.1f%%", 100.0 * Double(matched) / Double(total))])
    measured += 1
}

if measured == 0 {
    refuse("no candidate produced a measurement: \(queued.count) attempted and every one "
           + "failed, so every row above is dashes. Exit 0 here would let a caller record a "
           + "header as evidence.")
}
if measured < queued.count {
    FileHandle.standardError.write(Data(
        ("NOTE: \(queued.count - measured) of \(queued.count) candidates failed and carry "
         + "dashes rather than numbers.\n").utf8))
}
