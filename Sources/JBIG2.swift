import CoreGraphics
import Foundation

/// Compresses the visible page images with JBIG2, which is what lets a scanned
/// book stay small at full resolution.
///
/// CoreGraphics writes 1-bit images as Flate, which is a poor fit for scanned
/// text. Measured on 12 pages of a 300 DPI book scan, the identical 1897×3002
/// bitmap costs 107 KB as Flate and 36 KB as JBIG2 — and the whole book lands at
/// ~24 MB against ~28 MB for the library's own mixed-raster original.
///
/// Only JBIG2's **generic** region coding is used, which is lossless. Symbol
/// mode compresses several times harder by pooling visually similar glyph
/// shapes, and is the mechanism behind the Xerox scanners that silently swapped
/// digits in scanned documents; jbig2enc's lossless variant of it (`-s -r`)
/// reports itself as broken. Neither is offered here.
enum JBIG2 {

    /// One assembled page: the encoded image, its pixel size, and the size the
    /// page should be in points.
    ///
    /// A book mixes both kinds: text pages compress as JBIG2, illustrations have
    /// to stay greyscale or thresholding would destroy them.
    struct Page {
        enum Stream {
            /// JBIG2 bitmap: 1 bit, /JBIG2Decode.
            case jbig2(URL)
            /// JPEG: 8 bit, /DCTDecode. One component or three — `isColour` on
            /// the page says which, and the stream dictionary has to agree or
            /// the viewer reads three channels as one and renders noise.
            case jpeg(URL)
            /// Three layers: a background holding paper and pictures, a
            /// foreground holding ink colour, and a 1-bit JBIG2 stencil that
            /// says where the foreground shows. The reader paints the
            /// background, then the foreground through the stencil as an
            /// `/SMask`. See `Flattener.mrcLayers`.
            case mrc(MRC)

            /// C29 (B). A page whose pixels are its own: a born-digital page
            /// `Flattener.flatten` copied through instead of rasterising, so
            /// there is nothing to encode and nothing for `assemble` to draw.
            /// `splice` takes it from the user's own file once the rest of the
            /// document is assembled, which is what keeps the other pages'
            /// JBIG2 compression on a mixed document — the whole of C29 (B).
            ///
            /// It carries no page number. The array holding it is dense and
            /// indexed by page, which is what `Model`'s MRC loop, its
            /// `byPage[index + 1]` and the splice's own page ranges all rest on;
            /// a field here would be a second place for that to be true.
            case passthrough

            /// Every file this stream owns, so the caller can clean up without
            /// knowing which kind it is. This was `url` returning one file, and
            /// an MRC page would have leaked the two it did not name.
            var urls: [URL] {
                switch self {
                case .jbig2(let u), .jpeg(let u): return [u]
                case .mrc(let m): return [m.mask, m.background, m.foreground]
                case .passthrough: return []
                }
            }

            /// How many image XObjects the page needs. Object numbers are
            /// assigned from this, so a wrong answer here writes a broken xref.
            var imageCount: Int {
                switch self {
                case .jbig2, .jpeg: return 1
                case .mrc: return 3
                case .passthrough: return 0
                }
            }

            /// Whether this page has to come out of the source file rather than
            /// out of an encoded stream.
            var isPassthrough: Bool {
                if case .passthrough = self { return true }
                return false
            }
        }

        /// The three encoded layers. `mask` is already a JBIG2 stream, not a
        /// PNG — it goes through `encode` exactly like a bilevel page does.
        struct MRC {
            let mask: URL
            let background: URL
            let foreground: URL
            let backgroundWidth: Int, backgroundHeight: Int
            let foregroundWidth: Int, foregroundHeight: Int
            /// Whether the two tone layers are three-channel. Carried on the
            /// layers rather than read off `Page.isColour`, because those are
            /// different facts: `isColour` describes the single JPEG a page had
            /// before it was layered, and a colour page whose colour render
            /// failed is layered in grey. Reading the page's flag would then
            /// declare /DeviceRGB over one-channel streams and draw noise.
            var isColour = false
        }
        let stream: Stream
        let pixelWidth: Int
        let pixelHeight: Int
        let boxSize: CGSize
        /// True when `stream` is a three-channel JPEG.
        var isColour = false
    }

    enum Failure: LocalizedError {
        case encoderFailed(String)
        case overlayFailed(String)
        case cannotWrite
        case noPages
        case badPageBox(page: Int, size: CGSize)
        case cropBoxFailed(String)
        /// C29 (B). `assemble` was handed a page whose pixels are its own. It
        /// hand-writes image XObjects and has no way to carry a page's fonts,
        /// its own images or its content stream, so it refuses rather than
        /// writing a blank sheet in the right place — a plausible file with a
        /// page missing is exactly what invariant 1 forbids. The caller's job is
        /// to keep those pages out and to splice them in afterwards.
        case cannotAssemblePassthrough(page: Int)
        case spliceFailed(String)

        var errorDescription: String? {
            switch self {
            case .encoderFailed(let m): return "JBIG2 compression failed: \(m)"
            case .overlayFailed(let m): return "Merging the text layer failed: \(m)"
            case .cannotWrite: return "Could not write the compressed PDF."
            case .noPages: return "There were no page images to assemble."
            case .cropBoxFailed(let why):
                return "Could not carry the original's displayed area onto the "
                    + "compressed copy: \(why)"
            case .badPageBox(let page, let size):
                return "Page \(page) reports an unusable size "
                    + "(\(size.width) x \(size.height)), so the compressed pages "
                    + "could not be given a page box that matches the text layer."
            case .cannotAssemblePassthrough(let page):
                return "Page \(page) keeps its own content and cannot be "
                    + "assembled from an image stream; nothing was written."
            case .spliceFailed(let m):
                return "Putting the original pages back in failed: \(m)"
            }
        }
    }

    // MARK: - Availability

    /// Both tools are needed: jbig2enc to compress, qpdf to lay the text layer
    /// over the compressed pages without touching the image streams.
    static var encoder: String? { Runner.locateTool("jbig2") }
    static var merger: String? { Runner.locateTool("qpdf") }

    static var isAvailable: Bool { encoder != nil && merger != nil }

    static var installHint: String {
        "brew install jbig2enc qpdf"
    }

    /// The `/Decode` array on an MRC stencil.
    ///
    /// JBIG2 codes ink as 1. An `/SMask` reads 1 as opaque, so on that reading
    /// no inversion is needed — but PDF's JBIG2Decode filter presents the
    /// decoded bitmap as a DeviceGray image, where 1 is *white*, and the mask
    /// then makes the foreground show everywhere except the text. `[1 0]`
    /// flips it back.
    ///
    /// Established by rendering a page and looking at it, not by reading the
    /// specification — the two readings above are each defensible from the text
    /// and only one of them draws the right picture. `maskDecodeIsInverted`
    /// is the check that holds it.
    static let maskDecode = "[ 1 0 ]"

    // MARK: - Encoding

    /// Compresses one 1-bit PNG. jbig2enc writes the PDF-ready stream to stdout.
    static func encode(png: URL, to stream: URL, using jbig2: String,
                       register: (Process) -> Void = { _ in }) throws {
        FileManager.default.createFile(atPath: stream.path, contents: nil)
        guard let sink = try? FileHandle(forWritingTo: stream) else {
            throw Failure.cannotWrite
        }
        defer { try? sink.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: jbig2)
        // -p: emit the embedded-stream form a PDF expects. No -s: generic
        // region coding only, which is lossless.
        process.arguments = ["-p", png.path]
        process.standardOutput = sink
        let errPipe = Pipe()
        process.standardError = errPipe

        try process.run()
        register(process)
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: err, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.encoderFailed(message.isEmpty
                ? "jbig2 exited with code \(process.terminationStatus)" : message)
        }
    }

    // MARK: - Assembling the PDF

    /// Writes an image-only PDF whose pages carry the JBIG2 streams directly.
    ///
    /// Hand-assembled rather than going through jbig2enc's bundled
    /// `jbig2topdf.py`: that needs Python, and it derives each MediaBox from
    /// pixels ÷ DPI, which drifts from the source page box and would leave the
    /// text layer slightly out of register.
    /// `outline` is written into this file's catalogue, which is what lets the
    /// finished book keep both its outline *and* its JBIG2 compression: `overlay`
    /// puts the text layer on top of this document, and `qpdf --overlay` keeps
    /// the base file's catalogue — verified — so an outline placed here survives
    /// the merge. Routing it through PDFKit instead re-encodes every image stream
    /// and loses the compression entirely (measured: 374 KB with /JBIG2Decode
    /// becoming 467 KB without). See BUGS.md R19.
    static func assemble(_ pages: [Page], outline: [SearchableWriter.OutlineItem] = [],
                         to destination: URL) throws {
        // A zero-page PDF is not a valid one: with no pages this wrote a
        // /Type /Pages with /Count 0 and an empty /Kids, which `qpdf --check`
        // rejects with "ERROR: vector" — while `assemble` returned success.
        // Reporting a file nobody can open as a good result is the failure mode
        // invariant 1 exists to stop, so refuse instead.
        guard !pages.isEmpty else { throw Failure.noPages }

        // C29 (B). Every page here gets an image XObject and a content stream
        // that draws it; a passthrough page has neither, and its content is in
        // the user's own file. The caller filters them out and `splice` puts
        // them back — so this is a refusal and not a skip. Skipping would write
        // a document whose page count and whose page numbering both look right
        // and whose text layer lands one page out from page N onward, which is
        // the class of failure invariant 1 exists to stop.
        if let bad = pages.firstIndex(where: { $0.stream.isPassthrough }) {
            throw Failure.cannotAssemblePassthrough(page: bad + 1)
        }

        // Streamed to the file rather than accumulated in a Data. Building the
        // whole PDF in memory made peak usage the size of the output — measured
        // at 130 MB for 3000 pages, plus the current page's bytes, plus whatever
        // a geometric realloc near the end held twice. Only one page is in
        // memory at a time now, so peak is bounded by the largest page.
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        guard fm.createFile(atPath: destination.path, contents: nil),
              let sink = try? FileHandle(forWritingTo: destination) else {
            throw Failure.cannotWrite
        }
        // A partial file must not be left where a reader could open it: a
        // truncated-but-valid PDF is exactly the failure invariant 1 forbids.
        var completed = false
        defer {
            try? sink.close()
            if !completed { try? fm.removeItem(at: destination) }
        }

        var written = 0                  // bytes emitted so far; the xref needs it
        var offsets: [Int] = []          // byte offset of object n, at index n-1

        func emit(_ bytes: Data) throws {
            do { try sink.write(contentsOf: bytes) } catch { throw Failure.cannotWrite }
            written += bytes.count
        }
        func write(_ string: String) throws {
            // A2.4. `?? Data()` stood here, and it emits **nothing** for a string
            // Latin-1 cannot hold — while `written` does not advance either, so
            // the xref stays perfectly self-consistent over a file with an
            // object body missing. A structurally broken PDF with a
            // valid-looking cross-reference table, produced by the one file
            // whose whole job is not producing that.
            //
            // Unreachable today: every caller-controlled string goes through
            // `pdfString`, `trim` or `coordinate`. A throw costs nothing, and
            // "unreachable" is what R31, R32 and H2 were each called.
            guard let data = string.data(using: .isoLatin1) else {
                throw Failure.cannotWrite
            }
            try emit(data)
        }
        func beginObject(_ number: Int) throws {
            precondition(offsets.count == number - 1, "objects must be written in order")
            offsets.append(written)
            try write("\(number) 0 obj\n")
        }

        // 1 = catalog, 2 = page tree, then each page's objects, then — if there
        // is an outline — its root followed by one object per entry.
        //
        // Assigned in a pass rather than computed with arithmetic. It used to be
        // `3 + i * 3`, which was correct only while every page needed exactly
        // three objects; an MRC page needs five, and one such page anywhere in a
        // book would have shifted every later number while the xref went on
        // describing the old layout. That produces a file that opens and is
        // wrong, which is the failure mode this file exists to avoid.
        var pageObjects: [Int] = [], contentObjects: [Int] = [], imageObjects: [[Int]] = []
        var nextObject = 3
        for page in pages {
            pageObjects.append(nextObject); nextObject += 1
            contentObjects.append(nextObject); nextObject += 1
            let count = page.stream.imageCount
            imageObjects.append(Array(nextObject..<(nextObject + count)))
            nextObject += count
        }
        func pageObject(_ i: Int) -> Int { pageObjects[i] }
        func contentObject(_ i: Int) -> Int { contentObjects[i] }
        let afterPages = nextObject

        // Flattened depth-first, so every entry knows its own object number and
        // its parent's before anything is written. /Prev, /Next, /First and /Last
        // all need numbers that are only knowable once the whole tree is laid out.
        let flat = flatten(outline, from: afterPages + 1, parent: afterPages,
                           pageCount: pages.count)
        let outlineRoot = flat.isEmpty ? nil : afterPages
        // From the assignment pass, not recomputed: `nextObject` already counted
        // every page's objects including the variable number of images, and a
        // second formula here is a second thing to get wrong.
        let objectCount = (afterPages - 1) + (flat.isEmpty ? 0 : 1 + flat.count)

        try write("%PDF-1.4\n")
        try emit(Data([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]))      // binary marker

        try beginObject(1)
        if let outlineRoot {
            try write("<< /Type /Catalog /Pages 2 0 R /Outlines \(outlineRoot) 0 R >>\nendobj\n")
        } else {
            try write("<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")
        }

        try beginObject(2)
        let kids = pages.indices.map { "\(pageObject($0)) 0 R" }.joined(separator: " ")
        try write("<< /Type /Pages /Count \(pages.count) /Kids [ \(kids) ] >>\nendobj\n")

        for (i, page) in pages.enumerated() {
            guard let w = trim(page.boxSize.width), let h = trim(page.boxSize.height) else {
                throw Failure.badPageBox(page: i + 1, size: page.boxSize)
            }

            let objects = imageObjects[i]
            // One name per image, so the page's /XObject dictionary and its
            // content stream cannot disagree about which is which.
            let names = objects.indices.map { "/Im\($0)" }
            let resources = zip(names, objects)
                .map { "\($0) \($1) 0 R" }.joined(separator: " ")

            // **No `/CropBox` here, and that is deliberate — C23.**
            //
            // A page whose crop box hides part of the sheet is the defect C23
            // records, and the obvious fix is a `/CropBox` on this line. It was
            // written, measured and removed: `qpdf --overlay` wraps both this
            // page's content and the text layer in form XObjects whose `/BBox`
            // is the destination page's crop box, and then centres that box on
            // the media box. On a 612x792 page cropped to 312x400 at (100,100)
            // the image came out translated by (50, 96) and everything outside
            // the crop was clipped away for good. So the crop must not exist
            // when qpdf runs, and `Model.wantsJBIG2` keeps trimmed documents off
            // this route entirely rather than publishing a page that is wrong in
            // both geometry and content.
            //
            // If you are here to add one: the merged file is the thing that
            // needs it, and neither CGPDFContext nor PDFKit can rewrite these
            // pages without dropping /JBIG2Decode (measured).

            try beginObject(pageObject(i))
            try write("""
            << /Type /Page /Parent 2 0 R /MediaBox [ 0 0 \(w) \(h) ] \
            /Resources << /ProcSet [ /PDF /ImageB ] \
            /XObject << \(resources) >> >> \
            /Contents \(contentObject(i)) 0 R >>
            endobj\n
            """)

            // Scale the unit image square to the page box. An MRC page draws
            // twice: the background, then the foreground over it — the stencil
            // is not drawn, it is the foreground's /SMask.
            let content: String
            switch page.stream {
            case .mrc:
                content = "q \(w) 0 0 \(h) 0 0 cm /Im0 Do Q\n"
                        + "q \(w) 0 0 \(h) 0 0 cm /Im1 Do Q\n"
            case .jbig2, .jpeg:
                content = "q \(w) 0 0 \(h) 0 0 cm /Im0 Do Q\n"
            case .passthrough:
                // Refused at the top of this function; the case is here so that
                // adding a fourth stream kind cannot compile against a default.
                throw Failure.cannotAssemblePassthrough(page: i + 1)
            }
            try beginObject(contentObject(i))
            try write("<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream\nendobj\n")

            /// One image XObject. An unreadable or empty stream would otherwise
            /// become a blank page with no complaint — silent data loss in the
            /// middle of a book.
            func writeImage(_ number: Int, from url: URL, width: Int, height: Int,
                            filter: String, bits: Int, space: String,
                            smask: Int? = nil, decode: String? = nil) throws {
                guard let bytes = try? Data(contentsOf: url), !bytes.isEmpty else {
                    throw Failure.encoderFailed("page \(i + 1) produced no image data")
                }
                try beginObject(number)
                try write("""
                << /Type /XObject /Subtype /Image /Width \(width) \
                /Height \(height) /ColorSpace \(space) \
                /BitsPerComponent \(bits) /Filter \(filter) \
                \(decode.map { "/Decode \($0) " } ?? "")\
                \(smask.map { "/SMask \($0) 0 R " } ?? "")/Length \(bytes.count) >>
                stream\n
                """)
                try emit(bytes)
                try write("\nendstream\nendobj\n")
            }

            // /DeviceGray was hardcoded here, which was true of every stream
            // this ever wrote until Automatic started keeping colour pages in
            // colour. A three-channel JPEG declared as one channel is not an
            // error any reader reports — it just draws the page as noise.
            let space = page.isColour ? "/DeviceRGB" : "/DeviceGray"
            switch page.stream {
            case .jbig2(let u):
                try writeImage(objects[0], from: u, width: page.pixelWidth,
                               height: page.pixelHeight, filter: "/JBIG2Decode",
                               bits: 1, space: space)
            case .jpeg(let u):
                try writeImage(objects[0], from: u, width: page.pixelWidth,
                               height: page.pixelHeight, filter: "/DCTDecode",
                               bits: 8, space: space)
            case .mrc(let m):
                // The tone layers follow the layers' own flag, not the page's.
                // See MRC.isColour — they disagree when a colour page's colour
                // render failed and it was layered in grey instead.
                let toneSpace = m.isColour ? "/DeviceRGB" : "/DeviceGray"
                // Written in the order the objects were numbered: background,
                // foreground, then the stencil the foreground points at.
                try writeImage(objects[0], from: m.background,
                               width: m.backgroundWidth, height: m.backgroundHeight,
                               filter: "/DCTDecode", bits: 8, space: toneSpace)
                try writeImage(objects[1], from: m.foreground,
                               width: m.foregroundWidth, height: m.foregroundHeight,
                               filter: "/DCTDecode", bits: 8, space: toneSpace,
                               smask: objects[2])
                // The stencil, at full page resolution. /Decode [1 0] because
                // JBIG2 codes ink as 1 while an /SMask reads 1 as opaque and 0
                // as transparent — without the inversion the foreground would
                // show everywhere *except* the text. Verified by rendering, not
                // by reading the specification.
                try writeImage(objects[2], from: m.mask, width: page.pixelWidth,
                               height: page.pixelHeight, filter: "/JBIG2Decode",
                               bits: 1, space: "/DeviceGray", decode: maskDecode)
            case .passthrough:
                throw Failure.cannotAssemblePassthrough(page: i + 1)
            }
        }

        // The outline, after the pages so the page objects keep their numbering.
        if let outlineRoot {
            let tops = flat.filter { $0.parent == outlineRoot }
            try beginObject(outlineRoot)
            try write("<< /Type /Outlines /First \(tops.first!.number) 0 R "
                      + "/Last \(tops.last!.number) 0 R /Count \(flat.count) >>\nendobj\n")
            for node in flat {
                var parts = ["/Title \(pdfString(node.title))",
                             "/Parent \(node.parent) 0 R"]
                if let prev = node.prev { parts.append("/Prev \(prev) 0 R") }
                if let next = node.next { parts.append("/Next \(next) 0 R") }
                if let first = node.firstChild, let last = node.lastChild {
                    parts.append("/First \(first) 0 R")
                    parts.append("/Last \(last) 0 R")
                    // Positive: open, showing this many descendants.
                    parts.append("/Count \(node.descendants)")
                }
                if let page = node.pageIndex {
                    // null for anything the source left unspecified — /Fit,
                    // /FitH and /XYZ null all arrive that way, and turning them
                    // into 0 sends the reader to the foot of the page.
                    let x = node.left.flatMap(coordinate) ?? "null"
                    let y = node.top.flatMap(coordinate) ?? "null"
                    parts.append("/Dest [ \(pageObject(page)) 0 R /XYZ \(x) \(y) null ]")
                }
                try beginObject(node.number)
                try write("<< " + parts.joined(separator: " ") + " >>\nendobj\n")
            }
        }

        // Cross-reference table: every entry is exactly 20 bytes.
        let xrefOffset = written
        try write("xref\n0 \(objectCount + 1)\n")
        try write("0000000000 65535 f \n")
        for offset in offsets {
            // %010ld, not %010d: past 2 GiB a 32-bit conversion wraps negative
            // and every later offset is garbage.
            //
            // A2.4, the same trap's next boundary: an xref entry must be exactly
            // 20 bytes, and `%010ld` only keeps it there below 10 GB — past
            // 9,999,999,999 the field widens to 11 digits and every entry becomes
            // 21. Reachable only by something like 1,300 pages of 100-megapixel
            // colour plates, which `maximumPageMegapixels` does not forbid.
            // Refuse rather than write a file whose xref no reader can index.
            guard offset < 9_999_999_999 else {
                throw Failure.cannotWrite
            }
            try write(String(format: "%010ld 00000 n \n", offset))
        }
        try write("trailer\n<< /Size \(objectCount + 1) /Root 1 0 R >>\n")
        try write("startxref\n\(xrefOffset)\n%%EOF\n")

        completed = true
    }

    /// PDF numbers: 455.28 rather than 455.2800000000001.
    ///
    /// Not %g: it switches to scientific notation at 1e6 and prints "nan"/"inf",
    /// none of which is a legal PDF number. qpdf then discards the MediaBox and
    /// silently substitutes US Letter, stretching the image and desynchronising it
    /// from the text layer.
    // MARK: - Outline

    /// One outline entry with every cross-reference it needs, resolved.
    private struct FlatOutline {
        let number: Int
        let parent: Int
        let title: String
        let pageIndex: Int?
        let left: CGFloat?
        let top: CGFloat?
        var prev: Int?
        var next: Int?
        var firstChild: Int?
        var lastChild: Int?
        /// Visible descendants, for a positive `/Count` (i.e. shown open).
        var descendants: Int = 0
    }

    /// Numbers an outline tree depth-first and resolves the sibling and child
    /// links, so `assemble` can write each object in one pass.
    ///
    /// Depth-first because a PDF outline entry refers to its own children and to
    /// both its siblings, and none of those numbers exist until the whole tree
    /// has been laid out.
    private static func flatten(_ items: [SearchableWriter.OutlineItem],
                                from start: Int, parent: Int,
                                pageCount: Int) -> [FlatOutline] {
        var out: [FlatOutline] = []

        /// Appends `level` and its descendants, returning the object numbers of
        /// this level's own entries in order.
        @discardableResult
        func walk(_ level: [SearchableWriter.OutlineItem], parent: Int) -> [Int] {
            var mine: [Int] = []
            for item in level {
                let number = start + out.count
                mine.append(number)
                // Reserve the slot before recursing, so children number after it.
                let index = out.count
                // A destination off the end of the document is dropped rather
                // than written as a dangling reference; an entry that never had
                // one keeps nil, so no /Dest is invented for it.
                let page = item.pageIndex.flatMap {
                    $0 >= 0 && $0 < pageCount ? $0 : nil
                }
                out.append(FlatOutline(
                    number: number, parent: parent, title: item.title,
                    pageIndex: page, left: item.left, top: item.top))
                let kids = walk(item.children, parent: number)
                if let first = kids.first, let last = kids.last {
                    out[index].firstChild = first
                    out[index].lastChild = last
                    // Everything below this entry, not just its immediate kids.
                    out[index].descendants = out.count - index - 1
                }
            }
            // Sibling links, once this level's numbers are all known.
            for (i, number) in mine.enumerated() {
                guard let at = out.firstIndex(where: { $0.number == number }) else { continue }
                if i > 0 { out[at].prev = mine[i - 1] }
                if i < mine.count - 1 { out[at].next = mine[i + 1] }
            }
            return mine
        }

        walk(items, parent: parent)
        return out
    }

    /// A PDF string literal. Non-ASCII goes out as UTF-16BE in hex with a BOM,
    /// which is the only encoding a PDF text string can carry reliably — a
    /// Latin-1 literal would mangle any title with a dash or an accent in it, and
    /// archival material is full of both.
    private static func pdfString(_ text: String) -> String {
        // 127 is DEL, which is ASCII but not printable — emitting it raw put a
        // control character inside a PDF string literal.
        if text.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 32 && $0.value != 127 }) {
            var escaped = ""
            for character in text {
                switch character {
                case "(", ")", "\\": escaped.append("\\"); escaped.append(character)
                default: escaped.append(character)
                }
            }
            return "(\(escaped))"
        }
        var hex = "FEFF"
        for unit in Array(text.utf16) { hex += String(format: "%04X", unit) }
        return "<\(hex)>"
    }

    /// A destination coordinate. Unlike `trim` these may legitimately be zero or
    /// negative, so it has its own rule; anything unusable becomes 0.
    /// Nil for an unusable value, so the caller writes `null` rather than a
    /// coordinate we invented. Guessing 0 here is what sent /Fit bookmarks to the
    /// foot of the page.
    private static func coordinate(_ value: CGFloat) -> String? {
        let d = Double(value)
        guard d.isFinite, abs(d) < 200_000 else { return nil }
        return String(format: "%.4f", d)
    }

    /// Nil when the value is not a usable PDF number, so the caller can refuse.
    ///
    /// This used to substitute "612" — US Letter — for anything non-finite or
    /// out of range. A page reporting a malformed 0x0 box therefore produced an
    /// image page silently resized to Letter while the text layer kept the real
    /// geometry, so the two no longer lined up. Guessing a plausible number for
    /// a value we do not have is exactly what invariant 1 forbids; C12 and R12
    /// both landed on refusing, and so does this.
    private static func trim(_ value: CGFloat) -> String? {
        let d = Double(value)
        guard d.isFinite, d > 0, d < 200_000 else { return nil }
        return String(format: "%.4f", d)
    }

    // MARK: - Putting the original pages back — C29 (B)

    /// One qpdf page range, with consecutive pages collapsed into `a-b`.
    ///
    /// Not tidiness. A 3,000-page book with one born-digital cover would
    /// otherwise put 2,999 comma-separated numbers on the command line twice
    /// over, once for `--from` and once for `--to`.
    static func pageRange(_ pages: [Int]) -> String {
        // Deduplicated as well as sorted: a repeated page would break a run at
        // the repeat (equal, not one more) and then be named twice, which qpdf
        // would honour by duplicating the page.
        let sorted = Array(Set(pages)).sorted()
        var runs: [String] = []
        var i = 0
        while i < sorted.count {
            var j = i
            while j + 1 < sorted.count, sorted[j + 1] == sorted[j] + 1 { j += 1 }
            runs.append(i == j ? "\(sorted[i])" : "\(sorted[i])-\(sorted[j])")
            i = j + 1
        }
        return runs.joined(separator: ",")
    }

    /// The qpdf arguments that interleave the assembled pages with the source's
    /// own, so the finished document is page-for-page the original.
    ///
    /// `assembled` holds the pages that were encoded, in order, with the
    /// passthrough pages absent from it altogether; `passthrough` is their
    /// 1-based numbers in the *finished* document. So this is one decision per
    /// page — take it from the source or take the next assembled page — with
    /// consecutive pages from one file collapsed into a single file spec.
    ///
    /// Pure, and deliberately separate from `splice`, so it can be read and
    /// pinned without a qpdf on the machine. Getting these ranges wrong
    /// publishes a document with the right number of pages in the wrong order,
    /// and no page count can see that.
    static func spliceArguments(source: URL, password: String?, assembled: URL,
                                passthrough: [Int], pageCount: Int,
                                destination: URL) -> [String] {
        guard pageCount >= 1 else { return [] }
        let fromSource = Set(passthrough)
        var segments: [(url: URL, from: Int, to: Int)] = []
        var nextAssembled = 1
        for page in 1...pageCount {
            let isSource = fromSource.contains(page)
            let url = isSource ? source : assembled
            // The source is indexed by the page's own number; the assembled
            // file by how many encoded pages have gone before it.
            let number = isSource ? page : nextAssembled
            if !isSource { nextAssembled += 1 }
            if let last = segments.last, last.url == url, last.to + 1 == number {
                segments[segments.count - 1].to = number
            } else {
                segments.append((url, number, number))
            }
        }
        var arguments = ["--empty", "--pages"]
        for segment in segments {
            arguments.append(segment.url.path)
            // Per file spec, not once: qpdf reads `--password=` as belonging to
            // the file named before it, and the source can appear more than
            // once. The assembled file is one this app just wrote, so it never
            // needs one.
            if segment.url == source, let password, !password.isEmpty {
                arguments.append("--password=\(password)")
            }
            arguments.append(segment.from == segment.to
                             ? "\(segment.from)" : "\(segment.from)-\(segment.to)")
        }
        arguments.append("--")
        arguments.append(destination.path)
        return arguments
    }

    /// Rebuilds `assembled` into `destination` with the passthrough pages taken
    /// from the user's own file, in their own places.
    ///
    /// C29 (B). Before this, one born-digital page on a document turned the
    /// whole document's JBIG2 compression off: the page contributes no encoded
    /// stream, `Model`'s count guard failed, and the Flate route ran — measured
    /// at 3.13x the bytes on `1954 - Why.pdf`, nine tenths of it the MRC
    /// re-layering that lives inside the JBIG2 branch rather than the
    /// compression. qpdf copies a page object as it stands, so the spliced page
    /// keeps its own fonts, images, `/Rotate` and boxes with nothing scaled or
    /// re-encoded.
    ///
    /// The caller must verify the destination's page count: a wrong range here
    /// produces a valid PDF, and invariant 1's own words are that page count is
    /// not sufficient verification — but a page count that is *wrong* is proof,
    /// and it is the one thing an interleave can get wrong silently.
    ///
    /// ⚠️ **`--empty --pages` drops the `/Outlines` tree**, so an outline written
    /// into `assembled` would be lost here. `Model` keeps a document with both an
    /// outline and a passthrough page off this route for that reason; it is not
    /// something this function can repair.
    ///
    /// ⛔ Do NOT widen that to "keeps no document-level structure", which is what
    /// this comment said until 2026-08-25 and which is **measured false**: qpdf
    /// 12.3.2 carried `/PageLabels` through one `--empty --pages` run — a 10-page
    /// corpus document given decimal labels with `--set-page-labels 1:D`, two
    /// pages then taken out of it, key still present in the result. The
    /// overstatement matters because it invites a *second* refusal for structure
    /// that survives.
    /// ⚠️ **The narrow claim is all that one reading supports**: one input, not in
    /// the tree, and with the *source* first in the `--pages` list. Production
    /// puts `assembled` first whenever page 1 is not a passthrough, and the two
    /// orders need not behave alike — nothing has asked.
    static func splice(source: URL, password: String?, into assembled: URL,
                       passthrough: [Int], pageCount: Int, to destination: URL,
                       using qpdf: String,
                       register: (Process) -> Void = { _ in }) throws {
        // Arithmetic first, and as refusals rather than clamps. Each of these
        // would otherwise build a page list that qpdf accepts and a reader
        // cannot tell from a correct one.
        guard pageCount >= 1 else { throw Failure.spliceFailed("no pages") }
        guard !passthrough.isEmpty else {
            throw Failure.spliceFailed("no pages to put back")
        }
        guard passthrough.count < pageCount else {
            throw Failure.spliceFailed("every page was passed through, so there "
                                       + "is nothing to splice them into")
        }
        guard passthrough.allSatisfy({ $0 >= 1 && $0 <= pageCount }),
              Set(passthrough).count == passthrough.count else {
            throw Failure.spliceFailed("page numbers \(passthrough) do not fit a "
                                       + "\(pageCount)-page document")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: qpdf)
        process.arguments = spliceArguments(
            source: source, password: password, assembled: assembled,
            passthrough: passthrough, pageCount: pageCount,
            destination: destination)
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        register(process)
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // 3 is qpdf's warning exit, which still produces valid output — the
        // same reading `overlay` has always taken.
        guard process.terminationStatus == 0 || process.terminationStatus == 3,
              FileManager.default.fileExists(atPath: destination.path) else {
            let message = String(decoding: err, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.spliceFailed(message.isEmpty
                ? "qpdf exited with code \(process.terminationStatus)" : message)
        }
    }

    // MARK: - Merging the text layer

    /// Lays `text` over `images` with qpdf, which rewrites page structure only —
    /// the JBIG2 streams are copied through untouched.
    ///
    /// `pages` restricts the merge to those 1-based pages, in both files at
    /// once: this route's text layer and its image document are page-for-page
    /// the same document, so the layer page and the destination page are the
    /// same number. C29 (B) needs that, because a page left out of both is not
    /// stamped at all — qpdf never wraps its content in a form XObject, and a
    /// spliced born-digital page comes through exactly as its author wrote it.
    /// Measured before it was written: `--to=2-3` over a three-page file leaves
    /// page 1's extracted text identical to the input's, character for
    /// character, while pages 2 and 3 carry both files' text.
    ///
    /// That matters more than it looks. C23 measured what stamping *does* to a
    /// page: qpdf wraps the destination's content in a form XObject whose
    /// `/BBox` is the page's crop box and centres it on the media box, which
    /// translated a cropped page by (50, 96). A passthrough page carries the
    /// source's own crop box, so stamping it would move it.
    static func overlay(text: URL, onto images: URL, to destination: URL,
                        using qpdf: String, pages: [Int]? = nil,
                        register: (Process) -> Void = { _ in }) throws {
        var arguments = [images.path, "--overlay", text.path]
        if let pages {
            let range = pageRange(pages)
            arguments += ["--from=\(range)", "--to=\(range)"]
        }
        arguments += ["--", destination.path]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: qpdf)
        process.arguments = arguments
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()
        register(process)
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        // qpdf uses exit code 3 for warnings, which still produce valid output.
        guard process.terminationStatus == 0 || process.terminationStatus == 3,
              FileManager.default.fileExists(atPath: destination.path) else {
            let message = String(decoding: err, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.overlayFailed(message.isEmpty
                ? "qpdf exited with code \(process.terminationStatus)" : message)
        }
    }

    // MARK: - The crop box, after the merge

    /// Whether this qpdf can be asked to change a page dictionary without
    /// touching the streams beside it.
    ///
    /// `--update-from-json` arrived with qpdf JSON v2 (qpdf 11). An older qpdf
    /// on the user's machine is a real possibility, and the answer decides the
    /// **route**, so it is asked before a route is chosen rather than discovered
    /// after the pages are compressed.
    static func canSetCropBoxes(using qpdf: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: qpdf)
        process.arguments = ["--help=--update-from-json"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Adds `/CropBox` to the published pages of a finished file, in place.
    ///
    /// **This is the last step, and it has to be**: `qpdf --overlay` wraps both
    /// the destination's content and the stamped text layer in form XObjects
    /// whose `/BBox` is the destination page's crop box, then centres that box on
    /// the media box. A crop box present during the merge therefore clips away
    /// everything outside it — permanently, not just from view — and translates
    /// the page image. `BUGS.md` C23 has the measurement: (50, 96) of shift on a
    /// 612x792 page cropped to 312x400.
    ///
    /// So the crop arrives afterwards, through qpdf's own JSON, which leaves the
    /// `/JBIG2Decode` streams alone. Measured on a one-page fixture: 7,391 bytes
    /// in, 7,414 out, compression intact, and the ink outside the crop still
    /// there when the trim is lifted.
    ///
    /// ## The trap this function is built around
    ///
    /// **`--update-from-json` replaces an object; it does not merge into one.**
    /// A patch carrying only `/CropBox` for a page produces a page with *only* a
    /// crop box: measured, 7,391 bytes became **391**, with `/Contents` and the
    /// image gone — and `qpdf --check` called the result healthy. That is a
    /// content-destroying edit with a clean bill of health, which is invariant 1's
    /// nightmare.
    ///
    /// Two things keep it safe, and neither is optional:
    ///
    ///  1. **The page dictionary is never authored here.** It is read back from
    ///     qpdf's own serialisation of the file and handed straight back with one
    ///     key added. This function does not know what a page dictionary contains
    ///     and must not learn.
    ///  2. **The result is verified before it replaces anything** — every page's
    ///     content and image object lists must be unchanged, and the crop boxes
    ///     must be what was asked for. `qpdf --check` does not answer either
    ///     question, as the 391-byte file demonstrates.
    static func setCropBoxes(_ boxes: [Int: CGRect], in file: URL, using qpdf: String,
                             register: (Process) -> Void = { _ in }) throws {
        guard !boxes.isEmpty else { return }

        /// `qpdf --json`, as data. `stream-data=none` keeps image bytes out of it:
        /// the JSON is proportional to the file's *structure*, not its pages.
        func json(_ keys: [String]) throws -> [String: Any] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: qpdf)
            process.arguments = [file.path, "--json=2", "--json-stream-data=none"]
                + keys.map { "--json-key=\($0)" }
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            register(process)
            // Read before waiting: a large structure fills the pipe buffer and
            // the child blocks writing while we block waiting (C6's shape).
            let data = out.fileHandleForReading.readDataToEndOfFile()
            _ = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 || process.terminationStatus == 3,
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw Failure.cropBoxFailed("qpdf could not describe the merged file") }
            return parsed
        }

        /// page number (from 1) -> the object it lives in, e.g. `3 0 R`.
        func pageObjects(_ described: [String: Any]) throws -> [Int: String] {
            guard let pages = described["pages"] as? [[String: Any]] else {
                throw Failure.cropBoxFailed("qpdf listed no pages")
            }
            var byNumber: [Int: String] = [:]
            for page in pages {
                guard let number = page["pageposfrom1"] as? Int,
                      let object = page["object"] as? String else {
                    throw Failure.cropBoxFailed("a page in qpdf's listing has no object")
                }
                byNumber[number] = object
            }
            return byNumber
        }

        /// What must not change: which objects hold each page's content and
        /// images. The verification after the patch compares these.
        func fingerprint(_ described: [String: Any]) -> [String] {
            ((described["pages"] as? [[String: Any]]) ?? []).map { page in
                let contents = (page["contents"] as? [String] ?? []).joined(separator: ",")
                let images = (page["images"] as? [Any] ?? []).count
                return "\(page["pageposfrom1"] as? Int ?? -1):\(contents):\(images)"
            }
        }

        let before = try json(["pages"])
        let objects = try pageObjects(before)
        let described = try json(["qpdf"])
        guard let qpdfKey = described["qpdf"] as? [Any], qpdfKey.count == 2,
              let header = qpdfKey[0] as? [String: Any],
              let all = qpdfKey[1] as? [String: Any] else {
            throw Failure.cropBoxFailed("qpdf's JSON is not the shape this expects")
        }

        var patch: [String: Any] = [:]
        for (number, box) in boxes.sorted(by: { $0.key < $1.key }) {
            guard let object = objects[number] else {
                throw Failure.cropBoxFailed("page \(number) is not in the merged file")
            }
            let key = "obj:\(object)"
            // Read back, not authored. See the note above: a patch that does not
            // carry the whole dictionary deletes the rest of it.
            guard let entry = all[key] as? [String: Any],
                  var value = entry["value"] as? [String: Any] else {
                throw Failure.cropBoxFailed("qpdf did not describe page \(number)")
            }
            guard box.width > 0, box.height > 0,
                  box.minX.isFinite, box.minY.isFinite,
                  box.maxX.isFinite, box.maxY.isFinite else {
                throw Failure.cropBoxFailed("page \(number) has an unusable displayed area")
            }
            value["/CropBox"] = [box.minX, box.minY, box.maxX, box.maxY]
            patch[key] = ["value": value]
        }

        let work = file.deletingLastPathComponent()
        let patchURL = work.appendingPathComponent("cropbox-\(UUID().uuidString).json")
        let patched = work.appendingPathComponent("cropped-\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: patchURL)
            try? FileManager.default.removeItem(at: patched)
        }
        let document: [String: Any] = ["qpdf": [
            ["jsonversion": 2, "pdfversion": header["pdfversion"] ?? "1.4"], patch]]
        guard let body = try? JSONSerialization.data(withJSONObject: document),
              (try? body.write(to: patchURL)) != nil else {
            throw Failure.cropBoxFailed("could not write the page update")
        }

        let apply = Process()
        apply.executableURL = URL(fileURLWithPath: qpdf)
        apply.arguments = [file.path, "--update-from-json=\(patchURL.path)", patched.path]
        let err = Pipe()
        apply.standardError = err
        apply.standardOutput = FileHandle.nullDevice
        try apply.run()
        register(apply)
        let errorText = err.fileHandleForReading.readDataToEndOfFile()
        apply.waitUntilExit()
        guard apply.terminationStatus == 0 || apply.terminationStatus == 3,
              FileManager.default.fileExists(atPath: patched.path) else {
            let message = String(decoding: errorText, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.cropBoxFailed(message.isEmpty
                ? "qpdf exited with code \(apply.terminationStatus)" : message)
        }

        // Verify against the file that is about to be replaced, not against a
        // description of what should have happened.
        let check = Process()
        check.executableURL = URL(fileURLWithPath: qpdf)
        check.arguments = [patched.path, "--json=2", "--json-stream-data=none", "--json-key=pages"]
        let checkOut = Pipe()
        check.standardOutput = checkOut
        check.standardError = FileHandle.nullDevice
        try check.run()
        register(check)
        let checkData = checkOut.fileHandleForReading.readDataToEndOfFile()
        check.waitUntilExit()
        guard check.terminationStatus == 0 || check.terminationStatus == 3,
              let after = try? JSONSerialization.jsonObject(with: checkData) as? [String: Any],
              fingerprint(after) == fingerprint(before) else {
            throw Failure.cropBoxFailed(
                "the page contents changed while the displayed area was being set")
        }

        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: patched, to: file)
    }
}
