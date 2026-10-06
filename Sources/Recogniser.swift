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
        case unreadableRegions(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Cancelled."
            case .unreadableRegions(let what):
                return "The columns of a pasted-up page could not be read (\(what))."
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
            // C29. A passed-through page has no bitmap, so it is not in the work
            // list — and it is recorded as an **empty** array rather than left
            // out, because absent and empty are opposite outcomes downstream:
            // `SearchableWriter.missingPages` is `byPage[$0] == nil` and
            // `Model.swift`'s call to it *refuses the whole document* over a gap
            // ("The recogniser returned nothing for page(s) 1 of 9"). An empty
            // entry says "visited, nothing to draw", which is exactly true of a
            // page that kept its own text layer.
            //
            // ⛔ This is why the work list is keyed EXPLICITLY from here on.
            // Position in `bitmaps` is still position in the document — `flatten`
            // returns one entry per page whether it rasterised it or not — but
            // position in the *image* list no longer is, and everything below
            // used to rely on the two being the same.
            var work: [(page: Int, image: URL)] = []
            for (index, page) in bitmaps.enumerated() {
                if let url = imageURL(of: page) {
                    work.append((page: index + 1, image: url))
                } else {
                    byPage[index + 1] = []
                }
            }
            if useHelper, let helper = helperPath() {
                do {
                    let recognised = try recogniseViaHelper(
                        images: work.map(\.image), settings: settings,
                        helper: helper, isCancelled: isCancelled, onPage: onPage,
                        register: register)
                    // Keyed back onto page numbers. `if let` and not `?? []`: the
                    // helper promises an entry for every image it was given and
                    // throws otherwise, so a missing one is a broken promise, and
                    // filling it with `[]` would hide a page from `missingPages`
                    // — the one net that catches a silently untexted page.
                    for (offset, item) in work.enumerated() {
                        if let obs = recognised[offset + 1] { byPage[item.page] = obs }
                    }
                    return byPage
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
            for item in work {
                if isCancelled() { throw Failure.cancelled }
                // The page number, not the position in the work list: a document
                // with a passthrough page in it would otherwise count "page 8 of
                // 9" while recognising page 9. ⚠️ The HELPER arm does not have this
                // property — `recogniseViaHelper` counts against the image list it
                // was handed, which is shorter — so the two arms' progress strings
                // disagree on a mixed document. Cosmetic, and recorded rather than
                // fixed: `BUGS.md` C29 `#### (A) SHIPPED` names it.
                onPage(item.page - 1, total)
                guard let read = try recognisePage(at: item.image, settings: settings,
                                                   isCancelled: isCancelled) else {
                    throw Failure.unreadablePage(item.page)
                }
                byPage[item.page] = read
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
            // A13.4. This was `else { continue }`, alone among the three places
            // that ask a document for a page — the two below throw. `missingPages`
            // catches the gap downstream, so nothing was published untexted, but
            // the refusal it raises says "the recogniser returned nothing for
            // page N", which names the recogniser for a page PDFKit would not
            // hand over. Same refusal, at the point that knows the cause.
            guard let page = doc.page(at: index) else {
                throw Failure.unreadablePage(index + 1)
            }
            guard let image = render(page, settings: settings) else {
                throw Failure.unreadablePage(index + 1)
            }
            byPage[index + 1] = fittedToGutters(try recognisePage(image, settings: settings,
                                                                  isCancelled: isCancelled),
                                                of: image, isCancelled: isCancelled)
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
    /// *recognition* call the searchable pipeline uses — `recognise(_:settings:)` — but
    /// **not over the same pixels**, and this sentence said "the same path" until
    /// 2026-08-23. Here every page goes through `render(_:settings:)`, a plain render of
    /// the source page. The searchable pipeline rebuilds the page first and recognises
    /// `Flattener.flatten`'s bitmaps whenever `OCRModel.willRebuild` says so, and on a
    /// document with a crop box the two are not even the same geometry — `render`
    /// rasterises `Flattener.displayBox`, `flatten` `Flattener.fullBox`. So this is a *second*
    /// recognition of a *different* image, not a copy of the one the product made:
    /// measured on `BUGS.md` C30's document, where page 5's published text layer holds a
    /// line no run of this path returns. `Tools/make-observations.swift` is the instrument
    /// built on it and carries the same correction.
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
                                   observations: withoutStrayScript(try recognise(image, settings: settings))))
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
                               observations: withoutStrayScript(
                                   try recognise(image, orientation: orientation, settings: settings))))
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
        // A2.2. The loop above checks `isCancelled` at the top of each *page*, so a
        // cancel arriving during the last page finished it and fell straight through
        // to this write — which goes to the **user's destination**, replacing the
        // previous run's output with the output of a run they stopped. Measured: a
        // 13,006-byte previous .txt overwritten by a cancelled run's text.
        //
        // Invariant 2 says never write directly to the user's destination, and this
        // is the route that does. `.atomic` makes the replacement indivisible; it
        // does not make it wanted. So the last thing before writing is to ask again.
        //
        // Deliberately here and not only in `Model`: `extract` is what touches the
        // file, and a caller that forgot to re-check would be back to publishing a
        // cancelled run. The searchable route has this same guard immediately before
        // its own publish, seven sites' worth (R14, A2.2's other half).
        if isCancelled() { throw Failure.cancelled }
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
    ///
    /// **`nil` for a page `flatten` passed through** (C29): it wrote no bitmap,
    /// because the page kept its own text and there is nothing to recognise. The
    /// optional is the whole reason `recogniseDocument` keys its work list by page
    /// number — this function used to be total, and every caller read position in
    /// the image list as position in the document.
    static func imageURL(of page: Flattener.RebuiltPage) -> URL? {
        switch page.content {
        case .bilevel(let url), .jpeg(let url): return url
        case .passthrough: return nil
        }
    }

    /// The bitmap `flatten` wrote for a page, decoded, or nil when it wrote none.
    static func loadImage(_ page: Flattener.RebuiltPage) -> CGImage? {
        imageURL(of: page).flatMap { loadImage(at: $0) }
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
        // Vision's normalised space is the oriented image, whose sides swap here.
        let sideways = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)

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
                confidence: Double(observation.confidence),
                quarterTurns: quarterTurns(from: observation.topLeft, to: observation.topRight,
                                           width: sideways ? image.height : image.width,
                                           height: sideways ? image.width : image.height)))
        }
        return out
    }

    /// Which way a line reads, from its quad's top edge (`topLeft` to `topRight`, in
    /// Vision's normalised bottom-left space over an image `width` x `height` pixels):
    /// the nearest quarter turn anticlockwise, nil for upright.
    ///
    /// The axis-aligned `boundingBox` cannot say this. A line printed up the page
    /// gets a tall, narrow box, and the writer fitted its string across that box at
    /// about 1.5 pt (C36). The quad's corners follow the text: on Koh 2008 p127, a
    /// `/Rotate 270` table, every line's top edge runs straight up the page.
    static func quarterTurns(from topLeft: CGPoint, to topRight: CGPoint,
                             width: Int, height: Int) -> Int? {
        let dx = Double(topRight.x - topLeft.x) * Double(width)
        let dy = Double(topRight.y - topLeft.y) * Double(height)
        guard dx.isFinite, dy.isFinite, dx != 0 || dy != 0 else { return nil }
        if abs(dx) >= abs(dy) { return dx > 0 ? nil : 2 }
        return dy > 0 ? 1 : 3
    }

    // MARK: - Recognising a page again in bands (C30)

    /// One page's text as the searchable pipeline recognises it: the whole page,
    /// then — only when that leaves inked rows with no word over them, or a box
    /// shaped like two fused lines — the page again in overlapping horizontal
    /// bands, merged in.
    ///
    /// **Why.** One request over a whole scanned page skips blocks of clean body
    /// type: on `BUGS.md` C30's document 15–43% of each page's ink had no word box,
    /// and the same pixels cut into eight bands recovered almost all of it
    /// (`C30-TILES-2026-08-25.tsv`: 2,080 words to 3,577, void share 21–45% down
    /// to at most 6.8%). That experiment's bands did not overlap, so it cut lines
    /// at their edges; these do, and the merge keeps a band's line only where the
    /// page has no line.
    ///
    /// A page the whole-page request reads fully, with no box shaped like two
    /// fused lines (`hasFusedLine`), costs one ink scan and nothing more, and its observations come back exactly as `recognise` returned them.
    /// A page with a picture on it also starts the bands, and pays their time.
    /// The trigger is asked of the whole width and of four vertical strips
    /// (`voidStrips`), so a missed block standing *beside* recognised text on the
    /// same rows starts them too (C33: `Bird` p3 lost 14 lines of its right-hand
    /// column that way while the left column covered every row).
    ///
    /// Then each stretch of a line the merge reports unread is recognised on its
    /// own, and the last merge is run again with those reads (C33; `mergeBands`,
    /// "Unread stretches").
    ///
    /// `isCancelled` is asked between bands and between stretches, and a cancelled
    /// page returns what it has merged so far; the caller's own check between pages
    /// then throws.
    ///
    /// **Not in fast mode.** The fast recogniser reports 0.5 on every line
    /// (measured on C30's page 1: 61 of 61 whole-page lines, 88 of 89 band lines,
    /// the other 0.3), so the merge's full-confidence gate would admit nothing and
    /// the bands would be time spent for no text.
    ///
    /// Last, a line read straight across a column gutter is read again as its two
    /// halves (`splitAtGutter`, C34). A page with a candidate for that pays a
    /// further pass over its pixels for the ink level, and two small requests a line.
    /// The boxes reaching into a gutter are brought in to their ink by the callers,
    /// once a page's readings are merged (`fittedToGutters`, C52).
    static func recognisePage(_ image: CGImage, settings: Prefs.Snapshot,
                              isCancelled: () -> Bool = { false })
        throws -> [SearchableWriter.Observation] {
        withoutStrayScript(
            splitAtGutter(try recogniseInBands(image, settings: settings, isCancelled: isCancelled),
                          of: image, settings: settings, isCancelled: isCancelled))
    }

    // MARK: - Arabic and Hebrew misread on a Latin page (C46)

    /// Whether `s` is a Hebrew or Arabic letter or digit: the scripts PDFKit lays out
    /// right to left.
    static func isRightToLeft(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: return true
        default: return false
        }
    }

    /// `observations` without the lines Vision's language detection read as Arabic or
    /// Hebrew on a page that is Latin (C46).
    ///
    /// With no language named, Vision detects one per line, and a smudge or a cartoon
    /// signature on an English page comes back as Arabic: `___ 2.pdf` p1 carried
    /// `م٢٨٣٩ ٢٨ tcopnم ٦٦T` at 0.3 in a 4 pt gap between two lines already read.
    /// The cost is not only noise. With a right-to-left run anywhere on the page,
    /// PDFKit's `selection(from:to:)` exits SIGTRAP in
    /// `convertRTLTextRangeIndexToStringRangeIndex` on a click at the right end of
    /// another line (x≈738, `1-2下RIEKAAR`), and Preview makes the same call.
    ///
    /// A page is Latin unless a quarter of its letters, and a line's worth
    /// (`strayScriptLetters`), are right to left: a figure page's eight-letter ghost
    /// beside `Fig. 3` does not make it Arabic. On a Latin page, a line with any
    /// right-to-left letter goes when Vision was unsure of it (below full confidence)
    /// or when its own letters are not mostly right to left, the mixed strings no
    /// script is written in; the other lines lose any bidirectional control character
    /// (Vision wrote U+202B into the corpus). A confident line that is Arabic or Hebrew
    /// stays: a quotation on an English page is text. Arabic-Indic digits alone are
    /// not one: `Sewell` p325's microfilm target read its `1.0` as `١٠`. Dropped, not
    /// reported, like the confidence threshold's lines: a Latin line with a Hebrew
    /// word in it goes too, because Vision writes Hebrew only when it read the whole
    /// line as Hebrew.
    /// Rejected: naming the user's languages for them, which would stop a French or
    /// German page being detected as what it is; and filtering in the writer, where
    /// the lines could be reported, because `finerReading` would by then have put an
    /// Arabic reading over a line the coarse copy had read in English.
    static func withoutStrayScript(_ observations: [SearchableWriter.Observation])
        -> [SearchableWriter.Observation] {
        func letters(_ o: SearchableWriter.Observation) -> (all: Int, rtl: Int, words: Bool) {
            var all = 0, rtl = 0, words = false
            for s in o.text.unicodeScalars where s.properties.isAlphabetic || s.properties.numericType != nil {
                all += 1
                if isRightToLeft(s) { rtl += 1; words = words || s.properties.isAlphabetic }
            }
            return (all, rtl, words)
        }
        let counts = observations.map(letters)
        let rtl = counts.reduce(0) { $0 + $1.rtl }
        if rtl >= strayScriptLetters, rtl * 4 >= counts.reduce(0, { $0 + $1.all }) { return observations }
        return zip(observations, counts).compactMap { o, n in
            guard n.rtl == 0 else { return o.confidence >= 1 && n.words && n.rtl * 2 > n.all ? o : nil }
            guard o.text.unicodeScalars.contains(where: isBidiControl) else { return o }
            return SearchableWriter.with(o, String(String.UnicodeScalarView(
                o.text.unicodeScalars.filter { !isBidiControl($0) })))
        }
    }

    /// Right-to-left letters a page needs before it can be read as Arabic or Hebrew.
    static let strayScriptLetters = 40

    /// The marks and embeddings that turn on PDFKit's right-to-left layout.
    static func isBidiControl(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069: return true
        default: return false
        }
    }

    /// Whether most of a line's letters are Arabic or Hebrew, so that its row reads from
    /// the right (C53: `mergeBands` orders the fragments of a row by it).
    static func readsRightToLeft(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        return 2 * letters.filter { isRightToLeft($0) }.count > letters.count
    }

    // MARK: - A page pasted up from strips (C39)

    /// What `Flattener.flatten` names the file of a paste-up's regions, after the
    /// page's stem: `p00001.png` has its regions in `p00001.regions.json`.
    static let regionsSuffix = ".regions.json"

    /// What `Flattener.flatten` names the copy of a 1-bit page at its images'
    /// resolution, beside the bitmap it rebuilt at its type's (C39):
    /// `p00001.png` has it in `p00001.coarse.png`.
    static let coarseSuffix = ".coarse.png"

    /// What `Flattener.flatten` names the grey render a 1-bit page was thresholded
    /// from, on the grid it is read at (C50): `p00001.png` has it in `p00001.grey.jpg`.
    static let greySuffix = ".grey.jpg"

    /// What `Flattener.flatten` names a 1-bit page as Otsu's threshold drew it, when
    /// the published bitmap has had its strokes' fringe lifted (C56): the recogniser
    /// reads this one, so the thinner type changes what is seen and not what is read.
    /// `p00001.png` has it in `p00001.read.png`.
    static let readSuffix = ".read.png"

    /// The page bitmap the recogniser reads in place of the published one at `image`.
    static func readingImage(besides image: URL) -> URL {
        let read = image.deletingPathExtension().appendingPathExtension("read.png")
        return FileManager.default.fileExists(atPath: read.path) ? read : image
    }

    /// `lines`, with the text of each line that `grey`, a reading of the page's grey
    /// render, reads as the same line (`finerReading`) and with more dictionary words
    /// (`dictionaryWords`). The 1-bit page keeps its lines, boxes and order; the grey
    /// render reads strokes the threshold broke. Taken for every line `finerReading`
    /// matched, the grey reading lost 30 words on a 1928 typescript's 1,246 lines, and
    /// Vision's confidence could not choose (it is the same on both readings). Chosen
    /// by dictionary, over 28 sampled corpus pages and 4 named ones no page lost a
    /// dictionary word, and published, the 1928 page gained 74, Doermann p7 15, Ries p54
    /// 11 and NYSE 1956 p110 11.
    ///
    /// Two more for tables, where there are no words to count (`Xin Qu_2018` p24, C50).
    /// A line's numbers may change only from garbled to clean (`isGarbledNumber`):
    /// `ถ.120` and `n.490` take the grey `0.120` and `0.490`, and `1s` `is`, while every
    /// clean number stays, in order, so `$400,000` never becomes `$100,000` (the finer
    /// reading's misread that `finerReading` refuses), nor a 1928 typescript's `summer
    /// of 1921, b1` the grey `summer of 1911, bul`. And a
    /// line over `fusedHeight` median line heights tall that holds two or more grey
    /// lines stacked one under the other is two cells read as one: `- 1228` over the
    /// grey `0.081` and `-1.228`, which it is replaced by, each on its own box.
    static func greyReading(of lines: [SearchableWriter.Observation],
                            from grey: [SearchableWriter.Observation],
                            aspect: Double) -> [SearchableWriter.Observation] {
        let matched = finerReading(of: lines, from: grey, aspect: aspect)
        let renumbered = finerReading(of: lines, from: grey, aspect: aspect, keepingNumbers: false)
        let heights = lines.map(\.boundingBox.height).filter { $0.isFinite && $0 > 0 }.sorted()
        let median = heights.isEmpty ? 1.0 / 60 : heights[heights.count / 2]
        return lines.indices.flatMap { i -> [SearchableWriter.Observation] in
            let line = lines[i]
            if let cells = stacked(grey, in: i, of: lines, lineHeight: median, aspect: aspect) {
                return cells
            }
            let mine = dictionaryWords(in: line.text)
            if dictionaryWords(in: matched[i].text) > mine { return [matched[i]] }
            let candidate = renumbered[i], theirs = dictionaryWords(in: candidate.text)
            if numbers(in: candidate.text) == numbers(in: line.text) { return [line] }
            // Word by word: a garbled word may become a clean number, or a dictionary word
            // where each digit touches a lower-case letter (`1s`, `t1m`, `st1ll`, not a
            // label's `A1`), and every other word keeps its numbers.
            let (was, now) = (line.text.split(whereSeparator: \.isWhitespace),
                              candidate.text.split(whereSeparator: \.isWhitespace))
            guard theirs >= mine, was.count == now.count, was.contains(where: isGarbledNumber),
                  !now.contains(where: isGarbledNumber) else { return [line] }
            let fair = zip(was, now).allSatisfy { w, n in
                guard isGarbledNumber(w) else { return numbers(in: String(w)) == numbers(in: String(n)) }
                if n.contains(where: \.isNumber) { return true }
                let c = Array(w)
                return c.indices.allSatisfy { k in
                    !c[k].isNumber || (k > 0 && c[k - 1].isLowercase)
                        || (k + 1 < c.count && c[k + 1].isLowercase)
                } && n.split { !$0.isLetter }.allSatisfy { $0.count < 2 || isWord($0.lowercased()) }
            }
            return [fair ? candidate : line]
        }
    }

    /// Of the median line height, how tall a line must be for `greyReading` to look for
    /// two cells in it: `linesOnlyFiner`'s fused shape, without its width.
    static let fusedHeight = 1.4

    /// The grey lines `lines[i]` holds when it is two or more cells read as one
    /// (`greyReading`): upright, over `fusedHeight` line heights tall, holding two or
    /// more upright grey lines, each centred in its box and wholly inside it give or take
    /// a line height's fifth, meeting no other line of `lines`, and stacked with no two
    /// sharing more than 0.4 of the shorter's height (adjacent rows' grey boxes share a
    /// third on Xin Qu). Together they must have at least its letters and digits, its
    /// dictionary words, its numbers' digits in order and a `likeness` of a half, so
    /// nothing it read is lost and a tall heading read the same way twice is not split.
    /// Each keeps its own box and text and takes the line's confidence and region.
    /// `aspect` is the page's height over its width.
    static func stacked(_ grey: [SearchableWriter.Observation], in i: Int,
                        of lines: [SearchableWriter.Observation],
                        lineHeight: Double, aspect: Double) -> [SearchableWriter.Observation]? {
        let line = lines[i], a = line.boundingBox
        guard (line.quarterTurns ?? 0) % 4 == 0, a.height > fusedHeight * lineHeight else { return nil }
        let slack = lineHeight / 5, across = slack * aspect
        // Boxes of adjacent rows touch (`-1.228`'s grey box reaches 0.08% of the page into
        // `0.540`'s), so meeting is sharing a quarter of the shorter one's height.
        func meets(_ p: SearchableWriter.BoundingBox, _ q: SearchableWriter.BoundingBox) -> Bool {
            min(p.x + p.width, q.x + q.width) > max(p.x, q.x)
                && min(p.y + p.height, q.y + q.height) - max(p.y, q.y) > 0.25 * min(p.height, q.height)
        }
        let inside = grey.filter { g in
            let b = g.boundingBox
            return (g.quarterTurns ?? 0) % 4 == 0
                && !g.text.trimmingCharacters(in: .whitespaces).isEmpty
                && b.x >= a.x - across && b.x + b.width <= a.x + a.width + across
                && b.y >= a.y - slack && b.y + b.height <= a.y + a.height + slack
                && (a.x...(a.x + a.width)).contains(b.x + b.width / 2)
                && (a.y...(a.y + a.height)).contains(b.y + b.height / 2)
                && !lines.indices.contains { $0 != i && meets(lines[$0].boundingBox, b) }
        }.sorted { $0.boundingBox.y < $1.boundingBox.y }
        guard inside.count >= 2,
              zip(inside, inside.dropFirst()).allSatisfy({ p, q in
                  let shared = p.boundingBox.y + p.boundingBox.height - q.boundingBox.y
                  return shared <= 0.4 * min(p.boundingBox.height, q.boundingBox.height)
              })
        else { return nil }
        func letters(_ t: String) -> Int { t.filter { $0.isLetter || $0.isNumber }.count }
        let text = inside.map(\.text).joined(separator: " ")
        func digits(_ t: String) -> [String] { numbers(in: t).map { $0.filter(\.isNumber) } }
        var rest = digits(text)[...]
        let kept = digits(line.text).allSatisfy { n in
            guard let k = rest.firstIndex(of: n) else { return false }
            rest = rest[(k + 1)...]
            return true
        }
        guard kept, letters(text) >= letters(line.text), likeness(line.text, text) >= 0.5,
              dictionaryWords(in: text) >= dictionaryWords(in: line.text) else { return nil }
        return inside.map { g in
            var out = SearchableWriter.Observation(boundingBox: g.boundingBox, text: g.text,
                                                   confidence: line.confidence,
                                                   quarterTurns: line.quarterTurns)
            out.region = line.region
            return out
        }
    }

    /// Whether `word` holds a digit and is not a number: after the signs, brackets,
    /// quotes and currency before it and the brackets, stars, percent sign and
    /// punctuation after it, none of `numberShapes`. `ถ.120`, `n.490`, `0.20X1`,
    /// `1.29(1*`, `unt1l` and `A1` are; `-1.228`, `$400,000`, `(.023)`, `3,14`, `2nd`,
    /// `1990s`, `1990-91`, `3:15`, `12%` and `1967,` are not, nor is any word holding a
    /// digit other than 0-9 (`10³`, `½`, Arabic-Indic), which this cannot judge.
    static func isGarbledNumber(_ word: Substring) -> Bool {
        guard word.contains(where: \.isNumber),
              !word.contains(where: { $0.isNumber && !("0"..."9").contains($0) }) else { return false }
        let leading = Set("+-−–($£€[\"'“‘"), trailing = Set(")*%,.;:†‡]?!\"'”’")
        var core = word
        while let c = core.first, leading.contains(c) { core = core.dropFirst() }
        while let c = core.last, trailing.contains(c) { core = core.dropLast() }
        return !numberShapes.contains { core.range(of: $0, options: .regularExpression) != nil }
    }

    /// What `isGarbledNumber` takes for a number: grouped in threes or not, with a point;
    /// a point first; a decimal comma; an ordinal or a decade; a range or date; a time
    /// (not `2:900`, a point misread on Xin Qu).
    static let numberShapes = [#"^([0-9]{1,3}(,[0-9]{3})+|[0-9]+)(\.[0-9]+)?$"#, #"^\.[0-9]+$"#,
                               #"^[0-9]+,[0-9]{1,2}$"#, #"^[0-9]+(st|nd|rd|th|d)$"#, #"^[0-9]{2,}s$"#,
                               #"^[0-9]+([-–—/][0-9]+)+$"#, #"^[0-9]{1,2}:[0-9]{2}$"#]

    /// How many of `text`'s runs of two or more letters are words of the system's word
    /// list, `/usr/share/dict/words` (web2 on macOS), in any case, or one of its words
    /// with a plural or verb ending: web2 has `firm` and not `firms`, and a reading of
    /// "firms" must not lose to one of "firm". Zero on every text when the list is
    /// absent, so `greyReading` then changes nothing.
    static func dictionaryWords(in text: String) -> Int {
        text.split { !$0.isLetter }.filter { $0.count >= 2 && isWord($0.lowercased()) }.count
    }

    private static func isWord(_ word: String) -> Bool {
        if wordList.contains(word) { return true }
        for (ending, stems) in [("ies", ["y"]), ("es", [""]), ("s", [""]), ("ed", ["", "e"]),
                                ("ing", ["", "e"])]
        where word.count > ending.count + 2 && word.hasSuffix(ending) {
            let root = String(word.dropLast(ending.count))
            if stems.contains(where: { wordList.contains(root + $0) }) { return true }
        }
        return false
    }

    private static let wordList: Set<String> = {
        guard let list = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8)
        else { return [] }
        return Set(list.split(separator: "\n").map { $0.lowercased() })
    }()

    /// The bitmap to recognise for the page `flatten` wrote at `image`: the copy at its
    /// images' resolution when there is one, else the page itself.
    ///
    /// A layered scan's 1-bit page is published at its type's resolution, twice its
    /// images' on ProQuest's pages, and read where it always was. Read at the type's,
    /// the 35 corpus documents this reaches read 4,876 more dictionary words (web2) and
    /// lost 14 printed lines on 6 pages, found before and not after by PDFKit's search
    /// (`_1973_Committee Against Racism` p4: 6). So the copy gives the page its lines,
    /// and the page itself only their words (`recognisePage(at:)`, `BUGS.md` C39).
    static func recognitionImage(besides image: URL) -> URL {
        let coarse = image.deletingPathExtension().appendingPathExtension("coarse.png")
        return FileManager.default.fileExists(atPath: coarse.path)
            ? coarse : readingImage(besides: image)
    }

    /// The page `flatten` wrote at `image`, recognised as the app publishes it: strip by
    /// strip when it wrote regions beside it, else whole. Nil when the bitmap to read will
    /// not load, which each caller reports as its own unreadable page.
    ///
    /// A page with a copy at its images' resolution (`recognitionImage`) is read twice
    /// (C39): the copy gives the lines, as it did alone, and the page at its type's
    /// resolution gives the words of every line it read the same way
    /// (`finerReading`). Reading the page alone gained the words but lost lines and
    /// joined columns (on WSJ 1969, lines holding two columns' text 9 -> 46); taking
    /// its text only line for line keeps the copy's lines, boxes and order. When the
    /// second reading fails, the copy's stands: it is what the page published before.
    /// A grey render written beside it (`greySuffix`) is read last, for words, garbled
    /// numbers and cells read as one (`greyReading`, C50). The boxes reaching into a column gutter are brought in to their ink last, on the
    /// merged lines (`fittedToGutters`): fitted reading by reading, a box moved in one
    /// and not the other could fall outside `finerReading`'s match.
    static func recognisePage(at image: URL, settings: Prefs.Snapshot,
                              isCancelled: () -> Bool = { false })
        throws -> [SearchableWriter.Observation]? {
        let coarse = recognitionImage(besides: image)
        let pageURL = readingImage(besides: image)
        guard let first = loadImage(at: coarse) else { return nil }
        let regions = try regions(besides: image)
        func read(_ bitmap: CGImage) throws -> [SearchableWriter.Observation] {
            if let regions {
                // Again over the whole page: each strip was judged Latin on its own.
                return withoutStrayScript(try recognisePage(bitmap, regions: regions,
                                                            settings: settings,
                                                            isCancelled: isCancelled))
            }
            return try recognisePage(bitmap, settings: settings, isCancelled: isCancelled)
        }
        let lines = try read(first)
        var merged = lines, fitOn = first
        if coarse != pageURL, !isCancelled(), let page = loadImage(at: pageURL), page.width > 0,
           let finer = try? read(page), !isCancelled() {
            // Each reading was judged on its own letters; the page is judged on what it keeps.
            merged = withoutStrayScript(
                finerReading(of: lines, from: finer, aspect: Double(page.height) / Double(page.width))
                    + linesOnlyFiner(lines, finer, aspect: Double(page.height) / Double(page.width)))
            fitOn = page
        }
        // C50. The grey render the copy was thresholded from, on the copy's own grid.
        let greyURL = image.deletingPathExtension().appendingPathExtension("grey.jpg")
        if !isCancelled(), let grey = loadImage(at: greyURL),
           grey.width == first.width, grey.height == first.height,
           let greyLines = try? read(grey), !isCancelled() {
            merged = greyReading(of: merged, from: greyLines,
                                 aspect: Double(first.height) / Double(first.width))
        }
        return fittedToGutters(merged, of: fitOn, isCancelled: isCancelled)
    }

    /// The lines of `finer` that the copy's reading has nothing over: each at full
    /// confidence, with a box meeting none of `lines`' (C51). The copy is read for its
    /// lines, and on `Xin Qu_2018` p24 it skipped a whole column of a table the finer
    /// reading held cell by cell (`3.724`, `2.045`, `0.906`); the void test cannot see a
    /// column missed beside another column on the same rows. A line that touches no
    /// line of the copy cannot be two of its lines joined across a gutter, which is
    /// what `finerReading` refuses the finer reading for. A box of `hasFusedLine`'s
    /// shape, over 1.4 of the copy's median line height tall and eight wide, is left
    /// out: that is how Vision reads two lines as one garbled one, at full confidence.
    /// `aspect` is the page's height over its width, as `finerReading`'s.
    static func linesOnlyFiner(_ lines: [SearchableWriter.Observation],
                               _ finer: [SearchableWriter.Observation],
                               aspect: Double) -> [SearchableWriter.Observation] {
        func meets(_ a: SearchableWriter.BoundingBox, _ b: SearchableWriter.BoundingBox) -> Bool {
            min(a.x + a.width, b.x + b.width) > max(a.x, b.x)
                && min(a.y + a.height, b.y + b.height) > max(a.y, b.y)
        }
        let heights = lines.map(\.boundingBox.height).filter { $0.isFinite && $0 > 0 }.sorted()
        let line = heights.isEmpty ? 1.0 / 60 : heights[heights.count / 2]
        return finer.filter { f in
            f.confidence >= 1 && !f.text.trimmingCharacters(in: .whitespaces).isEmpty
                && !(f.boundingBox.height > 1.4 * line && f.boundingBox.width > 8 * line * aspect)
                && !lines.contains { meets($0.boundingBox, f.boundingBox) }
        }
    }

    /// `lines` with the text of each one that `finer`, a reading of the same page at a
    /// finer resolution, read as the same line. That is one finer line overlapping it by
    /// 0.6 of their union with both ends within 0.6 of its height, or, where there is
    /// none and the line is upright, two or more upright finer pieces inside its row that
    /// reach both of its ends, overlap nothing and leave no gap over `finerPieceGap`. Each
    /// finer line may serve one line only, of its own turn. The reading must have 0.9 to
    /// 1.15 times the line's letters, a `likeness` of a half, as many words and the same
    /// digits in its numbers, and must not undo a hyphen join the copy's reading makes.
    /// The line keeps its box, region and turn; only its text changes. With
    /// `keepingNumbers` false the digits may change, for `greyReading` to judge.
    ///
    /// Never two lines joined, and never a line split: where the copy cut a row in two
    /// and the finer reading did not, the row stays as `lines` cut it, because a finer
    /// line that reads two of them may be one read across a gutter (C39's parked band
    /// swap re-fused columns that way). Pieces are gathered only inside one line's own
    /// extent. Replayed over the saved readings of 495 of the corpus's 504 raised 1-bit
    /// pages, dictionary words (web2) go 77.46% -> 78.98% with all 33,532 lines kept, 372
    /// pages better and 14 worse (the worst in NYSE 1956's typescript, which the finer
    /// bitmap reads grainier); the finer reading alone reads 79.89% in 34,166 lines, cut
    /// differently and fused across columns (WSJ 1969: 9 -> 46 lines of two columns).
    /// `aspect` is the page's height over its width, to measure heights across it.
    static func finerReading(of lines: [SearchableWriter.Observation],
                             from finer: [SearchableWriter.Observation],
                             aspect: Double,
                             keepingNumbers: Bool = true) -> [SearchableWriter.Observation] {
        typealias Box = SearchableWriter.BoundingBox
        func turns(_ o: SearchableWriter.Observation) -> Int { (((o.quarterTurns ?? 0) % 4) + 4) % 4 }
        func reach(_ a: Box) -> Double { finerEdgeTolerance * a.height * aspect }
        /// A turned line (C36) runs down the page: its height is its box's width, and its
        /// ends are the box's top and bottom.
        func same(_ a: Box, _ b: Box, turned: Bool) -> Bool {
            let across = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
            let down = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
            guard across > 0, down > 0 else { return false }
            let shared = across * down
            let union = a.width * a.height + b.width * b.height - shared
            guard union > 0, shared / union >= finerOverlap else { return false }
            if turned {
                let along = finerEdgeTolerance * a.width / aspect
                return abs(a.y - b.y) <= along && abs((a.y + a.height) - (b.y + b.height)) <= along
            }
            return abs(a.x - b.x) <= reach(a) && abs((a.x + a.width) - (b.x + b.width)) <= reach(a)
        }
        /// The finer lines inside `a`'s row and ends, left to right, when there are two or
        /// more, none overlapping the next, and together they reach both of its ends.
        func pieces(of a: Box) -> [Int]? {
            let inside = finer.indices.filter { j in
                let b = finer[j].boundingBox
                return turns(finer[j]) == 0
                    && min(a.y + a.height, b.y + b.height) - max(a.y, b.y) >= finerOverlap * min(a.height, b.height)
                    && b.x >= a.x - reach(a) && b.x + b.width <= a.x + a.width + reach(a)
            }.sorted { finer[$0].boundingBox.x < finer[$1].boundingBox.x }
            // Each piece starts where the last one ended, give or take `reach`, and no more
            // than `finerPieceGap` line heights after it: a wider gap is a word the finer
            // reading missed (UN-OCred p27: `(and`, 1.4 line heights between its pieces).
            guard inside.count >= 2, let first = inside.first, let last = inside.last,
                  abs(finer[first].boundingBox.x - a.x) <= reach(a),
                  abs(finer[last].boundingBox.x + finer[last].boundingBox.width - (a.x + a.width)) <= reach(a),
                  zip(inside, inside.dropFirst()).allSatisfy({ p, q in
                      let end = finer[p].boundingBox.x + finer[p].boundingBox.width
                      return finer[q].boundingBox.x >= end - reach(a)
                          && finer[q].boundingBox.x - end <= finerPieceGap * a.height * aspect
                  })
            else { return nil }
            return inside
        }
        // Each line's finer reading, and whether it is pieces; how many lines claim each.
        var readings: [(found: [Int], pieces: Bool)] = []
        var claimed = [Int](repeating: 0, count: finer.count)
        for line in lines {
            let turn = turns(line)
            let whole = finer.indices.filter {
                turns(finer[$0]) == turn
                    && same(line.boundingBox, finer[$0].boundingBox, turned: turn % 2 == 1)
            }
            // Pieces are laid out along x, so only an upright line gathers them.
            let reading: (found: [Int], pieces: Bool) = whole.isEmpty && turn == 0
                ? (pieces(of: line.boundingBox).map { ($0, true) } ?? ([], false))
                : (whole, false)
            readings.append(reading)
            for j in reading.found { claimed[j] += 1 }
        }
        func letters(_ t: String) -> Int { t.filter { $0.isLetter || $0.isNumber }.count }
        // The hyphen joiner (`SearchableWriter.joiningHyphenatedWords`) joins a line ending in
        // a letter and a break hyphen to a next line starting with a lower-case letter, so a
        // reading may not lose either half where the copy had it: the copy's `$35.8 mall-`
        // joined `lion` and the page's `$35.8 mil` did not (WSJ 1969), and `compens.-`, or
        // `Tion` under `compensa-`, would undo a join too. One that finds a join is let
        // through: the page's `compensa-` joins `tion` where the copy read `compensa.`.
        func joinsAsHead(_ t: String) -> Bool {
            guard let last = t.last, SearchableWriter.breakHyphens.contains(last) else { return false }
            return t.dropLast().last?.isLetter ?? false
        }
        func joinsAsTail(_ t: String) -> Bool { t.first.map { $0.isLetter && $0.isLowercase } ?? false }
        // Only where the line may be a tail, by the joiner's own geometry: a head is above
        // it in its column (drawn baselines under `maximumJoinPitch` apart, sharing
        // `minimumColumnOverlap`), or it is one of the lines the joiner offers the page
        // before (`SearchableWriter.prepared`: the first `continuationCandidates` upright
        // lines in column order, near the top, which passes over a folio or running head),
        // or it is turned, which this does not place. Elsewhere a capital is let through,
        // because there the copy misread one (NYSE 1956: `tpon payanut` read `Upon payment`,
        // and 302 lines like it on the saved readings of 495 raised pages when the rule
        // applied everywhere).
        let joiner = SearchableWriter.self
        let opening: Set<Int> = {
            let upright = lines.indices.filter {
                turns(lines[$0]) == 0 && !lines[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.map { i -> SearchableWriter.Observation in
                var tagged = lines[i]
                tagged.region = i   // `columnOrdered` only reorders, so the tag comes back
                return tagged
            }.sorted { $0.boundingBox.y < $1.boundingBox.y }
            return Set(joiner.columnOrdered(upright, aspect: aspect)
                .prefix(joiner.continuationCandidates).compactMap(\.region))
        }()
        func baseline(_ a: Box) -> Double { a.y + (1 - Double(joiner.baselineFraction)) * a.height }
        func mayContinue(_ i: Int) -> Bool {
            guard turns(lines[i]) == 0 else { return true }
            let b = lines[i].boundingBox
            if opening.contains(i), b.y <= joiner.edgeOfPage { return true }
            return lines.indices.contains { k in
                guard k != i, turns(lines[k]) == 0, joinsAsHead(lines[k].text) else { return false }
                let a = lines[k].boundingBox
                let drop = baseline(b) - baseline(a)
                return drop > 0 && drop < Double(joiner.maximumJoinPitch) * a.height
                    && joiner.sharedWidthFraction(a, b) >= joiner.minimumColumnOverlap
            }
        }
        // Words, as runs of letters. A finer reading must have as many: fewer is a word it
        // missed (UN-OCred p27's `(and`, WSJ's `a` read `&`), more a word it broke up
        // (`poration` read `por atl on`). Where numbers may change, a word holding a digit
        // counts once, garbled or not: `ถ.120` is as many words as `0.120`, `1s` as `is`.
        func words(_ t: String) -> Int {
            guard !keepingNumbers else { return t.split { !$0.isLetter }.count }
            return t.split(whereSeparator: \.isWhitespace).map {
                $0.contains(where: \.isNumber) ? 1 : $0.split { !$0.isLetter }.count
            }.reduce(0, +)
        }
        return lines.indices.map { i in
            let line = lines[i]
            let (found, isPieces) = readings[i]
            guard !found.isEmpty, isPieces || found.count == 1,
                  found.allSatisfy({ claimed[$0] == 1 }) else { return line }
            let text = found.map { finer[$0].text }.joined(separator: " ")
            let (mine, theirs) = (Double(letters(line.text)), Double(letters(text)))
            guard mine > 0, theirs >= 0.9 * mine, theirs <= 1.15 * mine,
                  likeness(line.text, text) >= 0.5,
                  !joinsAsHead(line.text) || joinsAsHead(text),
                  !joinsAsTail(line.text) || joinsAsTail(text) || !mayContinue(i),
                  !keepingNumbers || numbers(in: text) == numbers(in: line.text),
                  words(text) == words(line.text) else { return line }
            var out = SearchableWriter.Observation(boundingBox: line.boundingBox, text: text,
                                                   confidence: line.confidence,
                                                   quarterTurns: line.quarterTurns)
            out.region = line.region
            return out
        }
    }

    /// The numbers in a reading, as digits with the points and commas between them. A
    /// finer reading may not change their digits, since a wrong number reads as a right
    /// one (WSJ 1969: `$400,000` read `$100,000`, `1967` read `1867`), nor split one
    /// (`700,000` read `700, 000`), nor read digits into a word (NYSE 1956's typescript:
    /// `unt1l paid 1n ful1`). Signs and symbols are not compared: there the finer reading
    /// mostly finds what the copy lost (`511 529` read `511-529`, `0.332` read `-0.332`).
    static func numbers(in t: String) -> [String] {
        var out: [String] = [], current = "", pending = ""
        for c in t {
            if c.isNumber {
                current += pending + String(c)
                pending = ""
            } else if c == "." || c == ",", !current.isEmpty, pending.isEmpty {
                pending = String(c)
            } else {
                if !current.isEmpty { out.append(current) }
                (current, pending) = ("", "")
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Of the union of two boxes, the least they must share to be one line (`finerReading`).
    static let finerOverlap = 0.6
    /// Of a line's height, how far apart two readings' ends may lie (`finerReading`).
    static let finerEdgeTolerance = 0.6
    /// In line heights, the widest gap between two finer pieces of one line (`finerReading`).
    /// On the 504 raised pages' readings 384 of 388 gathered lines keep under it; of the
    /// four above it, two had lost a word (`(and`, `&`).
    static let finerPieceGap = 1.25

    /// How alike two readings of one line are: the share of their pairs of adjacent
    /// characters in common (Dice), case folded and everything but letters and digits
    /// left out. The same line misread scores above a half (`protessor. ol.
    /// buglisa, who` against `professor of English, who re-`, 0.57); the line below it,
    /// with as many letters, well under (on C39's October 2, 1960 page a garbled `tainly
    /// esthe Second Cretion is far wiser, suc` against `earnest than are nine out of ten
    /// historical fictions.`).
    static func likeness(_ a: String, _ b: String) -> Double {
        func pairs(_ t: String) -> [String: Int] {
            let c = Array(t.lowercased().filter { $0.isLetter || $0.isNumber })
            var out: [String: Int] = [:]
            if c.count > 1 { for i in 0..<(c.count - 1) { out[String(c[i...i + 1]), default: 0] += 1 } }
            return out
        }
        let (x, y) = (pairs(a), pairs(b))
        let total = x.values.reduce(0, +) + y.values.reduce(0, +)
        guard total > 0 else { return 0 }
        let shared = x.reduce(0) { $0 + min($1.value, y[$1.key] ?? 0) }
        return 2 * Double(shared) / Double(total)
    }

    /// The regions `flatten` wrote beside the bitmap at `image`, or nil when it wrote
    /// none, which is every page but a paste-up. A file that is there and does not
    /// decode is an error, not a page without regions: the page would still read,
    /// but across its columns again, and nothing would say why.
    static func regions(besides image: URL) throws -> [SearchableWriter.BoundingBox]? {
        let url = image.deletingPathExtension().appendingPathExtension("regions.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url),
              let regions = try? JSONDecoder().decode([SearchableWriter.BoundingBox].self,
                                                      from: data)
        else { throw Failure.unreadableRegions(url.lastPathComponent) }
        return regions
    }

    /// `recognisePage` over a page pasted up from strips: each region on its own, then
    /// the page with every region painted out, for what lies between them (the
    /// masthead, a rule's caption). Every inked pixel is shown to Vision once.
    ///
    /// On `BUGS.md` C39's newspaper page at 300 DPI the whole-page route returned 70
    /// lines wider than a column (`in any sizable number of new they find no welcome
    /// in the per-`); strip by strip it returned 4, all one photograph's caption, and
    /// 18,591 characters against 17,125, in 17 s against 26 s.
    static func recognisePage(_ image: CGImage, regions: [SearchableWriter.BoundingBox],
                              settings: Prefs.Snapshot, isCancelled: () -> Bool = { false })
        throws -> [SearchableWriter.Observation] {
        let w = Double(image.width), h = Double(image.height)
        let full = CGRect(x: 0, y: 0, width: w, height: h)
        var pixels: [CGRect] = []
        var out: [SearchableWriter.Observation] = []
        let ordered = readingOrder(regions)
        let lanes = sideBySideLanes(ordered)
        for (index, region) in ordered.enumerated() {
            if isCancelled() { return out }
            let rect = CGRect(x: region.x * w, y: region.y * h,
                              width: region.width * w, height: region.height * h)
                .integral.intersection(full)
            guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { continue }
            pixels.append(rect)
            // `cropping(to:)` takes a top-left pixel rect, as the bands do.
            guard let crop = image.cropping(to: rect) else {
                throw Failure.unreadableRegions("a region of the page")
            }
            var local = settings
            local.minTextHeight = min(1, settings.minTextHeight * h / rect.height)
            for o in try recognisePage(crop, settings: local, isCancelled: isCancelled) {
                let b = o.boundingBox
                var left = (rect.minX + b.x * rect.width) / w
                var right = left + b.width * rect.width / w
                // Inside the strip's lane, so no run touches the next column's: the
                // box moves by at most the strips' overlap and the gap, never the text.
                // A box wholly outside it was read off the pixels the two strips share,
                // which the neighbour read as well, or off a sliver under `laneGap`
                // wide: on C39's page a lone `t` there joined two columns for PDFKit.
                guard min(right, lanes[index].right) > max(left, lanes[index].left) else {
                    continue
                }
                left = max(left, lanes[index].left)
                right = min(right, lanes[index].right)
                var placed = SearchableWriter.Observation(
                    boundingBox: .init(x: left, y: (rect.minY + b.y * rect.height) / h,
                                       width: right - left,
                                       height: b.height * rect.height / h),
                    text: o.text, confidence: o.confidence)
                placed.quarterTurns = o.quarterTurns
                placed.region = index
                out.append(placed)
            }
        }
        guard let rest = paintedOut(pixels, of: image) else {
            throw Failure.unreadableRegions("the page between its regions")
        }
        return try recognisePage(rest, settings: settings, isCancelled: isCancelled) + out
    }

    /// How far across the page each strip's lines may reach, left and right edge as
    /// fractions of the width: its own edges, except that where two strips stand side
    /// by side closer than `laneGap` (or overlapping, as C39's do by up to 4 pt) the
    /// boundary between them moves to the middle, `laneGap / 2` clear on each side.
    ///
    /// PDFKit groups runs into blocks by the paper between them. On C39's page one
    /// column's lines ended at 913.5 pt and the next column's began at 912.9, and
    /// PDFKit read the two as one block, five lines of each in turn, so a selection
    /// down either took half of the other. Strips stacked in one column are left as
    /// they are: reading on from one into the next is right.
    static func sideBySideLanes(_ regions: [SearchableWriter.BoundingBox])
        -> [(left: Double, right: Double)] {
        var lanes = regions.map { (left: $0.x, right: $0.x + $0.width) }
        for i in regions.indices {
            for j in regions.indices where j != i {
                let a = regions[i], b = regions[j]
                // Beside each other for a real share of their height, and overlapping by
                // no more than a strip edge: a headline over a column touches its top.
                guard min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
                        >= 0.25 * min(a.height, b.height),
                      a.x + a.width / 2 < b.x + b.width / 2 else { continue }
                let aRight = a.x + a.width, bLeft = b.x
                guard bLeft - aRight < laneGap, aRight - bLeft <= maximumLaneOverlap
                else { continue }
                let middle = (aRight + bLeft) / 2
                lanes[i].right = min(lanes[i].right, middle - laneGap / 2)
                lanes[j].left = max(lanes[j].left, middle + laneGap / 2)
            }
        }
        return lanes
    }

    /// Of the page's width: 2.1 pt on C39's 1,067 pt sheet. The writer's runs keep
    /// PDFKit's columns apart at 1 pt, measured on synthetic columns.
    static let laneGap = 0.002
    /// Of the page's width: the most two strips may overlap and still be neighbours in
    /// a row. C39's overlap by up to 4 pt, 0.0037.
    static let maximumLaneOverlap = 0.01

    /// A paste-up's strips in the order a reader takes them: down each column, the
    /// columns left to right. A strip belongs to the column whose first strip's left
    /// edge is within a quarter of the median strip's width of its own, so a strip
    /// set a few points in from its column's margin is not a column of its own.
    static func readingOrder(_ regions: [SearchableWriter.BoundingBox])
        -> [SearchableWriter.BoundingBox] {
        guard !regions.isEmpty else { return [] }
        let widths = regions.map(\.width).sorted()
        let tolerance = widths[widths.count / 2] / 4
        var columns: [(left: Double, members: [SearchableWriter.BoundingBox])] = []
        for r in regions.sorted(by: { ($0.x, $0.y) < ($1.x, $1.y) }) {
            if let last = columns.indices.last, r.x - columns[last].left <= tolerance {
                columns[last].members.append(r)
            } else {
                columns.append((r.x, [r]))
            }
        }
        return columns.flatMap { $0.members.sorted { ($0.y, $0.x) < ($1.y, $1.x) } }
    }

    /// `image` in grey with `rects` (top-left pixel rects) filled white.
    static func paintedOut(_ rects: [CGRect], of image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        context.setFillColor(gray: 1, alpha: 1)
        for r in rects {
            context.fill(CGRect(x: r.minX, y: CGFloat(h) - r.maxY, width: r.width, height: r.height))
        }
        return context.makeImage()
    }

    /// `recognisePage` before `splitAtGutter`: the whole page, the bands and the
    /// unread stretches. `recogniser` reads each image it is shown, the page and
    /// every crop of it; Vision, unless a check stands in for it.
    static func recogniseInBands(_ image: CGImage, settings: Prefs.Snapshot,
                                 isCancelled: () -> Bool = { false },
                                 recogniser: (CGImage, Prefs.Snapshot) throws -> [SearchableWriter.Observation]
                                     = { try Recogniser.recognise($0, settings: $1) })
        throws -> [SearchableWriter.Observation] {
        let whole = try recogniser(image, settings)
        let w = image.width, h = image.height
        let line = lineHeight(of: whole, pageHeight: h)
        guard !settings.fast, !bandPlan(height: h, lineHeight: line).isEmpty,
              let scan = inkScan(of: image) else { return whole }
        let inked = scan.rows
        // Two passes at most, the second with the seams moved half a stride, and
        // only while a void or a possibly fused box remains. Vision's reading of a
        // block depends on the window it is shown: on C30's page 1 one set of bands
        // read `members of the Department…` cleanly and another, whose bands were
        // 32 rows taller, returned a 215-px box of junk over it. (C33: the second
        // pass alone recovered `Leland` p2's footnotes, so a page with a tall
        // heading pays for both.)
        var merged = whole
        // The last merge's input, bands and unread stretches, for the stretches' pass.
        var last: (input: [SearchableWriter.Observation],
                   bands: [(observations: [SearchableWriter.Observation], top: Int, bottom: Int)],
                   stretches: [SearchableWriter.BoundingBox])?
        for pass in 0..<2 {
            guard wantsBands(inkedStrips: inked, observations: merged, pageWidth: w,
                             pageHeight: h, lineHeight: line)
            else { break }
            let plan = bandPlan(height: h, lineHeight: line, shifted: pass == 1)
            guard !plan.isEmpty else { break }
            var bands: [(observations: [SearchableWriter.Observation], top: Int, bottom: Int)] = []
            for band in plan {
                if isCancelled() { return merged }
                let bandHeight = band.bottom - band.top
                // `minimumTextHeight` is a fraction of the image handed to Vision, so a
                // band has to ask for the same absolute height the page did.
                var local = settings
                local.minTextHeight = min(1, settings.minTextHeight * Double(h) / Double(bandHeight))
                // `cropping(to:)` takes a TOP-left pixel rect: `Tools/score-text-voids`
                // group 11 measured it rather than reasoning about it. A band that will
                // not crop or whose request fails adds nothing, which leaves the page
                // exactly as the whole-page request read it — never worse than before
                // the bands existed, so it is not a reason to fail the document.
                guard let crop = image.cropping(to: CGRect(x: 0, y: band.top,
                                                           width: w, height: bandHeight)),
                      let read = try? recogniser(crop, local)
                else { continue }
                bands.append((read, band.top, band.bottom))
            }
            var stretches: [SearchableWriter.BoundingBox] = []
            let input = merged
            merged = mergeBands(whole: merged, bands: bands, pageHeight: h, lineHeight: line,
                                pageWidth: w,
                                hasInk: { hasInk(in: $0, of: image, level: scan.level) },
                                unread: { stretches.append($0) })
            last = (input, bands, stretches)
        }
        // Unread stretches (C33): the part of a line that no kept box reads, beside a
        // fragment the page kept. Each is recognised on its own (`stretchCrop`), and
        // the last merge is run again with those reads as further bands
        // (`stretchPiece`). On `Briefer` p3 this reads `1950. 86 pages…` beside
        // `United States Department of Labor…`, which lets the band's clean lines
        // replace a fused junk box.
        guard let last, !last.stretches.isEmpty else { return merged }
        let ink: (SearchableWriter.BoundingBox) -> Bool = { hasInk(in: $0, of: image, level: scan.level) }
        // Each stretch run out to the ends of its line's ink (C53, `reachingInk`).
        let kept = merged.map(\.boundingBox)
        let stretches = last.stretches.indices.map { k in
            reachingInk(last.stretches[k],
                        walls: kept + last.stretches.indices.filter { $0 != k }.map { last.stretches[$0] },
                        pageWidth: w, pageHeight: h, lineHeight: line, hasInk: ink)
        }
        typealias Piece = (observations: [SearchableWriter.Observation], top: Int, bottom: Int)
        func read(_ s: SearchableWriter.BoundingBox, padded: Bool, walls: [SearchableWriter.BoundingBox])
            -> Piece? {
            readStretch(s, of: image, settings: settings, lineHeight: line, padded: padded,
                        level: scan.level, walls: walls, recogniser: recogniser)
        }
        // A stretch moved or padded that reads nothing at full confidence, which is all the
        // merge admits, is read again as it was: Vision reads a crop a few pixels
        // different differently, and on `Briefer` p1 one moved crop read nothing at all.
        var pieces: [Piece] = []
        for (k, s) in stretches.enumerated() {
            if isCancelled() { return merged }
            let padded = cutsItsInk(s, of: image, level: scan.level, lineHeight: line)
            let changed = padded || !same(s, last.stretches[k])
            let walls = kept + stretches.indices.filter { $0 != k }.map { stretches[$0] }
            let first = read(s, padded: padded, walls: walls)
            if keepsRead(first, changed: changed), let first {
                pieces.append(first)
            } else if changed, let again = read(last.stretches[k], padded: false, walls: walls) ?? first {
                // The reading as it was, or, failing that, the moved one: its boxes under
                // full confidence are still evidence of text for `replaces`.
                pieces.append(again)
            }
        }
        // A band line kept beside a stretch is read again on its own, as a stretch is
        // (C53, `besideFragments`): on `Briefer` p4 both passes' bands read only
        // `chieving industria neace` of `achieving industrial peace than outside
        // factors…`, and nothing of the rest; shown that line alone, Vision reads it word
        // for word. The reading replaces the band line only when it spans it at full
        // confidence (`rereadSpans`). Out to its ink first, which a band's box can stop
        // short of. It is the rest of a line, for the merge's order, only when it follows
        // a stretch on its line; one that starts its line is not.
        var rereads: [(piece: Piece, stretch: SearchableWriter.BoundingBox?,
                       replaces: SearchableWriter.BoundingBox)] = []
        for (f, follows) in besideFragments(stretches, kept: kept, whole: whole.map(\.boundingBox),
                                            pageWidth: w, lineHeight: line) {
            if isCancelled() { return merged }
            let walls = kept.filter { !same($0, f) } + stretches
            let alone = reachingInk(f, walls: walls, pageWidth: w, pageHeight: h, lineHeight: line, hasInk: ink)
            guard let piece = read(alone, padded: cutsItsInk(alone, of: image, level: scan.level,
                                                              lineHeight: line), walls: walls),
                  rereadSpans(piece, f, pageHeight: h, pageWidth: w, lineHeight: line)
            else { continue }
            rereads.append((spreadOver(f, piece, pageHeight: h), follows ? alone : nil, f))
        }
        guard !pieces.isEmpty || !rereads.isEmpty else { return merged }
        return mergeRereading(input: last.input, bands: last.bands, pieces: pieces, rereads: rereads,
                              pageHeight: h, lineHeight: line, pageWidth: w, hasInk: ink,
                              continuing: stretches)
    }

    /// A reread's piece with each line on `f`'s line spread over `f`'s box as well as its
    /// own (C53), so it takes the band line's place in the page's order and keeps its
    /// reach to its neighbours. Read alone, Vision draws a tighter box: on `_1953_99
    /// Cong_ 2` p16 the reread of `of small business.` began 15 rows lower than the band
    /// line, and ended 10 px sooner, so the gap to `We know the im-` beside it passed a
    /// line's width and that fragment no longer followed it; either way the hyphen it
    /// ends was no longer joined to `portance`. Its own box is kept too, for a band line
    /// that saw only its x-height (`chieving industria neace`, 21 rows of a 48-row line)
    /// or stopped short of its ink (`low to Negotiate`).
    static func spreadOver(_ f: SearchableWriter.BoundingBox,
                           _ piece: (observations: [SearchableWriter.Observation], top: Int, bottom: Int),
                           pageHeight h: Int)
        -> (observations: [SearchableWriter.Observation], top: Int, bottom: Int) {
        let rows = Double(piece.bottom - piece.top)
        guard rows > 0, h > 0 else { return piece }
        let fTop = (f.y * Double(h) - Double(piece.top)) / rows
        let fBottom = ((f.y + f.height) * Double(h) - Double(piece.top)) / rows
        return (piece.observations.map { o in
            let b = o.boundingBox
            let top = (Double(piece.top) + b.y * rows) / Double(h)
            let tall = b.height * rows / Double(h)
            guard abs(top + tall / 2 - (f.y + f.height / 2)) < min(tall, f.height) / 2 else { return o }
            let y = min(b.y, fTop), bottom = max(b.y + b.height, fBottom)
            let x = min(b.x, f.x), right = max(b.x + b.width, f.x + f.width)
            return SearchableWriter.Observation(
                boundingBox: SearchableWriter.BoundingBox(x: x, y: y, width: right - x, height: bottom - y),
                text: o.text, confidence: o.confidence, quarterTurns: o.quarterTurns)
        }, piece.top, piece.bottom)
    }

    /// Whether `recogniseInBands` keeps a stretch's reading (C53): always for a stretch
    /// read as reported, and for one moved or padded (`changed`) only when it holds a
    /// line at full confidence, the only kind the merge admits; else the stretch is read
    /// again as it was.
    static func keepsRead(_ piece: (observations: [SearchableWriter.Observation], top: Int, bottom: Int)?,
                          changed: Bool) -> Bool {
        guard let piece else { return false }
        return !changed || piece.observations.contains { $0.confidence >= 1 }
    }

    /// Whether a band line's reading on its own (`readStretch`'s piece, rows of its crop)
    /// holds one observation at full confidence that spans the band line `f`, centred on
    /// its line in the page's rows. Spans means leaving at most a tenth of it, and at
    /// most half a line of `line` pixels on a page `pageWidth` wide, uncovered: a share
    /// alone would let a reading of a long line leave two words out unremarked.
    static func rereadSpans(_ piece: (observations: [SearchableWriter.Observation], top: Int, bottom: Int),
                            _ f: SearchableWriter.BoundingBox, pageHeight h: Int,
                            pageWidth w: Int, lineHeight line: Int) -> Bool {
        spanningRead(piece, f, pageHeight: h, pageWidth: w, lineHeight: line) != nil
    }

    /// The observation of a reread's piece that spans the band line `f` (`rereadSpans`),
    /// by its index in the piece and in the page's rows; nil when none does.
    static func spanningRead(_ piece: (observations: [SearchableWriter.Observation], top: Int, bottom: Int),
                             _ f: SearchableWriter.BoundingBox, pageHeight h: Int,
                             pageWidth w: Int, lineHeight line: Int)
        -> (index: Int, observation: SearchableWriter.Observation)? {
        guard h > 0, w > 0 else { return nil }
        let rows = Double(piece.bottom - piece.top)
        let open = min(0.1 * f.width, 0.5 * Double(line) / Double(w))
        for (i, o) in piece.observations.enumerated() {
            let b = o.boundingBox
            let top = (Double(piece.top) + b.y * rows) / Double(h)
            let tall = b.height * rows / Double(h)
            guard o.confidence >= 1, sidewaysOverlap(b, f) >= f.width - open,
                  abs(top + tall / 2 - (f.y + f.height / 2)) < min(tall, f.height) / 2 else { continue }
            return (i, SearchableWriter.Observation(
                boundingBox: SearchableWriter.BoundingBox(x: b.x, y: top, width: b.width, height: tall),
                text: o.text, confidence: o.confidence, quarterTurns: o.quarterTurns))
        }
        return nil
    }

    /// The last merge of `recogniseInBands`, over `input` with `bands` and then the
    /// stretches' `pieces`, and with each reread of a band line (C53) when it does no
    /// harm. A band line in `input`, kept by an earlier pass, is replaced there by its
    /// reading, in its place, so the page's order keeps the line where it was: added
    /// instead, on `_1941_Fiedler's hiring…` p1 `mat-` went before `they attended` on its
    /// own line. The rest of that reading, and the reading of a band line the last pass
    /// read, are tried before every band, so the pass's copy of the line does not refuse
    /// them; a reread's `stretch`, where it has one, is the rest of a line for the
    /// merge's order (`continuing`). Invariant 1, against the merge without rereads:
    /// every line that merge keeps at full confidence must be kept in this one, or
    /// spanned by its clean lines (`unspanned`), the band lines taken out included.
    /// Where a line is not spanned (the merge refused a reread beside a line of the
    /// page's own; a reread reaching into the next stretch refused that stretch's
    /// reading, `STAT. (1930) c. 135, s` on `Riesman_1942` p14; a junk box a band line had
    /// helped replace came back), the rereads beside it are dropped and the merge run
    /// again; with none beside it, all of them.
    static func mergeRereading(
        input: [SearchableWriter.Observation],
        bands: [(observations: [SearchableWriter.Observation], top: Int, bottom: Int)],
        pieces: [(observations: [SearchableWriter.Observation], top: Int, bottom: Int)],
        rereads: [(piece: (observations: [SearchableWriter.Observation], top: Int, bottom: Int),
                   stretch: SearchableWriter.BoundingBox?, replaces: SearchableWriter.BoundingBox)],
        pageHeight h: Int, lineHeight line: Int, pageWidth w: Int,
        hasInk: ((SearchableWriter.BoundingBox) -> Bool)?,
        continuing: [SearchableWriter.BoundingBox]
    ) -> [SearchableWriter.Observation] {
        let usual = mergeBands(whole: input, bands: bands + pieces, pageHeight: h, lineHeight: line,
                               pageWidth: w, hasInk: hasInk, continuing: continuing)
        guard h > 0, w > 0 else { return usual }
        let reach = Double(line) / Double(w)
        var rereads = rereads
        while !rereads.isEmpty {
            var page = input
            var first: [(observations: [SearchableWriter.Observation], top: Int, bottom: Int)] = []
            for r in rereads {
                if let i = page.firstIndex(where: { same($0.boundingBox, r.replaces) }),
                   let read = spanningRead(r.piece, r.replaces, pageHeight: h, pageWidth: w, lineHeight: line) {
                    page[i] = read.observation
                    var rest = r.piece
                    rest.observations.remove(at: read.index)
                    if !rest.observations.isEmpty { first.append(rest) }
                } else {
                    first.append(r.piece)
                }
            }
            let out = rereads.map(\.replaces)
            let again = mergeBands(whole: page.filter { o in !out.contains { same($0, o.boundingBox) } },
                                   bands: first + bands + pieces, pageHeight: h,
                                   lineHeight: line, pageWidth: w, hasInk: hasInk,
                                   continuing: continuing + rereads.compactMap(\.stretch))
            let lost = unspanned(usual, by: again, pageHeight: h, lineHeight: line, pageWidth: w)
            if lost.isEmpty { return again }
            let beside = rereads.filter { r in
                lost.contains { u in
                    min(u.y + u.height, r.replaces.y + r.replaces.height) > max(u.y, r.replaces.y)
                        && sidewaysOverlap(u, r.replaces) > -reach
                }
            }
            if beside.isEmpty { break }
            rereads.removeAll { r in beside.contains { same($0.replaces, r.replaces) } }
        }
        return usual
    }

    /// The lines of `held` at full confidence, no taller than two line heights, that
    /// `again` neither keeps, box for box, nor spans with its clean lines (`spanned`,
    /// C53). A clean line is one of those of no fused box's shape (`hasFusedLine`),
    /// which may be two lines read as one: a fused box at full confidence that came back
    /// over the lines it hides would otherwise span them. A fused-shaped line `held`
    /// keeps, large type say, counts as kept only when `again` keeps it too.
    static func unspanned(_ held: [SearchableWriter.Observation], by again: [SearchableWriter.Observation],
                          pageHeight h: Int, lineHeight line: Int, pageWidth w: Int)
        -> [SearchableWriter.BoundingBox] {
        guard h > 0, w > 0 else { return [] }
        let tallest = 2 * Double(line) / Double(h)
        let lines = again.filter {
            $0.confidence >= 1 && $0.boundingBox.height <= tallest
                && !hasFusedLine([$0], pageWidth: w, pageHeight: h, lineHeight: line)
        }.map(\.boundingBox)
        let open = 0.5 * Double(line) / Double(w)
        return held.filter { $0.confidence >= 1 && $0.boundingBox.height <= tallest }.map(\.boundingBox)
            .filter { b in !again.contains { same($0.boundingBox, b) } && !spanned(b, by: lines, open: open) }
    }

    /// Whether `boxes` centred on `box`'s line cover it between them, leaving at most a
    /// tenth of its width, and at most `open`, uncovered.
    static func spanned(_ box: SearchableWriter.BoundingBox, by boxes: [SearchableWriter.BoundingBox],
                        open: Double) -> Bool {
        let centre = box.y + box.height / 2
        let spans = boxes.filter { abs($0.y + $0.height / 2 - centre) < min($0.height, box.height) / 2 }
            .map { (max($0.x, box.x), min($0.x + $0.width, box.x + box.width)) }
            .filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var covered = 0.0, reach = box.x
        for (a, b) in spans where b > reach {
            covered += b - max(a, reach)
            reach = b
        }
        return covered >= box.width - min(0.1 * box.width, open)
    }

    /// Whether a page's reading so far buys the bands: a void (`hasVoid`), a box shaped
    /// like two fused lines (`hasFusedLine`), or one unread line beside a read one
    /// (`hasUnreadLine`, C53).
    static func wantsBands(inkedStrips: [[Bool]], observations: [SearchableWriter.Observation],
                           pageWidth w: Int, pageHeight h: Int, lineHeight line: Int) -> Bool {
        hasVoid(inkedStrips: inkedStrips, observations: observations, pageHeight: h, lineHeight: line)
            || hasFusedLine(observations, pageWidth: w, pageHeight: h, lineHeight: line)
            || hasUnreadLine(inkedStrips: inkedStrips, observations: observations, pageHeight: h,
                             lineHeight: line)
    }

    /// One unread stretch recognised on its own, as a band for `mergeBands`: cropped
    /// (`stretchCrop`), painted white outside its rows (`stretchRows`, `padded` when its
    /// box stops inside its line's type, `cutsItsInk`) and lifted back (`stretchPiece`).
    /// Nil when the crop or the request fails, which adds nothing.
    static func readStretch(_ s: SearchableWriter.BoundingBox, of image: CGImage,
                            settings: Prefs.Snapshot, lineHeight line: Int, padded: Bool,
                            /// The page's ink level, to keep the crop's sides off a glyph (`uncut`),
                            /// and the kept boxes and other stretches it does not reach into.
                            level: UInt8? = nil, walls: [SearchableWriter.BoundingBox] = [],
                            recogniser: (CGImage, Prefs.Snapshot) throws -> [SearchableWriter.Observation]
                                = { try Recogniser.recognise($0, settings: $1) })
        -> (observations: [SearchableWriter.Observation], top: Int, bottom: Int)? {
        let w = image.width, h = image.height
        guard let plain = stretchCrop(s, pageWidth: w, pageHeight: h, lineHeight: line) else { return nil }
        func read(_ rect: (left: Int, top: Int, right: Int, bottom: Int))
            -> (observations: [SearchableWriter.Observation], top: Int, bottom: Int)? {
            var local = settings
            local.minTextHeight = min(1, settings.minTextHeight * Double(h) / Double(rect.bottom - rect.top))
            let (width, height) = (rect.right - rect.left, rect.bottom - rect.top)
            let own = stretchRows(s, crop: rect, pageHeight: h, lineHeight: line, padded: padded)
            guard let cut = image.cropping(to: CGRect(x: rect.left, y: rect.top, width: width, height: height)),
                  let crop = paintedOut([CGRect(x: 0, y: 0, width: width, height: own.top),
                                         CGRect(x: 0, y: own.bottom, width: width, height: height - own.bottom)],
                                        of: cut),
                  let read = try? recogniser(crop, local)
            else { return nil }
            return stretchPiece(read, of: s, crop: rect, pageWidth: w, pageHeight: h)
        }
        guard let level else { return read(plain) }
        let rect = uncut(plain, of: s, walls: walls, image: image, level: level, lineHeight: line)
        guard rect != plain else { return read(plain) }
        // Both, and the wider one where it reads as many letters at full confidence, the only
        // lines the merge admits: Vision reads a crop a few pixels different differently, and
        // a reread is kept only where it spans its line (the review of this change).
        let (wider, asWas) = (read(rect), read(plain))
        func clean(_ p: (observations: [SearchableWriter.Observation], top: Int, bottom: Int)?) -> Int {
            p.map { $0.observations.filter { $0.confidence >= 1 }
                .reduce(0) { $0 + $1.text.filter { $0.isLetter || $0.isNumber }.count } } ?? -1
        }
        return clean(wider) >= clean(asWas) ? wider : asWas
    }

    /// A stretch's crop (`stretchCrop`) with each side moved out past a glyph it cuts
    /// (C53): where the crop's edge column and the one beyond it both hold ink on the
    /// stretch's middle rows, out to the glyph's end, then over up to the eighth of a line
    /// of paper the crop leaves at its sides. On `Briefer` p3 the crop of `…peculiar to
    /// industrial` ended 4 px into its `l`, and Vision read `industria`; with paper after
    /// the `l`, `industrial`. `reachingInk` moves a stretch's end only for half a line of
    /// ink, and 4 px is not that. Ink running on for a line past the edge, a rule or the
    /// line's own next words, moves nothing; nor does a column of ink two line heights tall,
    /// a vertical rule, which the edge test cannot tell from a glyph; nor a glyph of a kept
    /// box or another stretch beside it (`walls`, as `reachingInk` takes them): the crop of
    /// `M.D. Second Edition. The C. V. Mosby Company,` reached 6 px into the kept `3207
    /// Washington…`, and moved past its `3` it read `Company, 3`.
    static func uncut(_ rect: (left: Int, top: Int, right: Int, bottom: Int),
                      of s: SearchableWriter.BoundingBox, walls: [SearchableWriter.BoundingBox] = [],
                      image: CGImage, level: UInt8,
                      lineHeight line: Int) -> (left: Int, top: Int, right: Int, bottom: Int) {
        let w = image.width, h = image.height
        guard w > 0, h > 0, line > 0 else { return rect }
        let middle = middleHalf(of: s)
        /// Column `x`, probed over its own middle half-pixel so that `hasInk`'s rounding out
        /// to whole pixels cannot take in a neighbour (the review of this change).
        func inked(_ x: Int) -> Bool {
            guard x >= 0, x < w else { return false }
            return hasInk(in: SearchableWriter.BoundingBox(x: (Double(x) + 0.25) / Double(w), y: middle.y,
                                                         width: 0.5 / Double(w), height: middle.height),
                          of: image, level: level)
        }
        /// Whether column `x` is a rule: ink without a break over two line heights through the
        /// stretch's rows, which no glyph of a line is (the review of this change).
        func rule(_ x: Int) -> Bool {
            let mid = Int(((middle.y + middle.height / 2) * Double(h)).rounded())
            let (from, to) = (max(0, mid - 2 * line), min(h, mid + 2 * line))
            guard x >= 0, x < w, mid >= from, mid < to,
                  let grey = greyPixels(of: image, x0: x, y0: from, x1: x + 1, y1: to) else { return false }
            var (up, down) = (mid - from, mid - from)
            while up > 0, grey[up - 1] <= level { up -= 1 }
            while down < grey.count, grey[down] <= level { down += 1 }
            return down - up >= 2 * line
        }
        // The walls beside it on its rows, in pixels; one holding its centre is the box it was
        // cut from, and stops nothing.
        let centre = s.x + s.width / 2
        let beside = walls.filter {
            $0.x.isFinite && $0.width.isFinite
                && min($0.y + $0.height, middle.y + middle.height) > max($0.y, middle.y)
                && !($0.x <= centre && centre <= $0.x + $0.width)
        }
        func pixel(_ v: Double, _ rule: FloatingPointRoundingRule) -> Int {
            Int((min(max(v, 0), 1) * Double(w)).rounded(rule))
        }
        let rightWall = beside.filter { $0.x > centre }.map { pixel($0.x, .down) }.min() ?? w
        let leftWall = beside.filter { $0.x + $0.width < centre }.map { pixel($0.x + $0.width, .up) }.max() ?? 0
        let margin = max(1, line / 8)
        var (left, right) = (rect.left, rect.right)
        if right < rightWall, inked(right - 1), inked(right), !rule(right) {
            let limit = min(w, rect.right + line, rightWall)
            var end = right
            while end < limit, inked(end) { end += 1 }
            if end < limit {
                right = end
                while right < min(limit, end + margin), !inked(right) { right += 1 }
            }
        }
        if left > leftWall, inked(left), inked(left - 1), !rule(left - 1) {
            let limit = max(-1, rect.left - 1 - line, leftWall - 1)
            var start = left - 1
            while start > limit, inked(start) { start -= 1 }
            if start > limit {
                left = start + 1
                while left > max(limit + 1, start + 1 - margin), !inked(left - 1) { left -= 1 }
            }
        }
        return (left, rect.top, right, rect.bottom)
    }

    /// The rows of a stretch's crop (`stretchCrop`) shown to Vision, as rows of the crop:
    /// the stretch's own; the rest is painted white (C53). The crop keeps a line height
    /// of paper either side for the seam test, and shown the halves of the neighbouring
    /// lines there, Vision read `Briefer` p4's `(Address E. G. Wilson, …` as junk at 0.3
    /// that a band read cleanly. A stretch `padded`, cut to a box that stops inside its
    /// line's type (`cutsItsInk`), keeps a quarter line more each side (`seamMargin`).
    /// The one beside `chieving industria neace` had that box's 21 rows on a 48-row
    /// line, the bottom of the x-height outside them, and painted to them Vision read
    /// `nutside` and `nrofitahility`; padded, every word. Every other box keeps its
    /// rows: Vision reads a crop moved a few rows differently, and padded by height
    /// alone, `Briefer` p3's stretches of 38-44 rows on that page's 48 read `M.D.` as
    /// `V.D.` and lost an `a`, and a footnote's on `Riesman_1942` p14, small type under
    /// a page of body type, came back in three pieces that no longer replaced a fused box.
    static func stretchRows(_ s: SearchableWriter.BoundingBox,
                            crop: (left: Int, top: Int, right: Int, bottom: Int),
                            pageHeight h: Int, lineHeight line: Int,
                            padded: Bool) -> (top: Int, bottom: Int) {
        let pad = padded ? seamMargin(lineHeight: line) : 0
        let height = crop.bottom - crop.top
        let top = Int((s.y * Double(h)).rounded(.down)) - pad - crop.top
        let bottom = Int(((s.y + s.height) * Double(h)).rounded(.up)) + pad - crop.top
        return (min(height, max(0, top)), max(0, min(height, bottom)))
    }

    /// Whether a box stops inside its line's type (C53): the rows just inside its top or
    /// its bottom edge, an eighth of a line deep, hold four fifths as much ink within its
    /// columns, row for row, as its middle half's rows do, so the edge runs through the
    /// x-height. The band box `chieving industria neace` stopped four rows into it, at
    /// 0.88. A box that reaches past its ink, as Vision's do, has its own line's sparse
    /// ascenders or descenders there, or paper, whatever lies beyond: on `Riesman_1942`
    /// p14 a footnote line's box ends a row above the next line's dense capitals, and a
    /// test of the rows past the edge padded it, and its crop came back empty. One shown
    /// only its x-height misreads as surely as one cut into it, which the rows past the
    /// edge, a descender's, could not say (`ude fartore cuch ac` for `factors such as`).
    /// Four fifths, not half: the box of `Briefer` p3's `M.D. Second Edition…` clips
    /// three rows of its capitals' tips, 0.5 of its middle, and padded read `V.D.`.
    static func cutsItsInk(_ s: SearchableWriter.BoundingBox, of image: CGImage, level: UInt8,
                           lineHeight line: Int) -> Bool {
        let w = image.width, h = image.height
        guard s.x.isFinite, s.y.isFinite, s.width.isFinite, s.height.isFinite else { return false }
        let x0 = max(0, Int((s.x * Double(w)).rounded(.down)))
        let x1 = min(w, Int(((s.x + s.width) * Double(w)).rounded(.up)))
        let top = max(0, Int((s.y * Double(h)).rounded(.down)))
        let bottom = min(h, Int(((s.y + s.height) * Double(h)).rounded(.up)))
        let depth = max(2, line / 8)
        guard x1 > x0, bottom - top >= 4 else { return false }
        /// Inked pixels per row over rows `a..<b` of the box's columns.
        func ink(_ a: Int, _ b: Int) -> Double? {
            let (a, b) = (max(0, a), min(h, b))
            guard b > a, let grey = greyPixels(of: image, x0: x0, y0: a, x1: x1, y1: b) else { return nil }
            return Double(grey.lazy.filter { $0 <= level }.count) / Double(b - a)
        }
        let quarter = (bottom - top) / 4
        guard let middle = ink(top + quarter, bottom - quarter), middle > 0 else { return false }
        func dense(_ a: Int, _ b: Int) -> Bool { 5 * (ink(a, b) ?? 0) >= 4 * middle }
        let inside = max(1, min(depth, quarter))
        return dense(top, top + inside) || dense(bottom - inside, bottom)
    }

    /// A stretch run out sideways over the ink on its rows, to where its line's type
    /// ends (C53). A stretch's ends are boxes' ends, and a box Vision read as junk need
    /// not reach its own ink's: on `Briefer` p4 the fused box over `Employee
    /// Interchange. By Raymond W. Peters…` began 89 px into the line, so the stretch
    /// beside the kept `By Raymond W. Peters.` began there too and `Emp` was read by
    /// nothing. Each end moves out while there is ink past the eighth of a line that
    /// `stretchCrop` already shows beyond it, a quarter line at a time (`hasInk`, over
    /// the middle half of the stretch's rows). Two blank steps stop it, so paper under
    /// half a line wide, a space between words, is always crossed, and paper three
    /// quarters of a line wide never is. It stops at `walls`, the kept boxes and other
    /// stretches reaching those rows beside it (a wall holding the stretch's centre is
    /// the box it was cut from, and stops nothing), and goes no further than the lines
    /// above and below it within a line and a half reach, where there are any: a rule,
    /// a scan's edge or the next column across a narrow gutter is not its line. An end
    /// moves only for half a line of ink or more, two steps: Vision reads a crop moved
    /// by a few pixels differently, and on `Briefer` p1 a stretch moved 24 px for the
    /// last letter of `present` came back with nothing where it had read `egroes are at
    /// present` (so `recogniseInBands` reads a moved stretch again where it was when
    /// it comes back with nothing at full confidence). Returns `s` itself, unmoved.
    static func reachingInk(_ s: SearchableWriter.BoundingBox, walls: [SearchableWriter.BoundingBox],
                            pageWidth w: Int, pageHeight h: Int, lineHeight line: Int,
                            hasInk: (SearchableWriter.BoundingBox) -> Bool) -> SearchableWriter.BoundingBox {
        guard w > 0, h > 0, line > 0, s.width > 0, s.height > 0 else { return s }
        let step = Double(max(2, line / 4)) / Double(w)
        let slack = Double(line) / 8 / Double(w)
        let middle = middleHalf(of: s)
        let centre = s.x + s.width / 2
        let beside = walls.filter {
            min($0.y + $0.height, middle.y + middle.height) > max($0.y, middle.y)
                && !($0.x <= centre && centre <= $0.x + $0.width)
        }
        // The lines above and below in its column: centred off its middle rows, within a
        // line and a half, and over some of its width. On each side, not a box whose end
        // there is the stretch's own: the stretch took its end from that box, as from the
        // junk box over `Employee Interchange…` whose end the `Emp` fix gets past, and
        // that end says no more about where the line's ink ends.
        let around = walls.filter {
            let c = $0.y + $0.height / 2
            return !(c >= middle.y && c <= middle.y + middle.height)
                && abs(c - (s.y + s.height / 2)) <= 1.5 * Double(line) / Double(h)
                && overlapsSideways($0, s)
        }
        let pixel = 1 / Double(w)
        var leftmost = max(0, beside.filter { $0.x < centre }.map { min($0.x + $0.width, s.x) }.max() ?? 0)
        var rightmost = min(1, beside.filter { $0.x > centre }.map { max($0.x, s.x + s.width) }.min() ?? 1)
        // A step's tolerance: boxes end a few pixels either side of their ink (`How` of
        // `How to Negotiate` began 5 px left of the junk box over its line and the next).
        if let low = around.filter({ abs($0.x - s.x) > pixel }).map(\.x).min() {
            leftmost = max(leftmost, min(low - step, s.x))
        }
        if let high = around.map({ $0.x + $0.width }).filter({ abs($0 - (s.x + s.width)) > pixel }).max() {
            rightmost = min(rightmost, max(high + step, s.x + s.width))
        }
        func inked(_ from: Double) -> Bool {
            hasInk(SearchableWriter.BoundingBox(x: from, y: middle.y, width: step, height: middle.height))
        }
        var left = s.x, probe = s.x - slack, blank = 0, found = 0
        while blank < 2, probe - step >= leftmost {
            probe -= step
            if inked(probe) { left = probe; blank = 0; found += 1 } else { blank += 1 }
        }
        if found < 2 { left = s.x }
        var right = s.x + s.width
        probe = right + slack
        blank = 0
        found = 0
        while blank < 2, probe + step <= rightmost {
            if inked(probe) { right = probe + step; blank = 0; found += 1 } else { blank += 1 }
            probe += step
        }
        if found < 2 { right = s.x + s.width }
        if left == s.x, right == s.x + s.width { return s }
        return SearchableWriter.BoundingBox(x: left, y: s.y, width: right - left, height: s.height)
    }

    /// The band lines kept beside a stretch on its line (C53): kept boxes that are not
    /// the page's own (`whole`), centred on a stretch's line and within a quarter line
    /// of one of its ends, each with whether such a stretch lies to its left, so that it
    /// continues that stretch's line. A band that read part of a line and left the rest
    /// unread was shown that line badly, and `recogniseInBands` reads each of these
    /// again alone.
    static func besideFragments(_ stretches: [SearchableWriter.BoundingBox],
                                kept: [SearchableWriter.BoundingBox],
                                whole: [SearchableWriter.BoundingBox],
                                pageWidth w: Int, lineHeight line: Int)
        -> [(box: SearchableWriter.BoundingBox, follows: Bool)] {
        guard w > 0 else { return [] }
        let near = Double(max(2, line / 4)) / Double(w)
        return kept.compactMap { f in
            guard !whole.contains(where: { same($0, f) }) else { return nil }
            let by = stretches.filter { s in
                abs(f.y + f.height / 2 - (s.y + s.height / 2)) < min(f.height, s.height) / 2
                    && abs(sidewaysOverlap(f, s)) <= near
            }
            return by.isEmpty ? nil : (f, by.contains { $0.x < f.x })
        }
    }

    /// Whether two boxes are the same box, edge for edge: a kept box carried from one
    /// merge to the next is copied, never moved.
    static func same(_ a: SearchableWriter.BoundingBox, _ b: SearchableWriter.BoundingBox) -> Bool {
        a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height
    }

    /// `observations` with each line that runs across the page's column gutter
    /// (`SearchableWriter.columnGutter`) over no ink there replaced by its two
    /// halves, each recognised on its own as an unread stretch is (C34). On
    /// `Hughes` p3 Vision read three rows as single boxes 0.8 of the page wide,
    /// joining a line of the left column to the line beside it in the right
    /// (`tion whether the races will work well to- ployes sort themselves…`), and
    /// no ordering of the text layer can put half a box in each column.
    ///
    /// Vision's per-word boxes cannot place the split: on that page every gap
    /// between words, the gutter included, read 0.12-0.13 of the line's height.
    /// So the test is the paper: a heading or running head set across both columns
    /// has ink in the gutter and is left whole. Only a line starting at a margin of
    /// the column on the gutter's left is a candidate, which a centred heading with
    /// blank paper over the gutter is not: three or more of that side's column-wide
    /// lines start within three line heights of where it starts, or of where the
    /// fragment before it on its row starts (`_1953_99 Cong_ 2` p16 read `Mr. HILL`
    /// on its own and the rest of that row on into the next column). And a line is
    /// kept whole whose halves do not both
    /// read, read under 0.8 of its characters between them, or one of them under
    /// 0.4 of its share by width (invariant 1: the fused reading is kept rather
    /// than lose its text). The halves are cut in the middle of the blank paper
    /// (`blankGutter`), so the end of a long left line reaching into the gutter stays
    /// with its half. A row read across a rule printed down the gutter is cut beside
    /// the rule where the paper there is as wide as the gutter found, and kept whole
    /// where it is not.
    ///
    /// Every gutter the writer orders the page by is asked, not only the page's
    /// widest-backed one (`SearchableWriter.columnGutters`): on `Riesman_1949` p2, three
    /// columns, the four rows read across the second gutter started at the middle
    /// column's margin, and the page had one margin, the first column's (C52). A line
    /// crossing a gutter by under a line height is its own column's, overshooting
    /// (`SearchableWriter.readsAcross`), and is not read again.
    static func splitAtGutter(_ observations: [SearchableWriter.Observation], of image: CGImage,
                              settings: Prefs.Snapshot, isCancelled: () -> Bool = { false })
        -> [SearchableWriter.Observation] {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return observations }
        let line = lineHeight(of: observations, pageHeight: h)
        let lineX = Double(line) / Double(w)
        // Tagged with their places, since `columnGutters` hands back the lines each
        // gutter was found among and `columnOrdered` without clearing only reorders.
        let tagged = observations.enumerated().map { i, o -> SearchableWriter.Observation in
            var t = o
            t.region = i
            return t
        }
        var across: [Int: SearchableWriter.Gutter] = [:]
        for (g, among) in SearchableWriter.columnGutters(of: tagged, aspect: Double(h) / Double(w)) {
            let margins = among.map(\.boundingBox)
                .filter { $0.x < g.from && $0.x + $0.width <= g.to && $0.width >= 10 * lineX }
                .map(\.x)
            for o in among {
                guard let i = o.region, across[i] == nil,
                      SearchableWriter.readsAcross(o.boundingBox, g, reach: lineX) else { continue }
                let start = rowStart(of: i, in: observations, lineX: lineX)
                guard margins.filter({ abs($0 - start) <= 3 * lineX }).count >= 3 else { continue }
                across[i] = g
            }
        }
        guard !across.isEmpty else { return observations }
        var level: UInt8??
        var out: [SearchableWriter.Observation] = []
        for (index, o) in observations.enumerated() {
            let b = o.boundingBox
            guard !isCancelled(), let g = across[index] else { out.append(o); continue }
            if level == nil { level = inkScan(of: image, strips: [])?.level }
            guard let known = level ?? nil,
                  let middle = blankGutter(under: b, near: g, of: image, level: known, lineX: lineX)
            else { out.append(o); continue }
            var halves: [SearchableWriter.Observation] = []
            for s in [SearchableWriter.BoundingBox(x: b.x, y: b.y, width: middle - b.x,
                                                   height: b.height),
                      SearchableWriter.BoundingBox(x: middle, y: b.y, width: b.x + b.width - middle,
                                                   height: b.height)] {
                guard let rect = stretchCrop(s, pageWidth: w, pageHeight: h, lineHeight: line),
                      let crop = image.cropping(to: CGRect(x: rect.left, y: rect.top,
                                                           width: rect.right - rect.left,
                                                           height: rect.bottom - rect.top))
                else { halves = []; break }
                var local = settings
                local.minTextHeight = min(1, settings.minTextHeight * Double(h)
                                            / Double(rect.bottom - rect.top))
                // `stretchPiece` leaves y in the crop's rows, which `mergeBands` lifts;
                // nothing merges these, so they are lifted here.
                let rows = Double(rect.bottom - rect.top)
                let piece = stretchPiece((try? recognise(crop, settings: local)) ?? [], of: s,
                                         crop: rect, pageWidth: w, pageHeight: h).observations
                    .map { p in
                        SearchableWriter.Observation(
                            boundingBox: SearchableWriter.BoundingBox(
                                x: p.boundingBox.x,
                                y: (Double(rect.top) + p.boundingBox.y * rows) / Double(h),
                                width: p.boundingBox.width,
                                height: p.boundingBox.height * rows / Double(h)),
                            text: p.text, confidence: p.confidence,
                            quarterTurns: p.quarterTurns)
                    }
                let read = Double(piece.reduce(0) { $0 + $1.text.count })
                guard !piece.isEmpty, read >= 0.4 * s.width / b.width * Double(o.text.count)
                else { halves = []; break }
                halves += piece
            }
            let read = Double(halves.reduce(0) { $0 + $1.text.count })
            out += !halves.isEmpty && read >= 0.8 * Double(o.text.count) ? halves : [o]
        }
        return out
    }

    /// Where a line read across `g` is cut: the middle of a run of blank paper under its
    /// row `b`, within a line height of the gutter, at least as wide as the gutter and a
    /// third of a line, and covering half of it or more; of several, the one covering
    /// most. Nil when there is none: the row has ink across the gutter, as a heading
    /// does, whose word spaces are narrower than the gutter between its columns.
    ///
    /// Found from the pixels because a gutter found from the boxes can sit off the
    /// paper: on `Riesman_1949` p2 the right column's boxes overshoot further than the
    /// middle column's, the strip found started at 0.6405, and the fused first row's
    /// `more` ends at 0.6441, so a test of the whole strip read its last letter as ink
    /// in the gutter and the row stayed whole (C52). The blank paper runs to 0.6634
    /// there. A rule printed down the gutter leaves a run beside it, and a row read
    /// across it is cut there when that run is as wide as the gutter found. A pixel
    /// column is blank with under one pixel in 25 at or under `level`, which lets a speck
    /// of dirt pass.
    static func blankGutter(under b: SearchableWriter.BoundingBox, near g: SearchableWriter.Gutter,
                            of image: CGImage, level: UInt8, lineX: Double) -> Double? {
        let w = image.width, h = image.height
        let from = max(0, g.from - lineX), to = min(1, g.to + lineX)
        let top = max(0, b.y), bottom = min(1, b.y + b.height)
        guard [from, to, top, bottom].allSatisfy(\.isFinite), to > from, bottom > top else { return nil }
        let x0 = Int((from * Double(w)).rounded(.down)), x1 = Int((to * Double(w)).rounded(.up))
        let y0 = Int((top * Double(h)).rounded(.down)), y1 = Int((bottom * Double(h)).rounded(.up))
        guard let grey = greyPixels(of: image, x0: x0, y0: y0, x1: x1, y1: y1) else { return nil }
        let pw = x1 - x0, ph = y1 - y0
        let gutter = g.to - g.from
        var best: (middle: Double, covering: Double)?
        var start = 0
        for column in 0...pw {
            var blank = false
            if column < pw {
                var dark = 0
                for row in 0..<ph where grey[row * pw + column] <= level { dark += 1 }
                blank = dark * 25 < ph
            }
            if blank { continue }
            // The run `start..<column`, in widths of the page.
            let from = Double(x0 + start) / Double(w), to = Double(x0 + column) / Double(w)
            let covering = min(to, g.to) - max(from, g.from)
            if to - from >= max(lineX / 3, gutter), covering >= gutter / 2,
               covering > (best?.covering ?? 0) {
                best = ((from + to) / 2, covering)
            }
            start = column + 1
        }
        return best?.middle
    }

    /// The pixels `x0..<x1` by `y0..<y1` of `image` as 8-bit grey, row by row from the
    /// top; nil when the rect is empty or will not draw.
    private static func greyPixels(of image: CGImage, x0: Int, y0: Int, x1: Int, y1: Int) -> [UInt8]? {
        guard x1 > x0, y1 > y0,
              let piece = image.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
        else { return nil }
        let pw = x1 - x0, ph = y1 - y0
        var grey = [UInt8](repeating: 255, count: pw * ph)
        let drawn = grey.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress, let ctx = CGContext(
                data: base, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
            ctx.draw(piece, in: CGRect(x: 0, y: 0, width: pw, height: ph))
            return true
        }
        return drawn ? grey : nil
    }

    /// `observations` with the side of each line that faces a column gutter brought in to
    /// the line's ink (C52), so that the text layer's gutter is the page's.
    ///
    /// PDFKit, and so Preview, finds a page's columns from where the text lies, and
    /// keeps them apart only across a clear gap. Vision's boxes overshoot the ink by a
    /// point or two, and by five on some lines, and a box read from a crop more: on
    /// `Riesman_1949` p2 the gutter between the middle and right columns is 7-10 pt of
    /// paper, and the boxes left 3 pt of it. There PDFKit read the two columns in turns,
    /// eight lines of one and then eight of the other, and one box moved by a fraction
    /// of a point could change where [measured]. With the right column's lines starting
    /// where their ink does, it read each column whole at every clearance tried
    /// [measured]. So each line on one side of a gutter (`SearchableWriter.
    /// columnGutters`) whose box reaches into it has that edge moved to its ink, found
    /// over the box's whole height within three line heights of the edge, plus a
    /// sixteenth of a line. Only those: moving every edge near a gutter to its ink, 73
    /// of `Hughes` p3's, gained nothing there, and every box moved is a new layout for
    /// PDFKit to read. A box is only ever narrowed, never by half its width, and not at
    /// all where its ink reaches the edge or none is found: this cannot uncover a letter.
    /// Lines read across a gutter are `splitAtGutter`'s, and a page with no gutter is
    /// returned as it came.
    static func fittedToGutters(_ observations: [SearchableWriter.Observation], of image: CGImage,
                                isCancelled: () -> Bool = { false }) -> [SearchableWriter.Observation] {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return observations }
        let line = lineHeight(of: observations, pageHeight: h)
        let lineX = Double(line) / Double(w)
        let tagged = observations.enumerated().map { i, o -> SearchableWriter.Observation in
            var t = o
            t.region = i
            return t
        }
        let gutters = SearchableWriter.columnGutters(of: tagged, aspect: Double(h) / Double(w))
        guard !gutters.isEmpty, let level = inkScan(of: image, strips: [])?.level else {
            return observations
        }
        var out = observations
        for (g, among) in gutters {
            let middle = (g.from + g.to) / 2
            for o in among {
                guard !isCancelled(), let i = o.region else { continue }
                let b = out[i].boundingBox
                guard b.width >= 2 * lineX, !SearchableWriter.readsAcross(b, g, reach: lineX)
                else { continue }
                let onLeft = b.x + b.width / 2 < middle
                guard onLeft ? b.x + b.width > g.from : b.x < g.to,
                      let ink = inkEdge(of: b, facingRight: onLeft, in: image, level: level,
                                        lineX: lineX)
                else { continue }
                var left = b.x, right = b.x + b.width
                if onLeft { right = min(right, ink + lineX / 16) } else { left = max(left, ink - lineX / 16) }
                guard right - left < b.width, right - left >= b.width / 2 else { continue }
                let was = out[i]
                out[i] = SearchableWriter.Observation(
                    boundingBox: SearchableWriter.BoundingBox(x: left, y: b.y, width: right - left,
                                                              height: b.height),
                    text: was.text, confidence: was.confidence, quarterTurns: was.quarterTurns,
                    region: was.region)
            }
        }
        return out
    }

    /// The x, in widths of the page, where the ink of the line in `b` ends on its right
    /// (`facingRight`) or starts on its left: the outermost pixel column holding two dark
    /// pixels or more over the box's height, within three line heights of that edge. Nil
    /// when there is none, or when the ink reaches the edge and may go on past it. The
    /// whole height, so a closing quote or a comma counts; ink of the line above or
    /// below inside the box can only hold the edge further out.
    static func inkEdge(of b: SearchableWriter.BoundingBox, facingRight: Bool, in image: CGImage,
                        level: UInt8, lineX: Double) -> Double? {
        let w = image.width, h = image.height
        let near = facingRight ? b.x + b.width : b.x
        let from = max(0, max(b.x, facingRight ? near - 3 * lineX : near))
        let to = min(1, min(b.x + b.width, facingRight ? near : near + 3 * lineX))
        let top = max(0, b.y), bottom = min(1, b.y + b.height)
        guard [from, to, top, bottom].allSatisfy(\.isFinite), to > from, bottom > top else { return nil }
        let x0 = Int((from * Double(w)).rounded(.down)), x1 = Int((to * Double(w)).rounded(.up))
        let y0 = Int((top * Double(h)).rounded(.down)), y1 = Int((bottom * Double(h)).rounded(.up))
        guard let grey = greyPixels(of: image, x0: x0, y0: y0, x1: x1, y1: y1) else { return nil }
        let pw = x1 - x0, ph = y1 - y0
        func inked(_ column: Int) -> Bool {
            var dark = 0
            for row in 0..<ph where grey[row * pw + column] <= level {
                dark += 1
                if dark >= 2 { return true }
            }
            return false
        }
        let columns = facingRight ? Array((0..<pw).reversed()) : Array(0..<pw)
        guard let first = columns.first(where: inked), first != columns.first else { return nil }
        return Double(x0 + (facingRight ? first + 1 : first)) / Double(w)
    }

    /// Where the row of `observations[i]` starts: its own left edge, or the left edge of
    /// the fragment that ends within a third of a line height of where it starts on the
    /// same row, followed leftwards. Vision reads a speaker's name or a first word on its
    /// own and the rest of the row as another box (`Mr. HILL` / `That is right. But I do
    /// not…`). A third of a line is under any gutter (`columnGutter`), so this does not
    /// step into the column beside it.
    static func rowStart(of i: Int, in observations: [SearchableWriter.Observation],
                         lineX: Double) -> Double {
        let me = observations[i].boundingBox
        let centre = me.y + me.height / 2
        var start = me.x
        for _ in 0..<8 {
            guard let before = observations.first(where: { o in
                let b = o.boundingBox
                return abs(b.y + b.height / 2 - centre) < me.height / 2 && b.x < start
                    && abs(b.x + b.width - start) < lineX / 3
            }) else { break }
            start = before.boundingBox.x
        }
        return start
    }

    /// The pixel rect, top-left origin, recognised for an unread stretch: a line
    /// height clear above and below, so the seam test keeps its line (at half a line
    /// it cut `Leland` p2's `States and Municipalities,`, a taller box than the
    /// band's), and an eighth of one to either side (at half, it took in the kept
    /// fragment's last comma: `, 1950. 86 pages.`). Nil when nothing is left of it.
    static func stretchCrop(_ s: SearchableWriter.BoundingBox, pageWidth w: Int, pageHeight h: Int,
                            lineHeight line: Int) -> (left: Int, top: Int, right: Int, bottom: Int)? {
        guard s.x.isFinite, s.y.isFinite, s.width.isFinite, s.height.isFinite else { return nil }
        let left = max(0, Int((s.x * Double(w) - Double(line) / 8).rounded(.down)))
        let right = min(w, Int(((s.x + s.width) * Double(w) + Double(line) / 8).rounded(.up)))
        let top = max(0, Int((s.y * Double(h)).rounded(.down)) - line)
        let bottom = min(h, Int(((s.y + s.height) * Double(h)).rounded(.up)) + line)
        guard right > left, bottom > top else { return nil }
        return (left, top, right, bottom)
    }

    /// A stretch's reading as a band for `mergeBands`: rows of the crop, columns of
    /// the page. Only a read centred on the stretch's own rows is kept: Vision reads
    /// the halves of the neighbouring lines too, as junk and at full confidence
    /// (`uoromont Pintino Ofine Wochina.` on `Briefer` p3).
    static func stretchPiece(_ read: [SearchableWriter.Observation], of s: SearchableWriter.BoundingBox,
                             crop: (left: Int, top: Int, right: Int, bottom: Int),
                             pageWidth w: Int, pageHeight h: Int)
        -> (observations: [SearchableWriter.Observation], top: Int, bottom: Int) {
        let scale = Double(crop.right - crop.left) / Double(w)
        let rows = (from: s.y * Double(h) - Double(crop.top),
                    to: (s.y + s.height) * Double(h) - Double(crop.top))
        let own = read.filter {
            let centre = ($0.boundingBox.y + $0.boundingBox.height / 2) * Double(crop.bottom - crop.top)
            return centre >= rows.from && centre <= rows.to
        }
        return (own.map {
            SearchableWriter.Observation(
                boundingBox: SearchableWriter.BoundingBox(
                    x: Double(crop.left) / Double(w) + $0.boundingBox.x * scale,
                    y: $0.boundingBox.y,
                    width: $0.boundingBox.width * scale,
                    height: $0.boundingBox.height),
                text: $0.text, confidence: $0.confidence, quarterTurns: $0.quarterTurns)
        }, crop.top, crop.bottom)
    }

    /// The median observation height in pixels, the unit every length below is
    /// stated in. A page with no observations gets a sixtieth of its height —
    /// about 11 pt on a letter page — so the plan and the trigger still have a
    /// scale when the whole-page request returned nothing at all.
    static func lineHeight(of observations: [SearchableWriter.Observation],
                           pageHeight h: Int) -> Int {
        let heights = observations.map { $0.boundingBox.height * Double(h) }
            .filter { $0.isFinite && $0 > 0 }.sorted()
        guard !heights.isEmpty else { return max(1, h / 60) }
        return max(1, Int(min(heights[heights.count / 2], Double(h)).rounded()))
    }

    /// How close to an interior band edge a band's box may come before it counts
    /// as cut: a quarter line, and never under two rows. A cut box ends on the
    /// edge; a whole one clears it.
    static func seamMargin(lineHeight line: Int) -> Int { max(2, line / 4) }

    /// The bands to recognise, as half-open row ranges from the top of the image.
    ///
    /// **The rule.** Eight bands' worth of stride — the band count that did best on
    /// C30's ~4,400-row pages, about 550 rows each — but never under 256 rows or
    /// four line heights, so a small image or large type is not cut into slivers.
    /// Each band runs one stride plus an overlap into the next of **two line
    /// heights and a seam margin either side**, so any line up to two line heights
    /// tall lies inside some band clear of both its seam margins, and survives the
    /// merge's cut test there. A last band shorter than a stride is folded into the
    /// one before it rather than sent as a sliver. `shifted` moves every interior
    /// seam down half a
    /// stride — the first band grows by that much — for the second pass. Empty for
    /// an image under 1,024 rows, four of the
    /// shortest bands, where every loss C30 measured was on pages of 3,300–4,500
    /// rows; and whenever one band would be the whole page, since that is the
    /// request already made.
    static func bandPlan(height h: Int, lineHeight line: Int,
                         shifted: Bool = false) -> [(top: Int, bottom: Int)] {
        guard h >= 1024, line > 0, line <= h else { return [] }
        let overlap = 2 * line + 2 * seamMargin(lineHeight: line)
        let stride = max((h + 7) / 8, 4 * line, 256)
        var out: [(top: Int, bottom: Int)] = []
        var top = 0
        var next = stride + (shifted ? stride / 2 : 0)
        while true {
            let bottom = min(h, next + overlap)
            out.append((top, bottom))
            if bottom == h { break }
            top = next
            next += stride
        }
        if out.count > 1, let last = out.last, last.bottom - last.top < stride {
            out.removeLast()
            out[out.count - 1].bottom = h
        }
        return out.count > 1 ? out : []
    }

    /// Which rows of the image hold ink: at least 0.5% of the row's pixels at or
    /// below the page's Otsu level. The fraction and the level are
    /// `Tools/score-text-voids`' (`artefact.py`'s), the measure C30 was found with.
    ///
    /// Read in strips of 256 rows, twice — once for the histogram, once for the
    /// rows — so the scan never holds a grey copy of the whole page beside the
    /// image and Vision's own buffers: `Flattener.maximumPageMegapixels` lets a
    /// 400-megapixel page through, and a Swift array that cannot be allocated is
    /// a crash, not an error (R24).
    static func inkedRows(of image: CGImage) -> [Bool]? {
        inkedStrips(of: image, strips: [(0, 1)])?.first
    }

    /// The horizontal extents, as fractions of the width, the void trigger is
    /// asked over: the whole width, which is the test C30 shipped, and then four
    /// quarters, so a block missed beside a column the request did read is still
    /// a void in its own strip (C33). The quarters leave out the outer sixteenth
    /// each side, as `Flattener.interiorWindow` does: a quarter's rows are covered
    /// only by boxes reaching into it, so a scan's edge shadow in a margin no text
    /// reaches would be a void there that no band can fill, and every such page
    /// would pay for both passes.
    static let voidStrips: [(from: Double, to: Double)] =
        [(0, 1), (0.0625, 0.25), (0.25, 0.5), (0.5, 0.75), (0.75, 0.9375)]

    /// `inkedRows`, once for each strip: which rows hold ink within it. A row of a
    /// strip is inked at the same absolute count as a row of the page, 0.5% of the
    /// *page's* width, so a strip needs as much ink on a row as the page did.
    static func inkedStrips(of image: CGImage,
                            strips: [(from: Double, to: Double)] = voidStrips) -> [[Bool]]? {
        inkScan(of: image, strips: strips)?.rows
    }

    /// `inkedStrips`, with the Otsu level it judged ink by.
    static func inkScan(of image: CGImage, strips: [(from: Double, to: Double)] = voidStrips)
        -> (rows: [[Bool]], level: UInt8)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0,
              Double(w) * Double(h) <= Double(Flattener.maximumPageMegapixels) * 1_000_000
        else { return nil }
        let strip = min(256, h)
        var grey = [UInt8](repeating: 255, count: w * strip)
        /// Draws rows `top..<top + rows` into `grey`, top row first.
        func draw(_ top: Int, _ rows: Int) -> Bool {
            guard let piece = image.cropping(to: CGRect(x: 0, y: top, width: w, height: rows))
            else { return false }
            return grey.withUnsafeMutableBytes { raw -> Bool in
                guard let base = raw.baseAddress, let ctx = CGContext(
                    data: base, width: w, height: rows, bitsPerComponent: 8, bytesPerRow: w,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                ctx.setFillColor(gray: 1, alpha: 1)
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: rows))
                ctx.draw(piece, in: CGRect(x: 0, y: 0, width: w, height: rows))
                return true
            }
        }
        var histogram = [Int](repeating: 0, count: 256)
        for top in stride(from: 0, to: h, by: strip) {
            let rows = min(strip, h - top)
            guard draw(top, rows) else { return nil }
            for value in grey[0..<(w * rows)] { histogram[Int(value)] += 1 }
        }
        let level = Flattener.otsuThreshold(histogram: histogram)
        guard !strips.isEmpty else { return ([], level) }
        let need = max(1, w / 200)
        let spans = strips.map { s -> Range<Int> in
            let from = min(w, max(0, Int((s.from * Double(w)).rounded())))
            return from..<min(w, max(from, Int((s.to * Double(w)).rounded())))
        }
        var out = [[Bool]](repeating: [Bool](repeating: false, count: h), count: spans.count)
        for top in stride(from: 0, to: h, by: strip) {
            let rows = min(strip, h - top)
            guard draw(top, rows) else { return nil }
            for y in 0..<rows {
                let base = y * w
                for (s, span) in spans.enumerated() {
                    var dark = 0
                    for x in span where grey[base + x] <= level {
                        dark += 1
                        if dark >= need { break }
                    }
                    out[s][top + y] = dark >= need
                }
            }
        }
        return (out, level)
    }

    /// Whether at least 1% of `box` (normalised, top-left origin) is at or below
    /// `level`: printed text rather than paper. Type fills several percent of any
    /// stretch of a line; a blank margin or the end of a short line holds none.
    ///
    /// A box it cannot measure — off the page, not finite, a crop or a context that
    /// fails — answers **true**. `replaces` reads "no ink" as licence to drop a
    /// junk box, so not knowing has to keep it (invariant 1).
    static func hasInk(in box: SearchableWriter.BoundingBox, of image: CGImage,
                       level: UInt8) -> Bool {
        let w = image.width, h = image.height
        /// A normalised edge in pixels, clamped before the `Int` conversion, which
        /// traps outside `Int`'s range.
        func pixel(_ v: Double, _ size: Int, _ rule: FloatingPointRoundingRule) -> Int? {
            let p = v * Double(size)
            guard p.isFinite else { return nil }
            return Int(min(max(p, 0), Double(size)).rounded(rule))
        }
        guard let x0 = pixel(box.x, w, .down), let y0 = pixel(box.y, h, .down),
              let x1 = pixel(box.x + box.width, w, .up), let y1 = pixel(box.y + box.height, h, .up),
              x1 > x0, y1 > y0,
              let piece = image.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
        else { return true }
        let pw = x1 - x0, ph = y1 - y0
        var grey = [UInt8](repeating: 255, count: pw * ph)
        let drawn = grey.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress, let ctx = CGContext(
                data: base, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
            ctx.draw(piece, in: CGRect(x: 0, y: 0, width: pw, height: ph))
            return true
        }
        guard drawn else { return true }
        return grey.lazy.filter { $0 <= level }.count * 100 >= grey.count
    }

    /// Whether the whole-page result leaves a void: a run of rows no observation
    /// covers that holds at least **two line heights of inked rows**.
    ///
    /// Boxes cover their rows padded by a quarter line, so the gap between a word
    /// box's x-height and its line's ascenders is not a void. Two lines' worth and
    /// not one, so a stray rule or a lone missed page number does not buy eight
    /// more requests; C30's voids were 171 rows at 100 dpi, many lines each.
    ///
    /// **Or two lines, counted as lines** (C51): two runs of inked rows, each a
    /// quarter line tall, with blank rows between them. The line height is the
    /// page's median, body type; the three footnote lines `Bird` p5's request
    /// skipped held 79 inked rows against the 106 two body lines ask for, and the
    /// bands that read them never ran. A rule is one short run, a page number one;
    /// and the two must be lines of one block, under a line height of paper apart,
    /// so a page number below a scan's dark edge does not buy the bands either.
    static func hasVoid(inked: [Bool], observations: [SearchableWriter.Observation],
                        pageHeight h: Int, lineHeight line: Int) -> Bool {
        guard h > 0, inked.count >= h else { return false }
        var covered = [Bool](repeating: false, count: h)
        let pad = Double(max(1, line / 4))
        for o in observations {
            let top = o.boundingBox.y * Double(h) - pad
            let bottom = (o.boundingBox.y + o.boundingBox.height) * Double(h) + pad
            guard top.isFinite, bottom.isFinite else { continue }
            // Clamped before the `Int` conversion, which traps outside `Int`'s range.
            let first = max(0, Int(min(max(top, -1), Double(h)).rounded(.down)))
            let last = min(h - 1, Int(min(max(bottom, -1), Double(h)).rounded(.up)))
            if first <= last { for y in first...last { covered[y] = true } }
        }
        let need = 2 * line
        let tallRun = max(2, line / 4)
        var ink = 0, runs = 0, run = 0, blank = 0
        for y in 0..<h {
            if covered[y] { ink = 0; runs = 0; run = 0; blank = 0; continue }
            if inked[y] {
                ink += 1; run += 1; blank = 0
                if ink >= need { return true }
                if run == tallRun { runs += 1; if runs >= 2 { return true } }
            } else {
                run = 0; blank += 1
                if blank > line { runs = 0 }
            }
        }
        return false
    }

    /// Whether a strip's rows hold one line no observation reads, beside a line one
    /// does (C53): a run of inked rows, a quarter line to one and a half lines tall,
    /// that is nearest no observation's centre, under a line height of paper from a
    /// run that is. `Banks 2006` p101's request skipped the last line of a footnote,
    /// one line where `hasVoid` wants two, and the box of the line above it reached
    /// over it, so no row of it was uncovered. A page number set off by more than a
    /// line height of paper is not a line of the block, and buys no bands.
    static func hasUnreadLine(inked: [Bool], observations: [SearchableWriter.Observation],
                              pageHeight h: Int, lineHeight line: Int) -> Bool {
        guard h > 0, line > 0, inked.count >= h else { return false }
        var runs: [(top: Int, bottom: Int)] = []
        var start: Int?
        for y in 0...h {
            if y < h, inked[y] {
                if start == nil { start = y }
            } else if let s = start {
                if y - s >= max(2, line / 4) { runs.append((s, y)) }
                start = nil
            }
        }
        guard runs.count >= 2 else { return false }
        var read = [Bool](repeating: false, count: runs.count)
        for o in observations {
            let centre = (o.boundingBox.y + o.boundingBox.height / 2) * Double(h)
            guard centre.isFinite, let nearest = runs.indices.min(by: {
                abs(Double(runs[$0].top + runs[$0].bottom) / 2 - centre)
                    < abs(Double(runs[$1].top + runs[$1].bottom) / 2 - centre)
            }) else { continue }
            read[nearest] = true
        }
        for j in runs.indices where !read[j] && 2 * (runs[j].bottom - runs[j].top) <= 3 * line {
            if j > 0, read[j - 1], runs[j].top - runs[j - 1].bottom < line { return true }
            if j + 1 < runs.count, read[j + 1], runs[j + 1].top - runs[j].bottom < line { return true }
        }
        return false
    }

    /// How many of a page's published observations are lines Vision could not read
    /// (C53): `hasFusedLine`'s shape, over 1.4 line heights tall and eight wide, at
    /// under full confidence. Two footnote lines of `Riesman_1942` p14 came back as
    /// one box at 0.3 (`Brazian nation co Peda…`) that no band read cleanly enough to
    /// replace, and of the band lines no fused box survived at full confidence on the
    /// pages C33 and C53 name. Taken over normalised boxes, so the width test assumes
    /// a square page: on a portrait page the bar is about six line heights.
    static func unreadableLines(_ observations: [SearchableWriter.Observation]) -> Int {
        let heights = observations.map(\.boundingBox.height).filter { $0.isFinite && $0 > 0 }.sorted()
        guard !heights.isEmpty else { return 0 }
        let line = heights[heights.count / 2]
        return observations.filter {
            $0.confidence < 1 && $0.boundingBox.height > 1.4 * line && $0.boundingBox.width > 8 * line
        }.count
    }

    /// `hasUnreadLine` over each of `voidStrips`, a strip's rows read only by the
    /// observations that reach into it sideways.
    static func hasUnreadLine(inkedStrips: [[Bool]], observations: [SearchableWriter.Observation],
                              pageHeight h: Int, lineHeight line: Int,
                              strips: [(from: Double, to: Double)] = voidStrips) -> Bool {
        zip(inkedStrips, strips).contains { rows, strip in
            hasUnreadLine(inked: rows, observations: observations.filter {
                min($0.boundingBox.x + $0.boundingBox.width, strip.to) > max($0.boundingBox.x, strip.from)
            }, pageHeight: h, lineHeight: line)
        }
    }

    /// Whether the page holds a box that may be two lines read as one: over 1.4
    /// line heights tall and over eight wide, the shape of every fused reading on
    /// C33's pages (`since nhe dades indicated: meitlapolis…`, 1.7 line heights at
    /// full confidence, on `Leland` p2). Such a box covers its rows, so it leaves
    /// no void, and without this the bands that can replace it never run. A tall
    /// heading has the same shape and costs a page its bands; `replaces` keeps it.
    static func hasFusedLine(_ observations: [SearchableWriter.Observation],
                             pageWidth w: Int, pageHeight h: Int, lineHeight line: Int) -> Bool {
        observations.contains {
            $0.boundingBox.height * Double(h) > 1.4 * Double(line)
                && $0.boundingBox.width * Double(w) > 8 * Double(line)
        }
    }

    /// `hasVoid` over each of `voidStrips`, with `inkedStrips`' rows: a strip's
    /// rows are covered only by the observations that reach into it sideways.
    static func hasVoid(inkedStrips: [[Bool]], observations: [SearchableWriter.Observation],
                        pageHeight h: Int, lineHeight line: Int,
                        strips: [(from: Double, to: Double)] = voidStrips) -> Bool {
        for (rows, strip) in zip(inkedStrips, strips) {
            let reaching = observations.filter {
                min($0.boundingBox.x + $0.boundingBox.width, strip.to) > max($0.boundingBox.x, strip.from)
            }
            if hasVoid(inked: rows, observations: reaching, pageHeight: h, lineHeight: line) {
                return true
            }
        }
        return false
    }

    /// The whole-page observations, with every band observation that adds a line
    /// the page does not already have, less any fused box those lines replace.
    ///
    /// - **Whole-page observations are kept**, in their order, with one exception:
    ///   a box of `hasFusedLine`'s shape (over 1.4 line heights tall, over eight
    ///   wide) that the kept lines, one of them a band's, read as two lines or
    ///   more (`replaces` has the rule). Vision fuses two
    ///   lines into one garbled box, at any confidence; on C33's `Briefer` p3 four
    ///   such boxes (`WOMEN IN HICHER LAbOr, aahizrn…`, 1.8–2.7 line heights) hid
    ///   seven lines the bands had read cleanly, and PDFKit printed the junk.
    ///   Each one is put back unless the lines that replace it were admitted.
    /// - **A band observation is admitted only at full confidence.** On C30's
    ///   document 150 of the 151 band lines this merge added read 1.0, and the
    ///   one at 0.5 was garbled (`the comnane or the mimhor nf`), as was every
    ///   junk read found while building it. A band read is a supplement, so the
    ///   bar for it is higher than for the page's own; `settings.confidence`
    ///   has already been applied to both.
    /// - **One touching an interior band edge is dropped** (`seamMargin`). Its line
    ///   was cut, and the overlap guarantees a neighbouring band holds it clear.
    /// - **One taller than two line heights is dropped.** The plan guarantees only
    ///   lines up to that height lie whole in a band, so a taller box is cut or is
    ///   several lines read as one: on C30's page 5 a band returned a 201-px box
    ///   on a 48-px line reading `no industral angering derange`, over three real
    ///   lines. Taller type is left to the whole-page request, which reads large
    ///   type well; C30's losses were body text.
    /// - **One is dropped when kept boxes cover half of its middle half** — the
    ///   rows between a quarter and three quarters of its height. The same line
    ///   read again fills that strip, and so does a junk box spanning lines the
    ///   page already has (C30's page 1: `Can Lat`, 152 px over three lines). A
    ///   *different* line does not: its neighbours' boxes reach only its top and
    ///   bottom edges. On that page, where boxes are 72–88 px on a 55-px pitch, a
    ///   test over the whole box read 57% for the real line `Prepared by Mildred
    ///   Strunk…` and dropped it; its middle half reads 14%.
    /// - **And one is dropped when any kept box on the same line overlaps it
    ///   sideways by over a tenth of the narrower box's width** — "on the same
    ///   line" meaning the kept box's vertical centre falls in its middle half,
    ///   which a neighbouring line's never does. Not at all, as it was: on C33's
    ///   `Briefer` p3 the fragment `Women's Bureau,` reached 17 px (5% of its
    ///   width) into the box of `WOMEN IN HIGHER-LEVEL POSITIONS. Bulletin No.
    ///   236.`, the rest of its own line, and refused it. A tenth, because one
    ///   shared word is more than that on any fragment a few words long, so a
    ///   band's line still does not repeat a fragment the page kept, however the
    ///   two readings split or spell it (`witbin` against `within`): the
    ///   whole-page reading wins, and the rest of that line is left to the
    ///   unread stretches below. Kept boxes taller than two line heights are left out of this test,
    ///   so a narrow junk box of the page's own (a one-word `ASSAME` 115 px tall)
    ///   does not veto the lines it crosses. A tall kept box that covers half a
    ///   band line's middle still refuses it through the cover test above, which
    ///   is what keeps out a band's copy of part of a tall heading; so a narrow
    ///   or unreplaced junk box hides the lines under it, as it did before bands.
    ///
    /// Kept band observations join the set compared against, so two bands reading
    /// one line in their overlap add it once. Each band's observations are taken
    /// **ordinary-height boxes first, largest first within each tier** (see the
    /// sort below), so a band's whole line is kept before a fragment of it or a
    /// fused box across it, and those are the ones refused.
    ///
    /// **Unread stretches** (C33). What neither reading covers is reported to
    /// `unread`: the stretches that keep a fused box from being replaced
    /// (`replaces`), and the part of a refused band line that runs more than two
    /// line heights (a word) past every kept box on its line, over ink, into rows
    /// nothing covers. Both are the rest
    /// of a line beside a fragment the page kept; the band's copy cannot be
    /// admitted, because it repeats the fragment's words. `recognisePage`
    /// recognises each stretch alone and merges again with the reads as bands.
    ///
    /// **Order.** An added line goes in after the lowest line above it in its own
    /// column — the lowest kept line above it that it overlaps sideways, and after the
    /// rest of that line's row — so the text layer reads down each column rather than
    /// across them. With no such line it goes before the first whole-page line lower
    /// than itself. A line on its own row that follows it there, to its right (to its
    /// left in Arabic or Hebrew), is never above it however high its box starts, and it
    /// goes before that line. The rest of a line goes straight after the fragment it
    /// continues on that line.
    static func mergeBands(
        whole: [SearchableWriter.Observation],
        bands: [(observations: [SearchableWriter.Observation], top: Int, bottom: Int)],
        pageHeight h: Int,
        lineHeight given: Int? = nil,
        /// For `hasFusedLine`'s width test; a square page when not given.
        pageWidth: Int? = nil,
        /// Whether a normalised stretch of the page holds ink, for `replaces`.
        hasInk: ((SearchableWriter.BoundingBox) -> Bool)? = nil,
        /// Told each stretch of a line that holds text no kept box reads, for
        /// `recognisePage` to recognise on its own (see "Unread stretches" above).
        unread: ((SearchableWriter.BoundingBox) -> Void)? = nil,
        /// The stretches `unread` reported, once they have been read: an added line
        /// centred in one is the rest of a line, and is ordered as one.
        continuing: [SearchableWriter.BoundingBox] = []
    ) -> [SearchableWriter.Observation] {
        guard h > 0 else { return whole }
        let line = given ?? lineHeight(of: whole, pageHeight: h)
        let margin = Double(seamMargin(lineHeight: line))
        let tallest = 2 * Double(line) / Double(h)
        // Every band observation that may be admitted, lifted into the page's frame,
        // in the order they are tried.
        var candidates: [SearchableWriter.Observation] = []
        var seen: [SearchableWriter.BoundingBox] = []
        for band in bands {
            let bandHeight = Double(band.bottom - band.top)
            guard bandHeight > 0 else { continue }
            // Two tiers, each largest first: boxes of ordinary height for this band,
            // then the ones more than a third taller than its median, which are
            // where Vision fuses two lines into one (C30's page 1: 118- and 129-px
            // boxes of garbled text among 85-px lines, all at full confidence). The
            // real lines are kept first and refuse the fused box that crosses them.
            let heights = band.observations.map(\.boundingBox.height)
                .filter { $0.isFinite && $0 > 0 }.sorted()
            let usual = heights.isEmpty ? 0 : heights[heights.count / 2] * 4 / 3
            let ordered = band.observations.sorted {
                let (a, b) = ($0.boundingBox, $1.boundingBox)
                let (aTall, bTall) = (a.height > usual, b.height > usual)
                if aTall != bTall { return !aTall }
                return a.width * a.height > b.width * b.height
            }
            for o in ordered {
                let top = o.boundingBox.y * bandHeight
                let bottom = (o.boundingBox.y + o.boundingBox.height) * bandHeight
                guard top.isFinite, bottom.isFinite, o.boundingBox.x.isFinite,
                      o.boundingBox.width.isFinite, o.boundingBox.width > 0, bottom > top,
                      !o.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                let box = SearchableWriter.BoundingBox(
                    x: o.boundingBox.x,
                    y: (Double(band.top) + top) / Double(h),
                    width: o.boundingBox.width,
                    height: (bottom - top) / Double(h))
                // Whatever a band saw of ordinary height, at any confidence and cut
                // or not, is evidence of text for `replaces`.
                if bottom - top <= 1.4 * Double(line) { seen.append(box) }
                guard o.confidence >= 1 else { continue }
                if band.top > 0, top < margin { continue }
                if band.bottom < h, bottom > bandHeight - margin { continue }
                if bottom - top > 2 * Double(line) { continue }
                candidates.append(SearchableWriter.Observation(boundingBox: box, text: o.text,
                                                               confidence: o.confidence,
                                                               quarterTurns: o.quarterTurns))
            }
        }
        /// Whether kept box `k` is on the line of the box whose middle half is `middle`.
        func sameLine(_ k: SearchableWriter.BoundingBox, _ middle: SearchableWriter.BoundingBox) -> Bool {
            let centre = k.y + k.height / 2
            return k.height <= tallest && centre >= middle.y && centre <= middle.y + middle.height
        }
        /// The candidates admitted over the page's kept boxes `base`, in order, and
        /// the refused ones that overlap a kept box on their own line.
        func admit(over base: [SearchableWriter.BoundingBox])
            -> (added: [SearchableWriter.Observation], beside: [SearchableWriter.BoundingBox]) {
            var kept = base
            var added: [SearchableWriter.Observation] = []
            var beside: [SearchableWriter.BoundingBox] = []
            for o in candidates {
                let box = o.boundingBox
                let middle = middleHalf(of: box)
                // A neighbouring line covers with its own middle half (C53): Vision's
                // boxes run past their line's ink, 94 rows over 52-row type on a 55-row
                // pitch on `Briefer` p1, so the line above reached 58% of the next line's
                // middle half and refused it, read cleanly by two bands. A kept box whose
                // centre is within half the shorter box's height of this one's is this
                // line read again, offset (16 rows on `Bird` p3), and covers with all of
                // it; so does a box over two line heights, as junk across lines did.
                let centre = box.y + box.height / 2
                let cover = kept.map { k in
                    k.height > tallest || abs(k.y + k.height / 2 - centre) < min(k.height, box.height) / 2
                        ? k : middleHalf(of: k)
                }
                guard coveredShare(of: middle, by: cover) < 0.5,
                      !kept.contains(where: { k in
                          sameLine(k, middle) && sidewaysOverlap(k, box) > min(k.width, box.width) / 10
                      })
                else {
                    if kept.contains(where: { sameLine($0, middle) && overlapsSideways($0, box) }) {
                        beside.append(box)
                    }
                    continue
                }
                kept.append(box)
                added.append(o)
            }
            return (added, beside)
        }
        // A whole-page box of `hasFusedLine`'s shape may be two lines
        // fused into one reading (C33). Try the merge without all of them, then put
        // back each one the result does not replace, until none needs putting back.
        var displaced = Set(whole.indices.filter {
            hasFusedLine([whole[$0]], pageWidth: pageWidth ?? h, pageHeight: h, lineHeight: line)
        })
        var added: [SearchableWriter.Observation] = []
        var beside: [SearchableWriter.BoundingBox] = []
        // Each with the whole-page box whose replacement it blocked, if any.
        var stretches: [(box: SearchableWriter.BoundingBox, blocked: Int?)] = []
        // Half a line height across: about one character.
        let minimumWord = 0.5 * Double(line) / Double(pageWidth ?? h)
        while true {
            let base = whole.indices.filter { !displaced.contains($0) }.map { whole[$0].boundingBox }
            (added, beside) = admit(over: base)
            let restore = displaced.filter { i in
                !replaces(whole[i].boundingBox,
                          with: base + added.map(\.boundingBox),
                          added: added.map(\.boundingBox), seen: seen,
                          lineHeight: Double(line) / Double(h),
                          minimumWord: minimumWord,
                          hasInk: hasInk,
                          unread: unread == nil ? nil : { stretches.append(($0, i)) })
            }
            if restore.isEmpty { break }
            displaced.subtract(restore)
        }
        let page = whole.indices.filter { !displaced.contains($0) }.map { whole[$0] }
        if let unread {
            // A band line refused beside a fragment the page kept on its line, where
            // it runs past every kept box on that line by more than a word, into rows
            // no kept box covers (C33's `Leland` p2: `Effects of Fair Employment
            // Legislation in the` kept, and the band's `…in the States and
            // Municipalities,` refused by the cover test, the fragment being 65% of
            // it). Covered rows are a fused box's, and `replaces` reports those.
            let kept = page.map(\.boundingBox) + added.map(\.boundingBox)
            let word = 2 * Double(line) / Double(pageWidth ?? h)
            for box in beside {
                let middle = middleHalf(of: box)
                let spans = kept.filter { sameLine($0, middle) && overlapsSideways($0, box) }
                    .map { (max($0.x, box.x), min($0.x + $0.width, box.x + box.width)) }
                    .sorted { $0.0 < $1.0 }
                var reach = box.x
                var open: [(Double, Double)] = []
                for (from, to) in spans + [(box.x + box.width, box.x + box.width)] {
                    if from - reach > word { open.append((reach, from)) }
                    reach = max(reach, to)
                }
                for (from, to) in open {
                    let stretch = SearchableWriter.BoundingBox(x: from, y: box.y,
                                                               width: to - from, height: box.height)
                    if hasInk.map({ $0(middleHalf(of: stretch)) }) ?? true { stretches.append((stretch, nil)) }
                }
            }
            // And beside any kept line, over ink, out to where the lines above and below
            // it reach (C53): on `Briefer` p3 every band read `378 pages. $8.50. A
            // comprehensive review…` and the line under it as one box at 0.3, which is
            // never a candidate, so no refused line stood beside the kept `378 pages.
            // $8.50.` to report the rest.
            let pitch = 1.5 * Double(line) / Double(h)
            for box in kept where box.height <= tallest {
                let middle = middleHalf(of: box)
                let centre = box.y + box.height / 2
                let near = kept.filter {
                    $0.height <= tallest && !sameLine($0, middle) && overlapsSideways($0, box)
                        && abs($0.y + $0.height / 2 - centre) <= pitch
                }
                guard let left = near.map(\.x).min(),
                      let right = near.map({ $0.x + $0.width }).max() else { continue }
                let (from, to) = (min(left, box.x), max(right, box.x + box.width))
                // Stopped by any kept box reaching this line's middle rows, not only one
                // on its line: a newspaper's next column sets its lines off this one's.
                let spans = kept.filter {
                    min($0.y + $0.height, middle.y + middle.height) > max($0.y, middle.y)
                }
                    .map { (max($0.x, from), min($0.x + $0.width, to)) }
                    .filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
                var reach = from
                for (a, b) in spans + [(to, to)] {
                    if a - reach > word {
                        let stretch = SearchableWriter.BoundingBox(x: reach, y: box.y,
                                                                   width: a - reach, height: box.height)
                        if hasInk.map({ $0(middleHalf(of: stretch)) }) ?? false {
                            stretches.append((stretch, nil))
                        }
                    }
                    reach = max(reach, b)
                }
            }
            // Only what the final kept set leaves open, other than the box a stretch
            // kept in place: the restore loop's first round judges the page with every
            // fused box out, so it can report a gap that a box put back later covers
            // (the review of this change). Largest first, and once each, so two bands
            // reading one line in their overlap report it once, and a small stretch
            // inside a larger one does not refuse the larger one's reading.
            var reported: [SearchableWriter.BoundingBox] = []
            let open = stretches.filter { s in
                let others = whole.indices.filter { !displaced.contains($0) && $0 != s.blocked }
                    .map { whole[$0].boundingBox }
                return coveredShare(of: middleHalf(of: s.box), by: others + added.map(\.boundingBox)) < 0.5
            }.map(\.box).sorted { $0.width * $0.height > $1.width * $1.height }
            for s in open where !reported.contains(where: {
                coveredShare(of: middleHalf(of: s), by: [$0]) >= 0.5
            }) {
                reported.append(s)
                unread(s)
            }
        }
        guard !added.isEmpty else { return page }

        // Each added line's anchor: the index in `page` it goes after, or nil for
        // "before the first whole-page line lower than it". Chosen against the
        // whole-page lines only, and added lines sharing an anchor keep their order
        // down the page, so a run of recovered lines in one column stays together.
        //
        // The rest of a line goes after the fragment it continues instead: the
        // nearest box on its line to its left, a page box or an added one, ending
        // under a line height short of it. (C33: `1950.`, `86 pages.`, `25 cents.
        // Avail-` after `United States Department of Labor, Washington, D. C.,` on
        // `Briefer` p3.) The rest of a line means a read centred in one of the
        // `continuing` stretches, or one that some band read as a single line with
        // that fragment; not any box beside it, because a narrow gutter is under a
        // line height too, and a column the bands recovered would be threaded row by
        // row into its neighbour's (the review of this change). Vision does not read
        // across a gutter as one line. Every list below holds indices into `sortedAdded`.
        let sortedAdded = added.sorted { $0.boundingBox.y < $1.boundingBox.y }
        var after: [Int: [Int]] = [:]
        var follow: [Int: [Int]] = [:]
        var loose: [Int] = []
        let lineWidth = Double(line) / Double(pageWidth ?? h)
        func continues(_ a: SearchableWriter.BoundingBox, _ o: SearchableWriter.BoundingBox) -> Bool {
            let gap = -sidewaysOverlap(o, a)
            let middle = middleHalf(of: a)
            guard sameLine(o, middle), o.x < a.x, gap > -lineWidth, gap < lineWidth else { return false }
            let (x, y) = (a.x + a.width / 2, a.y + a.height / 2)
            return continuing.contains { x >= $0.x && x <= $0.x + $0.width && y >= $0.y && y <= $0.y + $0.height }
                || seen.contains { s in
                    sameLine(s, middle) && sidewaysOverlap(s, o) > o.width / 2
                        && sidewaysOverlap(s, a) > a.width / 2
                }
        }
        /// Whether page line `o` stands on added line `a`'s row after it, in the row's reading
        /// direction, which both their texts decide: a fragment of digits on a Hebrew row has
        /// no letters to say so (the second review of this change).
        func follows(_ o: SearchableWriter.Observation, _ a: SearchableWriter.Observation) -> Bool {
            onOneRow(o.boundingBox, a.boundingBox)
                && (readsRightToLeft(a.text + " " + o.text) ? o.boundingBox.x < a.boundingBox.x
                                                            : o.boundingBox.x > a.boundingBox.x)
        }
        for (n, a) in sortedAdded.enumerated() {
            let pagePrior = page.indices.filter { continues(a.boundingBox, page[$0].boundingBox) }
                .max { page[$0].boundingBox.x < page[$1].boundingBox.x }
            let addedPrior = sortedAdded.indices
                .filter { continues(a.boundingBox, sortedAdded[$0].boundingBox) }
                .max { sortedAdded[$0].boundingBox.x < sortedAdded[$1].boundingBox.x }
            if let j = addedPrior,
               pagePrior.map({ page[$0].boundingBox.x < sortedAdded[j].boundingBox.x }) ?? true {
                follow[j, default: []].append(n)
                continue
            }
            if let i = pagePrior { after[i, default: []].append(n); continue }
            // A line that follows this one on its row is beside it, not above it, however
            // much higher its box starts (C53): on `Briefer` p3 the shifted bands added
            // `WOMEN IN HIGHER-LEVEL POSITIONS. Bulletin No. 236.` after the first pass
            // had kept the rest of its line, `Women's Bureau,`, in a box starting 14 rows
            // higher, and the head went in after its own tail.
            var anchor: Int?
            for (i, o) in page.enumerated()
            where o.boundingBox.y < a.boundingBox.y && overlapsSideways(o.boundingBox, a.boundingBox)
                && !follows(o, a) {
                if anchor.map({ page[$0].boundingBox.y < o.boundingBox.y }) ?? true { anchor = i }
            }
            guard var anchor else { loose.append(n); continue }
            // And after the rest of the anchor's line above it, whose own tail may start
            // higher than the anchor (the review of this change). Not past the next column's
            // line on that row, nor onto a box centred lower than this one's top quarter,
            // which is on this one's row or under it (the second review).
            while anchor + 1 < page.count,
                  onOneRow(page[anchor + 1].boundingBox, page[anchor].boundingBox),
                  overlapsSideways(page[anchor + 1].boundingBox, a.boundingBox),
                  page[anchor + 1].boundingBox.y + page[anchor + 1].boundingBox.height / 2
                      < a.boundingBox.y + a.boundingBox.height / 4 {
                anchor += 1
            }
            after[anchor, default: []].append(n)
        }
        var out: [SearchableWriter.Observation] = []
        /// An added line, then whatever continues it on its line, left to right.
        /// `continues` asks for a box strictly to the left, so this cannot cycle.
        func emit(_ n: Int) {
            out.append(sortedAdded[n])
            (follow[n] ?? []).sorted { sortedAdded[$0].boundingBox.x < sortedAdded[$1].boundingBox.x }
                .forEach(emit)
        }
        var pending = loose
        for (i, o) in page.enumerated() {
            // Before the first page line lower than it, or before one that follows it on
            // its row: a head with no line above it at all, a page's first (C53). Every one
            // that is due, in order, since a later one can follow `o` when an earlier does not.
            let due = pending.filter {
                sortedAdded[$0].boundingBox.y < o.boundingBox.y || follows(o, sortedAdded[$0])
            }
            due.forEach(emit)
            pending.removeAll { due.contains($0) }
            out.append(o)
            (after[i] ?? []).forEach(emit)
        }
        pending.forEach(emit)
        return out
    }

    /// Whether two boxes stand on one row of text: each one's vertical centre falls in
    /// the other's middle half.
    static func onOneRow(_ a: SearchableWriter.BoundingBox, _ b: SearchableWriter.BoundingBox) -> Bool {
        func centred(_ p: SearchableWriter.BoundingBox, in q: SearchableWriter.BoundingBox) -> Bool {
            let centre = p.y + p.height / 2
            let middle = middleHalf(of: q)
            return centre >= middle.y && centre <= middle.y + middle.height
        }
        return centred(a, in: b) && centred(b, in: a)
    }

    /// Whether the boxes in `kept` read the rows of the whole-page box `fused` as
    /// two lines or more, with at least one of them a band's (`added`), spanning
    /// 80% of its width between them, and leaving no text unread inside it. Then
    /// `fused` is two lines Vision read as one, and the kept boxes are the better
    /// reading of it.
    ///
    /// A box's line is where its vertical centre falls, taken within the middle
    /// 80% of `fused`'s rows so a neighbouring line just touching it does not
    /// count; a centre half a line height below a line's first starts a new one.
    /// A tall heading read correctly has one line in it.
    ///
    /// **Unread** means ink on the page (`hasInk`, over the middle half of the
    /// rows), or a box a band saw of ordinary height at any confidence, cut at a
    /// seam or not (`seen`), in either of two places: the stretch of a line's
    /// width its kept boxes leave open, wider than `minimumWord`; or rows of
    /// `fused`, half a line or more, that no line reaches — the middle line of
    /// three (the second review of C33's draft).
    ///
    /// **The unread test, not a width per line.** The review of C33's first draft
    /// found the width pooled across lines, so one full line and any fragment of
    /// the other passed, and the rest of the second line went with the junk box
    /// unread: on `Leland` pp6 and 16 the ink test finds type in the half-line that
    /// draft dropped. A width per line cannot tell that from the short last line
    /// of a paragraph (30–45% of the box on the same pages); whether anything is
    /// there can.
    static func replaces(_ fused: SearchableWriter.BoundingBox,
                         with kept: [SearchableWriter.BoundingBox],
                         added: [SearchableWriter.BoundingBox],
                         seen: [SearchableWriter.BoundingBox] = [],
                         lineHeight line: Double,
                         minimumWord: Double = 0.02,
                         hasInk: ((SearchableWriter.BoundingBox) -> Bool)? = nil,
                         /// Given, every unread stretch is reported, not only the first.
                         unread report: ((SearchableWriter.BoundingBox) -> Void)? = nil) -> Bool {
        let top = fused.y + fused.height * 0.1, bottom = fused.y + fused.height * 0.9
        func inside(_ b: SearchableWriter.BoundingBox) -> Bool {
            let centre = b.y + b.height / 2
            return b.height < fused.height && centre >= top && centre <= bottom
                && overlapsSideways(b, fused)
        }
        guard added.contains(where: inside) else { return false }
        /// The stretches of `fused`'s width that `boxes` leave open.
        func gaps(_ boxes: [SearchableWriter.BoundingBox]) -> [(from: Double, to: Double)] {
            let spans = boxes.map { (max($0.x, fused.x), min($0.x + $0.width, fused.x + fused.width)) }
                .sorted { $0.0 < $1.0 }
            var out: [(from: Double, to: Double)] = []
            var reach = fused.x
            for (from, to) in spans where to > reach {
                if from > reach { out.append((reach, from)) }
                reach = to
            }
            if reach < fused.x + fused.width { out.append((reach, fused.x + fused.width)) }
            return out
        }
        func span(_ boxes: [SearchableWriter.BoundingBox]) -> Double {
            fused.width - gaps(boxes).reduce(0) { $0 + $1.to - $1.from }
        }
        let within = kept.filter(inside).sorted { $0.y + $0.height / 2 < $1.y + $1.height / 2 }
        var lines: [[SearchableWriter.BoundingBox]] = []
        var first = -Double.infinity
        for b in within {
            let centre = b.y + b.height / 2
            if lines.isEmpty || centre - first >= line / 2 {
                lines.append([b])
                first = centre
            } else {
                lines[lines.count - 1].append(b)
            }
        }
        guard lines.count >= 2, span(within) >= 0.8 * fused.width else { return false }
        /// Whether anything shows text in `open` stretches of the rows `top..<bottom`.
        func unread(top: Double, bottom: Double, open: [(from: Double, to: Double)]) -> Bool {
            guard !open.isEmpty, bottom > top else { return false }
            // The middle half of the rows, clear of the neighbouring lines' glyphs.
            let quarter = (bottom - top) / 4
            if let hasInk, open.contains(where: {
                hasInk(SearchableWriter.BoundingBox(x: $0.from, y: top + quarter,
                                                    width: $0.to - $0.from, height: 2 * quarter))
            }) { return true }
            return seen.contains { s in
                let centre = s.y + s.height / 2
                guard centre >= top, centre <= bottom else { return false }
                // A band's re-reading of a kept line, which spans it and the gap
                // beside it alike, says nothing about the gap.
                let rereads = within.contains { k in
                    centre >= k.y && centre <= k.y + k.height
                        && sidewaysOverlap(k, s) > s.width / 2
                }
                if rereads { return false }
                return open.contains { min($0.to, s.x + s.width) - max($0.from, s.x) > minimumWord }
            }
        }
        var blocked = false
        /// Whether `open` stretches of the rows `top..<bottom` are unread, reporting
        /// each one that is when asked to.
        func check(top: Double, bottom: Double, open: [(from: Double, to: Double)]) -> Bool {
            guard let report else { return unread(top: top, bottom: bottom, open: open) }
            for stretch in open where unread(top: top, bottom: bottom, open: [stretch]) {
                report(SearchableWriter.BoundingBox(x: stretch.from, y: top,
                                                    width: stretch.to - stretch.from,
                                                    height: bottom - top))
                blocked = true
            }
            return false
        }
        // Beside each line, where its kept boxes do not reach.
        for row in lines {
            let rowTop = row.map(\.y).min() ?? 0
            let rowBottom = row.map { $0.y + $0.height }.max() ?? 0
            if check(top: rowTop, bottom: rowBottom,
                     open: gaps(row).filter { $0.to - $0.from > minimumWord }) { return false }
        }
        // And across rows of `fused` no line reaches, half a line or more.
        let reached = lines.map { row in
            (row.map(\.y).min() ?? 0, row.map { $0.y + $0.height }.max() ?? 0)
        }.sorted { $0.0 < $1.0 }
        var reach = top
        for (from, to) in reached + [(bottom, bottom)] {
            if from - reach >= line / 2,
               check(top: reach, bottom: from, open: [(fused.x, fused.x + fused.width)]) {
                return false
            }
            reach = max(reach, to)
        }
        return !blocked
    }

    /// Whether two boxes share any horizontal extent.
    static func overlapsSideways(_ a: SearchableWriter.BoundingBox,
                                 _ b: SearchableWriter.BoundingBox) -> Bool {
        sidewaysOverlap(a, b) > 0
    }

    /// How much horizontal extent two boxes share, or a negative gap between them.
    static func sidewaysOverlap(_ a: SearchableWriter.BoundingBox,
                                _ b: SearchableWriter.BoundingBox) -> Double {
        min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
    }

    /// The rows of a box between a quarter and three quarters of its height.
    static func middleHalf(of box: SearchableWriter.BoundingBox) -> SearchableWriter.BoundingBox {
        SearchableWriter.BoundingBox(x: box.x, y: box.y + box.height / 4,
                                     width: box.width, height: box.height / 2)
    }

    /// How much of `box` the `others` cover between them, as a fraction of its
    /// area: the sum of the pairwise intersections, capped at 1. The sum
    /// over-counts where the others overlap each other, which errs toward
    /// refusing a band line, never toward printing one twice.
    static func coveredShare(of box: SearchableWriter.BoundingBox,
                             by others: [SearchableWriter.BoundingBox]) -> Double {
        let area = box.width * box.height
        guard area > 0 else { return 0 }
        var shared = 0.0
        for b in others {
            let wide = min(box.x + box.width, b.x + b.width) - max(box.x, b.x)
            let high = min(box.y + box.height, b.y + b.height) - max(box.y, b.y)
            if wide > 0, high > 0 { shared += wide * high }
        }
        return min(1, shared / area)
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
    /// never fire on anything.
    ///
    /// **It has to cover the *first* page**, which is the longest this can wait
    /// with nothing having arrived, and that is the arithmetic R44 got wrong at
    /// 300s. Measured on this corpus, recognition costs roughly 0.36s per
    /// megapixel — a 4.9 MP book page in 1.77s — and
    /// `Flattener.maximumPageMegapixels` lets a **400 MP** page through, so the
    /// worst legitimate first page is on the order of 144s. 300s left a factor of
    /// two against an estimate taken from ordinary book pages. A raised 1-bit page
    /// (C39) is read twice, itself and a copy at least `Flattener.minimumMaskRaise`
    /// coarser (up to 278 MP), so at most about 678 MP: 244s at that rate, and about
    /// 610s at the 0.9s per megapixel a dense newspaper page costs (C39's Raskin).
    ///
    /// The two errors are not symmetric, which is why this is generous rather
    /// than tight. Too long costs only later detection of a genuinely wedged
    /// helper, and cancelling interrupts the wait anyway. Too short throws away a
    /// page that was working and sends the whole document round again in-process.
    static let helperStallSeconds = 900.0

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
            // The helper recognises bitmaps and never sees a PDF's object graph, so
            // carrying annotations is not its business — and the helper's argument list
            // is the app's contract with it, so a setting that cannot reach it is
            // written false rather than threaded through.
            preserveAnnotations: false,
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
    /// The helper's exit codes, in the file the helper and the app **both**
    /// compile — which is R40's whole design, and the reason this is here rather
    /// than in `Helper/main.swift` where it used to live alone.
    ///
    /// A13.4: the app reported a signal death as "it exited with code 11", and 11
    /// is not one of these, so the single number in the message pointed the
    /// reader at a list that could not contain it. Knowing the list is what lets
    /// the message tell the two apart.
    enum HelperExit: Int32 {
        case badArguments = 2
        case unreadableManifest = 3
        case unreadablePage = 4
        case recognitionFailed = 5
        case cannotWrite = 6
    }

    enum HelperFailure: LocalizedError {
        case unusablePaths
        case unusableSettings
        case couldNotStart(String)
        case stalled
        case exited(Int32, String, bySignal: Bool = false)
        case incomplete(page: Int, of: Int)
        case unreadableResult(Int)

        var errorDescription: String? {
            switch self {
            case .unusablePaths:
                return "a page image's path contains a newline"
            case .unusableSettings:
                return "Languages or Custom words contains a NUL character, which "
                    + "cannot be passed to another process"
            case .couldNotStart(let why): return "it would not start: \(why)"
            case .stalled: return "it stopped responding"
            case .exited(let code, let detail, let bySignal):
                // A13.4. A child killed by a signal reports `terminationStatus`
                // as the **signal number**, and "it exited with code 11" sends
                // the reader to the helper's `HelperExit` list, which stops at 6
                // and cannot contain an 11 — the one number in the message is a
                // lie about where to look.
                //
                // From `Process.terminationReason`, not from the number: an
                // earlier version of this guessed, on the grounds that a small
                // code not in `HelperExit` must be a signal. The suite has a
                // fixture whose helper genuinely exits 7, and the guess called it
                // a signal. Two different facts, and only one of them is knowable
                // by arithmetic.
                return (bySignal ? "it was killed by signal \(code)"
                                 : "it exited with code \(code)")
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
        //
        // A13.3: `.newlines`, not `"\n"`. A path *ending* in CR passed the old
        // check, and in the joined manifest that CR merges with the separator into
        // one Swift `Character` (`"\r\n"`), so the helper's `split(separator: "\n")`
        // does not split there — 3 paths sent, 2 lines parsed. No content was lost,
        // because the merged line names no file, the helper exits 4 and the app
        // falls back — but it was the *count* check that saved it and not this
        // guard, and this guard's own comment says it exists for the future in
        // which something hands the pipeline a page image named by the user.
        guard !images.contains(where: {
            $0.path.rangeOfCharacter(from: .newlines) != nil
        }) else {
            throw HelperFailure.unusablePaths
        }

        // A13.1. `Process.arguments` goes through `fileSystemRepresentation`, which
        // raises **`NSInvalidArgumentException`** for a string containing U+0000.
        // An Objective-C exception is not a Swift error, so the `do/catch` around
        // `process.run()` below does not catch it: SIGABRT, exit 134, the whole app
        // gone — and `report` is never called, so `makeSearchablePDF`'s "the report
        // callback is called exactly once per file" is broken too.
        //
        // **The asymmetry is exact and it is why this is worth a guard rather than a
        // note**: the same snapshot recognises perfectly *in-process*, and
        // `useHelper` is `helperIsWorthIt`, so a one-file batch works and a two-file
        // batch kills the app. It also persists — `UserDefaults` round-trips the
        // NUL — so every multi-file batch aborts until the user finds and clears an
        // invisible character in a text field.
        //
        // Fuzzed 16 candidates in child processes: **only NUL does this.** U+0085,
        // U+2028, U+FFFF, a bare CR, ZWJ emoji, an RTL override and 256 KB
        // arguments all launch; a ≥1 MB list gives a *catchable* Swift error that
        // correctly falls back.
        //
        // §4b makes it a single-site fix: of five `Process.arguments` in `Sources/`,
        // the other four carry only paths and constants — and A4.3's password fix
        // incidentally removed the second free-text exposure. Falling back is the
        // right answer rather than sanitising the value, because a NUL in a
        // languages list is not a recognition setting the user meant, and
        // in-process recognition honours the same snapshot without launching
        // anything.
        guard !settings.languages.utf8.contains(0),
              !settings.customWords.utf8.contains(0) else {
            throw HelperFailure.unusableSettings
        }

        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("visionocr-recognise-\(UUID().uuidString)")
        let results = dir.appendingPathComponent("out")
        // **Above** the `createDirectory`, not below it (A4.5). As written, a throw
        // from `createDirectory` left `dir` behind — it can fail after creating the
        // parent and before creating `out` — and what survives in there for an
        // encrypted source is qpdf's stream dump, i.e. the document's content
        // *decrypted*, in a file named after the document. The other two scratch
        // roots in this codebase already order these correctly.
        defer { try? fm.removeItem(at: dir) }
        do {
            try fm.createDirectory(at: results, withIntermediateDirectories: true)
        } catch {
            throw HelperFailure.couldNotStart(error.localizedDescription)
        }

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
                                       lastLine(of: diagnostics),
                                       bySignal: process.terminationReason == .uncaughtSignal)
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
