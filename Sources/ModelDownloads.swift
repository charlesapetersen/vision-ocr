import Foundation
import CryptoKit

/// The accurate mode's downloads (C57, `ocr-integrate-settings` is-downloads): the shared runtime,
/// the layout model and each model reader, fetched the first time a reader that needs them is
/// chosen, never while the mode is off. Every file is checked against the size and SHA-256 the
/// app carries before anything is installed, and each item is staged beside its destination and
/// moved into place whole, so a cancel or a bad file leaves nothing half-installed for
/// `Prefs.AccurateReader.missing` to mistake for a download.
///
/// The models come from Hugging Face at the revision `ocr-compare-run` measured. The runtime
/// (`ops/ocrlab/make-runtime.sh`) and the layout model (`ops/ocrlab/convert-layout.py`) are this
/// project's builds, attached to the repository's `models-1` release; the archives the hashes
/// below were taken from are kept in the autonomous state's `model-files/`.
enum ModelDownloads {
    struct File: Equatable {
        let path: String
        let bytes: Int64
        let sha256: String
    }

    /// How an item arrives. `archive`: one `.tgz` from the release holding `top`, which becomes
    /// `destination` under the model home. `hub`: a model's files at `revision`, laid out as the
    /// Hub's cache (`Models/hub/models--<org>--<name>/snapshots/<revision>`, `refs/main`), which
    /// `read-model.py` opens offline.
    enum Plan: Equatable {
        case archive(File, top: String, destination: String)
        case hub(repo: String, revision: String, files: [File])

        var bytes: Int64 {
            switch self {
            case .archive(let file, _, _): return file.bytes
            case .hub(_, _, let files): return files.reduce(0) { $0 + $1.bytes }
            }
        }

        /// Where it is installed, relative to the model home.
        var destination: String {
            switch self {
            case .archive(_, _, let destination): return destination
            case .hub(let repo, _, _): return "Models/hub/models--" + repo.replacingOccurrences(of: "/", with: "--")
            }
        }
    }

    enum Item: String, CaseIterable {
        case runtime, layout, falcon, paddle

        var name: String {
            switch self {
            case .runtime: return "the shared runtime"
            case .layout: return "the layout model"
            case .falcon: return Prefs.AccurateReader.falcon.name
            case .paddle: return Prefs.AccurateReader.paddle.name
            }
        }

        var plan: Plan {
            switch self {
            case .runtime:
                return .archive(File(path: "runtime.tgz", bytes: 134_201_556,
                                     sha256: "e46afcb7150d801e62d49a6aceb4b8616d0c8433343c807009e52e6b22effac5"),
                                top: "runtime", destination: "Runtime")
            case .layout:
                return .archive(File(path: "doclayout-yolo.tgz", bytes: 64_836_242,
                                     sha256: "61e8114f535d2961f828d80a1d9afdd9c51f253a5540bda09bd65b1363e409e6"),
                                top: "doclayout-yolo.mlmodelc", destination: "Models/doclayout-yolo.mlmodelc")
            // Only what loading reads: not the model cards, their images or their benchmark files.
            case .falcon:
                return .hub(repo: "tiiuae/Falcon-OCR", revision: "fe757d59ecd79d4d68760162306a70a015761ad9", files: [
                    File(path: "attention.py", bytes: 4566, sha256: "9dcd7f868901e50ae5b541ff44c9893215c9fb9684127799c841f3e1456dc524"),
                    File(path: "config.json", bytes: 747, sha256: "ba4aec622ec2954e22c76d7ced80817c34d91e26970884e484c29a872e794adf"),
                    File(path: "configuration_falcon_ocr.py", bytes: 2223, sha256: "3caccafb5bdf7fb943c181031a95036e4ef98331dbcf2460c6ccd94068f41bd4"),
                    File(path: "model.safetensors", bytes: 1_079_789_464, sha256: "3df91e403dc48794bf1c48511e75c3508b1cc52df599dcc15f1080d46101ab16"),
                    File(path: "model_args.json", bytes: 823, sha256: "649dc7d6cc7b56c56622642d6365930fa3d0fc8045df1ae9ba4b573c74a69a1d"),
                    File(path: "modeling_falcon_ocr.py", bytes: 32874, sha256: "9d6bb7476c8d60d123b4aa6935c7a9f0a4005e3c2036bc44251069fa27a7c14c"),
                    File(path: "processing_falcon_ocr.py", bytes: 15537, sha256: "a6297617311dc9a02b1dcc17d40b9545e1bc348e6dffa7758b32f1ba7be44599"),
                    File(path: "rope.py", bytes: 4689, sha256: "8446ee8047a7da4291a9b4b91bbee2e7ca988dc05ab94ce65d9dc12868c345c7"),
                    File(path: "special_tokens_map.json", bytes: 9357, sha256: "edd96763ef5d2e6c583ddd4859f3aa23661a9ace343e3709d96cea05d555be51"),
                    File(path: "tokenizer.json", bytes: 5_063_163, sha256: "4a9892af2b1ef021a421f140c7e3c064f5b255f7d75ba18c883996d86e1cf15a"),
                    File(path: "tokenizer_config.json", bytes: 4352, sha256: "074e03d3fd56d190dac763ec5dfe75a728e15783fc5d919d4b5cbe72bcd24d26"),
                ])
            case .paddle:
                return .hub(repo: "mlx-community/PaddleOCR-VL-1.6-4bit", revision: "c8987b277bdd8aaec8bd265d154f391bd03ad165", files: [
                    File(path: "added_tokens.json", bytes: 25381, sha256: "f59f889088e0fe21c523e7cf121bb6dca3b0bb148cb7159fbb4572c74dfc5644"),
                    File(path: "chat_template.jinja", bytes: 1474, sha256: "2f27812dab7f333e471884e0c803d807f11953d5453140dfb1aaba234f872bc8"),
                    File(path: "config.json", bytes: 2676, sha256: "f3201c9d3ffb55873a844d10ca2c616c3e1dc4939ee0631c697905a9d245f504"),
                    File(path: "configuration_paddleocr_vl.py", bytes: 8104, sha256: "753dd93654c3a9c8c85a3eaee1e3092dd12591b0f2dce0305e1abfb7a41ff160"),
                    File(path: "generation_config.json", bytes: 133, sha256: "a6701d78ab3b4d972307cdec3b69d4c13f46e0d5140514f50ab7d84259324b94"),
                    File(path: "image_processing_paddleocr_vl.py", bytes: 25032, sha256: "a4fa521b9cb16e207f94b7f2d16427771776dfc634420d319fc4916ee58049ec"),
                    File(path: "model.safetensors", bytes: 703_562_705, sha256: "5d1ce8b52bf14c528a4b860ef8ed74a8136aecf21d98ed514c09522a19cdf559"),
                    File(path: "model.safetensors.index.json", bytes: 69879, sha256: "7922fd298904bb4271d80f51bc7bb5d4cc7d3a038921cdbf5080bfb6c0556271"),
                    File(path: "modeling_paddleocr_vl.py", bytes: 103_889, sha256: "c5013dff57ca8b87dc1de64d0fd839a44313de09d230a4fb2d08289d2cad5111"),
                    File(path: "preprocessor_config.json", bytes: 641, sha256: "111872ab1e8bb7fd040ac5087bfced7ab8f011f02139b088cba294964c3b1d0e"),
                    File(path: "processing_paddleocr_vl.py", bytes: 12253, sha256: "e29cb1e5f275f2bd3ce051bd5c9983a33894e693b2823a0e13d4c07c8c4f9e13"),
                    File(path: "processor_config.json", bytes: 609, sha256: "37e0b148483ccbd862ec95e5a4ccd9d5a6a8e79e8b49db95eeefcb94fcb436e2"),
                    File(path: "special_tokens_map.json", bytes: 1151, sha256: "d3a125c03103deb2acaf7730791bdbbf196f620e5a2213b664511ff9b4b25bab"),
                    File(path: "tokenizer.json", bytes: 11_188_983, sha256: "f64dee5b500fd0737498420a95cfa25927990ecbe37c0c112a6c8fcea22bc7f9"),
                    File(path: "tokenizer_config.json", bytes: 782, sha256: "ec27a60e0ac749b3820964af0511115d8e5a9b63ce22ff933ef6a09c36aa50fe"),
                ])
            }
        }

        /// The download in decimal MB, as the settings state it.
        var downloadMB: Int { Int((Double(plan.bytes) / 1_000_000).rounded()) }

        /// Whether it is in place: the runtime's interpreter runs, a model holds the pinned
        /// revision, the layout model's directory exists. A model cached at another revision is
        /// fetched again and replaces it: the pinned one is what the table measured.
        func installed(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
            let url = ModelRuntime.home(environment).appendingPathComponent(plan.destination)
            switch plan {
            case .hub(_, let revision, _):
                return FileManager.default.fileExists(atPath: url.appendingPathComponent("snapshots/\(revision)").path)
            case .archive:
                return self == .runtime ? Runner.isRunnable(url.appendingPathComponent("bin/python3").path)
                    : FileManager.default.fileExists(atPath: url.path)
            }
        }
    }

    /// Where the files come from. `VISIONOCR_MODEL_SOURCE`, a directory or URL, stands in for both
    /// for the suite and for checking a release before it is published: archives at
    /// `<source>/<file>`, the models' files at `<source>/<repo>/resolve/<revision>/<file>`.
    struct Source: Equatable {
        var release: URL
        var hub: URL

        static let published = Source(
            release: URL(string: "https://github.com/charlesapetersen/vision-ocr/releases/download/models-1/")!,
            hub: URL(string: "https://huggingface.co/")!)

        static func current(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Source {
            guard let raw = environment["VISIONOCR_MODEL_SOURCE"], !raw.isEmpty else { return published }
            let url = raw.contains("://") ? URL(string: raw)! : URL(fileURLWithPath: raw, isDirectory: true)
            return Source(release: url, hub: url)
        }

        func url(_ plan: Plan, _ file: File) -> URL {
            switch plan {
            case .archive: return release.appendingPathComponent(file.path)
            case .hub(let repo, let revision, _):
                return hub.appendingPathComponent("\(repo)/resolve/\(revision)/\(file.path)")
            }
        }
    }

    enum Failure: LocalizedError, Equatable {
        case mismatch
        case unpack
        case space(needMB: Int, freeMB: Int)
        case fetch(String)

        var errorDescription: String? {
            switch self {
            case .mismatch: return "a file did not match the one this version of the app expects, so nothing was installed"
            case .unpack: return "the archive could not be unpacked, so nothing was installed"
            case .space(let need, let free): return "it needs about \(need) MB of free disk space and \(free) MB is free"
            case .fetch(let why): return why
            }
        }
    }

    /// What the reader chosen for `kind` still needs, in the order they are fetched; nothing at
    /// all while the mode is off.
    static func needed(accurateMode: Bool, _ reader: Prefs.AccurateReader, _ kind: Recogniser.PageKind,
                       environment: [String: String] = ProcessInfo.processInfo.environment) -> [Item] {
        accurateMode ? reader.needs(kind).filter { !$0.installed(environment) } : []
    }

    /// Removes staging an earlier download left when the app quit or crashed under it. Run before
    /// the first download of a launch, when none can be in use.
    static func sweep(home: URL) {
        let fm = FileManager.default
        for dir in ["", "Models", "Models/hub"] {
            let parent = home.appendingPathComponent(dir)
            for name in (try? fm.contentsOfDirectory(atPath: parent.path)) ?? [] where name.hasPrefix(".download-") {
                try? fm.removeItem(at: parent.appendingPathComponent(name))
            }
        }
    }

    /// The SHA-256 of `url`'s contents, read a megabyte at a time.
    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Downloads, checks and installs `plan` under `home`. `progress` is called with the bytes
    /// fetched so far. A failure, or cancelling the task, leaves `home` as it was.
    static func install(_ plan: Plan, home: URL, source: Source,
                        progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws {
        let fm = FileManager.default
        let destination = home.appendingPathComponent(plan.destination)
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        // The archive, the unpacked copy and the room the installed copy takes beside it.
        let need = Int(plan.bytes / 1_000_000) * (plan.isArchive ? 5 : 1) + 50
        if let free = try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage, Int(free / 1_000_000) < need {
            throw Failure.space(needMB: need, freeMB: Int(free / 1_000_000))
        }
        // Staged on the destination's volume, so the final move is a rename.
        let staging = parent.appendingPathComponent(".download-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let built: URL
        switch plan {
        case .archive(let file, let top, _):
            let archive = staging.appendingPathComponent(file.path)
            try await fetch(source.url(plan, file), to: archive, expecting: file, done: 0, progress: progress)
            let unpacked = staging.appendingPathComponent("unpacked")
            try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
            let tar = Process()
            tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            tar.arguments = ["-xzf", archive.path, "-C", unpacked.path]
            tar.standardOutput = FileHandle.nullDevice
            tar.standardError = FileHandle.nullDevice
            try tar.run()
            tar.waitUntilExit()
            try? fm.removeItem(at: archive)
            built = unpacked.appendingPathComponent(top)
            // Only the one directory the release promised, so an archive cannot write elsewhere.
            let entries = (try? fm.contentsOfDirectory(atPath: unpacked.path)) ?? []
            guard tar.terminationStatus == 0, entries == [top], fm.fileExists(atPath: built.path) else {
                throw Failure.unpack
            }
        case .hub(_, let revision, let files):
            built = staging.appendingPathComponent("model")
            let snapshot = built.appendingPathComponent("snapshots/\(revision)")
            var done: Int64 = 0
            for file in files {
                let target = snapshot.appendingPathComponent(file.path)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await fetch(source.url(plan, file), to: target, expecting: file, done: done, progress: progress)
                done += file.bytes
            }
            let refs = built.appendingPathComponent("refs")
            try fm.createDirectory(at: refs, withIntermediateDirectories: true)
            try Data(revision.utf8).write(to: refs.appendingPathComponent("main"))
        }
        try Task.checkCancellation()
        // A broken copy left from before (a runtime that no longer runs) gives way to this one.
        if (try? fm.attributesOfItem(atPath: destination.path)) != nil {
            try fm.moveItem(at: destination, to: staging.appendingPathComponent("replaced"))
        }
        try fm.moveItem(at: built, to: destination)
    }

    /// One file to `target`, checked against `file`'s size and hash.
    private static func fetch(_ url: URL, to target: URL, expecting file: File, done: Int64,
                              progress: @escaping @Sendable (Int64) -> Void) async throws {
        try Task.checkCancellation()
        try await Fetcher(url: url, target: target) { progress(done + $0) }.run()
        let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value
        guard size == file.bytes, try sha256(target) == file.sha256 else {
            try? FileManager.default.removeItem(at: target)
            throw Failure.mismatch
        }
        progress(done + file.bytes)
    }

    /// A download task with progress, ended by cancelling the Swift task that awaits it.
    private final class Fetcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let url: URL, target: URL
        let progress: (Int64) -> Void
        private var continuation: CheckedContinuation<Void, Error>?
        /// How the task ended, kept when it ends before `run` has stored the continuation: a task
        /// cancelled before it starts reports at once, and a resume after that reports nothing.
        private var ended: Result<Void, Error>?
        private var moved: Error?
        private let lock = NSLock()

        init(url: URL, target: URL, progress: @escaping (Int64) -> Void) {
            self.url = url; self.target = target; self.progress = progress
        }

        func run() async throws {
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            let task = session.downloadTask(with: url)
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    lock.lock()
                    if let ended {
                        lock.unlock()
                        c.resume(with: ended)
                        return
                    }
                    continuation = c
                    lock.unlock()
                    task.resume()
                }
            } onCancel: { task.cancel() }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            progress(totalBytesWritten)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // The file is gone once this returns, so it is moved here.
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                moved = Failure.fetch("the server answered \(http.statusCode) for \(url.lastPathComponent)")
                return
            }
            do {
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: location, to: target)
            } catch { moved = error }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let result: Result<Void, Error>
            if let error = error as? URLError, error.code == .cancelled {
                result = .failure(CancellationError())
            } else if let error {
                result = .failure(Failure.fetch(error.localizedDescription))
            } else if let moved {
                result = .failure(moved)
            } else {
                result = .success(())
            }
            lock.lock()
            let c = continuation
            continuation = nil
            if c == nil { ended = result }
            lock.unlock()
            c?.resume(with: result)
        }
    }
}

extension ModelDownloads.Plan {
    var isArchive: Bool { if case .archive = self { return true } else { return false } }
}

extension Prefs.AccurateReader {
    /// What this reader needs to read `kind`, in the order a user would fetch them.
    func needs(_ kind: Recogniser.PageKind) -> [ModelDownloads.Item] {
        var out: [ModelDownloads.Item] = []
        switch self {
        case .falcon: out += [.runtime, .falcon]
        case .paddle: out += [.runtime, .paddle]
        case .vision, .visionRegions: break
        }
        if route(kind).arrangement == .regions { out.append(.layout) }
        return out
    }

    /// The names of what this reader still needs downloaded before it can read `kind`; empty
    /// when it is ready. A run that lacks one fails the file, saying which
    /// (`ModelRuntime.command`, `LayoutModel.model`).
    func missing(_ kind: Recogniser.PageKind,
                 environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        needs(kind).filter { !$0.installed(environment) }.map(\.name)
    }
}
