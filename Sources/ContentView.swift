import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    /// Owned by the app, not by this view — see `VisionOCRApp.model`. A
    /// `@StateObject` here made the running batch a property of the window, so
    /// it died with the window and there was one per window.
    @ObservedObject var model: OCRModel
    @AppStorage(Prefs.mode) private var modeRaw = Prefs.Mode.searchablePDF.rawValue
    @State private var showSettings = false
    @State private var isTargeted = false
    @State private var ignoredNotice: String?
    /// True when the notice on screen is "a run is in progress", which stops
    /// being true the moment the run ends. It used to sit in the header until
    /// the next add or Clear — long after the thing it described was over, and
    /// on a batch the user then had no reason to touch, for good.
    @State private var noticeExpiresWithRun = false

    private var mode: Prefs.Mode { Prefs.Mode(rawValue: modeRaw) ?? .searchablePDF }

    @State private var update: Updater.Release?

    var body: some View {
        VStack(spacing: 14) {
            if let update { updateBanner(update) }
            dropBox
            destinationRow
            actionRow
            if model.isRunning { progressPane }
            if !model.isRunning, !model.log.isEmpty { resultsPane }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 520)
        .task {
            // Three seconds after the window appears, not during launch: an
            // update check must never be between someone and their first drop.
            // Failures are silent by design — see Updater.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            Updater.check { result in
                if case .available(let release) = result {
                    DispatchQueue.main.async { update = release }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(runInProgress: model.isCommitted) { model.reloadDestination() }
        }
        // Finder can hand us files two ways the drop box never sees: dragged onto
        // the Dock icon, and "Open With". Info.plist has always advertised both.
        .onReceive(NotificationCenter.default.publisher(for: .visionOCROpenFiles)) { message in
            guard let urls = message.userInfo?["urls"] as? [URL], !urls.isEmpty else { return }
            // Dock and "Open With" can hand over a folder as readily as a file,
            // so this is the expanding form too (U20).
            model.add(urls) { note($0) }
        }
        // "Not added — a run is in progress" describes a condition that ends.
        .onChange(of: model.isRunning) { running in
            if !running, noticeExpiresWithRun {
                ignoredNotice = nil
                noticeExpiresWithRun = false
            }
        }
    }

    // MARK: - Drop box

    /// Shown only when there is something to say. No "you are up to date"
    /// banner: an app that congratulates itself for being unchanged is noise.
    @ViewBuilder
    private func updateBanner(_ release: Updater.Release) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Vision OCR \(release.version) is available")
                    .font(.callout).fontWeight(.medium)
                Text("You have \(Updater.currentVersion).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("What's New") { NSWorkspace.shared.open(release.url) }
                .buttonStyle(.link).font(.caption)
            Button("Download") { NSWorkspace.shared.open(release.url) }
            Button {
                UserDefaults.standard.set(release.version, forKey: Prefs.skippedVersion)
                update = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Skip \(release.version). You will be told about the version after it.")
            .accessibilityLabel("Skip version \(release.version)")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Update available: Vision OCR \(release.version)")
    }

    private var dropBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.45),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [6, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear))

            if model.files.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .accessibilityHidden(true)
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Drag PDFs here")
                        .font(.headline)
                    Text("Images and folders work too")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Dropping only unsupported files used to do nothing
                    // visible at all: the notice lived in the file list, which
                    // is exactly what does not appear in that case.
                    if let notice = ignoredNotice {
                        Text(notice)
                            .font(.caption).foregroundStyle(.orange)
                            .padding(.top, 2)
                    }
                    Button("Choose Files…") { chooseFiles() }
                        .padding(.top, 4)
                }
            } else {
                fileList
            }
        }
        .frame(minHeight: 180)
        .onDrop(of: [.fileURL], isTargeted: model.isCommitted ? .constant(false) : $isTargeted) {
            providers in
            load(providers)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Files to OCR")
        .accessibilityHint(model.files.isEmpty
                           ? "Drop PDFs or images here, or use Choose Files."
                           : "\(model.files.count) file\(model.files.count == 1 ? "" : "s") queued.")
    }

    /// Pending, running, done, failed. Deliberately four distinguishable shapes
    /// and not four colours: colour alone is not available to everyone, which is
    /// the same reason the log lines carry a glyph (U8).
    @ViewBuilder
    private func statusIcon(_ status: OCRModel.FileStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.mini)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .skipped:
            Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
        }
    }

    private var fileList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(listHeading)
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel(listHeading)
                if let notice = ignoredNotice {
                    Text("· \(notice)").font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                // Disabled during a run for the same reason Clear is: `start()`
                // snapshots the batch, so a file added now is silently excluded
                // from it — and then the summary says "3 of 3 succeeded" while
                // the list on screen shows five.
                Button("Add…") { chooseFiles() }
                    .buttonStyle(.link).font(.caption)
                    .disabled(model.isCommitted)
                Button("Clear List") { model.clearFiles(); ignoredNotice = nil }
                    .buttonStyle(.link).font(.caption)
                    .disabled(model.isCommitted)
                    .help("Empties the list. The log is kept — it is the only "
                          + "record of what happened to the last batch.")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.files, id: \.self) { url in
                        let status = model.status(url: url)
                        HStack(spacing: 6) {
                            statusIcon(status)
                                .frame(width: 14, height: 14)
                                .accessibilityHidden(true)   // the row says it
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent)
                                    .lineLimit(1).truncationMode(.middle)
                                    .foregroundStyle(status == .pending && model.isRunning
                                                     ? .secondary : .primary)
                                // The stage this file is at. The model has
                                // carried this all along and nothing ever showed
                                // it per file — on a long book "Rebuilding page
                                // 40 of 300" is the difference between working
                                // and hung.
                                if case .running(let stage) = status, let stage {
                                    Text(stage)
                                        .font(.caption2).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                            }
                            // The leaf name alone cannot distinguish two
                            // scan.pdfs from different folders — the case R4
                            // exists for — and the path was only in a
                            // tooltip, which is mouse-only.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(url.path)
                            .accessibilityValue(model.statusDescription(url: url))
                            Spacer(minLength: 4)
                            Button {
                                model.remove(url)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isCommitted)
                            .opacity(model.isCommitted ? 0 : 1)   // no dead controls
                            .accessibilityHidden(model.isCommitted)
                            .accessibilityLabel("Remove \(url.lastPathComponent)")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .help(url.path)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Destination

    private var destinationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Output").font(.subheadline).bold()
                Spacer()
                // The running batch resolved its destinations up front, so
                // flipping this mid-run would leave the panel describing
                // somewhere the output is not going.
                Toggle("Save beside each original", isOn: $model.besideOriginal)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .disabled(model.isCommitted)
            }

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .accessibilityHidden(true)
                    .foregroundStyle(model.besideOriginal ? .tertiary : .secondary)
                Text(model.besideOriginal
                     ? "Next to each input file"
                     : (model.outputFolder?.path ?? "No folder chosen"))
                    .font(.callout)
                    .lineLimit(1).truncationMode(.head)
                    .foregroundStyle(model.besideOriginal
                                     ? .secondary
                                     : (model.outputFolder == nil ? .secondary : .primary))
                Spacer(minLength: 6)
                Button("Choose…") { chooseOutputFolder() }
                    .disabled(model.besideOriginal || model.isCommitted)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Picker("", selection: $modeRaw) {
                ForEach(Prefs.Mode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Output mode")
            // A hard width is what made the action row unable to shrink at the
            // 520 pt minimum; everything else in it is already unshrinkable.
            .frame(minWidth: 170, idealWidth: 240, maxWidth: 240)
            .disabled(model.isCommitted)
            .help(mode.blurb)

            Spacer()

            if model.isRunning {
                Button("Cancel") { model.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
                    .accessibilityLabel("Cancel the run")
            }

            Button(model.isRunning ? "Running…"
                   : (model.isPreflighting ? "Checking…" : "Start OCR")) {
                model.start()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStart)
            .help(startBlockedReason ?? "")
            // A disabled control's tooltip is unreachable by keyboard, and the
            // only other clue was grey text 40 pt away.
            .accessibilityLabel(startBlockedReason.map { "Start OCR, unavailable: \($0)" }
                                ?? "Start OCR")
        }
    }

    // MARK: - Progress + log

    /// While a run is going: a bar and one line. Nothing else.
    ///
    /// This replaced a scrolling log of the pipeline's steps. The steps were
    /// honest and completely uninteresting to the person whose scans are being
    /// processed — they are still in Settings' command preview for anyone who
    /// wants them.
    private var progressPane: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Fraction, not file count: one long book left a file-count bar
            // pinned at zero for minutes. Indeterminate when nothing in flight
            // can report a fraction — Extract Text has no intra-file progress,
            // and a bar frozen at 50% reads as a hang.
            if model.progressIsIndeterminate {
                ProgressView().progressViewStyle(.linear)
                    .accessibilityLabel("OCR in progress")
                    .accessibilityValue(progressLabel)
            } else {
                ProgressView(value: model.overallFraction)
                    .animation(.easeOut(duration: 0.25), value: model.overallFraction)
                    .accessibilityLabel("OCR progress")
                    .accessibilityValue(progressLabel)
            }
            Text(progressLabel)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    /// After a run: what happened to each file.
    ///
    /// Kept, and deliberately not folded into the progress line, because it is
    /// the only place a *failure* is visible and the only record of where the
    /// output went — with "Save beside each original" there is no destination on
    /// screen to infer it from, and after a partly-failed batch the user needs to
    /// find the ones that worked (U10, invariant 1). Failures first: a red line
    /// twenty rows down a scroll view is not reporting.
    private var resultsPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(resultsHeading).font(.caption).foregroundStyle(.secondary)
                Spacer()
                // Only when there is something to retry, and only when it could
                // actually run. A four-file failure out of seventy-eight
                // otherwise means re-dropping four files by hand, and the model
                // already knows which they were.
                if let retryTitle {
                    Button(retryTitle) { model.retryFailures() }
                        .buttonStyle(.link).font(.caption)
                        .disabled(!model.canRetryFailures)
                        .help("Runs the files that failed again, and nothing else. "
                              + "The list narrows to those files first, so the window "
                              + "shows what is about to happen. The previous run's "
                              + "record is in its report.")
                        .accessibilityLabel(retryTitle)
                }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.logText, forType: .string)
                }
                .buttonStyle(.link).font(.caption)
                .help("Copies the whole record, for a bug report or your own notes.")
                Button("Clear") { model.clearLog() }
                    .buttonStyle(.link).font(.caption)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(model.logFailuresFirst) { line in
                            Text(line.text)
                                .font(.callout)
                                .foregroundStyle(line.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                // Colour alone does not say "this one failed".
                                .accessibilityLabel(line.spoken)
                                .id(line.id)
                        }
                    }
                    .padding(6)
                    // On the container, not each line: per-Text selection meant
                    // a drag could not span lines, so pulling three failures out
                    // of a 40-file run meant copying them one at a time.
                    .textSelection(.enabled)
                }
                .onChange(of: model.log.count) { _ in scrollLog(proxy) }
                // …and again when the run ends, which is when the anchor moves
                // to the problems and usually when the last line has already
                // been appended.
                .onChange(of: model.isRunning) { _ in scrollLog(proxy) }
            }
            .frame(minHeight: 90)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06)))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Results")
    }

    /// Follows the model's decision rather than making one here: a `View` body
    /// is the one place in this app no check can reach.
    private func scrollLog(_ proxy: ScrollViewProxy) {
        switch model.logAnchor {
        case .firstProblem:
            if let first = model.logFailuresFirst.first {
                proxy.scrollTo(first.id, anchor: .top)
            }
        case .newest:
            if let last = model.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    /// Nil when there is nothing to retry, so the button simply is not there.
    /// A separate property because the interpolation inside a `Button` label
    /// inside the results pane's stack put the type checker over its budget.
    private var retryTitle: String? {
        let n = model.failedFiles.count
        guard n > 0 else { return nil }
        return "Retry \(n) Failed"
    }

    private var resultsHeading: String {
        let failed = model.problemCount        // files, not log lines
        return failed > 0 ? "Results — \(failed) problem\(failed == 1 ? "" : "s")" : "Results"
    }

    /// "78 files" when idle; "78 files · 12 done, 3 running" while working, so
    /// the count above the list answers "how far along is this" without the user
    /// counting ticks.
    private var listHeading: String {
        let n = model.files.count
        let base = "\(n) file\(n == 1 ? "" : "s")"
        guard model.isRunning else { return base }
        let done = model.files.filter { model.status(url: $0) != .pending
                                        && !model.status(url: $0).isRunning }.count
        let running = model.files.filter { model.status(url: $0).isRunning }.count
        return "\(base) · \(done) done, \(running) running"
    }

    private var startBlockedReason: String? {
        if model.isPreflighting { return "checking the files for existing text" }
        if model.isRunning { return "a run is already in progress" }
        if model.files.isEmpty { return "no files have been added yet" }
        if !model.destinationReady {
            return "choose an output folder, or turn on Save beside each original"
        }
        return nil
    }
    /// With several files at once there's no single "current" file, so show what
    /// has landed plus what's in flight.
    private var progressLabel: String {
        let percent = Int((model.overallFraction * 100).rounded())
        if model.progressIsIndeterminate {
            let running = model.inFlight.count
            return model.total > 1
                ? "\(model.completed) of \(model.total) files"
                    + (running > 0 ? " · \(running) running" : "")
                : (model.stages.values.first?.label ?? "Working…")
        }
        // With several files at once there's no single "current" file, so say how
        // many are running; with one, name the phase it's in.
        if model.total > 1 {
            let running = model.inFlight.count
            return "\(percent)% · \(model.completed) of \(model.total) files"
                + (running > 0 ? " · \(running) running" : "")
        }
        if let stage = model.stages.values.first {
            return "\(percent)% · \(stage.label)"
        }
        return "\(percent)%"
    }

    // MARK: - Pickers and drop handling

    /// Turns the outcome of an add into the one line of feedback the drop box
    /// shows. Silence after a drop reads as "accepted", which is the whole
    /// problem being fixed here.
    private func note(_ result: OCRModel.AddResult) {
        switch result {
        case .refusedRunInProgress:
            ignoredNotice = "Not added — a run is in progress"
            noticeExpiresWithRun = true
        case .added(let ignored):
            ignoredNotice = ignored > 0 ? "\(ignored) unsupported skipped" : nil
            noticeExpiresWithRun = false
        }
    }

    private func load(_ providers: [NSItemProvider]) {
        resolveDroppedURLs(providers) { urls in
            guard !urls.isEmpty else { return }
            // The expanding form: a dropped folder is walked off the main actor
            // so the window keeps drawing while it happens (U20).
            model.add(urls) { note($0) }
        }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.message = "Choose PDFs or images to OCR"
        panel.prompt = "Add"
        if panel.runModal() == .OK {
            // canChooseDirectories is true, so this can be a whole tree too.
            model.add(panel.urls) { note($0) }
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose where the OCR results should go"
        panel.prompt = "Use Folder"
        panel.directoryURL = model.outputFolder
        if panel.runModal() == .OK, let url = panel.url {
            model.outputFolder = url
        }
    }
}
