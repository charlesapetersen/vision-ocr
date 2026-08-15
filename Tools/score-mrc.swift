// What MRC costs on the pages this app sends down the picture route, measured by
// running the shipped layering rather than a copy of it.
//
// Why this exists: a library MRC scan of the same material can be several times
// smaller than what this app produces, and the obvious conclusions about why are
// wrong in both directions. An earlier attempt compared MRC against single-layer
// JPEG 2000 on a page whose source layer was *already* JPEG 2000 and concluded
// they tied; they do not (BUGS.md R34). This tool renders each page once and
// builds both candidates from that one render, so nothing here can be an
// artefact of what codec the source happened to use.
//
// **It calls `Flattener.mrcLayers` — the function the app calls — and reads the
// three files it wrote.** It used to reimplement it, and the copy had drifted five
// ways (BUGS.md T15, REVIEW-2026-08-14.md A12.3, which found four of them). They
// did **not** all push the same way, which is why the errors did not cancel and
// why neither the totals nor any single row could be trusted:
//
//   - no R50 all-text shrink, so tone layers came out **10.5–18.3x** the shipped
//     size on the 38 of 72 corpus pages that take it — `mrcKB` overstated by
//     39.8–439.0 KB a page, making MRC look *dearer* than it is;
//   - no colour route, so on the 18 of 74 pages the app keeps in colour *both*
//     columns described a grey artefact nothing publishes — and there MRC looked
//     *cheaper* than it is, by 5.7–38.2 KB;
//   - a 60 MP gate where the render's bound is `maximumPageMegapixels` (400) and
//     the layering's is `maximumMRCPageMegapixels` (100), which silently dropped
//     the corpus's two largest picture pages — 26.7 MB of the 87 MB it was adding
//     up;
//   - no empty-stencil refusal, so a page the app declines to layer was
//     reported as layered;
//   - `Prefs.Snapshot.current()` with no `register()`, so Vision was asked with
//     `languageCorrection: false` against the app's true. Together with reading
//     the boxes off the raw grey render rather than the JPEG the app recognises,
//     that moved the word count on 18 of 24 pages, by up to 30 boxes.
//
// The header this replaces already said the right thing — "a tool that silently
// measures something other than what you are holding is worse than no tool" —
// about two constants it read from `Flattener` while mirroring the 200 lines
// those constants feed. Reading the constants is not the same as running the
// code. `Tools/score-text-route.swift` had never compiled at all (C25) for the
// same reason: mirroring is what tools here get wrong.
//
// So the only layering left in this file is the **blind** one behind MRC_BLIND=1,
// which exists precisely because it is *not* what the app does — see below.
//
// What the commercial tools do, for reference — measured from 275 MRC files in a
// real library, 52 of 60 sampled produced by ABBYY FineReader: they route per
// page exactly as this app does. Plain text pages go to 1-bit JBIG2 and are not
// layered at all; only pages that genuinely mix text with pictures get the three
// layers. So MRC is not a replacement for the 1-bit route — it is a replacement
// for the single big JPEG that mixed pages currently get.
//
//   mkdir -p /tmp/h && cp Tools/score-mrc.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/score-mrc -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/score-mrc testdocs/*/*.pdf
//
// Per picture page: what the app ships today, what the three layers cost, which
// of the two the app would actually publish, and the reconstruction's PSNR
// against the same source render — so a size is never read without the fidelity
// beside it. Pages the app would decline to layer get a row too, with the reason
// in the `note` column; four of them used to be a bare `continue`.
//
// Lines before the header begin with `#` — they say which downsample factors the
// run used and where each came from, because a table of sizes with no record of
// the settings that produced them is how `FEATURES.md` came to quote a figure
// nobody could reproduce.
//
// **It needs `jbig2` and `qpdf`** and refuses to run without either. `jbig2`
// because the stencil is about a third of the layered page and measuring two
// layers out of three would report MRC as cheaper than it is. `qpdf` because the
// app only reaches `mrcLayers` inside the JBIG2 route — `if wantJBIG2, …, let
// qpdf = JBIG2.merger` — so on a machine without it the app publishes **no**
// layered pages at all, and a tool reporting 4.37x there would be describing a
// route that machine cannot take. It cannot check the *setting* that also gates
// it (Searchable PDF ▸ JBIG2, on by default) because a tool has no business
// reading the user's live preferences for that; the banner names it instead.
//
// Environment:
//   MRC_BG / MRC_FG   override the two downsample factors. MRC_BG is the Photo
//                     detail knob; MRC_FG has no user control and defaults to
//                     `Flattener.mrcForegroundDownsample`. This is how the sweep
//                     behind the Photo detail settings was run.
//   MRC_BLIND=1       layer with a Sauvola stencil that is *not* confined to
//                     Vision's word boxes. Deliberately not the shipped route:
//                     it is where the smeared-photograph measurement in
//                     FEATURES.md came from, and it is kept so that measurement
//                     can be reproduced. It composes `Flattener`'s primitives —
//                     `sauvolaMask`, `fillHoles`, `downsample`, `jpegData`,
//                     `greyPNG` — rather than reimplementing any of them.
//
//                     **It differs from the shipped route in three ways, not
//                     one, and only the first is the point.** (1) no confinement,
//                     which is the demonstration. (2) R50's all-text shrink is
//                     not applied, because the signal it depends on is the very
//                     text region this mode throws away. (3) every page is
//                     layered in grey, because the colour interleave lives inside
//                     `mrcLayers` and copying it here is the mirroring this file
//                     exists to be rid of.
//
//                     So **a blind page total is not a like-for-like comparison
//                     against a shipped one** unless the page is grey and R50
//                     does not fire on it. The one column that compares cleanly
//                     everywhere is `maskKB`, which is the stencil the mode is
//                     about. FEATURES.md's confinement table says which is which,
//                     and it was wrong about this until it was recomputed. The
//                     banner repeats it on every blind run.
//   MRC_DUMP=<dir>    write the first three pages' reconstruction, today's
//                     output and the source side by side. Numbers alone cannot
//                     settle this one: PSNR punishes a smoothed background and
//                     is blind to text edges being exact, which is precisely the
//                     trade MRC makes. Look at the pages.
//
// A self-test runs on every invocation and refuses to measure anything if it
// fails, which is `score-threshold-loss`'s pattern and earns its keep the same
// way: its central assertion — that an all-text picture page reports the 8x/16x
// shrink and not 2x/4x — is exactly what this tool got wrong for its whole life.
import AppKit
import CoreGraphics
import Foundation
import PDFKit

// MARK: - The settings the app would run with

// `register` first, and it is not decoration. Without it `Snapshot.current()`
// reads an empty domain, where `languageCorrection` is **false** while every
// shipped run has it **true** — so the tool recognised with a different Vision
// request than the app, got different word boxes, and cut a different stencil.
// Found while fixing A12.3; `make-observations` and `score-line-separation`
// already did this and this file did not.
//
// `migrate: false`, and that half was found by reviewing this diff. A tool has no
// bundle identifier, so its `UserDefaults.standard` is a plist named after the
// *process* — and the migration would copy the user's pre-rename settings out of
// `com.cp1.VisionReaderGUI`, **delete them from there**, and file them in
// `score-mrc.plist`, where the app will never look. A measurement run would eat
// somebody's settings. Registration itself is in-memory, so with the migration off
// this tool writes no preferences at all.
Prefs.register(migrate: false)
let settings = Prefs.Snapshot.current()

let environment = ProcessInfo.processInfo.environment

/// The two factors the app passes. `photoDetail.downsample` is what
/// `makeSearchablePDF` hands to `mrcLayers` for the background; the foreground
/// has no user control and takes the shipped default.
let backgroundDownsample = Int(environment["MRC_BG"] ?? "")
    ?? settings.photoDetail.downsample
let foregroundDownsample = Int(environment["MRC_FG"] ?? "")
    ?? Flattener.mrcForegroundDownsample
let blind = environment["MRC_BLIND"] != nil
let dumpDirectory = environment["MRC_DUMP"]

let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("mrc-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

/// Give up, having cleaned up. A top-level `defer` does not run through `exit`,
/// so the three refusals below would each have left a scratch directory holding a
/// page's worth of layers behind — and this tool's whole subject is pages large
/// enough for that to matter.
func stop(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data(message.utf8))
    try? FileManager.default.removeItem(at: scratch)
    exit(code)
}
defer { try? FileManager.default.removeItem(at: scratch) }

// MARK: - Reading a published layer back

/// One or three 8-bit planes from an image, at a known size.
///
/// Drawn through a CGContext rather than read out of the CGImage, so a JPEG's
/// subsampling and colour space are resolved the way a reader resolves them.
/// Decoding a three-channel JPEG with `colour: false` gives its luminance, which
/// is what makes the grey comparison valid on a page whose layers came back grey.
/// Nil rather than a blank buffer when the context cannot be made. The first
/// version swallowed that failure and returned all-255, so a PSNR would have been
/// computed against a white page and printed as a measurement — §3's own trap, in
/// the code that exists to check the other code's numbers.
func planes(of image: CGImage, width w: Int, height h: Int, colour: Bool) -> [[UInt8]]? {
    guard w > 0, h > 0 else { return nil }
    let rect = CGRect(x: 0, y: 0, width: w, height: h)
    if colour {
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: rect)
            return true
        }
        guard drawn else { return nil }
        return (0..<3).map { channel in
            var plane = [UInt8](repeating: 0, count: w * h)
            for i in 0..<(w * h) { plane[i] = rgba[i * 4 + channel] }
            return plane
        }
    }
    var grey = [UInt8](repeating: 255, count: w * h)
    let drawn = grey.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        context.draw(image, in: rect)
        return true
    }
    return drawn ? [grey] : nil
}

func planes(ofFileAt url: URL, width w: Int, height h: Int, colour: Bool) -> [[UInt8]]? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return planes(of: image, width: w, height: h, colour: colour)
}

func planes(ofData data: Data, width w: Int, height h: Int, colour: Bool) -> [[UInt8]]? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    return planes(of: image, width: w, height: h, colour: colour)
}

/// The stencil, read back from the PNG `mrcLayers` wrote — 0 is ink, as
/// `JBIG2.assemble`'s `/Decode` array expects.
func stencil(atPNG url: URL, width w: Int, height h: Int) -> [Bool]? {
    guard let plane = planes(ofFileAt: url, width: w, height: h, colour: false)?.first
    else { return nil }
    return plane.map { $0 < 128 }
}

/// Bilinear, because that is what a PDF viewer does with a downsampled image.
/// Nearest-neighbour was the first version and it understated MRC badly: it puts
/// blocks of flat tone behind the text and the error lands entirely in the
/// background, which is the one layer MRC deliberately treats as cheap.
///
/// Stretching `(sw, sh)` onto `(w, h)` rather than scaling by the integer factor
/// is also what the reader does — `JBIG2.assemble` draws the layer over the whole
/// page box, so `downsample`'s unsampled ragged edge (A3.4) shows up here as the
/// same sub-1% stretch it shows up as on screen.
func upsample(_ src: [UInt8], width sw: Int, height sh: Int,
              toWidth w: Int, toHeight h: Int) -> [UInt8] {
    var out = [UInt8](repeating: 255, count: w * h)
    guard sw > 0, sh > 0, w > 0, h > 0, src.count >= sw * sh else { return out }
    for y in 0..<h {
        let fy = (Double(y) + 0.5) * Double(sh) / Double(h) - 0.5
        let y0 = max(Int(fy.rounded(.down)), 0), y1 = min(y0 + 1, sh - 1)
        let wy = fy - Double(y0)
        let row0 = min(y0, sh - 1) * sw, row1 = y1 * sw
        for x in 0..<w {
            let fx = (Double(x) + 0.5) * Double(sw) / Double(w) - 0.5
            let x0 = max(Int(fx.rounded(.down)), 0), x1 = min(x0 + 1, sw - 1)
            let wx = fx - Double(x0)
            let a = Double(src[row0 + x0]), b = Double(src[row0 + x1])
            let c = Double(src[row1 + x0]), d = Double(src[row1 + x1])
            let top = a + (b - a) * wx, bottom = c + (d - c) * wx
            out[y * w + x] = UInt8(max(0, min(255, (top + (bottom - top) * wy).rounded())))
        }
    }
    return out
}

/// Peak signal-to-noise over every plane at once, so a colour comparison is one
/// number rather than three that have to be averaged by hand.
func psnr(_ a: [[UInt8]], _ b: [[UInt8]]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return -1 }
    var squared = 0.0, samples = 0
    for (x, y) in zip(a, b) {
        guard x.count == y.count else { return -1 }
        for i in 0..<x.count {
            let d = Double(x[i]) - Double(y[i])
            squared += d * d
        }
        samples += x.count
    }
    guard samples > 0 else { return -1 }
    let mse = squared / Double(samples)
    return mse == 0 ? .infinity : 10 * log10(255 * 255 / mse)
}

/// A PNG of one or three planes, for MRC_DUMP only. Nothing in the pipeline
/// consumes this — `Flattener.greyPNG` is what the pipeline uses, and the blind
/// path below calls it rather than this.
func pngData(planes: [[UInt8]], width w: Int, height h: Int) -> Data? {
    guard w > 0, h > 0, planes.count == 1 || planes.count == 3,
          planes.allSatisfy({ $0.count >= w * h }) else { return nil }
    let samples = planes.count
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
        samplesPerPixel: samples, hasAlpha: false, isPlanar: false,
        colorSpaceName: samples == 1 ? .deviceWhite : .deviceRGB,
        bytesPerRow: w * samples, bitsPerPixel: 8 * samples) else { return nil }
    guard let dest = rep.bitmapData else { return nil }
    for i in 0..<(w * h) {
        for s in 0..<samples { dest[i * samples + s] = planes[s][i] }
    }
    return rep.representation(using: .png, properties: [:])
}

// MARK: - The stencil's real cost

/// JBIG2 bytes for the stencil `mrcLayers` wrote, through the same encoder and
/// the same call the app makes.
func jbig2Bytes(ofMaskAt png: URL, stem: String) -> Int? {
    guard let encoder = JBIG2.encoder else { return nil }
    let stream = scratch.appendingPathComponent(stem + ".jbig2")
    guard (try? JBIG2.encode(png: png, to: stream, using: encoder)) != nil else { return nil }
    defer { try? FileManager.default.removeItem(at: stream) }
    return (try? Data(contentsOf: stream).count)
}

// MARK: - The blind stencil (MRC_BLIND=1), which is not the shipped route

/// The same three layers with the stencil left unconfined, so Sauvola pulls
/// halftone into it.
///
/// This is the comparison, not the product: the measured result is a visibly
/// smeared and streaked photograph on a page whose text came out perfect, which
/// is why `textRegionMask` exists. Built out of `Flattener`'s own primitives so
/// the difference from the shipped route is exactly the missing confinement —
/// the whole of A12.3 was a copy of this function drifting into being a
/// different algorithm.
func blindLayers(grey: [UInt8], width w: Int, height h: Int,
                 dpi: Double, stem: String,
                 background backgroundFactor: Int,
                 foreground foregroundFactor: Int) -> Flattener.MRCLayers? {
    // No `for i where !region[i] { mask[i] = false }` line, which is the one
    // difference from the shipped route and the reason this mode exists.
    let mask = Flattener.sauvolaMask(grey, width: w, height: h,
                                     window: Flattener.sauvolaWindow(dpi: dpi,
                                                                     width: w, height: h))
    guard mask.count == w * h, mask.contains(true) else { return nil }
    // Blind means blind: no region, and therefore no `inkOutsideText` to ask, so
    // R50's shrink cannot be applied here. The factors are the caller's.
    let inverse = mask.map { !$0 }
    var maskPixels = [UInt8](repeating: 255, count: w * h)
    for i in 0..<(w * h) where mask[i] { maskPixels[i] = 0 }
    guard let maskPNG = Flattener.greyPNG(maskPixels, width: w, height: h) else { return nil }

    let filledBackground = Flattener.fillHoles(grey, holes: mask, width: w, height: h,
                                               radius: 10)
    let (background, bw, bh) = Flattener.downsample(filledBackground, width: w, height: h,
                                                    by: max(backgroundFactor, 1))
    let filledForeground = Flattener.fillHoles(grey, holes: inverse, width: w, height: h,
                                               radius: 3)
    let (foreground, fw, fh) = Flattener.downsample(filledForeground, width: w, height: h,
                                                    by: max(foregroundFactor, 1))
    guard let backgroundData = Flattener.jpegData(from: background, width: bw, height: bh,
                                                 quality: Flattener.pictureJPEGQuality),
          let foregroundData = Flattener.jpegData(from: foreground, width: fw, height: fh,
                                                 quality: Flattener.pictureJPEGQuality)
    else { return nil }

    let maskURL = scratch.appendingPathComponent(stem + ".mask.png")
    let backgroundURL = scratch.appendingPathComponent(stem + ".bg.jpg")
    let foregroundURL = scratch.appendingPathComponent(stem + ".fg.jpg")
    guard (try? maskPNG.write(to: maskURL)) != nil,
          (try? backgroundData.write(to: backgroundURL)) != nil,
          (try? foregroundData.write(to: foregroundURL)) != nil else { return nil }
    return Flattener.MRCLayers(mask: maskURL, background: backgroundURL,
                               foreground: foregroundURL,
                               backgroundWidth: bw, backgroundHeight: bh,
                               foregroundWidth: fw, foregroundHeight: fh,
                               isColour: false)
}

// MARK: - Reporting

/// One name per printed field. A row is built as an array and checked against
/// this, because the alternative has already failed twice in this tree: a
/// `String(format:)` row printed **12 fields under an 11-column header** here
/// (the trailing box count had no name), and `score-corpus` emitted a 10-field
/// SKIP row under a 9-column header inside a fix for a reporting defect. A
/// mis-sized row is now a refusal, not a column nobody can name.
let columns = ["file", "page", "px", "dpi", "route", "boxes", "inkOut", "nowKB",
               "maskKB", "bgKB", "fgKB", "mrcKB", "bgF", "fgF", "ratio", "kept",
               "mrcPSNR", "nowPSNR", "note"]

/// Nil when the row does not match the header, so the guard itself is testable
/// rather than being an `exit` the self-test cannot reach.
func rowText(_ cells: [String]) -> String? {
    cells.count == columns.count ? cells.joined(separator: "\t") : nil
}

func emit(_ cells: [String]) {
    guard let line = rowText(cells) else {
        stop("score-mrc: a row of \(cells.count) fields under a "
             + "\(columns.count)-column header; refusing to print it.\n"
             + "  \(cells.joined(separator: " | "))\n", code: 5)
    }
    print(line)
    fflush(stdout)
}

func kb(_ bytes: Int) -> String { String(format: "%.1f", Double(bytes) / 1024) }

/// A dB figure, or `-` when it could not be measured. `psnr` returns a negative
/// number for mismatched buffers, and printing that as `-1.00 dB` would read as a
/// measurement rather than as a failure to make one.
func decibels(_ value: Double) -> String {
    guard value >= 0 else { return "-" }
    return value.isFinite ? String(format: "%.2f", value) : "inf"
}

/// How many pages MRC_DUMP has written. Declared before `measure`, which reads
/// it: a top-level `var` used by a function above its own declaration is zero at
/// the time of the call.
var dumped = 0

// MARK: - One page

/// What the app would do with one page, and what it would cost either way.
///
/// Everything the self-test asserts on is in here rather than read back off the
/// printed row, and everything it asserts on is produced by this function rather
/// than by the self-test calling `Flattener` itself. That is the difference
/// between a check that would catch A12.3 coming back and one that would not: a
/// mirrored layering reintroduced *here* has to fail the self-test, and it does
/// only because the numbers it asserts on came through this path.
struct Outcome {
    var isPictureRoute = false
    /// Bytes of the single JPEG the page carries today.
    var now = 0
    /// Bytes of stencil + background + foreground, or nil when the app would
    /// decline to layer this page at all.
    var mrc: Int?
    var boxes = 0
    /// Why the question could not be asked at all — a page whose geometry is not a
    /// rectangle, one over `maximumPageMegapixels`, or one that would not render.
    /// Distinct from a *declined* layering, which is a picture page the app would
    /// publish as a single JPEG, and distinct again from a page that is simply not
    /// a picture. All three used to be the same silence.
    var refused: String?
    var inkOutsideText = -1.0
    /// The *measured* stretch, `w / backgroundWidth` — not the factor asked for.
    /// `downsample` truncates, so a 1,224 px page at /16 gives 76 px and a
    /// reported 16.1x. That is A3.4's unsampled ragged edge, and it is what the
    /// reader actually sees, so it is what gets printed.
    var backgroundFactor = 0.0
    var foregroundFactor = 0.0
    var stencilShare = -1.0
    var reconstructionPSNR = -1.0
    /// Whether the *published layers* are three-channel. False when Automatic sent
    /// the page down the grey route and false again when it kept the colour but the
    /// colour render failed inside `mrcLayers` — both of which mean the artefact
    /// measured here is grey, which is what the assertion cares about.
    var isColour = false
}

/// Reproduces `flatten`'s picture decision, then asks the shipped layering what
/// it would do — in Automatic, which is the only mode with a picture route to
/// measure. Black & white and Grayscale are instructions; `isPicture` is not
/// consulted in either.
///
/// The three factors are parameters with the environment's values as defaults, so
/// the self-test can measure the *shipped* configuration while MRC_BG, MRC_FG and
/// MRC_BLIND still govern the run. A self-test that inherited MRC_BG=1 would have
/// to re-derive R50's floor rule to know what to expect, which is the mirroring
/// this whole change exists to remove.
func measure(_ page: PDFPage, label: String, index: Int,
             background: Int = backgroundDownsample,
             foreground: Int = foregroundDownsample,
             blindStencil: Bool = blind,
             printing: Bool = true) -> Outcome {
    var outcome = Outcome()
    let box = Flattener.fullBox(of: page)
    let dpi = Flattener.rebuildDPI(of: page)
    let scale = dpi / 72.0
    let wide = (box.width * scale).rounded(), high = (box.height * scale).rounded()
    // `maximumPageMegapixels`, because that is the gate on rendering the page at
    // all. `mrcLayers` applies its own, smaller `maximumMRCPageMegapixels`
    // internally and declines — which is reported below rather than skipped. The
    // 60 MP literal that used to stand here belonged to neither.
    guard wide.isFinite, high.isFinite, wide >= 1, high >= 1 else {
        outcome.refused = "geometry is not a rectangle"
        return outcome
    }
    guard wide * high <= Double(Flattener.maximumPageMegapixels) * 1_000_000 else {
        outcome.refused = String(format: "%.1f MP, over the render bound of %d",
                                 wide * high / 1_000_000, Flattener.maximumPageMegapixels)
        return outcome
    }
    let w = max(Int(wide), 1), h = max(Int(high), 1)
    guard let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                          width: w, height: h, from: .mediaBox)
    else {
        outcome.refused = "would not render"
        return outcome
    }
    let threshold = Flattener.otsuThreshold(of: grey)
    let saturation = Flattener.saturation(of: page)
    guard Flattener.isPicture(page, grey: grey, width: w, height: h,
                              threshold: threshold, saturation: saturation)
    else { return outcome }
    outcome.isPictureRoute = true

    // What ships today, built exactly as `flatten` builds it: colour when
    // Automatic keeps the colour and both colour steps succeed, grey otherwise —
    // including the fall-through, which is a real path and not a formality.
    let wantColour = Flattener.shouldKeepColour(mode: .auto, saturation: saturation,
                                               pixels: wide * high)
    var isColour = false
    var sourceRGBA: [UInt8]?
    var nowEncoded: (data: Data, image: CGImage)?
    if wantColour, let rgba = Flattener.renderRGB(page, box: box, scale: scale,
                                                  width: w, height: h, from: .mediaBox),
       let encoded = Flattener.jpegRGB(from: rgba, width: w, height: h,
                                       quality: Flattener.pictureJPEGQuality) {
        sourceRGBA = rgba
        nowEncoded = encoded
        isColour = true
    } else {
        nowEncoded = Flattener.jpeg(from: grey, width: w, height: h,
                                    quality: Flattener.pictureJPEGQuality)
    }
    guard let now = nowEncoded else {
        outcome.refused = "would not JPEG-encode"
        return outcome
    }
    outcome.now = now.data.count

    let route = isColour ? "colour" : "grey"
    let stem = String(format: "p%05d", index + 1)
    /// Every field the row needs before the layering is known, so a decline
    /// prints the page rather than dropping it. A tool that silently skips is
    /// invariant 1's shape in the instrument — `score-gate` had it (T9) and so
    /// did this one, which used `continue` for all four of its refusals.
    func decline(_ why: String, boxes: Int, inkOut: String) {
        guard printing else { return }
        emit([label, "\(index + 1)", "\(w)x\(h)", String(format: "%.1f", dpi), route,
              "\(boxes)", inkOut, kb(now.data.count), "-", "-", "-", "-", "-", "-",
              "-", "jpeg", "-", "-", why])
    }

    // The boxes come from the *flattened* page, which is what the app recognises
    // — `recogniseDocument` is handed `flatten`'s own bitmaps. Reading them from
    // the raw grey render instead would cut the stencil from an artefact the
    // pipeline never sees.
    let observed = (try? Recogniser.recognise(now.image, settings: settings)) ?? []
    let boxes = observed.map(\.boundingBox)
    outcome.boxes = boxes.count
    guard !boxes.isEmpty else {
        // The app's own first guard: no words means a plate with no text on it,
        // and an empty stencil would publish a picture at a fraction of its
        // resolution for nothing.
        decline("no words", boxes: 0, inkOut: "-")
        return outcome
    }

    // Reported, not used: this is the signal that decides R50's shrink, so
    // printing it is what makes `bgF`/`fgF` legible rather than mysterious. It is
    // measured with the shipped functions over the shipped region.
    let region = Flattener.textRegionMask(boxes, width: w, height: h)
    let inkOutside = Flattener.inkOutsideText(grey, region: region, width: w, height: h,
                                              threshold: threshold)
    outcome.inkOutsideText = inkOutside
    let inkOut = String(format: "%.4f", inkOutside)

    let layers = blindStencil
        ? blindLayers(grey: grey, width: w, height: h, dpi: dpi, stem: stem,
                      background: background, foreground: foreground)
        : Flattener.mrcLayers(for: page, boxes: boxes, into: scratch, stem: stem,
                              backgroundDownsample: background,
                              foregroundDownsample: foreground,
                              inColour: isColour)
    guard let layers else {
        // Name what can be named. `mrcLayers` returns nil for four reasons and
        // says which for none of them, but two are visible from out here: the
        // megapixel gate is arithmetic on numbers this function already has, and
        // an empty box list was refused above. The rest is genuinely "it
        // declined", and saying so is better than a row that implies a fifth
        // cause.
        let megapixels = wide * high / 1_000_000
        decline(megapixels > Double(Flattener.maximumMRCPageMegapixels)
                ? String(format: "%.1f MP, over the layering bound of %d", megapixels,
                         Flattener.maximumMRCPageMegapixels)
                : "declined — empty stencil, or an encode failed",
                boxes: boxes.count, inkOut: inkOut)
        return outcome
    }
    defer {
        for url in [layers.mask, layers.background, layers.foreground] {
            try? FileManager.default.removeItem(at: url)
        }
    }
    guard let maskBytes = jbig2Bytes(ofMaskAt: layers.mask, stem: stem),
          let backgroundBytes = try? Data(contentsOf: layers.background).count,
          let foregroundBytes = try? Data(contentsOf: layers.foreground).count else {
        decline("encode failed", boxes: boxes.count, inkOut: inkOut)
        return outcome
    }
    let mrc = maskBytes + backgroundBytes + foregroundBytes
    outcome.mrc = mrc
    outcome.backgroundFactor = Double(w) / Double(max(layers.backgroundWidth, 1))
    outcome.foregroundFactor = Double(w) / Double(max(layers.foregroundWidth, 1))
    outcome.isColour = layers.isColour

    // Reconstruct from the files that were published, not from the buffers they
    // came from. A check that compares the copy against the source it was made
    // from agrees with itself.
    //
    // The comparison is in colour only when both sides are colour. A page whose
    // colour render failed inside `mrcLayers` comes back with grey layers while
    // today's JPEG is still colour, and the honest comparison there is in
    // luminance — which is what decoding a three-channel JPEG as one plane gives.
    var inColour = layers.isColour && isColour
    var source: [[UInt8]] = [grey]
    if inColour, let rgba = sourceRGBA {
        source = (0..<3).map { channel in
            var plane = [UInt8](repeating: 0, count: w * h)
            for i in 0..<(w * h) { plane[i] = rgba[i * 4 + channel] }
            return plane
        }
    } else {
        inColour = false
    }
    var mrcPSNR = -1.0, nowPSNR = -1.0
    var reconstruction: [[UInt8]] = []
    // Named `…Planes` rather than `background`/`foreground`, which are the two
    // factor parameters. Shadowing them here would compile and read as though the
    // reconstruction were being built from the numbers.
    if let ink = stencil(atPNG: layers.mask, width: w, height: h),
       let backgroundPlanes = planes(ofFileAt: layers.background,
                                     width: layers.backgroundWidth,
                                     height: layers.backgroundHeight, colour: inColour),
       let foregroundPlanes = planes(ofFileAt: layers.foreground,
                                     width: layers.foregroundWidth,
                                     height: layers.foregroundHeight, colour: inColour),
       backgroundPlanes.count == source.count, foregroundPlanes.count == source.count {
        outcome.stencilShare = Double(ink.lazy.filter { $0 }.count) / Double(w * h)
        reconstruction = (0..<source.count).map { plane in
            var out = upsample(backgroundPlanes[plane], width: layers.backgroundWidth,
                               height: layers.backgroundHeight, toWidth: w, toHeight: h)
            let over = upsample(foregroundPlanes[plane], width: layers.foregroundWidth,
                                height: layers.foregroundHeight, toWidth: w, toHeight: h)
            for i in 0..<(w * h) where ink[i] { out[i] = over[i] }
            return out
        }
        mrcPSNR = psnr(source, reconstruction)
        outcome.reconstructionPSNR = mrcPSNR
    }
    if let back = planes(ofData: now.data, width: w, height: h, colour: inColour) {
        nowPSNR = psnr(source, back)
    }

    guard printing else { return outcome }

    if let dump = dumpDirectory, dumped < 3 {
        let name = "\(label.prefix(24))-p\(index + 1)"
        let nowPlanes = planes(ofData: now.data, width: w, height: h, colour: inColour) ?? []
        for (suffix, pixels) in [("mrc", reconstruction), ("now", nowPlanes),
                                 ("src", source)] where !pixels.isEmpty {
            guard let data = pngData(planes: pixels, width: w, height: h) else { continue }
            try? data.write(to: URL(fileURLWithPath: dump)
                .appendingPathComponent("\(name)-\(suffix).png"))
        }
        dumped += 1
    }

    emit([label, "\(index + 1)", "\(w)x\(h)", String(format: "%.1f", dpi), route,
          "\(boxes.count)", inkOut, kb(now.data.count), kb(maskBytes),
          kb(backgroundBytes), kb(foregroundBytes), kb(mrc),
          String(format: "%.1f", outcome.backgroundFactor),
          String(format: "%.1f", outcome.foregroundFactor),
          String(format: "%.2fx", Double(now.data.count) / Double(max(mrc, 1))),
          // The app keeps whichever is smaller — `after < before` in
          // `makeSearchablePDF`. Three layers are not always cheaper than one
          // image, and a total that assumed they were would describe a route the
          // app declines to take.
          mrc < now.data.count ? "mrc" : "jpeg",
          decibels(mrcPSNR), decibels(nowPSNR),
          blindStencil ? "blind" : "-"])
    return outcome
}

// MARK: - Self-test, on every run

/// Two fixtures, because the self-test needs both halves of R50's rule and both
/// sides of the colour decision.
///
/// **`.allText`** — a page of type on paper dark enough to read as continuous
/// tone: `isPicture` routes it as a picture, and every ink pixel is inside a
/// recognised word. That combination is R50's whole population — the Internet
/// Archive scan whose 568 text pages went down the picture route because their
/// paper carried a cast — and it is the case `make-plate-fixtures` does not build.
/// Measured: `tone 0.984`, `sat 0.000`, `inkOutsideText 0.0000`, so it routes on
/// tone alone and the shrink fires. Paper at luminance 115 is in the middle of a
/// wide plateau: 100 through 130 all give tone > 0.98, and it flips to a text page
/// somewhere between 130 and 148, so the fixture is not finely balanced.
///
/// **`.colourPlate`** — the same type on cream stock with a saturated block on it.
/// It routes as a picture on *saturation*, `shouldKeepColour` keeps it, and its ink
/// is mostly outside the words, so it exercises everything the first fixture
/// cannot: the colour render, `jpegRGB`, `inColour`, the three-plane read-back and
/// the three-plane PSNR — **and R50 declining to fire**. Added because reviewing
/// this diff showed that deleting the colour route from `measure` altogether left
/// the self-test green while silently regrading 18 corpus pages from colour to
/// grey, which is the second of the five divergences this file was rewritten for.
enum SelfTestPage: String {
    case allText = "selftest-alltext"
    case colourPlate = "selftest-colour"
}

func writeSelfTestPage(_ kind: SelfTestPage, to url: URL) -> Bool {
    let dpi = 300.0
    let pageWide = 4.25 * 72, pageHigh = 5.5 * 72
    let pxWide = Int(4.25 * dpi), pxHigh = Int(5.5 * dpi)
    guard let canvas = CGContext(data: nil, width: pxWide, height: pxHigh,
                                 bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    switch kind {
    case .allText:
        let paper = 115.0 / 255.0
        canvas.setFillColor(red: paper, green: paper, blue: paper, alpha: 1)
    case .colourPlate:
        // Cream, not white: every real scan has some, and pure white makes Otsu's
        // job easier than it ever is in practice.
        canvas.setFillColor(red: 0.97, green: 0.955, blue: 0.92, alpha: 1)
    }
    canvas.fill(CGRect(x: 0, y: 0, width: pxWide, height: pxHigh))
    canvas.scaleBy(x: dpi / 72.0, y: dpi / 72.0)
    canvas.textMatrix = .identity
    let body = """
        The question of what a page is made of has an answer that depends \
        entirely on who is asking. A compositor sees a forme; a binder sees a \
        signature; a reader sees an argument. The scanner, which is the only one \
        of them that must decide without understanding, sees a field of luminance \
        and has to guess.
        """
    let margin = 36.0, column = pageWide - 2 * margin
    var y = pageHigh - margin
    for (piece, height) in [
        (NSAttributedString(string: "The Compositor's Question", attributes: [
            .font: NSFont(name: "Times-Bold", size: 15) ?? NSFont.boldSystemFont(ofSize: 15),
            .foregroundColor: NSColor.black]), 22.0),
        (NSAttributedString(string: body, attributes: [
            .font: NSFont(name: "Times-Roman", size: 11) ?? NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.black]), 220.0)
    ] {
        let path = CGPath(rect: CGRect(x: margin, y: y - height,
                                       width: column, height: height), transform: nil)
        let frame = CTFramesetterCreateFrame(
            CTFramesetterCreateWithAttributedString(piece), CFRange(), path, nil)
        canvas.saveGState()
        CTFrameDraw(frame, canvas)
        canvas.restoreGState()
        y -= height + 10
    }
    if kind == .colourPlate {
        // A saturated block in the lower third, the way `make-plate-fixtures` puts
        // a plate on a page. Luminance ~103 so it is ink by any threshold this page
        // produces, which is what puts `inkOutsideText` well above 0.08 and keeps
        // R50 from firing — the assertion the all-text fixture cannot make.
        canvas.setFillColor(red: 0.62, green: 0.14, blue: 0.16, alpha: 1)
        canvas.fill(CGRect(x: margin, y: 40, width: column, height: 130))
    }
    guard let image = canvas.makeImage(),
          let consumer = CGDataConsumer(url: url as CFURL) else { return false }
    var box = CGRect(x: 0, y: 0, width: pageWide, height: pageHigh)
    guard let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return false }
    pdf.beginPDFPage(nil)
    pdf.draw(image, in: box)
    pdf.endPDFPage()
    pdf.closePDF()
    return true
}

func selfTest() -> [String] {
    var failures: [String] = []
    // `@autoclosure`, so a detail string that costs a render is only paid for by a
    // failure. The picture-gate diagnosis below needs the three signals to be of
    // any use to whoever reads it, and computing them on every clean run would put
    // a second render of the fixture in front of every invocation.
    func expect(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String) {
        if !ok { failures.append("\(name) — \(detail())") }
    }
    /// The routing signals, for a failure message. Not used by any assertion —
    /// `measure` is what decides, and this only says why it decided.
    func signals(_ kind: SelfTestPage) -> String {
        guard let document = Flattener.open(
                  scratch.appendingPathComponent(kind.rawValue + ".pdf"), password: nil),
              let page = document.page(at: 0) else { return "the fixture would not reopen" }
        let box = Flattener.fullBox(of: page)
        let scale = Flattener.rebuildDPI(of: page) / 72.0
        let w = max(Int((box.width * scale).rounded()), 1)
        let h = max(Int((box.height * scale).rounded()), 1)
        guard let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                              width: w, height: h, from: .mediaBox)
        else { return "the fixture would not render" }
        let s = Flattener.pictureSignals(page, grey: grey, width: w, height: h)
        return String(format: "ink %.3f tone %.3f sat %.3f otsu %d "
                      + "(tone must clear %.2f or sat %.2f)",
                      s.ink, s.tone, s.sat, s.threshold, Flattener.pictureToneThreshold,
                      Flattener.pictureSaturationThreshold)
    }

    /// One fixture through `measure`, at the shipped factors. Returns nil when the
    /// page never got far enough for the assertions to mean anything.
    func run(_ kind: SelfTestPage) -> Outcome? {
        let url = scratch.appendingPathComponent(kind.rawValue + ".pdf")
        guard writeSelfTestPage(kind, to: url) else {
            failures.append("could not build the \(kind.rawValue) fixture"); return nil
        }
        guard let document = Flattener.open(url, password: nil),
              let page = document.page(at: 0) else {
            failures.append("could not open the \(kind.rawValue) fixture"); return nil
        }
        // Through `measure`, not around it. Everything asserted below is a property
        // of the *tool's* per-page path — the picture gate, the colour decision, the
        // recognition input, the delegation, the jbig2 encode and the layer
        // read-back — and calling `Flattener` directly here would leave the one
        // thing A12.3 was untested: a mirrored layering sitting in `measure` where
        // the delegation is.
        //
        // At the shipped factors, so the expected numbers are constants read from
        // `Flattener` rather than R50's floor rule re-derived. MRC_BG=1 legitimately
        // suppresses the shrink (`keepEveryPixel`), and a self-test that inherited
        // it would have to know that to know what to expect.
        return measure(page, label: kind.rawValue + ".pdf", index: 0,
                       background: Flattener.mrcBackgroundDownsample,
                       foreground: Flattener.mrcForegroundDownsample,
                       blindStencil: false, printing: false)
    }

    /// The properties both fixtures must have, whatever else differs.
    func expectMeasured(_ kind: SelfTestPage, _ outcome: Outcome) -> Bool {
        expect("\(kind.rawValue) routes as a picture", outcome.isPictureRoute,
               signals(kind))
        guard outcome.isPictureRoute else { return false }
        expect("Vision reads \(kind.rawValue)", outcome.boxes > 0, "no words found")
        // Today's bytes were unasserted, and they are half of every ratio printed.
        expect("\(kind.rawValue) has a page to compare against", outcome.now > 0,
               "today's JPEG measured 0 bytes")
        expect("\(kind.rawValue) was layered", outcome.mrc != nil,
               "the layering declined it")
        guard outcome.mrc != nil else { return false }
        expect("\(kind.rawValue)'s stencil holds a page of type",
               outcome.stencilShare > 0.001 && outcome.stencilShare < 0.20,
               String(format: "%.4f of the sheet", outcome.stencilShare))
        expect("\(kind.rawValue) reconstructs to something like the page",
               outcome.reconstructionPSNR > 20,
               String(format: "%.2f dB", outcome.reconstructionPSNR))
        return true
    }

    // The row guard, first and cheaply: it is the one thing here that has to hold
    // for a failure of anything else to be readable.
    expect("a short row is refused", rowText(["one"]) == nil, "it was accepted")
    expect("a full row is printed",
           rowText([String](repeating: "x", count: columns.count)) != nil, "it was refused")

    // Fixture 1 — R50 fires. The assertion this tool exists to keep: at the shipped
    // `2`, which is what the mirrored copy used unconditionally, an all-text page
    // must come back shrunk by `textPageBackgroundDownsample`. Reporting 2 and 4
    // here was the whole 10.5–18.3x overstatement.
    if let text = run(.allText), expectMeasured(.allText, text) {
        expect("the all-text fixture's ink is all text",
               text.inkOutsideText >= 0
                   && text.inkOutsideText < Flattener.textPageInkOutsideThreshold,
               String(format: "inkOutsideText %.4f, threshold %.2f", text.inkOutsideText,
                      Flattener.textPageInkOutsideThreshold))
        expect("an all-text page takes R50's background shrink",
               Int(text.backgroundFactor.rounded()) == Flattener.textPageBackgroundDownsample,
               String(format: "%.1fx, expected %dx", text.backgroundFactor,
                      Flattener.textPageBackgroundDownsample))
        expect("an all-text page takes R50's foreground shrink",
               Int(text.foregroundFactor.rounded()) == Flattener.textPageForegroundDownsample,
               String(format: "%.1fx, expected %dx", text.foregroundFactor,
                      Flattener.textPageForegroundDownsample))
        expect("an all-text page is grey", !text.isColour, "it came back colour")
    }

    // Fixture 2 — the colour route, and R50 *not* firing. Both halves were
    // unasserted: deleting `shouldKeepColour` from `measure` left the self-test
    // green while regrading every colour page to grey, and nothing would have
    // caught a shrink applied unconditionally either.
    if let plate = run(.colourPlate), expectMeasured(.colourPlate, plate) {
        expect("the colour fixture keeps its colour", plate.isColour,
               "it was layered and compared in grey — " + signals(.colourPlate))
        expect("a page with a plate on it has ink outside the words",
               plate.inkOutsideText >= Flattener.textPageInkOutsideThreshold,
               String(format: "inkOutsideText %.4f, threshold %.2f", plate.inkOutsideText,
                      Flattener.textPageInkOutsideThreshold))
        expect("a picture page keeps the caller's background factor",
               Int(plate.backgroundFactor.rounded()) == Flattener.mrcBackgroundDownsample,
               String(format: "%.1fx, expected %dx", plate.backgroundFactor,
                      Flattener.mrcBackgroundDownsample))
        expect("a picture page keeps the caller's foreground factor",
               Int(plate.foregroundFactor.rounded()) == Flattener.mrcForegroundDownsample,
               String(format: "%.1fx, expected %dx", plate.foregroundFactor,
                      Flattener.mrcForegroundDownsample))
    }
    return failures
}

// The encoder check comes *first*, because the self-test layers a page and would
// otherwise report a missing jbig2 as "the layering declined it" — a refusal that
// is right for the wrong reason, which is R43's shape and what `run_tests.sh`'s
// own helper check exists to avoid.
guard JBIG2.encoder != nil else {
    stop("score-mrc: jbig2 is not on PATH. The stencil is about a third of a\n"
         + "           layered page, so measuring two layers out of three would\n"
         + "           report MRC as cheaper than it is. Refusing.\n"
         + "           \(JBIG2.installHint)\n", code: 3)
}
// qpdf too, because the app reaches `mrcLayers` only inside the JBIG2 route: with
// no merger there are no layered pages to measure on this machine, whatever this
// tool would print. Found by asking §4b's question of the guard above — who else
// gates the thing I just made a precondition?
guard JBIG2.merger != nil else {
    stop("score-mrc: qpdf is not on PATH. The app only layers pages on the JBIG2\n"
         + "           route, which needs qpdf to merge — so on this machine it\n"
         + "           publishes no MRC at all and any ratio here would describe\n"
         + "           a route it cannot take. Refusing.\n"
         + "           \(JBIG2.installHint)\n", code: 3)
}
let failures = selfTest()
guard failures.isEmpty else {
    stop("score-mrc: self-test failed; measuring nothing:\n  "
         + failures.joined(separator: "\n  ") + "\n", code: 4)
}

// MARK: - The run

if blind {
    print("# MRC_BLIND=1: the stencil is not confined to Vision's boxes, and R50's")
    print("#   all-text shrink is not applied. This is the comparison, not the route.")
}
// Named for where each factor came from. Printing "Photo detail Balanced:
// background /1" under MRC_BG=1 would attribute an override to the setting it
// overrides, and Balanced is the one value a reader is most likely to assume.
print("# background /\(backgroundDownsample) "
      + (environment["MRC_BG"] == nil
         ? "(Photo detail \(settings.photoDetail.label))" : "(MRC_BG)")
      + ", foreground /\(foregroundDownsample) "
      + (environment["MRC_FG"] == nil ? "(shipped default)" : "(MRC_FG)")
      + " — before R50's all-text shrink, which is a floor and can only raise them")
print(columns.joined(separator: "\t"))

var pages = 0, layered = 0, declined = 0, unreadable = 0, refused = 0
var nowTotal = 0, mrcTotal = 0, publishedTotal = 0, mrcLostTo = 0
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    // Counted and named, not passed over. A locked or damaged document used to
    // leave no trace at all, so a corpus run that had silently read 200 of 233
    // files was indistinguishable from one that read them all — and the totals
    // below would still have printed a confident ratio.
    guard let document = Flattener.open(url, password: nil) else {
        unreadable += 1
        FileHandle.standardError.write(Data(
            "score-mrc: could not open \(url.lastPathComponent)\n".utf8))
        continue
    }
    // Distinct for every page count: `n/3 < n/2 < 3n/4` holds for all n >= 5, and
    // n <= 4 takes every page. A12.8 found `score-text-route` measuring page 1
    // three times at n=5; this sampling does not have that defect.
    let indices = document.pageCount <= 4
        ? Array(0..<document.pageCount)
        : [document.pageCount / 3, document.pageCount / 2, document.pageCount * 3 / 4]
    for index in indices {
        guard let page = document.page(at: index) else {
            refused += 1
            FileHandle.standardError.write(Data(
                "score-mrc: \(url.lastPathComponent) p\(index + 1) would not load\n".utf8))
            continue
        }
        let outcome = measure(page, label: url.lastPathComponent, index: index)
        // Terminal, and *before* the picture-route test. `refused` means the
        // question could not be asked, so the page has no `now` bytes to add: the
        // first version reported it and then counted it as a picture page anyway,
        // folding a zero into the totals and printing no row for it.
        if let why = outcome.refused {
            refused += 1
            FileHandle.standardError.write(Data(
                "score-mrc: \(url.lastPathComponent) p\(index + 1) — \(why)\n".utf8))
            continue
        }
        guard outcome.isPictureRoute else { continue }
        pages += 1
        nowTotal += outcome.now
        if let mrc = outcome.mrc {
            layered += 1
            mrcTotal += mrc
            publishedTotal += min(mrc, outcome.now)
            if mrc >= outcome.now { mrcLostTo += 1 }
        } else {
            declined += 1
            publishedTotal += outcome.now
        }
    }
}

print("\n=== \(pages) picture pages: \(layered) layered, \(declined) declined ==="
      + (unreadable > 0 ? "   \(unreadable) document(s) would not open" : "")
      + (refused > 0 ? "   \(refused) page(s) could not be measured — see stderr" : ""))
if layered > 0 {
    print("today  \(nowTotal / 1024) KB   layered \(mrcTotal / 1024) KB   "
          + String(format: "%.2fx smaller over the pages that layered",
                   Double(nowTotal) / Double(max(mrcTotal, 1))))
}
if pages > 0 {
    // What the app would actually publish: the smaller of the two per page, with
    // the declined pages keeping their JPEG. This is the number to quote.
    print("as published \(publishedTotal / 1024) KB   "
          + String(format: "%.2fx smaller than today", Double(nowTotal)
                   / Double(max(publishedTotal, 1)))
          + "   (\(mrcLostTo) page\(mrcLostTo == 1 ? "" : "s") where three layers "
          + "cost more than one image)")
}
