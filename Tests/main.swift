import AppKit
import Foundation
import CoreText
import PDFKit
import Vision

// Checks that the settings panel produces argument lists mac-ocr actually
// accepts, by building each one and running it for real against a generated
// scanned PDF. Run with ./run_tests.sh.

// A trap is not catchable, so a check that asserts "this must not take the
// process down" cannot make the call itself — it would take the suite down with
// it. These modes re-run this same binary on one hostile file and the caller
// inspects how the child exited. See R24.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--probe-hostile-page" {
    let url = URL(fileURLWithPath: CommandLine.arguments[2])
    _ = Flattener.hasDigitalText(url)
    if let page = PDFDocument(url: url)?.page(at: 0) {
        _ = Flattener.largestImage(of: page)
        _ = Flattener.nativeDPI(of: page)
        _ = Flattener.rebuildDPI(of: page)
        _ = Flattener.pageIsAnImage(page)
    }
    let out = url.deletingLastPathComponent().appendingPathComponent("probe-out.pdf")
    // Must throw a Failure, not trap. Either outcome is a clean exit; the point
    // is that we reach this line at all.
    //
    // BOTH modes. This ran .blackAndWhite only, and `isPicture` — and so
    // `saturation`, which sizes its own buffer from the raw page box — is gated
    // on `mode == .auto` at Flattener.swift:456. So "an absurd MediaBox does not
    // kill the process" passed without ever executing the code it named. .auto
    // is the shipped default (R29).
    for mode in [Flattener.Mode.auto, .blackAndWhite] {
        do { _ = try Flattener.flatten(url, to: out, mode: mode) } catch {}
    }
    exit(0)
}

// A7.1 and A3.2. Two `Int(Double)` conversions on numbers descending entirely from
// what a file declares, 1,300 lines below the `safeInt` that exists for exactly
// this. Both trap, so both are exercised here and the parent reads the markers:
// exit 0 alone would only prove nothing crashed, and the *behaviour* — an absurd
// box contributing nothing rather than the whole page — matters as much.
if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--probe-hostile-numbers" {
    // A7.1: `MediaBox [0 0 1e-14 1.3e-14]` with an image declaring 8000x10400
    // gives dpi 5.76e+19. `Int(1.44e19)` against `Int.max` 9.22e18 trapped, and
    // both routing gates pass first because `wide` reduces algebraically to the
    // declared `/Width`.
    print("window=\(Flattener.sauvolaWindow(dpi: 5.76e19, width: 8000, height: 10400))")
    print("windowNaN=\(Flattener.sauvolaWindow(dpi: .nan, width: 40, height: 40))")
    print("windowTiny=\(Flattener.sauvolaWindow(dpi: 300, width: 2, height: 2))")
    // sauvolaMask's own arithmetic: `y + r + 1` overflows for a merely large `r`,
    // so the bound has to be inside the function and not only at its caller.
    let flat = [UInt8](repeating: 200, count: 64)
    print("maskHuge=\(Flattener.sauvolaMask(flat, width: 8, height: 8, window: Int.max).count)")
    // A3.2: one non-finite word box among good ones.
    let bad = SearchableWriter.BoundingBox(x: .nan, y: 0.1, width: 0.2, height: 0.05)
    let good = SearchableWriter.BoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.05)
    print("mixed=\(Flattener.textRegionMask([bad, good], width: 100, height: 100).filter { $0 }.count)")
    print("goodOnly=\(Flattener.textRegionMask([good], width: 100, height: 100).filter { $0 }.count)")
    let absurd = SearchableWriter.BoundingBox(x: 1e300, y: 1e300, width: 1e300, height: 1e300)
    print("absurd=\(Flattener.textRegionMask([absurd], width: 100, height: 100).filter { $0 }.count)")
    exit(0)
}

// R23. copyOutline recurses once per outline level, and the stack that matters
// is the 512 KB of an OperationQueue worker — which is where the pipeline calls
// it from. Overflowing it is a SIGBUS, so this runs in a child too.
if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--probe-deep-outline" {
    let src = URL(fileURLWithPath: CommandLine.arguments[2])
    let composed = URL(fileURLWithPath: CommandLine.arguments[3])
    let out = URL(fileURLWithPath: CommandLine.arguments[4])
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.addOperation {
        _ = SearchableWriter.copyOutline(from: src, of: composed, to: out)
    }
    queue.waitUntilAllOperationsAreFinished()
    exit(0)
}

var failures = 0
var checks = 0

/// Blocks that did not run, and why.
///
/// A11.7. The skip census was **75 checks in eight blocks**, and getting that
/// number took an audit: five blocks skipped with no `else` at all, so they left
/// no trace in the log, and the two that did print said "jbig2enc/qpdf not
/// installed" without saying how much had gone. `ARCHITECTURE.md` claimed ~18 and
/// the audit that corrected it guessed ~76 before the count came out at 75.
///
/// A documented number goes stale the first time someone adds a gated check. So
/// the suite counts its own skips and prints the census at the end: the number is
/// **measured on every run** rather than asserted in a document, and a silent skip
/// is now a contradiction in terms.
var skippedBlocks: [(label: String, checks: Int, reason: String)] = []
func skipBlock(_ label: String, checks n: Int, because reason: String) {
    skippedBlocks.append((label, n, reason))
    print("  SKIP \(label) — \(n) check(s) not run: \(reason)")
}

func check(_ label: String, _ condition: Bool, _ detail: String = "") {
    checks += 1
    if condition {
        print("  ok   \(label)")
    } else {
        failures += 1
        print("  FAIL \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    }
}

let d = UserDefaults.standard
let allKeys = Prefs.allKeys
func resetPrefs() {
    for k in allKeys { d.removeObject(forKey: k) }
    Prefs.register()
    // Never pop Finder windows during a test run: the batch tests drive the real
    // model, and this pref defaults to on.
    d.set(false, forKey: Prefs.openWhenDone)
    // Nor a modal. The C17 pre-flight asks before discarding real digital text,
    // and `runModal()` in a headless test binary hangs the run instead of
    // failing it. The default is asserted separately, from the registered value.
    d.set(false, forKey: Prefs.warnDigitalText)
    // Nor litter ~/Library/Logs on the machine running the suite. Several tests
    // drive a real batch through `start()`, and this pref defaults to on; the
    // one test that checks the report turns it back on and cleans up after
    // itself. The default is asserted separately, from the registered value.
    d.set(false, forKey: Prefs.writeRunReport)
}
resetPrefs()

// MARK: - Fixtures

let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mac-ocr-gui-tests-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

/// An image-only PDF: no embedded text, so anything we read back came from OCR.
/// Fraction of a given page that is not paper, rendered through PDFKit.
///
/// Page count cannot tell a working image filter from a broken one — a stream a
/// reader cannot decode still opens, it is simply blank — and it equally cannot
/// tell an MRC stencil the right way round from one inverted, which floods the
/// sheet instead of emptying it. This can do both.
func inkFractionMRC(of url: URL, page index: Int) -> Double {
    guard let doc = PDFDocument(url: url), let page = doc.page(at: index) else { return -1 }
    let box = page.bounds(for: .mediaBox)
    guard box.width > 0, box.height > 0 else { return -1 }
    let w = 200, h = max(1, Int(200 * box.height / box.width))
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return -1 }
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: CGFloat(w) / box.width, y: CGFloat(h) / box.height)
    page.draw(with: .mediaBox, to: ctx)
    guard let data = ctx.data else { return -1 }
    let px = data.bindMemory(to: UInt8.self, capacity: w * h)
    var dark = 0
    for i in 0..<(w * h) where px[i] < 224 { dark += 1 }
    return Double(dark) / Double(w * h)
}

/// A scanned page of ordinary black text on paper of a given colour.
///
/// `paper` is what separates an archival scan from a born-digital page: real
/// book stock is cream, and measured on a 1964 monograph it carries a mean
/// saturation of 0.08 — above `pictureSaturationThreshold`, while its ink
/// coverage and tone fraction both say plainly that it is text.
func makeScannedPDF(at url: URL, lines: [String], paper: NSColor = .white) {
    let w = 1224, h = 1584
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    paper.setFill()
    NSRect(x: 0, y: 0, width: w, height: h).fill()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "Helvetica", size: 44) ?? NSFont.systemFont(ofSize: 44),
        .foregroundColor: NSColor.black,
    ]
    var y = CGFloat(h - 220)
    for line in lines {
        (line as NSString).draw(at: NSPoint(x: 130, y: y), withAttributes: attrs)
        y -= 78
    }
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let cg = rep.cgImage else { return }
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    pdf.beginPDFPage(nil)
    pdf.draw(cg, in: box)
    pdf.endPDFPage()
    pdf.closePDF()
}

let sample = tmp.appendingPathComponent("scan one.pdf")   // space on purpose
makeScannedPDF(at: sample, lines: ["Hello OCR World", "Invoice 98765", "Total 420.00"])

guard FileManager.default.fileExists(atPath: sample.path) else {
    print("could not build the test PDF"); exit(1)
}

// There used to be a `guard let binary = Runner.resolveBinary()` here, and the
// whole suite refused to run without mac-ocr installed. Recognition is in
// process now; nothing has to be found.
print("recognising with Vision, revision \(Recogniser.revision)\n")

/// Extract Text mode for one file, the way the model drives it now.
@discardableResult
func extractText(_ file: URL, to folder: URL?,
                 settings: Prefs.Snapshot = .current())
    -> (succeeded: Bool, message: String, output: URL) {
    let target = (folder ?? file.deletingLastPathComponent())
        .appendingPathComponent(file.deletingPathExtension().lastPathComponent
                                + "." + settings.textFormat.fileExtension)
    do {
        try Recogniser.extract(from: file, to: target, settings: settings)
        return (true, "", target)
    } catch {
        return (false, error.localizedDescription, target)
    }
}

/// Observations for one file, the way the pipeline gets them. Replaces the
/// `Runner.run(… jsonArguments …)` + `SearchableWriter.observations(fromJSONAt:)`
/// pair that appeared in a dozen checks.
func observations(of file: URL,
                  settings: Prefs.Snapshot = .current())
    -> [Int: [SearchableWriter.Observation]] {
    (try? Recogniser.recogniseDocument(visible: file, bitmaps: [], settings: settings)) ?? [:]
}

/// A PDF whose picture says one thing and whose invisible text layer says
/// another — the only way to tell OCR apart from text-layer extraction.
func makeDecoyPDF(at url: URL, imageSays lines: [String], textLayerSays decoy: String) {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    pdf.beginPDFPage(nil)

    let w = 1224, h = 1584
    if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
       let ctx = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        var y = CGFloat(1200)
        for (i, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 150, y: y), withAttributes: [
                .font: NSFont(name: i == 0 ? "Helvetica-Bold" : "Helvetica",
                              size: i == 0 ? 90 : 52)!,
                .foregroundColor: NSColor.black])
            y -= 120
        }
        NSGraphicsContext.current?.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        if let cg = rep.cgImage { pdf.draw(cg, in: box) }
    }

    // Invisible text, exactly how an OCR'd PDF stores its layer.
    pdf.setTextDrawingMode(.invisible)
    let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: decoy, attributes: [.font: font]))
    pdf.textPosition = CGPoint(x: 72, y: 400)
    CTLineDraw(line, pdf)

    pdf.endPDFPage()
    pdf.closePDF()
}

/// A PDF's embedded text layer, with no OCR involved.
func embeddedText(of url: URL) -> String {
    guard let doc = PDFDocument(url: url) else { return "" }
    return (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Runs a config for real and returns the files it produced in `out`.
let out = tmp.appendingPathComponent("out")

func runAndList(_ label: String, outDir: URL) -> (ok: Bool, message: String, files: [String]) {
    try? FileManager.default.removeItem(at: outDir)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let result = extractText(sample, to: outDir)
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: outDir.path)) ?? []).sorted()
    return (result.succeeded, result.message, files)
}

// MARK: - Argument construction

// The argument-construction block lived here: checks on the mac-ocr command
// line this app used to build — flag order, repeated -l, the shell quoting of
// the preview, the searchable-pdf subcommand it deliberately never invoked.
// Nothing builds a command line for recognition any more, so every one of those
// checks lost its subject at once. `Recogniser` takes a `Prefs.Snapshot` and
// sets request properties; what used to be an argument list to assert against is
// four assignments the compiler checks.
//
// What survived the move is checked elsewhere, and it is the part that mattered:
// the language list comes from the machine and an unsupported code is reported
// before a run ("recognition languages this Mac actually has"), and what a run
// will do is still previewed in Settings.

print("\nend-to-end runs")

do {
    resetPrefs()
    let r = runAndList("text", outDir: out)
    check("text mode succeeds", r.ok, r.message)
    check("text mode writes 'scan one.txt'", r.files == ["scan one.txt"], r.files.joined(separator: ","))
    let body = (try? String(contentsOf: out.appendingPathComponent("scan one.txt"), encoding: .utf8)) ?? ""
    check("recognized text is present", body.contains("Hello OCR World"),
          body.replacingOccurrences(of: "\n", with: "⏎"))
}

do {
    resetPrefs()
    d.set(Prefs.TextFormat.json.rawValue, forKey: Prefs.textFormat)
    let r = runAndList("json", outDir: out)
    check("json mode succeeds", r.ok, r.message)
    check("json mode writes .json", r.files == ["scan one.json"], r.files.joined(separator: ","))
}

do {
    // Through *our* pipeline, not `mac-ocr searchable-pdf`. This block used to
    // shell out to that subcommand and check its output, which measured a
    // writer this app deliberately does not use — its layer costs a third of
    // the words on extraction, which is the whole reason SearchableWriter
    // exists. What has to hold is that searchable mode produces a `.ocr.pdf`
    // beside a selectable text layer, and that is what is checked now.
    resetPrefs()
    let dir = tmp.appendingPathComponent("searchable-basic")
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Read it with PDFKit rather than mac-ocr — running OCR over the result
    // would pass even if no text layer had been added at all.
    check("the source PDF has no embedded text to begin with",
          embeddedText(of: sample).isEmpty, embeddedText(of: sample))

    let output = dir.appendingPathComponent("scan one.ocr.pdf")
    var outcome: Runner.Result.Outcome?
    var message = ""
    OCRModel.makeSearchablePDF(
        file: sample, output: output,
        rebuild: true, rebuildMode: .auto, password: nil,
        control: RunControl(), progress: { _, _ in },
        report: { o, m in outcome = o; message = m })

    check("searchable mode succeeds", outcome == .succeeded, message)
    let produced = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    check("searchable mode writes .ocr.pdf", produced == ["scan one.ocr.pdf"],
          produced.joined(separator: ","))
    let text = embeddedText(of: output)
    check("searchable PDF gains a selectable text layer",
          text.contains("Hello OCR World"),
          text.isEmpty ? "<none>" : text.replacingOccurrences(of: "\n", with: " / "))
    // The inverse of A13.2 below: an ordinary document that *did* yield text must
    // not carry the empty-document note, or that note is noise on every run.
    check("…and a document with text says nothing about being empty",
          !message.contains("no text was found"), message)
}

// MARK: - The text route's cancel handling (A2.2's text half, and R63)

// Two defects in eight lines, both about a cancel on the Extract Text route.
//
// A2.2: `Recogniser.extract` checks `isCancelled` only at the top of each page, so
// a cancel during the last page finishes it and then writes **straight to the
// user's destination** — `Data(body).write(to: target)`, no staging, no publish.
// The previous run's .txt is replaced by a run the user stopped. Invariant 2 says
// "never write directly to the user's destination" and this is the route that does.
//
// R63: the route caught everything and reported `.failed` with the error's
// description — and the error thrown by a cancel is `Failure.cancelled`, whose
// description is "Cancelled." So a cancelled Plain Text run put a red ✗ against
// every in-flight file, reason "Cancelled.", counted them as failures in the run
// report, and left them in `failedFiles` for Retry Failed to offer.

print("\ncancelling a text extraction neither publishes nor lies about it")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("a22-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let source = dir.appendingPathComponent("scan.pdf")
    makeScannedPDF(at: source, lines: ["First page of the extraction test."])
    let target = dir.appendingPathComponent("scan.txt")
    let precious = "PRECIOUS OUTPUT from the previous run\n"
    try? Data(precious.utf8).write(to: target)

    // False while the pages are read, true afterwards — so the cancel lands in
    // exactly the window A2.2 measured: after the last page, before the write.
    var pagesSeen = 0
    let cancelAfterTheLastPage = {
        defer { pagesSeen += 1 }
        return pagesSeen >= 1
    }
    var thrown: Error?
    do {
        try Recogniser.extract(from: source, to: target,
                               settings: Prefs.Snapshot.current(), password: nil,
                               isCancelled: cancelAfterTheLastPage)
    } catch { thrown = error }

    check("a cancel after the last page is thrown, not swallowed",
          (thrown as? Recogniser.Failure) == .cancelled,
          thrown.map { "\($0)" } ?? "nothing was thrown — it wrote the file")
    let after = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
    check("…and the previous output is still there, byte for byte",
          after == precious,
          after.isEmpty ? "<the file is gone>" : String(after.prefix(50)))

    // The inverse row: an uncancelled extraction must still write, or the guard
    // above is satisfied by a route that never produces anything.
    let fresh = dir.appendingPathComponent("fresh.txt")
    do {
        try Recogniser.extract(from: source, to: fresh,
                               settings: Prefs.Snapshot.current(), password: nil,
                               isCancelled: { false })
        let got = (try? String(contentsOf: fresh, encoding: .utf8)) ?? ""
        check("…while an uncancelled extraction does write its text", !got.isEmpty,
              "the file is empty")
    } catch {
        check("an uncancelled extraction does not throw", false, "\(error)")
    }

    // R63. The mapping, which the searchable route spells out in seven places and
    // the text route did not spell out at all.
    let cancelled = OCRModel.outcome(for: Recogniser.Failure.cancelled, cancelled: true)
    check("a cancelled file is reported as cancelled, not failed",
          cancelled.0 == .cancelled,
          "reported \(cancelled.0) with “\(cancelled.1)”")
    check("…with the message the rest of the app uses", cancelled.1 == "Cancelled.")
    // And the inverse: a real failure during a cancelled batch is still a failure —
    // otherwise cancelling would paper over every broken file in the run.
    let broken = OCRModel.outcome(for: SearchableWriter.Failure.unreadableSource,
                                  cancelled: false)
    check("…while a genuine failure is still a failure", broken.0 == .failed,
          "reported \(broken.0)")
    check("…and keeps its own description", !broken.1.isEmpty && broken.1 != "Cancelled.",
          broken.1)

    // The text route has to *use* it. A bare `report(.failed, error…)` in that
    // branch is the defect, and it is one line, so nothing else would notice.
    let modelSource = (try? String(contentsOfFile: "Sources/Model.swift",
                                   encoding: .utf8)) ?? ""
    check("the text route maps its error through outcome(for:cancelled:)",
          modelSource.contains("Self.outcome(for: error,"),
          modelSource.isEmpty ? "could not read Model.swift" : "it does not")
}

// MARK: - A document Vision reads nothing from says so (A13.2)

// `recogniseDocument` records `[]` for a blank page so `missingPages` can tell a
// skip from a blank (C12), and nothing checked the other side: a document where
// **every** page came back empty published as a success with `message=""`, zero
// characters, and no note anywhere.
//
// Right for a genuinely blank scan. Wrong for R56 and R57 — both open, both on the
// default route — where a pale drawing is erased or a page is blobbed to solid
// black, which produces exactly this signature. On a one-page document the user was
// told it succeeded and told nothing else at all.

print("\na document with no text on any page says so")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("a132-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // Genuinely blank pages, two of them, so the plural wording is exercised too.
    let empty = dir.appendingPathComponent("empty.pdf")
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    if let ctx = CGContext(empty as CFURL, mediaBox: &box, nil) {
        for _ in 0..<2 {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(box)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }
    check("the blank fixture is a two-page PDF",
          PDFDocument(url: empty)?.pageCount == 2,
          "\(PDFDocument(url: empty)?.pageCount ?? -1)")

    var outcome: Runner.Result.Outcome?
    var message = ""
    OCRModel.makeSearchablePDF(
        file: empty, output: dir.appendingPathComponent("empty.ocr.pdf"),
        rebuild: true, rebuildMode: .auto, password: nil,
        control: RunControl(), progress: { _, _ in },
        report: { o, m in outcome = o; message = m })

    // Still a success: a blank page is a legitimate thing to find, and refusing to
    // publish would make an empty scan unprocessable.
    check("a document with no text anywhere still succeeds", outcome == .succeeded, message)
    check("…but the message says no text was found",
          message.contains("no text was found"),
          message.isEmpty ? "<empty message — the A13.2 defect>" : message)
    check("…and says how many pages that was",
          message.contains("2 pages"), message)
    check("…and points at the two open routing defects rather than just shrugging",
          message.contains("reduced to nothing"), message)
}

do {
    resetPrefs()
    d.set(true, forKey: Prefs.fast)
    d.set(false, forKey: Prefs.languageCorrection)
    d.set(0.2, forKey: Prefs.confidence)
    d.set(false, forKey: Prefs.pdfDPIAuto)
    d.set(200, forKey: Prefs.pdfDPI)
    d.set("en-US", forKey: Prefs.languages)
    d.set("Fitzgerald", forKey: Prefs.customWords)
    d.set(true, forKey: Prefs.minTextHeightOn)
    d.set(0.01, forKey: Prefs.minTextHeight)
    let r = runAndList("every flag", outDir: out)
    check("every recognition option together is accepted", r.ok, r.message)
    check("…and still writes output", r.files == ["scan one.txt"], r.files.joined(separator: ","))
}

// The command preview is the one place in the UI that claims to say what a run
// will do, so it has to stop claiming things that are not true.
do {
    resetPrefs()
    // Fresh install: no folder chosen, and "beside each original" off. The
    // preview used to render this exactly like beside-each-original —
    // `-o '[dir]/[name].txt'` — while Start sat disabled with no explanation.
    d.set(false, forKey: Prefs.besideOriginal)
    let cold = Runner.previewLines(file: sample, outputFolder: nil)
    check("the preview admits when no destination is set",
          cold.contains { $0.contains("No output folder chosen yet") },
          cold.joined(separator: " / "))

    d.set(true, forKey: Prefs.besideOriginal)
    let beside = Runner.previewLines(file: sample, outputFolder: nil)
    check("…and says nothing of the sort once a destination exists",
          !beside.contains { $0.contains("No output folder chosen") },
          beside.joined(separator: " / "))

    // The preview used to name the resolved mac-ocr binary, because the path
    // setting was the one most likely to be wrong (U9). There is no path and no
    // binary; what the preview must still name is the recognition step itself.
    let named = Runner.previewLines(file: sample, outputFolder: out)
    check("the preview names the recognition step",
          named.contains { $0.lowercased().contains("recognise") },
          named.joined(separator: " / "))

    // Searchable mode is a pipeline, and the compression step shells out to two
    // further binaries that the preview never mentioned at all.
    resetPrefs()
    d.set(Prefs.Mode.searchablePDF.rawValue, forKey: Prefs.mode)
    d.set(true, forKey: Prefs.rebuildImages)
    d.set(true, forKey: Prefs.useJBIG2)
    d.set(true, forKey: Prefs.besideOriginal)
    let pipeline = Runner.previewLines(file: sample, outputFolder: nil)
        .joined(separator: "\n")
    check("the searchable preview shows the rebuild", pipeline.contains("rebuild pages"), pipeline)
    check("…the recognition call", pipeline.lowercased().contains("recognise the text"), pipeline)
    check("…the text layer", pipeline.contains("invisible text layer"), pipeline)
    check("…and the compression step, named or explained",
          pipeline.contains("jbig2") || pipeline.contains("JBIG2 compression is on"),
          pipeline)
    check("the preview still names the output", pipeline.contains("[name].ocr.pdf"), pipeline)
    // The layering step is the one the Photo detail setting controls, and a
    // preview that omits it describes an app that no longer exists. It is also
    // the step that changes what a photograph looks like, so it is exactly the
    // one a user checking this panel would want to find.
    check("…and the layering step, with the detail level it will use",
          pipeline.contains("store text and pictures separately")
            && pipeline.contains("balanced"),
          pipeline)
    d.set(Prefs.PhotoDetail.smallest.rawValue, forKey: Prefs.photoDetail)
    let atSmallest = Runner.previewLines(file: sample, outputFolder: nil)
        .joined(separator: "\n")
    check("…which follows the setting rather than being hardcoded",
          atSmallest.contains("smallest files"), atSmallest)
    resetPrefs()
}

// MARK: - Words broken across a line

print("\nrejoining hyphenated words")

do {
    // Two stacked lines, the first ending in a hyphen. Boxes are what the rule
    // reads, so they have to be laid out like real lines: same column, the
    // second one line-height below the first.
    func line(_ text: String, y: Double, x: Double = 0.1,
              width: Double = 0.8, height: Double = 0.04) -> SearchableWriter.Observation {
        SearchableWriter.Observation(
            boundingBox: SearchableWriter.BoundingBox(x: x, y: y, width: width, height: height),
            text: text, confidence: 1)
    }
    let box = CGRect(x: 0, y: 0, width: 612, height: 792)
    func joined(_ lines: [SearchableWriter.Observation]) -> [String] {
        SearchableWriter.joiningHyphenatedWords(lines, in: box).map(\.text)
    }

    check("a word broken over two lines is rejoined on the first",
          joined([line("the conditions of the merito-", y: 0.20),
                  line("cracy have been described", y: 0.25)])
            == ["the conditions of the meritocracy", "cracy have been described"],
          joined([line("the conditions of the merito-", y: 0.20),
                  line("cracy have been described", y: 0.25)]).joined(separator: " | "))

    // Nothing is removed — that is what keeps this outside invariant 1.
    check("…and the tail is left where it was, not moved or dropped",
          joined([line("merito-", y: 0.20), line("cracy and so on", y: 0.25)]).count == 2
            && joined([line("merito-", y: 0.20),
                       line("cracy and so on", y: 0.25)])[1] == "cracy and so on")

    check("a Unicode hyphen counts too, which is most of an old scan",
          joined([line("merito\u{2010}", y: 0.20), line("cracy", y: 0.25)])[0] == "meritocracy")

    check("an upper-case tail is left alone — Smith- / Jones is two names",
          joined([line("Smith-", y: 0.20), line("Jones wrote", y: 0.25)])[0] == "Smith-")

    check("a figure after the hyphen is not a broken word",
          joined([line("pages 3-", y: 0.20), line("7 of the report", y: 0.25)])[0] == "pages 3-")

    check("a line that is only a dash is not a candidate",
          joined([line("-", y: 0.20), line("continued", y: 0.25)])[0] == "-")

    // Fragments beside each other are one visual line; joining across that gap
    // would weld two words that are simply next to each other on the page.
    check("two fragments on the same visual line are not joined",
          joined([line("merito-", y: 0.20, x: 0.1, width: 0.3),
                  line("cracy", y: 0.20, x: 0.5, width: 0.3)])[0] == "merito-")

    // The next entry in reading order can be the top of the next column.
    check("a continuation too far below is not joined",
          joined([line("merito-", y: 0.20), line("cracy", y: 0.80)])[0] == "merito-")

    // Measured, not imagined: joining by vertical adjacency alone produced
    // `adminis+put`, `bipar+put`, `mi+appears` and `that+cerning` on real
    // two-column pages — a real word welded to a fragment of an unrelated one,
    // which is worse than the hyphen it replaced. Columns do not overlap.
    // A near-miss, not a clean miss: two columns whose boxes just touch still
    // share a little width, and a floor of zero would let them join. The
    // clean-miss fixture below cannot catch that — its overlap is negative, so
    // any non-negative floor refuses it and the guard looks tested when it is
    // not. This is what let `minimumColumnOverlap` survive its first mutant.
    check("a continuation in a barely-overlapping neighbouring column is refused",
          joined([line("merito-", y: 0.20, x: 0.05, width: 0.46),
                  line("cracy", y: 0.24, x: 0.48, width: 0.46)])[0] == "merito-")

    check("a continuation in the next column is not joined",
          joined([line("merito-", y: 0.20, x: 0.05, width: 0.40),
                  line("cracy", y: 0.24, x: 0.55, width: 0.40)])[0] == "merito-")
    check("…while the same column, slightly ragged, still joins",
          joined([line("merito-", y: 0.20, x: 0.05, width: 0.40),
                  line("cracy and so on", y: 0.24, x: 0.05, width: 0.36)])[0] == "meritocracy")

    check("…nor one above it",
          joined([line("merito-", y: 0.60), line("cracy", y: 0.20)])[0] == "merito-")

    // MARK: across a page break
    //
    // Not a rare case, though the first attempt at it concluded so: measured over
    // 45 documents and 1,225 pages, 29 pages — 2.37%, in 11 of the 45 — end on a
    // hyphenated line. The three documents that attempt was tested against held
    // twelve such pages and it joined none, which was read as the case being rare
    // instead of the code being wrong.
    //
    // What it was actually doing wrong is the first check below: it offered only
    // the next page's *topmost* line, which is the folio or the running head, so
    // every candidate failed the lower-case test and the search stopped there
    // rather than looking past the furniture.
    func joinedOver(_ lines: [SearchableWriter.Observation],
                    _ next: [SearchableWriter.Observation]) -> [String] {
        SearchableWriter.joiningHyphenatedWords(lines, in: box, continuation: next).map(\.text)
    }
    check("a word carried over a page break is joined past the running head",
          joinedOver([line("and he questioned the conven-", y: 0.86)],
                     [line("6130", y: 0.03),
                      line("CONGRESSIONAL RECORD", y: 0.05),
                      line("tions of his day", y: 0.10)])[0]
            == "and he questioned the conventions")
    check("…and when the body text is the very first line",
          joinedOver([line("merito-", y: 0.86)], [line("cracy and so on", y: 0.06)])[0]
            == "meritocracy")
    check("…but not to a folio alone, with no body text offered",
          joinedOver([line("merito-", y: 0.86)],
                     [line("6130", y: 0.03), line("RUNNING HEAD", y: 0.05)])[0] == "merito-")
    check("…and not when the head is mid-page",
          joinedOver([line("merito-", y: 0.40)], [line("cracy", y: 0.06)])[0] == "merito-")
    check("…and not to a line partway down the next page",
          joinedOver([line("merito-", y: 0.86)], [line("cracy", y: 0.58)])[0] == "merito-")
    check("…and the last page, with nothing after it, is left alone",
          joinedOver([line("merito-", y: 0.86)], [])[0] == "merito-")
    // The measured page geometry this rests on: the deepest hyphenated line seen
    // sat at 0.82 of the page, and an earlier guess of 0.18 put the boundary at
    // exactly 0.82, so nothing ever qualified.
    check("the page-edge band clears the measured depth of a last line",
          1 - SearchableWriter.edgeOfPage < 0.82,
          String(format: "boundary %.2f", 1 - SearchableWriter.edgeOfPage))

    // Through `compose`, not straight into the function.
    //
    // The checks above hand the continuation lines in directly, which tests the
    // rule and not the wiring that feeds it — and the wiring is where the bug
    // was. `compose` is what decides how many of the next page's lines to offer,
    // and offering one is exactly the defect: the folio and the running head sit
    // above the body text, so a single candidate is always furniture.
    // `const/continuationCandidates` survived its mutant until this existed.
    do {
        let dir = tmp.appendingPathComponent("crosspage")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let src = dir.appendingPathComponent("two.pdf")
        var pbox = CGRect(x: 0, y: 0, width: 612, height: 792)
        if let c = CGContext(src as CFURL, mediaBox: &pbox, nil) {
            for _ in 0..<2 { c.beginPDFPage(nil); c.endPDFPage() }
            c.closePDF()
        }
        // Page 2 opens with a folio and a running head, as a real book does.
        let obs: [Int: [SearchableWriter.Observation]] = [
            1: [line("and he questioned the conven-", y: 0.86)],
            2: [line("6130", y: 0.03, x: 0.05, width: 0.08),
                line("CONGRESSIONAL RECORD", y: 0.05, x: 0.2, width: 0.6),
                line("tions of his day and after", y: 0.11)],
        ]
        let out = dir.appendingPathComponent("joined.pdf")
        _ = try? SearchableWriter.compose(visible: src, observations: obs, to: out,
                                          drawImages: false, joinHyphenated: true)
        let text = PDFDocument(url: out)?.string ?? ""
        check("compose looks past the folio and running head to join across a page",
              text.contains("conventions"),
              text.replacingOccurrences(of: "\n", with: "⏎").prefix(90).description)
        check("…and the folio and running head are still in the text layer",
              text.contains("6130") && text.contains("CONGRESSIONAL"))
    }

    // Only the alphabetic run is taken, so punctuation stays on its own line.
    check("only the word is taken from the tail, not the rest of the line",
          joined([line("merito-", y: 0.20), line("cracy, he wrote,", y: 0.25)])[0]
            == "meritocracy")

    // And the whole point: it has to be findable in a real PDF.
    //
    // Not gated. `if JBIG2.encoder != nil || true {` stood here — a condition
    // that is always true, wearing the shape of a skip (A11.5). Nothing in this
    // block runs jbig2: it composes a text layer and reads it back. A reader
    // counting gated blocks counted this one, and a reader wondering why a
    // hyphenation check needed a compression tool had no answer.
    do {
        let dir = tmp.appendingPathComponent("hyphen")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let src = dir.appendingPathComponent("src.pdf")
        makeScannedPDF(at: src, lines: ["the conditions of the merito-",
                                        "cracy have been described"])
        let obs = [1: [line("the conditions of the merito-", y: 0.20),
                       line("cracy have been described", y: 0.25)]]
        let on = dir.appendingPathComponent("on.pdf")
        _ = try? SearchableWriter.compose(visible: src, observations: obs, to: on,
                                          drawImages: false, joinHyphenated: true)
        let off = dir.appendingPathComponent("off.pdf")
        _ = try? SearchableWriter.compose(visible: src, observations: obs, to: off,
                                          drawImages: false, joinHyphenated: false)
        let onText = PDFDocument(url: on)?.string ?? ""
        let offText = PDFDocument(url: off)?.string ?? ""
        check("the finished PDF can be searched for the whole word",
              onText.contains("meritocracy"), onText.replacingOccurrences(of: "\n", with: "⏎"))
        // Both directions, or a check that always passed would prove nothing.
        check("…and cannot be, with the setting off",
              !offText.contains("meritocracy"),
              offText.replacingOccurrences(of: "\n", with: "⏎"))
        check("…while the tail is still there either way",
              onText.contains("cracy") && offText.contains("cracy"))
    }
}

// MARK: - Saying so when the copy is larger than the original

print("\nreporting a copy larger than its original")

do {
    let dir = tmp.appendingPathComponent("sizenote")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    func file(_ name: String, bytes: Int) -> URL {
        let u = dir.appendingPathComponent(name)
        try? Data(repeating: 0x41, count: bytes).write(to: u)
        return u
    }
    let small = file("small.pdf", bytes: 100_000)
    let big = file("big.pdf", bytes: 250_000)
    let similar = file("similar.pdf", bytes: 105_000)
    let smaller = file("smaller.pdf", bytes: 40_000)

    check("a copy well over the original says so",
          OCRModel.sizeNote(from: small, to: big).contains("larger than the original"),
          OCRModel.sizeNote(from: small, to: big))
    // A searchable copy always costs something the original did not carry, so
    // reporting every few per cent would be noise rather than information.
    check("…a copy barely over it stays quiet",
          OCRModel.sizeNote(from: small, to: similar).isEmpty,
          OCRModel.sizeNote(from: small, to: similar))
    check("…and a copy that shrank stays quiet",
          OCRModel.sizeNote(from: small, to: smaller).isEmpty)
    // The drop box takes images too, and a photograph wrapped into a searchable
    // PDF is always larger than the photograph. Blaming that on the original's
    // compression would be wrong and baffling.
    let photo = file("scan.jpg", bytes: 100_000)
    check("…and an image input is never reported as growth",
          OCRModel.sizeNote(from: photo, to: big).isEmpty,
          OCRModel.sizeNote(from: photo, to: big))

    check("…and a missing file is not reported as growth",
          OCRModel.sizeNote(from: dir.appendingPathComponent("gone.pdf"), to: big).isEmpty)
    // The note names both figures, because "larger" without them is a worry
    // rather than a fact.
    check("…and the note carries both sizes",
          OCRModel.sizeNote(from: small, to: big).contains("KB"),
          OCRModel.sizeNote(from: small, to: big))
}

// MARK: - The unplaced-lines message carries no document text (A4.1)

// This string goes report(.failed:) -> log -> RunReport.text, which copies the log
// **verbatim** into ~/Library/Logs/VisionOCR — a file whose own docstring calls it
// one "that gets mailed to whoever is helping you", written by default. It used to
// carry text.prefix(24) for up to three lines: 72 characters of the user's own
// document, with the page numbers to locate them by. It is also spoken aloud.

print("\nthe unplaced-lines message names pages, not text")

do {
    // Text a reader would recognise instantly if it turned up in a shared file.
    let secret = "Kaczynski to Ellsberg, 14 March: the diagnosis is"
    let lost = [
        SearchableWriter.Unplaced(page: 3, text: secret, reason: "no room"),
        SearchableWriter.Unplaced(page: 7, text: "PATIENT NAME: Iris Chang", reason: "off page"),
    ]
    let summary = OCRModel.unplacedSummary(lost)

    check("the summary counts the lines", summary.contains("2 line(s)"), summary)
    check("…and names the page", summary.contains("p3") && summary.contains("p7"), summary)
    check("…and gives the reason", summary.contains("no room"), summary)
    // The property, stated as the negative it is. Substring of the whole message,
    // not of the prefix the old code took, so a shorter excerpt does not pass it.
    check("…and carries no word of the document",
          !summary.contains("Kaczynski") && !summary.contains("Ellsberg")
            && !summary.contains("PATIENT") && !summary.contains("Iris"),
          summary)
    // The excerpt was 24 characters, so a check that only looked for the whole
    // string would pass against the defect. This looks for the prefix that shipped.
    check("…not even the first 24 characters of it",
          !summary.contains(String(secret.prefix(24))), summary)

    // Invariant 1 still has to hold: the loss is reported, loudly, with enough to
    // find it. A message that dropped the text *and* the pages would satisfy the
    // privacy property by breaking the one this code exists for.
    let many = (1...5).map {
        SearchableWriter.Unplaced(page: $0, text: "line \($0)", reason: "no room")
    }
    check("more than three lines are elided, not silently dropped",
          OCRModel.unplacedSummary(many).contains("5 line(s)")
            && OCRModel.unplacedSummary(many).hasSuffix("…"),
          OCRModel.unplacedSummary(many))
}

// MARK: - Batch presets

print("\npresets")

do {
    resetPrefs()
    let d = UserDefaults.standard

    // The property that matters: a preset sets what the material implies and
    // leaves the user's own choices alone. A preset that reset where files are
    // written, or which languages to recognise, would be a trap.
    d.set("/Users/someone/Archive", forKey: Prefs.outputFolder)
    d.set("fr-FR, la", forKey: Prefs.languages)
    d.set(9, forKey: Prefs.concurrency)
    for preset in Prefs.Preset.allCases { preset.apply() }
    check("a preset leaves the output folder alone",
          d.string(forKey: Prefs.outputFolder) == "/Users/someone/Archive")
    check("…and the languages", d.string(forKey: Prefs.languages) == "fr-FR, la")
    check("…and how many files run at once", d.integer(forKey: Prefs.concurrency) == 9)

    // Every preset has to leave the app in a state it can actually run in.
    for preset in Prefs.Preset.allCases {
        resetPrefs(); Prefs.register()
        preset.apply()
        let snap = Prefs.Snapshot.current()
        check("\(preset.label) produces a runnable configuration",
              Flattener.Mode(rawValue: d.string(forKey: Prefs.rebuildMode) ?? "") != nil
                && snap.confidence >= 0 && snap.confidence <= 1)
    }

    // They must actually differ, or they are four buttons doing one thing.
    resetPrefs(); Prefs.register()
    Prefs.Preset.photographs.apply()
    let photoDetail = d.string(forKey: Prefs.photoDetail)
    Prefs.Preset.newspaper.apply()
    check("presets differ from one another where the material differs",
          d.string(forKey: Prefs.photoDetail) != photoDetail,
          "photographs \(photoDetail ?? "nil") vs newspaper "
            + "\(d.string(forKey: Prefs.photoDetail) ?? "nil")")

    // A10.3. The check above compares **one key**, and only Photographs against
    // Newspaper, so it says nothing about the other five pairs. Fingerprinted over
    // every key a preset may write: Newspaper and Book scan are byte-identical,
    // and both equal `register()`'s own values, so of four buttons two are
    // "restore defaults" under other names. The code is honest about that; the
    // blurbs were not — Newspaper's "keeps every uncertain word" **is** the
    // registered default.
    //
    // So the property is not "all four differ" (they do not, and forcing them to
    // would be inventing settings nothing measured). It is: **a preset that writes
    // exactly the defaults has to say so**, the way Book scan already does. That
    // check maintains itself — give Newspaper a real distinct value later and the
    // fingerprint stops matching, so the requirement lifts on its own.
    func fingerprint(_ preset: Prefs.Preset?) -> [String: String] {
        resetPrefs(); Prefs.register()
        preset?.apply()
        return Prefs.Preset.keysWritten.reduce(into: [String: String]()) {
            $0[$1] = String(describing: d.object(forKey: $1))
        }
    }
    let defaults = fingerprint(nil)
    var prints: [Prefs.Preset: [String: String]] = [:]
    for preset in Prefs.Preset.allCases { prints[preset] = fingerprint(preset) }

    for preset in Prefs.Preset.allCases where prints[preset] == defaults {
        check("\(preset.label) writes the registered defaults, so its blurb says so",
              preset.blurb.lowercased().contains("default"),
              "\(preset.label): \(preset.blurb)")
    }
    // And the pairs that *are* identical are named, so nobody has to re-derive
    // which buttons are the same button. Reported rather than refused: this is a
    // fact about a deliberate design, not a defect.
    let identical = Prefs.Preset.allCases.flatMap { a in
        Prefs.Preset.allCases.filter { b in
            a.rawValue < b.rawValue && prints[a] == prints[b]
        }.map { "\(a.label)=\($0.label)" }
    }
    check("the identical presets are the two this register records",
          identical == ["Book scan=Newspaper"] || identical == ["Newspaper=Book scan"],
          identical.isEmpty ? "none identical — the blurbs need revisiting"
                            : identical.joined(separator: ", "))
    // Not vacuous: at least one preset must be genuinely distinct, or "identical"
    // above could be satisfied by an `apply` that writes nothing at all.
    check("…and at least one preset really is different from the defaults",
          Prefs.Preset.allCases.contains { prints[$0] != defaults })

    // Photographs is the one preset that spends bytes on pictures.
    resetPrefs(); Prefs.register()
    Prefs.Preset.photographs.apply()
    check("Photographs keeps picture detail at maximum",
          d.string(forKey: Prefs.photoDetail) == Prefs.PhotoDetail.maximum.rawValue)

    // keysWritten is the list the first check above relies on; if a preset
    // writes a key that is not in it, that check silently stops covering it.
    resetPrefs()
    let before = Prefs.allKeys.filter { d.object(forKey: $0) != nil }
    Prefs.Preset.newspaper.apply()
    let touched = Prefs.allKeys.filter { d.object(forKey: $0) != nil && !before.contains($0) }
    check("a preset writes only the keys it declares",
          Set(touched).isSubset(of: Prefs.Preset.keysWritten),
          Set(touched).subtracting(Prefs.Preset.keysWritten).sorted().joined(separator: ", "))

    // U30 · the button has to say what it did.
    //
    // Every key a preset may write needs a label, because the summary is built
    // with `compactMap` — a key with no label is dropped from the line in
    // silence, so the feedback would quietly under-report exactly as the button
    // used to say nothing at all.
    let unlabelled = Prefs.Preset.keysWritten
        .filter { Prefs.Preset.settingLabels[$0] == nil }.sorted()
    check("every setting a preset writes has a label for the summary",
          unlabelled.isEmpty, unlabelled.joined(separator: ", "))
    check("…and no label names a key no preset writes",
          Set(Prefs.Preset.settingLabels.keys) == Prefs.Preset.keysWritten,
          Set(Prefs.Preset.settingLabels.keys)
              .symmetricDifference(Prefs.Preset.keysWritten).sorted().joined(separator: ", "))
    // The line is only useful if the names in it are the names on screen. A label
    // that no longer matches its control sends the user looking for a setting that
    // is not there, and nothing else would notice: the summary would still read
    // perfectly well.
    let panelSource = (try? String(contentsOfFile: "Sources/SettingsView.swift",
                                   encoding: .utf8)) ?? ""
    let absent = Prefs.Preset.settingLabels.values
        .filter { !panelSource.contains($0) }.sorted()
    check("…and every label is text the settings panel actually shows",
          !panelSource.isEmpty && absent.isEmpty,
          panelSource.isEmpty ? "could not read SettingsView.swift"
                              : absent.joined(separator: " | "))

    // Applied over settings it disagrees with, it reports what moved.
    resetPrefs(); Prefs.register()
    Prefs.Preset.photographs.apply()
    let movedToNewspaper = Prefs.Preset.newspaper.apply()
    check("a preset reports the settings it changed",
          movedToNewspaper.contains(Prefs.Preset.settingLabels[Prefs.photoDetail]!),
          movedToNewspaper.joined(separator: ", "))
    check("…and the summary names them in the user's terms",
          Prefs.Preset.newspaper.summary(afterChanging: movedToNewspaper)
              .contains("Photo detail"),
          Prefs.Preset.newspaper.summary(afterChanging: movedToNewspaper))

    // Applied twice, the second click moved nothing — and has to say so rather
    // than list seven settings it did not change. This is the check that fails
    // if `apply` ever reports what it *wrote* instead of what changed.
    let secondClick = Prefs.Preset.newspaper.apply()
    check("…and reports nothing changed when the settings already matched",
          secondClick.isEmpty, secondClick.joined(separator: ", "))
    check("…saying so in words rather than falling silent",
          Prefs.Preset.newspaper.summary(afterChanging: secondClick)
              .contains("already matched"),
          Prefs.Preset.newspaper.summary(afterChanging: secondClick))

    // And it still does not become sticky state: nothing anywhere records which
    // preset was last applied. That is the property `apply`'s comment defends,
    // and a "currently using X" key is what would break it.
    resetPrefs(); Prefs.register()
    Prefs.Preset.typescript.apply()
    let names = Prefs.allKeys.filter { d.object(forKey: $0) != nil }
    check("applying a preset records no 'currently using' state",
          !names.contains { $0.lowercased().contains("preset") },
          names.filter { $0.lowercased().contains("preset") }.joined(separator: ", "))
    resetPrefs()
}

// MARK: - Forced re-OCR

// Feeding this app an already-OCR'd PDF must redo the recognition rather than
// pass the old text layer through. Proven with a decoy: the page *looks* like
// one string but its embedded text layer says another, so the output identifies
// which one was actually read.

print("\nforced re-OCR of already-OCR'd input")

do {
    let trap = tmp.appendingPathComponent("decoy.pdf")
    makeDecoyPDF(at: trap,
                 imageSays: ["HELLO VISION", "THIS CAME FROM THE IMAGE"],
                 textLayerSays: "DECOY TEXT LAYER FROM EMBEDDED STRING")

    check("the decoy really has a conflicting text layer",
          embeddedText(of: trap).contains("DECOY"), embeddedText(of: trap))

    resetPrefs()
    let out = tmp.appendingPathComponent("decoy-out")
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let r = extractText(trap, to: out)
    let got = (try? String(contentsOf: out.appendingPathComponent("decoy.txt"), encoding: .utf8)) ?? ""

    check("extract-text mode re-OCRs", r.succeeded && got.contains("HELLO VISION"),
          got.replacingOccurrences(of: "\n", with: " / "))
    check("extract-text mode ignores the embedded layer", !got.contains("DECOY"),
          got.replacingOccurrences(of: "\n", with: " / "))

    // Searchable mode does not solve this with mac-ocr's --ocr-all-pages (which
    // *adds* a layer to whatever is there); it rebuilds the pages as images, so
    // there is nothing left to read back. That default is what must hold.
    check("the rebuild that forces re-OCR is on by default",
          UserDefaults.standard.bool(forKey: Prefs.rebuildImages))
    resetPrefs()
}

// MARK: - Rebuilding away an old text layer

// A searchable PDF must contain Vision's text and nothing else. mac-ocr adds its
// layer on top of any existing one, so already-OCR'd input is rebuilt as images
// first. These checks prove the old text is gone and the new text isn't doubled.

print("\nrebuild removes the old text layer")

do {
    resetPrefs()
    let already = tmp.appendingPathComponent("already-ocrd.pdf")
    makeDecoyPDF(at: already,
                 imageSays: ["HELLO VISION", "THIS CAME FROM THE IMAGE"],
                 textLayerSays: "STALE TEXT LAYER THAT MUST NOT SURVIVE")

    check("input starts with a text layer", Flattener.hasEmbeddedText(already))

    let rebuilt = tmp.appendingPathComponent("rebuilt.pdf")
    try? Flattener.flatten(already, to: rebuilt, mode: .blackAndWhite)
    check("the rebuild produces a file", FileManager.default.fileExists(atPath: rebuilt.path))
    check("the rebuild has no text layer", !Flattener.hasEmbeddedText(rebuilt),
          embeddedText(of: rebuilt))

    // The picture must survive the rebuild, or there is nothing left to OCR.
    let out = tmp.appendingPathComponent("rebuild-out")
    try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let r = extractText(rebuilt, to: out)
    let got = (try? String(contentsOf: out.appendingPathComponent("rebuilt.txt"),
                           encoding: .utf8)) ?? ""
    check("the image survives and still OCRs", r.succeeded && got.contains("HELLO VISION"),
          got.replacingOccurrences(of: "\n", with: " / "))
    check("the stale layer is nowhere in the OCR", !got.contains("STALE"))

    // And end to end through our own writer: one layer, Vision's, not doubled.
    let pdfOut = tmp.appendingPathComponent("rebuild-pdf-out")
    try? FileManager.default.createDirectory(at: pdfOut, withIntermediateDirectories: true)
    let recognised = observations(of: rebuilt)
    check("recognition returns observations", !recognised.isEmpty, "\(recognised.count) pages")

    let composed = pdfOut.appendingPathComponent("rebuilt.ocr.pdf")
    do {
        let byPage = recognised
        check("observations decode", !byPage.isEmpty, "\(byPage.count) pages")
        try SearchableWriter.compose(visible: rebuilt, observations: byPage, to: composed)
    } catch {
        check("compose succeeds", false, error.localizedDescription)
    }
    let finalText = embeddedText(of: composed)
    check("searchable output carries Vision's text", finalText.contains("HELLO"), finalText)
    check("searchable output has no stale text", !finalText.contains("STALE"), finalText)
    check("searchable output isn't doubled",
          finalText.components(separatedBy: "HELLO").count - 1 == 1, finalText)

    check("rebuild is on by default", UserDefaults.standard.bool(forKey: Prefs.rebuildImages))
    resetPrefs()
}

// MARK: - Per-page bilevel vs greyscale

// A single global choice is wrong either way: forcing 1-bit turns a halftone
// into blotches (measured on a real book, a map spread went from legible to
// unreadable), while forcing greyscale multiplies the size of a text-only book.
// Automatic mode decides per page from ink coverage.

print("\nautomatic per-page image mode")

/// A page dark enough to read as a picture rather than text.
/// Mean colour of a rendered page, for checking that colour survived a route.
///
/// R49 needed this and the grey `inkFractionMRC` could not do it: a three-channel
/// stream declared `/DeviceGray` draws as garbage, and garbage lands inside any
/// ink-fraction band you would think to write. A page whose red channel is
/// supposed to dominate is a claim the mistake cannot satisfy.
func meanRGBOfRendered(_ url: URL, page index: Int) -> (r: Double, g: Double, b: Double)? {
    guard let doc = PDFDocument(url: url), let page = doc.page(at: index) else { return nil }
    let box = page.bounds(for: .mediaBox)
    guard box.width > 0, box.height > 0 else { return nil }
    let w = 200, h = max(1, Int(200 * box.height / box.width))
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ok = buf.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return false }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: CGFloat(w) / box.width, y: CGFloat(h) / box.height)
        page.draw(with: .mediaBox, to: ctx)
        return true
    }
    guard ok else { return nil }
    var sr = 0.0, sg = 0.0, sb = 0.0
    for i in stride(from: 0, to: w * h * 4, by: 4) {
        sr += Double(buf[i]); sg += Double(buf[i + 1]); sb += Double(buf[i + 2])
    }
    let n = Double(w * h)
    return (sr / n, sg / n, sb / n)
}

/// A page with real colour on it *and* text-shaped marks: a plate with a caption,
/// which is the shape colour MRC layering exists for. The red is strong and
/// deliberate — it is what proves the colour arrived, and in the right channel.
func makeColourPlatePDF(at url: URL) {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    let w = 1224, h = 1584
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
    // The plate: a strongly red field over the lower two-thirds.
    NSColor(deviceRed: 0.80, green: 0.12, blue: 0.10, alpha: 1).setFill()
    NSRect(x: 100, y: 120, width: w - 200, height: h - 700).fill()
    // The caption: black text-shaped bars across the top, where the stencil goes.
    NSColor.black.setFill()
    for row in 0..<8 {
        var x = 140.0
        while x < Double(w) - 200 {
            let run = Double(20 + (row * 7 + Int(x) % 37) % 60)
            NSRect(x: x, y: Double(h - 200 - row * 40), width: run, height: 14).fill()
            x += run + 16
        }
    }
    NSGraphicsContext.current?.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
    guard let cg = rep.cgImage else { return }
    pdf.beginPDFPage(nil); pdf.draw(cg, in: box); pdf.endPDFPage(); pdf.closePDF()
}

func makeDarkPDF(at url: URL) {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    let w = 1224, h = 1584
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
    // A broad mid-grey block: the shape of a halftone illustration.
    NSColor(calibratedWhite: 0.45, alpha: 1).setFill()
    NSRect(x: 120, y: 300, width: w - 240, height: h - 600).fill()
    NSGraphicsContext.current?.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
    guard let cg = rep.cgImage else { return }
    pdf.beginPDFPage(nil); pdf.draw(cg, in: box); pdf.endPDFPage(); pdf.closePDF()
}

do {
    resetPrefs()
    check("automatic is the default rebuild mode",
          UserDefaults.standard.string(forKey: Prefs.rebuildMode) == Flattener.Mode.auto.rawValue)
    check("automatic can still use JBIG2", Flattener.Mode.auto.canUseJBIG2)
    check("forced greyscale cannot", !Flattener.Mode.grayscale.canUseJBIG2)

    let dir = tmp.appendingPathComponent("auto")
    let pngs = dir.appendingPathComponent("pages")
    try? FileManager.default.createDirectory(at: pngs, withIntermediateDirectories: true)

    let textPage = tmp.appendingPathComponent("auto-text.pdf")
    makeScannedPDF(at: textPage, lines: ["an ordinary page of text",
                                        "with a second line of it",
                                        "and a third for good measure"])
    let darkPage = tmp.appendingPathComponent("auto-dark.pdf")
    makeDarkPDF(at: darkPage)

    func kinds(_ src: URL, mode: Flattener.Mode, into sub: String) -> [String] {
        let out = pngs.appendingPathComponent(sub)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let pages = (try? Flattener.flatten(src, to: dir.appendingPathComponent("\(sub).pdf"),
                                            mode: mode, pngDirectory: out)) ?? []
        return pages.map {
            switch $0.content { case .bilevel: return "bilevel"; case .jpeg: return "jpeg" }
        }
    }

    check("a text page goes bilevel", kinds(textPage, mode: .auto, into: "t") == ["bilevel"],
          kinds(textPage, mode: .auto, into: "t2").joined(separator: ","))
    check("a picture page goes greyscale", kinds(darkPage, mode: .auto, into: "d") == ["jpeg"],
          kinds(darkPage, mode: .auto, into: "d2").joined(separator: ","))
    check("forcing black & white overrides the picture check",
          kinds(darkPage, mode: .blackAndWhite, into: "d3") == ["bilevel"])
    check("forcing greyscale overrides the text check",
          kinds(textPage, mode: .grayscale, into: "t3") == ["jpeg"])

    // MARK: The allocation bounds, which are arithmetic over constants (A11.5)
    //
    // **Deliberately outside the `if JBIG2.isAvailable` below.** These four ran
    // inside it and touch no external tool at all — they compare two constants —
    // so on a machine without jbig2/qpdf `mutate.py`'s `const/maximumMRCPageMegapixels`
    // and `const/maximumColourPageMegapixels` mutants had nothing that could kill
    // them, and the mutation log would have recorded a survivor for the wrong
    // reason. A gated check is a check that does not exist on somebody's machine.
    //
    // Checked as a decision rather than by allocating the page each describes. R24
    // bounded one allocation and left its sibling unbounded (R29); layering is that
    // sibling for `flatten`'s render, holding about 8 bytes a pixel against 5.5.
    check("layering's worst case stays inside the render's",
          Flattener.mrcBoundIsWithinTheRenderOne,
          String(format: "MRC %.2f GB vs render %.2f GB",
                 Double(Flattener.maximumMRCPageMegapixels)
                    * Flattener.measuredMRCBytesPerPixel / 1000,
                 Double(Flattener.maximumPageMegapixels)
                    * Flattener.measuredGreyBytesPerPixel / 1000))
    check("…and layering is recorded as the more expensive per pixel",
          Flattener.measuredMRCBytesPerPixel > Flattener.measuredGreyBytesPerPixel)
    // R49 · the same property for colour layering, which holds three planes where
    // the grey route holds one. R24/R29's shape again: a bound asserted in one place
    // and left to be inferred in its sibling.
    check("colour layering's worst case stays inside the render's too",
          Flattener.colourMRCBoundIsWithinTheRenderOne,
          String(format: "colour MRC %.2f GB vs render %.2f GB",
                 Double(Flattener.maximumMRCPageMegapixels)
                    * Flattener.statedColourMRCBytesPerPixel / 1000,
                 Double(Flattener.maximumPageMegapixels)
                    * Flattener.measuredGreyBytesPerPixel / 1000))
    check("…and colour layering is recorded as the more expensive of the two",
          Flattener.statedColourMRCBytesPerPixel > Flattener.measuredMRCBytesPerPixel)
    // A11.5's third pair — `colourBoundIsWithinTheGreyOne` over
    // `maximumColourPageMegapixels` — is already asserted ungated further down,
    // with better commentary than a copy here would have. What that pair was
    // missing is a *mutant*: it was not in `mutate.py`'s catalogue at all, so
    // nothing had ever perturbed the constant to see whether the check bites.
    // Added there instead of duplicated here.

    // A mixed book must assemble into one valid PDF carrying both filters.
    if JBIG2.isAvailable {
        let mixedSrc = tmp.appendingPathComponent("auto-mixed.pdf")
        let merged = PDFDocument()
        for src in [textPage, darkPage] {
            if let d = PDFDocument(url: src), let p = d.page(at: 0) {
                merged.insert(p, at: merged.pageCount)
            }
        }
        merged.write(to: mixedSrc)

        let mpngs = dir.appendingPathComponent("mixed-pages")
        try? FileManager.default.createDirectory(at: mpngs, withIntermediateDirectories: true)
        let pages = (try? Flattener.flatten(mixedSrc,
                                            to: dir.appendingPathComponent("mixed-rebuilt.pdf"),
                                            mode: .auto, pngDirectory: mpngs)) ?? []
        check("the mixed document rebuilds both pages", pages.count == 2, "\(pages.count)")

        var streams: [JBIG2.Page] = []
        for (i, p) in pages.enumerated() {
            switch p.content {
            case .bilevel(let png):
                let o = dir.appendingPathComponent("m\(i).jbig2")
                try? JBIG2.encode(png: png, to: o, using: JBIG2.encoder!)
                streams.append(JBIG2.Page(stream: .jbig2(o), pixelWidth: p.pixelWidth,
                                          pixelHeight: p.pixelHeight, boxSize: p.boxSize))
            case .jpeg(let j):
                streams.append(JBIG2.Page(stream: .jpeg(j), pixelWidth: p.pixelWidth,
                                          pixelHeight: p.pixelHeight, boxSize: p.boxSize))
            }
        }
        let assembled = dir.appendingPathComponent("mixed-images.pdf")
        do { try JBIG2.assemble(streams, to: assembled) }
        catch { check("mixed assembly succeeds", false, error.localizedDescription) }

        check("the mixed PDF opens with both pages",
              PDFDocument(url: assembled)?.pageCount == 2,
              "\(PDFDocument(url: assembled)?.pageCount ?? -1)")
        let raw = String(decoding: (try? Data(contentsOf: assembled)) ?? Data(),
                         as: UTF8.self)
        // MARK: MRC — three layers on one page
        //
        // The stencil is an /SMask, and its polarity is the thing that cannot be
        // reasoned out: JBIG2 codes ink as 1, an /SMask reads 1 as opaque, but
        // PDF presents the decoded bitmap as DeviceGray where 1 is white. Both
        // readings are defensible from the specification and only one draws the
        // right picture, so it is pinned by rendering. Inverted, the foreground
        // shows everywhere *except* the text and the page comes out nearly
        // solid — which is what the ink bounds below catch.
        let mrcDir = dir.appendingPathComponent("mrc")
        try? FileManager.default.createDirectory(at: mrcDir, withIntermediateDirectories: true)
        if let jb = JBIG2.encoder,
           let doc = PDFDocument(url: darkPage), let dpage = doc.page(at: 0) {
            // Boxes covering the top half only, so the bottom stays in the
            // background — the shape of a page with a picture on it.
            let boxes = (0..<6).map { i in
                SearchableWriter.BoundingBox(x: 0.1, y: 0.05 + Double(i) * 0.06,
                                             width: 0.8, height: 0.045)
            }
            if let layers = Flattener.mrcLayers(for: dpage, boxes: boxes,
                                                into: mrcDir, stem: "t") {
                let stencil = mrcDir.appendingPathComponent("t.jbig2")
                try? JBIG2.encode(png: layers.mask, to: stencil, using: jb)
                let size = Flattener.fullBox(of: dpage).size
                let scale = Flattener.rebuildDPI(of: dpage) / 72.0
                let pw = Int((size.width * scale).rounded())
                let ph = Int((size.height * scale).rounded())
                let mrcPage = JBIG2.Page(
                    stream: .mrc(JBIG2.Page.MRC(
                        mask: stencil, background: layers.background,
                        foreground: layers.foreground,
                        backgroundWidth: layers.backgroundWidth,
                        backgroundHeight: layers.backgroundHeight,
                        foregroundWidth: layers.foregroundWidth,
                        foregroundHeight: layers.foregroundHeight)),
                    pixelWidth: pw, pixelHeight: ph, boxSize: size)

                // Mixed with a bilevel page on purpose: the two need different
                // numbers of objects, which is what broke the old `3 + i * 3`
                // arithmetic and would write an xref describing the wrong layout.
                let bilevelFirst = streams.first { if case .jbig2 = $0.stream { return true }
                                                   return false }
                let mixed = (bilevelFirst.map { [$0, mrcPage] } ?? [mrcPage])
                let mrcPDF = dir.appendingPathComponent("mrc-page.pdf")
                do { try JBIG2.assemble(mixed, to: mrcPDF) }
                catch { check("the MRC page assembles", false, error.localizedDescription) }

                let mraw = String(decoding: (try? Data(contentsOf: mrcPDF)) ?? Data(),
                                  as: UTF8.self)
                check("an MRC page writes three image XObjects",
                      mraw.components(separatedBy: "/Subtype /Image").count - 1
                        == (bilevelFirst == nil ? 3 : 4),
                      "\(mraw.components(separatedBy: "/Subtype /Image").count - 1)")
                check("…the foreground carries an /SMask", mraw.contains("/SMask"))
                check("…and the stencil is inverted for it",
                      mraw.contains("/Decode \(JBIG2.maskDecode)"))
                check("…and the page draws both layers",
                      mraw.contains("/Im0 Do") && mraw.contains("/Im1 Do"))
                check("…and it opens with every page present",
                      PDFDocument(url: mrcPDF)?.pageCount == mixed.count,
                      "\(PDFDocument(url: mrcPDF)?.pageCount ?? -1)")

                // The polarity check. A correct page has ink on it but is mostly
                // paper; an inverted stencil paints the foreground over
                // everything the text is *not*, which floods the sheet.
                let ink = inkFractionMRC(of: mrcPDF, page: mixed.count - 1)
                check("…and the stencil is the right way round",
                      ink > 0.01 && ink < 0.60, String(format: "%.3f ink", ink))
                // R49 · the same page layered in colour.
                //
                // Colour pages were excluded from layering, and that exclusion
                // was the whole of a 14x inflation on an Internet Archive scan
                // whose grey-green paper reads as colour: 568 text pages each
                // kept as a full-resolution three-channel JPEG, 31 MB in and
                // 437 MB out.
                //
                // The thing that cannot be reasoned out is the colour space. A
                // three-channel JPEG declared /DeviceGray is not an error any
                // reader reports — it draws the page as noise — so both the
                // declaration and the rendering are checked.
                let colourPlate = tmp.appendingPathComponent("mrc-colour-plate.pdf")
                makeColourPlatePDF(at: colourPlate)
                let cdoc = PDFDocument(url: colourPlate)
                let cpage = cdoc?.page(at: 0)
                // The fixture's own premise: the source really is red. Without
                // this the channel check below could pass on a page that never
                // had colour on it.
                let sourceRGB = meanRGBOfRendered(colourPlate, page: 0)
                check("the colour fixture is actually red",
                      (sourceRGB.map { $0.r - $0.b } ?? 0) > 25,
                      sourceRGB.map { String(format: "r %.0f b %.0f", $0.r, $0.b) } ?? "nil")
                // Boxes over the caption bars only, so the plate stays in the
                // background — a plate with a caption, which is the shape this is
                // for.
                let cboxes = (0..<8).map { i in
                    SearchableWriter.BoundingBox(x: 0.10, y: 0.06 + Double(i) * 0.025,
                                                 width: 0.78, height: 0.020)
                }
                if let cpage,
                   let colourLayers = Flattener.mrcLayers(
                    for: cpage, boxes: cboxes, into: mrcDir, stem: "c", inColour: true) {
                    check("layering a colour page reports colour layers",
                          colourLayers.isColour)
                    // Three channels in the file, not just in the flag.
                    for (which, url) in [("background", colourLayers.background),
                                         ("foreground", colourLayers.foreground)] {
                        let samples = (try? Data(contentsOf: url))
                            .flatMap { NSBitmapImageRep(data: $0)?.samplesPerPixel }
                        check("…and the \(which) really carries three of them",
                              samples == 3, "\(samples.map(String.init) ?? "unreadable")")
                    }

                    let cStencil = mrcDir.appendingPathComponent("c.jbig2")
                    try? JBIG2.encode(png: colourLayers.mask, to: cStencil, using: jb)
                    let csize = Flattener.fullBox(of: cpage).size
                    let cscale = Flattener.rebuildDPI(of: cpage) / 72.0
                    let cPage = JBIG2.Page(
                        stream: .mrc(JBIG2.Page.MRC(
                            mask: cStencil, background: colourLayers.background,
                            foreground: colourLayers.foreground,
                            backgroundWidth: colourLayers.backgroundWidth,
                            backgroundHeight: colourLayers.backgroundHeight,
                            foregroundWidth: colourLayers.foregroundWidth,
                            foregroundHeight: colourLayers.foregroundHeight,
                            isColour: colourLayers.isColour)),
                        pixelWidth: Int((csize.width * cscale).rounded()),
                        pixelHeight: Int((csize.height * cscale).rounded()),
                        boxSize: csize, isColour: true)
                    let cPDF = dir.appendingPathComponent("mrc-colour.pdf")
                    do { try JBIG2.assemble([cPage], to: cPDF) }
                    catch { check("the colour MRC page assembles", false,
                                  error.localizedDescription) }
                    let craw = String(decoding: (try? Data(contentsOf: cPDF)) ?? Data(),
                                      as: UTF8.self)
                    check("a colour MRC page declares /DeviceRGB tone layers",
                          craw.components(separatedBy: "/ColorSpace /DeviceRGB").count - 1 == 2,
                          "\(craw.components(separatedBy: "/ColorSpace /DeviceRGB").count - 1)")
                    // The stencil stays one channel whatever the tone layers are:
                    // it is a bilevel mask, not a colour image.
                    check("…while its stencil stays /DeviceGray",
                          craw.components(separatedBy: "/ColorSpace /DeviceGray").count - 1 == 1,
                          "\(craw.components(separatedBy: "/ColorSpace /DeviceGray").count - 1)")
                    check("…and still writes three image XObjects",
                          craw.components(separatedBy: "/Subtype /Image").count - 1 == 3,
                          "\(craw.components(separatedBy: "/Subtype /Image").count - 1)")
                    // And it draws, with its colour in the right channel.
                    //
                    // This is the check that catches a three-channel stream
                    // declared /DeviceGray, and it has to be a *colour* check: the
                    // garbage such a page draws lands comfortably inside any
                    // ink-fraction band, so the grey measurement passes on it. A
                    // red plate whose red channel still leads does not.
                    let cink = inkFractionMRC(of: cPDF, page: 0)
                    check("…and the layered colour page still has ink and paper both",
                          cink > 0.01 && cink < 0.60, String(format: "%.3f ink", cink))
                    if let out = meanRGBOfRendered(cPDF, page: 0), let src = sourceRGB {
                        check("…and its red survives the layering, in the red channel",
                              out.r - out.b > 25,
                              String(format: "r %.0f g %.0f b %.0f", out.r, out.g, out.b))
                        // Not merely "some red": the cast has to resemble the
                        // source's rather than being a coincidence of garbage.
                        check("…at roughly the source's strength",
                              abs((out.r - out.b) - (src.r - src.b)) < 40,
                              String(format: "layered %.0f vs source %.0f",
                                     out.r - out.b, src.r - src.b))
                    } else {
                        check("the layered colour page renders", false, "nil")
                    }

                    // The grey route must not have picked up the colour space on
                    // the way past: the two are distinguished by the layers' own
                    // flag, not the page's.
                    check("a grey MRC page still declares no /DeviceRGB",
                          !mraw.contains("/ColorSpace /DeviceRGB"))
                } else {
                    check("the colour MRC fixture produces layers", false,
                          "mrcLayers(inColour:) returned nil")
                }
            } else {
                check("the MRC fixture produces layers", false, "mrcLayers returned nil")
            }
        }

        // MARK: R50 — a page whose ink is all text shrinks its tone layers
        //
        // The signal is structural, not statistical: ink that is not inside any
        // recognised word is not text. `isPicture` cannot ask this because it runs
        // before recognition; layering can, because it runs after.
        //
        // Asserted on buffers first, where the answer is known by construction,
        // because the page-level checks below can only show that *something*
        // changed.
        let inkW = 40, inkH = 40
        var allPaper = [UInt8](repeating: 255, count: inkW * inkH)
        var wordRegion = [Bool](repeating: false, count: inkW * inkH)
        // A block of "text": ink, inside the region Vision reported.
        for y in 4..<12 { for x in 4..<36 { allPaper[y * inkW + x] = 20; wordRegion[y * inkW + x] = true } }
        check("ink that is all inside the words reads as no picture",
              Flattener.inkOutsideText(allPaper, region: wordRegion,
                                       width: inkW, height: inkH, threshold: 128) == 0,
              String(format: "%.4f", Flattener.inkOutsideText(allPaper, region: wordRegion,
                                                              width: inkW, height: inkH,
                                                              threshold: 128)))
        // The same page with a figure on it: ink nowhere near a word.
        var withFigure = allPaper
        for y in 20..<32 { for x in 8..<32 { withFigure[y * inkW + x] = 30 } }
        let figureScore = Flattener.inkOutsideText(withFigure, region: wordRegion,
                                                   width: inkW, height: inkH, threshold: 128)
        check("…while ink outside them does not",
              figureScore > Flattener.textPageInkOutsideThreshold,
              String(format: "%.4f vs threshold %.2f", figureScore,
                     Flattener.textPageInkOutsideThreshold))
        // A blank page has no picture on it, and must not divide by zero deciding so.
        check("…and a page with no ink at all is not a picture",
              Flattener.inkOutsideText([UInt8](repeating: 255, count: inkW * inkH),
                                       region: wordRegion, width: inkW, height: inkH,
                                       threshold: 128) == 0)
        // The scan's own dark edge is not content. Ink only in the outer sixteenth
        // must not count, or every page of a book with dark scan borders reads as
        // carrying a picture — which is what happened before the margin existed.
        var borderOnly = [UInt8](repeating: 255, count: inkW * inkH)
        for x in 0..<inkW { borderOnly[x] = 0; borderOnly[(inkH - 1) * inkW + x] = 0 }
        for y in 0..<inkH { borderOnly[y * inkW] = 0; borderOnly[y * inkW + inkW - 1] = 0 }
        check("…and a dark scan edge is not a picture either",
              Flattener.inkOutsideText(borderOnly, region: wordRegion,
                                       width: inkW, height: inkH, threshold: 128) == 0)

        // And the layers it produces. A text page's tone layers must come out at
        // the shrunk size; a page with a picture must not.
        if let doc = PDFDocument(url: textPage), let tpage = doc.page(at: 0) {
            // Boxes over the text, which is all this fixture has.
            let tboxes = (0..<10).map { i in
                SearchableWriter.BoundingBox(x: 0.10, y: 0.06 + Double(i) * 0.07,
                                             width: 0.80, height: 0.05)
            }
            if let l = Flattener.mrcLayers(for: tpage, boxes: tboxes, into: mrcDir,
                                           stem: "r50text", inColour: true) {
                let size = Flattener.fullBox(of: tpage).size
                let scale = Flattener.rebuildDPI(of: tpage) / 72.0
                let fullW = Int((size.width * scale).rounded())
                // Shrunk by the text-page factor, not the default one.
                check("a text page's background is shrunk by the text-page factor",
                      l.backgroundWidth <= fullW / Flattener.textPageBackgroundDownsample + 1,
                      "\(l.backgroundWidth) wide of \(fullW) at 1x")
                check("…and its foreground harder still",
                      l.foregroundWidth <= fullW / Flattener.textPageForegroundDownsample + 1,
                      "\(l.foregroundWidth) wide of \(fullW) at 1x")
            } else {
                check("the text fixture layers", false, "mrcLayers returned nil")
            }
        }
        // The picture case: a halftone plate under a caption. Its background must
        // stay at the caller's factor.
        //
        // The fixture is a *tonal* plate, not a flat colour one, and that is the
        // point rather than convenience. `makeColourPlatePDF`'s flat red renders at
        // luminance 96–111 while Otsu on that page lands at 106, so half the plate
        // sits above the ink threshold and an ink-based signal cannot see it at all
        // — measured, and recorded on `textPageInkOutsideThreshold` as the case this
        // rule misses. A real halftone spans the range and is seen. Using the flat
        // fixture here would assert the limitation instead of the behaviour.
        let tonalPlate = tmp.appendingPathComponent("r50-tonal-plate.pdf")
        var tpBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        if let c = CGContext(tonalPlate as CFURL, mediaBox: &tpBox, nil) {
            c.beginPDFPage(nil)
            c.setFillColor(CGColor(red: 0.99, green: 0.98, blue: 0.96, alpha: 1))
            c.fill(tpBox)
            // Caption bars across the top fifth, where the boxes go.
            c.setFillColor(CGColor(gray: 0.05, alpha: 1))
            for row in 0..<6 {
                var x = 70.0
                while x < 520 {
                    let run = Double(14 + (row * 5 + Int(x) % 23) % 40)
                    c.fill(CGRect(x: x, y: 700 - Double(row) * 14, width: run, height: 6))
                    x += run + 8
                }
            }
            // The plate: a tonal ramp through the darks, as a halftone has.
            for i in 0..<60 {
                let t = CGFloat(i) / 60
                c.setFillColor(CGColor(red: 0.08 + t * 0.7, green: 0.10 + t * 0.66,
                                       blue: 0.14 + t * 0.6, alpha: 1))
                c.fill(CGRect(x: 90, y: 120 + CGFloat(i) * 8, width: 430, height: 9))
            }
            c.endPDFPage(); c.closePDF()
        }
        if let cdoc = PDFDocument(url: tonalPlate), let cp = cdoc.page(at: 0) {
            let capOnly = (0..<6).map { i in
                SearchableWriter.BoundingBox(x: 0.11, y: 0.10 + Double(i) * 0.0177,
                                            width: 0.74, height: 0.012)
            }
            if let l = Flattener.mrcLayers(for: cp, boxes: capOnly, into: mrcDir,
                                           stem: "r50plate", backgroundDownsample: 2,
                                           inColour: true) {
                let size = Flattener.fullBox(of: cp).size
                let scale = Flattener.rebuildDPI(of: cp) / 72.0
                let fullW = Int((size.width * scale).rounded())
                check("a page carrying a picture keeps the background it was asked for",
                      l.backgroundWidth > fullW / Flattener.textPageBackgroundDownsample + 1,
                      "\(l.backgroundWidth) wide of \(fullW) at 1x")
            } else {
                check("the plate fixture layers", false, "mrcLayers returned nil")
            }
        }

        // Photo detail = Maximum is an instruction, and the text-page shrink must
        // not override it.
        //
        // Found by reviewing this diff, not by a user losing a page: the first
        // version applied the shrink at every setting, so a page the ink signal
        // reads as all-text was stored at an eighth of its resolution even when the
        // user had asked to keep every pixel. That matters because the signal has
        // two recorded misses and one of them, a pale line drawing, is a picture
        // read as text — see `textPageInkOutsideThreshold`.
        if let doc = PDFDocument(url: textPage), let tpage = doc.page(at: 0) {
            let tboxes = (0..<10).map { i in
                SearchableWriter.BoundingBox(x: 0.10, y: 0.06 + Double(i) * 0.07,
                                             width: 0.80, height: 0.05)
            }
            let size = Flattener.fullBox(of: tpage).size
            let scale = Flattener.rebuildDPI(of: tpage) / 72.0
            let fullW = Int((size.width * scale).rounded())
            if let l = Flattener.mrcLayers(for: tpage, boxes: tboxes, into: mrcDir,
                                           stem: "r50max",
                                           backgroundDownsample: Prefs.PhotoDetail.maximum.downsample,
                                           inColour: true) {
                check("a text page at Photo detail Maximum keeps every pixel",
                      l.backgroundWidth >= fullW,
                      "\(l.backgroundWidth) wide of \(fullW) at 1x")
                check("…and its foreground is not shrunk past the default either",
                      l.foregroundWidth >= fullW / Flattener.mrcForegroundDownsample,
                      "\(l.foregroundWidth) wide of \(fullW) at 1x")
            } else {
                check("the Maximum fixture layers", false, "mrcLayers returned nil")
            }
            // …while the level below it still gets the saving, so the guard is
            // narrow rather than a way of turning the whole rule off.
            if let l = Flattener.mrcLayers(for: tpage, boxes: tboxes, into: mrcDir,
                                           stem: "r50bal",
                                           backgroundDownsample: Prefs.PhotoDetail.balanced.downsample,
                                           inColour: true) {
                check("…but Balanced still shrinks a text page",
                      l.backgroundWidth <= fullW / Flattener.textPageBackgroundDownsample + 1,
                      "\(l.backgroundWidth) wide of \(fullW) at 1x")
            }
        }

        // No words means no layering: a plate would otherwise be published at a
        // fraction of its resolution for no benefit.
        if let doc = PDFDocument(url: darkPage), let dpage = doc.page(at: 0) {
            check("a page with no recognised words is not layered",
                  Flattener.mrcLayers(for: dpage, boxes: [], into: mrcDir, stem: "e") == nil)
        }

        check("it carries a JBIG2 stream", raw.contains("/JBIG2Decode"))
        check("…and a DCT stream alongside it", raw.contains("/DCTDecode"))
        check("bit depths match their filters",
              raw.contains("/BitsPerComponent 1") && raw.contains("/BitsPerComponent 8"))
    }
    resetPrefs()
}

// MARK: - R38: heavy ink is not on its own a picture

print("\ndense bilevel type is routed to 1-bit, not to the picture path")

/// A page built from exact 8-bit grey values, so ink and tone are *set* rather
/// than hoped for. `NSColor(calibratedWhite:)` does not put the byte you asked
/// for into the buffer — the dark-page fixture above asks for 0.45 grey over
/// half the sheet and measures `ink=0.0000`, because the value it lands on is
/// above the page's own Otsu split. A fixture for a threshold has to control the
/// number the threshold reads.
func makeGreyValuePDF(at url: URL, inkFraction: Double,
                      toneFraction: Double, toneValue: UInt8 = 128) {
    let w = 1224, h = 1584
    var buffer = [UInt8](repeating: 255, count: w * h)
    let inkRows = Int(Double(h) * inkFraction)
    for y in 0..<inkRows { for x in 0..<w { buffer[y * w + x] = 0 } }
    let toneRows = Int(Double(h) * toneFraction)
    for y in inkRows..<min(inkRows + toneRows, h) {
        for x in 0..<w { buffer[y * w + x] = toneValue }
    }
    guard let provider = CGDataProvider(data: Data(buffer) as CFData),
          let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8,
                           bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                           bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                           decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { return }
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    pdf.beginPDFPage(nil); pdf.draw(cg, in: box); pdf.endPDFPage(); pdf.closePDF()
}

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("r38-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    /// The three signals plus the verdict, read through the shipped call.
    func signals(inkFraction: Double, toneFraction: Double, toneValue: UInt8 = 128)
        -> (ink: Double, tone: Double, picture: Bool)? {
        let url = dir.appendingPathComponent("f-\(inkFraction)-\(toneFraction)-\(toneValue).pdf")
        makeGreyValuePDF(at: url, inkFraction: inkFraction,
                         toneFraction: toneFraction, toneValue: toneValue)
        guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        let box = Flattener.fullBox(of: page)
        let scale = Flattener.rebuildDPI(of: page) / 72.0
        let w = max(Int(box.width * scale), 1), h = max(Int(box.height * scale), 1)
        guard let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                              width: w, height: h, from: .mediaBox)
        else { return nil }
        let t = Flattener.otsuThreshold(of: grey)
        let s = Flattener.pictureSignals(page, grey: grey, width: w, height: h)
        return (s.ink, s.tone,
                Flattener.isPicture(page, grey: grey, width: w, height: h, threshold: t))
    }

    // A 2x2 over the conjunction: ink above its threshold in every row, tone
    // stepped across `pictureInkMinimumTone` and then across
    // `pictureToneThreshold`. Each row kills a different mutant, which is the
    // point of writing it as a table rather than as one assertion:
    //
    //   no tone      — deleting the tone gate leaves this a picture (the R38 bug)
    //   2% tone      — moving pictureInkMinimumTone down to 0.01 leaves this a picture
    //   6% tone      — deleting the ink branch, or raising the constant to 0.1,
    //                  makes this text; the tone branch alone cannot save it (0.06 < 0.12)
    //   20% tone     — tone decides on its own, with or without the ink branch
    if let dense = signals(inkFraction: 0.25, toneFraction: 0.0) {
        check("the dense-type fixture really is heavy ink with no tone",
              dense.ink > Flattener.pictureInkThreshold
                && dense.tone <= Flattener.pictureInkMinimumTone,
              String(format: "ink %.4f tone %.4f", dense.ink, dense.tone))
        check("heavy ink with no tone is text, not a picture", !dense.picture,
              String(format: "ink %.4f tone %.4f", dense.ink, dense.tone))
    } else { check("the dense-type fixture builds", false) }

    if let faint = signals(inkFraction: 0.25, toneFraction: 0.02) {
        check("…and tone below the minimum does not rescue it", !faint.picture,
              String(format: "ink %.4f tone %.4f", faint.ink, faint.tone))
    } else { check("the faint-tone fixture builds", false) }

    if let corroborated = signals(inkFraction: 0.25, toneFraction: 0.06) {
        // The load-bearing row. Tone here is *below* pictureToneThreshold, so
        // the tone branch cannot be what routes it — only the ink branch can,
        // which is what makes this the check that the ink branch still works.
        check("the corroborated fixture's tone is below the tone threshold on its own",
              corroborated.tone > Flattener.pictureInkMinimumTone
                && corroborated.tone < Flattener.pictureToneThreshold,
              String(format: "tone %.4f", corroborated.tone))
        check("heavy ink WITH corroborating tone is still a picture", corroborated.picture,
              String(format: "ink %.4f tone %.4f", corroborated.ink, corroborated.tone))
    } else { check("the corroborated fixture builds", false) }

    if let toneOnly = signals(inkFraction: 0.25, toneFraction: 0.20) {
        check("continuous tone still decides on its own", toneOnly.picture,
              String(format: "ink %.4f tone %.4f", toneOnly.ink, toneOnly.tone))
    } else { check("the tone-only fixture builds", false) }

    // End to end through `flatten`, not just through the predicate. The
    // predicate is what changed, but `flatten` is what publishes — and this
    // project has shipped a fix whose only test called a replica of the
    // pipeline rather than the pipeline.
    let densePDF = dir.appendingPathComponent("dense.pdf")
    makeGreyValuePDF(at: densePDF, inkFraction: 0.25, toneFraction: 0.0)
    let cor = dir.appendingPathComponent("corroborated.pdf")
    makeGreyValuePDF(at: cor, inkFraction: 0.25, toneFraction: 0.06)
    func routed(_ src: URL, _ sub: String) -> [String] {
        let out = dir.appendingPathComponent(sub)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let pages = (try? Flattener.flatten(src, to: dir.appendingPathComponent("\(sub).pdf"),
                                            mode: .auto, pngDirectory: out)) ?? []
        return pages.map { if case .bilevel = $0.content { return "bilevel" } else { return "jpeg" } }
    }
    check("flatten sends dense type to the 1-bit route", routed(densePDF, "d") == ["bilevel"],
          routed(densePDF, "d2").joined(separator: ","))
    check("…and keeps the corroborated page on the picture route",
          routed(cor, "c") == ["jpeg"], routed(cor, "c2").joined(separator: ","))
    resetPrefs()
}

// MARK: - JBIG2 compression

print("\nJBIG2 compression of the page images")

do {
    resetPrefs()
    check("JBIG2 is on by default", UserDefaults.standard.bool(forKey: Prefs.useJBIG2))

    if !JBIG2.isAvailable {
        skipBlock("JBIG2 compression of the page images", checks: 14,
                  because: "jbig2enc/qpdf not installed (\(JBIG2.installHint))")
    } else {
        // The census figure above is asserted at the end of this block, so it
        // cannot go stale: on any machine with the tools it is measured, and the
        // number the *toolless* run reports is therefore one this suite has
        // verified rather than one somebody counted by hand once (A11.7).
        let checksBeforeJBIG2Block = checks
        let page = tmp.appendingPathComponent("jb-src.pdf")
        makeScannedPDF(at: page, lines: ["JBIG2 compression test page",
                                        "second line of the page",
                                        "third line with digits 1234567890"])
        let dir = tmp.appendingPathComponent("jb")
        let pngs = dir.appendingPathComponent("pages")
        try? FileManager.default.createDirectory(at: pngs, withIntermediateDirectories: true)

        // Rebuild, capturing the bitmaps for the encoder.
        let rebuilt = dir.appendingPathComponent("rebuilt.pdf")
        let bitmaps = (try? Flattener.flatten(page, to: rebuilt, mode: .blackAndWhite,
                                              pngDirectory: pngs)) ?? []
        check("the rebuild yields one bitmap per page", bitmaps.count == 1, "\(bitmaps.count)")
        check("the bitmap PNG exists", bitmaps.first.map { page in
            if case .bilevel(let png) = page.content {
                return FileManager.default.fileExists(atPath: png.path)
            }
            return false
        } ?? false)

        // Recognise, build the text layer alone, compress, merge.
        let json = dir.appendingPathComponent("obs.json")
        let byPage = observations(of: rebuilt)

        let textLayer = dir.appendingPathComponent("text.pdf")
        try? SearchableWriter.compose(visible: rebuilt, observations: byPage,
                                      to: textLayer, drawImages: false)
        check("the text-only layer carries no image",
              !embeddedText(of: textLayer).isEmpty)

        var encoded: [JBIG2.Page] = []
        for (i, b) in bitmaps.enumerated() {
            guard case .bilevel(let png) = b.content else { continue }
            let stream = dir.appendingPathComponent("s\(i).jbig2")
            do {
                try JBIG2.encode(png: png, to: stream, using: JBIG2.encoder!)
                encoded.append(JBIG2.Page(stream: .jbig2(stream), pixelWidth: b.pixelWidth,
                                          pixelHeight: b.pixelHeight, boxSize: b.boxSize))
            } catch {
                check("encoding succeeds", false, error.localizedDescription)
            }
        }
        check("every page encodes", encoded.count == bitmaps.count)
        let streamBytes = encoded.reduce(0) { total, page in
            total + page.stream.urls.reduce(0) { sum, u in
                sum + (((try? FileManager.default.attributesOfItem(atPath: u.path)[.size]
                         as? Int) ?? 0) ?? 0)
            }
        }
        check("the JBIG2 streams are non-empty", streamBytes > 0, "\(streamBytes) bytes")

        let images = dir.appendingPathComponent("images.pdf")
        let final = dir.appendingPathComponent("final.pdf")
        do {
            try JBIG2.assemble(encoded, to: images)
            try JBIG2.overlay(text: textLayer, onto: images, to: final, using: JBIG2.merger!)
        } catch {
            check("assemble + overlay succeed", false, error.localizedDescription)
        }

        // The assembled PDF must be readable, right size, and keep its text.
        if let doc = PDFDocument(url: final) {
            check("the merged PDF opens", true)
            check("page count survives", doc.pageCount == bitmaps.count,
                  "\(doc.pageCount) vs \(bitmaps.count)")
            let sourceBox = PDFDocument(url: rebuilt)?.page(at: 0)?.bounds(for: .mediaBox)
            let finalBox = doc.page(at: 0)?.bounds(for: .mediaBox)
            // Page geometry must match the rebuild, or the text sits off the ink.
            check("page box matches the source",
                  abs((finalBox?.width ?? 0) - (sourceBox?.width ?? -1)) < 0.5
                    && abs((finalBox?.height ?? 0) - (sourceBox?.height ?? -1)) < 0.5,
                  "\(String(describing: finalBox)) vs \(String(describing: sourceBox))")
            let text = embeddedText(of: final)
            check("the text layer survives the merge", text.contains("JBIG2"), text)
            check("no stale duplicate of the text",
                  text.components(separatedBy: "compression test").count - 1 == 1, text)
        } else {
            check("the merged PDF opens", false, "PDFDocument returned nil")
        }

        // A plain scan with no text layer must still get JBIG2: it was
        // previously skipped because bitmaps were only produced when an old
        // text layer needed stripping.
        let plain = tmp.appendingPathComponent("plain-scan.pdf")
        makeScannedPDF(at: plain, lines: ["a scan with no text layer at all"])
        check("the plain scan really has no text layer", !Flattener.hasEmbeddedText(plain))
        let plainPngs = tmp.appendingPathComponent("plain-pages")
        try? FileManager.default.createDirectory(at: plainPngs, withIntermediateDirectories: true)
        let plainBitmaps = (try? Flattener.flatten(
            plain, to: tmp.appendingPathComponent("plain-rebuilt.pdf"),
            mode: .blackAndWhite, pngDirectory: plainPngs)) ?? []
        check("a text-free scan still yields bitmaps for JBIG2",
              plainBitmaps.count == 1, "\(plainBitmaps.count)")

        // The whole point: smaller than the CoreGraphics route.
        let flate = dir.appendingPathComponent("flate.pdf")
        try? SearchableWriter.compose(visible: rebuilt, observations: byPage, to: flate)
        func size(_ u: URL) -> Int {
            (((try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? 0) ?? 0)
        }
        check("JBIG2 output is smaller than the Flate route",
              size(final) < size(flate),
              "\(size(final)/1024)K vs \(size(flate)/1024)K")
        // A11.7. The number the toolless run will report for this block, verified
        // here rather than counted by hand. `+ 1` counts this check itself.
        check("the skip census figure for this block is still right",
              checks - checksBeforeJBIG2Block + 1 == 14,
              "\(checks - checksBeforeJBIG2Block + 1) checks, census says 14")
    }
    resetPrefs()
}

// MARK: - Word spacing in the text layer

// mac-ocr's own searchable-pdf writer positions words without emitting real
// space characters, so extractors merge roughly a third of them. Ours writes one
// run per line, spaces included. This guards that difference.

print("\nword spacing in the searchable PDF")

do {
    resetPrefs()
    let page = tmp.appendingPathComponent("spacing.pdf")
    let sentence = "the Practice of Democracy because as a black leader of the latter group"
    makeScannedPDF(at: page, lines: [sentence, "said Kansas City was not yet ready"])

    let dir = tmp.appendingPathComponent("spacing")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Reference: plain text output, which is correctly spaced.
    let refRun = extractText(page, to: dir)
    let reference = (try? String(contentsOf: dir.appendingPathComponent("spacing.txt"),
                                 encoding: .utf8)) ?? ""
    check("reference text is spaced correctly",
          refRun.succeeded && reference.contains("Practice of Democracy"),
          reference.replacingOccurrences(of: "\n", with: " / "))

    // Ours: recognise, then compose.
    let json = dir.appendingPathComponent("obs.json")
    let ours = dir.appendingPathComponent("ours.pdf")
    try? SearchableWriter.compose(visible: page, observations: observations(of: page),
                                  to: ours)
    let oursText = embeddedText(of: ours)
    check("our text layer keeps word spacing",
          oursText.contains("Practice of Democracy"),
          oursText.replacingOccurrences(of: "\n", with: " / "))
    check("our text layer doesn't split words",
          !oursText.contains("Democ racy") && !oursText.contains("Practi ce"),
          oursText.replacingOccurrences(of: "\n", with: " / "))

    // Word count should track the reference closely.
    func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).count
    }
    let refCount = wordCount(reference), ourCount = wordCount(oursText)
    check("our word count matches the reference",
          refCount > 0 && abs(refCount - ourCount) <= max(1, refCount / 20),
          "reference \(refCount) vs ours \(ourCount)")
    resetPrefs()
}

do {
    // Output must land where the caller resolved it, not beside the input.
    // `uniqueOutputs` picks a distinct path per file precisely so two inputs
    // called scan.pdf cannot collide, and beside-the-original must not override
    // that. (There was an explicitOutputDir here too, tested and never called
    // by anything that ships; it is gone.)
    resetPrefs()
    d.set(true, forKey: Prefs.besideOriginal)
    let input = URL(fileURLWithPath: "/Users/someone/Inbox/Book.pdf")
    let resolved = URL(fileURLWithPath: "/Users/someone/Scans/Book 2.txt")
    // Two checks here read the mac-ocr argument list to prove that an explicit
    // output file overrode "beside the original" and that no [name] template was
    // emitted beside it. There is no argument list. The property they were really
    // about — `uniqueOutputs` deciding one distinct destination per input — is
    // asserted directly in "output naming".
}

// MARK: - Bidirectional text

// Vision hands us each line in logical order. CoreText lays an RTL line out with
// its first logical run at the RIGHT — which is where the ink is, so the
// invisible run sits over the words it belongs to and the highlight is correct.
//
// PDFKit recovers logical order from that. A geometry-driven extractor cannot:
// "<hebrew> alpha" laid out RTL and "alpha <hebrew>" laid out LTR produce
// byte-identical glyph positions (measured — same glyphs, same x to 0.01 pt), so
// nothing in the content stream distinguishes them. Reversing our placement to
// suit such an extractor would move the text layer off the ink, which is a worse
// bug than the one it fixes. See BUGS.md C5.
//
// So: guard the PDFKit round-trip, so a change to draw() cannot silently start
// reversing right-to-left lines.

print("\nright-to-left text")

do {
    resetPrefs()
    let hebrew = "\u{05E9}\u{05DC}\u{05D5}\u{05DD}"      // shalom
    let arabic = "\u{0645}\u{0631}\u{062D}\u{0628}\u{0627}"  // marhaba
    let samples: [(String, String)] = [
        ("pure Hebrew", hebrew),
        ("pure Arabic", arabic),
        ("RTL followed by two LTR runs", "\(hebrew) alpha beta"),
        ("LTR either side of RTL", "alpha \(hebrew) beta"),
        ("digits inside RTL", "\(hebrew) 1234 \(hebrew)"),
        ("LTR control", "alpha beta gamma"),
    ]

    // A blank page to compose onto: this checks the text layer alone, so it needs
    // no recogniser and stays deterministic.
    let blank = tmp.appendingPathComponent("bidi-blank.pdf")
    var blankBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    if let ctx = CGContext(blank as CFURL, mediaBox: &blankBox, nil) {
        ctx.beginPDFPage(nil)
        NSColor.white.setFill()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(blankBox)
        ctx.endPDFPage()
        ctx.closePDF()
    }

    // One observation per sample, well separated so nothing is clamped or merged.
    var observations: [SearchableWriter.Observation] = []
    for (i, sample) in samples.enumerated() {
        observations.append(SearchableWriter.Observation(
            boundingBox: SearchableWriter.BoundingBox(
                x: 0.10, y: 0.10 + Double(i) * 0.12, width: 0.55, height: 0.030),
            text: sample.1,
            confidence: 1.0))
    }

    let out = tmp.appendingPathComponent("bidi-layer.pdf")
    var unplaced: [SearchableWriter.Unplaced] = []
    do {
        unplaced = try SearchableWriter.compose(
            visible: blank, observations: [1: observations], to: out)
    } catch {
        check("composing a right-to-left text layer succeeds", false, "\(error)")
    }
    check("no right-to-left line was skipped", unplaced.isEmpty,
          unplaced.map { "\($0.text): \($0.reason)" }.joined(separator: "; "))

    let extracted = embeddedText(of: out)
    for (label, text) in samples {
        check("\(label) survives extraction in logical order",
              extracted.contains(text),
              "wanted \(text.unicodeScalars.map { String(format: "%04X", $0.value) }.joined(separator: " "))"
              + " in " + extracted.unicodeScalars.map { String(format: "%04X", $0.value) }.joined(separator: " "))
    }
    resetPrefs()
}

// MARK: - Unplaced lines belong to the file that lost them

// `compose` used to record unplaceable lines in a static, which the caller read
// back after it returned. Files are OCR'd concurrently, so the next file's
// compose reset that static before the previous file's caller had looked at it:
// a document that lost lines got published as a clean success. Invariant 1.
//
// compose now returns them. This asserts the property that makes the race
// impossible — each caller sees exactly its own losses, under real concurrency.

print("\nunplaced lines are reported per file")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("unplaced")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let blank = dir.appendingPathComponent("blank.pdf")
    var blankBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    if let ctx = CGContext(blank as CFURL, mediaBox: &blankBox, nil) {
        ctx.beginPDFPage(nil); ctx.endPDFPage(); ctx.closePDF()
    }

    func observation(_ text: String, y: Double, degenerate: Bool)
        -> SearchableWriter.Observation {
        // A degenerate box is the reliable way to make draw() refuse a line:
        // it trips the "box too small" guard rather than being clamped.
        SearchableWriter.Observation(
            boundingBox: SearchableWriter.BoundingBox(
                x: 0.1, y: y,
                width: degenerate ? 0.0000001 : 0.5,
                height: degenerate ? 0.0000001 : 0.02),
            text: text, confidence: 1.0)
    }

    // Document A loses three lines; document B loses none.
    let aObs = (0..<3).map { observation("lost \($0)", y: 0.1 + Double($0) * 0.1,
                                         degenerate: true) }
               + (0..<3).map { observation("kept \($0)", y: 0.5 + Double($0) * 0.1,
                                           degenerate: false) }
    let bObs = (0..<6).map { observation("fine \($0)", y: 0.1 + Double($0) * 0.12,
                                         degenerate: false) }

    check("a degenerate box really is refused",
          ((try? SearchableWriter.compose(
              visible: blank, observations: [1: aObs],
              to: dir.appendingPathComponent("probe.pdf")))?.count ?? -1) == 3,
          "expected 3 unplaced")

    // Now hammer both concurrently. With shared static state the counts drift.
    let rounds = 40
    let lock = NSLock()
    var aCounts: Set<Int> = [], bCounts: Set<Int> = []
    DispatchQueue.concurrentPerform(iterations: rounds * 2) { i in
        let isA = i % 2 == 0
        let out = dir.appendingPathComponent("c\(i).pdf")
        let got = (try? SearchableWriter.compose(
            visible: blank, observations: [1: isA ? aObs : bObs], to: out))?.count ?? -1
        lock.lock()
        if isA { aCounts.insert(got) } else { bCounts.insert(got) }
        lock.unlock()
        try? FileManager.default.removeItem(at: out)
    }
    check("the losing file always reports exactly its own 3 lost lines",
          aCounts == [3], "saw \(aCounts.sorted())")
    check("the clean file never inherits another file's losses",
          bCounts == [0], "saw \(bCounts.sorted())")
    resetPrefs()
}

// MARK: - The drop box

print("\ndrop box")

do {
    // Exactly what Finder supplies on a drop: a provider carrying a file URL.
    let providers = [NSItemProvider(contentsOf: sample)].compactMap { $0 }
    check("a provider was constructed", providers.count == 1)

    var resolved: [URL]?
    resolveDroppedURLs(providers) { resolved = $0 }

    // The completion lands on the main queue; pump it until it does.
    let deadline = Date().addingTimeInterval(5)
    while resolved == nil, Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    check("a dropped file decodes to its URL",
          resolved?.first?.standardizedFileURL.path == sample.standardizedFileURL.path,
          resolved?.first?.path ?? "nil")
}

do {
    var empty: [URL]?
    resolveDroppedURLs([]) { empty = $0 }
    let deadline = Date().addingTimeInterval(2)
    while empty == nil, Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    check("an empty drop resolves to nothing", empty?.isEmpty == true)
}

do {
    let junk = tmp.appendingPathComponent("notes.rtf")
    FileManager.default.createFile(atPath: junk.path, contents: Data("x".utf8))

    let r = collectInputFiles(from: [sample, junk])
    check("supported files are kept", r.files.map(\.lastPathComponent) == ["scan one.pdf"],
          r.files.map(\.lastPathComponent).joined(separator: ","))
    check("unsupported files are counted, not added", r.ignored == 1, "\(r.ignored)")

    let dupes = collectInputFiles(from: [sample, sample], existing: [])
    check("a file dropped twice is added once", dupes.files.count == 1, "\(dupes.files.count)")

    let already = collectInputFiles(from: [sample], existing: [sample])
    check("a file already listed is not re-added", already.files.isEmpty)

    // A dropped folder contributes what's inside it.
    let folder = tmp.appendingPathComponent("dropped-folder")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    makeScannedPDF(at: folder.appendingPathComponent("b.pdf"), lines: ["B"])
    makeScannedPDF(at: folder.appendingPathComponent("a.pdf"), lines: ["A"])
    FileManager.default.createFile(atPath: folder.appendingPathComponent("skip.rtf").path,
                                   contents: Data("x".utf8))

    let fromFolder = collectInputFiles(from: [folder])
    check("a dropped folder yields its PDFs, sorted",
          fromFolder.files.map(\.lastPathComponent) == ["a.pdf", "b.pdf"],
          fromFolder.files.map(\.lastPathComponent).joined(separator: ","))
    check("a folder's unsupported files aren't reported as skipped",
          fromFolder.ignored == 0, "\(fromFolder.ignored)")

    let ordered = collectInputFiles(from: [folder, sample])
    check("drop order is preserved",
          ordered.files.map(\.lastPathComponent) == ["a.pdf", "b.pdf", "scan one.pdf"],
          ordered.files.map(\.lastPathComponent).joined(separator: ","))

    check("extension matching ignores case",
          collectInputFiles(from: [tmp.appendingPathComponent("X.PDF")]).ignored == 0)
}

// MARK: - Failure reporting

do {
    resetPrefs()
    let missing = tmp.appendingPathComponent("does-not-exist.pdf")
    let r = extractText(missing, to: out)
    check("a missing file is reported as a failure", !r.succeeded, r.message)
    check("…and says it could not be read", !r.message.isEmpty, r.message)

    // Cancelling has to be distinguishable from failing, or the summary lies.
    //
    // Two checks here covered the recognition subprocess: that a cancel landing
    // between launch and adoption reported .cancelled, and that a crashing child
    // was not misreported as a cancellation. Recognition launches nothing now —
    // `Recogniser` checks cancellation between pages — so both have no subject.
    // Deleted rather than weakened; the equivalent for jbig2 and qpdf, which are
    // still children, is exercised where the JBIG2 route is.
    let control = RunControl()
    control.cancel()
    check("a cancelled control refuses the work before it starts", control.isCancelled)
    // Mid-run cancellation of a real batch is covered under "batch accounting".
}

// MARK: - Concurrency control

print("\nconcurrency")

do {
    let n = Prefs.defaultConcurrency
    check("default concurrency is a sane core count", (1...8).contains(n), "\(n)")
    check("max concurrency is above the default", Prefs.maxConcurrency >= n)
}

do {
    // /bin/sleep rather than mac-ocr: this is testing the control, not OCR.
    func sleeper() -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        try? p.run()
        return p
    }
    func waitForExit(_ ps: [Process], _ seconds: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(seconds)
        while ps.contains(where: { $0.isRunning }), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    let control = RunControl()
    let running = (0..<3).map { _ in sleeper() }
    running.forEach { control.adopt($0) }
    check("three processes launch", running.allSatisfy { $0.isRunning })

    control.cancel()
    waitForExit(running)
    check("cancel terminates every tracked process", running.allSatisfy { !$0.isRunning },
          "\(running.filter(\.isRunning).count) still alive")
    check("cancel latches", control.isCancelled)

    // A worker that launched just as Cancel landed must not be stranded.
    let late = sleeper()
    control.adopt(late)
    waitForExit([late])
    check("a process adopted after cancel is terminated", !late.isRunning)

    // A released process is no longer the control's business.
    let fresh = RunControl()
    let released = sleeper()
    fresh.adopt(released)
    fresh.release(released)
    fresh.cancel()
    Thread.sleep(forTimeInterval: 0.4)
    check("a released process isn't terminated by a later cancel", released.isRunning)
    released.terminate()
}

// MARK: - Batch accounting

// The risky part of running files concurrently: every queued file must report
// back exactly once, including ones cancelled before they ever launched, or the
// batch never reaches its total and the UI stays stuck on "Running…".

print("\nbatch accounting")

/// Pumps the main run loop until `predicate` holds or the deadline passes.
/// The model is main-actor bound, so the main thread has to stay free to serve it.
func pump(until predicate: @escaping () -> Bool, seconds: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !predicate(), Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return predicate()
}

do {
    let inDir = tmp.appendingPathComponent("batch-in")
    let outDir = tmp.appendingPathComponent("batch-out")
    try? FileManager.default.createDirectory(at: inDir, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    for i in 1...8 {
        makeScannedPDF(at: inDir.appendingPathComponent("f\(i).pdf"),
                       lines: ["File \(i) of the batch", "second line here"])
    }

    // --- a clean run completes and accounts for every file ------------------
    resetPrefs()
    d.set(2, forKey: Prefs.concurrency)

    final class Holder: @unchecked Sendable { var model: OCRModel? }
    let holder = Holder()
    var ready = false

    d.set(false, forKey: Prefs.openWhenDone)
    Task { @MainActor in
        let m = OCRModel()
        m.besideOriginal = false
        m.outputFolder = outDir
        _ = m.add((1...8).map { inDir.appendingPathComponent("f\($0).pdf") })
        holder.model = m
        m.start()
        ready = true
    }
    _ = pump(until: { ready }, seconds: 5)

    let finished = pump(until: {
        MainActor.assumeIsolated { holder.model?.isRunning == false }
    }, seconds: 90)
    check("a concurrent batch finishes", finished)

    MainActor.assumeIsolated {
        guard let m = holder.model else { check("model exists", false); return }
        check("every file is accounted for", m.completed == m.total,
              "\(m.completed)/\(m.total)")
        check("nothing is left marked in flight", m.inFlight.isEmpty,
              m.inFlight.map(\.lastPathComponent).joined(separator: ","))
        check("all 8 files succeeded",
              m.log.contains { $0.text.contains("8 of 8 succeeded") },
              m.log.last?.text ?? "no log")
        // U26. The row-status checks elsewhere set `outcomes` by hand, so none
        // of them exercises the code that fills it in. This is a real batch:
        // if `finish` stopped recording, every row would say "waiting" while
        // the summary said 8 of 8 succeeded, and nothing else would notice.
        check("…and every row says so",
              m.files.allSatisfy { m.status(url: $0) == .succeeded },
              m.files.map { "\($0.lastPathComponent)=\(m.status(url: $0))" }
                  .prefix(3).joined(separator: " "))
        check("…with one problem counted per failed file, and none here",
              m.problemCount == 0, "\(m.problemCount)")
    }

    // --- cancelling mid-run still accounts for every file -------------------
    let outDir2 = tmp.appendingPathComponent("batch-out-2")
    try? FileManager.default.createDirectory(at: outDir2, withIntermediateDirectories: true)
    let holder2 = Holder()
    var ready2 = false

    d.set(false, forKey: Prefs.openWhenDone)
    d.set(false, forKey: Prefs.openWhenDone)
    Task { @MainActor in
        let m = OCRModel()
        m.besideOriginal = false
        m.outputFolder = outDir2
        _ = m.add((1...8).map { inDir.appendingPathComponent("f\($0).pdf") })
        holder2.model = m
        m.start()
        ready2 = true
    }
    _ = pump(until: { ready2 }, seconds: 5)

    // Cancel with work both in flight (2) and still queued (6).
    _ = pump(until: { false }, seconds: 0.5)
    MainActor.assumeIsolated { holder2.model?.cancel() }

    let stopped = pump(until: {
        MainActor.assumeIsolated { holder2.model?.isRunning == false }
    }, seconds: 60)
    check("a cancelled batch finishes rather than hanging", stopped)

    MainActor.assumeIsolated {
        guard let m = holder2.model else { check("model exists", false); return }
        check("cancelled batch accounts for every file", m.completed == m.total,
              "\(m.completed)/\(m.total)")
        check("cancelled batch clears in-flight", m.inFlight.isEmpty)
        check("cancelled batch reports a summary",
              m.log.contains { $0.text.hasPrefix("Done —") },
              m.log.last?.text ?? "no log")
        // Files queued but never launched must be counted as cancelled, not lost.
        let summary = m.log.last(where: { $0.text.hasPrefix("Done —") })?.text ?? ""
        check("the summary mentions cancellation", summary.contains("cancelled"), summary)
    }
    resetPrefs()
}

// MARK: - The whole searchable pipeline, end to end

// Every other check here exercises one stage in isolation. That let a regression
// ship that broke every single run: the page-count guard read a file the
// cleanup step had already deleted, so it saw -1 pages and refused to publish.
// Nothing short of running the real function catches that.

print("\nsearchable PDF, end to end")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("e2e-pipeline")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Three pages, one of them picture-like, so both codecs are exercised.
    let src = dir.appendingPathComponent("book.pdf")
    let merged = PDFDocument()
    for i in 1...2 {
        let one = dir.appendingPathComponent("t\(i).pdf")
        makeScannedPDF(at: one, lines: ["page \(i) of the document",
                                       "a second line of running text"])
        if let d = PDFDocument(url: one), let p = d.page(at: 0) {
            merged.insert(p, at: merged.pageCount)
        }
    }
    let dark = dir.appendingPathComponent("dark.pdf")
    makeDarkPDF(at: dark)
    if let d = PDFDocument(url: dark), let p = d.page(at: 0) {
        merged.insert(p, at: merged.pageCount)
    }
    merged.write(to: src)
    check("the test document has three pages", PDFDocument(url: src)?.pageCount == 3)

    for jbig2 in [true, false] {
        resetPrefs()
        d.set(jbig2, forKey: Prefs.useJBIG2)
        let label = jbig2 ? "compressed" : "fallback"
        let output = dir.appendingPathComponent("out-\(label).pdf")
        var outcome: Runner.Result.Outcome?
        var message = ""

        OCRModel.makeSearchablePDF(
            file: src, output: output,
            rebuild: true, rebuildMode: .auto, password: nil,
            control: RunControl(), progress: { _, _ in },
            report: { o, m in outcome = o; message = m })

        check("\(label): the run succeeds", outcome == .succeeded, message)
        check("\(label): the output file exists",
              FileManager.default.fileExists(atPath: output.path))
        check("\(label): every page is present",
              PDFDocument(url: output)?.pageCount == 3,
              "\(PDFDocument(url: output)?.pageCount ?? -1) pages")
        let text = embeddedText(of: output)
        check("\(label): the text layer is there", text.contains("page 1"), text.prefix(60).description)
    }
    resetPrefs()
}

// MARK: - Output names never collide

// Two inputs with the same base name in different folders both mapped to one
// output path, so the second silently overwrote the first — and under
// concurrency they raced for it.

print("\noutput naming")

do {
    resetPrefs()
    let a = URL(fileURLWithPath: "/inbox/chapter1/scan.pdf")
    let b = URL(fileURLWithPath: "/inbox/chapter2/scan.pdf")
    let c = URL(fileURLWithPath: "/inbox/chapter3/other.pdf")
    let folder = URL(fileURLWithPath: "/results")

    let pdfOut = OCRModel.uniqueOutputs(for: [a, b, c], besideOriginal: false,
                                        folder: folder, suffix: ".ocr", extension: "pdf")
    let paths = [a, b, c].compactMap { pdfOut[$0]?.lastPathComponent }
    check("same-named inputs get distinct outputs",
          Set(paths).count == 3, paths.joined(separator: " | "))
    check("the first keeps the natural name", paths.first == "scan.ocr.pdf",
          paths.first ?? "nil")
    check("the clash is disambiguated, not dropped",
          paths.contains { $0.contains("2") }, paths.joined(separator: " | "))
    check("unrelated names are untouched", paths.contains("other.ocr.pdf"))

    // Beside-the-original can't collide: the folders differ.
    let beside = OCRModel.uniqueOutputs(for: [a, b], besideOriginal: true,
                                        folder: nil, suffix: ".ocr", extension: "pdf")
    check("beside-the-original keeps both natural names",
          beside[a]?.path == "/inbox/chapter1/scan.ocr.pdf"
            && beside[b]?.path == "/inbox/chapter2/scan.ocr.pdf",
          "\(beside[a]?.path ?? "nil") / \(beside[b]?.path ?? "nil")")

    // Text mode used to be checked here against mac-ocr's [name] template.
    // `uniqueOutputs` above is the whole of that decision now.
    resetPrefs()
}

// MARK: - The text layer tracks per-page size

// Both PDF writers set a per-page media box, and both must pass CFData: an
// NSValue is accepted and silently ignored, leaving every page with page 1's
// size. In a book whose pages vary (456x710 against 461x725) the text layer then
// had the wrong shape, qpdf scaled it onto the image layer, and the text drifted
// down by up to a full line — which made the first line of a selection vanish.

print("\ntext layer page geometry")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("geometry")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Two pages of deliberately different sizes.
    func sized(_ url: URL, w: CGFloat, h: CGFloat) {
        var box = CGRect(x: 0, y: 0, width: w, height: h)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
        pdf.beginPDFPage(nil)
        pdf.setFillColor(gray: 0, alpha: 1)
        pdf.fill(CGRect(x: 20, y: h - 60, width: w - 40, height: 8))
        pdf.endPDFPage(); pdf.closePDF()
    }
    let a = dir.appendingPathComponent("a.pdf"), b = dir.appendingPathComponent("b.pdf")
    sized(a, w: 461, h: 725)
    sized(b, w: 456, h: 710)
    let both = PDFDocument()
    for u in [a, b] {
        if let d = PDFDocument(url: u), let p = d.page(at: 0) { both.insert(p, at: both.pageCount) }
    }
    let src = dir.appendingPathComponent("both.pdf")
    both.write(to: src)
    check("the fixture has two different page sizes",
          PDFDocument(url: src)?.page(at: 0)?.bounds(for: .mediaBox).width == 461
            && PDFDocument(url: src)?.page(at: 1)?.bounds(for: .mediaBox).width == 456)

    // A text layer with one observation per page.
    func obs(_ t: String) -> SearchableWriter.Observation {
        .init(boundingBox: .init(x: 0.1, y: 0.1, width: 0.7, height: 0.02),
              text: t, confidence: 1)
    }
    let layer = dir.appendingPathComponent("layer.pdf")
    try? SearchableWriter.compose(visible: src,
                                  observations: [1: [obs("first page text")],
                                                 2: [obs("second page text")]],
                                  to: layer, drawImages: false)

    let out = PDFDocument(url: layer)
    check("the layer has both pages", out?.pageCount == 2, "\(out?.pageCount ?? -1)")
    let p1 = out?.page(at: 0)?.bounds(for: .mediaBox) ?? .zero
    let p2 = out?.page(at: 1)?.bounds(for: .mediaBox) ?? .zero
    check("page 1 of the layer matches page 1 of the source",
          Int(p1.width) == 461 && Int(p1.height) == 725,
          "\(Int(p1.width))x\(Int(p1.height))")
    check("page 2 keeps its OWN size, not page 1's",
          Int(p2.width) == 456 && Int(p2.height) == 710,
          "\(Int(p2.width))x\(Int(p2.height))")
    resetPrefs()
}

// MARK: - Closely-spaced lines stay selectable

// A superscript footnote marker sits only ~8pt from the line beneath it. Sizing
// the invisible text from line *width* inflated it by half again (Helvetica is
// narrower than book faces), so those runs overlapped and Preview stopped seeing
// them as separate lines: dragging over the paragraph silently skipped its last
// line. Geometry taken from a real page 76.

print("\nclosely-spaced lines")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("tight")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let page = dir.appendingPathComponent("page.pdf")
    makeScannedPDF(at: page, lines: ["placeholder"])

    func obs(_ text: String, x: Double, y: Double, w: Double, h: Double)
        -> SearchableWriter.Observation {
        SearchableWriter.Observation(
            boundingBox: .init(x: x, y: y, width: w, height: h),
            text: text, confidence: 1)
    }
    // Body line, superscript marker, then the paragraph's final line.
    let lines = [
        obs("interested in securing legal safeguards for merit employment",
            x: 0.1335, y: 0.6483, w: 0.7688, h: 0.0160),
        obs("68", x: 0.4793, y: 0.6686, w: 0.0301, h: 0.0145),
        obs("practices in San Francisco.", x: 0.1335, y: 0.6788, w: 0.3477, h: 0.0145),
    ]
    let out = dir.appendingPathComponent("layer.pdf")
    try? SearchableWriter.compose(visible: page, observations: [1: lines], to: out)

    let text = embeddedText(of: out)
    let rows = text.components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    check("all three runs are present",
          text.contains("merit employment") && text.contains("68")
            && text.contains("practices in San Francisco"),
          text.replacingOccurrences(of: "\n", with: " / "))
    check("they extract as three separate lines, not one merged line",
          rows.count == 3, "\(rows.count) lines: " + rows.joined(separator: " | "))
    check("the paragraph's last line stands alone",
          rows.last == "practices in San Francisco.", rows.last ?? "nil")
    check("word spacing survives",
          text.contains("securing legal safeguards for merit employment"),
          text.replacingOccurrences(of: "\n", with: " / "))
    resetPrefs()
}

// MARK: - Rotated pages

// A scan is often stored sideways with /Rotate set to display it upright. The
// rebuild has to honour that: getting it wrong produced a page drawn off-canvas
// that Vision read as completely blank, and later a portrait bitmap stretched
// into a landscape page box.

print("\nrotated pages")

/// A landscape sheet whose text is drawn sideways, as a sideways scan would be.
func makeSidewaysPDF(at url: URL, text: String) {
    var box = CGRect(x: 0, y: 0, width: 792, height: 612)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1584, pixelsHigh: 1224,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1584, height: 1224).fill()
    let t = NSAffineTransform()
    t.translateX(by: 200, yBy: 200); t.rotate(byDegrees: 90); t.concat()
    (text as NSString).draw(at: .zero, withAttributes: [
        .font: NSFont(name: "Helvetica-Bold", size: 70) ?? NSFont.systemFont(ofSize: 70),
        .foregroundColor: NSColor.black])
    NSGraphicsContext.current?.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
    guard let cg = rep.cgImage,
          let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    pdf.beginPDFPage(nil); pdf.draw(cg, in: box); pdf.endPDFPage(); pdf.closePDF()
}

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("rotate")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let sideways = dir.appendingPathComponent("sideways.pdf")
    makeSidewaysPDF(at: sideways, text: "SIDEWAYS SCAN TEXT")
    let doc = PDFDocument(url: sideways)
    let page = doc?.page(at: 0)
    check("built the sideways page", page != nil)
    page?.rotation = 270                       // turns it upright for a reader
    let rotated = dir.appendingPathComponent("rotated.pdf")
    doc?.write(to: rotated)

    let rp = PDFDocument(url: rotated)?.page(at: 0)
    check("rotation is preserved in the file", rp?.rotation == 270, "\(rp?.rotation ?? -1)")

    // MRC on a quarter-turned page. Invariant 5: a fixture without a rotated
    // page is structurally blind to geometry bugs, and this route has two
    // geometries that must agree — the stencil is built from Vision's boxes,
    // which are normalised to the *rebuilt* page (upright, dimensions swapped),
    // while the layers are rendered from the *source* page (sideways, with the
    // rotation applied during render). If those disagree the stencil lands at
    // ninety degrees to the text: every glyph stays in the background and the
    // foreground paints a band of ink across the page. Nothing else here would
    // notice, because the page count and the text layer would both be correct.
    if let jb = JBIG2.encoder, let rpage = rp {
        let rbox = Flattener.fullBox(of: rpage)
        let rscale = Flattener.rebuildDPI(of: rpage) / 72.0
        let rw = Int((rbox.width * rscale).rounded()), rh = Int((rbox.height * rscale).rounded())
        // The box is derived from where the ink actually is rather than guessed,
        // for the same reason Vision's would be: on a quarter-turned page the
        // text is not where the unrotated coordinates say it is, and a guessed
        // box that misses produces an empty stencil — which would look like a
        // passing test of nothing.
        var rboxes: [SearchableWriter.BoundingBox] = []
        if let g = Flattener.renderGrey(rpage, box: rbox, scale: rscale,
                                        width: rw, height: rh, from: .mediaBox) {
            var minX = rw, maxX = 0, minY = rh, maxY = 0
            for y in 0..<rh {
                for x in 0..<rw where g[y * rw + x] < 128 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            if minX <= maxX, minY <= maxY {
                rboxes = [SearchableWriter.BoundingBox(
                    x: Double(minX) / Double(rw), y: Double(minY) / Double(rh),
                    width: Double(maxX - minX + 1) / Double(rw),
                    height: Double(maxY - minY + 1) / Double(rh))]
            }
        }
        check("the rotated fixture has findable ink, or the checks below prove nothing",
              !rboxes.isEmpty)
        let rdir = dir.appendingPathComponent("mrc")
        try? FileManager.default.createDirectory(at: rdir, withIntermediateDirectories: true)
        if let layers = Flattener.mrcLayers(for: rpage, boxes: rboxes,
                                            into: rdir, stem: "r") {
            let st = rdir.appendingPathComponent("r.jbig2")
            try? JBIG2.encode(png: layers.mask, to: st, using: jb)
            let out = dir.appendingPathComponent("rotated-mrc.pdf")
            try? JBIG2.assemble([JBIG2.Page(
                stream: .mrc(JBIG2.Page.MRC(
                    mask: st, background: layers.background, foreground: layers.foreground,
                    backgroundWidth: layers.backgroundWidth,
                    backgroundHeight: layers.backgroundHeight,
                    foregroundWidth: layers.foregroundWidth,
                    foregroundHeight: layers.foregroundHeight)),
                pixelWidth: rw, pixelHeight: rh, boxSize: rbox.size)], to: out)
            check("a rotated page layers into a PDF that opens",
                  PDFDocument(url: out)?.pageCount == 1)
            // The published page must keep the reader-facing shape, not the raw
            // one — a stencil applied in the wrong geometry shows up here first.
            let pb = PDFDocument(url: out)?.page(at: 0)?.bounds(for: .mediaBox) ?? .zero
            check("…at the size a reader sees, not the unrotated one",
                  Int(pb.width) == Int(rbox.width) && Int(pb.height) == Int(rbox.height),
                  "\(Int(pb.width))x\(Int(pb.height)) vs \(Int(rbox.width))x\(Int(rbox.height))")
            let rink = inkFractionMRC(of: out, page: 0)
            check("…and it is neither blank nor flooded",
                  rink > 0.005 && rink < 0.60, String(format: "%.3f ink", rink))
        } else {
            check("the rotated page produces layers", false, "mrcLayers returned nil")
        }
    }

    // displayBox swaps the dimensions for a quarter turn.
    let display = rp.map { Flattener.displayBox(of: $0) } ?? .zero
    let raw = rp?.bounds(for: .mediaBox) ?? .zero
    check("displayBox swaps a quarter-turned page",
          Int(display.width) == Int(raw.height) && Int(display.height) == Int(raw.width),
          "display \(Int(display.width))x\(Int(display.height)) vs raw "
            + "\(Int(raw.width))x\(Int(raw.height))")

    let rebuilt = dir.appendingPathComponent("rebuilt.pdf")
    let pngs = dir.appendingPathComponent("pages")
    try? FileManager.default.createDirectory(at: pngs, withIntermediateDirectories: true)
    let pages = (try? Flattener.flatten(rotated, to: rebuilt, mode: .auto,
                                        pngDirectory: pngs)) ?? []

    let outBox = PDFDocument(url: rebuilt)?.page(at: 0)?.bounds(for: .mediaBox) ?? .zero
    check("the rebuilt page box matches the display box",
          Int(outBox.width) == Int(display.width) && Int(outBox.height) == Int(display.height),
          "\(Int(outBox.width))x\(Int(outBox.height)) vs \(Int(display.width))x\(Int(display.height))")

    // Box and bitmap must agree in orientation, or the image is stretched.
    if let first = pages.first {
        let boxIsPortrait = outBox.height > outBox.width
        let pixIsPortrait = first.pixelHeight > first.pixelWidth
        check("bitmap orientation matches the page box", boxIsPortrait == pixIsPortrait,
              "box \(Int(outBox.width))x\(Int(outBox.height)) vs bitmap "
                + "\(first.pixelWidth)x\(first.pixelHeight)")
    } else {
        check("the rotated page rebuilt at all", false)
    }

    // The real proof: Vision can still read it.
    let ocrOut = dir.appendingPathComponent("ocr")
    try? FileManager.default.createDirectory(at: ocrOut, withIntermediateDirectories: true)
    let r = extractText(rebuilt, to: ocrOut)
    let text = (try? String(contentsOf: ocrOut.appendingPathComponent("rebuilt.txt"),
                            encoding: .utf8)) ?? ""
    check("the rebuilt rotated page is still readable",
          r.succeeded && text.contains("SIDEWAYS"),
          text.trimmingCharacters(in: .whitespacesAndNewlines))
    resetPrefs()
}

// MARK: - Same-named inputs are tracked separately

// stages and inFlight were keyed by file *name*. Two inputs called scan.pdf in
// different folders shared one key: inFlight held two entries but stages one,
// so the bar read 0.25 where it should read 0.5, and
// `inFlight.removeAll { $0 == name }` dropped both when the first finished.

print("\ntwo inputs with the same name")

do {
    resetPrefs()
    let root = tmp.appendingPathComponent("samename")
    let a = root.appendingPathComponent("A"), b = root.appendingPathComponent("B")
    for d in [a, b] {
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    }
    // Same base name, different folders.
    let fileA = a.appendingPathComponent("scan.pdf")
    let fileB = b.appendingPathComponent("scan.pdf")
    makeScannedPDF(at: fileA, lines: ["Alpha document"])
    makeScannedPDF(at: fileB, lines: ["Bravo document"])

    let outs = OCRModel.uniqueOutputs(for: [fileA, fileB], besideOriginal: false,
                                      folder: root, suffix: ".ocr", extension: "pdf")
    check("the two inputs get distinct outputs",
          outs[fileA] != nil && outs[fileB] != nil && outs[fileA] != outs[fileB],
          "\(outs[fileA]?.lastPathComponent ?? "nil") vs \(outs[fileB]?.lastPathComponent ?? "nil")")
    check("exactly one of them keeps the plain name",
          [outs[fileA], outs[fileB]].compactMap { $0?.lastPathComponent }
              .filter { $0 == "scan.ocr.pdf" }.count == 1,
          "\(outs.values.map(\.lastPathComponent).sorted())")

    // Keyed by URL, the two no longer collide.
    var stages: [URL: Double] = [:]
    stages[fileA] = 0.5
    stages[fileB] = 0.5
    check("progress keyed by URL keeps both files", stages.count == 2, "\(stages.count)")
    var inFlight = [fileA, fileB]
    inFlight.removeAll { $0 == fileA }
    check("finishing one does not drop the other",
          inFlight == [fileB], "\(inFlight.map(\.path))")

    // The old behaviour, for contrast: by name they are one key.
    var byName: [String: Double] = [:]
    byName[fileA.lastPathComponent] = 0.5
    byName[fileB.lastPathComponent] = 0.5
    check("…which keying by name did not", byName.count == 1, "\(byName.count)")
    resetPrefs()
}

// MARK: - The streaming read, retired with the subprocess it served

// Two blocks lived here. `runStreaming`'s loop used to sit in `availableData`,
// which blocks until every writer closes stdout — including any grandchild that
// inherited it — so a child that exited at once while leaving a `sleep` holding
// the pipe parked the loop for the sleep's full duration, with Cancel already
// spent, and then reported success (R2, U18). The second checked that stderr was
// drained concurrently and kept, because a child that fills the stderr pipe
// while nobody reads it deadlocks (R3).
//
// Recognition no longer streams anything: `Recogniser` calls Vision in process
// and checks cancellation between pages. Both blocks are deleted rather than
// weakened, because a check that cannot fail is worse than none (T4, T6).
//
// **The reasoning is not lost — the same bounded-read shape survives in
// `captureBounded`**, which `locateTool` uses to ask a login shell where jbig2
// and qpdf are, and which is checked with the same wedged-grandchild fixture
// under "recognition languages this Mac actually has". `stop()`'s escalation
// past a SIGTERM-proof child is checked immediately below and still matters:
// jbig2 and qpdf are children.

print("\nstop() escalates past a child that ignores SIGTERM")

do {
    // terminate() alone leaves a SIGTERM-ignoring child running for ever.
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", "trap '' TERM; sleep 30"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    usleep(200_000)
    check("the stubborn child is running", p.isRunning)
    let began = Date()
    Runner.stop(p, graceSeconds: 0.5)
    let took = Date().timeIntervalSince(began)
    check("stop() kills it rather than waiting for the sleep",
          !p.isRunning && took < 5, String(format: "running=%@ took=%.2fs",
                                           p.isRunning ? "yes" : "no", took))
}

// MARK: - A small image must not set the whole page's resolution

// nativeDPI reports the resolution implied by the largest embedded image. On a
// born-digital page that image is a logo, not the scan, and rebuilding at its
// resolution destroys the text. Measured across the corpus: 84 of 214 sampled
// pages report under 150 DPI, and one page carrying 1,846 characters reports
// 1.9 DPI — a 595x841 pt page rebuilt as 16x23 pixels, reported as a success
// because the page count still matched.

print("\na logo does not set the page's rebuild resolution")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("dpi")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Real text, plus one deliberately tiny image — exactly the born-digital
    // shape that produced 1.9 DPI on the corpus.
    let born = dir.appendingPathComponent("born.pdf")
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    if let ctx = CGContext(born as CFURL, mediaBox: &box, nil) {
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(box)
        // A 16x16 logo on a 612 pt page implies 16 / (612/72) = 1.9 DPI.
        if let logo = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: logo)
            NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill()
            NSGraphicsContext.current?.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            if let cg = logo.cgImage {
                ctx.draw(cg, in: CGRect(x: 20, y: 740, width: 24, height: 24))
            }
        }
        let font = NSFont(name: "Helvetica", size: 24) ?? NSFont.systemFont(ofSize: 24)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "REBUILDABLE TEXT ON A BORN DIGITAL PAGE",
            attributes: [.font: font, .foregroundColor: NSColor.black]))
        ctx.textPosition = CGPoint(x: 60, y: 400)
        CTLineDraw(line, ctx)
        ctx.endPDFPage()
        ctx.closePDF()
    }

    guard let bd = PDFDocument(url: born), let bp = bd.page(at: 0) else {
        check("built a born-digital fixture", false); exit(1)
    }
    let native = Flattener.nativeDPI(of: bp) ?? -1
    check("the logo really does imply an absurd resolution",
          native > 0 && native < 20, String(format: "%.1f DPI", native))
    check("rebuildDPI refuses it and falls back",
          Flattener.rebuildDPI(of: bp) == Flattener.fallbackRebuildDPI,
          "\(Flattener.rebuildDPI(of: bp))")

    // The consequence, end to end: the text must survive the rebuild.
    let rebuilt = dir.appendingPathComponent("rebuilt.pdf")
    _ = try? Flattener.flatten(born, to: rebuilt, mode: .auto)
    let read = observations(of: rebuilt).values.flatMap { $0 }
        .map(\.text).joined(separator: " ")
    check("the page's text survives the rebuild",
          read.contains("BORN") && read.contains("DIGITAL"),
          String(read.prefix(200)))
    resetPrefs()
}

// MARK: - The document outline survives, and the text layer is unharmed

// compose rebuilds pages through a CGContext, which copies page content and
// nothing else, so a digitised book's chapter outline did not reach the copy.
// CoreGraphics cannot write one, so it takes a PDFKit rewrite of the finished
// file — and that rewrite re-serialises the invisible text layer, which is the
// most delicate thing here. Both halves are checked: the outline arrives AND
// the text layer still extracts and still sits on the ink.

print("\nthe document outline survives OCR")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("outline")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let src = dir.appendingPathComponent("book.pdf")
    makeScannedPDF(at: src, lines: ["CHAPTER ONE OPENING", "the body text of it"])
    // Give it a two-level outline, as a repository would.
    guard let doc = PDFDocument(url: src), let page0 = doc.page(at: 0) else {
        check("built the outline fixture", false); exit(1)
    }
    let root = PDFOutline()
    let chapter = PDFOutline()
    chapter.label = "Chapter One"
    chapter.destination = PDFDestination(page: page0, at: CGPoint(x: 0, y: 700))
    let section = PDFOutline()
    section.label = "Section 1.1"
    section.destination = PDFDestination(page: page0, at: CGPoint(x: 0, y: 500))
    chapter.insertChild(section, at: 0)
    root.insertChild(chapter, at: 0)
    doc.outlineRoot = root
    doc.write(to: src)
    check("the fixture really has an outline",
          PDFDocument(url: src)?.outlineRoot?.numberOfChildren == 1)

    // Greyscale mode, so `canUseJBIG2` is false and the Flate route runs. That
    // is where the outline pass applies — see the JBIG2 check further down.
    let out = dir.appendingPathComponent("book.ocr.pdf")
    var outcome: Runner.Result.Outcome?
    var detail = ""
    OCRModel.makeSearchablePDF(
        file: src, output: out,
        rebuild: true, rebuildMode: .grayscale, password: nil,
        control: RunControl(), progress: { _, _ in },
        report: { o, m in outcome = o; detail = m })
    check("the run succeeds", outcome == .succeeded, detail)

    guard let result = PDFDocument(url: out) else {
        check("an output was published", false); exit(1)
    }
    let outRoot = result.outlineRoot
    check("the outline reaches the copy", (outRoot?.numberOfChildren ?? 0) == 1,
          "\(outRoot?.numberOfChildren ?? -1) top-level entries")
    check("…with its labels", outRoot?.child(at: 0)?.label == "Chapter One",
          outRoot?.child(at: 0)?.label ?? "nil")
    check("…and its nesting",
          outRoot?.child(at: 0)?.child(at: 0)?.label == "Section 1.1",
          outRoot?.child(at: 0)?.child(at: 0)?.label ?? "nil")
    check("…pointing at a real page in the copy",
          outRoot?.child(at: 0)?.destination?.page != nil)

    // The half that matters more: the rewrite must not have damaged the layer.
    let text = embeddedText(of: out)
    check("the text layer survives the outline rewrite",
          text.contains("CHAPTER ONE OPENING"), String(text.prefix(120)))
    if let rp = result.page(at: 0),
       let found = result.findString("OPENING", withOptions: [.caseInsensitive]).first {
        let b = found.bounds(for: rp)
        check("…and its runs still have real geometry",
              b.width > 5 && b.height > 2, "\(b)")
    } else {
        check("…and its runs still have real geometry", false, "run not locatable")
    }

    // The JBIG2 route gets the outline a different way: written into the
    // catalogue of the PDF `JBIG2.assemble` hand-writes, which `qpdf --overlay`
    // preserves because that file is the overlay *base*. Routing it through
    // PDFKit instead re-encodes every image stream and loses the compression
    // (measured: 374 KB with /JBIG2Decode becoming 467 KB without), so this
    // asserts both halves — the outline arrives AND the compression survives.
    if JBIG2.isAvailable {
        // Self-verifying census figure, as above (A11.7).
        let checksBeforeOutlineBlock = checks
        let jb = dir.appendingPathComponent("book-jbig2.ocr.pdf")
        var jbOutcome: Runner.Result.Outcome?
        OCRModel.makeSearchablePDF(
            file: src, output: jb,
            rebuild: true, rebuildMode: .auto, password: nil,
            control: RunControl(), progress: { _, _ in },
            report: { o, _ in jbOutcome = o })
        let bytes = (try? Data(contentsOf: jb)) ?? Data()
        let keptJBIG2 = bytes.firstRange(of: Array("/JBIG2Decode".utf8)) != nil
        check("the JBIG2 route still succeeds", jbOutcome == .succeeded)
        check("…and keeps its JBIG2 compression", keptJBIG2)
        // Hold the document. `PDFDocument(url:)?.outlineRoot` alone lets the
        // document deallocate immediately, and a PDFOutline does not own its
        // document — the tree then reads back as a root with no children and no
        // destinations, which looks exactly like a broken outline. This cost an
        // hour of chasing correct code.
        let jbDoc = PDFDocument(url: jb)
        let jbRoot = jbDoc?.outlineRoot
        check("…and carries the outline too, without a PDFKit rewrite",
              (jbRoot?.numberOfChildren ?? 0) == 1,
              "\(jbRoot?.numberOfChildren ?? -1) top-level entries")
        check("…with its labels and nesting intact",
              jbRoot?.child(at: 0)?.label == "Chapter One"
              && jbRoot?.child(at: 0)?.child(at: 0)?.label == "Section 1.1",
              "\(jbRoot?.child(at: 0)?.label ?? "nil") / "
              + "\(jbRoot?.child(at: 0)?.child(at: 0)?.label ?? "nil")")
        check("…pointing at a real page",
              jbRoot?.child(at: 0)?.destination?.page != nil)
        // And the text layer is still there — the whole point of the merge.
        check("…and the text layer is unharmed",
              embeddedText(of: jb).contains("CHAPTER ONE OPENING"),
              String(embeddedText(of: jb).prefix(100)))
        check("the skip census figure for the outline block is still right",
              checks - checksBeforeOutlineBlock + 1 == 7,
              "\(checks - checksBeforeOutlineBlock + 1) checks, census says 7")
    } else {
        skipBlock("the outline across the JBIG2 route", checks: 7,
                  because: "jbig2enc/qpdf not installed (\(JBIG2.installHint))")
    }

    // A source with no outline must publish exactly as before.
    let plain = dir.appendingPathComponent("plain.pdf")
    makeScannedPDF(at: plain, lines: ["NO OUTLINE HERE"])
    let plainOut = dir.appendingPathComponent("plain.ocr.pdf")
    var plainOutcome: Runner.Result.Outcome?
    OCRModel.makeSearchablePDF(
        file: plain, output: plainOut,
        rebuild: true, rebuildMode: .auto, password: nil,
        control: RunControl(), progress: { _, _ in },
        report: { o, _ in plainOutcome = o })
    check("a source with no outline still publishes normally",
          plainOutcome == .succeeded
          && embeddedText(of: plainOut).contains("NO OUTLINE"),
          String(embeddedText(of: plainOut).prefix(80)))
    resetPrefs()
}

// MARK: - Files cannot join a run that has already started

// start() freezes the batch, so anything added during a run is never enqueued —
// it just sits in the list while the summary reports "40 of 40 succeeded" above
// 43 rows, with no output on disk for three of them and nothing saying so.
//
// Gating only the Add… button left the two other ways in — the drop zone and
// files handed over by Finder — so the guard belongs here, where all three meet.

print("\nfiles added during a run")

do {
    resetPrefs()
    let m = MainActor.assumeIsolated { OCRModel() }
    let a = tmp.appendingPathComponent("join-a.pdf")
    let b = tmp.appendingPathComponent("join-b.pdf")
    makeScannedPDF(at: a, lines: ["FIRST"])
    makeScannedPDF(at: b, lines: ["SECOND"])

    MainActor.assumeIsolated {
        switch m.add([a]) {
        case .added(let ignored):
            check("files are accepted when nothing is running", ignored == 0)
        case .refusedRunInProgress:
            check("files are accepted when nothing is running", false, "refused while idle")
        }
        check("…and land in the list", m.files.count == 1, "\(m.files.count)")

        // Simulate a run in flight without launching one: the guard is on
        // isRunning, and this keeps the check fast and deterministic.
        m.isRunning = true
        var refused = false
        if case .refusedRunInProgress = m.add([b]) { refused = true }
        check("a file offered during a run is refused, not silently queued", refused)
        check("…and the list is unchanged, so the count cannot contradict the summary",
              m.files.count == 1, "\(m.files.count)")

        m.isRunning = false
        var acceptedAfter = false
        if case .added = m.add([b]) { acceptedAfter = true }
        check("…and it is accepted again once the run ends", acceptedAfter)
        check("…arriving in the list", m.files.count == 2, "\(m.files.count)")

        // U19. isRunning is not the moment the batch is frozen. C17 put an
        // asynchronous pre-flight between the click and run(), and start()
        // captures the file list before dispatching it — so for the whole of
        // "Checking…" the contents were decided while every control that edits
        // them was still live. Same defect, one state earlier.
        m.files = [a]
        m.isRunning = false
        m.isPreflighting = true

        check("the batch counts as committed during the pre-flight", m.isCommitted)
        var refusedDuringPreflight = false
        if case .refusedRunInProgress = m.add([b]) { refusedDuringPreflight = true }
        check("a file offered during the pre-flight is refused too",
              refusedDuringPreflight)
        check("…and the list is unchanged", m.files.count == 1, "\(m.files.count)")
        check("…and Start stays disabled", !m.canStart)

        m.isPreflighting = false
        check("…and the batch is editable again once the pre-flight ends",
              !m.isCommitted)

        // U21. Start must also be unavailable while a folder is still being
        // walked. isImporting was published by U20 for exactly this and nothing
        // read it, so the batch could be frozen with files still arriving.
        m.files = [a]
        m.isRunning = false
        m.isPreflighting = false
        m.besideOriginal = true
        check("Start is available with a settled list", m.canStart)
        m.importsInFlight = 1
        check("…and unavailable while an import is in flight", !m.canStart)
        m.importsInFlight = 0
        check("…and available again once it lands", m.canStart)
    }
    resetPrefs()
}

print("\npages far too big for a recogniser to refuse")

do {
    // This block was mostly `recogniserDPICeiling`: mac-ocr refused a page over
    // 200 megapixels, so the app worked out the highest DPI each document could
    // be rendered at and asked for that. R39 was the hole in that negotiation and
    // 1.10.1 fixed it.
    //
    // All of it is gone, because the limit was **mac-ocr's, not Vision's**.
    // Measured on the very fixture R39 was reproduced with — a 20x30 inch page
    // declaring 12000x18000, which mac-ocr refuses outright — Vision recognises
    // the 216-megapixel image without complaint. No ceiling to compute, nothing
    // to clamp, no flag to send.
    //
    // `Flattener.maximumPageMegapixels` still bounds what this app will *render*
    // (R24: an allocation that fails is a crash, not an error).
    resetPrefs()
    let dir = tmp.appendingPathComponent("bigsheet-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let sheet = dir.appendingPathComponent("sheet.pdf")
    var sbox = CGRect(x: 0, y: 0, width: 20 * 72, height: 30 * 72)
    if let c = CGContext(sheet as CFURL, mediaBox: &sbox, nil) {
        let px = 12_000, py = 18_000, rowBytes = (12_000 + 7) / 8
        let bits = [UInt8](repeating: 0xFF, count: rowBytes * py)
        if let provider = CGDataProvider(data: Data(bits) as CFData),
           let image = CGImage(width: px, height: py, bitsPerComponent: 1, bitsPerPixel: 1,
                               bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                               decode: nil, shouldInterpolate: false, intent: .defaultIntent) {
            let d = withUnsafeBytes(of: &sbox) { Data($0) } as CFData
            c.beginPDFPage([kCGPDFContextMediaBox as String: d] as CFDictionary)
            c.draw(image, in: sbox)
            c.endPDFPage()
        }
        c.closePDF()
    }
    if let page = PDFDocument(url: sheet)?.page(at: 0) {
        check("the fixture is the 216-megapixel sheet mac-ocr refused",
              (Flattener.nativeDPI(of: page) ?? 0) == 600,
              String(describing: Flattener.nativeDPI(of: page)))
        var settings = Prefs.Snapshot.current()
        settings.pdfDPIAuto = true
        if let image = Recogniser.render(page, settings: settings) {
            check("…and it renders past the old 200-megapixel limit",
                  Double(image.width) * Double(image.height) / 1_000_000 > 200,
                  "\(image.width)x\(image.height)")
            check("…and Vision recognises it rather than refusing it",
                  (try? Recogniser.recognise(image, settings: settings)) != nil)
        } else {
            check("the 216-megapixel sheet renders for recognition", false, "render was nil")
        }
    }
    resetPrefs()
}

print("\nthe revision we pin is the revision Vision uses")

do {
    // `Recogniser.revision` is pinned to 3 because that is what the corpus was
    // measured at, and the Extract Text JSON reports that constant in its
    // `requestRevision` field. Reporting what we *asked for* rather than what
    // happened would be a claim rather than evidence — so check that Vision
    // honours the pin instead of assuming it.
    resetPrefs()
    let page = tmp.appendingPathComponent("revision-\(UUID().uuidString).pdf")
    makeScannedPDF(at: page, lines: ["a line to recognise"])
    let settings = Prefs.Snapshot.current()
    guard let doc = Flattener.open(page, password: nil), let first = doc.page(at: 0),
          let image = Recogniser.render(first, settings: settings) else {
        check("the revision fixture renders", false); resetPrefs(); exit(0)
    }
    let request = Recogniser.makeRequest(settings)
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([request])
    let observed = (request.results as? [VNRecognizedTextObservation] ?? [])
        .map(\.requestRevision)
    check("the fixture recognised something, or there is no revision to read",
          !observed.isEmpty, "\(observed.count) observations")
    check("every observation reports the revision we pinned",
          observed.allSatisfy { $0 == Recogniser.revision },
          "saw \(Set(observed).sorted()), pinned \(Recogniser.revision)")
    resetPrefs()
}

print("\ncancelling recognition is a cancellation, not a short document")

do {
    // Returning the pages recognised so far would hand `compose` something that
    // looks like a finished document and publish a text layer missing its last
    // pages — invariant 1's shape, and invisible to a page count.
    resetPrefs()
    let dir = tmp.appendingPathComponent("cancel-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    // Three pages, so there is something left to cancel after the first.
    let multi = dir.appendingPathComponent("three.pdf")
    let single = dir.appendingPathComponent("one.pdf")
    makeScannedPDF(at: single, lines: ["a page of text to recognise"])
    if let src = PDFDocument(url: single), let p0 = src.page(at: 0) {
        let doc = PDFDocument()
        for i in 0..<3 { doc.insert(p0.copy() as! PDFPage, at: i) }
        doc.write(to: multi)
    }
    var seen = 0
    do {
        _ = try Recogniser.recogniseDocument(
            visible: multi, bitmaps: [], settings: .current(),
            isCancelled: { seen >= 1 },          // cancel after the first page
            onPage: { done, _ in seen = max(seen, done) })
        check("a cancelled recognition throws rather than returning a partial map", false,
              "it returned")
    } catch let error as Recogniser.Failure {
        check("a cancelled recognition throws rather than returning a partial map",
              error == .cancelled || "\(error)" == "cancelled", "\(error)")
    } catch {
        check("a cancelled recognition throws rather than returning a partial map",
              false, "\(error)")
    }
    resetPrefs()
}

print("\nrecognition from several threads at once agrees with itself")

do {
    // The batch runs up to eight files concurrently, so `handler.perform` is
    // called from eight threads. mac-ocr wraps Vision in an actor precisely so
    // that cannot happen, with a comment noting `VNImageRequestHandler` is not
    // Sendable — which is a Swift concurrency-checking fact and not necessarily a
    // thread-safety one. Either it is fine, or it is a corruption bug that a
    // single clean batch would never reveal.
    //
    // Measured rather than assumed: identical signatures, box coordinates
    // included, from 8 and 12 threads on two documents. This keeps a cheap
    // version of that in the suite, because the day it stops being true is the
    // day every batch quietly produces slightly wrong text layers.
    resetPrefs()
    let page = tmp.appendingPathComponent("concurrent-\(UUID().uuidString).pdf")
    makeScannedPDF(at: page, lines: ["concurrent recognition must agree",
                                     "with the serial answer exactly"])
    let settings = Prefs.Snapshot.current()
    guard let doc = Flattener.open(page, password: nil), let first = doc.page(at: 0),
          let image = Recogniser.render(first, settings: settings) else {
        check("the concurrency fixture renders", false)
        resetPrefs()
        exit(0)
    }
    func signature(_ o: [SearchableWriter.Observation]) -> String {
        o.map { "\($0.text)@\(String(format: "%.4f,%.4f", $0.boundingBox.x, $0.boundingBox.y))" }
            .joined(separator: "|")
    }
    let serial = signature((try? Recogniser.recognise(image, settings: settings)) ?? [])
    check("the fixture recognises at all, or the comparison is empty",
          !serial.isEmpty, "\(serial.count) chars")

    let threads = 6
    var answers = [String?](repeating: nil, count: threads)
    let lock = NSLock()
    let group = DispatchGroup()
    for i in 0..<threads {
        DispatchQueue.global().async(group: group) {
            let r = signature((try? Recogniser.recognise(image, settings: settings)) ?? [])
            lock.lock(); answers[i] = r; lock.unlock()
        }
    }
    _ = group.wait(timeout: .now() + 120)
    check("every concurrent answer is identical to the serial one",
          answers.allSatisfy { $0 == serial },
          "\(answers.filter { $0 != serial }.count) of \(threads) differed")
    resetPrefs()
}

print("\nevery recognition setting reaches the request")

do {
    // CONTRIBUTING 4d — enumerate, do not reason about pairs. The forty checks on
    // the mac-ocr argument list are gone with the argument list, but the property
    // they protected is the one `ocrAllPages` is named for: a setting the panel
    // offers that cannot affect anything. `Prefs.Snapshot` is walked with a
    // Mirror, and every field is either shown to change the request (or the
    // result) or listed here as deliberately not a recognition setting.
    resetPrefs()

    // Fields that shape the output but not the recogniser's request.
    let notRecognition: Set<String> = [
        "mode",             // which pipeline runs
        "textFormat",       // how Extract Text is written
        "besideOriginal",   // where the output goes
        "useJBIG2",         // compression
        "photoDetail",      // the MRC background factor
        "joinHyphenated",   // a text-layer transform, after recognition
        "preserveAnnotations",  // object surgery after every page is written
        "password",         // opens the document; never reaches the request
        "pdfDPIAuto",       // what to rasterise at when not rebuilding
        "pdfDPI",
        "confidence",       // applied to the observations, not by the request
    ]

    var base = Prefs.Snapshot.current()
    base.languages = ""
    base.customWords = ""
    base.minTextHeightOn = false
    base.fast = false
    base.languageCorrection = true

    /// Does changing this field change the request?
    let changes: [String: (inout Prefs.Snapshot) -> Void] = [
        "fast": { $0.fast = true },
        "languageCorrection": { $0.languageCorrection = false },
        "languages": { $0.languages = "de-DE" },
        "customWords": { $0.customWords = "Boltanski" },
        "minTextHeight": { $0.minTextHeightOn = true; $0.minTextHeight = 0.05 },
        "minTextHeightOn": { $0.minTextHeightOn = true; $0.minTextHeight = 0.05 },
    ]

    let fields = Mirror(reflecting: base).children.compactMap(\.label)
    check("the snapshot has fields to enumerate", fields.count >= 16, "\(fields.count)")
    let unaccounted = fields.filter { !notRecognition.contains($0) && changes[$0] == nil }
    check("every setting is either wired to the request or listed as not one",
          unaccounted.isEmpty, unaccounted.joined(separator: ", "))

    func describe(_ r: VNRecognizeTextRequest) -> String {
        "level=\(r.recognitionLevel.rawValue) correction=\(r.usesLanguageCorrection) "
        + "languages=\(r.recognitionLanguages.joined(separator: ",")) "
        + "detect=\(r.automaticallyDetectsLanguage) "
        + "words=\(r.customWords.joined(separator: ",")) "
        + "minHeight=\(r.minimumTextHeight) revision=\(r.revision)"
    }
    let baseline = describe(Recogniser.makeRequest(base))
    for (field, mutate) in changes.sorted(by: { $0.key < $1.key }) {
        var changed = base
        mutate(&changed)
        check("changing \(field) changes the request",
              describe(Recogniser.makeRequest(changed)) != baseline,
              describe(Recogniser.makeRequest(changed)))
    }

    // The revision is pinned rather than left to the OS, because every corpus
    // figure was measured at 3 and a newer default would silently change what
    // the baseline describes.
    check("the request is pinned to revision 3",
          Recogniser.makeRequest(base).revision == VNRecognizeTextRequestRevision3,
          "\(Recogniser.makeRequest(base).revision)")
    // And the detection flag is the one that is wrong when left alone.
    check("no language named means Vision is asked to detect one",
          Recogniser.makeRequest(base).automaticallyDetectsLanguage)
    var named = base; named.languages = "en-US"
    check("…and naming one turns detection off",
          !Recogniser.makeRequest(named).automaticallyDetectsLanguage)
    resetPrefs()
}

print("\nevery recognition setting reaches the helper")

do {
    // The sibling of the block above, and it exists for the same reason. R40
    // moved recognition into a helper process, so there are now two ways for a
    // setting the panel offers to fail to reach the engine: not being put on the
    // request, and not surviving the handover to the process that builds it.
    // `ocrAllPages` is what the first one looks like; this is the second.
    resetPrefs()
    var base = Prefs.Snapshot.current()
    base.languages = ""
    base.customWords = ""
    base.minTextHeightOn = false
    base.fast = false
    base.languageCorrection = true
    base.confidence = 0

    // Every field the request check enumerates, **plus confidence** — which is
    // deliberately listed there as "not a recognition setting" because it is
    // applied to the observations rather than by the request. That makes it
    // exactly the one a handover could drop without any request-level check
    // noticing, and a helper that dropped it would hand back text the user had
    // set a threshold to discard.
    let helperChanges: [String: (inout Prefs.Snapshot) -> Void] = [
        "fast": { $0.fast = true },
        "languageCorrection": { $0.languageCorrection = false },
        "languages": { $0.languages = "de-DE" },
        "customWords": { $0.customWords = "Boltanski" },
        "minTextHeight": { $0.minTextHeightOn = true; $0.minTextHeight = 0.05 },
        "minTextHeightOn": { $0.minTextHeightOn = true; $0.minTextHeight = 0.05 },
        "confidence": { $0.confidence = 0.4 },
    ]

    func describeRequest(_ r: VNRecognizeTextRequest) -> String {
        "level=\(r.recognitionLevel.rawValue) correction=\(r.usesLanguageCorrection) "
        + "languages=\(r.recognitionLanguages.joined(separator: ",")) "
        + "detect=\(r.automaticallyDetectsLanguage) "
        + "words=\(r.customWords.joined(separator: ",")) "
        + "minHeight=\(r.minimumTextHeight) revision=\(r.revision)"
    }

    let baseArguments = Recogniser.helperArguments(base)
    for (field, mutate) in helperChanges.sorted(by: { $0.key < $1.key }) {
        var changed = base
        mutate(&changed)
        check("changing \(field) changes the helper's arguments",
              Recogniser.helperArguments(changed) != baseArguments,
              Recogniser.helperArguments(changed).joined(separator: " "))

        // Changing them is not enough — the far side has to read back the same
        // engine. This compares the *request the helper would build*, which is
        // the thing the corpus baseline is a measurement of.
        guard let back = Recogniser.helperSettings(from: Recogniser.helperArguments(changed))
        else {
            check("\(field) survives the round trip through the arguments", false,
                  "the arguments did not parse")
            continue
        }
        check("\(field) survives the round trip through the arguments",
              describeRequest(Recogniser.makeRequest(back))
                  == describeRequest(Recogniser.makeRequest(changed))
                  && back.confidence == changed.confidence,
              describeRequest(Recogniser.makeRequest(back)) + " conf=\(back.confidence)")
    }

    // The two list fields carry whatever the user typed, so a value is allowed
    // to look like a flag. Pairwise parsing is what makes that safe, and this is
    // the check that keeps it pairwise.
    var awkward = base
    awkward.languages = "--fast"
    awkward.customWords = "--manifest --out"
    let parsedAwkward = Recogniser.helperSettings(from: Recogniser.helperArguments(awkward))
    check("a setting whose value looks like a flag survives",
          parsedAwkward?.languages == "--fast"
              && parsedAwkward?.customWords == "--manifest --out",
          "\(parsedAwkward?.languages ?? "nil") / \(parsedAwkward?.customWords ?? "nil")")

    // Malformed input returns nil rather than a half-filled settings object: the
    // helper then exits, and the app recognises the document itself. Guessing at
    // a missing field would mean recognising with settings nobody chose.
    check("an odd number of arguments is refused",
          Recogniser.helperSettings(from: ["--fast"]) == nil)
    check("a value where a flag should be is refused",
          Recogniser.helperSettings(from: ["--fast", "1", "oops", "1"]) == nil)
    check("a missing setting is refused",
          Recogniser.helperSettings(from: ["--fast", "1"]) == nil)
    check("a non-numeric confidence is refused",
          Recogniser.helperSettings(
            from: Recogniser.helperArguments(base).map { $0 == "0.0" ? "yes" : $0 }) == nil)
    check("a full argument list is accepted",
          Recogniser.helperSettings(from: Recogniser.helperArguments(base)) != nil)
    resetPrefs()
}

print("\na helper is only worth it when there is something to overlap with")

do {
    // The decision `start()` makes. Checked here rather than by driving a batch,
    // because as an inlined condition it was reachable only through the whole
    // model — and a decision nothing can reach is a decision nothing checks.
    check("a batch of several files at several at a time uses helpers",
          Recogniser.helperIsWorthIt(concurrency: 6, files: 12))
    check("two files at two at a time is already worth it",
          Recogniser.helperIsWorthIt(concurrency: 2, files: 2))
    // Both inverse rows (CONTRIBUTING 4d): the property must also switch *off*,
    // or "always yes" would satisfy the table.
    check("one file is not, however high the concurrency",
          !Recogniser.helperIsWorthIt(concurrency: 12, files: 1))
    check("…nor many files with the concurrency turned down to one",
          !Recogniser.helperIsWorthIt(concurrency: 1, files: 255))
    check("…nor an empty batch", !Recogniser.helperIsWorthIt(concurrency: 6, files: 0))
}

print("\nthe helper recognises exactly what the app would")

do {
    // The property the whole change rests on. R40's fix is only safe because the
    // helper compiles `Recogniser.recognise` — the app's own function — rather
    // than reimplementing it, and this is what says so out loud: the same
    // bitmaps, through the same entry point, both ways, compared field by field.
    // "Both routes agree" is the only evidence that the corpus figures measured
    // before this change still describe the pipeline after it.
    let dir = tmp.appendingPathComponent("r40-parity")
    try? FileManager.default.removeItem(at: dir)
    let pngs = dir.appendingPathComponent("pages")
    try? FileManager.default.createDirectory(at: pngs, withIntermediateDirectories: true)

    let source = dir.appendingPathComponent("scan.pdf")
    makeScannedPDF(at: source, lines: ["The helper and the app", "must agree exactly",
                                       "including digits 1234567890"])
    let rebuilt = dir.appendingPathComponent("rebuilt.pdf")
    let bitmaps = (try? Flattener.flatten(source, to: rebuilt, mode: .blackAndWhite,
                                          pngDirectory: pngs)) ?? []
    check("the parity fixture rebuilt", !bitmaps.isEmpty, "\(bitmaps.count)")

    let settings = Prefs.Snapshot.current()
    check("the suite was given a helper to test",
          Recogniser.helperPath() != nil,
          "VISIONOCR_HELPER is unset or does not point at a runnable file")

    var fellBack: [String] = []
    let viaHelper = try? Recogniser.recogniseDocument(
        visible: rebuilt, bitmaps: bitmaps, settings: settings, useHelper: true,
        onFallback: { fellBack.append($0) })
    // Without this the comparison below would pass by testing the in-process
    // path against itself — the shape of the duplicate-of-the-thing-under-test
    // that an earlier review round found agreeing with itself by construction.
    check("recognition went to the helper rather than falling back",
          fellBack.isEmpty, fellBack.joined(separator: "; "))

    let inProcess = try? Recogniser.recogniseDocument(
        visible: rebuilt, bitmaps: bitmaps, settings: settings, useHelper: false)

    check("both routes returned the same pages",
          viaHelper?.keys.sorted() == inProcess?.keys.sorted(),
          "\(viaHelper?.keys.sorted() ?? []) vs \(inProcess?.keys.sorted() ?? [])")
    check("the helper found something to compare", (viaHelper?[1]?.count ?? 0) > 0,
          "\(viaHelper?[1]?.count ?? 0) observations")

    var differences = 0, compared = 0
    for page in (inProcess ?? [:]).keys.sorted() {
        let mine = inProcess?[page] ?? [], theirs = viaHelper?[page] ?? []
        if mine.count != theirs.count { differences += 1; continue }
        for (a, b) in zip(mine, theirs) {
            compared += 1
            if a.text != b.text || a.confidence != b.confidence
                || a.boundingBox.x != b.boundingBox.x
                || a.boundingBox.y != b.boundingBox.y
                || a.boundingBox.width != b.boundingBox.width
                || a.boundingBox.height != b.boundingBox.height { differences += 1 }
        }
    }
    // Exactly equal, not nearly. The boxes are doubles that went through JSON,
    // and "close enough" here would be a licence for the text layer to drift.
    check("every observation matches to the last digit",
          differences == 0 && compared > 0, "\(differences) of \(compared) differ")

    // **And again down the colour route.** The check above only ever sees
    // 1-bit PNGs, and the other thing `flatten` emits is a three-channel JPEG —
    // 23 of the 232 corpus documents carry one. It is the same `loadImage` on
    // both sides, so this should hold by construction; "should hold by
    // construction" is what the corpus gate keeps disproving, and a decode that
    // differed on colour would move the text layer on exactly the pages whose
    // geometry is hardest to eyeball.
    let colourDir = dir.appendingPathComponent("colour")
    let colourPNGs = colourDir.appendingPathComponent("pages")
    try? FileManager.default.createDirectory(at: colourPNGs, withIntermediateDirectories: true)
    let colourSource = colourDir.appendingPathComponent("plate.pdf")
    var plateBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    if let c = CGContext(colourSource as CFURL, mediaBox: &plateBox, nil) {
        c.beginPDFPage(nil)
        c.setFillColor(CGColor(gray: 1, alpha: 1))
        c.fill(plateBox)
        let font = CTFontCreateWithName("Helvetica" as CFString, 22, nil)
        var y: CGFloat = 720
        for line in ["Parity across the colour route", "must hold as it does in 1-bit",
                     "digits 1234567890 and more words"] {
            let attributed = NSAttributedString(string: line, attributes: [
                .font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)])
            c.textPosition = CGPoint(x: 60, y: y)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), c)
            y -= 34
        }
        // Continuous tone, which is what sends a page down the picture path.
        for x in stride(from: 0, to: 552, by: 1) {
            for band in 0..<3 {
                let t = Double(x) / 552.0
                c.setFillColor(CGColor(red: t, green: 0.4 + 0.3 * Double(band),
                                       blue: 1 - t, alpha: 1))
                c.fill(CGRect(x: 30 + CGFloat(x), y: 120 + CGFloat(band) * 150,
                              width: 1, height: 148))
            }
        }
        c.endPDFPage(); c.closePDF()
    }
    let colourBitmaps = (try? Flattener.flatten(
        colourSource, to: colourDir.appendingPathComponent("rebuilt.pdf"),
        mode: .auto, pngDirectory: colourPNGs)) ?? []
    // Without this the comparison below would be a second bilevel run wearing a
    // different name.
    check("the colour fixture really routed to a JPEG page",
          colourBitmaps.contains { if case .jpeg = $0.content { return true }; return false },
          colourBitmaps.map { if case .jpeg = $0.content { return "jpeg" } else { return "bilevel" } }
            .joined(separator: ", "))

    var colourFellBack: [String] = []
    let colourHelper = try? Recogniser.recogniseDocument(
        visible: colourDir.appendingPathComponent("rebuilt.pdf"), bitmaps: colourBitmaps,
        settings: settings, useHelper: true, onFallback: { colourFellBack.append($0) })
    let colourInProcess = try? Recogniser.recogniseDocument(
        visible: colourDir.appendingPathComponent("rebuilt.pdf"), bitmaps: colourBitmaps,
        settings: settings, useHelper: false)
    check("the colour page went to the helper too", colourFellBack.isEmpty,
          colourFellBack.joined(separator: "; "))

    var colourDifferences = 0, colourCompared = 0
    for page in (colourInProcess ?? [:]).keys.sorted() {
        let mine = colourInProcess?[page] ?? [], theirs = colourHelper?[page] ?? []
        if mine.count != theirs.count { colourDifferences += 1; continue }
        for (a, b) in zip(mine, theirs) {
            colourCompared += 1
            if a.text != b.text || a.confidence != b.confidence
                || a.boundingBox.x != b.boundingBox.x
                || a.boundingBox.y != b.boundingBox.y
                || a.boundingBox.width != b.boundingBox.width
                || a.boundingBox.height != b.boundingBox.height { colourDifferences += 1 }
        }
    }
    check("a JPEG page decodes to the same observations both ways",
          colourDifferences == 0 && colourCompared > 0,
          "\(colourDifferences) of \(colourCompared) differ")
}

print("\na helper that misbehaves costs time, never content")

do {
    // CONTRIBUTING 4c — the error branches only exist if something makes them
    // run. Each of these is a helper that fails in a different way, and the
    // property under test is the same one every time: the app notices, and it
    // never accepts a short answer. R40's helper is deliberately not
    // authoritative about failure, so all of these must degrade to recognising
    // in-process rather than failing a file.
    let dir = tmp.appendingPathComponent("r40-faults")
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    func fakeHelper(_ name: String, _ body: String) -> String {
        let url = dir.appendingPathComponent("\(name).sh")
        // $2 is the manifest and $4 the output directory: the app always passes
        // --manifest and --out first, which is what makes these scripts short.
        try? Data("#!/bin/bash\nout=\"$4\"\n\(body)\n".utf8).write(to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: url.path)
        return url.path
    }

    // Two page images that exist, so nothing fails for the wrong reason.
    let pngs = dir.appendingPathComponent("pages")
    try? FileManager.default.createDirectory(at: pngs, withIntermediateDirectories: true)
    let source = dir.appendingPathComponent("scan.pdf")
    makeScannedPDF(at: source, lines: ["fault injection"])
    _ = try? Flattener.flatten(source, to: dir.appendingPathComponent("r.pdf"),
                               mode: .blackAndWhite, pngDirectory: pngs)
    let images = ((try? FileManager.default.contentsOfDirectory(
        at: pngs, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension == "png" }.sorted { $0.path < $1.path }
    let two = images.isEmpty ? [] : [images[0], images[0]]
    check("the fault-injection fixture has page images", !two.isEmpty, "\(images.count)")

    let settings = Prefs.Snapshot.current()
    func run(_ helper: String, stall: Double = 300,
             cancelled: Bool = false) -> Result<[Int: [SearchableWriter.Observation]], Error> {
        Result { try Recogniser.recogniseViaHelper(
            images: two, settings: settings, helper: helper, stallSeconds: stall,
            isCancelled: { cancelled }) }
    }

    func failed(_ result: Result<[Int: [SearchableWriter.Observation]], Error>) -> String? {
        if case .failure(let error) = result { return error.localizedDescription }
        return nil
    }

    // Each of these runs **once**, and the condition and the message come from
    // that one run. They used to call `run` twice — judging one process and
    // describing another, in two cases with different scripts — so an
    // intermittent case would have printed a message about a run that had not
    // failed (R42).
    let exited = run(fakeHelper("exits", "exit 7"))
    check("a helper that exits non-zero is refused",
          failed(exited)?.contains("code 7") == true, failed(exited) ?? "it succeeded")

    // Invariant 1, at the point the gap is visible. A short dictionary here
    // would compose as a document with untexted pages and publish.
    let short = run(fakeHelper("short", """
        printf '{"observations":[]}' > "$out/0.json"
        echo 0
        exit 0
        """))
    check("a helper that returns fewer pages than it was given is refused",
          failed(short)?.contains("page 2 of 2") == true, failed(short) ?? "it succeeded")

    let garbled = run(fakeHelper("garbled", """
        printf 'not json at all' > "$out/0.json"
        printf 'not json at all' > "$out/1.json"
        """))
    check("a helper whose output cannot be parsed is refused",
          failed(garbled)?.contains("page 1") == true, failed(garbled) ?? "it succeeded")

    // The bound is on silence, not on the run: a real book is minutes of work.
    let stalledStart = DispatchTime.now()
    let stalled = run(fakeHelper("stalls", "sleep 30"), stall: 1)
    let stalledSeconds = Double(DispatchTime.now().uptimeNanoseconds
                                - stalledStart.uptimeNanoseconds) / 1e9
    check("a helper that goes silent is given up on",
          failed(stalled)?.contains("stopped responding") == true,
          failed(stalled) ?? "it succeeded")
    check("…and is not waited out", stalledSeconds < 15, "\(stalledSeconds)s")

    // Noise on stdout moves a progress bar wrongly and nothing else. This is the
    // property that separates this protocol from mac-ocr's, where the page count
    // came from counting streamed lines and a garbled one lost a page.
    let noisy = run(fakeHelper("noisy", """
        echo "starting up, which is not a page number"
        printf '{"observations":[]}' > "$out/0.json"
        echo 0
        echo "-1"
        echo "9999"
        printf '{"observations":[]}' > "$out/1.json"
        echo 1
        """))
    check("junk on the helper's stdout does not lose a page",
          (try? noisy.get())?.keys.sorted() == [1, 2],
          "\((try? noisy.get())?.keys.sorted() ?? [])")

    // Cancelling must not be read as a broken helper: falling back would send
    // the whole document round again in-process, which is the opposite of what
    // the user asked for.
    let cancelled = run(fakeHelper("fine", """
        printf '{"observations":[]}' > "$out/0.json"
        printf '{"observations":[]}' > "$out/1.json"
        """), cancelled: true)
    check("cancelling throws a cancellation, not a helper failure",
          { if case .failure(let e) = cancelled { return e as? Recogniser.Failure == .cancelled }
            return false }(),
          failed(cancelled) ?? "it succeeded")

    // U2. A child the app forgets is a child that outlives a quit.
    let control = RunControl()
    var seen = 0
    _ = try? control.adopting { register in
        _ = try Recogniser.recogniseViaHelper(
            images: two, settings: settings, helper: fakeHelper("adopted", """
                printf '{"observations":[]}' > "$out/0.json"
                printf '{"observations":[]}' > "$out/1.json"
                """),
            register: { process in seen += 1; register(process) })
    }
    check("the helper is adopted so a quit can stop it", seen == 1, "\(seen)")
    check("…and released again, so a batch does not accumulate them",
          control.adoptedCount == 0, "\(control.adoptedCount)")

    // And the whole point: a broken helper is slower, not fatal. Same call the
    // pipeline makes, with the override pointed at a helper that always fails.
    let saved = ProcessInfo.processInfo.environment["VISIONOCR_HELPER"]
    setenv("VISIONOCR_HELPER", fakeHelper("always-fails", "exit 9"), 1)
    check("a broken helper is found and used", Recogniser.helperPath() != nil)
    var told: [String] = []
    let recovered = try? Recogniser.recogniseDocument(
        visible: dir.appendingPathComponent("r.pdf"),
        bitmaps: (try? Flattener.flatten(source, to: dir.appendingPathComponent("r2.pdf"),
                                         mode: .blackAndWhite, pngDirectory: pngs)) ?? [],
        settings: settings, useHelper: true, onFallback: { told.append($0) })
    check("a document whose helper fails is still recognised",
          (recovered?[1]?.isEmpty == false), "\(recovered?[1]?.count ?? -1) observations")
    check("…and the fallback says so rather than going quiet",
          told.count == 1 && told[0].contains("code 9"), told.joined(separator: "; "))

    setenv("VISIONOCR_HELPER", "/nonexistent/visionocr-recognise", 1)
    check("an override that names nothing runnable finds no helper",
          Recogniser.helperPath() == nil)
    if let saved { setenv("VISIONOCR_HELPER", saved, 1) } else { unsetenv("VISIONOCR_HELPER") }
    check("the suite's own helper is back", Recogniser.helperPath() != nil)

    // MARK: A13.1 — a NUL in a settings field must not abort the app

    // `Process.arguments` goes through `fileSystemRepresentation`, which raises
    // NSInvalidArgumentException for a string containing U+0000. An Objective-C
    // exception is not a Swift error, so the do/catch around `process.run()` does
    // not catch it: SIGABRT, exit 134, the whole app gone — and `report` is never
    // called, so "the report callback is called exactly once per file" breaks too.
    //
    // The asymmetry is what makes it worth a guard: the same snapshot recognises
    // perfectly in-process, and `useHelper` is `helperIsWorthIt`, so a one-file
    // batch works and a two-file batch kills the app. It persists, because
    // UserDefaults round-trips the NUL.
    //
    // **Where the NUL sits decides which of two defects you get**, measured with a
    // four-case probe against the real `Process.arguments` rather than reasoned
    // about (the review recorded only the first):
    //
    //     "en-US\0"        ran, exit 0     <- silently truncated to "en-US"
    //     "\0"             ran, exit 0     <- silently became an empty argument
    //     "Bolt\0Latour"   exit 134        <- uncaught NSException, SIGABRT
    //     "\0en-US"        exit 134        <- likewise
    //
    // So a NUL raises iff something follows it, and a NUL in the final position
    // instead changes the value the user asked for without saying so. Both are
    // refused here: one aborts the app, and the other is a languages list quietly
    // not being the one in the text field.
    //
    // Two of these cases run in-process against the real API, so with the guard
    // removed this block does not merely go red — the embedded cases take the suite
    // down with SIGABRT, which is what the missing guard actually costs. The
    // mutation log for `A13.1-nul-in-settings` shows both halves: one FAIL line for
    // a truncating case, then `exit=134`.
    for (field, hostile) in [("languages", "en-US\u{0}"),
                             ("languages", "\u{0}en-US"),
                             ("languages", "en\u{0}US"),
                             ("customWords", "Boltanski\u{0}Latour"),
                             ("customWords", "Latour\u{0}")] {
        var poisoned = settings
        if field == "languages" { poisoned.languages = hostile }
        else { poisoned.customWords = hostile }
        let where_ = hostile.hasSuffix("\u{0}") ? "at the end"
            : hostile.hasPrefix("\u{0}") ? "at the start" : "in the middle"
        let result = Result {
            try Recogniser.recogniseViaHelper(
                images: two, settings: poisoned,
                helper: fakeHelper("nul-\(field)-\(hostile.utf8.count)-\(where_.count)", """
                    printf '{"observations":[]}' > "$out/0.json"
                    printf '{"observations":[]}' > "$out/1.json"
                    """))
        }
        check("a NUL \(where_) of \(field) is refused before the process is launched",
              failed(result)?.contains("NUL") == true,
              failed(result) ?? "it succeeded, so the NUL reached Process.arguments")
    }
    // The inverse row: every other awkward character still goes through, because a
    // guard that refused them would turn a crash into a permanent fallback to the
    // slow path. Fuzzing found only NUL aborts; these all launch.
    for (name, value) in [("a bare CR", "en-US\r"), ("U+0085", "en-US\u{85}"),
                          ("U+2028", "en-US\u{2028}"), ("an RTL override", "en-US\u{202E}"),
                          ("ZWJ emoji", "en-US\u{1F469}\u{200D}\u{1F4BB}")] {
        var odd = settings
        odd.languages = value
        let result = Result {
            try Recogniser.recogniseViaHelper(
                images: two, settings: odd,
                helper: fakeHelper("odd-\(value.hashValue.magnitude)", """
                    printf '{"observations":[]}' > "$out/0.json"
                    printf '{"observations":[]}' > "$out/1.json"
                    """))
        }
        check("…while \(name) in a languages list still reaches the helper",
              failed(result) == nil, failed(result) ?? "")
    }

    // MARK: A13.3 — the newline guard has to mean every newline

    // A path *ending* in CR passed the old `contains("\n")` check, and in the joined
    // manifest that CR merges with the separator into one Swift Character ("\r\n"),
    // so the helper's `split(separator: "\n")` does not split there: 3 paths sent,
    // 2 lines parsed. No content was lost — the merged line names no file, the
    // helper exits 4, the app falls back — but the *count* check saved it, not this
    // guard, and the guard exists for the future in which a page image is named by
    // the user.
    if let first = two.first {
        for (name, suffix) in [("a newline", "\n"), ("a carriage return", "\r"),
                               ("a CRLF", "\r\n"), ("U+2028", "\u{2028}")] {
            let hostilePath = URL(fileURLWithPath: first.path + suffix)
            let result = Result {
                try Recogniser.recogniseViaHelper(
                    images: [first, hostilePath], settings: settings,
                    helper: fakeHelper("crlf-\(suffix.hashValue.magnitude)", """
                        printf '{"observations":[]}' > "$out/0.json"
                        printf '{"observations":[]}' > "$out/1.json"
                        """))
            }
            check("a page path containing \(name) is refused",
                  failed(result)?.contains("newline") == true,
                  failed(result) ?? "it succeeded")
        }
    }
}

print("\nthe engine assumptions two declined features rest on")

// Labelled so the fixture guard below can give up on *this block* rather than on
// the process. It called `exit()` first, which would have ended the whole suite
// at this point — skipping every later check and the final summary with it, and
// reporting a green run over a few hundred checks that never executed (R47).
assumptions: do {
    // **These do not test this app. They test Vision**, and they exist because
    // two user-visible qualities of this product are the engine's rather than
    // this codebase's, and nothing else here would notice if either stopped
    // holding:
    //
    //  - **Reading order.** `SearchableWriter.compose` draws observations in the
    //    order Vision returns them and never sorts. Multi-column pages come out
    //    readable because Vision puts them that way. `FEATURES.md` item 3 —
    //    columns and reading order — was declined on exactly this, measured over
    //    54 corpus pages at a median interleaving of 1.0.
    //  - **Skew tolerance.** Recognition is flat across ±3° and the reported
    //    quads tilt with the page. `FEATURES.md` item 2 — deskew — was declined
    //    twice on exactly this, the second time after building the thing and
    //    measuring it losing text.
    //
    // Both were measured once, in a session, and used to refuse work. Neither was
    // *held*. A macOS update that changed Vision's line grouping would degrade
    // both silently, and the only place it would surface is the corpus gate, as a
    // character-count drift indistinguishable from the 23 characters that moved
    // in the 1.11.0 run and could not be localised (R46).
    //
    // **If one of these fails, this app is probably not broken.** An assumption
    // about the recogniser stopped holding, and the two declined features should
    // be re-opened and re-measured with `Tools/score-reading-order.swift` and
    // `Tools/score-skew.swift`. Reading it as a defect in `SearchableWriter` is
    // R21's shape and the most expensive mistake this register records.
    let dir = tmp.appendingPathComponent("engine-assumptions")
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let left = ["The first column begins here", "and carries several lines of",
                "ordinary prose so that the",
                "recogniser has a real block of", "text to group rather than a",
                "handful of stray words on an",
                "otherwise empty sheet of paper", "which it would read quite",
                "differently and teach us less."]
    let right = ["The second column sits beside", "the first across a wide gutter",
                 "and says something different",
                 "so that the two can never be", "confused for one another when",
                 "the order they arrive in is",
                 "what the checking code counts", "before deciding whether this",
                 "page was read down or across."]

    /// The two-column fixture, rasterised once at `degrees` straight from the
    /// vector content — one resampling however it is turned, so a skewed
    /// rendering is not also a blurrier one. That conflation is what made the
    /// first deskew measurement report a loss that was its own doing.
    func render(degrees: Double) -> CGImage? {
        let pageBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdf = dir.appendingPathComponent("columns.pdf")
        var box = pageBox
        guard let c = CGContext(pdf as CFURL, mediaBox: &box, nil) else { return nil }
        c.beginPDFPage(nil)
        c.setFillColor(CGColor(gray: 1, alpha: 1))
        c.fill(pageBox)
        let font = CTFontCreateWithName("Helvetica" as CFString, 15, nil)
        for (column, lines) in [(CGFloat(60), left), (CGFloat(332), right)] {
            var y: CGFloat = 700
            for line in lines {
                let attributed = NSAttributedString(string: line, attributes: [
                    .font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)])
                c.textPosition = CGPoint(x: column, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(attributed), c)
                y -= 26
            }
        }
        c.endPDFPage(); c.closePDF()

        guard let page = PDFDocument(url: pdf)?.page(at: 0) else { return nil }
        let scale = 200.0 / 72.0
        let w = pageBox.width * scale, h = pageBox.height * scale
        let radians = degrees * .pi / 180
        let wide = abs(w * cos(radians)) + abs(h * sin(radians))
        let high = abs(w * sin(radians)) + abs(h * cos(radians))
        let W = Int(wide.rounded()), H = Int(high.rounded())
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: W, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.translateBy(x: wide / 2, y: high / 2)
        ctx.rotate(by: radians)
        ctx.translateBy(x: -w / 2, y: -h / 2)
        ctx.scaleBy(x: scale, y: scale)
        guard let cgPage = page.pageRef else { return nil }
        ctx.concatenate(cgPage.getDrawingTransform(
            .mediaBox, rect: CGRect(origin: .zero, size: pageBox.size),
            rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(cgPage)
        return ctx.makeImage()
    }

    var plain = Prefs.Snapshot.current()
    plain.languages = ""; plain.customWords = ""; plain.minTextHeightOn = false
    plain.fast = false; plain.languageCorrection = true; plain.confidence = 0

    guard let straight = render(degrees: 0),
          let observations = try? Recogniser.recognise(straight, settings: plain)
    else {
        check("the two-column fixture recognised", false, "it did not")
        break assumptions
    }

    // Not vacuous: without this the ordering checks below pass over an empty or
    // near-empty page, which is the shape of the duplicate-of-the-thing-under-test
    // an earlier review round found agreeing with itself by construction.
    check("the two-column fixture produced enough lines to order",
          observations.count >= 12, "\(observations.count) observations")

    // The gutter runs from x=280 to x=332 of 612 — 8.5% of the page, far wider
    // than any word space.
    let gutterLow = 280.0 / 612.0, gutterHigh = 332.0 / 612.0
    var lastLeft = -1, firstRight = Int.max, crossing = 0
    for (position, o) in observations.enumerated() {
        let l = o.boundingBox.x, r = o.boundingBox.x + o.boundingBox.width
        if l < gutterLow && r > gutterHigh { crossing += 1; continue }
        if r <= gutterHigh { lastLeft = max(lastLeft, position) }
        if l >= gutterLow { firstRight = min(firstRight, position) }
    }

    // The property `compose` inherits whole, since it never sorts.
    check("ENGINE ASSUMPTION: Vision returns the left column before the right",
          lastLeft >= 0 && firstRight < Int.max && lastLeft < firstRight,
          "last left at \(lastLeft), first right at "
            + (firstRight == Int.max ? "none" : "\(firstRight)")
            + " — if this fails, re-open FEATURES.md item 3; the app did not change")
    check("ENGINE ASSUMPTION: no line is welded across the gutter",
          crossing == 0,
          "\(crossing) observation(s) span both columns — reordering could not "
            + "repair this, the halves are already one string")

    // Skew. A generous band on purpose: Vision's line grouping genuinely flips
    // between interpretations, so a real page measured +2.0° at −2.73% while
    // +3.0° came back +0.08%. A tight bound here would be flaky, and a flaky
    // check in this position is worse than none at all.
    let straightCharacters = observations.reduce(0) { $0 + $1.text.count }
    check("the fixture recovered enough text to compare", straightCharacters > 200,
          "\(straightCharacters) characters")
    // Vision directly, not through `Recogniser.recognise`, for the one reason
    // that justifies bypassing the app's own function: the property under test is
    // the *quadrilateral*, and `recognise` deliberately throws it away — it
    // reduces each observation to an axis-aligned box because that is what the
    // text layer places. The request is still `Recogniser.makeRequest`, so this
    // asks Vision exactly what the app asks it.
    if let tilted = render(degrees: 2.0) {
        let request = Recogniser.makeRequest(plain)
        let handler = VNImageRequestHandler(cgImage: tilted, orientation: .up, options: [:])
        try? handler.perform([request])
        let raw = (request.results ?? []).compactMap { $0 as? VNRecognizedTextObservation }
        let skewedCharacters = raw.reduce(0) { $0 + ($1.topCandidates(1).first?.string.count ?? 0) }

        check("ENGINE ASSUMPTION: a 2° page reads about as well as a straight one",
              Double(skewedCharacters) >= Double(straightCharacters) * 0.8,
              "\(skewedCharacters) against \(straightCharacters) — if this fails, "
                + "re-open FEATURES.md item 2; deskew was declined because this held")

        // The sharper half, and the one the refusal actually rests on: Vision is
        // not *tolerating* the tilt, it is reporting it. The corners come back
        // rotated with the page, which is why a deskew step has nothing left to
        // win and can only add a resampling.
        let aspect = Double(tilted.width) / Double(tilted.height)
        var angles: [Double] = []
        for o in raw {
            let dx = (Double(o.bottomRight.x) - Double(o.bottomLeft.x)) * aspect
            let dy = Double(o.bottomRight.y) - Double(o.bottomLeft.y)
            if dx != 0 || dy != 0 { angles.append(atan2(dy, dx) * 180 / .pi) }
        }
        let sorted = angles.sorted()
        let median = sorted.isEmpty ? Double.nan : sorted[sorted.count / 2]
        check("ENGINE ASSUMPTION: the reported quads tilt with the page",
              abs(median - 2.0) <= 0.75,
              "median quad angle \(String(format: "%.2f", median))° for a 2.0° page "
                + "— if this fails, re-open FEATURES.md item 2")
    } else {
        check("the skewed fixture rendered", false, "it did not")
    }
}

print("\na photograph that says it is sideways is read as sideways")

do {
    // Recognition honours EXIF orientation. In the searchable pipeline this
    // cannot arise — those bitmaps are CGImages this app drew — but Extract Text
    // takes image files, and `CGImageSourceCreateImageAtIndex` hands back the
    // stored pixels with the flag unapplied.
    //
    // Vision reads rotated text either way, so the *strings* survive and no
    // character count can see the fault. What breaks is the geometry: the boxes
    // come back in the stored frame. So this checks the boxes, not the text.
    //
    // The fixture defeated two instruments before it worked. `sips -g
    // orientation` and `mdls` both report nothing for a file that plainly
    // carries the tag — which read as "the flag would not stick" and nearly
    // closed the question as untestable. `CGImageSourceCopyPropertiesAtIndex`
    // sees it perfectly.
    resetPrefs()
    let dir = tmp.appendingPathComponent("exif-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // Text drawn sideways, so the stored pixels need a quarter turn to read.
    let w = 900, h = 1200
    let upright = dir.appendingPathComponent("sideways.jpg")
    if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                  bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false,
                                  isPlanar: false, colorSpaceName: .deviceWhite,
                                  bytesPerRow: w, bitsPerPixel: 8),
       let ctx = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        let t = NSAffineTransform()
        t.translateX(by: CGFloat(w), yBy: 0)
        t.rotate(byDegrees: 90)
        t.concat()
        ("ORIENTATION" as NSString).draw(
            at: NSPoint(x: 120, y: 300),
            withAttributes: [.font: NSFont.systemFont(ofSize: 72),
                             .foregroundColor: NSColor.black])
        NSGraphicsContext.current?.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .jpeg, properties: [:])?.write(to: upright)
    }

    // Stamp orientation 6 — "rotate 90° clockwise to display" — the way a phone
    // camera does.
    let flagged = dir.appendingPathComponent("flagged.jpg")
    if let source = CGImageSourceCreateWithURL(upright as CFURL, nil),
       let type = CGImageSourceGetType(source),
       let dest = CGImageDestinationCreateWithURL(flagged as CFURL, type, 1, nil) {
        var props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        props[kCGImagePropertyOrientation] = 6
        CGImageDestinationAddImageFromSource(dest, source, 0, props as CFDictionary)
        _ = CGImageDestinationFinalize(dest)
    }

    guard let source = CGImageSourceCreateWithURL(flagged as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        check("the orientation fixture was written", false)
        resetPrefs()
        exit(0)
    }
    check("the fixture really carries an orientation flag, or nothing below means anything",
          Recogniser.exifOrientation(of: source) == .right,
          "\(Recogniser.exifOrientation(of: source).rawValue)")

    let settings = Prefs.Snapshot.current()
    let ignored = (try? Recogniser.recognise(image, orientation: .up, settings: settings)) ?? []
    let honoured = (try? Recogniser.recognise(image, orientation: .right,
                                              settings: settings)) ?? []
    check("Vision finds the text whichever way it is told to read it",
          !ignored.isEmpty && !honoured.isEmpty,
          "ignored \(ignored.count), honoured \(honoured.count)")
    // A line of text is wider than it is tall once the page is the right way up.
    // Ignoring the flag leaves it in the stored frame, where it is the reverse.
    if let a = ignored.first, let b = honoured.first {
        check("ignoring the flag leaves the line standing on end",
              a.boundingBox.height > a.boundingBox.width,
              String(format: "%.3f x %.3f", a.boundingBox.width, a.boundingBox.height))
        check("…and honouring it lays the line down",
              b.boundingBox.width > b.boundingBox.height,
              String(format: "%.3f x %.3f", b.boundingBox.width, b.boundingBox.height))
    }
    resetPrefs()
}

print("\nevery control VoiceOver cannot name from its own label has one")

do {
    // The question "are the controls named for VoiceOver" sat open from
    // 2026-08-09, and three different runtime attribute reads gave three
    // different answers — AppleScript's `description` returns the *role*,
    // `AXDescription` is absent on toggles, and `AXAttributedDescription` came
    // back while the probe was visibly failing to advance focus. TODO.md's
    // conclusion was to distrust a scripted read of the interface.
    //
    // The source is not a scripted read of the interface. A control either
    // carries a name or it does not, and two constructs are known to leave one
    // without: `labelsHidden()`, which hides the label from VoiceOver as well as
    // from the eye, and a `Button` whose label is a bare `Image(systemName:)`,
    // from which SwiftUI derives nothing. Both are found by reading the file.
    //
    // What this does NOT establish is how any of it *sounds*. It establishes
    // that no control is anonymous, which is the part that was in doubt.
    // Each control owns the lines from where it is introduced to where the next
    // one is, and its modifiers are looked for only in there. A fixed window
    // either way does not work: the first version used plus or minus eight
    // lines, and in a stack of two pickers three lines apart the unlabelled one
    // saw its neighbour's `.accessibilityLabel` and was scored as named. The
    // self-test below caught that; on the real files it would have been a
    // silently clean result.
    // Shared by both scanners below. It was local to the first one, and a second
    // copy in the second would be free to drift: a starter added to one list and
    // not the other silently narrows one scan while the other still looks
    // thorough.
    let starters = ["Picker(", "Toggle(", "Button(", "Button {", "Slider(",
                    "Stepper(", "TextField(", "Menu(", "SecureField("]

    func controlsMissingNames(_ path: String) -> (missing: [String], labelled: Int) {
        let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let lines = source.components(separatedBy: "\n")
        var starts: [Int] = []
        for (i, line) in lines.enumerated() where starters.contains(where: line.contains) {
            starts.append(i)
        }
        var missing: [String] = []
        var labelled = 0
        for (n, start) in starts.enumerated() {
            let end = n + 1 < starts.count ? starts[n + 1] : lines.count
            let chunk = Array(lines[start..<end])
            let text = chunk.joined(separator: "\n")
            // The two constructs that leave a control with no name of its own.
            // `Label("Settings", systemImage:)` names itself and is not one of
            // them — but the test for it has to ignore `.accessibilityLabel(`,
            // which also contains "Label(", or every *correctly named* icon
            // button is excluded from the scan and the result looks clean
            // because nothing was examined. The "has controls of this shape"
            // check below is what caught that.
            let withoutA11y = text.replacingOccurrences(of: ".accessibilityLabel(",
                                                        with: ".␣(")
            let hidesLabel = text.contains(".labelsHidden()")
            let iconOnly = text.contains("label:") && text.contains("Image(systemName:")
                && !withoutA11y.contains("Label(")
            guard hidesLabel || iconOnly else { continue }
            if text.contains(".accessibilityLabel(") || text.contains(".accessibilityHidden(true)") {
                labelled += 1
            } else {
                missing.append("\((path as NSString).lastPathComponent):\(start + 1) "
                               + lines[start].trimmingCharacters(in: .whitespaces))
            }
        }
        return (missing, labelled)
    }

    // The scanner has to be shown to work before its silence means anything.
    // A scanner that matched nothing would report a perfectly clean interface.
    let synthetic = tmp.appendingPathComponent("synthetic-view-\(UUID().uuidString).swift")
    try? """
    Picker("", selection: $a) { Text("x") }
        .labelsHidden()
        .accessibilityLabel("Named picker")
    Picker("", selection: $b) { Text("y") }
        .labelsHidden()
    """.write(to: synthetic, atomically: true, encoding: .utf8)
    let probe = controlsMissingNames(synthetic.path)
    check("the scanner sees a labelled hidden-label control as labelled",
          probe.labelled == 1, "\(probe.labelled)")
    check("…and an unlabelled one as missing",
          probe.missing.count == 1, probe.missing.joined(separator: " | "))
    try? FileManager.default.removeItem(at: synthetic)

    for file in ["Sources/ContentView.swift", "Sources/SettingsView.swift"] {
        let r = controlsMissingNames(file)
        check("\((file as NSString).lastPathComponent) has controls of this shape to check",
              r.labelled + r.missing.count >= 3,
              "\(r.labelled + r.missing.count) found")
        check("…and every one of them is named",
              r.missing.isEmpty, r.missing.joined(separator: " | "))
    }

    // U29 · and no two of them carry the *same* name.
    //
    // The scanner above asserts that every control of the two anonymous shapes
    // carries a name. Nothing asserted that a name appears once, and that is the
    // shape a paste error takes: the entire updates block was in SettingsView
    // twice — 36 lines for 36, comment and all — and survived because both
    // copies bound the same state, so nothing misbehaved. A settings panel is
    // exactly where a duplicated control hides, because the duplicate looks like
    // a control that belongs there.
    //
    // The name is the first string literal on the line that introduces the
    // control, or the `.accessibilityLabel` of one that has no visible label.
    func firstStringLiteral(in text: String) -> String? {
        guard let open = text.firstIndex(of: "\"") else { return nil }
        var out = ""
        var i = text.index(after: open)
        while i < text.endIndex {
            let c = text[i]
            if c == "\\" {
                // Skip the escaped character rather than letting a \" end the
                // literal early.
                i = text.index(after: i)
                if i < text.endIndex { out.append(text[i]); i = text.index(after: i) }
                continue
            }
            if c == "\"" { return out }
            out.append(c)
            i = text.index(after: i)
        }
        return nil
    }

    func duplicateControlNames(_ path: String) -> (dupes: [String], named: Int) {
        let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let lines = source.components(separatedBy: "\n")
        var starts: [Int] = []
        for (i, line) in lines.enumerated() where starters.contains(where: line.contains) {
            starts.append(i)
        }
        var seen: [String: [Int]] = [:]
        for (n, start) in starts.enumerated() {
            let end = n + 1 < starts.count ? starts[n + 1] : lines.count
            let chunk = lines[start..<end].joined(separator: "\n")
            // An empty literal is a deliberately label-less control — the shape
            // the scanner above covers — so it is not a name and cannot collide.
            var name = firstStringLiteral(in: lines[start])
            if name?.isEmpty ?? true,
               let marker = chunk.range(of: ".accessibilityLabel(") {
                name = firstStringLiteral(in: String(chunk[marker.upperBound...]))
            }
            guard let name, !name.isEmpty else { continue }
            seen[name, default: []].append(start + 1)
        }
        let dupes = seen.filter { $0.value.count > 1 }
            .map { "\($0.key) at line\($0.value.count == 1 ? "" : "s") "
                   + $0.value.map(String.init).joined(separator: ", ") }
            .sorted()
        return (dupes, seen.count)
    }

    // Shown to bite before its silence is allowed to mean anything — the same
    // discipline the scanner above needed, and for the same reason.
    let twinned = tmp.appendingPathComponent("twinned-view-\(UUID().uuidString).swift")
    try? """
    Toggle("Check for new versions", isOn: $a)
    Button("Check Now") { }
    Toggle("Check for new versions", isOn: $a)
    Button("Something else") { }
    """.write(to: twinned, atomically: true, encoding: .utf8)
    let twins = duplicateControlNames(twinned.path)
    check("the duplicate-name scanner sees a name used twice",
          twins.dupes.count == 1 && twins.dupes[0].contains("Check for new versions"),
          twins.dupes.joined(separator: " | "))
    check("…and does not report the names used once",
          twins.named == 3, "\(twins.named) distinct names")
    try? FileManager.default.removeItem(at: twinned)

    for file in ["Sources/ContentView.swift", "Sources/SettingsView.swift"] {
        let d = duplicateControlNames(file)
        check("\((file as NSString).lastPathComponent) has named controls to check",
              d.named >= 3, "\(d.named) named")
        check("…and no two of them share a name",
              d.dupes.isEmpty, d.dupes.joined(separator: " | "))
    }
    resetPrefs()
}

print("\ntelling a new version from an old one")

do {
    // The classic way an updater goes quiet is string comparison: "1.10.0" is
    // newer than "1.9.0" and sorts before it alphabetically, so the check stops
    // working at exactly the release where it starts mattering.
    check("a later patch is newer", Updater.isNewer("1.5.2", than: "1.5.1"))
    check("a later minor is newer", Updater.isNewer("1.6.0", than: "1.5.9"))
    check("a later major is newer", Updater.isNewer("2.0.0", than: "1.99.99"))
    check("1.10.0 is newer than 1.9.0, which string order gets wrong",
          Updater.isNewer("1.10.0", than: "1.9.0"))
    check("the same version is not newer", !Updater.isNewer("1.5.1", than: "1.5.1"))
    check("an older version is not newer", !Updater.isNewer("1.5.0", than: "1.5.1"))
    check("missing components count as zero", !Updater.isNewer("1.5", than: "1.5.0")
              && !Updater.isNewer("1.5.0", than: "1.5"))
    check("a longer but equal version is not newer", !Updater.isNewer("1.5.0.0", than: "1.5"))

    // Parsing. A half-understood response must never become "an update exists".
    let good = """
    {"tag_name":"v1.9.0","html_url":"https://example.com/r/1.9.0","body":"notes","draft":false,"prerelease":false}
    """.data(using: .utf8)!
    let parsed = Updater.release(from: good)
    check("a well-formed release parses", parsed?.version == "1.9.0", String(describing: parsed))
    check("…with the v stripped and the page kept",
          parsed?.url.absoluteString == "https://example.com/r/1.9.0")

    check("a draft is not an offer", Updater.release(from: """
    {"tag_name":"v2.0.0","html_url":"https://example.com/x","draft":true}
    """.data(using: .utf8)!) == nil)
    check("a prerelease is not an offer", Updater.release(from: """
    {"tag_name":"v2.0.0","html_url":"https://example.com/x","prerelease":true}
    """.data(using: .utf8)!) == nil)
    check("a tag that is not a version is refused", Updater.release(from: """
    {"tag_name":"nightly","html_url":"https://example.com/x"}
    """.data(using: .utf8)!) == nil)
    check("junk is refused rather than guessed at",
          Updater.release(from: Data("not json".utf8)) == nil
          && Updater.release(from: Data()) == nil)

    // A4.2. The URL out of the response went straight to NSWorkspace.open, so
    // whoever controls the response body chose what the Download button opened.
    // All three of these were accepted by the real parser before the guard.
    for hostile in ["file:///Applications/Calculator.app",
                    "x-fake-handler://run?cmd=rm",
                    "ftp://example.com/payload",
                    "javascript:alert(1)"] {
        check("an update URL with scheme \(hostile.prefix(12))… is refused",
              Updater.release(from: Data("""
              {"tag_name":"v9.9.9","html_url":"\(hostile)"}
              """.utf8)) == nil,
              hostile)
    }
    // Refused as *unreadable*, not as "no update": a response this app cannot
    // trust is a failed check, and `notAnOffer` would mean the endpoint answered
    // and had nothing — which stops the retry (U25's ninety-six-requests case).
    check("…and refused as unreadable rather than as a successful non-offer",
          Updater.parse(Data("""
          {"tag_name":"v9.9.9","html_url":"file:///tmp/x"}
          """.utf8)) == .unreadable)
    // The inverse row: https still works, or the guard would be satisfied by an
    // updater that refuses everything.
    check("…while an ordinary https release page is still offered",
          Updater.release(from: Data("""
          {"tag_name":"v9.9.9","html_url":"https://github.com/x/y/releases/tag/v9.9.9"}
          """.utf8))?.version == "9.9.9")
    check("…and the predicate itself is scheme-based, not host-based",
          Updater.isOfferableURL(URL(string: "https://not-github.example/evil")!)
            && !Updater.isOfferableURL(URL(string: "http://github.com/x")!))
    // A prerelease is a *successful* check with nothing to offer, and a
    // truncated response is a failure. `release(from:)` returns nil for both,
    // and `check` treats nil as failure — which spends fifteen minutes and
    // tries again, for ever, on a repo whose latest release happens to be a
    // prerelease. Ninety-six requests a day from an app that promises one, and
    // the promise is the point (U25 review).
    check("a prerelease parses as a real answer with nothing to offer",
          Updater.parse(Data("""
          {"tag_name":"v9.9.9","html_url":"https://x/y","prerelease":true}
          """.utf8)) == .notAnOffer)
    check("a draft is a real answer too",
          Updater.parse(Data("""
          {"tag_name":"v9.9.9","html_url":"https://x/y","draft":true}
          """.utf8)) == .notAnOffer)
    check("…while a truncated response is unreadable, not an answer",
          Updater.parse(Data("not json".utf8)) == .unreadable)
    check("…and so is JSON with no tag in it",
          Updater.parse(Data("{}".utf8)) == .unreadable)
    check("a real release still parses as an offer",
          Updater.parse(Data("""
          {"tag_name":"v9.9.9","html_url":"https://x/y","body":"notes"}
          """.utf8)) == .offer(Updater.Release(version: "9.9.9",
                                               url: URL(string: "https://x/y")!,
                                               notes: "notes")))

    check("a release with no url is refused", Updater.release(from: """
    {"tag_name":"v2.0.0"}
    """.data(using: .utf8)!) == nil)

    // What gets announced.
    let newer = Updater.Release(version: "9.9.9", url: URL(string: "https://x")!, notes: "")
    check("a newer version is announced",
          Updater.shouldAnnounce(newer, current: "1.0.0", skipped: nil))
    check("…unless it is the one that was skipped",
          !Updater.shouldAnnounce(newer, current: "1.0.0", skipped: "9.9.9"))
    check("…but skipping one version does not silence the next",
          Updater.shouldAnnounce(newer, current: "1.0.0", skipped: "9.9.8"))
    check("an older release is never announced",
          !Updater.shouldAnnounce(Updater.Release(version: "0.1", url: URL(string: "https://x")!,
                                                  notes: ""), current: "1.0.0", skipped: nil))

    // Rate limiting, including the clock going backwards — which must not
    // disable checking for ever (R30's lesson, in a different file).
    let now = Date(timeIntervalSince1970: 1_000_000)
    check("a check is due when there has never been one",
          Updater.isDue(now: now, last: 0, enabled: true))
    check("…and not again straight away",
          !Updater.isDue(now: now, last: now.timeIntervalSince1970 - 60, enabled: true))
    check("…but is a day later",
          Updater.isDue(now: now, last: now.timeIntervalSince1970 - 90_000, enabled: true))
    check("a clock that jumped backwards does not disable checking for ever",
          Updater.isDue(now: now, last: now.timeIntervalSince1970 + 100_000, enabled: true))
    check("and nothing is due when the setting is off",
          !Updater.isDue(now: now, last: 0, enabled: false))

    // The three above pass `enabled:` explicitly, so none of them reads the
    // preference that actually gates every network request in the app. Omit the
    // argument and let the default read UserDefaults — that is the code path
    // that ships (U26).
    do {
        let saved = UserDefaults.standard.object(forKey: Prefs.checkForUpdates)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: Prefs.checkForUpdates) }
            else { UserDefaults.standard.removeObject(forKey: Prefs.checkForUpdates) }
        }
        UserDefaults.standard.set(false, forKey: Prefs.checkForUpdates)
        UserDefaults.standard.set(0.0, forKey: Prefs.lastUpdateCheck)
        check("with the preference off, no automatic check is due",
              !Updater.isDue(now: now, last: 0))
        UserDefaults.standard.set(true, forKey: Prefs.checkForUpdates)
        check("…and with it on, one is",
              Updater.isDue(now: now, last: 0))
    }
}

print("\nwhat each file's row shows")

do {
    // The per-file status the list draws. It lives in the model rather than in
    // the view body because run_tests.sh compiles the views and never
    // instantiates one — logic in a View is logic no check can reach, which is
    // how the UI has historically gone untested (U13, U15, U17 all needed a VM).
    resetPrefs()
    let dir = tmp.appendingPathComponent("rows-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = dir.appendingPathComponent("a.pdf")
    let b = dir.appendingPathComponent("b.pdf")
    makeScannedPDF(at: a, lines: ["A"]); makeScannedPDF(at: b, lines: ["B"])

    MainActor.assumeIsolated {
        let m = OCRModel()
        m.besideOriginal = true
        _ = m.add([a, b])

        check("a queued file is pending", m.status(url: a) == .pending)
        check("…and says so", m.statusDescription(url: a) == "waiting")

        m.inFlight = [a]
        check("a file in flight is running", m.status(url: a).isRunning)
        check("…with no stage yet, it still reads as in progress",
              m.statusDescription(url: a) == "in progress")

        m.stages[a] = ("Rebuilding page 3 of 12", 0.25)
        check("…and carries its stage once there is one",
              m.status(url: a) == .running("Rebuilding page 3 of 12"),
              m.statusDescription(url: a))
        check("…which is what the row shows",
              m.statusDescription(url: a) == "in progress, Rebuilding page 3 of 12")

        // The other file is untouched by any of that.
        check("a file not in flight is unaffected", m.status(url: b) == .pending)

        m.inFlight = []
        m.outcomes[a] = .succeeded
        m.outcomes[b] = .failed
        check("a finished file shows its outcome", m.status(url: a) == .succeeded)
        check("…and a failed one shows failure", m.status(url: b) == .failed)
        check("…spoken as done and failed",
              m.statusDescription(url: a) == "done" && m.statusDescription(url: b) == "failed")

        // U26. Everything above sets inFlight/outcomes by hand, so none of it
        // touches the code that actually populates them — a run could stop
        // recording outcomes entirely and all eleven would stay green. These
        // two drive real batches.
        _ = m

        // Editing the list must take the row state with it, or a file dropped
        // again shows last run's tick before it has done anything.
        m.outcomes[a] = .succeeded
        m.stages[a] = ("stale", 0.5)
        m.remove(a)
        check("removing a file forgets its status",
              m.status(url: a) == .pending && m.stages[a] == nil,
              String(describing: m.status(url: a)))
        _ = m.add([a])
        check("…so re-adding it shows waiting, not last run's tick",
              m.status(url: a) == .pending, String(describing: m.status(url: a)))

        // Sibling sweep on the U26 fix, which cleared `outcomes` and `stages`
        // and missed the third per-file collection: a file that kept its own
        // text is in `skipped`, and that is a row state like any other. It is
        // reset when a run starts, so the stale value shows in exactly the gap
        // where someone is deciding what to run.
        m.skipped = [a]
        _ = m.remove(a)
        check("removing a skipped file forgets that too",
              m.status(url: a) == .pending, String(describing: m.status(url: a)))
        _ = m.add([a])

        m.outcomes[a] = .failed
        m.skipped = [a]
        _ = m.clearFiles()
        check("Clear List forgets every status",
              m.outcomes.isEmpty && m.stages.isEmpty && m.skipped.isEmpty,
              "\(m.outcomes.count) outcomes, \(m.stages.count) stages, \(m.skipped.count) skipped")

        // Running beats a recorded outcome: re-running a file that failed last
        // time must not still show a cross while it is working.
        m.inFlight = [b]
        check("a re-run file shows as running, not as its old outcome",
              m.status(url: b).isRunning, String(describing: m.status(url: b)))
    }
    resetPrefs()
}

print("\nevery door into a committed batch is shut")

do {
    // U23, and the control for the fourth way fixes produce bugs: two changes
    // that are each correct alone. U19 gave the model `isCommitted` and gated
    // `add` on it; U20 added an async import that also checks it. Neither was
    // wrong, and U21 still happened, because the *property* — "from the click
    // until the run ends the batch cannot change" — lived in no single place
    // and each feature checked it at its own moment.
    //
    // So enumerate instead of reasoning: every state from the click onwards,
    // crossed with every way to mutate the batch. A cross product is finite and
    // small, and it does not care which pair of features happens to interact.
    // It is also what catches a state nobody represented — U21 was exactly that,
    // a "deciding" state that existed in behaviour and in no flag.
    resetPrefs()
    let dir = tmp.appendingPathComponent("doors-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let one = dir.appendingPathComponent("one.pdf")
    let two = dir.appendingPathComponent("two.pdf")
    let three = dir.appendingPathComponent("three.pdf")
    makeScannedPDF(at: one, lines: ["ONE"])
    makeScannedPDF(at: two, lines: ["TWO"])
    makeScannedPDF(at: three, lines: ["THREE"])

    // Every state in which the batch is committed and therefore frozen.
    let committedStates: [(String, @MainActor (OCRModel) -> Void)] = [
        ("pre-flighting", { $0.isPreflighting = true }),
        ("running", { $0.isRunning = true }),
        // The state U21 was about: the scan is over, the alert is up, the batch
        // was decided at the click. Represented now, so it can be enumerated.
        ("deciding", { $0.isPreflighting = true; $0.isRunning = false }),
    ]

    // Every door. `mutate` returns true if the batch actually changed.
    //
    // **The batch is two files, and it has to be** (`REVIEW-2026-08-14.md`
    // A11.2). With one file that was also the failed one, `retryFailures`'
    // narrowing was the *identity map*: `files != before` was false whether the
    // gate held or not, in all three states. Mutating `canRetryFailures`'
    // `!isCommitted` to `!isRunning` — U19's recorded defect verbatim — left the
    // suite **862/862, exit 0**, while under it a retry in the pre-flighting and
    // deciding states erased every verdict and silently narrowed a committed
    // two-file batch to one. Three of this table's cells were decorative, in
    // CONTRIBUTING 4d's flagship control.
    //
    // So `add` opens a *third* file: adding `two` to a batch that already holds
    // it would dedupe, and the add row would go inert in the same way.
    let doors: [(String, @MainActor (OCRModel) -> Bool)] = [
        ("add", { m in let before = m.files; _ = m.add([three]); return m.files != before }),
        ("remove", { m in let before = m.files; m.remove(one); return m.files != before }),
        ("clearFiles", { m in let before = m.files; m.clearFiles(); return m.files != before }),
        // The seventh door. `retryFailures` replaces `files` wholesale, which is
        // the most destructive mutation of the three above, and it is reachable
        // from a button that is visible whenever the last run left a failure —
        // including while the next run is in flight.
        ("retryFailures", { m in
            // One of the two failed and one did not, so a retry that ran would
            // narrow [one, two] to [one] and be visible in `files`.
            m.outcomes[one] = .failed
            m.outcomes[two] = .succeeded
            let before = m.files
            _ = m.retryFailures()
            return m.files != before
        }),
    ]

    for (stateName, enter) in committedStates {
        for (doorName, mutate) in doors {
            MainActor.assumeIsolated {
                let m = OCRModel()
                m.besideOriginal = true
                _ = m.add([one, two])
                enter(m)
                check("\(doorName) cannot change a committed batch (\(stateName))",
                      !mutate(m), "the batch changed while \(stateName)")
            }
        }
    }

    // And the same doors must still work when nothing is committed, or the
    // guards above would be satisfied by an app that does nothing at all.
    MainActor.assumeIsolated {
        let m = OCRModel()
        m.besideOriginal = true
        _ = m.add([one, two])
        check("…and add still works when idle",
              { _ = m.add([three]); return m.files.count == 3 }(), "\(m.files.count)")
        check("…and remove still works when idle",
              { m.remove(one); return m.files.count == 2 }(), "\(m.files.count)")
        check("…and clearFiles still works when idle", { m.clearFiles(); return m.files.isEmpty }())
    }
    // The seventh door's inverse row is not repeated here: "retrying the
    // failures from a finished batch" above drives `retryFailures` from an idle
    // model and asserts both that it starts a run and that `files` narrows to
    // `[broken]`. Repeating it here would mean a second real batch — the
    // narrowing is inseparable from `start()` — for coverage that already exists.
    resetPrefs()
}

// MARK: - The import interlock counts, and every door respects it (A5.3)

// `isImporting` was a boolean set true by every `add` and false by every
// completion, so the **first** completion cleared it while other walks were still
// in flight. Two drops, one large: at the moment the small one lands the interlock
// is down, Start is available, and the batch total is 1 — then the 8,000-file walk
// completes into a batch that has already been frozen, or lands *after* `finishUp`
// as 8,001 rows over "Done — 1 of 1 succeeded". U1 verbatim, for the fourth time.
//
// And the interlock lived only in `canStart`, so it was a property enforced in the
// view: `start()` never checked it at all, and `clearFiles()` was not interlocked
// either. U19 and U23 are the two entries about exactly that shape.

print("\nthe import interlock counts imports, not drops")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("a53-\(UUID().uuidString)")
    let bigDir = dir.appendingPathComponent("many")
    let smallDir = dir.appendingPathComponent("few")
    for d in [bigDir, smallDir] {
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: dir) }
    // Deliberately tiny. The review's scenario used an 8,000-file walk to make the
    // race observable by hand, but nothing here depends on a race: both `add`
    // calls dispatch before either completion can run, because this block holds
    // the main actor until it returns to the run loop. So both walks are in flight
    // by construction, and the suite does not pay for 8,000 files to prove it.
    for i in 1...3 {
        makeScannedPDF(at: bigDir.appendingPathComponent("scan \(i).pdf"),
                       lines: ["Page one of scan \(i)."])
    }
    makeScannedPDF(at: smallDir.appendingPathComponent("only.pdf"), lines: ["Only."])

    var importingAtEachCompletion: [Bool] = []
    let m = MainActor.assumeIsolated { OCRModel() }
    MainActor.assumeIsolated {
        m.besideOriginal = true
        // Both in flight before either completion can run: `add` returns
        // immediately and does the walk on a background queue.
        m.add([bigDir]) { _ in
            MainActor.assumeIsolated { importingAtEachCompletion.append(m.isImporting) }
        }
        m.add([smallDir]) { _ in
            MainActor.assumeIsolated { importingAtEachCompletion.append(m.isImporting) }
        }
    }
    let started = Date()
    while importingAtEachCompletion.count < 2, Date().timeIntervalSince(started) < 60 {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }

    check("both imports completed", importingAtEachCompletion.count == 2,
          "\(importingAtEachCompletion.count)")
    // Order-independent on purpose: whichever walk finishes first, one import is
    // still outstanding when it does. With a boolean this is false.
    check("the interlock is still up when the first of two imports completes",
          importingAtEachCompletion.first == true,
          "isImporting was already false with a walk still in flight")
    check("…and down once the second completes",
          importingAtEachCompletion.last == false)
    MainActor.assumeIsolated {
        check("…and both drops' files arrived", m.files.count == 4, "\(m.files.count)")
    }
    resetPrefs()
}

do {
    // The other half of A5.3: the interlock has to be enforced where the mutation
    // happens, not only where the button is drawn. Driven through the state
    // directly, the way the doors table drives `isRunning` — a real race would be
    // a timing test, and this is a property.
    resetPrefs()
    let dir = tmp.appendingPathComponent("a53b-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let one = dir.appendingPathComponent("one.pdf")
    makeScannedPDF(at: one, lines: ["One."])

    // A fresh model per door. Sharing one made two of these pass for the wrong
    // reason: `start()` got through, which set `isRunning`, and `clearFiles` then
    // refused on the *isCommitted* guard it already had — a green check over an
    // unguarded door, decided by the defect in the check above it.
    @MainActor func importing() -> OCRModel {
        let m = OCRModel()
        m.besideOriginal = true
        _ = m.add([one])
        m.importsInFlight = 1                      // a walk is outstanding
        return m
    }

    MainActor.assumeIsolated {
        check("Start is not offered while an import is in flight", !importing().canStart)

        let s = importing()
        s.start()
        check("…and start() refuses even when called directly",
              !s.isRunning && !s.isPreflighting,
              "a batch began with an import still walking")

        let c = importing()
        check("…and clearFiles refuses too", !c.clearFiles())
        check("…so the files are still there", c.files == [one], "\(c.files.count)")

        // The inverse row, or the three above are satisfied by an app that does
        // nothing at all (CONTRIBUTING 4d).
        let done = importing()
        done.importsInFlight = 0
        check("…and Start is offered again once the walk lands", done.canStart)
        check("…and clearFiles works again", done.clearFiles())
    }
    resetPrefs()
}

print("\nretrying the failures from a finished batch")

do {
    // The model already knows which files failed; without this a four-file
    // failure out of seventy-eight means re-dropping four files by hand.
    resetPrefs()
    let dir = tmp.appendingPathComponent("retry-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = dir.appendingPathComponent("a.pdf"), b = dir.appendingPathComponent("b.pdf")
    let c = dir.appendingPathComponent("c.pdf")
    for u in [a, b, c] { makeScannedPDF(at: u, lines: [u.lastPathComponent]) }

    MainActor.assumeIsolated {
        let m = OCRModel()
        m.besideOriginal = true
        _ = m.add([a, b, c])
        check("nothing to retry before a run", m.failedFiles.isEmpty && !m.canRetryFailures)

        m.outcomes = [a: .succeeded, b: .failed, c: .failed]
        check("the failures are the failures", m.failedFiles == [b, c],
              m.failedFiles.map(\.lastPathComponent).joined(separator: ","))
        // `outcomes` is a dictionary. Taking the order from it would shuffle the
        // retry against the first run's log, which is what you read them side
        // by side for.
        m.outcomes = [c: .failed, b: .failed, a: .succeeded]
        check("…in list order, not dictionary order", m.failedFiles == [b, c],
              m.failedFiles.map(\.lastPathComponent).joined(separator: ","))
        check("…and retrying is offered", m.canRetryFailures)

        // A cancelled file is not a failed one: it did not fail, it was stopped,
        // and sweeping it into a retry would restart work the user cancelled.
        m.outcomes = [a: .succeeded, b: .cancelled, c: .failed]
        check("a cancelled file is not retried", m.failedFiles == [c],
              m.failedFiles.map(\.lastPathComponent).joined(separator: ","))
    }

    // The whole thing end to end, with a file that really cannot be read.
    let broken = dir.appendingPathComponent("broken.pdf")
    try? Data("not a pdf at all".utf8).write(to: broken)
    let outDir = dir.appendingPathComponent("out")
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    final class Box2: @unchecked Sendable { var model: OCRModel? }
    let box = Box2()
    var started = false
    Task { @MainActor in
        let m = OCRModel()
        m.besideOriginal = false
        m.outputFolder = outDir
        _ = m.add([a, broken])
        box.model = m
        m.start()
        started = true
    }
    _ = pump(until: { started }, seconds: 5)
    _ = pump(until: { MainActor.assumeIsolated { box.model?.isRunning == true } }, seconds: 30)
    _ = pump(until: { MainActor.assumeIsolated { box.model?.isRunning == false } }, seconds: 180)

    var retried = false
    MainActor.assumeIsolated {
        guard let m = box.model else { check("the retry model exists", false); return }
        check("the unreadable file failed, or the retry has nothing to work on",
              m.failedFiles == [broken],
              m.failedFiles.map(\.lastPathComponent).joined(separator: ","))
        check("…and the good one did not", m.outcomes[a] == .succeeded,
              String(describing: m.outcomes[a]))
        retried = m.retryFailures()
        check("retrying starts a run", retried)
        // The list narrows to what is about to happen, so the window is not
        // showing three files while one runs.
        check("…over the failures alone", m.files == [broken],
              m.files.map(\.lastPathComponent).joined(separator: ","))
        // U26's shape: a row that keeps showing a verdict from a run that is
        // over, describing something that is not going to happen again.
        check("…and the old verdicts are cleared", m.outcomes[a] == nil)
    }
    if retried {
        _ = pump(until: { MainActor.assumeIsolated { box.model?.isRunning == false } },
                 seconds: 180)
        MainActor.assumeIsolated {
            guard let m = box.model else { return }
            let text = m.log.map(\.text).joined(separator: "\n")
            check("the retry's log says why it is running",
                  text.contains("Retrying 1 file that failed"), text.prefix(120).description)
            check("…and it failed again, since nothing about the file changed",
                  m.failedFiles == [broken],
                  m.failedFiles.map(\.lastPathComponent).joined(separator: ","))
            check("…and it can be retried again", m.canRetryFailures)
        }
    }

    // The note is a parameter, not model state. A stored one survives every
    // path that declines to run and reappears heading an unrelated batch.
    MainActor.assumeIsolated {
        let m = OCRModel()
        m.besideOriginal = true
        _ = m.add([a])
        m.outcomes = [a: .failed]
        m.isRunning = true                      // start() will decline
        check("a declined retry does not run", !m.retryFailures())
        m.isRunning = false
        m.outcomes = [:]
        _ = m.add([b])
        check("…and leaves no retry note behind for the next batch",
              !m.log.map(\.text).joined().contains("Retrying"),
              m.log.map(\.text).joined(separator: " | "))
    }

    // `canRetryFailures` cannot see every reason `start` declines. Point the
    // binary somewhere that does not exist and it declines *after*
    // `retryFailures` has narrowed the list and erased the verdicts, which
    // would leave the user holding neither.
    MainActor.assumeIsolated {
        let m = OCRModel()
        m.besideOriginal = true
        _ = m.add([a, b, c])
        m.outcomes = [a: .succeeded, b: .failed, c: .failed]
        // `start()` used to decline when mac-ocr could not be found, and that is
        // what this drove. Nothing has to be found now, so the decline is forced
        // the way any other refusal is: no destination.
        m.besideOriginal = false
        m.outputFolder = nil
        check("there is no destination, so start() will decline",
              !m.destinationReady)
        check("retrying reports that it did not start", !m.retryFailures())
        check("…and puts the whole batch back", m.files == [a, b, c],
              m.files.map(\.lastPathComponent).joined(separator: ","))
        check("…with its verdicts intact", m.outcomes[a] == .succeeded
                && m.outcomes[b] == .failed && m.outcomes[c] == .failed,
              "\(m.outcomes.count) outcomes")
    }
    resetPrefs()
}

// MARK: - A declined retry puts the batch back, on the path that actually declines (A5.2)

// The block above drives the **first** guard: with no destination
// `canRetryFailures` is false, so `retryFailures` returns before it has narrowed
// anything, and "puts the whole batch back" is a check that cannot fail — it
// asserts a list nothing took away. The eleventh of those in this project, and it
// is guarding the very thing A5.2 is about.
//
// The decline that matters arrives *after* the narrowing, out of the async
// pre-flight. Under the shipped defaults `start()` returns with `isPreflighting`
// already true, so `guard isCommitted` passes, `retryFailures` reports success,
// and the restore it exists for never runs. What the user is left holding: a list
// narrowed to the failures, every verdict erased, `canRetryFailures` false so the
// record is unrecoverable — under a log line reading "Start cancelled — nothing
// was changed."

print("\na retry declined at the alert puts the batch back")

do {
    resetPrefs()
    let d = UserDefaults.standard
    let dir = tmp.appendingPathComponent("a52-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: dir)
        OCRModel.digitalTextDecisionForTesting = nil
    }
    // Both born-digital, so the pre-flight fires on the retried one.
    var made: [URL] = []
    for name in ["kept.pdf", "failed.pdf"] {
        let u = dir.appendingPathComponent(name)
        makeDigitalPDF(at: u, lines: (1...26).map {
            "Line \($0) of ordinary running prose, long enough to be a real paragraph."
        })
        made.append(u)
    }
    let kept = made[0], failed = made[1]

    d.set(true, forKey: Prefs.warnDigitalText)
    d.set(true, forKey: Prefs.rebuildImages)
    d.set(Prefs.Mode.searchablePDF.rawValue, forKey: Prefs.mode)

    let asked = DispatchSemaphore(value: 0)
    var narrowedAtDecision: [URL] = []
    let m = MainActor.assumeIsolated { OCRModel() }
    OCRModel.digitalTextDecisionForTesting = { _, _ in
        MainActor.assumeIsolated { narrowedAtDecision = m.files }
        asked.signal()
        return .cancel
    }

    let claimed: Bool = MainActor.assumeIsolated {
        m.besideOriginal = true
        _ = m.add([kept, failed])
        m.outcomes = [kept: .succeeded, failed: .failed]
        check("the retry is offered", m.canRetryFailures)
        return m.retryFailures()
    }
    let started = Date()
    while asked.wait(timeout: .now()) == .timedOut,
          Date().timeIntervalSince(started) < 30 {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    // Let the cancel branch run after the decision returns.
    let settled = Date()
    while MainActor.assumeIsolated({ m.isPreflighting }),
          Date().timeIntervalSince(settled) < 30 {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }

    check("the pre-flight reached the decision", !narrowedAtDecision.isEmpty,
          "never asked")
    // The premise, asserted rather than assumed: the list really was narrowed, so
    // the restore below has something to restore. Without this the whole block
    // could pass against a `retryFailures` that never got started.
    check("…and the list really was narrowed to the failure first",
          narrowedAtDecision == [failed],
          narrowedAtDecision.map(\.lastPathComponent).joined(separator: ","))
    check("…and retryFailures reported that it started", claimed)

    MainActor.assumeIsolated {
        check("the whole batch is back after the decline", m.files == [kept, failed],
              m.files.map(\.lastPathComponent).joined(separator: ","))
        check("…with every verdict intact",
              m.outcomes[kept] == .succeeded && m.outcomes[failed] == .failed,
              "\(m.outcomes.count) outcomes")
        check("…so the record of what failed is still recoverable", m.canRetryFailures)
        check("…and the log's claim that nothing changed is now true",
              m.log.map(\.text).joined().contains("nothing was changed"),
              m.log.map(\.text).joined(separator: " | "))
    }
    OCRModel.digitalTextDecisionForTesting = nil
    resetPrefs()
}

// MARK: - A retry cannot publish over a file the batch protected (R60)

// `uniqueOutputs` keeps every output off **every input in the batch**, so
// re-running a folder that already holds a previous run's results cannot claim a
// name another worker is reading. `retryFailures` narrows `files` to the
// failures — so the sibling that was doing the protecting leaves the batch, and
// the retry claims the name that had been reserved away from it. Verified end to
// end: 13,006 bytes of somebody's previous output replaced by 7,268 bytes of a
// re-scan, with nothing in the log about it.
//
// The unit checks come first because they are exhaustive and instant, and because
// **both halves of the fix are needed and neither is sufficient** — the first
// attempt at this carried only the earlier attempt's *outputs* forward and failed
// its own test twice over.

print("\na retry cannot claim a path the batch it came from protected")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("retry-claim-\(UUID().uuidString)")
    let sub = dir.appendingPathComponent("b")
    let outDir = dir.appendingPathComponent("out")
    for u in [dir, sub, outDir] {
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: dir) }

    // Sequence A's shape: a folder holding a previous run's output beside the
    // original it came from. Both are inputs, because the user dropped the folder.
    let precious = dir.appendingPathComponent("scan.ocr.pdf")
    let original = dir.appendingPathComponent("scan.pdf")

    // What run 1 resolved, computed by the real function.
    let first = OCRModel.uniqueOutputs(for: [precious, original], besideOriginal: true,
                                       folder: nil, suffix: ".ocr", extension: "pdf")
    check("run 1 keeps the second input off the first input's own path",
          first[original]?.lastPathComponent == "scan 2.ocr.pdf",
          first[original]?.lastPathComponent ?? "nil")
    check("…and the first input's output is a third name",
          first[precious]?.lastPathComponent == "scan.ocr.ocr.pdf",
          first[precious]?.lastPathComponent ?? "nil")

    // The defect, stated as a check: with only the retried file in the list and
    // nothing carried forward, the protected path is exactly what it claims.
    let naive = OCRModel.uniqueOutputs(for: [original], besideOriginal: true,
                                       folder: nil, suffix: ".ocr", extension: "pdf")
    check("a narrowed batch on its own claims the protected path — the defect",
          naive[original]?.lastPathComponent == "scan.ocr.pdf",
          naive[original]?.lastPathComponent ?? "nil")

    // The fix: the earlier attempt's inputs *and* outputs carried forward, with
    // the retried file's own previous slot released back to it.
    let carried = Set<URL>([precious, original]).union(first.values)
    let retried = OCRModel.uniqueOutputs(
        for: [original], besideOriginal: true, folder: nil, suffix: ".ocr",
        extension: "pdf", alsoClaimed: carried, releasing: [first[original]!])
    check("carrying the earlier attempt forward protects the path",
          retried[original]?.lastPathComponent == "scan 2.ocr.pdf",
          retried[original]?.lastPathComponent ?? "nil")

    // And **outputs alone are not enough**, which is the half that was tried
    // first: the protected path was an *input* of the earlier attempt, never one
    // of its outputs, so carrying outputs forward does not re-reserve it.
    let outputsOnly = OCRModel.uniqueOutputs(
        for: [original], besideOriginal: true, folder: nil, suffix: ".ocr",
        extension: "pdf", alsoClaimed: Set(first.values),
        releasing: [first[original]!])
    check("…and carrying only the outputs forward does not — the fix that failed",
          outputsOnly[original]?.lastPathComponent == "scan.ocr.pdf",
          outputsOnly[original]?.lastPathComponent ?? "nil")

    // Nor is releasing optional. Without it the retried file is pushed past its
    // own previous slot to a *third* name, and would be renamed again on every
    // retry — the quieter second bug in the same place.
    let noRelease = OCRModel.uniqueOutputs(
        for: [original], besideOriginal: true, folder: nil, suffix: ".ocr",
        extension: "pdf", alsoClaimed: carried)
    check("…and without releasing its own slot the retry is renamed again",
          noRelease[original]?.lastPathComponent == "scan 3.ocr.pdf",
          noRelease[original]?.lastPathComponent ?? "nil")

    // Sequence B: two inputs sharing a base name in different folders, one output
    // folder, the second one failing. The retry must reuse its own slot and leave
    // the first input's finished output alone.
    let aScan = dir.appendingPathComponent("scan.pdf")
    let bScan = sub.appendingPathComponent("scan.pdf")
    let firstB = OCRModel.uniqueOutputs(for: [aScan, bScan], besideOriginal: false,
                                        folder: outDir, suffix: ".ocr", extension: "pdf")
    check("two inputs sharing a base name get distinct outputs",
          firstB[aScan]?.lastPathComponent == "scan.ocr.pdf"
            && firstB[bScan]?.lastPathComponent == "scan 2.ocr.pdf",
          "\(firstB[aScan]?.lastPathComponent ?? "nil") / "
            + "\(firstB[bScan]?.lastPathComponent ?? "nil")")
    let retriedB = OCRModel.uniqueOutputs(
        for: [bScan], besideOriginal: false, folder: outDir, suffix: ".ocr",
        extension: "pdf", alsoClaimed: Set([aScan, bScan]).union(firstB.values),
        releasing: [firstB[bScan]!])
    check("a retry keeps off the other input's finished output",
          retriedB[bScan]?.lastPathComponent == "scan 2.ocr.pdf",
          retriedB[bScan]?.lastPathComponent ?? "nil")

    // An input of *this* batch outranks a release. A path being read right now is
    // the case `uniqueOutputs` exists for, so `releasing` must not be able to
    // hand it out — otherwise a retry that still holds the previous output as an
    // input would publish over the file it is reading.
    let clash = OCRModel.uniqueOutputs(
        for: [precious, original], besideOriginal: true, folder: nil, suffix: ".ocr",
        extension: "pdf", alsoClaimed: [precious], releasing: [precious])
    check("releasing cannot hand out a path this batch is reading",
          clash[original]?.lastPathComponent == "scan 2.ocr.pdf",
          clash[original]?.lastPathComponent ?? "nil")

    // Three attempts, so the accumulation is exercised rather than assumed: the
    // third must still remember what the first reserved.
    let cScan = dir.appendingPathComponent("third.pdf")
    var chain: Set<URL> = [precious, original, cScan]
    let a1 = OCRModel.uniqueOutputs(for: [precious, original, cScan], besideOriginal: true,
                                    folder: nil, suffix: ".ocr", extension: "pdf")
    chain.formUnion(a1.values)
    let a2 = OCRModel.uniqueOutputs(
        for: [original, cScan], besideOriginal: true, folder: nil, suffix: ".ocr",
        extension: "pdf", alsoClaimed: chain,
        releasing: [a1[original]!, a1[cScan]!])
    chain.formUnion(a2.values)
    let a3 = OCRModel.uniqueOutputs(
        for: [original], besideOriginal: true, folder: nil, suffix: ".ocr",
        extension: "pdf", alsoClaimed: chain, releasing: [a2[original]!])
    check("a third attempt still keeps off what the first reserved",
          a3[original]?.lastPathComponent == "scan 2.ocr.pdf",
          a3[original]?.lastPathComponent ?? "nil")
    check("…and does not rename its own output again",
          a3[original] == a1[original] && a2[original] == a1[original],
          "\(a1[original]?.lastPathComponent ?? "nil") → "
            + "\(a2[original]?.lastPathComponent ?? "nil") → "
            + "\(a3[original]?.lastPathComponent ?? "nil")")
    resetPrefs()
}

// And the same sequence through the real model, because the unit checks above
// prove the *rule* and this proves the model applies it. The recorded harm is a
// user's file replaced, so the assertion is on the user's file, byte for byte.

print("\nthe retried batch really does protect the earlier one's files")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("retry-e2e-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // No modal in a headless run: the digital-text prompt would sit there for
    // ever, and this block drives a real batch.
    d.set(false, forKey: Prefs.warnDigitalText)

    // A previous run's output — named exactly as `uniqueOutputs` would have named
    // it — carrying text nothing else in the suite writes.
    let precious = dir.appendingPathComponent("scan.ocr.pdf")
    makeScannedPDF(at: precious, lines: ["PRECIOUS ORIGINAL from the previous run"])
    // …and its original, which arrives unreadable so the first attempt fails it.
    let original = dir.appendingPathComponent("scan.pdf")
    try? Data("not a pdf at all".utf8).write(to: original)
    let preciousBefore = try? Data(contentsOf: precious)

    final class Box: @unchecked Sendable { var model: OCRModel? }
    let box = Box()
    var started = false
    Task { @MainActor in
        let m = OCRModel()
        m.besideOriginal = true
        _ = m.add([precious, original])
        box.model = m
        m.start()
        started = true
    }
    _ = pump(until: { started }, seconds: 5)
    _ = pump(until: { MainActor.assumeIsolated { box.model?.isRunning == true } }, seconds: 30)
    _ = pump(until: { MainActor.assumeIsolated { box.model?.isRunning == false } }, seconds: 240)

    var retried = false
    MainActor.assumeIsolated {
        guard let m = box.model else { check("the model exists", false); return }
        check("the unreadable original failed, or there is nothing to retry",
              m.failedFiles == [original],
              m.failedFiles.map(\.lastPathComponent).joined(separator: ","))
        check("…and the previous output was itself processed",
              m.outcomes[precious] == .succeeded, String(describing: m.outcomes[precious]))
        check("the first run left the previous output alone",
              preciousBefore == (try? Data(contentsOf: precious)))
        // The original is readable now — a truncated download that completed, an
        // encrypted file whose password was entered, a destination that came back.
        makeScannedPDF(at: original, lines: ["REPLACEMENT SCAN, freshly readable"])
        retried = m.retryFailures()
        check("the retry starts", retried)
    }
    if retried {
        _ = pump(until: { MainActor.assumeIsolated { box.model?.isRunning == false } },
                 seconds: 240)
        MainActor.assumeIsolated {
            guard let m = box.model else { return }
            check("the retry succeeded", m.outcomes[original] == .succeeded,
                  m.log.map(\.text).joined(separator: " | ").prefix(200).description)
            // THE CHECK THIS BLOCK EXISTS FOR.
            check("the file the first batch protected is byte-for-byte intact",
                  preciousBefore != nil && preciousBefore == (try? Data(contentsOf: precious)),
                  "\(preciousBefore?.count ?? -1) bytes before, "
                    + "\((try? Data(contentsOf: precious))?.count ?? -1) after")
            // Byte identity is the assertion, and it is the strongest one
            // available. A first version added "…and it still says what it said"
            // over `embeddedText(of: precious)` — which is empty for every
            // fixture `makeScannedPDF` builds, because a scan has pixels and no
            // text layer. It failed against a file that was provably unchanged:
            // a check that cannot pass, next to a check that cannot fail, in a
            // block about checks that cannot fail. What corroborates that the
            // protected file held real content is run 1's own output from it.
            let derived = dir.appendingPathComponent("scan.ocr.ocr.pdf")
            check("…and run 1's output from it carries its text, so it was not empty",
                  embeddedText(of: derived).uppercased().contains("PRECIOUS"),
                  embeddedText(of: derived).prefix(80).description)
            // The retry's own output went somewhere, and the log says where.
            let renamed = dir.appendingPathComponent("scan 2.ocr.pdf")
            check("the retry published to its own slot instead",
                  FileManager.default.fileExists(atPath: renamed.path),
                  ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
                      .sorted().joined(separator: ", "))
            check("…carrying the replacement's text",
                  embeddedText(of: renamed).uppercased().contains("REPLACEMENT"),
                  embeddedText(of: renamed).prefix(80).description)
            // R60 also noted the silence: `renamedOutputs` was empty on a retry,
            // so even the "(renamed; another input claimed that name)" note was
            // absent. Reusing its own slot makes the name differ from the default
            // again, so the note is back.
            let text = m.log.map(\.text).joined(separator: "\n")
            check("…and the log says the name was not the default",
                  text.contains("renamed") || text.contains("scan 2.ocr.pdf"),
                  text.prefix(300).description)
        }
    }
    resetPrefs()
}

print("\nthe batch stays frozen while the alert is up")

do {
    // U21. start() froze the batch, ran the pre-flight, then cleared
    // isPreflighting BEFORE putting up the modal alert. Main-queue work runs
    // behind a modal NSAlert, so U20's async import completed into a batch that
    // had already been decided — "Done — 1 of 1 succeeded" over a list of 301.
    //
    // The alert cannot run in a headless suite, which is how this shipped. The
    // seam records what was true at the moment the decision was asked for.
    resetPrefs()
    let dir = tmp.appendingPathComponent("u21-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: dir)
        OCRModel.digitalTextDecisionForTesting = nil
    }
    let digital = dir.appendingPathComponent("born-digital.pdf")
    // 26 lines a page, matching the C17 fixture: hasDigitalText wants a real
    // paragraph, and one line is not enough to read as born-digital.
    makeDigitalPDF(at: digital, lines: (1...26).map {
        "Line \($0) of ordinary running prose, long enough to be a real paragraph."
    })

    d.set(true, forKey: Prefs.warnDigitalText)
    d.set(Prefs.Mode.searchablePDF.rawValue, forKey: Prefs.mode)
    d.set(true, forKey: Prefs.rebuildImages)

    check("the fixture is seen as born-digital, or the alert never comes",
          Flattener.hasDigitalText(digital))
    check("warnDigitalText is on for this block",
          d.bool(forKey: Prefs.warnDigitalText))
    // A `check("nothing external has to resolve for start() to reach the
    // pre-flight", true)` stood here, and its twin below. `git log -S` shows the
    // mac-ocr removal replaced a real assertion — `Runner.resolveBinary() != nil`
    // — with the literal, leaving a falsifiable label over nothing
    // (`REVIEW-2026-08-14.md` A11.3). Deleted rather than weakened further: the
    // property is now true by construction, because the pre-flight's only work is
    // `Flattener.hasDigitalText`, which runs no program at all. This file already
    // handles this correctly elsewhere and says so — "Deleted rather than
    // weakened into something that passes without testing anything."

    var committedAtDecision: Bool?
    var preflightingAtDecision: Bool?
    let asked = DispatchSemaphore(value: 0)
    let m = MainActor.assumeIsolated { OCRModel() }
    OCRModel.digitalTextDecisionForTesting = { _, _ in
        MainActor.assumeIsolated {
            committedAtDecision = m.isCommitted
            preflightingAtDecision = m.isPreflighting
        }
        asked.signal()
        return .cancel                      // nothing runs; we only want the state
    }

    MainActor.assumeIsolated {
        m.besideOriginal = true
        _ = m.add([digital])
        check("the fixture is in the list", m.files.count == 1, "\(m.files.count)")
        check("Start is available", m.canStart)
        m.start()
    }
    let started = Date()
    while committedAtDecision == nil, Date().timeIntervalSince(started) < 30 {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }

    check("the pre-flight reached the decision", committedAtDecision != nil,
          "never asked")
    check("the batch is still committed when the alert goes up",
          committedAtDecision == true,
          "isCommitted was \(String(describing: committedAtDecision)) — an import "
          + "completing here lands in a batch already frozen")
    check("…because isPreflighting is still set", preflightingAtDecision == true)
    check("…and it is cleared once the decision is made",
          MainActor.assumeIsolated { !m.isPreflighting && !m.isCommitted })
    OCRModel.digitalTextDecisionForTesting = nil
    resetPrefs()
}

do {
    // "Skip Those" has to leave a visible mark on the rows it skipped.
    //
    // U26 added `FileStatus.skipped` for this and it could never appear:
    // `skipThem` sets `skipped`, then calls `run`, whose first act is to clear
    // every per-file collection — including that one, two lines later. The
    // glyph was unreachable and the eleven row-status checks all set the state
    // by hand, so nothing noticed. Two real files, one born-digital and one
    // scanned, so there is something left to run.
    resetPrefs()
    d.set(true, forKey: Prefs.warnDigitalText)
    d.set(false, forKey: Prefs.openWhenDone)
    d.set(Prefs.Mode.searchablePDF.rawValue, forKey: Prefs.mode)

    let dir = tmp.appendingPathComponent("skip-status-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let born = dir.appendingPathComponent("born-digital.pdf")
    // 26 lines a page: hasDigitalText wants a real paragraph, and one line does
    // not read as born-digital.
    makeDigitalPDF(at: born, lines: (1...26).map {
        "Line \($0) of ordinary running prose, long enough to be a real paragraph."
    })
    let scan = dir.appendingPathComponent("scanned.pdf")
    makeScannedPDF(at: scan, lines: ["A scan that still needs recognising"])

    check("the skip-status fixture is born-digital, or the alert never comes",
          Flattener.hasDigitalText(born))
    // The twin of the literal-`true` check deleted above — A11.3.

    // On for this block only: the report is where a skipped file could go
    // missing without anyone noticing, so it has to be written to be checked.
    d.set(true, forKey: Prefs.writeRunReport)
    OCRModel.digitalTextDecisionForTesting = { _, _ in .skipThem }
    final class SkipHolder: @unchecked Sendable { var model: OCRModel? }
    let holder = SkipHolder()
    var ready = false
    Task { @MainActor in
        let m = OCRModel()
        m.besideOriginal = false
        m.outputFolder = dir
        _ = m.add([born, scan])
        holder.model = m
        m.start()
        ready = true
    }
    _ = pump(until: { ready }, seconds: 5)
    let done = pump(until: {
        MainActor.assumeIsolated { holder.model.map { !$0.isRunning && $0.completed > 0 } ?? false }
    }, seconds: 120)
    check("the skip-those batch runs the file that was left", done)

    MainActor.assumeIsolated {
        guard let m = holder.model else { check("model exists", false); return }
        check("the skipped file's row says so, and keeps saying so after the run",
              m.status(url: born) == .skipped, String(describing: m.status(url: born)))
        check("…and the file that did run shows as done, not skipped",
              m.status(url: scan) == .succeeded, String(describing: m.status(url: scan)))
        check("…and VoiceOver has something true to read out",
              m.statusDescription(url: born).contains("skipped"),
              m.statusDescription(url: born))

        // "Skip Those" hands `run` the remainder, so a report counting only
        // what ran would say "1 file, 1 succeeded" about a drop of two. The
        // omission is invisible afterwards, which is what invariant 1 is about.
        if let report = m.lastReport,
           let body = try? String(contentsOf: report, encoding: .utf8) {
            check("the report counts the files that were skipped, not just the ones that ran",
                  body.contains("2 files") && body.contains("1 skipped"),
                  body.split(separator: "\n").first { $0.contains("files —") }
                      .map(String.init) ?? body.prefix(120).description)
            check("…and names the skipped one in its log",
                  body.contains("Skipped 1 file"), body.prefix(400).description)
            try? FileManager.default.removeItem(at: report)
        } else {
            check("the skip-those run wrote a report", false)
        }
    }
    OCRModel.digitalTextDecisionForTesting = nil
    resetPrefs()
}

print("\nimporting a folder does not block the main actor")

do {
    // U20. add(_:) is @MainActor and filesInFolder enumerates a whole subtree,
    // materialises every URL, filters and then sorts with localizedStandardCompare.
    // On a big tree — or any folder on a stalled mount — that ran on the main
    // thread with the drop highlight lit and nothing able to respond.
    resetPrefs()
    let root = tmp.appendingPathComponent("bigtree-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    // Wide and deep enough to take real time, without writing real PDFs: the
    // walk is what is being measured, not the reading.
    let leafCount = 4_000
    for i in 0..<20 {
        let sub = root.appendingPathComponent("dir\(String(format: "%02d", i))")
        try! FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for j in 0..<(leafCount / 20) {
            FileManager.default.createFile(
                atPath: sub.appendingPathComponent("scan\(j).pdf").path, contents: Data())
        }
    }

    let m = MainActor.assumeIsolated { OCRModel() }
    var result: OCRModel.AddResult?
    let started = Date()
    // Recorded INSIDE the completion. Reading Thread.isMainThread at the call
    // site asserts nothing: the suite's top-level code is the main thread
    // unconditionally, so it was true before the completion ran, after it ran,
    // and if it never ran at all (T4).
    var onMain: Bool?
    var pumped = false
    MainActor.assumeIsolated {
        m.add([root]) { onMain = Thread.isMainThread; result = $0 }
    }
    let returnedAfter = Date().timeIntervalSince(started)

    // The whole property, stated without reference to the clock: when the call
    // comes back, the work has not been done yet. A timing bound would need a
    // tree big enough to be slow on every machine — 4,000 files walk in well
    // under the threshold any such check could use — and would still be a
    // guess. "The list is not populated yet" cannot be satisfied by a blocking
    // implementation at any speed.
    check("the walk has not happened by the time the call returns",
          MainActor.assumeIsolated { m.files.isEmpty },
          "\(MainActor.assumeIsolated { m.files.count }) files already listed")
    check("…and an import is flagged as in flight",
          MainActor.assumeIsolated { m.isImporting })
    check("…and it came back promptly",
          returnedAfter < 0.25, String(format: "returned in %.3fs", returnedAfter))

    // Pump the main runloop until the completion lands, the way an app would.
    while result == nil, Date().timeIntervalSince(started) < 60 {
        pumped = true                    // the completion had not arrived yet
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    let total = Date().timeIntervalSince(started)

    check("the completion arrives", result != nil,
          String(format: "waited %.2fs", total))
    check("…on the main thread", onMain == true,
          "recorded \(String(describing: onMain)) inside the completion")
    check("…with every file in the tree",
          MainActor.assumeIsolated { m.files.count } == leafCount,
          "\(MainActor.assumeIsolated { m.files.count }) of \(leafCount)")
    check("…and the importing flag is cleared",
          MainActor.assumeIsolated { !m.isImporting })
    // Not `total > returnedAfter`: both come from the same base in straight-line
    // program order with three check() calls between them, so it is arithmetic,
    // not evidence, and a synchronous implementation satisfies it (T4). What a
    // synchronous implementation cannot do is make the pump loop run at all — it
    // would have delivered before the loop was reached.
    check("the completion had not arrived before the pump loop started",
          pumped,
          String(format: "returned in %.3fs, finished in %.2fs", returnedAfter, total))

    // Same answer as the blocking form, which is the thing that must not change.
    let n = MainActor.assumeIsolated { OCRModel() }
    _ = MainActor.assumeIsolated { n.add([root]) }
    check("the expanding form agrees with the synchronous one",
          MainActor.assumeIsolated { n.files.count } == leafCount,
          "\(MainActor.assumeIsolated { n.files.count })")
    resetPrefs()
}

// MARK: - The progress bar does not invent a number

// Extract Text is the default mode and has no intra-file progress to report —
// Runner.run is one blocking call. Reporting 0.5 pinned the bar at exactly half
// for the whole of a single-file run, which reads as a stall. A negative
// fraction is how a stage says "working, no idea", and the bar goes
// indeterminate instead of showing a number nobody measured.

print("\nindeterminate progress")

do {
    resetPrefs()
    let m = MainActor.assumeIsolated { OCRModel() }
    MainActor.assumeIsolated {
        check("no stages means not indeterminate — the bar is simply idle",
              !m.progressIsIndeterminate)

        m.stages[URL(fileURLWithPath: "/tmp/a.pdf")] = ("Recognising", -1)
        check("a stage that cannot measure itself makes the bar indeterminate",
              m.progressIsIndeterminate)
        check("…and contributes nothing to the fraction rather than counting as half",
              m.overallFraction == 0, "\(m.overallFraction)")

        m.stages[URL(fileURLWithPath: "/tmp/b.pdf")] = ("Writing pages", 0.5)
        check("one measurable stage is enough to show a real bar",
              !m.progressIsIndeterminate)
    }
    resetPrefs()
}

do {
    // A 255-file batch with 254 done and one broadsheet still grinding is 99.6%
    // complete, and 99.6% of a progress bar is indistinguishable from all of
    // it. A user watched exactly that for several minutes and concluded the app
    // had hung — the bar said finished while the heading said running, and the
    // bar is what you see from across the room (U25).
    resetPrefs()
    let m = MainActor.assumeIsolated { OCRModel() }
    MainActor.assumeIsolated {
        // `total` set directly rather than via add(): the pre-flight guard
        // refuses paths that do not exist, so adding 255 imaginary files left
        // total at 0 and the "< 0.98" check below passed against 0.0000 —
        // green, and testing nothing at all.
        let files = (1...255).map { URL(fileURLWithPath: "/tmp/big/f\($0).pdf") }
        m.total = 255
        m.isRunning = true
        m.completed = 254
        m.inFlight = [files[254]]
        m.stages[files[254]] = ("Recognising page 8 of 9", 0.9)
        let fraction = m.overallFraction
        check("a batch with one file left does not draw as a finished bar",
              fraction < 0.98, String(format: "%.4f", fraction))
        check("…but is still nearly finished, not reset to the middle",
              fraction > 0.5, String(format: "%.4f", fraction))

        // The results pane must keep following a running batch even after
        // something has failed. Pinning to the problem the moment one appears
        // means the other 252 files each yank the view back to the top.
        m.log.append(OCRModel.LogLine(text: "✗ f3.pdf", kind: .failure))
        m.outcomes[URL(fileURLWithPath: "/tmp/big/f3.pdf")] = .failed
        m.log.append(OCRModel.LogLine(text: "✓ f4.pdf", kind: .success))
        check("a live run keeps following the newest line despite a failure",
              m.logAnchor == .newest, String(describing: m.logAnchor))
        m.isRunning = false
        check("…and jumps to the problem once the run is over",
              m.logAnchor == .firstProblem, String(describing: m.logAnchor))
        check("…which is the failure, not whatever finished last",
              m.logFailuresFirst.first?.text == "✗ f3.pdf",
              m.logFailuresFirst.first?.text ?? "none")
        m.outcomes.removeAll()
        check("a clean finished run just shows the end of the log",
              m.logAnchor == .newest, String(describing: m.logAnchor))
        m.log.removeAll()
        m.isRunning = true

        // And the moment it really is done, it must reach the end — a bar that
        // never fills is its own kind of lie.
        m.completed = 255
        m.inFlight = []
        m.stages.removeAll()
        m.isRunning = false
        check("…and reaches the end once the batch is genuinely finished",
              m.overallFraction == 1, String(format: "%.4f", m.overallFraction))
    }
    resetPrefs()
}

// MARK: - Outline destinations follow the ink

// The pipeline republishes every page derotated into a box at the origin, so a
// coordinate taken from the source means something different on the output. A
// /Rotate 180 page's heading at (72, 700) ends up at (540, 92); on a /Rotate 90
// page y=700 falls off a 612-tall box entirely. Copied verbatim the bookmark
// lands hundreds of points away and nothing is out of range, so no guard fires.

print("\noutline destinations survive the page rewrite")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("destspace")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    /// A one-page PDF with a given box and rotation.
    func page(_ url: URL, box: CGRect, rotation: Int) -> PDFPage? {
        var b = box
        guard let ctx = CGContext(url as CFURL, mediaBox: &b, nil) else { return nil }
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(b)
        ctx.endPDFPage(); ctx.closePDF()
        guard let d = PDFDocument(url: url), let p = d.page(at: 0) else { return nil }
        if rotation != 0 {
            p.rotation = rotation
            d.write(to: url)
            return PDFDocument(url: url)?.page(at: 0)
        }
        return p
    }

    // An unrotated page at the origin is the identity case.
    if let p = page(dir.appendingPathComponent("r0.pdf"),
                    box: CGRect(x: 0, y: 0, width: 612, height: 792), rotation: 0) {
        let moved = SearchableWriter.mapToOutput(CGPoint(x: 72, y: 700), on: p)
        check("an unrotated page leaves a destination where it was",
              abs(moved.x - 72) < 1 && abs(moved.y - 700) < 1, "\(moved)")
    }

    // A quarter turn swaps the axes; y=700 on a 792-tall page must land inside
    // the 612-tall published box rather than off the top of it.
    if let p = page(dir.appendingPathComponent("r90.pdf"),
                    box: CGRect(x: 0, y: 0, width: 612, height: 792), rotation: 90) {
        let box = Flattener.fullBox(of: p)
        let moved = SearchableWriter.mapToOutput(CGPoint(x: 72, y: 700), on: p)
        check("a quarter-turned page's destination stays on the page",
              moved.x >= 0 && moved.x <= box.width && moved.y >= 0 && moved.y <= box.height,
              "\(moved) in \(Int(box.width))x\(Int(box.height))")
        check("…and actually moves, rather than being copied verbatim",
              abs(moved.y - 700) > 1, "\(moved)")
    }

    // A half turn puts a point near the top-left near the bottom-right.
    if let p = page(dir.appendingPathComponent("r180.pdf"),
                    box: CGRect(x: 0, y: 0, width: 612, height: 792), rotation: 180) {
        let moved = SearchableWriter.mapToOutput(CGPoint(x: 72, y: 700), on: p)
        check("a half-turned page's destination is mirrored, not copied",
              abs(moved.x - 540) < 2 && abs(moved.y - 92) < 2,
              "\(moved), wanted about (540, 92)")
    }

    // C21. A /FitH carries only y, and PDFKit reports the other member as
    // kPDFDestinationUnspecifiedValue. R19 counted 276 of those against 80
    // fully-specified across the corpus, so this is the common shape. The old
    // code substituted 0 for the missing member and kept `moved.y` — sound while
    // the transform is axis-aligned, wrong at 90 and 270 where the axes swap:
    // `moved.y` becomes a function of the substituted zero and the real
    // coordinate lands in `moved.x` and was thrown away.
    for rotation in [90, 270] {
        guard let p = page(dir.appendingPathComponent("fith\(rotation).pdf"),
                           box: CGRect(x: 0, y: 0, width: 612, height: 792),
                           rotation: rotation) else { continue }
        let placed = SearchableWriter.mapSingleAxis(700, isVertical: true, on: p)
        let full = SearchableWriter.mapToOutput(CGPoint(x: 0, y: 700), on: p)

        check("a /FitH on a \(rotation)-rotated page keeps a horizontal destination",
              placed.left != nil && placed.top == nil,
              "left=\(String(describing: placed.left)) top=\(String(describing: placed.top))")
        check("…carrying the coordinate the page actually turned it into",
              placed.left.map { abs($0 - full.x) < 0.5 } ?? false,
              "\(String(describing: placed.left)) against \(full.x)")
        // The old behaviour, stated so a regression is unmistakable: it kept
        // moved.y, which at 270 is the substituted zero — the foot of the page.
        check("…and not the value derived from the substituted zero",
              placed.top == nil,
              "kept top=\(String(describing: placed.top)), which is /XYZ null 0 null again")
    }

    // Unrotated, the same call must still behave exactly as before.
    if let p = page(dir.appendingPathComponent("fith0.pdf"),
                    box: CGRect(x: 0, y: 0, width: 612, height: 792), rotation: 0) {
        let placed = SearchableWriter.mapSingleAxis(700, isVertical: true, on: p)
        check("a /FitH on an unrotated page is still vertical",
              placed.top != nil && placed.left == nil,
              "left=\(String(describing: placed.left)) top=\(String(describing: placed.top))")
        check("…and lands where it did before",
              placed.top.map { abs($0 - 700) < 2 } ?? false,
              String(describing: placed.top))

        // And a /FitV — only x — stays horizontal on an unrotated page.
        let vertical = SearchableWriter.mapSingleAxis(72, isVertical: false, on: p)
        check("a /FitV on an unrotated page is still horizontal",
              vertical.left != nil && vertical.top == nil,
              "left=\(String(describing: vertical.left))")
    }

    // A media box with a non-zero origin is republished at the origin.
    if let p = page(dir.appendingPathComponent("shift.pdf"),
                    box: CGRect(x: 100, y: 100, width: 612, height: 792), rotation: 0) {
        let moved = SearchableWriter.mapToOutput(CGPoint(x: 172, y: 800), on: p)
        check("a shifted media box moves the destination to the new origin",
              abs(moved.x - 72) < 2 && abs(moved.y - 700) < 2,
              "\(moved), wanted about (72, 700)")
    }
    resetPrefs()
}

print("\na pathological outline cannot take the batch down")

do {
    // convert recurses once per level on a 512 KB worker stack — about 1,200
    // levels. A stack overflow is not catchable, so a PDF nested deeper than
    // that killed the process and every concurrent file's OCR with it.
    check("the depth limit is far below the stack and far above any real outline",
          SearchableWriter.maximumOutlineDepth >= 16
          && SearchableWriter.maximumOutlineDepth <= 128,
          "\(SearchableWriter.maximumOutlineDepth)")

    let dir = tmp.appendingPathComponent("deepoutline")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let src = dir.appendingPathComponent("deep.pdf")
    makeScannedPDF(at: src, lines: ["DEEP OUTLINE"])
    if let doc = PDFDocument(url: src), let p0 = doc.page(at: 0) {
        // 4,000 levels: past the limit, and past what a 512 KB stack survives.
        let root = PDFOutline()
        var node = root
        for i in 0..<4_000 {
            let child = PDFOutline()
            child.label = "level \(i)"
            child.destination = PDFDestination(page: p0, at: CGPoint(x: 0, y: 100))
            node.insertChild(child, at: 0)
            node = child
        }
        doc.outlineRoot = root
        doc.write(to: src)
    }
    // The point is that this returns at all.
    let items = SearchableWriter.readOutline(from: src)
    func depth(_ xs: [SearchableWriter.OutlineItem]) -> Int {
        xs.map { 1 + depth($0.children) }.max() ?? 0
    }
    check("reading a 4,000-level outline returns instead of overflowing the stack",
          depth(items) <= SearchableWriter.maximumOutlineDepth,
          "depth \(depth(items))")

    // R23. readOutline is only half of it. copyOutline is the same walk on the
    // Flate route and had neither bound — and the asymmetry hid itself, because
    // Model gates the call on `!readOutline(...).isEmpty` and readOutline
    // satisfies that for this very fixture by truncating it at 32. The
    // truncation that conceals the depth is what licensed the unbounded pass.
    //
    // In a child, on an OperationQueue worker: the 512 KB worker stack is what
    // makes the depth fatal, and a SIGBUS cannot be caught in-process.
    let composed = dir.appendingPathComponent("composed.pdf")
    makeScannedPDF(at: composed, lines: ["DEEP OUTLINE"])
    let outlined = dir.appendingPathComponent("outlined.pdf")

    check("the deep fixture still passes Model's gate, which is why this is reachable",
          !SearchableWriter.readOutline(from: src).isEmpty)

    let probe = Process()
    probe.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    probe.arguments = ["--probe-deep-outline", src.path, composed.path, outlined.path]
    probe.standardOutput = FileHandle.nullDevice
    probe.standardError = FileHandle.nullDevice
    var survived = false
    do {
        try probe.run()
        probe.waitUntilExit()
        survived = probe.terminationReason == .exit && probe.terminationStatus == 0
    } catch { survived = false }
    check("copying a 4,000-level outline does not kill the worker",
          survived,
          "terminationReason=\(probe.terminationReason.rawValue) status=\(probe.terminationStatus)")

    // Bounded, not abandoned: the outline is still copied, just truncated, and
    // the OCR it is attached to is never at risk.
    check("…and the outline still lands in the output, truncated",
          PDFDocument(url: outlined)?.outlineRoot?.numberOfChildren ?? 0 > 0,
          "no outline written")
}

// MARK: - Every destination form, not just the convenient one

// PDFKit collapses /Fit, /FitH and /XYZ null null null into a point whose members
// are kPDFDestinationUnspecifiedValue (3.4e38). Running that through a coordinate
// formatter clamped it to 0, so every one of those bookmarks was rewritten as
// /XYZ 0 0 — the *bottom* of the page. And an entry with no destination at all
// was given one pointing at page 1. Both are worse than losing the outline,
// because they look like they work.

print("\noutline destinations of every form")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("dests")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    var streams: [JBIG2.Page] = []
    for i in 0..<2 {
        let u = dir.appendingPathComponent("s\(i).jbig2")
        try? Data(repeating: 0x41, count: 64).write(to: u)
        streams.append(JBIG2.Page(stream: .jbig2(u), pixelWidth: 80, pixelHeight: 100,
                                  boxSize: CGSize(width: 300, height: 400)))
    }
    let unspecified = kPDFDestinationUnspecifiedValue
    let items: [SearchableWriter.OutlineItem] = [
        // An explicit /XYZ, the only form that used to survive.
        .init(title: "Explicit", pageIndex: 0, left: 20, top: 380, children: []),
        // What /Fit, /FitH and /XYZ-null all look like once PDFKit has read them.
        .init(title: "Unspecified", pageIndex: 1, left: nil, top: nil, children: []),
        // Half-specified, as /FitH would be if PDFKit reported the top.
        .init(title: "TopOnly", pageIndex: 1, left: nil, top: 350, children: []),
        // A pure label, as "Contents" and an issue masthead are in real files.
        .init(title: "Label only", pageIndex: nil, left: nil, top: nil, children: []),
    ]
    let out = dir.appendingPathComponent("dests.pdf")
    do { try JBIG2.assemble(streams, outline: items, to: out) }
    catch { check("assembled an outline of mixed destination forms", false, "\(error)") }

    let raw = String(decoding: (try? Data(contentsOf: out)) ?? Data(), as: UTF8.self)
    func entry(_ title: String) -> String {
        guard let r = raw.range(of: "/Title (\(title))") else { return "" }
        let line = raw[raw.range(of: "<<", options: .backwards, range: raw.startIndex..<r.lowerBound)!
                       .lowerBound...]
        return String(line.prefix(while: { $0 != "\n" }))
    }
    check("an explicit point is written as-is",
          entry("Explicit").contains("/XYZ 20.0000 380.0000 null"), entry("Explicit"))
    check("an unspecified destination becomes /XYZ null null, not 0 0",
          entry("Unspecified").contains("/XYZ null null null"), entry("Unspecified"))
    check("a half-specified destination keeps the half it has",
          entry("TopOnly").contains("/XYZ null 350.0000 null"), entry("TopOnly"))
    check("an entry with no destination is given none",
          !entry("Label only").contains("/Dest"), entry("Label only"))

    // And the whole thing is still a valid PDF that PDFKit can read back.
    let doc = PDFDocument(url: out)
    let root = doc?.outlineRoot
    check("all four entries survive", (root?.numberOfChildren ?? 0) == 4,
          "\(root?.numberOfChildren ?? -1)")
    check("the label-only entry has no destination",
          root?.child(at: 3)?.destination == nil)

    // The unspecified one must NOT have been turned into a jump to the page foot.
    if let dst = root?.child(at: 1)?.destination {
        let y = dst.point.y
        check("the unspecified destination did not become the foot of the page",
              y == unspecified || y > 1, String(format: "y=%.1f", y))
    } else {
        check("the unspecified destination did not become the foot of the page", true)
    }
    resetPrefs()
}

// MARK: - Backend robustness: leaks, unbounded waits, self-overwriting batches

print("\nthe backend does not leak or wedge")

do {
    resetPrefs()

    // Every adoption must be paired. The JBIG2 route launches one child per
    // page and never released them, so a 600-page book held 600 live Processes
    // and their pipe descriptors until the batch ended.
    let control = RunControl()
    for _ in 0..<50 {
        control.adopting { register in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/echo")
            p.arguments = ["x"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            register(p)
            p.waitUntilExit()
        }
    }
    check("adopting releases every child it takes", control.adoptedCount == 0,
          "\(control.adoptedCount) still held after 50 children")
    // Retire it before the registry checks below, which ask a process-wide
    // question and would otherwise see this one still counting as live.
    control.finished()

    // Quitting mid-run used to orphan the OCR children: a child of a process
    // that exits is reparented to launchd, not killed. The app delegate asks
    // RunControl whether anything is live and cancels it on the way out, so the
    // registry has to be accurate — including after a control is discarded.
    do {
        // Note: `RunControl.isAnyRunning` is a process-wide question, and this
        // suite leaves controls alive in other blocks, so asserting on it here
        // would be testing the rest of the file. Assert the properties the app
        // delegate actually depends on instead.
        var scoped: RunControl? = RunControl()
        weak var observed = scoped
        check("a fresh control counts as live", RunControl.isAnyRunning)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 20"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        scoped?.adopt(p)
        RunControl.cancelAll()
        _ = Runner.wait(for: p, upTo: 3)
        check("cancelAll reaches a child of a live batch", !p.isRunning)

        check("a control is live until it says otherwise", scoped?.isFinished == false)
        scoped?.finished()
        check("…and reports finished once the batch ends", scoped?.isFinished == true)

        // The registry must be weak, or every batch's control — and the Process
        // objects it holds — would live for the life of the app. A strong
        // registry also meant deinit never ran, so entries never left.
        scoped = nil
        check("the registry holds controls weakly, so a finished batch is freed",
              observed == nil)
    }

    // A child that ignores SIGTERM used to be able to wedge an Extract Text
    // worker, and this measured that `Runner.run` still returned promptly. That
    // path is gone: Extract Text calls Vision in process. `Runner.stop` and its
    // process-group escalation survive for jbig2 and qpdf and are checked below.

    // A failing run must never report a bare empty message. Driven through the
    // recogniser now rather than through a subprocess exiting non-zero: a file
    // that is not a PDF and not an image has to come back with something a user
    // can read.
    let unreadable = tmp.appendingPathComponent("not-a-document.pdf")
    try? Data("plain text".utf8).write(to: unreadable)
    let failed = extractText(unreadable, to: nil)
    check("a failing run says something", !failed.succeeded && !failed.message.isEmpty,
          failed.message)

}

// MARK: - A page the recogniser skipped is caught

// Nothing compared the recogniser's page records to the document's page count.
// A page mac-ocr never reported composes as a page with no text, passes
// `produced == expected`, and publishes as a success — a silently untextable
// page in the middle of a book.

print("\na skipped page is not mistaken for a blank one")

do {
    resetPrefs()
    func obs(_ t: String) -> SearchableWriter.Observation {
        .init(boundingBox: .init(x: 0.1, y: 0.1, width: 0.5, height: 0.02),
              text: t, confidence: 1)
    }
    // A blank page is still *reported*, with an empty observations array —
    // verified against mac-ocr, which emits three records for a 3-page document
    // whose middle page is blank. So an empty array is fine; a missing key is not.
    let blankMiddle: [Int: [SearchableWriter.Observation]] =
        [1: [obs("first")], 2: [], 3: [obs("third")]]
    check("a legitimately blank page is not reported as missing",
          SearchableWriter.missingPages(in: blankMiddle, of: 3).isEmpty,
          "\(SearchableWriter.missingPages(in: blankMiddle, of: 3))")

    let skipped: [Int: [SearchableWriter.Observation]] =
        [1: [obs("first")], 3: [obs("third")]]
    check("a page the recogniser never reported is caught",
          SearchableWriter.missingPages(in: skipped, of: 3) == [2],
          "\(SearchableWriter.missingPages(in: skipped, of: 3))")

    check("a truncated run is caught, not just a hole",
          SearchableWriter.missingPages(in: [1: [obs("only")]], of: 4) == [2, 3, 4],
          "\(SearchableWriter.missingPages(in: [1: [obs("only")]], of: 4))")
    check("an unknown page count reports nothing rather than guessing",
          SearchableWriter.missingPages(in: [:], of: 0).isEmpty)

    // And end to end: a real document with a genuinely blank middle page must
    // still succeed, or the new guard would be worse than the bug.
    let dir = tmp.appendingPathComponent("blankpage")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let src = dir.appendingPathComponent("blanky.pdf")
    var pbox = CGRect(x: 0, y: 0, width: 612, height: 792)
    if let ctx = CGContext(src as CFURL, mediaBox: &pbox, nil) {
        for i in 0..<3 {
            if let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 1224, pixelsHigh: 1584,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                NSColor.white.setFill()
                NSRect(x: 0, y: 0, width: 1224, height: 1584).fill()
                if i != 1 {
                    ("PAGE \(i + 1) HAS WORDS" as NSString).draw(
                        at: NSPoint(x: 150, y: 800),
                        withAttributes: [.font: NSFont(name: "Helvetica", size: 60)
                                         ?? NSFont.systemFont(ofSize: 60),
                                         .foregroundColor: NSColor.black])
                }
                NSGraphicsContext.current?.flushGraphics()
                NSGraphicsContext.restoreGraphicsState()
                if let cg = rep.cgImage {
                    ctx.beginPDFPage(nil); ctx.draw(cg, in: pbox); ctx.endPDFPage()
                }
            }
        }
        ctx.closePDF()
    }
    var outcome: Runner.Result.Outcome?
    var detail = ""
    OCRModel.makeSearchablePDF(
        file: src, output: dir.appendingPathComponent("blanky.ocr.pdf"),
        rebuild: true, rebuildMode: .auto, password: nil,
        control: RunControl(), progress: { _, _ in },
        report: { o, m in outcome = o; detail = m })
    check("a document with a genuinely blank page still succeeds",
          outcome == .succeeded, detail)
    resetPrefs()
}

// MARK: - Wrapping a dropped image

// wrapImage used the horizontal DPI for both axes, so an image recording
// different horizontal and vertical resolution (200x100 is a standard fax mode)
// became a page squashed by the ratio between them. And it never applied EXIF
// orientation — CGImageSourceCreateImageAtIndex hands back the stored pixels —
// so a phone photo shot in portrait was wrapped as a landscape page.

print("\nwrapping a dropped image")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("wrap")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    /// A TIFF, because it can carry per-axis resolution and an orientation tag.
    func writeImage(_ url: URL, w: Int, h: Int, dpiX: Double, dpiY: Double,
                    orientation: UInt32) {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let cg = rep.cgImage else { return }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.tiff" as CFString, 1, nil) else { return }
        let props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpiX,
            kCGImagePropertyDPIHeight: dpiY,
            kCGImagePropertyOrientation: orientation,
        ]
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    // 400x400 pixels at 200x100 dpi is 2in wide and 4in tall: 144 x 288 pt.
    let fax = dir.appendingPathComponent("fax.tiff")
    writeImage(fax, w: 400, h: 400, dpiX: 200, dpiY: 100, orientation: 1)
    if let wrapped = Flattener.wrapImage(fax, into: dir),
       let box = PDFDocument(url: wrapped)?.page(at: 0)?.bounds(for: .mediaBox) {
        check("per-axis resolution is honoured, not squashed to the horizontal one",
              abs(box.width - 144) < 2 && abs(box.height - 288) < 2,
              "\(Int(box.width))x\(Int(box.height)) pt, wanted 144x288")
    } else {
        check("per-axis resolution is honoured, not squashed to the horizontal one",
              false, "wrapImage returned nil")
    }

    // A landscape image tagged as needing a quarter turn must wrap as portrait.
    // 600x300 at 72 dpi is 600x300 pt unrotated, 300x600 pt once turned.
    for (tag, orientation) in [("6 (90° CW)", UInt32(6)), ("8 (90° CCW)", UInt32(8))] {
        let photo = dir.appendingPathComponent("photo\(orientation).tiff")
        writeImage(photo, w: 600, h: 300, dpiX: 72, dpiY: 72, orientation: orientation)
        if let wrapped = Flattener.wrapImage(photo, into: dir),
           let box = PDFDocument(url: wrapped)?.page(at: 0)?.bounds(for: .mediaBox) {
            check("EXIF orientation \(tag) turns the page upright",
                  abs(box.width - 300) < 2 && abs(box.height - 600) < 2,
                  "\(Int(box.width))x\(Int(box.height)) pt, wanted 300x600")
        } else {
            check("EXIF orientation \(tag) turns the page upright", false, "nil")
        }
    }

    // And an untagged image is unchanged.
    let plain = dir.appendingPathComponent("plain.tiff")
    writeImage(plain, w: 600, h: 300, dpiX: 72, dpiY: 72, orientation: 1)
    if let wrapped = Flattener.wrapImage(plain, into: dir),
       let box = PDFDocument(url: wrapped)?.page(at: 0)?.bounds(for: .mediaBox) {
        check("an unrotated image is left alone",
              abs(box.width - 600) < 2 && abs(box.height - 300) < 2,
              "\(Int(box.width))x\(Int(box.height)) pt, wanted 600x300")
    }

    // A multi-page TIFF is what every sheet-fed archival scanner produces.
    // Reading only image 0 reduced a whole document to its cover page and
    // reported success, because one page in was one page out.
    let multi = dir.appendingPathComponent("multi.tiff")
    if let dest = CGImageDestinationCreateWithURL(
        multi as CFURL, "public.tiff" as CFString, 3, nil) {
        // Deliberately differing sizes, so the per-page box is exercised too.
        for (i, size) in [(600, 800), (500, 700), (640, 900)].enumerated() {
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: size.0, pixelsHigh: size.1,
                bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let cg = rep.cgImage else { continue }
            _ = i
            CGImageDestinationAddImage(dest, cg, [kCGImagePropertyDPIWidth: 72.0,
                                                  kCGImagePropertyDPIHeight: 72.0] as CFDictionary)
        }
        _ = CGImageDestinationFinalize(dest)
    }
    if let wrapped = Flattener.wrapImage(multi, into: dir),
       let doc = PDFDocument(url: wrapped) {
        check("every sheet of a multi-page TIFF becomes a page",
              doc.pageCount == 3, "\(doc.pageCount) page(s), wanted 3")
        let widths = (0..<doc.pageCount).compactMap {
            doc.page(at: $0).map { Int($0.bounds(for: .mediaBox).width) }
        }
        check("…each keeping its own size, not sheet 1's",
              widths == [600, 500, 640], "\(widths)")
    } else {
        check("every sheet of a multi-page TIFF becomes a page", false, "wrapImage nil")
    }
    resetPrefs()
}

// MARK: - Small correctness fixes

print("\nopen-when-finished picks a folder in every configuration")

do {
    // R7 was recorded as fixed but was not: the guard was `let folder =
    // destination`, and destination is nil precisely when "beside each
    // original" is on — the configuration the setting most obviously covers.
    let inputs = [URL(fileURLWithPath: "/Users/someone/Scans/a.pdf"),
                  URL(fileURLWithPath: "/Users/someone/Other/b.pdf")]
    let chosen = URL(fileURLWithPath: "/Users/someone/Out")
    check("an explicit output folder is used as-is",
          OCRModel.folderToReveal(destination: chosen, inputs: inputs) == chosen,
          "\(String(describing: OCRModel.folderToReveal(destination: chosen, inputs: inputs)))")
    check("beside-each-original falls back to the first input's folder",
          OCRModel.folderToReveal(destination: nil, inputs: inputs)?.path
              == "/Users/someone/Scans",
          "\(String(describing: OCRModel.folderToReveal(destination: nil, inputs: inputs)))")
    check("nothing to open when there were no inputs",
          OCRModel.folderToReveal(destination: nil, inputs: []) == nil)
}

print("\nassembling no pages is refused")

do {
    // assemble([]) wrote a /Count 0 page tree that qpdf --check rejects, and
    // reported success. Unreachable from makeSearchablePDF, but "returns a file
    // nobody can open, and calls it a success" is the shape invariant 1 forbids.
    let empty = tmp.appendingPathComponent("empty-assemble.pdf")
    var threw = false
    do { try JBIG2.assemble([], to: empty) } catch { threw = true }
    check("JBIG2.assemble([]) throws instead of writing an invalid PDF", threw)
    check("…and writes no file at all",
          !FileManager.default.fileExists(atPath: empty.path))
}

// MARK: - Crop box

// mac-ocr renders the CROP box, not the media box: given MediaBox 612x792 and
// CropBox (100,100)-(412,500) it reports a 312x400 render and recognises only
// what is inside the crop. So Vision's normalised boxes are relative to the crop
// box, and mapping them onto the media box offset and rescaled every one of them.
// Guards that the whole geometry chain agrees on the crop box. See BUGS.md C7.

print("\ncrop box differing from media box")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("cropbox")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Image-only, so mac-ocr must OCR rather than lift an existing text layer.
    let mediaW = 612.0, mediaH = 792.0
    let crop = CGRect(x: 100, y: 100, width: 312, height: 400)
    let inkX = 150.0, inkY = 300.0          // inside the crop, in media space
    let scale = 2.0
    let full = dir.appendingPathComponent("full.pdf")
    if let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(mediaW * scale), pixelsHigh: Int(mediaH * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: mediaW * scale, height: mediaH * scale).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Helvetica", size: 40 * scale) ?? NSFont.systemFont(ofSize: 80),
            .foregroundColor: NSColor.black,
        ]
        // One word inside the crop, two outside it.
        ("ALPHA"   as NSString).draw(at: NSPoint(x: inkX * scale, y: 700 * scale), withAttributes: attrs)
        ("BRAVO"   as NSString).draw(at: NSPoint(x: inkX * scale, y: inkY * scale), withAttributes: attrs)
        ("CHARLIE" as NSString).draw(at: NSPoint(x: inkX * scale, y:  50 * scale), withAttributes: attrs)
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        var box = CGRect(x: 0, y: 0, width: mediaW, height: mediaH)
        if let cg = rep.cgImage, let ctx = CGContext(full as CFURL, mediaBox: &box, nil) {
            ctx.beginPDFPage(nil)
            ctx.draw(cg, in: box)
            ctx.endPDFPage()
            ctx.closePDF()
        }
    }

    let cropped = dir.appendingPathComponent("cropped.pdf")
    if let doc = PDFDocument(url: full), let page = doc.page(at: 0) {
        page.setBounds(crop, for: .cropBox)
        doc.write(to: cropped)
    }

    guard let made = PDFDocument(url: cropped), let madePage = made.page(at: 0) else {
        check("built a PDF with a crop box", false); exit(1)
    }
    check("the fixture's boxes really differ",
          madePage.bounds(for: .mediaBox) != madePage.bounds(for: .cropBox),
          "media \(madePage.bounds(for: .mediaBox)) crop \(madePage.bounds(for: .cropBox))")

    check("displayBox reports the crop box, not the media box",
          Flattener.displayBox(of: madePage).size == crop.size,
          "\(Flattener.displayBox(of: madePage).size) vs \(crop.size)")

    // The other half of the split: the rebuild must keep the whole sheet, or it
    // silently discards whatever the crop excluded (invariant 1). Cropping the
    // rebuild also measurably hurt line separation on a real corpus document.
    check("fullBox reports the media box, so the rebuild keeps the whole sheet",
          Flattener.fullBox(of: madePage).size == CGSize(width: mediaW, height: mediaH),
          "\(Flattener.fullBox(of: madePage).size) vs \(mediaW)x\(mediaH)")

    let rebuilt = dir.appendingPathComponent("rebuilt.pdf")
    _ = try? Flattener.flatten(cropped, to: rebuilt, mode: .grayscale)
    if let rd = PDFDocument(url: rebuilt), let rp = rd.page(at: 0) {
        check("the rebuild is the full sheet, not the crop",
              abs(rp.bounds(for: .mediaBox).width - mediaW) < 1
              && abs(rp.bounds(for: .mediaBox).height - mediaH) < 1,
              "\(rp.bounds(for: .mediaBox))")
        // Content outside the crop must survive the rebuild.
        let seen = observations(of: rebuilt).values.flatMap { $0 }
            .map(\.text).joined(separator: " ")
        check("words outside the crop survive the rebuild",
              seen.contains("ALPHA") && seen.contains("CHARLIE"),
              "ALPHA \(seen.contains("ALPHA")), CHARLIE \(seen.contains("CHARLIE"))")
    } else {
        check("the rebuild is the full sheet, not the crop", false, "no rebuilt PDF")
    }

    // Recognise the original (the non-rebuild path, which is where this bites)
    // and compose the layer straight onto it.
    let json = dir.appendingPathComponent("obs.json")
    let out = dir.appendingPathComponent("out.pdf")
    if case let byPage = observations(of: cropped), !byPage.isEmpty {
        try? SearchableWriter.compose(visible: cropped, observations: byPage, to: out)
    }

    guard let result = PDFDocument(url: out), let resultPage = result.page(at: 0) else {
        check("composed a layer over the cropped page", false); exit(1)
    }
    // The published page keeps the WHOLE SHEET. Publishing at the crop box
    // would place the text correctly but silently drop everything the crop
    // excludes — on this path `visible` is the user's own file, so that is their
    // content vanishing from their copy with the run reported as a success.
    check("the composed page is the full media size, not the crop",
          abs(resultPage.bounds(for: .mediaBox).width - mediaW) < 1
          && abs(resultPage.bounds(for: .mediaBox).height - mediaH) < 1,
          "\(resultPage.bounds(for: .mediaBox))")

    // Keeping the whole sheet must not un-trim the document. Without a crop box
    // on the output, a page the original displayed at 312x400 would display at
    // 612x792 — revealing margin notes the viewer had been hiding, which the
    // recogniser never saw and the text layer therefore does not cover.
    let outCrop = resultPage.bounds(for: .cropBox)
    check("…and it still displays as the crop, so the copy looks like the original",
          abs(outCrop.width - crop.width) < 1 && abs(outCrop.height - crop.height) < 1,
          "displays \(Int(outCrop.width))x\(Int(outCrop.height)), original showed "
          + "\(Int(crop.width))x\(Int(crop.height))")
    // Not just the boxes — the ink. The words outside the crop must still be in
    // the file even though the crop hides them, exactly as in the original.
    //
    // Re-OCRing the copy directly cannot show this: mac-ocr renders the crop box
    // (that is C7), so it would report only what is displayed and prove nothing
    // either way. Lift the trim off a throwaway duplicate first, then OCR — if
    // the marks were dropped at compose time, they are not there to find.
    let untrimmed = dir.appendingPathComponent("untrimmed.pdf")
    if let dup = PDFDocument(url: out), let dp = dup.page(at: 0) {
        dp.setBounds(dp.bounds(for: .mediaBox), for: .cropBox)
        dup.write(to: untrimmed)
    }
    let rendered = observations(of: untrimmed).values.flatMap { $0 }
        .map(\.text).joined(separator: " ")
    check("ink outside the crop is retained in the file, merely not displayed",
          rendered.contains("ALPHA") && rendered.contains("CHARLIE"),
          "ALPHA \(rendered.contains("ALPHA")), CHARLIE \(rendered.contains("CHARLIE"))")

    let text = embeddedText(of: out)
    check("the word inside the crop is in the layer", text.contains("BRAVO"), text)

    // And it still lands on the ink. Observations are normalised to the crop, so
    // they have to be placed inside the crop's sub-rectangle of the page — BRAVO's
    // ink is at media (150, 300), which is where the run must be, NOT at the
    // crop-relative (50, 200) it would land at if the origin were dropped.
    let found = result.findString("BRAVO", withOptions: [.caseInsensitive]).first
    let bounds = found?.bounds(for: resultPage) ?? .zero
    check("the text layer lands on the ink in full-page coordinates",
          bounds.width > 0 && abs(bounds.minX - inkX) < 12
          && abs(bounds.minY - inkY) < 22,
          "run at \(bounds), ink at x=\(inkX) y=\(inkY)")

    // cropRegion must place the crop where it really is on the page.
    let region = SearchableWriter.cropRegion(
        of: madePage, on: CGRect(x: 0, y: 0, width: mediaW, height: mediaH))
    check("cropRegion reports the crop's true position on the sheet",
          abs(region.minX - crop.minX) < 1 && abs(region.minY - crop.minY) < 1
          && abs(region.width - crop.width) < 1 && abs(region.height - crop.height) < 1,
          "\(region) vs \(crop)")

    // A crop box on a ROTATED page is the case the arithmetic is most likely to
    // get wrong, and it is why cropRegion goes through getDrawingTransform
    // rather than composing the quarter turn by hand.
    //
    // The rotation has to be written to disk and re-read, not just set on an
    // in-memory PDFPage. `cropRegion` asks CoreGraphics for the transform, and
    // the CGPDFPage's /Rotate does not follow a PDFKit-side `page.rotation`
    // assignment — so an in-memory mutation makes the two disagree and the
    // measurement is of the test, not the code. Every production path reads its
    // pages from a file, where they always agree.
    for turn in [90, 180, 270] {
        guard let rotDoc = PDFDocument(url: cropped), let mutable = rotDoc.page(at: 0)
        else { continue }
        mutable.rotation = turn
        let turnedURL = dir.appendingPathComponent("turn\(turn).pdf")
        guard rotDoc.write(to: turnedURL),
              let onDisk = PDFDocument(url: turnedURL), let rp = onDisk.page(at: 0)
        else { check("wrote the \(turn)° fixture", false); continue }
        let page = Flattener.fullBox(of: rp)          // dimensions swap at 90/270
        let r = SearchableWriter.cropRegion(of: rp, on: page)
        // Whatever the turn, the region must stay inside the page, keep the
        // crop's area, and have the crop's dimensions in whichever orientation
        // the page now displays.
        let swapped = (turn == 90 || turn == 270)
        let wantW = swapped ? crop.height : crop.width
        let wantH = swapped ? crop.width : crop.height
        let inside = page.contains(r.insetBy(dx: 0.5, dy: 0.5))
        check("cropRegion survives a \(turn)° rotation",
              inside && abs(r.width - wantW) < 1.5 && abs(r.height - wantH) < 1.5,
              "page \(Int(page.width))x\(Int(page.height)), region \(r), "
              + "wanted \(Int(wantW))x\(Int(wantH)), inside=\(inside)")
    }
    resetPrefs()
}

// MARK: - Invariant 5: differing page sizes AND a rotated page, end to end

// CLAUDE.md invariant 5 requires a fixture with at least two pages of differing
// size and at least one rotated page, because a single-page or uniform fixture
// is structurally blind to the "every page inherits page 1's box" class of bug —
// which has bitten both PDF writers, weeks apart.
//
// No fixture met it. `both.pdf` has two sizes but no rotation and only ever
// reaches compose(drawImages: false); `rotated.pdf` is one page. So neither
// Flattener.flatten nor JBIG2.assemble had ever seen a document with both
// properties. This runs one through the real makeSearchablePDF.

/// An image-only page of a given size carrying one legible line.
///
/// File scope rather than block scope because two fixtures need it: this block's
/// and the non-rebuild block's. The non-rebuild fixture used `makeScannedPDF`,
/// which hard-codes 612×792, and so claimed "two pages of differing size" while
/// building two identical ones (A11.4). One helper means the two fixtures cannot
/// drift apart in what they mean by a different size.
func mixedPage(_ url: URL, w: CGFloat, h: CGFloat, text: String) {
    let px = 2.0
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(w * px), pixelsHigh: Int(h * px),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: w * px, height: h * px).fill()
    (text as NSString).draw(at: NSPoint(x: 40 * px, y: h * px / 2), withAttributes: [
        .font: NSFont(name: "Helvetica-Bold", size: 36 * px)
            ?? NSFont.systemFont(ofSize: 72),
        .foregroundColor: NSColor.black])
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    var box = CGRect(x: 0, y: 0, width: w, height: h)
    guard let cg = rep.cgImage, let ctx = CGContext(url as CFURL, mediaBox: &box, nil)
    else { return }
    ctx.beginPDFPage(nil); ctx.draw(cg, in: box); ctx.endPDFPage(); ctx.closePDF()
}

print("\nmixed page sizes and rotation through the whole pipeline")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("mixed")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Three pages, three different boxes, the last one quarter-turned.
    //
    // Page 3 is 700x540 so that its *displayed* box (540x700, dimensions swapped
    // by the rotation) differs from both of the others. An obvious choice like
    // 792x612 would display as 612x792 — exactly page 1's box — and a page that
    // wrongly inherited page 1's size would then look correct.
    let sizes: [(CGFloat, CGFloat, String)] = [
        (612, 792, "PAGE ONE LETTER"),
        (456, 710, "PAGE TWO NARROW"),
        (700, 540, "PAGE THREE WIDE"),
    ]
    let mixed = PDFDocument()
    for (i, s) in sizes.enumerated() {
        let one = dir.appendingPathComponent("p\(i).pdf")
        mixedPage(one, w: s.0, h: s.1, text: s.2)
        if let d = PDFDocument(url: one), let p = d.page(at: 0) {
            if i == 2 { p.rotation = 270 }         // and one rotated page
            mixed.insert(p, at: mixed.pageCount)
        }
    }
    let src = dir.appendingPathComponent("mixed.pdf")
    mixed.write(to: src)

    guard let sd = PDFDocument(url: src), sd.pageCount == 3 else {
        check("built the mixed fixture", false); exit(1)
    }
    let srcBoxes = (0..<3).compactMap { sd.page(at: $0).map { Flattener.displayBox(of: $0) } }
    check("the fixture has three different display boxes",
          Set(srcBoxes.map { "\(Int($0.width))x\(Int($0.height))" }).count == 3,
          "\(srcBoxes.map { "\(Int($0.width))x\(Int($0.height))" })")
    check("…and one of them is rotated",
          (0..<3).contains { sd.page(at: $0)?.rotation == 270 })

    // The real function, not a replica of the pipeline.
    let out = dir.appendingPathComponent("mixed.ocr.pdf")
    var outcome: Runner.Result.Outcome?
    var detail = ""
    OCRModel.makeSearchablePDF(
        file: src, output: out,
        rebuild: true, rebuildMode: .auto, password: nil,
        control: RunControl(), progress: { _, _ in },
        report: { o, m in outcome = o; detail = m })

    check("the mixed document succeeds", outcome == .succeeded, detail)
    guard let od = PDFDocument(url: out) else {
        check("the mixed document was written", false, detail); exit(1)
    }
    check("every page survives", od.pageCount == 3, "\(od.pageCount)")

    // The bug this fixture exists to catch: pages inheriting page 1's box.
    var boxesMatch = true
    var report: [String] = []
    for i in 0..<min(od.pageCount, 3) {
        let want = srcBoxes[i]
        let got = od.page(at: i).map { Flattener.displayBox(of: $0) } ?? .zero
        report.append("p\(i + 1) want \(Int(want.width))x\(Int(want.height))"
                      + " got \(Int(got.width))x\(Int(got.height))")
        if abs(got.width - want.width) > 2 || abs(got.height - want.height) > 2 {
            boxesMatch = false
        }
    }
    check("each page keeps its own size, not page 1's", boxesMatch,
          report.joined(separator: "; "))

    // And the text really is on every page, including the rotated one.
    let text = embeddedText(of: out).uppercased()
    check("page 1's text is in the layer", text.contains("LETTER"), String(text.prefix(160)))
    check("page 2's text is in the layer", text.contains("NARROW"), String(text.prefix(160)))
    check("the rotated page's text is in the layer", text.contains("WIDE"),
          String(text.prefix(160)))

    // The assertion that actually catches this bug class, and the reasoning
    // behind its shape — because the obvious version does not work.
    //
    // A page whose text layer carries page 1's box is NOT visible as a wrong
    // published page size: on the JBIG2 route the boxes come from
    // JBIG2.assemble, which reads the source geometry and is unaffected. Nor is
    // it visible as missing text. It shows up as *drift* — qpdf --overlay scales
    // the mis-sized layer to fit the image page, moving every run on it.
    //
    // Comparing each run against an absolute expected position does not
    // discriminate either: there is a constant ~20 pt offset between a drawn
    // baseline and the run's midY, so an absolute tolerance loose enough to
    // accept a correct build also accepts a broken one. Measured, reverting
    // kCGPDFContextMediaBox to an NSValue:
    //
    //     page 1 offset  +20.0 -> +20.0   (page 1 is never wrong: it IS page 1)
    //     page 2 offset  +19.0 -> -15.6
    //
    // So compare the pages to *each other*. Both lines were drawn at half their
    // own page's height, so in a correct build their offsets agree within a
    // point; any per-page geometry error makes them diverge — here by 35 pt.
    func offsetFromDrawnPosition(_ i: Int, _ word: String) -> Double? {
        guard let p = od.page(at: i),
              let found = od.findString(word, withOptions: [.caseInsensitive])
                  .first(where: { $0.pages.contains(p) }) else { return nil }
        return found.bounds(for: p).midY - Flattener.displayBox(of: p).height / 2
    }
    // Page 3 is excluded on purpose: it was drawn before being rotated, so its
    // line is not at half height in display space and is not comparable.
    if let first = offsetFromDrawnPosition(0, "LETTER"),
       let second = offsetFromDrawnPosition(1, "NARROW") {
        check("a differently-sized page's run is placed like page 1's, not drifted",
              abs(second - first) < 8,
              String(format: "page 1 offset %+.1f, page 2 offset %+.1f, diverge %.1f pt",
                     first, second, abs(second - first)))
    } else {
        check("both runs were locatable", false)
    }
    resetPrefs()
}

// MARK: - Not publishing partial results

// Cancelling used to leave a PDF that opened perfectly but was missing its later
// pages, written straight over any previous good output. The result is now built
// in a scratch directory and only moved into place once its page count matches.
//
// This block had three checks that carried no information, and CLAUDE.md
// invariant 2 therefore had no working test at all — `REVIEW-2026-08-14.md`
// A11.1, the tenth un-failable check in `BUGS.md`:
//
//   * `"the truncated file is not at the destination"` asserted that
//     `published.pdf` did not exist. **`published.pdf` occurred exactly twice in
//     the 8,600-line file: its declaration and that check.** Nothing ever wrote
//     it, and the block never called `makeSearchablePDF` or `publish` at all.
//     Deleting the page-count gate the check claimed to cover left the suite
//     **862/862, exit 0** — so the mechanism CLAUDE.md names verbatim could be
//     removed with a green suite.
//   * `"and it stays intact on disk"` restated `goodPages == 3` from the line
//     above, and its comment said "a previous good output must survive a later
//     failed run" when **no run happened between writing the file and checking
//     it**.
//
// What replaces them drives the real functions, with a real good file at the
// destination, and goes red when either gate is removed.

print("\npartial results are never published")

do {
    resetPrefs()
    let outDir = tmp.appendingPathComponent("publish-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outDir) }

    // A truncated build is detectable purely from the page count.
    let src = outDir.appendingPathComponent("pub-src.pdf")
    let three = PDFDocument()
    for i in 1...3 {
        let one = outDir.appendingPathComponent("pub-\(i).pdf")
        makeScannedPDF(at: one, lines: ["page \(i) of the source"])
        if let d = PDFDocument(url: one), let p = d.page(at: 0) {
            three.insert(p, at: three.pageCount)
        }
    }
    three.write(to: src)
    check("the source has three pages", PDFDocument(url: src)?.pageCount == 3)

    // Compose with cancellation already set: the writer stops early.
    let staged = outDir.appendingPathComponent("staged.pdf")
    let byPage = observations(of: src)
    try? SearchableWriter.compose(visible: src, observations: byPage, to: staged,
                                  isCancelled: { true })
    let truncated = PDFDocument(url: staged)?.pageCount ?? -1
    check("a cancelled compose really does truncate", truncated < 3, "\(truncated) pages")

    // The refusal itself, and its wording. A11.8: neither of
    // `makeSearchablePDF`'s refusal messages was asserted anywhere, so the
    // wiring from predicate to reported text was untested in both directions.
    let refusal = OCRModel.incompleteRefusal(staged, expecting: 3)
    check("a short staged file is refused", refusal != nil, "got nil")
    check("…and the refusal says nothing was written",
          refusal?.contains("nothing was written") == true, refusal ?? "nil")
    check("…and names both counts",
          refusal?.contains("\(truncated) pages") == true
            && refusal?.contains("source has 3") == true, refusal ?? "nil")
    check("a complete staged file is not refused",
          OCRModel.incompleteRefusal(src, expecting: 3) == nil,
          OCRModel.incompleteRefusal(src, expecting: 3) ?? "")

    // THE CHECK A11.1 IS ABOUT. A good previous output at the destination, a
    // short file offered for publication, and the good file must still be there
    // afterwards — byte for byte, not merely present with the right page count.
    //
    // Byte comparison on purpose: the truncated file also opens, and it also has
    // "some pages". `fileExists` and a page count are both satisfied by the
    // destroyed state this invariant exists to prevent.
    let keeper = outDir.appendingPathComponent("keeper.pdf")
    try? SearchableWriter.compose(visible: src, observations: byPage, to: keeper)
    let keeperBefore = try? Data(contentsOf: keeper)
    check("the previous good output has every page",
          PDFDocument(url: keeper)?.pageCount == 3,
          "\(PDFDocument(url: keeper)?.pageCount ?? -1)")

    var refused = false
    do {
        try OCRModel.publishVerified(staged, expecting: 3, to: keeper)
    } catch {
        refused = true
        check("…and the refusal reaches the caller as the same sentence",
              error.localizedDescription.contains("nothing was written"),
              error.localizedDescription)
    }
    check("publishing a short result over a good one is refused", refused,
          "publishVerified returned without throwing")
    let keeperAfter = try? Data(contentsOf: keeper)
    check("…and the previous good output is byte-for-byte intact",
          keeperBefore != nil && keeperBefore == keeperAfter,
          "\(keeperBefore?.count ?? -1) bytes before, \(keeperAfter?.count ?? -1) after")
    check("…and the truncated file never moved to the destination",
          FileManager.default.fileExists(atPath: staged.path))

    // The inverse row, per CONTRIBUTING 4d: the gate must still *publish* when
    // the result is complete, or an app that never writes anything satisfies the
    // three checks above.
    let complete = outDir.appendingPathComponent("complete.pdf")
    try? SearchableWriter.compose(visible: src, observations: byPage, to: complete)
    var published = false
    do {
        try OCRModel.publishVerified(complete, expecting: 3, to: keeper)
        published = true
    } catch {
        check("a complete result publishes", false, error.localizedDescription)
    }
    check("a complete result does publish", published)
    // Moved, not copied: the staged file is gone from where it was and the
    // destination has every page. Comparing the destination's bytes against
    // `keeperBefore` would prove nothing here — `complete` was composed from the
    // same source with the same observations, so it can legitimately be
    // byte-identical to what it replaced.
    check("…and the staged file was moved into place, not left behind",
          !FileManager.default.fileExists(atPath: complete.path))
    check("…and the destination has every page",
          PDFDocument(url: keeper)?.pageCount == 3,
          "\(PDFDocument(url: keeper)?.pageCount ?? -1)")

    // A pre-cancelled run reports `.cancelled`, which is T3's closing list made
    // true: what it recorded as covered is `check("a cancelled control refuses the
    // work before it starts", control.isCancelled)` — a property of `RunControl`,
    // asserted without calling `makeSearchablePDF` at all.
    //
    // **And it proves nothing about publishing, which is worth saying plainly
    // because the first version of this block claimed it did.** A pre-cancelled
    // control makes recognition throw, the catch at `Model.swift`'s "A cancellation
    // surfaces here as a throw" reports `.cancelled` and returns, and the run never
    // composes and never reaches `publish`. So "the good file at the destination is
    // untouched" would have held for every possible implementation of
    // `publishVerified` — an un-failable check, inside the fix for un-failable
    // checks. It bites on the outcome and only on the outcome: delete that
    // `if control.isCancelled` and this goes red with `.failed`.
    let good2 = outDir.appendingPathComponent("survivor.pdf")
    try? SearchableWriter.compose(visible: src, observations: byPage, to: good2)
    let cancelled = RunControl()
    cancelled.cancel()
    var outcome: Runner.Result.Outcome?
    var detail = ""
    OCRModel.makeSearchablePDF(
        file: src, output: good2,
        rebuild: false, rebuildMode: .auto, password: nil,
        control: cancelled, progress: { _, _ in },
        report: { o, m in outcome = o; detail = m })
    check("a cancelled run reports cancelled, not failed",
          outcome == .cancelled, "\(String(describing: outcome)) \(detail)")

    // The end-to-end check that *can* fail: a run that composes successfully and
    // then fails at the publish step, with the user's content at the destination.
    //
    // A directory is the one reachable way to get there. Nothing in the pipeline
    // can produce a short staged file — established by trying: a cancel is caught
    // before the gate, and PDFKit repairs a page tree that over-declares its
    // `/Count` rather than handing back a nil page — so the page-count half of
    // `publishVerified` has no end-to-end trigger and is defence in depth, tested
    // at its seam above. The folder half has one, and this drives the whole
    // pipeline through the new call site: compose, the gate, `publish`, the throw,
    // and the outcome the user is shown.
    let folder = outDir.appendingPathComponent("aimed-at-a-folder.pdf", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let inside = folder.appendingPathComponent("someone's work.pdf")
    try? SearchableWriter.compose(visible: src, observations: byPage, to: inside)
    let insideBefore = try? Data(contentsOf: inside)
    check("the folder fixture holds a real file", (insideBefore?.count ?? 0) > 0)
    var folderOutcome: Runner.Result.Outcome?
    var folderDetail = ""
    OCRModel.makeSearchablePDF(
        file: src, output: folder,
        rebuild: false, rebuildMode: .auto, password: nil,
        control: RunControl(), progress: { _, _ in },
        report: { o, m in folderOutcome = o; folderDetail = m })
    check("a run whose destination is a folder fails rather than publishing",
          folderOutcome == .failed, "\(String(describing: folderOutcome)) \(folderDetail)")
    check("…and says so, in the words the user sees",
          folderDetail.contains("is a folder"), folderDetail)
    check("…and the folder is still there",
          FileManager.default.fileExists(atPath: folder.path))
    check("…with the file inside it byte-for-byte intact",
          insideBefore != nil && insideBefore == (try? Data(contentsOf: inside)),
          "\(insideBefore?.count ?? -1) bytes before, "
            + "\((try? Data(contentsOf: inside))?.count ?? -1) after")
    resetPrefs()
}

// MARK: - Cancel reaches grandchildren, not just the child

// A grandchild holding a pipe used to outlive Cancel and Quit — U2's failure one
// level down. The hole was not where TODO.md said it was: `Process.terminate()`
// already signals the whole group, so a co-operative tree does die. The
// escalation did not. `kill(pid, SIGKILL)` reaches exactly one process, so a
// child that *ignores* SIGTERM — the only case escalation exists for — was also
// the only case that leaked its descendants.

print("\ncancel reaches the whole process tree")

/// A shell that holds a backgrounded `sleep` and reports its pid.
/// A bare `sh -c '/bin/sleep 45'` is no good: sh execs straight into sleep and
/// there is no grandchild to lose.
func treeFixture(trapTerm: Bool) -> (parent: Process, grandchild: pid_t) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", (trapTerm ? "trap '' TERM; " : "") + "/bin/sleep 45 & echo $!; wait"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    let announced = String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return (p, pid_t(announced) ?? -1)
}

func gone(_ pid: pid_t, within seconds: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while kill(pid, 0) == 0, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    return kill(pid, 0) != 0
}

do {
    // The group is what makes one signal reach the tree, so check it exists
    // before concluding anything from a process dying.
    let (parent, grandchild) = treeFixture(trapTerm: false)
    check("the fixture really produced a grandchild",
          grandchild > 0 && kill(grandchild, 0) == 0, "announced pid '\(grandchild)'")
    check("Foundation makes the child its own process-group leader",
          Runner.processGroup(of: parent) == parent.processIdentifier,
          "pgid \(getpgid(parent.processIdentifier)) vs pid \(parent.processIdentifier)")
    check("…and the grandchild is in that group",
          getpgid(grandchild) == parent.processIdentifier,
          "grandchild pgid \(getpgid(grandchild))")
    check("…and it is never this process's own group",
          Runner.processGroup(of: parent) != getpgid(0))

    Runner.stop(parent)
    let cleared = gone(grandchild)
    check("a co-operative tree goes down whole", cleared, "pid \(grandchild) still alive")
    check("and the child itself is gone", !parent.isRunning)
    if !cleared { kill(grandchild, SIGKILL) }
}

do {
    // The case that actually leaked: the child ignores SIGTERM, so `stop`
    // escalates — and the escalation used to reach the child alone. Measured
    // before the fix: child dead, grandchild alive and reparented to launchd.
    let (parent, grandchild) = treeFixture(trapTerm: true)
    check("the trapping fixture has a grandchild too",
          grandchild > 0 && kill(grandchild, 0) == 0, "announced pid '\(grandchild)'")

    // Prove the child really does ignore SIGTERM, or this tests nothing.
    kill(parent.processIdentifier, SIGTERM)
    Thread.sleep(forTimeInterval: 0.4)
    check("the fixture really ignores SIGTERM", parent.isRunning)

    Runner.stop(parent, graceSeconds: 0.5)
    check("the SIGTERM-proof child is killed", gone(parent.processIdentifier))
    let cleared = gone(grandchild)
    check("and SIGKILL reaches its grandchild as well", cleared,
          "pid \(grandchild) survived — kill(pid) reaches one process, kill(-pgid) reaches the tree")
    if !cleared { kill(grandchild, SIGKILL) }
}

// MARK: - Publishing is the step that touches the user's disk

// Invariant 2: build in scratch, move into place only on success. `publish` is
// the move, and it had no test of its own — the branch that replaces a previous
// run's output was covered by nothing at all.

print("\npublishing")

do {
    let dir = tmp.appendingPathComponent("publish-unit")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Fresh destination: a plain move.
    let staged = dir.appendingPathComponent("staged-1.pdf")
    let target = dir.appendingPathComponent("result.pdf")
    makeScannedPDF(at: staged, lines: ["the first published copy"])
    try? OCRModel.publish(staged, to: target)
    check("publish moves a staged file into place",
          FileManager.default.fileExists(atPath: target.path))
    check("…and leaves nothing behind in scratch",
          !FileManager.default.fileExists(atPath: staged.path))
    let firstPages = PDFDocument(url: target)?.pageCount ?? -1

    // Occupied destination: replace, not fail, and not truncate.
    let second = dir.appendingPathComponent("staged-2.pdf")
    makeScannedPDF(at: second, lines: ["the second published copy",
                                       "with an extra line so the bytes differ"])
    let before = (try? Data(contentsOf: target))?.count ?? 0
    try? OCRModel.publish(second, to: target)
    let after = (try? Data(contentsOf: target))?.count ?? 0
    check("publish replaces a previous run's output",
          FileManager.default.fileExists(atPath: target.path) && after != before,
          "\(before) → \(after) bytes")
    check("…and the replacement is a whole PDF",
          (PDFDocument(url: target)?.pageCount ?? -1) == firstPages)
    check("…with the staged copy consumed",
          !FileManager.default.fileExists(atPath: second.path))
}

// MARK: - makeSearchablePDF's failure and cancel branches

// Only the two branches with explicit tests were covered. These are the ones a
// user actually hits: a file that is neither PDF nor image, a binary that will
// not run, and Cancel.

print("\nsearchable pipeline: the unhappy branches")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("branches")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    func run(_ file: URL, control: RunControl = RunControl(),
             rebuild: Bool = true) -> (Runner.Result.Outcome?, String) {
        var outcome: Runner.Result.Outcome?
        var message = ""
        OCRModel.makeSearchablePDF(
            file: file,
            output: dir.appendingPathComponent("\(UUID().uuidString).pdf"),
            rebuild: rebuild, rebuildMode: .auto, password: nil,
            control: control, progress: { _, _ in },
            report: { o, m in outcome = o; message = m })
        return (outcome, message)
    }

    // Not a PDF and not an image. This used to fail with a message that blamed
    // the file for something else entirely.
    let junk = dir.appendingPathComponent("notes.pdf")
    try? "this is not a PDF at all".write(to: junk, atomically: true, encoding: .utf8)
    let (junkOutcome, junkMessage) = run(junk)
    check("an unreadable file fails, and says which way", junkOutcome == .failed,
          "\(String(describing: junkOutcome)): \(junkMessage)")
    check("…naming the real problem",
          junkMessage.lowercased().contains("pdf") || junkMessage.lowercased().contains("image"),
          junkMessage)

    // There used to be a check here that an unlaunchable mac-ocr failed the file
    // rather than the batch. Recognition no longer launches anything, so the
    // check has no subject: `Recogniser` calls Vision in process. Deleted rather
    // than weakened into something that passes without testing anything — a
    // check that cannot fail is what T4 and T6 are about.
    //
    // The property it protected still has an owner. jbig2 and qpdf are still
    // subprocesses, and a missing or unlaunchable one must degrade to the
    // CoreGraphics route rather than fail the file; that is covered where the
    // JBIG2 fallback is exercised, and by `Tools/fault-inject.sh`.
    let real = dir.appendingPathComponent("real.pdf")
    makeScannedPDF(at: real, lines: ["a page that would OCR fine"])
    let (goodOutcome, goodMessage) = run(real)
    check("a page that can be read succeeds without any binary to launch",
          goodOutcome == .succeeded, "\(String(describing: goodOutcome)): \(goodMessage)")

    // Cancel before anything starts: reported as cancelled, never as failed,
    // and nothing is published. R14 was exactly this mistake on one route.
    let cancelled = RunControl()
    cancelled.cancel()
    let output = dir.appendingPathComponent("never-written.pdf")
    var cancelOutcome: Runner.Result.Outcome?
    OCRModel.makeSearchablePDF(
        file: real, output: output,
        rebuild: true, rebuildMode: .auto, password: nil,
        control: cancelled, progress: { _, _ in },
        report: { o, _ in cancelOutcome = o })
    check("a cancelled run reports cancellation, not failure", cancelOutcome == .cancelled,
          String(describing: cancelOutcome))
    check("…and publishes nothing", !FileManager.default.fileExists(atPath: output.path))
    resetPrefs()
}

// MARK: - The non-rebuild path

// `rebuild: false` is where C7 and C10 both bit, and nothing covered it.

print("\nsearchable pipeline without the rebuild")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("norebuild")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Pages of differing size with one rotated, per invariant 5 — the non-rebuild
    // path takes its geometry from the source rather than from anything it drew,
    // which is precisely where the crop-box bugs lived.
    //
    // **This fixture did not satisfy the invariant its comment claimed**
    // (`REVIEW-2026-08-14.md` A11.4). It built both pages with `makeScannedPDF`,
    // which hard-codes 612×792, so both pages were *the same size* — "a different
    // size" was the text drawn on the sheet, mistaken for the sheet. There was no
    // geometry assertion at all, on the one route where C7 *and* C10 both bit,
    // and `BUGS.md` T1's closing list recorded this as done. T1 recurring inside
    // T1's own closing list.
    //
    // `mixedPage` is the same helper the invariant-5 block uses, so the two
    // fixtures cannot drift apart in what they mean by "a different size".
    let src = dir.appendingPathComponent("plain.pdf")
    // Short lines on purpose. The first version drew "SECOND PAGE NARROW" on the
    // 456 pt page, which runs close enough to the right edge that Vision read
    // **"SECOND PAGE NARRO"** — so a check asserting the whole word failed over a
    // fixture, not over the code. A fixture whose text does not comfortably fit
    // its own page tests the margin, and the assertion must not hang on the last
    // glyph.
    let sizes: [(CGFloat, CGFloat, String)] = [
        (612, 792, "ONE LETTER"),
        (456, 710, "TWO NARROW"),
        (700, 540, "THREE WIDE"),
    ]
    let merged = PDFDocument()
    for (i, s) in sizes.enumerated() {
        let one = dir.appendingPathComponent("p\(i).pdf")
        mixedPage(one, w: s.0, h: s.1, text: s.2)
        if let doc = PDFDocument(url: one), let page = doc.page(at: 0) {
            // 700×540 turned a quarter displays as 540×700, which is neither of
            // the other two — an obvious 792×612 would display as page 1's box
            // and a page that wrongly inherited it would look correct.
            if i == 2 { page.rotation = 270 }
            merged.insert(page, at: merged.pageCount)
        }
    }
    merged.write(to: src)

    guard let sd = PDFDocument(url: src), sd.pageCount == 3 else {
        check("built the non-rebuild fixture", false); exit(1)
    }
    let srcBoxes = (0..<3).compactMap { sd.page(at: $0).map { Flattener.displayBox(of: $0) } }
    check("the non-rebuild fixture has three different display boxes",
          Set(srcBoxes.map { "\(Int($0.width))x\(Int($0.height))" }).count == 3,
          "\(srcBoxes.map { "\(Int($0.width))x\(Int($0.height))" })")
    check("…and one of them is rotated",
          (0..<3).contains { sd.page(at: $0)?.rotation == 270 })

    let output = dir.appendingPathComponent("plain.ocr.pdf")
    var outcome: Runner.Result.Outcome?
    var message = ""
    OCRModel.makeSearchablePDF(
        file: src, output: output,
        rebuild: false, rebuildMode: .auto, password: nil,
        control: RunControl(), progress: { _, _ in },
        report: { o, m in outcome = o; message = m })

    check("the non-rebuild path succeeds", outcome == .succeeded, message)
    check("…keeps every page",
          PDFDocument(url: output)?.pageCount == merged.pageCount,
          "\(PDFDocument(url: output)?.pageCount ?? -1) of \(merged.pageCount)")
    // The assertion the block never had: each page keeps its own box rather than
    // inheriting page 1's. On this route the geometry comes straight from the
    // source, so a wrong box here is invariant 4's failure with nothing between
    // it and the user.
    var boxesMatch = true
    var boxReport: [String] = []
    if let od = PDFDocument(url: output) {
        for i in 0..<min(od.pageCount, 3) {
            let want = srcBoxes[i]
            let got = od.page(at: i).map { Flattener.displayBox(of: $0) } ?? .zero
            boxReport.append("p\(i + 1) want \(Int(want.width))x\(Int(want.height))"
                             + " got \(Int(got.width))x\(Int(got.height))")
            if abs(got.width - want.width) > 2 || abs(got.height - want.height) > 2 {
                boxesMatch = false
            }
        }
    } else {
        boxesMatch = false
        boxReport.append("the output does not open")
    }
    check("…and each page keeps its own size, not page 1's", boxesMatch,
          boxReport.joined(separator: "; "))
    let text = embeddedText(of: output).uppercased()
    check("…and writes a text layer", text.contains("ONE LETTER"), text.prefix(120).description)
    check("…on the differently-sized page too", text.contains("NARROW"),
          text.prefix(120).description)
    check("…and on the rotated one", text.contains("WIDE"), text.prefix(120).description)
    resetPrefs()
}

// MARK: - Encrypted input, end to end

// The password paths exist — `Flattener.open` unlocks, `Prefs.Snapshot` carries
// the password down to `--password` — and had never been run.

print("\nencrypted input")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("locked")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let plain = dir.appendingPathComponent("plain.pdf")
    makeScannedPDF(at: plain, lines: ["Locked Document Heading", "a second line of text"])
    let locked = dir.appendingPathComponent("locked.pdf")
    let secret = "correct horse"
    PDFDocument(url: plain)?.write(to: locked, withOptions: [
        .userPasswordOption: secret,
        .ownerPasswordOption: secret,
    ])

    // Suspect the instrument: prove the fixture is actually encrypted before
    // concluding anything about the code that opens it.
    check("the fixture really is locked", PDFDocument(url: locked)?.isLocked == true)
    check("…and unreadable without the password",
          Flattener.open(locked, password: nil) == nil)
    check("…and readable with it", Flattener.open(locked, password: secret) != nil)
    check("hasEmbeddedText does not report a locked file as empty prose",
          Flattener.hasEmbeddedText(locked, password: secret) == false)

    // The whole pipeline, with the password travelling the way a batch sends it.
    d.set(secret, forKey: Prefs.password)
    let settings = Prefs.Snapshot.current()
    check("the snapshot carries the password", settings.password == secret)
    // It used to be checked by reading it back off the command line. The
    // password now reaches PDFKit's `open`, and the check that matters is the one
    // below: the locked file is actually recognised with it and refused without.

    let output = dir.appendingPathComponent("locked.ocr.pdf")
    var outcome: Runner.Result.Outcome?
    var message = ""
    OCRModel.makeSearchablePDF(
        file: locked, output: output,
        rebuild: true, rebuildMode: .auto, password: secret,
        settings: settings, control: RunControl(), progress: { _, _ in },
        report: { o, m in outcome = o; message = m })
    check("an encrypted PDF runs through the whole pipeline", outcome == .succeeded, message)
    check("…and its text is recovered",
          embeddedText(of: output).contains("Locked"), embeddedText(of: output).prefix(60).description)

    // And the wrong password fails loudly rather than rendering blank pages.
    var wrongOutcome: Runner.Result.Outcome?
    OCRModel.makeSearchablePDF(
        file: locked,
        output: dir.appendingPathComponent("wrong.pdf"),
        rebuild: true, rebuildMode: .auto, password: "not the password",
        control: RunControl(), progress: { _, _ in },
        report: { o, _ in wrongOutcome = o })
    check("the wrong password fails rather than publishing blank pages",
          wrongOutcome == .failed, String(describing: wrongOutcome))
    check("…and writes nothing",
          !FileManager.default.fileExists(atPath: dir.appendingPathComponent("wrong.pdf").path))
    resetPrefs()
}

// MARK: - Colour pages

// `saturation` feeds the routing decision that has destroyed content twice, and
// no fixture had colour on it. The dangerous case is not a photograph: it is a
// pale tint. Pure yellow has luminance 226, so a tinted figure scores almost no
// ink, gets called text, and is thresholded to blotches — 99% of one real page
// was lost that way.

print("\ncolour pages")

func makeTintedPDF(at url: URL) {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    pdf.beginPDFPage(nil)
    pdf.setFillColor(NSColor.white.cgColor)
    pdf.fill(box)
    // A big pale-yellow figure with paler detail inside it: high saturation,
    // negligible luminance contrast. This is the shape that was destroyed.
    pdf.setFillColor(NSColor(calibratedRed: 1.0, green: 0.95, blue: 0.15, alpha: 1).cgColor)
    pdf.fill(CGRect(x: 80, y: 220, width: 452, height: 420))
    pdf.setFillColor(NSColor(calibratedRed: 0.95, green: 0.75, blue: 0.1, alpha: 1).cgColor)
    for i in 0..<9 {
        pdf.fill(CGRect(x: 110, y: 250 + CGFloat(i) * 44, width: 392, height: 20))
    }
    pdf.endPDFPage()
    pdf.closePDF()
}

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("colour")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let tinted = dir.appendingPathComponent("tinted.pdf")
    makeTintedPDF(at: tinted)

    guard let page = PDFDocument(url: tinted)?.page(at: 0) else {
        check("the colour fixture builds", false); exit(1)
    }
    let sat = Flattener.saturation(of: page)
    check("the fixture is genuinely coloured", sat > Flattener.pictureSaturationThreshold,
          String(format: "saturation %.3f vs threshold %.3f",
                 sat, Flattener.pictureSaturationThreshold))

    // The decision itself: this page must not be routed to 1-bit.
    let pngDir = dir.appendingPathComponent("pages")
    try? FileManager.default.createDirectory(at: pngDir, withIntermediateDirectories: true)
    let rebuilt = try? Flattener.flatten(tinted, to: dir.appendingPathComponent("rebuilt.pdf"),
                                         mode: .auto, pngDirectory: pngDir)
    check("a coloured page is rebuilt", (rebuilt?.count ?? 0) == 1, "\(rebuilt?.count ?? 0) pages")
    if let first = rebuilt?.first {
        var wentToJPEG = false
        if case .jpeg = first.content { wentToJPEG = true }
        check("a coloured page is not thresholded to 1 bit", wentToJPEG,
              "routed to bilevel — this is the failure that lost 99% of a page")
    }

    // And the whole pipeline survives it: a page with no recognisable text at
    // all must still publish, not fail the file.
    let output = dir.appendingPathComponent("tinted.ocr.pdf")
    var outcome: Runner.Result.Outcome?
    var message = ""
    OCRModel.makeSearchablePDF(
        file: tinted, output: output,
        rebuild: true, rebuildMode: .auto, password: nil,
        control: RunControl(), progress: { _, _ in },
        report: { o, m in outcome = o; message = m })
    check("a colour page runs through the pipeline", outcome == .succeeded, message)
    check("…and publishes its page", PDFDocument(url: output)?.pageCount == 1)
    resetPrefs()
}

// MARK: - A short text layer cannot hide behind the page count

// On the JBIG2 route `produced == expected` compares the *images* PDF, which is
// built from the same page list that was just verified. `qpdf --overlay` stamps
// as many layer pages as it has and leaves the rest bare, so a text layer that
// stopped short published a full-length, perfectly valid PDF whose later pages
// simply had no text. Invariant 1: page count is not sufficient verification.

print("\na short text layer is caught")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("shortlayer")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let src = dir.appendingPathComponent("three.pdf")
    let three = PDFDocument()
    for i in 1...3 {
        let one = dir.appendingPathComponent("s\(i).pdf")
        makeScannedPDF(at: one, lines: ["Page \(i) marker text", "second line of page \(i)"])
        if let doc = PDFDocument(url: one), let page = doc.page(at: 0) {
            three.insert(page, at: three.pageCount)
        }
    }
    three.write(to: src)

    let json = dir.appendingPathComponent("obs.json")
    let byPage = observations(of: src)

    // A layer that stopped early, exactly as an interrupted compose leaves it.
    let short = dir.appendingPathComponent("short-layer.pdf")
    try? SearchableWriter.compose(visible: src, observations: byPage, to: short,
                                  drawImages: false, isCancelled: { true })
    let shortPages = PDFDocument(url: short)?.pageCount ?? -1
    check("the truncated layer really is short", shortPages < 3, "\(shortPages) of 3 pages")

    // The predicate the pipeline now applies before it merges anything.
    check("a short layer fails the page-count check", shortPages != 3)

    // And the reason that check has to exist: the merge hides it. Overlaying a
    // short layer yields a full-length file that every page-count test passes.
    if let qpdf = JBIG2.merger, shortPages > 0 {
        let merged = dir.appendingPathComponent("merged.pdf")
        try? JBIG2.overlay(text: short, onto: src, to: merged, using: qpdf, register: { _ in })
        let mergedPages = PDFDocument(url: merged)?.pageCount ?? -1
        check("overlaying a short layer still produces a full-length PDF",
              mergedPages == 3,
              "\(mergedPages) pages — this is why the page count cannot be the check")
    }
    resetPrefs()
}

// MARK: - Concurrent searchable runs

// The concurrency test above runs in text mode, so the route C8's content-loss
// race lived on had no multi-file coverage at all. Two searchable files at once,
// asserting both outputs are complete *and* attributed to the right input.

print("\nconcurrent searchable batch")

do {
    resetPrefs()
    let inDir = tmp.appendingPathComponent("cs-in")
    let outDir = tmp.appendingPathComponent("cs-out")
    try? FileManager.default.createDirectory(at: inDir, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    // Distinct content per file: an output carrying the other file's text is
    // the failure this is looking for, and identical fixtures cannot show it.
    let names = ["alpha", "beta"]
    for name in names {
        makeScannedPDF(at: inDir.appendingPathComponent("\(name).pdf"),
                       lines: ["Document \(name.uppercased()) heading",
                               "the body of \(name) runs on here"])
    }

    d.set(Prefs.Mode.searchablePDF.rawValue, forKey: Prefs.mode)
    d.set(2, forKey: Prefs.concurrency)
    d.set(false, forKey: Prefs.openWhenDone)

    final class Box: @unchecked Sendable { var model: OCRModel? }
    let box = Box()
    var started = false
    Task { @MainActor in
        let m = OCRModel()
        m.besideOriginal = false
        m.outputFolder = outDir
        _ = m.add(names.map { inDir.appendingPathComponent("\($0).pdf") })
        box.model = m
        m.start()
        started = true
    }
    _ = pump(until: { started }, seconds: 5)
    // Wait for the batch to actually BEGIN before waiting for it to end. With
    // the C17 pre-flight, `start()` returns before the run exists, so
    // "isRunning == false" is true on the way in as well as on the way out —
    // and a test that only waits for the second one passes instantly against a
    // batch that never ran.
    let began = pump(until: {
        MainActor.assumeIsolated { box.model?.isRunning == true }
    }, seconds: 30)
    check("the batch actually starts", began)
    let done = pump(until: {
        MainActor.assumeIsolated { box.model?.isRunning == false }
    }, seconds: 180)
    check("a concurrent searchable batch finishes", done)

    MainActor.assumeIsolated {
        guard let m = box.model else { check("the model exists", false); return }
        check("both searchable files are accounted for", m.completed == m.total,
              "\(m.completed)/\(m.total)")
        check("both succeeded", m.log.contains { $0.text.contains("2 of 2 succeeded") },
              m.log.map(\.text).joined(separator: " | "))
    }

    for name in names {
        let output = outDir.appendingPathComponent("\(name).ocr.pdf")
        check("\(name): an output exists",
              FileManager.default.fileExists(atPath: output.path))
        check("\(name): it has its page", PDFDocument(url: output)?.pageCount == 1,
              "\(PDFDocument(url: output)?.pageCount ?? -1)")
        let text = embeddedText(of: output).uppercased()
        check("\(name): it carries its own text", text.contains(name.uppercased()),
              text.prefix(60).description)
        let other = names.first { $0 != name }!.uppercased()
        check("\(name): and not the other file's",
              !text.contains("DOCUMENT \(other) HEADING"), text.prefix(60).description)
    }
    resetPrefs()
}

// MARK: - Real digital text is not an OCR layer

// C17. The rebuild discards any existing text layer, which is right for a scan
// — that layer is a previous OCR pass and it would otherwise double up — and
// wrong for a born-digital PDF, where it is the real text and OCR of a picture
// of it is measurably worse. The two cases both "have text", so the test that
// separates them is whether the text sits on a page-sized image.

print("\ntelling real digital text from an OCR layer")

/// A born-digital page: real drawn text, no raster anywhere.
func makeDigitalPDF(at url: URL, lines: [String], pages: Int = 3) {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
    for p in 1...pages {
        pdf.beginPDFPage(nil)
        var y: CGFloat = 720
        for line in lines {
            let text = "p\(p): \(line)"
            let ct = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: [.font: font]))
            pdf.textPosition = CGPoint(x: 72, y: y)
            CTLineDraw(ct, pdf)
            y -= 16
        }
        pdf.endPDFPage()
    }
    pdf.closePDF()
}

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("digital")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let prose = (1...26).map {
        "Line \($0) of ordinary running prose, long enough to be a real paragraph of text."
    }

    // 1. Born-digital: text, no page image.
    let digital = dir.appendingPathComponent("born-digital.pdf")
    makeDigitalPDF(at: digital, lines: prose)
    check("a born-digital PDF is recognised as carrying real text",
          Flattener.hasDigitalText(digital))

    // 2. A plain scan: image, no text at all.
    let scan = dir.appendingPathComponent("scan.pdf")
    makeScannedPDF(at: scan, lines: ["A SCANNED HEADING", "and a line beneath it"])
    check("a plain scan is not", !Flattener.hasDigitalText(scan))

    // 3. The one that matters: a scan that has ALREADY been OCR'd. It has text
    //    *and* a page image, and rebuilding it is correct — that is what stops
    //    the doubled-text problem the whole rebuild exists for. Calling this
    //    "digital text" would put a warning in front of the app's main use case
    //    and, if the user then skipped it, silently do nothing.
    let ocrd = dir.appendingPathComponent("already-ocrd.pdf")
    makeDecoyPDF(at: ocrd, imageSays: ["A SCANNED HEADING", "and a line beneath it"],
                 textLayerSays: String(repeating: "previously recognised text ", count: 12))
    check("the decoy really has both an image and a text layer",
          !embeddedText(of: ocrd).isEmpty)
    check("an already-OCR'd SCAN is not treated as digital text",
          !Flattener.hasDigitalText(ocrd),
          "this is the app's main input; warning about it would be the wrong way round")

    // The signal underneath, checked directly so a failure above is diagnosable.
    if let p = PDFDocument(url: scan)?.page(at: 0) {
        check("a scanned page reads as a page-sized image", Flattener.pageIsAnImage(p))
    }
    if let p = PDFDocument(url: digital)?.page(at: 0) {
        check("a born-digital page does not", !Flattener.pageIsAnImage(p))
    }

    // 4. The batch-level pre-flight picks out exactly the digital ones.
    let mixed = [scan, digital, ocrd]
    let flagged = OCRModel.filesWithDigitalText(in: mixed, password: nil)
    check("the pre-flight flags only the born-digital file",
          flagged == [digital],
          flagged.map(\.lastPathComponent).joined(separator: ","))

    // 5. The wording names the files and is honest about the cost.
    let warning = OCRModel.digitalTextWarning(for: [digital], of: 3, mode: .searchablePDF)
    check("the warning names the file", warning.contains("born-digital.pdf"), warning)
    check("…says how much of the batch it is", warning.contains("1 of 3"), warning)
    check("…and says re-OCRing is legitimate when the text is broken",
          warning.lowercased().contains("broken"), warning)
    // A5.4, as corrected by A10.1: the un-qualified wording named a harm that
    // cannot happen in Extract Text. Nothing is rebuilt and nothing is discarded
    // in that mode — `start()`'s own comment says so — and a message describing
    // destruction that is not on offer pushes the user toward Cancel for a reason
    // that does not exist. It was wrong for *every* text format, not only json.
    let textWarning = OCRModel.digitalTextWarning(for: [digital], of: 3, mode: .text)
    check("the Extract Text wording does not claim the pages are rebuilt",
          !textWarning.contains("Rebuilding the pages"), textWarning)
    check("…and does not claim anything is discarded or replaced",
          !textWarning.contains("discards") && !textWarning.contains("replaces"),
          textWarning)
    check("…but still names the 9% loss, which is the real cost",
          textWarning.contains("9% of the words"), textWarning)
    check("…and still names the file and the scope",
          textWarning.contains("born-digital.pdf") && textWarning.contains("1 of 3"))
    check("…while the Searchable PDF wording keeps the harm that is real there",
          warning.contains("Rebuilding the pages"), warning)

    // 5b. A10.1. The setting is live in four states and its control was drawn in
    // one of them. Enumerated as a table rather than reasoned about in pairs
    // (CONTRIBUTING 4d), and driven through the **real** `start()`, because the
    // defect was precisely that the panel's condition and `start()`'s condition
    // were two different expressions of one rule.
    //
    // The harm: work in Extract Text, get the alert, tick "Don't ask again". From
    // then on Extract Text silently OCRs a picture of good text — 9% of the words
    // — and no control in the panel can turn it back on, because the only one
    // lived in the other mode under a toggle that mode does not have.
    do {
        let table: [(Prefs.Mode, Bool, Bool)] = [
            (.searchablePDF, true,  true),    // rebuild destroys the real text (C17)
            (.searchablePDF, false, false),   // nothing is discarded, nothing to ask
            (.text,          true,  true),    // OCR of a picture of good text
            (.text,          false, true),    // …and the rebuild flag is irrelevant here
        ]
        for (mode, rebuild, expected) in table {
            check("the warning applies in \(mode.rawValue), rebuild "
                    + "\(rebuild ? "on" : "off"): \(expected)",
                  OCRModel.warnsAboutDigitalText(mode: mode, rebuildImages: rebuild)
                    == expected)
        }

        // And the panel draws the toggle under that predicate rather than under a
        // second opinion. A source check, because the alternative is instantiating
        // a SwiftUI view: what it holds is that the control is inside the guard,
        // which is the whole of the defect.
        let panel = (try? String(contentsOfFile: "Sources/SettingsView.swift",
                                 encoding: .utf8)) ?? ""
        check("the panel draws the toggle under the model's own predicate",
              panel.contains("OCRModel.warnsAboutDigitalText(mode: mode, "
                             + "rebuildImages: rebuildImages)"),
              panel.isEmpty ? "could not read SettingsView.swift" : "predicate not used")
        // The toggle must not be back inside the rebuild-only branch. `range(of:)`
        // on the two positions: the guard has to come *before* the toggle.
        if let guardAt = panel.range(of: "warnsAboutDigitalText"),
           let toggleAt = panel.range(of: "Ask first if a PDF already has selectable text") {
            check("…and the toggle is the thing that guard governs",
                  guardAt.lowerBound < toggleAt.lowerBound)
        } else {
            check("the panel still has the toggle and the guard", false)
        }

        // The real `start()`, for the one state the review measured as broken:
        // Extract Text with the rebuild off. If the pre-flight does not fire here
        // the whole predicate is decoration.
        resetPrefs()
        let d2 = UserDefaults.standard
        d2.set(true, forKey: Prefs.warnDigitalText)
        d2.set(false, forKey: Prefs.rebuildImages)
        d2.set(Prefs.Mode.text.rawValue, forKey: Prefs.mode)
        d2.set(Prefs.TextFormat.text.rawValue, forKey: Prefs.textFormat)
        var askedInTextMode = false
        let asked2 = DispatchSemaphore(value: 0)
        let m2 = MainActor.assumeIsolated { OCRModel() }
        OCRModel.digitalTextDecisionForTesting = { _, _ in
            askedInTextMode = true
            asked2.signal()
            return .cancel
        }
        MainActor.assumeIsolated {
            m2.besideOriginal = true
            _ = m2.add([digital])
            m2.start()
        }
        let began = Date()
        while asked2.wait(timeout: .now()) == .timedOut,
              Date().timeIntervalSince(began) < 30 {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        check("Extract Text with the rebuild off still asks about born-digital text",
              askedInTextMode, "the pre-flight never fired")
        OCRModel.digitalTextDecisionForTesting = nil
        resetPrefs()
    }

    // 6. Extract Text has a strictly better answer than OCR for these files:
    //    read the text out. Verify it round-trips and beats what OCR would give.
    let extracted = dir.appendingPathComponent("extracted.txt")
    try? OCRModel.writeEmbeddedText(from: digital, to: extracted, password: nil)
    let got = (try? String(contentsOf: extracted, encoding: .utf8)) ?? ""
    check("the embedded text is written out", !got.isEmpty)
    check("…faithfully, not through OCR",
          got.contains("Line 1 of ordinary running prose"), String(got.prefix(70)))
    check("…including later pages", got.contains("p3:"), "page breaks kept")

    // Overwriting a previous result must go through publish, not a raw write.
    try? OCRModel.writeEmbeddedText(from: digital, to: extracted, password: nil)
    check("extracting twice replaces cleanly",
          ((try? String(contentsOf: extracted, encoding: .utf8)) ?? "").contains("p3:"))

    // A scan has nothing to extract, and must say so rather than write an empty
    // file that looks like a successful run.
    var refused = false
    do { try OCRModel.writeEmbeddedText(from: scan, to: dir.appendingPathComponent("x.txt"),
                                        password: nil) }
    catch { refused = true }
    check("extracting from a scan fails loudly rather than writing nothing", refused)

    // C19. The dangerous shape is neither of the two above: a document that is
    // *mostly* born-digital with some scanned pages in it. hasDigitalText samples
    // at most four pages and needs only a majority, so such a file is flagged as
    // digital and "Use Existing Text" is the default button — and every scanned
    // page then contributes "" to a "\n\n"-joined body, indistinguishable from a
    // page break. The whole-body guard passes because the digital pages carry it.
    let mixedURL = dir.appendingPathComponent("mostly-digital.pdf")
    if let mixed = PDFDocument(url: digital), let scanned = PDFDocument(url: scan),
       let plate = scanned.page(at: 0) {
        mixed.insert(plate, at: mixed.pageCount)     // an image-only appendix page
        mixed.write(to: mixedURL)
    }
    let mixedDoc = PDFDocument(url: mixedURL)
    check("the mixed fixture is digital pages plus one image-only page",
          mixedDoc?.pageCount == 4
              && (mixedDoc?.page(at: 3)?.string ?? "")
                  .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          "pages=\(mixedDoc?.pageCount ?? -1)")

    // And it is routed here, which is what makes the silence dangerous.
    check("…and hasDigitalText still flags it, so this is the default route",
          Flattener.hasDigitalText(mixedURL))

    let mixedOut = dir.appendingPathComponent("mostly-digital.txt")
    let dropped = (try? OCRModel.writeEmbeddedText(from: mixedURL, to: mixedOut,
                                                   password: nil)) ?? []
    let mixedText = (try? String(contentsOf: mixedOut, encoding: .utf8)) ?? ""

    check("the digital pages are still extracted",
          mixedText.contains("Line 1 of ordinary running prose"))
    check("the page that contributed nothing is reported",
          dropped == [4], String(describing: dropped))
    check("…and the output file says so where the page would have been",
          mixedText.contains("page 4") && mixedText.lowercased().contains("not"),
          mixedText.suffix(120).description)

    // A genuinely blank page is not a loss and must not be reported as one.
    let blankURL = dir.appendingPathComponent("with-blank.pdf")
    if let withBlank = PDFDocument(url: digital) {
        withBlank.insert(PDFPage(), at: withBlank.pageCount)
        withBlank.write(to: blankURL)
    }
    let blankOut = dir.appendingPathComponent("with-blank.txt")
    let blankDropped = (try? OCRModel.writeEmbeddedText(from: blankURL, to: blankOut,
                                                        password: nil)) ?? [-1]
    check("an empty page carrying no image is not reported as dropped",
          blankDropped.isEmpty, String(describing: blankDropped))

    // 7. It is a warning, not a lock: the setting exists and defaults to asking.
    d.removeObject(forKey: Prefs.warnDigitalText)
    Prefs.register()
    check("asking is on by default",
          UserDefaults.standard.bool(forKey: Prefs.warnDigitalText),
          "the registered default, not the value resetPrefs forces off for the suite")
    resetPrefs()
}

// MARK: - What the window is for

// This app's job is making scans searchable; extracting plain text is the
// specialist case. The segmented control's order comes from `Mode.allCases`,
// so the enum's declaration order IS the UI order — a detail that is easy to
// undo by tidying the enum.

print("\ndefaults and ordering")

do {
    resetPrefs()
    check("Searchable PDF is the default mode",
          Prefs.Snapshot.current().mode == .searchablePDF,
          Prefs.Snapshot.current().mode.rawValue)
    check("…and comes first in the picker",
          Prefs.Mode.allCases.first == .searchablePDF,
          Prefs.Mode.allCases.map(\.rawValue).joined(separator: ","))
    check("Extract text is second", Prefs.Mode.allCases.last == .text)

    // A stored value the app cannot parse must fall back to the default rather
    // than to whatever case happens to be written first in the file.
    d.set("nonsense-mode", forKey: Prefs.mode)
    check("an unparseable stored mode falls back to the default",
          Prefs.Snapshot.current().mode == .searchablePDF)

    // Read from the registration domain, not from `resetPrefs`, which turns
    // this one off so the suite does not write into ~/Library/Logs. Asserting
    // the value the suite itself set would test nothing (T4).
    let registered = UserDefaults.standard.volatileDomain(
        forName: UserDefaults.registrationDomain)
    check("the run report is written by default",
          registered[Prefs.writeRunReport] as? Bool == true,
          "\(String(describing: registered[Prefs.writeRunReport]))")
    resetPrefs()
}

// The log used to open with the pipeline's steps — the mac-ocr command line,
// the rebuild, the JBIG2 merge. Honest, and a developer's view of a run. The
// window shows progress; the steps live in Settings' command preview.

print("\nthe run log carries outcomes, not pipeline steps")

do {
    resetPrefs()
    let inDir = tmp.appendingPathComponent("nosteps-in")
    let outDir = tmp.appendingPathComponent("nosteps-out")
    for dir in [inDir, outDir] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    makeScannedPDF(at: inDir.appendingPathComponent("one.pdf"), lines: ["A single page"])
    d.set(false, forKey: Prefs.openWhenDone)
    // The one place the report is exercised end to end, through the real
    // `finishUp`. Cleaned up below.
    d.set(true, forKey: Prefs.writeRunReport)

    final class Box: @unchecked Sendable { var model: OCRModel? }
    let box = Box()
    var started = false
    Task { @MainActor in
        let m = OCRModel()
        m.besideOriginal = false
        m.outputFolder = outDir
        _ = m.add([inDir.appendingPathComponent("one.pdf")])
        box.model = m
        m.start()
        started = true
    }
    _ = pump(until: { started }, seconds: 5)
    _ = pump(until: { MainActor.assumeIsolated { box.model?.isRunning == true } }, seconds: 30)
    _ = pump(until: { MainActor.assumeIsolated { box.model?.isRunning == false } }, seconds: 120)

    MainActor.assumeIsolated {
        guard let m = box.model else { check("the model exists", false); return }
        let text = m.log.map(\.text).joined(separator: "\n")
        check("the log does not open with the mac-ocr command line",
              !text.contains("--format"), text.prefix(90).description)
        check("…nor the rebuild step", !text.lowercased().contains("rebuild pages"),
              text.prefix(90).description)
        check("…nor the JBIG2 note", !text.contains("JBIG2 compression is on"),
              text.prefix(90).description)
        // What it must still carry: the outcome, and where the file went.
        check("it does say what happened", text.contains("Done —"), text)
        check("…and where the output went", text.contains(outDir.lastPathComponent), text)
        // The report is written by the same `finishUp` and names itself in the
        // log, so a run that wrote one and a run that did not are told apart
        // from the record rather than from the filesystem.
        check("…and where the run report went",
              text.contains("Run report: ") && m.lastReport != nil, text)
        if let report = m.lastReport {
            check("the run report exists on disk",
                  FileManager.default.fileExists(atPath: report.path), report.path)
            let body = (try? String(contentsOf: report, encoding: .utf8)) ?? ""
            check("…and it carries the whole log",
                  body.contains("Done —") && body.contains("one.pdf"),
                  body.prefix(200).description)
            check("…and the settings that produced it",
                  body.contains("Searchable PDF") && body.contains("Files at once"),
                  body.prefix(400).description)
            try? FileManager.default.removeItem(at: report)
        }
    }
    resetPrefs()
}

// MARK: - Recognition languages come from the machine

print("\nrecognition languages this Mac actually has")

do {
    resetPrefs()
    // Not a mock. The whole point of this feature is that the list comes from
    // the installed macOS through the installed binary; a fixture list would
    // test a hand-written copy of the answer against itself (T4's shape).
    let accurate = Recogniser.supportedLanguages(fast: false)
    let quick = Recogniser.supportedLanguages(fast: true)
    if accurate.isEmpty {
        // A11.7. This said "mac-ocr not resolvable" and offered
        // `brew install jbig2enc qpdf` as the remedy — naming a dependency removed
        // in 1.11.0 and a fix for a different one. Twelve checks hid behind it.
        // Recognition is in-process now (R40), so an empty list means Vision
        // reported no languages, which is a property of the OS and not something a
        // user can install.
        skipBlock("recognition languages this Mac actually has", checks: 12,
                  because: "Vision reported no recognition languages on this system")
    } else {
        // Self-verifying census figure (A11.7).
        let checksBeforeLanguageBlock = checks
        check("the accurate recognizer reports a plausible list",
              accurate.count >= 5 && accurate.contains("en-US"),
              "\(accurate.count): \(accurate.prefix(6).joined(separator: ","))")
        check("…every entry looks like a BCP-47 code",
              accurate.allSatisfy { $0.contains("-") && !$0.contains(" ") && $0.count <= 12 },
              accurate.filter { !$0.contains("-") }.joined(separator: ","))
        // The finding that makes this feature worth more than a convenience:
        // fast recognition supports a strict subset, so ticking Fast can
        // invalidate a language that was working.
        check("fast recognition reports a subset, not the same list",
              !quick.isEmpty && quick.count < accurate.count
                && Set(quick).isSubset(of: Set(accurate)),
              "fast \(quick.count) of \(accurate.count)")

        check("a code the machine has is not reported unsupported",
              Recogniser.unsupportedLanguages(in: "en-US", fast: false).isEmpty)
        check("…and a code it does not have is",
              Recogniser.unsupportedLanguages(in: "xx-XX", fast: false) == ["xx-XX"],
              Recogniser.unsupportedLanguages(in: "xx-XX", fast: false).joined(separator: ","))
        check("…case does not decide it",
              Recogniser.unsupportedLanguages(in: "EN-us", fast: false).isEmpty)
        check("…and the list is split the same way the command line splits it",
              Recogniser.unsupportedLanguages(in: "en-US, xx-XX", fast: false) == ["xx-XX"],
              Recogniser.unsupportedLanguages(in: "en-US, xx-XX", fast: false)
                .joined(separator: ","))

        // The Fast interaction, stated as a check rather than as a comment.
        if let onlyAccurate = accurate.first(where: { !quick.contains($0) }) {
            check("a language available only to the accurate recognizer is flagged under Fast",
                  Recogniser.unsupportedLanguages(in: onlyAccurate, fast: false).isEmpty
                    && Recogniser.unsupportedLanguages(in: onlyAccurate, fast: true)
                        == [onlyAccurate],
                  onlyAccurate)
        } else {
            check("the two lists differ, or the Fast check proves nothing", false)
        }

        // Blank is "let Vision decide" and must never be reported as a problem.
        check("blank is not an unsupported language",
              Recogniser.unsupportedLanguages(in: "", fast: false).isEmpty
                && Recogniser.unsupportedLanguages(in: "  ,  ", fast: false).isEmpty)

        check("the picker labels a code with its language name",
              SettingsView.languageLabel("ja-JP").contains("ja-JP")
                && SettingsView.languageLabel("ja-JP").count > "ja-JP".count,
              SettingsView.languageLabel("ja-JP"))
        check("…and an unknown code still labels as itself",
              SettingsView.languageLabel("zz") == "zz"
                || SettingsView.languageLabel("zz").contains("zz"),
              SettingsView.languageLabel("zz"))
        // A11.7, as above: the figure the skipping branch reports, verified here.
        check("the skip census figure for the language block is still right",
              checks - checksBeforeLanguageBlock + 1 == 12,
              "\(checks - checksBeforeLanguageBlock + 1) checks, census says 12")
    }

    // The bounded capture the language list rides on is the same one tool
    // lookup uses, so its bound is exercised here too rather than only through
    // a shell.
    check("a command that does not exist captures nothing",
          Runner.captureBounded("/nonexistent/binary", []) == nil)
    check("a command that fails captures nothing",
          Runner.captureBounded("/bin/sh", ["-c", "echo out; exit 3"]) == nil)
    check("…and one that succeeds captures its stdout",
          Runner.captureBounded("/bin/sh", ["-c", "echo hello"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
    // U18. The bound has to cover the read, not just the wait: a child that
    // exits while a grandchild holds stdout open must not hang the caller.
    let began = DispatchTime.now()
    // A9.3. This fixture *creates* the leak — the child exits and a backgrounded
    // grandchild keeps stdout open — and the check asserted only `took < 5`, so the
    // stranded process it produced went unnoticed. The grandchild writes its own
    // pid where this can read it, so "was it collected?" is a question about that
    // process and not a pattern match against every process on the machine.
    let pidFile = tmp.appendingPathComponent("a93-\(UUID().uuidString).pid")
    defer { try? FileManager.default.removeItem(at: pidFile) }
    let held = Runner.captureBounded(
        "/bin/sh", ["-c", "(sleep 30 & echo $! > '\(pidFile.path)') ; echo partial"],
        seconds: 1)
    let took = Double(DispatchTime.now().uptimeNanoseconds &- began.uptimeNanoseconds) / 1e9
    check("a background job holding stdout cannot hang the capture",
          took < 5, String(format: "%.1fs, returned %@", took,
                           held == nil ? "nil" : "a value"))

    let grandchild = Int32((try? String(contentsOf: pidFile, encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    check("the grandchild's pid was recorded, so this is testing something",
          grandchild > 0, "\(grandchild)")
    if grandchild > 0 {
        // `kill(pid, 0)` asks whether the process exists without signalling it.
        // A moment's grace: `stop` signals the group and the kernel reaps
        // asynchronously.
        var alive = true
        for _ in 0..<40 {
            if kill(grandchild, 0) != 0 { alive = false; break }
            usleep(50_000)
        }
        check("…and the grandchild holding the pipe was collected, not stranded",
              !alive,
              "pid \(grandchild) is still running — stop() returned early because "
                + "the child had already exited, so the group was never signalled")
    }

    // A9.6. No byte cap: `drain`'s other caller caps its accumulator explicitly and
    // says why, and this one did not, so a child that writes without ever closing
    // the pipe was bounded in time and unbounded in memory — measured with
    // `cat /dev/zero`, peak RSS 9 MB -> 1,985 MB.
    //
    // Asserted through *time*, not memory: the cap makes `drain` stop as soon as it
    // trips, so a five-second bound ends in well under five seconds. `ru_maxrss` is
    // the instrument this project has already been burned by (A3.1), and it would
    // read a multi-phase suite as a sum of peaks here.
    let floodBegan = DispatchTime.now()
    let flooded = Runner.captureBounded("/bin/sh", ["-c", "cat /dev/zero"], seconds: 5)
    let floodTook = Double(DispatchTime.now().uptimeNanoseconds
                            &- floodBegan.uptimeNanoseconds) / 1e9
    check("a child that floods stdout is refused", flooded == nil)
    check("…and is stopped by the byte cap, not by the five-second deadline",
          floodTook < 3, String(format: "%.2fs — it ran to the deadline instead",
                                floodTook))
    resetPrefs()
}

// MARK: - The written run report

print("\nthe written run report")

do {
    resetPrefs()
    let a = URL(fileURLWithPath: "/tmp/a.pdf"), b = URL(fileURLWithPath: "/tmp/b.pdf")
    let c = URL(fileURLWithPath: "/tmp/c.pdf"), e = URL(fileURLWithPath: "/tmp/e.pdf")
    var snapshot = Prefs.Snapshot.current()
    // Every optional row switched on, so the coverage check below is exercising
    // the rows rather than the conditions that hide them.
    snapshot.password = "hunter2"
    snapshot.customWords = "Boltanski"
    snapshot.confidence = 0.4
    snapshot.minTextHeightOn = true
    snapshot.minTextHeight = 0.02
    snapshot.mode = .searchablePDF
    let context = RunReport.Context(
        version: "9.9.9",
        started: Date(timeIntervalSince1970: 1_760_000_000),
        finished: Date(timeIntervalSince1970: 1_760_003_671),
        elapsed: 3671,
        settings: snapshot,
        rebuildImages: true, rebuildMode: .auto, concurrency: 6,
        recognitionInHelpers: true, recognitionFallbacks: 0,
        // The default for this block: the setting is on and every file took the
        // route. The A9.2 checks below vary it.
        jbig2Files: 4,
        destination: URL(fileURLWithPath: "/tmp/out"),
        inputs: [a, b, c, e],
        outcomes: [a: .succeeded, b: .failed, c: .cancelled],
        skipped: [e],
        log: ["✓ a.pdf", "✗ b.pdf", "    it broke"])
    let text = RunReport.text(context)

    check("the report names the version", text.contains("Vision OCR 9.9.9"))
    check("…and both timestamps", text.contains("Started   ") && text.contains("Finished  "))
    check("…and the elapsed time, from the monotonic reading",
          text.contains("1h 01m 11s"), RunReport.duration(3671))
    // Counted from `outcomes`, the source the results pane counts. U25 is what
    // happens when a second view of the same state derives it a second way.
    check("…and one line per outcome kind",
          text.contains("4 files — 1 succeeded, 1 failed, 1 cancelled, 1 skipped"),
          text.split(separator: "\n").first { $0.contains("files —") }.map(String.init) ?? "")
    check("…counting files offered, not files that ran", text.contains("4 files"))
    check("…and it lists the failures by path before anything else",
          text.range(of: "Failed\n  /tmp/b.pdf") != nil
            && text.range(of: "Failed")!.lowerBound < text.range(of: "Settings")!.lowerBound)
    check("…and the log verbatim, in arrival order",
          text.contains("✓ a.pdf") && text.contains("✗ b.pdf")
            && text.range(of: "✓ a.pdf")!.lowerBound < text.range(of: "✗ b.pdf")!.lowerBound)
    // A report is a file people mail to whoever is helping them.
    check("the password is never in the report",
          !text.contains("hunter2") && text.contains("Password") && text.contains("(set)"))

    // R40. Two runs of the same files with the same settings can differ by 2.5x
    // in wall clock depending on this alone, and nothing else in the report
    // would say which one it was.
    check("the report says where recognition ran",
          text.contains("Recognition runs in") && text.contains("helper processes"),
          text.split(separator: "\n").first { $0.contains("Recognition runs in") }
            .map(String.init) ?? "absent")
    var inTheApp = context
    inTheApp.recognitionInHelpers = false
    check("…and says the slow way when that is what happened",
          RunReport.text(inTheApp).contains("the app itself"))

    // R41. The row used to be derived from the *configuration*, so a helper that
    // was present and failed on every file produced a report saying "helper
    // processes" over a batch that ran entirely in-process at 2.5x the time.
    // A report that misdescribes how its documents were produced is the thing
    // `settingsRows`' own doc comment exists to prevent.
    var withFallbacks = context
    withFallbacks.recognitionFallbacks = 3
    let fallbackText = RunReport.text(withFallbacks)
    check("a run whose helpers failed says so, rather than claiming them",
          fallbackText.contains("3 file(s) fell back"),
          fallbackText.split(separator: "\n").first { $0.contains("Recognition runs in") }
            .map(String.init) ?? "absent")
    check("…and a clean helper run is not made to look like a fallback",
          !RunReport.text(context).contains("fell back"))
    // The inverse row: fallbacks cannot resurrect a run that never used helpers.
    var neither = context
    neither.recognitionInHelpers = false
    neither.recognitionFallbacks = 3
    check("…and a run that never used a helper still says the app itself",
          RunReport.text(neither).contains("the app itself")
            && !RunReport.text(neither).contains("fell back"))

    // A9.2. The same defect R41 fixed for the recognition row, one row below it:
    // "JBIG2 compression" read the *checkbox*. Three of the four states that reach
    // this row report "on" about a step that did not run — rebuild off, greyscale
    // mode, or the tools not found — and A9.1 reaches the same place invisibly.
    // The size difference is ~3x, so the report was denying the one thing a user
    // would go looking for. `usedJBIG2` existed and never left the function.
    // Read the row rather than matching column padding, so the checks are about
    // what the row says and not about how wide the label column happens to be.
    func jbig2Row(_ c: RunReport.Context) -> String {
        RunReport.text(c).split(separator: "\n")
            .first { $0.contains("JBIG2") }.map(String.init) ?? "absent"
    }
    var noJBIG2 = context
    noJBIG2.jbig2Files = 0
    check("the JBIG2 row does not claim a route no file took",
          !jbig2Row(noJBIG2).hasSuffix("on"), jbig2Row(noJBIG2))
    check("…and says so in words rather than by omission",
          jbig2Row(noJBIG2).contains("no page took that route"), jbig2Row(noJBIG2))
    var someJBIG2 = context
    someJBIG2.jbig2Files = 2
    check("…and counts the files that really took it",
          jbig2Row(someJBIG2).contains("2 of 4 file(s)"), jbig2Row(someJBIG2))
    // The inverse row: a count cannot resurrect a setting that was off.
    var offButCounted = context
    offButCounted.settings.useJBIG2 = false
    offButCounted.jbig2Files = 2
    check("…and a run with the setting off still says off",
          jbig2Row(offButCounted).hasSuffix("off"), jbig2Row(offButCounted))

    // A9.4. Extract Text calls a function with no helper parameter, so the row is
    // "the app itself" by construction — and it used to say "helper processes" over
    // a batch that never launched one, with recognitionFallbacks at 0 so the
    // qualifier that would have made it honest never appeared either.
    var textHelpers = context
    textHelpers.settings.mode = .text
    textHelpers.recognitionInHelpers = true
    check("a text run never claims helper processes",
          RunReport.text(textHelpers).contains("the app itself"),
          RunReport.text(textHelpers).split(separator: "\n")
            .first { $0.contains("Recognition runs in") }.map(String.init) ?? "absent")
    check("…and a searchable run still can", RunReport.text(context).contains("helper processes"))

    // A9.7. Cancelled files were named nowhere but the log, while failures got a
    // by-name block — so after a batch stopped part way, the report counted the
    // cancellations and left the reader to work out which documents they were.
    check("the report names the cancelled files, not just the failed ones",
          RunReport.text(context).contains("Cancelled\n  /tmp/c.pdf"),
          RunReport.text(context).split(separator: "\n")
            .first { $0.hasPrefix("Cancelled") }.map(String.init) ?? "no Cancelled block")
    var noneStopped = context
    noneStopped.outcomes = [a: .succeeded, b: .failed]
    check("…and omits the block when nothing was cancelled",
          !RunReport.text(noneStopped).contains("Cancelled\n"))

    // A9.7. The sixth bare Int(Double) in the codebase, in the one file A7.3's
    // grep did not cover — that sweep was scoped to Flattener.
    check("a nonsense elapsed time does not trap the report",
          RunReport.duration(.nan) == "0s" && RunReport.duration(1e19).hasSuffix("s"),
          "\(RunReport.duration(.nan)) / \(RunReport.duration(1e19))")
    check("…and an ordinary one is unchanged", RunReport.duration(3671) == "1h 01m 11s",
          RunReport.duration(3671))

    // CONTRIBUTING 4d — enumerate, do not reason about pairs. A setting added
    // to `Snapshot` and forgotten here makes every later report quietly wrong
    // about how its documents were produced, and nothing afterwards can tell.
    let fields = Mirror(reflecting: snapshot).children.compactMap(\.label)
    check("the snapshot has fields to check", fields.count >= 16, "\(fields.count)")
    let unmapped = fields.filter { RunReport.reportedBySnapshotField[$0] == nil }
    check("every setting in the snapshot is mapped to a report row",
          unmapped.isEmpty, unmapped.joined(separator: ", "))
    let rows = RunReport.settingsRows(context)
    let labels = Set(rows.map(\.0))
    let missing = Set(fields.compactMap { RunReport.reportedBySnapshotField[$0] })
        .subtracting(labels)
    check("…and every mapped row is actually emitted",
          missing.isEmpty, missing.sorted().joined(separator: ", "))
    let unexplained = labels.subtracting(RunReport.reportedBySnapshotField.values)
        .subtracting(RunReport.rowsOutsideTheSnapshot)
    check("…and no row reports something the map does not explain",
          unexplained.isEmpty, unexplained.sorted().joined(separator: ", "))

    // Extract Text hides the searchable-PDF rows, which must not make the
    // report claim a JBIG2 setting shaped a text extraction.
    var textMode = context
    textMode.settings.mode = .text
    let textRows = Set(RunReport.settingsRows(textMode).map(\.0))
    check("a text run does not report searchable-PDF settings",
          !textRows.contains("JBIG2 compression") && !textRows.contains("Photo detail"),
          textRows.sorted().joined(separator: ", "))

    check("durations keep seconds at every scale",
          RunReport.duration(61) == "1m 01s" && RunReport.duration(12) == "12s"
            && RunReport.duration(3600) == "1h 00m 00s",
          "\(RunReport.duration(61)) / \(RunReport.duration(12)) / \(RunReport.duration(3600))")
    check("a negative elapsed cannot produce a negative duration",
          RunReport.duration(-5) == "0s", RunReport.duration(-5))
    check("the file name sorts chronologically and has no colons",
          RunReport.fileName(for: context.finished).hasPrefix("Run 20")
            && !RunReport.fileName(for: context.finished).contains(":"),
          RunReport.fileName(for: context.finished))

    // Every label is followed by at least one space, whatever its length. The
    // padding used to be to `max(22, label.count)`, which for a long label is
    // no padding at all and runs the value straight into it.
    let widest = RunReport.settingsRows(context).max { $0.0.count < $1.0.count }?.0 ?? ""
    var stretched = context
    stretched.destination = URL(fileURLWithPath: "/tmp/x")
    check("the settings column always leaves a gap",
          RunReport.text(context).split(separator: "\n")
            .filter { $0.hasPrefix("  ") && $0.contains(widest) }
            .allSatisfy { $0.contains(widest + "  ") || $0.contains(widest + " ") },
          "widest label: \(widest) (\(widest.count))")

    // One-second resolution plus an atomic write means the second of two short
    // batches finishing in the same second would replace the first's report
    // with no word about it. `uniqueOutputs` solves the same problem for the
    // documents; this is that, for the record of them.
    let clash = tmp.appendingPathComponent("clash-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: clash, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: clash) }
    var written: [URL] = []
    for _ in 0..<3 {
        if case .success(let u) = RunReport.write(context, to: clash) { written.append(u) }
    }
    check("three reports finishing in the same second are three files",
          Set(written.map(\.lastPathComponent)).count == 3
            && (try? FileManager.default.contentsOfDirectory(atPath: clash.path))?.count == 3,
          written.map(\.lastPathComponent).joined(separator: " | "))

    // A9.7. The check above is satisfied by ask-then-write, which is
    // time-of-check-to-time-of-use: two writers can both be told a name is free.
    // This app runs concurrent workers and finishes batches in the same second, so
    // the window is real. Driven concurrently — the property is that N writers
    // produce N files, whatever order the kernel serialises them in.
    let race = tmp.appendingPathComponent("race-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: race, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: race) }
    let group = DispatchGroup()
    let raceLock = NSLock()
    var racedPaths: Set<String> = []
    var raceFailures = 0
    for _ in 0..<12 {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = RunReport.write(context, to: race)
            raceLock.lock()
            if case .success(let u) = result { racedPaths.insert(u.lastPathComponent) }
            else { raceFailures += 1 }
            raceLock.unlock()
            group.leave()
        }
    }
    group.wait()
    let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: race.path))?.count ?? -1
    check("twelve reports written at once are twelve distinct files",
          racedPaths.count == 12 && onDisk == 12,
          "\(racedPaths.count) names, \(onDisk) files, \(raceFailures) refused")
    check("…and none of them was refused", raceFailures == 0, "\(raceFailures)")

    // CONTRIBUTING 4c — make the failure path actually fail. A report that
    // could not be written must say so, not return quietly.
    let dir = tmp.appendingPathComponent("report-\(UUID().uuidString)")
    switch RunReport.write(context, to: dir) {
    case .success(let url):
        check("a report writes to a directory that does not exist yet",
              FileManager.default.fileExists(atPath: url.path), url.path)
        check("…and reads back byte for byte",
              (try? String(contentsOf: url, encoding: .utf8)) == text)
    case .failure(let error):
        check("a report writes to a directory that does not exist yet", false,
              error.localizedDescription)
    }
    // A regular file where the directory should be: createDirectory fails, and
    // the caller has to be told rather than left to assume.
    let blocked = tmp.appendingPathComponent("blocked-\(UUID().uuidString)")
    try? Data("not a directory".utf8).write(to: blocked)
    switch RunReport.write(context, to: blocked) {
    case .success(let url):
        check("a report that cannot be written reports the failure", false,
              "wrote to \(url.path)")
    case .failure:
        check("a report that cannot be written reports the failure", true)
    }
    try? FileManager.default.removeItem(at: dir)
    try? FileManager.default.removeItem(at: blocked)
    resetPrefs()
}

// MARK: - Side-by-side fragments of one line keep their space

// The fourth property of the text layer, and it used to hold by accident.
// Vision splits one visual line of a newspaper column into fragments sitting
// side by side. There is no space character between them — each is its own
// CTLineDraw — so PDFKit synthesises the space from the geometric gap, and
// stops below roughly 0.15 em. Nothing reserved that gap: it existed only as
// slack left over from `minimumVertical` capping the font size. Widening runs
// to their true box width (which is what makes line ends selectable) closed it,
// and adjacent words welded: "valuablestudy", "Londos,and".
//
// This test drives `compose` with hand-built observations rather than real OCR,
// because the failure needs two fragments at a controlled distance and Vision's
// segmentation is not ours to dictate. It bites: with the reserve switched off
// the words weld, and the check for that runs first so a silently-ineffective
// guard cannot pass.

print("\ncalibrated constants have not drifted")

do {
    // T5. Tools/mutate.py moved each of these far enough to change behaviour and
    // re-ran the suite. Six survived — nothing went red — so the values the doc
    // comments describe as *measured* were not pinned by anything.
    //
    // Be clear about what this block is and is not. It is a **drift guard**, not
    // a behavioural test: it cannot tell you 1.5 is the right headroom factor.
    // What validates these values is the corpus, and what this stops is one of
    // them being changed in passing, months from now, with a green suite as
    // reassurance. Overclaiming here would be the exact mistake T4 records.
    //
    // Changing one deliberately means changing it here too, and re-running
    // Tools/score-corpus.swift over testdocs/ — 232 documents, about 16 minutes
    // — because that is the evidence, not this.
    check("baselineFraction is the calibrated 0.22",
          SearchableWriter.baselineFraction == 0.22,
          "\(SearchableWriter.baselineFraction); re-measure with Tools/probe-text-offset.swift")
    check("headroomFactor is the calibrated 1.5",
          SearchableWriter.headroomFactor == 1.5,
          "\(SearchableWriter.headroomFactor); 0.95 scored 80-83% line selection against 84-91%")
    check("reserveEms is the calibrated 0.25",
          SearchableWriter.reserveEms == 0.25,
          "\(SearchableWriter.reserveEms); 0 welds adjacent words — C18's fourth property")
    check("minimumVertical is the calibrated 0.25",
          SearchableWriter.minimumVertical == 0.25,
          "\(SearchableWriter.minimumVertical); 0.5 bottomed line-end out at 71% on newsprint")
    check("sameLineBaselineFraction is the calibrated 0.4",
          SearchableWriter.sameLineBaselineFraction == 0.4,
          "\(SearchableWriter.sameLineBaselineFraction)")
    check("duplicateBaselineFraction is the calibrated 0.3",
          SearchableWriter.duplicateBaselineFraction == 0.3,
          "\(SearchableWriter.duplicateBaselineFraction)")
    check("the DPI floor is the calibrated 150",
          Flattener.minimumPlausibleScanDPI == 150,
          "\(Flattener.minimumPlausibleScanDPI); below it a logo's DPI is not the page's")
    check("the fallback rebuild DPI is 300",
          Flattener.fallbackRebuildDPI == 300,
          "\(Flattener.fallbackRebuildDPI)")
    check("the picture ink threshold is the calibrated 0.15",
          Flattener.pictureInkThreshold == 0.15,
          "\(Flattener.pictureInkThreshold); text pages measured 6-8.4%")
    check("the ink branch's minimum tone is the calibrated 0.03",
          Flattener.pictureInkMinimumTone == 0.03,
          "\(Flattener.pictureInkMinimumTone); R38 — pictures 0.071-0.145, dense type 0.0017-0.0247")
    check("…and it sits below the tone threshold it corroborates",
          Flattener.pictureInkMinimumTone < Flattener.pictureToneThreshold,
          "\(Flattener.pictureInkMinimumTone) vs \(Flattener.pictureToneThreshold)")

    // reserveEms is the one the harness proved was *doubly* unguarded: the
    // fragment checks below set it themselves, so they exercise the mechanism
    // and say nothing about the shipped value. Restore it if a check left it
    // moved, so this block cannot be fooled by ordering.
    SearchableWriter.reserveEms = 0.25
}

print("\nresolution decisions the corpus rests on")

do {
    // Behavioural cover for two constants the drift guard only pins by value.
    // A page whose largest image is a small logo must NOT be rebuilt at the
    // logo's resolution — C14: a 595x841 pt page rebuilt as 16x23 px, page count
    // still matching, reported as success.
    let dir = tmp.appendingPathComponent("dpi-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let logoPage = dir.appendingPathComponent("logo.pdf")
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    if let ctx = CGContext(logoPage as CFURL, mediaBox: &box, nil) {
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(box)
        // A 40x40 px image drawn 200 pt wide: ~14 DPI, far below the floor.
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40,
                                      bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0),
           let cg = rep.cgImage {
            ctx.draw(cg, in: CGRect(x: 40, y: 700, width: 200, height: 60))
        }
        ctx.endPDFPage(); ctx.closePDF()
    }
    if let page = PDFDocument(url: logoPage)?.page(at: 0) {
        let native = Flattener.nativeDPI(of: page) ?? -1
        check("the fixture's largest image really is below the floor",
              native < Flattener.minimumPlausibleScanDPI && native > 0,
              String(format: "native %.1f DPI", native))
        check("a page whose only image is a logo rebuilds at the fallback, not the logo's DPI",
              Flattener.rebuildDPI(of: page) == Flattener.fallbackRebuildDPI,
              String(format: "%.1f, wanted %.0f",
                     Flattener.rebuildDPI(of: page), Flattener.fallbackRebuildDPI))
    }
}

print("\nsafeInt cannot be handed something that traps")

do {
    // T5. Mutating `guard value.isFinite` to `guard true` survived: nothing
    // reached safeInt with a non-finite value, because flatten checks that
    // first. The guard is defence in depth for a general-purpose helper, so it
    // is tested where it lives rather than only through a caller that happens
    // to protect it.
    check("a NaN yields zero rather than trapping", Flattener.safeInt(Double.nan) == 0)
    check("an infinity yields zero", Flattener.safeInt(Double.infinity) == 0
              && Flattener.safeInt(-Double.infinity) == 0)
    check("a value past Int's range saturates", Flattener.safeInt(1e30) == Int(9.0e18)
              && Flattener.safeInt(-1e30) == Int(-9.0e18))
    check("an ordinary value is unchanged", Flattener.safeInt(1234.7) == 1234)
}

// MARK: - The two conversions safeInt did not cover (A7.1, A3.2)

// `safeInt` exists because `Int(_:)` traps, and two conversions 1,300 lines below
// it were still bare — both on numbers descending entirely from what a file
// declares, and both on the **default** route. A trap is uncatchable and takes
// every concurrent file with it, so the hostile calls run in a child and this
// reads the markers it prints: exit 0 alone would only say nothing crashed, and
// the behaviour matters as much as the survival.

print("\nthe declared-geometry conversions cannot trap")

do {
    // Reachability first, because a bound on an unreachable value is not a fix.
    // `wide` reduces algebraically to the declared `/Width`, so any raster size
    // is reachable at any box scale and *both* routing gates pass: the page
    // renders as an ordinary 8000x10400 sheet that `qpdf --check` calls clean.
    let dir = tmp.appendingPathComponent("hostile-dpi-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let tiny = dir.appendingPathComponent("tinybox.pdf")
    let bodies = [
        "<</Type/Catalog/Pages 2 0 R>>",
        "<</Type/Pages/Kids[3 0 R]/Count 1>>",
        "<</Type/Page/Parent 2 0 R/MediaBox[0 0 0.00000000000001 0.000000000000013]"
            + "/Resources<</XObject<</Im0 4 0 R>>>>/Contents 5 0 R>>",
        "<</Type/XObject/Subtype/Image/Width 8000/Height 10400"
            + "/ColorSpace/DeviceGray/BitsPerComponent 8/Length 3>>\nstream\nabc\nendstream",
        "<</Length 1>>\nstream\n \nendstream",
    ]
    var raw = "%PDF-1.4\n"
    var offsets: [Int] = []
    for (i, body) in bodies.enumerated() {
        offsets.append(raw.utf8.count)
        raw += "\(i + 1) 0 obj\n\(body)\nendobj\n"
    }
    let startxref = raw.utf8.count
    raw += "xref\n0 \(bodies.count + 1)\n0000000000 65535 f \n"
    for off in offsets { raw += String(format: "%010d 00000 n \n", off) }
    raw += "trailer\n<</Size \(bodies.count + 1)/Root 1 0 R>>\nstartxref\n\(startxref)\n%%EOF\n"
    try? raw.write(to: tiny, atomically: true, encoding: .ascii)

    // Labelled for the tiny box specifically: R24's own probe block already has a
    // check called "the hostile fixture is a PDF the app will actually open", and
    // triage here is grepping 880 lines of log for the one that failed.
    check("the tiny-media-box fixture is a PDF the app will actually open",
          PDFDocument(url: tiny)?.pageCount == 1)
    if let page = PDFDocument(url: tiny)?.page(at: 0) {
        let dpi = Flattener.rebuildDPI(of: page)
        // Reading it is safe; converting it was not. Over 3.7e19 is what puts
        // `dpi / 4` past `Int.max`.
        check("a declared geometry really does produce a DPI past Int's range",
              dpi > 3.7e19, String(format: "%.3g", dpi))
    } else {
        check("the tiny-media-box page opens", false)
    }

    /// Runs the trapping calls in a child and hands back its markers.
    func hostileNumbers() -> (survived: Bool, markers: [String: String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        p.arguments = ["--probe-hostile-numbers"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return (false, [:]) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var markers: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { markers[String(parts[0])] = String(parts[1]) }
        }
        return (p.terminationReason == .exit && p.terminationStatus == 0, markers)
    }

    let probe = hostileNumbers()
    check("the hostile conversions do not take the process down", probe.survived,
          "the child died on a signal — Int(dpi / 4) or Int(NaN * width) trapped")
    // A7.1's upper half: the window is clamped to half the shorter side, because a
    // radius covering the whole image is the single global threshold Sauvola's own
    // doc comment exists to avoid. 8000x10400 -> 4000.
    check("…and the window is clamped to a local one", probe.markers["window"] == "4000",
          probe.markers["window"] ?? "missing")
    check("…with the floor still 3 for a nonsense DPI", probe.markers["windowNaN"] == "3",
          probe.markers["windowNaN"] ?? "missing")
    check("…and a tiny page cannot get a window of 1",
          probe.markers["windowTiny"] == "3", probe.markers["windowTiny"] ?? "missing")
    // sauvolaMask's own bound: `y + r + 1` overflows for an `r` that is merely
    // large, so a caller who did not go through the helper would still trap.
    check("sauvolaMask bounds its own radius", probe.markers["maskHuge"] == "64",
          probe.markers["maskHuge"] ?? "missing")
    // A3.2: skipped, not clamped. Including an absurd box would put the whole page
    // into the stencil, which is the harm `textRegionMask` exists to prevent.
    check("a non-finite word box is skipped and the good one is kept",
          probe.markers["mixed"] == probe.markers["goodOnly"]
            && (Int(probe.markers["goodOnly"] ?? "0") ?? 0) > 0,
          "mixed \(probe.markers["mixed"] ?? "?") vs good-only "
            + "\(probe.markers["goodOnly"] ?? "?")")
    check("…and an absurd one contributes nothing rather than the whole page",
          probe.markers["absurd"] == "0", probe.markers["absurd"] ?? "missing")

    // The other half of a trap fix: it must not *also* be a threshold change. The
    // window is compared against the expression it replaced, over every DPI the app
    // can render, on a page large enough that the new ceiling is not the binding
    // term. `safeInt` truncates, so these agree exactly; a `.rounded()` — which the
    // first version of this fix had — moves the window by a pixel wherever `dpi / 4`
    // lands on a half, which is about half of all pages, silently editing the 1-bit
    // stencil on the default route. Mutant: A7.1-sauvola-window-truncates.
    var windowDrift: [String] = []
    for tenths in 720...6_000 {
        let dpi = Double(tenths) / 10
        let now = Flattener.sauvolaWindow(dpi: dpi, width: 2550, height: 3300)
        let before = max(Int(dpi / 4), 3)
        if now != before { windowDrift.append("\(dpi): \(before) -> \(now)") }
    }
    check("the shipped window is unchanged for every DPI the app can render",
          windowDrift.isEmpty,
          "\(windowDrift.count) drifted, e.g. \(windowDrift.prefix(3).joined(separator: ", "))")
}

// MARK: - inkCoverage's two halves come from one population (A7.2)

print("\nink coverage cannot exceed one")

do {
    // The one fraction in Flattener whose numerator and denominator were
    // different populations: it walked all of `grey` and divided by
    // `width * height`. No shipped caller mismatches, so this was latent — but the
    // two constants a rescaled value would miscalibrate, `pictureInkThreshold` and
    // `pictureInkMinimumTone`, are the two whose miscalibration destroyed content
    // twice, and the next caller to hand it a downsampled buffer would not know.
    let allDark = [UInt8](repeating: 0, count: 4_000)
    check("a buffer larger than its stated size cannot exceed 1",
          Flattener.inkCoverage(of: allDark, width: 20, height: 20, threshold: 128) <= 1,
          String(Flattener.inkCoverage(of: allDark, width: 20, height: 20, threshold: 128)))
    check("…and reports the coverage of what it was actually given",
          Flattener.inkCoverage(of: allDark, width: 20, height: 20, threshold: 128) == 1)
    let short = [UInt8](repeating: 0, count: 100)
    check("a buffer smaller than its stated size is not under-reported 4x",
          Flattener.inkCoverage(of: short, width: 20, height: 20, threshold: 128) == 1,
          String(Flattener.inkCoverage(of: short, width: 20, height: 20, threshold: 128)))
    var half = [UInt8](repeating: 0, count: 200)
    for i in 100..<200 { half[i] = 255 }
    check("an ordinary buffer is unchanged",
          abs(Flattener.inkCoverage(of: half, width: 20, height: 10,
                                    threshold: 128) - 0.5) < 1e-9,
          String(Flattener.inkCoverage(of: half, width: 20, height: 10, threshold: 128)))
    check("an empty buffer is zero, not a division by zero",
          Flattener.inkCoverage(of: [], width: 20, height: 20, threshold: 128) == 0)
}

print("\nrepeated text in a column is not a duplicate")

do {
    // C22. `deduplicated` drops an observation repeating an already-kept one's
    // text within one line height in BOTH axes. The horizontal half is free in
    // an aligned column — identical text has identical width, so identical left
    // edges — and the vertical half is satisfied by two DIFFERENT ROWS whenever
    // the row pitch is smaller than the box height, which is ordinary typesetting:
    // Vision's boxes include ascender and descender space, so a 12 pt leading
    // inside a 13 pt box qualifies.
    //
    // It is the only line-dropping path in the writer that reports nothing: the
    // drop happens in compose before draw, so there is no Unplaced, no `skipped`,
    // produced == expected, and the file publishes as succeeded.
    let box = CGRect(x: 0, y: 0, width: 612, height: 792)
    func row(_ text: String, atPointsFromTop y: Double, heightPoints h: Double = 13,
             xFraction: Double = 0.20) -> SearchableWriter.Observation {
        SearchableWriter.Observation(
            boundingBox: SearchableWriter.BoundingBox(
                x: xFraction, y: y / 792.0, width: 0.12, height: h / 792.0),
            text: text, confidence: 1.0)
    }

    // A pay table: the same figure on four consecutive rows, 12 pt apart, in
    // boxes 13 pt tall. Every row after the first was being deleted.
    let table = (0..<4).map { row("1,000", atPointsFromTop: 300 + Double($0) * 12) }
    let keptTable = SearchableWriter.deduplicated(table, in: box)
    check("four rows of a column repeating one figure all survive",
          keptTable.count == 4, "kept \(keptTable.count) of 4")

    // Tighter still — 10 pt leading in a 13 pt box, which is what archival
    // typescript looks like.
    let tight = (0..<3).map { row("Ibid.", atPointsFromTop: 400 + Double($0) * 10) }
    check("…and at a 10 pt leading in a 13 pt box",
          SearchableWriter.deduplicated(tight, in: box).count == 3,
          "kept \(SearchableWriter.deduplicated(tight, in: box).count) of 3")

    // C4 is why this function exists and must keep working: mac-ocr's `auto`
    // strategy emits the same line twice, and the twin sits on top of the
    // original, not a row below it.
    let exactTwin = [row("the text", atPointsFromTop: 500),
                     row("the text", atPointsFromTop: 500)]
    check("an exact duplicate is still dropped",
          SearchableWriter.deduplicated(exactTwin, in: box).count == 1,
          "kept \(SearchableWriter.deduplicated(exactTwin, in: box).count) of 2")

    // Rounding between the two passes moves it by a fraction of a point.
    let jittered = [row("the text", atPointsFromTop: 500),
                    row("the text", atPointsFromTop: 500.4)]
    check("…as is one that differs only by rounding",
          SearchableWriter.deduplicated(jittered, in: box).count == 1,
          "kept \(SearchableWriter.deduplicated(jittered, in: box).count) of 2")

    // And the original reason for the horizontal half: a running head that
    // repeats a phrase from the body is not a duplicate.
    let head = [row("The Nature of Managerial Work", atPointsFromTop: 60, xFraction: 0.20),
                row("The Nature of Managerial Work", atPointsFromTop: 60, xFraction: 0.62)]
    check("the same words elsewhere on the line are not a duplicate",
          SearchableWriter.deduplicated(head, in: box).count == 2,
          "kept \(SearchableWriter.deduplicated(head, in: box).count) of 2")
}

print("\nadjacent fragments of one line keep their space")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("sidebyside")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let page = dir.appendingPathComponent("page.pdf")
    makeScannedPDF(at: page, lines: ["ignored — the layer is built from the boxes below"])

    // Two fragments on one baseline, boxes touching: the newspaper case.
    func frag(_ text: String, x: Double, width w: Double) -> SearchableWriter.Observation {
        SearchableWriter.Observation(
            boundingBox: SearchableWriter.BoundingBox(x: x, y: 0.30, width: w, height: 0.022),
            text: text, confidence: 1.0)
    }
    let left = frag("that", x: 0.10, width: 0.055)
    let right = frag("measurable by standardised", x: 0.156, width: 0.30)

    func extract(reserve: CGFloat) -> String {
        SearchableWriter.reserveEms = reserve
        let out = dir.appendingPathComponent("layer-\(reserve).pdf")
        try? SearchableWriter.compose(visible: page, observations: [1: [left, right]],
                                      to: out, drawImages: false)
        // NOT flattening newlines into spaces: this assertion exists to tell
        // one separator from another, and "that\nmeasurable" would satisfy a
        // contains("that measurable") check on a flattened string. PDFKit does
        // not currently emit a newline between same-baseline runs — swept the
        // gap 0-150 pt — but an assertion that could not tell is no assertion.
        return PDFDocument(url: out)?.string ?? ""
    }

    // 1. Without the reserve the two fragments weld. If this ever stops being
    //    true the test below proves nothing, so it is checked, not assumed.
    let welded = extract(reserve: 0)
    check("without the reserve, adjacent fragments weld",
          welded.contains("thatmeasurable"),
          "got: '\(welded.prefix(60))' — if this no longer welds, the guard below is untested")

    // 2. With it, the space survives.
    let spaced = extract(reserve: 0.25)
    check("with the reserve, the space survives",
          spaced.contains("that measurable"), "got: '\(spaced.prefix(60))'")
    check("…and no word is welded", !spaced.contains("thatmeasurable"), spaced.prefix(60).description)
    check("…and both fragments are still present",
          spaced.contains("that") && spaced.contains("standardised"), spaced.prefix(80).description)

    SearchableWriter.reserveEms = 0.25

    // The reserve must be 0.25 em OF THE RUN ACTUALLY DRAWN, not of the size it
    // would have had before shrinking. Budgeting against the pre-shrink size
    // makes the reserve a flat fraction of the line height, so the cost falls as
    // ~0.5/n for an n-character fragment: measured, a one-character fragment
    // kept 21% of its width and a narrow one collapsed past the 0.5 pt size
    // floor, where `size * vertical == wanted` stops holding entirely.
    func drawnWidth(_ text: String, boxWidth: Double, neighbourAt: Double?) -> Double {
        let me = frag(text, x: 0.10, width: boxWidth)
        var obs = [me]
        if let n = neighbourAt { obs.append(frag("next", x: n, width: 0.20)) }
        let out = dir.appendingPathComponent("w-\(text.count)-\(neighbourAt ?? -1).pdf")
        try? SearchableWriter.compose(visible: page, observations: [1: obs],
                                      to: out, drawImages: false)
        guard let doc = PDFDocument(url: out), let pg = doc.page(at: 0) else { return 0 }
        // Selection bounds of this fragment's own text = what was really drawn.
        guard let sel = pg.selection(for: pg.bounds(for: .mediaBox)) else { return 0 }
        _ = sel
        let b = pg.bounds(for: .mediaBox)
        var right = 0.0
        for step in stride(from: 0.10, through: 0.70, by: 0.005) {
            let r = CGRect(x: b.minX + b.width * step, y: b.maxY - b.height * 0.34,
                           width: b.width * 0.004, height: b.height * 0.03)
            if !((pg.selection(for: r)?.string ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines).isEmpty) { right = step }
        }
        return right
    }

    // A short fragment with a close neighbour keeps most of its box. The
    // neighbour sits just past the box edge, so only the reserve is in play.
    let shortAlone = drawnWidth("in", boxWidth: 0.030, neighbourAt: nil)
    let shortNext  = drawnWidth("in", boxWidth: 0.030, neighbourAt: 0.131)
    check("a short fragment keeps most of its width next to a neighbour",
          shortNext > shortAlone * 0.55,
          String(format: "alone reached %.3f, with a neighbour %.3f", shortAlone, shortNext))

    // Vision's fragment boxes routinely overlap by a point or two. The reserve
    // used to be skipped entirely past 0.5 pt of overlap — a cliff — and the
    // words welded again with no signal.
    let overlapping = frag("that", x: 0.10, width: 0.058)      // right edge 0.158
    let intruder = frag("measurable by standardised", x: 0.156, width: 0.30)
    let ovOut = dir.appendingPathComponent("overlap.pdf")
    try? SearchableWriter.compose(visible: page, observations: [1: [overlapping, intruder]],
                                  to: ovOut, drawImages: false)
    let ovText = (PDFDocument(url: ovOut)?.string ?? "").replacingOccurrences(of: "\n", with: " ")
    check("boxes that overlap by more than half a point still get the reserve",
          !ovText.contains("thatmeasurable"), "got: '\(ovText.prefix(60))'")

    // The narrowest fragments are the ones the old arithmetic protected least:
    // `allowed = rightLimit - gap - left` went NEGATIVE when a fragment's own
    // advance was shorter than the reserve, and the guard was skipped rather
    // than clamped. Measured before the fix: "l", "i", "j" and "\'" all welded.
    for tiny in ["l", "i", "j"] {
        let small = frag(tiny, x: 0.10, width: 0.006)
        let after = frag("following words here", x: 0.107, width: 0.24)
        let out = dir.appendingPathComponent("tiny-\(tiny).pdf")
        try? SearchableWriter.compose(visible: page, observations: [1: [small, after]],
                                      to: out, drawImages: false)
        let got = PDFDocument(url: out)?.string ?? ""
        check("a one-character fragment (\(tiny)) does not weld to its neighbour",
              !got.contains("\(tiny)following"), got.prefix(40).description)
    }

    // C20. The band where headroom and rightLimit used to disagree. Two
    // fragments of ONE visual line whose drawn baselines differ only because one
    // has descenders and the other does not: 0.78 x the height difference, about
    // 1.9 pt here. rightLimit called that the same line (under 0.4 x the shorter
    // height); headroom called it a vertical neighbour (over 0.5 pt, with more
    // than 1 pt of horizontal overlap). Both fired, so the pair was shrunk by the
    // reserve — correct — and crushed by the ceiling — not.
    //
    // Note the existing checks above cannot see this: `frag` gives every
    // fragment the same y and height, so their baselines are identical, the gap
    // is 0, and headroom sits out.
    func band(_ text: String, x: Double, width w: Double, height h: Double)
        -> SearchableWriter.Observation {
        SearchableWriter.Observation(
            boundingBox: SearchableWriter.BoundingBox(x: x, y: 0.30, width: w, height: h),
            text: text, confidence: 1.0)
    }
    // 0.0130 x 792 = 10.3 pt with descenders; 0.0100 x 792 = 7.9 pt without.
    // Baselines differ by 0.78 x 2.4 = 1.9 pt: over headroom's 0.5, under
    // rightLimit's 0.4 x 7.9 = 3.2. Boxes overlap by 1.5 pt, clearing the `> 1`.
    let descender = band("typographic", x: 0.10, width: 0.30, height: 0.0130)
    let ascender  = band("measurable", x: 0.39755, width: 0.20, height: 0.0100)

    let bandOut = dir.appendingPathComponent("band.pdf")
    try? SearchableWriter.compose(visible: page, observations: [1: [descender, ascender]],
                                  to: bandOut, drawImages: false)

    // How far right the first fragment is actually selectable. Its box ends at
    // x = 0.40; crushed to a quarter width it stops around 0.175.
    // Scanning the rows too, not guessing one: a crushed run is barely a point
    // tall, so a probe at a fixed height can miss it entirely and report 0.000
    // for both the broken and the fixed build — which is a test that cannot fail
    // in the useful direction.
    // Stopping short of 0.39755, where the SECOND fragment starts: scanning
    // into it means any hit there is the neighbour's text, and the probe reports
    // the line as fully covered however badly the first run was crushed. That is
    // how the first version of this check passed against the bug.
    var reach = 0.0
    var reachedText = ""
    if let doc = PDFDocument(url: bandOut), let pg = doc.page(at: 0) {
        let b = pg.bounds(for: .mediaBox)
        for step in stride(from: 0.10, through: 0.390, by: 0.005) {
            var hit = false
            for row in stride(from: 0.290, through: 0.330, by: 0.002) {
                let r = CGRect(x: b.minX + b.width * step, y: b.maxY - b.height * row,
                               width: b.width * 0.004, height: b.height * 0.004)
                let got = (pg.selection(for: r)?.string ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !got.isEmpty { hit = true; reachedText = got; break }
            }
            if hit { reach = step }
        }
    }
    check("a fragment whose neighbour differs only by a descender still spans its box",
          reach > 0.34,
          String(format: "selectable only to %.3f of the page; its box ends at 0.400, "
                 + "last hit '%@'", reach, reachedText))

    // And the other three properties still hold for the same pair.
    let bandText = (PDFDocument(url: bandOut)?.string ?? "")
        .replacingOccurrences(of: "\n", with: " ")
    check("…and the two words do not weld",
          !bandText.contains("typographicmeasurable"), bandText.prefix(60).description)
    check("…and both fragments are still there",
          bandText.contains("typographic") && bandText.contains("measurable"),
          bandText.prefix(60).description)

    // A tall element must not treat a body line a row away as its own
    // neighbour. Baselines differ by far more than the shorter height.
    let headline = SearchableWriter.Observation(
        boundingBox: SearchableWriter.BoundingBox(x: 0.10, y: 0.20, width: 0.30, height: 0.060),
        text: "A DISPLAY HEADLINE", confidence: 1.0)
    let bodyNextColumn = SearchableWriter.Observation(
        boundingBox: SearchableWriter.BoundingBox(x: 0.42, y: 0.235, width: 0.30, height: 0.018),
        text: "body text one row up in the next column", confidence: 1.0)
    let tallOut = dir.appendingPathComponent("tall.pdf")
    try? SearchableWriter.compose(visible: page, observations: [1: [headline, bodyNextColumn]],
                                  to: tallOut, drawImages: false)
    let tallText = (PDFDocument(url: tallOut)?.string ?? "")
    check("a tall element is not shrunk by a body line on another row",
          tallText.contains("DISPLAY HEADLINE"), tallText.prefix(70).description)

    // A line with nothing to its right must be untouched — the reserve is a
    // no-op there, and shortening those runs is exactly the bug being fixed.
    let alone = frag("a line with no neighbour to its right at all", x: 0.10, width: 0.60)
    let onlyOut = dir.appendingPathComponent("alone.pdf")
    try? SearchableWriter.compose(visible: page, observations: [1: [alone]],
                                  to: onlyOut, drawImages: false)
    let aloneText = (PDFDocument(url: onlyOut)?.string ?? "")
    check("a line with no right-hand neighbour still gets its full width",
          aloneText.contains("no neighbour"), aloneText.prefix(60).description)
    resetPrefs()
}

// MARK: - The rename must not cost anyone their settings

// A bundle identifier IS the preferences domain, so renaming the app to Vision
// OCR moves it — and without a migration everyone silently loses their output
// folder, language list and mac-ocr path on a release that only changed a name.

print("\nsaying what the confidence setting means")

do {
    // "Min. confidence — 0.00" is a label, a number and no information: no
    // units, no direction, and nothing about what happens to the text on the
    // wrong side of it. The readout has to answer the question someone
    // actually has, which at the default is "so is this doing anything?".
    check("the default says what the default does, not '0.00'",
          Prefs.confidenceReadout(0) == "keep everything",
          Prefs.confidenceReadout(0))
    check("…and never shows a bare decimal at any position",
          !stride(from: 0.0, through: 1.0, by: 0.05)
              .map(Prefs.confidenceReadout)
              .contains { $0.first?.isNumber == true },
          Prefs.confidenceReadout(0.35))
    check("a raised threshold says which way the discarding runs",
          Prefs.confidenceReadout(0.4) == "drop below 40%",
          Prefs.confidenceReadout(0.4))
    check("…in whole percent, because a scan is not a measurement",
          Prefs.confidenceReadout(0.355) == "drop below 36%",
          Prefs.confidenceReadout(0.355))
    check("the top of the slider is 100%, not 1",
          Prefs.confidenceReadout(1) == "drop below 100%",
          Prefs.confidenceReadout(1))

    // The consequence is invisible in the output, so it is stated on the panel
    // rather than in a tooltip nobody hovers.
    check("no warning at the default, where there is nothing to warn about",
          Prefs.confidenceWarning(0) == nil,
          Prefs.confidenceWarning(0) ?? "nil")
    check("a warning the moment it is raised at all",
          Prefs.confidenceWarning(0.01) != nil)
    check("…that says the words go missing, not that they are 'discarded'",
          (Prefs.confidenceWarning(0.4) ?? "").contains("missing")
            && (Prefs.confidenceWarning(0.4) ?? "").contains("nothing to show"),
          Prefs.confidenceWarning(0.4) ?? "nil")
    check("…and names the same percentage the readout does",
          (Prefs.confidenceWarning(0.4) ?? "").contains("40%"),
          Prefs.confidenceWarning(0.4) ?? "nil")

    // The label has to fit the panel's fixed 116pt label column, which is what
    // "Discard uncertain text" would not do — it would silently truncate.
    let label = "Uncertain text"
    let width = (label as NSString).size(withAttributes: [
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width
    check("the row label fits the label column without truncating",
          width <= 116, String(format: "%.0f pt", width))

    // …and so must the readout itself, in the 96pt column beside the slider.
    // Truncation is the failure mode for a phrase where a number used to be:
    // "keep everyth…" is worse than the 0.00 it replaced.
    let caption = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    var widest = 0.0, widestText = ""
    for step in stride(from: 0.0, through: 1.0, by: 0.01) {
        let text = Prefs.confidenceReadout(step)
        let w = (text as NSString).size(withAttributes: [.font: caption]).width
        if w > widest { widest = w; widestText = text }
    }
    check("the widest readout the slider can produce fits its column",
          widest <= 96, String(format: "\"%@\" is %.0f pt", widestText, widest))
}

print("\nwhat the rebuild does, and to which files")

do {
    // The Settings panel used to say the rebuild is "only applied to files that
    // already contain text". True with JBIG2 off, false with it on — and it is
    // on by default. JBIG2 is a bilevel codec, so it needs every page as a
    // bitmap, which means switching on a *compression* option re-renders pages
    // that had nothing wrong with them.
    resetPrefs()
    var s = Prefs.Snapshot.current()

    s.useJBIG2 = false
    check("with JBIG2 off, an untouched file really is left alone",
          !OCRModel.willRebuild(hasEmbeddedText: false, rebuild: true, settings: s,
                                mode: .auto, jbig2Available: true))
    check("…while one carrying an old text layer is rebuilt, which is the point",
          OCRModel.willRebuild(hasEmbeddedText: true, rebuild: true, settings: s,
                               mode: .auto, jbig2Available: true))

    s.useJBIG2 = true
    check("with JBIG2 on, every file is rebuilt, text layer or not",
          OCRModel.willRebuild(hasEmbeddedText: false, rebuild: true, settings: s,
                               mode: .auto, jbig2Available: true))
    check("…unless the codec is not installed, where it falls back and leaves it",
          !OCRModel.willRebuild(hasEmbeddedText: false, rebuild: true, settings: s,
                                mode: .auto, jbig2Available: false))
    check("…and not in Grayscale, which JBIG2 cannot encode",
          !OCRModel.willRebuild(hasEmbeddedText: false, rebuild: true, settings: s,
                                mode: .grayscale, jbig2Available: true))
    check("turning the rebuild off turns it off, whatever JBIG2 says",
          !OCRModel.willRebuild(hasEmbeddedText: true, rebuild: false, settings: s,
                                mode: .auto, jbig2Available: true))

    // And what the rebuild costs: there is no colour path through it at all.
    // `render` draws into a DeviceGray context, so every mode discards colour —
    // Auto only chooses between 1-bit and grey. Worth pinning, because the
    // saturation signal exists to *detect* colour, which reads as if colour
    // were preserved somewhere.
    let dir = tmp.appendingPathComponent("colour-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let colour = dir.appendingPathComponent("colour.pdf")
    var cbox = CGRect(x: 0, y: 0, width: 612, height: 792)
    if let c = CGContext(colour as CFURL, mediaBox: &cbox, nil) {
        c.beginPDFPage(nil)
        for (i, col) in [CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1),
                         CGColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1),
                         CGColor(red: 0.95, green: 0.75, blue: 0.05, alpha: 1)].enumerated() {
            c.setFillColor(col)
            c.fill(CGRect(x: 60, y: 400 + CGFloat(i) * 90, width: 480, height: 84))
        }
        c.endPDFPage(); c.closePDF()
    }

    /// Mean saturation of a rendered page. 0 means nothing coloured survived.
    func saturation(of url: URL) -> Double {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return -1 }
        let box = page.bounds(for: .mediaBox)
        let w = 120, h = Int(120 * box.height / box.width)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return -1 }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: CGFloat(w) / box.width, y: CGFloat(w) / box.width)
        page.draw(with: .mediaBox, to: ctx)
        guard let data = ctx.data else { return -1 }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var total = 0.0
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
            let mx = max(r, g, b), mn = min(r, g, b)
            total += mx > 0 ? (mx - mn) / mx : 0
        }
        return total / Double(w * h)
    }

    check("the fixture is genuinely coloured, or the checks below prove nothing",
          saturation(of: colour) > 0.1, String(format: "%.3f", saturation(of: colour)))

    // MARK: Aged paper is not a colour page
    //
    // A 600-page 1964 monograph came out of this app at 709 MB against a 33 MB
    // original — every page a full-resolution three-channel JPEG. Ink coverage
    // (0.11) and tone fraction (0.009) both said "text" on every one of them.
    // Only saturation fired, at 0.078-0.089 against a 0.06 threshold, because
    // the paper is cream. That one signal then did two jobs: it took the page
    // off the 1-bit route *and* promoted it to three channels, so the same 0.02
    // was charged twice. Measured on five real pages: 1,185 KB/page as shipped,
    // 48 KB/page as 1-bit — and the 1-bit rendering is clean.
    //
    // The signal cannot be rescued by moving the threshold. Over the corpus the
    // six wrongly-promoted text pages span saturation 0.061-0.113 and the
    // eighteen genuinely coloured ones span 0.061-…: the two populations
    // overlap almost exactly. So the measure itself has to change — saturation
    // is now measured relative to the page's own paper rather than to grey.
    let cream = dir.appendingPathComponent("cream.pdf")
    makeScannedPDF(at: cream, lines: (1...22).map {
        "Line \($0) of ordinary black text on aged cream book paper."
    }, paper: NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.86, alpha: 1))
    let creamSat = Flattener.saturation(of: PDFDocument(url: cream)!.page(at: 0)!)
    check("a cream-paper text page does not read as colour",
          creamSat <= Flattener.pictureSaturationThreshold,
          String(format: "%.4f vs threshold %.2f", creamSat,
                 Flattener.pictureSaturationThreshold))
    // The whole point is that it stays on the cheap route, so assert the route
    // and not merely the number that feeds it.
    let cpngs2 = dir.appendingPathComponent("cream-pngs")
    try? FileManager.default.createDirectory(at: cpngs2, withIntermediateDirectories: true)
    let creamPages = (try? Flattener.flatten(cream,
                                             to: dir.appendingPathComponent("cream-out.pdf"),
                                             mode: .auto, pngDirectory: cpngs2)) ?? []
    check("…and rebuilds 1-bit, not as a colour JPEG",
          !creamPages.isEmpty && creamPages.allSatisfy {
              if case .bilevel = $0.content { return !$0.isColour }
              return false
          },
          creamPages.map { "\($0.content) colour=\($0.isColour)" }.joined(separator: ","))
    // Both directions, or a measure that always returns zero would pass.
    check("…while a page with real colour on it is still detected",
          Flattener.saturation(of: PDFDocument(url: colour)!.page(at: 0)!)
              > Flattener.pictureSaturationThreshold,
          String(format: "%.4f",
                 Flattener.saturation(of: PDFDocument(url: colour)!.page(at: 0)!)))
    // Across the range of stock archival material is actually printed on, not
    // just the one shade that produced the bug report. The concern this answers
    // is that the correction's per-channel gain grows with the tint, so a strong
    // one could in principle amplify the residual on neutral ink past the
    // threshold — arithmetically 0.118 per pixel for pure black on cream. It
    // does not happen, because at 40 DPI almost every text pixel is a blend of
    // ink and paper.
    for (name, paper) in [
        ("tan", NSColor(calibratedRed: 0.90, green: 0.83, blue: 0.70, alpha: 1)),
        ("manila", NSColor(calibratedRed: 0.88, green: 0.78, blue: 0.58, alpha: 1)),
        ("legal-pad yellow", NSColor(calibratedRed: 1.00, green: 0.98, blue: 0.55, alpha: 1)),
        ("ochre", NSColor(calibratedRed: 0.85, green: 0.70, blue: 0.35, alpha: 1)),
    ] {
        let stock = dir.appendingPathComponent("stock-\(name.replacingOccurrences(of: " ", with: "-")).pdf")
        makeScannedPDF(at: stock, lines: (1...22).map {
            "Line \($0) of ordinary black text on \(name) book paper."
        }, paper: paper)
        let s = Flattener.saturation(of: PDFDocument(url: stock)!.page(at: 0)!)
        check("…and on \(name) stock too, however strong the tint",
              s <= Flattener.pictureSaturationThreshold, String(format: "%.4f", s))
    }

    // The correction must not eat a real colour cast. A page that is *all*
    // image has no paper on it, so there is nothing to white-balance against —
    // and measuring "paper" from the image itself would neutralise exactly the
    // colour we are trying to detect. `paperLuminanceFloor` is what prevents
    // that, and it survived a mutation to 10.0 until this check existed: with
    // every dark pixel counted as paper, `minimumPaperFraction` is satisfied by
    // any page at all and the guard stops guarding.
    let fullBleed = dir.appendingPathComponent("full-bleed.pdf")
    var fbox = CGRect(x: 0, y: 0, width: 612, height: 792)
    if let c = CGContext(fullBleed as CFURL, mediaBox: &fbox, nil) {
        c.beginPDFPage(nil)
        // A sepia plate covering the sheet, mid-tone so nothing clears the
        // paper floor. Strongly tinted, and none of it is paper.
        for i in 0..<40 {
            let t = CGFloat(i) / 40
            c.setFillColor(CGColor(red: 0.55 + t * 0.22, green: 0.36 + t * 0.16,
                                   blue: 0.16 + t * 0.08, alpha: 1))
            c.fill(CGRect(x: 0, y: CGFloat(i) * 792 / 40, width: 612, height: 792 / 40 + 1))
        }
        c.endPDFPage(); c.closePDF()
    }
    let bleedSat = Flattener.saturation(of: PDFDocument(url: fullBleed)!.page(at: 0)!)
    check("a full-bleed tinted plate keeps its colour, not corrected away",
          bleedSat > Flattener.pictureSaturationThreshold,
          String(format: "%.4f vs threshold %.2f", bleedSat,
                 Flattener.pictureSaturationThreshold))
    // …and the mechanism behind it, on buffers rather than through a render.
    func rgba(_ r: UInt8, _ g: UInt8, _ b: UInt8, count: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count * 4)
        for _ in 0..<count { out.append(contentsOf: [r, g, b, 255]) }
        return out
    }
    let creamBuf = rgba(245, 237, 219, count: 400)
    check("paper is found on a page that has paper",
          Flattener.paperColour(ofRGBA: creamBuf, width: 20, height: 20) != nil)
    // Mid-tone sepia: every pixel below the floor, so there is no paper here.
    let sepiaBuf = rgba(150, 100, 45, count: 400)
    check("…and not invented on a page that has none",
          Flattener.paperColour(ofRGBA: sepiaBuf, width: 20, height: 20) == nil)
    // A page that is mostly plate with a thin white margin: too little paper to
    // believe, which is what minimumPaperFraction is for.
    var mostlyPlate = rgba(150, 100, 45, count: 380)
    mostlyPlate.append(contentsOf: rgba(250, 250, 250, count: 20))   // 5% margin
    check("…and not believed from a 5% margin",
          Flattener.paperColour(ofRGBA: mostlyPlate, width: 20, height: 20) == nil)

    // A plain white scan must not move: it had no tint to correct for.
    let plainWhite = dir.appendingPathComponent("plain-white.pdf")
    makeScannedPDF(at: plainWhite, lines: (1...22).map {
        "Line \($0) of ordinary black text on plain white paper."
    })
    let plainSat = Flattener.saturation(of: PDFDocument(url: plainWhite)!.page(at: 0)!)
    check("…and a white-paper page still reads as no colour at all",
          plainSat <= Flattener.pictureSaturationThreshold,
          String(format: "%.4f", plainSat))

    // Automatic keeps it; the two modes that are instructions rather than
    // questions do what they were told.
    for mode in Flattener.Mode.allCases {
        let out = dir.appendingPathComponent("out-\(mode.rawValue).pdf")
        _ = try? Flattener.flatten(colour, to: out, mode: mode, password: nil,
                                   pngDirectory: nil, isCancelled: { false },
                                   progress: { _, _ in }, onPage: nil)
        let sat = saturation(of: out)
        if mode == .auto {
            check("Automatic keeps a colour page in colour",
                  sat > 0.1, String(format: "%.3f", sat))
        } else {
            check("\(mode.label) is an instruction, and discards colour as asked",
                  sat == 0, String(format: "%.3f", sat))
        }
    }

    // The colour path must not reach pages that have no colour in them. A page
    // of ordinary text stays 1-bit — the whole size argument for Automatic —
    // and a grey halftone stays a grey JPEG rather than paying three channels
    // for one channel's worth of information.
    let textPage = dir.appendingPathComponent("text.pdf")
    makeScannedPDF(at: textPage, lines: (1...24).map {
        "Line \($0) of ordinary black text on white paper, nothing coloured here."
    })
    let textPNGs = dir.appendingPathComponent("text-pngs")
    try? FileManager.default.createDirectory(at: textPNGs, withIntermediateDirectories: true)
    let textPages = (try? Flattener.flatten(textPage,
                                            to: dir.appendingPathComponent("text-out.pdf"),
                                            mode: .auto, pngDirectory: textPNGs)) ?? []
    check("a plain text page still rebuilds 1-bit, not as a colour JPEG",
          !textPages.isEmpty && textPages.allSatisfy {
              if case .bilevel = $0.content { return !$0.isColour }
              return false
          },
          textPages.map { "\($0.isColour)" }.joined(separator: ","))

    // The bound, checked as a decision rather than by allocating the page it
    // describes. Four bytes a pixel is why it exists.
    let underBound = Double(Flattener.maximumColourPageMegapixels) * 1_000_000 - 1
    let overBound = Double(Flattener.maximumColourPageMegapixels) * 1_000_000 + 1
    check("a colourful page inside the memory bound keeps its colour",
          Flattener.shouldKeepColour(mode: .auto, saturation: 0.3, pixels: underBound))
    check("…and past it gives the colour up rather than the four-byte allocation",
          !Flattener.shouldKeepColour(mode: .auto, saturation: 0.3, pixels: overBound))
    // This check replaces one that asserted the bound was "a quarter of the grey
    // one, so peak memory is unchanged". Both halves were false: the grey buffer
    // is still alive when the RGBA one is allocated, and both are copied again
    // into a bitmap rep, a JPEG and a decoded CGImage. Measured peak RSS on a
    // 64.8 MP page: 356 MB grey, 1,261 MB colour. What the bound has to satisfy
    // is that colour cannot reach a high-water mark grey could not already.
    check("the colour bound's worst case stays inside the grey one's",
          Flattener.colourBoundIsWithinTheGreyOne,
          String(format: "colour %.2f GB vs grey %.2f GB",
                 Double(Flattener.maximumColourPageMegapixels)
                    * Flattener.measuredColourBytesPerPixel / 1000,
                 Double(Flattener.maximumPageMegapixels)
                    * Flattener.measuredGreyBytesPerPixel / 1000))
    check("…and the colour path is still recorded as the more expensive one",
          Flattener.measuredColourBytesPerPixel > Flattener.measuredGreyBytesPerPixel)
    check("a grey page is never promoted to colour, whatever its size",
          !Flattener.shouldKeepColour(mode: .auto, saturation: 0, pixels: 1000))
    check("…and colour is Automatic's decision alone",
          !Flattener.shouldKeepColour(mode: .grayscale, saturation: 0.3, pixels: 1000)
            && !Flattener.shouldKeepColour(mode: .blackAndWhite, saturation: 0.3, pixels: 1000))
    check("the threshold is the same one that routes the page here",
          !Flattener.shouldKeepColour(mode: .auto,
                                      saturation: Flattener.pictureSaturationThreshold,
                                      pixels: 1000)
            && Flattener.shouldKeepColour(mode: .auto,
                                          saturation: Flattener.pictureSaturationThreshold + 0.001,
                                          pixels: 1000))

    // And the half that renders as noise if it is wrong: a three-channel stream
    // in the JBIG2 merge has to be declared /DeviceRGB. Nothing reports this —
    // the page simply draws as static.
    let cpngs = dir.appendingPathComponent("colour-pngs")
    try? FileManager.default.createDirectory(at: cpngs, withIntermediateDirectories: true)
    let cpages = (try? Flattener.flatten(colour,
                                         to: dir.appendingPathComponent("colour-rebuilt.pdf"),
                                         mode: .auto, pngDirectory: cpngs)) ?? []
    check("the colour page comes back marked as colour",
          cpages.count == 1 && cpages[0].isColour,
          cpages.map { "\($0.isColour)" }.joined(separator: ","))
    if let first = cpages.first, case .jpeg(let j) = first.content {
        let merged = dir.appendingPathComponent("colour-merged.pdf")
        let page = JBIG2.Page(stream: .jpeg(j), pixelWidth: first.pixelWidth,
                              pixelHeight: first.pixelHeight, boxSize: first.boxSize,
                              isColour: true)
        do { try JBIG2.assemble([page], to: merged) } catch {
            check("the colour page assembles", false, error.localizedDescription)
        }
        let raw = String(decoding: (try? Data(contentsOf: merged)) ?? Data(), as: UTF8.self)
        check("the merged stream declares DeviceRGB, not DeviceGray",
              raw.contains("/DeviceRGB") && !raw.contains("/DeviceGray"),
              raw.contains("/DeviceGray") ? "declared /DeviceGray" : "declared neither")
        check("…and the merged page is still coloured when drawn",
              saturation(of: merged) > 0.1,
              String(format: "%.3f", saturation(of: merged)))
        // A grey page through the same merge must keep saying DeviceGray.
        let greyMerged = dir.appendingPathComponent("grey-merged.pdf")
        let greyPage = JBIG2.Page(stream: .jpeg(j), pixelWidth: first.pixelWidth,
                                  pixelHeight: first.pixelHeight, boxSize: first.boxSize)
        try? JBIG2.assemble([greyPage], to: greyMerged)
        let greyRaw = String(decoding: (try? Data(contentsOf: greyMerged)) ?? Data(),
                             as: UTF8.self)
        check("…while a page not marked colour still declares DeviceGray",
              greyRaw.contains("/DeviceGray"), "did not")
    }

    // Row stride. `jpegRGB` packs RGBA into a 24-bit rep at bytesPerRow =
    // width * 3, which AppKit is free to ignore and pad to its own alignment.
    // If it did, the tight three-byte copy would skew every row progressively.
    //
    // The first version of this sampled two corners of a two-block pattern and
    // was worthless: a one-pixel-per-row shear leaves a big red block still
    // reddish in the top-left, so a deliberately padded stride passed it. What
    // catches a shear is comparing the whole page against the original, which
    // is also the property actually wanted — the rebuild should look like the
    // page it rebuilt.
    func meanChannelDifference(_ a: URL, _ b: URL) -> Double? {
        func sample(_ url: URL) -> ([UInt8], Int, Int)? {
            guard let d = PDFDocument(url: url), let p = d.page(at: 0) else { return nil }
            let box = p.bounds(for: .mediaBox)
            let w = 48, h = max(Int(48 * box.height / box.width), 1)
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: CGFloat(w) / box.width, y: CGFloat(w) / box.width)
            p.draw(with: .mediaBox, to: ctx)
            guard let raw = ctx.data else { return nil }
            let buf = UnsafeBufferPointer(start: raw.bindMemory(to: UInt8.self,
                                                                capacity: w * h * 4),
                                          count: w * h * 4)
            return (Array(buf), w, h)
        }
        guard let (x, w1, h1) = sample(a), let (y, w2, h2) = sample(b),
              w1 == w2, h1 == h2 else { return nil }
        var total = 0.0, n = 0
        for i in stride(from: 0, to: min(x.count, y.count), by: 4) {
            for c in 0..<3 { total += abs(Double(x[i + c]) - Double(y[i + c])); n += 1 }
        }
        return n > 0 ? total / Double(n) : nil
    }

    for pointWidth in [100.0, 100.25, 100.5, 101.0] {
        let src = dir.appendingPathComponent("stride-\(pointWidth).pdf")
        var sbox = CGRect(x: 0, y: 0, width: pointWidth, height: 120)
        guard let c = CGContext(src as CFURL, mediaBox: &sbox, nil) else { continue }
        c.beginPDFPage(nil)
        // Diagonal wedges, not blocks: every row differs from its neighbours, so
        // a shear of even one pixel per row shows up as a large difference.
        for i in 0..<6 {
            c.setFillColor(CGColor(red: Double(i % 3) / 2, green: Double((i / 3) % 2),
                                   blue: Double((i + 1) % 2), alpha: 1))
            c.fill(CGRect(x: pointWidth * Double(i) / 6.0, y: 0,
                          width: pointWidth / 6.0, height: 120))
        }
        c.endPDFPage(); c.closePDF()

        let out = dir.appendingPathComponent("stride-out-\(pointWidth).pdf")
        _ = try? Flattener.flatten(src, to: out, mode: .auto)
        let pixelsWide = Int((sbox.width * Flattener.fallbackRebuildDPI / 72).rounded())
        guard let diff = meanChannelDifference(src, out) else {
            check("the stride fixture at \(pointWidth) pt rebuilds", false, "unreadable")
            continue
        }
        check("at \(pixelsWide) px wide the rebuild still looks like the original",
              // Correct code measures 4.3-6.2 here; a stride padded by one
              // pixel measures 111-113. Twenty sits between them with room on
              // both sides, and the first fixture — 24 narrow wedges rather
              // than 6 wide ones — was rejected for reading 20.6 on correct
              // code purely from resampling a high-frequency pattern.
              diff < 20, String(format: "mean channel difference %.1f", diff))
    }

    // The panel's prose has now been wrong about this twice — "only applied to
    // files that already contain text", then "never colour" written the same
    // day colour arrived. These tie the words to the behaviour, so the next
    // change to one fails on the other.
    check("Automatic's blurb mentions colour, because Automatic keeps colour",
          Flattener.shouldKeepColour(mode: .auto, saturation: 0.3, pixels: 1000)
            == Flattener.Mode.auto.blurb.lowercased().contains("colour"),
          Flattener.Mode.auto.blurb)
    check("…and Grayscale's does not promise what Grayscale does not do",
          !Flattener.shouldKeepColour(mode: .grayscale, saturation: 0.3, pixels: 1000)
            && !Flattener.Mode.grayscale.blurb.lowercased().contains("keeps colour"),
          Flattener.Mode.grayscale.blurb)
    check("no mode's blurb is empty, since one is always on screen",
          Flattener.Mode.allCases.allSatisfy { !$0.blurb.isEmpty && !$0.label.isEmpty })

    try? FileManager.default.removeItem(at: dir)
    resetPrefs()
}

print("\nsettings survive the rename")

do {
    resetPrefs()
    let oldDomain = "com.cp1.VisionReaderGUI"
    guard let old = UserDefaults(suiteName: oldDomain) else {
        check("the previous domain is reachable", false); exit(1)
    }
    // One list, three readers: the migration, resetAll, and this harness. R6 was
    // resetAll silently omitting four keys, which is what duplication costs.
    check("there is a single canonical key list", Prefs.allKeys.count > 15,
          "\(Prefs.allKeys.count) keys")
    check("…and it covers the ones a user would notice losing",
          Prefs.allKeys.contains(Prefs.outputFolder)
            && Prefs.allKeys.contains(Prefs.languages)
            && Prefs.allKeys.contains(Prefs.concurrency))
    // R6 was four keys missing from this list. Naming them one at a time is how
    // that happened, so assert the whole set instead: every `static let` in
    // Prefs that names a key must be here, or be one of the two deliberate
    // exceptions with their reasons written down.
    do {
        // Read the keys out of the SOURCE, not out of a list retyped here. The
        // first version of this compared allKeys against a hand-copied
        // duplicate of allKeys, so adding a key and forgetting both places
        // passed — it asserted that two copies of the same mistake agreed (U26).
        let source = (try? String(contentsOfFile: "Sources/Prefs.swift", encoding: .utf8)) ?? ""
        let pattern = #"static let ([A-Za-z]+)\s*=\s*"([A-Za-z]+)""#
        let re = try! NSRegularExpression(pattern: pattern)
        var declared: [String: String] = [:]     // swift name -> key string
        for m in re.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let n = Range(m.range(at: 1), in: source),
                  let v = Range(m.range(at: 2), in: source) else { continue }
            declared[String(source[n])] = String(source[v])
        }
        check("the key list was read out of Prefs.swift", declared.count >= 20,
              "found \(declared.count) — if this is 0 the next check proves nothing")

        // Two are deliberately outside allKeys, each with its reason in the source.
        let exempt = ["migratedFromOldName"]
        let missing = declared
            .filter { !exempt.contains($0.key) && !Prefs.allKeys.contains($0.value) }
            .keys.sorted()
        check("every key declared in Prefs.swift is in allKeys",
              missing.isEmpty, "missing: \(missing.joined(separator: ", "))")
        check("…and the migration marker is deliberately not",
              !Prefs.allKeys.contains(Prefs.migratedFromOldName))
    }

    // Simulate the pre-rename install, then a first launch under the new name.
    old.set("/Users/someone/Scans", forKey: Prefs.outputFolder)
    old.set("de-DE", forKey: Prefs.languages)
    old.set(Prefs.Mode.text.rawValue, forKey: Prefs.mode)
    for k in Prefs.allKeys { d.removeObject(forKey: k) }
    d.removeObject(forKey: Prefs.migratedFromOldName)

    Prefs.migrateFromPreviousName()
    check("the old output folder is carried over",
          d.string(forKey: Prefs.outputFolder) == "/Users/someone/Scans",
          d.string(forKey: Prefs.outputFolder) ?? "nil")
    check("…and the language list", d.string(forKey: Prefs.languages) == "de-DE")
    check("…and a non-default mode", d.string(forKey: Prefs.mode) == Prefs.Mode.text.rawValue)

    // Runs once. A later change under the new name must not be reverted by it.
    d.set("/Users/someone/Elsewhere", forKey: Prefs.outputFolder)
    Prefs.migrateFromPreviousName()
    check("migrating twice does not clobber a newer choice",
          d.string(forKey: Prefs.outputFolder) == "/Users/someone/Elsewhere",
          d.string(forKey: Prefs.outputFolder) ?? "nil")

    // The marker is deliberately outside allKeys: a reset must not re-import.
    d.set(true, forKey: Prefs.migratedFromOldName)
    for k in Prefs.allKeys { d.removeObject(forKey: k) }
    Prefs.migrateFromPreviousName()
    check("Reset to Defaults does not re-import the old settings",
          d.string(forKey: Prefs.outputFolder) == nil,
          d.string(forKey: Prefs.outputFolder) ?? "nil")

    for k in Prefs.allKeys { old.removeObject(forKey: k) }
    d.removeObject(forKey: Prefs.migratedFromOldName)
    resetPrefs()
}

// MARK: - Tool lookup is cached

print("\ntool lookup")

do {
    // The fallback spawns a login shell (~85 ms). SwiftUI calls these from inside
    // a view body, so an uncached lookup cost ~0.4 s per keystroke.
    Runner.forgetToolPaths()
    let first = Date()
    _ = Runner.locateTool("mac-ocr")
    let cold = Date().timeIntervalSince(first)

    let second = Date()
    for _ in 0..<200 { _ = Runner.locateTool("mac-ocr") }
    let warm = Date().timeIntervalSince(second)

    check("repeated lookups are cached", warm < max(cold, 0.001) * 10,
          String(format: "200 cached lookups took %.4fs; one cold took %.4fs", warm, cold))
    check("a missing tool caches its absence too", {
        Runner.forgetToolPaths()
        _ = Runner.locateTool("definitely-not-a-real-tool-xyz")
        let t = Date()
        for _ in 0..<50 { _ = Runner.locateTool("definitely-not-a-real-tool-xyz") }
        return Date().timeIntervalSince(t) < 0.05
    }(), "a negative result must not re-shell every time")
    check("the cache still finds a real tool", Runner.locateTool("sh") != nil)
}

print("\nan input named after a scratch intermediate")

do {
    // R27. The rebuilt page images keep the input's own name inside the scratch
    // directory, while the intermediates use fixed literals in that same
    // directory: staged.pdf, text.pdf, images.pdf, outlined.pdf. For an input
    // called text.pdf, `visible` and `textLayer` are one path — compose writes
    // the layer over the rebuild, and then the JBIG2 branch deletes `visible`,
    // which is the layer it is about to merge. qpdf is handed a --overlay file
    // that no longer exists and the file fails, deterministically, for a reason
    // that has nothing to do with its contents.
    check("JBIG2 is available, so the route this bites on is live",
          JBIG2.isAvailable, "install jbig2enc and qpdf to cover R27")

    for stem in ["text", "staged", "images", "outlined"] {
        let dir = tmp.appendingPathComponent("reserved-\(stem)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let src = dir.appendingPathComponent("\(stem).pdf")
        makeScannedPDF(at: src, lines: ["RESERVED NAME \(stem.uppercased())"])
        let out = dir.appendingPathComponent("\(stem).ocr.pdf")

        var outcome: Runner.Result.Outcome?
        var message = ""
        OCRModel.makeSearchablePDF(
            file: src, output: out,
            rebuild: true, rebuildMode: .auto, password: nil,
            control: RunControl(), progress: { _, _ in },
            report: { o, m in outcome = o; message = m })

        check("an input named \(stem).pdf still succeeds",
              outcome == .succeeded, message)
        check("…and \(stem).ocr.pdf has a text layer",
              embeddedText(of: out).contains("RESERVED NAME"),
              embeddedText(of: out).isEmpty ? "<none>" : embeddedText(of: out))
    }
}

print("\nhostile page dimensions")

do {
    // R24. R20 added maximumPageMegapixels so an impossible page is refused
    // rather than crashing the process "taking every other file in flight with
    // it". But the guard multiplies in signed Int, and Swift traps on Int
    // overflow — the trap fires before the comparison. /Width and /Height are
    // whatever the file declares; nothing cross-checks them against the stream.
    let dir = tmp.appendingPathComponent("hostile-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    /// A structurally valid one-page PDF whose image XObject declares the given
    /// dimensions. The stream is three bytes; that is the point.
    func hostilePDF(named name: String, width: String, height: String,
                    mediaBox: String = "0 0 612 792") -> URL {
        let bodies = [
            "<</Type/Catalog/Pages 2 0 R>>",
            "<</Type/Pages/Kids[3 0 R]/Count 1>>",
            "<</Type/Page/Parent 2 0 R/MediaBox[\(mediaBox)]"
                + "/Resources<</XObject<</Im0 4 0 R>>>>/Contents 5 0 R>>",
            "<</Type/XObject/Subtype/Image/Width \(width)/Height \(height)"
                + "/ColorSpace/DeviceGray/BitsPerComponent 8/Length 3>>\nstream\nabc\nendstream",
            "<</Length 1>>\nstream\n \nendstream",
        ]
        var out = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (i, body) in bodies.enumerated() {
            offsets.append(out.utf8.count)
            out += "\(i + 1) 0 obj\n\(body)\nendobj\n"
        }
        let startxref = out.utf8.count
        out += "xref\n0 \(bodies.count + 1)\n0000000000 65535 f \n"
        for off in offsets { out += String(format: "%010d 00000 n \n", off) }
        out += "trailer\n<</Size \(bodies.count + 1)/Root 1 0 R>>\n"
            + "startxref\n\(startxref)\n%%EOF\n"
        let url = dir.appendingPathComponent(name)
        try! out.write(to: url, atomically: true, encoding: .ascii)
        return url
    }

    /// Runs the risky calls in a child so a trap fails the check instead of
    /// killing the suite. Returns nil if the child died on a signal.
    func probeSurvives(_ pdf: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        p.arguments = ["--probe-hostile-page", pdf.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationReason == .exit && p.terminationStatus == 0
    }

    // The file has to be readable, or the walk is never reached and the check
    // proves nothing.
    let overflow = hostilePDF(named: "overflow.pdf",
                              width: "4000000000", height: "4000000000")
    check("the hostile fixture is a PDF the app will actually open",
          PDFDocument(url: overflow)?.pageCount == 1)

    check("declared dimensions that overflow Int do not kill the process",
          probeSurvives(overflow),
          "Int(w) * Int(h) is 1.6e19 against an Int.max of 9.2e18")

    // Fits in Int, so it clears line 833, and then rebuildDPI reports ~4.1e8 DPI
    // and the multiplication *inside* the guard overflows instead.
    check("a declaration that overflows only inside the guard does not either",
          probeSurvives(hostilePDF(named: "inguard.pdf",
                                   width: "3500000000", height: "1")),
          "the trap fires inside the check meant to refuse the page")

    check("a negative declared dimension does not either",
          probeSurvives(hostilePDF(named: "negative.pdf",
                                   width: "-4000000000", height: "8")))

    // R29. The original check here used `1e300`, and PDFDocument does reject
    // that — but because `1e300` is not valid PDF real syntax, not because of
    // its magnitude. It tested the parser. A plain-integer box is legal PDF and
    // opens fine, reporting its declared size verbatim, which is why the
    // fixtures below are integers.
    check("an unparseable MediaBox is still refused by CoreGraphics",
          PDFDocument(url: hostilePDF(named: "hugebox.pdf", width: "8", height: "8",
                                      mediaBox: "0 0 1e300 1e300")) == nil,
          "the 1e300 fixture is a parser test, not a magnitude test")

    // The bypass: a huge box carrying a *small* image. largestImage reports 700
    // px, rebuildDPI trusts it, the render is 700x700 and clears the 400 MP
    // guard — and then saturation sizes off the unscaled box.
    let bigBox = hostilePDF(named: "bigbox.pdf", width: "700", height: "700",
                            mediaBox: "0 0 100000 100000")
    check("a plain-integer huge MediaBox really does open",
          PDFDocument(url: bigBox)?.page(at: 0)
              .map { Int($0.bounds(for: .mediaBox).width) } == 100000,
          "if this stops opening, the two checks below stop meaning anything")
    check("…and does not exhaust memory in the picture-routing thumbnail",
          probeSurvives(bigBox),
          "saturation sized 8000x8000x4 from the raw box")

    // That probe alone cannot fail on this machine — 8000x8000x4 is 256 MB,
    // which a Mac survives. Assert the bound directly, where it is checkable.
    let huge = Flattener.thumbnailSize(for: CGRect(x: 0, y: 0,
                                                   width: 100_000, height: 100_000))
    check("the routing thumbnail is bounded on a huge page",
          (huge?.width ?? .max) <= Flattener.maximumThumbnailEdge
              && (huge?.height ?? .max) <= Flattener.maximumThumbnailEdge,
          "got \(huge?.width ?? -1)x\(huge?.height ?? -1)")
    check("…and its buffer therefore cannot overflow Int",
          (huge?.width ?? .max) * (huge?.height ?? .max) * 4 > 0)

    // A real page must be untouched by the bound: Letter at 40 DPI is 340x440.
    let letter = Flattener.thumbnailSize(for: CGRect(x: 0, y: 0, width: 612, height: 792))
    check("a Letter page still gets its 40 DPI thumbnail",
          letter?.width == 340 && letter?.height == 440,
          "got \(letter?.width ?? -1)x\(letter?.height ?? -1), wanted 340x440")
    // The largest sheet in the corpus is nowhere near the cap either.
    let eSize = Flattener.thumbnailSize(for: CGRect(x: 0, y: 0, width: 33 * 72, height: 44 * 72))
    check("…as does a 33x44in E-size sheet",
          eSize?.width == 1320 && eSize?.height == 1760,
          "got \(eSize?.width ?? -1)x\(eSize?.height ?? -1)")

    check("a degenerate box yields no thumbnail rather than a bad one",
          Flattener.thumbnailSize(for: CGRect(x: 0, y: 0, width: 0, height: 100)) == nil
              && Flattener.thumbnailSize(for: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10)) == nil)

    check("a MediaBox whose thumbnail would overflow Int does not trap",
          probeSurvives(hostilePDF(named: "trapbox.pdf", width: "700", height: "700",
                                   mediaBox: "0 0 1000000000000 1000000000000")),
          "w * h * 4 in saturation")

    // And the guard still does its job for a page that is merely enormous.
    let big = hostilePDF(named: "big.pdf", width: "200000", height: "200000")
    var refused = false
    if PDFDocument(url: big)?.page(at: 0) != nil {
        do {
            _ = try Flattener.flatten(big, to: dir.appendingPathComponent("o.pdf"),
                                      mode: .blackAndWhite)
        } catch {
            refused = "\(error)".contains("pageTooLarge")
                || error.localizedDescription.contains("MP limit")
        }
    }
    check("a merely enormous page is still refused, not rendered", refused)

    // R26. The refusal used to say "Set an explicit PDF render DPI in Settings
    // to process it at a lower resolution." That control becomes mac-ocr's
    // --pdf-dpi for the recognition pass, which flatten throws before reaching;
    // Flattener never reads Prefs at all. Following the advice produced a
    // byte-identical refusal.
    let message = Flattener.Failure
        .pageTooLarge(page: 1, megapixels: 443, dpi: 800)
        .errorDescription ?? ""
    check("the refusal still names the page, its size and its DPI",
          message.contains("Page 1") && message.contains("443")
              && message.contains("800") && message.contains("400"))
    // A3.3, and this check is the interesting part: **it used to assert the
    // opposite, and it was R26's own belief written down.** R26 removed "Set an
    // explicit PDF render DPI" because that control had no effect on `flatten`,
    // which is true — `Flattener` reads nothing from `Prefs`. What R26 then
    // concluded, and what this check enforced, is that the setting is irrelevant to
    // the refusal. It is not: the remedy R26 put in its place, turning the rebuild
    // off, sends the page to `Recogniser.render`, which applies **the same
    // `rebuildDPI` and the same megapixel guard** — and `pdfDPIAuto` defaults to
    // true. Measured on a page declaring 2,100 DPI:
    //
    //     rebuild off, Page DPI = Automatic (the default) : still fails
    //     rebuild off, Page DPI = 144                     : 1224x1584, works
    //
    // So the advertised remedy changed the message and not the outcome, while the
    // setting the message explicitly disclaimed is the only one that helps. Both
    // halves are needed, and the old check would have kept the second one out.
    check("the refusal names the rebuild toggle",
          message.contains("Rebuild page images first"), message)
    check("…and the DPI setting, which is the half that actually works",
          message.contains("PDF render DPI"), message)
    check("…and says Automatic is not good enough, since that is the default",
          message.contains("Automatic"), message)
    // The property under both messages: a remedy named must be one that works.
    // Asserted against the real render, so this cannot drift into prose again.
    var fixed = Prefs.Snapshot.current()
    fixed.pdfDPIAuto = false
    fixed.pdfDPI = 144
    var auto = fixed
    auto.pdfDPIAuto = true
    if let huge = PDFDocument(url: big)?.page(at: 0) {
        check("Automatic really does still fail on the oversized page",
              Recogniser.render(huge, settings: auto) == nil)
        check("…and a fixed 144 DPI really does render it",
              Recogniser.render(huge, settings: fixed) != nil)
    } else {
        check("the oversized fixture opens", false)
    }

    try? FileManager.default.removeItem(at: dir)
}

print("\nshared form resources")

do {
    // R25. `walk` recurses into every Form XObject's /Resources, bounded only by
    // depth < 4, and keeps no record of what it has already visited. A form
    // whose /Resources is an indirect reference to the page's own — an
    // imposition and Ghostscript-rewrite pattern — makes the same dictionary
    // re-walked once per referring form at every level: N + N² + N³ + N⁴ block
    // invocations instead of N. The depth cap bounds recursion, not breadth.
    let dir = tmp.appendingPathComponent("sharedres-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let forms = 60          // 60 + 60² + 60³ + 60⁴ = 13,179,660 against 61 real entries
    let firstForm = 6
    var names = (0..<forms).map { "/F\($0) \(firstForm + $0) 0 R" }.joined()
    names += "/Im0 \(firstForm + forms) 0 R"

    var bodies = [
        "<</Type/Catalog/Pages 2 0 R>>",
        "<</Type/Pages/Kids[3 0 R]/Count 1>>",
        "<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Resources 5 0 R/Contents 4 0 R>>",
        "<</Length 1>>\nstream\n \nendstream",
        "<</XObject<<\(names)>>>>",                       // the one shared dictionary
    ]
    for _ in 0..<forms {
        // /Resources points back at object 5 — the dictionary that lists every
        // one of these forms.
        bodies.append("<</Type/XObject/Subtype/Form/BBox[0 0 10 10]"
                      + "/Resources 5 0 R/Length 0>>\nstream\n\nendstream")
    }
    bodies.append("<</Type/XObject/Subtype/Image/Width 1000/Height 1000"
                  + "/ColorSpace/DeviceGray/BitsPerComponent 8/Length 3>>\nstream\nabc\nendstream")

    var out = "%PDF-1.4\n"
    var offsets: [Int] = []
    for (i, body) in bodies.enumerated() {
        offsets.append(out.utf8.count)
        out += "\(i + 1) 0 obj\n\(body)\nendobj\n"
    }
    let startxref = out.utf8.count
    out += "xref\n0 \(bodies.count + 1)\n0000000000 65535 f \n"
    for off in offsets { out += String(format: "%010d 00000 n \n", off) }
    out += "trailer\n<</Size \(bodies.count + 1)/Root 1 0 R>>\n"
        + "startxref\n\(startxref)\n%%EOF\n"
    let url = dir.appendingPathComponent("shared.pdf")
    try! out.write(to: url, atomically: true, encoding: .ascii)

    let page = PDFDocument(url: url)?.page(at: 0)
    check("the shared-resources fixture opens", page != nil)

    if let page {
        // Bounded, on a background thread: unfixed this is tens of millions of
        // callbacks, each allocating a String, and a suite that appears to hang
        // is worse than one that fails.
        var found: (dpi: Double, pixelWidth: Int)?
        let done = DispatchSemaphore(value: 0)
        let started = Date()
        DispatchQueue.global().async {
            found = Flattener.largestImage(of: page)
            done.signal()
        }
        let finished = done.wait(timeout: .now() + 25) == .success
        let elapsed = Date().timeIntervalSince(started)

        check("60 forms sharing one Resources dictionary do not fan out",
              finished && elapsed < 2,
              finished ? String(format: "took %.2fs", elapsed)
                       : "did not finish in 25s — N^4 over a shared dictionary")

        // The pruning must not cost the answer: the image is still there to find.
        check("…and the image on the page is still found",
              finished && found?.pixelWidth == 1000,
              String(describing: found))
    }

    // The pruning has to be depth-aware, and this is what proves it. A plain
    // "have I seen this dictionary" set gets it wrong: dictionary S is reached
    // first down the long chain, at a depth where the cap stops its subtree
    // being explored, and marking it seen there turns away the short path that
    // would have explored it. The image sits three levels under S, so only the
    // short path can reach it:
    //
    //   page(0) ─ long(1) ─ B ─ S(2) ─ E ─ (3) ─ F ─ image at 4   past the cap
    //           └ short ─────── S(1) ─ E ─ (2) ─ F ─ image at 3   in range
    //
    // Which sibling is walked first is CGPDFDictionaryApplyBlock's business, and
    // it is not alphabetical — measured on this fixture it yields ["Z", "A"].
    // So build it both ways round and require both: whichever order the
    // framework uses, one of the two puts the long chain first, and identity-only
    // pruning loses that one's image.
    func depthFixture(named name: String, longKey: String, shortKey: String) -> URL {
        let bodies = [
            "<</Type/Catalog/Pages 2 0 R>>",
            "<</Type/Pages/Kids[3 0 R]/Count 1>>",
            "<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Resources 5 0 R/Contents 4 0 R>>",
            "<</Length 1>>\nstream\n \nendstream",
            // 5: the page's resources, holding both routes to S
            "<</XObject<</\(longKey) 6 0 R/\(shortKey) 9 0 R>>>>",
            // 6: first form of the long chain → 7
            "<</Type/XObject/Subtype/Form/BBox[0 0 10 10]/Resources 7 0 R/Length 0>>\nstream\n\nendstream",
            // 7: → form B
            "<</XObject<</B 8 0 R>>>>",
            // 8: form B → S, reaching it at depth 2
            "<</Type/XObject/Subtype/Form/BBox[0 0 10 10]/Resources 10 0 R/Length 0>>\nstream\n\nendstream",
            // 9: the short route → S, reaching it at depth 1
            "<</Type/XObject/Subtype/Form/BBox[0 0 10 10]/Resources 10 0 R/Length 0>>\nstream\n\nendstream",
            // 10: S, the shared dictionary
            "<</XObject<</E 11 0 R>>>>",
            "<</Type/XObject/Subtype/Form/BBox[0 0 10 10]/Resources 12 0 R/Length 0>>\nstream\n\nendstream",
            "<</XObject<</F 13 0 R>>>>",
            "<</Type/XObject/Subtype/Form/BBox[0 0 10 10]/Resources 14 0 R/Length 0>>\nstream\n\nendstream",
            // 14: where the image actually lives
            "<</XObject<</Im0 15 0 R>>>>",
            "<</Type/XObject/Subtype/Image/Width 777/Height 777"
                + "/ColorSpace/DeviceGray/BitsPerComponent 8/Length 3>>\nstream\nabc\nendstream",
        ]
        var body = "%PDF-1.4\n"
        var offs: [Int] = []
        for (i, b) in bodies.enumerated() {
            offs.append(body.utf8.count)
            body += "\(i + 1) 0 obj\n\(b)\nendobj\n"
        }
        let start = body.utf8.count
        body += "xref\n0 \(bodies.count + 1)\n0000000000 65535 f \n"
        for off in offs { body += String(format: "%010d 00000 n \n", off) }
        body += "trailer\n<</Size \(bodies.count + 1)/Root 1 0 R>>\n"
            + "startxref\n\(start)\n%%EOF\n"
        let url = dir.appendingPathComponent(name)
        try! body.write(to: url, atomically: true, encoding: .ascii)
        return url
    }

    // Both orderings, because which sibling CGPDFDictionaryApplyBlock hands back
    // first is not ours to choose. This is a guard that pruning does not lose an
    // image reachable by two routes of different lengths — it is *not* a
    // discriminating test of the depth-awareness itself. See R25: in every
    // arrangement tried, CoreGraphics walked the shallower branch first, which
    // is exactly the order in which identity-only pruning would also be correct.
    for (name, long, short) in [("depth-az.pdf", "A", "Z"), ("depth-za.pdf", "Z", "A")] {
        let page = PDFDocument(url: depthFixture(named: name, longKey: long,
                                                 shortKey: short))?.page(at: 0)
        check("an image reachable by two routes survives pruning (/\(long) long)",
              page.flatMap { Flattener.largestImage(of: $0) }?.pixelWidth == 777)
    }
}

do {
    // U18. U5 bounded this lookup at three seconds "because this runs on the main
    // thread", but put the bound *after* `readDataToEndOfFile()`, which returns
    // only when every writer on the pipe closes. A login shell that never exits
    // never reaches the bound. The two shells below are the two shapes: one that
    // hangs outright, and one that exits immediately while a background job it
    // started keeps the write end of stdout open.
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("u18-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    func shell(_ name: String, _ body: String) -> String {
        let url = dir.appendingPathComponent(name)
        try! "#!/bin/bash\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: url.path)
        return url.path
    }

    // Never exits. The wedged-NFS / interactive-prompt case U5 named.
    let wedged = shell("wedged", "sleep 300")
    // Exits at once, but `sleep` inherited stdout and holds it open — the
    // grandchild variant Runner.swift:260 already documents for the child's stderr.
    let holder = shell("holder", "sleep 300 &\nexit 0")

    let realShell = ProcessInfo.processInfo.environment["SHELL"]
    defer {
        if let realShell { setenv("SHELL", realShell, 1) } else { unsetenv("SHELL") }
        Runner.forgetToolPaths()
    }

    // Off the main thread with our own timeout: without the fix this call never
    // returns, and a suite that hangs is worse than one that fails.
    func lookupTime(using shellPath: String) -> Double? {
        setenv("SHELL", shellPath, 1)
        Runner.forgetToolPaths()
        let done = DispatchSemaphore(value: 0)
        let started = Date()
        DispatchQueue.global().async {
            _ = Runner.locateTool("definitely-not-a-real-tool-u18")
            done.signal()
        }
        guard done.wait(timeout: .now() + 20) == .success else { return nil }
        return Date().timeIntervalSince(started)
    }

    let wedgedTime = lookupTime(using: wedged)
    check("a login shell that never exits cannot hang the lookup",
          wedgedTime != nil && wedgedTime! < 10,
          wedgedTime.map { String(format: "returned in %.2fs", $0) }
              ?? "never returned — the bound is still behind the read")

    let holderTime = lookupTime(using: holder)
    check("a background job holding stdout cannot hang the lookup",
          holderTime != nil && holderTime! < 10,
          holderTime.map { String(format: "returned in %.2fs", $0) }
              ?? "never returned — EOF needs every writer to close")

    // The compression tools are bundled too, and unlike mac-ocr they come from
    // Homebrew single-architecture. isExecutableFile says yes to an arm64-only
    // binary on an Intel Mac, which then dies at exec with a message no user can
    // act on — so the bundled lookup reads the Mach-O header.
    do {
        let dir = tmp.appendingPathComponent("arch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // This test binary, built for the machine running it.
        check("a binary for this machine is recognised",
              Runner.containsNativeSlice(CommandLine.arguments[0]))

        // T6. Every other fixture here is a THIN Mach-O, so the fat branch — the
        // one the bundled universal mac-ocr actually takes — had no coverage at
        // all. Break the fat_arch stride or the 8 + i * stride offset and
        // bundledTool returns nil on every Mac, silently, with the suite green.
        // Built with lipo rather than borrowing /bin/ls, so the fixture is ours
        // and cannot change under us.
        // Fused from THIS binary plus the other slice of /bin/ls. Not from
        // /bin/ls alone: it is `x86_64 arm64e`, with no plain arm64 to thin, so
        // the obvious construction produces nothing — which the "really has both
        // slices" guard below caught rather than letting the next check pass on
        // a missing file.
        let slices = dir.appendingPathComponent("universal")
        func lipo(_ args: [String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
            p.arguments = args
            p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
        #if arch(arm64)
        let otherSlice = "x86_64"
        #else
        let otherSlice = "arm64e"
        #endif
        lipo(["/bin/ls", "-thin", otherSlice, "-output", dir.appendingPathComponent("x").path])
        lipo(["-create", CommandLine.arguments[0],
              dir.appendingPathComponent("x").path, "-output", slices.path])

        let archs = { () -> String in
            let p = Process(); let pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
            p.arguments = ["-archs", slices.path]
            p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(),
                          as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        check("the universal fixture really has both slices, or the next check proves nothing",
              archs.contains("arm64") && archs.contains("x86_64"), archs)
        check("a universal binary is recognised through the fat header",
              Runner.containsNativeSlice(slices.path),
              "the fat branch is what the bundled mac-ocr takes")

        // The other slice of a universal binary, on its own. /bin/ls is
        // universal on every supported macOS; thin it to the architecture we are
        // NOT, and the answer must be no.
        #if arch(arm64)
        let foreign = "x86_64"
        #else
        let foreign = "arm64"
        #endif
        let thinned = dir.appendingPathComponent("foreign")
        let lipo = Process()
        lipo.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        lipo.arguments = ["/bin/ls", "-thin", foreign, "-output", thinned.path]
        lipo.standardError = FileHandle.nullDevice
        try? lipo.run(); lipo.waitUntilExit()
        if lipo.terminationStatus == 0 {
            check("a binary for the other architecture is refused",
                  !Runner.containsNativeSlice(thinned.path),
                  "a \(foreign)-only Mach-O must not look runnable here")
            // T6. The fixture has to be confirmed present, or a failed copy
            // makes `bundledTool == nil` true for the wrong reason and this is
            // the only check that kills the bundle-arch-check mutant.
            if let res = Bundle.main.resourceURL {
                let planted = res.appendingPathComponent("foreign-arch-probe")
                try? FileManager.default.removeItem(at: planted)
                try? FileManager.default.copyItem(at: thinned, to: planted)
                defer { try? FileManager.default.removeItem(at: planted) }
                check("the foreign-architecture fixture was planted, or the next check proves nothing",
                      FileManager.default.isExecutableFile(atPath: planted.path),
                      planted.path)
                check("…and the bundled lookup refuses it too",
                      Runner.bundledTool("foreign-arch-probe") == nil,
                      String(describing: Runner.bundledTool("foreign-arch-probe")))
            }
        } else {
            check("lipo could thin /bin/ls, or this check proves nothing", false,
                  "could not build a foreign-architecture fixture")
        }

        // A shell script is a perfectly good tool and cannot be judged this way.
        let script = dir.appendingPathComponent("wrapper.sh")
        try? "#!/bin/sh\nexit 0\n".write(to: script, atomically: true, encoding: .utf8)
        check("a script is not rejected for not being a Mach-O",
              Runner.containsNativeSlice(script.path))
        check("…and a file too short to have a header is refused",
              !Runner.containsNativeSlice("/dev/null"))
    }

    // The engine ships inside the app now, so the lookup has to see it. In the
    // suite Bundle.main.resourceURL is the directory holding the test binary,
    // which is a faithful stand-in: same API, same isRunnable check.
    if let res = Bundle.main.resourceURL {
        let fake = res.appendingPathComponent("bundled-tool-probe")
        try? "#!/bin/sh\nexit 0\n".write(to: fake, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: fake.path)
        defer { try? FileManager.default.removeItem(at: fake) }

        check("a helper inside the bundle is found",
              Runner.bundledTool("bundled-tool-probe") == fake.path,
              String(describing: Runner.bundledTool("bundled-tool-probe")))
        check("…and a name that is not there is not invented",
              Runner.bundledTool("no-such-bundled-tool") == nil)

        // Order: the bundled copy must win over Homebrew, so a machine with an
        // older or newer mac-ocr installed still runs what was measured.
        //
        // T6. Asserting only that the bundled probe is found proves nothing
        // about ORDER, because the probe name exists nowhere else — hoist the
        // prefix loop above bundledTool and the check still passes. A decoy the
        // prefix scan would reach is what makes it a precedence test. The three
        // hard-coded prefixes are not writable, so the decoy goes where the
        // login-shell fallback looks: SHELL is pointed at a script that answers
        // with it, which is the last resort in the same search.
        let decoy = dir.appendingPathComponent("decoy-tool")
        try? "#!/bin/sh\nexit 0\n".write(to: decoy, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: decoy.path)
        let answering = dir.appendingPathComponent("answers-with-decoy")
        try? "#!/bin/bash\necho \(decoy.path)\n".write(to: answering, atomically: true,
                                                          encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: answering.path)
        let realShellForOrder = ProcessInfo.processInfo.environment["SHELL"]
        setenv("SHELL", answering.path, 1)
        Runner.forgetToolPaths()

        check("the decoy is reachable by the fallback, or the next check proves nothing",
              FileManager.default.isExecutableFile(atPath: decoy.path))
        check("the bundled copy is preferred to one the search would otherwise find",
              Runner.locateTool("bundled-tool-probe") == fake.path,
              "got \(String(describing: Runner.locateTool("bundled-tool-probe"))), "
              + "decoy at \(decoy.path)")

        // And with no bundled copy, the same search does reach the decoy — so
        // the check above is about precedence rather than the decoy being
        // unreachable.
        Runner.forgetToolPaths()
        check("…and without a bundled copy the search reaches the decoy",
              Runner.locateTool("no-bundled-copy-of-this") == decoy.path,
              String(describing: Runner.locateTool("no-bundled-copy-of-this")))

        if let realShellForOrder { setenv("SHELL", realShellForOrder, 1) } else { unsetenv("SHELL") }
        Runner.forgetToolPaths()

        // A non-executable file of the right name must not be mistaken for one.
        let dud = res.appendingPathComponent("bundled-dud-probe")
        try? "not executable".write(to: dud, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                               ofItemAtPath: dud.path)
        defer { try? FileManager.default.removeItem(at: dud) }
        check("…and a non-executable of the right name is not believed",
              Runner.bundledTool("bundled-dud-probe") == nil)
    }

    // R30. The helper the bound is built on: unsigned DispatchTime subtraction
    // underflows to ~584 years if taken in the wrong direction, which would turn
    // "past the deadline" into "essentially forever".
    check("a deadline in the future reports the time remaining",
          abs(Runner.secondsUntil(DispatchTime.now() + 2.0) - 2.0) < 0.05,
          "\(Runner.secondsUntil(DispatchTime.now() + 2.0))")
    check("a deadline already past reports zero, not an underflow",
          Runner.secondsUntil(DispatchTime.now() - 1.0) == 0,
          "\(Runner.secondsUntil(DispatchTime.now() - 1.0))")
    check("…and exactly now is not in the future either",
          Runner.secondsUntil(DispatchTime.now()) == 0)

    // T4. This block covered only the timeout-and-return-nil path. The check
    // that claimed to cover the success path timed `locateTool("mac-ocr")`, and
    // locateTool tries /opt/homebrew/bin first — where mac-ocr is — so
    // askLoginShell was never entered and it timed three stat calls. The read
    // accumulation and sawEOF latching that U18 newly wrote had no coverage at
    // all, for exactly the population U18 was written for: people whose mac-ocr
    // is NOT in those three prefixes.
    //
    // A shell that answers with a real path, for a tool name that is in none of
    // the prefixes, so the lookup has to go through askLoginShell.
    let answering = shell("answering", "echo /bin/ls")
    setenv("SHELL", answering, 1)
    Runner.forgetToolPaths()
    let found = Runner.locateTool("definitely-not-a-real-tool-u18-success")
    check("a login shell that answers is believed",
          found == "/bin/ls", String(describing: found))

    // The same, delivered in pieces with a pause: the loop has to accumulate
    // across several reads rather than assume one wakeup carries everything.
    let dribbling = shell("dribbling",
                          "printf '/bin/'\nsleep 0.3\nprintf 'ls'\nsleep 0.2\necho")
    setenv("SHELL", dribbling, 1)
    Runner.forgetToolPaths()
    let assembled = Runner.locateTool("definitely-not-a-real-tool-u18-chunks")
    check("…and a path arriving in chunks is reassembled, not truncated",
          assembled == "/bin/ls", String(describing: assembled))

    // A9.1. `zsh -lc` sources .zshenv/.zprofile/.zlogin onto the *same* stdout
    // before it runs the command, so one `echo` in a login startup file makes an
    // installed tool invisible — and the nil is memoised for the session, so
    // JBIG2 stays off for every file in every batch until the app is relaunched.
    // ~3x the output size, and Settings shows "Not installed" over a tool that is
    // installed. `command -v` prints its answer last; the chatter comes first.
    let chatty = shell("chatty", "echo 'Last login: Fri Aug 15 09:02:11 on ttys002'\necho /bin/ls")
    setenv("SHELL", chatty, 1)
    Runner.forgetToolPaths()
    check("a startup file's chatter does not hide an installed tool",
          Runner.locateTool("definitely-not-a-real-tool-a91-chatty") == "/bin/ls",
          String(describing: Runner.locateTool("definitely-not-a-real-tool-a91-chatty")))

    // The version-manager notice, which is several lines and the common case.
    let nvmish = shell("nvmish", "echo 'Now using node v20.11.0 (npm v10.2.4)'\n"
                       + "echo 'nvm is not compatible with the npm config prefix'\n"
                       + "echo /bin/ls")
    setenv("SHELL", nvmish, 1)
    Runner.forgetToolPaths()
    check("…nor does a multi-line one",
          Runner.locateTool("definitely-not-a-real-tool-a91-nvm") == "/bin/ls",
          String(describing: Runner.locateTool("definitely-not-a-real-tool-a91-nvm")))

    // A shell that answers with something unusable must still be refused — and
    // the chatty version of it too, or "take the last line" would have replaced
    // one way of believing the wrong thing with another.
    let nonsense = shell("nonsense", "echo /no/such/binary/at/all")
    setenv("SHELL", nonsense, 1)
    Runner.forgetToolPaths()
    check("a path that is not runnable is not believed",
          Runner.locateTool("definitely-not-a-real-tool-u18-bogus") == nil)

    let chattyNonsense = shell("chatty-nonsense",
                               "echo 'Last login: whenever'\necho /no/such/binary/at/all")
    setenv("SHELL", chattyNonsense, 1)
    Runner.forgetToolPaths()
    check("…and neither is the last line of chatter when it is not a tool",
          Runner.locateTool("definitely-not-a-real-tool-a91-bogus") == nil)

    // `command -v` finding nothing prints nothing, so the whole output is
    // chatter. Taking the last line must not turn that into a believed path.
    let chatterOnly = shell("chatter-only", "echo 'Last login: whenever'")
    setenv("SHELL", chatterOnly, 1)
    Runner.forgetToolPaths()
    check("…and a shell that only chatters finds nothing",
          Runner.locateTool("definitely-not-a-real-tool-a91-silent") == nil)

    // And the prefix scan itself stays fast. Renamed: it measures the three
    // stat calls, which is worth holding, but it is not a test of the shell.
    setenv("SHELL", realShell ?? "/bin/zsh", 1)
    Runner.forgetToolPaths()
    let t = Date()
    _ = Runner.locateTool("mac-ocr")
    let normal = Date().timeIntervalSince(t)
    check("a tool in a standard prefix is found without a shell at all",
          normal < 2, String(format: "prefix scan took %.3fs", normal))
}

// MARK: - publish, which is the step that touches the user's disk
//
// Three defects found by review, all in the one function invariant 2 is about.
do {
    let dir = tmp.appendingPathComponent("publish-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let fm = FileManager.default

    func staged(_ contents: String) -> URL {
        let url = dir.appendingPathComponent("staged-\(UUID().uuidString).pdf")
        try? Data(contents.utf8).write(to: url)
        return url
    }

    // A folder at the destination must stop the publish. `fileExists` is true for a
    // directory and `replaceItemAt` removes it *recursively* — a folder called
    // `scan.ocr.pdf` was deleted with its contents, and publish returned success.
    let folder = dir.appendingPathComponent("looks-like-output.pdf")
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let treasure = folder.appendingPathComponent("someone's thesis.docx")
    try? Data("irreplaceable".utf8).write(to: treasure)
    var refusedFolder = false
    do { try OCRModel.publish(staged("new"), to: folder) } catch { refusedFolder = true }
    check("publishing onto a folder is refused", refusedFolder)
    check("…and the folder's contents are still there",
          (try? Data(contentsOf: treasure)) != nil)

    // Replacing an existing file still works, and really replaces it.
    let existing = dir.appendingPathComponent("out.pdf")
    try? Data("old".utf8).write(to: existing)
    try? OCRModel.publish(staged("new"), to: existing)
    check("publishing over an existing file replaces it",
          String(data: (try? Data(contentsOf: existing)) ?? Data(), encoding: .utf8) == "new")

    // Publishing over an existing file goes through a sibling of the *destination*, not
    // straight from scratch, and leaves nothing behind.
    let siblings = (try? FileManager.default.contentsOfDirectory(atPath: dir.path))?
        .filter { $0.hasPrefix(".visionocr-publish-") } ?? []
    check("…and leaves no scratch beside the user's file",
          siblings.isEmpty, siblings.joined(separator: ", "))

    // **The cross-volume case is deliberately not tested here.** `replaceItemAt` requires
    // both items on one volume, and the staged file is always in the boot volume's
    // temporary directory — so an output folder on an external drive worked once and then
    // failed the whole batch with POSIX 18. Reproducing that needs a second real volume,
    // and mounting and ejecting a RAM disk inside a suite the pre-commit hook runs on
    // every commit is too much machinery pointed at the developer's own machine. It was
    // verified by hand on an HFS+ RAM disk, before and after, and REVIEW-2026-08-14.md
    // records the numbers. What the suite holds instead is the property that makes the fix
    // work: the replacement happens through a sibling of the destination, which is
    // same-volume by construction.

    resetPrefs()
}

// MARK: - Carrying a reader's marks across the rebuild
//
// TODO item 2. The rebuild turns each page into an image and drops every annotation
// with it, so 9% of a working library could not be re-OCR'd without destroying
// somebody's marginalia. `Annotations.transplant` copies the marks onto the finished
// file and then *verifies* its own work, which is the part these checks are about: the
// interesting failure is not "no marks" but "marks that moved".
do {
    let dir = tmp.appendingPathComponent("annots-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // What is and is not a reader's mark. Asserted on the set rather than through a
    // document, because a document can only show that today's fixture behaves.
    check("form fields are not a reader's mark",
          !Annotations.copiedSubtypes.contains("/Widget"))
    check("nor are the links a download wrapper leaves behind",
          !Annotations.copiedSubtypes.contains("/Link"))
    check("a highlight is", Annotations.copiedSubtypes.contains("/Highlight"))
    check("and so is a stamp, which is the type PDFKit could not copy",
          Annotations.copiedSubtypes.contains("/Stamp"))

    // A fixture carrying one of every copied type, plus the two that must be refused.
    // Three pages of differing size with one rotated, per CLAUDE.md invariant 5: a
    // single-page fixture is structurally blind to the geometry bugs this can have.
    let annotated = dir.appendingPathComponent("marked.pdf")
    let built = PDFDocument()
    for (i, size) in [CGSize(width: 612, height: 792), CGSize(width: 420, height: 595),
                      CGSize(width: 612, height: 792)].enumerated() {
        let page = PDFPage()
        page.setBounds(CGRect(origin: .zero, size: size), for: .mediaBox)
        if i == 2 { page.rotation = 90 }
        built.insert(page, at: i)
    }
    let kinds: [(PDFAnnotationSubtype, String)] = [
        (.highlight, "Highlight"), (.underline, "Underline"), (.strikeOut, "StrikeOut"),
        (.text, "Text"), (.freeText, "FreeText"), (.ink, "Ink"), (.stamp, "Stamp"),
        (.square, "Square"), (.circle, "Circle"), (.line, "Line"),
        (.link, "Link"), (.widget, "Widget"),
    ]
    var expectedCopied = 0
    // Marks go on the two *unrotated* pages only. The third page is rotated, per
    // CLAUDE.md invariant 5, and a rotated page carrying a mark is now refused outright —
    // so leaving them spread across all three turned this fixture into a test of the
    // refusal. The refusal has its own fixture below.
    for (i, kind) in kinds.enumerated() {
        guard let page = built.page(at: i % 2) else { continue }
        let mark = PDFAnnotation(bounds: CGRect(x: 40 + Double(i % 4) * 90,
                                                y: 80 + Double(i / 4) * 120,
                                                width: 70, height: 30),
                                 forType: kind.0, withProperties: nil)
        mark.contents = kind.1
        mark.color = .yellow
        page.addAnnotation(mark)
        if Annotations.copiedSubtypes.contains("/" + kind.1) { expectedCopied += 1 }
    }
    check("the annotation fixture wrote", built.write(to: annotated))

    if let qpdf = JBIG2.merger {
        // The rebuilt file, made the way the app makes it: pages as images, no marks.
        let rebuilt = dir.appendingPathComponent("rebuilt.pdf")
        let pngs = dir.appendingPathComponent("pngs")
        try? FileManager.default.createDirectory(at: pngs, withIntermediateDirectories: true)
        _ = try? Flattener.flatten(annotated, to: rebuilt, mode: .auto, pngDirectory: pngs)
        let strippedCount = (PDFDocument(url: rebuilt)?.pageCount ?? 0) > 0
            ? (0..<(PDFDocument(url: rebuilt)!.pageCount)).reduce(0) {
                  $0 + (PDFDocument(url: rebuilt)!.page(at: $1)?.annotations.count ?? 0) }
            : -1
        // The premise. If the rebuild ever stops dropping annotations, every check
        // below would pass while testing nothing.
        check("the rebuild drops every mark, which is why this feature exists",
              strippedCount == 0, "\(strippedCount) survived")

        let before = PDFDocument(url: rebuilt)?.pageCount ?? -1
        var report: Annotations.Report?
        var thrown: String?
        do {
            report = try Annotations.transplant(from: annotated, into: rebuilt,
                                                password: nil, qpdf: qpdf, scratch: dir)
        } catch { thrown = error.localizedDescription }
        check("the transplant succeeded", thrown == nil, thrown ?? "")
        check("every reader's mark was carried",
              report?.copiedTotal == expectedCopied,
              "\(report?.copiedTotal ?? -1) of \(expectedCopied)")
        check("the form field was refused", (report?.dropped["/Widget"] ?? 0) == 1)
        check("the link was refused", (report?.dropped["/Link"] ?? 0) == 1)
        check("and what was refused is reported, not silent",
              (report?.droppedTotal ?? 0) >= 2, report?.summary ?? "")
        check("the page count is unchanged",
              PDFDocument(url: rebuilt)?.pageCount == before,
              "\(PDFDocument(url: rebuilt)?.pageCount ?? -1) vs \(before)")

        // Geometry, exactly. The page boxes are preserved by the rebuild, so there is
        // no remapping and no reason to allow a tolerance — a tolerance here would
        // hide the systematic shift that would mean that assumption had broken.
        var moved: [String] = []
        if let original = PDFDocument(url: annotated), let carried = PDFDocument(url: rebuilt) {
            for i in 0..<original.pageCount {
                let want = (original.page(at: i)?.annotations ?? [])
                    .filter { Annotations.copiedSubtypes.contains("/" + ($0.type ?? "")) }
                let got = carried.page(at: i)?.annotations ?? []
                for mark in want {
                    let match = got.first {
                        $0.type == mark.type && $0.bounds == mark.bounds
                    }
                    if match == nil {
                        moved.append("p\(i + 1) \(mark.type ?? "?") \(mark.bounds)")
                    }
                }
            }
        }
        check("every carried mark sits exactly where it was",
              moved.isEmpty, moved.prefix(3).joined(separator: "; "))

        // A second transplant onto an already-transplanted file **fails**, and that is
        // worth pinning because it is not what the first version of this comment claimed.
        // It said the marks would simply be carried twice. They are not: the verification
        // counts every copied-subtype mark present on the rebuilt page, so the ones
        // already there make the count disagree and the document is refused. Better than
        // duplicating somebody's highlights, and the pipeline calls this once per staged
        // rebuild anyway — but a sweep that ever retries in place needs to know it gets a
        // failure rather than a quiet doubling.
        let firstTotal = report?.copiedTotal ?? 0
        var secondRefused = false
        do {
            _ = try Annotations.transplant(from: annotated, into: rebuilt, password: nil,
                                           qpdf: qpdf, scratch: dir)
        } catch { secondRefused = true }
        let total = (PDFDocument(url: rebuilt)?.pageCount ?? 0) > 0
            ? (0..<PDFDocument(url: rebuilt)!.pageCount).reduce(0) {
                  $0 + (PDFDocument(url: rebuilt)!.page(at: $1)?.annotations
                          .filter { Annotations.copiedSubtypes.contains("/" + ($0.type ?? "")) }
                          .count ?? 0) }
            : -1
        check("transplanting twice is refused rather than doubling the marks",
              secondRefused, "second transplant did not throw")
        check("…and the file still carries exactly one copy of each",
              total == firstTotal, "\(total) marks, expected \(firstTotal)")
    } else {
        check("qpdf is present for the annotation checks", false, "skipped: no qpdf")
    }

    // MARK: The two defects an adversarial review of this feature's own first commit found
    //
    // Both were invisible to the checks that shipped with it, for the same reason: the
    // geometry check compared the copied `/Rect` against the *source* `/Rect`, so it
    // agreed with itself by construction and could not see that the rebuilt page's
    // coordinate space was not the source's. CONTRIBUTING §4b names this shape.
    if let qpdf = JBIG2.merger {
        // 1. A rotated page. `Flattener.boxSize` bakes rotation into the raster and swaps
        //    width and height, so a mark copied verbatim onto one can land off the sheet
        //    — measured on this very fixture before the fix: the highlight vanished.
        //    Refused rather than corrected, and the refusal is what is asserted.
        let rotated = dir.appendingPathComponent("rotated.pdf")
        let spun = PDFDocument()
        for (i, rotation) in [0, 90].enumerated() {
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            page.rotation = rotation
            let mark = PDFAnnotation(bounds: CGRect(x: 40, y: 700, width: 200, height: 20),
                                     forType: .highlight, withProperties: nil)
            mark.color = .yellow
            page.addAnnotation(mark)
            spun.insert(page, at: i)
        }
        _ = spun.write(to: rotated)
        let spunRebuild = dir.appendingPathComponent("rotated-rebuilt.pdf")
        let spunPNGs = dir.appendingPathComponent("rotated-pngs")
        try? FileManager.default.createDirectory(at: spunPNGs, withIntermediateDirectories: true)
        _ = try? Flattener.flatten(rotated, to: spunRebuild, mode: .auto,
                                   pngDirectory: spunPNGs)
        var rotationRefused = false
        do {
            _ = try Annotations.transplant(from: rotated, into: spunRebuild, password: nil,
                                           qpdf: qpdf, scratch: dir)
        } catch { rotationRefused = "\(error)".contains("rotatedPage") }
        check("a mark on a rotated page is refused, not moved to the wrong place",
              rotationRefused)
        // …and the file it would have been written into is untouched by the attempt.
        check("…and the rebuilt file is left alone when it is refused",
              (PDFDocument(url: spunRebuild)?.page(at: 0)?.annotations.count ?? -1) == 0)

        // 2. A media box that does not start at the origin. `boxSize` moves it to (0,0),
        //    so every page-space coordinate has to move with it. Measured on
        //    `Cohen_1990_Making a New Deal` page 6 (media box `[0 -24.69 408 588]`)
        //    before the fix: the highlight landed 24.7 points low, a line and a half.
        //    105 of 233 corpus documents have an offset box.
        let offset = dir.appendingPathComponent("offset.pdf")
        let shifted = PDFDocument()
        let shiftedPage = PDFPage()
        // The same shape as Cohen's: origin below zero.
        shiftedPage.setBounds(CGRect(x: 0, y: -24.69, width: 408, height: 588),
                              for: .mediaBox)
        let shiftedMark = PDFAnnotation(bounds: CGRect(x: 40, y: 80, width: 200, height: 20),
                                        forType: .highlight, withProperties: nil)
        shiftedMark.color = .yellow
        shiftedPage.addAnnotation(shiftedMark)
        shifted.insert(shiftedPage, at: 0)
        _ = shifted.write(to: offset)
        let offsetRebuild = dir.appendingPathComponent("offset-rebuilt.pdf")
        let offsetPNGs = dir.appendingPathComponent("offset-pngs")
        try? FileManager.default.createDirectory(at: offsetPNGs, withIntermediateDirectories: true)
        _ = try? Flattener.flatten(offset, to: offsetRebuild, mode: .auto,
                                   pngDirectory: offsetPNGs)
        let sourceRect = shiftedMark.bounds
        var carriedRect: CGRect?
        if (try? Annotations.transplant(from: offset, into: offsetRebuild, password: nil,
                                        qpdf: qpdf, scratch: dir)) != nil {
            carriedRect = PDFDocument(url: offsetRebuild)?.page(at: 0)?.annotations.first?.bounds
        }
        // The mark must move *up* by the box's own offset, into the rebuilt page's space.
        // Asserting the shift rather than equality is the whole point: equality is what
        // the broken version asserted, and it passed.
        check("a mark on an offset media box is translated into the rebuilt page's space",
              carriedRect != nil
                  && abs((carriedRect!.minY - sourceRect.minY) - 24.69) < 0.02,
              "moved \(carriedRect.map { $0.minY - sourceRect.minY } ?? -999) points, "
                  + "expected 24.69")
    }

    // The indirect-`/Rect` case, which is a regression test for a real defect.
    //
    // On page 11 of `Hyman_2012_Rethinking the Postwar Corporation`, two of fourteen
    // annotations carry `/Rect` as an indirect reference — `890 0 R` — rather than as
    // an inline array. The first version of this code cast straight to an array, so
    // those two were copied but never recorded as expected, and the count check then
    // fired with 14 found against 12 expected. It was right to. The fix resolves the
    // reference; this asserts the resolver rather than the symptom, because building a
    // PDF with an indirect `/Rect` through PDFKit is not possible.
    check("an annotation rectangle may be an indirect reference, and is resolved",
          Annotations.resolvesIndirectRectangles)

    // The three cases a PDFKit fixture cannot express, each of which was a live defect
    // found by review rather than by a test. `/Rotate` and `/MediaBox` are *inheritable*
    // and qpdf does not push them down; geometry arrays may be indirect. All three were
    // silently wrong, and the worst — an indirect `/QuadPoints` left in the old coordinate
    // space while `/Rect` moved — drew a highlight 24.69 points from the words it marked
    // while every check passed.
    check("a page inherits /Rotate and /MediaBox from its /Pages node",
          Annotations.resolvesInheritedPageAttributes)
    check("geometry behind an indirect reference is translated, not skipped",
          Annotations.translatesIndirectGeometry)

    // And the adoption is paired. An unpaired adopt leaked one file descriptor per qpdf
    // pass for the whole batch — R15's shape at a new site, and measured at 204 open
    // descriptors for 200 documents, against Foundation's ceiling of about 2,560. The
    // library this feature exists to sweep is roughly 16,000 documents.
    if let qpdf = JBIG2.merger {
        let control = RunControl()
        let plain = dir.appendingPathComponent("unmarked.pdf")
        let bare = PDFDocument()
        let barePage = PDFPage()
        barePage.setBounds(CGRect(x: 0, y: 0, width: 300, height: 300), for: .mediaBox)
        bare.insert(barePage, at: 0)
        _ = bare.write(to: plain)
        let staged = dir.appendingPathComponent("unmarked-staged.pdf")
        try? FileManager.default.copyItem(at: plain, to: staged)
        _ = try? Annotations.transplant(from: plain, into: staged, password: nil,
                                        qpdf: qpdf, scratch: dir,
                                        adopting: { body in try control.adopting(body) })
        check("every qpdf pass releases its adopted child",
              control.adoptedCount == 0, "\(control.adoptedCount) still adopted")
    }
    resetPrefs()
}

resetPrefs()

// A11.7. Measured, not documented. The census used to live in `ARCHITECTURE.md` as
// a number that was wrong by 57, and five of the eight blocks left no trace at all
// when they skipped.
if skippedBlocks.isEmpty {
    print("\nno checks were skipped — every gated block ran")
} else {
    let total = skippedBlocks.reduce(0) { $0 + $1.checks }
    print("\n\(total) check(s) skipped, in \(skippedBlocks.count) block(s):")
    for b in skippedBlocks { print("  \(b.label) — \(b.checks): \(b.reason)") }
    print("so this run exercised \(checks) of a possible \(checks + total).")
}
print("\n\(checks - failures)/\(checks) passed")
exit(failures == 0 ? 0 : 1)
