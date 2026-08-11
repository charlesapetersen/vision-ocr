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

            /// Every file this stream owns, so the caller can clean up without
            /// knowing which kind it is. This was `url` returning one file, and
            /// an MRC page would have leaked the two it did not name.
            var urls: [URL] {
                switch self {
                case .jbig2(let u), .jpeg(let u): return [u]
                case .mrc(let m): return [m.mask, m.background, m.foreground]
                }
            }

            /// How many image XObjects the page needs. Object numbers are
            /// assigned from this, so a wrong answer here writes a broken xref.
            var imageCount: Int {
                switch self {
                case .jbig2, .jpeg: return 1
                case .mrc: return 3
                }
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

        var errorDescription: String? {
            switch self {
            case .encoderFailed(let m): return "JBIG2 compression failed: \(m)"
            case .overlayFailed(let m): return "Merging the text layer failed: \(m)"
            case .cannotWrite: return "Could not write the compressed PDF."
            case .noPages: return "There were no page images to assemble."
            case .badPageBox(let page, let size):
                return "Page \(page) reports an unusable size "
                    + "(\(size.width) x \(size.height)), so the compressed pages "
                    + "could not be given a page box that matches the text layer."
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
            try emit(string.data(using: .isoLatin1) ?? Data())
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
                // Written in the order the objects were numbered: background,
                // foreground, then the stencil the foreground points at.
                try writeImage(objects[0], from: m.background,
                               width: m.backgroundWidth, height: m.backgroundHeight,
                               filter: "/DCTDecode", bits: 8, space: "/DeviceGray")
                try writeImage(objects[1], from: m.foreground,
                               width: m.foregroundWidth, height: m.foregroundHeight,
                               filter: "/DCTDecode", bits: 8, space: "/DeviceGray",
                               smask: objects[2])
                // The stencil, at full page resolution. /Decode [1 0] because
                // JBIG2 codes ink as 1 while an /SMask reads 1 as opaque and 0
                // as transparent — without the inversion the foreground would
                // show everywhere *except* the text. Verified by rendering, not
                // by reading the specification.
                try writeImage(objects[2], from: m.mask, width: page.pixelWidth,
                               height: page.pixelHeight, filter: "/JBIG2Decode",
                               bits: 1, space: "/DeviceGray", decode: maskDecode)
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

    // MARK: - Merging the text layer

    /// Lays `text` over `images` with qpdf, which rewrites page structure only —
    /// the JBIG2 streams are copied through untouched.
    static func overlay(text: URL, onto images: URL, to destination: URL,
                        using qpdf: String, register: (Process) -> Void = { _ in }) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: qpdf)
        process.arguments = [images.path, "--overlay", text.path, "--", destination.path]
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
}
