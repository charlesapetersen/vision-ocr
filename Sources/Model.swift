import AppKit
import PDFKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    /// Files handed to the app by Finder — dropped on the Dock icon, or opened
    /// with "Open With" — rather than dropped on the window.
    ///
    /// Declared here rather than beside the app delegate that posts it because
    /// `run_tests.sh` compiles the views but not `App.swift` (its `@main` would
    /// collide with the test script's top-level code), and a name only the app
    /// target can see breaks that build.
    static let visionOCROpenFiles = Notification.Name("VisionOCROpenFiles")
}

/// File types mac-ocr can read. PDFs are the point; images come free.
let supportedExtensions: Set<String> = [
    "pdf", "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp",
]

/// Turns the item providers from a Finder drop into file URLs.
///
/// Lives outside the view so the decode can be tested against a real
/// NSItemProvider. The callbacks fire on arbitrary threads in arbitrary order,
/// so results are slotted by index and handed back once, on the main queue,
/// in the order they were dropped.
func resolveDroppedURLs(
    _ providers: [NSItemProvider],
    completion: @escaping ([URL]) -> Void
) {
    guard !providers.isEmpty else { completion([]); return }

    let group = DispatchGroup()
    let lock = NSLock()
    var slots = [URL?](repeating: nil, count: providers.count)

    for (i, provider) in providers.enumerated() {
        group.enter()
        provider.loadDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier
        ) { data, _ in
            defer { group.leave() }
            // Finder hands over a bookmark-style URL blob, not a UTF-8 path.
            guard let data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            lock.lock(); slots[i] = url; lock.unlock()
        }
    }

    group.notify(queue: .main) { completion(slots.compactMap { $0 }) }
}

/// Expands dropped folders, keeps only what mac-ocr can read, and drops
/// duplicates — preserving the order things were dropped in.
///
/// `existing` is the list already on screen, so re-dropping a file is a no-op.
/// Returns the new files plus a count of unsupported ones, for the UI notice.
func collectInputFiles(
    from urls: [URL],
    existing: [URL] = []
) -> (files: [URL], ignored: Int) {
    var seen = Set(existing.map(\.standardizedFileURL.path))
    var accepted: [URL] = []
    var ignored = 0

    for url in urls {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        if isDir {
            // A dropped folder contributes the supported files inside it. Files
            // it doesn't contain aren't "unsupported", so nothing is counted.
            for candidate in filesInFolder(url) {
                let path = candidate.standardizedFileURL.path
                guard !seen.contains(path) else { continue }
                seen.insert(path)
                accepted.append(candidate)
            }
            continue
        }

        guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
            ignored += 1
            continue
        }
        let path = url.standardizedFileURL.path
        guard !seen.contains(path) else { continue }
        seen.insert(path)
        accepted.append(url)
    }

    return (accepted, ignored)
}

private func filesInFolder(_ folder: URL) -> [URL] {
    guard let walker = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return [] }
    return walker.compactMap { $0 as? URL }
        .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
}

/// Shared between the UI and the worker threads, so Cancel can take effect
/// mid-file without hopping actors. Plain lock rather than actor isolation:
/// `Process.terminate()` has to be callable straight from the click.
///
/// Tracks every in-flight process, since several files run at once.
final class RunControl: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    private var _processes: [ObjectIdentifier: Process] = [:]

    // MARK: - Live batches, so quitting doesn't orphan children

    /// Every control belonging to a batch that is still running.
    ///
    /// A child of a process that exits is reparented to launchd and keeps going,
    /// so quitting mid-run used to leave mac-ocr, jbig2 and qpdf grinding away
    /// invisibly — on a large book, for minutes, competing for the machine with
    /// whatever the user did next. The app delegate stops them on the way out.
    /// **Weak.** A strong registry would keep every batch's control — and the
    /// `Process` objects it holds — alive for the life of the app, and `deinit`
    /// would never run to remove the entry. Caught by the deregistration test,
    /// which is why that test exists.
    /// A box rather than `NSHashTable.weakObjects()`: that is an Objective-C
    /// collection, and it did not give Swift-weak semantics for this plain Swift
    /// class — the deallocation test caught it still holding on. An explicit
    /// `weak` has no such ambiguity.
    private final class WeakControl {
        weak var value: RunControl?
        init(_ value: RunControl) { self.value = value }
    }
    private static let registryLock = NSLock()
    private static var live: [ObjectIdentifier: WeakControl] = [:]

    /// Live controls, dropping any that have since been deallocated.
    /// Pruning on read means there is no deinit to get wrong.
    private static func liveControls() -> [RunControl] {
        registryLock.lock(); defer { registryLock.unlock() }
        live = live.filter { $0.value.value != nil }
        return live.values.compactMap(\.value)
    }

    /// True while any batch is running. Drives the "really quit?" prompt.
    static var isAnyRunning: Bool { liveControls().contains { !$0.isFinished } }

    /// Cancels every live batch. Best effort by design: the app is quitting, and
    /// a child that ignores SIGTERM is not worth blocking the quit for.
    static func cancelAll() {
        for control in liveControls() { control.cancel() }
    }

    /// Set once the batch is over, so a control awaiting deallocation does not
    /// keep reporting itself as running.
    private var _finished = false
    var isFinished: Bool {
        lock.lock(); defer { lock.unlock() }
        return _finished
    }

    /// Marks the batch done and drops any remaining process references.
    func finished() {
        lock.lock()
        _finished = true
        _processes.removeAll()
        lock.unlock()
    }

    init() {
        Self.registryLock.lock()
        Self.live[ObjectIdentifier(self)] = WeakControl(self)
        Self.registryLock.unlock()
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }

    func adopt(_ process: Process) {
        lock.lock()
        let alreadyCancelled = _cancelled
        if !alreadyCancelled { _processes[ObjectIdentifier(process)] = process }
        lock.unlock()
        // Cancel may have landed between launch and adoption; don't strand it.
        if alreadyCancelled { process.terminate() }
    }

    func release(_ process: Process) {
        lock.lock()
        _processes[ObjectIdentifier(process)] = nil
        lock.unlock()
    }

    /// Adopts whatever `body` registers, and releases it again on the way out.
    ///
    /// Every adoption must be paired or the batch accumulates one live `Process`
    /// — and its pipe file descriptors — per child. The JBIG2 route launches one
    /// child *per page*, so a 600-page book leaked 600 of them and held them
    /// until the whole batch finished; long enough to exhaust the descriptor
    /// limit. Using this instead of a bare `adopt` makes the pairing structural.
    func adopting<T>(_ body: ((Process) -> Void) throws -> T) rethrows -> T {
        var adopted: Process?
        defer { if let adopted { release(adopted) } }
        return try body { process in
            adopted = process
            self.adopt(process)
        }
    }

    /// How many children are currently adopted. For tests: an adoption that is
    /// never released is a leak, and this is what makes it visible.
    var adoptedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _processes.count
    }

    func cancel() {
        lock.lock()
        _cancelled = true
        let running = Array(_processes.values)
        _processes.removeAll()
        lock.unlock()
        for process in running { process.terminate() }
    }
}

@MainActor
final class OCRModel: ObservableObject {
    @Published var files: [URL] = []

    // Destination lives here rather than in @AppStorage because Runner reads it
    // back out of UserDefaults — one owner, written on every change.
    @Published var outputFolder: URL? {
        didSet {
            UserDefaults.standard.set(outputFolder?.path ?? "", forKey: Prefs.outputFolder)
        }
    }
    @Published var besideOriginal: Bool {
        didSet { UserDefaults.standard.set(besideOriginal, forKey: Prefs.besideOriginal) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: Prefs.outputFolder) ?? ""
        var isDir: ObjCBool = false
        if !saved.isEmpty,
           FileManager.default.fileExists(atPath: saved, isDirectory: &isDir), isDir.boolValue {
            outputFolder = URL(fileURLWithPath: saved)
        }
        besideOriginal = UserDefaults.standard.bool(forKey: Prefs.besideOriginal)
    }

    /// Re-reads the destination from `UserDefaults`.
    ///
    /// "Reset to Defaults" removes those keys, but this object owns the live
    /// values and writes them straight back on the next change — so without this
    /// the reset silently failed for the two settings the main window shows.
    func reloadDestination() {
        let saved = UserDefaults.standard.string(forKey: Prefs.outputFolder) ?? ""
        var isDir: ObjCBool = false
        outputFolder = (!saved.isEmpty
                        && FileManager.default.fileExists(atPath: saved, isDirectory: &isDir)
                        && isDir.boolValue) ? URL(fileURLWithPath: saved) : nil
        besideOriginal = UserDefaults.standard.bool(forKey: Prefs.besideOriginal)
    }

    @Published var isRunning = false
    @Published var completed = 0            // files finished, however they ended
    @Published var total = 0
    @Published var inFlight: [URL] = []     // files currently being OCR'd
    /// What each in-flight file is doing, and how far through it is (0...1).
    ///
    /// The bar used to be bound to files-completed, so a single 200-page book left
    /// it pinned at zero for minutes. This carries intra-file progress so it
    /// actually moves.
    ///
    /// Keyed by URL, not by file name. Two inputs called `scan.pdf` in different
    /// folders shared one key: at concurrency 2 `inFlight` held two entries but
    /// `stages` one, so the bar read 0.25 where it should have read 0.5, and
    /// `inFlight.removeAll { $0 == name }` dropped *both* when the first
    /// finished. Names are for display; identity is the URL.
    @Published var stages: [URL: (label: String, fraction: Double)] = [:]

    /// How each file of the current batch ended, for the row it sits on.
    ///
    /// The log already records this, but only as text and only in a pane that
    /// appears *after* the run. On a 78-file batch that means the list you are
    /// watching says nothing about the sixty files already finished.
    @Published var outcomes: [URL: Runner.Result.Outcome] = [:]

    /// Files the user chose to leave alone at the digital-text prompt.
    @Published var skipped: Set<URL> = []

    /// What to draw beside a file. One place, in the model, because the suite
    /// compiles the views but never instantiates one — logic left in a `View`
    /// body is logic no check can reach.
    enum FileStatus: Equatable {
        case pending            // queued, not started
        case running(String?)   // in flight, with the stage label if there is one
        case succeeded
        case failed
        case cancelled
        /// Left out of the batch by "Skip Those", because it already had text.
        /// Its own state rather than `pending`: those files sit in the list for
        /// ever afterwards showing the waiting glyph and speaking "waiting",
        /// which describes something that is never going to happen (U26).
        case skipped

        var isRunning: Bool { if case .running = self { return true }; return false }
    }

    func status(url file: URL) -> FileStatus {
        // In flight wins over a recorded outcome: a file re-run in a later batch
        // is running now, whatever happened to it last time.
        if inFlight.contains(file) { return .running(stages[file]?.label) }
        switch outcomes[file] {
        case .succeeded: return .succeeded
        case .failed: return .failed
        case .cancelled: return .cancelled
        case nil: return skipped.contains(file) ? .skipped : .pending
        }
    }

    /// Spoken and shown. Keep it short — VoiceOver reads it per row.
    func statusDescription(url file: URL) -> String {
        switch status(url: file) {
        case .pending: return "waiting"
        case .running(let stage): return stage.map { "in progress, \($0)" } ?? "in progress"
        case .succeeded: return "done"
        case .failed: return "failed"
        case .cancelled: return "cancelled"
        case .skipped: return "skipped — it kept its own text"
        }
    }

    /// Overall fraction across the batch, counting partial work on the files
    /// currently running.
    var overallFraction: Double {
        guard total > 0 else { return 0 }
        let partial = stages.values.reduce(0) { $0 + min(max($1.fraction, 0), 1) }
        let raw = (Double(completed) + partial) / Double(total)
        // Hold back a visible sliver while anything is still running.
        //
        // 254 of 255 files done is 99.6% complete and draws as a full bar. That
        // is arithmetically honest and practically a lie: someone watching a
        // 63 MB broadsheet grind through recognition saw a finished bar for
        // several minutes and concluded the app had hung. The bar is the thing
        // you read from across the room, so it must not say "finished" until it
        // is (U25).
        let stillWorking = isRunning && (completed < total || !inFlight.isEmpty)
        return stillWorking ? min(raw, 0.97) : min(raw, 1)
    }

    /// True when there is genuinely nothing to report, so the bar should be
    /// indeterminate rather than showing a number nobody measured.
    /// A negative fraction is how a stage says "working, no idea".
    ///
    /// Only for a single file. Across a batch, "3 of 8 done" is real information
    /// even when no individual file can measure itself — going indeterminate
    /// there would discard progress the user can actually use.
    var progressIsIndeterminate: Bool {
        total <= 1 && !stages.isEmpty && stages.values.allSatisfy { $0.fraction < 0 }
    }
    @Published var log: [LogLine] = []

    private var control: RunControl?
    private var queue: OperationQueue?

    /// Inputs whose output `uniqueOutputs` had to rename, and what it became.
    /// Only the renamed ones — the log mentions it for exactly these.
    private var renamedOutputs: [URL: URL] = [:]

    /// Where every input's result was written. The log names it on success:
    /// a base name alone is not enough to find a file afterwards, especially
    /// with "beside each original" or a partly-failed batch.
    private var resolvedOutputs: [URL: URL] = [:]

    struct LogLine: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
        enum Kind { case info, success, failure }

        /// Spoken outcome, because colour is not available to everyone and the
        /// glyph alone ("✓") is not announced usefully. This is a tool whose
        /// entire job is telling you what happened to your documents.
        var spoken: String {
            switch kind {
            case .success: return "Succeeded: \(text)"
            case .failure: return "Failed: \(text)"
            case .info: return text
            }
        }

        var color: Color {
            switch kind {
            case .info: return .secondary
            case .success: return .green
            case .failure: return .red
            }
        }
    }

    /// Speaks something to VoiceOver at the moment it happens.
    ///
    /// U8 made the interface *readable* — every control labelled, the progress
    /// bar carrying a value, each log line carrying its outcome. It did not make
    /// it *spoken*: a batch could start, grind through eighty archival scans and
    /// finish in complete silence, and the only way to learn that was to
    /// navigate back and re-read the progress row. An announcement is the one
    /// AppKit mechanism that reaches a user who is not looking at the window.
    ///
    /// Three moments, chosen because they are the ones a sighted user gets for
    /// free from the window: the batch starting, each file landing, and the
    /// summary. The summary goes out at high priority so it is not dropped in
    /// favour of whatever VoiceOver happens to be saying.
    ///
    /// `NSApp` is nil in the test binary, which never builds an application
    /// object; announcing into nothing is not worth a crash.
    private func announce(_ message: String, important: Bool = false) {
        guard let app = NSApp, let element = app.mainWindow ?? app.windows.first else { return }
        let priority = important
            ? NSAccessibilityPriorityLevel.high
            : NSAccessibilityPriorityLevel.medium
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: priority.rawValue])
    }

    /// Writing beside each original needs no folder; anything else does.
    var destinationReady: Bool { besideOriginal || outputFolder != nil }

    /// True from the moment Start freezes the batch until the run is over.
    ///
    /// `isRunning` is not that moment. C17's pre-flight sits between the click
    /// and `run()`, and `start()` captures `let candidates = files` before
    /// dispatching it — so for the whole of "Checking…" the batch contents were
    /// already decided while `isRunning` was still false and every control that
    /// edits them was still live. That is U1 again by another route (U19).
    ///
    /// One flag, because the bug was seven `.disabled(model.isRunning)` and one
    /// `guard` that each had to be remembered separately when C17 added a state.
    var isCommitted: Bool { isRunning || isPreflighting }

    var canStart: Bool {
        // `isImporting` too: a folder drop is walked off the main actor (U20),
        // and Start was available during the walk, so the batch could be frozen
        // while files were still arriving. The flag was published for this and
        // nothing read it (U21).
        !files.isEmpty && !isCommitted && !isImporting && destinationReady
    }

    // MARK: - The drop box

    /// What happened to a set of dropped or chosen files.
    enum AddResult {
        /// Added. `ignored` counts files whose type this app cannot read.
        case added(ignored: Int)
        /// Refused because a batch is running.
        case refusedRunInProgress
    }

    /// Adds files, expanding any dropped folders and skipping duplicates and
    /// unsupported types — unless a run is in flight.
    ///
    /// `start()` freezes the batch (`let batch = files`), so anything added
    /// during a run is never enqueued — it just sits in the list while the
    /// summary reports "40 of 40 succeeded" above 43 rows, with no output on
    /// disk for three of them and nothing saying so. The UI was actively
    /// soliciting that mistake: the drop border still highlighted and the header
    /// count incremented, both of which read as "accepted into the job".
    ///
    /// Refusing is the honest option, and it is enforced here rather than in the
    /// view because there are three ways in — the button, the drop zone, and
    /// files handed over by Finder — and gating only the button left the other
    /// two open.
    @discardableResult
    func add(_ urls: [URL]) -> AddResult {
        // isCommitted, not isRunning: the batch is frozen from the click, not
        // from the moment the first subprocess starts (U19).
        guard !isCommitted else { return .refusedRunInProgress }
        let result = collectInputFiles(from: urls, existing: files)
        files.append(contentsOf: result.files)
        return .added(ignored: result.ignored)
    }

    /// True while a drop or an Add… is being expanded off the main actor.
    @Published var isImporting = false

    /// The same as `add`, with the directory walk moved off the main actor.
    ///
    /// `add` is `@MainActor` and `filesInFolder` enumerates a whole subtree,
    /// materialises every URL, filters it and then sorts with
    /// `localizedStandardCompare` — the collated comparison. On a scanned-archive
    /// folder of tens of thousands of files, or any folder on a mounted share
    /// where each directory read is a round trip, that ran on the main thread
    /// with the drop highlight still lit and nothing able to respond, including
    /// Cancel. On a stalled mount it did not return at all (U20).
    ///
    /// The expansion happens on a background queue; the cheap part — deduplicating
    /// against what is already listed — happens back on the main actor against
    /// the *current* list rather than a snapshot, so two overlapping drops cannot
    /// each miss the other's files.
    ///
    /// U5 and C17 moved the login-shell lookup and the digital-text scan off the
    /// main thread for exactly this reason. The import path never got it.
    func add(_ urls: [URL], then completion: @escaping (AddResult) -> Void) {
        guard !isCommitted else { completion(.refusedRunInProgress); return }
        isImporting = true
        DispatchQueue.global(qos: .userInitiated).async {
            // No `existing:` here — this pass is only the expensive expansion.
            let expanded = collectInputFiles(from: urls)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.isImporting = false
                    // Re-checked: Start can have been pressed while we walked.
                    guard !self.isCommitted else {
                        completion(.refusedRunInProgress)
                        return
                    }
                    // Cheap now — nothing left to expand, so this is a dedupe
                    // against the list as it stands at this instant.
                    let result = collectInputFiles(from: expanded.files,
                                                   existing: self.files)
                    self.files.append(contentsOf: result.files)
                    completion(.added(ignored: expanded.ignored + result.ignored))
                }
            }
        }
    }

    /// Guarded here, not only in the view, for the reason `add` gives above: a
    /// committed batch must be immutable through **every** door, and a view
    /// modifier only closes the one door that exists today. `add` was written
    /// that way after U1; `remove` and `clearFiles` were not, and the sibling
    /// sweep in CONTRIBUTING 4b is what noticed (U23).
    @discardableResult
    func remove(_ url: URL) -> Bool {
        guard !isCommitted else { return false }
        files.removeAll { $0 == url }
        // With it: a file removed and dropped again showed last run's tick
        // before it had done anything this time (U26).
        outcomes[url] = nil
        stages[url] = nil
        skipped.remove(url)          // a row state like any other (U25 sweep)
        return true
    }

    /// The whole log as text, for the Copy button.
    var logText: String { log.map(\.text).joined(separator: "\n") }

    /// How many files had a problem — **files, not log lines**.
    ///
    /// The heading counted lines with `kind == .failure`, and a failure appends
    /// two of them (the name, then the message), so one bad file read as "2
    /// problems" and a run with one failure plus a stray line read as three.
    /// Counting outcomes makes it one per file by construction (U25).
    var problemCount: Int { outcomes.values.filter { $0 == .failed }.count }

    /// The log with failures first, which is what the doc comment on the
    /// results pane has always claimed and the code never did — it rendered
    /// `log` in arrival order, so on a 255-file run the one red entry sat two
    /// hundred rows down a scroll view. A failure you have to hunt for is not
    /// reporting (U25).
    ///
    /// Stable within each group: the order files finished in is information.
    var logFailuresFirst: [LogLine] {
        log.filter { $0.kind == .failure } + log.filter { $0.kind != .failure }
    }

    /// Which line the results pane should bring into view when the log changes.
    enum LogAnchor { case newest, firstProblem }

    /// While the run is going, follow the newest line: that is the live record
    /// of what is happening, and it is what someone watching a long batch is
    /// reading. Only once it is over does the pane jump to the top, where the
    /// failures now are.
    ///
    /// The first version of this pinned to the first problem whenever there was
    /// one, which sounds right and is not: on a 255-file run where file 3
    /// fails, each of the remaining 252 files appends a line, and every one of
    /// them yanks the view back to the top. The log would stop following the
    /// run at the moment it became most worth following (U25).
    var logAnchor: LogAnchor {
        if isRunning { return .newest }
        return problemCount > 0 ? .firstProblem : .newest
    }

    /// Empties the file list. **Not** the log: it is the only record of which
    /// files failed and where the outputs went, and clearing the list to queue
    /// the next batch is a normal thing to do straight after reading it.
    @discardableResult
    func clearFiles() -> Bool {
        guard !isCommitted else { return false }
        files.removeAll()
        // The log is deliberately kept — it is the record of the last batch —
        // but the per-row state is about *these* rows, and there are none.
        outcomes.removeAll()
        stages.removeAll()
        skipped.removeAll()
        return true
    }

    /// Empties the log, separately and deliberately.
    func clearLog() {
        log.removeAll()
    }

    // MARK: - Running the batch

    /// What to do about inputs that already carry real digital text.
    enum DigitalTextChoice { case ocrAnyway, skipThem, useExisting, cancel }

    /// Stands in for the modal alert, so the decision step can be tested.
    ///
    /// `askAboutDigitalText` runs an `NSAlert`, which a headless suite cannot
    /// drive — and U21 is precisely a defect in what is true *while that alert
    /// is up*, so leaving it untestable is how U21 got shipped. A test sets this,
    /// records the state it is called with, and returns a decision. Nil in the
    /// app, always.
    nonisolated(unsafe) static var digitalTextDecisionForTesting:
        ((_ digital: [URL], _ total: Int) -> DigitalTextChoice)?

    /// Writes a PDF's own embedded text out, instead of OCRing a picture of it.
    ///
    /// Only for the plain-text format. `json` and `jsonl` are Vision's
    /// observation schema — per-line bounding boxes and confidences — and a PDF's
    /// text layer cannot honestly be dressed up as that. Offering it would mean
    /// fabricating geometry, which is worse than the problem.
    ///
    /// Page breaks are a blank line, which is what `mac-ocr --format text`
    /// produces between pages, so a downstream script does not need to care
    /// which route produced the file.
    /// Returns the 1-based numbers of pages that contributed nothing **and had
    /// something to contribute** — an image with no text layer, which is content
    /// OCR could have recovered and this route silently skipped (C19).
    ///
    /// A page with neither text nor an image is a genuinely blank leaf and is not
    /// reported: crying loss over the blank verso of a chapter opener would train
    /// people to ignore the warning that matters.
    @discardableResult
    nonisolated static func writeEmbeddedText(
        from input: URL, to output: URL, password: String?
    ) throws -> [Int] {
        guard let doc = Flattener.open(input, password: password) else {
            throw Failure.unreadable
        }
        var pages: [String] = []
        var skipped: [Int] = []
        // Real extracted text, ignoring the markers below. The guard at the end
        // has to be "did we get anything out of this file", and once markers are
        // written into the body they would otherwise satisfy it on their own —
        // turning the all-scan refusal into a file full of apologies.
        var foundText = false
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else {
                // Unreadable page. Nothing to extract and no way to tell what was
                // there, which is exactly the case invariant 1 is about.
                skipped.append(i + 1)
                pages.append("[page \(i + 1): could not be read — no text extracted]")
                continue
            }
            let text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               Flattener.pageIsAnImage(page) {
                // The marker goes in the file, not only in the log. A run that
                // drops thirty pages of appendix must not produce an artifact
                // that reads as complete — a downstream script never sees the
                // log line, and the gap between two "\n\n" is invisible.
                skipped.append(i + 1)
                pages.append("[page \(i + 1): image with no text layer — "
                             + "not OCR'd, re-run in Searchable PDF mode to read it]")
            } else {
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    foundText = true
                }
                pages.append(text)
            }
        }
        let body = pages.joined(separator: "\n\n")
        guard foundText else { throw Failure.noTextFound }
        // Staged and moved, like every other write here: invariant 2 applies to
        // this path too, and it is the one that overwrites a previous result.
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mac-ocr-gui-extract-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try body.write(to: scratch, atomically: true, encoding: .utf8)
        try publish(scratch, to: output)
        return skipped
    }

    enum Failure: LocalizedError {
        case unreadable, noTextFound
        var errorDescription: String? {
            switch self {
            case .unreadable: return "Could not open that PDF to read its text."
            case .noTextFound: return "That PDF turned out to have no extractable text after all."
            }
        }
    }

    /// True while the pre-flight scan is reading the inputs. Start is disabled
    /// meanwhile, so the scan cannot be launched twice.
    @Published var isPreflighting = false

    /// Inputs whose own text is better than anything this run will produce.
    ///
    /// Sampling every file costs one `PDFDocument` open each, so it happens off
    /// the main actor — a 78-file batch would otherwise freeze the window for
    /// the length of the scan, which is the U5 mistake with a different cause.
    nonisolated static func filesWithDigitalText(
        in files: [URL], password: String?
    ) -> [URL] {
        files.filter { Flattener.hasDigitalText($0, password: password) }
    }

    /// The sentence the user has to answer. Separate from the alert so the
    /// wording is testable without an `NSAlert` on screen.
    /// Whether JBIG2 encoding will be attempted, which also decides whether the
    /// pages get re-rendered even when there is no text layer to strip.
    nonisolated static func wantsJBIG2(rebuild: Bool, settings: Prefs.Snapshot,
                                       mode: Flattener.Mode,
                                       available: Bool = JBIG2.isAvailable) -> Bool {
        rebuild && settings.useJBIG2 && mode.canUseJBIG2 && available
    }

    /// Whether this file's pages will be re-rendered — the question the Settings
    /// panel answers in prose, extracted so the prose can be checked.
    ///
    /// The panel used to say the rebuild was "only applied to files that already
    /// contain text", which is what the code does when JBIG2 is off and simply
    /// untrue when it is on: JBIG2 is a bilevel codec and needs the pages as
    /// bitmaps, so switching on a *compression* option quietly re-renders every
    /// page — and re-rendering is what turns a colour scan grey.
    nonisolated static func willRebuild(hasEmbeddedText: Bool, rebuild: Bool,
                                        settings: Prefs.Snapshot,
                                        mode: Flattener.Mode,
                                        jbig2Available: Bool = JBIG2.isAvailable) -> Bool {
        let mustStrip = rebuild && hasEmbeddedText
        return mustStrip || wantsJBIG2(rebuild: rebuild, settings: settings,
                                       mode: mode, available: jbig2Available)
    }

    nonisolated static func digitalTextWarning(for digital: [URL], of total: Int) -> String {
        let names = digital.prefix(5).map(\.lastPathComponent).joined(separator: "\n• ")
        let more = digital.count > 5 ? "\n• …and \(digital.count - 5) more" : ""
        let subject = digital.count == 1 ? "This file already contains" : "These files already contain"
        let scope = digital.count == total
            ? ""
            : " (\(digital.count) of \(total) in the batch)"
        return "\(subject) selectable text that was not produced by OCR\(scope):\n\n• "
            + names + more
            + "\n\nRebuilding the pages as images discards that text and replaces it with "
            + "Vision's, which is usually worse — measured on one such book, 9% of the words "
            + "were lost and about one word in seven of the rest was an OCR error.\n\n"
            + "If the existing text is broken, re-OCRing is the right thing to do."
    }

    func start() {
        guard !files.isEmpty, !isRunning, !isPreflighting else { return }

        guard let binary = Runner.resolveBinary() else {
            log = [LogLine(
                text: "Can't find the mac-ocr command. Install it with "
                    + "\"npm install -g mac-ocr\", then reopen this app — "
                    + "or point Settings at the binary directly.",
                kind: .failure)]
            return
        }

        // Two different wrongs, both worth stopping for.
        //
        // Searchable PDF + rebuild *destroys* the existing text (C17). Extract
        // Text destroys nothing — but it still hands back OCR of a picture of
        // text the file was carrying perfectly well, which for the plain-text
        // format this app can simply read out instead.
        let d = UserDefaults.standard
        let mode = Prefs.Mode(rawValue: d.string(forKey: Prefs.mode) ?? "") ?? .searchablePDF
        let willDiscardText = mode == .searchablePDF && d.bool(forKey: Prefs.rebuildImages)
        let couldReadInstead = mode == .text
        guard willDiscardText || couldReadInstead, d.bool(forKey: Prefs.warnDigitalText) else {
            run(files, binary: binary)
            return
        }

        let candidates = files
        let saved = d.string(forKey: Prefs.password) ?? ""
        let password = saved.isEmpty ? nil : saved
        isPreflighting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let digital = Self.filesWithDigitalText(in: candidates, password: password)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Cleared when the DECISION is over, not when the scan is.
                // `askAboutDigitalText` below runs a modal NSAlert, and
                // main-queue work executes behind one — NSModalPanelRunLoopMode
                // is in the main run loop's mode set, which was checked rather
                // than assumed. So clearing the flag first left isCommitted
                // false while the alert was up, and U20's async import appended
                // to a batch that had already been frozen: "Done — 1 of 1
                // succeeded" over a list of 301, which is U1 for the third time
                // (U21).
                //
                // `defer`, because four of the five branches below hand off to
                // `run()`, which sets isRunning synchronously — so isCommitted
                // never goes false between the two — and the fifth has to clear
                // it on the way out.
                defer { self.isPreflighting = false }
                guard !digital.isEmpty else { self.run(candidates, binary: binary); return }

                let choice = Self.digitalTextDecisionForTesting?(digital, candidates.count)
                    ?? self.askAboutDigitalText(digital, of: candidates.count)
                switch choice {
                case .ocrAnyway:
                    self.run(candidates, binary: binary)
                case .useExisting:
                    self.run(candidates, binary: binary, readingTextFrom: Set(digital))
                case .skipThem:
                    let rest = candidates.filter { !digital.contains($0) }
                    self.skipped = Set(digital)
                    let skipped = "Skipped \(digital.count) file(s) that already had "
                        + "selectable text; their own text is kept."
                    guard !rest.isEmpty else {
                        self.log.append(LogLine(text: skipped + " Nothing left to run.",
                                                kind: .info))
                        return
                    }
                    self.run(rest, binary: binary)
                    self.log.append(LogLine(text: skipped, kind: .info))
                case .cancel:
                    self.log.append(LogLine(text: "Start cancelled — nothing was changed.",
                                            kind: .info))
                }
            }
        }
    }

    /// Puts the question on screen. Returns what the user chose.
    ///
    /// The options differ by mode because the wrong thing differs by mode. In
    /// Searchable PDF the text is about to be destroyed, so the alternative is
    /// to leave those files alone. In Extract Text nothing is destroyed and
    /// there is a strictly better answer available — read the text out — so
    /// that is offered, and made the default.
    private func askAboutDigitalText(_ digital: [URL], of total: Int) -> DigitalTextChoice {
        let d = UserDefaults.standard
        let mode = Prefs.Mode(rawValue: d.string(forKey: Prefs.mode) ?? "") ?? .searchablePDF
        let format = Prefs.TextFormat(rawValue: d.string(forKey: Prefs.textFormat) ?? "") ?? .text
        // Only plain text can be read out honestly: json and jsonl are Vision's
        // observation schema, and a text layer has no bounding boxes to put in it.
        let canReadInstead = mode == .text && format == .text

        let alert = NSAlert()
        alert.messageText = digital.count == 1
            ? "This PDF already has selectable text."
            : "\(digital.count) of these PDFs already have selectable text."
        alert.informativeText = Self.digitalTextWarning(for: digital, of: total)
        alert.alertStyle = .warning

        var actions: [DigitalTextChoice] = []
        if canReadInstead {
            alert.addButton(withTitle: "Use Existing Text"); actions.append(.useExisting)
            alert.addButton(withTitle: "OCR Anyway"); actions.append(.ocrAnyway)
        } else {
            alert.addButton(withTitle: "OCR Anyway"); actions.append(.ocrAnyway)
            if digital.count != total {
                alert.addButton(withTitle: "Skip Those"); actions.append(.skipThem)
            }
        }
        alert.addButton(withTitle: "Cancel"); actions.append(.cancel)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            d.set(false, forKey: Prefs.warnDigitalText)
        }
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard index >= 0, index < actions.count else { return .cancel }
        return actions[index]
    }

    /// Runs a batch that has already been through the pre-flight.
    ///
    /// `readingTextFrom` names inputs whose own embedded text is to be written
    /// out instead of OCRing them — the Extract Text answer to C17's problem.
    /// They still travel through the same queue, tally and log, so a mixed batch
    /// reports as one batch.
    private func run(_ batch: [URL], binary: String, readingTextFrom extract: Set<URL> = []) {
        guard !batch.isEmpty, !isRunning else { return }

        // Re-checked here, not only at the click. The file list is frozen when
        // Start is pressed but the destination is read at this point, so the two
        // halves of the batch definition were taken at different moments — and
        // unticking "Save beside each original" during the pre-flight left
        // destinationReady false while `uniqueOutputs` quietly fell back to
        // `file.deletingLastPathComponent()`, writing the whole batch beside the
        // originals instead of into a folder the user never chose (U19).
        guard destinationReady else {
            isPreflighting = false
            log.append(LogLine(
                text: "Nothing was written: choose an output folder, or turn on "
                    + "\"Save beside each original\".",
                kind: .failure))
            return
        }
        let destination = besideOriginal ? nil : outputFolder
        let control = RunControl()
        self.control = control

        // mac-ocr already parallelises pages inside one file, but that leaves
        // cores idle; running several files at once is ~3x faster. An
        // OperationQueue rather than a TaskGroup because Runner.run blocks on
        // waitUntilExit, and blocking Swift-concurrency's cooperative threads
        // is exactly what it asks you not to do.
        let limit = max(1, min(UserDefaults.standard.integer(forKey: Prefs.concurrency),
                               Prefs.maxConcurrency))
        let opQueue = OperationQueue()
        opQueue.maxConcurrentOperationCount = limit
        opQueue.qualityOfService = .userInitiated
        self.queue = opQueue

        isRunning = true
        completed = 0
        total = batch.count
        inFlight = []
        // Only this batch's files: a list still showing last run's ticks beside
        // files that have not started again would be a lie about the present.
        outcomes = [:]
        stages = [:]
        // …but only for the files in *this* batch. `skipThem` sets `skipped`
        // and then calls straight into here, so clearing the whole set wiped
        // the mark two lines after it was made and U26's skipped glyph could
        // never appear at all. Subtracting the batch keeps that mark while
        // still clearing anything stale about a file that is running now.
        skipped.subtract(batch)

        // The log used to open with the pipeline's steps — the mac-ocr command
        // line, the rebuild, the JBIG2 merge. That is a developer's view of the
        // run, and this app is for people who want their scans searchable. The
        // steps still exist in Settings' command preview, where someone looking
        // for them will look. What the window shows is progress, and afterwards
        // what happened to each file.
        log = []
        announce(batch.count == 1
                 ? "Started OCR on \(batch[0].lastPathComponent)."
                 : "Started OCR on \(batch.count) files.")

        // Read once, on the main actor, rather than from each worker thread.
        // Every per-file setting travels in this snapshot; the Settings sheet
        // stays open during a run, and re-reading UserDefaults per file made a
        // mid-batch change apply to some files and not others.
        let settings = Prefs.Snapshot.current()
        let isSearchable = settings.mode == .searchablePDF
        let needsRebuild = UserDefaults.standard.bool(forKey: Prefs.rebuildImages) && isSearchable
        let rebuildMode = Flattener.Mode(
            rawValue: UserDefaults.standard.string(forKey: Prefs.rebuildMode) ?? "")
            ?? .auto
        let besideOriginal = self.besideOriginal
        let password = settings.password.isEmpty ? nil : settings.password

        let textExt = settings.textFormat.fileExtension
        let outputSuffix = isSearchable ? ".ocr" : ""
        let outputExt = isSearchable ? "pdf" : textExt
        let outputs = Self.uniqueOutputs(
            for: batch, besideOriginal: besideOriginal, folder: destination,
            suffix: outputSuffix, extension: outputExt)

        // uniqueOutputs appends " 2" when two inputs would claim one path. That
        // rename was invisible: a user with two files called scan.pdf saw two
        // ✓ scan.pdf lines and no way to tell which became "scan 2.ocr.pdf".
        resolvedOutputs = outputs
        renamedOutputs = outputs.filter { input, output in
            let base = input.deletingPathExtension().lastPathComponent
            return output.lastPathComponent != "\(base)\(outputSuffix).\(outputExt)"
        }

        tally = (0, 0, 0)
        stages = [:]
        finishUp = { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.inFlight = []
            // Tell the control it is over before dropping it: the app delegate
            // asks the registry whether anything is running, and a control
            // awaiting deallocation must not answer yes.
            self.control?.finished()
            self.control = nil
            self.queue = nil
            self.finishUp = nil

            let (ok, bad, stopped) = self.tally
            var summary = "Done — \(ok) of \(batch.count) succeeded"
            if bad > 0 { summary += ", \(bad) failed" }
            if stopped > 0 { summary += ", \(stopped) cancelled" }
            self.log.append(LogLine(
                text: summary + ".",
                kind: bad > 0 ? .failure : (stopped > 0 ? .info : .success)))
            self.announce(summary + ".", important: true)

            if ok > 0,
               UserDefaults.standard.bool(forKey: Prefs.openWhenDone),
               let folder = OCRModel.folderToReveal(destination: destination,
                                                    inputs: batch) {
                NSWorkspace.shared.open(folder)
            }
        }

        for file in batch {
            opQueue.addOperation { [weak self] in
                // Cancelled while queued: never launch it at all.
                if control.isCancelled {
                    DispatchQueue.main.async { self?.finish(file, outcome: .cancelled, message: "") }
                    return
                }

                DispatchQueue.main.async { self?.inFlight.append(file) }

                let report: (Runner.Result.Outcome, String) -> Void = { outcome, message in
                    DispatchQueue.main.async {
                        self?.stages[file] = nil
                        self?.finish(file, outcome: outcome, message: message)
                    }
                }
                // Phase label plus an absolute fraction for this file.
                let note: (String, Double) -> Void = { label, fraction in
                    DispatchQueue.main.async {
                        self?.stages[file] = (label, fraction)
                    }
                }

                if isSearchable {
                    Self.makeSearchablePDF(
                        file: file, binary: binary,
                        output: outputs[file] ?? file.deletingLastPathComponent()
                            .appendingPathComponent(
                                file.deletingPathExtension().lastPathComponent + ".ocr.pdf"),
                        rebuild: needsRebuild, rebuildMode: rebuildMode,
                        password: password, settings: settings,
                        control: control, progress: note, report: report)
                    return
                }

                // The file already had better text than OCR would produce, and
                // the user said to use it. No subprocess, no rebuild — just read
                // it out. Fast enough that the bar never needs to move.
                if extract.contains(file) {
                    note("Reading the existing text", -1)
                    let target = outputs[file] ?? file.deletingLastPathComponent()
                        .appendingPathComponent(
                            file.deletingPathExtension().lastPathComponent + "." + textExt)
                    do {
                        let skipped = try Self.writeEmbeddedText(
                            from: file, to: target, password: password)
                        if skipped.isEmpty {
                            report(.succeeded, "used the PDF's own text; no OCR was run")
                        } else {
                            // Invariant 1: this path can drop a page, so it says
                            // which. The file carries the same note in place.
                            let list = skipped.count > 6
                                ? skipped.prefix(6).map(String.init).joined(separator: ", ")
                                    + " and \(skipped.count - 6) more"
                                : skipped.map(String.init).joined(separator: ", ")
                            report(.succeeded,
                                   "used the PDF's own text; no OCR was run — but "
                                   + "\(skipped.count) page\(skipped.count == 1 ? "" : "s") "
                                   + "(\(list)) carry an image with no text and were "
                                   + "not read. Re-run in Searchable PDF mode for those.")
                        }
                    } catch {
                        report(.failed, error.localizedDescription)
                    }
                    return
                }

                // No fraction: Runner.run is one blocking call with nothing to
                // report from inside it. Claiming 0.5 pinned the bar at exactly
                // half for the whole of a single-file run, which reads as a
                // stall. An indeterminate bar is the honest shape.
                note("Recognising", -1)
                var launched: Process?
                let result = Runner.run(
                    binary: binary,
                    file: file,
                    outputFolder: destination,
                    explicitOutputFile: outputs[file],
                    settings: settings,
                    wasCancelled: { control.isCancelled },
                    register: { process in
                        launched = process
                        control.adopt(process)
                    })
                if let launched { control.release(launched) }
                report(result.outcome, result.message)
            }
        }

    }


    /// Assigns every input a distinct output path.
    ///
    /// Two files with the same base name in different folders both mapped to one
    /// output, so the second silently overwrote the first — and under
    /// concurrency they raced for the same path. Resolved once, up front, on the
    /// main actor.
    ///
    /// Outputs are also kept off **every input in the batch**, not merely off
    /// each other. Re-running a folder that already holds a previous run's
    /// results puts both `scan.pdf` and `scan.ocr.pdf` in the batch, and
    /// `scan.pdf` would claim `scan.ocr.pdf` as its destination — a path another
    /// worker is concurrently reading. `publish` would then replace a file
    /// mid-read. Seeding `claimed` with the inputs pushes the collision to
    /// `scan 2.ocr.pdf` instead.
    nonisolated static func uniqueOutputs(
        for files: [URL],
        besideOriginal: Bool,
        folder: URL?,
        suffix: String,
        extension ext: String
    ) -> [URL: URL] {
        var claimed = Set(files.map { $0.standardizedFileURL.path.lowercased() })
        var result: [URL: URL] = [:]
        for file in files {
            let dir = besideOriginal ? file.deletingLastPathComponent()
                                     : (folder ?? file.deletingLastPathComponent())
            let base = file.deletingPathExtension().lastPathComponent
            var candidate = dir.appendingPathComponent("\(base)\(suffix).\(ext)")
            var n = 2
            // Lowercased: the default APFS volume is case-insensitive, so
            // "Scan.ocr.pdf" and "scan.ocr.pdf" are one file and two workers
            // raced for it, silently discarding one result.
            while claimed.contains(candidate.standardizedFileURL.path.lowercased()) {
                candidate = dir.appendingPathComponent("\(base) \(n)\(suffix).\(ext)")
                n += 1
            }
            claimed.insert(candidate.standardizedFileURL.path.lowercased())
            result[file] = candidate
        }
        return result
    }

    /// Moves a finished file into place, replacing any previous run's output.
    ///
    /// Internal rather than private for the same reason `makeSearchablePDF` is:
    /// this is the step that touches the user's disk, invariant 2 is about
    /// exactly this step, and it had no test of its own.
    nonisolated static func publish(_ staged: URL, to output: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: output.path) {
            _ = try fm.replaceItemAt(output, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: output)
        }
    }

    /// The whole searchable-PDF pipeline for one file, on a worker thread:
    /// strip any old text layer, recognise, then write the text layer ourselves.
    ///
    /// mac-ocr is used for recognition only. Its own `searchable-pdf` writer
    /// positions each word separately without real spaces, which costs a third
    /// of the words on extraction — see SearchableWriter for the measurements.
    ///
    /// Internal rather than private so the whole pipeline can be tested end to
    /// end. Testing only its parts let a regression ship that failed every run.
    nonisolated static func makeSearchablePDF(
        file inputFile: URL,
        binary: String,
        output: URL,
        rebuild: Bool,
        rebuildMode: Flattener.Mode,
        password: String?,
        settings: Prefs.Snapshot = .current(),
        control: RunControl,
        progress: @escaping (String, Double) -> Void,
        report: @escaping (Runner.Result.Outcome, String) -> Void
    ) {
        // Shares of the wall clock, measured on a 22-page run: rebuilding and
        // compressing took 5.9s, recognition 12.8s, the text layer 0.7s. Weighting
        // by those keeps the bar roughly linear in time rather than lurching.
        func rebuildShare(_ d: Int, _ t: Int) -> Double { 0.30 * Double(d) / Double(max(t, 1)) }
        func ocrShare(_ d: Int, _ t: Int) -> Double { 0.30 + 0.63 * Double(d) / Double(max(t, 1)) }
        func layerShare(_ d: Int, _ t: Int) -> Double { 0.93 + 0.05 * Double(d) / Double(max(t, 1)) }

        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mac-ocr-gui-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }

        // The pipeline's own intermediates live in here, and nothing named after
        // the user's file ever does. They used to share `scratch` with the
        // rebuild, which keeps the input's own name — so an input called
        // text.pdf *was* the text layer, and the JBIG2 branch deleted the layer
        // it was about to merge (R27). Separating them by directory kills the
        // whole class rather than one name: renaming the intermediates would
        // only move the collision, since a dropped image called rebuilt.png is
        // wrapped to rebuilt.pdf in the same place.
        let work = scratch.appendingPathComponent("work")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        } catch {
            report(.failed, "Could not create a working directory: \(error.localizedDescription)")
            return
        }

        // An image input is wrapped as a one-page PDF first; everything below is
        // PDF-shaped. Without this, dropping a PNG failed with a message that
        // blamed the user's file.
        var file = inputFile
        if PDFDocument(url: file) == nil {
            guard let wrapped = Flattener.wrapImage(file, into: scratch) else {
                report(.failed, "Could not read that file as a PDF or an image.")
                return
            }
            file = wrapped
        }

        // 1. What the reader will see. Rebuilding as images is what removes an
        //    existing text layer; without it mac-ocr's would survive alongside.
        //    JBIG2 needs the per-page bitmaps too, so ask for them in the same
        //    pass rather than rendering everything twice.
        //
        //    `rebuild` gates JBIG2 as well: wanting bitmaps is not permission to
        //    re-render pages the user asked us to leave alone.
        let wantJBIG2 = Self.wantsJBIG2(rebuild: rebuild, settings: settings,
                                        mode: rebuildMode)
        var visible = file
        var bitmaps: [Flattener.RebuiltPage] = []
        var encoded: [JBIG2.Page] = []
        let pngDir = scratch.appendingPathComponent("pages")

        // Rebuild when there's an old text layer to strip, and also whenever
        // JBIG2 is wanted — it needs the per-page bitmaps.
        // Through `willRebuild`, not a copy of its condition. It was a copy —
        // extracted "so the prose can be checked", asserted against by six
        // checks, and called by nothing. A predicate the product does not use
        // is a duplicate of the thing under test that agrees with it by
        // construction: change the line below and every one of those checks
        // stays green while the Settings panel goes back to lying. U26 had this
        // exact shape with `Prefs.allKeys`.
        if Self.willRebuild(hasEmbeddedText: Flattener.hasEmbeddedText(file, password: password),
                            rebuild: rebuild, settings: settings, mode: rebuildMode) {
            let rebuilt = scratch.appendingPathComponent(file.lastPathComponent)
            if wantJBIG2 {
                try? FileManager.default.createDirectory(at: pngDir,
                                                         withIntermediateDirectories: true)
            }
            do {
                bitmaps = try Flattener.flatten(
                    file, to: rebuilt, mode: rebuildMode, password: password,
                    pngDirectory: wantJBIG2 ? pngDir : nil,
                    isCancelled: { control.isCancelled },
                    progress: { d, t in progress("Rebuilding page \(d) of \(t)", rebuildShare(d, t)) },
                    // Compress and discard each page as it is produced. Holding
                    // every bitmap until the end cost ~110 KB per page of
                    // scratch — 60 MB on a 600-page book, for nothing.
                    onPage: wantJBIG2 ? { page in
                        guard let jb = JBIG2.encoder else { return }
                        switch page.content {
                        case .bilevel(let png):
                            let out = scratch.appendingPathComponent(
                                String(format: "s%05d.jbig2", encoded.count))
                            // adopting, not adopt: one child per page, and an
                            // unpaired adopt held every one of them for the
                            // whole batch.
                            try control.adopting { register in
                                try JBIG2.encode(png: png, to: out, using: jb,
                                                 register: register)
                            }
                            try? FileManager.default.removeItem(at: png)
                            encoded.append(JBIG2.Page(
                                stream: .jbig2(out), pixelWidth: page.pixelWidth,
                                pixelHeight: page.pixelHeight, boxSize: page.boxSize))
                        case .jpeg(let jpeg):
                            encoded.append(JBIG2.Page(
                                stream: .jpeg(jpeg), pixelWidth: page.pixelWidth,
                                pixelHeight: page.pixelHeight, boxSize: page.boxSize,
                                // Carried through, or the merge declares a
                                // three-channel stream as /DeviceGray.
                                isColour: page.isColour))
                        }
                    } : nil)
                visible = rebuilt
            } catch {
                // Same as below: a cancelled jbig2 child surfaces here as a
                // throw, and is a cancellation, not a broken file.
                if control.isCancelled { report(.cancelled, "Cancelled."); return }
                report(.failed, "Could not rebuild page images: \(error.localizedDescription)")
                return
            }
        }
        if control.isCancelled { report(.cancelled, "Cancelled."); return }

        // 2. Recognise it. Coordinates must come from the same pages we draw.
        //
        //    Streamed as JSON Lines rather than one buffered JSON blob: mac-ocr
        //    emits a page at a time, which is the only progress signal available
        //    for what is the longest phase of a long document.
        let pageTotal = PDFPageCount(visible)
        var jsonLines: [String] = []
        progress("Recognising page 0 of \(max(pageTotal, 0))", ocrShare(0, pageTotal))
        var launched: Process?
        let ocr = Runner.runStreaming(
            binary: binary,
            // A page we are willing to rebuild can still be one mac-ocr refuses
            // to render — its limit is 200 MP against our 400 — and finding out
            // after the rebuild means the whole file fails. Ask for a DPI that
            // fits when it does not (U25).
            arguments: Runner.jsonLinesArguments(
                for: visible, settings: settings,
                dpiCeiling: Flattener.recogniserDPICeiling(for: visible, password: password)),
            onLine: { line in
                jsonLines.append(line)
                let done = jsonLines.count
                progress("Recognising page \(done) of \(max(pageTotal, done))",
                         ocrShare(done, pageTotal))
            },
            wasCancelled: { control.isCancelled },
            register: { process in launched = process; control.adopt(process) })
        if let launched { control.release(launched) }
        guard ocr.succeeded else { report(ocr.outcome, ocr.message); return }
        if control.isCancelled { report(.cancelled, "Cancelled."); return }

        // 3. Write the PDF. The destination was reserved up front, so two inputs
        //    with the same base name cannot collide here.
        let staged = work.appendingPathComponent("staged.pdf")

        // Read the expected page count now, while everything still exists. The
        // scratch intermediates get deleted as they're spent, so asking later
        // returned -1 for a file that had just been removed.
        let expected = PDFPageCount(visible)
        guard expected > 0 else {
            report(.failed, "Could not read the rebuilt PDF to check it.")
            return
        }

        do {
            let byPage = try SearchableWriter.observations(fromJSONLines: jsonLines)

            // A page the recogniser never reported would compose as a page with
            // no text, pass the page-count check, and publish as a success. The
            // recogniser emits a record per page even when a page is blank, so a
            // gap here means a page was skipped, not that it was empty.
            let missing = SearchableWriter.missingPages(in: byPage, of: pageTotal)
            if !missing.isEmpty {
                let shown = missing.prefix(5).map(String.init).joined(separator: ", ")
                report(.failed, "The recogniser returned nothing for page(s) "
                    + shown + (missing.count > 5 ? " …" : "")
                    + " of \(pageTotal); nothing was written.")
                return
            }

            // Held locally, not read back off a static: files run concurrently,
            // and a shared static let the next file's compose erase this one's
            // losses before they were reported. See BUGS.md C8.
            var unplaced: [SearchableWriter.Unplaced] = []

            // JBIG2 route: text layer on its own, page images compressed by
            // jbig2enc, merged by qpdf. Roughly a third the size of the
            // CoreGraphics route at the same resolution.
            // Whether the published file carries JBIG2 image streams. The two
            // routes carry the outline across by different means, so this
            // decides which one runs.
            var usedJBIG2 = false

            // Read once. The JBIG2 route writes it into the assembled PDF's
            // catalogue; the Flate route hands it back to PDFKit afterwards.
            let outline = SearchableWriter.readOutline(from: inputFile, password: password)

            if wantJBIG2, encoded.count == expected,
               encoded.count == bitmaps.count, let qpdf = JBIG2.merger {
                usedJBIG2 = true
                let textLayer = work.appendingPathComponent("text.pdf")
                unplaced = try SearchableWriter.compose(
                    visible: visible, observations: byPage, to: textLayer,
                    drawImages: false, password: password,
                    isCancelled: { control.isCancelled },
                    progress: { d, t in progress("Writing text layer \(d) of \(t)",
                                                 layerShare(d, t)) })

                // Check the *layer* here, not just the finished file.
                //
                // The guard below compares `produced == expected`, and on this
                // route `produced` is the page count of the images PDF that
                // `JBIG2.assemble` built — which comes from `encoded`, already
                // known to match. `qpdf --overlay` stamps as many layer pages as
                // it has onto the images and leaves the rest bare, so a text
                // layer that stopped short published a full-length, perfectly
                // valid PDF whose later pages simply had no text, and the
                // page-count check waved it through. Invariant 1: page count is
                // not sufficient verification.
                // Cancellation first, or this guard reports the user's own Cancel
                // as a broken file: `compose` returns a short layer when it is
                // interrupted, which is R14's mistake in a new place.
                if control.isCancelled { report(.cancelled, "Cancelled."); return }
                let layerPages = PDFPageCount(textLayer)
                guard layerPages == expected else {
                    report(.failed, "The text layer covered \(layerPages) of "
                        + "\(expected) pages; nothing was written.")
                    return
                }

                progress("Compressing pages", 0.98)

                // The Flate rebuild was only needed for recognition and for the
                // text layer's geometry; both are done, and it is the largest
                // thing in scratch.
                try? FileManager.default.removeItem(at: visible)

                let imagesOnly = work.appendingPathComponent("images.pdf")
                // Into the catalogue here, not through PDFKit afterwards:
                // qpdf --overlay keeps this file's catalogue, and a PDFKit
                // rewrite would re-encode every image stream and throw the
                // compression away. See BUGS.md R19.
                try JBIG2.assemble(encoded, outline: outline, to: imagesOnly)
                for page in encoded { try? FileManager.default.removeItem(at: page.stream.url) }
                // Registered so Cancel can interrupt the merge, which is the slow
                // step on a large book and used to leave Cancel looking dead.
                try control.adopting { register in
                    try JBIG2.overlay(text: textLayer, onto: imagesOnly,
                                      to: staged, using: qpdf, register: register)
                }
                try? FileManager.default.removeItem(at: imagesOnly)
                try? FileManager.default.removeItem(at: textLayer)
            } else {
                unplaced = try SearchableWriter.compose(
                    visible: visible, observations: byPage, to: staged,
                    password: password,
                    isCancelled: { control.isCancelled },
                    progress: { d, t in progress("Writing pages \(d) of \(t)",
                                                 layerShare(d, t)) })
            }

            // Never publish a partial result.
            if control.isCancelled { report(.cancelled, "Cancelled."); return }
            let produced = PDFPageCount(staged)
            guard produced == expected else {
                report(.failed, "The result had \(produced) pages but the source has "
                    + "\(expected); nothing was written.")
                return
            }

            // A line the writer could not place is reported, not swallowed.
            if !unplaced.isEmpty {
                let lost = unplaced
                let detail = lost.prefix(3)
                    .map { "p\($0.page) \"\($0.text.prefix(24))\" (\($0.reason))" }
                    .joined(separator: "; ")
                report(.failed, "\(lost.count) line(s) could not be placed: \(detail)"
                    + (lost.count > 3 ? " …" : ""))
                return
            }
            // Carry the source's outline across, if it has one. CoreGraphics
            // cannot write an outline, so this is a PDFKit rewrite — done into a
            // separate file and verified before use, because that rewrite
            // re-serialises the invisible text layer. Anything unexpected and we
            // publish the composed file untouched: an outline is worth having,
            // never worth risking the OCR for.
            //
            // Only for the Flate route — the JBIG2 route already wrote the
            // outline into the assembled catalogue above, and running PDFKit over
            // it here would undo the compression that route exists for.
            let outlined = work.appendingPathComponent("outlined.pdf")
            if !usedJBIG2, !outline.isEmpty,
               SearchableWriter.copyOutline(from: inputFile, of: staged, to: outlined,
                                            password: password),
               PDFPageCount(outlined) == expected {
                try publish(outlined, to: output)
            } else {
                try publish(staged, to: output)
            }
        } catch {
            // Cancelling reaches the jbig2 and qpdf children as SIGTERM, so they
            // exit 15 and JBIG2.encode/overlay throw — arriving here, where the
            // run was reported as a failure ("jbig2 exited with code 15") rather
            // than as the cancellation it was. Runner gets this right for
            // mac-ocr; the JBIG2 route did not.
            if control.isCancelled { report(.cancelled, "Cancelled."); return }
            report(.failed, error.localizedDescription)
            return
        }
        report(.succeeded, "")
    }

    /// Running totals for the batch in flight. Main-actor only.
    private var tally: (succeeded: Int, failed: Int, cancelled: Int) = (0, 0, 0)

    /// Wraps up the batch. Held as a closure so it captures the batch's
    /// destination and size, and runs exactly once — when the last file lands.
    private var finishUp: (() -> Void)?

    /// Guards the JBIG2 route: if the rebuild produced fewer bitmaps than the
    /// PDF has pages (a page that failed to render, say), fall back rather than
    /// assemble a PDF that silently drops pages.
    private nonisolated static func PDFPageCount(_ url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? -1
    }

    /// Where "open the output folder when finished" should point.
    ///
    /// `destination` is nil precisely when "save beside each original" is on,
    /// which is the case the setting most obviously means to cover — so falling
    /// back to the first input's folder is the whole point, not an edge case.
    /// Guarding on `let folder = destination` instead made the setting do
    /// nothing in exactly that configuration.
    nonisolated static func folderToReveal(destination: URL?, inputs: [URL]) -> URL? {
        if let destination { return destination }
        return inputs.first?.deletingLastPathComponent()
    }

    /// Records one finished file. Log order is completion order, which with
    /// several files in flight won't match the list order — that's honest.
    ///
    /// Every queued file reports exactly once, even when cancelled before it
    /// launched, so `completed` always reaches `total` and the batch finishes.
    private func finish(_ file: URL, outcome: Runner.Result.Outcome, message: String) {
        guard isRunning else { return }
        let name = file.lastPathComponent
        inFlight.removeAll { $0 == file }
        // Before `completed`, so a view recomputing on either one never sees a
        // file that is neither in flight nor finished.
        outcomes[file] = outcome
        stages[file] = nil
        completed += 1

        switch outcome {
        case .succeeded:
            tally.succeeded += 1
            log.append(LogLine(text: "✓ \(name)", kind: .success))
            // Where it went. With "beside each original" there is no single
            // destination on screen to infer it from, and after a partly-failed
            // batch the user needs to find the ones that worked.
            if let output = resolvedOutputs[file] {
                let note = renamedOutputs[file] != nil
                    ? "    → \(output.path)  (renamed; another input claimed that name)"
                    : "    → \(output.path)"
                log.append(LogLine(text: note, kind: .info))
            }
            // mac-ocr is silent on success; surface it if it isn't.
            if !message.isEmpty {
                log.append(LogLine(text: "    \(message)", kind: .info))
            }
        case .cancelled:
            tally.cancelled += 1
            log.append(LogLine(text: "⊘ \(name) — cancelled", kind: .info))
        case .failed:
            tally.failed += 1
            log.append(LogLine(text: "✗ \(name)", kind: .failure))
            log.append(LogLine(text: "    \(message)", kind: .failure))
        }

        // Spoken as it happens. Suppressed for the file that ends the batch,
        // because `finishUp` announces the summary a moment later and saying
        // both is just noise — on a single-file run it would be three
        // announcements for one document.
        if completed < total {
            let progressed = total > 1 ? " — \(completed) of \(total)" : ""
            switch outcome {
            case .succeeded: announce("\(name) finished\(progressed).")
            case .cancelled: announce("\(name) cancelled\(progressed).")
            case .failed: announce("\(name) failed\(progressed). \(message)")
            }
        }

        if completed >= total { finishUp?() }
    }

    func cancel() {
        // Not opQueue.cancelAllOperations(): a cancelled Operation never runs,
        // so it would never report back and the batch would never finish.
        // control.isCancelled makes each queued file return immediately instead.
        control?.cancel()
        log.append(LogLine(text: "Cancelling…", kind: .info))
    }
}
