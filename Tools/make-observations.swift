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
// is the same code path the user's own Extract Text ▸ JSON produces. `Tools/README.md`
// gives the reason for compiling these tools against `Sources/` at all, and it is the
// wider one: they exercise the shipped code rather than a reimplementation of it, the
// lesson a hand-written replica taught the hard way. What follows from that here is
// that the SHAPE of this output cannot drift from the product's.
//
// ⛔ **What it does NOT give you is the searchable pipeline's own recognition, and
// this comment claimed otherwise until 2026-08-23** — it said going through
// `extract` meant "the instrument's input and the product's output cannot drift
// apart", full stop. That is true of Extract Text ▸ JSON, whose output this *is*.
// It is false of the searchable PDF: `OCRModel` recognises `Flattener.flatten`'s
// REBUILT BITMAPS whenever `Model.swift:1919`'s `willRebuild` gate says so (the
// bitmaps are handed on at `Model.swift:2005`, and `Recogniser.swift:141` is the arm
// that takes them), while `extract` recognises `Recogniser.render`'s plain render of
// the source page. Same page, different pixels — and on a document with a crop box not
// even the same geometry, since `render` rasterises `Flattener.displayBox` and
// `flatten` `Flattener.fullBox`. Measured on `BUGS.md` C30's document, they return
// different WORDS: page 5's published layer holds a line no fresh observation from
// this tool contains. So a run of this tool is a *second* recognition of a *different*
// image, not a copy of the one the product made. Every C30 instrument is built on
// it, which is why the correction is here and not only in the register.
// ⚠️ The line numbers above are a gate and a hand-off, not the recognition itself;
// `Sources/Recogniser.swift`'s `extract` doc comment carries the same correction
// closer to the code, and was the sibling this one's own sweep missed.
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

        argv[2] is WRITTEN and must be named .json — a shell glob would otherwise
        land a corpus PDF there. See BUGS.md T19.

        """.utf8))
    exit(2)
}

// ⛔ argv[2] IS WRITTEN, AND THE CORPUS IS NOT COMMITTED. `make-observations
// testdocs/*/*.pdf` WOULD recognise corpus document 1 and write its JSON over corpus
// document 2, with document 3 taken as the password and the rest unread; 1.2 GB of
// third-party PDFs that cannot be rebuilt without the owner's Zotero library was one
// glob away. Nobody ran it — latent, and measured on scratch fixtures (T19), where
// the pre-fix tool did exactly that and reported `1 page(s), 14 observations` over
// the PDF it had just destroyed. Of the eight tools here that read argv[2] as
// something other than a path, this and `pdf-extract-pages` are the two that WRITE
// it, which is why they were guarded first (BUGS.md T19; the owner's decision,
// 2026-08-19).
//
// Two guards, and the discriminator is different from `pdf-extract-pages`'s on
// purpose: that tool writes the same file type it reads, so existence is the only
// signal it has and it needs an OVERWRITE escape. This one writes JSON, so the
// destination's *extension* separates the corpus accident from the legitimate re-run
// — and re-running the invariant-3 procedure onto its own obs.json, which is the
// common case, stays free.
//
// What that does NOT do, written out because the first draft of this comment said
// "perfectly": there is no existence guard here, so an unrelated `.json` named as
// argv[2] is still overwritten with no override. The hazard being closed is the
// unrebuildable corpus, and the corpus is `.pdf`; a hand-typed `.json` path is an
// ordinary mistake with an ordinary cost. The two guards land in different places
// and `fault-inject.sh argv_writers` has a row for each — the count guard needs
// FOUR arguments to fire, which the first version of that case never gave it.
func refuse(_ why: String) -> Never {
    FileHandle.standardError.write(Data("REFUSED: \(why)\n".utf8))
    exit(2)
}
guard arguments.count <= 4 else {
    refuse("""
        \(arguments.count - 1) arguments; this tool takes <pdf> <out.json> [password].
                 Extra paths are a shell glob, and argv[2] is written, not read.
        """)
}
guard arguments[2].lowercased().hasSuffix(".json") else {
    refuse("""
        the destination '\(arguments[2])' is not named .json, and argv[2] is written, not read.
                 A shell glob puts a corpus document here.
        """)
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
