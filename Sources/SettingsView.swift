import AppKit
import SwiftUI

/// The settings panel: the recognition options Vision takes, plus what to do
/// with the result.
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
    @AppStorage(Prefs.joinHyphenated) private var joinHyphenated = true
    @AppStorage(Prefs.preserveAnnotations) private var preserveAnnotations = false
    @AppStorage(Prefs.photoDetail) private var photoDetailRaw = Prefs.PhotoDetail.balanced.rawValue
    private var photoDetail: Prefs.PhotoDetail {
        Prefs.PhotoDetail(rawValue: photoDetailRaw) ?? .balanced
    }
    @AppStorage(Prefs.imageDetail) private var imageDetailRaw = Prefs.ImageDetail.initial.rawValue
    private var imageDetail: Prefs.ImageDetail {
        Prefs.ImageDetail(rawValue: imageDetailRaw) ?? .initial
    }
    /// The slider's position, 0 (most detail) to 4 (smallest files), over `ImageDetail`'s
    /// steps in order, so a stored value that is no step reads as the default's place.
    private var imageDetailStep: Binding<Double> {
        let steps = Prefs.ImageDetail.allCases
        return Binding(
            get: { Double(steps.firstIndex(of: imageDetail) ?? 0) },
            set: { imageDetailRaw = steps[min(max(Int($0.rounded()), 0), steps.count - 1)].rawValue })
    }
    @AppStorage(Prefs.rebuildMode) private var rebuildModeRaw =
        Flattener.Mode.auto.rawValue

    @AppStorage(Prefs.checkForUpdates) private var checkForUpdates = true
    @State private var updateStatus = ""
    /// The release page for an update this panel has found (A10.4). The
    /// banner is the app's usual surface for this, and it is unreachable
    /// after a failed automatic check — so the panel keeps its own.
    @State private var updateURL: URL?
    /// What the last "Start from" button did. View state, not a setting: it
    /// describes an action that happened, and must not become a "currently using
    /// preset X" flag — see `Prefs.Preset.apply`.
    @State private var presetSummary = ""

    // Behaviour
    @AppStorage(Prefs.openWhenDone) private var openWhenDone = true
    @AppStorage(Prefs.writeRunReport) private var writeRunReport = true
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
                    recognitionSection.disabled(runInProgress)
                    modeSection.disabled(runInProgress)
                    accurateSection
                    behaviourSection.disabled(runInProgress)
                    commandPreview
                }
                .padding(16)
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
        Box("Reading the text") {
            HStack(spacing: 18) {
                Toggle("Faster reading (more mistakes)", isOn: $fast)
                    .help("Reads more quickly but can miss or misread more words. Leave this off for the best text.")
                Toggle("Use spelling and context to help", isOn: $languageCorrection)
                    .help("Uses the surrounding words to help read unclear text. On by default; turn it off if it changes unusual names or spellings.")
                Spacer()
            }

            Row("Languages", labelWidth) {
                TextField("leave empty to detect automatically", text: $languages)
                    .help("Use Add to choose languages. The short codes shown here identify them: en-US means US English and ja-JP means Japanese. List your main language first. "
                          + "Leave empty to let the Mac decide.")
                // Asked of Vision directly, so it lists what this
                // macOS actually recognises rather than what someone remembers.
                Menu("Add") {
                    let available = Recogniser.supportedLanguages(fast: fast)
                    if available.isEmpty {
                        Text("Can't read the language list")
                    } else {
                        ForEach(available, id: \.self) { code in
                            Button(Self.languageLabel(code)) { append(language: code) }
                                .disabled(Runner.splitList(languages)
                                            .contains { $0.caseInsensitiveCompare(code)
                                                         == .orderedSame })
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Add a recognition language")
            }
            // Not decoration. A code this Mac does not recognise is not ignored:
            // Vision refuses an unsupported language outright, so every
            // file in the batch fails and the run produces nothing. Ticking Fast
            // is the common way to arrive here — it supports 6 languages against
            // the accurate recognizer's 30, so a working setting stops working
            // with no other sign.
            if !unsupportedLanguages.isEmpty {
                Row("", labelWidth) {
                    Label {
                        Text(unsupportedLanguages.count == 1
                             ? "\(unsupportedLanguages[0]) is not available"
                                + (fast ? " to fast recognition on this Mac." : " on this Mac.")
                             : "\(unsupportedLanguages.joined(separator: ", ")) are not available"
                                + (fast ? " to fast recognition on this Mac." : " on this Mac."))
                            + Text(" Every file would fail. ")
                            + Text(fast ? "Turn off Faster reading, or pick from the Add menu."
                                        : "Pick from the Add menu.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }

            Row("Unsure words", labelWidth) {
                Slider(value: $confidence, in: 0...1)
                    .accessibilityLabel("What to do with uncertain text")
                    .accessibilityValue(Prefs.confidenceReadout(confidence))
                Text(Prefs.confidenceReadout(confidence))
                    .font(.caption)
                    .frame(width: 96, alignment: .trailing)
                    .foregroundStyle(confidence > 0 ? .primary : .secondary)
            }
            .help("Vision scores how sure it is of every word it reads. Keeping "
                  + "everything is usually right for a scan: a rough guess at a "
                  + "smudged word is still something you can search for, and a "
                  + "wrong guess is rarely worse than a gap. Move this right and "
                  + "anything scored below the mark is thrown away instead.")

            // Only once it has been moved, so it costs nothing at the default.
            if let warning = Prefs.confidenceWarning(confidence) {
                Text(warning)
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Row("Reading detail", labelWidth) {
                Toggle("Automatic", isOn: $pdfDPIAuto).toggleStyle(.checkbox)
                    .accessibilityLabel("Choose reading detail automatically")
                Stepper(value: $pdfDPI, in: 72...600, step: 24) {
                    Text("\(pdfDPI) dots/inch")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 82, alignment: .trailing)
                        .foregroundStyle(pdfDPIAuto ? .secondary : .primary)
                }
                .disabled(pdfDPIAuto)
                .accessibilityLabel("Reading detail in dots per inch")
                .accessibilityValue("\(pdfDPI)")
                Spacer()
            }
            // A10.2. Qualified, because on the shipped default route this setting
            // cannot affect anything. Its only reader is `Recogniser.render`, which
            // runs when `bitmaps` is empty — and with the rebuild on, every page
            // arrives as a bitmap from `flatten`, which takes no DPI at all.
            // Measured on one fixture: 1431 characters at Auto, 72 and 600 alike
            // with the rebuild on; 1407 at 72 with it off. So the control is live in
            // Extract Text, and in Searchable PDF with the rebuild off, and inert
            // otherwise.
            //
            // A caption rather than a code change on purpose. H1 deleted
            // `ocrAllPages` and `strategy` for being settings that did nothing, and
            // this is not that: it does something in two of the four states. What
            // was wrong was the panel asserting it unconditionally while
            // `pageTooLarge`'s own error text already said "does not affect this
            // step" — the app holding two opinions about one control.
            .help("DPI means dots per inch: higher numbers give the reader a more detailed picture and take longer. Automatic is a good starting point.\n\n"
                  + "Only used in Extract "
                  + "Text, and in Searchable PDF with “Replace old selectable text” "
                  + "turned off. With replacement on, the app chooses picture detail from the "
                  + "file itself, and this control has no effect.")
            if mode == .searchablePDF, rebuildImages {
                Row("", labelWidth) {
                    Text("Not used while “Replace old selectable text” is on: the app then picks "
                         + "the detail itself.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }

            Row("Ignore small text", labelWidth) {
                Toggle("", isOn: $minTextHeightOn).labelsHidden().toggleStyle(.checkbox)
                    .accessibilityLabel("Ignore small text")
                Slider(value: $minTextHeight, in: 0...0.2)
                    .disabled(!minTextHeightOn)
                    .accessibilityLabel("Minimum text height")
                    .accessibilityValue(String(format: "%.1f percent of page height", minTextHeight * 100))
                Text(String(format: "%.1f%% of page", minTextHeight * 100))
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 85, alignment: .trailing)
                    .foregroundStyle(minTextHeightOn ? .primary : .secondary)
            }
            .help("Skips letters smaller than this percentage of the page height. Leave this off to keep small print; turn it on only "
                  + "to ignore page footers or small margin notes.")

            Row("Custom words", labelWidth) {
                TextField("surnames, jargon, place names", text: $customWords)
                    .help("Separate words with commas, spaces or new lines. Helps the reader recognise "
                          + "unusual names and words it might otherwise miss.")
            }

            Row("PDF password", labelWidth) {
                SecureField("if a PDF asks for a password", text: $password)
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
                        Text("For other software: JSON (.json)").tag(Prefs.TextFormat.json.rawValue)
                        Text("For other software: JSON Lines (.jsonl)").tag(Prefs.TextFormat.jsonl.rawValue)
                    }
                    .accessibilityLabel("Output file format")
                    .labelsHidden()
                    .help("Plain text is for reading and copying. JSON is a structured file for other software, "
                          + "with each word's position and how sure the reader was. JSON Lines stores one page "
                          + "per line. Choose plain text unless another program asks for one of these formats.")
                    Spacer()
                }
            case .searchablePDF:
                // A starting point, not a mode. Applying one writes ordinary
                // settings, which stay visible and editable below — there is no
                // "currently using X" state to drift out of sync with them.
                Row("Quick setup", labelWidth) {
                    ForEach(Prefs.Preset.allCases) { preset in
                        Button(preset.label) {
                            let summary = preset.summary(afterChanging: preset.apply())
                            presetSummary = summary
                            // Written *and* spoken. A line in the panel is
                            // readable but not announced, so on its own it
                            // answers U30 for the eye and leaves the button just
                            // as silent for VoiceOver — which is the half of U8's
                            // objection that is about being reachable at all.
                            NSAccessibility.post(
                                element: NSApp as Any,
                                notification: .announcementRequested,
                                userInfo: [.announcement: summary,
                                           .priority: NSAccessibilityPriorityLevel.high.rawValue])
                        }
                            .help(preset.blurb + "\n\nSets the options below; "
                                  + "everything stays editable afterwards. Your "
                                  + "languages, output folder and file handling "
                                  + "are not touched.")
                    }
                    Spacer()
                }
                // U30 · the buttons used to write six or seven settings and give
                // no sign they had done anything. Deliberately a line in the
                // panel and not a tooltip: a tooltip is mouse-only, which is the
                // objection U8 already recorded. It names the settings that
                // actually moved, so it doubles as an explanation of what the
                // preset *is* — and it says so plainly when nothing moved, which
                // is the honest answer for a preset the panel already matched.
                if !presetSummary.isEmpty {
                    Row("", labelWidth) {
                        Text(presetSummary)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }

                Toggle("Replace old selectable text (recommended)",
                       isOn: $rebuildImages)
                    .help("Makes a fresh picture of each page that needs it, then adds newly read text. "
                          + "This replaces any previous selectable text so copied words do not appear twice. "
                          + "The smaller-PDF option makes a fresh picture of every page. Page appearance below "
                          + "controls its colour and photo detail. The original file is kept.")

                Toggle("Keep highlights and notes", isOn: $preserveAnnotations)
                    .help("Carries your highlights and notes into the new PDF and checks their positions. "
                          + "If the checks fail, no finished file is saved. Leave this on for marked-up PDFs. "
                          + "Off by default because checking takes extra time. Without it, making fresh page "
                          + "pictures drops these marks. Form fields and links are not carried; the report "
                          + "lists what was left out.")

                Toggle("Find words broken across two lines", isOn: $joinHyphenated)
                    .help("A word split by a line break is read as two pieces — "
                          + "\u{201C}merito-\u{201D} at the end of one line and "
                          + "\u{201C}cracy\u{201D} at the start of the next — so searching "
                          + "the finished PDF for \u{201C}meritocracy\u{201D} finds nothing. "
                          + "In narrow columns that is a lot of words, and they tend to be "
                          + "the long, specific ones worth searching for.\n\n"
                          + "With this on, the whole word is also written into the first "
                          + "line, so a search finds it. The cost is that the second half "
                          + "appears twice if you copy the text out. Nothing is removed "
                          + "either way.")

                if rebuildMode.canUseJBIG2 {
                    Toggle("Make text pages smaller", isOn: $useJBIG2)
                        .help("Uses a storage method called JBIG2 to keep black-and-white page pictures "
                              + "unchanged in about a third of the space. This requires fresh pictures of "
                              + "every page. Photographs and colour pages are stored separately, with the "
                              + "detail chosen below. Turn on Replace old selectable text to use compression.")
                    if useJBIG2, rebuildImages, !JBIG2.isAvailable {
                        Text("The optional compression tools are missing; PDFs will be larger. For help installing them: "
                             + JBIG2.installHint)
                            .font(.caption2).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Only meaningful when there is a JBIG2 stencil to layer
                    // against, which is why it sits inside this branch.
                    if useJBIG2 {
                        Row("Photo detail", labelWidth) {
                            Picker("", selection: $photoDetailRaw) {
                                ForEach(Prefs.PhotoDetail.allCases) {
                                    Text($0.label).tag($0.rawValue)
                                }
                            }
                            .labelsHidden()
                            // `labelsHidden()` hides the label from VoiceOver as
                            // well as from the eye, and the row's "Photo detail"
                            // text is a sibling rather than the control's label.
                            // Every other picker in this file carries one; this
                            // was the omission.
                            .accessibilityLabel("Photo detail")
                            .pickerStyle(.segmented)
                            .help("\(photoDetail.label): \(photoDetail.blurb)\n\n"
                                  + "On a page that has both text and a picture, the two are "
                                  + "stored separately. This changes the picture's detail, "
                                  + "while printed text keeps its full detail. No part of "
                                  + "the page is cropped. Smaller files can lose fine picture detail.\n\n"
                                  + Prefs.PhotoDetail.allCases.map {
                                      "\($0.label): \($0.blurb)"
                                  }.joined(separator: "\n\n"))
                        }

                        // photo-pdf-size. A page that came from a photo or another image
                        // file and holds only text: its words are a sharp stencil at every
                        // step, and this sets how much of the paper behind them is kept.
                        Row("Photographed pages", labelWidth) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("More detail").font(.caption)
                                    Slider(value: imageDetailStep,
                                           in: 0...Double(Prefs.ImageDetail.allCases.count - 1),
                                           step: 1)
                                        .accessibilityLabel("Photographed pages")
                                        .accessibilityValue("\(imageDetail.label), "
                                                            + "about \(imageDetail.exampleKB) KB a page")
                                    Text("Smaller files").font(.caption)
                                }
                                Text("\(imageDetail.blurb) A phone photo of a typed letter "
                                     + "comes to about \(imageDetail.exampleKB) KB (kilobytes; "
                                     + "1,000 KB is 1 MB).")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .help("For a photo of a page, or any image file you add, when the "
                                  + "page holds only text. The words are kept sharp at every "
                                  + "step; this sets how much of the paper behind them is kept, "
                                  + "and with it signatures, pencil and faint marks. The photo "
                                  + "itself came to 831 KB before it was compressed.")
                        }
                    }
                }

                if rebuildImages {
                    Row("Page appearance", labelWidth) {
                        Picker("", selection: $rebuildModeRaw) {
                            ForEach(Flattener.Mode.allCases) {
                                Text($0 == .grayscale ? "Grey tones" : $0.label).tag($0.rawValue)
                            }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Page appearance")
                        .frame(width: 150)
                        Text(rebuildMode == .auto ? "Keeps colour and pictures; makes text pages smaller."
                             : rebuildMode == .blackAndWhite ? "Smallest files; photographs can turn into blotches."
                             : "Keeps photo shades; turns all colour grey. Larger files.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                }

                if !rebuildImages {
                    Text("Keeping the old selectable text and adding new text can make copied words "
                         + "appear twice. Making smaller PDFs is also unavailable without replacement.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Outside the switch, and guarded by the *same* predicate `start()`
            // uses (A10.1). It used to be drawn inside `case .searchablePDF` and
            // under `if rebuildImages`, so in Extract Text — where the setting is
            // just as live — there was no control for it anywhere: tick "Don't ask
            // again" once and Extract Text silently OCRs a picture of good text,
            // with nothing in the panel able to turn the question back on.
            if OCRModel.warnsAboutDigitalText(mode: mode, rebuildImages: rebuildImages) {
                Toggle("Ask first if a PDF already has selectable text",
                       isOn: $warnDigitalText)
                    .help(mode == .text
                          ? "PDFs made on a computer often already have correct text. Reading a picture "
                            + "of it can introduce mistakes. Asks before doing that; the original is kept. "
                            + "Turn this off only if you want to read such files again because their text is broken."
                          : "Asks before replacing text in PDFs made on a computer, where it is usually "
                            + "better than text read from a picture. Old text read from a scan is replaced "
                            + "without asking. Turn this off only if you intend to replace the computer-made text.")
            }
        }
    }

    // MARK: - Accurate mode

    private var accurateSection: some View {
        AccurateSettingsSection(runInProgress: runInProgress)
    }

    // MARK: - Behaviour

    private var behaviourSection: some View {
        Box("Saving and app updates") {
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
                        ? "recommended for this Mac"
                        : "\(Prefs.defaultConcurrency) is recommended for this Mac")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            .help("Each file uses several parts of the Mac's processor. Reading multiple files "
                  + "at once is often faster, but uses more memory. The recommended maximum is "
                  + "\(Prefs.defaultConcurrency) on this Mac; "
                  + "lower it if you want other apps to stay responsive.")

            Toggle("Open the output folder when finished", isOn: $openWhenDone)

            Toggle("Write a report for each finished batch", isOn: $writeRunReport)
                .help("A text file listing every input, where its output went, "
                      + "what happened to it and the settings that produced it. "
                      + "Written to ~/Library/Logs/VisionOCR. The results pane "
                      + "keeps the same information only until the window closes.")
            Row("", labelWidth) {
                Text(verbatim: RunReport.directory.path)
                    .font(.caption2).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Show Reports") {
                    // Create it first: revealing a folder that does not exist
                    // yet does nothing at all, and "nothing happened" is the
                    // worst answer a button can give.
                    try? FileManager.default.createDirectory(
                        at: RunReport.directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(RunReport.directory)
                }
                .disabled(!writeRunReport)
            }

            // Stated in full rather than as a bare toggle: this is the only
            // thing in the app that touches the network, and someone who chose
            // it partly because nothing leaves their Mac deserves to read
            // exactly what does.
            Toggle("Check for new versions", isOn: $checkForUpdates)
                .help("Asks GitHub once a day whether a newer version exists. "
                      + "Sends nothing about you or your documents — no "
                      + "identifiers, no telemetry — and never installs "
                      + "anything on its own.")
            Row("", labelWidth) {
                Text("Update checks and optional reader downloads use the internet. Your documents "
                     + "never leave your Mac either way.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Check Now") {
                    updateStatus = "Checking…"
                    Updater.check(force: true) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .available(let r):
                                updateStatus = "\(r.version) is available"
                                // A10.4. The panel kept `r.version` and threw away
                                // `r.url`, and the banner — the only surface with
                                // *What's New* and *Download* — is set from the
                                // non-forced `.task`, which returns immediately when
                                // `isDue()` is false. A successful forced check then
                                // stamps the full 24-hour interval. So after any
                                // failed automatic check (offline, 5xx, rate limit),
                                // Check Now read "99.0.0 is available" and gave no
                                // link, no button and no banner — this session or
                                // for the next day. Keeping the URL costs one line.
                                updateURL = r.url
                            case .upToDate:
                                updateStatus = "Up to date (\(Updater.currentVersion))"
                                updateURL = nil
                            case .failed(let why):
                                updateStatus = "Could not check — \(why)"
                                updateURL = nil
                            }
                        }
                    }
                }
                .buttonStyle(.link).font(.caption)
            }
            if !updateStatus.isEmpty {
                Row("", labelWidth) {
                    Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                    if let updateURL {
                        Link("Download", destination: updateURL)
                            .font(.caption)
                            .accessibilityLabel("Download the available update")
                    }
                    Spacer()
                }
            }

            // The mac-ocr path field used to sit here, with a caption saying
            // whether what you typed could actually be run. Recognition no
            // longer runs anything: there is no path to get wrong, and nothing
            // to install. The compression tools are still located the same
            // awkward way, and the preview below names them.
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
            // "COMMAND" was the wrong word for what this is. Only one of its
            // lines is a command; the rest is a numbered description of the
            // pipeline, and two of them are the only place the app explains why
            // Start is disabled or why compression was skipped. Labelling that
            // COMMAND tells the person who most needs it that it is not for
            // them — and this app's whole claim is that there is no Terminal
            // step.
            Text("WHAT WILL HAPPEN")
                .font(.caption2).bold().kerning(0.6)
                .foregroundStyle(.secondary)
            Text(Runner.previewLines(file: URL(fileURLWithPath: "/…/scan.pdf"),
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
        let path = Prefs.store.string(forKey: Prefs.outputFolder) ?? ""
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    // MARK: - Helpers

    /// The codes the current recognizer would refuse. Recomputed with `fast`,
    /// which is the whole point: the warning has to appear the moment the Fast
    /// toggle invalidates a language, not on the next run.
    private var unsupportedLanguages: [String] {
        Recogniser.unsupportedLanguages(in: languages, fast: fast)
    }

    /// `Japanese — ja-JP`. The code stays visible because it is what is stored,
    /// what the command preview shows and what a bug report will quote.
    static func languageLabel(_ code: String) -> String {
        let name = Locale.current.localizedString(forIdentifier: code)
            ?? Locale.current.localizedString(forLanguageCode: String(code.prefix(2)))
        guard let name, !name.isEmpty else { return code }
        return "\(name) — \(code)"
    }

    /// Appends to the priority list, preserving order and separator style.
    private func append(language code: String) {
        let existing = Runner.splitList(languages)
        guard !existing.contains(where: { $0.caseInsensitiveCompare(code) == .orderedSame })
        else { return }
        languages = (existing + [code]).joined(separator: ", ")
    }

    private func resetAll() {
        let d = Prefs.store
        // A10.6. `skippedVersion` is in `allKeys` — it has to be, or `resetAll`'s
        // own enumeration check would flag it — but it is not a *setting*. It is a
        // record of something the user already told the app once ("don't offer me
        // 1.9.0 again"), and Reset to Defaults un-skipped it, so the next check
        // re-offered a version they had dismissed. Same shape as `lastUpdateCheck`,
        // which is bookkeeping rather than preference for the same reason.
        for key in Prefs.allKeys where !Prefs.notASetting.contains(key) {
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

/// The download under way, whichever reader it is for, or how the last one ended.
private struct DownloadProgressRow: View {
    let labelWidth: CGFloat
    @ObservedObject private var downloads = DownloadRunner.shared

    var body: some View {
        if downloads.current != nil {
            Row("Download", labelWidth) {
                ProgressView(value: downloads.fraction).frame(width: 120)
                Button("Stop Download") { downloads.stop() }
                Text(downloads.status ?? "")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        } else if let status = downloads.status {
            Row("Download", labelWidth) {
                Text(status).font(.caption2).foregroundStyle(downloads.failed == nil ? Color.secondary : .orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
    }
}

/// Why a kind of page is not read by the reader stored for it (`AccurateReader.warning`).
private struct PageKindWarnings: View {
    let labelWidth: CGFloat
    @AppStorage(Prefs.accurateReader) private var accurateReader = Prefs.AccurateReader.vision.rawValue
    @AppStorage(Prefs.accurateNewspaperReader) private var accurateNewspaperReader =
        Prefs.AccurateReader.vision.rawValue
    @AppStorage(Prefs.accuratePhotoReader) private var accuratePhotoReader = Prefs.AccurateReader.vision.rawValue
    @AppStorage(Prefs.accurateEnabled) private var enabledRaw = ""
    @AppStorage(Prefs.modelMemoryGB) private var modelMemoryGB = Prefs.defaultModelMemoryGB()
    @ObservedObject private var downloads = DownloadRunner.shared

    var body: some View {
        ForEach(lines, id: \.self) { line in
            Row("", labelWidth) {
                Text(line).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
    }

    private var lines: [String] {
        let enabled = Prefs.AccurateReader.enabled(raw: enabledRaw)
        return [(Recogniser.PageKind.newspaper, "newspapers", accurateNewspaperReader),
                (.photograph, "photographed pages", accuratePhotoReader),
                (.other, "other documents", accurateReader)].compactMap { kind, title, raw in
            Prefs.AccurateReader.warning(raw, kind, title, memoryGB: modelMemoryGB, enabled: enabled)
        }
    }
}

/// The two accurate-mode dialogs' one way out; not "Done", which the panel's own footer is named.
private struct DialogDone: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Spacer()
            Button("Close") { dismiss() }.keyboardShortcut(.defaultAction)
        }
    }
}

/// The models dialog: each model reader with what it downloads, the memory it needs and what it
/// reads well. A download starts only from the confirmation, which names the total size.
struct AccurateModelsDialog: View {
    @AppStorage(Prefs.accurateEnabled) private var enabledRaw = ""
    @AppStorage(Prefs.modelMemoryGB) private var modelMemoryGB = Prefs.defaultModelMemoryGB()
    @ObservedObject private var downloads = DownloadRunner.shared
    @State private var confirming: Prefs.AccurateReader?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Download extra readers").font(.headline)
            Text("A reader turns a scanned picture into text you can select and search. Vision is already "
                 + "built in and is a good starting point. These optional readers may help with difficult print. "
                 + "They work on your Mac; your documents are never uploaded.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Prefs.AccurateReader.downloadable, id: \.self) { reader in
                        let fetch = reader.toFetch()
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(reader.name).fontWeight(.semibold)
                                Spacer()
                                action(reader, fetch)
                            }
                            Text(reader.readsWell).fixedSize(horizontal: false, vertical: true)
                            Text("\(fetch.isEmpty ? "Downloaded" : "Download: " + DownloadRunner.size(fetch)). "
                                 + "Disk space: about \(reader.diskSpace). "
                                 + "Working memory: about \(String(format: "%.1f", reader.memoryNeedGB)) GB.")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if reader.memoryNeedGB > modelMemoryGB {
                                Text("Needs more than your \(Int(modelMemoryGB)) GB memory limit. Raise the limit "
                                     + "in Settings before choosing this reader.")
                                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .font(.caption)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.07)))
                    }
                    Text("Download sizes include any shared reading software and the helper that finds columns "
                         + "on a page. These parts are fetched once, so later downloads can be smaller. "
                         + "Disk space includes these shared parts; extra space is needed during installation. "
                         + "MB means megabytes; 1,000 MB is about 1 GB (a gigabyte). Working memory is "
                         + "temporary space used while reading; other apps need some too.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxHeight: 430)
            Text("After downloading, we check that reader's speed automatically on sample pages. You can stop "
                 + "the check. Then use Choose pages in Settings to decide where to use the reader. "
                 + "Turning off “Offer in Choose pages” keeps the download, and Vision reads those pages again.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DownloadProgressRow(labelWidth: 70)
            DialogDone()
        }
        .padding(16)
        .frame(width: 660)
        .frame(minHeight: 360, idealHeight: 600, maxHeight: 640)
        .alert(confirming.map { "Download \($0.name)?" } ?? "",
               isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
               presenting: confirming) { reader in
            Button("Download \(DownloadRunner.size(reader.toFetch()))") {
                Prefs.AccurateReader.setEnabled(reader, true, Prefs.store)
                downloads.start(reader.toFetch(), reader: reader)
            }
            Button("Cancel", role: .cancel) {}
        } message: { reader in
            Text(Prefs.AccurateReader.confirmation(reader, reader.toFetch()))
        }
    }

    @ViewBuilder
    private func action(_ reader: Prefs.AccurateReader, _ fetch: [ModelDownloads.Item]) -> some View {
        if !fetch.isEmpty, downloads.covers(fetch) {
            Text("Downloading…").foregroundStyle(.secondary)
        } else if fetch.isEmpty {
            Toggle("Offer in Choose pages", isOn: Binding(
                get: { Prefs.AccurateReader.enabled(raw: enabledRaw).contains(reader) },
                set: { Prefs.AccurateReader.setEnabled(reader, $0, Prefs.store) }))
                .accessibilityLabel("Allow \(reader.name) in page choices")
        } else {
            Button("Download…") { confirming = reader }
                .accessibilityLabel("Download and enable \(reader.name)")
        }
    }
}

/// Choices and measured tradeoffs, with ordinary language kept beside the figures.
struct AccuratePageKindsDialog: View {
    @AppStorage(Prefs.accurateReader) private var accurateReader = Prefs.AccurateReader.vision.rawValue
    @AppStorage(Prefs.accurateNewspaperReader) private var accurateNewspaperReader =
        Prefs.AccurateReader.vision.rawValue
    @AppStorage(Prefs.accuratePhotoReader) private var accuratePhotoReader = Prefs.AccurateReader.vision.rawValue
    @AppStorage(Prefs.accurateEnabled) private var enabledRaw = ""
    @AppStorage(Prefs.modelMemoryGB) private var modelMemoryGB = Prefs.defaultModelMemoryGB()
    @AppStorage(Prefs.accurateTiming) private var accurateTimingData = Data()
    @ObservedObject private var downloads = DownloadRunner.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose how to read your pages").font(.headline)
            Text("Keep Vision for a fast start. An extra reader can reduce wrong or missing words, but "
                 + "takes longer. The app sorts every page into one of three kinds by itself and uses your "
                 + "choice for that kind. Photographed pages are pages taken with a camera or phone; a page a "
                 + "scanner app has flattened and evenly lit usually counts as a scan. A photo of a newspaper "
                 + "counts as a newspaper. "
                 + "“Other documents” covers everything else: scanned books, articles and letters, and pages "
                 + "made on a computer, such as born-digital PDFs and screenshots.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    kind("Newspapers", .newspaper, $accurateNewspaperReader)
                    kind("Photographed pages", .photograph, $accuratePhotoReader)
                    kind("Other documents", .other, $accurateReader)
                    PageKindWarnings(labelWidth: 0)
                    Text("A reader is a method of reading text. Vision is built in; Vision, section by section "
                         + "reads a newspaper's separate blocks. PaddleOCR-VL and Falcon-OCR are optional extra "
                         + "readers. Only downloaded readers with Offer in Choose pages turned on, and enough memory, "
                         + "can be selected. Add them in Downloads in Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Errors means words wrong or missing out of every 1,000; lower is better. "
                         + "We counted these on 67 sample pages, and photographed pages on 31 photos, a small "
                         + "sample of typed and printed pages. Your documents may differ. Times include "
                         + "the whole reading process; “4.1× Vision” means about four times as long as Vision. "
                         + "Memory is temporary working space, in GB (gigabytes); “no extra” means none beyond "
                         + "the app's normal use; a reader needs a little more on some kinds of page than on others. "
                         + TimingRunner.speedNote(Prefs.AccurateTiming(accurateTimingData)))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxHeight: 460)
            DialogDone()
        }
        .padding(16)
        .frame(width: 720)
        .frame(minHeight: 360, idealHeight: 600, maxHeight: 640)
    }

    @ViewBuilder
    private func kind(_ title: String, _ kind: Recogniser.PageKind, _ choice: Binding<String>) -> some View {
        let enabled = Prefs.AccurateReader.enabled(raw: enabledRaw)
        let ready = Prefs.AccurateReader.ready(kind, memoryGB: modelMemoryGB, enabled: enabled)
        let chosen = Prefs.AccurateReader.chosen(choice.wrappedValue, kind, memoryGB: modelMemoryGB, enabled: enabled)
        let timing = Prefs.AccurateTiming(accurateTimingData)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Picker("", selection: Binding(get: { chosen.rawValue }, set: { choice.wrappedValue = $0 })) {
                    ForEach(ready, id: \.self) { Text($0.name).tag($0.rawValue) }
                    if !ready.contains(chosen) {
                        Text("\(chosen.name) (not downloaded)").tag(chosen.rawValue)
                    }
                }
                .labelsHidden().frame(width: 260)
                .accessibilityLabel("Reader for \(title.lowercased())")
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    ForEach(["Reader", "Errors / 1,000", "Time per page", "Memory", "Available?"], id: \.self) {
                        Text($0).bold()
                    }
                }
                ForEach(Prefs.AccurateReader.allCases.filter { $0.figures(kind) != nil }, id: \.self) { reader in
                    GridRow {
                        Text(reader.name).fixedSize(horizontal: false, vertical: true)
                        ForEach(Array((reader.cells(kind, timing: timing) ?? []).dropLast().enumerated()), id: \.offset) {
                            Text($0.element).fixedSize(horizontal: false, vertical: true)
                        }
                        Text(reader.state(kind, memoryGB: modelMemoryGB, enabled: enabled))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(ready.contains(reader) ? .primary : .secondary)
                    .fontWeight(reader == chosen ? .semibold : .regular)
                }
            }
            .font(.caption)
        }
    }
}

/// The accurate mode's downloads (`ModelDownloads`), one item at a time, kept outside the panel
/// so that closing Settings neither stops them nor lets a second copy of one start beside it.
@MainActor
final class DownloadRunner: ObservableObject {
    static let shared = DownloadRunner()
    private let timing: TimingRunner
    private var readersToTime: Set<Prefs.AccurateReader> = []

    init(timing: TimingRunner? = nil) { self.timing = timing ?? .shared }

    /// What is downloading, and how far it has got, 0...1.
    @Published private(set) var current: ModelDownloads.Item?
    @Published private(set) var fraction = 0.0
    /// What the download is doing, or how the last one ended; nil before any.
    @Published private(set) var status: String?
    /// The item the last download failed on, with why; cleared when one is started again.
    @Published private(set) var failed: (item: ModelDownloads.Item, why: String)?
    private var queue: [ModelDownloads.Item] = []
    private var task: Task<Void, Never>?
    /// Which run is current: a stopped one may take seconds to unwind (hashing a 1 GB file),
    /// and must neither report nor clear what a run started after it is doing.
    private var generation = 0
    private var swept = false

    func start(_ items: [ModelDownloads.Item], reader: Prefs.AccurateReader? = nil) {
        if let reader, !items.isEmpty { readersToTime.insert(reader) }
        for item in items where item != current && !queue.contains(item) { queue.append(item) }
        guard task == nil, !queue.isEmpty else { return }
        if !swept {
            ModelDownloads.sweep(home: ModelRuntime.home())
            swept = true
        }
        failed = nil
        generation += 1
        let mine = generation
        task = Task { await drain(mine) }
    }

    /// Stops at once, as far as the panel is concerned; nothing stopped is installed.
    func stop() {
        guard task != nil || !queue.isEmpty else { return }
        queue = []
        readersToTime = []
        task?.cancel()
        task = nil
        generation += 1
        if let current { status = "Stopped; \(current.name) was not installed." }
        current = nil
    }

    /// Whether every one of `items` is downloading or waiting to.
    func covers(_ items: [ModelDownloads.Item]) -> Bool {
        !items.isEmpty && items.allSatisfy { $0 == current || queue.contains($0) }
    }

    private func drain(_ mine: Int) async {
        // The mode can be turned off where this panel cannot see it, by an imported settings file.
        while mine == generation, !queue.isEmpty, Prefs.store.bool(forKey: Prefs.accurateMode) {
            let item = queue.removeFirst()
            if item.installed() { continue }
            current = item
            fraction = 0
            status = "Downloading \(item.name), \(Self.size([item]))…"
            let total = Double(item.plan.bytes)
            do {
                try await ModelDownloads.install(item.plan, home: ModelRuntime.home(),
                                                 source: .current()) { bytes in
                    let f = min(1, Double(bytes) / total)
                    DispatchQueue.main.async {
                        let me = self
                        if me.generation == mine, f - me.fraction >= 0.005 || f == 1 { me.fraction = f }
                    }
                }
                guard mine == generation else { return }
                status = "Downloaded \(item.name)."
            } catch {
                // Stopped: `stop` has said so, and a later run may be under way.
                guard mine == generation else { return }
                // Readers already complete keep their check; `afterDownload` skips the one that
                // is still missing a part.
                queue = []
                let why = error.localizedDescription
                failed = (item, why)
                status = "\(item.name) could not be downloaded: \(why)."
            }
        }
        guard mine == generation else { return }
        queue = []
        current = nil
        task = nil
        let ready = readersToTime
        readersToTime = []
        // Only readers requested by this download: installing a shared part must not
        // re-time an unrelated reader that was already available on this Mac.
        for reader in Prefs.AccurateReader.downloadable where ready.contains(reader) {
            timing.afterDownload(reader)
        }
    }

    /// Why the last download of one of `items` failed, as a sentence; nil if none did.
    func failure(_ items: [ModelDownloads.Item]) -> String? {
        guard let failed, items.contains(failed.item) else { return nil }
        return "The last try failed: \(failed.why)."
    }

    /// The download size of `items`, as the table states it.
    nonisolated static func size(_ items: [ModelDownloads.Item]) -> String {
        let mb = items.reduce(0) { $0 + $1.downloadMB }
        return mb < 1000 ? "\(mb) MB" : String(format: "%.1f GB", Double(mb) / 1000)
    }
}

/// Accurate mode can be rendered on its own and keeps Stop available during a document batch.
struct AccurateSettingsSection: View {
    var runInProgress = false
    private let labelWidth: CGFloat = 116
    // Accurate mode
    @AppStorage(Prefs.accurateMode) private var accurateMode = false
    @AppStorage(Prefs.accurateReader) private var accurateReader = Prefs.AccurateReader.vision.rawValue
    @AppStorage(Prefs.accurateNewspaperReader) private var accurateNewspaperReader =
        Prefs.AccurateReader.vision.rawValue
    @AppStorage(Prefs.accuratePhotoReader) private var accuratePhotoReader = Prefs.AccurateReader.vision.rawValue
    @AppStorage(Prefs.modelMemoryGB) private var modelMemoryGB = Prefs.defaultModelMemoryGB()
    @AppStorage(Prefs.accurateTiming) private var accurateTimingData = Data()
    @ObservedObject private var timingRun = TimingRunner.shared
    @ObservedObject private var downloads = DownloadRunner.shared
    private var timing: Prefs.AccurateTiming? { Prefs.AccurateTiming(accurateTimingData) }
    @AppStorage(Prefs.accurateEnabled) private var accurateEnabled = ""
    @State private var showModels = false
    @State private var showPageKinds = false

    /// The readers the owner approved for each kind of page (C57), off by default. A stored
    /// choice that stops fitting under the memory slider is run as Vision
    /// (`Prefs.AccurateReader.chosen`), which `PageKindWarnings` says.
    var body: some View {
        Box("Accurate mode") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Off unless you turn it on, and best left off for everyday scans. Vision, the reader built into "
                     + "your Mac, already reads most books and articles well. No download is needed.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Try extra readers for difficult print", isOn: $accurateMode)
                    .help("A reader turns the words in a scanned picture into text you can select and search. "
                          + "Extra readers may correct more words, but take longer. Your documents stay on your Mac.")
                    .onChange(of: accurateMode) { on in if !on { downloads.stop(); timingRun.stop() } }
                if accurateMode {
                    Text("Newspapers can benefit most. Our extra readers took about 1½–3 times as long on "
                         + "newspapers and 4 times as long on books and articles. Results vary by document.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Row("1. Add a reader", labelWidth) {
                        Button("Downloads…") { showModels = true }
                            .help("Compare extra readers, their space and memory needs, then choose what to download.")
                        Spacer()
                    }
                    Text(modelsSummary).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DownloadProgressRow(labelWidth: labelWidth)
                    Row("2. Use it for", labelWidth) {
                        Button("Choose pages…") { showPageKinds = true }
                        Spacer()
                    }
                    Text(kindsSummary).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Downloading makes a reader available; choose it for a kind of page to use it. "
                         + "Until then, Vision keeps reading everything. Your documents never leave your Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PageKindWarnings(labelWidth: labelWidth)
                    Row("Memory limit", labelWidth) {
                        Slider(value: $modelMemoryGB, in: Prefs.modelMemoryRange, step: 1)
                            .accessibilityLabel("Most working memory an extra reader may use")
                            .accessibilityValue("\(Int(modelMemoryGB)) gigabytes")
                        Text("\(Int(modelMemoryGB)) GB")
                            .frame(width: 42, alignment: .trailing)
                    }
                    .onChange(of: modelMemoryGB) { gb in
                        accurateReader = Prefs.AccurateReader.chosen(accurateReader, .other, memoryGB: gb).rawValue
                        accurateNewspaperReader = Prefs.AccurateReader.chosen(accurateNewspaperReader, .newspaper,
                                                                              memoryGB: gb).rawValue
                        accuratePhotoReader = Prefs.AccurateReader.chosen(accuratePhotoReader, .photograph,
                                                                          memoryGB: gb).rawValue
                    }
                    Text("Memory is temporary working space, separate from disk storage. GB means gigabytes. "
                         + "The default is \(Int(Prefs.defaultModelMemoryGB())) GB on this Mac. If a reader exceeds "
                         + "the limit, it stops and Vision's text is kept for that page. A reader that needs more "
                         + "than the limit cannot be chosen.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if Prefs.physicalGB() < 16 {
                        Label("This Mac has \(Int(Prefs.physicalGB().rounded())) GB in total. Extra readers may "
                              + "slow other apps; keep the limit low.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .disabled(runInProgress)
            // Cancellation stays available while settings themselves are locked by a batch.
            if accurateMode || timingRun.running { timingRow }
        }
        .sheet(isPresented: $showModels) { AccurateModelsDialog() }
        .sheet(isPresented: $showPageKinds) { AccuratePageKindsDialog() }
    }

    /// Each model reader's state: not downloaded, downloaded, enabled.
    private var modelsSummary: String {
        let enabled = Prefs.AccurateReader.enabled(raw: accurateEnabled)
        return Prefs.AccurateReader.downloadable.map { reader in
            "\(reader.name) " + (!reader.toFetch().isEmpty ? "not downloaded"
                                 : enabled.contains(reader) ? "available to choose" : "downloaded, turned off")
        }.joined(separator: "; ") + "."
    }

    /// Which reader each kind of page is read with.
    private var kindsSummary: String {
        let enabled = Prefs.AccurateReader.enabled(raw: accurateEnabled)
        let news = Prefs.AccurateReader.chosen(accurateNewspaperReader, .newspaper, memoryGB: modelMemoryGB,
                                               enabled: enabled)
        let photo = Prefs.AccurateReader.chosen(accuratePhotoReader, .photograph, memoryGB: modelMemoryGB,
                                                enabled: enabled)
        let other = Prefs.AccurateReader.chosen(accurateReader, .other, memoryGB: modelMemoryGB, enabled: enabled)
        return "Newspapers: \(news.name). Photographed pages: \(photo.name). Other documents: \(other.name)."
    }

    /// "Measure on this Mac": times the readers that are ready here and replaces the speed
    /// column (`TimingRun`). Speed only; the accuracy column stays ours.
    @ViewBuilder
    private var timingRow: some View {
        let legs = TimingRun.legs(memoryGB: modelMemoryGB)
        VStack(alignment: .leading, spacing: 6) {
        Text("A speed check starts by itself after each download, once the app has finished any files it "
             + "is reading. Its times for this Mac replace our test Mac's in Choose pages. You can stop it "
             + "or measure again below; it uses sample pages, not your documents.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Row("Speed check", labelWidth) {
            if timingRun.running {
                Button("Stop") { timingRun.stop() }
                ProgressView().controlSize(.small)
            } else {
                Button("Measure on this Mac") { timingRun.start(legs, memoryGB: modelMemoryGB) }
                    .disabled(runInProgress)
                    .help("Checks speed again using sample pages and every downloaded reader that fits "
                          + "the memory limit. It updates the time estimates in Choose pages, and can be "
                          + "used once your files have finished. This measures speed, not accuracy.")
            }
            Text(timingRun.running ? timingRun.status ?? ""
                 : [timingRun.status, TimingRunner.plan(legs)].compactMap { $0 }.joined(separator: " "))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        }
    }

}
