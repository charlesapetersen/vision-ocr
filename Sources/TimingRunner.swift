import Foundation
import Combine

/// Speed checks outlive Settings. Automatic requests name one newly downloaded reader;
/// manual requests retain the button's all-ready-readers behavior. Nothing runs beside a batch.
@MainActor
final class TimingRunner: ObservableObject {
    static let shared = TimingRunner()
    typealias Execute = ([TimingRun.Leg], Double, RunControl, @escaping (String) -> Void) throws -> Prefs.AccurateTiming

    @Published private(set) var running = false
    @Published private(set) var status: String?
    private enum Request {
        case automatic(Prefs.AccurateReader)
        case manual([TimingRun.Leg], Double)
    }
    private let execute: Execute
    private var requests: [Request] = []
    private var activeReader: Prefs.AccurateReader?
    private var task: Task<Void, Never>?
    private var control: RunControl?

    init(execute: @escaping Execute = { try TimingRun.run($0, memoryGB: $1, control: $2, progress: $3) }) {
        self.execute = execute
    }

    /// Called once a requested reader's whole download is in place. Pending/active requests
    /// are coalesced, so shared download parts or a second open panel cannot start duplicates.
    func afterDownload(_ reader: Prefs.AccurateReader) {
        guard reader != .vision, reader.isTimed, activeReader != reader,
              !requests.contains(where: { if case .automatic(let pending) = $0 { return pending == reader }; return false }),
              Prefs.store.bool(forKey: Prefs.accurateMode),
              Prefs.AccurateReader.enabled(Prefs.store).contains(reader), reader.toFetch().isEmpty else { return }
        requests.append(.automatic(reader))
        begin()
    }

    func start(_ legs: [TimingRun.Leg], memoryGB: Double) {
        guard !running, !legs.isEmpty else { return }
        guard !RunControl.isAnyCommitted else {
            status = "Files are being read; measure when they have finished."
            return
        }
        requests.append(.manual(legs, memoryGB))
        begin()
    }

    private func begin() {
        guard task == nil, !requests.isEmpty else { return }
        running = true
        task = Task { await drain() }
    }

    private func drain() async {
        defer {
            control = nil
            activeReader = nil
            task = nil
            running = false
            // A download may finish while a stopped check is still unwinding.
            if !requests.isEmpty { begin() }
        }
        while !requests.isEmpty, !Task.isCancelled {
            let request = requests.removeFirst()
            if case .automatic(let reader) = request { activeReader = reader }
            else { activeReader = nil }
            while RunControl.isAnyCommitted {
                status = "Waiting for your files to finish before checking speed…"
                do { try await Task.sleep(nanoseconds: 250_000_000) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            let legs: [TimingRun.Leg]
            let memory: Double
            switch request {
            case .manual(let chosen, let gb):
                legs = chosen
                memory = gb
            case .automatic(let reader):
                // Re-check at execution time: settings can change while waiting for a batch.
                guard Prefs.store.bool(forKey: Prefs.accurateMode),
                      Prefs.AccurateReader.enabled(Prefs.store).contains(reader) else {
                    status = "Speed check skipped because the reader was turned off."
                    continue
                }
                memory = Prefs.store.double(forKey: Prefs.modelMemoryGB)
                // Vision is timed beside it on the same kinds of page: the table's "× Vision"
                // compares a reader with Vision timed in the same run, not with our Mac's Vision.
                let all = TimingRun.legs(memoryGB: memory)
                let kinds = Set(all.filter { $0.reader == reader }.map(\.kind))
                legs = all.filter { $0.reader == reader || ($0.reader == .vision && kinds.contains($0.kind)) }
                guard !kinds.isEmpty else {
                    status = "Could not check \(reader.name): it needs a complete download and enough memory."
                    continue
                }
            }
            let control = RunControl()
            self.control = control
            status = "Checking speed on sample pages…"
            let execute = self.execute
            let result: Result<Prefs.AccurateTiming, Error> = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result { try execute(legs, memory, control) { text in
                        Task { @MainActor in
                            if self.control === control, !control.isCancelled { self.status = text }
                        }
                    } }
                    control.finished()
                    continuation.resume(returning: result)
                }
            }
            self.control = nil
            guard !Task.isCancelled, !control.isCancelled else { return }
            switch result {
            case .success(var timing):
                // One reader's new result must not erase the others' measurements; the button's
                // run times every ready reader and replaces them, as it always has.
                if activeReader != nil,
                   let previous = Prefs.AccurateTiming(Prefs.store.data(forKey: Prefs.accurateTiming)) {
                    timing.seconds = previous.seconds.merging(timing.seconds) { _, new in new }
                }
                Prefs.store.set(timing.data, forKey: Prefs.accurateTiming)
                status = activeReader.map { "Speed checked for \($0.name)." } ?? "Speed checked on this Mac."
            case .failure(let error):
                status = "Previous speed estimates kept. " + error.localizedDescription
            }
        }
    }

    /// Stop works while waiting as well as during reading, without touching document batches.
    func stop() {
        guard running || !requests.isEmpty else { return }
        requests = []
        task?.cancel()
        control?.cancel()
        status = "Speed check stopped. Previous estimates kept."
    }

    nonisolated static func plan(_ legs: [TimingRun.Leg]) -> String {
        let models = legs.filter { $0.reader != .vision }
        let minutes = max(1, Int((TimingRun.estimate(legs) / 60).rounded(.up)))
        return models.isEmpty
            ? "Checks the built-in reader only; no extra reader is ready. About \(minutes) min."
            : "Checks the built-in reader and \(models.count) extra reader\(models.count == 1 ? "" : "s"). About \(minutes) min on our test Mac."
    }

    nonisolated static func speedNote(_ timing: Prefs.AccurateTiming?) -> String {
        guard let timing, !timing.seconds.isEmpty else { return "Times are from our test Mac." }
        let date = DateFormatter.localizedString(from: timing.measured, dateStyle: .medium, timeStyle: .none)
        return "Times are estimated for this Mac; last speed check: \(date). A time marked (test Mac) "
            + "has not been checked here."
    }
}
