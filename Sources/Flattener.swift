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

    /// …but heavy ink on its own is not enough. A page routed to the picture
    /// path by ink coverage alone must also carry *some* continuous tone.
    ///
    /// R38. Dense bilevel type — a broadsheet page, a page of 8-point footnotes,
    /// a comic strip — reads as heavy ink while both other signals say text
    /// emphatically, and `isPicture` ORs its signals so one overrode two. Those
    /// pages then got a JBIG2 stencil *plus* a greyscale DCT background carrying
    /// nothing the stencil did not already have. Measured on the 232-document
    /// corpus: `Boltanski_2006` came out **16 MB → 156 MB (9.45x)**, `Noble_1977`
    /// 17 MB → 87 MB (5.0x), a 1950 comic page 3.48x, a 1926 broadsheet 3.20x.
    ///
    /// 0.03 sits in a wide measured gap between the two populations, taken over
    /// every ink-triggered page in the corpus:
    ///
    /// | | tone |
    /// |---|---|
    /// | real pictures (Findlay, Black, Ehrenreich, Marth) | 0.0709–0.1453 |
    /// | dense bilevel type (the four inflating documents) | 0.0017–0.0247 |
    ///
    /// **Why this is safe rather than merely smaller.** The picture route exists
    /// because thresholding destroys an *unresolved* halftone, and an unresolved
    /// halftone is precisely what puts pixels between paper and ink. Low tone
    /// means the page is genuinely bimodal, which is exactly the case where 1-bit
    /// loses nothing. The two riskiest pages this moves — a newspaper comic and a
    /// dense title spread — were rendered at 1-bit and read clean.
    ///
    /// Only the *ink* branch is gated. Tone and saturation still route a page to
    /// pictures on their own, so the tinted-figure case the tone threshold exists
    /// for (and the pale-colour case behind `pictureSaturationThreshold`) is
    /// untouched: both of those fire on pages whose ink coverage is near zero.
    static let pictureInkMinimumTone = 0.03

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

    // The recogniser's own page-size limit, the DPI ceiling that kept pages
    // inside it, and `engineAutoDPI` all lived here — about seventy lines of
    // negotiating with a subprocess that re-rasterised our PDF at a resolution
    // of its own choosing. 200 megapixels was *mac-ocr's* refusal, not Vision's,
    // and R39 was the hole in that negotiation. Vision takes a 216-megapixel
    // CGImage without complaint (measured), and `Recogniser` hands it the
    // bitmaps this file already drew, so there is nothing left to negotiate.
    //
    // `maximumPageMegapixels` above still bounds what we will *render*, for
    // R24's reason: an allocation that fails is a crash, not a catchable error.

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
                //
                // **And the replacement was wrong too, which is R26 recurring**
                // (A3.3). Turning the rebuild off is *not sufficient*:
                // `Recogniser.render` applies the same `rebuildDPI` and the same
                // megapixel guard on the non-rebuild path, and `pdfDPIAuto`
                // defaults to true — so on a page declaring 2,100 DPI, rebuild off
                // with Page DPI on Automatic **still fails**, while rebuild off
                // with Page DPI set to 144 renders 1224×1584 and works. So the
                // advertised remedy changed the message and not the outcome, while
                // the setting the message explicitly disclaimed is the only one
                // that helps. Both halves have to be named, in the order they have
                // to be done.
                return "Page \(page) would rebuild to \(megapixels) megapixels at "
                    + "its own \(dpi) DPI, past the \(maximumPageMegapixels) MP limit. "
                    + "Nothing was written. To process this file, turn off "
                    + "\"Rebuild page images first\" in Settings **and** set "
                    + "\"PDF render DPI\" to a fixed value such as 144 — leaving it "
                    + "on Automatic takes the page's own DPI again and fails the "
                    + "same way."
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

    /// `wanted` page indices spread through a document of `count` pages, in
    /// ascending order and **never repeating**.
    ///
    /// One definition because there were five, four of them different, and two of
    /// those repeated a page: `score-text-route` measured page 1 **three times**
    /// on a five-page document (27 of 233 corpus documents are short enough to
    /// hit it), and `score-routing`'s `[1, n/3, n/2, n*3/4]` is `[1, 1, 2, 3]` at
    /// n=5. A sample that repeats a page weights it twice in every average taken
    /// over the sample, and both tools average (`REVIEW-2026-08-14.md` A12.8).
    ///
    /// Page 1 is deliberately never chosen when the whole document does not fit:
    /// a born-digital book often has a raster cover and a scan often has a clean
    /// title page, so it is the least informative page in either.
    ///
    /// Distinct by construction rather than by a `Set`: with `n < count` the step
    /// `count / (n + 1)` is at least 1, and a half-open interval of length ≥ 1
    /// always contains an integer, so the floors strictly increase.
    ///
    /// The `n == count` line is a statement, not a shortcut: the general formula
    /// gives `[0 ..< count]` there anyway, since `floor(k·c / (c+1)) = k − 1` for
    /// every `k ≤ c`. It is kept because "the whole document" should not depend on
    /// the reader noticing that identity, and the suite's distinctness, order,
    /// range and count checks pin the two to the same answer.
    static func sampleIndices(count: Int, wanted: Int) -> [Int] {
        guard count > 0, wanted > 0 else { return [] }
        let n = min(wanted, count)
        if n == count { return Array(0..<count) }
        return (0..<n).map { ($0 + 1) * count / (n + 1) }
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
        guard let doc = open(url, password: password) else { return false }
        return hasDigitalText(in: doc)
    }

    /// The same question against a document that is already open.
    ///
    /// Exists so a *tool* can ask it without re-opening the file it is already
    /// holding — and, more to the point, so that no tool has an excuse to
    /// re-implement the rule. `Tools/classify-source.swift` had its own copy of
    /// `pageIsAnImage` for a week, with a different predicate, and the corpus
    /// gate whose only job is D1 consequently admitted the two documents this
    /// function calls born-digital (`REVIEW-2026-08-14.md` A12.4).
    static func hasDigitalText(in doc: PDFDocument) -> Bool {
        guard doc.pageCount > 0 else { return false }
        let indices = sampleIndices(count: doc.pageCount, wanted: 4)

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
            // Bounded at **both** ends (A3.4). It only guarded from below, so at
            // 1.0001 DPI a 200×100 px image became a 200×100 **inch** page and died
            // at the megapixel gate quoting A3.3's remedy, and at 1e6 DPI it
            // *succeeded* and published a 1/5000-inch page. Neither is a resolution
            // any scanner or camera records; both come from a malformed or hostile
            // file. 4,800 DPI is drum-scanner territory and twice any flatbed's
            // optical maximum, so anything past it is a declaration to disbelieve
            // rather than a page to render.
            func resolution(_ key: CFString) -> Double {
                (props?[key] as? Double)
                    .flatMap { $0 > 1 && $0 <= 4800 ? $0 : nil } ?? 72
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
        /// Where the **source** page's crop box lands on this rebuilt sheet, or
        /// nil when the source trimmed nothing.
        ///
        /// **The rebuilt file deliberately does not declare it**, and that is not
        /// an oversight — it is what makes recognition work. On the JBIG2 route
        /// Vision reads the per-page bitmaps, which are whole sheets, so the
        /// observations come back normalised to the media box; a crop box on this
        /// intermediate would make `compose` map them into the trimmed
        /// rectangle and shift every run on the page. On the Flate route it
        /// would instead stop the hidden margin being read at all. Either way the
        /// crop belongs on the **published** page and nowhere else, which is
        /// where `compose` and `JBIG2.assemble` put it. See `BUGS.md` C23.
        var sourceCropBox: CGRect?
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

        // Seed the context with page 1's *media* box. The per-page override
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

            // C23. Carried, not declared — `RebuiltPage.sourceCropBox` says why
            // this page dictionary must keep only a media box while the
            // published one gets both. Through `SearchableWriter.cropRegion`,
            // the app's own mapping, because the rebuild bakes `/Rotate` in and
            // a crop rect written out by hand here would be a second answer to
            // a question that already has one.
            let region = SearchableWriter.cropRegion(of: page, on: pageBox)
            let sourceCrop = region == pageBox ? nil : region

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
                    // `if true {` stood here and around the JPEG branch below
                    // (A3.4) — two conditionals that read as gates and were not.
                    let entry = RebuiltPage(content: .bilevel(png), pixelWidth: width,
                                            pixelHeight: height, boxSize: box.size,
                                            sourceCropBox: sourceCrop)
                    rebuilt.append(entry)
                    try onPage?(entry)
                } else {
                    // Literally the bytes embedded in the PDF above, not a second
                    // encode of the same buffer, so the compressed build and the
                    // fallback build cannot drift apart.
                    let jpeg = pngDirectory.appendingPathComponent(stem + ".jpg")
                    guard let data = jpegBytes,
                          (try? data.write(to: jpeg)) != nil else {
                        throw Failure.pageFailed(page: index + 1, of: count)
                    }
                    let entry = RebuiltPage(content: .jpeg(jpeg), pixelWidth: width,
                                            pixelHeight: height, boxSize: box.size,
                                            isColour: isColour, sourceCropBox: sourceCrop)
                    rebuilt.append(entry)
                    try onPage?(entry)
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
        // The guard `greyPNG` and `jpegRGB` both have and this one did not
        // (A7.3): `grey[src + x]` below indexes to `width * height - 1`, so a
        // buffer shorter than its stated size reads out of bounds rather than
        // returning nil. No shipped caller mismatches; the sibling sweep's rule is
        // that a missing guard is recorded and closed, not argued about.
        guard width > 0, height > 0, grey.count >= width * height else { return nil }
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

    /// Is this page a picture rather than text? Three signals, because each
    /// misses cases the others catch:
    ///
    ///  - heavy ink: dark scans and coarse halftones — but only when some
    ///    continuous tone corroborates it, see `pictureInkMinimumTone` (R38);
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
        let tone = toneFraction(of: grey, threshold: threshold)
        if tone > pictureToneThreshold { return true }
        // Heavy ink, but only with corroborating tone. R38 — dense bilevel type
        // is heavy ink and nothing else, and 1-bit is what it wants.
        if tone > pictureInkMinimumTone,
           inkCoverage(of: grey, width: width, height: height,
                       threshold: threshold) > pictureInkThreshold { return true }
        if (precomputed ?? saturation(of: page)) > pictureSaturationThreshold { return true }

        // The three signals above are all statistics of the whole sheet, and R56 and
        // R57 are both pages where that is the defect rather than the threshold: a
        // plate over a fifth of a page dilutes its own tone by five, and a pale
        // drawing is not counted by any of them at all. The two below ask about
        // *things on the page* instead.
        //
        // **They are last, and that saves less than it looks.** The pages that reach
        // here are the ones the three above called text, which is the great majority,
        // so the cost is paid on nearly every page rather than on a few. Measured, best
        // of 25 over two real corpus pages: the three above cost 4.8 ms on a 3.4 MP
        // page and these two add 25.8 ms; at 9.8 MP it is 9.3 ms against 40.3.
        // Ordering them last buys the picture pages, not the text ones. Worth paying
        // against a per-page recognition cost two orders of magnitude larger — and
        // worth knowing that `saturation` measured *without* the caller's precomputed
        // value costs 85 ms on that 9.8 MP page, more than all of this together, which
        // is where an optimisation should start.
        let dpi = renderDPI(of: page, pixelWidth: width)
        let marks = pageMarks(grey, width: width, height: height,
                              threshold: threshold, dpi: dpi)
        // R57. The page's own tone constant, asked about the region the tone is in.
        if largeMarkTone(marks, grey: grey, width: width, height: height,
                         threshold: threshold) > pictureToneThreshold { return true }
        // R56. A pale mark too big to be type and too empty to be a shaded block.
        return paleDrawing(marks, dpi: dpi).extent > paleDrawingThreshold
    }

    /// The resolution a render of `page` was taken at, from the render itself.
    ///
    /// Derived from the buffer in hand rather than by calling `rebuildDPI` a second
    /// time, for two reasons: `rebuildDPI` walks the page's resources and is not free,
    /// and a caller that rendered at some other scale — every tool in `Tools/` at
    /// some point, and `score-threshold-loss`'s header records what that mistake
    /// looks like — would otherwise be told about a page nothing produced.
    static func renderDPI(of page: PDFPage, pixelWidth: Int) -> Double {
        let box = fullBox(of: page)
        guard box.width > 0, pixelWidth > 0 else { return 72 }
        return Double(pixelWidth) * 72.0 / Double(box.width)
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
        guard let t = saturationThumbnail(of: page) else { return 0 }
        return saturation(ofRGBA: t.buffer, width: t.width, height: t.height)
    }

    /// The ~40 DPI RGBA thumbnail every colour signal is measured on — the page
    /// the routing decision actually describes.
    ///
    /// Split out of `saturation(of:)` for C27, which needs a **different statistic
    /// of the same pixels**. A tool that rendered its own page at its own
    /// resolution would be comparing two calibrations, and the number
    /// `shouldKeepColour` reads is the one taken here. Nothing about the render
    /// moved: the body is `saturation(of:)`'s, and the two ways that function used
    /// to answer 0 — no thumbnail size, and a context or page ref it could not get
    /// — are the two ways this one answers nil.
    ///
    /// ⚠️ **Not a pure function of the page, measured 2026-08-19.** On pages whose
    /// images CoreGraphics caches, what this draws depends on whether the page was
    /// already rendered at a higher resolution in the same process: `1954 - Why` p7
    /// gives `saturation(ofRGBA:)` **0.041 after `flatten`'s grey render and 0.044
    /// taken cold**, and `saturatedFraction(above: 0.25)` **0.02831 against 0.03033**
    /// (+7.1%); `Schwaller - 2026` p101 moves 0.06367 -> 0.06514; five of seven pages
    /// tried are identical either way. `flatten` renders grey first, so **production's
    /// number is the warm one** and so is every committed tool's (they all render the
    /// page before asking) — but a check or tool that calls this first will not
    /// reproduce production, and that is a wrong-instrument session waiting to happen.
    /// C27's `#### The population, swept` has the measurement.
    static func saturationThumbnail(of page: PDFPage)
        -> (buffer: [UInt8], width: Int, height: Int)? {
        // The same area flatten rebuilds, so the routing signal describes the
        // page that actually gets written.
        let box = fullBox(of: page)
        guard let (w, h, scale) = thumbnailSize(for: box) else { return nil }
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
        guard ok else { return nil }
        return (buffer, w, h)
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
        var total = 0.0
        forEachSaturation(ofRGBA: buffer, width: width, height: height) { total += $0 }
        return total / Double(pixels)
    }

    /// Every pixel's saturation, corrected for the page's own paper, handed to
    /// `body` one at a time — **including the zeros**, so a caller can divide by
    /// the pixel count it passed in and get a mean over the sheet rather than over
    /// the coloured part of it.
    ///
    /// One walk and not two because C27 asks for a *different statistic of the same
    /// population*: `saturation(ofRGBA:)` above is the mean of exactly these
    /// values, `saturatedFraction` below counts how many clear a floor. The von
    /// Kries correction is what a user's 600-page monograph paid for at 709 MB, and
    /// a second copy of it — in a tool, or in a later fix for C27 — is R23's and
    /// R29's shape exactly: one instance corrected, its twin left behind holding
    /// the older definition. So the correction and `(hi - lo) / hi` exist once.
    ///
    /// A pure black pixel yields 0 rather than being skipped. That is what the
    /// version of this loop inside `saturation` did (`if hi > 0 { total += … }`
    /// over a denominator of every pixel), and adding a literal zero to a running
    /// `Double` is exact, so the mean is unchanged bit for bit.
    static func forEachSaturation(ofRGBA buffer: [UInt8], width: Int, height: Int,
                                  _ body: (Double) -> Void) {
        let pixels = width * height
        guard pixels > 0, buffer.count >= pixels * 4 else { return }
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
        for i in stride(from: 0, to: pixels * 4, by: 4) {
            let r = Double(buffer[i]) * kr
            let g = Double(buffer[i + 1]) * kg
            let b = Double(buffer[i + 2]) * kb
            let hi = max(r, max(g, b)), lo = min(r, min(g, b))
            body(hi > 0 ? (hi - lo) / hi : 0)
        }
    }

    /// How much of the page carries ink of its own colour, rather than how much
    /// colour the page carries on average: the fraction of pixels whose
    /// paper-corrected saturation is **strictly above** `floor`, matching
    /// `shouldKeepColour`'s own strict comparison against the mean.
    ///
    /// **C27 is the whole reason this exists, and no shipped decision reads it.**
    /// The route and the colour decision both read the mean, and reaching 0.06
    /// there takes something like 6% of the sheet in saturated ink (C27 reasoned
    /// "roughly 8%" before this column existed; measured on ten real pages, `sat`
    /// and this fraction at a 0.15 floor differ by 0.69x-1.30x, which puts it
    /// nearer 6%). Red subheads, rules and a corner cartoon come to 3-4%, so
    /// either way "this document is printed in two inks"
    /// is *structurally* invisible to that statistic whatever the constant is set
    /// to. Measured over the corpus, mean saturation either side of 0.06 is one
    /// continuum with a 0.004-wide gap, so tinted grey scans and two-ink sheets are
    /// not separated populations on it. A fraction can hold them apart — a page
    /// with 3% of its area at saturation 0.8 is not the page with a uniform 0.03
    /// cast — which is why C27 says the statistic is wrong rather than the number.
    ///
    /// `floor` is the caller's and there is deliberately no constant for it here.
    /// Sizing C27's population was supposed to settle a floor. **That sweep ran on
    /// 2026-08-19 (`SATFRAC-2026-08-19.tsv`, 233 documents, 441 pages) and settled
    /// no floor, because measured over the corpus there is not one to settle**: the
    /// noise is a per-page property, and one page of a 1938 magazine scan reads
    /// **2.0% of its sheet above a 0.25 floor with no ink of its own on it** — above
    /// the 1.36% of a page that loses real red ink — while another page of that same
    /// scan reads 0.04%. So no single value clears the noise everywhere, the answer
    /// wants a term about *where* the colour is rather than how much (R56's shape),
    /// and a constant in this file would read as a shipped
    /// calibration to every later reader — which is what `Tools/score-skew.swift`
    /// and R56's own refused candidate signal both record as the reason for keeping
    /// an unshipped measurement out of `Flattener`. This one is here only because it
    /// cannot be written outside it without a second copy of the correction above.
    static func saturatedFraction(ofRGBA buffer: [UInt8], width: Int, height: Int,
                                  above floor: Double) -> Double {
        let pixels = width * height
        guard pixels > 0, buffer.count >= pixels * 4 else { return 0 }
        var saturated = 0
        forEachSaturation(ofRGBA: buffer, width: width, height: height) {
            if $0 > floor { saturated += 1 }
        }
        return Double(saturated) / Double(pixels)
    }

    /// Fraction of the page that would be ink once thresholded. Text sits at
    /// 6–8%; halftones and dark scans run far higher.
    /// **Both halves come from one population, and that is the whole of A7.2.**
    /// It used to walk all of `grey` and divide by `width * height`. Told a
    /// 4,000-pixel buffer was 20x20 it returned **10.0** — a coverage above 1 —
    /// and told a 100-pixel buffer was 20x20 it under-reported 4x. Every sibling
    /// fraction in this file takes numerator and denominator from the same place.
    /// No shipped caller mismatches today; the two constants a rescaled value
    /// would miscalibrate, `pictureInkThreshold` and `pictureInkMinimumTone`, are
    /// the two whose miscalibration destroyed content twice.
    static func inkCoverage(
        of grey: [UInt8], width: Int, height: Int, threshold: UInt8
    ) -> Double {
        guard width > 0, height > 0 else { return 0 }
        let pixels = min(grey.count, width * height)
        guard pixels > 0 else { return 0 }
        var dark = 0
        for i in 0..<pixels where grey[i] < threshold { dark += 1 }
        return Double(dark) / Double(pixels)
    }

    /// The encoded JPEG bytes, so the same data can go into a hand-built PDF.
    ///
    /// A3.4 / A4.4. The `grey.count` precondition `greyPNG` and `jpegRGB` both have
    /// and this one did not. A 16-byte buffer at 100×100 produced a **valid
    /// 2,055-byte JPEG from 9,984 bytes past the end of the array** — so the
    /// framing is not "it traps" but **adjacent heap bytes get JPEG-encoded into
    /// the published page image**, which is memory disclosure into the output
    /// document. Not reachable from today's three callers (all traced, all pass
    /// exactly-sized buffers), and `jpegData` is `static` and already called from
    /// `Tools/`. The unguarded sibling in a family of three is R23's and R29's
    /// shape, and this is the one where the shape is a memory-safety bug.
    static func jpegData(
        from grey: [UInt8], width: Int, height: Int, quality: Double
    ) -> Data? {
        guard width > 0, height > 0, grey.count >= width * height else { return nil }
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
    /// **Those last two are superseded.** They came from the instrument BUGS.md T15
    /// was about, which never applied R50's all-text shrink; re-measured over 74
    /// corpus picture pages, 2x is **4.37x** and 3x is **6.66x**, and at 1x three
    /// layers cost *more* than one image on 31 of the 74 — see `FEATURES.md`. Left
    /// in place rather than rewritten because the per-page photograph figures above
    /// are still the ones that chose the value.
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

    // MARK: - Pages whose ink is all text
    //
    // R50. The tone layers, not the stencil, are what keeps a layered file above
    // the size of a good mixed-raster original. Measured over 568 pages against
    // the Internet Archive's own scan of the same book: our stencils cost
    // **21.2 MB against their 21.7**, and our tone layers **40.7 MB against their
    // 4.3**. The stencil is already right; the tone layers are carried at a
    // fidelity paper does not need.
    //
    // On a page that is nothing but text, the background holds paper and the
    // foreground holds one nearly-flat ink colour, so both can be shrunk far
    // harder than `mrcBackgroundDownsample` allows without anything visible
    // changing. On a page carrying a picture they cannot. So the question is which
    // kind of page this is — and that question has a cheap, honest answer at this
    // point in the pipeline that it does not have earlier.

    /// How much of a page's ink Vision found no words for.
    ///
    /// **Why this works where three other signals failed.** `isPicture` runs
    /// before recognition, so it has only the page's own histogram, and a
    /// histogram cannot tell text from a tinted plate — R49 measured that, twice
    /// over. This runs *after* recognition, where the word boxes exist, so it can
    /// ask a structural question instead of a statistical one: ink that is not
    /// inside any recognised word is, by construction, not text.
    ///
    /// Measured. Text pages sit at zero and pictures sit two orders of magnitude
    /// above them:
    ///
    /// | | ink outside the words |
    /// |---|---|
    /// | text pages (`Blacks in the City` 41, 163, 244; a synthetic text page) | 0.0000 |
    /// | 91 real corpus pages, median | 0.017 |
    /// | a line chart under a paragraph | 0.153 |
    /// | a seal covering 1% of the sheet | 0.250 |
    /// | a photograph covering 8% | 0.694 |
    /// | full-page photogravure plates (`Blacks` 78, 300, 301, 303) | 0.971–0.993 |
    ///
    /// **It is a threshold on a continuum, not a gap, and that is stated rather
    /// than dressed up.** Across the 91 corpus pages the values run smoothly from
    /// 0 to 0.97. What makes a bar here defensible is not a hole in the
    /// distribution but where the two ways of being wrong land: a page wrongly
    /// held at fine resolution costs bytes and nothing else. Every hazard that
    /// could be constructed for it lands at 0.153 or above, and 0.045 leaves a
    /// factor of 3.4 below the nearest one.
    ///
    /// ⛔ **This paragraph read "0.08 … *both* ways of being wrong are mild — …a
    /// page wrongly shrunk has its figure softened, never removed" until
    /// 2026-08-19, and the second half of that is FALSE.** It is what C26 was
    /// decided against. Measured over 13 of the 16 corpus pages the bar move
    /// rescues (`INKDUMP` on `Tools/score-text-route.swift`, in the entry's
    /// "Sub-step 4, the benefit"), 11 lose something and **8 lose content
    /// outright** — `Xin Qu et al_2018` p20 loses thirteen values out of a
    /// Pearson correlation matrix, `_1973_Committee Against Racism_` p4 seven
    /// lines of prose. Words Vision did not box are cut from the stencil by
    /// `textRegionMask`, left in the background, and destroyed at 1/8. So one
    /// way of being wrong here is invariant-1 content loss, not softening, and
    /// the reasoning that sized this constant had it the other way round.
    ///
    /// **Why 0.045, measured 2026-08-19 and decided by the owner.** A
    /// 233-document corpus sweep (`Tools/sweep-ink-bar.py`, committed as
    /// `INKBAR-2026-08-19.tsv`, 2,129 measured page rows) sized the band
    /// `[0.045, 0.08)`: **16 pages, all of which stop being shrunk** — 0.75% of
    /// sampled pages, 18.0% of the 89 shrunk today, over 10 documents of 233. (A
    /// seventeenth row prints `0.0450`; its true value is under the bar, so it
    /// does not move and is not in the band.)
    /// They cost **838,569 -> 3,804,222 B, 4.54x, 185,353 B a page**, which is
    /// **~21 pages of 16,987 and ~4.0 MB at corpus scale, +0.55%** of R50's
    /// 721 MB gate (the stratified estimate; pooling the rate is 6x high, and the
    /// entry says why). R49/R50 set no growth-tolerance bar, so this was the R55
    /// shape — the campaign measures, the owner closes it on the arithmetic.
    ///
    /// ⚠️ **And the counter-finding is recorded rather than waved away: a
    /// threshold is a blunt instrument here.** 32.4% of the band's byte cost
    /// lands on two pages a reader cannot tell apart (`RIESMAN_1942` p10, the
    /// dearest of the 16 at +702,280 B and 6.47x, whose only non-stencil ink is
    /// a pale scanner-edge strip; and `Riesman - 1954` p18). C26 stays OPEN on
    /// the question this campaign surfaced and this constant cannot answer — why
    /// recognised-page prose is dropped from the stencil at all.
    ///
    /// **What it misses — two cases, both recorded because they will come up.** The
    /// signal is ink, so anything whose luminance sits near the paper/ink boundary
    /// is invisible to it:
    ///
    /// - a *pale* line drawing reads **0.0000**, because Otsu puts light grey on the
    ///   paper side and it is therefore not ink at all;
    /// - a **flat mid-luminance colour field** reads **0.0365**. Measured on a flat
    ///   red plate: it renders at luminance 96–111 while Otsu on that page lands at
    ///   **106**, so half the plate is above the threshold. This is why the suite
    ///   builds a *tonal* plate to test the picture case, and why that fixture must
    ///   not be "simplified" back to a flat one — it would assert the limitation
    ///   instead of the behaviour.
    ///
    /// Both survive the move to 0.045: a pale drawing still reads 0.0000 (R56's
    /// shape signal is the term that reaches it, and it is the second half of
    /// `pageIsAllText()` for that reason), and 0.0365 is still under the bar. ⛔ The
    /// sentence that stood here — *"Neither is alarming, because this only ever
    /// changes resolution: the worst it can do is soften something, never remove
    /// it"* — is **retracted, 2026-08-19**, for the reason given above the table:
    /// at 8x it removes lines of prose. What is still true is that a flat field
    /// loses nothing to a downsample, so the second miss is self-cancelling in the
    /// common case; what suffers is a detailed colour image with no dark tones.
    /// `PhotoDetail.maximum` is honoured in full for exactly this reason — see the
    /// `keepEveryPixel` guard in `mrcLayers`.
    static let textPageInkOutsideThreshold = 0.045

    /// A substitute bar, for a tool asking what a **different** threshold would publish.
    ///
    /// `nil` in the app, always — nothing in `Sources/` sets it and no setting reaches it.
    /// It exists for C26's sub-step 3, which is a pricing question the shipped code cannot
    /// otherwise be asked: three drawings were erased because `inkOutsideText` reads
    /// 0.0493–0.0660 against what was then a bar of 0.08, a bar at 0.045 refuses all three,
    /// and the cost of refusing a page is bytes on every page that newly stays at the
    /// caller's factor. R49/R50 are the entries about paying those bytes, so the number had
    /// to be measured before the constant moved. **It was, and the constant moved on
    /// 2026-08-19 — `textPageInkOutsideThreshold` is 0.045.** So the direction this seam is
    /// driven in has reversed: substituting 0.045 now asks the shipped question, and it is
    /// **0.08** that prices the old behaviour. The suite's C26 block was re-paired for
    /// exactly that reason — a check comparing `nil` against 0.045 is a run compared with
    /// itself, which is a check that cannot fail.
    ///
    /// **It substitutes the bar, not the verdict, and that is the point.** Forcing
    /// `pageIsAllText()` to return false would measure a proxy: **R56's `paleDrawing` term
    /// would stop participating**, so a page refused today by that second term would be priced
    /// as though this first one had moved it. Substituting the comparand leaves the guard in
    /// place, so what a sweep measures is the proposed change and not a hand-forced outcome.
    /// (An earlier version of this comment claimed `keepEveryPixel` for the same argument. It
    /// does not belong there: it is applied *outside* this function — `!keepEveryPixel &&
    /// pageIsAllText()` — so a forced-false verdict and a `keepEveryPixel` page give the same
    /// answer, and the only term the choice actually protects is `paleDrawing`. Caught by the
    /// adversarial review of the diff that added this property.)
    ///
    /// Unlike `rebuildDPIOverride` this one needs no `useHelper` caveat: it is read in
    /// `mrcLayers`, which runs in the app's own process. `visionocr-recognise` compiles this
    /// file — see `build.sh`'s `HELPER_SOURCES` — but never layers a page, so there is no
    /// second address space for the value to be `nil` in.
    nonisolated(unsafe) static var textPageInkOutsideThresholdOverride: Double?

    /// What a page of nothing but text shrinks its tone layers to.
    ///
    /// 8 and 16, measured on `Blacks in the City` page 41 (1899x3138 at 360 DPI),
    /// against the 2 and 4 that ship for pages with pictures on them:
    ///
    /// | | background | foreground | page |
    /// |---|---|---|---|
    /// | 2x / 4x | 36,383 B | 23,894 B | 99,130 B |
    /// | 8x / 16x | 4,374 B | 3,108 B | **46,332 B** |
    ///
    /// At which point the 1-bit stencil is 81% of the page and the tone layers are
    /// 7.5 KB — the Internet Archive's own are 5.8 KB, so this is the right
    /// neighbourhood rather than a number pushed until it hurt. Rendered at 100
    /// DPI beside the 2x/4x version, the text page is indistinguishable.
    static let textPageBackgroundDownsample = 8
    static let textPageForegroundDownsample = 16

    /// The fraction of the page's ink that falls outside `region`.
    ///
    /// The outer sixteenth is ignored on every side. A scan carries the dark edge
    /// of the platen and the shadow in the gutter, which is ink by any threshold
    /// and is not content — on `Blacks in the City` it is most of the ink outside
    /// the words, and counting it put every text page in the book above any
    /// threshold worth setting.
    static func inkOutsideText(_ grey: [UInt8], region: [Bool],
                               width w: Int, height h: Int, threshold: UInt8) -> Double {
        guard w > 0, h > 0, grey.count >= w * h, region.count >= w * h else { return 1 }
        let mx = w / 16, my = h / 16
        let x1 = max(w - mx, mx + 1), y1 = max(h - my, my + 1)
        var outside = 0, total = 0
        for y in my..<min(y1, h) {
            let row = y * w
            for x in mx..<min(x1, w) where grey[row + x] < threshold {
                total += 1
                if !region[row + x] { outside += 1 }
            }
        }
        // No ink at all is a blank page, and a blank page has no picture on it.
        return total > 0 ? Double(outside) / Double(total) : 0
    }

    // MARK: - Shape: what is on the page, rather than how dark it is

    /// The resolution the mark analysis runs at, in cells to the inch.
    ///
    /// A **physical** cell rather than a fixed reduction factor, because the corpus
    /// renders between 72 and 600 DPI and every statistic below is a size in inches.
    /// A fixed factor would make a quarter inch mean 19 cells on one document and 3
    /// on another, and the constants would then be describing the scanner.
    ///
    /// **150, and 75 was tried first and is measurably worse.** 150 ppi is where
    /// Leptonica's own page segmentation operates: `pixGetRegionsBinary` documents its
    /// input as 300–400 ppi and reduces 2x, and `pixGenerateHalftoneMask` documents
    /// *"assumed to be 150 to 200 ppi"* and adds *"this is not intended to work on
    /// small thumbnails"*. Its 37.5 ppi levels are **seeds** for a morphological
    /// reconstruction back into a higher-resolution mask, never a surface a decision
    /// is taken on, and reading them as one is what put the first draft of this at 75.
    /// `RESEARCH-shape-signals.md` §7 is the survey that settles it.
    ///
    /// The cost of the coarser choice was concrete rather than theoretical: at 75 the
    /// interline gap of a 300 DPI page is one or two cells, a rank-1 reduction bridges
    /// it, and the show-through on `Ibson_2006` p29 merges into components four inches
    /// tall — which is exactly what the type ceiling below exists to rule out.
    ///
    /// **It is a ceiling on the analysis resolution rather than the resolution.** The
    /// reduction never *up*samples, so a page rendered below about 225 DPI is analysed
    /// at its own resolution — 72 to 200 cells an inch, and `rebuildDPI`'s own note
    /// records 37 real 72 DPI scans in the corpus. Those pages sit in the coarse
    /// regime the paragraph above rejects, and the honest statement is that they are
    /// covered by the corpus census rather than by this argument: not one of them
    /// changes route, and `Himanen_2001` at 144 DPI is one of the two documents that
    /// measured `minimumMarkContrast`. Upsampling to reach 150 would invent detail,
    /// which C14 and `rebuildDPI` refuse everywhere else in this file.
    static let markCellsPerInch = 150.0

    /// The most cells the mark analysis will ever hold, whatever the page is.
    ///
    /// **R24 and R29's shape, caught before it shipped rather than after.** The
    /// reduction factor is derived from the render's DPI, so on a *low*-resolution
    /// page it is 1 and the analysis runs at full size — and the labelling holds an
    /// `Int32` a cell. `maximumPageMegapixels` allows 400 MP, which a 200-inch page
    /// (PDF ≤1.5's own ceiling on a page box) reaches at 100 DPI, and at factor 1
    /// that is **1.6 GB of labels** on top of a render this file bounds at 5.5 bytes
    /// a pixel. Both R24 and R29 were an allocation bounded in one place and left
    /// unbounded in its sibling; this is that sibling, and it is bounded here.
    ///
    /// **What 4 million cells actually costs, counted rather than estimated** — the
    /// first version of this comment said "16 MB of labels and 8 MB of masks" and
    /// omitted the largest term:
    ///
    /// | buffer | at the ceiling |
    /// |---|---|
    /// | `labels` `[Int32]` | 16 MB |
    /// | `ink`, `pale`, and `pale`'s copy in the suppression pass | 12 MB |
    /// | `area`, `x0`, `x1`, `y0`, `y1` `[Int]`, one entry a *label* | up to 160 MB |
    ///
    /// The last row is the one that was missed, and it is worst on the page kind this
    /// is least interested in: a mask of scanner speckle can produce a label per
    /// second cell. Measured by the review of this diff on a 2000x2000 speckle mask —
    /// 1,000,000 labels, 44 MB — and the ceiling is four times that page.
    ///
    /// A 300 DPI Letter page uses **1.61 M** of the ceiling: 1,116 x 1,444 after
    /// **both** insets and the 2x reduction. (The first version said 1,195 x 1,547,
    /// which is the sixteenth taken off once instead of once at each end — the
    /// arithmetic contradicted `pageMarks`' own doc comment two screens below it.)
    /// Real text pages produce a few thousand labels, not a million, so the honest
    /// figure for the common case is about 1.3 bytes a pixel of render against the
    /// 5.5 the render itself is budgeted at, and the table above is the worst case.
    static let markCellCeiling = 4_000_000

    /// A mark taller than this is not a letter, and so is not show-through either.
    ///
    /// **Physical, and the page-relative version was tried first and is wrong.** The
    /// obvious scale is the median height of the page's own ink components — and on
    /// the halftone fixture that reads 2 cells, because ten thousand halftone dots
    /// outvote three hundred glyphs. A scale taken from the page's own components is
    /// corrupted by exactly the pages this exists to judge. Type on a page is under a
    /// quarter inch: 24 pt has a cap height near 0.24 in, and the corpus holds no body
    /// face remotely that large. Show-through is the *reverse* page's type, so the
    /// same bound holds it.
    ///
    /// Height only, deliberately. Show-through blurs adjacent glyphs into one
    /// component the width of a whole line — four or five inches — so any width term
    /// would put show-through in the same class as a drawing. Its *height* is still a
    /// line's height.
    static let typeCeilingInches = 0.25

    /// How far below its paper a mark has to sit before it is a mark at all.
    ///
    /// **This constant is two measured corpus failures, and without it the pale layer
    /// is mostly paper.** The level below which a pixel is not paper was, in
    /// `score-threshold-loss`'s round 3, the paper's mode less three times the spread
    /// of the peak's clean upper side. On a scan whose white is *clipped* the mode is
    /// 255, there is no upper side, the spread is 0.0, and the rule degenerates to
    /// `paper - 4`. Measured on the corpus that reads a **quarter of the pages of
    /// `Himanen_2001`** — 228 of 255 — as carrying pale content, when what they carry
    /// is a page of type whose 1-bit rendering is perfect and whose "pale marks" are
    /// paper four levels off white.
    ///
    /// The second is faint show-through, 8–15 levels below the paper on the corpus
    /// pages that carry it. That case is *also* held by `maximumInkUnderADrawing`
    /// below, and deliberately by both: this constant keeps it out of the mask at all,
    /// and that one keeps what does get in from being called a drawing. Neither is
    /// sufficient alone — measured, `Ibson_2006` needs the second and `Himanen_2001`
    /// needs the first.
    ///
    /// 24 levels is 9% of the range. The pale-drawing fixture's strokes sit **47**
    /// below their paper, so the constant has a factor of two of headroom against the
    /// case it exists to protect, and the corpus population it excludes is 8–15.
    static let minimumMarkContrast = 24.0

    /// A mark that fills this much of its own bounding box is a filled shape rather
    /// than a stroke: a shaded table cell, not a drawing.
    ///
    /// The two populations are far apart rather than adjacent — a solid rectangle is
    /// 1.0 and the pale-drawing fixture's strokes are 0.11 — so this is a divider
    /// between two clusters, not a tuned threshold.
    static let solidMarkFill = 0.6

    /// A component has to span this much of the sheet before its own tone is asked
    /// about. Below it, a mark is too small for a misjudgement to cost anything.
    ///
    /// **A genuine continuum, and the pages on both sides of it were rendered and
    /// looked at** — which is the only reason a number here is defensible at all. Of
    /// the 114 corpus pages this branch moves, **16 have their qualifying mark between
    /// 0.02 and 0.05 of the sheet**, so that band is what the choice is about:
    ///
    /// - it holds **two `Schwaller` photograph pages** (p173 and p191, small figures on
    ///   a page of type) which 1-bit turns into black shapes;
    /// - and **three `Doermann_1967` pages** whose mark is a scanner-edge blob just
    ///   inside the inset. p22 was rendered: a clean typescript that 1-bit prints
    ///   perfectly, so those three cost bytes and nothing else.
    ///
    /// 0.02, because a page wrongly held in greyscale costs bytes and a page wrongly
    /// thresholded loses its picture. That asymmetry is the register's standing answer
    /// (R50), and it is the whole of why this sits one step low rather than one high.
    ///
    /// *(An earlier draft of this comment justified 0.02 by claiming 0.05 would lose
    /// `Scott_TK` p13's reversed-out advertisement. It would not: p13 stays at 1-bit at
    /// **both** values, because its largest mark does not clear `minimumPlateFill`. The
    /// number was checked against the corpus rather than assumed, and it was wrong —
    /// the same failure the review of this diff had already caught twice.)*
    static let largeMarkShare = 0.02

    /// …and it has to *fill* this much of what it spans, or it is a frame rather than
    /// a plate.
    ///
    /// **Both terms, and each was reached by getting the other one wrong.** The first
    /// version gated on bounding-box area alone: a 3 px rule round the edge of a sheet
    /// spans the whole page, qualified, and the tone of everything the frame *encloses*
    /// was then measured — 1.54x the whole-sheet figure on a synthetic framed text
    /// page, in a branch with no `pictureInkMinimumTone`-style gate to catch it. The
    /// second version gated on the component's own **ink** instead, which is 0.4% for a
    /// frame and correctly refused it — and also refused `Scott_TK` p13, a 1915 trade
    /// magazine page whose reversed-out advertisement really is destroyed at 1-bit.
    ///
    /// Fill is what actually separates the two: a frame is 0.02 of its box, a plate is
    /// 0.5 to 0.9. 0.25 sits in the middle of that gap and is a divider between two
    /// clusters rather than a tuned value. Held by a check on a synthetic framed page,
    /// where setting this to 0.0 makes the frame's own tone read **0.1668 against the
    /// sheet's 0.1223** — and the first version of that check drew its frame inside the
    /// margin the analysis crops away, so it could not fail. `mutate.py` found that,
    /// not a person.
    ///
    /// **What it gives up, named because it was measured.** `Scott_TK` p13's
    /// reversed-out advertisement — a 1915 trade-magazine page that 1-bit turns into a
    /// black rectangle with illegible white text — has a largest mark spanning 0.16 of
    /// the sheet and does *not* clear this, so the page stays at 1-bit. The
    /// advertisement is white type on black, so the component that survives the
    /// reduction is the type rather than the ground. Recorded rather than fixed: the
    /// term is what keeps a page *frame* from being read as a plate, and no value of it
    /// separates those two cases.
    static let minimumPlateFill = 0.25

    /// How much ink may sit inside a pale mark's own rectangle before the mark is
    /// judged to be lying *in* the type rather than in a space of its own.
    ///
    /// **This is the term that separates a drawing from show-through, and it is the
    /// only one tried that does.** R56's refusal turns on those two being
    /// indistinguishable, and four rounds of luminance and two of shape agree with it:
    /// a contrast floor cannot separate them (`Doermann_1967`'s show-through is as far
    /// below its paper as the fixture's strokes are below theirs), and neither can
    /// size or fill (at any reduction, show-through merges into components taller than
    /// a line and emptier than a block).
    ///
    /// What does separate them is **where they are**. A figure occupies a part of the
    /// sheet the type does not; show-through lies *in* the type, because it is the
    /// reverse page's type and the two pages are set to the same measure. So the
    /// question is asked of the mark's own rectangle: how much of it is this page's
    /// ink?
    ///
    /// Measured, holding everything else fixed, counting pages over the threshold:
    ///
    /// | | term off | at 0.10 | at 0.05 | at 0.02 |
    /// |---|---|---|---|---|
    /// | `Doermann_1967`, show-through, 27 pp | 24 | 2 | **1** | 1 |
    /// | `Ibson_2006`, show-through, 263 pp | 93 | 0 | **0** | 0 |
    /// | `Boltanski_2006`, dense type, 203 pp | 0 | 0 | **0** | 0 |
    /// | the pale-drawing fixture | fires | fires | **fires** | fires |
    ///
    /// The fixture does not move by a thousandth across the whole range, because its
    /// plate has no type under it at all. 0.05 is the middle of a range where the
    /// answer does not change, which is the most a constant can be asked to be.
    static let maximumInkUnderADrawing = 0.05

    /// How much of the sheet **one** drawing-shaped pale mark has to span before the
    /// page is kept off the 1-bit route.
    ///
    /// **One mark, not the sum of them, and the first version summed.** It summed the
    /// *ink* of every drawing-shaped mark, which is the wrong statistic twice over: it
    /// makes a page of scattered specks look like a page with a figure on it, and it
    /// under-counts the very thing it exists to protect, because a drawing is thin.
    /// The `pale-chart` fixture — a chart drawn the way charts are drawn, hairline
    /// plot lines with its own axis numerals inside the frame — scored **0.0115** of
    /// the sheet in ink against a 0.012 bar and was erased, while the same page's mark
    /// *spans* 0.2221 of the sheet. R49 said this three days earlier in one sentence:
    /// text is thousands of small components and a subject is one large one. The
    /// question is about the mark, not about the page.
    ///
    /// 0.05 of a Letter sheet is 4.7 square inches — a mark about 2.2 inches on a
    /// side. Measured over ten documents chosen for being awkward: the two
    /// show-through ones, R38's dense-type one, the faded-type one, and four that
    /// carry real pale marks.
    ///
    /// | | pages | over 0.02 | over 0.05 | over 0.10 |
    /// |---|---|---|---|---|
    /// | `Doermann_1967` + `Ibson_2006` — show-through | 290 | 1 | **0** | 0 |
    /// | `Boltanski_2006` — dense type, R38's document | 203 | 2 | **0** | 0 |
    /// | `Himanen_2001` — faded type | 255 | 0 | **0** | 0 |
    /// | `Broadhead_1994` | 13 | 13 | **0** | 0 |
    /// | four documents carrying real pale marks | 61 | 26 | **17** | 11 |
    /// | the two positive fixtures | 2 | 2 | **2** | 2 |
    ///
    /// The confusers cluster under 0.02 and the fixtures sit at 0.2221 and 0.2556, so
    /// 0.05 is 2.5x above one population and 4.4x below the other. That is a divider
    /// between two clusters rather than a tuned value — which is the most a constant
    /// in this neighbourhood has ever managed.
    ///
    /// What it gives up is a *small* figure: under 2.2 inches on a side, a pale
    /// drawing is still erased. That is recorded rather than fixed, because the
    /// alternative is a threshold inside the confuser cluster.
    static let paleDrawingThreshold = 0.05

    /// One connected mark: where it is, how big, and how much of its box it fills.
    struct MarkComponent {
        var x = 0, y = 0
        var width = 0, height = 0
        var area = 0
        /// Set cells over bounding-box area. A solid rectangle is 1.0; a curved
        /// stroke is a tenth of that, and that difference is the whole of how a
        /// drawing is told from a shaded table cell.
        var fill: Double { Double(area) / Double(max(width * height, 1)) }
    }

    /// The page at `markCellsPerInch`, in two layers: what the threshold calls ink,
    /// and the marks it will erase.
    ///
    /// **Why a reduced mask and not the render.** Component labelling over a 300 DPI
    /// page would hold a label per pixel — 4 bytes where the render holds 1 — and
    /// `maximumPageMegapixels` is sized at 5.5 bytes a pixel for the render alone.
    /// R24 and R29 are both an allocation bounded in one place and unbounded in its
    /// sibling; this one is built to stay inside the bound that already exists. On a
    /// 300 DPI Letter page the two masks and the suppression pass's copy are
    /// **0.57 bytes a pixel** of render, against the 5.5 the render is budgeted at.
    /// `markCellCeiling` has the worst case, which is larger and is dominated by a
    /// term the first version of that comment left out entirely.
    ///
    /// **The pale layer is `Tools/score-threshold-loss.swift`'s population, minus its
    /// fourth property.** Properties 2 and 3 are kept, because both are measured and
    /// both are about what a mark *is*: an anti-aliased edge is not content, and a
    /// large pale area must not be allowed to redefine what paper is. Property 4,
    /// thinness, is deliberately dropped — it exists to suppress table shading, which
    /// is a judgement about the *kind* of mark, and making that judgement by shape is
    /// the whole point of this. R56 refused the luminance version of it.
    struct Marks {
        var ink: [Bool] = []
        var pale: [Bool] = []
        var width = 0, height = 0
        /// The luminance below which a pixel is too dark to be this page's paper.
        var paperLimit = 0
        /// Cells inside the inset, which is what every share below is a share of.
        var cells = 0
        /// Render pixels to a cell, and where cell (0, 0) starts in the render.
        /// Carried rather than recomputed: `largeMarkTone` has to map a component
        /// back onto the render, and reconstructing the factor by dividing the two
        /// sizes is a second answer to a question that already has one — C20's shape,
        /// and it rounds differently.
        var factor = 1
        var originX = 0, originY = 0
        /// Pale cells property 2 threw away: pale, not ink, and 8-adjacent to ink.
        ///
        /// Carried for the same reason `factor` is — it cannot be recovered from
        /// outside without becoming a second answer to a question that already has
        /// one. Recomputing the pale band needs `limit`, and `paperLimit` is that
        /// number **floored**, so a replica's `v < paperLimit` and `v <= paperLimit`
        /// straddle production's own `Double(v) < limit` and each is right on some
        /// pages and wrong on others. C26's instrument needs the count and nothing
        /// else does; it is written here rather than guessed there.
        ///
        /// Diagnostic only. Nothing in the app reads it and no decision turns on it.
        var paleBesideInk = 0
    }

    /// Build both layers in one pass over the render.
    ///
    /// The outer sixteenth is dropped on every side, which is `inkOutsideText`'s
    /// inset and its recorded reason: a scan carries the dark edge of the platen and
    /// the shadow in the gutter, and that is ink by any threshold and is not content.
    /// Without it the largest component on a great many corpus pages is the gutter,
    /// and every statistic here would be describing the scanner.
    static func pageMarks(_ grey: [UInt8], width w: Int, height h: Int,
                          threshold: UInt8, dpi: Double,
                          minimumContrast: Double = minimumMarkContrast) -> Marks {
        var out = Marks()
        guard w > 0, h > 0, grey.count >= w * h, dpi > 0 else { return out }
        let mx = w / 16, my = h / 16
        let cx1 = max(w - mx, mx + 1), cy1 = max(h - my, my + 1)
        let rows = my..<min(cy1, h), cols = mx..<min(cx1, w)
        guard rows.count > 0, cols.count > 0 else { return out }

        // Property 3: the paper's level is the mode of everything the threshold calls
        // paper, and its noise is measured from the side of that peak pale content
        // cannot reach. The mean is unusable — a large pale area is part of the bright
        // class, so it drags the mean down and inflates the spread until it excludes
        // itself, which is what defeated round 2 of R56 outright.
        var histogram = [Int](repeating: 0, count: 256)
        var bright = 0
        for y in rows {
            let row = y * w
            for x in cols where grey[row + x] >= threshold {
                histogram[Int(grey[row + x])] += 1; bright += 1
            }
        }
        var paper = Int(threshold), peak = -1
        for v in Int(threshold)..<256 where histogram[v] > peak {
            peak = histogram[v]; paper = v
        }
        var weighted = 0, counted = 0
        for v in paper..<256 { weighted += histogram[v] * (v - paper); counted += histogram[v] }
        let spread = counted > 0 ? Double(weighted) / Double(counted) : 0
        // The floor is `minimumMarkContrast`, and it is doing most of the work: on a
        // scan with clipped white the spread is 0.0 and three times nothing is
        // nothing. See the constant for the two corpus documents that measured it.
        let limit = bright > 0
            ? Double(paper) - max(3 * spread, minimumContrast) : Double(threshold)
        out.paperLimit = Int(max(limit, Double(threshold)))

        // The physical factor, then coarsened further if the page is large enough to
        // breach the cell ceiling. Both bounds, not either: the first makes the
        // constants mean inches, the second keeps the allocation finite.
        //
        // **`safeInt`, not `Int`.** `dpi` descends entirely from what the file declares
        // and is bounded above by nothing: `MediaBox [0 0 1e-16 1e-16]` with an image
        // declaring 2000x2000 gives 1.44e21, which is 4 megapixels — inside both the
        // render's 400 MP gate and layering's 100 MP one — and `Int(1.44e21/150)` is
        // an **uncatchable** trap that takes every concurrent file in the batch with
        // it. This is A7.1's shape at a sixth site in this file, and A7.1 verified the
        // same reachability end to end at 5.76e19 on shipped defaults. Found by the
        // review of this diff, using CONTRIBUTING 4b's own suggested grep.
        var factor = max(safeInt((dpi / markCellsPerInch).rounded()), 1)
        // **The loop must test the cell count that is actually allocated**, which is
        // the one below with its `max(…, 1)` in it. Testing the bare floored product
        // is a bound that does not bind: a 20,000,000 x 1 render floors the height to
        // zero, the product is zero, the loop exits at once and 8.75 million cells are
        // allocated against a ceiling of four. R24 and R29 are both a bound written in
        // one place and not holding in its sibling, and this was very nearly the third
        // — in the constant whose own comment says it was "caught before it shipped".
        while factor < Int.max / 2,
              max(cols.count / factor, 1) * max(rows.count / factor, 1) > markCellCeiling {
            factor *= 2
        }
        let rw = max(cols.count / factor, 1), rh = max(rows.count / factor, 1)
        out.width = rw; out.height = rh; out.cells = rw * rh
        out.factor = factor
        out.originX = cols.lowerBound; out.originY = rows.lowerBound
        var ink = [Bool](repeating: false, count: rw * rh)
        var pale = [Bool](repeating: false, count: rw * rh)
        let hasPale = limit > Double(threshold)

        // A cell is ink if *any* pixel in it is ink, and pale if it is not ink and any
        // pixel in it is pale. Rank-1, which is Leptonica's own default for keeping
        // thin strokes through a reduction and the reason a box filter will not do:
        // R56's whole subject is a hairline at luminance 200, and averaging a 4x4 cell
        // holding one such stroke puts the cell back on the paper side. A mask that
        // cannot represent the thing being detected is not a resolution choice, it is
        // the detector failing silently.
        for y in rows {
            let ry = (y - rows.lowerBound) / factor
            guard ry < rh else { continue }
            let row = y * w, base = ry * rw
            for x in cols {
                let rx = (x - cols.lowerBound) / factor
                guard rx < rw else { continue }
                let v = grey[row + x]
                if v < threshold {
                    ink[base + rx] = true
                } else if hasPale, Double(v) < limit {
                    pale[base + rx] = true
                }
            }
        }
        // Ink wins the cell, and its neighbours are suppressed as well — property 2,
        // at this resolution. An edge is always beside ink and a mark is surrounded by
        // paper, and a cell is 1/150 in at 300 DPI — wider than any anti-aliased edge.
        for i in 0..<(rw * rh) where ink[i] { pale[i] = false }
        if hasPale {
            var kept = pale
            for y in 0..<rh {
                for x in 0..<rw where pale[y * rw + x] {
                    var beside = false
                    for dy in max(y - 1, 0)...min(y + 1, rh - 1) where !beside {
                        for dx in max(x - 1, 0)...min(x + 1, rw - 1) where ink[dy * rw + dx] {
                            beside = true; break
                        }
                    }
                    if beside { kept[y * rw + x] = false; out.paleBesideInk += 1 }
                }
            }
            pale = kept
        }
        out.ink = ink
        out.pale = pale
        return out
    }

    /// Connected components of a reduced mask, 8-connected, two passes with a
    /// union-find.
    ///
    /// Components smaller than `minimumCells` are dropped: at 150 cells to the inch
    /// three cells is about a fiftieth of an inch, which is a speck of scanner noise
    /// rather than a mark, and a page of dirty photocopy carries thousands of them.
    /// **The number did not change when the resolution doubled and it should be read
    /// as a floor, not as a size** — nothing downstream depends on it, because both
    /// consumers filter far above it: `largeMarkTone` wants 2% of the sheet and
    /// `paleDrawing` wants a quarter inch of height.
    static func markComponents(_ mask: [Bool], width w: Int, height h: Int,
                               minimumCells: Int = 3) -> [MarkComponent] {
        guard w > 0, h > 0, mask.count >= w * h else { return [] }
        var labels = [Int32](repeating: 0, count: w * h)
        var parent: [Int32] = [0]
        func find(_ a: Int32) -> Int32 {
            var r = a
            while parent[Int(r)] != r { r = parent[Int(r)] }
            var c = a
            while parent[Int(c)] != c { let n = parent[Int(c)]; parent[Int(c)] = r; c = n }
            return r
        }
        for y in 0..<h {
            let row = y * w
            for x in 0..<w where mask[row + x] {
                var best: Int32 = 0
                // West, north-west, north, north-east: the four already-labelled
                // neighbours of an 8-connected pixel in raster order.
                for (dx, dy) in [(-1, 0), (-1, -1), (0, -1), (1, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < w, ny >= 0 else { continue }
                    let l = labels[ny * w + nx]
                    guard l != 0 else { continue }
                    if best == 0 {
                        best = l
                    } else {
                        let ra = find(best), rb = find(l)
                        if ra != rb { parent[Int(max(ra, rb))] = min(ra, rb) }
                        best = min(best, l)
                    }
                }
                if best == 0 {
                    parent.append(Int32(parent.count))
                    best = Int32(parent.count - 1)
                }
                labels[row + x] = best
            }
        }
        // `Int32`, not `Int`. These are five arrays with one entry per *label*, and a
        // mask of scanner speckle produces a label per second cell — at
        // `markCellCeiling` that is 160 MB in `Int`, which is the largest allocation in
        // this file and the one `markCellCeiling`'s first accounting left out
        // entirely. Every value is bounded by the mask's own width, height or area, so
        // 32 bits is not a narrowing.
        var area = [Int32](repeating: 0, count: parent.count)
        var x0 = [Int32](repeating: Int32(w), count: parent.count)
        var x1 = [Int32](repeating: -1, count: parent.count)
        var y0 = [Int32](repeating: Int32(h), count: parent.count)
        var y1 = [Int32](repeating: -1, count: parent.count)
        for y in 0..<h {
            let row = y * w
            for x in 0..<w where labels[row + x] != 0 {
                let r = Int(find(labels[row + x]))
                area[r] += 1
                if Int32(x) < x0[r] { x0[r] = Int32(x) }
                if Int32(x) > x1[r] { x1[r] = Int32(x) }
                if Int32(y) < y0[r] { y0[r] = Int32(y) }
                if Int32(y) > y1[r] { y1[r] = Int32(y) }
            }
        }
        var out: [MarkComponent] = []
        for r in 1..<parent.count where area[r] >= Int32(minimumCells) && x1[r] >= 0 {
            out.append(MarkComponent(x: Int(x0[r]), y: Int(y0[r]),
                                     width: Int(x1[r] - x0[r]) + 1,
                                     height: Int(y1[r] - y0[r]) + 1,
                                     area: Int(area[r])))
        }
        return out
    }

    /// The most continuous tone found **inside** one of the page's large marks,
    /// rather than averaged over the sheet.
    ///
    /// **R57 in one line.** `pictureToneThreshold` is not miscalibrated — the tonal
    /// plate reads 0.102 against its 0.12 — it is being asked about the wrong region.
    /// A plate over a fifth of a page dilutes its own tone by five, and the constant
    /// was measured on pages a picture *dominates*. A connected component gives the
    /// tone the region it belongs to, so the existing constant can be asked the
    /// question it was calibrated for: is *this thing* continuous tone?
    ///
    /// It is the same argument `pictureInkMinimumTone` already rests on and it cuts
    /// the same way. A halftone is bimodal, so a coarse screen's own component reads
    /// low and stays on the 1-bit route where R38 measured that it belongs; a solid
    /// black rule or a rubber stamp reads near zero for the same reason. What reads
    /// high is an unresolved halftone or a photograph, which is exactly what 1-bit
    /// destroys.
    static func largeMarkTone(_ marks: Marks, grey: [UInt8], width w: Int, height h: Int,
                              threshold: UInt8) -> Double {
        guard marks.cells > 0, w > 0, h > 0, grey.count >= w * h else { return 0 }
        let factor = max(marks.factor, 1)
        var best = 0.0
        for c in markComponents(marks.ink, width: marks.width, height: marks.height) {
            // Big enough to matter, **and solid enough to be a thing rather than a
            // frame round other things**. See `minimumPlateFill`: gating on the box
            // alone admits a page border and then measures the tone of the type inside
            // it, and gating on the component's own ink instead refuses a real
            // reversed-out advertisement.
            guard Double(c.width * c.height) / Double(marks.cells) >= largeMarkShare,
                  c.fill >= minimumPlateFill else { continue }
            // Back to the render's own coordinates, clamped: the reduction floors, so
            // the last cell of a row can name pixels the render does not have.
            let px0 = min(marks.originX + c.x * factor, w - 1)
            let py0 = min(marks.originY + c.y * factor, h - 1)
            let px1 = min(px0 + c.width * factor, w)
            let py1 = min(py0 + c.height * factor, h)
            guard px1 > px0, py1 > py0 else { continue }
            var patch = [UInt8](); patch.reserveCapacity((px1 - px0) * (py1 - py0))
            for y in py0..<py1 { patch.append(contentsOf: grey[(y * w + px0)..<(y * w + px1)]) }
            best = max(best, toneFraction(of: patch, threshold: threshold))
        }
        return best
    }

    /// The pale marks on this page that are **shaped like a drawing**: taller than
    /// any type could be, not a filled block, and not lying in the type.
    ///
    /// **R56 in one line.** The blind zone above the threshold holds three kinds of
    /// thing and luminance cannot separate them — a pale drawing (keep it), decorative
    /// table shading (harmless to lose) and show-through from the reverse of the sheet
    /// (losing it is *desirable*). Four rounds of luminance signal were refused on
    /// exactly that, and the register's own summary is the specification for this
    /// function: every one of the three is a statement about shape.
    ///
    ///  - show-through is the reverse page's type, so it is the size of type. It is
    ///    under the ceiling, and it is not counted.
    ///  - shading is a filled rectangle: over the ceiling, and it fills its box.
    ///  - a drawing's strokes are long and thin, so the box is large and mostly empty.
    ///    That is what this returns.
    struct PaleDrawing {
        /// The largest drawing-shaped mark's bounding box, as a share of the sheet.
        /// **This is the one the route is decided on.**
        var extent = 0.0
        /// The ink of every drawing-shaped mark, as a share of the sheet. Kept
        /// because it is what the first version decided on, and because the census
        /// prints both — see `paleDrawingThreshold` for why it was the wrong one.
        var coverage = 0.0
    }

    static func paleDrawing(_ marks: Marks, dpi: Double,
                            maximumInkInBox: Double = maximumInkUnderADrawing)
        -> PaleDrawing {
        var out = PaleDrawing()
        guard marks.cells > 0, dpi > 0 else { return out }
        // From the reduction the marks were actually taken at, not from
        // `markCellsPerInch`: `pageMarks` coarsens past that when a page would breach
        // `markCellCeiling`, and a ceiling computed from the nominal resolution would
        // then be measuring a different page from the one in hand. Never fewer than
        // two cells, or at a coarse reduction every mark clears it.
        let ceiling = max(typeCeilingInches * dpi / Double(max(marks.factor, 1)), 2)
        /// Ink cells inside a component's bounding rectangle, over that rectangle's
        /// area — not over `MarkComponent.area`, which is the mark's own ink and is a
        /// different number.
        func inkUnder(_ c: MarkComponent) -> Double {
            guard marks.ink.count >= marks.width * marks.height else { return 1 }
            var ink = 0
            for y in c.y..<min(c.y + c.height, marks.height) {
                let row = y * marks.width
                for x in c.x..<min(c.x + c.width, marks.width) where marks.ink[row + x] {
                    ink += 1
                }
            }
            return Double(ink) / Double(max(c.width * c.height, 1))
        }
        var drawing = 0, widest = 0
        for c in markComponents(marks.pale, width: marks.width, height: marks.height)
        where Double(c.height) > ceiling && c.fill < solidMarkFill
                && inkUnder(c) <= maximumInkInBox {
            drawing += c.area
            widest = max(widest, c.width * c.height)
        }
        out.coverage = Double(drawing) / Double(marks.cells)
        out.extent = Double(widest) / Double(marks.cells)
        return out
    }

    /// The largest page that gets layered.
    ///
    /// Not `maximumPageMegapixels`, which is the bound on *rendering* a page and
    /// is sized for the grey buffer at 5.5 bytes a pixel. Layering the same page
    /// holds a good deal more at once. At 400 MP that would be over 3 GB for a
    /// saving, on a page nobody asked to be made smaller.
    ///
    /// **This paragraph used to enumerate the wrong phase** (A3.1): "the grey
    /// buffer, the stencil, the text-region map, the filled background, and
    /// inside `fillHoles` a second copy of the buffer plus two more flag arrays —
    /// about 8 bytes a pixel". Every item is real and the peak is not among them.
    /// `sauvolaMask` runs first and holds two `(w+1)(h+1)` `[Double]` integral
    /// images — **16 bytes a pixel on their own** — and it is not in the list.
    /// The peak of a function is the maximum over its phases, not the phase
    /// somebody enumerated.
    ///
    /// 100 MP matches `maximumColourPageMegapixels`, which was measured for the
    /// same reason. Above it the page keeps the single JPEG it already has,
    /// which is exactly what MRC declining is supposed to do.
    ///
    /// R24 and R29 are both this shape — an allocation bounded in one place and
    /// not in its sibling — so the bound is asserted directly by
    /// `mrcBoundIsWithinTheRenderOne` rather than left to be inferred.
    static let maximumMRCPageMegapixels = 100

    /// Peak bytes per pixel while layering, against the render's 5.5.
    ///
    /// **Analytic, and named for it** (A3.1). The 8.0 that stood here was an
    /// RSS measurement of the wrong phase, and RSS is the wrong instrument for
    /// this question: `ru_maxrss` is a high-water mark and libmalloc keeps freed
    /// large blocks mapped and dirty, so over a multi-phase function it reads as
    /// a sum of distinct-size peaks rather than a maximum. The review's control
    /// settles it — two 8 B/px phases with a `free` between them read 16.38 by
    /// `ru_maxrss` and 8.00 by live bytes.
    ///
    /// So this is counted from the code instead, at the peak phase
    /// (`sauvolaMask`), which is the one the enumeration above missed:
    ///
    /// | buffer | bytes a pixel |
    /// |---|---|
    /// | `grey` `[UInt8]` w·h | 1 |
    /// | `sum` `[Double]` (w+1)(h+1) | 8 |
    /// | `sq` `[Double]` (w+1)(h+1) | 8 |
    /// | `mask` `[Bool]` w·h | 1 |
    /// | | **18** |
    ///
    /// Corroborated independently: the review measured **19.11 B/px live** on a
    /// real page against this 18.005 analytic, and the phases provably do not
    /// overlap — `renderGrey + sauvolaMask` and the whole grey `mrcLayers` read
    /// the same 1,181.8 MB live peak, to the byte.
    ///
    /// **What this number does not include**, on either side of the comparison:
    /// CoreGraphics' own buffers for the render and the JPEG encode. The bound
    /// below is therefore a statement about *this file's* allocations, which is
    /// what it can honestly be.
    static let analyticMRCBytesPerPixel = 18.0

    /// Whether layering's worst case stays inside the render's.
    ///
    /// 100 × 18.0 = 1.8 GB against 400 × 5.5 = 2.2 GB. It held at the old 8.0 and
    /// it still holds at the real number, which is the useful thing to be able to
    /// say after correcting a constant by 2.25x.
    static var mrcBoundIsWithinTheRenderOne: Bool {
        Double(maximumMRCPageMegapixels) * analyticMRCBytesPerPixel
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
        /// JPEGs, grey or three-channel as `isColour` says. The background holds
        /// paper and pictures, the foreground holds ink colour, and the stencil
        /// says which shows.
        let background: URL
        let foreground: URL
        let backgroundWidth: Int, backgroundHeight: Int
        let foregroundWidth: Int, foregroundHeight: Int
        /// True when the two tone layers are three-channel. The assembled stream
        /// dictionary has to agree: a three-channel JPEG declared /DeviceGray
        /// draws as noise, and nothing reports it.
        var isColour = false
    }

    /// Peak bytes per pixel while layering a *colour* page.
    ///
    /// Colour layering holds, at peak: the grey render the stencil comes from (1),
    /// the RGBA render (4), the stencil, the text-region map and its inverse (3),
    /// the channel plane being worked on and its filled copy (2), and inside
    /// `fillHoles` a second copy of that plane plus two flag arrays (4) — 14 so far.
    /// The three planes are taken and released one at a time, which is why this is
    /// not three times the grey figure.
    ///
    /// **The interleaved output layer is not always small.** An earlier version of
    /// this comment said the downsampled layers were "small by construction", which
    /// is true at every Photo detail level except the one that matters:
    /// `PhotoDetail.maximum` is a factor of **1**, `downsample` returns its input
    /// unchanged, and the interleaved RGBA background is then a full-resolution
    /// 4 B/px buffer with `jpegRGB`'s 24-bit representation another 3 on top of it.
    /// That is 21, not 14. Found by reviewing this code rather than by running out
    /// of memory, which is the good way to find it.
    ///
    /// **22.0 was that sum rounded up, and it was short by three** (A3.1). Counted
    /// buffer by buffer at the peak — channel 0 of the interleave, at
    /// `PhotoDetail.maximum` where every downsample factor is 1:
    ///
    /// | buffer | bytes a pixel |
    /// |---|---|
    /// | `grey`, `mask`, `region`, `inverse`, `maskPixels` | 5 |
    /// | `rgba` from `renderRGB`, w·h·4 | 4 |
    /// | `plane`, `filledBG`, `bgPlane`, `filledFG`, `fgPlane` | 5 |
    /// | `background` w·h·4, `foreground` w·h·4 | 8 |
    /// | `fillHoles`' own copy and two flag arrays, during the second call | 3 |
    /// | | **25** |
    ///
    /// The old sum reasoned about the interleaved *background* and forgot that the
    /// **foreground** is a second full-resolution RGBA buffer at that setting, and
    /// that both `fillHoles` results are alive at once. The review's independent
    /// measurement reads 42.4 B/px by peak footprint, which is this plus
    /// CoreGraphics' render and encode buffers — outside what this file allocates
    /// and outside both sides of the bound below.
    static let analyticColourMRCBytesPerPixel = 25.0

    /// The largest page that gets layered **in colour**.
    ///
    /// A3.1: at the corrected 25 B/px, 100 MP is 2.5 GB against the render's
    /// 2.2 GB, so the property below was false at the shipped bound while both
    /// assertions passed — the colour one by sitting exactly on the boundary,
    /// which the review rightly calls the signature of a constant tuned to pass.
    ///
    /// **Derived, not chosen**: 400 × 5.5 / 25 = 88. A colour page larger than
    /// this is layered in **grey** rather than not at all — the same fallback
    /// `mrcLayers` already takes when the colour render fails, and for the same
    /// reason: layering in grey is an improvement on the single JPEG, and nothing
    /// about the colour route is a requirement.
    ///
    /// Corpus impact **none**: the largest page in the 233-document corpus is
    /// 64.84 MP, and there are no pages over 72 MP.
    static let maximumColourMRCPageMegapixels = 88

    /// Whether colour layering's worst case stays inside the render's, the same
    /// property `mrcBoundIsWithinTheRenderOne` asserts for the grey route.
    ///
    /// Against `maximumColourMRCPageMegapixels`, not the grey bound: that is the
    /// correction. Reading the grey bound here was what made a false statement
    /// pass — the two routes hold different amounts and were compared as if they
    /// held the same.
    static var colourMRCBoundIsWithinTheRenderOne: Bool {
        Double(maximumColourMRCPageMegapixels) * analyticColourMRCBytesPerPixel
            <= Double(maximumPageMegapixels) * measuredGreyBytesPerPixel
    }

    /// The local window for a page rendered at `dpi`, bounded at both ends.
    ///
    /// A quarter of an inch is the measured choice and stays the choice; this only
    /// stops a declared-geometry absurdity from reaching the arithmetic. The upper
    /// bound is half the shorter side, because a window wider than the image is a
    /// *global* threshold wearing a local threshold's name.
    ///
    /// **Truncating, not rounding.** `safeInt(dpi / 4)` is `Int(dpi / 4)` for every
    /// value in range, so the window this returns for a page the app can actually
    /// render is the byte-identical one it returned before. A `.rounded()` here
    /// would move the window by one pixel on about half of all pages — a silent
    /// change to the 1-bit stencil on the default route, bought for nothing, in a
    /// fix for a trap. That is this project's own recurring defect shape
    /// (CONTRIBUTING preamble), so the conversion stays truncating.
    static func sauvolaWindow(dpi: Double, width w: Int, height h: Int) -> Int {
        let quarterInch = safeInt(dpi / 4)
        let ceiling = max(3, min(w, h) / 2)
        return min(max(quarterInch, 3), ceiling)
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
        // Clamped here as well as by `sauvolaWindow`, because `y + r + 1` below
        // overflows for an `r` that is merely large — a window a caller obtained
        // without going through the helper would trap inside this function rather
        // than at the conversion. Its own invariant, enforced by itself.
        let r = min(max(window / 2, 1), max(w, h))
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
    ///
    /// **Re-measured over 74 corpus picture pages (T15), and the "smaller" half is
    /// the solid one**: the confined stencil is 1.33x smaller in total and *never*
    /// larger on a single page. The page-total pair above is superseded — a blind
    /// run also skips R50's shrink and layers colour pages in grey, so most of any
    /// whole-sample gap is not confinement at all. On the 26 pages where the two
    /// differ in exactly one way it is 1.07x. `FEATURES.md` has both columns.
    static func textRegionMask(_ boxes: [SearchableWriter.BoundingBox],
                               width w: Int, height h: Int) -> [Bool] {
        // The guard first. `[Bool](repeating:count:)` was being asked for `w * h`
        // on the line *above* the check that either is positive — A7.3's list, and
        // the shape R24 and R29 are both made of.
        guard w > 0, h > 0 else { return [] }
        var region = [Bool](repeating: false, count: w * h)
        for b in boxes {
            // A non-finite or absurd word box traps the conversion, uncatchably,
            // 1,300 lines below the `safeInt` that exists for exactly this (A3.2).
            // Skipped rather than clamped: a box this arithmetic cannot describe is
            // not a region to include, and including the whole page would put a
            // picture into the stencil — which is what `textRegionMask` exists to
            // prevent.
            guard b.x.isFinite, b.y.isFinite, b.width.isFinite, b.height.isFinite
            else { continue }
            // The pad is a fraction of the box's *height* in both directions, so
            // it is converted through the aspect ratio for the horizontal one.
            let padY = b.height * mrcBoxPadding
            let padX = padY * Double(h) / Double(w)
            let x0 = max(safeInt((b.x - padX) * Double(w)), 0)
            let x1 = min(safeInt((b.x + b.width + padX) * Double(w)) &+ 1, w)
            let y0 = max(safeInt((b.y - padY) * Double(h)), 0)
            let y1 = min(safeInt((b.y + b.height + padY) * Double(h)) &+ 1, h)
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
    /// **The last `w mod f` columns and `h mod f` rows are not sampled** (A3.4),
    /// and `JBIG2.assemble` then stretches the layer over the whole page box: at
    /// 1,899 px and f=16 that drops 11 columns, a **0.58% horizontal stretch**. Only
    /// ever the tone layers, and only where they are flat enough to have been
    /// downsampled by 16 in the first place, so it is invisible in practice — but it
    /// was undocumented, which is how a 0.58% geometric error becomes somebody's
    /// afternoon. Not fixed: sampling the ragged edge would need a partial-window
    /// mean, and the layer it affects is a blur by construction.
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
    ///
    /// `inColour` layers the page's three channels instead of its luminance, for
    /// a page Automatic decided to keep in colour. It is the same decomposition
    /// run once per channel — deliberately, rather than a colour-specific
    /// algorithm: `fillHoles` and `downsample` are the two pieces whose constants
    /// were measured, and reusing them per plane keeps that calibration rather
    /// than inventing a second version of it to re-measure.
    static func mrcLayers(for page: PDFPage, boxes: [SearchableWriter.BoundingBox],
                          into directory: URL, stem: String,
                          backgroundDownsample: Int = mrcBackgroundDownsample,
                          foregroundDownsample: Int = mrcForegroundDownsample,
                          inColour: Bool = false) -> MRCLayers? {
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
        // A3.1. Colour layering holds 25 bytes a pixel against grey's 18, so it
        // stops sooner — and stopping means *grey* layering, not none.
        if inColour, wide * high > Double(maximumColourMRCPageMegapixels) * 1_000_000 {
            return mrcLayers(for: page, boxes: boxes, into: directory, stem: stem,
                             backgroundDownsample: backgroundDownsample,
                             foregroundDownsample: foregroundDownsample, inColour: false)
        }
        let w = max(Int(wide), 1), h = max(Int(high), 1)
        guard let grey = renderGrey(page, box: box, scale: scale,
                                    width: w, height: h, from: .mediaBox) else { return nil }

        // `safeInt`, not `Int`, and clamped at both ends. `dpi` descends entirely
        // from what the file declares and is *not* covered by the megapixel guard
        // above, because `wide` reduces algebraically to the declared `/Width`:
        // `MediaBox [0 0 1e-14 1.3e-14]` with an image declaring 8000x10400 gives
        // dpi 5.76e+19, both gates pass, and `Int(1.44e19)` against `Int.max`
        // 9.22e18 **trapped uncatchably**, taking every concurrent file with it
        // (A7.1, verified end to end on shipped defaults). The upper clamp is the
        // second half: at a merely large DPI the window computed to 3.6e12, so
        // Sauvola's radius covered the whole image and it silently degenerated
        // into the single global threshold its own doc comment exists to avoid.
        var mask = sauvolaMask(grey, width: w, height: h,
                               window: sauvolaWindow(dpi: dpi, width: w, height: h))
        guard mask.count == w * h else { return nil }
        let region = textRegionMask(boxes, width: w, height: h)
        for i in 0..<(w * h) where !region[i] { mask[i] = false }
        // A stencil with nothing in it is not a layering, it is a downsampled
        // page. Refuse it the same way an empty box list is refused.
        guard mask.contains(true) else { return nil }

        let inverse = mask.map { !$0 }

        // R50. A page whose ink is all text has nothing in its tone layers worth
        // full resolution, so both are shrunk far harder. See
        // `textPageInkOutsideThreshold` for why this is asked here and not in
        // `isPicture`, and for the two page kinds it misses.
        //
        // `max` rather than a replacement: the caller's factor is a floor, so a
        // page that *does* carry a picture is never shrunk harder than the setting
        // asked for. On a page with no picture, Photo detail is governing a
        // photograph that is not there.
        //
        // **Except when the caller asked for every pixel.** `PhotoDetail.maximum`
        // is a factor of 1, and it promises "photographs keep every pixel" — an
        // instruction, in the sense `Flattener.Mode` already uses the word, where
        // Black & white and Grayscale are instructions and Automatic is the one
        // that works out what the page needs. This signal has two recorded misses,
        // and one of them — a pale line drawing — is a picture it reads as text, so
        // honouring the instruction is what keeps the miss from costing that user
        // resolution they explicitly asked to keep. Found by reviewing this diff:
        // the first version applied the shrink at every setting, so Maximum stored
        // such a page at an eighth of its resolution with no way to override it.
        // **And the pale drawing is asked about again here**, because closing R56 in
        // `isPicture` alone would have moved the harm rather than removed it. That
        // page now reaches the picture path — and this rule, whose signal is ink, was
        // still reading it as all text and storing it at an eighth of its resolution.
        // R50 recorded that miss and correctly judged it harmless *"because this only
        // ever changes resolution"*; it is harmless at 2x and much less so at 8x, and
        // it is the same miss in front of a second decision. CONTRIBUTING 4b: the
        // register's most repeated shape is a fix that closed one instance of a defect
        // and left its twin.
        //
        // Both new terms are behind the short circuit, deliberately. A first version
        // hoisted the threshold out to a `let` and every layered page then paid a
        // full histogram pass over up to 100 megapixels for a value that
        // `PhotoDetail.maximum` never reads — found by the review of this diff.
        let keepEveryPixel = backgroundDownsample <= 1
        func pageIsAllText() -> Bool {
            let pageThreshold = otsuThreshold(of: grey)
            // C26. The bar is substitutable so a tool can price a different one; `nil`
            // means "the shipped bar", not "refuse the page", and every other term of
            // this guard is untouched. See `textPageInkOutsideThresholdOverride`.
            let bar = textPageInkOutsideThresholdOverride ?? textPageInkOutsideThreshold
            guard inkOutsideText(grey, region: region, width: w, height: h,
                                 threshold: pageThreshold) < bar
            else { return false }
            return paleDrawing(pageMarks(grey, width: w, height: h,
                                         threshold: pageThreshold, dpi: dpi),
                               dpi: dpi).extent <= paleDrawingThreshold
        }
        let allText = !keepEveryPixel && pageIsAllText()
        let bgFactor = allText
            ? max(backgroundDownsample, textPageBackgroundDownsample) : backgroundDownsample
        let fgFactor = allText
            ? max(foregroundDownsample, textPageForegroundDownsample) : foregroundDownsample

        // The stencil is the same either way: it comes from the luminance render,
        // so a colour page's text is cut out exactly as a grey one's is.
        var maskPixels = [UInt8](repeating: 255, count: w * h)
        for i in 0..<(w * h) where mask[i] { maskPixels[i] = 0 }
        guard let maskPNG = greyPNG(maskPixels, width: w, height: h) else { return nil }

        let bw: Int, bh: Int, fw: Int, fh: Int
        let bgData: Data, fgData: Data
        if inColour {
            // Falls back to the grey layering rather than failing the page if the
            // colour render does not come back: layering in colour is an
            // improvement on layering, which is itself an improvement on the
            // single JPEG. Nothing here is a requirement.
            guard let rgba = renderRGB(page, box: box, scale: scale,
                                       width: w, height: h, from: .mediaBox) else {
                return mrcLayers(for: page, boxes: boxes, into: directory, stem: stem,
                                 backgroundDownsample: backgroundDownsample,
                                 foregroundDownsample: foregroundDownsample,
                                 inColour: false)
            }
            var background: [UInt8] = [], foreground: [UInt8] = []
            var sizes: (bw: Int, bh: Int, fw: Int, fh: Int) = (0, 0, 0, 0)
            for channel in 0..<3 {
                // One plane at a time, and released before the next is taken, so
                // three channels do not mean three times the peak.
                var plane = [UInt8](repeating: 0, count: w * h)
                for i in 0..<(w * h) { plane[i] = rgba[i * 4 + channel] }
                let filledBG = fillHoles(plane, holes: mask, width: w, height: h, radius: 10)
                let (bgPlane, pbw, pbh) = downsample(filledBG, width: w, height: h,
                                                     by: max(bgFactor, 1))
                let filledFG = fillHoles(plane, holes: inverse, width: w, height: h, radius: 3)
                let (fgPlane, pfw, pfh) = downsample(filledFG, width: w, height: h,
                                                     by: max(fgFactor, 1))
                if channel == 0 {
                    sizes = (pbw, pbh, pfw, pfh)
                    background = [UInt8](repeating: 255, count: pbw * pbh * 4)
                    foreground = [UInt8](repeating: 255, count: pfw * pfh * 4)
                }
                // A channel that came back a different size would interleave
                // garbage into the other two rather than fail, so it is checked
                // instead of assumed.
                guard (pbw, pbh, pfw, pfh) == sizes else { return nil }
                for i in 0..<(pbw * pbh) { background[i * 4 + channel] = bgPlane[i] }
                for i in 0..<(pfw * pfh) { foreground[i * 4 + channel] = fgPlane[i] }
            }
            (bw, bh, fw, fh) = sizes
            guard let bg = jpegRGB(from: background, width: bw, height: bh,
                                   quality: pictureJPEGQuality)?.data,
                  let fg = jpegRGB(from: foreground, width: fw, height: fh,
                                   quality: pictureJPEGQuality)?.data
            else { return nil }
            bgData = bg; fgData = fg
        } else {
            let bgFull = fillHoles(grey, holes: mask, width: w, height: h, radius: 10)
            let (bg, gbw, gbh) = downsample(bgFull, width: w, height: h,
                                            by: max(bgFactor, 1))
            let fgFull = fillHoles(grey, holes: inverse, width: w, height: h, radius: 3)
            let (fg, gfw, gfh) = downsample(fgFull, width: w, height: h,
                                            by: max(fgFactor, 1))
            bw = gbw; bh = gbh; fw = gfw; fh = gfh
            guard let b = jpegData(from: bg, width: bw, height: bh, quality: pictureJPEGQuality),
                  let f = jpegData(from: fg, width: fw, height: fh, quality: pictureJPEGQuality)
            else { return nil }
            bgData = b; fgData = f
        }

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
                         foregroundWidth: fw, foregroundHeight: fh,
                         isColour: inColour)
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
    ///
    /// **The measurement is `drawnLargestImage`, not `largestImage` — C24, closed
    /// 2026-08-17.** The policy above is unchanged; what changed is which number it is
    /// applied to. `largestImage` walks the page's `/Resources`, and 4 of the corpus's
    /// 208 multi-page documents share one dictionary across every page, so a page was
    /// told its resolution by a *neighbour's* plate. C24's structural half fixed the 85
    /// pages that draw nothing at all; this fixes the **45 that draw a different image
    /// than the dictionary holds** — `AI 2027` 38, `Sherman_1986` 5, `Batzell` 2.
    /// Measured over all 16,987 corpus pages, before against after: exactly those 45
    /// change resolution and not one other.
    ///
    /// **`.unreadable` keeps the `/Resources` answer**, which is T14's rule one level up
    /// from the walk that already obeys it: a `Do` whose name would not resolve is
    /// evidence the instrument read nothing, never evidence the page draws nothing.
    /// Dropping such a page to the fallback would refuse a real scan's resolution on the
    /// strength of a failed read. 3 corpus pages, all of `Astin__The Challenge of Open
    /// Admissions`, and all three keep the 302.6 DPI they have today.
    ///
    /// **Not wired here: `pageIsAnImage`**, which asks a different question — is the page
    /// a raster rather than what should it be rebuilt at — and feeds `Model`'s
    /// text-extraction skip marker, `hasDigitalText` and `Tools/classify-source.swift`,
    /// which is D1's corpus gate (R55). Applying its predicate to both columns of the
    /// 16,987-page sweep in `DRAWN-2026-08-17.tsv`, wiring the drawn walk there would flip
    /// exactly **2** pages: `Batzell` p22 (600 px, under the 900 floor) and `AI 2027` p1
    /// (245 px). Both have embedded text, so neither reaches `Model`'s marker branch; the
    /// reason to leave it is that it moves a corpus gate the owner closed on its own
    /// arithmetic, not that it is unaffected.
    static func rebuildDPI(of page: PDFPage) -> Double {
        if let override = rebuildDPIOverride, let answer = override(page) { return answer }
        switch drawnLargestImage(of: page) {
        case .unreadable: return rebuildDPI(from: largestImage(of: page))
        case .noImage: return rebuildDPI(from: nil)
        case let .largest(dpi, pixelWidth):
            return rebuildDPI(from: (dpi: dpi, pixelWidth: pixelWidth))
        }
    }

    /// A substitute resolution, for a tool asking what a page **would** rebuild at.
    ///
    /// `nil` in the app, always — nothing in `Sources/` sets it, and the settings panel
    /// has no control that reaches it. It exists because "what would this page recognise at
    /// some other resolution" is a question the shipped code cannot be asked: `Flattener`
    /// reads nothing from `Prefs`, so the rebuild resolution is always the page's own, and
    /// `Recogniser.render`'s manual "PDF render DPI" governs the *non*-rebuild route only.
    /// Measuring it therefore meant either a tool reproducing `flatten`'s render — the
    /// divergence T15 charges for — or this. C24's second half is what wanted it first, and
    /// the same seam then ran that half's corpus gate; it is not specific to either.
    ///
    /// **One hook rather than a parameter, because there are three consumers.**
    /// `flatten`, `mrcLayers` and `Recogniser.render` each call `rebuildDPI(of:)`
    /// independently, and a page measured at one resolution and layered at another is a
    /// worse instrument than no instrument. Overriding the one function they share is the
    /// only way all three move together; see "a measurement override reaches every page
    /// the rebuild renders" in the suite, which asserts exactly that rather than trusting
    /// it.
    ///
    /// **It cannot cross a process boundary.** Recognition may run in
    /// `visionocr-recognise`, which has its own address space and its own `nil` here, so a
    /// tool that sets this must keep `useHelper` false. `Tools/score-rebuild-dpi.swift`
    /// does, and says so.
    ///
    /// Returning `nil` from the closure means "no opinion about this page", so a sweep can
    /// move one page and leave the rest of the document on the shipped policy.
    nonisolated(unsafe) static var rebuildDPIOverride: ((PDFPage) -> Double?)?

    /// The policy alone, over a measurement someone else took.
    ///
    /// Split out so `Tools/score-drawn-images.swift` can apply the *shipped* policy to
    /// `drawnLargestImage`'s answer instead of carrying a second copy of these three
    /// branches — T15 is what a drifting copy costs, and the whole question C24's open
    /// half asks is what this policy does to a different measurement.
    static func rebuildDPI(from found: (dpi: Double, pixelWidth: Int)?) -> Double {
        guard let found else { return fallbackRebuildDPI }
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

    /// Does this page's content stream invoke **any** XObject?
    ///
    /// `nil` means the question could not be answered — an unreadable page, or a
    /// content stream the scanner returned no operators at all for. A caller must treat
    /// that as "assume it does", because the alternative is deciding a page draws
    /// nothing on the strength of an instrument that measured nothing. T14's rule, in
    /// the one place here where getting it wrong loses detail rather than bytes.
    ///
    /// **This is C24's structural half.** `largestImage` walks the page's `/Resources`,
    /// and 4 of the corpus's 208 multi-page documents share one `/Resources` across
    /// every page — so a page that draws nothing at all is told its resolution by
    /// another page's plate. Asking whether the page draws anything needs no threshold
    /// and no coverage rule, which is what killed the entry's first two repairs: it is
    /// a fact about the content stream.
    ///
    /// Any `Do` counts, including a form's. A scan nested one level down inside a Form
    /// XObject — which scanner drivers routinely produce, and which broke the entry's
    /// second repair — still reaches this as the `Do` that invokes the form.
    static func drawsAnyXObject(_ page: PDFPage) -> Bool? {
        guard let cgPage = page.pageRef else { return nil }
        final class Count { var draws = 0; var operators = 0 }
        let seen = Count()
        guard let table = CGPDFOperatorTableCreate() else { return nil }
        // Two callbacks: `Do` counts what we are after, and `q` counts *anything at
        // all*, so a stream the scanner could not read is distinguishable from a page
        // that genuinely draws nothing. Every real content stream has a `q` in it; a
        // page with neither is one this cannot speak for.
        CGPDFOperatorTableSetCallback(table, "Do") { _, info in
            guard let info else { return }
            Unmanaged<Count>.fromOpaque(info).takeUnretainedValue().draws += 1
        }
        for op in ["q", "Q", "cm", "BT", "re", "gs"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in
                guard let info else { return }
                Unmanaged<Count>.fromOpaque(info).takeUnretainedValue().operators += 1
            }
        }
        let stream = CGPDFContentStreamCreateWithPage(cgPage)
        let scanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(seen).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)
        CGPDFOperatorTableRelease(table)
        if seen.draws > 0 { return true }
        return seen.operators > 0 ? false : nil
    }

    /// The largest embedded image's implied resolution *and* its pixel width.
    /// `rebuildDPI` needs both to tell a coarse scan from a logo.
    ///
    /// **A page that draws no XObject has no image on it, whatever its `/Resources`
    /// says it may reach** — C24. Refused here rather than in `rebuildDPI` because it
    /// is a correction to the *measurement*: this function's own doc calls itself "the
    /// largest embedded image's implied resolution", and on those pages there is no
    /// embedded image. `nativeDPI` reads better for it too, and the three tools that
    /// refuse a row when production and an extracted copy disagree stop refusing on
    /// the pages where the disagreement was production's fault.
    static func largestImage(of page: PDFPage) -> (dpi: Double, pixelWidth: Int)? {
        guard drawsAnyXObject(page) != false else { return nil }
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

    /// What `drawnLargestImage` found, with "could not tell" kept apart from "nothing".
    enum DrawnImage: Equatable {
        /// The question could not be answered — an unreadable page, a content stream that
        /// yielded no operators, a `Do` whose operand name would not pop, or a name that
        /// resolves to nothing. A caller must fall back to the `/Resources` answer rather
        /// than conclude the page draws nothing: `drawsAnyXObject`'s rule and T14's, in
        /// the one place here where believing an instrument that measured nothing costs
        /// detail rather than bytes.
        case unreadable
        /// The page draws no image. It may still draw forms, rules and text.
        case noImage
        case largest(dpi: Double, pixelWidth: Int)
    }

    /// The largest image the page actually **draws**, found by resolving every `Do` the
    /// content stream issues rather than by walking `/Resources`.
    ///
    /// **This was C24's open half; it is what `rebuildDPI` reads.** `largestImage` answers a
    /// question about the resource dictionary, and 4 of the corpus's 208 multi-page documents
    /// share one dictionary across every page. `drawsAnyXObject` closed the degenerate case —
    /// a page that invokes nothing at all — and **45 corpus pages invoked a *different* image
    /// than the shared dictionary holds**, so they took a neighbour's plate resolution.
    /// Measured with this function: **39 draw a smaller image and 6 draw a wider one**, the
    /// six being pages of `AI 2027`. "Smaller" was the entry's word for all 45 and is wrong
    /// for those six — both walks pick the largest image by *area* and then report its
    /// *width*, so a subset's winner can be the wider of two.
    ///
    /// **Wired into `rebuildDPI(of:)` on 2026-08-17, and the reason it was not has been
    /// answered twice.** Restricting the walk to the invoked names is structural: it needs no
    /// coverage rule and no threshold, which is what killed the entry's second repair. What
    /// this comment then said it needed was a constant recalibrated —
    /// `minimumScanPixelWidth` separated 47 logos of 16–96 px from 37 page-sized scans of
    /// 1936–2592 px measured against each document's *maximum*, and the entry's first repair
    /// sent `Batzell` p22 from 369.6 DPI to **70.6** because that page's own figure is 600 px
    /// wide. This comment called that "C9 again", **which was reasoned and is measured
    /// false** (C24, 2026-08-17): p22 at 70.6 DPI retains 92.8% of its own 291 words against
    /// 94.2% at 369.6 and 93.8% at the 300 fallback, for 87% fewer published bytes, and the
    /// other two pages the constant faces are right as well. C9 was a page rebuilt as
    /// 16 x 23 px; this is 600 x 776.
    ///
    /// **Then the corpus gate ran, over 12 of the 45 pages the wiring moves.** Retention
    /// against each page's own embedded text is flat to slightly up — `AI 2027` p16 gains 11
    /// words of 386 and p47 gains 13 of 446, `Batzell`'s two lose 4 each — while published
    /// bytes fall 25% on `AI 2027`'s five, 81% on `Batzell`'s two and 3% on `Sherman_1986`'s
    /// five. `Tools/score-rebuild-dpi.swift` took those figures and
    /// `REBUILD-DPI-WIRING-2026-08-17.tsv` is the run; `Tools/score-drawn-images.swift` is
    /// the per-page population and the before/after over all 16,987.
    ///
    /// Forms are followed by scanning their own content streams, which is the only way to
    /// learn what a form draws. C24's second repair died on that shape: `Lyons oral
    /// history` puts its scan one level down inside a form on 114 of 114 pages, and
    /// scanner drivers routinely produce it.
    static func drawnLargestImage(of page: PDFPage) -> DrawnImage {
        // The shipped guard first, unchanged, so this cannot disagree with it about
        // whether the page draws anything — and so the two mutants protecting it still
        // protect this.
        switch drawsAnyXObject(page) {
        case nil: return .unreadable
        case false: return .noImage
        default: break
        }
        guard let cgPage = page.pageRef else { return .unreadable }

        /// One form stream scanned in one resource scope. **Both halves are load-bearing**,
        /// and the stream alone is not enough: a form with no `/Resources` of its own
        /// resolves its names against whatever invoked it, so the same stream reached from
        /// two scopes is two different measurements and must be scanned twice. Keying on
        /// the stream alone silently kept the first answer for both.
        struct Visit: Hashable {
            let stream: UnsafeRawPointer
            let scope: UnsafeRawPointer
        }
        final class State {
            var width = 0, height = 0
            var unreadable = false
            var depth = 0
            /// The shallowest depth each (form stream, scope) pair has been entered at.
            /// R25's memo for R25's *shape* — the depth cap bounds recursion and not
            /// breadth, so one stream reachable by many paths is otherwise re-scanned once
            /// per path at every level, N + N² + N³ + N⁴ where N is 1 walk. R25's own 5.09 s
            /// figure belongs to `largestImage` and its dictionary-keyed memo; this is the
            /// same blow-up over streams, not that measurement.
            var enteredAt: [Visit: Int] = [:]
            var table: CGPDFOperatorTableRef?
            /// The resource scope in effect: the page's to begin with, then each form's as
            /// it is entered, restored on the way out.
            var resources: CGPDFDictionaryRef?
        }
        let state = State()
        if let dict = cgPage.dictionary {
            var resources: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(dict, "Resources", &resources) {
                state.resources = resources
            }
        }
        guard let table = CGPDFOperatorTableCreate() else { return .unreadable }
        state.table = table

        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            guard let info else { return }
            let s = Unmanaged<State>.fromOpaque(info).takeUnretainedValue()
            var name: UnsafePointer<Int8>?
            let cs = CGPDFScannerGetContentStream(scanner)
            guard CGPDFScannerPopName(scanner, &name), let name,
                  let object = CGPDFContentStreamGetResource(cs, "XObject", name) else {
                s.unreadable = true
                return
            }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let streamDict = CGPDFStreamGetDictionary(stream) else {
                s.unreadable = true
                return
            }
            var subtype: UnsafePointer<Int8>?
            guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtype), let subtype else {
                s.unreadable = true
                return
            }
            switch String(cString: subtype) {
            case "Image":
                var w: CGPDFInteger = 0, h: CGPDFInteger = 0
                // The same guards `largestImage` applies, for the same reason: /Width and
                // /Height are whatever the file declares and nothing cross-checks them
                // against a stream that can be three bytes long (R24, A7.1).
                guard CGPDFDictionaryGetInteger(streamDict, "Width", &w),
                      CGPDFDictionaryGetInteger(streamDict, "Height", &h),
                      w > 0, h > 0,
                      w <= CGPDFInteger(Flattener.maximumDeclaredImageSide),
                      h <= CGPDFInteger(Flattener.maximumDeclaredImageSide)
                else { return }
                if Int(w) * Int(h) > s.width * s.height {
                    s.width = Int(w)
                    s.height = Int(h)
                }
            case "Form":
                // **`< 3`, not `< 4`, so this reaches exactly as far as `largestImage`.**
                // That walk starts at the page's dictionary at depth 0 and refuses depth 4,
                // so it sees images listed in a form three levels down and no further. A
                // form entered here at `s.depth == 3` would be a fourth level, and an image
                // it draws would show up as a drawn-versus-dictionary difference caused by
                // the two caps disagreeing rather than by what the page draws — a confound
                // in the one instrument built to isolate that variable. Measured over the
                // corpus: `< 4` and `< 3` produce byte-identical sweeps, so nothing here
                // nests that deep and the symmetry costs nothing. If this is ever wired
                // into `rebuildDPI`, the cap becomes a question about pages rather than
                // about agreement, and wants re-measuring then.
                guard s.depth < 3, let table = s.table else { return }
                // A form need not carry `/Resources`; PDF then resolves its names against
                // the scope that **invoked** it, which is not the same thing as the page.
                // Skipping resource-less forms would go blind on exactly the nesting that
                // scanner drivers produce, and that is how the entry's second repair died.
                //
                // **The invoker's scope, not the page's**, and the review of this diff
                // caught the page's being used. On the ninth page of `shared-resources.pdf`
                // — a bare form nested inside a form that carries its own `/Resources`,
                // where the form and the page each define `/Ix` — resolving against the page
                // answered its 3000 px plate instead of the 1500 px image the form draws.
                //
                // *And the obvious way to get this right does not work.* Passing the form's
                // own stream dictionary and letting `CGPDFContentStreamCreateWithStream`'s
                // `parent` argument inherit — which an earlier comment here asserted it
                // would — measured `.unreadable` on **both** that page and the fifth,
                // because `CGPDFContentStreamGetResource` does not search the parent chain
                // for a name absent from the dictionary it was handed. Verified by running
                // it, which is the only reason this reads the way it does.
                var formResources: CGPDFDictionaryRef?
                _ = CGPDFDictionaryGetDictionary(streamDict, "Resources", &formResources)
                let inherited = s.resources
                let resources = formResources ?? inherited ?? streamDict
                // The memo, after the scope is known rather than before: what this scan will
                // answer is a function of the pair, so the pair is what may be skipped.
                let visit = Visit(stream: unsafeBitCast(stream, to: UnsafeRawPointer.self),
                                  scope: unsafeBitCast(resources, to: UnsafeRawPointer.self))
                if let seen = s.enteredAt[visit], seen <= s.depth { return }
                s.enteredAt[visit] = s.depth
                let nested = CGPDFContentStreamCreateWithStream(stream, resources, cs)
                let nestedScanner = CGPDFScannerCreate(nested, table, info)
                s.depth += 1
                s.resources = resources
                CGPDFScannerScan(nestedScanner)
                s.resources = inherited
                s.depth -= 1
                CGPDFScannerRelease(nestedScanner)
                CGPDFContentStreamRelease(nested)
            default:
                // A `/PS` XObject, or a subtype this does not know. Resolvable, and not an
                // image: it contributes nothing and hides nothing.
                break
            }
        }

        let stream = CGPDFContentStreamCreateWithPage(cgPage)
        let scanner = CGPDFScannerCreate(stream, table,
                                        Unmanaged.passUnretained(state).toOpaque())
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(stream)
        CGPDFOperatorTableRelease(table)

        if state.unreadable { return .unreadable }
        guard state.width > 0 else { return .noImage }
        // Media box, to match `largestImage` and the area flatten renders — see fullBox.
        let widthPt = page.bounds(for: .mediaBox).width
        guard widthPt > 0 else { return .unreadable }
        return .largest(dpi: Double(state.width) / (Double(widthPt) / 72.0),
                        pixelWidth: state.width)
    }
}
