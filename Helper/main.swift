import Foundation
import Vision
import CoreGraphics

/// `visionocr-recognise` — the recognition helper R40 asked for.
///
/// Reads a manifest of page bitmaps, recognises each one, writes the
/// observations as JSON, and says nothing else. It exists because **Vision does
/// not parallelise across concurrent requests inside one process** (1.08x at six
/// threads), so the only way to use more than one core on a batch is more than
/// one process. `Recogniser.helperName` carries the measurements and the reasons
/// this is not a return to the `mac-ocr` dependency.
///
/// Two properties matter more than anything else in this file:
///
///  - **It recognises through `Recogniser.recognise`** — the app's own function,
///    compiled into this binary from the same file. Not a copy of it, not a
///    reimplementation that agrees today. Every character count in the corpus
///    baseline depends on this binary and the app doing identically the same
///    thing, and the only way to guarantee that is for there to be one of it.
///  - **It is never authoritative about failure.** Anything unexpected here is
///    an exit code, and the app responds by recognising the document itself. So
///    the worst a bug in this file can do is cost time; it cannot fail a file
///    that would otherwise have succeeded, and it cannot publish a document
///    with pages missing — the app checks that every page came back.
///
/// ```
/// visionocr-recognise --manifest <file> --out <dir> \
///     --fast 0|1 --language-correction 0|1 --languages <raw> \
///     --custom-words <raw> --min-text-height-on 0|1 \
///     --min-text-height <n> --confidence <n>
/// ```
///
/// The manifest is one image path per line. For line *i* (counted from zero) it
/// writes `<dir>/i.json`, then prints `i` on stdout — in that order, so a page
/// the app has been told about is a page it can read. Progress is *only*
/// progress: the observations never travel over the pipe, because a page that
/// arrives as a stream of lines is a page a garbled line can lose, and that was
/// mac-ocr's shape.

/// Exit codes, so a failed run in a log says what went wrong.
enum Exit: Int32 {
    case badArguments = 2
    case unreadableManifest = 3
    case unreadablePage = 4
    case recognitionFailed = 5
    case cannotWrite = 6
}

func die(_ code: Exit, _ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code.rawValue)
}

/// One page done, written straight to the descriptor.
///
/// No buffering to forget to flush: the app is watching this pipe to move a
/// progress bar and to know the helper is alive, and a page that has been
/// recognised but is sitting in a `stdio` buffer looks exactly like a hang.
func announce(_ index: Int) {
    let bytes = Array("\(index)\n".utf8)
    var offset = 0
    while offset < bytes.count {
        let written = bytes.withUnsafeBytes {
            write(1, $0.baseAddress!.advanced(by: offset), bytes.count - offset)
        }
        if written > 0 { offset += written; continue }
        // EINTR is a resumption. Anything else means the app is no longer
        // listening, which is not this process's problem to solve — the pages
        // still get written, and it will be stopped soon enough.
        if errno == EINTR { continue }
        return
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

// Answered before anything else, and the reason it exists is `build.sh`: the
// disk image's own verification runs every bundled executable out of the
// mounted image with an empty environment, because the claim that image makes
// is "no Terminal needed". The recogniser revision is the useful thing to print
// — it is what every corpus figure was measured at, and a helper answering with
// a different one would mean the baseline describes a different engine.
if arguments == ["--version"] {
    print("visionocr-recognise, Vision text revision \(Recogniser.revision)")
    exit(0)
}

guard let settings = Recogniser.helperSettings(from: arguments) else {
    die(.badArguments, "could not read the recognition settings from the arguments")
}

var paths: [String: String] = [:]
for pair in stride(from: 0, to: arguments.count - 1, by: 2) {
    paths[arguments[pair]] = arguments[pair + 1]
}
guard let manifestPath = paths["--manifest"], let outputPath = paths["--out"] else {
    die(.badArguments, "--manifest and --out are both required")
}

guard let manifest = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
    die(.unreadableManifest, "could not read the manifest at \(manifestPath)")
}
// A trailing newline is not a page. Empty lines in the middle would be, and are
// left to fail as unreadable rather than silently skipped — a page the app
// listed and this did not recognise must not come back as a success.
let pages = manifest.hasSuffix("\n")
    ? Array(manifest.split(separator: "\n", omittingEmptySubsequences: false).dropLast())
    : manifest.split(separator: "\n", omittingEmptySubsequences: false)

let output = URL(fileURLWithPath: outputPath, isDirectory: true)
let encoder = JSONEncoder()

for (index, line) in pages.enumerated() {
    let path = String(line)
    guard let image = Recogniser.loadImage(at: URL(fileURLWithPath: path)) else {
        die(.unreadablePage, "page \(index + 1) could not be read: \(path)")
    }
    let observations: [SearchableWriter.Observation]
    do {
        observations = try Recogniser.recognise(image, settings: settings)
    } catch {
        die(.recognitionFailed,
            "page \(index + 1) could not be recognised: \(error.localizedDescription)")
    }
    guard let data = try? encoder.encode(Recogniser.HelperPage(observations: observations)),
          (try? data.write(to: output.appendingPathComponent("\(index).json"),
                           options: .atomic)) != nil
    else {
        die(.cannotWrite, "could not write the observations for page \(index + 1)")
    }
    announce(index)
}
