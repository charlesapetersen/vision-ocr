import Foundation

/// Finds the compression tools, and the process handling they need.
///
/// This file used to exist because recognition shelled out to `mac-ocr`, and
/// most of it was about launching, bounding, streaming and killing that child —
/// the source of C6, R2, R3, R16, R17, R21, R22, U18 and R30. Recognition is
/// now in-process (`Recogniser`), and what is left is what `jbig2` and `qpdf`
/// still need: finding them on a PATH a Finder-launched app does not have,
/// refusing one built for the wrong architecture, and a bounded read that
/// cannot hang the main thread.
enum Runner {

    // MARK: - Finding the tools

    // `searchPaths` used to sit here: three hard-coded `mac-ocr` install
    // prefixes, left behind when that dependency was removed and read by
    // nothing. `locateTool` has its own list of prefixes and always did. Deleted
    // rather than left as scenery — a constant naming a program this app no
    // longer runs is a false lead for whoever greps for it next.

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

    /// The copy of a helper shipped inside the app bundle, if there is one.
    ///
    /// `mac-ocr` is a 2.4 MB universal Mach-O that links nothing but system
    /// frameworks — verified by running it under `env -i` with Homebrew and node
    /// off PATH — so it can simply travel with the app. Before this, using Vision
    /// OCR meant installing Homebrew, then Node, then an npm package, in a
    /// Terminal, before the app would do anything at all. For the audience the
    /// README now addresses that was the whole barrier.
    ///
    /// MIT, Copyright (c) Hiroki Osame; the licence travels in
    /// `Contents/Resources/mac-ocr-LICENSE`.
    ///
    /// Deliberately *below* the Settings override and *above* Homebrew: the
    /// bundled copy is the version this release's corpus figures were measured
    /// against, so it is what the app should use unless someone says otherwise.
    /// Anyone wanting a newer one can point Settings at it.
    static func bundledTool(_ name: String) -> String? {
        guard let dir = Bundle.main.resourceURL else { return nil }
        let path = dir.appendingPathComponent(name).path
        return isRunnable(path) && containsNativeSlice(path) ? path : nil
    }

    /// Whether a Mach-O at this path has code for the architecture we are
    /// running on. True for anything that is not a recognisable Mach-O, since a
    /// shell wrapper is a perfectly good tool and this cannot judge it.
    ///
    /// `isExecutableFile` does not look at architecture: it says yes to an
    /// arm64-only binary on an Intel Mac, which then fails at `exec` with an
    /// error no user can act on. That is not hypothetical here — the bundled
    /// compression tools come from Homebrew, which builds for the machine it is
    /// installed on, so a disk image built on Apple Silicon carries arm64-only
    /// copies of `jbig2` and `qpdf`. On an Intel Mac they must be invisible, so
    /// the search falls through to Homebrew exactly as it did before.
    static func containsNativeSlice(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4096), head.count >= 8 else { return false }

        #if arch(arm64)
        let native: UInt32 = 0x0100_000c        // CPU_TYPE_ARM64
        #else
        let native: UInt32 = 0x0100_0007        // CPU_TYPE_X86_64
        #endif

        func word(_ offset: Int, bigEndian: Bool) -> UInt32? {
            guard offset + 4 <= head.count else { return nil }
            let b = head[head.startIndex + offset ..< head.startIndex + offset + 4]
            let v = b.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }        // big-endian read
            return bigEndian ? v : v.byteSwapped
        }
        guard let magic = word(0, bigEndian: true) else { return false }

        // `magic` was read big-endian, so these are the ON-DISK byte orders.
        // A Mach-O stores its magic in the file's own order: every Mac is
        // little-endian, so 0xFEEDFACF lands on disk as CF FA ED FE and reads
        // back here as 0xCFFAEDFE. Getting this the wrong way round made the
        // check reject the very binary it was running as.
        switch magic {
        case 0xcffa_edfe, 0xcefa_edfe:                     // little-endian file
            return word(4, bigEndian: false) == native
        case 0xfeed_facf, 0xfeed_face:                     // big-endian file
            return word(4, bigEndian: true) == native
        case 0xcafe_babe, 0xcafe_babf:                     // fat; entries are big-endian
            let wide = magic == 0xcafe_babf
            guard let count = word(4, bigEndian: true), count < 64 else { return false }
            let stride = wide ? 32 : 20
            for i in 0..<Int(count) {
                if word(8 + i * stride, bigEndian: true) == native { return true }
            }
            return false
        default:
            // Not a Mach-O — a script, most likely. Nothing to object to.
            return true
        }
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

        var found: String? = bundledTool(name)
        if found == nil {
            for prefix in ["/opt/homebrew/bin/", "/usr/local/bin/", "/opt/local/bin/"] {
                let path = prefix + name
                if isRunnable(path) { found = path; break }
            }
        }
        if found == nil { found = askLoginShell(for: name) }

        cacheLock.lock()
        discovered[name] = found
        cacheLock.unlock()
        return found
    }

    /// Forgets the cache, for when the user installs something mid-session.
    static func forgetToolPaths() {
        cacheLock.lock()
        discovered.removeAll()
        cacheLock.unlock()
    }

    private static let cacheLock = NSLock()
    private static var discovered: [String: String?] = [:]

    /// The **last** line of output, not all of it.
    ///
    /// A9.1. `zsh -lc` sources `.zshenv`, `.zprofile` and `.zlogin` onto the same
    /// stdout before it runs the command, so a single `echo` in a login startup
    /// file — a "Last login" line, a version manager's notice — used to make an
    /// installed tool invisible: the whole output was trimmed and handed to
    /// `isRunnable`, which correctly refused `"Now using node v20…\n/opt/homebrew/bin/jbig2"`.
    ///
    /// The nil is then memoised for the session (`discovered`), so `JBIG2.isAvailable`
    /// goes false, `wantsJBIG2` goes false, and **every page in every batch takes
    /// the Flate route at roughly 3x the size** until the app is relaunched — while
    /// Settings shows its "Not installed" hint, naming a remedy the user has
    /// already applied.
    ///
    /// `command -v` prints its answer after the startup files have had their say,
    /// so the answer is the last line. Still validated by `isRunnable`, so the last
    /// line of pure chatter is refused exactly as the whole blob was.
    ///
    /// Not fixed, and worth knowing: `tcsh` and `csh` have no `-lc` at all, so this
    /// route finds nothing for anyone whose `SHELL` is one of those. They fall back
    /// to the bundled tool and the three standard prefixes, which is every
    /// supported install.
    private static func askLoginShell(for name: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard let out = captureBounded(shell, ["-lc", "command -v \(name)"]) else { return nil }
        let path = out.split(whereSeparator: \.isNewline).last
            .map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !path.isEmpty, isRunnable(path) else { return nil }
        return path
    }

    /// How a `drain` ended. Only `.eof` means the child said everything it had.
    enum DrainOutcome { case eof, stopped, timedOut, failed }

    /// Reads a pipe until EOF, a caller's stop, or a deadline — without ever
    /// blocking past that deadline.
    ///
    /// **The one copy of this loop.** It used to be inlined in
    /// `captureBounded`, which was itself written to replace the third copy of
    /// the same thing; R40's helper wanted a fourth, so it was lifted out
    /// instead. The subtleties it carries are all paid for: the read has to be
    /// inside the bound (U18 — a `readDataToEndOfFile` before a `wait` returns
    /// only when every writer on the pipe closes, so a shell that never exited
    /// never reached the timeout meant to catch it), `EINTR` and `EAGAIN` are
    /// resumptions rather than failures, and the poll is capped at 200 ms so a
    /// stop is noticed promptly however far away the deadline is.
    ///
    /// `deadline` is a closure, not a value, because the two callers want
    /// different clocks from the same loop: `captureBounded` wants a fixed
    /// bound on the whole exchange, and the recognition helper wants a *stall*
    /// bound that moves forward every time a page lands — a 600-page book is
    /// legitimately minutes of work, and a total deadline long enough for it
    /// would not catch a hang at all.
    ///
    /// Sets the descriptor non-blocking itself, so no caller can forget to.
    static func drain(_ fd: Int32,
                      deadline: () -> DispatchTime,
                      shouldStop: () -> Bool = { false },
                      onChunk: (ArraySlice<UInt8>) -> Void) -> DrainOutcome {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK)
        var buffer = [UInt8](repeating: 0, count: 4 * 1024)
        while true {
            if shouldStop() { return .stopped }
            let remaining = secondsUntil(deadline())
            if remaining <= 0 { return .timedOut }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32(min(remaining * 1000, 200)))
            if ready < 0 { if errno == EINTR { continue }; return .failed }
            if ready == 0 { continue }
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n == 0 { return .eof }
            if n < 0 { if errno == EAGAIN || errno == EINTR { continue }; return .failed }
            onChunk(buffer[0..<n])
        }
    }

    /// Runs a short command on the main thread and hands back its stdout, or
    /// nil if it failed, hung or was not exec'able.
    ///
    /// Bounded, because callers run it from the main thread — `locateTool` from
    /// `start()` and from the Settings panel's body. A login shell that blocks
    /// (a slow network mount in a profile, an interactive prompt, a wedged NFS
    /// home) froze the whole app with no way out. Three seconds is far longer
    /// than the ~85 ms these normally take.
    ///
    /// **The bound has to cover the read** (U18). It used to be a
    /// `readDataToEndOfFile()` placed before `wait(for:upTo:)`, and that returns
    /// only when every writer on the pipe closes — so a shell that never exited
    /// never reached the timeout meant to catch it, and neither did a shell that
    /// exited while a background job it started kept stdout open. Same reasoning
    /// as the child's stderr drain below, and R2's read loop.
    ///
    /// It was the third copy of that loop in this file when `languages` wanted a
    /// fourth. One copy, two callers: the alternative is a bound that gets fixed
    /// in one place and left wrong in another, which is the shape of R23, R29
    /// and C20.
    static func captureBounded(_ executable: String, _ arguments: [String],
                               seconds: Double = 3) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        // Read while the child is certainly alive: `stop` cannot recover it once
        // Foundation has reaped the child, and the whole point of calling `stop`
        // here is the case where the child has exited and a grandchild is still
        // holding the pipe (A9.3).
        let group = processGroup(of: p)

        let fd = pipe.fileHandleForReading.fileDescriptor
        var data = Data()
        // A9.6. `drain`'s other caller caps its accumulator explicitly and says
        // why; this one did not, so a child that writes without ever closing the
        // pipe was bounded in *time* and unbounded in *memory*. Measured with
        // `cat /dev/zero` for the window: peak RSS 9 MB -> **1,985 MB**.
        //
        // 1 MB is four orders of magnitude more than any real answer here — the
        // longest legitimate output is one absolute path — and the cap is a stop,
        // not a truncation: whatever is on the other end is not answering the
        // question that was asked, so the answer is discarded either way.
        let byteCap = 1 << 20
        var overflowed = false
        // Monotonic, for the reason `wait(for:upTo:)` gives below its own
        // deadline: a wall clock steps in both directions and both are wrong
        // here. Forward — an NTP correction, or waking from sleep, which moves
        // `Date()` and not `DispatchTime` — abandons a healthy shell mid-probe,
        // and `locateTool` then memoises the absence for the whole session, so
        // every later jbig2 and qpdf lookup returns nil without re-probing.
        // Backward extends the bound that exists to keep the main thread
        // responsive. This function reached for `Date()` while the file it lives
        // in already documented why not (R30).
        let deadline = DispatchTime.now() + seconds
        let outcome = drain(fd, deadline: { deadline },
                            shouldStop: { overflowed }) { chunk in
            if data.count >= byteCap { overflowed = true; return }
            data.append(contentsOf: chunk)
        }
        // No EOF inside the bound means something is still holding the pipe. The
        // answer is not worth waiting for, and `stop` takes the whole group so a
        // backgrounded grandchild goes with it.
        //
        // A9.6: `graceSeconds: 0.5` rather than the default 2. The bound was being
        // applied twice in series plus `stop`'s grace, so the worst case was
        // `2 × seconds + 2` — measured **7.98 s** held on the main thread, and with
        // `forgetToolPaths()` per Settings appear and two tool names, about 16 s of
        // frozen UI. Half a second is ample for a child that has already had SIGTERM
        // and whose answer is being thrown away regardless.
        guard outcome == .eof, !overflowed else {
            stop(p, knownGroup: group, graceSeconds: 0.5)
            return nil
        }
        if !wait(for: p, upTo: seconds) {
            stop(p, knownGroup: group, graceSeconds: 0.5)
            return nil
        }
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func secondsUntil(_ deadline: DispatchTime) -> Double {
        let now = DispatchTime.now()
        guard deadline > now else { return 0 }
        return Double(deadline.uptimeNanoseconds - now.uptimeNanoseconds) / 1_000_000_000
    }

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
    /// `knownGroup` is the process group read **at launch**, for the case the
    /// child has already exited (A9.3).
    ///
    /// `guard process.isRunning else { return }` used to be the whole of this
    /// function's behaviour in that case — and an exited child is exactly the case
    /// `captureBounded`'s own comment describes: "no EOF inside the bound means
    /// something is still holding the pipe", and if it is not the child then the
    /// child has finished and something it started has not. Once Foundation reaps
    /// the child, `getpgid` fails and the group is unrecoverable, so the
    /// grandchild survives with nothing left referring to it. Verified: a
    /// `sleep 40` outlived `stop` entirely, and a manual `kill(-pgid)` would have
    /// collected it. `SettingsView` calls `forgetToolPaths()` on every appear, so
    /// that was **one stranded process per tool name per Settings open**.
    ///
    /// The group therefore has to be captured while the child is alive and handed
    /// back in. PID reuse is the risk that argues against signalling a group we no
    /// longer see: it is bounded here because the only caller passing `knownGroup`
    /// does so within one `captureBounded` window — a few seconds — and because
    /// `processGroup(of:)` only ever returns a group the child was the leader of.
    static func stop(_ process: Process, knownGroup: pid_t? = nil,
                     graceSeconds: Double = 2) {
        guard process.isRunning else {
            // The child is gone; anything it started and left holding the pipe is
            // not. Killing an empty group is a no-op, so this costs nothing when
            // the child really did clean up after itself.
            if let knownGroup { kill(-knownGroup, SIGKILL) }
            return
        }
        let group = knownGroup ?? processGroup(of: process)

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
    static func previewLines(file: URL, outputFolder: URL?) -> [String] {
        let d = UserDefaults.standard
        let mode = Prefs.Mode(rawValue: d.string(forKey: Prefs.mode) ?? "") ?? .searchablePDF
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
            let format = Prefs.TextFormat(rawValue: d.string(forKey: Prefs.textFormat) ?? "")
                ?? .text
            lines.append("1. recognise the text with Vision")
            lines.append("2. write it as \(format.fileExtension) → [name].\(format.fileExtension)")
        case .searchablePDF:
            var steps: [String] = []
            let rebuilding = d.bool(forKey: Prefs.rebuildImages)
            let how = Flattener.Mode(rawValue: d.string(forKey: Prefs.rebuildMode) ?? "") ?? .auto
            if rebuilding {
                steps.append("rebuild pages as \(how.label.lowercased()) images "
                             + "(drops any existing text layer)")
            }
            steps.append("recognise the text with Vision"
                         + (rebuilding ? " from those page images" : ""))
            steps.append("write the invisible text layer")

            // The compression step is two binaries, found the awkward way that
            // mac-ocr used to be. Name them, or say plainly that they are
            // missing — they are now the only external programs this app runs,
            // and the only ones whose absence changes what happens.
            var note: String?
            if rebuilding, d.bool(forKey: Prefs.useJBIG2), how.canUseJBIG2 {
                if let encoder = JBIG2.encoder, let merger = JBIG2.merger {
                    // Layering happens between recognition and compression, and
                    // is worth naming: it is the step the Photo detail setting
                    // controls, and a user who changed that setting should be
                    // able to see where it lands.
                    let detail = Prefs.PhotoDetail(
                        rawValue: d.string(forKey: Prefs.photoDetail) ?? "") ?? .balanced
                    steps.append("store text and pictures separately on pages that "
                                 + "have both (\(detail.label.lowercased()) photo detail)")
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
    // MARK: - Running

    /// How one file ended, and what to say about it.
    ///
    /// Named for a subprocess that no longer exists — recognition is in-process
    /// now — but the type is the pipeline's own per-file outcome and is used by
    /// the model, the row statuses and the run report. Kept where it is rather
    /// than moved for the sake of the name.
    struct Result {
        let file: URL
        let outcome: Outcome
        /// What went wrong, in the words the user is shown.
        let message: String

        /// Cancelling is kept apart from failing: the user asking to stop isn't
        /// an error, and shouldn't be summarised as one.
        enum Outcome { case succeeded, failed, cancelled }

        var succeeded: Bool { outcome == .succeeded }
    }

    /// Runs mac-ocr for one file. Blocking; call from a background queue.
    /// `register` hands back the Process so a cancel can terminate it.
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
