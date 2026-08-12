import Foundation
import PDFKit
import Vision
import CoreGraphics

/// Recognition, done here rather than through the `mac-ocr` subprocess.
///
/// The dependency was kept deliberately for a long time and the reasons are in
/// `HANDOFF.md`. What changed the decision is that the handover was costing
/// capability, not tidiness:
///
///  - **We already have the pixels.** `flatten` renders every page to a
///    `CGImage`, wrote them into a PDF, and handed that PDF to a process which
///    re-opened and re-rasterised it at a resolution we did not control. R39 is
///    that round trip: `recogniserDPICeiling`, `engineAutoDPI` and half of U25
///    existed only to negotiate with a rasteriser we were already doing the work
///    of. Recognising the image directly deletes the question.
///  - **The geometry was being thrown away.** `mac-ocr` emits an axis-aligned
///    `boundingBox`; Vision returns a quadrilateral, and per-character ranges on
///    request. The text layer places every run with a zero rotation term because
///    a rotated one cannot be derived from a rectangle.
///
/// Recognition itself is unchanged — this is the same Vision, at the same
/// revision, with the same options — and that is the property the corpus
/// baseline depends on.
enum Recogniser {

    /// Pinned, not left to default. `mac-ocr` reports `requestRevision: 3` in
    /// its output, so every figure in this project's corpus was measured at
    /// revision 3; letting a future macOS pick a newer one would silently make
    /// the baseline describe a different recogniser. Raise it deliberately, with
    /// a corpus run, or not at all.
    static let revision = VNRecognizeTextRequestRevision3

    /// The languages this Mac supports, in Vision's own priority order.
    ///
    /// Replaces a subprocess (`mac-ocr languages`) with a direct call, so the
    /// Settings panel no longer pays ~85 ms and a process launch to populate a
    /// menu. The two recognizers support different sets — 30 against 6 on
    /// macOS 26.6 — which is why this takes the level rather than assuming.
    static func supportedLanguages(fast: Bool) -> [String] {
        let request = VNRecognizeTextRequest()
        request.revision = revision
        request.recognitionLevel = fast ? .fast : .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    /// Every page of a document, in the shape `SearchableWriter` consumes.
    ///
    /// **Recognises the bitmaps `flatten` already produced**, when there are
    /// any. That is the whole point of the change: the pipeline was rendering
    /// each page, writing it into a PDF, and handing that PDF to something that
    /// re-rendered it at a resolution of its own choosing. Now the pixels that
    /// were drawn are the pixels that are read, which is also the only way the
    /// text layer's coordinates can be *guaranteed* to describe the page they
    /// are drawn over rather than merely to line up in practice.
    ///
    /// When the user has turned the rebuild off there are no bitmaps, so the
    /// source is rasterised here — at its own resolution on Automatic, or at
    /// the chosen Page DPI. That is what `--pdf-dpi` used to mean, kept.
    ///
    /// Pages are recognised one at a time so cancellation lands between them
    /// and progress is exact — the page count is known up front, which it was
    /// not when progress came from counting streamed lines.
    static func recogniseDocument(
        visible: URL,
        bitmaps: [Flattener.RebuiltPage],
        settings: Prefs.Snapshot,
        password: String? = nil,
        isCancelled: () -> Bool = { false },
        onPage: (Int, Int) -> Void = { _, _ in }
    ) throws -> [Int: [SearchableWriter.Observation]] {
        var byPage: [Int: [SearchableWriter.Observation]] = [:]

        if !bitmaps.isEmpty {
            let total = bitmaps.count
            for (index, page) in bitmaps.enumerated() {
                if isCancelled() { return byPage }
                onPage(index, total)
                guard let image = loadImage(page) else {
                    throw SearchableWriter.Failure.unreadableSource
                }
                byPage[index + 1] = try recognise(image, settings: settings)
            }
            onPage(total, total)
            return byPage
        }

        guard let doc = Flattener.open(visible, password: password) else {
            throw SearchableWriter.Failure.unreadableSource
        }
        let total = doc.pageCount
        for index in 0..<total {
            if isCancelled() { return byPage }
            onPage(index, total)
            guard let page = doc.page(at: index) else { continue }
            guard let image = render(page, settings: settings) else {
                throw SearchableWriter.Failure.unreadableSource
            }
            byPage[index + 1] = try recognise(image, settings: settings)
        }
        onPage(total, total)
        return byPage
    }

    /// **Extract Text** mode: recognise a file and write it out.
    ///
    /// The three formats reproduce what `mac-ocr` emitted, field for field —
    /// `text` is the observations joined by newlines under a
    /// `==> path (page n/N) <==` banner, and the two JSON forms carry
    /// `page`, `pageCount`, `width`, `height`, `source`, `text` and the
    /// observation list. Somebody's script may be reading these, and a
    /// dependency change is not a reason to break its input.
    ///
    /// Images are recognised directly; PDFs go page by page through the same
    /// path the searchable pipeline uses.
    static func extract(from file: URL, to target: URL,
                        settings: Prefs.Snapshot, password: String? = nil,
                        isCancelled: () -> Bool = { false }) throws {
        struct PageOut {
            let page: Int, width: Int, height: Int
            let observations: [SearchableWriter.Observation]
            var text: String { observations.map(\.text).joined(separator: "\n") }
        }
        var out: [PageOut] = []

        if let doc = Flattener.open(file, password: password), doc.pageCount > 0 {
            for index in 0..<doc.pageCount {
                if isCancelled() { return }
                guard let page = doc.page(at: index), let image = render(page, settings: settings)
                else { throw SearchableWriter.Failure.unreadableSource }
                out.append(PageOut(page: index + 1, width: image.width, height: image.height,
                                   observations: try recognise(image, settings: settings)))
            }
        } else {
            // An image input, which the drop box accepts alongside PDFs.
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw SearchableWriter.Failure.unreadableSource }
            out.append(PageOut(page: 1, width: image.width, height: image.height,
                               observations: try recognise(image, settings: settings)))
        }

        func object(_ p: PageOut) -> [String: Any] {
            [
                "page": p.page, "pageCount": out.count,
                "width": p.width, "height": p.height,
                "source": ["path": file.path, "type": "file"],
                "text": p.text,
                "observations": p.observations.map { o in
                    [
                        "text": o.text,
                        "confidence": o.confidence,
                        "requestRevision": revision,
                        "boundingBox": ["x": o.boundingBox.x, "y": o.boundingBox.y,
                                        "width": o.boundingBox.width,
                                        "height": o.boundingBox.height],
                    ] as [String: Any]
                },
            ]
        }

        let body: String
        switch settings.textFormat {
        case .text:
            body = out.map { p in
                "==> \(file.path) (page \(p.page)/\(out.count)) <==\n" + p.text
            }.joined(separator: "\n") + "\n"
        case .json:
            let data = try JSONSerialization.data(withJSONObject: out.map(object),
                                                  options: [.prettyPrinted, .sortedKeys])
            body = String(decoding: data, as: UTF8.self) + "\n"
        case .jsonl:
            body = try out.map { p in
                let data = try JSONSerialization.data(withJSONObject: object(p),
                                                      options: [.sortedKeys])
                return String(decoding: data, as: UTF8.self)
            }.joined(separator: "\n") + "\n"
        }
        try Data(body.utf8).write(to: target, options: .atomic)
    }

    /// The bitmap `flatten` wrote for a page, decoded.
    static func loadImage(_ page: Flattener.RebuiltPage) -> CGImage? {
        let url: URL
        switch page.content {
        case .bilevel(let u): url = u
        case .jpeg(let u): url = u
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Rasterise a source page for recognition, for the no-rebuild path.
    ///
    /// Bounded by `Flattener.maximumPageMegapixels` for the same reason the
    /// rebuild is: a Swift array that cannot be allocated is a crash, not a
    /// catchable error, and it would take every other file in the batch with it
    /// (R24). Vision itself has no such limit — a 216-megapixel page it accepts
    /// without complaint, which is the measurement that made mac-ocr's 200 MP
    /// refusal, `recogniserDPICeiling` and R39 unnecessary rather than merely
    /// unfortunate.
    static func render(_ page: PDFPage, settings: Prefs.Snapshot) -> CGImage? {
        let box = Flattener.fullBox(of: page)
        let dpi = settings.pdfDPIAuto ? Flattener.rebuildDPI(of: page)
                                      : Double(settings.pdfDPI)
        let scale = dpi / 72.0
        let wide = (box.width * scale).rounded(), high = (box.height * scale).rounded()
        guard wide.isFinite, high.isFinite, wide >= 1, high >= 1,
              wide * high <= Double(Flattener.maximumPageMegapixels) * 1_000_000
        else { return nil }
        let w = max(Int(wide), 1), h = max(Int(high), 1)
        guard let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                              width: w, height: h, from: .mediaBox),
              let provider = CGDataProvider(data: Data(grey) as CFData)
        else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// One page's recognised text, in the shape the rest of the pipeline already
    /// consumes.
    ///
    /// **The origin is the trap.** Vision reports normalised boxes with a
    /// *bottom-left* origin; `SearchableWriter.BoundingBox` is documented as
    /// *top-left*, because that is what `mac-ocr` emitted and what every
    /// placement constant was calibrated against. Flipping here rather than at
    /// the call site keeps the one conversion in the one place that knows both
    /// conventions.
    static func recognise(_ image: CGImage,
                          settings: Prefs.Snapshot) throws -> [SearchableWriter.Observation] {
        let request = VNRecognizeTextRequest()
        request.revision = revision
        request.recognitionLevel = settings.fast ? .fast : .accurate
        request.usesLanguageCorrection = settings.languageCorrection
        let languages = Runner.splitList(settings.languages)
        if !languages.isEmpty { request.recognitionLanguages = languages }
        let words = Runner.splitList(settings.customWords)
        if !words.isEmpty { request.customWords = words }
        if settings.minTextHeightOn, settings.minTextHeight > 0 {
            request.minimumTextHeight = Float(settings.minTextHeight)
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        var out: [SearchableWriter.Observation] = []
        for case let observation as VNRecognizedTextObservation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            // Applied here, not by Vision: the request has no minimum-confidence
            // option, and the setting's contract is that anything below the mark
            // is discarded. `> 0` because the default keeps everything and an
            // observation at exactly 0 confidence is still text on the page.
            if settings.confidence > 0, Double(candidate.confidence) < settings.confidence {
                continue
            }
            let box = observation.boundingBox
            out.append(SearchableWriter.Observation(
                boundingBox: SearchableWriter.BoundingBox(
                    x: box.origin.x,
                    y: 1 - box.origin.y - box.size.height,
                    width: box.size.width,
                    height: box.size.height),
                text: candidate.string,
                confidence: Double(candidate.confidence)))
        }
        return out
    }
}
