import AppKit
import CoreText
import Foundation
import PDFKit

/// Builds the searchable PDF ourselves, from Vision's line observations.
///
/// Why not just use `mac-ocr searchable-pdf`: its text layer positions each word
/// as its own run without emitting real space characters, so text extractors
/// have to infer word gaps from geometry and frequently miss them. Measured over
/// three pages of a 300 DPI book scan, word-level extraction accuracy against
/// the same recognition was 64% (PDFKit) and 27% (poppler). Writing one run per
/// *line*, spaces and all, sized from the line's height, gives 99.8% and 97%.
///
/// One run per line is the design, but Vision does not always give a whole line
/// — on a newspaper column it hands back fragments sitting side by side, and
/// there is no space character between two runs. `reserveEms` is what keeps
/// them from welding into one word. See C18.
///
/// Vision itself is not the problem — it returns whole lines with correct
/// spacing, which is why `mac-ocr --format text` reads perfectly.
enum SearchableWriter {

    /// Where the baseline sits inside Vision's box, as a fraction of its height
    /// measured up from the bottom.
    ///
    /// Calibrated, not derived. The sweep that produced 0.22 lived in `Tests`
    /// and no longer exists; what re-measures it now is
    /// `Tools/probe-text-offset.swift`, which slides a probe down each line to
    /// find where the text actually sits and reports the offset from the ink
    /// (0.00 = dead on it). The shipped value holds median 0.00 across the
    /// 78-document corpus, worst case 0.20. Change it and re-run that probe:
    /// this constant is what "the highlight sits on the line" means.
    static var baselineFraction: CGFloat = 0.22

    /// Fraction of the gap to a neighbouring line that a run's glyphs may occupy.
    ///
    /// **Higher means shorter glyphs**, and less chance that two runs overlap
    /// and Preview stops seeing them as separate lines — `headroom` *divides*
    /// the measured gap by this. (The prose here used to say the opposite. Fix
    /// the prose, never the code: the value is corpus-calibrated, and inverting
    /// the arithmetic to match a wrong sentence would undo the measurement
    /// below.)
    ///
    /// Measured on tightly-set archival material: raising this from 0.95 to 1.5
    /// took line-by-line selection from 80-83% to 84-91% of lines on 1920s-50s
    /// letters and typescripts, and to 100% on modern print, with no loss in
    /// line-edge coverage or word accuracy. It costs only highlight thickness,
    /// since width is set by font size and height by the vertical squash in the
    /// text matrix — the two are independent.
    static var headroomFactor: CGFloat = 1.5

    /// Space kept clear before a run's right-hand neighbour on the same line.
    ///
    /// **This is the fourth property, and it used to hold by accident.**
    /// CLAUDE.md invariant 3 names three that fight each other; this is a
    /// fourth. Vision splits one visual line of a newspaper column into
    /// fragments sitting side by side, and there is no space character between
    /// them — each is its own `CTLineDraw`. PDFKit synthesises the space from
    /// the geometric gap, and stops doing it below roughly 0.15 em.
    ///
    /// Nothing was reserving that gap. It existed because `minimumVertical`
    /// capped the font size, leaving 4-16 pt of unused slack at each run's
    /// right edge — a side effect of a constant chosen for something else
    /// entirely. Widening the runs to their true box width (which is what fixes
    /// line-end selectability) removes the slack, and adjacent words weld:
    /// "valuablestudy", "Londos,and". Measured: no characters lost, word
    /// boundaries lost, 5-18 welded pairs per newspaper page.
    ///
    /// So reserve it deliberately: a quarter of the run's own size. Measured in
    /// ems rather than points on purpose — the thresholds extractors apply are
    /// themselves proportional to the font size, so 0.25 em clears them at
    /// *every* size and no absolute floor is needed. One was tried, at 0.5, 2 and
    /// 4 pt: all three scored identically to no floor at all across 25 newspaper
    /// scans, so it is not here. A line with no right-hand neighbour on it is
    /// untouched.
    ///
    /// **0.25 was calibrated, and it is now bounded** (`RESEARCH-2026-08-16.md`).
    /// Three of the four extractors that matter are readable, and every one of
    /// them re-derives word breaks from the drawn gap:
    ///
    /// | extractor | needs at least | complains above |
    /// |---|---|---|
    /// | poppler `minWordBreakSpace` | 0.10 em | ~1.0 em, read as a column gap |
    /// | pdf.js `TRACKING_SPACE_FACTOR` | 0.102 em | 0.6 em, which breaks the span |
    /// | mupdf `SPACE_DIST` | 0.15 em | **0.30 em, where it emits _two_ spaces** |
    /// | PDFKit | unknown, and closed | unknown |
    ///
    /// So the window is **(0.15, 0.30) em** and this sits in the middle of it.
    /// Below 0.15 poppler and mupdf stop seeing a word break at all; above 0.30
    /// mupdf doubles the space. That is the derivation this constant never had.
    ///
    /// **A real space character does not remove the need for the gap**, which is
    /// the counter-intuitive part and the reason this constant cannot be retired
    /// by writing spaces: poppler consumes a `U+0020` as a word *terminator* and
    /// then discards it, re-deciding from geometry; pdf.js drops whitespace
    /// before its heuristic runs. Only mupdf honours it outright.
    static var reserveEms: CGFloat = 0.25

    /// Floor on the vertical squash in the text matrix.
    ///
    /// When a line needs a big font to span its box but the gap to its
    /// neighbours is small, `draw` has to choose. Squashing further is one
    /// answer; capping the font size is the other. This is where that line
    /// sits — below it, the size gets capped instead.
    ///
    /// **Capping the size costs width, not height.** The drawn height is
    /// `min(wanted, 3 * widthSize)` and `minimumVertical` does not appear in it:
    /// in the capping branch `size = wanted/minimumVertical` and `vertical`
    /// clamps back to exactly `minimumVertical`, so the product is `wanted` for
    /// any floor. (`reserveEms` is not quite so clean — it reduces `widthSize`,
    /// which lowers the height once `vertical` has hit its 3.0 clamp: measured,
    /// 17.081 pt to 17.037 pt. Always *shorter*, so it cannot cause overlap.)
    /// A capped run is simply narrower; a capped run is simply
    /// narrower than its box, so its last words fall outside it — which is why
    /// this was 0.5 and line-end selectability bottomed out at 71% on dense
    /// newsprint, with 72% of those misses being a run that simply stopped
    /// short. At 0.25, across the 84-document corpus: 28 documents better on
    /// line-end, 1 worse, worst case 71% -> 91%, and vertical overlap and text
    /// offset both unchanged to the digit.
    ///
    /// Lowering it alone welded adjacent words together — see `reserveEms`,
    /// which is the other half of this change and must not be removed without
    /// putting this back up. Exposed so the trade can be measured rather than
    /// argued about: `score-corpus.swift` takes it as argv[4].
    static var minimumVertical: CGFloat = 0.25

    /// A line the writer could not place, and why.
    ///
    /// The pipeline's only integrity check is page count, so a line abandoned
    /// inside `draw` would otherwise be undetectable. `compose` **returns**
    /// these rather than recording them in a static: files are OCR'd
    /// concurrently (up to `Prefs.maxConcurrency`), and a shared static was a
    /// real content-loss race — the next file's `compose` reset it before the
    /// previous file's caller had read it, so a document that lost lines was
    /// published as a success. See BUGS.md C8.
    struct Unplaced {
        let page: Int
        let text: String
        let reason: String
    }

    // MARK: - Vision's output, as mac-ocr reports it

    /// **`Encodable` as well, because the recognition helper writes these.**
    /// R40's helper process recognises a page and hands the observations back as
    /// JSON, and the app decodes them into this same type — so the two halves of
    /// that round trip are one declaration rather than two that agree today.
    /// `Codable`'s synthesis is what keeps them in step: a field added here
    /// appears on both sides or on neither.
    struct Observation: Codable {
        let boundingBox: BoundingBox
        let text: String
        let confidence: Double
    }

    /// Normalised to the page, with a top-left origin.
    struct BoundingBox: Codable {
        let x, y, width, height: Double
    }

    enum Failure: LocalizedError {
        case unreadableSource
        case unreadableObservations
        case cannotWrite

        var errorDescription: String? {
            switch self {
            case .unreadableSource: return "Could not read the page images to build the PDF."
            case .unreadableObservations: return "Could not read Vision's output."
            case .cannotWrite: return "Could not write the searchable PDF."
            }
        }
    }

    // `observations(fromJSONLines:)` and `observations(fromJSONAt:)` used to sit
    // here, and A1.3 records them as dead since recognition came in-process:
    // nothing had called either since R40, and they were divergent siblings —
    // one refused an undecodable line and an empty result, the other refused
    // neither. `Recogniser.HelperPage` is the live decoder of this shape, and
    // one decoder is the point (C20). Removed with R81; `Failure` keeps
    // `unreadableObservations`, which is part of the type's public surface and
    // reads correctly for a caller that adds a parser back.

    // MARK: - Composing

    /// Draws `visible` page by page and lays an invisible text layer over it.
    ///
    /// `visible` must be what was OCR'd, or the boxes won't line up with the ink.
    /// When `drawImages` is false, the pages carry only the invisible text and
    /// stay transparent — a layer to be merged over separately-compressed page
    /// images. `visible` is still needed, for page count and geometry.
    /// Returns the lines it could not place — empty means every line landed.
    @discardableResult
    static func compose(
        visible: URL,
        observations byPage: [Int: [Observation]],
        to destination: URL,
        drawImages: Bool = true,
        password: String? = nil,
        joinHyphenated: Bool = true,
        cropBoxes: [Int: CGRect] = [:],
        isCancelled: () -> Bool = { false },
        progress: (Int, Int) -> Void = { _, _ in }
    ) throws -> [Unplaced] {
        // Through Flattener.open, so an encrypted source is unlocked rather than
        // rendering as blank pages — which previously produced an empty-looking
        // document reported as a success.
        var skipped: [Unplaced] = []
        guard let doc = Flattener.open(visible, password: password), doc.pageCount > 0,
              let first = doc.page(at: 0) else { throw Failure.unreadableSource }

        // The published page is the **whole sheet**, not the crop.
        //
        // Observations are normalised to the crop box (that is what mac-ocr
        // renders — see Flattener.displayBox), but publishing at the crop box
        // would silently drop whatever the crop excludes. On the non-rebuild
        // path `visible` is the user's own file, so that is real content
        // disappearing from their copy with the run still reported as a success,
        // which invariant 1 forbids.
        //
        // So: page at fullBox, and the observations mapped into the sub-rectangle
        // where the crop actually lands. When a page has no crop box — 44 of the
        // 78 corpus documents, plus every rebuilt file, which carries only a
        // media box — the two coincide and this is exactly the old behaviour.
        var mediaBox = Flattener.fullBox(of: first)
        guard let pdf = CGContext(destination as CFURL, mediaBox: &mediaBox, nil) else {
            throw Failure.cannotWrite
        }

        // One face is enough: the size adapts to each line's measured width, and
        // the height is corrected separately. See draw(_:).
        let base = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let count = doc.pageCount

        for index in 0..<count {
            if isCancelled() { break }
            guard let page = doc.page(at: index) else { continue }
            let box = Flattener.fullBox(of: page)
            let pageBox = CGRect(origin: .zero, size: box.size)

            // Where the crop box lands on the published page. Derived by putting
            // the crop rect through the very transform CoreGraphics uses to draw
            // the media box, so /Rotate is handled once, by the framework, rather
            // than by hand here.
            let region = cropRegion(of: page, on: pageBox)

            // CFData, not NSValue: an NSValue here is accepted and silently
            // ignored, so every page inherited page 1's size. In a book whose
            // pages vary (456x710 against 461x725) the text layer then had the
            // wrong shape, and qpdf scaled it to fit the image layer — drifting
            // the text down by up to a full line, which is what made the first
            // line of a selection disappear.
            var mutableBox = pageBox
            let boxData = withUnsafeBytes(of: &mutableBox) { Data($0) } as CFData
            var pageInfo: [String: Any] = [kCGPDFContextMediaBox as String: boxData]

            // Carry the crop box across too, or the copy is not the same document.
            //
            // Publishing at the media box keeps every mark on the sheet (C10),
            // but writing *only* a media box drops the trim: a page the original
            // displayed at 420x250 came out displaying 612x792, revealing margin
            // notes and running heads the viewer had been hiding — and since the
            // recogniser only ever saw the crop, that newly-visible ink carries
            // no text layer. The result looked like a successful OCR of a
            // document that had suddenly grown unsearchable furniture.
            //
            // Media box for what is kept, crop box for what is shown.
            //
            // C23: `region` is derived from `visible`, and on **every rebuild
            // route** `visible` is the rebuilt copy, which carries only a media
            // box — so this wrote the media box twice and the published page
            // displayed the black scanner gutter the original hid. The caller
            // knows the source's crop and passes it in this page's own space;
            // `region` remains what the observations are normalised to, which on
            // that route is the whole sheet and must stay that way.
            //
            // Deliberately two different rectangles, because they answer two
            // questions: where the text goes, and what the reader is shown.
            let displayed = cropBoxes[index + 1] ?? region
            if displayed != pageBox {
                var cropRect = displayed
                let cropData = withUnsafeBytes(of: &cropRect) { Data($0) } as CFData
                pageInfo[kCGPDFContextCropBox as String] = cropData
            }
            pdf.beginPDFPage(pageInfo as CFDictionary)

            if drawImages, let cgPage = page.pageRef {
                // The whole sheet, drawn through the page's own transform so
                // rotation is honoured. `.mediaBox` to match the page box above:
                // drawing the crop here would put the ink somewhere the text
                // layer is not.
                pdf.saveGState()
                pdf.concatenate(cgPage.getDrawingTransform(
                    .mediaBox, rect: pageBox, rotate: 0, preserveAspectRatio: true))
                pdf.drawPDFPage(cgPage)
                pdf.restoreGState()
            }

            // The text, invisible, over the top.
            pdf.saveGState()
            pdf.setTextDrawingMode(.invisible)
            let lines = prepared(byPage[index + 1] ?? [], nextPage: byPage[index + 2] ?? [],
                                 in: region, joinHyphenated: joinHyphenated)
            for (position, observation) in lines.enumerated() {
                if let reason = draw(observation, in: region,
                                     ceiling: headroom(for: position, among: lines, in: region),
                                     rightLimit: rightLimit(for: position, among: lines,
                                                            in: region),
                                     font: base, into: pdf) {
                    skipped.append(Unplaced(page: index + 1, text: observation.text,
                                            reason: reason))
                }
            }
            pdf.restoreGState()

            pdf.endPDFPage()
            progress(index + 1, count)
        }
        pdf.closePDF()
        return skipped
    }

    /// The observations a page's text layer is actually built from: everything
    /// `compose` does to a page's raw recognition before any geometry is
    /// computed from it.
    ///
    /// Split out of `compose` for the same reason `placement` was: an instrument
    /// that measures the text layer has to start from the list the writer draws,
    /// and the alternative is a second copy of this sequence drifting out of step
    /// with it (C20). The order matters and is asserted by the suite — dedup
    /// before joining, so a line reported twice cannot be joined to its own twin.
    static func prepared(
        _ raw: [Observation],
        nextPage: [Observation] = [],
        in region: CGRect,
        joinHyphenated: Bool = true
    ) -> [Observation] {
        // A13.4: there was a `minimumConfidence` here and on `compose`, filtering
        // by a threshold `Recogniser.recognise` has already applied — a second
        // live definition of one rule, with **no shipped caller setting it**. The
        // confidence filter belongs where the confidences are produced, and now
        // it is only there. `ocrAllPages` is the same shape and is in the
        // register for it.
        func usable(_ lines: [Observation]) -> [Observation] {
            lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let lines = deduplicated(usable(raw), in: region)
        guard joinHyphenated else { return lines }
        // The next page's topmost lines, so a word carried over a page break can
        // be joined. The caller already holds them — no extra render, no extra
        // recognition.
        let next = usable(nextPage)
            .sorted { $0.boundingBox.y < $1.boundingBox.y }
            .prefix(SearchableWriter.continuationCandidates)
        return joiningHyphenatedWords(lines, in: region, continuation: Array(next))
    }

    /// One entry of a document outline, detached from PDFKit.
    ///
    /// Neutral on purpose: the Flate route hands the outline back to PDFKit, and
    /// the JBIG2 route writes it into a hand-assembled PDF by hand, so neither
    /// can depend on the other's representation.
    struct OutlineItem {
        let title: String
        /// Zero-based page in the *output*, or nil for an entry that points
        /// nowhere. Page count is 1:1 through the pipeline, so the source's
        /// index carries over unchanged.
        ///
        /// Optional because real outlines are full of pure labels — "Contents",
        /// an issue masthead — and giving those a page would fabricate a
        /// destination the author never wrote.
        let pageIndex: Int?
        /// Destination coordinates in PDF user space, each nil when the source
        /// left it unspecified.
        ///
        /// Separate optionals rather than a `CGPoint`, because "unspecified" is a
        /// real and common state that a point cannot represent. PDFKit collapses
        /// `/Fit`, `/FitH` and `/XYZ null null null` into a point whose members
        /// are `kPDFDestinationUnspecifiedValue` (3.4e38); writing that through a
        /// coordinate formatter turned every one of them into `/XYZ 0 0`, which
        /// lands the reader at the *bottom* of the page. Nil here becomes `null`
        /// in the `/XYZ` array, which means "leave this as it is".
        let left: CGFloat?
        let top: CGFloat?
        let children: [OutlineItem]
    }

    /// How deep an outline may nest before we stop descending.
    ///
    /// `convert` recurses once per level on an `OperationQueue` worker, whose
    /// stack is 512 KB — around 1,200 levels. A PDF nested deeper than that
    /// (malformed, or hostile) killed the whole process with SIGBUS, taking
    /// every *other* file in the batch down with it and publishing nothing.
    /// A stack overflow is not catchable, so the only defence is not to reach it.
    ///
    /// No real outline is anywhere near this. Deepest in the corpus is 3.
    static let maximumOutlineDepth = 32

    /// Reads a document's outline into `OutlineItem`s. Empty when there is none.
    ///
    /// Bounded in depth and in total size: an outline is navigation, and no
    /// document needs an unbounded amount of it. Losing a pathological outline
    /// costs the user nothing; crashing the batch costs them every file in it.
    static func readOutline(from source: URL, password: String? = nil) -> [OutlineItem] {
        guard let doc = Flattener.open(source, password: password),
              let root = doc.outlineRoot else { return [] }

        var budget = 20_000            // total entries, against a cyclic outline

        func convert(_ node: PDFOutline, depth: Int) -> OutlineItem? {
            guard depth < maximumOutlineDepth, budget > 0 else { return nil }
            budget -= 1
            var kids: [OutlineItem] = []
            for i in 0..<node.numberOfChildren {
                if let child = node.child(at: i), let built = convert(child, depth: depth + 1) {
                    kids.append(built)
                }
            }
            let label = node.label ?? ""
            var index: Int?
            var left: CGFloat?
            var top: CGFloat?
            if let destination = node.destination, let page = destination.page {
                // Bounded, like `copyOutline`'s mirror of this line: `index(for:)`
                // answers `NSNotFound` for a page this document does not hold, and
                // an entry pointing at page 9,223,372,036,854,775,807 is worse
                // than one pointing nowhere — nowhere is a state the type has.
                let found = doc.index(for: page)
                index = (found >= 0 && found < doc.pageCount) ? found : nil
                let p = destination.point
                // kPDFDestinationUnspecifiedValue is how PDFKit reports "the
                // source did not say" — for /Fit, /FitH and /XYZ null alike.
                let hasX = p.x.isFinite && p.x != kPDFDestinationUnspecifiedValue
                let hasY = p.y.isFinite && p.y != kPDFDestinationUnspecifiedValue
                if hasX || hasY {
                    // Through the same transform the ink goes through.
                    //
                    // The pipeline republishes each page derotated into a box at
                    // the origin, so a coordinate from the source means something
                    // different on the output: a /Rotate 180 page's heading at
                    // (72, 700) ends up at (540, 92), and on a /Rotate 90 page
                    // y=700 falls off the top of a 612-tall box entirely. Copied
                    // verbatim, the bookmark lands hundreds of points from its
                    // heading and no guard fires, because nothing is out of range.
                    if hasX && hasY {
                        let moved = mapToOutput(p, on: page)
                        left = moved.x
                        top = moved.y
                    } else {
                        // Only one member is real. Keep the output axis it
                        // actually lands on, which is not its own under a
                        // quarter turn (C21).
                        (left, top) = mapSingleAxis(hasX ? p.x : p.y,
                                                    isVertical: !hasX, on: page)
                    }
                }
            }
            // Keep entries that point nowhere. Real outlines are full of them —
            // "Contents", an issue masthead, a publisher's banner — and measured
            // across the corpus they are the majority: dropping destination-less
            // entries lost 26 of 41 on `2380659` and 21 of 27 on `Ladimeji_1974`,
            // silently re-shaping the author's outline. A title-only item is
            // valid PDF (only /Title and /Parent are required) and behaves
            // exactly as it did in the original: clicking it does nothing.
            // Keep it if it has *any* of the three things an outline entry can
            // carry. The earlier rule tested only title and children, so a
            // blank-titled entry with a real destination was dropped here while
            // copyOutline kept it — the two routes disagreeing about the same
            // document.
            guard !label.isEmpty || !kids.isEmpty || index != nil else { return nil }
            return OutlineItem(title: label, pageIndex: index,
                               left: left, top: top, children: kids)
        }

        var top: [OutlineItem] = []
        for i in 0..<root.numberOfChildren {
            if let child = root.child(at: i), let built = convert(child, depth: 0) {
                top.append(built)
            }
        }
        return top
    }

    /// Maps a point in a source page's user space to where it lands on the
    /// republished page.
    ///
    /// The published page is `fullBox` — the media box, derotated, at the origin
    /// — and the ink gets there through `getDrawingTransform(.mediaBox, …)`. A
    /// destination has to make the same journey or it no longer points at the
    /// thing it named.
    static func mapToOutput(_ point: CGPoint, on page: PDFPage) -> CGPoint {
        guard let cgPage = page.pageRef else { return point }
        let box = Flattener.fullBox(of: page)
        let transform = cgPage.getDrawingTransform(
            .mediaBox, rect: CGRect(origin: .zero, size: box.size),
            rotate: 0, preserveAspectRatio: true)
        let moved = point.applying(transform)
        // Clamp rather than emit a destination outside the page: a viewer would
        // silently ignore it, which looks identical to a bookmark that works.
        return CGPoint(x: min(max(moved.x, 0), box.width),
                       y: min(max(moved.y, 0), box.height))
    }

    /// Where a *single* specified destination coordinate lands, when the other
    /// member is unspecified.
    ///
    /// PDFKit collapses `/FitH 700` into a point whose x is
    /// `kPDFDestinationUnspecifiedValue`, and R19 measured 276 of those against
    /// 80 fully-specified across the corpus — so this is the common case, not the
    /// exotic one. Substituting 0 for the missing member and keeping `moved.y` is
    /// correct only while the transform is axis-aligned. At `/Rotate 90` and
    /// `/Rotate 270` the axes swap: `moved.y` becomes a function of the
    /// substituted zero, and the one coordinate the destination actually carried
    /// lands in `moved.x`, where it was being discarded. A `/FitH` on a
    /// 270-rotated plate came out as `/XYZ null 0 null` — the foot of the page,
    /// which is the symptom R19 fixed for the `/XYZ 0 0` case (C21).
    ///
    /// Returns whichever output axis the source axis really drives; the other is
    /// nil and stays unspecified. Under a quarter turn a `/FitH` becomes a
    /// horizontal destination, which is what the geometry means.
    static func mapSingleAxis(_ value: CGFloat, isVertical: Bool,
                              on page: PDFPage) -> (left: CGFloat?, top: CGFloat?) {
        guard let cgPage = page.pageRef else {
            return isVertical ? (nil, value) : (value, nil)
        }
        let box = Flattener.fullBox(of: page)
        let t = cgPage.getDrawingTransform(
            .mediaBox, rect: CGRect(origin: .zero, size: box.size),
            rotate: 0, preserveAspectRatio: true)
        // x' = a·x + c·y + tx,  y' = b·x + d·y + ty. So a source y contributes
        // c to x' and d to y'; a source x contributes a and b.
        let towardsX = isVertical ? t.c : t.a
        let towardsY = isVertical ? t.d : t.b
        let moved = mapToOutput(CGPoint(x: isVertical ? 0 : value,
                                        y: isVertical ? value : 0), on: page)
        return abs(towardsY) >= abs(towardsX) ? (nil, moved.y) : (moved.x, nil)
    }

    /// Copies the source document's outline onto a finished file, in place.
    ///
    /// `compose` rebuilds pages through a `CGContext`, which copies page content
    /// and nothing else, so the chapter outline an institutional repository
    /// attaches to a digitised book did not survive into the copy. For an
    /// archival pipeline that outline is a large part of what makes a scan
    /// usable.
    ///
    /// Annotations are deliberately **not** copied. They are a much larger
    /// surface — links, highlights, form fields, each with its own coordinate
    /// space to remap — and nothing downstream depends on them.
    ///
    /// CoreGraphics cannot write an outline at all, so this is a PDFKit pass over
    /// the finished file, which re-serialises it. That is the risk: the invisible
    /// text layer is the most delicate thing in this codebase. It is guarded by
    /// "the outline survives and the text layer is unharmed", which re-measures
    /// extraction and run geometry after the rewrite.
    ///
    /// Writes to `out` rather than in place, so a failed rewrite can never damage
    /// the composed file — the caller falls back to publishing that instead.
    /// Returns false if there was nothing to copy or the copy failed; losing an
    /// outline must never cost the user their OCR.
    @discardableResult
    static func copyOutline(from source: URL, of composed: URL, to out: URL,
                            password: String? = nil) -> Bool {
        guard let src = Flattener.open(source, password: password),
              let root = src.outlineRoot, root.numberOfChildren > 0,
              let dst = PDFDocument(url: composed), dst.pageCount > 0 else { return false }

        // The same two bounds `readOutline` has, for the same reason and with the
        // same numbers (R23). This is the Flate route's mirror of that function
        // and it had neither, which was hidden by the way it is reached: Model
        // gates the call on `!readOutline(...).isEmpty`, and readOutline satisfies
        // that for a 4,000-level chain precisely *by truncating it at 32* — so
        // the truncation that concealed the depth is what licensed the unbounded
        // pass over the untruncated tree.
        var budget = 20_000            // total entries, against a cyclic outline

        /// Rebuilds one node against the destination's pages, matched by index.
        /// Page count is 1:1 through the pipeline, so the index is the mapping.
        func rebuild(_ node: PDFOutline, depth: Int) -> PDFOutline? {
            guard depth < maximumOutlineDepth, budget > 0 else { return nil }
            budget -= 1
            let copy = PDFOutline()
            copy.label = node.label
            if let source = node.destination, let page = source.page,
               case let index = src.index(for: page), index < dst.pageCount,
               let target = dst.page(at: index) {
                // Unspecified members pass through verbatim — substituting
                // .zero turned a /Fit bookmark into a jump to the foot of the
                // page — but a real coordinate has to be moved into the
                // republished page's space, exactly as on the JBIG2 route.
                let p = source.point
                let hasX = p.x.isFinite && p.x != kPDFDestinationUnspecifiedValue
                let hasY = p.y.isFinite && p.y != kPDFDestinationUnspecifiedValue
                if hasX || hasY {
                    let placed: (left: CGFloat?, top: CGFloat?)
                    if hasX && hasY {
                        let moved = mapToOutput(p, on: page)
                        placed = (moved.x, moved.y)
                    } else {
                        placed = mapSingleAxis(hasX ? p.x : p.y,
                                               isVertical: !hasX, on: page)
                    }
                    // The member this axis does not drive stays unspecified,
                    // rather than carrying a value derived from a substituted 0.
                    copy.destination = PDFDestination(
                        page: target,
                        at: CGPoint(x: placed.left ?? CGFloat(kPDFDestinationUnspecifiedValue),
                                    y: placed.top ?? CGFloat(kPDFDestinationUnspecifiedValue)))
                } else {
                    copy.destination = PDFDestination(page: target, at: p)
                }
            }
            var kept = 0
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i),
                      let built = rebuild(child, depth: depth + 1) else { continue }
                copy.insertChild(built, at: kept)
                kept += 1
            }
            // Same rule as readOutline: a destination-less entry is still part
            // of the outline the author wrote.
            return (copy.destination != nil || kept > 0 || !(copy.label ?? "").isEmpty)
                ? copy : nil
        }

        // The root is not an entry, and `readOutline` has always known that:
        // it walks `root`'s children at depth 0. This called `rebuild(root, 0)`,
        // so the root itself spent a level and real entries started at 1 —
        // **31 levels here against 32 there** (A1.3). Mirrors that disagree
        // about their own bound is R23 exactly, and the disagreement is invisible
        // until a document is deep enough to be truncated by one of them.
        let newRoot = PDFOutline()
        var kept = 0
        for i in 0..<root.numberOfChildren {
            guard let child = root.child(at: i),
                  let built = rebuild(child, depth: 0) else { continue }
            newRoot.insertChild(built, at: kept)
            kept += 1
        }
        guard kept > 0 else { return false }
        dst.outlineRoot = newRoot
        return dst.write(to: out)
    }

    /// Page numbers the recogniser never reported at all.
    ///
    /// mac-ocr emits one JSON Lines record per page **including blank ones** —
    /// verified: a 3-page document with a blank middle page yields three records,
    /// the middle one with an empty `observations` array. So a page number
    /// missing from the output means that page was never recognised, not that it
    /// had nothing on it.
    ///
    /// Worth checking separately because it is invisible to every other guard:
    /// the page still gets composed, still counts toward `produced == expected`,
    /// and simply carries no text. A silently untextable page in the middle of a
    /// book is exactly what invariant 1 is about.
    static func missingPages(in byPage: [Int: [Observation]], of pageCount: Int) -> [Int] {
        guard pageCount > 0 else { return [] }
        return (1...pageCount).filter { byPage[$0] == nil }
    }

    /// Where a page's crop box lands once the whole sheet is drawn into `pageBox`.
    ///
    /// Observations are normalised to the crop box, but the published page is the
    /// media box, so they have to be placed inside this sub-rectangle rather than
    /// across the whole page. Computed by running the crop rect through the same
    /// `getDrawingTransform` CoreGraphics uses for the media box, which is what
    /// makes /Rotate come out right without any hand-rolled quarter-turn
    /// arithmetic — the class of thing that previously drew pages off-canvas.
    ///
    /// Falls back to the whole page whenever the two boxes coincide, which is the
    /// common case and every rebuilt file.
    static func cropRegion(of page: PDFPage, on pageBox: CGRect) -> CGRect {
        let media = page.bounds(for: .mediaBox)
        let crop = page.bounds(for: .cropBox)
        guard crop != media, !crop.isEmpty, let cgPage = page.pageRef else { return pageBox }
        let transform = cgPage.getDrawingTransform(
            .mediaBox, rect: pageBox, rotate: 0, preserveAspectRatio: true)
        let mapped = crop.applying(transform)
        // A crop box larger than the media box is out of spec; the PDF spec says
        // to intersect them. Never hand back something off the page.
        let clipped = mapped.intersection(pageBox)
        return clipped.isNull || clipped.isEmpty ? pageBox : clipped
    }

    /// How far apart two same-text observations may sit vertically and still be
    /// one observation reported twice, as a fraction of the box height.
    ///
    /// 0.3 rather than 1.0. The duplicates this exists for — `auto`'s
    /// partitioned pass emitting a line twice — are co-located to within
    /// rounding, so the tolerance only has to survive sub-point jitter. A whole
    /// line height instead reached the adjacent row: D3 measured 295 of 14,782
    /// adjacent horizontally-overlapping pairs across the corpus at a pitch
    /// below 0.6 of a box height, and this test is the looser `< 1.0` (C22).
    ///
    /// Below 0.3 of a box height two rows would have to overlap by seventy per
    /// cent, which is not typesetting — it is the same line reported twice.
    static var duplicateBaselineFraction: CGFloat = 0.3

    /// Removes observations that repeat the same text in the same place.
    ///
    /// The recogniser can report a line twice — mac-ocr's `auto` strategy is
    /// documented as emitting overlapping observations on large pages — and both
    /// copies were drawn, so the line extracted as "the text the text".
    static func deduplicated(_ lines: [Observation], in box: CGRect) -> [Observation] {
        var kept: [Observation] = []
        for line in lines {
            let isDuplicate = kept.contains { other in
                guard other.text == line.text else { return false }
                // Same words in nearly the same spot, not merely the same words:
                // a running head can legitimately repeat a phrase from the body.
                let dx = abs(other.boundingBox.x - line.boundingBox.x) * box.width
                let dy = abs(other.boundingBox.y - line.boundingBox.y) * box.height
                let h = max(line.boundingBox.height * box.height, 1)
                // Vertically this has to mean "on top of", not "near". A twin
                // from `auto`'s partitioned pass sits at the same y to within
                // rounding; a full line height of tolerance also swallowed the
                // NEXT ROW, because Vision's boxes carry ascender and descender
                // space, so ordinary 12 pt leading inside a 13 pt box satisfied
                // it. A column repeating a figure lost every row after the
                // first, silently — this is the one line-dropping path in the
                // writer that produces no `Unplaced` (C22).
                //
                // Horizontally a full line height stays: that half was always
                // about telling a running head from the body text under it, and
                // it was never the problem.
                return dx < h && dy < h * duplicateBaselineFraction
            }
            if !isDuplicate { kept.append(line) }
        }
        return kept
    }

    // MARK: - Words broken across a line

    /// The characters a typesetter may break a word with.
    ///
    /// Not just `-`: archival scans are full of the Unicode hyphen (U+2010) and
    /// the non-breaking one (U+2011), and Vision reports what it sees. A rule
    /// that only knew about ASCII would silently do nothing on exactly the older
    /// material this app exists for.
    static let breakHyphens: Set<Character> = ["-", "\u{2010}", "\u{2011}", "\u{00AD}"]

    /// Rejoins a word a line break split in two, so the whole word can be found.
    ///
    /// A word broken over two lines reaches the text layer as Vision read it —
    /// `merito-` ending one line and `cracy` beginning the next — so searching
    /// the finished PDF for `meritocracy` finds nothing. In narrow columns that
    /// is a lot of words, and they are disproportionately the long specific ones
    /// people search for.
    ///
    /// The joined word is written **over the first fragment**, and the tail is
    /// left where it is. So the tail is extractable twice: once inside the
    /// joined word and once on its own line. That is deliberate and it is the
    /// trade this feature is: a duplicated tail is noise in extracted text,
    /// while an unfindable word is a document that cannot be searched. Nothing
    /// is removed, which keeps this outside invariant 1 entirely — no path here
    /// can drop text, only add it.
    ///
    /// Geometry is untouched. `draw` fits each run to its own box by choosing a
    /// font size, so a longer string means narrower glyphs in the same
    /// rectangle; every measurement invariant 3 cares about — where the run
    /// starts, how wide it is, its baseline, its height — is unchanged.
    ///
    /// Conservative about what counts as a break:
    ///
    /// - the tail must start lower-case, so `Smith-` / `Jones` stays apart;
    /// - the tail's first word must be alphabetic, so a hyphen followed by a
    ///   figure or a bullet is left alone;
    /// - the head must have something before the hyphen, so a line that is only
    ///   a dash — a rule, an em-dash used as punctuation — is not a candidate;
    /// - the two lines must be *consecutive in reading order and vertically
    ///   adjacent*, not merely one after the other in the array.
    ///
    /// What it cannot do is tell a broken word from a real compound: `well-`
    /// followed by `known` becomes `wellknown`. That needs a dictionary this app
    /// does not have and should not grow. The damage is bounded — the joined
    /// form is added, both fragments remain, and a search for `well` still
    /// matches inside `wellknown` — so it is accepted rather than guessed at.
    /// `continuation` is the first line of the *next page*, so a word broken by a
    /// page break can be joined too. Nil on the last page.
    ///
    /// That case is not rare, and the first attempt at it wrongly concluded it
    /// was. Measured over 45 documents and 1,225 pages, **29 pages — 2.37%, in 11
    /// of the 45 — end on a hyphenated line.** The three documents used to test
    /// the first attempt held twelve such pages between them and it joined none
    /// of them, which was read as the case being rare rather than as the code
    /// being wrong. `JOIN_DEBUG` now reports every candidate and the guard that
    /// rejected it, precisely so that mistake cannot repeat: silence there means
    /// no candidates, not no opportunities.
    static func joiningHyphenatedWords(_ lines: [Observation], in box: CGRect,
                                       continuation: [Observation] = []) -> [Observation] {
        guard !lines.isEmpty else { return lines }
        let debug = ProcessInfo.processInfo.environment["JOIN_DEBUG"] != nil
        func note(_ m: String) {
            if debug { FileHandle.standardError.write((m + "\n").data(using: .utf8)!) }
        }
        var out = lines
        for i in 0..<out.count {
            let head = out[i].text
            guard let last = head.last, breakHyphens.contains(last) else { continue }
            let stem = String(head.dropLast())
            // Something must precede the hyphen, and it must end in a letter —
            // `page 3-` is a range, not a broken word.
            guard let stemLast = stem.last, stemLast.isLetter else { continue }

            // Candidates, in reading order: the next line on this page, then —
            // for a head at the foot of the page — the first line of the next.
            let headBottom = out[i].boundingBox.y + out[i].boundingBox.height
            let atFoot = headBottom >= 1 - edgeOfPage
            var candidates: [(Observation, Bool)] = []
            if i + 1 < out.count { candidates.append((out[i + 1], false)) }
            if atFoot {
                // The next page's *first few* lines, not only its topmost.
                //
                // Taking one was the whole reason the first attempt joined
                // nothing: the topmost thing on a page is the folio or the
                // running head — measured, the two candidates offered were
                // `6130` and `CONGRESSIONAL `. Both are correctly refused by
                // the lower-case test, and with only one candidate on offer the
                // refusal ended the search instead of moving past the furniture
                // to the body text underneath.
                candidates += continuation.map { ($0, true) }
            }
            note(String(format: "  [cand] %@… bottom=%.3f atFoot=%@ candidates=%d",
                        String(stem.suffix(18)), headBottom, atFoot ? "y":"n", candidates.count))
            guard !candidates.isEmpty else { continue }

            var chosen: Observation?
            var chosenAcrossPage = false
            for (tailLine, acrossPage) in candidates {
                if !acrossPage {
                    guard !isSameVisualLine(out[i], tailLine, in: box) else {
                        note("    reject: same visual line"); continue
                    }
                }
                if acrossPage {
                    // The tail must be at the head of the next sheet — otherwise it
                    // is a running head, a folio or a caption, and joining to it
                    // invents a word.
                    guard tailLine.boundingBox.y <= edgeOfPage else {
                        note(String(format: "    reject: tail not at top (%.3f > %.3f)",
                                    tailLine.boundingBox.y, edgeOfPage)); continue
                    }
                } else {
                    // Below, and close below. Vision returns reading order, but a
                    // multi-column page can put the next entry at the top of the
                    // next column, and joining across that is joining two unrelated
                    // words.
                    let drop = drawnBaseline(out[i], in: box) - drawnBaseline(tailLine, in: box)
                    let pitch = max(out[i].boundingBox.height * box.height, 1)
                    guard drop > 0, drop < pitch * maximumJoinPitch else {
                        note(String(format: "    reject: pitch (drop %.1f, limit %.1f)",
                                    drop, pitch * maximumJoinPitch)); continue
                    }
                }

                // Same column. Vertical adjacency alone is not enough and this was
                // measured, not imagined: on a two-column page the next entry in
                // reading order is often the next line of the *other* column at a
                // similar height, and joining across produced `adminis+put`,
                // `bipar+put`, `mi+appears`, `that+cerning` — a real word welded to
                // a fragment of an unrelated one, which is worse than the hyphen it
                // replaced. Columns do not overlap horizontally, so requiring the
                // two spans to share most of their width rules the whole class out.
                if !acrossPage {
                    let overlap = sharedWidthFraction(out[i].boundingBox, tailLine.boundingBox)
                    guard overlap >= minimumColumnOverlap else {
                        note(String(format: "    reject: different column (%.2f overlap)",
                                    overlap)); continue
                    }
                }

                let tail = tailLine.text
                guard let firstScalar = tail.first, firstScalar.isLowercase else {
                    note("    reject: tail not lower-case (\(tail.prefix(14)))"); continue
                }
                guard !tail.prefix(while: { $0.isLetter }).isEmpty else {
                    note("    reject: tail starts with no letter"); continue
                }
                chosen = tailLine
                chosenAcrossPage = acrossPage
                break
            }

            guard let tailLine = chosen else { note("    -> no candidate taken"); continue }
            let word = tailLine.text.prefix { $0.isLetter }
            note("    -> join\(chosenAcrossPage ? " ACROSS PAGE" : ""): \(stem)+\(word)")
            out[i] = Observation(boundingBox: out[i].boundingBox,
                                 text: stem + word,
                                 confidence: out[i].confidence)
        }
        return out
    }

    /// How far below a line its continuation may sit, in multiples of the line's
    /// own height, before the pair stops being consecutive lines of one column.
    ///
    /// 2.5 covers ordinary leading and a paragraph break; it does not reach the
    /// top of the next column, which on any real page is a whole column height
    /// away and usually *above* rather than below.
    static var maximumJoinPitch: CGFloat = 2.5

    /// How much of the **narrower** box two horizontal spans have in common, as a
    /// fraction of it. Negative when they do not overlap at all, and 0 for a box
    /// with no width — which no caller may treat as an overlap.
    ///
    /// One definition, two questions. `joiningHyphenatedWords` asks whether two
    /// lines are in the same column (`minimumColumnOverlap`); `rightLimit` asks
    /// whether two same-line boxes are describing the same ink
    /// (`sharedInkFraction`). The measure is identical and the thresholds are
    /// deliberately not — a constant serving two questions is what C20 was, and
    /// A1.1 is `sameLineBaselineFraction` still being shared by two.
    ///
    /// The narrower box is the denominator on purpose: a short last line of a
    /// paragraph still sits inside the column above it, and a small fragment
    /// swallowed whole by a mis-grouped observation is entirely inside it.
    static func sharedWidthFraction(_ a: BoundingBox, _ b: BoundingBox) -> Double {
        let shared = min(a.x + a.width, b.x + b.width) - max(a.x, b.x)
        let narrower = min(a.width, b.width)
        guard narrower > 0 else { return 0 }
        return shared / narrower
    }

    /// How much of their width two lines must share before they count as being
    /// in the same column.
    ///
    /// 0.6, which a two-column layout cannot satisfy across the gutter and which
    /// ordinary consecutive lines clear easily — a short last line of a paragraph
    /// still sits inside the column above it, so the *narrower* span is the
    /// denominator rather than the wider one.
    static var minimumColumnOverlap: Double = 0.6

    /// How near the foot or head of a page a line must be to take part in a join
    /// across the page break, as a fraction of page height.
    ///
    /// **Measured, after a guess got it wrong.** 0.18 was the guess, and it
    /// admitted nothing at all: the deepest hyphenated line on a Congressional
    /// report sits at 0.82 of the page, which is exactly the boundary `1 - 0.18`
    /// produces, so every candidate failed on a rounding. Page margins are
    /// larger than they look — a bottom margin plus the last line's descender
    /// box is comfortably a fifth of the sheet.
    ///
    /// 0.25 clears the measured 0.82 with room. It is only reachable by a line
    /// that is already the *last* candidate on its page and already ends in a
    /// hyphen, so widening it does not open the door to the mid-column failures
    /// (`adminis+put`, `bipar+put`) that `minimumColumnOverlap` exists for —
    /// those are same-page joins and never reach this test.
    static var edgeOfPage: Double = 0.25

    /// How many of the next page's opening lines to offer as continuations.
    ///
    /// Three, because the furniture above the first line of body text is a folio,
    /// a running head, or both — never more than that on the archival material
    /// this handles. Each is still put through every guard, so a wrong one is
    /// refused rather than taken; the count only decides how far past the
    /// furniture the search is allowed to look.
    static var continuationCandidates: Int = 3


    /// How tall this line's glyphs may be before they collide with the nearest
    /// line above or below.
    ///
    /// Necessary because Vision's lines sit much closer together than a naive
    /// font size implies — a superscript footnote marker can be 8 pt from the
    /// line beneath it. Where invisible runs overlap, Preview stops treating them
    /// as separate lines and a drag-selection runs straight past one.
    /// Where this observation's text is actually *drawn*, not where its box
    /// bottom sits. Comparing box bottoms over-estimates the gap by 0.22 x the
    /// height difference, which let a short superscript overlap a taller line —
    /// and, in `rightLimit`, let a display numeral count a body line two rows
    /// away as its own line's neighbour.
    ///
    /// Not `private`, and not for the app's benefit: `Tools/score-line-separation`
    /// has to group fragments into visual lines the way this file does, and a
    /// second definition of "one visual line" living in an instrument is C20's
    /// shape with the writer and its own measuring stick as the two halves.
    static func drawnBaseline(_ o: Observation, in box: CGRect) -> CGFloat {
        let h = o.boundingBox.height * box.height
        let bottom = box.height - (o.boundingBox.y * box.height) - h
        return bottom + h * baselineFraction
    }

    /// How far two drawn baselines may differ and still be one visual line, as a
    /// fraction of the shorter box's height.
    ///
    /// The shorter of the two, not the taller: a tall display numeral must not
    /// be able to claim a body line two rows away — that was measured, and it is
    /// why `rightLimit` uses `min`.
    static var sameLineBaselineFraction: CGFloat = 0.4

    /// How much of the smaller of two same-line boxes the other may cover before
    /// they stop being two fragments and start being two readings of one piece
    /// of ink.
    ///
    /// Sequential fragments of a line do not overlap: their boxes meet, or miss
    /// by a point or two of Vision's own jitter. A box covering *half* of its
    /// neighbour is not the next thing along the line — it is the same words
    /// recognised twice, or a mis-grouped observation swallowing a real one, and
    /// `rightLimit` must not shrink a run to make room for it. That is A1.2:
    /// `('their', 19.4 pt)` against `('their eder but', 63.3 pt)` starting 1.0 pt
    /// later, and the first drawn at 5.0% of its box.
    ///
    /// **This constant sits in a continuum, not a gap, and the honest defence is
    /// that it barely matters where in the continuum it sits.** Measured over 852
    /// limited runs on 24 real newspaper pages (`Tools/score-run-width`), with
    /// "harmed" meaning drawn under half its box:
    ///
    /// | shared ink | pairs | of those, drawn under half their box |
    /// |---|---|---|
    /// | ≤ 0.47 | 779 | 1 |
    /// | 0.47–0.53 | 3 | 1 |
    /// | ≥ 0.53 | 70 | 60 |
    ///
    /// Three pairs of 852 lie in the band this constant could move through, and
    /// moving it from 0.5 to 0.4 or 0.6 changes the verdict on **six** — 75
    /// neighbours refused instead of 71, or 69. Nothing here is calibrated on a
    /// knife edge, which is the property to check, since the corpus has no gap
    /// to put a threshold in and a constant chosen inside a continuum is how
    /// `BUGS.md` C24's repairs went wrong.
    ///
    /// Both directions of error were priced before choosing. Refusing a genuine
    /// neighbour risks a weld; but two boxes overlapping by half the smaller are
    /// drawn over each other whatever this says, so the gap PDFKit would read
    /// between them is not a gap in the first place. Keeping a false neighbour
    /// costs a line nobody can highlight, which is the defect being fixed.
    ///
    /// `Double`, like `minimumColumnOverlap` and unlike the geometry constants
    /// around it, because `sharedWidthFraction` works in the observations' own
    /// normalised coordinates and that is the type they arrive in.
    static var sharedInkFraction: Double = 0.5

    /// Whether two observations are fragments of **one visual line**.
    ///
    /// One definition, because there were two and they disagreed (C20).
    /// `rightLimit` called a neighbour same-line below `0.4 · min(height)`;
    /// `headroom` called one a *vertical* neighbour above 0.5 pt with more than
    /// 1 pt of horizontal overlap. Everything in the band between — and two
    /// fragments sharing a true baseline land there whenever one has a descender
    /// and the other does not, about 1.7 pt on 10 pt text — satisfied both. Such
    /// a pair was shrunk by the reserve (right, it is one line) *and* crushed by
    /// the ceiling (wrong) at the same time. Measured on the Harper's 1938
    /// corpus page: eight observations across four pages, worst case a run drawn
    /// 0.71 pt tall against a natural 9.04 pt, at a quarter of its box width.
    ///
    /// C18's overlap tolerance is what opened the door: it established that
    /// Vision's fragment boxes routinely overlap by a point or two, and an
    /// overlap in (1, 2] pt clears `headroom`'s `> 1` test.
    ///
    /// Not `private`, for the reason `drawnBaseline` gives: the instrument that
    /// measures line separation groups fragments with *this* predicate rather
    /// than a copy of it.
    ///
    /// **Which height the tolerance scales with is the caller's question, not a
    /// second predicate.** C20 unified two functions that disagreed about "one
    /// visual line"; A1.1 is the discovery that the two callers really do want
    /// different tolerances, and the way to have that without re-creating C20 is
    /// one function, one constant and an explicit argument at each call site.
    /// `.shorter` is what C20 chose and what `headroom` still asks for; `.taller`
    /// is what the horizontal reserve asks for and why is in `Scale`.
    enum Scale {
        /// 0.4 × the shorter box. A tall display numeral cannot claim a body line
        /// two rows away — measured, and the reason `min` was chosen.
        case shorter
        /// 0.4 × the taller box. Two fragments of one line whose heights differ —
        /// a headline word beside a body word, a figure beside its caption — get
        /// a tolerance of 1.4–2.1 pt under `.shorter`, and in the band above it
        /// no reserve is opened, the run is drawn to its full box width and the
        /// words weld (`REVIEW-2026-08-14.md` A1.1, `BUGS.md` R82).
        case taller
    }

    static func isSameVisualLine(_ a: Observation, _ b: Observation,
                                 in box: CGRect, _ scale: Scale = .shorter) -> Bool {
        let heights = (a.boundingBox.height * box.height, b.boundingBox.height * box.height)
        let reference = scale == .shorter ? min(heights.0, heights.1)
                                          : max(heights.0, heights.1)
        let tolerance = reference * sameLineBaselineFraction
        return abs(drawnBaseline(a, in: box) - drawnBaseline(b, in: box)) < tolerance
    }

    /// Not `private`, for the reason `rightLimit` is not: `Tools/score-run-width`
    /// measures both halves of the fight — how wide a run is drawn and how far
    /// the ceiling squashed it — and C20 is the entry about a pair getting both
    /// treatments at once, so an instrument that can see only one of them cannot
    /// see C20 at all.
    static func headroom(for position: Int, among lines: [Observation],
                         in box: CGRect) -> CGFloat {
        func baseline(_ o: Observation) -> CGFloat { drawnBaseline(o, in: box) }
        func span(_ o: Observation) -> (CGFloat, CGFloat) {
            let x = o.boundingBox.x * box.width
            return (x, x + o.boundingBox.width * box.width)
        }
        let me = lines[position]
        let mine = baseline(me)
        let (myLeft, myRight) = span(me)

        var nearest = CGFloat.greatestFiniteMagnitude
        for (i, other) in lines.enumerated() where i != position {
            // Only lines sharing horizontal space can collide. Two fragments of
            // one visual line sit at the same baseline side by side; treating
            // those as vertical neighbours crushed the font to a couple of points.
            let (left, right) = span(other)
            guard min(myRight, right) - max(myLeft, left) > 1 else { continue }
            // A fragment of my own line is rightLimit's business, not mine.
            // These two used to answer that question differently, and a pair in
            // the band between the two answers got both treatments (C20).
            guard !isSameVisualLine(me, other, in: box) else { continue }
            let gap = abs(baseline(other) - mine)
            if gap > 0.5 { nearest = min(nearest, gap) }
        }
        guard nearest < .greatestFiniteMagnitude else { return .greatestFiniteMagnitude }
        // CTFont reports Helvetica as ascent 0.770 + descent 0.230 = 1.0 em, and
        // that is what CoreGraphics embeds; the old 0.925 estimate let every
        // clamped run come out 5% taller than the gap it had to fit.
        return nearest / max(headroomFactor, 0.1)
    }

    /// How far right this run may extend before it runs into the next fragment
    /// of the same visual line. `.greatestFiniteMagnitude` when there is none.
    ///
    /// The mirror of `headroom`, and for the mirrored reason: that one stops
    /// runs colliding *vertically*, this one stops them colliding
    /// *horizontally*. Same-baseline neighbours only — a line on the row below
    /// is `headroom`'s business, and treating it as a horizontal obstacle would
    /// crush every run on a tightly-set page.
    ///
    /// Not `private`, for the reason `isSameVisualLine` and `drawnBaseline` are
    /// not: `Tools/score-run-width` has to ask which neighbour limited a run, and
    /// a second implementation of that question in an instrument is C20's shape.
    static func rightLimit(for position: Int, among lines: [Observation],
                           in box: CGRect) -> CGFloat {
        let me = lines[position]
        let myLeft = me.boundingBox.x * box.width

        var nearest = CGFloat.greatestFiniteMagnitude
        for (i, other) in lines.enumerated() where i != position {
            // Baselines, and the TALLER of the two heights. The same predicate
            // `headroom` uses — one function, one constant — asked at the scale
            // this direction needs: a short fragment beside a tall one is one
            // line, and under `.shorter` its tolerance is 1.4–2.1 pt, so the
            // reserve never opened and the words welded (A1.1).
            guard isSameVisualLine(me, other, in: box, .taller) else { continue }

            // Anything starting to the right of MY LEFT edge is after me on this
            // line. The test used to be `>= myRight - 0.5`, which is a cliff:
            // Vision's fragment boxes routinely overlap by a point or two — 0.5 pt
            // is two pixels at 300 DPI — and past it the neighbour was dropped
            // entirely and the words silently welded again. Measured: welds
            // returned for overlaps of 0.51-2.0 pt.
            let otherLeft = other.boundingBox.x * box.width
            guard otherLeft > myLeft else { continue }

            // …but "to the right of my left edge" also accepts a box sitting on
            // top of mine, and that is A1.2: the run is then shrunk to the couple
            // of points before the intruder starts and a whole line is drawn at
            // 5% of its width, silently. This is the test the comment above used
            // to claim `allowed > 0` was making, which it never was — `allowed`
            // is positive for *any* neighbour right of my left edge, measured
            // 4,338 times out of 4,338, the smallest at 1.97e-07 pt.
            // The same measure `joiningHyphenatedWords` uses for "same column",
            // against a threshold of its own: see `sharedWidthFraction`.
            guard sharedWidthFraction(me.boundingBox, other.boundingBox)
                    <= sharedInkFraction else { continue }

            nearest = min(nearest, box.minX + otherLeft)
        }
        return nearest
    }

    /// Where one run lands, and how big it is: everything `draw` decides before
    /// it draws anything.
    ///
    /// Split out of `draw` so an instrument can ask the writer what it *will*
    /// draw instead of re-deriving it. `Tools/score-run-width` measures property
    /// (c) — does the run span its ink — over thousands of fragments, and the
    /// only honest way to do that is with this arithmetic rather than a second
    /// copy of it: C20 is in the register because two functions held two
    /// definitions of one idea, and `score-line-separation` already had to stop
    /// keeping its own "one visual line".
    struct Run {
        /// The font size the glyphs are drawn at, after both the width fit and
        /// the vertical cap.
        let size: CGFloat
        /// The y scale in the text matrix — how far the glyphs are squashed.
        let vertical: CGFloat
        /// Origin of the run in PDF user space.
        let left, bottom: CGFloat
        /// The observation's own box, in points.
        let boxWidth, boxHeight: CGFloat
        /// The advance this text has at `reference`, from which the drawn
        /// advance scales linearly.
        let naturalAdvance, reference: CGFloat
        /// How tall the glyphs would stand if no neighbouring line were in the
        /// way: the ink's own height, less the `0.86` the writer never exceeds.
        let idealHeight: CGFloat
        /// True when a same-visual-line neighbour to the right shortened it.
        let limitedByNeighbour: Bool

        /// How wide the run is actually drawn, in points.
        var advance: CGFloat { naturalAdvance * size / reference }
        /// The share of its own box the run covers. Property (c) lives here: at
        /// 5% of the box, a click past the first tenth of the line selects some
        /// other line (`REVIEW-2026-08-14.md` A1.2).
        var widthShare: CGFloat { boxWidth > 0 ? advance / boxWidth : 0 }
        /// How tall the glyphs are actually drawn, in points.
        var drawnHeight: CGFloat { size * vertical }
        /// The share of the height it wanted that the ceiling left it. C20 is
        /// what happens when this and `widthShare` are both small on one run —
        /// measured there at a quarter of its box width and 0.71 pt against a
        /// natural 9.04 pt.
        var heightShare: CGFloat { idealHeight > 0 ? drawnHeight / idealHeight : 0 }
    }

    /// The placement of one observation, or the reason it cannot be placed.
    enum Placement {
        case placed(Run)
        case refused(String)
    }

    /// What `draw` will do with this observation, without a context to draw into.
    ///
    /// `draw` is this function plus four lines of CoreText, so the two cannot
    /// disagree about what gets drawn.
    static func placement(
        of observation: Observation,
        in box: CGRect,
        ceiling: CGFloat,
        rightLimit: CGFloat,
        font: CTFont
    ) -> Placement {
        let text = observation.text
        guard !text.isEmpty else { return .refused("empty text") }

        // Vision's boxes are normalised with a top-left origin; PDF user space
        // has its origin at the bottom left.
        //
        // `box` is the region the observations were normalised to — the crop box
        // as it lands on the published page — which is usually but not always the
        // whole page, so its origin has to be added rather than assumed zero.
        let width = observation.boundingBox.width * box.width
        let height = observation.boundingBox.height * box.height
        let left = box.minX + observation.boundingBox.x * box.width
        let bottom = box.minY + box.height - (observation.boundingBox.y * box.height) - height
        guard width > 0.5, height > 0.5 else {
            return .refused(String(format: "box too small (%.2f x %.2f pt)", width, height))
        }

        // Width and height are set independently, which is the only way to get
        // all three properties at once:
        //
        //  - advances natural at the chosen size, so extractors never see an
        //    exaggerated inter-glyph gap and split a word ("accom plished");
        //  - the run spans the ink, so a selection highlight reaches the end of
        //    the line and every word is clickable;
        //  - glyphs no taller than the ink, so neighbouring lines never overlap
        //    and line-by-line selection works.
        //
        // So: pick the size that makes the natural width match the box, then
        // compress vertically in the text matrix. Scaling y leaves every
        // horizontal metric alone, which is what the extractors look at. Fitting
        // width by stretching x instead exaggerates the gaps; fitting it by size
        // alone leaves the glyphs too tall.
        let reference = max(height, 1)
        let probeFont = CTFontCreateCopyWithAttributes(font, reference, nil, nil)
        let probe = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: probeFont]))
        let probeWidth = CTLineGetTypographicBounds(probe, nil, nil, nil)
        guard probeWidth > 0 else { return .refused("text has no typographic width") }

        // Clamped, not abandoned. This band used to drop real content — a "I 3"
        // table row (420.9), an em-rule over a wide box (428), a lone page number
        // in a wide column (550), and any very long line (0.44). A clamped line is
        // slightly the wrong width; a dropped line is missing text.
        var widthSize = min(max(reference * (width / probeWidth), 0.5), 400)

        // Keep clear of the next fragment on this line. Without this, widening
        // runs to their true box width — which is what makes line ends
        // selectable — closes the geometric gap PDFKit reads as a space, and
        // two words weld into one. See `reserveEms`.
        var limited = false
        if rightLimit < .greatestFiniteMagnitude {
            // Solve for the size, don't budget against the pre-shrink one.
            //
            // Taking `gap = widthSize * reserveEms` and then recomputing
            // `widthSize` from what is left makes the realised gap larger than
            // asked, because the run it is measured against got smaller. When
            // the box hugs its text the reserve becomes a flat 0.25 x line
            // height whatever the fragment's length, so the cost is ~0.5/n for
            // an n-character fragment: measured, `I` kept 21% of its width and
            // a single `i` in a narrow box collapsed to 0.11 pt — past the 0.5 pt
            // size floor, where `size * vertical == wanted` stops holding and
            // the glyph stops tracking the ink at all.
            //
            // Width and gap both scale with size, so the fixed point is exact:
            //   probeWidth * s / reference + s * reserveEms = rightLimit - left
            // Clamped: this is non-monotonic as a knob. Past about 1 em the
            // run shrinks to nothing and the reserve reads as harmless in a
            // sweep, which in this project is how a calibration goes wrong.
            let ems = min(max(reserveEms, 0), 1)
            let room = rightLimit - left
            let allowed = room / (1 + ems * reference / probeWidth)
            if allowed > 0, allowed < width {
                widthSize = min(max(reference * (allowed / probeWidth), 0.5), 400)
                limited = true
            }
        }

        // How much to squash so the glyphs stand no taller than the ink.
        let idealHeight = height * 0.86
        let wanted = min(idealHeight, ceiling)

        // A sparse row — "1 24" in a table of contents, a lone page number in a
        // wide column — needs a huge size to span its box, and squashing that back
        // used to hit a 0.15 floor. Past the floor the glyphs stayed taller than
        // the ink and welded onto the line above: a TOC row extracted as
        // "…book page 2 1 24" with no line break.
        //
        // When the two demands conflict, height wins. Selection breaks when runs
        // overlap; a run that stops short of the box edge only shortens the
        // highlight. So cap the size instead of flooring the squash.
        let minimumVertical = Self.minimumVertical
        var size = widthSize
        if wanted / size < minimumVertical { size = wanted / minimumVertical }
        let vertical = min(max(wanted / size, minimumVertical), 3.0)

        return .placed(Run(size: size, vertical: vertical, left: left, bottom: bottom,
                           boxWidth: width, boxHeight: height,
                           naturalAdvance: probeWidth, reference: reference,
                           idealHeight: idealHeight, limitedByNeighbour: limited))
    }

    /// Returns nil when the line was placed, or a reason when it could not be.
    @discardableResult
    private static func draw(
        _ observation: Observation,
        in box: CGRect,
        ceiling: CGFloat,
        rightLimit: CGFloat,
        font: CTFont,
        into pdf: CGContext
    ) -> String? {
        switch placement(of: observation, in: box, ceiling: ceiling,
                         rightLimit: rightLimit, font: font) {
        case .refused(let why):
            return why
        case .placed(let run):
            let sized = CTFontCreateCopyWithAttributes(font, run.size, nil, nil)
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: observation.text, attributes: [.font: sized]))
            var matrix = CGAffineTransform(a: 1, b: 0, c: 0, d: run.vertical, tx: 0, ty: 0)
            matrix.tx = run.left
            matrix.ty = run.bottom + run.boxHeight * baselineFraction
            pdf.textMatrix = matrix
            CTLineDraw(line, pdf)
            return nil
        }
    }
}
