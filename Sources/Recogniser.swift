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
                guard let image = loadImage(at: item.image) else {
                    throw Failure.unreadablePage(item.page)
                }
                byPage[item.page] = try recognisePage(image, settings: settings,
                                                      isCancelled: isCancelled)
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
            byPage[index + 1] = try recognisePage(image, settings: settings,
                                                  isCancelled: isCancelled)
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
    static func recognisePage(_ image: CGImage, settings: Prefs.Snapshot,
                              isCancelled: () -> Bool = { false })
        throws -> [SearchableWriter.Observation] {
        let whole = try recognise(image, settings: settings)
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
            guard hasVoid(inkedStrips: inked, observations: merged, pageHeight: h,
                          lineHeight: line)
                    || hasFusedLine(merged, pageWidth: w, pageHeight: h, lineHeight: line)
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
                      let read = try? recognise(crop, settings: local)
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
        var pieces: [(observations: [SearchableWriter.Observation], top: Int, bottom: Int)] = []
        for s in last.stretches {
            if isCancelled() { return merged }
            guard let rect = stretchCrop(s, pageWidth: w, pageHeight: h, lineHeight: line)
            else { continue }
            var local = settings
            local.minTextHeight = min(1, settings.minTextHeight * Double(h) / Double(rect.bottom - rect.top))
            guard let crop = image.cropping(to: CGRect(x: rect.left, y: rect.top,
                                                       width: rect.right - rect.left,
                                                       height: rect.bottom - rect.top)),
                  let read = try? recognise(crop, settings: local)
            else { continue }
            pieces.append(stretchPiece(read, of: s, crop: rect, pageWidth: w, pageHeight: h))
        }
        guard !pieces.isEmpty else { return merged }
        return mergeBands(whole: last.input, bands: last.bands + pieces, pageHeight: h,
                          lineHeight: line, pageWidth: w,
                          hasInk: { hasInk(in: $0, of: image, level: scan.level) },
                          continuing: last.stretches)
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
                text: $0.text, confidence: $0.confidence)
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
        var ink = 0
        for y in 0..<h {
            if covered[y] { ink = 0; continue }
            if inked[y] { ink += 1; if ink >= need { return true } }
        }
        return false
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
    /// column — the lowest kept line above it that it overlaps sideways — so the
    /// text layer reads down each column rather than across them. With no such
    /// line it goes before the first whole-page line lower than itself. The rest
    /// of a line goes straight after the fragment it continues on that line.
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
                                                               confidence: o.confidence))
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
                guard coveredShare(of: middle, by: kept) < 0.5,
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
            var anchor: Int?
            for (i, o) in page.enumerated()
            where o.boundingBox.y < a.boundingBox.y && overlapsSideways(o.boundingBox, a.boundingBox) {
                if anchor.map({ page[$0].boundingBox.y < o.boundingBox.y }) ?? true { anchor = i }
            }
            if let anchor { after[anchor, default: []].append(n) } else { loose.append(n) }
        }
        var out: [SearchableWriter.Observation] = []
        /// An added line, then whatever continues it on its line, left to right.
        /// `continues` asks for a box strictly to the left, so this cannot cycle.
        func emit(_ n: Int) {
            out.append(sortedAdded[n])
            (follow[n] ?? []).sorted { sortedAdded[$0].boundingBox.x < sortedAdded[$1].boundingBox.x }
                .forEach(emit)
        }
        var pending = loose[...]
        for (i, o) in page.enumerated() {
            while let next = pending.first, sortedAdded[next].boundingBox.y < o.boundingBox.y {
                emit(next)
                pending = pending.dropFirst()
            }
            out.append(o)
            (after[i] ?? []).forEach(emit)
        }
        pending.forEach(emit)
        return out
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
    /// two against an estimate taken from ordinary book pages.
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
