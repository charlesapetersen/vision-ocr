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

    /// Every path an earlier attempt in this retry chain was reading from or
    /// writing to — its inputs *and* its outputs, accumulated across however many
    /// retries there have been.
    ///
    /// R60 is what this is for. A retry runs a *subset* of a previous batch, and
    /// `uniqueOutputs`' protection is only as wide as the list it is handed, so
    /// the sibling that was keeping a name reserved is gone and the retry takes
    /// it. A set of paths rather than a map keyed by input, because a third
    /// attempt has to remember what the first one reserved.
    private var claimedByEarlierAttempts: Set<URL> = []

    /// Each input's output on the previous attempt, so a retry can *reuse* its own
    /// slot. Without it, carrying the earlier attempt's outputs forward
    /// over-reserves: the retried file's own previous name is in that set, so it
    /// is pushed to a third name and renamed again on every retry.
    private var previousOutputs: [URL: URL] = [:]

    /// Everything `retryFailures` cleared, held until the run it asked for either
    /// starts or is declined.
    ///
    /// A5.2. `retryFailures` narrows `files` to the failures and erases every
    /// verdict, and put them back with `guard isCommitted else { … }` — which
    /// **never runs**, because under the shipped defaults `start()` returns with
    /// `isPreflighting` already true, so `isCommitted` is true and the guard
    /// passes. Every refusal arriving after the pre-flight left the user holding a
    /// list narrowed to the failures, no verdicts, and `canRetryFailures` false so
    /// the record of what failed was unrecoverable — under a log line reading
    /// "Start cancelled — nothing was changed."
    ///
    /// Restored on exactly the paths that clear `continuesRetryChain`, because the
    /// two have the same lifetime: a retry chain continues iff a run began.
    private var retryPutBack: (files: [URL],
                               outcomes: [URL: Runner.Result.Outcome],
                               stages: [URL: (label: String, fraction: Double)],
                               skipped: Set<URL>)?

    /// True from `retryFailures` until the run it asks for reaches `run()`.
    ///
    /// A property rather than a parameter threaded through `start`: `start`
    /// reaches `run` through five branches and an async pre-flight, and a sixth
    /// branch added later would default to "a new chain" — which is the safe
    /// direction for over-reserving and the *unsafe* direction for R60.
    private var continuesRetryChain = false

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

    /// The files the last batch failed on, in list order.
    ///
    /// Order matters and is not arbitrary: `files` is the order the user added
    /// them, and a retry that reshuffled them would make the second run's log
    /// hard to line up against the first. `outcomes` is a dictionary and has no
    /// order of its own, which is exactly the trap.
    var failedFiles: [URL] { files.filter { outcomes[$0] == .failed } }

    /// Retrying is not "start again". A four-file failure out of seventy-eight
    /// currently means re-dropping four files by hand, and the model already
    /// knows which they were.
    ///
    /// Gated on the same flag as everything else that mutates a batch. Every
    /// door into a committed batch is shut by `isCommitted`, and adding a
    /// seventh door with its own condition is precisely how U19, U20 and U21
    /// happened — the states-by-doors table in `Tests/main.swift` has a row for
    /// this one.
    var canRetryFailures: Bool {
        !isCommitted && !isImporting && destinationReady && !failedFiles.isEmpty
    }

    /// Runs the last batch's failures again, and nothing else.
    ///
    /// Deliberately goes through `start()`'s pre-flight rather than straight to
    /// `run`: the digital-text warning (C17) applies to a retried file exactly
    /// as it did the first time, and a path that skipped it would be a way to
    /// discard real text without being asked. The pre-flight reads `files`, so
    /// the list is narrowed to the failures first — which is also what the user
    /// sees, so the window agrees with what is about to happen.
    @discardableResult
    func retryFailures() -> Bool {
        guard canRetryFailures else { return false }
        let retry = failedFiles
        // Put back if the run does not happen. `canRetryFailures` cannot see
        // every reason `start` declines — a binary that has gone missing since
        // the last batch is one — and without this the user is left holding a
        // list narrowed to the failures, with every verdict erased and only a
        // line in the log. Restoring is three lines; reasoning about which
        // refusals are possible is how U21 happened.
        //
        // A5.2: it has to survive `start()` *returning*, because the refusal that
        // matters arrives later, from the async pre-flight. Held in
        // `retryPutBack` and released by `abandonRetry()` on every path that
        // declines, or dropped by `run()` when a batch really begins. Everything
        // this function clears is captured, so "nothing was changed" is true of
        // the rows and the progress labels too, not only of the list.
        retryPutBack = (files: files, outcomes: outcomes,
                        stages: stages, skipped: skipped)
        let previousFiles = files
        let previousOutcomes = outcomes
        // The note goes through `start`, because `run` clears the log as its
        // first act and a line written here would vanish. The previous run's
        // record is not lost with it — the report on disk is what that batch
        // left behind, which is the first time clearing the log has been safe.
        files = retry
        // Their old verdicts are about the previous run. Left in place, the rows
        // would show ✗ while the files sat waiting, and `failedFiles` would
        // still list them after a successful retry (U26's shape: a status that
        // describes something that is no longer going to happen).
        outcomes.removeAll()
        stages.removeAll()
        skipped.subtract(retry)
        // Set before `start`, because `run` reads it. R60: this run must not be
        // allowed to claim a path the batch it descends from had reserved.
        continuesRetryChain = true
        start(note: "Retrying \(retry.count) file\(retry.count == 1 ? "" : "s") "
                  + "that failed in the previous run.")
        guard isCommitted else {
            // The synchronous refusals — `start` returning at its own first guard.
            // `previousFiles`/`previousOutcomes` are kept as the local, obvious
            // path for this case; `abandonRetry` covers the asynchronous ones.
            files = previousFiles
            outcomes = previousOutcomes
            abandonRetry()
            return false
        }
        return true
    }

    /// Undo a `retryFailures` whose run never began.
    ///
    /// Called from every path that declines after the list has been narrowed:
    /// `start`'s own first guard, the pre-flight's Cancel, and the Skip Those
    /// branch that leaves nothing to run. Those are exactly the paths that clear
    /// `continuesRetryChain`, which is not a coincidence — a chain continues if
    /// and only if a run began, so the two are cleared together and neither can
    /// be added to without the other being considered.
    private func abandonRetry() {
        continuesRetryChain = false
        guard let put = retryPutBack else { return }
        retryPutBack = nil
        files = put.files
        outcomes = put.outcomes
        stages = put.stages
        skipped = put.skipped
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

    /// How many drops or Add…s are being expanded off the main actor right now.
    ///
    /// A **count**, not a flag: `isImporting` was a boolean set true by every
    /// `add` and cleared by every completion, so the first walk to land lowered
    /// the interlock while the others were still going (A5.3).
    @Published var importsInFlight = 0

    /// True while any drop or Add… is being expanded off the main actor.
    var isImporting: Bool { importsInFlight > 0 }

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
        importsInFlight += 1
        DispatchQueue.global(qos: .userInitiated).async {
            // No `existing:` here — this pass is only the expensive expansion.
            let expanded = collectInputFiles(from: urls)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // `max(0,)` so a stray extra completion cannot drive the count
                    // negative and leave the interlock permanently down — the
                    // failure this whole change is about, one layer along.
                    self.importsInFlight = max(0, self.importsInFlight - 1)
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
        // `!isImporting` for the same reason as `start`: measured 0 → 8,000 files
        // after a Clear the user explicitly asked for, because the walk that was
        // still running appended into the list Clear had just emptied.
        guard !isCommitted, !isImporting else { return false }
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
        /// The destination path is a folder. `replaceItemAt` would delete it and
        /// everything in it, and report success.
        case destinationIsFolder(String)
        /// The file about to be published is not the full length. Carries the
        /// message rather than the counts so there is one copy of the wording —
        /// see `incompleteRefusal`.
        case incompleteResult(String)
        var errorDescription: String? {
            switch self {
            case .unreadable: return "Could not open that PDF to read its text."
            case .noTextFound: return "That PDF turned out to have no extractable text after all."
            case .destinationIsFolder(let name):
                return "\u{201C}\(name)\u{201D} is a folder, so nothing was written "
                     + "\u{2014} publishing over it would have deleted it."
            case .incompleteResult(let message): return message
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

    /// `note`, when there is one, is the first line of the run log: why this
    /// batch exists, when it is not simply "the user pressed Start". Passed
    /// through rather than stored on the model — a stored one survives every
    /// path that declines to run (no binary, the pre-flight cancelled) and
    /// reappears as the header of an unrelated batch later.
    func start(note: String? = nil) {
        // `!isImporting` is here and not only in `canStart`: a guard that lives in
        // the view is a guard for the button, and U19 and U23 are both entries
        // about a door someone else can walk through. A batch frozen while a walk
        // is still expanding is U1's "8,001 rows over Done — 1 of 1 succeeded".
        guard !files.isEmpty, !isRunning, !isPreflighting, !isImporting else { return }

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
            run(files, note: note)
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
                guard !digital.isEmpty else {
                    self.run(candidates, note: note); return
                }

                let choice = Self.digitalTextDecisionForTesting?(digital, candidates.count)
                    ?? self.askAboutDigitalText(digital, of: candidates.count)
                switch choice {
                case .ocrAnyway:
                    self.run(candidates, note: note)
                case .useExisting:
                    self.run(candidates, readingTextFrom: Set(digital), note: note)
                case .skipThem:
                    let rest = candidates.filter { !digital.contains($0) }
                    self.skipped = Set(digital)
                    let skipped = "Skipped \(digital.count) file(s) that already had "
                        + "selectable text; their own text is kept."
                    guard !rest.isEmpty else {
                        self.log.append(LogLine(text: skipped + " Nothing left to run.",
                                                kind: .info))
                        // No run, so no chain continues from here (R60) and a
                        // retry that got this far is put back (A5.2).
                        self.abandonRetry()
                        return
                    }
                    self.run(rest, note: note, leftOut: digital)
                    self.log.append(LogLine(text: skipped, kind: .info))
                case .cancel:
                    self.log.append(LogLine(text: "Start cancelled — nothing was changed.",
                                            kind: .info))
                    // The sentence above is the reason this call is here: it was
                    // false for a retry, which had had its list narrowed and every
                    // verdict erased by the time the alert went up (A5.2).
                    self.abandonRetry()
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
    private func run(_ batch: [URL], readingTextFrom extract: Set<URL> = [],
                     note: String? = nil, leftOut: [URL] = []) {
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

        // Running several files at once is ~3x faster than one at a time. An
        // OperationQueue rather than a TaskGroup because the per-file work
        // blocks on children, and blocking Swift-concurrency's cooperative
        // threads is exactly what it asks you not to do.
        let limit = max(1, min(UserDefaults.standard.integer(forKey: Prefs.concurrency),
                               Prefs.maxConcurrency))

        // **Where the ~3x actually comes from.** It was never threads: Vision
        // does not parallelise across concurrent requests inside one process
        // (1.08x at six), so while recognition ran in-process this queue bought
        // almost nothing and the corpus gate took 187 minutes against 75. It is
        // process-level parallelism, and R40 puts it back by giving each file's
        // recognition its own helper process. At most one helper per file in
        // flight, so this queue's limit is also the helper count.
        //
        // Not worth it for a batch that cannot be concurrent: with one file, or
        // with the setting turned down to one, there is nothing to overlap with
        // and the helper would only pay Vision's ~0.20s start-up a second time.
        let useHelper = Recogniser.helperIsWorthIt(concurrency: limit,
                                                   files: batch.count)
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
        // Why this batch exists, when it is not simply "the user pressed Start".
        // Passed in by `retryFailures` through `start`. A parameter rather than
        // model state, so a path that declines to run cannot leave it behind to
        // head an unrelated batch later.
        if let note { log.append(LogLine(text: note, kind: .info)) }
        // Both clocks. The wall clock is what a person reads off a report —
        // "which run was this?" — and the monotonic one is what the elapsed
        // time has to come from, because an overnight batch is exactly when a
        // clock adjustment lands and R30 is what happens when the two are
        // confused.
        runStarted = Date()
        runStartedMonotonic = DispatchTime.now()

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

        // Said once, up front, because the alternative is finding out 255 times.
        // An unsupported `-l` code is not ignored: mac-ocr exits 64 with
        // "Unsupported recognition language" and every file in the batch fails.
        // The usual way to get here is ticking Fast, which drops the list from
        // 30 languages to 6. Settings warns at the point of the mistake; this is
        // for the run that was already configured before anyone read that.
        //
        // Read from `settings`, not from UserDefaults again: every per-file
        // setting travels in the snapshot, and a second reader of the same key
        // is how a mid-batch change came to apply to some files and not others.
        let unsupported = Recogniser.unsupportedLanguages(in: settings.languages,
                                                         fast: settings.fast)
        if !unsupported.isEmpty {
            log.append(LogLine(
                text: "\(unsupported.joined(separator: ", ")) "
                    + (unsupported.count == 1 ? "is" : "are")
                    + " not a recognition language this Mac supports"
                    + (settings.fast ? " with Fast on" : "")
                    + " — every file will fail. Settings ▸ Recognition ▸ Languages.",
                kind: .failure))
        }

        // Said once for the batch, not once per file — a 255-file run would
        // otherwise carry 255 copies of it. A build with no helper in it still
        // works; it is just back to the throughput R40 is about, and going
        // quiet about that is how a 2.5x regression shipped unnoticed once.
        if useHelper, Recogniser.helperPath() == nil {
            log.append(LogLine(
                text: "The recognition helper is missing from this build, so "
                    + "recognition cannot use more than one core at a time and "
                    + "this batch will take considerably longer.",
                kind: .info))
        }

        let textExt = settings.textFormat.fileExtension
        let outputSuffix = isSearchable ? ".ocr" : ""
        let outputExt = isSearchable ? "pdf" : textExt

        // A fresh Start begins a new chain of reservations; a retry continues the
        // previous one's. **Not cleared from `add`, `remove` or `clearFiles`**,
        // and that is a correction to R60's own recorded fix direction: clearing
        // at a door reopens the defect whenever a retry follows the door. Drop a
        // folder holding a previous run's results, have one file fail, add an
        // unrelated file, then press Retry Failed — the list changed, so the
        // reservations would be gone, and the retry takes the protected name
        // again. The chain ends where a chain can actually end: at a Start that
        // is not a retry.
        if continuesRetryChain {
            continuesRetryChain = false
        } else {
            claimedByEarlierAttempts = []
            previousOutputs = [:]
        }
        // A run is really beginning, so there is nothing to put back: dropped, not
        // restored (A5.2). This is the one exit from `retryPutBack` that is not
        // `abandonRetry`, and it is the definition of the two states — a retry
        // either ran or it did not.
        retryPutBack = nil
        // Each retried input's own slot from the previous attempt, given back so
        // it is reused rather than renamed again.
        let releasing = Set(batch.compactMap { previousOutputs[$0] })
        let outputs = Self.uniqueOutputs(
            for: batch, besideOriginal: besideOriginal, folder: destination,
            suffix: outputSuffix, extension: outputExt,
            alsoClaimed: claimedByEarlierAttempts, releasing: releasing)

        // Recorded *after* resolving, so the next attempt in this chain knows
        // both what this one read and what it wrote. `files`, not `batch`: a file
        // the user chose to skip is still a file on disk that this batch had in
        // hand, and over-reserving only ever renames an output — visibly, through
        // `renamedOutputs` — where under-reserving destroys one.
        claimedByEarlierAttempts.formUnion(files)
        claimedByEarlierAttempts.formUnion(outputs.values)
        for (input, output) in outputs { previousOutputs[input] = output }

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
        // Per batch, like `tally`: a count left over from the last run would
        // describe the wrong batch in this run's report (R41).
        recognitionFallbacks = 0
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

            // The written report, last — so the log it copies is complete,
            // including the summary line above. Writing it before that point
            // would produce a report of a run that had not finished.
            self.writeReport(batch: batch, leftOut: leftOut, settings: settings,
                             rebuildImages: needsRebuild, rebuildMode: rebuildMode,
                             concurrency: limit,
                             recognitionInHelpers: useHelper
                                 && Recogniser.helperPath() != nil,
                             recognitionFallbacks: self.recognitionFallbacks,
                             destination: destination)

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
                // Said once per file at most: recognition fell back out of its
                // helper process, so this file was done the slow way. Counted as
                // well as logged, because the run report has to describe what
                // happened rather than what was configured (R41).
                let fellBack: (String) -> Void = { text in
                    DispatchQueue.main.async {
                        self?.recognitionFallbacks += 1
                        self?.log.append(LogLine(
                            text: "\(file.lastPathComponent): \(text)", kind: .info))
                    }
                }

                if isSearchable {
                    Self.makeSearchablePDF(
                        file: file,
                        output: outputs[file] ?? file.deletingLastPathComponent()
                            .appendingPathComponent(
                                file.deletingPathExtension().lastPathComponent + ".ocr.pdf"),
                        rebuild: needsRebuild, rebuildMode: rebuildMode,
                        password: password, settings: settings,
                        control: control, useHelper: useHelper,
                        progress: note, fellBack: fellBack, report: report)
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

                // No fraction: recognition of a whole file reports nothing
                // useful part-way for the single-page images this mode is
                // usually given. Claiming 0.5 pinned the bar at exactly half
                // for the whole of a single-file run, which reads as a stall.
                // An indeterminate bar is the honest shape.
                note("Recognising", -1)
                let target = outputs[file] ?? destination?
                    .appendingPathComponent(
                        file.deletingPathExtension().lastPathComponent + "." + textExt)
                    ?? file.deletingLastPathComponent().appendingPathComponent(
                        file.deletingPathExtension().lastPathComponent + "." + textExt)
                do {
                    try Recogniser.extract(from: file, to: target, settings: settings,
                                           password: password,
                                           isCancelled: { control.isCancelled })
                    if control.isCancelled { report(.cancelled, "Cancelled.") }
                    else { report(.succeeded, "") }
                } catch {
                    report(.failed, error.localizedDescription)
                }
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
    ///
    /// **And that protection is only as wide as the list it is given, which is
    /// how R60 destroyed a file.** `retryFailures` narrows `files` to the
    /// failures, so the sibling that was doing the protecting is no longer in the
    /// batch and the retry claims the name that had been reserved away from it.
    /// `alsoClaimed` carries the earlier attempt's inputs *and* its outputs
    /// forward; `releasing` gives each retried input its own previous slot back,
    /// so a retry reuses `scan 2.ocr.pdf` rather than being pushed to a third
    /// name on every attempt. Both are needed and neither is sufficient — R60
    /// records the two ways a one-sided version of this fails its own test.
    nonisolated static func uniqueOutputs(
        for files: [URL],
        besideOriginal: Bool,
        folder: URL?,
        suffix: String,
        extension ext: String,
        alsoClaimed: Set<URL> = [],
        releasing: Set<URL> = []
    ) -> [URL: URL] {
        func key(_ url: URL) -> String { url.standardizedFileURL.path.lowercased() }
        // Union in this order deliberately: an input of *this* batch is claimed
        // even if `releasing` names it, because a path being read right now is
        // the case the whole function exists for.
        var claimed = Set(alsoClaimed.map(key)).subtracting(releasing.map(key))
        claimed.formUnion(files.map(key))
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
    /// Two things this has to get right, and it got both wrong.
    ///
    /// **`replaceItemAt` needs both items on one volume**, and `staged` is always in
    /// `NSTemporaryDirectory()` — the boot volume. So an output folder on an external
    /// drive or a network share worked the first time and failed every time afterwards,
    /// with POSIX 18 (`EXDEV`) surfacing as "The file couldn't be saved in the folder".
    /// Correcting a setting and pressing Start again failed the whole batch. Fixed by
    /// moving the staged file next to its destination *first*, so the atomic replacement
    /// happens within one volume — which is what keeps invariant 2 ("build into scratch,
    /// publish only on success") true for a destination anywhere.
    ///
    /// **And `fileExists` is true for a directory**, which `replaceItemAt` then removes
    /// recursively: a directory named `scan.ocr.pdf` was destroyed, and publish returned
    /// success. Nothing in the pipeline aims at a directory — `uniqueOutputs` compares
    /// output paths against each other, never against what is on disk — but silently
    /// deleting a folder that was never OCR output is not a thing to leave to luck.
    nonisolated static func publish(_ staged: URL, to output: URL) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: output.path, isDirectory: &isDirectory)
        if exists, isDirectory.boolValue {
            throw Failure.destinationIsFolder(output.lastPathComponent)
        }
        guard exists else {
            try fm.moveItem(at: staged, to: output)
            return
        }
        // A sibling of the destination, so the replacement is same-volume whatever volume
        // that is. The name cannot collide with a real output: `uniqueOutputs` never
        // produces one with this prefix.
        let sibling = output.deletingLastPathComponent()
            .appendingPathComponent(".visionocr-publish-\(UUID().uuidString)")
        do {
            try fm.moveItem(at: staged, to: sibling)
        } catch {
            // The destination's own directory is not writable, or the volume is full.
            // Nothing has been touched, so the previous output survives — which is the
            // half of invariant 2 that matters most here.
            throw error
        }
        do {
            _ = try fm.replaceItemAt(output, withItemAt: sibling)
        } catch {
            // Put the staged file back where the caller left it, so a retry has
            // something to publish and no scratch is orphaned beside the user's file.
            try? fm.moveItem(at: sibling, to: staged)
            throw error
        }
    }

    /// Invariant 2's refusal, as one function: the message when `staged` is not
    /// the full length, and nil when it is.
    ///
    /// One copy, because there are two call sites — an early one that fails the
    /// document before spending seconds on the outline rewrite and the annotation
    /// transplant, and `publishVerified` immediately before the user's disk is
    /// touched. Two copies of a refusal is how C20 happened.
    nonisolated static func incompleteRefusal(_ staged: URL, expecting expected: Int) -> String? {
        let produced = PDFPageCount(staged)
        guard produced != expected else { return nil }
        return "The result had \(produced) pages but the source has \(expected); "
             + "nothing was written."
    }

    /// **CLAUDE.md invariant 2, in one place.** Verifies, and only then publishes.
    ///
    /// It exists because the invariant had no working test. Its sole guardian was
    /// a check asserting that a path *nothing in the test had ever written* did
    /// not exist, so deleting the page-count gate left the suite 862/862 green
    /// (`REVIEW-2026-08-14.md` A11.1). Splitting the verify-then-move pair into a
    /// named function is what lets a check drive it with a deliberately short
    /// file and a good file already at the destination — which is the exact
    /// situation the invariant exists for, and which no check could reach while
    /// the gate was one `guard` in the middle of a 500-line function.
    ///
    /// **It is defence in depth, not the closing of a hole, and saying otherwise
    /// would be this register's own recurring mistake.** A first version of this
    /// comment claimed the landing file "was never the file that was checked".
    /// That is false: the outline branch only adopts `outlined` when
    /// `PDFPageCount(outlined) == expected`, and the annotation branch re-reads
    /// `finished` and refuses on `after != expected`. Every path to `publish`
    /// already verified what it was about to publish. What this adds is a single
    /// named place where the invariant lives — which is what lets one check drive
    /// it with a deliberately short file, and what the mutant
    /// `A11.1-publishVerified-gate` perturbs.
    nonisolated static func publishVerified(_ staged: URL, expecting expected: Int,
                                            to output: URL) throws {
        if let refusal = incompleteRefusal(staged, expecting: expected) {
            throw Failure.incompleteResult(refusal)
        }
        try publish(staged, to: output)
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
        output: URL,
        rebuild: Bool,
        rebuildMode: Flattener.Mode,
        password: String?,
        settings: Prefs.Snapshot = .current(),
        control: RunControl,
        /// Whether recognition may go to a helper process (R40). Decided by the
        /// batch rather than here: a helper buys process-level parallelism, and
        /// with one file in the batch there is nothing to be parallel *with* —
        /// it would only pay Vision's ~0.20s start-up twice.
        useHelper: Bool = false,
        progress: @escaping (String, Double) -> Void,
        /// Called when recognition gave up on its helper process and did the
        /// document in-process instead (R40). Named for that one event rather
        /// than being a general "notice" channel, because the run report counts
        /// these — and a second, unrelated use of a general channel would
        /// silently inflate that count (R41).
        fellBack: @escaping (String) -> Void = { _ in },
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
        // Bilevel PNGs that jbig2enc has already consumed and recognition has
        // still to read. Only these: the JPEGs in the same directory are the
        // picture pages' actual streams and the assembly reads them later.
        var spentBitmaps: [URL] = []

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
            // Always, not only for JBIG2. The page bitmaps are what recognition
            // reads now, so the pixels drawn onto the page are exactly the
            // pixels Vision is given — no second rasterisation by anyone, at
            // any resolution, which is the whole of R39 removed rather than
            // worked around. The CoreGraphics route pays one PNG per page for
            // it, on a fallback that only runs when jbig2/qpdf are missing.
            try? FileManager.default.createDirectory(at: pngDir,
                                                     withIntermediateDirectories: true)
            do {
                bitmaps = try Flattener.flatten(
                    file, to: rebuilt, mode: rebuildMode, password: password,
                    pngDirectory: pngDir,
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
                            // Not deleted here any more: recognition has still
                            // to read it. It goes once the observations are in
                            // hand, which costs ~110 KB a page of scratch until
                            // then — 60 MB on a 600-page book, and no longer
                            // "for nothing".
                            spentBitmaps.append(png)
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

        // 2. Recognise it. Coordinates must come from the same pages we draw —
        //    and now they provably do: the bitmaps `flatten` produced are the
        //    images Vision reads, rather than a PDF re-rasterised by something
        //    else at a resolution of its own choosing. That round trip is what
        //    R39 was, and what U25's DPI negotiation existed to survive.
        let pageTotal = bitmaps.isEmpty ? PDFPageCount(visible) : bitmaps.count
        progress("Recognising page 0 of \(max(pageTotal, 0))", ocrShare(0, pageTotal))
        // `var` only because `adopting` takes a closure and Swift will not let one
        // initialise a `let` declared outside it. Assigned exactly once.
        var byPage: [Int: [SearchableWriter.Observation]] = [:]
        do {
            // `adopting`, not a bare `adopt`: the helper is a child, and quitting
            // the app must not leave it running (U2). One adoption for one
            // process, released structurally on the way out — the pairing the
            // JBIG2 route had to learn after leaking one per page.
            try control.adopting { register in
                byPage = try Recogniser.recogniseDocument(
                    visible: visible, bitmaps: bitmaps, settings: settings,
                    password: password, useHelper: useHelper,
                    isCancelled: { control.isCancelled },
                    onPage: { done, total in
                        progress("Recognising page \(done) of \(max(total, done))",
                                 ocrShare(done, total))
                    },
                    register: register,
                    onFallback: fellBack)
            }
        } catch {
            // A cancellation surfaces here as a throw, exactly as it does from the
            // rebuild above, and is a cancellation rather than a broken file.
            if control.isCancelled { report(.cancelled, "Cancelled."); return }
            report(.failed, "Could not recognise the pages: \(error.localizedDescription)")
            return
        }
        if control.isCancelled { report(.cancelled, "Cancelled."); return }
        // The bilevel bitmaps have been read and compressed; nothing wants them
        // again. Deliberately not the whole directory — the picture pages' JPEGs
        // sit beside them and are the streams the assembly is about to embed.
        for png in spentBitmaps { try? FileManager.default.removeItem(at: png) }

        // 3. Write the PDF. The destination was reserved up front, so two inputs
        //    with the same base name cannot collide here.
        let staged = work.appendingPathComponent("staged.pdf")

        // Carried out of the annotation step and onto the success line, because that is
        // what the run report keeps. See the transplant call below.
        var marksNote: String?

        // Read the expected page count now, while everything still exists. The
        // scratch intermediates get deleted as they're spent, so asking later
        // returned -1 for a file that had just been removed.
        let expected = PDFPageCount(visible)
        guard expected > 0 else {
            report(.failed, "Could not read the rebuilt PDF to check it.")
            return
        }

        do {
            // A page the recogniser never reported would compose as a page with
            // no text, pass the page-count check, and publish as a success.
            // `recogniseDocument` records every page it visits, empty array and
            // all, so a gap here means a page was skipped rather than blank —
            // which is now a bug in our own loop rather than in a subprocess's
            // output, and is still worth refusing to publish over.
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

                // Re-layer the picture pages now that the recogniser has said
                // where the words are.
                //
                // This has to happen here and not in `flatten`, which runs
                // before OCR and so does not yet know. The alternative — running
                // the recogniser inside `flatten` — would recognise every
                // document twice, and the whole point of doing this after the
                // fact is that the boxes already exist.
                //
                // Every failure is a no-op that leaves the page's existing JPEG
                // in place. MRC is an improvement on a working page, never a
                // requirement, and a page that costs more is a far better
                // outcome than one that fails or draws wrong.
                if let jb = JBIG2.encoder,
                   let source = Flattener.open(inputFile, password: password) {
                    var relayered = 0, savedBytes = 0
                    for index in encoded.indices {
                        if control.isCancelled { break }
                        // Any picture page, grey or colour. A bilevel page is
                        // already cheaper than MRC could be and is skipped.
                        //
                        // R49. Colour pages were excluded here because their
                        // layers had not been measured, and that exclusion was
                        // the whole of a 14x inflation: an Internet Archive scan
                        // of a 1971 monograph renders with its paper at luminance
                        // 148 and a grey-green cast, which reads as colour on the
                        // page, so all 568 text pages were kept in colour — and
                        // colour was exactly the case that could not be layered.
                        // 31 MB in, 437 MB out, every page a full-resolution
                        // three-channel JPEG.
                        //
                        // Layering is the right answer rather than re-routing
                        // those pages: whether that scan's cast is paper or ink
                        // cannot be told from its luminance histogram — measured,
                        // a flat-tinted plate with a dark subject on it is
                        // indistinguishable from it on every tonal signal — so a
                        // detector change would have to guess. This does not
                        // guess. It keeps the page's colour, keeps its text at
                        // full resolution in the stencil, and is taken only when
                        // it is measurably smaller.
                        guard case .jpeg(let existing) = encoded[index].stream,
                              let page = source.page(at: index),
                              let boxes = byPage[index + 1]?.map({ $0.boundingBox }),
                              !boxes.isEmpty else { continue }
                        let before = (try? Data(contentsOf: existing).count) ?? 0
                        guard let layers = Flattener.mrcLayers(
                            for: page, boxes: boxes, into: pngDir,
                            stem: String(format: "m%05d", index + 1),
                            backgroundDownsample: settings.photoDetail.downsample,
                            inColour: encoded[index].isColour)
                        else { continue }
                        let stencil = pngDir.appendingPathComponent(
                            String(format: "m%05d.jbig2", index + 1))
                        do {
                            try control.adopting { register in
                                try JBIG2.encode(png: layers.mask, to: stencil,
                                                 using: jb, register: register)
                            }
                        } catch {
                            for u in [layers.mask, layers.background, layers.foreground,
                                      stencil] {
                                try? FileManager.default.removeItem(at: u)
                            }
                            continue
                        }
                        try? FileManager.default.removeItem(at: layers.mask)
                        let after = [stencil, layers.background, layers.foreground]
                            .reduce(0) { $0 + ((try? Data(contentsOf: $1).count) ?? 0) }
                        // Three layers are not always cheaper than one image —
                        // a page of dense halftone with a caption under it can
                        // come out larger. Keep whichever is smaller rather than
                        // assuming, and say so in the log.
                        guard after < before else {
                            for u in [stencil, layers.background, layers.foreground] {
                                try? FileManager.default.removeItem(at: u)
                            }
                            continue
                        }
                        encoded[index] = JBIG2.Page(
                            stream: .mrc(JBIG2.Page.MRC(
                                mask: stencil,
                                background: layers.background,
                                foreground: layers.foreground,
                                backgroundWidth: layers.backgroundWidth,
                                backgroundHeight: layers.backgroundHeight,
                                foregroundWidth: layers.foregroundWidth,
                                foregroundHeight: layers.foregroundHeight,
                                // The layers', not the page's: a colour page
                                // whose colour render failed is layered in grey.
                                isColour: layers.isColour)),
                            pixelWidth: encoded[index].pixelWidth,
                            pixelHeight: encoded[index].pixelHeight,
                            boxSize: encoded[index].boxSize,
                            isColour: encoded[index].isColour)
                        try? FileManager.default.removeItem(at: existing)
                        relayered += 1
                        savedBytes += before - after
                    }
                    if relayered > 0 {
                        progress("Layered \(relayered) picture page"
                                 + "\(relayered == 1 ? "" : "s"), saving \(savedBytes / 1024) KB",
                                 layerShare(0, 1))
                    }
                }
                let textLayer = work.appendingPathComponent("text.pdf")
                unplaced = try SearchableWriter.compose(
                    visible: visible, observations: byPage, to: textLayer,
                    drawImages: false, password: password,
                    joinHyphenated: settings.joinHyphenated,
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
                for page in encoded { for u in page.stream.urls { try? FileManager.default.removeItem(at: u) } }
                // Registered so Cancel can interrupt the merge, which is the slow
                // step on a large book and used to leave Cancel looking dead.
                try control.adopting { register in
                    try JBIG2.overlay(text: textLayer, onto: imagesOnly,
                                      to: staged, using: qpdf, register: register)
                }
                try? FileManager.default.removeItem(at: imagesOnly)
                try? FileManager.default.removeItem(at: textLayer)
            } else {
                // The Flate route. Same setting, or a user who turned joining on
                // would get it only when jbig2 and qpdf happened to be present —
                // the sibling-site mistake R23, R29 and C20 are all made of.
                unplaced = try SearchableWriter.compose(
                    visible: visible, observations: byPage, to: staged,
                    password: password,
                    joinHyphenated: settings.joinHyphenated,
                    isCancelled: { control.isCancelled },
                    progress: { d, t in progress("Writing pages \(d) of \(t)",
                                                 layerShare(d, t)) })
            }

            // Never publish a partial result. Early, so a short result fails
            // before the outline rewrite and the annotation transplant are paid
            // for; the copy that *enforces* the invariant is `publishVerified`,
            // immediately before the move, and reads the file that actually
            // lands rather than this one.
            if control.isCancelled { report(.cancelled, "Cancelled."); return }
            if let refusal = Self.incompleteRefusal(staged, expecting: expected) {
                report(.failed, refusal)
                return
            }

            // A line the writer could not place is reported, not swallowed.
            if !unplaced.isEmpty {
                report(.failed, Self.unplacedSummary(unplaced))
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
            var finished = staged
            if !usedJBIG2, !outline.isEmpty,
               SearchableWriter.copyOutline(from: inputFile, of: staged, to: outlined,
                                            password: password),
               PDFPageCount(outlined) == expected {
                finished = outlined
            }

            // Carry the reader's own marks across, last, onto whichever file is about
            // to be published.
            //
            // **Last, and not earlier**, for two reasons. The outline rewrite above is
            // a PDFKit re-serialisation, and running it *after* the transplant would
            // re-encode every appearance stream the transplant just carried — the same
            // 4.08x inflation that ruled PDFKit out as the mechanism. And a transplant
            // is only worth doing onto a file that has already passed every other gate.
            //
            // **A failure here fails the document.** `Annotations.transplant` verifies
            // its own work — count and rectangle per page, read back out of the rebuilt
            // file — and throws rather than publishing something it cannot vouch for.
            // That is invariant 1 applied to somebody's marginalia: a file whose
            // highlights silently moved misrepresents their reading of it, and is worse
            // than a file left alone. The catch below reports it and returns, so
            // nothing is published and the input is untouched.
            if settings.preserveAnnotations {
                // `file`, not `inputFile`: an image input was wrapped into a PDF above,
                // and qpdf cannot read a PNG. Passing the original made every image
                // input fail the whole conversion once this setting was on — over a
                // transplant that could never have had anything to do.
                //
                // Not named `report`: that is the outcome callback, and shadowing it
                // here would silently redirect the failure paths below.
                let marks = try Annotations.transplant(
                    from: file, into: finished, password: password,
                    qpdf: JBIG2.merger, scratch: work,
                    isCancelled: { control.isCancelled },
                    // `adopting`, not `adopt`: the pairing is what releases the child.
                    // An unpaired adopt here leaked one descriptor per qpdf pass for the
                    // whole batch — R15's shape, and fatal on a library-sized sweep.
                    adopting: { body in try control.adopting(body) })
                if marks.copiedTotal > 0 || marks.droppedTotal > 0 {
                    progress(marks.summary, layerShare(1, 1))
                    // And onto the outcome, which is what reaches the run report. A
                    // status line is cleared the moment the file finishes, so "left
                    // 3,991 Links" was unrecoverable a second after it was said — thin
                    // for something invariant 1 requires to be reported.
                    marksNote = marks.summary
                }
                // The transplant rewrites the file through qpdf, so the page count is
                // established again rather than assumed to have survived.
                let after = PDFPageCount(finished)
                guard after == expected else {
                    report(.failed, "Carrying the reader's marks changed the page count "
                        + "from \(expected) to \(after); nothing was written.")
                    return
                }
            }
            // Last thing before the user's disk is touched.
            //
            // The gate above is several seconds earlier on a long document: `copyOutline`
            // is a full PDFKit re-serialisation at about 13 ms a page, and the annotation
            // transplant adds three qpdf passes. Measured, a cancel landing in that window
            // published the file and reported **succeeded** — so "failure is reported,
            // never published" and "three gates, then publish" were both false. This does
            // not shorten the window, it stops it from ending in a publish.
            if control.isCancelled { report(.cancelled, "Cancelled."); return }
            try publishVerified(finished, expecting: expected, to: output)
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
        // `filter { !$0.isEmpty }`, not `compactMap`: `sizeNote` returns an empty string
        // rather than nil unless the copy grew, so joining on it put a leading " — " in
        // front of the message every ordinary run showed the user.
        report(.succeeded, [sizeNote(from: inputFile, to: output), marksNote ?? ""]
                             .filter { !$0.isEmpty }.joined(separator: " — "))
    }

    /// A note when the searchable copy came out **larger** than the original.
    ///
    /// Measured across 40 corpus documents, the app is 1.79x smaller overall
    /// (134.3 MB in, 75.0 MB out) — but 15 of the 40 grew, and the split is by
    /// input size: under 1 MB, 9 of 13 grew. That surprised the person it
    /// happened to, and a surprise on an archival tool is worth a sentence.
    ///
    /// Diagnosed rather than guessed at (BUGS.md R37). The growth is entirely in
    /// the images — on the worst case the text layer is 29 KB of a 249 KB file —
    /// and it is not resolution or a noisy threshold: rendered at the source's
    /// own DPI, our bilevel page carries the same ink to three decimal places
    /// (0.0974 against 0.0973) and is indistinguishable at 1:1. What differs is
    /// the encoder. Such inputs were compressed with **symbol-mode JBIG2**,
    /// which pools repeated glyph shapes and which this app refuses on purpose —
    /// it is the mechanism behind the Xerox scanners that silently swapped
    /// digits. Measured on one such page at 4300x6000: 17 KB theirs, 95 KB ours.
    ///
    /// So this is not a defect to fix by compressing harder; the alternative is
    /// a compression that can alter digits in an archival document. It is a
    /// result to state plainly, so nobody has to wonder.
    /// The failure message for lines `compose` could not place.
    ///
    /// **Counts, pages and reasons — never the text itself.** This string reaches
    /// `report(.failed:)` → `log` → `RunReport.text`, and the report copies the
    /// log *verbatim* into `~/Library/Logs/VisionOCR`, a file whose own docstring
    /// calls it one "that gets mailed to whoever is helping you". It is written by
    /// default and it is also spoken aloud.
    ///
    /// It carried `text.prefix(24)` for up to three lines until A4.1 — 72
    /// characters of the user's document, with the page numbers to find them by.
    /// The page and the reason are what diagnosing an unplaced line actually
    /// needs, and neither identifies content. **Invariant 1 is unaffected**: the
    /// count, the pages and the elision are all still here, so the loss is as
    /// loud as it was. The text was the one part that only the user's own file
    /// could supply.
    nonisolated static func unplacedSummary(_ lost: [SearchableWriter.Unplaced]) -> String {
        let detail = lost.prefix(3)
            .map { "p\($0.page) (\($0.reason))" }
            .joined(separator: "; ")
        return "\(lost.count) line(s) could not be placed: \(detail)"
            + (lost.count > 3 ? " …" : "")
    }

    nonisolated static func sizeNote(from input: URL, to output: URL) -> String {
        // PDF in, PDF out, or the comparison is meaningless. The drop box also
        // takes jpg, png, heic and tiff, and a photograph wrapped into a
        // searchable PDF is *always* bigger than the photograph — saying the
        // original "used a stronger compression" would be both wrong and
        // baffling, since the user never chose a compression at all.
        guard input.pathExtension.lowercased() == "pdf" else { return "" }
        func bytes(_ url: URL) -> Int? {
            (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int
        }
        guard let before = bytes(input), let after = bytes(output),
              before > 0, after > before else { return "" }
        // A hair over is not worth a sentence; the searchable copy carries a
        // text layer the original did not have, and that is the product.
        guard Double(after) / Double(before) >= sizeNoteRatio else { return "" }
        return String(format: "the searchable copy is larger than the original "
                      + "(%@ from %@) — the original used a stronger compression "
                      + "than this app will apply to a scan",
                      ByteCountFormatter.string(fromByteCount: Int64(after), countStyle: .file),
                      ByteCountFormatter.string(fromByteCount: Int64(before), countStyle: .file))
    }

    /// How much larger the copy has to be before it is worth saying so.
    ///
    /// 1.25: a searchable copy always costs something the original did not carry,
    /// and reporting every 3% would be noise. The cases this exists for ran
    /// 1.35x to 2.26x.
    nonisolated static let sizeNoteRatio = 1.25

    /// Running totals for the batch in flight. Main-actor only.
    private var tally: (succeeded: Int, failed: Int, cancelled: Int) = (0, 0, 0)

    /// How many files in this batch gave up on their helper process and
    /// recognised in the app instead (R40's fallback). Counted so the run report
    /// can say what *happened* rather than what was configured — a helper that is
    /// present and broken used to be reported as though it had been used (R41).
    private var recognitionFallbacks = 0

    /// When the batch in flight began, on both clocks. See `run(_:binary:)`.
    private var runStarted: Date?
    private var runStartedMonotonic: DispatchTime?

    /// Where the last finished batch's report was written, if one was.
    /// Published so the results pane can offer to reveal it.
    @Published var lastReport: URL?

    /// Writes the run report, and says in the log what it did.
    ///
    /// Never throws and never fails the batch: the documents are already
    /// written and a missing report is not a lost page. But it does not fail
    /// *silently* either — the point of the feature is knowing what happened,
    /// and a report that was not written while the log claims one exists is the
    /// same shape as the bug it fixes.
    private func writeReport(batch: [URL], leftOut: [URL], settings: Prefs.Snapshot,
                             rebuildImages: Bool, rebuildMode: Flattener.Mode,
                             concurrency: Int, recognitionInHelpers: Bool,
                             recognitionFallbacks: Int, destination: URL?) {
        lastReport = nil
        guard UserDefaults.standard.bool(forKey: Prefs.writeRunReport) else { return }
        let finished = Date()
        let elapsed = runStartedMonotonic.map {
            Double(DispatchTime.now().uptimeNanoseconds &- $0.uptimeNanoseconds) / 1_000_000_000
        } ?? 0
        let context = RunReport.Context(
            version: Updater.currentVersion,
            started: runStarted ?? finished,
            finished: finished,
            elapsed: elapsed,
            settings: settings,
            rebuildImages: rebuildImages,
            rebuildMode: rebuildMode,
            concurrency: concurrency,
            recognitionInHelpers: recognitionInHelpers,
            recognitionFallbacks: recognitionFallbacks,
            destination: destination,
            // `batch` is what ran; "Skip Those" hands `run` the remainder and
            // keeps the skipped ones out of it. Counting only `batch` would let
            // a report say "10 files, 10 succeeded" about a drop of fourteen —
            // an omission of exactly the shape invariant 1 forbids. Passed in
            // rather than read off `self.skipped`, which also holds marks from
            // earlier runs.
            inputs: batch + leftOut,
            outcomes: outcomes,
            skipped: Set(leftOut),
            log: log.map(\.text))
        switch RunReport.write(context) {
        case .success(let url):
            lastReport = url
            log.append(LogLine(text: "Run report: \(url.path)", kind: .info))
        case .failure(let error):
            log.append(LogLine(
                text: "Couldn't write the run report: \(error.localizedDescription)",
                kind: .failure))
        }
    }

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
