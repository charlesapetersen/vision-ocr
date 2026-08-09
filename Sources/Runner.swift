import Foundation

/// Locates the mac-ocr binary and runs it once per input file.
///
/// One process per file rather than one process for all of them: mac-ocr goes
/// silent when its output is piped, so per-file invocation is the only way to
/// report real progress, and it lets one bad PDF fail without taking the rest
/// of the batch down with it.
enum Runner {

    // MARK: - Finding the binary

    /// A GUI app launched from Finder gets a bare PATH (/usr/bin:/bin:...), so
    /// the Homebrew/npm install of mac-ocr is *not* on it. Look in the places
    /// it actually lands instead of trusting the environment.
    static let searchPaths = [
        "/opt/homebrew/bin/mac-ocr",          // Homebrew, Apple silicon
        "/usr/local/bin/mac-ocr",             // Homebrew (Intel) and npm -g default
        "/opt/local/bin/mac-ocr",             // MacPorts
    ]

    /// Whether a path names something we could actually execute.
    ///
    /// `isExecutableFile(atPath:)` alone is not enough — it returns **true for
    /// directories** (verified: `/opt/homebrew/bin` and `/Users/<name>` both
    /// report true), because the executable bit on a directory means "searchable".
    /// So typing a folder into the mac-ocr path field passed validation, the
    /// panel reported it was being used, and then every file in the batch failed
    /// with "Could not launch mac-ocr".
    static func isRunnable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return false }
        return fm.isExecutableFile(atPath: path)
    }

    /// Resolved path to mac-ocr, or nil if it can't be found.
    /// An explicit path in settings always wins.
    static func resolveBinary() -> String? {
        let override = (UserDefaults.standard.string(forKey: Prefs.binaryPath) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty {
            // Checked live, not cached: the user can point this anywhere.
            return isRunnable(override) ? override : nil
        }
        // Standard prefixes, then a login shell for nvm/asdf/custom prefixes.
        return locateTool("mac-ocr")
    }

    /// Finds any helper tool the same way, for the same reason: a Finder-launched
    /// app gets a bare PATH and won't see Homebrew.
    ///
    /// Memoised, because the fallback spawns a login shell (~85 ms) and SwiftUI
    /// asks for these paths from inside a view body — which is re-evaluated on
    /// every keystroke. Uncached, a settings panel on a machine where the tools
    /// live outside the standard prefixes spent ~0.4 s per keypress shelling out.
    static func locateTool(_ name: String) -> String? {
        cacheLock.lock()
        if let cached = discovered[name] { cacheLock.unlock(); return cached }
        cacheLock.unlock()

        var found: String?
        for prefix in ["/opt/homebrew/bin/", "/usr/local/bin/", "/opt/local/bin/"] {
            let path = prefix + name
            if isRunnable(path) { found = path; break }
        }
        if found == nil { found = askLoginShell(for: name) }

        cacheLock.lock()
        discovered[name] = found
        cacheLock.unlock()
        return found
    }

    /// Forgets the cache, for when the user installs something mid-session.
    static func forgetToolPaths() {
        cacheLock.lock(); discovered.removeAll(); cacheLock.unlock()
    }

    private static let cacheLock = NSLock()
    private static var discovered: [String: String?] = [:]

    private static func askLoginShell() -> String? { askLoginShell(for: "mac-ocr") }

    private static func askLoginShell(for name: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lc", "command -v \(name)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }

        // Bounded, because this runs on the main thread — from `start()` and
        // from the Settings panel's body. A login shell that blocks (a slow
        // network mount in a profile, an interactive prompt, a wedged NFS home)
        // froze the whole app with no way out. Three seconds is far longer than
        // the ~85 ms this normally takes.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if !wait(for: p, upTo: 3) {
            stop(p)
            return nil
        }
        guard p.terminationStatus == 0 else { return nil }
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, isRunnable(path) else { return nil }
        return path
    }

    // MARK: - Building the command

    /// Builds the argument list for one input file in **Extract Text** mode.
    /// `outputFolder` is ignored when the "beside the original" pref is set.
    ///
    /// `explicitOutputFile` overrides both and is what the batch path always
    /// passes, because `uniqueOutputs` has already resolved a distinct
    /// destination for every input — two files called `scan.pdf` in different
    /// folders would otherwise write to one place.
    ///
    /// There was an `explicitOutputDir` here too, for a caller that hands mac-ocr
    /// a temporary copy rather than the user's own file. It never had one: the
    /// searchable pipeline does not go through `arguments` at all, so the
    /// parameter was a correct, tested override for a caller that did not exist.
    /// Deleted rather than kept — dead options are how `ocrAllPages` survived
    /// for months looking live.
    ///
    /// `settings` is snapshotted once per batch on the main actor. It defaults to
    /// reading the live values so tools and tests stay terse, but the batch path
    /// always passes one — reading `UserDefaults` per file on a worker thread is
    /// what let a mid-run settings change apply to some files and not others.
    ///
    /// **There is deliberately no searchable-PDF form.** mac-ocr's own
    /// `searchable-pdf` subcommand has zero call sites in this app and always
    /// has — see HANDOFF.md for why we write the text layer ourselves — so the
    /// branch that used to build it here described a command that never ran, as
    /// did the `--ocr-all-pages` and `--ocr-strategy` flags, which belong to
    /// that subcommand and to nothing else. `Model.makeSearchablePDF` is the
    /// searchable pipeline; it asks mac-ocr for recognition only, through
    /// `jsonLinesArguments`.
    static func arguments(
        for file: URL,
        outputFolder: URL?,
        explicitOutputFile: URL? = nil,
        settings: Prefs.Snapshot = .current()
    ) -> [String] {
        var args = [file.path]

        // --- where the result goes -------------------------------------------
        // '[name]' is a mac-ocr template placeholder for the input's base name.
        // Without it, a directory target yields "scan.pdf.txt" rather than
        // "scan.txt".
        let beside = settings.besideOriginal
        let format = settings.textFormat
        args += ["--format", format.rawValue]
        if let explicitOutputFile {
            // A concrete path, not mac-ocr's '[name]' template: two inputs
            // with the same base name would otherwise write to one file.
            args += ["-o", explicitOutputFile.path]
        } else {
            let dir = beside ? "[dir]" : (outputFolder?.path ?? "[dir]")
            args += ["-o", "\(dir)/[name].\(format.fileExtension)"]
        }

        return args + recognitionArguments(settings)
    }

    /// Recognition options, identical whatever we ask mac-ocr to produce.
    static func recognitionArguments(_ settings: Prefs.Snapshot = .current()) -> [String] {
        var args: [String] = []

        if settings.fast { args.append("--fast") }

        // Repeatable -l, one per language. Accepts commas, spaces or newlines.
        for lang in splitList(settings.languages) {
            args += ["-l", lang]
        }

        if !settings.languageCorrection { args.append("--no-language-correction") }

        if settings.confidence > 0 { args += ["-c", trimNumber(settings.confidence)] }

        if !settings.pdfDPIAuto {
            args += ["--pdf-dpi", String(clamp(settings.pdfDPI, 72, 600))]
        }

        if !settings.password.isEmpty { args += ["--password", settings.password] }

        for word in splitList(settings.customWords) {
            args += ["-w", word]
        }

        if settings.minTextHeightOn, settings.minTextHeight > 0 {
            args += ["--min-text-height", trimNumber(settings.minTextHeight)]
        }

        return args
    }

    /// Asks for Vision's observations as JSON, which is all we need from mac-ocr
    /// when this app writes the searchable PDF itself.
    static func jsonArguments(for file: URL, jsonOut: URL,
                              settings: Prefs.Snapshot = .current()) -> [String] {
        [file.path, "--format", "json", "-o", jsonOut.path] + recognitionArguments(settings)
    }

    /// Same, but as JSON Lines on stdout: one object per page, emitted as each
    /// page is recognised. That streaming is what lets a 200-page book report
    /// progress instead of sitting silent for minutes.
    static func jsonLinesArguments(for file: URL,
                                   settings: Prefs.Snapshot = .current()) -> [String] {
        [file.path, "--format", "jsonl"] + recognitionArguments(settings)
    }

    /// Runs mac-ocr and hands back each stdout line as it arrives.
    ///
    /// `Runner.run` discards stdout and only returns on exit, so it can't report
    /// progress. This reads incrementally instead.
    static func runStreaming(
        binary: String,
        arguments: [String],
        onLine: @escaping (String) -> Void,
        wasCancelled: () -> Bool = { false },
        register: (Process) -> Void
    ) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        do { try process.run() } catch {
            return Result(file: URL(fileURLWithPath: arguments.first ?? ""), outcome: .failed,
                          message: "Could not launch mac-ocr: \(error.localizedDescription)")
        }
        register(process)

        // Drain stderr on a separate queue so a chatty run can't fill the pipe
        // and deadlock while we're reading stdout.
        //
        // Behind a lock: the drain outlives the wait below when it times out, and
        // reading a plain `var` written on another queue was a real data race
        // (ThreadSanitizer-confirmed) that also lost the error message.
        final class ErrorBox: @unchecked Sendable {
            private let lock = NSLock()
            private var value = Data()
            func append(_ bytes: Data) { lock.lock(); value.append(bytes); lock.unlock() }
            var text: String {
                lock.lock(); defer { lock.unlock() }
                return String(decoding: value, as: UTF8.self)
            }
        }
        let errorBox = ErrorBox()
        let errQueue = DispatchQueue(label: "mac-ocr-stderr")
        let errDone = DispatchSemaphore(value: 0)

        // A DispatchSource rather than a poll loop. `readDataToEndOfFile` is out
        // — it returns only when every writer closes, and the writers include
        // any grandchild that inherited stderr, which parked the drain for ever
        // on the cancelled path and stranded a thread and a pipe per cancelled
        // file. But the poll loop that replaced it woke every 200 ms for the
        // whole life of the run purely to notice a stop flag: with a dozen files
        // in flight that is sixty wakeups a second doing nothing. A read source
        // is genuinely idle until bytes arrive, and `cancel()` replaces the flag.
        let efd = err.fileHandleForReading.fileDescriptor
        _ = fcntl(efd, F_SETFL, fcntl(efd, F_GETFL, 0) | O_NONBLOCK)
        let errSource = DispatchSource.makeReadSource(fileDescriptor: efd, queue: errQueue)
        errSource.setEventHandler {
            var chunk = [UInt8](repeating: 0, count: 16 * 1024)
            while true {
                let n = chunk.withUnsafeMutableBytes { read(efd, $0.baseAddress, $0.count) }
                if n > 0 { errorBox.append(Data(chunk[0..<n])); continue }
                if n == 0 { errSource.cancel(); return }   // EOF: every writer closed
                if errno == EINTR { continue }
                if errno == EAGAIN { return }              // drained; wait for more
                errSource.cancel()
                return
            }
        }
        // Runs once, whichever cancels first — EOF above or the defer below.
        errSource.setCancelHandler { errDone.signal() }
        errSource.resume()
        // However this call returns, the drain goes with it — and it is finished
        // touching the descriptor before it does. Cancellation is asynchronous,
        // `err`'s descriptor closes when this scope ends, and a handler still
        // in `read()` on a closed descriptor is undefined behaviour. The queue
        // is serial, so a sync barrier is the whole of the fix.
        defer {
            errSource.cancel()
            errQueue.sync { }
        }

        // Poll rather than `availableData`. `availableData` blocks in read(2)
        // until a byte arrives or every writer closes, and the writers include
        // any grandchild that inherited stdout — so a child that exits promptly
        // while leaving a descendant holding the pipe used to keep this loop
        // parked long after Cancel, with the cancel already spent. Verified: a
        // child exiting immediately but leaving a `sleep 8` on stdout, cancelled
        // at 1.0 s, returned after 8.28 s reporting success.
        //
        // With a timeout the loop wakes regularly, notices the cancellation and
        // leaves, and the pipe is abandoned rather than waited on.
        let fd = out.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)

        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var cancelledMidRead = false

        readLoop: while true {
            if wasCancelled() { cancelledMidRead = true; break }

            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 200)      // ms: how long a cancel waits
            if ready < 0 {
                if errno == EINTR { continue }
                break
            }
            if ready == 0 { continue }                  // timed out; re-check cancel

            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n == 0 { break }                         // EOF: every writer closed
            if n < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                break
            }
            pending.append(contentsOf: buffer[0..<n])
            while let nl = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<nl]
                pending.removeSubrange(pending.startIndex...nl)
                if !line.isEmpty { onLine(String(decoding: line, as: UTF8.self)) }
            }
        }
        if !cancelledMidRead, !pending.isEmpty {
            onLine(String(decoding: pending, as: UTF8.self))
        }

        let file = URL(fileURLWithPath: arguments.first ?? "")
        if cancelledMidRead {
            // Don't wait on it: the reason we are here is that something in the
            // process tree is not going away on its own.
            stop(process)
            _ = errDone.wait(timeout: .now() + 1)
            return Result(file: file, outcome: .cancelled, message: "Cancelled.")
        }

        // Bounded, so a child that ignores SIGTERM cannot wedge the batch here
        // either — this was a second unbounded wait on the same path.
        var exited = wait(for: process, upTo: 5)
        if !exited {
            stop(process)
            exited = !process.isRunning
        }
        _ = errDone.wait(timeout: .now() + 5)
        let errorText = errorBox.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // `terminationStatus` raises an ObjC exception if the child has not
        // exited, and an ObjC exception in Swift is not catchable — it aborts the
        // process. Both waits above are best-effort by construction, so the
        // status may simply not exist yet. Say what actually happened instead of
        // reading a value that isn't there.
        guard exited else {
            return Result(file: file, outcome: .failed,
                          message: errorText.isEmpty
                              ? "mac-ocr stopped responding and could not be terminated."
                              : errorText)
        }

        if process.terminationStatus == 0 { return Result(file: file, outcome: .succeeded, message: "") }
        if process.terminationReason == .uncaughtSignal, wasCancelled() {
            return Result(file: file, outcome: .cancelled, message: "Cancelled.")
        }
        // A child we killed ourselves prints nothing, so the stderr box is empty
        // and the run used to be reported as a bare "failed" with no message.
        return Result(file: file, outcome: .failed,
                      message: errorText.isEmpty
                          ? "mac-ocr exited with code \(process.terminationStatus)."
                          : errorText)
    }

    /// Waits for a process, but not forever. True if it exited in time.
    ///
    /// Monotonic, not `Date()`. A wall clock goes backwards and forwards — an
    /// NTP step, or a laptop waking from sleep — and either direction is wrong
    /// here: a jump forward abandons a perfectly healthy child on its next
    /// iteration, and a jump back extends a wait that is supposed to be bounded.
    @discardableResult
    static func wait(for process: Process, upTo seconds: Double) -> Bool {
        let deadline = DispatchTime.now() + seconds
        while process.isRunning, DispatchTime.now() < deadline { usleep(20_000) }
        return !process.isRunning
    }

    /// The process group a child leads, when it leads one of its own.
    ///
    /// Foundation launches each child as its own process-group leader, and a
    /// grandchild inherits that group. Measured — child pid 31398, child pgid
    /// 31398, grandchild pgid 31398 — and it is the whole reason a single
    /// signal can reach the tree without replacing `Process` with `posix_spawn`.
    ///
    /// Returns nil unless the child really is the leader of a group that is not
    /// ours. `kill(-group)` on our own group would take the app down along with
    /// the batch, so the `group == pid` test is load-bearing, not defensive
    /// decoration: if a future Foundation stops making its children group
    /// leaders this returns nil and `stop` falls back to signalling the pid,
    /// which is what it did before.
    static func processGroup(of process: Process) -> pid_t? {
        let pid = process.processIdentifier
        guard pid > 0 else { return nil }
        let group = getpgid(pid)
        guard group > 0, group == pid, group != getpgid(0) else { return nil }
        return group
    }

    /// SIGTERM, then SIGKILL if it does not go — to the child *and everything
    /// it started*.
    ///
    /// The escalation was the hole, and it was not where it was thought to be.
    /// `Process.terminate()` already reaches the whole group, so a well-behaved
    /// tree does die (measured: a `sh` with a backgrounded `sleep` loses both).
    /// But the SIGKILL was sent to the *pid*, and `kill(pid, SIGKILL)` reaches
    /// one process. So the one case escalation exists for — a child that ignores
    /// SIGTERM — was also the one case that leaked: measured, the child died and
    /// its grandchild ran on, reparented to launchd, holding its pipe. SIGKILL
    /// goes to the group now.
    ///
    /// The group is read before the first signal, because `getpgid` needs the
    /// child to still exist.
    static func stop(_ process: Process, graceSeconds: Double = 2) {
        guard process.isRunning else { return }
        let group = processGroup(of: process)

        // Reaches the group as well as the child.
        process.terminate()

        if !wait(for: process, upTo: graceSeconds) {
            // Re-check immediately before signalling. `wait` returning false only
            // means the child was still up when the deadline passed; if it exited in
            // the interval since, its PID could in principle have been reused, and
            // SIGKILL to a recycled PID would kill something else entirely.
            if process.isRunning {
                if let group { kill(-group, SIGKILL) } else { kill(process.processIdentifier, SIGKILL) }
                _ = wait(for: process, upTo: 2)
            }
        }

        // And anything left in the group either way: a descendant that ignored
        // SIGTERM outlives a child that did not, and nothing else would collect
        // it. Killing an empty group is a no-op.
        if let group { kill(-group, SIGKILL) }
    }

    /// What a run will actually do, for the log and the settings panel.
    ///
    /// Searchable PDFs are a multi-step pipeline, not a single command, so
    /// showing only the mac-ocr call would misrepresent it — and the steps that
    /// are *not* mac-ocr are the ones most likely to be misconfigured.
    ///
    /// Not "the exact command a run will use", which is what this claimed while
    /// getting two things wrong. On a fresh install there is no destination yet,
    /// and an unchosen folder rendered identically to "save beside each
    /// original" — `-o '[dir]/[name].txt'`, promising a destination the run
    /// would refuse while Start sat disabled. And the compression step, which
    /// shells out to two further binaries, was not shown at all, so the setting
    /// most likely to be wrong (the tool paths, U9) could not be checked against
    /// the one place in the UI that exists for checking settings.
    static func previewLines(binary: String, file: URL, outputFolder: URL?) -> [String] {
        let d = UserDefaults.standard
        let mode = Prefs.Mode(rawValue: d.string(forKey: Prefs.mode) ?? "") ?? .searchablePDF
        let shown = (binary as NSString).lastPathComponent
        func leaf(_ path: String) -> String { (path as NSString).lastPathComponent }

        var lines: [String] = []
        // "Nowhere yet" is not "beside each original". A run cannot start in
        // this state, and the preview now says so rather than showing a
        // plausible command against a destination nobody chose.
        if !d.bool(forKey: Prefs.besideOriginal), outputFolder == nil {
            lines.append("No output folder chosen yet — Start stays disabled until you "
                         + "pick one, or turn on “Save beside each original”.")
        }

        switch mode {
        case .text:
            lines.append(preview(binary: shown,
                                 arguments: arguments(for: file, outputFolder: outputFolder)))
        case .searchablePDF:
            var steps: [String] = []
            let rebuilding = d.bool(forKey: Prefs.rebuildImages)
            let how = Flattener.Mode(rawValue: d.string(forKey: Prefs.rebuildMode) ?? "") ?? .auto
            if rebuilding {
                steps.append("rebuild pages as \(how.label.lowercased()) images "
                             + "(drops any existing text layer)")
            }
            steps.append(preview(binary: shown, arguments: jsonLinesArguments(for: file)))
            steps.append("write the invisible text layer")

            // The compression step is two more binaries, found the same awkward
            // way mac-ocr is. Name them, or say plainly that they are missing.
            var note: String?
            if rebuilding, d.bool(forKey: Prefs.useJBIG2), how.canUseJBIG2 {
                if let encoder = JBIG2.encoder, let merger = JBIG2.merger {
                    steps.append("compress each page with \(leaf(encoder)) "
                                 + "and merge with \(leaf(merger))")
                } else {
                    let missing = [JBIG2.encoder == nil ? "jbig2" : nil,
                                   JBIG2.merger == nil ? "qpdf" : nil].compactMap { $0 }
                    note = "JBIG2 compression is on, but \(missing.joined(separator: " and ")) "
                        + "could not be found — that step is skipped and CoreGraphics' Flate "
                        + "is used instead."
                }
            }
            steps[steps.count - 1] += " → [name].ocr.pdf"
            lines += steps.enumerated().map { "\($0.offset + 1). \($0.element)" }
            if let note { lines.append(note) }
        }
        return lines
    }

    /// A shell-quoted preview of the command, for the log and the settings panel.
    static func preview(binary: String, arguments: [String]) -> String {
        ([binary] + arguments).map { arg in
            arg.rangeOfCharacter(from: CharacterSet(charactersIn: " '\"\\$`")) == nil
                ? arg
                : "'" + arg.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        }.joined(separator: " ")
    }

    // MARK: - Running

    struct Result {
        let file: URL
        let outcome: Outcome
        /// stderr from mac-ocr — where it reports what went wrong.
        let message: String

        /// Cancelling is kept apart from failing: the user asking to stop isn't
        /// an error, and shouldn't be summarised as one.
        enum Outcome { case succeeded, failed, cancelled }

        var succeeded: Bool { outcome == .succeeded }
    }

    /// Runs mac-ocr for one file. Blocking; call from a background queue.
    /// `register` hands back the Process so a cancel can terminate it.
    static func run(
        binary: String,
        file: URL,
        outputFolder: URL?,
        explicitOutputFile: URL? = nil,
        argumentsOverride: [String]? = nil,
        settings: Prefs.Snapshot = .current(),
        wasCancelled: () -> Bool = { false },
        register: (Process) -> Void
    ) -> Result {
        let args = argumentsOverride
            ?? arguments(for: file, outputFolder: outputFolder,
                         explicitOutputFile: explicitOutputFile,
                         settings: settings)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args

        let errPipe = Pipe()
        p.standardError = errPipe
        // -o writes the file, so stdout is empty in normal use; discard it so a
        // chatty run can never fill the pipe buffer and deadlock the process.
        p.standardOutput = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice

        do {
            try p.run()
        } catch {
            return Result(file: file, outcome: .failed,
                          message: "Could not launch mac-ocr: \(error.localizedDescription)")
        }
        register(p)

        // Bounded and cancellable, exactly as runStreaming is (R2). This path —
        // Extract Text, the default mode — kept an unbounded
        // `readDataToEndOfFile()` followed by an unbounded `waitUntilExit()` with
        // no cancellation check, so a child that ignored SIGTERM, or a descendant
        // holding stderr, wedged the worker for good with Cancel already spent.
        //
        // Read before waiting either way: waiting first would deadlock on a full
        // pipe.
        let errFD = errPipe.fileHandleForReading.fileDescriptor
        _ = fcntl(errFD, F_SETFL, fcntl(errFD, F_GETFL, 0) | O_NONBLOCK)
        var errData = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        var cancelledMidRead = false
        while true {
            if wasCancelled() { cancelledMidRead = true; break }
            var descriptor = pollfd(fd: errFD, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 200)
            if ready < 0 { if errno == EINTR { continue }; break }
            if ready == 0 { continue }
            let n = buffer.withUnsafeMutableBytes { read(errFD, $0.baseAddress, $0.count) }
            if n == 0 { break }
            if n < 0 { if errno == EAGAIN || errno == EINTR { continue }; break }
            errData.append(contentsOf: buffer[0..<n])
        }

        let stderr = String(decoding: errData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cancelledMidRead {
            stop(p)
            return Result(file: file, outcome: .cancelled, message: "Cancelled.")
        }

        var exited = wait(for: p, upTo: 5)
        if !exited { stop(p); exited = !p.isRunning }
        // Not readable until it has actually exited — see runStreaming.
        guard exited else {
            return Result(file: file, outcome: .failed,
                          message: stderr.isEmpty
                              ? "mac-ocr stopped responding and could not be terminated."
                              : stderr)
        }

        if p.terminationStatus == 0 {
            return Result(file: file, outcome: .succeeded, message: stderr)
        }
        // terminate() sends SIGTERM, which surfaces here as an uncaught signal —
        // but so does a crash. Only call it cancelled if we actually cancelled;
        // otherwise a batch where every file crashed read as if the user stopped it.
        if p.terminationReason == .uncaughtSignal, wasCancelled() {
            return Result(file: file, outcome: .cancelled, message: "Cancelled.")
        }
        return Result(file: file, outcome: .failed,
                      message: stderr.isEmpty
                          ? "mac-ocr exited with code \(p.terminationStatus)."
                          : stderr)
    }

    // MARK: - Helpers

    /// Splits a comma / whitespace / newline separated field into clean items.
    static func splitList(_ raw: String?) -> [String] {
        (raw ?? "")
            .components(separatedBy: CharacterSet(charactersIn: ",\n\r\t "))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 0.5 not 0.500000 — mac-ocr parses either, but the log stays readable.
    private static func trimNumber(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        min(max(v, lo), hi)
    }
}
