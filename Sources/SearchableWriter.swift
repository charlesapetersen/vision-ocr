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
    /// ems rather than points on purpose — the threshold PDFKit applies is
    /// itself proportional (~0.15 em), so 0.25 em clears it at *every* font
    /// size, and no absolute floor is needed. One was tried, at 0.5, 2 and 4 pt:
    /// all three scored identically to no floor at all across 25 newspaper
    /// scans, so it is not here. A line with no right-hand neighbour on it is
    /// untouched.
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

    struct Page: Decodable {
        let page: Int
        let observations: [Observation]
    }

    struct Observation: Decodable {
        let boundingBox: BoundingBox
        let text: String
        let confidence: Double
    }

    /// Normalised to the page, with a top-left origin.
    struct BoundingBox: Decodable {
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

    /// Parses JSON Lines: one page object per line, as mac-ocr streams them.
    static func observations(fromJSONLines lines: [String]) throws -> [Int: [Observation]] {
        let decoder = JSONDecoder()
        var byPage: [Int: [Observation]] = [:]
        var undecodable = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard let page = try? decoder.decode(Page.self, from: data) else {
                undecodable += 1
                continue
            }
            byPage[page.page, default: []] += page.observations
        }
        // Skipping these quietly published the affected pages with no text at all
        // and still reported success — the page-count check cannot see it.
        guard undecodable == 0 else { throw Failure.unreadableObservations }
        guard !byPage.isEmpty else { throw Failure.unreadableObservations }
        return byPage
    }

    static func observations(fromJSONAt url: URL) throws -> [Int: [Observation]] {
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadableObservations }
        let pages: [Page]
        do { pages = try JSONDecoder().decode([Page].self, from: data) }
        catch { throw Failure.unreadableObservations }
        // mac-ocr numbers pages from 1. Merge rather than overwrite, so a
        // duplicated page entry can't silently drop text.
        var byPage: [Int: [Observation]] = [:]
        for page in pages { byPage[page.page, default: []] += page.observations }
        return byPage
    }

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
        minimumConfidence: Double = 0,
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
            if region != pageBox {
                var cropRect = region
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
            var lines = (byPage[index + 1] ?? [])
                .filter { $0.confidence >= minimumConfidence
                    && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            lines = deduplicated(lines, in: region)
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
                index = doc.index(for: page)
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

        guard let newRoot = rebuild(root, depth: 0),
              newRoot.numberOfChildren > 0 else { return false }
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
                return dx < h && dy < h
            }
            if !isDuplicate { kept.append(line) }
        }
        return kept
    }

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
    private static func drawnBaseline(_ o: Observation, in box: CGRect) -> CGFloat {
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
    private static func isSameVisualLine(_ a: Observation, _ b: Observation,
                                         in box: CGRect) -> Bool {
        let tolerance = min(a.boundingBox.height * box.height,
                            b.boundingBox.height * box.height) * sameLineBaselineFraction
        return abs(drawnBaseline(a, in: box) - drawnBaseline(b, in: box)) < tolerance
    }

    private static func headroom(for position: Int, among lines: [Observation],
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
    private static func rightLimit(for position: Int, among lines: [Observation],
                                   in box: CGRect) -> CGFloat {
        let me = lines[position]
        let myHeight = me.boundingBox.height * box.height
        let myBaseline = drawnBaseline(me, in: box)
        let myLeft = me.boundingBox.x * box.width

        var nearest = CGFloat.greatestFiniteMagnitude
        for (i, other) in lines.enumerated() where i != position {
            // Baselines, and the SHORTER of the two heights — see
            // `sameLineBaselineFraction`. The same predicate `headroom` uses, so
            // the two cannot drift apart again (C20).
            guard isSameVisualLine(me, other, in: box) else { continue }

            // Anything starting to the right of MY LEFT edge is after me on this
            // line. The test used to be `>= myRight - 0.5`, which is a cliff:
            // Vision's fragment boxes routinely overlap by a point or two — 0.5 pt
            // is two pixels at 300 DPI — and past it the neighbour was dropped
            // entirely and the words silently welded again. Measured: welds
            // returned for overlaps of 0.51-2.0 pt. How far to shrink is decided
            // by `allowed > 0` below, which already refuses a heavy overlap.
            let otherLeft = other.boundingBox.x * box.width
            guard otherLeft > myLeft else { continue }
            nearest = min(nearest, box.minX + otherLeft)
        }
        return nearest
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
        let text = observation.text
        guard !text.isEmpty else { return "empty text" }

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
            return String(format: "box too small (%.2f x %.2f pt)", width, height)
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
        guard probeWidth > 0 else { return "text has no typographic width" }

        // Clamped, not abandoned. This band used to drop real content — a "I 3"
        // table row (420.9), an em-rule over a wide box (428), a lone page number
        // in a wide column (550), and any very long line (0.44). A clamped line is
        // slightly the wrong width; a dropped line is missing text.
        var widthSize = min(max(reference * (width / probeWidth), 0.5), 400)

        // Keep clear of the next fragment on this line. Without this, widening
        // runs to their true box width — which is what makes line ends
        // selectable — closes the geometric gap PDFKit reads as a space, and
        // two words weld into one. See `reserveEms`.
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
            }
        }
        let sizedFont = CTFontCreateCopyWithAttributes(font, widthSize, nil, nil)
        var line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [.font: sizedFont]))

        // How much to squash so the glyphs stand no taller than the ink.
        let wanted = min(height * 0.86, ceiling)

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
        if size != widthSize {
            let refit = CTFontCreateCopyWithAttributes(font, size, nil, nil)
            line = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: [.font: refit]))
        }

        var matrix = CGAffineTransform(a: 1, b: 0, c: 0, d: vertical, tx: 0, ty: 0)
        matrix.tx = left
        matrix.ty = bottom + height * baselineFraction
        pdf.textMatrix = matrix
        CTLineDraw(line, pdf)
        return nil
    }
}
