import Foundation

/// Everything the settings panel can change, persisted in UserDefaults.
///
/// Only the mac-ocr flags that matter for dropping PDFs on a window are here.
/// The image-layer flags (--image-quality, --image-page-dpi,
/// --image-downsample-dpi) only affect *image* inputs and --roi needs a visual
/// picker to be usable, so they're deliberately left out.
enum Prefs {
    /// Where every setting is read and written. The app leaves it at `.standard`,
    /// its own domain, which `@AppStorage` in the views also uses.
    ///
    /// The test suite points it at a domain of its own per run (concurrent-suites).
    /// `build/tests` has no bundle identifier, so `.standard` there is `tests.plist`,
    /// one file shared by every worktree's suite, and a second suite's
    /// `resetPrefs()` wiped the first one's settings mid-run.
    nonisolated(unsafe) static var store: UserDefaults = .standard
    /// The pre-rename domain `migrateFromPreviousName` reads from and empties. A
    /// variable so that the suite runs the migration against a domain of its own
    /// rather than the owner's real `com.cp1.VisionReaderGUI`.
    nonisolated(unsafe) static var previousDomain = "com.cp1.VisionReaderGUI"

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
                return "Reads the page pictures again, even if the PDF already has selectable text."
            case .searchablePDF:
                return "Creates a PDF you can select text in and search. Keeps the original file."
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
                return "Keeps all picture detail. Largest files."
            case .balanced:
                return "Keeps half the picture detail, usually enough for printed photographs. Smaller files."
            case .smallest:
                // ⚠️ This blurb used to end *"though nothing is lost from them"*, and C28
                // question 2b measured that false on 2026-08-21. Not of a photograph — of the
                // prose and figures that end up in the photo layer because the stencil is
                // confined to Vision's word boxes. `Xin Qu et al_2018` p20's correlation
                // matrix is legible in the 460 px background Balanced gives it and unreadable
                // in this setting's 307 px one, and the page that loses those thirteen
                // numbers saves the fewest bytes of the sixteen measured.
                //
                // The clause was DELETED on 2026-08-21, the owner's call, and nothing was put
                // in its place: a caveat about small print would itself need retracting if
                // C28 is fixed, whereas an absent promise stays true either way. Do not
                // restore it as a "fix" — `Tests/main.swift` pins the absence.
                // See `BUGS.md` C28 `#### The same loss at 1/3, RENDERED over 16 of the 109`.
                return "Photographs keep a third of their resolution and look "
                     + "noticeably soft up close. Files are about a fifth the size."
            }
        }
    }

    /// photo-pdf-size. How much of the paper a page that came from an image file keeps
    /// when it holds nothing but text: the factor its background is shrunk by, the
    /// foreground taking twice it. The type is a full-resolution stencil at every step;
    /// what changes is the paper, the signature and any stroke the stencil left out.
    ///
    /// The owner's pick, 2026-10-14, is `.sixth`, Baker's 87 KB step
    /// (`PHOTO-SIZE-DECISION-2026-10-14.md`). At `.eighth` a photographed table's faint
    /// typewriter digits broke ("1979-80" drew as "1?79-6?") and a sheet of pencil
    /// figures became a smudge, because uneven light leaves such strokes out of the
    /// stencil and only the background holds them; at `.quarter` both read. At `.sixth`,
    /// measured 2026-10-14 in 2.5x PDFKit renders, the table's figures read but soften
    /// ("CSs" toward "C5s") and the pencil sheet is all but gone, which is what the
    /// `.sixth` blurb says. The run report names every page stored this way.
    enum ImageDetail: Int, CaseIterable, Identifiable {
        case half = 2, third = 3, quarter = 4, sixth = 6, eighth = 8

        var id: Int { rawValue }

        /// "1/6": the paper's resolution against the photo's, as the slider shows it.
        var label: String { "1/\(rawValue)" }

        var backgroundDownsample: Int { rawValue }
        var foregroundDownsample: Int { rawValue * 2 }

        /// "the rest of the page was stored at …", in the run report.
        var fraction: String {
            switch self {
            case .half: return "a half"
            case .third: return "a third"
            case .quarter: return "a quarter"
            case .sixth: return "a sixth"
            case .eighth: return "an eighth"
            }
        }

        /// Baker (`00187 — Baker.JPG`, a phone photo of a typed letter) at this step,
        /// measured 2026-10-14 (`PHOTO-SIZE-DECISION-2026-10-14.md`; 1/2 and 1/3 again once
        /// they stopped taking a mark layer). The photo published as 831 KB before any of this.
        var exampleKB: Int {
            switch self {
            case .half: return 244
            case .third: return 143
            case .quarter: return 113
            case .sixth: return 87
            case .eighth: return 79
            }
        }

        var blurb: String {
            switch self {
            case .half, .third:
                return "Paper, signatures and pencil keep their texture. Files are larger."
            case .quarter:
                return "Faint pencil and pale figures stay readable."
            case .sixth:
                return "Typed text and ink stay sharp; faint pencil can fade away."
            case .eighth:
                return "Smallest files. Typed text and ink stay sharp; faint pencil and "
                     + "pale figures can be lost."
            }
        }

        static let initial = ImageDetail.sixth
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
            case .photographs: return "Photos"
            case .bookScan: return "Book scan"
            }
        }

        /// What the preset is for, in the user's terms.
        ///
        /// **A10.3: these have to describe what the preset writes, not what its
        /// name suggests.** Newspaper's used to promise that it "keeps every
        /// uncertain word, because a rough guess at a smudged word is still
        /// findable" — which is true of the app, and true of every other preset,
        /// and true of the defaults. `confidence = 0.0` is what `register()`
        /// already sets. Newspaper and Book scan write byte-identical values, so
        /// two of the four buttons are "restore the defaults" under names that say
        /// what material those defaults suit. That is a reasonable thing for them
        /// to be; claiming a distinguishing behaviour they do not have is not, and
        /// the suite now requires any preset equal to the defaults to say so.
        var blurb: String {
            switch self {
            case .newspaper:
                return "Dense columns on poor paper — the settings this app already "
                     + "defaults to, which suit newsprint as they come."
            case .typescript:
                return "Carbon copies and mimeographs. The defaults with language "
                     + "correction off, because it is tuned for prose and a typescript "
                     + "is full of names, abbreviations and struck-through text."
            case .photographs:
                return "Plates and illustrated pages. The defaults with picture detail "
                     + "at maximum, which costs size."
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
        func apply(to d: UserDefaults = Prefs.store) -> [String] {
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
            Prefs.rebuildImages: "Replace old selectable text",
            Prefs.useJBIG2: "Make text pages smaller",
            Prefs.joinHyphenated: "Find words broken across two lines",
            Prefs.fast: "Faster reading",
            Prefs.rebuildMode: "Page appearance",
            Prefs.photoDetail: "Photo detail",
            Prefs.imageDetail: "Photographed pages",
            Prefs.confidence: "Unsure words",
            Prefs.languageCorrection: "Use spelling and context to help",
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
                d.set(ImageDetail.initial.rawValue, forKey: Prefs.imageDetail)
                // Keep everything. The confidence slider's own doc comment makes
                // the case: on a scan a rough guess at a smudged word is still
                // something you can search for.
                d.set(0.0, forKey: Prefs.confidence)
                d.set(true, forKey: Prefs.languageCorrection)
            case .typescript:
                d.set(Flattener.Mode.auto.rawValue, forKey: Prefs.rebuildMode)
                d.set(PhotoDetail.balanced.rawValue, forKey: Prefs.photoDetail)
                d.set(ImageDetail.initial.rawValue, forKey: Prefs.imageDetail)
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
                // And a photographed page keeps half its paper, for the same reason.
                d.set(ImageDetail.half.rawValue, forKey: Prefs.imageDetail)
                d.set(0.0, forKey: Prefs.confidence)
                d.set(true, forKey: Prefs.languageCorrection)
            case .bookScan:
                d.set(Flattener.Mode.auto.rawValue, forKey: Prefs.rebuildMode)
                d.set(PhotoDetail.balanced.rawValue, forKey: Prefs.photoDetail)
                d.set(ImageDetail.initial.rawValue, forKey: Prefs.imageDetail)
                d.set(0.0, forKey: Prefs.confidence)
                d.set(true, forKey: Prefs.languageCorrection)
            }
        }

        /// The keys any preset may write. Used to check a preset leaves the
        /// user's own choices alone, which is the property that matters.
        static let keysWritten: Set<String> = [
            Prefs.rebuildImages, Prefs.useJBIG2, Prefs.joinHyphenated, Prefs.fast,
            Prefs.rebuildMode, Prefs.photoDetail, Prefs.imageDetail, Prefs.confidence,
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
    /// photo-pdf-size. `ImageDetail`'s raw value: the paper a photographed page keeps.
    static let imageDetail       = "imageDetail"

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

    /// How a second, stronger reader's words reach the text layer (`ocr-hybrid-proto`).
    /// Off by default and offered nowhere in the panel yet: the arrangements are being
    /// built and measured, and `ocr-integrate-settings` gives the winner its controls.
    static let modelArrangement = "modelArrangement"
    /// The reader itself: an executable run as `<reader> <page image> <out.txt>`, which
    /// writes the page's text, in reading order, to `out.txt` and exits 0. `fill` runs it
    /// as `<reader> <page image> <out.txt> <crops.tsv>`: a header line, then one crop a
    /// line as `name x y width height` in the image's pixels, tab-separated; it writes
    /// each crop's text on one line of `out.txt`, in the file's order. Under `replace` and `regions` the
    /// reader writes the page's layout blocks to `out.txt`, one a line, in reading order, as
    /// `x0 y0 x1 y1 label text`, tab-separated, the four as fractions of the image with a
    /// top-left origin (`Recogniser.modelBlocks`).
    static let modelReader = "modelReader"
    /// The arrangement and reader for newspaper pages (`Recogniser.pageKind`), when they are
    /// read otherwise than the rest (C57, ie-readers). Unset, a newspaper page is read as
    /// every other page is, by `modelArrangement` and `modelReader`.
    static let newspaperModelArrangement = "newspaperModelArrangement"
    static let newspaperModelReader = "newspaperModelReader"
    /// The same for photographed pages (`Recogniser.isPhotograph`, page-kinds-three). Unset, a
    /// photographed page is read as every other page is.
    static let photoModelArrangement = "photoModelArrangement"
    static let photoModelReader = "photoModelReader"
    /// The same for handwritten pages (`Recogniser.isHandwritten`, page-kind-handwriting).
    static let handModelArrangement = "handModelArrangement"
    static let handModelReader = "handModelReader"
    /// Whether a handwritten page read by a whole-page model reader is followed by a page of
    /// that reader's text (hw-qwen), its image page keeping Vision's own layer. On by default:
    /// the reader's words mostly cannot be placed on the hand's lines (`HW-PLACE-2026-10-15.tsv`).
    /// Off, the words go into the page's own layer by `align`, as the other kinds' do.
    static let handTextPage = "handTextPage"
    /// The most memory a model reader may hold, in GB, before `ModelGuard` stops it and the
    /// page keeps Vision's reading (C57, ie-guard): the memory slider `ocr-integrate-settings`
    /// gives a control. Measured as the reader's whole process group's physical footprint,
    /// which, unlike its resident size, counts MLX's Metal buffers.
    static let modelMemoryGB = "modelMemoryGB"

    /// 5 GB on a Mac with 16 GB or more, and below that the slider's lowest step, with a
    /// warning (owner, 2026-10-12). Falcon-OCR's whole-page reading peaked at 3.9 GB.
    static func defaultModelMemoryGB(physicalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Double {
        physicalGB(physicalBytes) >= 16 ? 5 : modelMemoryRange.lowerBound
    }

    /// The memory slider's span, in whole GB (owner, 2026-10-12).
    static let modelMemoryRange: ClosedRange<Double> = 4...12

    static func physicalGB(_ bytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> Double {
        Double(bytes) / 1_073_741_824
    }

    /// The accurate mode (C57, `ocr-integrate-settings`). Off by default, and off, no model
    /// is run or downloaded. On, each kind of page is read by the reader chosen for it in
    /// `accurateReader`, `accurateNewspaperReader`, `accuratePhotoReader` and `accurateHandReader` (`AccurateReader`
    /// raw values; unset is Vision), and the lab's `modelArrangement` keys are not read.
    static let accurateMode = "accurateMode"
    static let accurateReader = "accurateReader"
    static let accurateNewspaperReader = "accurateNewspaperReader"
    static let accuratePhotoReader = "accuratePhotoReader"
    static let accurateHandReader = "accurateHandReader"
    /// The model readers the user has downloaded and enabled in the models dialog
    /// (`ocr-model-dialogs`), as comma-separated `AccurateReader` raw values. Only these, once
    /// downloaded, are offered for a kind of page (`AccurateReader.ready`).
    static let accurateEnabled = "accurateEnabledReaders"

    /// The readers the accurate mode offers, with the figures the settings show beside them:
    /// `OCR-COMPARE-2026-10-13.tsv`'s rows for the arrangements the owner approved
    /// (`OCR-COMPARE-DECISION-2026-10-13.md`), measured on this project's 67-page sample on
    /// one Mac. Speed is ours until a timing run on the user's Mac replaces it.
    enum AccurateReader: String, CaseIterable {
        case vision, visionRegions = "vision-regions", paddle = "paddleocr-vl", falcon = "falcon-ocr",
             lighton = "lightonocr-3"

        var name: String {
            switch self {
            case .vision: return "Vision (built in)"
            case .visionRegions: return "Vision, section by section"
            case .paddle: return "PaddleOCR-VL"
            case .falcon: return "Falcon-OCR"
            case .lighton: return "LightOnOCR-3"
            }
        }

        struct Figures: Equatable {
            /// Words wrong or missing, of every 1,000 (`wm_share`).
            let wrongPer1000: Int
            /// The app's time a page (`secs`).
            let secondsPerPage: Double
            /// The reader's largest guard peak, in GB; 0 for Vision alone.
            let memoryGB: Double
            /// The model and, where its arrangement cuts regions, the layout model; not the
            /// runtime, which the models share (`runtimeDownloadMB`).
            let downloadMB: Int
        }

        /// What each download fetches, in decimal MB: `ModelDownloads.Item.downloadMB`, which the
        /// helper does not compile, so the suite holds the two equal. The runtime is 433 MB on disk,
        /// the layout model 72 MB.
        static let runtimeDownloadMB = 134
        static let layoutDownloadMB = 65
        static let paddleDownloadMB = 715
        static let falconDownloadMB = 1085
        static let lightonDownloadMB = 5164

        /// This reader's figures on `kind`, or nil where it is not offered: Vision on regions
        /// off newspapers gave no real advantage (1.20% to 1.09% at twice the time).
        func figures(_ kind: Recogniser.PageKind) -> Figures? {
            switch (self, kind) {
            case (.vision, .newspaper):        return Figures(wrongPer1000: 296, secondsPerPage: 23.1, memoryGB: 0, downloadMB: 0)
            case (.vision, .other):            return Figures(wrongPer1000: 12, secondsPerPage: 3.4, memoryGB: 0, downloadMB: 0)
            case (.visionRegions, .newspaper): return Figures(wrongPer1000: 265, secondsPerPage: 33.0, memoryGB: 0.6,
                                                              downloadMB: Self.layoutDownloadMB)
            case (.visionRegions, .other):     return nil
            case (.paddle, .newspaper):        return Figures(wrongPer1000: 218, secondsPerPage: 59.8, memoryGB: 2.5,
                                                              downloadMB: Self.paddleDownloadMB + Self.layoutDownloadMB)
            case (.paddle, .other):            return Figures(wrongPer1000: 7, secondsPerPage: 13.2, memoryGB: 2.4,
                                                              downloadMB: Self.paddleDownloadMB + Self.layoutDownloadMB)
            case (.falcon, .newspaper):        return Figures(wrongPer1000: 214, secondsPerPage: 67.6, memoryGB: 3.7,
                                                              downloadMB: Self.falconDownloadMB + Self.layoutDownloadMB)
            case (.falcon, .other):            return Figures(wrongPer1000: 6, secondsPerPage: 13.8, memoryGB: 3.9, downloadMB: Self.falconDownloadMB)
            // Photographed pages (page-kinds-three): `PK-PHOTO-MEASURE-2026-10-14.tsv`, 31 photos,
            // a small sample, print only; memory is the scans' figure, not measured on photos.
            case (.vision, .photograph):       return Figures(wrongPer1000: 34, secondsPerPage: 2.1, memoryGB: 0, downloadMB: 0)
            case (.visionRegions, .photograph): return nil
            case (.paddle, .photograph):       return Figures(wrongPer1000: 31, secondsPerPage: 8.5, memoryGB: 2.4,
                                                              downloadMB: Self.paddleDownloadMB + Self.layoutDownloadMB)
            case (.falcon, .photograph):       return Figures(wrongPer1000: 27, secondsPerPage: 36.9, memoryGB: 3.9,
                                                              downloadMB: Self.falconDownloadMB)
            // Handwritten pages (page-kind-handwriting): `HW-MEASURE-2026-10-15.tsv`, 19 photographed
            // pages of one archive's hands, a small sample; words missed only. Seconds are the
            // harness's wall less its own start-up (about 18 s, reasoned); memory is the scans'.
            case (.vision, .handwriting):      return Figures(wrongPer1000: 561, secondsPerPage: 2.3, memoryGB: 0, downloadMB: 0)
            case (.visionRegions, .handwriting): return nil
            case (.paddle, .handwriting):      return Figures(wrongPer1000: 454, secondsPerPage: 3.3, memoryGB: 2.4,
                                                              downloadMB: Self.paddleDownloadMB + Self.layoutDownloadMB)
            case (.falcon, .handwriting):      return Figures(wrongPer1000: 409, secondsPerPage: 38.6, memoryGB: 3.9,
                                                              downloadMB: Self.falconDownloadMB)
            // LightOnOCR-3 (hw-qwen): `HW-PANEL-2026-10-15.tsv`, the same 19 pages, missed words
            // only; memory its guard peak there, seconds the app's own run over the 21 pages
            // (`HW-BUILD-2026-10-15.tsv`, 8 min 30 s). Handwritten pages only: measured on nothing else.
            case (.lighton, .handwriting):     return Figures(wrongPer1000: 96, secondsPerPage: 22.0, memoryGB: 7.6,
                                                              downloadMB: Self.lightonDownloadMB)
            case (.lighton, _):                return nil
            }
        }

        /// The arrangement and `modelReader` name the helper runs this reader as on `kind`
        /// (`ModelRuntime.readers`' approved arrangements): `.off` is Vision alone.
        func route(_ kind: Recogniser.PageKind) -> (arrangement: ModelArrangement, reader: String) {
            switch self {
            case .vision: return (.off, "")
            case .visionRegions: return (.regions, ModelRuntime.visionRegions)
            case .paddle: return (.regions, rawValue)
            case .falcon: return (kind == .newspaper ? .regions : .align, rawValue)
            case .lighton: return (.align, rawValue)
            }
        }

        /// Seconds a page `TimingRun` took over its own pages, each reader as the settings run
        /// it, on the Mac `figures` were measured on (2026-10-14). A timing run elsewhere scales
        /// `figures`' speed by its time against this one, so the column keeps the 67-page
        /// sample's mix of pages and takes the user's Mac's speed.
        func referenceSeconds(_ kind: Recogniser.PageKind) -> Double? {
            switch (self, kind) {
            // The mean of two runs, which agreed within 2-5% a reader.
            case (.vision, .newspaper):        return 39.6
            case (.vision, .other):            return 2.9
            case (.visionRegions, .newspaper): return 51.5
            case (.visionRegions, .other):     return nil
            case (.paddle, .newspaper):        return 77.7
            case (.paddle, .other):            return 10.1
            case (.falcon, .newspaper):        return 96.2
            case (.falcon, .other):            return 10.3
            case (.lighton, _):                return nil
            // No timing run has photographed or handwritten pages; their speed stays ours.
            case (_, .photograph), (_, .handwriting): return nil
            }
        }

        /// Seconds a page on `kind`: ours, or ours scaled by `timing`'s run on this Mac, and
        /// which. Nil where the reader is not offered.
        func speed(_ kind: Recogniser.PageKind, timing: AccurateTiming?) -> (seconds: Double, measured: Bool)? {
            guard let f = figures(kind) else { return nil }
            if let mine = timing?.seconds[AccurateTiming.key(self, kind)], mine > 0,
               let reference = referenceSeconds(kind), reference > 0 {
                return (f.secondsPerPage * mine / reference, true)
            }
            return (f.secondsPerPage, false)
        }

        /// The settings table's cells for this reader on `kind`, in words a user reads: words
        /// wrong or missing, speed, memory, download. Nil where it is not offered. Speed is
        /// `timing`'s where it timed this reader, and then against Vision timed in the same run.
        func cells(_ kind: Recogniser.PageKind, timing: AccurateTiming? = nil) -> [String]? {
            guard let f = figures(kind), let speed = speed(kind, timing: timing),
                  let base = AccurateReader.vision.speed(kind, timing: speed.measured ? timing : nil)
            else { return nil }
            let seconds = String(format: "%.0f", speed.seconds)
            let times = (self == .vision ? "" : String(format: ", %.1f× Vision", speed.seconds / base.seconds))
                // Beside readers this Mac timed, one it did not says so; so does every reader on a
                // kind no timing run reads (photographs, handwriting), once there has been a run.
                + (!speed.measured && timing.map { t in
                       referenceSeconds(kind) == nil || t.seconds.keys.contains { $0.hasSuffix(".\(kind.rawValue)") }
                   } == true ? " (test Mac)" : "")
            let download = f.downloadMB == 0 ? "none"
                : f.downloadMB < 500 ? "\(f.downloadMB) MB"
                : String(format: "%.1f GB", Double(f.downloadMB) / 1000)
            return ["about \(f.wrongPer1000)", "about \(seconds) seconds\(times)",
                    f.memoryGB == 0 ? "no extra" : String(format: "%.1f GB", f.memoryGB), download]
        }

        /// The readers offered on `kind` whose memory fits under the slider. Vision is always one.
        static func offered(_ kind: Recogniser.PageKind, memoryGB: Double) -> [AccurateReader] {
            allCases.filter { reader in reader.figures(kind).map { $0.memoryGB <= memoryGB } ?? false }
        }

        /// The stored choice as it is run: Vision when it is unset, unknown, not offered on
        /// `kind`, no longer fits under the slider, or, given `enabled`, is a model reader not
        /// enabled in the models dialog.
        static func chosen(_ raw: String?, _ kind: Recogniser.PageKind, memoryGB: Double,
                           enabled: Set<AccurateReader>? = nil) -> AccurateReader {
            AccurateReader(rawValue: raw ?? "").flatMap { offered(kind, memoryGB: memoryGB).contains($0) ? $0 : nil }
                .flatMap { $0 == .vision || enabled?.contains($0) != false ? $0 : nil }
                ?? .vision
        }

        /// What it reads well, for the models dialog: from `figures`, in words.
        var readsWell: String {
            switch self {
            case .vision: return "Built in; fast on every kind of page."
            case .visionRegions: return "For newspapers: helps Vision read each block of text on its own. The smallest download."
            case .paddle: return "For books, articles and newspapers: fewer word mistakes in our sample, using less memory than Falcon-OCR."
            case .falcon: return "For books, articles and newspapers: the fewest word mistakes in our sample, using more memory than PaddleOCR-VL."
            case .lighton: return "For handwritten pages only: about a sixth of Vision's missed words in our small sample of letters "
                + "and notes. A large download, and it needs a memory limit of 8 GB or more. Its text goes on a page "
                + "of its own after each handwritten page."
            }
        }

        /// The most memory it needs on any kind of page it is offered on, in GB.
        var memoryNeedGB: Double {
            Recogniser.PageKind.allCases.compactMap { figures($0)?.memoryGB }.max() ?? 0
        }

        /// The readers enabled in the models dialog, read from `d`.
        static func enabled(_ d: UserDefaults) -> Set<AccurateReader> {
            enabled(raw: d.string(forKey: Prefs.accurateEnabled) ?? "")
        }

        static func enabled(raw: String) -> Set<AccurateReader> {
            Set(raw.split(separator: ",").compactMap { AccurateReader(rawValue: String($0)) })
        }

        /// Enables or disables `reader`. Disabling it puts each kind of page that had it back to
        /// Vision, as the memory slider does with a reader it stops allowing.
        static func setEnabled(_ reader: AccurateReader, _ on: Bool, _ d: UserDefaults) {
            var set = enabled(d)
            if on { set.insert(reader) } else { set.remove(reader) }
            d.set(allCases.filter(set.contains).map(\.rawValue).joined(separator: ","), forKey: Prefs.accurateEnabled)
            guard !on else { return }
            for key in [Prefs.accurateReader, Prefs.accurateNewspaperReader, Prefs.accuratePhotoReader,
                        Prefs.accurateHandReader]
            where d.string(forKey: key) == reader.rawValue {
                d.set(AccurateReader.vision.rawValue, forKey: key)
            }
        }
    }

    /// The last "Measure on this Mac" run (`TimingRun`), stored as JSON under `accurateTiming`:
    /// when it ran and the seconds a page each reader took over the run's pages. It measures
    /// speed only; accuracy stays ours.
    static let accurateTiming = "accurateTiming"

    struct AccurateTiming: Codable, Equatable {
        var measured: Date
        /// Keyed `key(reader, kind)`.
        var seconds: [String: Double]
        /// The `referenceSeconds` and pages it was measured against, and the Mac it ran on: a
        /// timing from other pages, or carried to another Mac with the settings, is no timing.
        var reference: Int
        var machine: String

        /// Raise it whenever `referenceSeconds`, `TimingRun`'s pages or what a leg runs changes.
        static let referenceVersion = 1

        static func key(_ reader: AccurateReader, _ kind: Recogniser.PageKind) -> String {
            "\(reader.rawValue).\(kind.rawValue)"
        }

        /// The Mac's model identifier, `Mac15,6` or the like.
        static var thisMachine: String {
            var size = 0
            sysctlbyname("hw.model", nil, &size, nil, 0)
            var bytes = [CChar](repeating: 0, count: max(size, 1))
            sysctlbyname("hw.model", &bytes, &size, nil, 0)
            return String(cString: bytes)
        }

        init(measured: Date, seconds: [String: Double], reference: Int = referenceVersion,
             machine: String = thisMachine) {
            self.measured = measured
            self.seconds = seconds
            self.reference = reference
            self.machine = machine
        }

        /// Nil for no run yet, for data this build cannot read, and for a timing measured
        /// against another reference or on another Mac.
        init?(_ data: Data?) {
            guard let data, let t = try? JSONDecoder().decode(AccurateTiming.self, from: data),
                  t.reference == Self.referenceVersion, t.machine == Self.thisMachine else { return nil }
            self = t
        }

        var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }
    }

    /// `modelArrangement`'s values. `align` keeps Vision's lines, boxes and order and
    /// takes their words from one whole-page reading by the model
    /// (`Recogniser.alignedReading`): the queue's arrangement (b). `fill` keeps Vision's
    /// reading and has the model read only the lines Vision was unsure of and the
    /// inked lines it skipped (`Recogniser.filledReading`): arrangement (c). `replace`
    /// takes the model's blocks and words in place of Vision's, its lines found in the
    /// ink of each block (`Recogniser.replacedReading`): arrangement (a). `regions` keeps
    /// Vision's lines and takes their words from the model's reading of each layout
    /// region they lie in (`Recogniser.regionedReading`), for newspaper pages: its reader
    /// writes blocks as `replace`'s does, or leaves them unread for Vision to read
    /// (`Recogniser.visionRegionLabel`).
    enum ModelArrangement: String, CaseIterable {
        case off, align, fill, replace, regions
    }

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
        var imageDetail: ImageDetail = .initial
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
        var modelArrangement: ModelArrangement = .off
        var modelReader: String = ""
        /// Nil: newspaper pages are read as the rest (`Prefs.newspaperModelArrangement`).
        var newspaperModelArrangement: ModelArrangement? = nil
        var newspaperModelReader: String = ""
        /// Nil: photographed pages are read as the rest (`Prefs.photoModelArrangement`).
        var photoModelArrangement: ModelArrangement? = nil
        var photoModelReader: String = ""
        /// Nil: handwritten pages are read as the rest (`Prefs.handModelArrangement`).
        var handModelArrangement: ModelArrangement? = nil
        var handModelReader: String = ""
        /// `Prefs.handTextPage`. Read only through `model(for: .handwriting)`, which sets `textPage`.
        var handTextPage: Bool = false
        /// Whether this page's model reading goes on a text page after it rather than into its
        /// layer: set by `model(for:)` on a handwritten page only, never by a caller.
        var textPage: Bool = false
        var modelMemoryGB: Double = Prefs.defaultModelMemoryGB()

        /// Reads the live settings. Call on the main actor, once per batch.
        static func current(_ d: UserDefaults = Prefs.store) -> Snapshot {
            var snapshot = Snapshot(
                mode: Mode(rawValue: d.string(forKey: Prefs.mode) ?? "") ?? .searchablePDF,
                textFormat: TextFormat(rawValue: d.string(forKey: Prefs.textFormat) ?? "")
                    ?? .text,
                besideOriginal: d.bool(forKey: Prefs.besideOriginal),
                useJBIG2: d.bool(forKey: Prefs.useJBIG2),
                photoDetail: PhotoDetail(rawValue: d.string(forKey: Prefs.photoDetail) ?? "")
                    ?? .balanced,
                imageDetail: ImageDetail(rawValue: d.integer(forKey: Prefs.imageDetail))
                    ?? .initial,
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
                minTextHeight: d.double(forKey: Prefs.minTextHeight),
                modelArrangement: ModelArrangement(
                    rawValue: d.string(forKey: Prefs.modelArrangement) ?? "") ?? .off,
                modelReader: d.string(forKey: Prefs.modelReader) ?? "",
                // Unset or empty is the main pair's; a value that is no arrangement is off.
                newspaperModelArrangement: (d.string(forKey: Prefs.newspaperModelArrangement))
                    .flatMap { $0.isEmpty ? nil : ModelArrangement(rawValue: $0) ?? .off },
                newspaperModelReader: d.string(forKey: Prefs.newspaperModelReader) ?? "",
                photoModelArrangement: (d.string(forKey: Prefs.photoModelArrangement))
                    .flatMap { $0.isEmpty ? nil : ModelArrangement(rawValue: $0) ?? .off },
                photoModelReader: d.string(forKey: Prefs.photoModelReader) ?? "",
                handModelArrangement: (d.string(forKey: Prefs.handModelArrangement))
                    .flatMap { $0.isEmpty ? nil : ModelArrangement(rawValue: $0) ?? .off },
                handModelReader: d.string(forKey: Prefs.handModelReader) ?? "",
                handTextPage: d.bool(forKey: Prefs.handTextPage),
                // Unset reads 0, which would stop every reader at its first sample.
                modelMemoryGB: d.double(forKey: Prefs.modelMemoryGB) > 0
                    ? d.double(forKey: Prefs.modelMemoryGB) : Prefs.defaultModelMemoryGB())
            if d.bool(forKey: Prefs.accurateMode) { snapshot.applyAccurateMode(d) }
            return snapshot
        }

        /// The accurate mode's choices in place of the lab's model keys: each kind's reader as
        /// `AccurateReader.chosen` resolves it, a reader not enabled being Vision, newspapers
        /// photographs and handwriting always set apart so that they never take the print
        /// reader's arrangement.
        mutating func applyAccurateMode(_ d: UserDefaults) {
            let enabled = AccurateReader.enabled(d)
            let other = AccurateReader.chosen(d.string(forKey: Prefs.accurateReader), .other, memoryGB: modelMemoryGB,
                                              enabled: enabled).route(.other)
            let news = AccurateReader.chosen(d.string(forKey: Prefs.accurateNewspaperReader), .newspaper,
                                             memoryGB: modelMemoryGB, enabled: enabled).route(.newspaper)
            modelArrangement = other.arrangement
            modelReader = other.reader
            newspaperModelArrangement = news.arrangement
            newspaperModelReader = news.reader
            let photo = AccurateReader.chosen(d.string(forKey: Prefs.accuratePhotoReader), .photograph,
                                              memoryGB: modelMemoryGB, enabled: enabled).route(.photograph)
            photoModelArrangement = photo.arrangement
            photoModelReader = photo.reader
            let hand = AccurateReader.chosen(d.string(forKey: Prefs.accurateHandReader), .handwriting,
                                             memoryGB: modelMemoryGB, enabled: enabled).route(.handwriting)
            handModelArrangement = hand.arrangement
            handModelReader = hand.reader
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
        warnDigitalText, rebuildImages, rebuildMode, useJBIG2, photoDetail, imageDetail,
        joinHyphenated, preserveAnnotations, writeRunReport, concurrency,
        checkForUpdates, skippedVersion, lastUpdateCheck, modelArrangement, modelReader,
        newspaperModelArrangement, newspaperModelReader, photoModelArrangement, photoModelReader,
        handModelArrangement, handModelReader, handTextPage, modelMemoryGB, accurateMode, accurateReader,
        accurateNewspaperReader, accuratePhotoReader, accurateHandReader, accurateEnabled, accurateTiming,
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
        let d = Prefs.store
        guard !d.bool(forKey: migratedFromOldName) else { return }
        // The registration domain is process-wide, so a suite sees registered
        // defaults too (measured 2026-10-13; this said each suite had its own). The
        // app migrates before `register()` registers anything, which is what keeps
        // this to what the old app actually persisted.
        if let old = UserDefaults(suiteName: previousDomain) {
            for key in allKeys {
                if let value = old.object(forKey: key) { d.set(value, forKey: key) }
            }
            // **And remove the source** (A4.3). This copied every key including
            // `password` and left the old domain intact, while `resetAll` clears
            // only the current one — so anyone who set a PDF password before the
            // rename had a **stale plaintext copy that "Reset to Defaults" could not
            // reach**, readable with `defaults read com.cp1.VisionReaderGUI` and
            // present in Time Machine backups and APFS local snapshots.
            //
            // Every key, not just the password: the migration's whole point is that
            // the old domain is finished with, and a half-emptied one is a second
            // source of truth for settings this app no longer reads from there.
            for key in allKeys { old.removeObject(forKey: key) }
        }
        d.set(true, forKey: migratedFromOldName)
    }

    /// Keys in `allKeys` that are **records, not settings** (A10.6).
    ///
    /// They have to be in `allKeys` — the migration and the enumeration checks walk
    /// it — but "Reset to Defaults" must not touch them. `skippedVersion` is the
    /// user having already said "don't offer me 1.9.0 again", so resetting it
    /// re-offered a version they had dismissed; `lastUpdateCheck` is bookkeeping
    /// that decides when the next request is due, and clearing it makes the app ask
    /// again immediately. `accurateTiming` is a measurement of this Mac, minutes to redo.
    static let notASetting: Set<String> = [skippedVersion, lastUpdateCheck, accurateTiming]

    /// Defaults chosen to match mac-ocr's own defaults, so an untouched
    /// settings panel behaves exactly like running the CLI bare.
    ///
    /// **`migrate: false` is for the tools, and it is not a nicety.** A tool in
    /// `Tools/` has no bundle identifier, so `UserDefaults.standard` lands in a
    /// domain keyed by its *process name* — and `migrateFromPreviousName` then
    /// copies every setting out of `com.cp1.VisionReaderGUI` **and removes it from
    /// there**, into a plist called `score-mrc.plist`. A measurement run would
    /// consume the user's pre-rename migration and drop it somewhere the app will
    /// never look, so the next real launch would find nothing to migrate: A4.3's
    /// harm through a door A4.3 did not consider. It also means two runs of one
    /// tool race on one file, which is the `tests.plist` hazard in CLAUDE.md.
    ///
    /// The registration itself is in-memory, so a tool calling
    /// `register(migrate: false)` gets exactly the shipped defaults and writes
    /// nothing at all. Every tool passes false; only the app migrates.
    ///
    /// `store` is for a run that wants the shipped defaults and none of the user's
    /// settings (`TimingRun`): a scratch domain registered here and never written.
    static func register(migrate: Bool = true, into store: UserDefaults = Prefs.store) {
        if migrate { migrateFromPreviousName() }
        store.register(defaults: [
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

            // The owner's pick, 2026-10-14: Baker's 87 KB step (`ImageDetail`).
            imageDetail: ImageDetail.initial.rawValue,

            // On by default. The failure mode of joining is a slightly noisier
            // extracted text — the tail of the word appears twice — and the
            // failure mode of not joining is a document whose long words cannot
            // be found at all. In narrow-column archival material that is most
            // of the words worth searching for.
            joinHyphenated: true,

            modelArrangement: ModelArrangement.off.rawValue,
            modelReader: "",
            modelMemoryGB: defaultModelMemoryGB(),
            accurateMode: false,
            accurateReader: AccurateReader.vision.rawValue,
            accurateNewspaperReader: AccurateReader.vision.rawValue,
            accuratePhotoReader: AccurateReader.vision.rawValue,
            accurateHandReader: AccurateReader.vision.rawValue,
            accurateEnabled: "",
            handTextPage: true,

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
