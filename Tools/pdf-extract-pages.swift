import PDFKit
import Foundation

// Pull pages into a small fixture.
//
//     pdf-extract-pages <src.pdf> <dest.pdf> <page1based>…
//
// ⛔ argv[2] IS WRITTEN, AND THE CORPUS IS NOT COMMITTED. Until 2026-08-20 this
// file was thirteen lines with no guard at all, so `pdf-extract-pages
// testdocs/*/*.pdf` WOULD HAVE opened corpus document 1, overwritten corpus
// document 2 with an EMPTY pdf, silently dropped the remaining 231 paths (every one
// of them failing `Int($0)` inside a loop whose only response was `continue`), and
// printed `extracted 0 pages` on exit 0. Nobody ran it — this was latent, and the
// figures in T19 are from scratch fixtures, not from the corpus. `testdocs/` is
// 1.2 GB of third-party PDFs that is not committed and cannot be rebuilt without
// the owner's Zotero library. Of the eight tools here that read argv[2] as
// something other than a path, this and `make-observations` are the two that WRITE
// it, which is why they were guarded first (BUGS.md T19; the owner's decision,
// 2026-08-19).
//
// Refused, not dropped — `score-rebuild-dpi`'s argument in its own argv guard:
// "the row that never appears is indistinguishable from a resolution that was never
// asked for", invariant 1's shape in an instrument. Here the argument that used to
// be dropped is a path and the row that never appeared is a page.
//
// Every glob shape is now refused, and by construction rather than by heuristic:
// two paths land in the usage guard (no page arguments), three or more land in the
// page parse (a path is not an `Int`), and any shape whose second path already
// exists lands in the overwrite guard before either. `OVERWRITE=1` is the way to
// mean it — the destination is the same file type as the source here, so existence
// is the only signal this tool has, and a re-run onto its own output is the one
// legitimate case it cannot tell from the accident.
//
// SEVEN refusals on argv — usage, destination-is-source, destination-is-directory,
// destination-exists, not-a-page, page-twice, page-out-of-range — and each has its
// own row in `Tools/fault-inject.sh argv_writers`, plus one refusal on a staging
// collision. The count is not decoration: the first version of that case had four
// rows landing in two guards, so deleting the overwrite guard left every check
// green, and `pdf-extract-pages A.pdf B.pdf 3` — the accident that is not a glob —
// reached none of them. Two rounds of adversarial review on this diff found that,
// and then found that the staged write below had created a NEW way to destroy a
// directory. If you add a refusal here, add its row there and watch the row fail
// without it.

let args = Array(CommandLine.arguments.dropFirst())

func refuse(_ why: String) -> Never {
    FileHandle.standardError.write(Data("REFUSED: \(why)\n".utf8))
    exit(2)
}

guard args.count >= 3 else {
    FileHandle.standardError.write(Data("""
        usage: pdf-extract-pages <src.pdf> <dest.pdf> <page1based>…

        argv[2] is WRITTEN. Every argument after it is a 1-based page number, so a
        shell glob lands corpus paths in the destination and in the page list; that
        is refused rather than written. At least one page is required — a run that
        selects no pages used to write an empty PDF over argv[2] and report success.
        Set OVERWRITE=1 to permit an existing destination.

        """.utf8))
    exit(2)
}

let src = URL(fileURLWithPath: args[0])
let dest = URL(fileURLWithPath: args[1])

// Before the escape hatch, not after it: `OVERWRITE=1` means "yes, replace my own
// fixture", never "yes, write the file you are reading". `outDoc.write` would run
// with `doc` still holding that URL open, and the source is the one file here that
// cannot be regenerated from the other.
if dest.resolvingSymlinksInPath().standardizedFileURL
    == src.resolvingSymlinksInPath().standardizedFileURL {
    refuse("the destination is the source ('\(src.path)'). OVERWRITE=1 does not cover that.")
}

// A DIRECTORY, refused ahead of the escape hatch too. `OVERWRITE=1 pdf-extract-pages
// src.pdf fixtures/ 3` — the filename forgotten, with the override the documents
// recommend — would otherwise reach `replaceItemAt`, which swaps a file in for the
// directory and takes its contents with it. The review of this diff called that a NEW
// hazard the staged write had created, reasoning that `write(to: <directory>)` simply
// failed before. ⛔ MEASURED, and it is the older hazard: the thirteen-line original,
// given a directory holding a PDF, left `the directory is gone` — PDFKit replaced it,
// on exit 0, with `extracted 1 pages` on stdout. Suspect the reasoning; the row is in
// `fault-inject.sh` either way.
var isDirectory: ObjCBool = false
if FileManager.default.fileExists(atPath: dest.path, isDirectory: &isDirectory),
   isDirectory.boolValue {
    refuse("the destination '\(dest.path)' is a directory. OVERWRITE=1 does not cover that.")
}

// The destructive case first, so the diagnostic names the file that was nearly
// lost rather than the page number that was mistyped.
if FileManager.default.fileExists(atPath: dest.path),
   ProcessInfo.processInfo.environment["OVERWRITE"] != "1" {
    let what = PDFDocument(url: dest).map { "a readable PDF of \($0.pageCount) page(s)" }
        ?? "an existing file"
    refuse("""
        the destination '\(dest.path)' is \(what), and argv[2] is written, not read.
                 A shell glob puts a second corpus document here. If you meant it:  OVERWRITE=1 \
        pdf-extract-pages …
        """)
}

let pages: [Int] = args.dropFirst(2).map {
    guard let page = Int($0), page >= 1 else {
        refuse("'\($0)' is not a 1-based page number. Everything after the destination is a page.")
    }
    return page
}
// Named rather than deduplicated. Whatever `PDFDocument.insert` does with a page it
// has already reparented — and this is reasoned, not measured — the read-back below
// would blame the wrong thing if the count came back short. `… 1 1` is a typo either
// way; say which one.
guard Set(pages).count == pages.count else {
    refuse("page \(pages.first { p in pages.filter { $0 == p }.count > 1 } ?? 0) is asked for twice.")
}

guard let doc = PDFDocument(url: src) else {
    FileHandle.standardError.write(Data("pdf-extract-pages: cannot open \(src.path)\n".utf8))
    exit(1)
}

let outDoc = PDFDocument()
for page in pages {
    // A page outside the document used to `continue` too, so `… 4 6 7` over a
    // five-page source wrote a one-page fixture and said `extracted 1 pages`.
    guard let extracted = doc.page(at: page - 1) else {
        refuse("page \(page) is outside \(src.lastPathComponent), which has \(doc.pageCount) page(s).")
    }
    outDoc.insert(extracted, at: outDoc.pageCount)
}

// Invariant 2, in a tool: build into scratch and publish only on success. The write's
// own answer, and then the file's — `write(to:)` is discardable and was discarded, so
// a full disk printed the page count of a document that had never reached the disk.
// Staged because the two new things in this file fight otherwise: verifying the
// read-back means a *failed* verification would leave a bad file at the destination,
// and the overwrite guard would then refuse the retry. Nothing lands at `dest` unless
// it read back correctly.
func die(_ what: String, staging: URL?) -> Never {
    if let staging { try? FileManager.default.removeItem(at: staging) }
    FileHandle.standardError.write(Data("pdf-extract-pages: \(what)\n".utf8))
    exit(1)
}
// Named with this process's pid, and REFUSED rather than removed if it is somehow
// there. The first version of this block did `try? removeItem(at: staging)` on a
// fixed name — a silent recursive delete of a path the user never typed, in the tool
// that had just learned to refuse an existing destination, and a collision between
// two concurrent runs onto the same destination.
let staging = dest.appendingPathExtension("visionocr-staging-\(getpid())")
guard !FileManager.default.fileExists(atPath: staging.path) else {
    refuse("the staging path '\(staging.path)' already exists. Remove it; nothing here deletes it.")
}
guard outDoc.write(to: staging) else { die("writing \(staging.path) failed", staging: staging) }
guard let written = PDFDocument(url: staging), written.pageCount == pages.count else {
    die("\(staging.path) does not read back as \(pages.count) page(s) — \(dest.path) is untouched",
        staging: staging)
}
// `replaceItemAt` may hand back a URL that is not the one asked for, so the published
// file is whatever it says it is — and then that file is re-opened. The comment above
// promises "the write's own answer, and then the file's"; the publish step was the one
// step that did neither, and the success line named a path nothing had re-checked.
var published = dest
do {
    if FileManager.default.fileExists(atPath: dest.path) {
        published = try FileManager.default.replaceItemAt(dest, withItemAt: staging) ?? dest
    } else {
        try FileManager.default.moveItem(at: staging, to: dest)
    }
} catch {
    die("cannot publish \(staging.path) as \(dest.path): \(error)", staging: staging)
}
guard let readBack = PDFDocument(url: published), readBack.pageCount == pages.count else {
    die("\(published.path) does not read back as \(pages.count) page(s) after publishing",
        staging: staging)
}
print("extracted \(readBack.pageCount) page(s) of \(doc.pageCount) to \(published.path)")
