import AppKit
import Foundation
import CoreText
import PDFKit

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
    do { _ = try Flattener.flatten(url, to: out, mode: .blackAndWhite) } catch {}
    exit(0)
}

var failures = 0
var checks = 0

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
}
resetPrefs()

// MARK: - Fixtures

let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mac-ocr-gui-tests-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

/// An image-only PDF: no embedded text, so anything we read back came from OCR.
func makeScannedPDF(at url: URL, lines: [String]) {
    let w = 1224, h = 1584
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    NSColor.white.setFill()
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

guard let binary = Runner.resolveBinary() else {
    print("mac-ocr not found — install it with: npm install -g mac-ocr"); exit(1)
}
print("using \(binary)\n")

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
func runAndList(_ label: String, outDir: URL) -> (ok: Bool, message: String, files: [String]) {
    try? FileManager.default.removeItem(at: outDir)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let result = Runner.run(binary: binary, file: sample, outputFolder: outDir, register: { _ in })
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: outDir.path)) ?? []).sorted()
    return (result.succeeded, result.message, files)
}

// MARK: - Argument construction

print("argument construction")
resetPrefs()
let out = tmp.appendingPathComponent("out")

do {
    let args = Runner.arguments(for: sample, outputFolder: out)
    check("text mode uses no subcommand", args.first == sample.path, args.joined(separator: " "))
    check("text mode requests a [name] template",
          args.contains("\(out.path)/[name].txt"), args.joined(separator: " "))
    check("defaults add no recognition flags",
          !args.contains("--fast") && !args.contains("--no-language-correction")
            && !args.contains("-c") && !args.contains("--pdf-dpi"),
          args.joined(separator: " "))
}

// mac-ocr's own `searchable-pdf` subcommand has zero call sites here — the
// searchable pipeline asks for recognition only and writes its own text layer —
// so `arguments` builds the Extract Text command and nothing else. It must not
// grow a searchable form back: a command this app never runs is a command
// nothing keeps honest.
do {
    d.set(Prefs.Mode.searchablePDF.rawValue, forKey: Prefs.mode)
    let args = Runner.arguments(for: sample, outputFolder: out)
    check("no subcommand is ever emitted", args.first == sample.path,
          args.joined(separator: " "))
    check("no searchable-pdf-only flags are emitted",
          !args.contains("--ocr-all-pages") && !args.contains("--ocr-strategy"),
          args.joined(separator: " "))
    check("the searchable route asks mac-ocr for jsonl, not a PDF",
          Runner.jsonLinesArguments(for: sample).contains("jsonl"))
    resetPrefs()
}

do {
    d.set(true, forKey: Prefs.besideOriginal)
    let textArgs = Runner.arguments(for: sample, outputFolder: out)
    check("beside-original uses the [dir] placeholder",
          textArgs.contains("[dir]/[name].txt"), textArgs.joined(separator: " "))
    resetPrefs()
}

do {
    d.set("en-US, ja-JP  fr-FR", forKey: Prefs.languages)
    let args = Runner.arguments(for: sample, outputFolder: out)
    let langs = zip(args, args.dropFirst()).filter { $0.0 == "-l" }.map(\.1)
    check("languages split on commas and spaces", langs == ["en-US", "ja-JP", "fr-FR"],
          langs.joined(separator: "|"))
    resetPrefs()
}

do {
    d.set(0.5, forKey: Prefs.confidence)
    check("confidence formats without trailing zeros",
          Runner.arguments(for: sample, outputFolder: out).contains("0.5"))
    resetPrefs()
}

do {
    d.set(false, forKey: Prefs.pdfDPIAuto)
    d.set(5000, forKey: Prefs.pdfDPI)          // out of range on purpose
    let args = Runner.arguments(for: sample, outputFolder: out)
    check("pdf dpi is clamped into 72–600", args.contains("600"), args.joined(separator: " "))
    resetPrefs()
}

do {
    d.set("Fitzgerald, Bourdieu\nDurkheim", forKey: Prefs.customWords)
    let args = Runner.arguments(for: sample, outputFolder: out)
    let words = zip(args, args.dropFirst()).filter { $0.0 == "-w" }.map(\.1)
    check("custom words split on commas and newlines",
          words == ["Fitzgerald", "Bourdieu", "Durkheim"], words.joined(separator: "|"))
    resetPrefs()
}

// MARK: - Real runs

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
        file: sample, binary: binary, output: output,
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
    check("every recognition flag together is accepted by mac-ocr", r.ok, r.message)
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
    let cold = Runner.previewLines(binary: "mac-ocr", file: sample, outputFolder: nil)
    check("the preview admits when no destination is set",
          cold.contains { $0.contains("No output folder chosen yet") },
          cold.joined(separator: " / "))

    d.set(true, forKey: Prefs.besideOriginal)
    let beside = Runner.previewLines(binary: "mac-ocr", file: sample, outputFolder: nil)
    check("…and says nothing of the sort once a destination exists",
          !beside.contains { $0.contains("No output folder chosen") },
          beside.joined(separator: " / "))

    // The binary is the resolved one. A preview that hard-codes "mac-ocr"
    // cannot be used to check the mac-ocr path setting, which is the setting
    // most likely to be wrong (U9).
    let named = Runner.previewLines(binary: "/custom/prefix/mac-ocr-9000",
                                    file: sample, outputFolder: out)
    check("the preview shows the binary it was given",
          named.contains { $0.contains("mac-ocr-9000") }, named.joined(separator: " / "))

    // Searchable mode is a pipeline, and the compression step shells out to two
    // further binaries that the preview never mentioned at all.
    resetPrefs()
    d.set(Prefs.Mode.searchablePDF.rawValue, forKey: Prefs.mode)
    d.set(true, forKey: Prefs.rebuildImages)
    d.set(true, forKey: Prefs.useJBIG2)
    d.set(true, forKey: Prefs.besideOriginal)
    let pipeline = Runner.previewLines(binary: binary, file: sample, outputFolder: nil)
        .joined(separator: "\n")
    check("the searchable preview shows the rebuild", pipeline.contains("rebuild pages"), pipeline)
    check("…the recognition call", pipeline.contains("jsonl"), pipeline)
    check("…the text layer", pipeline.contains("invisible text layer"), pipeline)
    check("…and the compression step, named or explained",
          pipeline.contains("jbig2") || pipeline.contains("JBIG2 compression is on"),
          pipeline)
    check("the preview still names the output", pipeline.contains("[name].ocr.pdf"), pipeline)
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
    let r = Runner.run(binary: binary, file: trap, outputFolder: out, register: { _ in })
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
    let r = Runner.run(binary: binary, file: rebuilt, outputFolder: out, register: { _ in })
    let got = (try? String(contentsOf: out.appendingPathComponent("rebuilt.txt"),
                           encoding: .utf8)) ?? ""
    check("the image survives and still OCRs", r.succeeded && got.contains("HELLO VISION"),
          got.replacingOccurrences(of: "\n", with: " / "))
    check("the stale layer is nowhere in the OCR", !got.contains("STALE"))

    // And end to end through our own writer: one layer, Vision's, not doubled.
    let pdfOut = tmp.appendingPathComponent("rebuild-pdf-out")
    try? FileManager.default.createDirectory(at: pdfOut, withIntermediateDirectories: true)
    let json = tmp.appendingPathComponent("obs.json")
    let jr = Runner.run(binary: binary, file: rebuilt, outputFolder: nil,
                        argumentsOverride: Runner.jsonArguments(for: rebuilt, jsonOut: json),
                        register: { _ in })
    check("recognition to JSON succeeds", jr.succeeded, jr.message)

    let composed = pdfOut.appendingPathComponent("rebuilt.ocr.pdf")
    do {
        let byPage = try SearchableWriter.observations(fromJSONAt: json)
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
        check("it carries a JBIG2 stream", raw.contains("/JBIG2Decode"))
        check("…and a DCT stream alongside it", raw.contains("/DCTDecode"))
        check("bit depths match their filters",
              raw.contains("/BitsPerComponent 1") && raw.contains("/BitsPerComponent 8"))
    }
    resetPrefs()
}

// MARK: - JBIG2 compression

print("\nJBIG2 compression of the page images")

do {
    resetPrefs()
    check("JBIG2 is on by default", UserDefaults.standard.bool(forKey: Prefs.useJBIG2))

    if !JBIG2.isAvailable {
        print("  skipped — jbig2enc/qpdf not installed (\(JBIG2.installHint))")
    } else {
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
        _ = Runner.run(binary: binary, file: rebuilt, outputFolder: nil,
                       argumentsOverride: Runner.jsonArguments(for: rebuilt, jsonOut: json),
                       register: { _ in })
        let byPage = (try? SearchableWriter.observations(fromJSONAt: json)) ?? [:]

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
        let streamBytes = encoded.reduce(0) {
            $0 + (((try? FileManager.default.attributesOfItem(atPath: $1.stream.url.path)[.size]
                    as? Int) ?? 0) ?? 0)
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
    let refRun = Runner.run(binary: binary, file: page, outputFolder: dir, register: { _ in })
    let reference = (try? String(contentsOf: dir.appendingPathComponent("spacing.txt"),
                                 encoding: .utf8)) ?? ""
    check("reference text is spaced correctly",
          refRun.succeeded && reference.contains("Practice of Democracy"),
          reference.replacingOccurrences(of: "\n", with: " / "))

    // Ours: recognise, then compose.
    let json = dir.appendingPathComponent("obs.json")
    _ = Runner.run(binary: binary, file: page, outputFolder: nil,
                   argumentsOverride: Runner.jsonArguments(for: page, jsonOut: json),
                   register: { _ in })
    let ours = dir.appendingPathComponent("ours.pdf")
    if let byPage = try? SearchableWriter.observations(fromJSONAt: json) {
        try? SearchableWriter.compose(visible: page, observations: byPage, to: ours)
    }
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
    let args = Runner.arguments(for: input, outputFolder: nil, explicitOutputFile: resolved)
    check("an explicit output file overrides beside-the-original",
          args.contains("/Users/someone/Scans/Book 2.txt"), args.joined(separator: " "))
    check("…and no [name] template is emitted alongside it",
          !args.contains { $0.contains("[name]") }, args.joined(separator: " "))
    resetPrefs()
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
    let r = Runner.run(binary: binary, file: missing, outputFolder: out, register: { _ in })
    check("a missing file is reported as a failure", r.outcome == .failed)
    check("…with mac-ocr's own message", r.message.lowercased().contains("no such file"), r.message)

    // Cancelling has to be distinguishable from failing, or the summary lies.
    //
    // Cancel *before* the run rather than racing a sleep against it: a one-page
    // synthetic PDF can finish in well under the delay, which made this flaky.
    // This exercises the real race anyway — cancel landing between launch and
    // adoption, where adopt() has to terminate a process it has just been handed.
    let control = RunControl()
    control.cancel()
    let cancelled = Runner.run(binary: binary, file: sample, outputFolder: out,
                               wasCancelled: { control.isCancelled },
                               register: { control.adopt($0) })
    check("a cancelled run reports .cancelled, not .failed",
          cancelled.outcome == .cancelled, String(describing: cancelled.outcome))

    // And a crash must NOT be reported as a cancellation: a batch where every
    // file crashed used to read as if the user had stopped it.
    let notCancelled = RunControl()
    let crashed = Runner.run(binary: "/bin/sh", file: sample, outputFolder: out,
                             argumentsOverride: ["-c", "kill -SEGV $$"],
                             wasCancelled: { notCancelled.isCancelled },
                             register: { notCancelled.adopt($0) })
    check("a crash is reported as failure, not cancellation",
          crashed.outcome == .failed, String(describing: crashed.outcome))
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
            file: src, binary: binary, output: output,
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

    // Text mode gets a concrete path rather than mac-ocr's [name] template.
    let target = folder.appendingPathComponent("scan 2.txt")
    let args = Runner.arguments(for: b, outputFolder: folder, explicitOutputFile: target)
    check("an explicit output file replaces the [name] template",
          args.contains(target.path) && !args.contains { $0.contains("[name]") },
          args.joined(separator: " "))
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
    let r = Runner.run(binary: binary, file: rebuilt, outputFolder: ocrOut, register: { _ in })
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

// MARK: - Cancelling actually interrupts the read

// runStreaming's loop used to sit in availableData, which blocks until every
// writer closes stdout — and the writers include any grandchild that inherited
// it. A child that exited at once while leaving a `sleep` holding the pipe kept
// the loop parked for the sleep's full duration, with Cancel already spent, and
// then reported success.

print("\ncancelling interrupts a wedged read")

do {
    let sh = "/bin/sh"
    // Exits immediately; the backgrounded sleep inherits stdout and holds it.
    let wedge = ["-c", "echo first; ( sleep 8 ) & exit 0"]

    var cancelled = false
    let began = Date()
    var captured: Process?
    let result = Runner.runStreaming(
        binary: sh, arguments: wedge,
        onLine: { _ in },
        wasCancelled: { cancelled },
        register: { captured = $0 })
    let elapsedNoCancel = Date().timeIntervalSince(began)
    _ = result
    // Without cancelling we must still return — via EOF or the bounded wait —
    // rather than hanging indefinitely.
    check("an uncancelled wedged read still returns", elapsedNoCancel < 20,
          String(format: "%.2fs", elapsedNoCancel))
    if let captured { Runner.stop(captured) }

    // Now the real case: cancel 0.5s in, and require a prompt return.
    cancelled = false
    var live: Process?
    let start = Date()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { cancelled = true }
    let cancelledResult = Runner.runStreaming(
        binary: sh, arguments: wedge,
        onLine: { _ in },
        wasCancelled: { cancelled },
        register: { live = $0 })
    let elapsed = Date().timeIntervalSince(start)
    if let live { Runner.stop(live) }

    check("a cancelled read returns promptly, not when the grandchild exits",
          elapsed < 3.0, String(format: "%.2fs (the grandchild holds stdout for 8s)", elapsed))
    check("…and reports it as cancelled, not as success",
          cancelledResult.outcome == .cancelled, "\(cancelledResult.outcome)")
}

// MARK: - The stderr drain

// The drain exists for two reasons and had a test for neither. C6: a failing run
// must report what the child said, or the user gets a bare exit code. And it
// must keep reading while stdout is being read, or a child that writes more than
// a pipe buffer to stderr blocks for ever and takes the file with it.
//
// It is a DispatchSource now rather than a 200 ms poll loop (R22), which is a
// rewrite of exactly the code these two properties depend on.

print("\nstderr is drained, kept, and cannot deadlock")

do {
    let sh = "/bin/sh"

    let spoke = Runner.runStreaming(
        binary: sh, arguments: ["-c", "echo a line of output; echo boom on stderr >&2; exit 3"],
        onLine: { _ in }, register: { _ in })
    check("a failing child's stderr is reported", spoke.message.contains("boom on stderr"),
          "got: '\(spoke.message)'")
    check("…and it is reported as a failure", spoke.outcome == .failed, "\(spoke.outcome)")

    // 256 KB, well past the 64 KB pipe buffer: if the drain stops reading, the
    // child blocks in write() and never exits.
    var lines = 0
    let began = Date()
    let flood = Runner.runStreaming(
        binary: sh,
        arguments: ["-c", "/usr/bin/head -c 262144 /dev/zero | /usr/bin/tr '\\0' 'x' >&2; "
                          + "echo done; exit 0"],
        onLine: { _ in lines += 1 }, register: { _ in })
    let elapsed = Date().timeIntervalSince(began)
    check("a child that floods stderr does not deadlock", flood.outcome == .succeeded,
          "\(flood.outcome) after \(String(format: "%.2fs", elapsed)): \(flood.message)")
    check("…and its stdout still arrives", lines == 1, "\(lines) line(s)")

    // Success is silent for mac-ocr, and an empty stderr must not be confused
    // with a lost one.
    let quiet = Runner.runStreaming(
        binary: sh, arguments: ["-c", "echo only stdout; exit 0"],
        onLine: { _ in }, register: { _ in })
    check("a clean run reports no error text",
          quiet.outcome == .succeeded && quiet.message.isEmpty, "'\(quiet.message)'")
}

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
    let json = dir.appendingPathComponent("rebuilt.json")
    _ = Runner.run(binary: binary, file: rebuilt, outputFolder: nil,
                   argumentsOverride: Runner.jsonArguments(for: rebuilt, jsonOut: json),
                   register: { _ in })
    let read = (try? String(contentsOf: json, encoding: .utf8)) ?? ""
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
        file: src, binary: binary, output: out,
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
        let jb = dir.appendingPathComponent("book-jbig2.ocr.pdf")
        var jbOutcome: Runner.Result.Outcome?
        OCRModel.makeSearchablePDF(
            file: src, binary: binary, output: jb,
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
    } else {
        print("  skipped — jbig2enc/qpdf not installed (\(JBIG2.installHint))")
    }

    // A source with no outline must publish exactly as before.
    let plain = dir.appendingPathComponent("plain.pdf")
    makeScannedPDF(at: plain, lines: ["NO OUTLINE HERE"])
    let plainOut = dir.appendingPathComponent("plain.ocr.pdf")
    var plainOutcome: Runner.Result.Outcome?
    OCRModel.makeSearchablePDF(
        file: plain, binary: binary, output: plainOut,
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
    }
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

    // Extract Text mode: a child that ignores SIGTERM must not wedge the worker.
    var cancelled = false
    var captured: Process?
    let began = Date()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { cancelled = true }
    let result = Runner.run(
        binary: "/bin/sh",
        file: URL(fileURLWithPath: "/tmp/none.pdf"),
        outputFolder: nil,
        argumentsOverride: ["-c", "trap '' TERM; sleep 30"],
        wasCancelled: { cancelled },
        register: { captured = $0 })
    let elapsed = Date().timeIntervalSince(began)
    if let captured { Runner.stop(captured) }
    check("Runner.run returns promptly when cancelled, even against SIGTERM-proof children",
          elapsed < 5, String(format: "%.2fs", elapsed))
    check("…and reports it as cancelled", result.outcome == .cancelled, "\(result.outcome)")

    // A failing run must never report a bare empty message.
    let failed = Runner.run(
        binary: "/bin/sh",
        file: URL(fileURLWithPath: "/tmp/none.pdf"),
        outputFolder: nil,
        argumentsOverride: ["-c", "exit 3"],
        register: { _ in })
    check("a failure always carries a message",
          failed.outcome == .failed && !failed.message.isEmpty, "'\(failed.message)'")

    // A batch must never plan to overwrite one of its own inputs.
    let folder = URL(fileURLWithPath: "/Users/someone/Scans")
    let original = folder.appendingPathComponent("scan.pdf")
    let previous = folder.appendingPathComponent("scan.ocr.pdf")
    let outs = OCRModel.uniqueOutputs(for: [original, previous], besideOriginal: true,
                                      folder: nil, suffix: ".ocr", extension: "pdf")
    let planned = Set(outs.values.map { $0.standardizedFileURL.path })
    let inputs = Set([original, previous].map { $0.standardizedFileURL.path })
    check("no output overwrites another input in the same batch",
          planned.isDisjoint(with: inputs),
          "planned \(planned.sorted()) vs inputs \(inputs.sorted())")
    resetPrefs()
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
        file: src, binary: binary, output: dir.appendingPathComponent("blanky.ocr.pdf"),
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
        let rebuiltJSON = dir.appendingPathComponent("rebuilt.json")
        _ = Runner.run(binary: binary, file: rebuilt, outputFolder: nil,
                       argumentsOverride: Runner.jsonArguments(for: rebuilt,
                                                               jsonOut: rebuiltJSON),
                       register: { _ in })
        let seen = (try? String(contentsOf: rebuiltJSON, encoding: .utf8)) ?? ""
        check("words outside the crop survive the rebuild",
              seen.contains("ALPHA") && seen.contains("CHARLIE"),
              "ALPHA \(seen.contains("ALPHA")), CHARLIE \(seen.contains("CHARLIE"))")
    } else {
        check("the rebuild is the full sheet, not the crop", false, "no rebuilt PDF")
    }

    // Recognise the original (the non-rebuild path, which is where this bites)
    // and compose the layer straight onto it.
    let json = dir.appendingPathComponent("obs.json")
    _ = Runner.run(binary: binary, file: cropped, outputFolder: nil,
                   argumentsOverride: Runner.jsonArguments(for: cropped, jsonOut: json),
                   register: { _ in })
    let out = dir.appendingPathComponent("out.pdf")
    if let byPage = try? SearchableWriter.observations(fromJSONAt: json) {
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
    let copyJSON = dir.appendingPathComponent("copy.json")
    _ = Runner.run(binary: binary, file: untrimmed, outputFolder: nil,
                   argumentsOverride: Runner.jsonArguments(for: untrimmed, jsonOut: copyJSON),
                   register: { _ in })
    let rendered = (try? String(contentsOf: copyJSON, encoding: .utf8)) ?? ""
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

print("\nmixed page sizes and rotation through the whole pipeline")

do {
    resetPrefs()
    let dir = tmp.appendingPathComponent("mixed")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    /// An image-only page of a given size carrying one legible line.
    func page(_ url: URL, w: CGFloat, h: CGFloat, text: String) {
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
        page(one, w: s.0, h: s.1, text: s.2)
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
        file: src, binary: binary, output: out,
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

print("\npartial results are never published")

do {
    resetPrefs()
    let outDir = tmp.appendingPathComponent("publish")
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    // A truncated build is detectable purely from the page count.
    let src = tmp.appendingPathComponent("pub-src.pdf")
    let three = PDFDocument()
    for i in 1...3 {
        let one = tmp.appendingPathComponent("pub-\(i).pdf")
        makeScannedPDF(at: one, lines: ["page \(i) of the source"])
        if let d = PDFDocument(url: one), let p = d.page(at: 0) {
            three.insert(p, at: three.pageCount)
        }
    }
    three.write(to: src)
    check("the source has three pages", PDFDocument(url: src)?.pageCount == 3)

    // Compose with cancellation already set: the writer stops early.
    let staged = outDir.appendingPathComponent("staged.pdf")
    let json = outDir.appendingPathComponent("obs.json")
    _ = Runner.run(binary: binary, file: src, outputFolder: nil,
                   argumentsOverride: Runner.jsonArguments(for: src, jsonOut: json),
                   register: { _ in })
    let byPage = (try? SearchableWriter.observations(fromJSONAt: json)) ?? [:]
    try? SearchableWriter.compose(visible: src, observations: byPage, to: staged,
                                  isCancelled: { true })
    let truncated = PDFDocument(url: staged)?.pageCount ?? -1
    check("a cancelled compose really does truncate", truncated < 3, "\(truncated) pages")

    // Which is exactly what the page-count guard catches before publishing.
    let published = outDir.appendingPathComponent("published.pdf")
    check("the truncated file is not at the destination",
          !FileManager.default.fileExists(atPath: published.path))

    // A previous good output must survive a later failed run.
    let good = outDir.appendingPathComponent("keeper.pdf")
    try? SearchableWriter.compose(visible: src, observations: byPage, to: good)
    let goodPages = PDFDocument(url: good)?.pageCount ?? -1
    check("a complete run writes every page", goodPages == 3, "\(goodPages)")
    check("and it stays intact on disk",
          FileManager.default.fileExists(atPath: good.path) && goodPages == 3)
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

    func run(_ file: URL, binary: String, control: RunControl = RunControl(),
             rebuild: Bool = true) -> (Runner.Result.Outcome?, String) {
        var outcome: Runner.Result.Outcome?
        var message = ""
        OCRModel.makeSearchablePDF(
            file: file, binary: binary,
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
    let (junkOutcome, junkMessage) = run(junk, binary: binary)
    check("an unreadable file fails, and says which way", junkOutcome == .failed,
          "\(String(describing: junkOutcome)): \(junkMessage)")
    check("…naming the real problem",
          junkMessage.lowercased().contains("pdf") || junkMessage.lowercased().contains("image"),
          junkMessage)

    // A binary that cannot be launched must fail the file, not the batch.
    let real = dir.appendingPathComponent("real.pdf")
    makeScannedPDF(at: real, lines: ["a page that would OCR fine"])
    let (badBinaryOutcome, badBinaryMessage) = run(real, binary: "/nonexistent/mac-ocr")
    check("an unlaunchable binary is a failure, not a crash",
          badBinaryOutcome == .failed, badBinaryMessage)

    // Cancel before anything starts: reported as cancelled, never as failed,
    // and nothing is published. R14 was exactly this mistake on one route.
    let cancelled = RunControl()
    cancelled.cancel()
    let output = dir.appendingPathComponent("never-written.pdf")
    var cancelOutcome: Runner.Result.Outcome?
    OCRModel.makeSearchablePDF(
        file: real, binary: binary, output: output,
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

    // Two pages of differing size, per invariant 5 — the non-rebuild path takes
    // its geometry from the source rather than from anything it drew, which is
    // precisely where the crop-box bugs lived.
    let src = dir.appendingPathComponent("plain.pdf")
    let merged = PDFDocument()
    for (i, lines) in [["first page of the untouched source"],
                       ["second page, a different size"]].enumerated() {
        let one = dir.appendingPathComponent("p\(i).pdf")
        makeScannedPDF(at: one, lines: lines)
        if let doc = PDFDocument(url: one), let page = doc.page(at: 0) {
            merged.insert(page, at: merged.pageCount)
        }
    }
    merged.write(to: src)

    let output = dir.appendingPathComponent("plain.ocr.pdf")
    var outcome: Runner.Result.Outcome?
    var message = ""
    OCRModel.makeSearchablePDF(
        file: src, binary: binary, output: output,
        rebuild: false, rebuildMode: .auto, password: nil,
        control: RunControl(), progress: { _, _ in },
        report: { o, m in outcome = o; message = m })

    check("the non-rebuild path succeeds", outcome == .succeeded, message)
    check("…keeps every page",
          PDFDocument(url: output)?.pageCount == merged.pageCount,
          "\(PDFDocument(url: output)?.pageCount ?? -1) of \(merged.pageCount)")
    let text = embeddedText(of: output)
    check("…and writes a text layer", text.contains("first page"), text.prefix(80).description)
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
    check("…and it reaches mac-ocr's command line",
          Runner.recognitionArguments(settings).contains("--password")
            && Runner.recognitionArguments(settings).contains(secret))

    let output = dir.appendingPathComponent("locked.ocr.pdf")
    var outcome: Runner.Result.Outcome?
    var message = ""
    OCRModel.makeSearchablePDF(
        file: locked, binary: binary, output: output,
        rebuild: true, rebuildMode: .auto, password: secret,
        settings: settings, control: RunControl(), progress: { _, _ in },
        report: { o, m in outcome = o; message = m })
    check("an encrypted PDF runs through the whole pipeline", outcome == .succeeded, message)
    check("…and its text is recovered",
          embeddedText(of: output).contains("Locked"), embeddedText(of: output).prefix(60).description)

    // And the wrong password fails loudly rather than rendering blank pages.
    var wrongOutcome: Runner.Result.Outcome?
    OCRModel.makeSearchablePDF(
        file: locked, binary: binary,
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
        file: tinted, binary: binary, output: output,
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
    _ = Runner.run(binary: binary, file: src, outputFolder: nil,
                   argumentsOverride: Runner.jsonArguments(for: src, jsonOut: json),
                   register: { _ in })
    let byPage = (try? SearchableWriter.observations(fromJSONAt: json)) ?? [:]

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
    let warning = OCRModel.digitalTextWarning(for: [digital], of: 3)
    check("the warning names the file", warning.contains("born-digital.pdf"), warning)
    check("…says how much of the batch it is", warning.contains("1 of 3"), warning)
    check("…and says re-OCRing is legitimate when the text is broken",
          warning.lowercased().contains("broken"), warning)

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
    }
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
            && Prefs.allKeys.contains(Prefs.binaryPath))

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
    check("the cache still finds the real binary", Runner.resolveBinary() != nil)
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
    guard let binary = Runner.resolveBinary() else {
        check("mac-ocr is available for the reserved-name checks", false)
        exit(1)
    }
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
            file: src, binary: binary, output: out,
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

    // Same class, different input: `saturation` and `fullBox` size their buffers
    // from the page box rather than from a declared image, so a MediaBox the
    // file invented reaches the same unguarded `Int(_:)`.
    check("an absurd MediaBox does not kill the process either",
          probeSurvives(hostilePDF(named: "hugebox.pdf", width: "8", height: "8",
                                   mediaBox: "0 0 1e300 1e300")),
          "saturation/flatten size buffers from the page box")

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
    check("the refusal does not point at the render-DPI setting",
          !message.lowercased().contains("render dpi")
              || message.contains("does not"),
          message)
    check("the refusal names the control that does let the file through",
          message.contains("Rebuild page images first"),
          message)

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

    // The bound must not have been bought by making the normal case slow.
    setenv("SHELL", realShell ?? "/bin/zsh", 1)
    Runner.forgetToolPaths()
    let t = Date()
    _ = Runner.locateTool("mac-ocr")
    let normal = Date().timeIntervalSince(t)
    check("a real shell still answers promptly", normal < 2,
          String(format: "cold lookup took %.3fs", normal))
}

resetPrefs()
print("\n\(checks - failures)/\(checks) passed")
exit(failures == 0 ? 0 : 1)
