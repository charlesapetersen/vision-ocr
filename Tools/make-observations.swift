import Foundation

// Writes the observation JSON the invariant-3 probes read.
//
//     make-observations <pdf> <out.json> [password]
//
// This exists because CLAUDE.md invariant 3's re-measurement procedure was not
// executable as written: `probe-line-edges` and `probe-text-offset` both take a
// JSON of observations as argv[3], and nothing in `Tools/` produced that shape
// any more. The helper writes one file *per page*, a top-level object keyed
// `index`/`observations`, not the array of pages the probes decode — so the
// documented procedure died silently the day recognition moved into the helper,
// and the next person to follow it had to write this file before they could
// start.
//
// It is a wrapper, not a second measurement. `Recogniser.extract` with
// `textFormat = .json` already emits exactly the array the probes decode —
// `[{page, pageCount, width, height, source, text, observations:[…]}]` — and it
// is the same code path the user's own Extract Text ▸ JSON produces. Going
// through it rather than re-deriving the shape here means the instrument's input
// and the product's output cannot drift apart, which is the reason
// `Tools/README.md` gives for compiling these tools against `Sources/` at all.
//
// The probes only decode `page`, `text` and `boundingBox`; the extra keys are
// ignored by their `Decodable` synthesis. That is deliberate — they read the
// real artefact, not a reduced one.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("""
        usage: make-observations <pdf-or-image> <out.json> [password]

        Writes the observation JSON that probe-line-edges, probe-text-offset and
        probe-line-coverage read as their last argument. See CLAUDE.md invariant 3.

        """.utf8))
    exit(2)
}
let source = URL(fileURLWithPath: arguments[1])
let target = URL(fileURLWithPath: arguments[2])
let password = arguments.count > 3 && !arguments[3].isEmpty ? arguments[3] : nil

Prefs.register(migrate: false)
UserDefaults.standard.set(false, forKey: Prefs.openWhenDone)
var settings = Prefs.Snapshot.current()
settings.textFormat = .json

do {
    try Recogniser.extract(from: source, to: target, settings: settings, password: password)
} catch {
    FileHandle.standardError.write(Data("make-observations: \(error)\n".utf8))
    exit(1)
}

// Refuse rather than hand a probe an empty file to report a clean run over.
// A6.1's whole shape is instruments that measure nothing and say nothing about
// it; a producer that writes `[]` and exits 0 would put that defect one step
// upstream of the probes it was written to repair.
struct Page: Decodable { let page: Int; let observations: [Observation] }
struct Observation: Decodable { let text: String }
guard let data = try? Data(contentsOf: target),
      let pages = try? JSONDecoder().decode([Page].self, from: data) else {
    FileHandle.standardError.write(Data("make-observations: wrote nothing readable\n".utf8))
    exit(1)
}
let total = pages.reduce(0) { $0 + $1.observations.count }
guard total > 0 else {
    FileHandle.standardError.write(Data("""
        make-observations: \(pages.count) page(s), 0 observations — the reference read \
        nothing from this file, so any probe fed this JSON would report a clean run \
        over no measurement.

        """.utf8))
    exit(3)
}
print("\(target.path): \(pages.count) page(s), \(total) observations "
      + "(\(pages.map { "p\($0.page)=\($0.observations.count)" }.joined(separator: " ")))")
