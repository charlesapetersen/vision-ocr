import AppKit
import SwiftUI

/// The settings panel: mac-ocr's recognition flags, plus where to find it.
/// Laid out to fit on one page without scrolling — help text lives in tooltips
/// rather than caption lines so nothing ends up below the fold.
struct SettingsView: View {
    /// True while a batch is running.
    ///
    /// `start()` snapshots every per-file setting (BUGS.md R5), so a change made
    /// now genuinely cannot affect the run in flight — and worse, changing the
    /// text format mid-run would write JSON into the `.txt` path `uniqueOutputs`
    /// already reserved. The panel says so and stops accepting edits rather than
    /// letting the user believe otherwise.
    var runInProgress = false

    /// Called after "Reset to Defaults", so the main window's destination — which
    /// `OCRModel` owns in memory and writes back to `UserDefaults` — is re-read
    /// rather than quietly restored from the stale value.
    var onReset: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @AppStorage(Prefs.mode) private var modeRaw = Prefs.Mode.searchablePDF.rawValue

    // Recognition (both modes)
    @AppStorage(Prefs.fast) private var fast = false
    @AppStorage(Prefs.languages) private var languages = ""
    @AppStorage(Prefs.languageCorrection) private var languageCorrection = true
    @AppStorage(Prefs.confidence) private var confidence = 0.0
    @AppStorage(Prefs.pdfDPIAuto) private var pdfDPIAuto = true
    @AppStorage(Prefs.pdfDPI) private var pdfDPI = 144
    @AppStorage(Prefs.password) private var password = ""
    @AppStorage(Prefs.customWords) private var customWords = ""
    @AppStorage(Prefs.minTextHeightOn) private var minTextHeightOn = false
    @AppStorage(Prefs.minTextHeight) private var minTextHeight = 0.0

    // Extract text
    @AppStorage(Prefs.textFormat) private var textFormatRaw = Prefs.TextFormat.text.rawValue

    // Searchable PDF
    @AppStorage(Prefs.rebuildImages) private var rebuildImages = true
    @AppStorage(Prefs.warnDigitalText) private var warnDigitalText = true
    @AppStorage(Prefs.useJBIG2) private var useJBIG2 = true
    @AppStorage(Prefs.rebuildMode) private var rebuildModeRaw =
        Flattener.Mode.auto.rawValue

    // Behaviour
    @AppStorage(Prefs.openWhenDone) private var openWhenDone = true
    @AppStorage(Prefs.binaryPath) private var binaryPath = ""
    @AppStorage(Prefs.concurrency) private var concurrency = Prefs.defaultConcurrency

    private var mode: Prefs.Mode { Prefs.Mode(rawValue: modeRaw) ?? .searchablePDF }
    private var rebuildMode: Flattener.Mode {
        Flattener.Mode(rawValue: rebuildModeRaw) ?? .auto
    }
    private let labelWidth: CGFloat = 116

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Reset to Defaults") { resetAll() }
                    .buttonStyle(.link).font(.caption)
                    .disabled(runInProgress)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 9)

            Divider()

            // The ScrollView below is the safety net for short displays — but
            // only if the sheet is allowed to be shorter than its content. It
            // was a hard 560x660, so on a display too short for 660 pt the sheet
            // did not shrink, it overflowed, and the fixed Done footer went off
            // the bottom of the screen. Escape still dismissed, which is not
            // something a user should have to know.
            if runInProgress {
                HStack(spacing: 6) {
                    Image(systemName: "clock").accessibilityHidden(true)
                    Text("A run is in progress. Settings are locked until it "
                         + "finishes — the running batch uses the settings it "
                         + "started with.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    recognitionSection
                    modeSection
                    behaviourSection
                    commandPreview
                }
                .padding(16)
                .disabled(runInProgress)
            }

            Divider()

            HStack {
                Text(mode.blurb)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .frame(width: 560)
        .frame(minHeight: 360, idealHeight: 660, maxHeight: 660)
        // Tool lookups are memoised for the session, negative results included,
        // so a user who followed this panel's own "brew install jbig2enc qpdf"
        // hint kept seeing the warning until they relaunched. Opening Settings
        // is the moment to look again: it is where the hint is read, and it
        // costs one login shell (~85 ms) rather than one per keystroke.
        //
        // Never mid-run, though: workers are resolving those same paths, and
        // re-probing can block the main thread on a login shell while they do.
        .onAppear { if !runInProgress { Runner.forgetToolPaths() } }
    }

    // MARK: - Recognition

    private var recognitionSection: some View {
        Box("Recognition") {
            HStack(spacing: 18) {
                Toggle("Fast (lower accuracy)", isOn: $fast)
                    .help("Vision's fast recognizer. Quicker, misses more.")
                Toggle("Language correction", isOn: $languageCorrection)
                    .help("Vision's spelling and context correction. On by default.")
                Spacer()
            }

            Row("Languages", labelWidth) {
                TextField("blank = automatic", text: $languages)
                    .help("BCP-47 codes in priority order, e.g. en-US, ja-JP. "
                          + "Blank lets Vision decide.")
            }

            Row("Min. confidence", labelWidth) {
                Slider(value: $confidence, in: 0...1)
                    .accessibilityLabel("Minimum confidence")
                    .accessibilityValue(String(format: "%.2f", confidence))
                Text(String(format: "%.2f", confidence))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 32, alignment: .trailing)
            }
            .help("Discards text recognized below this confidence. 0 keeps everything.")

            Row("PDF render DPI", labelWidth) {
                Toggle("Auto", isOn: $pdfDPIAuto).toggleStyle(.checkbox)
                    .accessibilityLabel("Automatic PDF render DPI")
                Stepper(value: $pdfDPI, in: 72...600, step: 24) {
                    Text("\(pdfDPI)")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 28, alignment: .trailing)
                        .foregroundStyle(pdfDPIAuto ? .secondary : .primary)
                }
                .disabled(pdfDPIAuto)
                .accessibilityLabel("PDF render DPI")
                .accessibilityValue("\(pdfDPI)")
                Spacer()
            }
            .help("Higher DPI can rescue small print, at the cost of speed.")

            Row("Ignore small text", labelWidth) {
                Toggle("", isOn: $minTextHeightOn).labelsHidden().toggleStyle(.checkbox)
                    .accessibilityLabel("Ignore small text")
                Slider(value: $minTextHeight, in: 0...0.2)
                    .disabled(!minTextHeightOn)
                    .accessibilityLabel("Minimum text height")
                    .accessibilityValue(String(format: "%.3f", minTextHeight))
                Text(String(format: "%.3f", minTextHeight))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 38, alignment: .trailing)
                    .foregroundStyle(minTextHeightOn ? .primary : .secondary)
            }
            .help("Skips text shorter than this fraction of the page height — "
                  + "useful for ignoring footers and marginalia.")

            Row("Custom words", labelWidth) {
                TextField("surnames, jargon, place names", text: $customWords)
                    .help("Comma, space or newline separated. Biases recognition "
                          + "toward vocabulary Vision wouldn't otherwise know.")
            }

            Row("PDF password", labelWidth) {
                SecureField("only for encrypted PDFs", text: $password)
            }
        }
    }

    // MARK: - Per-mode

    private var modeSection: some View {
        Box(mode == .text ? "Extract Text" : "Searchable PDF") {
            switch mode {
            case .text:
                Row("File format", labelWidth) {
                    Picker("", selection: $textFormatRaw) {
                        Text("Plain text (.txt)").tag(Prefs.TextFormat.text.rawValue)
                        Text("JSON — boxes + confidence").tag(Prefs.TextFormat.json.rawValue)
                        Text("JSON Lines — one per page").tag(Prefs.TextFormat.jsonl.rawValue)
                    }
                    .accessibilityLabel("Output file format")
                    .labelsHidden()
                    Spacer()
                }
            case .searchablePDF:
                Toggle("Rebuild page images first, discarding any old text layer",
                       isOn: $rebuildImages)
                    .help("mac-ocr adds its text layer on top of any existing one, which "
                          + "makes copied text come out doubled. Rebuilding the pages as "
                          + "images first means Vision's OCR is the only text in the result. "
                          + "Note the rebuild also re-encodes the pages, in the format "
                          + "chosen below. "
                          + "Only applied to files that already contain text.")

                if rebuildImages {
                    Toggle("Ask first if a PDF already has selectable text",
                           isOn: $warnDigitalText)
                        .help("The rebuild discards any existing text layer. For a scan "
                              + "that layer is a previous OCR pass and losing it is the "
                              + "point. For a born-digital PDF it is the real text, and "
                              + "OCR of a picture of it is worse — measured on one such "
                              + "book, 9% of the words were lost. This asks before "
                              + "replacing text that was not produced by OCR; turn it off "
                              + "if you are deliberately re-OCRing files whose embedded "
                              + "text is broken.")
                }

                if rebuildMode.canUseJBIG2 {
                    Toggle("Compress with JBIG2 (about a third the size)", isOn: $useJBIG2)
                        .help("Lossless JBIG2 instead of the Flate that CoreGraphics writes: "
                              + "same pixels at the same resolution, roughly a third the bytes. "
                              + "Needs jbig2enc and qpdf; without them the app falls back "
                              + "silently.")
                    if useJBIG2, rebuildImages, !JBIG2.isAvailable {
                        Text("Not installed — falling back to Flate. Install with: "
                             + JBIG2.installHint)
                            .font(.caption2).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if rebuildImages {
                    Row("Rebuild as", labelWidth) {
                        Picker("", selection: $rebuildModeRaw) {
                            ForEach(Flattener.Mode.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Rebuild pages as")
                        .frame(width: 150)
                        Text(rebuildMode.blurb)
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                if !rebuildImages {
                    Text("Without the rebuild, an already-OCR'd PDF keeps its old text "
                         + "layer and gains Vision's on top, so copied text appears twice. "
                         + "Compression is unavailable too, since it needs rebuilt pages.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// What to say under the mac-ocr path field.
    private var binaryStatus: String {
        let typed = binaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            return Runner.resolveBinary().map { "Found automatically at \($0)" }
                ?? "Not found — install with: npm install -g mac-ocr"
        }
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: typed, isDirectory: &isDirectory) {
            return "There is nothing at that path."
        }
        if isDirectory.boolValue {
            return "That is a folder. Point this at the mac-ocr program itself."
        }
        if !Runner.isRunnable(typed) {
            return "That file is not executable, so it cannot be run."
        }
        return "Using this path instead of the automatic one."
    }

    // MARK: - Behaviour

    private var behaviourSection: some View {
        Box("Behaviour") {
            Row("Files at once", labelWidth) {
                Stepper(value: $concurrency, in: 1...Prefs.maxConcurrency) {
                    Text("\(concurrency)")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 20, alignment: .trailing)
                }
                .accessibilityLabel("Files at once")
                .accessibilityValue("\(concurrency)")
                Text(concurrency == 1
                     ? "one at a time"
                     : concurrency == Prefs.defaultConcurrency
                        ? "matches this Mac's performance cores"
                        : "of \(Prefs.defaultConcurrency) performance cores")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            .help("mac-ocr already uses several cores per file, but running files "
                  + "concurrently is still much faster. Gains flatten around the "
                  + "number of performance cores (\(Prefs.defaultConcurrency) here); "
                  + "lower it if OCR is competing with other work.")

            Toggle("Open the output folder when finished", isOn: $openWhenDone)

            Row("mac-ocr path", labelWidth) {
                TextField(Runner.resolveBinary() ?? "not found", text: $binaryPath)
                    .accessibilityLabel("Path to the mac-ocr program")
                Button("Choose…") { chooseBinary() }
            }
            .help("Leave blank to find it automatically.")

            // Say what is actually true of the path typed in. The old caption
            // read "Using this path instead of the automatic one" even when the
            // path was a directory or a non-executable file and nothing could
            // run — which is the one case the user needs told.
            Text(binaryStatus)
                .font(.caption2)
                .foregroundStyle(Runner.resolveBinary() == nil ? .red : .secondary)
        }
    }

    // MARK: - Preview

    /// What a run would do with the settings as they stand — a cheap check that
    /// a setting does what its label claims.
    ///
    /// The binary is the resolved one, not the literal string "mac-ocr". The
    /// path field is the setting most likely to be wrong (U9), and a preview
    /// that hard-codes the name it is supposed to be verifying cannot verify it.
    private var commandPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COMMAND")
                .font(.caption2).bold().kerning(0.6)
                .foregroundStyle(.secondary)
            Text(Runner.previewLines(binary: Runner.resolveBinary() ?? "mac-ocr",
                                     file: URL(fileURLWithPath: "/…/scan.pdf"),
                                     outputFolder: savedOutputFolder)
                    .joined(separator: "\n"))
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.10)))
        }
    }

    private var savedOutputFolder: URL? {
        let path = UserDefaults.standard.string(forKey: Prefs.outputFolder) ?? ""
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    // MARK: - Helpers

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.showsHiddenFiles = true
        panel.message = "Select the mac-ocr executable"
        panel.prompt = "Use"
        if panel.runModal() == .OK, let url = panel.url { binaryPath = url.path }
    }

    private func resetAll() {
        let d = UserDefaults.standard
        for key in Prefs.allKeys {
            d.removeObject(forKey: key)
        }
        // The registered defaults survive removal, so the UI snaps back to
        // mac-ocr's own defaults rather than to empty values.
        onReset()
    }
}

/// A label + controls row with a consistent label column.
private struct Row<Content: View>: View {
    let label: String
    let width: CGFloat
    @ViewBuilder let content: Content

    init(_ label: String, _ width: CGFloat, @ViewBuilder content: () -> Content) {
        self.label = label
        self.width = width
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: width, alignment: .trailing)
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// A titled group of rows. Named `Box` to avoid colliding with SwiftUI's
/// `Section`, which wants a List or Form to live in.
private struct Box<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2).bold().kerning(0.6)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) { content }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.07)))
        }
    }
}
