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
///
/// **Three of those options were got right by reading `mac-ocr`'s source rather
/// than by testing** (MIT, Copyright (c) Hiroki Osame; the licence travels in
/// `Contents/Resources/mac-ocr-LICENSE`). Each was a silent divergence from the
/// behaviour every corpus figure was measured with:
///
///  - EXIF orientation is read and passed to the request handler. An attempt to
///    build a fixture for this locally could not get an orientation flag to
///    stick through `sips` or `CGImageDestination`, so the prior art settled in
///    minutes what a test could not.
///  - `automaticallyDetectsLanguage` is set to `languages.isEmpty`. Leaving it
///    unset is not the same as leaving it alone.
///  - `confidence` is the *observation's*, not the top candidate's. They are
///    different numbers, and the threshold and the JSON field both reported the
///    former.
///
/// Their per-word geometry — `VNRecognizedText.boundingBox(for:)` over
/// whitespace-separated tokens — is the capability this app's text layer would
/// want next, and is not reachable through the CLI's output at all.
enum Recogniser {

    /// Recognition's own failures, kept apart from `SearchableWriter`'s so a
    /// cancellation is never mistaken for a broken file.
    enum Failure: LocalizedError, Equatable {
        case cancelled
        case unreadablePage(Int)

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Cancelled."
            case .unreadablePage(let n):
                return "Page \(n) could not be prepared for recognition. It may be "
                    + "larger than this app will render."
            }
        }
    }

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

    /// The codes in `list` this Mac will refuse, given the recognizer in use.
    ///
    /// Empty when the language list could not be read at all — that means "we do
    /// not know", and reporting every code as unsupported because the probe
    /// failed would be a warning that fires hardest when it knows least.
    static func unsupportedLanguages(in list: String, fast: Bool) -> [String] {
        let available = supportedLanguages(fast: fast)
        guard !available.isEmpty else { return [] }
        let known = Set(available.map { $0.lowercased() })
        return Runner.splitList(list).filter { !known.contains($0.lowercased()) }
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
    ///
    /// **`useHelper` sends the page bitmaps to a helper process** instead of
    /// recognising them here — R40, and the reasoning is on `helperName` below.
    /// It applies only to this branch, where `flatten` has already written the
    /// pages to disk and the handover costs nothing but the paths. The
    /// no-rebuild branch underneath renders in memory and would have to encode
    /// and write every page to use a helper at all; it is an opt-out of the
    /// default route, it is not what the corpus gate or the library sweep
    /// exercise, and it is left in-process rather than given that cost
    /// unmeasured.
    static func recogniseDocument(
        visible: URL,
        bitmaps: [Flattener.RebuiltPage],
        settings: Prefs.Snapshot,
        password: String? = nil,
        useHelper: Bool = false,
        isCancelled: () -> Bool = { false },
        onPage: (Int, Int) -> Void = { _, _ in },
        register: (Process) -> Void = { _ in },
        onFallback: (String) -> Void = { _ in }
    ) throws -> [Int: [SearchableWriter.Observation]] {
        var byPage: [Int: [SearchableWriter.Observation]] = [:]

        // Cancellation **throws** rather than returning what it has. Returning a
        // short dictionary hands the caller something that looks like a finished
        // document, and `compose` would publish a text layer missing its last
        // pages — invariant 1's exact shape. `makeSearchablePDF` catches this and
        // asks the control whether it was a cancellation before calling it a
        // failure, which is the same idiom the flatten step already uses.
        if !bitmaps.isEmpty {
            let total = bitmaps.count
            if useHelper, let helper = helperPath() {
                do {
                    return try recogniseViaHelper(
                        images: bitmaps.map(imageURL(of:)), settings: settings,
                        helper: helper, isCancelled: isCancelled, onPage: onPage,
                        register: register)
                } catch let cancellation as Failure {
                    throw cancellation
                } catch {
                    // Degrade, do not fail — and say so. A helper that has
                    // stopped working costs throughput and nothing else, but a
                    // silent fallback would hide both the breakage and the 2.5x
                    // it is costing, which is how R40 came to ship unnoticed in
                    // the first place.
                    if isCancelled() { throw Failure.cancelled }
                    onFallback("The recognition helper could not be used — "
                               + "\(error.localizedDescription). Recognising in "
                               + "the app instead, which is slower.")
                }
            }
            for (index, page) in bitmaps.enumerated() {
                if isCancelled() { throw Failure.cancelled }
                onPage(index, total)
                guard let image = loadImage(page) else {
                    throw Failure.unreadablePage(index + 1)
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
            if isCancelled() { throw Failure.cancelled }
            onPage(index, total)
            guard let page = doc.page(at: index) else { continue }
            guard let image = render(page, settings: settings) else {
                throw Failure.unreadablePage(index + 1)
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
                if isCancelled() { throw Failure.cancelled }
                guard let page = doc.page(at: index), let image = render(page, settings: settings)
                else { throw Failure.unreadablePage(index + 1) }
                out.append(PageOut(page: index + 1, width: image.width, height: image.height,
                                   observations: try recognise(image, settings: settings)))
            }
        } else {
            // An image input, which the drop box accepts alongside PDFs. This
            // is the only path where EXIF orientation exists to be honoured —
            // the PDF pages above are rendered by us and have none.
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { throw SearchableWriter.Failure.unreadableSource }
            let orientation = exifOrientation(of: source)
            // Reported in display space, so a sideways photograph does not
            // describe itself with its width and height swapped.
            let sideways = [.left, .leftMirrored, .right, .rightMirrored]
                .contains(orientation)
            out.append(PageOut(page: 1,
                               width: sideways ? image.height : image.width,
                               height: sideways ? image.width : image.height,
                               observations: try recognise(image, orientation: orientation,
                                                           settings: settings)))
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
            // The `==> path (page n/N) <==` banner only when there is more than
            // one page. Verified against the binary rather than assumed: a
            // single-page file gets no banner, a two-page file gets one per page.
            // Emitting it unconditionally put the file's whole path into a
            // one-page .txt, which the word-spacing check noticed by counting
            // every path component as a word.
            body = out.map { p in
                out.count > 1
                    ? "==> \(file.path) (page \(p.page)/\(out.count)) <==\n" + p.text
                    : p.text
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

    /// The EXIF orientation an image file declares, or `.up`.
    static func exifOrientation(of source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let raw = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: raw)
        else { return .up }
        return orientation
    }

    /// The file `flatten` wrote for a page.
    ///
    /// Split out from `loadImage` because the helper wants the *path* — it does
    /// its own decoding, in its own process, through the function below, so the
    /// two routes cannot drift into decoding the same file differently.
    static func imageURL(of page: Flattener.RebuiltPage) -> URL {
        switch page.content {
        case .bilevel(let url), .jpeg(let url): return url
        }
    }

    /// The bitmap `flatten` wrote for a page, decoded.
    static func loadImage(_ page: Flattener.RebuiltPage) -> CGImage? {
        loadImage(at: imageURL(of: page))
    }

    /// One decode, used by the app and by the helper process alike.
    static func loadImage(at url: URL) -> CGImage? {
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
        // **The crop box, not the whole sheet.** `SearchableWriter.compose` maps
        // observations from the crop box into the sub-rectangle where the crop
        // lands on the published media-box page, because that is what mac-ocr
        // rendered — CoreGraphics draws a page's *display* box by default.
        // Rendering the media box here instead would normalise the boxes to a
        // different rectangle and compose would map them a second time, putting
        // the invisible text off the ink on every cropped page. Two of the
        // crop-box checks caught exactly that.
        //
        // `displayBox` falls back to the media box when a page has no crop box,
        // which is 44 of the 78 corpus documents and every rebuilt file — so for
        // almost everything the two are the same rectangle.
        let box = Flattener.displayBox(of: page)
        let dpi = settings.pdfDPIAuto ? Flattener.rebuildDPI(of: page)
                                      : Double(settings.pdfDPI)
        let scale = dpi / 72.0
        let wide = (box.width * scale).rounded(), high = (box.height * scale).rounded()
        guard wide.isFinite, high.isFinite, wide >= 1, high >= 1,
              wide * high <= Double(Flattener.maximumPageMegapixels) * 1_000_000
        else { return nil }
        let w = max(Int(wide), 1), h = max(Int(high), 1)
        guard let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                              width: w, height: h, from: .cropBox),
              let provider = CGDataProvider(data: Data(grey) as CFData)
        else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// The configured request, built where it can be asserted.
    ///
    /// Separate from `recognise` on purpose. The suite used to have forty checks
    /// on the argument list this app handed a CLI, and every one of them lost its
    /// subject when recognition came in-process. What those checks were really
    /// protecting is that **a setting the panel offers actually reaches the
    /// engine** — the failure `ocrAllPages` is named for, a setting that looked
    /// live and could not affect anything. A request object's properties are
    /// readable, so that property is still enumerable rather than merely
    /// plausible; see "every recognition setting reaches the request".
    static func makeRequest(_ settings: Prefs.Snapshot) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.revision = revision
        request.recognitionLevel = settings.fast ? .fast : .accurate
        request.usesLanguageCorrection = settings.languageCorrection

        let languages = Runner.splitList(settings.languages)
        if !languages.isEmpty { request.recognitionLanguages = languages }
        // Set explicitly, and only when no language was named. Leaving it unset
        // is not the same as leaving it alone: with no languages given Vision
        // falls back to its own default list rather than detecting, so an
        // untouched settings panel would have quietly stopped detecting the
        // language — a divergence from every figure the corpus was measured
        // with. mac-ocr sets `automaticallyDetectsLanguage = languages.isEmpty`
        // and this matches it.
        request.automaticallyDetectsLanguage = languages.isEmpty

        let words = Runner.splitList(settings.customWords)
        if !words.isEmpty { request.customWords = words }
        if settings.minTextHeightOn, settings.minTextHeight > 0 {
            request.minimumTextHeight = Float(settings.minTextHeight)
        }
        return request
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
    static func recognise(_ image: CGImage, orientation: CGImagePropertyOrientation = .up,
                          settings: Prefs.Snapshot) throws -> [SearchableWriter.Observation] {
        let request = makeRequest(settings)
        // Orientation, not `.up`. A photograph from a phone stores its pixels
        // sideways and says so in an EXIF tag, and
        // `CGImageSourceCreateImageAtIndex` hands back the stored pixels
        // without applying it. Vision reads rotated text anyway, so the
        // *strings* survive — but the boxes would be in the stored frame, which
        // is wrong for anything that positions text by them.
        //
        // Found by reading mac-ocr's own source rather than by testing: it
        // reads `kCGImagePropertyOrientation` and passes it to the handler, and
        // an attempt to build a fixture here could not get an EXIF flag to
        // stick through `sips` or `CGImageDestination`. Prior art was cheaper
        // than the fixture.
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation,
                                            options: [:])
        try handler.perform([request])

        var out: [SearchableWriter.Observation] = []
        for case let observation as VNRecognizedTextObservation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            // Applied here, not by Vision: the request has no minimum-confidence
            // option, and the setting's contract is that anything below the mark
            // is discarded. `> 0` because the default keeps everything and an
            // observation at exactly 0 confidence is still text on the page.
            // The *observation's* confidence, not the candidate's. They are
            // different numbers, and mac-ocr filtered and reported on the
            // observation — so a user's existing threshold has to keep meaning
            // what it meant, and the `confidence` field in the JSON has to keep
            // reporting the same quantity.
            if settings.confidence > 0, Double(observation.confidence) < settings.confidence {
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
                confidence: Double(observation.confidence)))
        }
        return out
    }

    // MARK: - Recognition in helper processes (R40)

    /// **Vision does not parallelise across concurrent requests inside one
    /// process.** Measured on thirty-six page images in one process: 22.5s at
    /// one thread, 20.8s at six — 1.08x. The ~3x that running files
    /// concurrently used to buy was never thread-level; it came from `mac-ocr`
    /// being *one process per file*, and removing that dependency handed it
    /// back. The corpus gate went from 75 minutes to 187 with every correctness
    /// figure unchanged or better, which is R40.
    ///
    /// So the parallelism has to be processes again — but not the dependency,
    /// and the distinction is the whole point:
    ///
    ///  - The helper is handed **bitmaps this app rendered**, never a PDF.
    ///    Nothing re-rasterises anything, so R39 cannot come back and
    ///    `recogniserDPICeiling` stays deleted.
    ///  - It compiles `Recogniser.recognise` — *this* function, above — so the
    ///    observations are identical by construction rather than by agreement.
    ///    That is what the corpus baseline depends on.
    ///  - The protocol is ours, so the quads and per-word boxes the CLI could
    ///    never expose stay reachable when the text layer wants them.
    ///  - It is never authoritative about failure. Any helper trouble at all
    ///    falls back to recognising in this process, so the worst a broken
    ///    helper can cost is time. A missing one degrades rather than fails,
    ///    which is the JBIG2 route's precedent.
    ///
    /// **One helper per document, not per page.** Measured: a process pays
    /// ~0.03s to launch and Vision ~0.20s to answer its first request (same
    /// page, same process: 1.400s then 1.238s, 1.211s, 1.157s). Per page that
    /// 0.23s is 19% of a typical page and would hand back a fifth of what this
    /// change is for; per document it is 0.23s against minutes. The bound on
    /// how many run at once needs no pool of its own — `start()` already runs
    /// at most `Prefs.concurrency` files at a time and each holds at most one
    /// helper, so the process count is the setting, by construction.
    static let helperName = "visionocr-recognise"

    /// How long the app will wait without a page arriving before deciding the
    /// helper has stopped responding.
    ///
    /// **A bound on silence, not on the run.** A 600-page book is legitimately
    /// many minutes of work, so a total deadline long enough to be safe would
    /// never fire on anything. Generous — a single 200-megapixel page can take
    /// tens of seconds and being wrong here costs the whole document a second
    /// pass in-process, while being slow costs only a wedged helper's timeout,
    /// which cancelling already interrupts.
    static let helperStallSeconds = 300.0

    /// Whether a batch is worth giving helper processes at all.
    ///
    /// A helper buys **process-level** parallelism and nothing else — Vision
    /// gives 1.08x for six threads in one process, so overlapping is the entire
    /// return. One file, or a concurrency of one, has nothing to overlap with,
    /// and the helper would only pay Vision's ~0.20s start-up a second time.
    ///
    /// Its own function so it can be checked without running a batch: as a
    /// condition inlined in `start()` it was reachable only by driving the whole
    /// model, which is how a decision ends up with no check on it at all.
    static func helperIsWorthIt(concurrency: Int, files: Int) -> Bool {
        concurrency > 1 && files > 1
    }

    /// Where the helper is, or nil if this build has none.
    ///
    /// Deliberately **not** `Runner.locateTool`. That exists for `jbig2` and
    /// `qpdf`, which are other people's programs that a user may have installed
    /// anywhere; this one is ours and ships inside the bundle, so scanning
    /// Homebrew's prefixes for it would be looking where it cannot be, and the
    /// login-shell fallback would spend ~85 ms proving it.
    ///
    /// The environment override is how the suite and `Tools/fault-inject.sh`
    /// reach a helper that is not inside an app bundle — and how they point at
    /// one that is missing or broken, which is the only way the fallback path
    /// below ever executes (CONTRIBUTING 4c).
    static func helperPath() -> String? {
        if let override = ProcessInfo.processInfo.environment["VISIONOCR_HELPER"] {
            return Runner.isRunnable(override) ? override : nil
        }
        return Runner.bundledTool(helperName)
    }

    /// The recognition settings, as the helper's arguments.
    ///
    /// **Total, and one flag per setting even when it is off.** The forty checks
    /// this project used to keep on a CLI's argument list were protecting one
    /// property — that a setting the panel offers actually reaches the engine,
    /// the failure `ocrAllPages` is named for — and an encoding that omits its
    /// defaults cannot be enumerated for that. Every value is written, so
    /// "changing this field changes the arguments" is checkable for all of them;
    /// see "every recognition setting reaches the helper" in the suite.
    ///
    /// The two list fields travel **raw**, exactly as the user typed them, and
    /// are split by `Runner.splitList` on the far side — the same call
    /// `makeRequest` makes here. Splitting before the handover and re-joining
    /// after would be a second parser to keep in step with the first.
    ///
    /// `confidence` is here even though it is not a property of the request: it
    /// is applied to the observations by `recognise`, so a helper that did not
    /// receive it would hand back text this app had been told to discard.
    static func helperArguments(_ settings: Prefs.Snapshot) -> [String] {
        [
            "--fast", settings.fast ? "1" : "0",
            "--language-correction", settings.languageCorrection ? "1" : "0",
            "--languages", settings.languages,
            "--custom-words", settings.customWords,
            "--min-text-height-on", settings.minTextHeightOn ? "1" : "0",
            "--min-text-height", "\(settings.minTextHeight)",
            "--confidence", "\(settings.confidence)",
        ]
    }

    /// The inverse, run by the helper on its own argument list.
    ///
    /// Strictly pairwise: every even element must be a `--flag` and every odd
    /// one its value. A value is therefore allowed to look like a flag, which
    /// matters because `--languages` and `--custom-words` carry whatever the
    /// user typed. Anything that does not parse returns nil rather than a
    /// half-filled settings object — the helper then exits non-zero and the app
    /// recognises in-process, which is the safe direction.
    ///
    /// Fields that are not recognition settings are filled with fixed values,
    /// never read from `UserDefaults`: the helper is a different process with
    /// its own (empty) preferences domain, and reading them there would make
    /// the result depend on something the caller cannot see.
    static func helperSettings(from arguments: [String]) -> Prefs.Snapshot? {
        guard arguments.count % 2 == 0 else { return nil }
        var values: [String: String] = [:]
        for pair in stride(from: 0, to: arguments.count, by: 2) {
            guard arguments[pair].hasPrefix("--") else { return nil }
            values[arguments[pair]] = arguments[pair + 1]
        }
        func flag(_ name: String) -> Bool? {
            switch values[name] {
            case "1": return true
            case "0": return false
            default: return nil
            }
        }
        func number(_ name: String) -> Double? { values[name].flatMap(Double.init) }

        guard let fast = flag("--fast"),
              let correction = flag("--language-correction"),
              let languages = values["--languages"],
              let words = values["--custom-words"],
              let minOn = flag("--min-text-height-on"),
              let minHeight = number("--min-text-height"),
              let confidence = number("--confidence")
        else { return nil }

        return Prefs.Snapshot(
            mode: .searchablePDF, textFormat: .text, besideOriginal: false,
            useJBIG2: false, photoDetail: .balanced, joinHyphenated: false,
            fast: fast, languages: languages, languageCorrection: correction,
            confidence: confidence, pdfDPIAuto: true, pdfDPI: 0, password: "",
            customWords: words, minTextHeightOn: minOn, minTextHeight: minHeight)
    }

    /// One page's worth of the helper's output, and the app's input.
    struct HelperPage: Codable {
        let observations: [SearchableWriter.Observation]
    }

    /// Why a helper run was abandoned. Every case falls back to in-process
    /// recognition, so these are diagnoses for the log rather than failures the
    /// user has to act on.
    enum HelperFailure: LocalizedError {
        case unusablePaths
        case couldNotStart(String)
        case stalled
        case exited(Int32, String)
        case incomplete(page: Int, of: Int)
        case unreadableResult(Int)

        var errorDescription: String? {
            switch self {
            case .unusablePaths:
                return "a page image's path contains a newline"
            case .couldNotStart(let why): return "it would not start: \(why)"
            case .stalled: return "it stopped responding"
            case .exited(let code, let detail):
                return "it exited with code \(code)"
                    + (detail.isEmpty ? "" : ": \(detail)")
            case .incomplete(let page, let total):
                return "it returned nothing for page \(page) of \(total)"
            case .unreadableResult(let page):
                return "its output for page \(page) could not be read"
            }
        }
    }

    /// Recognises page bitmaps in a helper process.
    ///
    /// Throws on anything unexpected so the caller can fall back; the one
    /// exception is `Failure.cancelled`, which means the user asked to stop and
    /// redoing the work in-process would be the opposite of what they asked.
    ///
    /// `stallSeconds` bounds *silence*, not the run. A 600-page book is
    /// legitimately many minutes of work, so a total deadline long enough to be
    /// safe would never fire; what a wedged helper actually looks like is no
    /// page landing for a long time.
    static func recogniseViaHelper(
        images: [URL],
        settings: Prefs.Snapshot,
        helper: String,
        stallSeconds: Double = helperStallSeconds,
        isCancelled: () -> Bool = { false },
        onPage: (Int, Int) -> Void = { _, _ in },
        register: (Process) -> Void = { _ in }
    ) throws -> [Int: [SearchableWriter.Observation]] {
        let total = images.count
        guard total > 0 else { return [:] }
        // The manifest is newline-separated and macOS permits a newline in a
        // file name. These are scratch paths this app chose, so this cannot
        // fire today — it is here so that if something ever hands the pipeline
        // a page image named by the user, the handover refuses rather than
        // silently recognising the wrong list of files.
        guard !images.contains(where: { $0.path.contains("\n") }) else {
            throw HelperFailure.unusablePaths
        }

        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("visionocr-recognise-\(UUID().uuidString)")
        let results = dir.appendingPathComponent("out")
        do {
            try fm.createDirectory(at: results, withIntermediateDirectories: true)
        } catch {
            throw HelperFailure.couldNotStart(error.localizedDescription)
        }
        defer { try? fm.removeItem(at: dir) }

        let manifest = dir.appendingPathComponent("pages.txt")
        do {
            try Data(images.map(\.path).joined(separator: "\n").utf8)
                .write(to: manifest, options: .atomic)
        } catch {
            throw HelperFailure.couldNotStart(error.localizedDescription)
        }

        // A file, not a pipe. Nothing in the loop below reads the child's
        // stderr, and a pipe nobody drains fills at 64 KB and blocks the writer
        // forever — the deadlock U18 and R2 are both shaped like. A file cannot
        // block, and it means a helper that failed can say why.
        let diagnostics = dir.appendingPathComponent("stderr.txt")
        fm.createFile(atPath: diagnostics.path, contents: nil)
        guard let errorSink = try? FileHandle(forWritingTo: diagnostics) else {
            throw HelperFailure.couldNotStart("no scratch space for its diagnostics")
        }
        defer { try? errorSink.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helper)
        process.arguments = ["--manifest", manifest.path, "--out", results.path]
            + helperArguments(settings)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorSink
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch {
            throw HelperFailure.couldNotStart(error.localizedDescription)
        }
        register(process)

        // Progress, and *only* progress. The helper writes the index of each
        // page as it finishes it; the observations themselves go to files. That
        // separation is deliberate: mac-ocr's page count came from counting
        // streamed lines, so a dropped or garbled line was a lost page, and
        // this is the one property that has to survive a helper writing
        // something unexpected to stdout. Here a garbled line moves a progress
        // bar and nothing else — what the app publishes is read from the files
        // and checked against the page count below.
        var lastMoved = DispatchTime.now()
        var pending: [UInt8] = []
        var done = 0
        let outcome = Runner.drain(pipe.fileHandleForReading.fileDescriptor,
                                   deadline: { lastMoved + stallSeconds },
                                   shouldStop: isCancelled) { chunk in
            pending.append(contentsOf: chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[..<newline], as: UTF8.self)
                pending.removeFirst(newline + 1)
                if let index = Int(line), index >= 0, index < total, index >= done {
                    done = index + 1
                    lastMoved = DispatchTime.now()
                    onPage(done, total)
                }
            }
            // Something that is not our progress, and never will be a line.
            // Dropped rather than accumulated: a helper spraying binary at
            // stdout must not be able to grow this without limit.
            if pending.count > 4096 { pending.removeAll(keepingCapacity: true) }
        }

        switch outcome {
        case .eof: break
        case .stopped:
            Runner.stop(process)
            throw Failure.cancelled
        case .timedOut:
            Runner.stop(process)
            throw HelperFailure.stalled
        case .failed:
            Runner.stop(process)
            throw HelperFailure.couldNotStart("its output could not be read")
        }

        if !Runner.wait(for: process, upTo: 10) {
            Runner.stop(process)
            throw HelperFailure.stalled
        }
        // Before the exit status, not after. Cancelling terminates the helper,
        // so it exits non-zero *because* the user asked it to — and reading
        // that as a broken helper would send the whole document round again
        // in-process, which is precisely what they asked to stop.
        if isCancelled() { throw Failure.cancelled }
        guard process.terminationStatus == 0 else {
            throw HelperFailure.exited(process.terminationStatus,
                                       lastLine(of: diagnostics))
        }

        // Invariant 1. A short dictionary here would compose as a document with
        // some pages silently untexted, pass the page-count check and publish;
        // `missingPages` is the net downstream, and this is the same refusal at
        // the point the gap is visible.
        var byPage: [Int: [SearchableWriter.Observation]] = [:]
        let decoder = JSONDecoder()
        for index in 0..<total {
            let file = results.appendingPathComponent("\(index).json")
            guard let data = try? Data(contentsOf: file) else {
                throw HelperFailure.incomplete(page: index + 1, of: total)
            }
            guard let page = try? decoder.decode(HelperPage.self, from: data) else {
                throw HelperFailure.unreadableResult(index + 1)
            }
            byPage[index + 1] = page.observations
        }
        onPage(total, total)
        return byPage
    }

    /// The last thing the helper said before it died, for the log.
    private static func lastLine(of file: URL) -> String {
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return "" }
        return String(decoding: data.suffix(400), as: UTF8.self)
            .split(separator: "\n").last.map(String.init) ?? ""
    }
}
