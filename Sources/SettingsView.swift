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
                            + Text(fast ? "Turn off Fast, or pick from the Add menu."
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

            Row("Uncertain text", labelWidth) {
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
            .help("Higher DPI can rescue small print, at the cost of speed.\n\n"
                  + "Only applies when Vision reads the pages as they are: in Extract "
                  + "Text, and in Searchable PDF with “Rebuild page images first” "
                  + "turned off. With the rebuild on, the pages are re-rendered at a "
                  + "resolution taken from the file itself and this has no effect.")
            if mode == .searchablePDF, rebuildImages {
                Row("", labelWidth) {
                    Text("Not in use: the rebuild renders the pages, so this DPI is "
                         + "ignored for this run.")
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
                // A starting point, not a mode. Applying one writes ordinary
                // settings, which stay visible and editable below — there is no
                // "currently using X" state to drift out of sync with them.
                Row("Start from", labelWidth) {
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

                Toggle("Rebuild page images first, discarding any old text layer",
                       isOn: $rebuildImages)
                    .help("A second text layer on top of an existing one, which "
                          + "makes copied text come out doubled. Rebuilding the pages as "
                          + "images first means Vision's OCR is the only text in the result. "
                          + "The rebuild re-encodes every page it touches, in the format "
                          + "chosen below. It runs on files that already contain text, and "
                          + "on all of them when JBIG2 is on below, since JBIG2 needs the "
                          + "pages as bitmaps.")

                Toggle("Keep highlights and notes", isOn: $preserveAnnotations)
                    .help("Rebuilding a page turns it into an image, and a highlight or a "
                          + "margin note is not part of the page — it hangs off it as a "
                          + "separate object. So the rebuild drops every one of them. "
                          + "About one document in eleven in a working library carries a "
                          + "reader\u{2019}s own marks.\n\n"
                          + "With this on they are carried onto the finished file and then "
                          + "checked: every mark counted, and every one\u{2019}s position "
                          + "compared against the original. If any of that cannot be "
                          + "verified the file is not written at all, because a highlight "
                          + "that has quietly moved misrepresents what somebody marked.\n\n"
                          + "Off by default: it costs three extra passes over the finished "
                          + "document and does nothing for a document nobody has marked "
                          + "up. Form fields, and the links that library download wrappers "
                          + "leave behind, are deliberately not carried — the run log says "
                          + "what was left.")

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
                    Toggle("Compress with JBIG2 (about a third the size)", isOn: $useJBIG2)
                        .help("Lossless JBIG2 instead of the Flate that CoreGraphics writes: "
                              + "the same bitmap at the same resolution, in roughly a third "
                              + "the bytes. It can only encode black-and-white pages, so "
                              + "switching it on rebuilds every page — including ones that "
                              + "would otherwise have been left exactly as they came in. "
                              + "Pages it cannot encode, like photographs and colour plates, "
                              + "are kept as JPEG alongside it.")
                    if useJBIG2, rebuildImages, !JBIG2.isAvailable {
                        Text("Not installed — falling back to Flate. Install with: "
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
                                  + "stored separately: the text as a full-resolution "
                                  + "stencil, the picture behind it. **This setting only "
                                  + "affects the picture — text is stored at full "
                                  + "resolution whichever you choose, and nothing is ever "
                                  + "cropped or dropped.**\n\n"
                                  + Prefs.PhotoDetail.allCases.map {
                                      "\($0.label): \($0.blurb)"
                                  }.joined(separator: "\n\n"))
                        }
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
                          ? "A born-digital PDF already holds its real text. OCR reads a "
                            + "picture of that text instead, and comes out worse — measured "
                            + "on one such book, 9% of the words were lost. Nothing is "
                            + "overwritten in this mode; the question is which text ends up "
                            + "in the output file. Turn it off if you are deliberately "
                            + "OCRing files whose embedded text is broken."
                          : "The rebuild discards any existing text layer. For a scan "
                            + "that layer is a previous OCR pass and losing it is the "
                            + "point. For a born-digital PDF it is the real text, and "
                            + "OCR of a picture of it is worse — measured on one such "
                            + "book, 9% of the words were lost. This asks before "
                            + "replacing text that was not produced by OCR; turn it off "
                            + "if you are deliberately re-OCRing files whose embedded "
                            + "text is broken.")
            }
        }
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
                Text("The only network request this app makes. Your documents "
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
        let path = UserDefaults.standard.string(forKey: Prefs.outputFolder) ?? ""
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
        let d = UserDefaults.standard
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
