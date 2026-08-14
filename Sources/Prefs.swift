import Foundation

/// Everything the settings panel can change, persisted in UserDefaults.
///
/// Only the mac-ocr flags that matter for dropping PDFs on a window are here.
/// The image-layer flags (--image-quality, --image-page-dpi,
/// --image-downsample-dpi) only affect *image* inputs and --roi needs a visual
/// picker to be usable, so they're deliberately left out.
enum Prefs {
    enum Mode: String, CaseIterable, Identifiable {
        // Order is the segmented control's order, and searchable PDF is the
        // reason most people open this app — extracting plain text is the
        // specialist case, not the default one.
        case searchablePDF = "searchable-pdf"
        case text = "text"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .text: return "Extract text"
            case .searchablePDF: return "Searchable PDF"
            }
        }
        var blurb: String {
            switch self {
            case .text:
                // Verified: mac-ocr's ocr subcommand always rasterises and runs
                // Vision, so an existing text layer is never read back.
                return "Always re-runs Vision, ignoring any existing text layer."
            case .searchablePDF:
                return "Copies each PDF with an invisible, selectable text layer."
            }
        }
    }

    /// How much resolution a photograph keeps on a page that also has text.
    ///
    /// These pages are stored as three layers: the text as a full-resolution
    /// stencil, and the picture behind it. The text is unaffected by this
    /// setting at every level — it is always stored at full resolution — so what
    /// is being traded is picture detail against file size, and nothing else.
    ///
    /// The numbers in `blurb` are measured, not estimated: a page carrying a
    /// photograph, and a 40-document sample for the aggregate. See FEATURES.md.
    enum PhotoDetail: String, CaseIterable, Identifiable {
        case maximum, balanced, smallest

        var id: String { rawValue }

        /// The factor the picture layer is shrunk by.
        var downsample: Int {
            switch self {
            case .maximum: return 1
            case .balanced: return 2
            case .smallest: return 3
            }
        }

        var label: String {
            switch self {
            case .maximum: return "Maximum"
            case .balanced: return "Balanced"
            case .smallest: return "Smallest files"
            }
        }

        var blurb: String {
            switch self {
            case .maximum:
                return "Photographs keep every pixel. Files are about 15% smaller "
                     + "than before — the saving comes from the text, not the picture."
            case .balanced:
                return "Photographs keep half their resolution, which on a printed "
                     + "halftone is hard to tell from the original. Files are about "
                     + "a third the size."
            case .smallest:
                return "Photographs keep a third of their resolution and look "
                     + "noticeably soft up close, though nothing is lost from them. "
                     + "Files are about a fifth the size."
            }
        }
    }

    /// A named bundle of the settings that depend on what the material *is*.
    ///
    /// The point is not convenience — it is that the right settings differ by
    /// era and by kind, the corpus already shows how, and encoding that once is
    /// better than each user rediscovering it. FEATURES.md put the condition
    /// plainly when this was still an idea: presets should carry *measured*
    /// settings rather than guesses, so every value below cites where it comes
    /// from, and where nothing has been measured the preset leaves the setting
    /// alone rather than inventing one.
    ///
    /// A preset is a starting point, not a mode: applying one writes the values
    /// into the ordinary settings, where they stay visible and editable. There
    /// is deliberately no "currently using preset X" state to get out of sync
    /// with the settings it wrote — `ocrAllPages` is what a setting that only
    /// looks live turns into.
    enum Preset: String, CaseIterable, Identifiable {
        case newspaper, typescript, photographs, bookScan

        var id: String { rawValue }

        var label: String {
            switch self {
            case .newspaper: return "Newspaper"
            case .typescript: return "Typescript"
            case .photographs: return "Photographs"
            case .bookScan: return "Book scan"
            }
        }

        /// What the preset is for, in the user's terms.
        var blurb: String {
            switch self {
            case .newspaper:
                return "Dense columns on poor paper. Keeps every uncertain word, "
                     + "because a rough guess at a smudged word is still findable."
            case .typescript:
                return "Carbon copies and mimeographs. Aged paper reads as tinted, "
                     + "so this leans on the layout signals rather than colour."
            case .photographs:
                return "Plates and illustrated pages. Keeps picture detail at the "
                     + "cost of size."
            case .bookScan:
                return "Printed books. The settings this app already defaults to."
            }
        }

        /// Applies the preset over the current settings, and reports which
        /// settings actually moved.
        ///
        /// Only the settings the preset has a *reason* to set. Languages,
        /// output folder, concurrency and the recogniser path are the user's and
        /// are never touched — a preset that resets where files are written
        /// would be a trap.
        ///
        /// U30 is the return value. The button wrote six or seven settings and
        /// said nothing: nothing moved that the eye was on, and the only
        /// explanation was a `.help` tooltip, which is mouse-only — the objection
        /// U8 already recorded against explaining anything in a tooltip.
        ///
        /// What it reports is what *changed*, not what it wrote. Those differ,
        /// and the difference is the useful part: clicking Book scan on a
        /// default panel changes nothing, and "settings already matched" is a
        /// better answer to "did that do anything?" than a list of seven
        /// settings that were already set that way.
        ///
        /// This deliberately does not make the button stick. `Preset` keeps no
        /// "currently using X" state, because a setting that only looks live is
        /// what `ocrAllPages` turned into: it would be a second source of truth
        /// for values the panel below already owns, and it would go stale the
        /// moment anyone touched one of them. The defect was feedback, not state.
        @discardableResult
        func apply(to d: UserDefaults = .standard) -> [String] {
            // Snapshotted before anything is written, and compared by
            // description rather than by `isEqual:` — these are Bool, String and
            // Double read back as `Any?`, where nil (never set) has to compare
            // unequal to a written value rather than crash or silently match.
            let before = Preset.keysWritten.reduce(into: [String: String]()) {
                $0[$1] = String(describing: d.object(forKey: $1))
            }
            write(to: d)
            return Preset.keysWritten
                .filter { before[$0] != String(describing: d.object(forKey: $0)) }
                .compactMap { Preset.settingLabels[$0] }
                .sorted()
        }

        /// One line of feedback for the panel, in the user's terms.
        func summary(afterChanging changed: [String]) -> String {
            guard !changed.isEmpty else {
                return "\(label) applied — your settings already matched."
            }
            return "\(label) applied — changed "
                + changed.joined(separator: ", ") + "."
        }

        /// The label each written key wears in the panel below, so the line
        /// points at controls the user can actually see and check.
        static let settingLabels: [String: String] = [
            Prefs.rebuildImages: "Rebuild page images",
            Prefs.useJBIG2: "Compress with JBIG2",
            Prefs.joinHyphenated: "Find words broken across two lines",
            Prefs.fast: "Fast",
            Prefs.rebuildMode: "Rebuild as",
            Prefs.photoDetail: "Photo detail",
            Prefs.confidence: "Uncertain text",
            Prefs.languageCorrection: "Language correction",
        ]

        private func write(to d: UserDefaults) {
            // Every preset wants the layered route and joined hyphens: both are
            // measured wins on every kind of material this app sees (BUGS.md
            // R33, and the hyphen work in FEATURES.md), so neither is a
            // material-dependent choice.
            d.set(true, forKey: Prefs.rebuildImages)
            d.set(true, forKey: Prefs.useJBIG2)
            d.set(true, forKey: Prefs.joinHyphenated)
            d.set(false, forKey: Prefs.fast)

            switch self {
            case .newspaper:
                // Automatic: newspaper pages mix dense text with halftone
                // photographs, which is exactly the routing decision.
                d.set(Flattener.Mode.auto.rawValue, forKey: Prefs.rebuildMode)
                // Balanced, not Maximum: newsprint halftones are coarse to begin
                // with, so half resolution is close to the original (FEATURES.md
                // records 2x as visually near-identical on a printed halftone).
                d.set(PhotoDetail.balanced.rawValue, forKey: Prefs.photoDetail)
                // Keep everything. The confidence slider's own doc comment makes
                // the case: on a scan a rough guess at a smudged word is still
                // something you can search for.
                d.set(0.0, forKey: Prefs.confidence)
                d.set(true, forKey: Prefs.languageCorrection)
            case .typescript:
                d.set(Flattener.Mode.auto.rawValue, forKey: Prefs.rebuildMode)
                d.set(PhotoDetail.balanced.rawValue, forKey: Prefs.photoDetail)
                d.set(0.0, forKey: Prefs.confidence)
                // Off: correction is tuned for prose, and a typescript is full
                // of names, abbreviations and struck-through text where it has
                // less to work with. Not measured — stated as the reason so it
                // can be argued with, and it is one switch to undo.
                d.set(false, forKey: Prefs.languageCorrection)
            case .photographs:
                d.set(Flattener.Mode.auto.rawValue, forKey: Prefs.rebuildMode)
                // The one preset that spends bytes on pictures.
                d.set(PhotoDetail.maximum.rawValue, forKey: Prefs.photoDetail)
                d.set(0.0, forKey: Prefs.confidence)
                d.set(true, forKey: Prefs.languageCorrection)
            case .bookScan:
                d.set(Flattener.Mode.auto.rawValue, forKey: Prefs.rebuildMode)
                d.set(PhotoDetail.balanced.rawValue, forKey: Prefs.photoDetail)
                d.set(0.0, forKey: Prefs.confidence)
                d.set(true, forKey: Prefs.languageCorrection)
            }
        }

        /// The keys any preset may write. Used to check a preset leaves the
        /// user's own choices alone, which is the property that matters.
        static let keysWritten: Set<String> = [
            Prefs.rebuildImages, Prefs.useJBIG2, Prefs.joinHyphenated, Prefs.fast,
            Prefs.rebuildMode, Prefs.photoDetail, Prefs.confidence,
            Prefs.languageCorrection,
        ]
    }

    enum TextFormat: String, CaseIterable, Identifiable {
        case text, json, jsonl
        var id: String { rawValue }
        /// Extension used in the -o '[name].EXT' template.
        var fileExtension: String { self == .text ? "txt" : rawValue }
    }

    // Keys are namespaced so they can't collide with SwiftUI's own state.
    static let mode              = "mode"
    static let outputFolder      = "outputFolder"
    static let besideOriginal    = "besideOriginal"
    static let openWhenDone      = "openWhenDone"

    // Update checking. The only keys in here that cause network traffic.
    static let checkForUpdates   = "checkForUpdates"
    static let lastUpdateCheck   = "lastUpdateCheck"
    static let skippedVersion    = "skippedVersion"

    static let textFormat        = "textFormat"

    static let fast              = "fast"
    static let languages         = "languages"
    static let languageCorrection = "languageCorrection"
    static let confidence        = "confidence"
    static let pdfDPIAuto        = "pdfDPIAuto"
    static let pdfDPI            = "pdfDPI"
    static let password          = "password"
    static let customWords       = "customWords"
    static let minTextHeightOn   = "minTextHeightOn"
    static let minTextHeight     = "minTextHeight"

    // `ocrAllPages` and `strategy` used to live here. They are flags of
    // mac-ocr's `searchable-pdf` subcommand, which this app has never invoked —
    // so they were settings that could not affect anything, carried through
    // `Snapshot`, reset by "Reset to Defaults" and written into every
    // `UserDefaults` this app has ever touched. What was learned from them is
    // recorded in BUGS.md under the entry that removed them; the keys are gone.

    /// Ask before re-OCRing a PDF that already has real digital text.
    ///
    /// Not a lock: sometimes the embedded text *is* the problem — a bad export,
    /// a mis-mapped font, a publisher's broken layer — and re-OCRing is exactly
    /// what the user wants. The point is that it should be a decision rather
    /// than a surprise, so this asks and remembers if told to.
    static let warnDigitalText   = "warnDigitalText"

    static let rebuildImages     = "rebuildImages"
    static let rebuildMode       = "rebuildMode"
    static let useJBIG2          = "useJBIG2"
    static let photoDetail       = "photoDetail"

    /// Rejoin a word a line break split in two, so it can be searched for.
    static let joinHyphenated    = "joinHyphenated"

    /// Carry a reader's highlights, notes and ink onto the rebuilt file.
    ///
    /// **Off by default, deliberately.** It costs three extra qpdf passes over the
    /// finished document — the original, the rebuild, and the result read back to check
    /// it — and it only does anything at all for a document somebody has marked up.
    /// Measured over a 1-in-16 library sample, that is 9.0% of documents. Charging every
    /// run for the ninth is the wrong default.
    ///
    /// The other half of the reason is the failure mode. When this is on, a document
    /// whose marks cannot be carried *and verified* fails rather than publishing —
    /// because a file whose highlights moved misrepresents somebody's reading of it. That
    /// is the right trade for a re-OCR sweep over a library of marked-up scholarship, and
    /// the wrong one to impose on someone converting a receipt.
    static let preserveAnnotations = "preserveAnnotations"

    /// Write a record of each finished batch to `~/Library/Logs/VisionOCR`.
    ///
    /// On by default. The log this copies is in-memory and dies with the
    /// window, so without it "something failed last night" is all anyone can
    /// say about an overnight run over material that may not be re-scannable.
    /// A few kilobytes of text per batch, in the directory macOS keeps logs in.
    static let writeRunReport    = "writeRunReport"

    static let concurrency       = "concurrency"

    /// How many files to OCR at once.
    ///
    /// mac-ocr already parallelises *pages* within one file (~4 cores' worth),
    /// but that leaves headroom: measured on an M3 Pro, running files
    /// concurrently is 3–3.6x faster than one at a time. Gains flatten at the
    /// performance-core count — the efficiency cores contribute almost nothing
    /// and only add contention — so that's the default.
    static var defaultConcurrency: Int {
        let cores = sysctlInt("hw.perflevel0.logicalcpu")
            ?? max(ProcessInfo.processInfo.activeProcessorCount / 2, 1)
        return min(max(cores, 1), 8)
    }

    static let maxConcurrency = 12

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, value > 0 else { return nil }
        return Int(value)
    }

    /// Every setting one file's run depends on, read once.
    ///
    /// `start()` deliberately reads settings on the main actor, but
    /// `Runner.arguments`, `Runner.recognitionArguments` and `Model.wantJBIG2`
    /// went back to `UserDefaults` per file on a worker thread. The Settings
    /// sheet stays open during a run, so a change mid-batch applied to some
    /// files and not others — and switching Plain text to JSON mid-run wrote
    /// JSON into the `.txt` path `uniqueOutputs` had already reserved.
    ///
    /// Snapshot it once, pass it down.
    struct Snapshot: Sendable {
        var mode: Mode
        var textFormat: TextFormat
        var besideOriginal: Bool
        var useJBIG2: Bool
        var photoDetail: PhotoDetail
        var joinHyphenated: Bool
        var preserveAnnotations: Bool

        var fast: Bool
        var languages: String
        var languageCorrection: Bool
        var confidence: Double
        var pdfDPIAuto: Bool
        var pdfDPI: Int
        var password: String
        var customWords: String
        var minTextHeightOn: Bool
        var minTextHeight: Double

        /// Reads the live settings. Call on the main actor, once per batch.
        static func current(_ d: UserDefaults = .standard) -> Snapshot {
            Snapshot(
                mode: Mode(rawValue: d.string(forKey: Prefs.mode) ?? "") ?? .searchablePDF,
                textFormat: TextFormat(rawValue: d.string(forKey: Prefs.textFormat) ?? "")
                    ?? .text,
                besideOriginal: d.bool(forKey: Prefs.besideOriginal),
                useJBIG2: d.bool(forKey: Prefs.useJBIG2),
                photoDetail: PhotoDetail(rawValue: d.string(forKey: Prefs.photoDetail) ?? "")
                    ?? .balanced,
                joinHyphenated: d.bool(forKey: Prefs.joinHyphenated),
                preserveAnnotations: d.bool(forKey: Prefs.preserveAnnotations),
                fast: d.bool(forKey: Prefs.fast),
                languages: d.string(forKey: Prefs.languages) ?? "",
                languageCorrection: d.bool(forKey: Prefs.languageCorrection),
                confidence: d.double(forKey: Prefs.confidence),
                pdfDPIAuto: d.bool(forKey: Prefs.pdfDPIAuto),
                pdfDPI: d.integer(forKey: Prefs.pdfDPI),
                password: d.string(forKey: Prefs.password) ?? "",
                customWords: d.string(forKey: Prefs.customWords) ?? "",
                minTextHeightOn: d.bool(forKey: Prefs.minTextHeightOn),
                minTextHeight: d.double(forKey: Prefs.minTextHeight))
        }
    }

    /// Every key this app owns, in one place.
    ///
    /// There were three copies of this list — "Reset to Defaults", the test
    /// harness, and now the rename migration — and R6 was exactly the bug that
    /// costs: `resetAll()` omitted four keys, so a reset silently left them set.
    /// One list, three readers.
    static let allKeys: [String] = [
        mode, outputFolder, besideOriginal, openWhenDone, textFormat,
        fast, languages, languageCorrection, confidence, pdfDPIAuto, pdfDPI,
        password, customWords, minTextHeightOn, minTextHeight,
        warnDigitalText, rebuildImages, rebuildMode, useJBIG2, photoDetail,
        joinHyphenated, preserveAnnotations, writeRunReport, concurrency,
        checkForUpdates, skippedVersion, lastUpdateCheck,
    ]

    /// Set once the pre-rename settings have been brought across. Deliberately
    /// **not** in `allKeys`: "Reset to Defaults" must not clear it, or the next
    /// launch would import the old values again over the reset.
    static let migratedFromOldName = "migratedFromVisionReaderGUI"

    /// Carries settings over from the pre-rename bundle identifier.
    ///
    /// The app was `com.cp1.VisionReaderGUI` until it became Vision OCR, and a
    /// bundle identifier *is* the preferences domain — so without this, everyone
    /// silently loses their output folder, their language list and their mac-ocr
    /// path on a release that only changed a name.
    ///
    /// Gated on an explicit marker, not on "does this domain have a mode yet".
    /// That was the first attempt and it never fired: `object(forKey:)` searches
    /// the *registration* domain too, so once `register()` has run every key
    /// looks present. Caught by the test, which is the only reason this works.
    static func migrateFromPreviousName() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: migratedFromOldName) else { return }
        // A suite has its own (empty) registration domain, so this reads only
        // what the old app actually persisted.
        if let old = UserDefaults(suiteName: "com.cp1.VisionReaderGUI") {
            for key in allKeys {
                if let value = old.object(forKey: key) { d.set(value, forKey: key) }
            }
        }
        d.set(true, forKey: migratedFromOldName)
    }

    /// Defaults chosen to match mac-ocr's own defaults, so an untouched
    /// settings panel behaves exactly like running the CLI bare.
    static func register() {
        migrateFromPreviousName()
        UserDefaults.standard.register(defaults: [
            mode: Mode.searchablePDF.rawValue,
            besideOriginal: false,
            openWhenDone: true,

            // On by default: an app distributed outside the App Store has no
            // other way to say "the thing that lost your table rows is fixed".
            // Off is one checkbox away, and documented in the README rather
            // than buried.
            checkForUpdates: true,
            lastUpdateCheck: 0.0,
            skippedVersion: "",

            textFormat: TextFormat.text.rawValue,

            fast: false,
            languages: "",
            languageCorrection: true,
            confidence: 0.0,
            pdfDPIAuto: true,
            pdfDPI: 144,
            password: "",
            customWords: "",
            minTextHeightOn: false,
            minTextHeight: 0.0,

            // Feeding this app an already-OCR'd PDF must redo the recognition
            // rather than pass the old layer through, and the rebuild is what
            // guarantees it: the pages become images, so Vision's text is the
            // only text there is. mac-ocr's own `--ocr-all-pages` would *add* a
            // layer rather than replace one, which is the wrong shape and is
            // why this app does not use that subcommand at all.
            rebuildImages: true,
            rebuildMode: Flattener.Mode.auto.rawValue,

            // On: the rebuild discards an existing text layer, and for a
            // born-digital file that layer is better than anything OCR will
            // produce. See BUGS.md C17.
            warnDigitalText: true,

            // Roughly a third the size at identical resolution. Falls back to
            // CoreGraphics' Flate silently when jbig2enc/qpdf aren't installed.
            useJBIG2: true,

            // Balanced, not Maximum. The pages this applies to are the ones with
            // pictures on them, so the default has to be a real answer rather
            // than a refusal to choose — and half resolution on a printed
            // halftone is very hard to tell from the original, while costing a
            // third of the bytes. Maximum is one click away for anyone who wants
            // the pixels, and the text is full resolution at every level.
            photoDetail: PhotoDetail.balanced.rawValue,

            // On by default. The failure mode of joining is a slightly noisier
            // extracted text — the tail of the word appears twice — and the
            // failure mode of not joining is a document whose long words cannot
            // be found at all. In narrow-column archival material that is most
            // of the words worth searching for.
            joinHyphenated: true,

            // On by default. The cost is a few kilobytes of text per batch in
            // the directory macOS already keeps logs in; the benefit is that a
            // failure discovered the next morning can be identified at all.
            writeRunReport: true,

            concurrency: defaultConcurrency,
        ])
    }

    // MARK: - Saying what a setting means

    /// Plain-language readout for the confidence threshold.
    ///
    /// The slider read "0.00", which is three problems at once: the number has
    /// no units, it does not say which direction is *more*, and it says nothing
    /// about what happens to the text on the wrong side of it. At the default it
    /// now answers the only question a reader actually has — it keeps
    /// everything — and once moved it says which way the discarding runs.
    static func confidenceReadout(_ value: Double) -> String {
        value <= 0 ? "keep everything"
                   : "drop below \(Int((min(value, 1) * 100).rounded()))%"
    }

    /// What raising it costs, or nil at the default, where it costs nothing.
    ///
    /// Shown on the panel rather than hidden in a tooltip, because the cost is
    /// invisible in the result: discarded words leave no gap, no marker and no
    /// note in the report, so a page comes back looking complete with words
    /// missing from the text underneath it. Someone who does not know that is
    /// exactly the person who should not be moving this slider.
    static func confidenceWarning(_ value: Double) -> String? {
        guard value > 0 else { return nil }
        return "Words Vision is less than \(Int((min(value, 1) * 100).rounded()))% "
            + "sure of will be missing from the finished text, with nothing to "
            + "show where they were."
    }

}
