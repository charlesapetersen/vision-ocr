import Foundation

/// Carries a reader's own marks — highlights, notes, ink, stamps — from the original
/// document onto the rebuilt one.
///
/// **Why this exists.** The rebuild turns every page into an image, and an annotation
/// is not part of the page's content stream: it is a separate object hanging off
/// `/Annots`. So the rebuild drops every one of them, silently. Measured over a 1-in-16
/// sample of a real library — 1,006 documents — **91 carry a reader's own mark (9.0%),
/// 4,903 marks in total**, the heaviest single file holding 227. The same rate appears
/// in the 232-document corpus (21, 9.1%). Until this existed, any file with marks had
/// to be excluded from a re-OCR sweep by hand, which meant either skipping a tenth of
/// the library or destroying somebody's scholarship.
///
/// **Why qpdf and not PDFKit.** `PDFDocument.write(to:)` re-encodes every image stream,
/// and the whole point of the rebuild is size. Measured on this app's own JBIG2 output:
/// Hayek 35.42 → 144.68 MB (4.08x), Boltanski 24.38 → 82.89 (3.40x), Countryman
/// 25.30 → 57.91 (2.29x), Schwaller 33.52 → 50.88 (1.52x). Text survives to the
/// character, so the entire loss is size. qpdf's JSON round-trip is byte-exact by
/// comparison — a 25,565,129-byte file comes back 25,565,129 — because the streams are
/// carried as opaque files and never decoded. That is what makes the object surgery
/// below affordable: qpdf does the xref, the `/Length` values and the object plumbing,
/// which is the "substantial piece of hand-written PDF" this was once refused for.
///
/// **Page *i* of the output is page *i* of the input — but its coordinate space is not
/// always the same one, and assuming it was put marks in the wrong place.**
///
/// The first version of this file said "no remapping is needed", cited 0 media-box and 0
/// rotation mismatches across the corpus, and asserted exact `/Rect` equality on the
/// strength of it. That was wrong twice over, and the check could not see either fault
/// because it compared the copied `/Rect` against the source `/Rect` — it agreed with
/// itself by construction, which is the shape CONTRIBUTING §4b warns about.
///
/// What `flatten` actually does is `Flattener.boxSize`, which returns
/// `CGRect(origin: .zero, …)` and **swaps width and height for a quarter-turn**. So:
///
/// - **A media box that does not start at the origin is translated to it.** Measured on
///   `Cohen_1990_Making a New Deal` page 6, media box `[0 -24.69 408 588]`: a highlight
///   copied verbatim lands **24.7 points low**, one and a half lines, which is exactly
///   the "highlight forty points low" the specification said would misrepresent
///   somebody's scholarship. **105 of 233 corpus documents** have an offset media box.
///   This is corrected, by translating every page-space geometry array in the copied
///   graph — see `pageSpaceGeometryKeys`.
/// - **A rotated page is a different user space altogether**, and a mark copied onto one
///   can land off the sheet entirely: measured on a 90° fixture, the highlight
///   disappeared. Rotation is **refused** rather than corrected. Getting it wrong is
///   silent misplacement, the correction would have to reach `/QuadPoints`, `/InkList`,
///   `/Vertices` and each appearance stream's own `/Matrix`, and 475 of 16,987 corpus
///   pages are rotated while **none of the 21 marked documents has a rotated page
///   carrying a mark**. So the case is real, rare, and not worth guessing at: the
///   document fails and says why, per the specification's "an unverifiable transplant
///   means that candidate is skipped and listed".
///
/// The geometry check therefore compares against the *transformed* rectangle, and the
/// independent check is `Tools/score-annotations.swift`, which renders both files and
/// compares where each mark's ink actually falls.
enum Annotations {

    /// The marks a reader makes, and nothing else.
    ///
    /// **`Widget` is excluded deliberately.** Form fields are not a reader's marks, and
    /// copying one drags in the whole `/AcroForm` graph — the field tree, the default
    /// resources, the appearance dictionaries — for something nobody highlighted.
    ///
    /// **`Link` is excluded because it is platform furniture**, not scholarship: 3,991
    /// of the corpus's 4,867 annotations are links left behind by JSTOR and ProQuest
    /// wrappers, pointing at session URLs that have long since expired. v1 drops them.
    ///
    /// Both exclusions are *reported* rather than silent, which is invariant 1 applied
    /// to a reader's marks: the caller is told what was left behind, by type and page.
    static let copiedSubtypes: Set<String> = [
        "/Highlight", "/Underline", "/StrikeOut", "/Squiggly", "/Text", "/FreeText",
        "/Ink", "/Stamp", "/Square", "/Circle", "/Polygon", "/PolyLine", "/Caret",
        "/FileAttachment",
        // `/Line` was missing from the list TODO.md specified, next to `/Polygon` and
        // `/PolyLine`, and the omission looks accidental rather than decided: an arrow
        // drawn beside a paragraph is a reader's mark by any reading of the phrase.
        // Added deliberately, and recorded here so it is not mistaken for the spec.
        "/Line",
    ]

    /// The annotation keys whose numbers live in the *page's* coordinate space, and so
    /// have to move when the page's origin does.
    ///
    /// Each holds x,y pairs in order, so translating means adding dx to every even index
    /// and dy to every odd one. `/InkList` is one level deeper — an array of such arrays.
    ///
    /// **`/BBox` and `/Matrix` are deliberately absent.** An appearance stream lives in
    /// *form* space, and a viewer maps its transformed `/BBox` onto the annotation's
    /// `/Rect`; translating `/Rect` therefore carries the appearance with it, and
    /// translating the form as well would move it twice. This is why the stamps — which
    /// are nothing but an appearance stream — come out right with no special handling.
    static let pageSpaceGeometryKeys: Set<String> = [
        "/Rect", "/QuadPoints", "/Vertices", "/L", "/CL",
    ]
    /// The same, one level of nesting deeper.
    static let nestedPageSpaceGeometryKeys: Set<String> = ["/InkList"]

    /// What a transplant did, and what it refused to do.
    struct Report {
        /// Marks copied, by subtype.
        var copied: [String: Int] = [:]
        /// Marks left behind, by subtype — links, form fields, anything unrecognised.
        var dropped: [String: Int] = [:]
        /// Pages that gained at least one mark.
        var pagesTouched = 0
        /// References inside copied objects that pointed at something not copied and
        /// were therefore removed rather than left dangling.
        var prunedReferences = 0

        var copiedTotal: Int { copied.values.reduce(0, +) }
        var droppedTotal: Int { dropped.values.reduce(0, +) }

        /// One line for the run log, listing types rather than a bare total: "3
        /// highlights" and "3 stamps" are worth different amounts of trust.
        var summary: String {
            func list(_ counts: [String: Int]) -> String {
                counts.sorted { $0.key < $1.key }
                    .map { "\($0.value) \($0.key.dropFirst())" }
                    .joined(separator: ", ")
            }
            var parts: [String] = []
            if copiedTotal > 0 {
                parts.append("carried \(copiedTotal) mark\(copiedTotal == 1 ? "" : "s")"
                             + " onto \(pagesTouched) page\(pagesTouched == 1 ? "" : "s")"
                             + " (\(list(copied)))")
            } else {
                parts.append("no reader's marks to carry")
            }
            if droppedTotal > 0 { parts.append("left \(list(dropped))") }
            if prunedReferences > 0 { parts.append("\(prunedReferences) dangling reference(s) removed") }
            return parts.joined(separator: "; ")
        }
    }

    enum Failure: LocalizedError {
        /// Cancelled between passes. Distinct from a failure so the caller can report it
        /// as the cancellation it is rather than as a broken document — the same
        /// distinction the JBIG2 route had to learn.
        case cancelled
        case qpdfMissing
        case qpdfFailed(stage: String, message: String)
        case unreadableJSON(stage: String)
        case pageCountChanged(before: Int, after: Int)
        /// The verification bar. Any of these means nothing is published.
        ///
        /// Carries the subtype breakdown rather than two integers: "12 against 14" says
        /// nothing about what to look at, and the first time this fired the answer was
        /// visible immediately once the types were listed.
        case countMismatch(page: Int, expected: [String], found: [String])
        case geometryMismatch(page: Int, subtype: String, expected: [Double], found: [Double])
        /// A mark whose `/Rect` cannot be read is a mark whose position cannot be
        /// checked, so it is refused rather than carried unverified.
        case unreadableRectangle(page: Int, subtype: String)
        /// A rotated page's rebuild has a different user space, and correcting a mark
        /// into it is not attempted. See the type's doc comment.
        case rotatedPage(page: Int, rotation: Int, marks: Int)
        /// An entry in `/Annots` that is not a reference to an object cannot be copied,
        /// and a mark that cannot be copied is not passed over in silence.
        case inlineAnnotation(page: Int)
        /// qpdf preserves generation numbers and this code only understands generation
        /// 0. Resolving `4 1 R` as `4 0 R` would graft an unrelated object into a
        /// mark's graph, so it is refused instead.
        case unsupportedGeneration(page: Int, reference: String)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return "Cancelled."
            case .qpdfMissing:
                return "qpdf is needed to carry annotations across and was not found."
            case .qpdfFailed(let stage, let message):
                return "qpdf failed while \(stage): \(message)"
            case .unreadableJSON(let stage):
                return "Could not read qpdf's description of the \(stage)."
            case .pageCountChanged(let before, let after):
                return "Carrying annotations changed the page count from \(before) to \(after)."
            case .countMismatch(let page, let expected, let found):
                func tally(_ types: [String]) -> String {
                    Dictionary(grouping: types, by: { $0 }).sorted { $0.key < $1.key }
                        .map { "\($0.value.count) \($0.key.dropFirst())" }
                        .joined(separator: ", ")
                }
                return "Page \(page) should carry \(expected.count) of the reader's marks "
                     + "(\(tally(expected))) and carries \(found.count) "
                     + "(\(tally(found))); nothing was written."
            case .geometryMismatch(let page, let subtype, let expected, let found):
                return "A \(subtype.dropFirst()) on page \(page) moved: expected "
                     + "\(expected) and got \(found); nothing was written."
            case .unreadableRectangle(let page, let subtype):
                return "Could not read where a \(subtype.dropFirst()) sits on page "
                     + "\(page), so it could not be checked; nothing was written."
            case .rotatedPage(let page, let rotation, let marks):
                return "Page \(page) is rotated \(rotation)° and carries "
                     + "\(marks) of the reader's mark\(marks == 1 ? "" : "s"). The "
                     + "rebuilt page uses a different coordinate space, and moving a mark "
                     + "into it is not attempted rather than risked; nothing was written."
            case .inlineAnnotation(let page):
                return "Page \(page) carries a mark written directly into the page "
                     + "rather than as its own object, which cannot be copied; nothing "
                     + "was written."
            case .unsupportedGeneration(let page, let reference):
                return "Page \(page) refers to \(reference), and only generation 0 "
                     + "objects can be carried; nothing was written."
            }
        }
    }

    // MARK: - The JSON surface

    /// qpdf's `--json-output=2` shape, reduced to what this needs.
    ///
    /// Objects are keyed `"obj:N 0 R"`, and their bodies are either `{"value": …}` or
    /// `{"stream": {"dict": …, "datafile": …}}`. A reference is the *string* `"N 0 R"`,
    /// which is why every rewrite below is a string substitution on a known pattern
    /// rather than a type change: qpdf will read back exactly what it wrote.
    private struct Document {
        var header: [String: Any]
        var objects: [String: Any]
        let url: URL
        let streamDirectory: URL

        static func key(_ id: Int) -> String { "obj:\(id) 0 R" }
        static func reference(_ id: Int) -> String { "\(id) 0 R" }

        /// The object id a reference names, or nil if the value is not a reference.
        ///
        /// **Generation 0 only, and non-zero is a refusal rather than a silent
        /// approximation.** qpdf's JSON preserves generations — an incrementally-updated
        /// file really does produce keys like `obj:4 1 R` — and an earlier version of this
        /// threw the generation away, so `4 1 R` resolved to `obj:4 0 R`. In a file that
        /// contains both, that grafts an unrelated object into a mark's graph: the wrong
        /// appearance stream, with the `/Rect` check passing. `nonZeroGeneration` says
        /// which it was so the caller can refuse.
        static func id(ofReference value: Any) -> Int? {
            guard let string = value as? String else { return nil }
            let parts = string.split(separator: " ")
            guard parts.count == 3, parts[2] == "R", let id = Int(parts[0]),
                  parts[1] == "0" else { return nil }
            return id
        }

        /// True when `value` is a reference this code cannot follow, as opposed to not a
        /// reference at all. The two must not be confused: one is a refusal and the other
        /// is an inline value.
        static func isNonZeroGeneration(_ value: Any) -> Bool {
            guard let string = value as? String else { return false }
            let parts = string.split(separator: " ")
            return parts.count == 3 && parts[2] == "R" && Int(parts[0]) != nil
                && parts[1] != "0"
        }

        func body(_ id: Int) -> [String: Any]? {
            objects[Document.key(id)] as? [String: Any]
        }
        /// The dictionary of an object, whether it is a plain value or a stream.
        func dictionary(_ id: Int) -> [String: Any]? {
            guard let body = body(id) else { return nil }
            if let value = body["value"] as? [String: Any] { return value }
            if let stream = body["stream"] as? [String: Any] {
                return stream["dict"] as? [String: Any]
            }
            return nil
        }
        func array(_ id: Int) -> [Any]? {
            (body(id)?["value"]) as? [Any]
        }

        /// Follow a value that may be a reference to an array, or may be one already.
        func resolveArray(_ value: Any?) -> [Any]? {
            guard let value else { return nil }
            if let direct = value as? [Any] { return direct }
            if let id = Document.id(ofReference: value) { return array(id) }
            return nil
        }

        /// An annotation's rectangle, whether it is written inline or as its own object.
        ///
        /// **`/Rect` really is indirect in the wild**, and assuming otherwise was a
        /// defect this file's own verification caught: on page 11 of
        /// `Hyman_2012_Rethinking the Postwar Corporation`, two of fourteen annotations
        /// carry `/Rect` as `890 0 R` and `885 0 R`. A cast straight to an array
        /// silently skipped them, so they were copied but never checked, and the count
        /// check then found 14 where 12 were expected — correctly. Every number inside
        /// may be indirect too, so each element is resolved on its own.
        func rect(of dictionary: [String: Any]) -> [Double]? {
            guard let raw = resolveArray(dictionary["/Rect"]), raw.count == 4 else { return nil }
            var out: [Double] = []
            for element in raw {
                if let number = element as? NSNumber { out.append(number.doubleValue); continue }
                if let id = Document.id(ofReference: element),
                   let number = body(id)?["value"] as? NSNumber {
                    out.append(number.doubleValue); continue
                }
                return nil
            }
            return out
        }
    }

    /// Move every page-space number in a copied annotation graph by `dx`, `dy`.
    ///
    /// Applied by key name, because a PDF number carries no units and there is no other
    /// way to tell a coordinate from a colour component or a border width. The keys are
    /// listed on `pageSpaceGeometryKeys`, with the reason `/BBox` and `/Matrix` are not
    /// among them.
    private static func translated(_ value: Any, key: String?,
                                   dx: Double, dy: Double) -> Any {
        func shiftPairs(_ array: [Any]) -> [Any] {
            array.enumerated().map { index, element in
                guard let number = element as? NSNumber else { return element }
                return number.doubleValue + (index % 2 == 0 ? dx : dy)
            }
        }
        if let key, pageSpaceGeometryKeys.contains(key), let array = value as? [Any] {
            return shiftPairs(array)
        }
        if let key, nestedPageSpaceGeometryKeys.contains(key), let outer = value as? [Any] {
            return outer.map { inner in
                (inner as? [Any]).map { shiftPairs($0) as Any } ?? inner
            }
        }
        return value
    }

    /// Every page object id, in reading order.
    ///
    /// Walked from `/Root` rather than taken from qpdf's `calledgetallpages` helper,
    /// because `--json-output` does not run it, and **cycle-safe with a visited set**:
    /// a malformed `/Kids` that points back at its own parent would otherwise recurse
    /// until the stack ran out, on a file this app is expected to reject rather than
    /// crash on.
    private static func pageOrder(_ document: Document) -> [Int] {
        guard let trailer = document.objects["trailer"] as? [String: Any],
              let value = trailer["value"] as? [String: Any],
              let rootID = Document.id(ofReference: value["/Root"] ?? ""),
              let root = document.dictionary(rootID),
              let pagesID = Document.id(ofReference: root["/Pages"] ?? "") else { return [] }
        var pages: [Int] = []
        var seen = Set<Int>()
        func walk(_ id: Int) {
            guard seen.insert(id).inserted, let node = document.dictionary(id) else { return }
            if node["/Type"] as? String == "/Page" { pages.append(id); return }
            for kid in document.resolveArray(node["/Kids"]) ?? [] {
                if let kidID = Document.id(ofReference: kid) { walk(kidID) }
            }
        }
        walk(pagesID)
        return pages
    }

    /// Does the rectangle reader follow an indirect `/Rect`, and an indirect number
    /// inside one?
    ///
    /// Asserted directly rather than through a document, because **PDFKit cannot write
    /// an indirect `/Rect`** and the case is therefore unreachable from a fixture built
    /// in this repo — while being present in real material: two of the fourteen
    /// annotations on page 11 of `Hyman_2012_Rethinking the Postwar Corporation` carry
    /// theirs as `890 0 R` and `885 0 R`. The first version of this file cast straight to
    /// an array, so those two were copied without being recorded as expected, and the
    /// count check fired with 14 against 12. It was right to.
    ///
    /// This is the shape `mrcBoundIsWithinTheRenderOne` uses: a property the product
    /// evaluates, so a test cannot agree with a replica of the thing under test.
    static var resolvesIndirectRectangles: Bool {
        let objects: [String: Any] = [
            // The annotation, with its rectangle one indirection away.
            "obj:1 0 R": ["value": ["/Subtype": "/Text", "/Rect": "2 0 R"]],
            // The rectangle, with one of its four numbers a further indirection away.
            "obj:2 0 R": ["value": [1.5, 2.5, "3 0 R", 4.5]],
            "obj:3 0 R": ["value": 3.5],
        ]
        let document = Document(header: [:], objects: objects,
                                url: URL(fileURLWithPath: "/"),
                                streamDirectory: URL(fileURLWithPath: "/"))
        guard let annotation = document.dictionary(1) else { return false }
        guard document.rect(of: annotation) == [1.5, 2.5, 3.5, 4.5] else { return false }
        // And a rectangle that cannot be resolved must come back nil rather than a
        // plausible-looking partial answer, or the caller cannot tell it apart from a
        // mark that really does sit at the origin.
        let broken: [String: Any] = [
            "obj:1 0 R": ["value": ["/Subtype": "/Text", "/Rect": "9 0 R"]],
        ]
        let second = Document(header: [:], objects: broken,
                              url: URL(fileURLWithPath: "/"),
                              streamDirectory: URL(fileURLWithPath: "/"))
        guard let other = second.dictionary(1) else { return false }
        return second.rect(of: other) == nil
    }

    // MARK: - Running qpdf

    /// `register` hands the child to the batch's `RunControl`, exactly as the jbig2 and
    /// qpdf children on the compression route are handed over.
    ///
    /// Without it these three full-document passes were uninterruptible: Cancel could not
    /// reach them, and quitting the app orphaned them. `Runner.stop` escalates SIGTERM to
    /// SIGKILL against the child's *process group*, which is the mechanism R21 exists for.
    private static func run(_ qpdf: String, _ arguments: [String], stage: String,
                            register: ((Process) -> Void)?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: qpdf)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        // Not a Pipe: nothing drains standard output, and an undrained pipe that fills up
        // blocks the child forever. qpdf writes its result to a file and says nothing on
        // stdout today, so a pipe was a hazard with no purpose.
        process.standardOutput = FileHandle.nullDevice
        // Read before waiting: a pipe that fills up blocks the child forever, and
        // qpdf is chatty about warnings on the files this app is given.
        try process.run()
        register?(process)
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // qpdf exits 3 for warnings — "operation succeeded with warnings" — and those
        // are routine on library scans. Only 0 and 3 are success.
        guard process.terminationStatus == 0 || process.terminationStatus == 3 else {
            let message = String(data: data, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw Failure.qpdfFailed(stage: stage,
                                     message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func read(_ url: URL, streamDirectory: URL) throws -> Document {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pair = root["qpdf"] as? [Any], pair.count == 2,
              let header = pair[0] as? [String: Any],
              let objects = pair[1] as? [String: Any]
        else { throw Failure.unreadableJSON(stage: url.lastPathComponent) }
        return Document(header: header, objects: objects, url: url,
                        streamDirectory: streamDirectory)
    }

    // MARK: - The transplant

    /// Copy the reader's marks from `source` onto `staged`, in place.
    ///
    /// Throws rather than degrading. A transplant that cannot be *verified* must not be
    /// published: a file whose marks were silently dropped is worse than a file left
    /// alone, and a file whose highlights have moved forty points misrepresents
    /// somebody's reading of it. The caller's contract is therefore "publish nothing and
    /// report it" — which is why the checks at the end are throws and not warnings.
    @discardableResult
    static func transplant(from source: URL, into staged: URL, password: String?,
                           qpdf: String?, scratch: URL,
                           isCancelled: () -> Bool = { false },
                           register: ((Process) -> Void)? = nil) throws -> Report {
        guard let qpdf else { throw Failure.qpdfMissing }
        let work = scratch.appendingPathComponent("annots-\(UUID().uuidString)")
        let sourceStreams = work.appendingPathComponent("src")
        let stagedStreams = work.appendingPathComponent("out")
        for directory in [work, sourceStreams, stagedStreams] {
            try? FileManager.default.createDirectory(at: directory,
                                                     withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: work) }

        // **Ask the cheap question first: does this document have any marks at all?**
        //
        // `--json-stream-data=none` describes the object graph without writing one file
        // per stream, so this pass costs a fraction of the two below. It matters because
        // of what the numbers say: **91% of documents carry no reader's marks**, and
        // without this probe every one of them paid two full stream dumps — every image
        // stream of the original *and* of the finished file written out to disk — before
        // discovering there was nothing to do. On a sweep of 1,053 files that is the
        // difference between a feature that can be left on and one that cannot.
        // The password goes in a file, not in argv.
        //
        // An argv element is visible in `ps` to every local user for as long as the child
        // runs, and this is the only place in the app that would hand a user's document
        // password to a subprocess. `--password-file` reads it from a path instead; the
        // file lives in the per-run scratch directory that is deleted on the way out, and
        // is written 0600.
        var passwordFile: URL?
        if let password, !password.isEmpty {
            let path = work.appendingPathComponent("pw")
            if (try? Data(password.utf8).write(to: path)) != nil {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                       ofItemAtPath: path.path)
                passwordFile = path
            }
        }
        func withPassword(_ arguments: [String]) -> [String] {
            guard let passwordFile else { return arguments }
            return ["--password-file=" + passwordFile.path] + arguments
        }

        let probeJSON = work.appendingPathComponent("probe.json")
        var probeArguments = ["--json-output=2", "--json-stream-data=none"]
        probeArguments += [source.path, probeJSON.path]
        try run(qpdf, withPassword(probeArguments), stage: "looking for marks",
                register: register)
        let probe = try read(probeJSON, streamDirectory: work)
        var anyMarks = false
        for pageID in pageOrder(probe) {
            guard let dictionary = probe.dictionary(pageID),
                  let annots = probe.resolveArray(dictionary["/Annots"]) else { continue }
            for entry in annots {
                // An inline dictionary or an unfollowable generation is *not* "no marks":
                // both are refusals, and they are diagnosed properly by the full pass
                // below rather than being quietly skipped here.
                if !(entry is String) { anyMarks = true; break }
                if Document.isNonZeroGeneration(entry) { anyMarks = true; break }
                guard let id = Document.id(ofReference: entry),
                      let annotation = probe.dictionary(id),
                      let subtype = annotation["/Subtype"] as? String else { continue }
                if copiedSubtypes.contains(subtype) { anyMarks = true; break }
            }
            if anyMarks { break }
        }
        // Nothing to carry, and nothing was written. The two exclusions are not reported
        // here on purpose: a document with only links and form fields has no reader's
        // marks, and saying "left 3,991 Links" about every JSTOR download would bury the
        // one line that matters on the file that does have marks.
        guard anyMarks else { return Report() }
        if isCancelled() { throw Failure.cancelled }

        let sourceJSON = work.appendingPathComponent("source.json")
        let stagedJSON = work.appendingPathComponent("staged.json")
        let sourceArguments = ["--json-output=2", "--json-stream-data=file",
                               "--json-stream-prefix=" + sourceStreams.path + "/s",
                               source.path, sourceJSON.path]
        try run(qpdf, withPassword(sourceArguments), stage: "reading the original",
                register: register)
        if isCancelled() { throw Failure.cancelled }
        try run(qpdf, ["--json-output=2", "--json-stream-data=file",
                       "--json-stream-prefix=" + stagedStreams.path + "/s",
                       staged.path, stagedJSON.path],
                stage: "reading the rebuilt file", register: register)
        if isCancelled() { throw Failure.cancelled }

        let from = try read(sourceJSON, streamDirectory: sourceStreams)
        var into = try read(stagedJSON, streamDirectory: stagedStreams)

        let sourcePages = pageOrder(from)
        let stagedPages = pageOrder(into)
        guard sourcePages.count == stagedPages.count else {
            throw Failure.pageCountChanged(before: sourcePages.count, after: stagedPages.count)
        }

        var report = Report()
        // Fresh ids start above anything the *staged* document uses, which is all that
        // is needed: every reference carried across is renumbered into this range, so the
        // source's numbering is irrelevant. `maxobjectid` is qpdf's own high-water mark,
        // and the object table is scanned as well in case a file numbers higher than it
        // claims.
        var nextID = max((into.header["maxobjectid"] as? Int) ?? 0,
                         into.objects.keys.compactMap { key -> Int in
                             guard key.hasPrefix("obj:") else { return 0 }
                             return Int(key.dropFirst(4).split(separator: " ").first ?? "") ?? 0
                         }.max() ?? 0) + 1

        /// What each copied annotation should look like afterwards, for the checks.
        var expected: [(page: Int, subtype: String, rect: [Double])] = []

        for (index, sourcePage) in sourcePages.enumerated() {
            let stagedPage = stagedPages[index]
            guard let sourceDictionary = from.dictionary(sourcePage),
                  let annots = from.resolveArray(sourceDictionary["/Annots"]),
                  !annots.isEmpty else { continue }

            // How many of the marks on this page are ones we would carry. Computed before
            // anything is copied, so a page that is refused below is refused for a reason
            // the message can state.
            let wantedHere = annots.filter { entry in
                guard let id = Document.id(ofReference: entry),
                      let dictionary = from.dictionary(id),
                      let subtype = dictionary["/Subtype"] as? String else { return false }
                return copiedSubtypes.contains(subtype)
            }.count

            // `flatten` bakes rotation into the raster, so the rebuilt page's user space
            // is not the source's. Refused rather than guessed at — see the type's doc
            // comment. A rotated page carrying nothing we would copy is not a problem.
            let rotation = ((((sourceDictionary["/Rotate"] as? NSNumber)?.intValue ?? 0)
                             % 360) + 360) % 360
            if rotation != 0, wantedHere > 0 {
                throw Failure.rotatedPage(page: index + 1, rotation: rotation,
                                          marks: wantedHere)
            }

            // …and it moves the media box to the origin, so every page-space coordinate
            // in a copied mark moves with it. Zero for most documents; -24.69 points on
            // `Cohen_1990` page 6, which is a line and a half.
            var dx = 0.0, dy = 0.0
            if let box = from.resolveArray(sourceDictionary["/MediaBox"]), box.count == 4 {
                let numbers = box.compactMap { element -> Double? in
                    if let n = element as? NSNumber { return n.doubleValue }
                    if let id = Document.id(ofReference: element),
                       let n = from.body(id)?["value"] as? NSNumber { return n.doubleValue }
                    return nil
                }
                if numbers.count == 4 {
                    dx = -min(numbers[0], numbers[2])
                    dy = -min(numbers[1], numbers[3])
                }
            }

            var carried: [String] = []
            for entry in annots {
                // A mark written straight into `/Annots` rather than as its own object
                // cannot be copied by id. Refused loudly: skipping it would drop a mark
                // without it ever reaching `expected`, so no later check could notice.
                if Document.isNonZeroGeneration(entry) {
                    throw Failure.unsupportedGeneration(page: index + 1,
                                                        reference: (entry as? String) ?? "?")
                }
                if !(entry is String) { throw Failure.inlineAnnotation(page: index + 1) }
                guard let annotationID = Document.id(ofReference: entry),
                      let annotation = from.dictionary(annotationID) else { continue }
                let subtype = (annotation["/Subtype"] as? String) ?? "/Unknown"
                guard copiedSubtypes.contains(subtype) else {
                    report.dropped[subtype, default: 0] += 1
                    continue
                }
                // Copy the transitive closure, then point the copy at this document's
                // page rather than the original's.
                var mapping: [Int: Int] = [:]
                let newID = copy(annotationID, from: from, into: &into, mapping: &mapping,
                                 nextID: &nextID, report: &report,
                                 stagedPage: stagedPage, sourcePages: Set(sourcePages),
                                 dx: dx, dy: dy)
                guard let newID else { continue }
                carried.append(Document.reference(newID))
                report.copied[subtype, default: 0] += 1
                // A mark whose rectangle cannot be read cannot be checked, and an
                // unverifiable transplant does not get published. Refusing here rather
                // than skipping is the whole difference: skipping is what made the
                // count check fire on Hyman page 11, because a copied mark was left out
                // of `expected` and the check was right to notice.
                guard let rect = from.rect(of: annotation) else {
                    throw Failure.unreadableRectangle(page: index + 1, subtype: subtype)
                }
                // The *transformed* rectangle, which is what should be in the output.
                // Comparing against the source's would be comparing the copy with the
                // thing it was copied from, which is how the origin shift went unseen.
                expected.append((page: index + 1, subtype: subtype,
                                 rect: [rect[0] + dx, rect[1] + dy,
                                        rect[2] + dx, rect[3] + dy]))
            }
            guard !carried.isEmpty else { continue }
            report.pagesTouched += 1
            append(carried, toAnnotsOf: stagedPage, in: &into, nextID: &nextID)
        }

        guard report.copiedTotal > 0 else { return report }

        // Write it back and let qpdf rebuild the object plumbing.
        let editedJSON = work.appendingPathComponent("edited.json")
        let rebuilt = work.appendingPathComponent("rebuilt.pdf")
        let payload: [String: Any] = ["qpdf": [into.header, into.objects]]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            throw Failure.unreadableJSON(stage: "edited description")
        }
        try data.write(to: editedJSON)
        try run(qpdf, ["--json-input", editedJSON.path, rebuilt.path],
                stage: "writing the annotated file", register: register)
        if isCancelled() { throw Failure.cancelled }

        // MARK: The verification bar
        //
        // Read the *rebuilt file*, not the JSON that was written: the check has to
        // cover qpdf's interpretation of the edit, not the edit. Counting the objects
        // that were added would agree with itself by construction, which is the shape
        // BUGS.md U26 and the `willRebuild` duplicate both had.
        let verifyStreams = work.appendingPathComponent("verify")
        try? FileManager.default.createDirectory(at: verifyStreams,
                                                 withIntermediateDirectories: true)
        let verifyJSON = work.appendingPathComponent("verify.json")
        try run(qpdf, ["--json-output=2", "--json-stream-data=file",
                       "--json-stream-prefix=" + verifyStreams.path + "/s",
                       rebuilt.path, verifyJSON.path],
                stage: "checking the annotated file", register: register)
        let check = try read(verifyJSON, streamDirectory: verifyStreams)
        let checkPages = pageOrder(check)
        guard checkPages.count == stagedPages.count else {
            throw Failure.pageCountChanged(before: stagedPages.count, after: checkPages.count)
        }

        // Per page: every mark that should be there is there, and its rectangle is
        // exactly where it was. Exact, not approximate — see the type's doc comment.
        for (index, pageID) in checkPages.enumerated() {
            let wanted = expected.filter { $0.page == index + 1 }
            let present = (check.dictionary(pageID)?["/Annots"])
                .flatMap { check.resolveArray($0) } ?? []
            var found: [(subtype: String, rect: [Double])] = []
            for entry in present {
                guard let id = Document.id(ofReference: entry),
                      let dictionary = check.dictionary(id),
                      let subtype = dictionary["/Subtype"] as? String,
                      copiedSubtypes.contains(subtype) else { continue }
                found.append((subtype, check.rect(of: dictionary) ?? []))
            }
            // Both directions. `wanted.isEmpty` used to `continue` here, so a mark that
            // appeared on a page nothing was copied to would never be looked at — not
            // reachable from the pipeline, where a staged rebuild starts with no
            // annotations at all, but the asymmetry was doing no work.
            guard found.count == wanted.count else {
                throw Failure.countMismatch(page: index + 1,
                                            expected: wanted.map { $0.subtype },
                                            found: found.map { $0.subtype })
            }
            if wanted.isEmpty { continue }
            // Match by subtype and rectangle rather than by position in the array:
            // qpdf is entitled to reorder `/Annots`, and asserting the order would be
            // asserting an implementation detail of the writer.
            var remaining = found
            for want in wanted {
                guard let hit = remaining.firstIndex(where: {
                    $0.subtype == want.subtype && $0.rect == want.rect
                }) else {
                    let near = remaining.first { $0.subtype == want.subtype }
                    throw Failure.geometryMismatch(page: want.page, subtype: want.subtype,
                                                   expected: want.rect,
                                                   found: near?.rect ?? [])
                }
                remaining.remove(at: hit)
            }
        }

        // Only now does the staged file change. Everything above worked on copies, so
        // a throw anywhere leaves the caller's file exactly as it was — which is what
        // lets the caller treat a failure as "publish nothing" rather than as a
        // half-annotated document.
        _ = try? FileManager.default.removeItem(at: staged)
        try FileManager.default.moveItem(at: rebuilt, to: staged)
        return report
    }

    /// Copy one object and everything it reaches, renumbering as it goes.
    ///
    /// Cycle-safe by allocating the new id **before** recursing: `/Popup` points at an
    /// annotation whose `/Parent` points back, so a depth-first copy that allocated on
    /// the way out would not terminate.
    ///
    /// Two kinds of reference are deliberately not followed:
    ///
    /// - **the page**, whether reached through `/P` or `/Parent`. Following it would
    ///   drag the entire page tree — and with it the source's content streams and
    ///   resources — into a file whose whole purpose is to be smaller. `/P` is
    ///   rewritten to this document's page; any other reference to a page is pruned.
    /// - **anything unresolvable**. A reference whose target is not in the source's
    ///   object table is removed rather than carried, because a dangling reference is a
    ///   broken PDF and qpdf would be within its rights to reject the whole file.
    private static func copy(_ id: Int, from: Document, into: inout Document,
                             mapping: inout [Int: Int], nextID: inout Int,
                             report: inout Report, stagedPage: Int,
                             sourcePages: Set<Int>, dx: Double, dy: Double) -> Int? {
        if let already = mapping[id] { return already }
        guard let body = from.body(id) else { return nil }
        let newID = nextID
        nextID += 1
        mapping[id] = newID

        /// Rewrite every reference inside a value.
        func rewrite(_ value: Any, key: String?) -> Any? {
            if let referenced = Document.id(ofReference: value) {
                // `/P` is the annotation's back-reference to its page, and it must
                // point at *this* document's page object.
                if key == "/P", sourcePages.contains(referenced) {
                    return Document.reference(stagedPage)
                }
                if sourcePages.contains(referenced) {
                    report.prunedReferences += 1
                    return nil
                }
                guard let copied = copy(referenced, from: from, into: &into,
                                        mapping: &mapping, nextID: &nextID,
                                        report: &report, stagedPage: stagedPage,
                                        sourcePages: sourcePages, dx: dx, dy: dy) else {
                    report.prunedReferences += 1
                    return nil
                }
                return Document.reference(copied)
            }
            if let dictionary = value as? [String: Any] {
                var out: [String: Any] = [:]
                for (k, v) in dictionary {
                    if let rewritten = rewrite(v, key: k) {
                        // Page-space coordinates move with the page's origin. Applied
                        // here, on the copy, so the source is never mutated.
                        out[k] = translated(rewritten, key: k, dx: dx, dy: dy)
                    }
                }
                return out
            }
            if let array = value as? [Any] {
                // A pruned element inside an array becomes null rather than vanishing:
                // `/QuadPoints` and `/Vertices` are positional, and shortening one
                // would move the mark rather than drop a reference.
                return array.map { rewrite($0, key: nil) ?? NSNull() }
            }
            return value
        }

        var failedStream = false
        var newBody: [String: Any] = [:]
        if let value = body["value"] {
            newBody["value"] = rewrite(value, key: nil) ?? NSNull()
        } else if let stream = body["stream"] as? [String: Any] {
            var newStream: [String: Any] = [:]
            if let dictionary = stream["dict"] {
                newStream["dict"] = rewrite(dictionary, key: nil) ?? [String: Any]()
            }
            // The stream's bytes live in a separate file, and `--json-input` will read
            // it from wherever `datafile` says. Copy it into the staged document's own
            // prefix directory so the two documents' stream files cannot collide, and
            // so deleting the source's scratch cannot pull the data out from under the
            // rebuild.
            if let datafile = stream["datafile"] as? String {
                let destination = into.streamDirectory
                    .appendingPathComponent("carried-\(newID).bin")
                if (try? FileManager.default.copyItem(
                        at: URL(fileURLWithPath: datafile), to: destination)) != nil {
                    newStream["datafile"] = destination.path
                } else {
                    // An appearance stream whose bytes cannot be carried is not a mark
                    // that can be drawn, and a mark that cannot be drawn is not published:
                    // refusing the object would leave an `/AP` with no `/N`, which a
                    // viewer draws as nothing while every count and rectangle check
                    // passes. So this fails the document instead.
                    //
                    // `mapping[id] = nil` was what this did, and in Swift that *removes*
                    // the key rather than recording a failure — so a second path to the
                    // same object allocated a fresh id and walked it again, while
                    // children already copied kept references to the abandoned one.
                    failedStream = true
                    return nil
                }
            }
            if failedStream { return nil }
            newBody["stream"] = newStream
        } else {
            return nil
        }
        into.objects[Document.key(newID)] = newBody
        return newID
    }

    /// Add the copied marks to a page's `/Annots`, creating it when the page has none.
    ///
    /// `/Annots` may be a direct array or a reference to one, and both occur in the
    /// wild — this app's own JBIG2 output writes pages with no `/Annots` at all, while
    /// the Flate route inherits whatever PDFKit produced.
    private static func append(_ references: [String], toAnnotsOf pageID: Int,
                               in document: inout Document, nextID: inout Int) {
        guard var body = document.body(pageID),
              var page = (body["value"] as? [String: Any]) else { return }
        if let existing = page["/Annots"] {
            if let id = Document.id(ofReference: existing) {
                // Indirect: extend the array object it names.
                var array = document.array(id) ?? []
                array.append(contentsOf: references)
                document.objects[Document.key(id)] = ["value": array]
                return
            }
            if var array = existing as? [Any] {
                array.append(contentsOf: references)
                page["/Annots"] = array
                body["value"] = page
                document.objects[Document.key(pageID)] = body
                return
            }
        }
        page["/Annots"] = references
        body["value"] = page
        document.objects[Document.key(pageID)] = body
    }
}
