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
            /// background, then the foreground through the stencil as a
            /// `/Mask`. See `Flattener.mrcLayers`.
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

            /// C47. The source page's own drawing, with its text taken out: a
            /// layered scan whose images cost no more than the rebuild's, such as
            /// Berendzen's two JPX layers under a JBIG2 mask. `splice` takes it
            /// from `textlessCopy`'s file, as it takes a passthrough page, but it
            /// was recognised, so unlike one it is stamped with the text layer.
            case sourcePage

            /// Every file this stream owns, so the caller can clean up without
            /// knowing which kind it is. This was `url` returning one file, and
            /// an MRC page would have leaked the two it did not name.
            var urls: [URL] {
                switch self {
                case .jbig2(let u), .jpeg(let u): return [u]
                case .mrc(let m): return [m.mask, m.background, m.foreground]
                case .passthrough, .sourcePage: return []
                }
            }

            /// How many image XObjects the page needs. Object numbers are
            /// assigned from this, so a wrong answer here writes a broken xref.
            var imageCount: Int {
                switch self {
                case .jbig2, .jpeg: return 1
                case .mrc: return 3
                case .passthrough, .sourcePage: return 0
                }
            }

            /// Whether this page keeps the source's own text, so takes no text
            /// layer. Only a passthrough page does.
            var isPassthrough: Bool {
                if case .passthrough = self { return true }
                return false
            }

            /// Whether this page has to come out of a source file rather than
            /// out of an encoded stream.
            var isFromSource: Bool {
                switch self {
                case .passthrough, .sourcePage: return true
                default: return false
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
            /// Whether the two tone layers are three-channel. Carried on the
            /// layers rather than read off `Page.isColour`, because those are
            /// different facts: `isColour` describes the single JPEG a page had
            /// before it was layered, and a colour page whose colour render
            /// failed is layered in grey. Reading the page's flag would then
            /// declare /DeviceRGB over one-channel streams and draw noise.
            var isColour = false
            /// The stencil's pixel size, or `nil` for the page's. They differ on a
            /// layered scan whose type is finer than its images (`BUGS.md` C39): the
            /// page is rebuilt at its images' resolution and the stencil at its type's.
            /// A size that disagrees with the stream is not an error any reader
            /// reports; it draws the stencil stretched over part of the page.
            var maskWidth: Int? = nil, maskHeight: Int? = nil
        }
        let stream: Stream
        let pixelWidth: Int
        let pixelHeight: Int
        let boxSize: CGSize
        /// True when `stream` is a three-channel JPEG.
        var isColour = false
        /// C37. The `/JBIG2Globals` a kept source stream decodes against, on a
        /// `.jbig2` page only. Pages that share one URL share one object, as
        /// they did in the source.
        var globals: URL? = nil
        /// C37. Whether `globals` is stored Flate-compressed, as a file that has
        /// been through qpdf has it, and is written that way.
        var globalsAreFlate = false
        /// C37. On a `.jbig2` page, where its stream goes, in points, and the
        /// stream's own pixel size, when it is a kept source image placed on part
        /// of the sheet. nil: the whole sheet, at `pixelWidth` by `pixelHeight`.
        /// `flipped`: drawn upside down, as the source drew it (C47).
        var placement: (rect: CGRect, width: Int, height: Int, flipped: Bool)? = nil
        /// C37. A 1-bit JBIG2 stencil drawn black over a placed stream: the ink
        /// the source page draws over its image, such as JSTOR's download line.
        var overlay: (stream: URL, width: Int, height: Int, rect: CGRect)? = nil

        /// Image XObjects this page writes: its stream's, and the overlay's.
        var imageCount: Int { stream.imageCount + (overlay == nil ? 0 : 1) }
    }

    /// C37. A source page's one image, when it is a JBIG2 stream this file can
    /// carry as it stands: the only image on the page, `/JBIG2Decode` alone, and
    /// no decode parameter but `/JBIG2Globals`. `data` holds its bytes exactly as
    /// the source stored them, and `globals` its globals, likewise — unfiltered
    /// or Flate, and `globalsAreFlate` says which. nil when there are none, or
    /// when the source's globals stream is empty, which decodes exactly as none.
    struct SourceImage: Equatable {
        let width: Int
        let height: Int
        let data: URL
        let globals: URL?
        var globalsAreFlate = false
    }

    /// C37. `SourceImage`s by 0-based page, with every stream of `file` written
    /// raw into `directory` in one qpdf pass. Empty when qpdf cannot say, which
    /// sends every page down the encoder as before.
    ///
    /// One pass, not one `--show-object` a page: qpdf re-reads the whole file
    /// each time it runs, and on a file whose cross-reference table it has to
    /// rebuild (Hayek 1978, 574 pages) that was 1.18 s a call against the 0.07 s
    /// encode it replaced. Exit 3, qpdf's warning, is accepted because that file
    /// always earns one; what a damaged stream would cost is caught by `Model`
    /// decoding the kept stream before it is used.
    ///
    /// Only the streams of a page whose own dictionary names its resources are
    /// looked at by `Flattener.sourceBitmap`, so a page inheriting them from
    /// `/Pages` is not kept. That costs bytes, never content.
    static func sourceImages(in file: URL, password: String?, using qpdf: String,
                             streamsInto directory: URL,
                             register: (Process) -> Void = { _ in }) -> [Int: SourceImage] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // `--decode-level=none`: every stream exactly as stored. Decoding would
        // write a Flate scan page out at its full 8-bit size — 40 MB against 28 MB
        // for Hayek, and gigabytes on a book of such pages.
        var arguments = ["--json", "--json-key=pages", "--json-key=qpdf",
                         "--json-stream-data=file", "--decode-level=none",
                         "--json-stream-prefix=\(directory.appendingPathComponent("s").path)"]
        // In a file, not in argv, where `ps` would show it to every local user for
        // as long as qpdf runs — `Annotations.transplant`'s reason, and its route.
        if let password, !password.isEmpty {
            let path = directory.appendingPathComponent("pw")
            guard (try? Data(password.utf8).write(to: path)) != nil else { return [:] }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: path.path)
            arguments.insert("--password-file=" + path.path, at: 0)
        }
        defer { try? FileManager.default.removeItem(at: directory.appendingPathComponent("pw")) }
        arguments.append(file.path)
        guard let out = try? runQPDF(arguments, using: qpdf, register: register),
              let top = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any],
              let pages = top["pages"] as? [[String: Any]],
              let objects = (top["qpdf"] as? [Any])?.last as? [String: Any] else { return [:] }
        return parseSourceImages(pages, objects: objects)
    }

    /// The pure half of `sourceImages`, so the rules can be pinned without qpdf.
    /// `objects` is qpdf's `obj:N G R` map, whose stream dictionaries describe
    /// the data as it was written: a filter qpdf decoded would be gone from them,
    /// and with nothing decoded every filter is still there.
    static func parseSourceImages(_ pages: [[String: Any]], objects: [String: Any])
        -> [Int: SourceImage] {
        func stream(_ ref: Any?) -> (dict: [String: Any], data: URL)? {
            guard let ref = ref as? String,
                  let s = (objects["obj:" + ref] as? [String: Any])?["stream"] as? [String: Any],
                  let dict = s["dict"] as? [String: Any],
                  let file = s["datafile"] as? String else { return nil }
            return (dict, URL(fileURLWithPath: file))
        }
        func filters(_ dict: [String: Any]) -> [String] {
            if let one = dict["/Filter"] as? String { return [one] }
            return dict["/Filter"] as? [String] ?? []
        }
        /// A dictionary, direct or by reference.
        func dictionary(_ value: Any?) -> [String: Any]? {
            if let ref = value as? String, ref.hasSuffix(" R") {
                let object = objects["obj:" + ref] as? [String: Any]
                return object?["value"] as? [String: Any]
                    ?? (object?["stream"] as? [String: Any])?["dict"] as? [String: Any]
            }
            return value as? [String: Any]
        }
        /// C47. qpdf lists only the images a page names itself. A page whose own
        /// resources name one form, whose own resources name one image, draws
        /// that image: `Flattener.soleImageStream`'s rule, which the render proves.
        func formImage(_ page: [String: Any]) -> [String: Any]? {
            let resources = dictionary(dictionary(page["object"])?["/Resources"])
            guard let xobjects = dictionary(resources?["/XObject"]), xobjects.count == 1,
                  let formRef = xobjects.values.first,
                  let form = dictionary(formRef), form["/Subtype"] as? String == "/Form",
                  let inner = dictionary(dictionary(form["/Resources"])?["/XObject"]),
                  inner.count == 1, let imageRef = inner.values.first as? String,
                  let image = dictionary(imageRef), image["/Subtype"] as? String == "/Image"
            else { return nil }
            return ["object": imageRef, "width": image["/Width"] as Any,
                    "height": image["/Height"] as Any]
        }
        var found: [Int: SourceImage] = [:]
        for (index, page) in pages.enumerated() {
            let listed = page["images"] as? [[String: Any]] ?? []
            guard let image = listed.count == 1 ? listed.first
                      : listed.isEmpty ? formImage(page) : nil,
                  let width = image["width"] as? Int, let height = image["height"] as? Int,
                  let data = stream(image["object"]),
                  // Still filtered in the file qpdf wrote, so these are the raw bytes.
                  filters(data.dict) == ["/JBIG2Decode"] else { continue }
            var globals: URL?
            var globalsAreFlate = false
            var parms = data.dict["/DecodeParms"]
            if let list = parms as? [Any] {
                guard list.count == 1 else { continue }
                parms = list[0] is NSNull ? nil : list[0]
            }
            if let parms, !(parms is NSNull) {
                guard let dict = parms as? [String: Any],
                      Set(dict.keys).isSubset(of: ["/JBIG2Globals"]) else { continue }
                if let ref = dict["/JBIG2Globals"] {
                    // Unfiltered or Flate, with no parameters, which is every way
                    // the corpus stores them and what qpdf writes by default: the
                    // bytes are kept with their one filter. Anything else is not
                    // written as data. Neither is proof the segments are whole — a
                    // truncated stream looks the same — which is why `Model` decodes
                    // the kept page again before it is used.
                    guard let g = stream(ref), g.dict["/DecodeParms"] == nil else { continue }
                    let kind = filters(g.dict)
                    guard kind.isEmpty || kind == ["/FlateDecode"] else { continue }
                    let size = (try? FileManager.default.attributesOfItem(
                        atPath: g.data.path)[.size] as? Int) ?? nil
                    guard let size else { continue }
                    if size > 0 { globals = g.data; globalsAreFlate = !kind.isEmpty }
                }
            }
            found[index] = SourceImage(width: width, height: height, data: data.data,
                                       globals: globals, globalsAreFlate: globalsAreFlate)
        }
        return found
    }

    /// qpdf's stdout, or a throw. 3 is its warning exit and still an answer.
    private static func runQPDF(_ arguments: [String], using qpdf: String,
                                register: (Process) -> Void = { _ in }) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: qpdf)
        process.arguments = arguments
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        register(process)
        // Both pipes drained before the wait, and concurrently: a child that
        // fills the one nobody is reading blocks forever.
        var err = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            err = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave()
        }
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || process.terminationStatus == 3 else {
            let message = String(decoding: err, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure.encoderFailed(message.isEmpty
                ? "qpdf exited with code \(process.terminationStatus)" : message)
        }
        return out
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
        case outlineFailed(String)
        case documentInfoFailed(String)
        case textlessCopyFailed(String)

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
            case .outlineFailed(let m):
                return "Carrying the outline onto the compressed copy failed: \(m)"
            case .documentInfoFailed(let m):
                return "Carrying the page numbers and title across failed: \(m)"
            case .textlessCopyFailed(let m):
                return "Taking the original's text off its own pages failed: \(m)"
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
    /// The stencil is an `/ImageMask`, the foreground's `/Mask`, and a stencil
    /// mask paints where its sample is 0. PDF's JBIG2Decode filter presents ink
    /// as 0 (DeviceGray black), so the default `[0 1]` is right, and it is
    /// written out so that the polarity is one visible constant. `[1 0]` paints
    /// the foreground everywhere except the text.
    ///
    /// C38: this was an `/SMask` with `[1 0]` until 2026-09-26. CoreGraphics,
    /// and so PDFKit and Preview, samples an `/SMask` on a /DeviceRGB base
    /// image's grid (not on a /DeviceGray one), so on a 28 ppi colour foreground
    /// the 111 ppi text came out a blur that poppler never showed. PDFKit and
    /// poppler both draw a `/Mask` stencil at the stencil's own resolution.
    /// Established by rendering, as the old polarity was. The ink-bounds check
    /// in the MRC block holds the polarity, and the sharpness check the
    /// resolution; the stripes are symmetric, so that one cannot see polarity.
    static let maskDecode = "[ 0 1 ]"

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
        if let bad = pages.firstIndex(where: { $0.stream.isFromSource }) {
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
        // C37. One object per distinct globals stream, numbered right after the
        // first page that uses it, which is also where it is written.
        var globalsObjects: [URL: Int] = [:], globalsFirstWrittenBy: [Int: URL] = [:]
        var nextObject = 3
        for (i, page) in pages.enumerated() {
            pageObjects.append(nextObject); nextObject += 1
            contentObjects.append(nextObject); nextObject += 1
            let count = page.imageCount
            imageObjects.append(Array(nextObject..<(nextObject + count)))
            nextObject += count
            if case .jbig2 = page.stream, let globals = page.globals,
               globalsObjects[globals] == nil {
                globalsObjects[globals] = nextObject; nextObject += 1
                globalsFirstWrittenBy[i] = globals
            }
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
            // is not drawn, it is the foreground's /Mask.
            let content: String
            switch page.stream {
            case .mrc:
                content = "q \(w) 0 0 \(h) 0 0 cm /Im0 Do Q\n"
                        + "q \(w) 0 0 \(h) 0 0 cm /Im1 Do Q\n"
            case .jbig2 where page.placement != nil || page.overlay != nil:
                // C37. A kept stream on its own rect, then the ink over it, black.
                var drawn = ""
                for (name, rect, flipped) in [("/Im0 Do", page.placement?.rect,
                                               page.placement?.flipped ?? false),
                                              ("0 g /Im1 Do", page.overlay?.rect, false)] {
                    guard let rect else { continue }
                    // C47. A flipped stream is drawn as its source drew it: from
                    // the rect's top, downwards, so its first row lands at the foot.
                    guard let x = trimOffset(rect.minX),
                          let y = trimOffset(flipped ? rect.maxY : rect.minY),
                          let rw = trim(rect.width), let rh = trim(rect.height) else {
                        throw Failure.badPageBox(page: i + 1, size: rect.size)
                    }
                    drawn += "q \(rw) 0 0 \(flipped ? "-" : "")\(rh) \(x) \(y) cm \(name) Q\n"
                }
                content = page.placement == nil
                    ? "q \(w) 0 0 \(h) 0 0 cm /Im0 Do Q\n" + drawn : drawn
            case .jbig2, .jpeg:
                content = "q \(w) 0 0 \(h) 0 0 cm /Im0 Do Q\n"
            case .passthrough, .sourcePage:
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
                            mask: Int? = nil, isStencil: Bool = false,
                            decode: String? = nil, parms: String? = nil) throws {
                guard let bytes = try? Data(contentsOf: url), !bytes.isEmpty else {
                    throw Failure.encoderFailed("page \(i + 1) produced no image data")
                }
                try beginObject(number)
                try write("""
                << /Type /XObject /Subtype /Image /Width \(width) \
                /Height \(height) \(isStencil ? "/ImageMask true" : "/ColorSpace \(space)") \
                /BitsPerComponent \(bits) /Filter \(filter) \
                \(decode.map { "/Decode \($0) " } ?? "")\
                \(parms.map { "/DecodeParms \($0) " } ?? "")\
                \(mask.map { "/Mask \($0) 0 R " } ?? "")/Length \(bytes.count) >>
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
                let globals = page.globals.flatMap { globalsObjects[$0] }
                try writeImage(objects[0], from: u, width: page.placement?.width ?? page.pixelWidth,
                               height: page.placement?.height ?? page.pixelHeight,
                               filter: "/JBIG2Decode", bits: 1, space: space,
                               parms: globals.map { "<< /JBIG2Globals \($0) 0 R >>" })
                // Numbered after the page's stream and before any globals.
                if let overlay = page.overlay {
                    try writeImage(objects[1], from: overlay.stream, width: overlay.width,
                                   height: overlay.height, filter: "/JBIG2Decode", bits: 1,
                                   space: "", isStencil: true, decode: maskDecode)
                }
                if let url = globalsFirstWrittenBy[i], let number = globalsObjects[url] {
                    guard let bytes = try? Data(contentsOf: url), !bytes.isEmpty else {
                        throw Failure.encoderFailed("page \(i + 1)'s JBIG2 globals are empty")
                    }
                    try beginObject(number)
                    let filter = page.globalsAreFlate ? " /Filter /FlateDecode" : ""
                    try write("<< /Length \(bytes.count)\(filter) >>\nstream\n")
                    try emit(bytes)
                    try write("\nendstream\nendobj\n")
                }
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
                               mask: objects[2])
                // The stencil, at full page resolution or finer (C39): an
                // /ImageMask, which PDFKit draws at its own resolution, where an
                // /SMask was drawn at the foreground's (C38). Polarity: see
                // `maskDecode`.
                try writeImage(objects[2], from: m.mask, width: m.maskWidth ?? page.pixelWidth,
                               height: m.maskHeight ?? page.pixelHeight, filter: "/JBIG2Decode",
                               bits: 1, space: "", isStencil: true, decode: maskDecode)
            case .passthrough, .sourcePage:
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

    /// `trim` for a position rather than a size: zero and negative are real
    /// places, an overlay's grid starting a fraction of a point off the sheet.
    private static func trimOffset(_ value: CGFloat) -> String? {
        let d = Double(value)
        guard d.isFinite, abs(d) < 200_000 else { return nil }
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
    /// into `assembled` would be lost here. `Model` writes the outline onto the
    /// spliced file afterwards (C35), and keeps the document off this route when
    /// its qpdf cannot; it is not something this function can repair.
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
        // Every page passed through is allowed since C43: the result is the
        // source's own pages, and `assembled` is never read.
        guard passthrough.count <= pageCount else {
            throw Failure.spliceFailed("\(passthrough.count) pages to put back into a "
                                       + "\(pageCount)-page document")
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

    // MARK: - A source page without its text — C47

    /// C47. The operators that set, place or show text. Taking out these and their
    /// operands, and nothing else, leaves the rest of a page's drawing as it was:
    /// every other operator a text object may hold (colour, `gs`, marked content)
    /// is legal outside one and sets the state it set.
    static let textOperators: Set<String> = [
        "BT", "ET", "Tc", "Tw", "Tz", "TL", "Tf", "Tr", "Ts", "Td", "TD", "Tm", "T*",
        "Tj", "TJ", "'", "\"",
    ]

    /// C47. A page's content streams with every text operator and its operands
    /// taken out, each replaced by a newline, and every other byte kept. Read as
    /// one, as a reader draws them, so a text object may open in one stream and
    /// close in the next.
    ///
    /// nil when a stream cannot be read with certainty: a text object that nests or
    /// does not close, text shown outside one, a stream that ends inside an array,
    /// a dictionary or an operator's operands while another follows, an
    /// unterminated string, or an inline image, whose data a scan for `EI` can
    /// misread. nil keeps the page on the rebuild, which is what it had before.
    static func removingText(from streams: [Data]) -> [Data]? {
        func isSpace(_ c: UInt8) -> Bool {
            c == 0x00 || c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D || c == 0x20
        }
        func isDelimiter(_ c: UInt8) -> Bool {
            c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B || c == 0x5D
                || c == 0x7B || c == 0x7D || c == 0x2F || c == 0x25
        }
        var inText = false
        var result: [Data] = []
        for (number, content) in streams.enumerated() {
            let bytes = [UInt8](content), n = bytes.count
            var out = Data(capacity: n)
            var copied = 0              // bytes before this are in `out`, or taken out
            var operands: Int?          // where the next operator's operands begin
            var open: [UInt8] = []      // `[` or `<` for each array or dictionary open
            var i = 0
            while i < n {
                let c = bytes[i]
                if isSpace(c) { i += 1; continue }
                if c == 0x25 {          // a comment, to the end of its line
                    while i < n, bytes[i] != 0x0A, bytes[i] != 0x0D { i += 1 }
                    continue
                }
                let start = i
                switch c {
                case 0x28:              // a string: parentheses balance, `\` escapes a byte
                    var level = 0
                    while true {
                        guard i < n else { return nil }
                        let b = bytes[i]
                        i += 1
                        if b == 0x5C {
                            i += 1
                        } else if b == 0x28 {
                            level += 1
                        } else if b == 0x29 {
                            level -= 1
                            if level == 0 { break }
                        }
                    }
                case 0x3C where i + 1 < n && bytes[i + 1] == 0x3C:
                    open.append(0x3C)
                    i += 2
                case 0x3C:              // a hex string
                    while i < n, bytes[i] != 0x3E { i += 1 }
                    guard i < n else { return nil }
                    i += 1
                case 0x3E:              // `>>` closes a dictionary; a lone `>` is malformed
                    guard i + 1 < n, bytes[i + 1] == 0x3E, open.last == 0x3C else { return nil }
                    open.removeLast()
                    i += 2
                case 0x5B:
                    open.append(0x5B)
                    i += 1
                case 0x5D:
                    guard open.last == 0x5B else { return nil }
                    open.removeLast()
                    i += 1
                case 0x29, 0x7B, 0x7D:  // a stray `)`, or a PostScript procedure
                    return nil
                case 0x2F:              // a name
                    i += 1
                    while i < n, !isSpace(bytes[i]), !isDelimiter(bytes[i]) { i += 1 }
                default:                // a number, a keyword or an operator
                    while i < n, !isSpace(bytes[i]), !isDelimiter(bytes[i]) { i += 1 }
                    let first = bytes[start]
                    let word = String(decoding: bytes[start..<i], as: UTF8.self)
                    if !open.isEmpty || word == "true" || word == "false" || word == "null"
                        || (0x30...0x39).contains(first) || first == 0x2B || first == 0x2D
                        || first == 0x2E {
                        break
                    }
                    // An operator, which takes every operand since the one before it.
                    if word == "BI" || word == "ID" || word == "EI" { return nil }
                    let from = operands ?? start
                    operands = nil
                    guard textOperators.contains(word) else { continue }
                    switch word {
                    case "BT":
                        guard !inText else { return nil }
                        inText = true
                    case "ET":
                        guard inText else { return nil }
                        inText = false
                    case "Tj", "TJ", "'", "\"":
                        guard inText else { return nil }
                    default:
                        break
                    }
                    out.append(contentsOf: bytes[copied..<from])
                    out.append(0x0A)
                    copied = i
                    continue
                }
                // Whatever reached here is an operand of the next operator.
                if operands == nil { operands = start }
            }
            // A stream ends between tokens, so an operand left over would belong to
            // an operator in the next one, which this reads on its own.
            guard open.isEmpty, operands == nil || number == streams.count - 1 else { return nil }
            out.append(contentsOf: bytes[copied..<n])
            result.append(out)
        }
        return inText ? nil : result
    }

    /// C47. A copy of `file`, decrypted, in which each page in `budgets` whose own
    /// drawing costs no more than its budget in bytes has had its text taken out
    /// (`removingText`), its `/Annots` dropped and the fonts it no longer uses
    /// unlisted. Returns those pages, numbered from 1, with what each costs; every
    /// other page is as it was.
    ///
    /// A page costs what `splice` would carry into the finished file for it: every
    /// stream its resources reach, the fonts it no longer uses aside, and its
    /// content. The caller's budget is what the rebuild would publish, so a page
    /// leaves the rebuild only when keeping it costs no more. Berendzen's two JPX
    /// layers under their JBIG2 mask, and its two JPX photographs, come to 134 KB
    /// against the rebuild's 220 KB.
    ///
    /// Its annotations go because the rebuild carries none either: the transplant
    /// adds them back when the reader asks for them, and a page that kept its own
    /// would be given each mark twice (`Model`'s passthrough refusal says so).
    ///
    /// Only a page on a sheet the rebuild would have left as it is is taken: no
    /// turn, no crop or trim box but the sheet, the sheet at the origin (the guard
    /// below says why each), and no optional content anywhere in the document.
    ///
    /// ⚠️ Nothing here proves the copy draws what the source drew, and no page of it
    /// may be published without that proof: `Model` renders each returned page from
    /// both files and keeps only those that match, pixel for pixel
    /// (`Flattener.drawsAlike`). The page dictionaries are read back from qpdf's own
    /// JSON and handed back with keys removed, never authored, for `setCropBoxes`'s
    /// reason.
    static func textlessCopy(of file: URL, password: String?, budgets: [Int: Int],
                             to destination: URL, using qpdf: String,
                             register: (Process) -> Void = { _ in }) throws -> [Int: Int] {
        guard !budgets.isEmpty else { return [:] }
        let work = destination.deletingLastPathComponent()
        // In a file, not in argv, for `sourceImages`'s reason.
        let passwordFile = work.appendingPathComponent("pw-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: passwordFile) }
        var unlock: [String] = []
        if let password, !password.isEmpty {
            guard (try? Data(password.utf8).write(to: passwordFile)) != nil else {
                throw Failure.textlessCopyFailed("could not hand qpdf the password")
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: passwordFile.path)
            unlock = ["--password-file=" + passwordFile.path]
        }
        func run(_ arguments: [String]) throws -> Data {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: qpdf)
            process.arguments = arguments
            // Warnings to a file, not a pipe, for `carryDocumentInfo`'s reason: a
            // child blocked on a full stderr never closes stdout.
            let errURL = work.appendingPathComponent("qpdf-\(UUID().uuidString).err")
            defer { try? FileManager.default.removeItem(at: errURL) }
            FileManager.default.createFile(atPath: errURL.path, contents: nil)
            let err = try FileHandle(forWritingTo: errURL)
            defer { try? err.close() }
            let out = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            register(process)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 || process.terminationStatus == 3 else {
                let message = String(decoding: (try? Data(contentsOf: errURL)) ?? Data(),
                                     as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw Failure.textlessCopyFailed(message.isEmpty
                    ? "qpdf exited with code \(process.terminationStatus)" : message)
            }
            return data
        }
        func json(_ arguments: [String]) throws -> [String: Any] {
            guard let parsed = try? JSONSerialization.jsonObject(with: run(arguments))
                    as? [String: Any] else {
                throw Failure.textlessCopyFailed("qpdf could not describe the file")
            }
            return parsed
        }
        func isRef(_ s: String) -> Bool {
            let parts = s.split(separator: " ")
            return parts.count == 3 && parts[2] == "R" && Int(parts[0]) != nil
                && Int(parts[1]) != nil
        }

        let described = try json(unlock + [file.path, "--json=2", "--json-stream-data=none",
                                            "--json-key=pages", "--json-key=qpdf"])
        guard let pages = described["pages"] as? [[String: Any]],
              let qpdfKey = described["qpdf"] as? [Any], qpdfKey.count == 2,
              let header = qpdfKey[0] as? [String: Any],
              let all = qpdfKey[1] as? [String: Any] else {
            throw Failure.textlessCopyFailed("qpdf's JSON is not the shape this expects")
        }
        func object(_ ref: String) -> [String: Any]? { all["obj:" + ref] as? [String: Any] }
        func resolve(_ value: Any?) -> Any? {
            guard let ref = value as? String, isRef(ref) else { return value }
            let o = object(ref)
            return o?["value"] ?? (o?["stream"] as? [String: Any])?["dict"]
        }
        func length(_ ref: String) -> Int? {
            guard let dict = (object(ref)?["stream"] as? [String: Any])?["dict"]
                    as? [String: Any] else { return nil }
            return (dict["/Length"] as? Int) ?? (resolve(dict["/Length"]) as? Int)
        }
        /// A rectangle as four numbers, lower-left first, or nil.
        func rect(_ value: Any?) -> [Double]? {
            guard let array = resolve(value) as? [Any], array.count == 4 else { return nil }
            let n = array.compactMap { (resolve($0) as? NSNumber)?.doubleValue }
            guard n.count == 4 else { return nil }
            return [min(n[0], n[2]), min(n[1], n[3]), max(n[0], n[2]), max(n[1], n[3])]
        }
        /// What a page inherits: its own entry, or the nearest `/Pages` node's above it.
        func inherited(_ key: String, _ page: [String: Any]) -> Any? {
            var node: [String: Any]? = page
            for _ in 0..<64 {
                guard let n = node else { return nil }
                if let v = n[key] { return resolve(v) }
                node = resolve(n["/Parent"]) as? [String: Any]
            }
            return nil
        }
        // A document with optional content is left alone: `splice` does not carry the
        // catalogue's `/OCProperties`, so a layer it hides would show on a kept page.
        if let trailer = (all["trailer"] as? [String: Any])?["value"] as? [String: Any],
           let catalog = resolve(trailer["/Root"]) as? [String: Any],
           catalog["/OCProperties"] != nil {
            return [:]
        }
        // How often each object is named anywhere in the file. A content stream or a
        // resource dictionary that anything else names cannot change for one page.
        var named: [String: Int] = [:]
        var pending: [Any] = Array(all.values)
        while let value = pending.popLast() {
            if let s = value as? String {
                if isRef(s) { named[s, default: 0] += 1 }
            } else if let a = value as? [Any] {
                pending.append(contentsOf: a)
            } else if let d = value as? [String: Any] {
                // An object's own entry names nothing: its "value", or its stream's "dict".
                pending.append(contentsOf: d.filter { $0.key != "datafile" }.values)
            }
        }
        /// Every stream `roots` reach, in bytes: what the splice carries for them. Not
        /// up a page tree, which belongs to the document; nil past `budget`, past a
        /// bound, or at a stream whose length qpdf does not give. Stopping at the budget
        /// keeps a book whose pages share one resource dictionary naming every image
        /// from walking every image once per page.
        func cost(of roots: [Any], within budget: Int) -> Int? {
            var seen = Set<String>(), stack = roots, total = 0, steps = 0
            while let value = stack.popLast() {
                steps += 1
                if steps > 200_000 { return nil }
                if let s = value as? String {
                    guard isRef(s), seen.insert(s).inserted, let o = object(s) else { continue }
                    if let stream = o["stream"] as? [String: Any] {
                        guard let bytes = length(s) else { return nil }
                        total += bytes
                        if total > budget { return nil }
                        if let dict = stream["dict"] { stack.append(dict) }
                    } else if let v = o["value"] {
                        // A page reached from a resource is another page's to carry, and
                        // the structure tree and the catalogue are the document's.
                        if let type = (v as? [String: Any])?["/Type"] as? String,
                           ["/Page", "/Pages", "/StructElem", "/StructTreeRoot", "/Catalog"]
                               .contains(type) { continue }
                        stack.append(v)
                    }
                } else if let a = value as? [Any] {
                    stack.append(contentsOf: a)
                } else if let d = value as? [String: Any] {
                    for (key, v) in d where key != "/Parent" { stack.append(v) }
                }
            }
            return total
        }

        struct Candidate {
            let page: Int, ref: String, value: [String: Any], contents: [String]
            /// The page's own resources, when no other object names them, so their
            /// `/Font` can go: `ref` nil when they are written in the page itself.
            let resources: (ref: String?, dict: [String: Any])?
            let cost: Int
        }
        var candidates: [Candidate] = []
        for (number, budget) in budgets.sorted(by: { $0.key < $1.key }) {
            guard number >= 1, number <= pages.count,
                  pages[number - 1]["pageposfrom1"] as? Int == number,
                  let ref = pages[number - 1]["object"] as? String,
                  let value = object(ref)?["value"] as? [String: Any],
                  let contents = pages[number - 1]["contents"] as? [String], !contents.isEmpty,
                  contents.allSatisfy({ named[$0] == 1 }),
                  // An array of them, by reference, is shared as surely as a stream is.
                  (value["/Contents"] as? String).map({ !isRef($0) || named[$0] == 1 }) ?? true,
                  (resolve(value["/UserUnit"]) as? NSNumber).map({ $0.doubleValue == 1 }) ?? true
            else { continue }
            // The text layer lands on a kept page as it lands on a rebuilt one only on a
            // sheet the rebuild would not have changed. Asked here, of the page's own
            // dictionary: PDFKit clips a crop box to the media box, so one larger than the
            // sheet read as equal to it, and `overlay` then centred the scan in it.
            //  - No turn: the rebuild bakes a `/Rotate` in, and the layer is drawn upright.
            //  - No crop or trim box but the sheet: `overlay` fits the layer into the trim
            //    box and moves the page's own drawing to centre it there (C23).
            //  - A sheet at the origin, to half a point: the reader's marks and the outline
            //    are placed as on a rebuilt page, which starts there (`transplant` moves
            //    them by the source's offset: -24.69 pt on `Cohen_1990`).
            let turn = (inherited("/Rotate", value) as? NSNumber)?.intValue ?? 0
            guard turn % 360 == 0, let sheet = rect(inherited("/MediaBox", value)),
                  abs(sheet[0]) <= 0.5, abs(sheet[1]) <= 0.5,
                  [inherited("/CropBox", value), value["/TrimBox"]].allSatisfy({ box in
                      guard box != nil else { return true }
                      guard let r = rect(box) else { return false }
                      return zip(r, sheet).allSatisfy { abs($0 - $1) <= 0.01 }
                  })
            else { continue }
            var resources: (ref: String?, dict: [String: Any])?
            if let dict = value["/Resources"] as? [String: Any] {
                resources = (nil, dict)
            } else if let r = value["/Resources"] as? String, isRef(r), named[r] == 1,
                      let dict = object(r)?["value"] as? [String: Any] {
                resources = (r, dict)
            }
            // Inherited or shared, the fonts stay, and are charged: the splice carries them.
            var roots: [Any] = []
            if var own = resources?.dict {
                own.removeValue(forKey: "/Font")
                roots.append(own)
            } else if let shared = inherited("/Resources", value) {
                roots.append(shared)
            }
            // And whatever else the page names, a thumbnail or `/PieceInfo`: the splice
            // carries it. Not its content, charged below, nor what the copy drops.
            for (key, v) in value where !["/Parent", "/Contents", "/Resources", "/Annots", "/B"]
                .contains(key) {
                roots.append(v)
            }
            guard let bytes = cost(of: roots, within: budget) else { continue }
            candidates.append(Candidate(page: number, ref: ref, value: value, contents: contents,
                                        resources: resources, cost: bytes))
        }
        guard !candidates.isEmpty else { return [:] }

        // The content streams alone, decoded: every stream would write a Flate scan out
        // at its full size (`sourceImages` measured 40 MB against 28 MB for Hayek).
        let wanted = candidates.flatMap(\.contents).map { ref -> String in
            let parts = ref.split(separator: " ")
            return "--json-object=\(parts[0]),\(parts[1])"
        }
        let fetched = try json(unlock + [file.path, "--json=2", "--json-key=qpdf",
                                         "--json-stream-data=inline",
                                         "--decode-level=generalized"] + wanted)
        guard let streams = (fetched["qpdf"] as? [Any])?.last as? [String: Any] else {
            throw Failure.textlessCopyFailed("qpdf did not give the pages' content")
        }
        var patch: [String: Any] = [:]
        var stripped: [Int: Int] = [:]
        for candidate in candidates {
            var dicts: [[String: Any]] = [], datas: [Data] = []
            for ref in candidate.contents {
                // Still filtered means qpdf could not decode it, and it cannot be read.
                guard let s = (streams["obj:" + ref] as? [String: Any])?["stream"]
                        as? [String: Any],
                      let dict = s["dict"] as? [String: Any], dict["/Filter"] == nil,
                      let data = Data(base64Encoded: s["data"] as? String ?? "") else { break }
                dicts.append(dict)
                datas.append(data)
            }
            guard datas.count == candidate.contents.count,
                  let without = removingText(from: datas) else { continue }
            let cost = candidate.cost + without.reduce(0, { $0 + $1.count })
            guard cost <= budgets[candidate.page] ?? 0 else { continue }
            for (k, ref) in candidate.contents.enumerated() {
                patch["obj:" + ref] = ["stream": ["dict": dicts[k],
                                                  "data": without[k].base64EncodedString()]]
            }
            var value = candidate.value
            value.removeValue(forKey: "/Annots")
            if let resources = candidate.resources {
                var dict = resources.dict
                dict.removeValue(forKey: "/Font")
                if let r = resources.ref { patch["obj:" + r] = ["value": dict] }
                else { value["/Resources"] = dict }
            }
            patch["obj:" + candidate.ref] = ["value": value]
            stripped[candidate.page] = cost
        }
        guard !stripped.isEmpty else { return [:] }

        let patchURL = work.appendingPathComponent("textless-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: patchURL) }
        let document: [String: Any] = ["qpdf": [
            ["jsonversion": 2, "pdfversion": header["pdfversion"] ?? "1.4"], patch]]
        guard let body = try? JSONSerialization.data(withJSONObject: document),
              (try? body.write(to: patchURL)) != nil else {
            throw Failure.textlessCopyFailed("could not write the page update")
        }
        try? FileManager.default.removeItem(at: destination)
        // Every stream as it was stored: by default qpdf compresses one the source kept
        // raw, and, told not to, writes out decoded every stream it can decode. Either
        // reads below as a page changed. The splice compresses the new content.
        _ = try run(unlock + [file.path, "--decrypt", "--decode-level=none",
                              "--compress-streams=n", "--update-from-json=\(patchURL.path)",
                              destination.path])
        // Every page's content objects and images as they were: only bytes of the
        // content streams, and keys of the page dictionaries, may have changed.
        let after = try json([destination.path, "--json=2", "--json-stream-data=none",
                              "--json-key=pages"])
        guard FileManager.default.fileExists(atPath: destination.path),
              pageFingerprint(after) == pageFingerprint(described) else {
            try? FileManager.default.removeItem(at: destination)
            throw Failure.textlessCopyFailed("the pages changed while their text was taken out")
        }
        return stripped
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

    // MARK: - The outline, after the splice — C35

    /// Writes `outline` into a finished file's catalogue, in place.
    ///
    /// C35. `splice` runs `qpdf --empty --pages`, which drops `/Outlines`, and a
    /// document with an outline and one born-digital page was kept off this route
    /// for that reason. Every JSTOR download is one: its cover is born digital and
    /// its outline is the article's. The Flate route it took drew each page again
    /// through CoreGraphics — 1-bit pages as Flate at ~50x their JBIG2 size, and
    /// born-digital pages with their fonts embedded once per page — so Hughes grew
    /// 0.5 → 3.0 MB and Dobbin 2.6 → 17.6 MB.
    ///
    /// So the outline goes on after the splice, through qpdf's own JSON, the same
    /// way `setCropBoxes` puts the crop box on, and `overlay` then keeps it
    /// because it keeps the base file's catalogue. The catalogue is read back and
    /// handed back with one key added (`setCropBoxes` says why nothing here may
    /// author a whole object), and the result is verified before it replaces
    /// anything: every entry's title and page must read back as written, and every
    /// page's content objects must be unchanged.
    static func setOutline(_ outline: [SearchableWriter.OutlineItem], in file: URL,
                           using qpdf: String,
                           register: (Process) -> Void = { _ in }) throws {
        guard !outline.isEmpty else { return }

        func json(_ url: URL, _ keys: [String]) throws -> [String: Any] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: qpdf)
            process.arguments = [url.path, "--json=2", "--json-stream-data=none"]
                + keys.map { "--json-key=\($0)" }
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()
            register(process)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            _ = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 || process.terminationStatus == 3,
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw Failure.outlineFailed("qpdf could not describe the file") }
            return parsed
        }
        let fingerprint = pageFingerprint

        let before = try json(file, ["pages"])
        guard let pages = before["pages"] as? [[String: Any]], !pages.isEmpty else {
            throw Failure.outlineFailed("qpdf listed no pages")
        }
        var pageObjects: [String] = []
        for (i, page) in pages.enumerated() {
            guard page["pageposfrom1"] as? Int == i + 1,
                  let object = page["object"] as? String else {
                throw Failure.outlineFailed("qpdf's page list is not in order")
            }
            pageObjects.append(object)
        }
        let described = try json(file, ["qpdf"])
        guard let qpdfKey = described["qpdf"] as? [Any], qpdfKey.count == 2,
              let header = qpdfKey[0] as? [String: Any],
              let all = qpdfKey[1] as? [String: Any],
              let trailer = (all["trailer"] as? [String: Any])?["value"] as? [String: Any],
              let rootRef = trailer["/Root"] as? String,
              var catalog = (all["obj:\(rootRef)"] as? [String: Any])?["value"] as? [String: Any]
        else { throw Failure.outlineFailed("qpdf's JSON is not the shape this expects") }

        // New objects numbered past every one the file has.
        var highest = header["maxobjectid"] as? Int ?? 0
        for key in all.keys where key.hasPrefix("obj:") {
            let number = key.dropFirst(4).split(separator: " ").first.flatMap { Int($0) } ?? 0
            highest = max(highest, number)
        }
        let root = highest + 1
        let flat = flatten(outline, from: root + 1, parent: root, pageCount: pageObjects.count)
        guard let first = flat.first(where: { $0.parent == root }),
              let last = flat.last(where: { $0.parent == root }) else { return }

        func ref(_ n: Int) -> String { "\(n) 0 R" }
        var patch: [String: Any] = [:]
        catalog["/Outlines"] = ref(root)
        patch["obj:\(rootRef)"] = ["value": catalog]
        patch["obj:\(ref(root))"] = ["value": [
            "/Type": "/Outlines", "/First": ref(first.number), "/Last": ref(last.number),
            "/Count": flat.count] as [String: Any]]
        for node in flat {
            // "u:" is qpdf's marker for a text string it encodes itself.
            var value: [String: Any] = ["/Title": "u:" + node.title, "/Parent": ref(node.parent)]
            if let prev = node.prev { value["/Prev"] = ref(prev) }
            if let next = node.next { value["/Next"] = ref(next) }
            if let a = node.firstChild, let b = node.lastChild {
                value["/First"] = ref(a)
                value["/Last"] = ref(b)
                value["/Count"] = node.descendants
            }
            if let page = node.pageIndex {
                // null for what the source left unspecified, as `assemble` writes it.
                func number(_ v: CGFloat?) -> Any {
                    v.flatMap(coordinate).flatMap(Double.init) ?? NSNull()
                }
                value["/Dest"] = [pageObjects[page], "/XYZ", number(node.left),
                                  number(node.top), NSNull()]
            }
            patch["obj:\(ref(node.number))"] = ["value": value]
        }

        let work = file.deletingLastPathComponent()
        let patchURL = work.appendingPathComponent("outline-\(UUID().uuidString).json")
        let patched = work.appendingPathComponent("outlined-\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: patchURL)
            try? FileManager.default.removeItem(at: patched)
        }
        let document: [String: Any] = ["qpdf": [
            ["jsonversion": 2, "pdfversion": header["pdfversion"] ?? "1.4"], patch]]
        guard let body = try? JSONSerialization.data(withJSONObject: document),
              (try? body.write(to: patchURL)) != nil else {
            throw Failure.outlineFailed("could not write the outline update")
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
            throw Failure.outlineFailed(message.isEmpty
                ? "qpdf exited with code \(apply.terminationStatus)" : message)
        }

        // Read back from the file about to replace this one: the entries in
        // order, each with its title and page, and the pages untouched.
        func entries(_ items: [[String: Any]]) -> [String] {
            items.flatMap { item -> [String] in
                let page = (item["destpageposfrom1"] as? Int).map(String.init) ?? "-"
                return ["\(item["title"] as? String ?? "?")@\(page)"]
                    + entries(item["kids"] as? [[String: Any]] ?? [])
            }
        }
        let wanted = flat.map { "\($0.title)@\($0.pageIndex.map { String($0 + 1) } ?? "-")" }
        let after = try json(patched, ["pages", "outlines"])
        guard fingerprint(after) == fingerprint(before) else {
            throw Failure.outlineFailed("the pages changed while the outline was written")
        }
        guard entries(after["outlines"] as? [[String: Any]] ?? []) == wanted else {
            throw Failure.outlineFailed("the outline did not read back as written")
        }

        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: patched, to: file)
    }

    /// Each page's contents and images, from qpdf's `pages` key. Not object
    /// numbers: qpdf renumbers on write, and an outline, reached from the
    /// catalogue before `/Pages`, numbers ahead of every page.
    private static func pageFingerprint(_ described: [String: Any]) -> [String] {
        ((described["pages"] as? [[String: Any]]) ?? []).map { page in
            let contents = (page["contents"] as? [Any] ?? []).count
            let images = (page["images"] as? [[String: Any]] ?? []).map { image in
                "\(image["width"] ?? "?")x\(image["height"] ?? "?")"
                    + "\(image["filter"] ?? "")"
            }.joined(separator: ",")
            return "\(page["pageposfrom1"] as? Int ?? -1):\(contents):\(images)"
        }
    }

    // MARK: - Page labels and the title — C48

    /// A qpdf JSON string as it should be written. qpdf writes a non-ASCII "u:"
    /// string in PDFDocEncoding and then reads it back as "b:" hex, so text goes
    /// in as UTF-16BE with its byte-order mark, which qpdf keeps byte for byte.
    static func qpdfString(_ s: String) -> String {
        guard s.hasPrefix("u:"), !s.dropFirst(2).allSatisfy(\.isASCII) else { return s }
        let bytes: [UInt8] = [0xFE, 0xFF] + String(s.dropFirst(2)).utf16.flatMap {
            [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        return "b:" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// What a qpdf JSON string says, so two spellings of one text compare equal.
    static func qpdfText(_ s: String) -> String {
        if s.hasPrefix("u:") { return "t:" + s.dropFirst(2) }
        let hex = Array(s.dropFirst(2).utf8)
        guard s.hasPrefix("b:"), hex.count % 2 == 0, hex.count >= 4 else { return s }
        let bytes: [UInt8] = stride(from: 0, to: hex.count, by: 2).compactMap {
            UInt8(String(decoding: hex[$0..<$0 + 2], as: UTF8.self), radix: 16) }
        guard bytes.count * 2 == hex.count, bytes[0] == 0xFE, bytes[1] == 0xFF,
              bytes.count % 2 == 0 else { return s }
        let units = stride(from: 2, to: bytes.count, by: 2).map {
            UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
        return "t:" + String(decoding: units, as: UTF16.self)
    }

    /// The `/Info` keys carried across: what Preview, Spotlight and Zotero show.
    static let carriedInfoKeys = ["/Title", "/Author", "/Subject", "/Keywords"]

    /// Writes `source`'s page labels and its title, author, subject and keywords
    /// onto a finished file, in place.
    ///
    /// C48. Nothing wrote them. A fully rebuilt document lost its printed numbers
    /// (Hobsbawm i-iv,1-320 became 1-324), a spliced one got qpdf's `{/St n}`
    /// with no style, which is an empty label, and every output had no title. The
    /// output has the source's pages in the source's order, so the source's
    /// number tree applies as it stands. It is copied from qpdf's own reading of
    /// it, not the source's objects, so a nested tree arrives flat; the values
    /// inside a label are not resolved, and `text` follows those. The same
    /// JSON-update route as `setOutline`, verified the same way before it
    /// replaces anything: labels and info read back as
    /// written, and every page's contents unchanged.
    static func carryDocumentInfo(from source: URL, password: String?, into file: URL,
                                  using qpdf: String,
                                  register: (Process) -> Void = { _ in }) throws {
        func json(_ url: URL, password: String? = nil, _ keys: [String],
                  objects: [String] = []) throws -> [String: Any] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: qpdf)
            var arguments = [url.path]
            if let password, !password.isEmpty { arguments.append("--password=\(password)") }
            process.arguments = arguments + ["--json=2", "--json-stream-data=none"]
                + keys.map { "--json-key=\($0)" } + objects.map { "--json-object=\($0)" }
            // Not a pipe: this reads the user's file, whose warnings can fill one
            // while stdout is being drained, and then both sides wait forever.
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            try process.run()
            register(process)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 || process.terminationStatus == 3,
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw Failure.documentInfoFailed("qpdf could not describe the file") }
            return parsed
        }
        /// A string value, followed if it is a reference: qpdf resolves neither a
        /// label's `/P` nor an `/Info` entry, and copying "9 0 R" into the output
        /// would point it at whatever object 9 is there.
        func text(_ raw: Any?, in url: URL, password: String? = nil) throws -> String? {
            guard let s = raw as? String else { return nil }
            if s.hasPrefix("u:") || s.hasPrefix("b:") { return s }
            guard s.hasSuffix(" R"), s.split(separator: " ").count == 3 else { return nil }
            let described = try json(url, password: password, ["qpdf"], objects: [s])
            let resolved = objects(described).flatMap { value($0.all, "obj:\(s)") } as? String
            return resolved.flatMap { $0.hasPrefix("u:") || $0.hasPrefix("b:") ? $0 : nil }
        }
        func objects(_ described: [String: Any]) -> (header: [String: Any], all: [String: Any])? {
            guard let pair = described["qpdf"] as? [Any], pair.count == 2,
                  let header = pair[0] as? [String: Any],
                  let all = pair[1] as? [String: Any] else { return nil }
            return (header, all)
        }
        func value(_ all: [String: Any], _ key: String) -> Any? {
            (all[key] as? [String: Any])?["value"]
        }
        /// The trailer's `/Info` as a dictionary, and its reference when it has one.
        func info(_ url: URL, password: String? = nil, trailer: [String: Any])
            throws -> (ref: String?, value: [String: Any]) {
            if let direct = trailer["/Info"] as? [String: Any] { return (nil, direct) }
            guard let ref = trailer["/Info"] as? String else { return (nil, [:]) }
            let described = try json(url, password: password, ["qpdf"], objects: [ref])
            return (ref, objects(described).flatMap {
                value($0.all, "obj:\(ref)") as? [String: Any] } ?? [:])
        }
        /// Reduced to what a label is, so the source and the output compare alike.
        func labels(_ described: [String: Any], in url: URL,
                    password: String? = nil) throws -> [[String: Any]] {
            try ((described["pagelabels"] as? [[String: Any]]) ?? []).map { entry in
                guard let index = entry["index"] as? Int,
                      let label = entry["label"] as? [String: Any] else {
                    throw Failure.documentInfoFailed("a page label is not the shape this expects")
                }
                var kept: [String: Any] = [:]
                if let style = label["/S"] as? String, style.hasPrefix("/") { kept["/S"] = style }
                if let start = label["/St"] as? Int { kept["/St"] = start }
                if label["/P"] != nil {
                    guard let prefix = try text(label["/P"], in: url, password: password) else {
                        throw Failure.documentInfoFailed("a page label's prefix is not a string")
                    }
                    kept["/P"] = qpdfText(prefix)
                }
                return ["index": index, "label": kept]
            }
        }

        // The source.
        let src = try json(source, password: password, ["pagelabels", "qpdf"],
                           objects: ["trailer"])
        let wantedLabels = try labels(src, in: source, password: password)
        guard let srcTrailer = objects(src).flatMap({ value($0.all, "trailer") })
                as? [String: Any] else {
            throw Failure.documentInfoFailed("qpdf's JSON is not the shape this expects")
        }
        // Strings only, and only non-empty ones: "u:" and "b:" are qpdf's text and
        // binary string markers, and a bare marker is an empty string. Held as
        // `qpdfText`, and written back through `qpdfString`.
        let srcInfo = try info(source, password: password, trailer: srcTrailer).value
        var carried: [String: String] = [:]
        for key in carriedInfoKeys {
            if let s = try text(srcInfo[key], in: source, password: password), s.count > 2 {
                carried[key] = qpdfText(s)
            }
        }
        func written(_ s: String) -> String {
            s.hasPrefix("t:") ? qpdfString("u:" + s.dropFirst(2)) : s
        }
        func carriedMatch(_ info: [String: Any]) -> Bool {
            carried.allSatisfy { (info[$0.key] as? String).map(qpdfText) == $0.value }
        }

        // The output.
        let before = try json(file, ["pages", "pagelabels", "qpdf"], objects: ["trailer"])
        guard let (header, all) = objects(before),
              var trailer = value(all, "trailer") as? [String: Any],
              let rootRef = trailer["/Root"] as? String else {
            throw Failure.documentInfoFailed("qpdf's JSON is not the shape this expects")
        }
        let (infoRef, outInfo) = try info(file, trailer: trailer)
        let haveLabels = try labels(before, in: file)
        let infoDone = carriedMatch(outInfo)
        if (haveLabels as NSArray).isEqual(to: wantedLabels), infoDone { return }

        guard var catalog = objects(try json(file, ["qpdf"], objects: [rootRef]))
                .flatMap({ value($0.all, "obj:\(rootRef)") }) as? [String: Any] else {
            throw Failure.documentInfoFailed("qpdf could not read the catalogue")
        }
        var patch: [String: Any] = [:]
        if wantedLabels.isEmpty {
            catalog.removeValue(forKey: "/PageLabels")
        } else {
            catalog["/PageLabels"] = ["/Nums": wantedLabels.flatMap { entry -> [Any] in
                var label = entry["label"] as? [String: Any] ?? [:]
                if let prefix = label["/P"] as? String { label["/P"] = written(prefix) }
                return [entry["index"]!, label]
            }]
        }
        patch["obj:\(rootRef)"] = ["value": catalog]
        if !infoDone {
            let merged = outInfo.merging(carried.mapValues(written)) { $1 }
            if let infoRef {
                patch["obj:\(infoRef)"] = ["value": merged]
            } else {
                let ref = "\((header["maxobjectid"] as? Int ?? 0) + 1) 0 R"
                patch["obj:\(ref)"] = ["value": merged]
                trailer["/Info"] = ref
                patch["trailer"] = ["value": trailer]
            }
        }

        let work = file.deletingLastPathComponent()
        let patchURL = work.appendingPathComponent("info-\(UUID().uuidString).json")
        let patched = work.appendingPathComponent("info-\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: patchURL)
            try? FileManager.default.removeItem(at: patched)
        }
        let document: [String: Any] = ["qpdf": [
            ["jsonversion": 2, "pdfversion": header["pdfversion"] ?? "1.4"], patch]]
        guard let body = try? JSONSerialization.data(withJSONObject: document),
              (try? body.write(to: patchURL)) != nil else {
            throw Failure.documentInfoFailed("could not write the update")
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
            throw Failure.documentInfoFailed(message.isEmpty
                ? "qpdf exited with code \(apply.terminationStatus)" : message)
        }

        let after = try json(patched, ["pages", "pagelabels", "qpdf"], objects: ["trailer"])
        guard pageFingerprint(after) == pageFingerprint(before) else {
            throw Failure.documentInfoFailed("the pages changed while the labels were written")
        }
        guard (try labels(after, in: patched) as NSArray).isEqual(to: wantedLabels) else {
            throw Failure.documentInfoFailed("the page labels did not read back as written")
        }
        guard let afterTrailer = objects(after).flatMap({ value($0.all, "trailer") })
                as? [String: Any],
              carriedMatch(try info(patched, trailer: afterTrailer).value) else {
            throw Failure.documentInfoFailed("the title did not read back as written")
        }

        // One step, so a failed swap cannot leave the finished file deleted.
        _ = try FileManager.default.replaceItemAt(file, withItemAt: patched)
    }

    /// C47. The finished file with its dictionaries packed into object streams,
    /// as the compact sources store theirs: Keyssar 184,799 -> 155,630 B, most of
    /// it the page, font and outline dictionaries this build writes out plain.
    /// Kept only when qpdf succeeds without a warning, every page's contents and
    /// images read back the same, and the file is smaller;
    /// otherwise the file is left as it was, since nothing in it is lost either way.
    static func packObjects(in file: URL, using qpdf: String,
                            register: (Process) -> Void = { _ in }) {
        let packed = file.deletingLastPathComponent()
            .appendingPathComponent("packed-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: packed) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: qpdf)
        process.arguments = ["--object-streams=generate", file.path, packed.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        register(process)
        process.waitUntilExit()
        func size(_ url: URL) -> Int {
            ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0
        }
        // Every page's contents and images, as `carryDocumentInfo` checks its own
        // rewrite: a page count alone would pass a page qpdf had to repair.
        func fingerprint(_ url: URL) -> [String]? {
            guard let out = try? runQPDF([url.path, "--json=2", "--json-stream-data=none",
                                          "--json-key=pages"], using: qpdf, register: register),
                  let described = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any]
            else { return nil }
            return pageFingerprint(described)
        }
        guard process.terminationStatus == 0,
              size(packed) > 0, size(packed) < size(file),
              let before = CGPDFDocument(file as CFURL)?.numberOfPages,
              CGPDFDocument(packed as CFURL)?.numberOfPages == before,
              let was = fingerprint(file), was.count == before, fingerprint(packed) == was
        else { return }
        _ = try? FileManager.default.replaceItemAt(file, withItemAt: packed)
    }
}
