import Foundation

/// A written record of a finished batch: what went in, what came out, what
/// happened to each file, and the settings that produced it.
///
/// The log this is built from is in-memory and dies with the window. On a long
/// overnight batch over archival material that is the difference between
/// "something failed last night" and knowing which document and why.
///
/// **The report is the log plus the context the log lacks**, rather than a
/// second rendering of the same facts. That is deliberate: this project has
/// twice shipped a second view of some state that disagreed with the first
/// (the results-pane heading counted log *lines* where the user counts files,
/// U25; the Settings prose described behaviour the code did not have, twice).
/// A report assembled by re-deriving per-file outcomes would be a third. So the
/// body is `log` verbatim, in arrival order, and what this file adds is the
/// header, the settings and the problem summary — none of which the log holds.
///
/// Split into `text(…)` and `write(…)` so the whole document can be asserted
/// without touching a filesystem, and so a failure to write is a value the
/// caller has to handle rather than a silent nothing.
///
/// ## What is in it, written down because it is meant to be shared
///
/// The log is copied **verbatim**, so anything any code puts in a `LogLine` is in
/// a file the user is invited to send to someone. As of A4.1 that is:
///
/// - every input file's **absolute path**, and every output's, so the user's
///   short name and directory layout;
/// - **every file name in the batch**, which for archival material is often the
///   author, title and date of the document;
/// - the destination folder, the settings, and the **custom-words list
///   verbatim** — typically proper nouns lifted from the document being scanned;
/// - `qpdf`'s stderr, which prefixes its diagnostics with the input file name.
///
/// All of that is defensible: it is what makes the report worth having when a
/// batch fails overnight, and none of it can be dropped without making the file
/// useless. **The password is deliberately excluded** and there is a check
/// asserting it never appears.
///
/// What is *not* in it, and must not come back, is the content of the documents
/// themselves. `OCRModel.unplacedSummary` is the one place that had it — up to 72
/// characters of recognised text with page numbers (A4.1) — and its own
/// docstring says why it now reports pages and reasons only. Anything new that
/// wants to log recognised text belongs behind a debug environment variable, the
/// way `joiningHyphenatedWords`' `JOIN_DEBUG` notes are: stderr, off by default,
/// and nowhere near this file.
enum RunReport {

    /// Where reports go. `~/Library/Logs/VisionOCR`, which is where macOS
    /// expects an application's logs, is outside any document folder the user
    /// might sync or clear, and is what Console.app already shows.
    ///
    /// Not the output folder: with "beside each original" there is no single
    /// output folder, and writing a report into each of five source directories
    /// is litter. The run log names the path it wrote, and the Help menu opens
    /// the directory, so it is discoverable without being underfoot.
    static var directory: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return base.appendingPathComponent("Logs/VisionOCR", isDirectory: true)
    }

    /// A stable, sortable file name. Colons are legal in HFS+ file names and
    /// display as slashes in Finder, so the time uses hyphens.
    static func fileName(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        f.timeZone = .current
        return "Run \(f.string(from: date)).txt"
    }

    static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f.string(from: date)
    }

    /// `1h 04m 12s`, `4m 12s`, `12s`. Seconds are kept at every scale: a batch
    /// that took 61 seconds and one that took 119 both read as "1m" otherwise.
    static func duration(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0).rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, s) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }

    /// Everything the report needs that the log does not carry.
    struct Context {
        var version: String
        var started: Date
        var finished: Date
        /// Measured monotonically. Wall-clock subtraction is what R30 is about:
        /// a clock adjustment mid-batch would make the elapsed time a fiction,
        /// and an overnight run is exactly when one happens.
        var elapsed: Double
        var settings: Prefs.Snapshot
        var rebuildImages: Bool
        var rebuildMode: Flattener.Mode
        var concurrency: Int
        /// Whether recognition was set up to run in helper processes (R40).
        /// Recorded because it is the difference between a batch taking an hour
        /// and the same batch taking two and a half, and afterwards there is
        /// nothing else in the report that would say which one happened.
        var recognitionInHelpers: Bool
        /// How many files gave up on their helper and recognised in the app
        /// instead. **This is what makes the row above true rather than merely
        /// intended** (R41): a helper that is present and fails on every file
        /// used to be reported as "helper processes" over a batch that ran
        /// entirely in-process.
        var recognitionFallbacks: Int
        var destination: URL?
        /// Input order, as dropped.
        var inputs: [URL]
        var outcomes: [URL: Runner.Result.Outcome]
        var skipped: Set<URL>
        var log: [String]
    }

    /// The whole document. Pure: same context in, same bytes out.
    static func text(_ c: Context) -> String {
        var out = "Vision OCR \(c.version) — run report\n"
        out += "Started   \(stamp(c.started))\n"
        out += "Finished  \(stamp(c.finished))  (\(duration(c.elapsed)))\n\n"

        // Counted from `outcomes`, the same source the results pane counts, so
        // the two cannot disagree. U25 is what happens when they can.
        let succeeded = c.outcomes.values.filter { $0 == .succeeded }.count
        let failed = c.outcomes.values.filter { $0 == .failed }.count
        let cancelled = c.outcomes.values.filter { $0 == .cancelled }.count
        let skipped = c.skipped.count
        var counts = ["\(succeeded) succeeded"]
        if failed > 0 { counts.append("\(failed) failed") }
        if cancelled > 0 { counts.append("\(cancelled) cancelled") }
        if skipped > 0 { counts.append("\(skipped) skipped") }
        // "of N", where N is the files that were *offered*, not the ones that
        // ran. A batch of 10 where 4 were skipped is not a batch of 6, and a
        // report that says so hides the skip.
        out += "\(c.inputs.count) file\(c.inputs.count == 1 ? "" : "s") — "
            + counts.joined(separator: ", ") + "\n\n"

        // Failures first and by name, because that is what the report is opened
        // for. The log below has them too, in order, with their messages.
        let bad = c.inputs.filter { c.outcomes[$0] == .failed }
        if !bad.isEmpty {
            out += "Failed\n"
            for url in bad { out += "  \(url.path)\n" }
            out += "\n"
        }

        out += "Settings\n"
        for (label, value) in settingsRows(c) {
            // `+ 2`, not `max(22, count)`: a label longer than the column would
            // otherwise be padded to its own length, which is no padding, and
            // the value would run straight into it.
            out += "  " + label.padding(toLength: max(22, label.count + 2), withPad: " ",
                                        startingAt: 0) + value + "\n"
        }
        out += "\n"

        out += "Log\n"
        for line in c.log { out += "  \(line)\n" }
        if c.log.isEmpty { out += "  (empty)\n" }
        return out
    }

    /// The settings that shaped this run, as label/value pairs.
    ///
    /// Extracted so the *set* of them can be asserted. The failure mode this
    /// guards is a setting being added to the app and not to the report, which
    /// makes an old report quietly wrong about how its files were produced —
    /// and there is no way to tell afterwards.
    static func settingsRows(_ c: Context) -> [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Mode", c.settings.mode == .searchablePDF
                        ? "Searchable PDF" : "Extract text (\(c.settings.textFormat.rawValue))"))
        rows.append(("Destination", c.settings.besideOriginal
                        ? "beside each original"
                        : (c.destination?.path ?? "(none)")))
        rows.append(("Files at once", "\(c.concurrency)"))
        rows.append(("Recognition runs in", {
            guard c.recognitionInHelpers else { return "the app itself" }
            guard c.recognitionFallbacks > 0 else { return "helper processes" }
            return "helper processes — \(c.recognitionFallbacks) file(s) fell back "
                + "to the app, which is slower"
        }()))

        if c.settings.mode == .searchablePDF {
            rows.append(("Rebuild page images", c.rebuildImages
                            ? c.rebuildMode.label : "off"))
            rows.append(("JBIG2 compression", c.settings.useJBIG2 ? "on" : "off"))
            rows.append(("Photo detail", c.settings.photoDetail.label))
            rows.append(("Join broken words", c.settings.joinHyphenated ? "on" : "off"))
            rows.append(("Keep highlights and notes",
                         c.settings.preserveAnnotations ? "on" : "off"))
        }

        rows.append(("Recognition", c.settings.fast ? "fast" : "accurate"))
        rows.append(("Language correction", c.settings.languageCorrection ? "on" : "off"))
        rows.append(("Languages", c.settings.languages.isEmpty
                        ? "automatic" : c.settings.languages))
        if c.settings.confidence > 0 {
            rows.append(("Minimum confidence", String(format: "%.2f", c.settings.confidence)))
        }
        if c.settings.minTextHeightOn {
            rows.append(("Minimum text height", String(format: "%.3f", c.settings.minTextHeight)))
        }
        rows.append(("Page DPI", c.settings.pdfDPIAuto ? "automatic" : "\(c.settings.pdfDPI)"))
        if !c.settings.customWords.isEmpty {
            rows.append(("Custom words", c.settings.customWords))
        }
        // Deliberately never the password itself — a report is a file that gets
        // mailed to whoever is helping you.
        if !c.settings.password.isEmpty { rows.append(("Password", "(set)")) }
        return rows
    }

    /// Which row reports each field of `Prefs.Snapshot`.
    ///
    /// The failure this exists to stop: a setting gets added to the app and not
    /// to the report, so a run that used it produces a report that is quietly
    /// wrong about how those documents were made — and nothing afterwards can
    /// tell. Reasoning about "did I remember to add it" does not scale, and
    /// CONTRIBUTING 4d says to enumerate instead. The suite walks `Snapshot`'s
    /// stored properties with a `Mirror` and requires every one to appear here,
    /// so a new field fails the build's checks until it is either reported or
    /// deliberately excused below.
    static let reportedBySnapshotField: [String: String] = [
        "mode": "Mode",
        "textFormat": "Mode",              // named inside the mode's own value
        "besideOriginal": "Destination",
        "useJBIG2": "JBIG2 compression",
        "photoDetail": "Photo detail",
        "joinHyphenated": "Join broken words",
        "preserveAnnotations": "Keep highlights and notes",
        "fast": "Recognition",
        "languages": "Languages",
        "languageCorrection": "Language correction",
        "confidence": "Minimum confidence",
        "pdfDPIAuto": "Page DPI",
        "pdfDPI": "Page DPI",
        "password": "Password",
        "customWords": "Custom words",
        "minTextHeightOn": "Minimum text height",
        "minTextHeight": "Minimum text height",
    ]

    /// Rows that report something outside the snapshot, so the coverage check
    /// does not read them as unexplained.
    static let rowsOutsideTheSnapshot: Set<String> =
        ["Files at once", "Rebuild page images", "Recognition runs in"]

    /// A path in `dir` that nothing is using, ` 2`, ` 3`… if the plain one is
    /// taken. The name has one-second resolution, and an atomic write to a name
    /// already in use replaces what was there — so two short batches finishing
    /// in the same second would lose the first report without a word.
    /// `uniqueOutputs` does the same thing for the documents themselves.
    static func unusedPath(in dir: URL, for date: Date) -> URL {
        let name = fileName(for: date)
        let base = (name as NSString).deletingPathExtension
        var url = dir.appendingPathComponent(name)
        var n = 2
        // Bounded: a directory with a thousand reports for one second is not a
        // situation to keep spinning on.
        while FileManager.default.fileExists(atPath: url.path), n < 1000 {
            url = dir.appendingPathComponent("\(base) \(n).txt")
            n += 1
        }
        return url
    }

    /// Writes the report and hands back where it went, or what stopped it.
    ///
    /// A `Result`, not an optional and not a silent no-op: the caller has to
    /// decide what to say. A report that failed to write and said nothing is
    /// the same shape as the bug this feature exists to fix.
    static func write(_ c: Context, to directory: URL? = nil)
        -> Result<URL, Error> {
        let dir = directory ?? self.directory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = unusedPath(in: dir, for: c.finished)
            try Data(text(c).utf8).write(to: url, options: .atomic)
            return .success(url)
        } catch {
            return .failure(error)
        }
    }
}
