import AppKit
import CoreImage
import Foundation
import PDFKit

/// Rebuilds a PDF as pages of pure image, so no text layer survives.
///
/// Why this exists: mac-ocr's `searchable-pdf` adds its text layer *on top of*
/// whatever is already there. Feeding it an already-OCR'd scan therefore yields
/// a file with two text layers, and copied text comes out doubled. Rebuilding
/// the pages as images first means Vision's pass is the only source of text.
///
/// Measured on a 300 DPI mixed-raster book scan: OCR of the rebuilt pages
/// differs from OCR of the untouched original by 0.13% of characters, so the
/// rebuild costs essentially nothing in recognition quality.
enum Flattener {

    enum Mode: String, CaseIterable, Identifiable {
        /// Per page: 1-bit for text, grey for a halftone, colour for anything
        /// with real colour in it. The default, because a single global choice
        /// is wrong every way — forcing 1-bit destroys halftones, forcing grey
        /// throws away colour plates, and forcing either onto a text-only book
        /// makes it several times larger than it needs to be.
        case auto
        /// 1-bit everywhere. Scanned text compresses far better this way than as
        /// JPEG (~110 KB/page vs ~1 MB/page at 300 DPI), and OCR is unaffected.
        case blackAndWhite
        /// 8-bit grey JPEG everywhere, colour included — an instruction, not a
        /// question. Much larger than 1-bit, and the mode to pick when you want
        /// a colour original rendered grey on purpose.
        case grayscale

        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: return "Automatic"
            case .blackAndWhite: return "Black & white"
            case .grayscale: return "Grayscale"
            }
        }
        var blurb: String {
            switch self {
            case .auto: return "1-bit text pages, grey halftones, colour kept where it is."
            case .blackAndWhite: return "Smallest. Flattens photographs to blotches."
            case .grayscale: return "Much larger. Keeps photographs, renders colour grey."
            }
        }
        /// JBIG2 is a bilevel codec, so only these modes can produce pages for it.
        var canUseJBIG2: Bool { self != .grayscale }
    }

    /// A page whose 1-bit rendering would be this much ink is not text — it's a
    /// halftone or a dark scan, and thresholding would wreck it.
    ///
    /// Calibrated on a 582-page book scan: ordinary text pages land at 6–8.4%,
    /// and the only pages above 15% were the two covers (100%) and a halftone
    /// map spread (17.8% and 34.8%). Erring low is the safe direction — a text
    /// page misrouted to greyscale just costs bytes, whereas a picture misrouted
    /// to 1-bit is destroyed.
    static let pictureInkThreshold = 0.15

    /// JPEG quality for the pages that get routed to greyscale.
    ///
    /// 0.6, not 0.8: the pages that come here are photographs and noisy
    /// photocopies, where the extra quality mostly encodes scanner grain.
    /// Measured on archival typescripts: ~1 MB/page at 0.8.
    ///
    /// A constant rather than a defaulted `flatten` parameter. It was the
    /// latter, and nothing in the app, the tools or the tests ever passed
    /// anything else — so it read as a knob while being a constant with extra
    /// steps, and one that had to be threaded through every call site to stay
    /// consistent.
    static let pictureJPEGQuality = 0.6

    /// A page with this much continuous tone is a picture, whatever its ink
    /// coverage. Ink coverage alone was a broken test: warm and light colours
    /// have a *high* greyscale luminance (pure yellow is 226, pale cyan 217), so
    /// a page of tinted figures scored near zero coverage — the picture signal
    /// was at its minimum for exactly the pages thresholding destroys. Measured:
    /// a tinted isobar figure lost 99.1% of its visible content.
    static let pictureToneThreshold = 0.12

    /// And any real colour means a page is not plain text — where "colour" means
    /// colour the page's own paper does not already have. See `saturation`.
    static let pictureSaturationThreshold = 0.06

    /// A pixel this bright is paper rather than ink, for the purpose of working
    /// out what colour the paper is.
    ///
    /// 176 is 69% of white. Cream book stock measures 219–245 per channel and
    /// clears it comfortably; text ink on the same page sits under 90. The value
    /// only has to separate the two populations on a page that *has* two, and it
    /// is not finely balanced — anything from about 140 to 200 selects the same
    /// paper on the corpus.
    static let paperLuminanceFloor = 176.0

    /// …and this much of the page has to be paper before its colour is believed.
    ///
    /// Below it there is no paper to speak of — a full-bleed photograph, a dark
    /// cover — and correcting for a "paper" measured from the brightest corner of
    /// a photograph would neutralise a real colour cast. Such pages keep the
    /// uncorrected measure, which is the behaviour that shipped.
    static let minimumPaperFraction = 0.15

    /// Below this, the largest embedded image is *not* the page's scan — it is a
    /// logo, a rule or a figure on a born-digital page — and rebuilding at its
    /// resolution destroys everything else on the sheet.
    ///
    /// Measured across the 78-document corpus, 214 sampled pages: 84 report
    /// under 150 DPI and 35 under 72. The worst is a born-digital magazine page
    /// carrying 1,846 characters of text whose largest image implies **1.9 DPI**
    /// — it rebuilt a 595x841 pt page as a **16 x 23 pixel** image. The page
    /// count still matched, so the run reported success.
    ///
    /// A genuine scan is essentially never below this. Treating a real 100 DPI
    /// scan as 300 upsamples it, which costs bytes and loses nothing;
    /// treating a logo's 1.9 DPI as the page's resolution loses the page.
    /// The asymmetry is the whole argument for erring high.
    static let minimumPlausibleScanDPI: Double = 150

    /// What to rebuild at when the page's own resolution can't be trusted.
    static let fallbackRebuildDPI: Double = 300

    /// Refuse a page whose raster would be larger than this, rather than trying.
    ///
    /// `renderGrey` allocates `width * height` bytes, and a Swift array that
    /// cannot be allocated is a **crash**, not a catchable error — so an
    /// enormous sheet at a high native resolution took the whole process down,
    /// taking every other file in flight with it.
    ///
    /// Deliberately a refusal and not a downscale: the policy for this pipeline
    /// is fidelity, so a page is rendered at its own resolution or not at all.
    /// A silent downscale would be the "publishing something plausible" that
    /// invariant 1 forbids.
    ///
    /// 400 megapixels is ~19x the largest page in the 78-document corpus
    /// (21.5 MP, a 3600x5967 journal scan), and is a 33x44 inch E-size sheet at
    /// 600 DPI — so it does not reject real archival material. Measured across
    /// all 4,992 corpus pages: none exceed 100 MP.
    static let maximumPageMegapixels = 400

    /// The most megapixels a page may be before its colour is given up.
    ///
    /// Above it the page still rebuilds — in grey, as it always did — because a
    /// coarser rendering of one big plate is a quality loss, while a failed
    /// two-gigabyte allocation takes down every file running alongside it.
    ///
    /// **Derived from measurement, not from arithmetic.** The first version of
    /// this said "a colour render is four bytes a pixel where grey is one, so a
    /// quarter keeps peak memory unchanged", which is wrong twice over: the grey
    /// buffer is still alive when the RGBA one is allocated, and both are then
    /// copied into a 24-bit bitmap rep, a JPEG, and a decoded CGImage on the way
    /// into the PDF. Measured peak RSS on one 64.8 MP page: **356 MB grey,
    /// 1,261 MB colour** — 5.5 and 19.5 bytes per pixel, a ratio of 3.5, not 4.
    ///
    /// What makes 100 defensible is that it lands *below* a ceiling this app
    /// already lived with: 100 MP of colour peaks near 1.95 GB, and a 400 MP
    /// grey page — which `maximumPageMegapixels` has always allowed — peaks near
    /// 2.20 GB. So colour cannot reach a high-water mark grey could not.
    /// `colourBoundIsWithinTheGreyOne` checks that, so raising either constant
    /// without re-measuring fails rather than quietly doubling the worst case.
    static let maximumColourPageMegapixels = 100

    /// Peak process bytes per pixel on each rebuild path, measured rather than
    /// reasoned about — see `maximumColourPageMegapixels`. Re-measure if the
    /// encoding path changes; they are here so the bound can be checked.
    static let measuredGreyBytesPerPixel = 5.5
    static let measuredColourBytesPerPixel = 19.5

    /// Whether the colour bound's worst case stays inside the grey one's.
    static var colourBoundIsWithinTheGreyOne: Bool {
        Double(maximumColourPageMegapixels) * measuredColourBytesPerPixel
            <= Double(maximumPageMegapixels) * measuredGreyBytesPerPixel
    }

    /// The most megapixels mac-ocr will render a PDF page to before refusing.
    ///
    /// Its own limit, not ours, and **lower than ours** — we refuse past 400 MP
    /// (`maximumPageMegapixels`), it refuses past 200. So a page we happily
    /// rebuild can be one it will not read, and the run fails at recognition
    /// with "PDF page at 300 DPI would render to 250 megapixels (max 200 MP)"
    /// after all the rebuild work is done. Taken from that message rather than
    /// from documentation, because that message is what the shipped binary
    /// actually enforces (U25).
    static let recogniserPageMegapixelLimit = 200

    /// The highest `--pdf-dpi` at which every page of this document stays inside
    /// the recogniser's limit, or nil if no page is near it.
    ///
    /// Returned so the caller can ask for a DPI that works instead of letting
    /// the default fail: a slightly coarser render of one enormous broadsheet is
    /// worth more than no text at all, and it changes nothing for the documents
    /// that were never close.
    static func recogniserDPICeiling(for url: URL, password: String? = nil) -> Int? {
        guard let doc = open(url, password: password) else { return nil }
        var lowest = Int.max
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let box = fullBox(of: page)
            let inches = (box.width / 72.0) * (box.height / 72.0)
            guard inches > 0, inches.isFinite else { continue }
            // pixels = inches² × dpi², so dpi = sqrt(limit / inches²).
            let ceiling = (Double(recogniserPageMegapixelLimit) * 1_000_000 / inches).squareRoot()
            // A little under, because the limit is a refusal and rounding at the
            // boundary would still fail.
            lowest = min(lowest, safeInt(ceiling * 0.98))
        }
        // 72 is the floor mac-ocr itself accepts; below that there is nothing
        // useful to ask for and the document simply cannot be read.
        //
        // Nil means "nothing to measure" — no pages, or a file PDFKit could not
        // open — never "fine at some particular DPI". Comparing against a
        // default here is what made a 30 x 40 poster fail at a requested 600:
        // it needs no ceiling at 300, so none was reported, so nothing clamped
        // the 600 the recogniser then refused. Deciding *whether* the ceiling
        // binds is the caller's job, and `recognitionArguments` does it by
        // taking the lower of this and what was asked for (U25).
        return lowest == Int.max ? nil : max(lowest, 72)
    }

    /// The largest `/Width` or `/Height` worth believing from an image XObject.
    /// Those are declarations, not measurements: `CGPDFInteger` is 64-bit, the
    /// stream behind them can be three bytes, and nothing cross-checks the two.
    /// 200,000 px is a 26-inch sheet at 7,700 DPI — past anything real, and
    /// small enough that the product of two of them cannot overflow `Int` (R24).
    static let maximumDeclaredImageSide = 200_000

    /// `Int(_:)` traps for a Double that is not finite or is outside `Int`'s
    /// range. Every dimension in this file descends from a number some document
    /// declared, so the conversion is never safe on its own (R24).
    static func safeInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        if value >= 9.0e18 { return Int(9.0e18) }
        if value <= -9.0e18 { return Int(-9.0e18) }
        return Int(value)
    }

    enum Failure: LocalizedError {
        case unreadable
        case cannotWrite
        case pageFailed(page: Int, of: Int)
        case locked
        case pageTooLarge(page: Int, megapixels: Int, dpi: Int)

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Could not read the PDF to rebuild it."
            case .cannotWrite: return "Could not write the rebuilt PDF."
            case .locked:
                return "The PDF is password-protected. Enter its password in "
                    + "Settings, under PDF password."
            case .pageFailed(let page, let total):
                return "Page \(page) of \(total) could not be rendered, "
                    + "so the rebuild would have been missing a page."
            case .pageTooLarge(let page, let megapixels, let dpi):
                // Named numbers, so the size and where it came from are visible.
                //
                // The remedy has to be one that works. This used to send the
                // user to "PDF render DPI", which is a real control with a
                // convincing name and no effect here: it becomes mac-ocr's
                // --pdf-dpi for the recognition pass, and this throws long
                // before that runs. Flattener reads nothing from Prefs — the
                // rebuild resolution is always the page's own. The only setting
                // that lets the file through is the one that stops the rebuild
                // happening at all (R26).
                return "Page \(page) would rebuild to \(megapixels) megapixels at "
                    + "its own \(dpi) DPI, past the \(maximumPageMegapixels) MP limit. "
                    + "Nothing was written. To process this file, turn off "
                    + "\"Rebuild page images first\" in Settings. The PDF render "
                    + "DPI setting does not affect this step."
            }
        }
    }

    /// True if any page carries selectable text — the case that needs rebuilding.
    /// Stops at the first hit rather than reading a 600-page book to the end.
    static func hasEmbeddedText(_ url: URL, password: String? = nil) -> Bool {
        guard let doc = open(url, password: password) else { return false }
        for i in 0..<doc.pageCount {
            let s = doc.page(at: i)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !s.isEmpty { return true }
        }
        return false
    }

    /// Is this page a picture of a page, rather than a page?
    ///
    /// A scan is one big raster. 900 px across is about 110 DPI on a Letter
    /// sheet — below that it is a figure, a logo or a cover thumbnail, not the
    /// page itself. The upper bound rejects the absurd resolutions that come
    /// from a mis-declared box rather than a scanner.
    static func pageIsAnImage(_ page: PDFPage) -> Bool {
        guard let largest = largestImage(of: page) else { return false }
        return largest.pixelWidth >= 900 && largest.dpi >= 72 && largest.dpi <= 1400
    }

    /// Does this file already carry **real digital text**, as opposed to an OCR
    /// layer over a scan?
    ///
    /// This is the whole of C17, and the distinction is not "does it have text".
    /// Both kinds of file do. The difference is what the text sits on:
    ///
    /// - a **scan** that has been OCR'd before has text *over a full-page image*.
    ///   Rebuilding it is right — that strips a previous OCR pass which would
    ///   otherwise double up, which is why `rebuildImages` defaults on.
    /// - a **born-digital** page has text and no page-sized raster at all.
    ///   Rebuilding it throws away better text than Vision can produce and
    ///   replaces it with OCR of a picture of that text. Measured on three pages
    ///   of a born-digital book: 1,031 words became 938, and only 86.1% of the
    ///   output's words existed in the original.
    ///
    /// Pages are sampled through the document rather than from the front: a
    /// born-digital book often has a raster cover, and a scan often has a clean
    /// title page, so page 1 is the least informative page in either.
    ///
    /// Conservative by construction — it answers "yes" only when a majority of
    /// sampled pages carry substantial text *and* no page-sized image. A
    /// false negative costs the user nothing but the warning; a false positive
    /// puts a question in front of someone who did not need one.
    static func hasDigitalText(_ url: URL, password: String? = nil) -> Bool {
        guard let doc = open(url, password: password), doc.pageCount > 0 else { return false }
        let total = doc.pageCount
        let wanted = min(4, total)
        let indices = (0..<wanted).map { total <= 4 ? $0 : ($0 + 1) * total / (wanted + 1) }

        var digital = 0, sampled = 0
        for i in indices {
            guard let page = doc.page(at: i) else { continue }
            sampled += 1
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // 120 characters is about two lines. Below that a page is a plate,
            // a blank, or a part title, and says nothing either way.
            if text.count >= 120, !pageIsAnImage(page) { digital += 1 }
        }
        guard sampled > 0 else { return false }
        return digital * 2 > sampled
    }

    /// A PDF wrapping an image file, so the rest of the pipeline — which is all
    /// PDF-shaped — can accept the PNG/JPEG/HEIC/TIFF inputs the drop box
    /// advertises. Previously those failed with "Could not read the rebuilt PDF",
    /// which blamed the user's file.
    ///
    /// **One page per image in the file, not one page.** A container format can
    /// hold many: a multi-page TIFF is the standard output of every sheet-fed
    /// archival scanner, and reading only image 0 silently discarded every sheet
    /// after the first — a whole document reduced to its cover page, published
    /// as a success because one page in is one page out.
    static func wrapImage(_ url: URL, into directory: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        /// One image, oriented, with the page size its resolution implies.
        func page(at index: Int) -> (image: CGImage, box: CGRect)? {
            guard let decoded = CGImageSourceCreateImageAtIndex(source, index, nil)
            else { return nil }
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any]

            // EXIF orientation, which CGImageSourceCreateImageAtIndex does *not*
            // apply — it hands back the stored pixels. A phone photo shot in
            // portrait is stored landscape with an orientation tag, so it was
            // wrapped sideways: a landscape page with the text running up it.
            //
            // Rendered through CoreImage rather than by composing the transform
            // by hand. Hand-rolled quarter-turn arithmetic is what drew rotated
            // PDF pages off-canvas, and these are single images, not books.
            var image = decoded
            let raw = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
            if raw != 1, let orientation = CGImagePropertyOrientation(rawValue: raw) {
                let oriented = CIImage(cgImage: decoded).oriented(orientation)
                if let turned = CIContext().createCGImage(oriented, from: oriented.extent) {
                    image = turned
                }
            }

            // Both axes, separately. A scanner or fax can record different
            // horizontal and vertical resolution — 200x100 dpi is a standard fax
            // mode — and using the horizontal figure for both squashed the page
            // by the ratio between them. 72 dpi unless the file says otherwise,
            // so an image with no resolution recorded still gets a sensible size.
            func resolution(_ key: CFString) -> Double {
                (props?[key] as? Double).flatMap { $0 > 1 ? $0 : nil } ?? 72
            }
            var dpiX = resolution(kCGImagePropertyDPIWidth)
            var dpiY = resolution(kCGImagePropertyDPIHeight)
            // A quarter turn swaps which axis each resolution describes.
            if [5, 6, 7, 8].contains(raw) { swap(&dpiX, &dpiY) }

            return (image, CGRect(x: 0, y: 0,
                                  width: Double(image.width) * 72.0 / dpiX,
                                  height: Double(image.height) * 72.0 / dpiY))
        }

        guard let first = page(at: 0) else { return nil }
        var box = first.box
        let dest = directory.appendingPathComponent(
            url.deletingPathExtension().lastPathComponent + ".pdf")
        guard let pdf = CGContext(dest as CFURL, mediaBox: &box, nil) else { return nil }

        for index in 0..<count {
            // Refusing beats dropping: a sheet we cannot decode must not vanish
            // from the middle of a document with the run still reporting success.
            guard let this = index == 0 ? first : page(at: index) else {
                pdf.closePDF()
                try? FileManager.default.removeItem(at: dest)
                return nil
            }
            // Per-page box as CFData — sheets in one TIFF need not match, and an
            // NSValue here is silently ignored (invariant 4).
            var pageBox = this.box
            let boxData = withUnsafeBytes(of: &pageBox) { Data($0) } as CFData
            pdf.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            pdf.draw(this.image, in: pageBox)
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return dest
    }

    /// Opens a PDF, unlocking it if a password is supplied. Returns nil when the
    /// file is unreadable or still locked afterwards.
    static func open(_ url: URL, password: String?) -> PDFDocument? {
        guard let doc = PDFDocument(url: url) else { return nil }
        if doc.isLocked, let password, !password.isEmpty {
            _ = doc.unlock(withPassword: password)
        }
        return doc.isLocked ? nil : doc
    }

    /// What one rebuilt page looked like, for a later compression pass.
    struct RebuiltPage {
        /// Which codec this page needs. Automatic mode mixes both in one book.
        enum Content {
            /// 1-bit PNG, ready for jbig2enc.
            case bilevel(URL)
            /// Already-encoded JPEG, embedded as-is. Grey for a halftone,
            /// RGB for a page with real colour in it — `isColour` says which,
            /// because the JBIG2 merge has to declare the right colour space
            /// and a colour stream labelled /DeviceGray renders as garbage.
            case jpeg(URL)
        }
        let content: Content
        let pixelWidth: Int
        let pixelHeight: Int
        let boxSize: CGSize
        /// True when `content` is a three-channel JPEG.
        var isColour = false
    }

    /// Rebuilds `source` into `destination` as image-only pages.
    /// `progress` is called with (pagesDone, pageCount) and may run on any thread.
    /// Returns early if `isCancelled` starts returning true.
    ///
    /// When `pngDirectory` is given, each page is also written there as a 1-bit
    /// PNG so an external encoder can compress it better than CoreGraphics can.
    /// Only black-and-white mode produces those, since JBIG2 is bilevel-only.
    @discardableResult
    static func flatten(
        _ source: URL,
        to destination: URL,
        mode: Mode,
        password: String? = nil,
        pngDirectory: URL? = nil,
        isCancelled: () -> Bool = { false },
        progress: (Int, Int) -> Void = { _, _ in },
        onPage: ((RebuiltPage) throws -> Void)? = nil
    ) throws -> [RebuiltPage] {
        var rebuilt: [RebuiltPage] = []
        guard let doc = open(source, password: password) else {
            // Distinguish "needs a password" from "not a PDF": the first is
            // fixable by the user, and a locked document would otherwise render
            // as blank pages with no complaint.
            throw PDFDocument(url: source)?.isLocked == true
                ? Failure.locked : Failure.unreadable
        }
        guard doc.pageCount > 0, let first = doc.page(at: 0) else {
            throw Failure.unreadable
        }

        // Seed the context with page 1's *display* box. The per-page override
        // below should govern, but CoreGraphics falls back to this one, so a
        // rotated first page would otherwise stretch into the wrong shape.
        var mediaBox = fullBox(of: first)
        guard let pdf = CGContext(destination as CFURL, mediaBox: &mediaBox, nil) else {
            throw Failure.cannotWrite
        }

        // Close the context on every exit, or a throw mid-document leaves a
        // readable but silently truncated PDF behind.
        var finished = false
        defer { if !finished { pdf.closePDF() } }

        let count = doc.pageCount
        for index in 0..<count {
            if isCancelled() { break }
            guard let page = doc.page(at: index) else {
                throw Failure.pageFailed(page: index + 1, of: count)
            }
            // A page with /Rotate set displays at swapped dimensions, and its
            // content has to be rotated into place. Getting this wrong drew the
            // page off-canvas and produced a blank rebuild — total content loss
            // for any sideways plate.
            // The whole sheet, not the crop: a rebuild that kept only the crop
            // would silently discard everything outside it. See fullBox.
            let box = fullBox(of: page)

            // Render at the scan's own resolution: no upsampling, no lost
            // detail — but only when that resolution is believable. See
            // rebuildDPI.
            let dpi = rebuildDPI(of: page)
            let scale = dpi / 72.0

            // Decide in Double and convert only once the value is known to be
            // small enough. `Int(_:)` traps for a Double outside Int's range,
            // and both the box and the scale descend from numbers the file
            // declared — so the conversion itself was a crash on a malformed
            // page, before any guard could look at it (R24).
            let wide = (box.width * scale).rounded()
            let high = (box.height * scale).rounded()
            guard wide.isFinite, high.isFinite, wide >= 1, high >= 1 else {
                throw Failure.pageFailed(page: index + 1, of: count)
            }

            // Before allocating, not after: renderGrey asks for width * height
            // bytes and an array that cannot be allocated crashes the process
            // rather than throwing, which would take every concurrent file with
            // it. See maximumPageMegapixels — this refuses rather than
            // downscaling, because the policy here is fidelity.
            //
            // In Double as well, for the same reason: multiplying the two in Int
            // overflowed and trapped *inside the guard meant to prevent exactly
            // this crash*.
            guard wide * high <= Double(maximumPageMegapixels) * 1_000_000 else {
                throw Failure.pageTooLarge(page: index + 1,
                                           megapixels: safeInt(wide * high / 1_000_000),
                                           dpi: safeInt(dpi.rounded()))
            }
            let width = max(Int(wide), 1)
            let height = max(Int(high), 1)

            guard let grey = renderGrey(page, box: box, scale: scale,
                                        width: width, height: height,
                                        from: .mediaBox) else {
                throw Failure.pageFailed(page: index + 1, of: count)
            }

            // Decide per page in automatic mode. One threshold per page, derived
            // from its own histogram, used for both the rendering and the
            // is-this-a-picture test.
            //
            // Decide *before* rendering anything. This used to build the bilevel
            // image first and throw it away for picture pages, on the stated
            // grounds that its ink coverage was what identified a picture — but
            // `isPicture` reads the grey buffer, not the bilevel one, so the
            // threshold pass was pure waste on exactly the pages that also pay
            // for a JPEG.
            let threshold = otsuThreshold(of: grey)
            var useBilevel = mode != .grayscale
            // Measured once and used twice: as one of the three picture signals,
            // and to decide whether the picture it found is a colour one.
            let sat = mode == .auto ? saturation(of: page) : 0
            if useBilevel, mode == .auto,
               isPicture(page, grey: grey, width: width, height: height,
                         threshold: threshold, saturation: sat) {
                useBilevel = false
            }

            // A page with real colour in it keeps its colour, in Automatic only.
            //
            // Black & white is an instruction and Grayscale is an instruction;
            // Automatic is the one that is supposed to work out what the page
            // needs, and until now its answer for a colour plate was grey — the
            // detector could *see* the colour, since saturation is one of the
            // three signals that route the page here, and then threw it away.
            //
            // Bounded by megapixels because the colour path costs ~3.5x the
            // peak memory of the grey one, measured. Over the bound the page
            // rebuilds grey, exactly as it used to.
            let wantColour = !useBilevel
                && shouldKeepColour(mode: mode, saturation: sat, pixels: wide * high)

            // Encoded once, whichever way it goes. The JPEG bytes are reused for
            // the stream file below rather than encoded a second time.
            var jpegBytes: Data?
            var isColour = false
            let image: CGImage?
            if useBilevel {
                image = bilevelImage(from: grey, width: width, height: height,
                                     threshold: threshold)
            } else if wantColour,
                      let rgba = renderRGB(page, box: box, scale: scale,
                                           width: width, height: height, from: .mediaBox),
                      let encoded = jpegRGB(from: rgba, width: width, height: height,
                                            quality: pictureJPEGQuality) {
                // Falls through to grey if either step fails rather than failing
                // the page: colour is an improvement on grey, not a requirement,
                // and there is a correct grey rendering already in hand.
                jpegBytes = encoded.data
                image = encoded.image
                isColour = true
            } else {
                let encoded = jpeg(from: grey, width: width, height: height,
                                   quality: pictureJPEGQuality)
                jpegBytes = encoded?.data
                image = encoded?.image
            }
            guard let image else { throw Failure.pageFailed(page: index + 1, of: count) }

            // Per-page media box: page sizes vary across a scanned book, and an
            // A5 page stamped into a Letter box comes out visibly stretched.
            //
            // The value has to be CFData wrapping the CGRect. Passing an NSValue
            // is accepted and silently ignored, which is how every page ended up
            // with page 1's dimensions.
            var pageBox = CGRect(origin: .zero, size: box.size)
            let boxData = withUnsafeBytes(of: &pageBox) { Data($0) } as CFData
            pdf.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            pdf.draw(image, in: pageBox)
            pdf.endPDFPage()

            if let pngDirectory {
                let stem = String(format: "p%05d", index + 1)
                if useBilevel {
                    let png = pngDirectory.appendingPathComponent(stem + ".png")
                    guard writePNG(image, to: png) else {
                        // Silently omitting it made the caller fall back to the
                        // 3x larger route with no explanation, on what is really
                        // a disk-full or permissions fault.
                        throw Failure.pageFailed(page: index + 1, of: count)
                    }
                    if true {
                        let entry = RebuiltPage(content: .bilevel(png), pixelWidth: width,
                                                pixelHeight: height, boxSize: box.size)
                        rebuilt.append(entry)
                        try onPage?(entry)
                    }
                } else {
                    // Literally the bytes embedded in the PDF above, not a second
                    // encode of the same buffer, so the compressed build and the
                    // fallback build cannot drift apart.
                    let jpeg = pngDirectory.appendingPathComponent(stem + ".jpg")
                    guard let data = jpegBytes,
                          (try? data.write(to: jpeg)) != nil else {
                        throw Failure.pageFailed(page: index + 1, of: count)
                    }
                    if true {
                        let entry = RebuiltPage(content: .jpeg(jpeg), pixelWidth: width,
                                                pixelHeight: height, boxSize: box.size,
                                                isColour: isColour)
                        rebuilt.append(entry)
                        try onPage?(entry)
                    }
                }
            }

            progress(index + 1, count)
        }
        pdf.closePDF()
        finished = true
        return rebuilt
    }

    /// CGImageDestination widens the 1-bit image to 8-bit grey on the way out,
    /// so the file holds only 0 and 255. jbig2enc then re-thresholds at its own
    /// default (200), which lands every 0 on black and every 255 on white — the
    /// same bitmap we started with. Harmless, but don't introduce anti-aliasing
    /// here or the two thresholds would start to disagree.
    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    // MARK: - Rendering

    /// The area a viewer shows, with /Rotate applied — the **crop** box.
    ///
    /// Measured, not assumed: given a page with MediaBox 612x792 and CropBox
    /// (100,100)-(412,500), mac-ocr reported a 312x400 render and recognised only
    /// the word inside the crop. So Vision's normalised observations come back
    /// relative to the crop box, and anything mapping them onto a page must use
    /// the same box or every one of them is offset and rescaled.
    ///
    /// Use this to agree with a recogniser about a file it was handed. To decide
    /// what to *keep*, use `fullBox` — see the note there.
    ///
    /// `bounds(for: .cropBox)` falls back to the media box when a page has no
    /// crop box, which is the overwhelmingly common case (44 of 78 corpus
    /// documents have no crop box at all, and 26 more set it equal to the media
    /// box).
    static func displayBox(of page: PDFPage) -> CGRect {
        boxSize(page.bounds(for: .cropBox), rotation: page.rotation)
    }

    /// The whole sheet, with /Rotate applied — the **media** box.
    ///
    /// The rebuild renders this, not the crop box, because a rebuild that only
    /// kept the crop would silently discard whatever lies outside it, which
    /// invariant 1 forbids. It is also measurably worse: cropping the rebuild of
    /// `Margalit_2013` (media 546x762, crop 504x720) took line separation from
    /// 100% to 90%.
    ///
    /// There is no mismatch in doing so. The rebuilt file carries only a media
    /// box, so when the recogniser and then `compose` look at *it*, `displayBox`
    /// falls back to that same media box and all three agree.
    static func fullBox(of page: PDFPage) -> CGRect {
        boxSize(page.bounds(for: .mediaBox), rotation: page.rotation)
    }

    /// PDFKit's `bounds(for:)` reports the unrotated box, so a 90°-rotated page
    /// has to have its dimensions swapped.
    private static func boxSize(_ box: CGRect, rotation: Int) -> CGRect {
        let quarterTurns = ((rotation % 360) + 360) % 360
        if quarterTurns == 90 || quarterTurns == 270 {
            return CGRect(origin: .zero, size: CGSize(width: box.height, height: box.width))
        }
        return CGRect(origin: .zero, size: box.size)
    }

    /// 8-bit greyscale render of one page. Greyscale rather than RGB because
    /// these are scans, and it is a third of the memory.
    ///
    /// Draws through `CGPDFPageGetDrawingTransform`, which is the only thing that
    /// gets rotation, cropping and centring right; a hand-rolled translate drew
    /// rotated pages off the canvas entirely.
    /// `from` must be the box `box` was measured with, or the page is drawn to
    /// the wrong scale: pass `.mediaBox` alongside `fullBox`, `.cropBox`
    /// alongside `displayBox`.
    static func renderGrey(
        _ page: PDFPage, box: CGRect, scale: CGFloat, width: Int, height: Int,
        from pdfBox: CGPDFBox = .mediaBox
    ) -> [UInt8]? {
        var buffer = [UInt8](repeating: 255, count: width * height)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            guard let cgPage = page.pageRef else {
                // No CGPDFPage (unlikely): fall back to PDFKit's own drawing.
                ctx.scaleBy(x: scale, y: scale)
                page.draw(with: pdfBox == .cropBox ? .cropBox : .mediaBox, to: ctx)
                return true
            }
            ctx.scaleBy(x: scale, y: scale)
            ctx.concatenate(cgPage.getDrawingTransform(
                pdfBox, rect: CGRect(origin: .zero, size: box.size),
                rotate: 0, preserveAspectRatio: true))
            ctx.drawPDFPage(cgPage)
            return true
        }
        return ok ? buffer : nil
    }

    /// Whether a page already routed away from 1-bit should keep its colour.
    ///
    /// Extracted from `flatten` so the megapixel bound can be checked without
    /// allocating the page it describes — a check that has to render 100 MP to
    /// find out is a check nobody runs.
    static func shouldKeepColour(mode: Mode, saturation: Double, pixels: Double) -> Bool {
        guard mode == .auto else { return false }
        guard saturation > pictureSaturationThreshold else { return false }
        return pixels <= Double(maximumColourPageMegapixels) * 1_000_000
    }

    /// 8-bit RGBA render of one page, for the pages that have colour worth
    /// keeping. Four bytes a pixel against `renderGrey`'s one — and the grey
    /// buffer is still alive alongside it, which is half of why
    /// `maximumColourPageMegapixels` exists and is measured rather than derived.
    ///
    /// Identical to `renderGrey` in every other respect, deliberately: same
    /// drawing transform, same white fill, same fallback. Rotation and cropping
    /// are the part that has silently produced blank pages before, and having
    /// two ways to draw a page is how the two drift.
    static func renderRGB(
        _ page: PDFPage, box: CGRect, scale: CGFloat, width: Int, height: Int,
        from pdfBox: CGPDFBox = .mediaBox
    ) -> [UInt8]? {
        var buffer = [UInt8](repeating: 255, count: width * height * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            guard let cgPage = page.pageRef else {
                ctx.scaleBy(x: scale, y: scale)
                page.draw(with: pdfBox == .cropBox ? .cropBox : .mediaBox, to: ctx)
                return true
            }
            ctx.scaleBy(x: scale, y: scale)
            ctx.concatenate(cgPage.getDrawingTransform(
                pdfBox, rect: CGRect(origin: .zero, size: box.size),
                rotate: 0, preserveAspectRatio: true))
            ctx.drawPDFPage(cgPage)
            return true
        }
        return ok ? buffer : nil
    }

    /// JPEG-encode an RGBA buffer as three-channel colour, giving back the bytes
    /// and an image over them — the colour twin of `jpeg(from:)`.
    ///
    /// The alpha channel is dropped here rather than left to the encoder. Every
    /// pixel is opaque (the buffer starts as opaque white and the page is drawn
    /// over it), so there is nothing to composite, and a 24-bit representation
    /// is what the PDF stream declares: three components, /DeviceRGB.
    static func jpegRGB(
        from rgba: [UInt8], width: Int, height: Int, quality: Double
    ) -> (data: Data, image: CGImage)? {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 3, bitsPerPixel: 24)
        else { return nil }
        guard let dest = rep.bitmapData else { return nil }
        for pixel in 0..<(width * height) {
            dest[pixel * 3]     = rgba[pixel * 4]
            dest[pixel * 3 + 1] = rgba[pixel * 4 + 1]
            dest[pixel * 3 + 2] = rgba[pixel * 4 + 2]
        }
        guard let data = rep.representation(using: .jpeg,
                                            properties: [.compressionFactor: quality]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return (data, image)
    }

    /// Otsu's threshold: the split that best separates the page's two tonal
    /// populations, paper and ink.
    ///
    /// A fixed threshold is wrong for anything but bright white paper. On a grey
    /// mimeograph or a yellowed typescript the paper itself falls below 186, so
    /// 86-98% of the page reads as "ink": thresholding turned such pages almost
    /// solid black, and the ink-coverage test then classified them as pictures and
    /// sent them down the greyscale path at ~1 MB/page.
    static func otsuThreshold(of grey: [UInt8]) -> UInt8 {
        var histogram = [Int](repeating: 0, count: 256)
        for value in grey { histogram[Int(value)] += 1 }
        let total = grey.count
        guard total > 0 else { return 186 }

        var sum = 0.0
        for i in 0..<256 { sum += Double(i) * Double(histogram[i]) }
        var sumB = 0.0, weightB = 0, best = 0.0
        var chosen = 186
        for t in 0..<256 {
            weightB += histogram[t]
            if weightB == 0 { continue }
            let weightF = total - weightB
            if weightF == 0 { break }
            sumB += Double(t) * Double(histogram[t])
            let meanB = sumB / Double(weightB)
            let meanF = (sum - sumB) / Double(weightF)
            let between = Double(weightB) * Double(weightF) * (meanB - meanF) * (meanB - meanF)
            if between > best { best = between; chosen = t }
        }
        // Keep it in a sane band: a page of solid tone has no meaningful split.
        return UInt8(min(max(chosen, 90), 230))
    }

    /// Threshold to 1 bit, packed MSB-first, 1 = white.
    private static func bilevelImage(
        from grey: [UInt8], width: Int, height: Int, threshold: UInt8
    ) -> CGImage? {
        let rowBytes = (width + 7) / 8
        var bits = [UInt8](repeating: 0, count: rowBytes * height)
        for y in 0..<height {
            let src = y * width, dst = y * rowBytes
            for x in 0..<width where grey[src + x] >= threshold {
                bits[dst + (x >> 3)] |= UInt8(0x80) >> UInt8(x & 7)
            }
        }
        guard let provider = CGDataProvider(data: Data(bits) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 1, bitsPerPixel: 1,
            bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Is this page a picture rather than text? Any one of three signals is
    /// enough, because each misses cases the others catch:
    ///
    ///  - heavy ink: dark scans and coarse halftones;
    ///  - continuous tone: photographs and tinted figures, which can be *lighter*
    ///    than text and so invisible to an ink-coverage test;
    ///  - colour: a coloured page is never plain text, and thresholding it is
    ///    always destructive.
    /// Diagnostic view of the three signals, for calibration.
    static func pictureSignals(_ page: PDFPage, grey: [UInt8], width: Int, height: Int)
        -> (ink: Double, tone: Double, sat: Double, threshold: Int) {
        let t = otsuThreshold(of: grey)
        return (inkCoverage(of: grey, width: width, height: height, threshold: t),
                toneFraction(of: grey, threshold: t), saturation(of: page), Int(t))
    }

    /// `saturation` may be passed in when the caller has already measured it.
    /// The signal costs a second render of the page, and `flatten` needs the
    /// number anyway to decide between a grey JPEG and a colour one — measuring
    /// it twice per illustrated page was pure waste.
    static func isPicture(_ page: PDFPage, grey: [UInt8],
                          width: Int, height: Int, threshold: UInt8,
                          saturation precomputed: Double? = nil) -> Bool {
        if inkCoverage(of: grey, width: width, height: height,
                       threshold: threshold) > pictureInkThreshold { return true }
        if toneFraction(of: grey, threshold: threshold) > pictureToneThreshold { return true }
        return (precomputed ?? saturation(of: page)) > pictureSaturationThreshold
    }

    /// Fraction of pixels that are neither near-white nor near-black. Text is
    /// bimodal — paper and ink — so only its anti-aliased edges land in between.
    static func toneFraction(of grey: [UInt8], threshold: UInt8) -> Double {
        guard !grey.isEmpty else { return 0 }
        // A band around the split. Text is bimodal, so little lands here; a
        // photograph or a tint fills it. Measured against the page's own
        // threshold so grey paper doesn't read as continuous tone.
        let lo = Int(threshold) - 45, hi = Int(threshold) + 45
        var mid = 0
        for value in grey where Int(value) > lo && Int(value) < hi { mid += 1 }
        return Double(mid) / Double(grey.count)
    }

    /// The longest edge the routing thumbnail may have.
    ///
    /// At 40 DPI a page would have to be **100 inches** on a side to reach this,
    /// which is past the 200-inch ceiling PDF ≤1.5 imposes on a page box at all
    /// and far past any archival sheet — so no real document is resized by it.
    /// What it bounds is the unreal ones: 4,000 px caps the buffer at 64 MB (R29).
    static let maximumThumbnailEdge = 4_000

    /// Pixel size of the routing thumbnail for a page box, and the scale that
    /// produces it. Nil when the box is not a usable rectangle.
    ///
    /// Separate from `saturation` so the bound can be asserted directly. R24
    /// bounded `flatten`'s *render*, which is the box scaled by the page's own
    /// DPI; this is the box scaled by a **fixed** 40 DPI, and the two diverge
    /// exactly when a huge box carries a small image — `rebuildDPI` then returns
    /// a tiny DPI, the render is small and passes R24's guard, and this one was
    /// still sized off the raw box. At `[0 0 1000000000000 1000000000000]`,
    /// `w * h * 4` overflowed `Int` and took the process down with SIGTRAP (R29).
    static func thumbnailSize(for box: CGRect) -> (width: Int, height: Int, scale: CGFloat)? {
        guard box.width.isFinite, box.height.isFinite,
              box.width > 0, box.height > 0 else { return nil }
        let longest = max(box.width, box.height)
        // Never magnify: a small page keeps its 40 DPI thumbnail.
        let scale: CGFloat = min(40.0 / 72.0, CGFloat(maximumThumbnailEdge) / longest)
        let w = max(min(safeInt(box.width * scale), maximumThumbnailEdge), 1)
        let h = max(min(safeInt(box.height * scale), maximumThumbnailEdge), 1)
        return (w, h, scale)
    }

    /// Mean saturation from a small RGB thumbnail. Cheap: the page is redrawn at
    /// about 40 DPI purely to ask whether there is colour on it.
    static func saturation(of page: PDFPage) -> Double {
        // The same area flatten rebuilds, so the routing signal describes the
        // page that actually gets written.
        let box = fullBox(of: page)
        guard let (w, h, scale) = thumbnailSize(for: box) else { return 0 }
        var buffer = [UInt8](repeating: 255, count: w * h * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            guard let cgPage = page.pageRef else { return false }
            ctx.scaleBy(x: scale, y: scale)
            ctx.concatenate(cgPage.getDrawingTransform(
                .mediaBox, rect: CGRect(origin: .zero, size: box.size),
                rotate: 0, preserveAspectRatio: true))
            ctx.drawPDFPage(cgPage)
            return true
        }
        guard ok else { return 0 }
        return saturation(ofRGBA: buffer, width: w, height: h)
    }

    /// The colour of the page's own paper, or nil when the page has no credible
    /// paper on it. The mean of every pixel bright enough to be paper.
    ///
    /// Split out so it can be asserted directly, and because the "no paper here"
    /// answer is a real one that the caller has to handle rather than a failure.
    static func paperColour(ofRGBA buffer: [UInt8], width: Int, height: Int)
        -> (r: Double, g: Double, b: Double)? {
        let pixels = width * height
        guard pixels > 0, buffer.count >= pixels * 4 else { return nil }
        var sr = 0.0, sg = 0.0, sb = 0.0, n = 0
        for i in stride(from: 0, to: pixels * 4, by: 4) {
            let r = Double(buffer[i]), g = Double(buffer[i + 1]), b = Double(buffer[i + 2])
            guard 0.299 * r + 0.587 * g + 0.114 * b >= paperLuminanceFloor else { continue }
            sr += r; sg += g; sb += b; n += 1
        }
        guard n > 0, Double(n) / Double(pixels) >= minimumPaperFraction else { return nil }
        return (sr / Double(n), sg / Double(n), sb / Double(n))
    }

    /// How much colour is on the page, measured against the page's **own paper**
    /// rather than against grey.
    ///
    /// Measuring against grey is what this used to do, and it cost a user a
    /// 600-page 1964 monograph: 33 MB in, 709 MB out, every page a
    /// full-resolution three-channel JPEG. Cream book stock has genuine
    /// saturation — 0.078 to 0.089 measured across that book, against a 0.06
    /// threshold — so every page read as "coloured" while its ink coverage
    /// (0.11) and tone fraction (0.009) both said plainly that it was text. The
    /// same number was then charged twice, because one constant gates both
    /// `isPicture` and `shouldKeepColour`: the page lost the 1-bit route *and*
    /// gained two channels. 1,185 KB/page against 48 KB/page as 1-bit.
    ///
    /// Moving the threshold cannot fix it. Over the corpus the wrongly-promoted
    /// text pages span 0.061–0.113 and the genuinely coloured ones span
    /// 0.061–0.31: the populations overlap, because a mean cannot tell a faint
    /// tint spread over the whole sheet from a strong colour in one corner of it.
    ///
    /// So the page is white-balanced to its own paper first — a von Kries
    /// correction, each channel divided by the paper's — and the same
    /// saturation measure is then taken on the corrected pixels. Cream paper
    /// becomes neutral and scores nothing; an illustration on that same cream
    /// page still scores, because it was never the paper colour. A page with no
    /// paper on it is left uncorrected.
    ///
    /// Neutral ink over tinted paper picks up a small opposite cast from the
    /// correction — 0.118 per pixel for pure black on cream, arithmetically —
    /// which is why this is a mean over the page and not a maximum. In practice
    /// it stays far below even that, because the signal is measured on a 40 DPI
    /// thumbnail where almost every text pixel is a blend of ink and paper and
    /// so lies between the two chromaticities rather than at the neutral end.
    /// Measured on a sweep of stocks from white through cream, tan, manila and
    /// legal-pad yellow to a strong ochre, all with black text: **0.000 to
    /// 0.008**, against a threshold of 0.06. The correction does not weaken as
    /// the tint gets stronger, which was the thing worth checking.
    static func saturation(ofRGBA buffer: [UInt8], width: Int, height: Int) -> Double {
        let pixels = width * height
        guard pixels > 0, buffer.count >= pixels * 4 else { return 0 }
        var kr = 1.0, kg = 1.0, kb = 1.0
        if let paper = paperColour(ofRGBA: buffer, width: width, height: height) {
            let peak = max(paper.r, max(paper.g, paper.b))
            // Scaled so the brightest channel is unchanged: this removes the
            // paper's cast without lightening or darkening the page, so the
            // measure stays comparable to the one the threshold was set against.
            if peak > 0, paper.r > 0, paper.g > 0, paper.b > 0 {
                kr = peak / paper.r; kg = peak / paper.g; kb = peak / paper.b
            }
        }
        var total = 0.0
        for i in stride(from: 0, to: pixels * 4, by: 4) {
            let r = Double(buffer[i]) * kr
            let g = Double(buffer[i + 1]) * kg
            let b = Double(buffer[i + 2]) * kb
            let hi = max(r, max(g, b)), lo = min(r, min(g, b))
            if hi > 0 { total += (hi - lo) / hi }
        }
        return total / Double(pixels)
    }

    /// Fraction of the page that would be ink once thresholded. Text sits at
    /// 6–8%; halftones and dark scans run far higher.
    static func inkCoverage(
        of grey: [UInt8], width: Int, height: Int, threshold: UInt8
    ) -> Double {
        guard width > 0, height > 0 else { return 0 }
        var dark = 0
        for value in grey where value < threshold { dark += 1 }
        return Double(dark) / Double(width * height)
    }

    /// The encoded JPEG bytes, so the same data can go into a hand-built PDF.
    static func jpegData(
        from grey: [UInt8], width: Int, height: Int, quality: Double
    ) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
            colorSpaceName: .deviceWhite, bytesPerRow: width, bitsPerPixel: 8)
        else { return nil }
        if let dest = rep.bitmapData {
            grey.withUnsafeBytes { dest.update(from: $0.bindMemory(to: UInt8.self).baseAddress!,
                                               count: width * height) }
        }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// JPEG-encode ourselves so the compression is ours to pick, then hand back
    /// a JPEG-backed image for the PDF context to embed.
    /// One JPEG encode, giving back both the bytes and an image over them.
    ///
    /// These were two functions — `jpegImage` for the PDF and `jpegData` for the
    /// stream file — and `jpegImage` was itself encoding to JPEG and decoding
    /// straight back, so a picture page paid for the same encode twice over the
    /// same buffer. The bytes and the image are now the same bytes, which also
    /// guarantees the compressed build and the fallback build are identical
    /// rather than merely meant to be.
    static func jpeg(
        from grey: [UInt8], width: Int, height: Int, quality: Double
    ) -> (data: Data, image: CGImage)? {
        guard let data = jpegData(from: grey, width: width, height: height,
                                  quality: quality),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return (data, image)
    }

    // MARK: - MRC layers

    /// Sauvola's k. 0.34 follows `internetarchive/archive-pdf-tools`, which
    /// produced two of the MRC exemplars this was calibrated against.
    static let sauvolaK = 0.34

    /// How much the background is shrunk. It is the quality knob and it is
    /// steep: measured on a page carrying a photograph, 1x saves 1.15x, 2x saves
    /// 3.05x and 3x saves 4.72x. Over 40 documents, 2x is 3.28x and 3x is 5.15x.
    ///
    /// 2, not 3, because the pages that reach this route are by definition the
    /// ones with pictures on them. At 3x the photograph survives but is visibly
    /// soft; at 2x it is close to what ships today. Trading a picture's
    /// resolution for bytes on archival material is the R13 decision again, and
    /// it went the same way.
    static let mrcBackgroundDownsample = 2

    /// The foreground carries ink colour, which on a scan is nearly flat, so it
    /// can be shrunk much harder than the background without anything showing.
    static let mrcForegroundDownsample = 4

    /// The largest page that gets layered.
    ///
    /// Not `maximumPageMegapixels`, which is the bound on *rendering* a page and
    /// is sized for the grey buffer at a measured 5.5 bytes a pixel. Layering
    /// the same page holds a good deal more at once: the grey buffer, the
    /// stencil, the text-region map, the filled background, and inside
    /// `fillHoles` a second copy of the buffer plus two more flag arrays — about
    /// 8 bytes a pixel at peak against the render's 5.5. At 400 MP that is over
    /// 3 GB for a saving, on a page nobody asked to be made smaller.
    ///
    /// 100 MP matches `maximumColourPageMegapixels`, which was measured for the
    /// same reason. Above it the page keeps the single JPEG it already has,
    /// which is exactly what MRC declining is supposed to do.
    ///
    /// R24 and R29 are both this shape — an allocation bounded in one place and
    /// not in its sibling — so the bound is asserted directly by
    /// `mrcBoundIsWithinTheRenderOne` rather than left to be inferred.
    static let maximumMRCPageMegapixels = 100

    /// Peak bytes per pixel while layering, measured against the render's 5.5.
    static let measuredMRCBytesPerPixel = 8.0

    /// Whether layering's worst case stays inside the render's.
    static var mrcBoundIsWithinTheRenderOne: Bool {
        Double(maximumMRCPageMegapixels) * measuredMRCBytesPerPixel
            <= Double(maximumPageMegapixels) * measuredGreyBytesPerPixel
    }

    /// Vision's boxes are tight around the glyphs it recognised. A stencil
    /// clipped to them files the ascenders, descenders and anti-aliased edge off
    /// every character on the page, so they are grown by this much of their own
    /// height first.
    static let mrcBoxPadding = 0.25

    /// One page as three layers.
    struct MRCLayers {
        /// 1-bit PNG of the text stencil, ready for jbig2enc.
        let mask: URL
        /// 8-bit grey JPEGs. The background holds paper and pictures, the
        /// foreground holds ink colour, and the stencil says which shows.
        let background: URL
        let foreground: URL
        let backgroundWidth: Int, backgroundHeight: Int
        let foregroundWidth: Int, foregroundHeight: Int
    }

    /// Sauvola's local threshold: `t(x) = m(x) * (1 + k * (s(x)/128 - 1))`.
    ///
    /// Local, not global. Otsu picks one threshold for the whole sheet, which is
    /// the right question for *whether* a page is a picture and the wrong one for
    /// cutting text out of one: on a page that is half photograph the photograph
    /// drags the global threshold until the text either bloats or vanishes.
    /// Integral images, so the window size costs nothing.
    static func sauvolaMask(_ grey: [UInt8], width w: Int, height h: Int,
                            window: Int) -> [Bool] {
        guard w > 0, h > 0, grey.count >= w * h else { return [] }
        let stride1 = w + 1
        var sum = [Double](repeating: 0, count: stride1 * (h + 1))
        var sq = [Double](repeating: 0, count: stride1 * (h + 1))
        for y in 0..<h {
            var rs = 0.0, rq = 0.0
            for x in 0..<w {
                let v = Double(grey[y * w + x])
                rs += v; rq += v * v
                sum[(y + 1) * stride1 + x + 1] = sum[y * stride1 + x + 1] + rs
                sq[(y + 1) * stride1 + x + 1] = sq[y * stride1 + x + 1] + rq
            }
        }
        let r = max(window / 2, 1)
        var mask = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            let y0 = max(y - r, 0), y1 = min(y + r + 1, h)
            for x in 0..<w {
                let x0 = max(x - r, 0), x1 = min(x + r + 1, w)
                let area = Double((y1 - y0) * (x1 - x0))
                let s = sum[y1 * stride1 + x1] - sum[y0 * stride1 + x1]
                      - sum[y1 * stride1 + x0] + sum[y0 * stride1 + x0]
                let q = sq[y1 * stride1 + x1] - sq[y0 * stride1 + x1]
                      - sq[y1 * stride1 + x0] + sq[y0 * stride1 + x0]
                let mean = s / area
                let sd = max(q / area - mean * mean, 0).squareRoot()
                if Double(grey[y * w + x]) < mean * (1 + sauvolaK * (sd / 128.0 - 1)) {
                    mask[y * w + x] = true
                }
            }
        }
        return mask
    }

    /// Where the stencil is allowed to look, from Vision's word boxes.
    ///
    /// This is what makes MRC safe here. Sauvola cannot tell a halftone dot from
    /// a full stop, so on its own it pulls photographs into the stencil, and the
    /// picture is then destroyed by the very layering meant to preserve it —
    /// measured, on a page carrying one: visibly smeared and streaked, while the
    /// text on the same page was perfect. Confining the stencil to where words
    /// were actually recognised leaves pictures wholly in the background.
    ///
    /// It is also *smaller*: a mask restricted to text has far fewer connected
    /// components, so it costs less as JBIG2 than the blind one it replaces.
    /// 5.15x against 4.96x, better on both axes.
    static func textRegionMask(_ boxes: [SearchableWriter.BoundingBox],
                               width w: Int, height h: Int) -> [Bool] {
        var region = [Bool](repeating: false, count: w * h)
        guard w > 0, h > 0 else { return region }
        for b in boxes {
            // The pad is a fraction of the box's *height* in both directions, so
            // it is converted through the aspect ratio for the horizontal one.
            let padY = b.height * mrcBoxPadding
            let padX = padY * Double(h) / Double(w)
            let x0 = max(Int((b.x - padX) * Double(w)), 0)
            let x1 = min(Int((b.x + b.width + padX) * Double(w)) + 1, w)
            let y0 = max(Int((b.y - padY) * Double(h)), 0)
            let y1 = min(Int((b.y + b.height + padY) * Double(h)) + 1, h)
            guard x0 < x1, y0 < y1 else { continue }
            for y in y0..<y1 { for x in x0..<x1 { region[y * w + x] = true } }
        }
        return region
    }

    /// Fill the pixels under `holes` from their surroundings.
    ///
    /// Both layers get this treatment before they are shrunk, and it is not
    /// cosmetic: a background with the text punched out of it as hard-edged
    /// holes costs *more* to compress than the background with the text still
    /// in it, because the edges are exactly the high frequencies the codec is
    /// bad at. Filling them flat is what makes the layer cheap.
    ///
    /// The radius doubles on each pass so an isolated hole is reached quickly
    /// and a large one still terminates. Anything never reached takes the mean
    /// of what was kept, rather than being left at its original ink value where
    /// it would show through as a ghost.
    static func fillHoles(_ src: [UInt8], holes: [Bool], width w: Int, height h: Int,
                          radius: Int, passes: Int = 3) -> [UInt8] {
        guard w > 0, h > 0, src.count >= w * h, holes.count >= w * h else { return src }
        var out = src, live = holes, rad = max(radius, 1)
        for _ in 0..<passes {
            var next = out, still = live
            var any = false
            for y in 0..<h {
                for x in 0..<w where live[y * w + x] {
                    any = true
                    var acc = 0, cnt = 0
                    let step = max(rad / 3, 1)
                    var dy = -rad
                    while dy <= rad {
                        let yy = y + dy
                        if yy >= 0, yy < h {
                            var dx = -rad
                            while dx <= rad {
                                let xx = x + dx
                                if xx >= 0, xx < w, !live[yy * w + xx] {
                                    acc += Int(out[yy * w + xx]); cnt += 1
                                }
                                dx += step
                            }
                        }
                        dy += step
                    }
                    if cnt > 0 { next[y * w + x] = UInt8(acc / cnt); still[y * w + x] = false }
                }
            }
            out = next; live = still
            if !any { break }
            rad *= 2
        }
        if live.contains(true) {
            var total = 0, count = 0
            for i in 0..<(w * h) where !holes[i] { total += Int(out[i]); count += 1 }
            let mean = UInt8(count > 0 ? total / count : 255)
            for i in 0..<(w * h) where live[i] { out[i] = mean }
        }
        return out
    }

    /// Box-average shrink by an integer factor.
    static func downsample(_ src: [UInt8], width w: Int, height h: Int, by f: Int)
        -> (pixels: [UInt8], width: Int, height: Int) {
        guard f > 1, w > 0, h > 0 else { return (src, w, h) }
        let nw = max(w / f, 1), nh = max(h / f, 1)
        var out = [UInt8](repeating: 255, count: nw * nh)
        for y in 0..<nh {
            for x in 0..<nw {
                var acc = 0, cnt = 0
                for dy in 0..<f where y * f + dy < h {
                    let row = (y * f + dy) * w
                    for dx in 0..<f where x * f + dx < w {
                        acc += Int(src[row + x * f + dx]); cnt += 1
                    }
                }
                out[y * nw + x] = UInt8(cnt > 0 ? acc / cnt : 255)
            }
        }
        return (out, nw, nh)
    }

    /// An 8-bit grey PNG from a raw buffer, for the layers that have to reach an
    /// external encoder as a file.
    static func greyPNG(_ pixels: [UInt8], width w: Int, height h: Int) -> Data? {
        guard w > 0, h > 0, pixels.count >= w * h,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                colorSpaceName: .deviceWhite, bytesPerRow: w, bitsPerPixel: 8)
        else { return nil }
        if let dest = rep.bitmapData {
            pixels.withUnsafeBytes { dest.update(from: $0.bindMemory(to: UInt8.self).baseAddress!,
                                                 count: w * h) }
        }
        return rep.representation(using: .png, properties: [:])
    }

    /// Build the three layers for one page, or nil when the page should keep the
    /// single image it already has.
    ///
    /// Nil, not a throw, and deliberately: MRC is an improvement on a working
    /// page, never a requirement. Every way this can decline — no words found,
    /// a render that failed, an encode that failed — leaves the caller with the
    /// JPEG it already had. A page that costs more is a far better outcome than
    /// a page that fails, and the alternative is a route whose failures are
    /// invisible until someone opens the book.
    static func mrcLayers(for page: PDFPage, boxes: [SearchableWriter.BoundingBox],
                          into directory: URL, stem: String,
                          backgroundDownsample: Int = mrcBackgroundDownsample) -> MRCLayers? {
        // No words means a plate with no text on it. An empty stencil would put
        // the whole page into a downsampled background — publishing a picture at
        // half its resolution for no compression benefit at all.
        guard !boxes.isEmpty else { return nil }

        let box = fullBox(of: page)
        let dpi = rebuildDPI(of: page)
        let scale = dpi / 72.0
        let wide = (box.width * scale).rounded(), high = (box.height * scale).rounded()
        guard wide.isFinite, high.isFinite, wide >= 1, high >= 1,
              wide * high <= Double(maximumMRCPageMegapixels) * 1_000_000 else { return nil }
        let w = max(Int(wide), 1), h = max(Int(high), 1)
        guard let grey = renderGrey(page, box: box, scale: scale,
                                    width: w, height: h, from: .mediaBox) else { return nil }

        var mask = sauvolaMask(grey, width: w, height: h, window: max(Int(dpi / 4), 3))
        guard mask.count == w * h else { return nil }
        let region = textRegionMask(boxes, width: w, height: h)
        for i in 0..<(w * h) where !region[i] { mask[i] = false }
        // A stencil with nothing in it is not a layering, it is a downsampled
        // page. Refuse it the same way an empty box list is refused.
        guard mask.contains(true) else { return nil }

        let inverse = mask.map { !$0 }
        let bgFull = fillHoles(grey, holes: mask, width: w, height: h, radius: 10)
        let (bg, bw, bh) = downsample(bgFull, width: w, height: h,
                                      by: max(backgroundDownsample, 1))
        let fgFull = fillHoles(grey, holes: inverse, width: w, height: h, radius: 3)
        let (fg, fw, fh) = downsample(fgFull, width: w, height: h, by: mrcForegroundDownsample)

        var maskPixels = [UInt8](repeating: 255, count: w * h)
        for i in 0..<(w * h) where mask[i] { maskPixels[i] = 0 }
        guard let maskPNG = greyPNG(maskPixels, width: w, height: h),
              let bgData = jpegData(from: bg, width: bw, height: bh, quality: pictureJPEGQuality),
              let fgData = jpegData(from: fg, width: fw, height: fh, quality: pictureJPEGQuality)
        else { return nil }

        let maskURL = directory.appendingPathComponent(stem + ".mask.png")
        let bgURL = directory.appendingPathComponent(stem + ".bg.jpg")
        let fgURL = directory.appendingPathComponent(stem + ".fg.jpg")
        guard (try? maskPNG.write(to: maskURL)) != nil,
              (try? bgData.write(to: bgURL)) != nil,
              (try? fgData.write(to: fgURL)) != nil else {
            for u in [maskURL, bgURL, fgURL] { try? FileManager.default.removeItem(at: u) }
            return nil
        }
        return MRCLayers(mask: maskURL, background: bgURL, foreground: fgURL,
                         backgroundWidth: bw, backgroundHeight: bh,
                         foregroundWidth: fw, foregroundHeight: fh)
    }

    // MARK: - Resolution

    /// The resolution to rebuild a page at.
    ///
    /// `nativeDPI` reports a fact — the resolution implied by the largest image
    /// on the page — and on a born-digital page that image is decoration, not
    /// the page. This applies the policy.
    ///
    /// A low implied DPI has two quite different causes, and the first version of
    /// this check conflated them:
    ///
    /// - a **logo** on a born-digital page. Its DPI is meaningless and rendering
    ///   the page at it destroys everything else (C9: a 595x841 pt page carrying
    ///   1,846 characters rebuilt as 16x23 px).
    /// - a **genuine low-resolution scan**, where the image really is the page.
    ///   Rendering that at 300 is pure upsampling: 4x the linear scale, 17x the
    ///   pixels, for no more detail — and with several files in flight it is the
    ///   difference between comfortable and gigabytes.
    ///
    /// The pixel width separates them, cleanly. Measured over the corpus, the 84
    /// sampled pages below the DPI floor split into 47 logos, 16–96 px wide, and
    /// 37 real 72 DPI scans, 1936–2592 px wide. Nothing lands in between, so the
    /// threshold is not finely balanced.
    static func rebuildDPI(of page: PDFPage) -> Double {
        guard let found = largestImage(of: page) else { return fallbackRebuildDPI }
        // Comfortably a scan.
        if found.dpi >= minimumPlausibleScanDPI { return found.dpi }
        // Below the floor, but page-sized: a real scan that happens to be coarse.
        // Trust it rather than inventing detail it does not have.
        if found.pixelWidth >= minimumScanPixelWidth { return found.dpi }
        // Small and low-resolution: decoration. Ignore it.
        return fallbackRebuildDPI
    }

    /// Wide enough that the image plausibly *is* the page rather than something
    /// sitting on it. A Letter sheet scanned at even 72 DPI is 612 px across;
    /// the corpus's logos top out at 96.
    static let minimumScanPixelWidth = 600

    /// The DPI of the largest image embedded on the page — the same thing
    /// mac-ocr's `--pdf-dpi auto` works out. Recurses into Form XObjects, where
    /// scanners often nest the scan itself.
    ///
    /// A measurement, not a decision: it will happily report 1.9 DPI for a page
    /// whose only image is a logo. Use `rebuildDPI` to render with.
    static func nativeDPI(of page: PDFPage) -> Double? { largestImage(of: page)?.dpi }

    /// The largest embedded image's implied resolution *and* its pixel width.
    /// `rebuildDPI` needs both to tell a coarse scan from a logo.
    static func largestImage(of page: PDFPage) -> (dpi: Double, pixelWidth: Int)? {
        guard let cgPage = page.pageRef, let dict = cgPage.dictionary else { return nil }

        final class Largest { var width = 0; var height = 0 }
        let largest = Largest()

        // A form's /Resources is frequently an indirect reference to the page's
        // own, and forms on one page routinely share a single dictionary. The
        // depth cap below bounds recursion but not breadth, so without this the
        // same dictionary is re-walked once per referring form at every level —
        // N + N² + N³ + N⁴ block invocations instead of N. Measured at 60 forms:
        // 5.09 s for a page with 61 real entries (R25).
        // The shallowest depth each dictionary has been walked at, not merely
        // whether it has been. A plain visited set would be wrong: a dictionary
        // first reached at depth 3 has its own children cut off by the depth cap,
        // and a later path arriving at depth 1 — which *would* explore them —
        // must not be turned away by the earlier, poorer visit.
        var walkedAt: [UnsafeRawPointer: Int] = [:]

        func walk(_ resources: CGPDFDictionaryRef, depth: Int) {
            guard depth < 4 else { return }
            // Identity, not contents: CoreGraphics resolves an indirect
            // reference to the same dictionary pointer every time, which is what
            // makes this work. CGPDFDictionaryRef is an opaque pointer with no
            // Swift-visible conversion, hence the bitcast.
            let identity = unsafeBitCast(resources, to: UnsafeRawPointer.self)
            if let seen = walkedAt[identity], seen <= depth { return }
            walkedAt[identity] = depth
            var xobjects: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects),
                  let xobjects else { return }
            var nestedResources: [CGPDFDictionaryRef] = []

            CGPDFDictionaryApplyBlock(xobjects, { _, value, info in
                let found = Unmanaged<Largest>.fromOpaque(info!).takeUnretainedValue()
                var stream: CGPDFStreamRef?
                guard CGPDFObjectGetValue(value, .stream, &stream), let stream,
                      let streamDict = CGPDFStreamGetDictionary(stream) else { return true }
                var subtype: UnsafePointer<Int8>?
                guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtype),
                      let subtype else { return true }

                switch String(cString: subtype) {
                case "Image":
                    var w: CGPDFInteger = 0, h: CGPDFInteger = 0
                    // /Width and /Height are whatever the file declares —
                    // CGPDFInteger is 64-bit and nothing cross-checks them
                    // against the stream, which can be three bytes. Reject the
                    // implausible here so no arithmetic downstream can overflow
                    // (R24), rather than at each place that multiplies them.
                    guard CGPDFDictionaryGetInteger(streamDict, "Width", &w),
                          CGPDFDictionaryGetInteger(streamDict, "Height", &h),
                          w > 0, h > 0,
                          w <= CGPDFInteger(maximumDeclaredImageSide),
                          h <= CGPDFInteger(maximumDeclaredImageSide)
                    else { return true }
                    if Int(w) * Int(h) > found.width * found.height {
                        found.width = Int(w); found.height = Int(h)
                    }
                case "Form":
                    // Scanner drivers often nest the scan one level down. Missing
                    // this silently upsampled nested scans (2.25x the bytes for no
                    // detail) and downsampled 400/600 DPI ones, losing detail.
                    var nested: CGPDFDictionaryRef?
                    if CGPDFDictionaryGetDictionary(streamDict, "Resources", &nested),
                       let nested {
                        nestedResources.append(nested)
                    }
                default:
                    break
                }
                return true
            }, Unmanaged.passUnretained(largest).toOpaque())
            for nested in nestedResources { walk(nested, depth: depth + 1) }
        }

        var resources: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(dict, "Resources", &resources), let resources {
            walk(resources, depth: 0)
        }
        guard largest.width > 0 else { return nil }
        // Media box, to match the area flatten renders — see fullBox.
        let widthPt = page.bounds(for: .mediaBox).width
        guard widthPt > 0 else { return nil }
        return (dpi: Double(largest.width) / (Double(widthPt) / 72.0),
                pixelWidth: largest.width)
    }
}
