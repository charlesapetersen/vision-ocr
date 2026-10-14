import Foundation
import CoreGraphics
import CoreText

/// "Measure on this Mac" (C57, `ocr-integrate-settings`, is-timing): a short run that times each
/// accurate-mode reader this Mac can run, through the production pipeline, and replaces the
/// settings table's speed column with what it found. It measures speed only, never accuracy.
///
/// Its pages are drawn here rather than bundled: the comparison's sample is third-party and
/// copyrighted, and a drawn page costs the app nothing to carry. So its seconds are not the
/// sample's. They are compared with `AccurateReader.referenceSeconds`, the same run on the Mac
/// the table was measured on, and the table's figure is scaled by the ratio.
enum TimingRun {
    /// One reader on one kind of page.
    struct Leg: Equatable {
        let reader: Prefs.AccurateReader
        let kind: Recogniser.PageKind
    }

    /// Pages a leg reads: one broadsheet, or two book pages.
    static func pages(_ kind: Recogniser.PageKind) -> Int { kind == .newspaper ? 1 : 2 }

    /// What a run would time now: Vision on each kind, which needs nothing, and every reader
    /// offered on a kind under `memoryGB` with nothing left to download.
    static func legs(memoryGB: Double,
                     environment: [String: String] = ProcessInfo.processInfo.environment) -> [Leg] {
        [Recogniser.PageKind.newspaper, .other].flatMap { kind in
            Prefs.AccurateReader.offered(kind, memoryGB: memoryGB)
                .filter { $0.missing(kind, environment: environment).isEmpty }
                .map { Leg(reader: $0, kind: kind) }
        }
    }

    /// About how long `legs` take on the Mac the table was measured on, in seconds.
    static func estimate(_ legs: [Leg]) -> Double {
        legs.reduce(0) { $0 + ($1.reader.referenceSeconds($1.kind) ?? 0) * Double(pages($1.kind)) }
    }

    /// The settings a leg runs under: the shipped defaults, none of the user's, so that this
    /// Mac and the reference read the same pages the same way; the leg's reader in both pairs;
    /// and the user's memory cap. The pages are of the leg's kind, and the classifier calls
    /// them so (measured: every leg of the reference runs read without a fallback, and
    /// Falcon-OCR is approved only on regions for newspapers and only on align for the rest);
    /// a Mac that called them otherwise would end the run, saying the reader is not offered.
    static func settings(_ leg: Leg, memoryGB: Double) -> Prefs.Snapshot {
        // Registered only, so nothing is written; nil is only ever NSGlobalDomain's name.
        let name = "local.visionocr-timing.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        Prefs.register(migrate: false, into: d)
        var s = Prefs.Snapshot.current(d)
        let route = leg.reader.route(leg.kind)
        s.modelArrangement = route.arrangement
        s.modelReader = route.reader
        s.newspaperModelArrangement = route.arrangement
        s.newspaperModelReader = route.reader
        s.modelMemoryGB = memoryGB
        return s
    }

    enum Failure: LocalizedError {
        case pages(String), leg(Leg, String), cancelled
        var errorDescription: String? {
            switch self {
            case .pages(let why): return "Could not draw the timing pages: \(why)"
            case .leg(let leg, let why): return "\(leg.reader.name) on \(leg.kind.pages) did not finish: \(why)"
            case .cancelled: return "Stopped."
            }
        }
    }

    /// Times every leg in turn and returns the seconds a page each took. Blocking; call it
    /// off the main thread. A leg that fails, or whose model fell back to Vision, ends the
    /// run with nothing stored: a time for a reading that did not happen is not a speed.
    static func run(_ legs: [Leg], memoryGB: Double, control: RunControl,
                    now: () -> Date = Date.init,
                    progress: @escaping (String) -> Void) throws -> Prefs.AccurateTiming {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("visionocr-timing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        } catch { throw Failure.pages(error.localizedDescription) }
        var sources: [Recogniser.PageKind: URL] = [:]
        for kind in [Recogniser.PageKind.newspaper, .other] where legs.contains(where: { $0.kind == kind }) {
            let url = scratch.appendingPathComponent("\(kind.rawValue).pdf")
            try drawPages(kind, to: url)
            sources[kind] = url
        }
        var seconds: [String: Double] = [:]
        for (i, leg) in legs.enumerated() {
            if control.isCancelled { throw Failure.cancelled }
            progress("Timing \(leg.reader.name) on \(leg.kind.pages) (\(i + 1) of \(legs.count))…")
            guard let source = sources[leg.kind] else { continue }
            let output = scratch.appendingPathComponent("\(i).ocr.pdf")
            var outcome: (Runner.Result.Outcome, String)?
            var fellBack: String?
            let start = Date()
            OCRModel.makeSearchablePDF(
                file: source, output: output, rebuild: true, rebuildMode: .auto, password: nil,
                settings: settings(leg, memoryGB: memoryGB), control: control,
                progress: { _, _ in }, modelFallbackNote: { fellBack = $0 },
                report: { outcome = ($0, $1) })
            let elapsed = Date().timeIntervalSince(start)
            if control.isCancelled || outcome?.0 == .cancelled { throw Failure.cancelled }
            guard let outcome, outcome.0 == .succeeded else {
                throw Failure.leg(leg, outcome?.1 ?? "no result")
            }
            if let fellBack { throw Failure.leg(leg, fellBack) }
            seconds[Prefs.AccurateTiming.key(leg.reader, leg.kind)] = elapsed / Double(pages(leg.kind))
        }
        return Prefs.AccurateTiming(measured: now(), seconds: seconds)
    }

    // MARK: - The pages

    /// Writes `kind`'s timing pages to `url`: grey scans with no text layer, a broadsheet of
    /// six columns at 200 dpi or two book pages at 300 dpi, their words the same on every Mac.
    static func drawPages(_ kind: Recogniser.PageKind, to url: URL) throws {
        let (size, dpi): (CGSize, CGFloat) = kind == .newspaper
            ? (CGSize(width: 864, height: 1224), 200) : (CGSize(width: 396, height: 612), 300)
        var box = CGRect(origin: .zero, size: size)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw Failure.pages("cannot write \(url.lastPathComponent)")
        }
        var words = Words(seed: kind == .newspaper ? 1910 : 1926)
        for _ in 0..<pages(kind) {
            guard let image = drawPage(kind, size: size, dpi: dpi, words: &words) else {
                throw Failure.pages("cannot draw a page")
            }
            pdf.beginPDFPage(nil)
            pdf.draw(image, in: box)
            pdf.endPDFPage()
        }
        pdf.closePDF()
    }

    private static func drawPage(_ kind: Recogniser.PageKind, size: CGSize, dpi: CGFloat,
                                 words: inout Words) -> CGImage? {
        let scale = dpi / 72
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 0.96, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(gray: 0.1, alpha: 1)
        ctx.setStrokeColor(gray: 0.1, alpha: 1)
        if kind == .newspaper {
            let margin: CGFloat = 36, gutter: CGFloat = 10, columns = 6
            let top = size.height - margin
            draw(text("THE EVENING SAMPLE", "Times-Bold", 60, centred: true), in:
                 CGRect(x: margin, y: top - 76, width: size.width - 2 * margin, height: 90), ctx)
            draw(text("VOL. XII.    WEDNESDAY, MARCH 16, 1910.    PRICE ONE CENT.", "Times-Roman", 9, centred: true),
                 in: CGRect(x: margin, y: top - 92, width: size.width - 2 * margin, height: 14), ctx)
            ctx.setLineWidth(1.2)
            ctx.stroke(CGRect(x: margin, y: top - 96, width: size.width - 2 * margin, height: 0))
            let width = (size.width - 2 * margin - gutter * CGFloat(columns - 1)) / CGFloat(columns)
            for c in 0..<columns {
                let x = margin + CGFloat(c) * (width + gutter)
                let column = NSMutableAttributedString()
                while column.length < 9000 {
                    column.append(text(words.sentence(4).uppercased() + "\n", "Times-Bold", 11, centred: true))
                    for _ in 0..<3 {
                        column.append(text("  " + words.paragraph() + "\n", "Times-Roman", 6.8))
                    }
                }
                draw(column, in: CGRect(x: x, y: margin, width: width, height: top - 102 - margin), ctx)
                if c > 0 {
                    ctx.setLineWidth(0.4)
                    ctx.stroke(CGRect(x: x - gutter / 2, y: margin, width: 0, height: top - 102 - margin))
                }
            }
        } else {
            let margin: CGFloat = 50
            let body = NSMutableAttributedString()
            body.append(text("CHAPTER \(words.next(9) + 2)\n\n", "Times-Bold", 13, centred: true))
            while body.length < 4000 {
                body.append(text("    " + words.paragraph() + "\n", "Times-Roman", 10.5))
            }
            draw(body, in: CGRect(x: margin, y: margin + 20, width: size.width - 2 * margin,
                                  height: size.height - 2 * margin - 20), ctx)
            draw(text("\(words.next(300) + 1)", "Times-Roman", 9, centred: true),
                 in: CGRect(x: margin, y: margin - 10, width: size.width - 2 * margin, height: 14), ctx)
        }
        return ctx.makeImage()
    }

    private static func text(_ s: String, _ font: String, _ size: CGFloat,
                             centred: Bool = false) -> NSMutableAttributedString {
        var alignment: CTTextAlignment = centred ? .center : .justified
        let style = withUnsafePointer(to: &alignment) { pointer in
            CTParagraphStyleCreate([CTParagraphStyleSetting(spec: .alignment,
                                                             valueSize: MemoryLayout<CTTextAlignment>.size,
                                                             value: pointer)], 1)
        }
        return NSMutableAttributedString(string: s, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(font as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style,
        ])
    }

    private static func draw(_ s: NSAttributedString, in rect: CGRect, _ ctx: CGContext) {
        let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(s), CFRange(location: 0, length: 0),
                                             CGPath(rect: rect, transform: nil), nil)
        CTFrameDraw(frame, ctx)
    }

    /// Plain English words in a fixed order, from a fixed seed: the same pages everywhere.
    struct Words {
        private var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next(_ n: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(n))
        }

        mutating func sentence(_ count: Int) -> String {
            let s = (0..<count).map { _ in Self.vocabulary[next(Self.vocabulary.count)] }.joined(separator: " ")
            return s.prefix(1).uppercased() + s.dropFirst()
        }

        mutating func paragraph() -> String {
            (0..<(4 + next(4))).map { _ in sentence(8 + next(12)) + (next(5) == 0 ? ";" : ".") }
                .joined(separator: " ")
        }

        static let vocabulary = """
            the of and to in a that was for on with as by at from his it be which this had not are \
            but were have their all they one been has more when would there who will no other so an \
            what out up into its said them only time than new these some could two our may first then \
            any like now over such make our after most also made did many before must through back \
            years where much your way well down should because each just those people how too little \
            state good very great world still own men work long here between both life being under \
            never day same another know while last might us great old year off come since against go \
            came right used take three city county council street railway company river bridge office \
            court mayor market school church board water public members meeting evening morning week \
            yesterday house letter account report question number place order hundred dollars cents \
            president committee government village farmers harvest weather station train passengers
            """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
    }
}
