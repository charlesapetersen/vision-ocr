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
    static let binaryPath        = "binaryPath"

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
        mode, outputFolder, besideOriginal, openWhenDone, binaryPath, textFormat,
        fast, languages, languageCorrection, confidence, pdfDPIAuto, pdfDPI,
        password, customWords, minTextHeightOn, minTextHeight,
        warnDigitalText, rebuildImages, rebuildMode, useJBIG2, concurrency,
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
            binaryPath: "",

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


            concurrency: defaultConcurrency,
        ])
    }
}
