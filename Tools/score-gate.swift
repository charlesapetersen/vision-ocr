// The release gate: every document in a corpus through the whole app, end to end.
//
// This is the check the unit suite cannot do. `run_tests.sh` exercises the parts;
// this exercises `OCRModel.start()` over hundreds of real documents at the app's
// own concurrency and reports what came out the other side. Worth running before
// any release that touches `Flattener`, `SearchableWriter` or `JBIG2` — 1.8.0 and
// 1.9.0 both shipped without it, and the run that finally happened found R38.
//
//   mkdir -p /tmp/h && cp Tools/score-gate.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/gate -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   swiftc -O -o /tmp/visionocr-recognise -target "$(uname -m)-apple-macos13.0" \
//     Sources/{Prefs,Runner,Recogniser,SearchableWriter,Flattener,JBIG2}.swift \
//     Helper/main.swift
//   VISIONOCR_HELPER=/tmp/visionocr-recognise /tmp/gate testdocs /tmp/gateout
//
// **Build the helper and point at it, or the timing means nothing** (R40).
// Recognition runs in helper processes because Vision does not parallelise
// across concurrent requests inside one process; without one this harness
// silently falls back to in-process recognition and measures the 187-minute
// configuration while looking exactly like a 75-minute one. It says which it is
// doing in its opening line — read that line before believing the minutes.
//
// **Run it through `start()`, never in a serial loop over `makeSearchablePDF`.**
// A serial version was tried and projected **9.1 hours** for work this does in
// **78 minutes**: `start()` runs files in parallel at `defaultConcurrency`, the
// serial harness ran one at a time. Its timing measured a configuration the app
// never runs, which is worse than no number at all.
//
// Two things it must keep doing, both learned the hard way:
//
//  1. `warnDigitalText` **off**. The digital-text confirmation is a modal, and in
//     a headless run it sits there indefinitely — indistinguishable from a hang.
//  2. Read the **output PDFs** at the end, not just the outcome enum. Page count
//     is not sufficient verification (invariant 1) and neither is a success
//     value; a stream a reader cannot decode still opens as a page.
//
// The baseline it establishes is recorded in HANDOFF.md.

import AppKit
import PDFKit

// The full-corpus gate, driven through OCRModel.start() at the app's own
// concurrency — which is what the 1.7.0 baseline measured.
//
// A serial loop over makeSearchablePDF was tried first and projected 9 hours
// against the baseline's 23 minutes. That is not a regression, it is a
// different instrument: start() runs files in parallel at defaultConcurrency
// and the serial harness ran one at a time. Measuring throughput with the
// concurrency removed would have produced a number worth nothing.
final class Harness: NSObject, NSApplicationDelegate {
    var model: OCRModel!
    var started = Date()
    var total = 0
    var outDir = URL(fileURLWithPath: NSTemporaryDirectory())

    func applicationDidFinishLaunching(_ n: Notification) {
        let root = CommandLine.arguments[1]
        outDir = URL(fileURLWithPath: CommandLine.arguments[2])
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let d = UserDefaults.standard
        Prefs.register()
        // No modal can be allowed to stop a headless run: the digital-text
        // warning is exactly the prompt that would sit there for nine hours.
        d.set(false, forKey: Prefs.warnDigitalText)
        d.set(false, forKey: Prefs.besideOriginal)
        d.set(outDir.path, forKey: Prefs.outputFolder)
        d.set(false, forKey: Prefs.openWhenDone)
        d.set(Prefs.Mode.searchablePDF.rawValue, forKey: Prefs.mode)
        d.set(true, forKey: Prefs.rebuildImages)
        d.set(true, forKey: Prefs.useJBIG2)

        var files: [URL] = []
        if let e = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                                                  includingPropertiesForKeys: nil) {
            for case let u as URL in e where u.pathExtension.lowercased() == "pdf" {
                files.append(u)
            }
        }
        files.sort { $0.path < $1.path }
        total = files.count

        model = OCRModel()
        _ = model.add(files)
        print("documents: \(model.files.count) (found \(total))  concurrency: \(Prefs.defaultConcurrency)")
        // Stated, not assumed, and stated as what this run will actually *do*
        // rather than as what is available. A run without the helper is a
        // different measurement — same correctness, 2.5x the minutes — and the
        // two are indistinguishable from the output otherwise. The first version
        // of this line reported the helper as present and said nothing about
        // whether the batch would reach for it, which on a one-document run is
        // exactly the wrong answer: `helperIsWorthIt` declines below two files.
        let concurrency = max(1, min(d.integer(forKey: Prefs.concurrency), Prefs.maxConcurrency))
        let wanted = Recogniser.helperIsWorthIt(concurrency: concurrency,
                                                files: model.files.count)
        switch (wanted, Recogniser.helperPath()) {
        case (true, .some(let path)): print("recognition: helper processes (\(path))")
        case (true, .none):
            print("recognition: IN-PROCESS — no helper found, expect ~2.5x the time")
        case (false, _):
            print("recognition: in-process — this batch is too small to overlap "
                  + "(\(model.files.count) file(s) at \(concurrency) at a time)")
        }
        fflush(stdout)
        started = Date()
        model.start()

        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] t in
            guard let self else { return }
            MainActor.assumeIsolated {
                let done = self.model.outcomes.count
                let mins = Int(Date().timeIntervalSince(self.started) / 60)
                if !self.model.isRunning && done > 0 {
                    t.invalidate()
                    self.finish(minutes: mins)
                } else {
                    print("  \(done)/\(self.model.files.count)  \(mins) min")
                    fflush(stdout)
                }
            }
        }
    }

    @MainActor func finish(minutes: Int) {
        var ok = 0, failed = 0
        for (_, o) in model.outcomes {
            if case .succeeded = o { ok += 1 } else { failed += 1 }
        }
        // Read the products, not just the tally: page count is not sufficient
        // verification and neither is an outcome enum.
        var chars = 0, colour = 0, outs = 0, bytes = 0
        // Per document as well as in total, written beside the outputs. The
        // 2026-08-13 run came back 23 characters short of the previous one out of
        // 34.2 million — 1 part in 1.5 million, with every direct comparison of
        // the two routes exact — and it could not be localised, because a single
        // total says only that something moved somewhere. A diff of two of these
        // files names the document in one command.
        var perDocument: [(String, Int, Int)] = []
        if let e = FileManager.default.enumerator(at: outDir, includingPropertiesForKeys: nil) {
            for case let u as URL in e where u.pathExtension.lowercased() == "pdf" {
                outs += 1
                let size = (try? Data(contentsOf: u).count) ?? 0
                bytes += size
                let these = PDFDocument(url: u)?.string?.count ?? 0
                chars += these
                perDocument.append((u.lastPathComponent, these, size))
                if let raw = try? Data(contentsOf: u),
                   String(decoding: raw.prefix(4_000_000), as: UTF8.self).contains("/DeviceRGB") {
                    colour += 1
                }
            }
        }
        let breakdown = outDir.appendingPathComponent("per-document.tsv")
        try? Data((["file\tcharacters\tbytes"]
                   + perDocument.sorted { $0.0 < $1.0 }.map { "\($0.0)\t\($0.1)\t\($0.2)" })
                  .joined(separator: "\n").appending("\n").utf8)
            .write(to: breakdown, options: .atomic)
        print("""

        === RESULT ===
          documents    \(model.files.count)
          succeeded    \(ok)
          failed       \(failed)
          outputs      \(outs)
          characters   \(chars)
          colour       \(colour)
          output bytes \(bytes / 1_048_576) MB
          minutes      \(minutes)
        === 1.7.0 baseline: 255 ok, 0 failed, 12.6M chars, 15 colour, 23 min ===
        === note: 232 testdocs, NOT the 255-document library set ===
        === per-document characters and bytes: \(breakdown.path) ===
        """)
        fflush(stdout)
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let h = Harness()
app.delegate = h
app.setActivationPolicy(.accessory)
app.run()
