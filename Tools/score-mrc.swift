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
// ⚠️ **C27 (b) added `arm`, `wantC` and `pubKB` on 2026-08-26**, and the first two
// exist because MRC_COLOUR below can make this tool print a row for a decision the
// app does NOT take. `wantC` is `shouldKeepColour`'s own answer for the page and
// `arm` says which decision the row measured, so a forced row can never be read as
// production's. `pubKB` is what the app would publish for that page under that arm —
// the single JPEG, or the three layers when they came out smaller — and it is the
// quantity C27's byte price is denominated in. It is what the closing
// `as published` total adds up, from the same expression.
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
//   MRC_PAGES=4,7     measure exactly these 1-based pages of EVERY document in the
//                     invocation, instead of the three-page sample. C27's population
//                     is named pages of named documents and the sample reaches almost
//                     none of them, so its run is one invocation per document. A page
//                     past the end lands in `refused` and is named on stderr rather
//                     than dropped. Refused (exit 2) on anything that is not a
//                     comma-separated list of positive integers, `MRC_PAGES=` and
//                     `MRC_PAGES=4,,7` included — **and on a REPEATED page**, because
//                     `MRC_PAGES=1,1,1` otherwise counted one page three times into
//                     every total (found by the review of the commit that added this,
//                     2026-08-26; it is A12.8's defect in a second place). The repeat
//                     refusal has a message of its OWN, naming the page — so a check
//                     can pin which guard spoke and not merely which knob.
//   MRC_COLOUR=colour force the colour decision on every picture page instead of
//         |grey       asking `shouldKeepColour`. **C27 (b): the byte price of keeping
//                     spot colour.** The constant cannot be moved to ask this —
//                     `pictureSaturationThreshold` gates the ROUTE as well as the
//                     colour, so a lower bar changes which pages are picture pages at
//                     the same time, and the byte figure would be two changes added
//                     together. Refused (exit 2) on any other value.
//
//                     ⛔ **It is NOT "the colour decision and nothing else", and this
//                     tool's own run measured that.** A forced arm hands Vision a
//                     colour JPEG instead of a grey one, so the word boxes come back
//                     different on 21 of 30 sampled pages and `pageIsAllText()` flips
//                     on 6 — moving `bgF` between /8 and /2, which is a background
//                     resolution change and not a colour one. What the knob buys over
//                     a lower bar is that the ROUTE is held fixed; downstream of the
//                     route it is one change with a measured second-order effect, and
//                     80.4% of the naive aggregate is that effect rather than colour.
//                     See `BUGS.md` C27 `#### The byte price, MEASURED`.
//
//                     **The negative control is free and it is inside the knob**: on a
//                     page whose own verdict is already colour, `MRC_COLOUR=colour`
//                     must reproduce the shipped row byte for byte, and `wantC` is
//                     what says which pages those are. So the price is the difference
//                     between two runs of ONE binary, with the rows that should not
//                     have moved available in the same pair of files.
//
//                     ⛔ It is not a seam and not a proposal. Nothing in `Sources/`
//                     reads it and no constant moves; a `force-` row is a price.
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
//                     **Exits 6 if it did not write what it promised**, including
//                     the case where it wrote nothing at all over a run that did
//                     layer pages. Every failure in the writer used to be a `try?`
//                     or a `continue` and the page was counted as dumped anyway, so
//                     an unwritable directory produced an empty directory and a
//                     clean exit — over the one mode whose entire output is images.
//                     Found by C26 sub-step 4's sibling sweep. 6 rather than 4
//                     because 4 already means "the self-test failed and nothing was
//                     measured" and 5 a drifted row width; a lost dump plane must
//                     not read as either.
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

/// C27 (b). Which colour decision the run measures on every picture page.
///
/// `shipped` is `Flattener.shouldKeepColour`'s own answer, which is what every row
/// this tool printed before 2026-08-26 was. The two forcing values exist because
/// C27's open question is what the *other* answer costs, and the constant cannot be
/// moved to ask it: `pictureSaturationThreshold` gates the ROUTE as well as the
/// colour (C9's "the same number charged twice"), so a bar low enough to keep a
/// page's colour also changes which pages are picture pages, and a byte figure taken
/// that way would be two changes added together. Forcing the decision here holds the
/// ROUTE fixed, which is the whole benefit over a lower bar.
///
/// ⛔ **What it does NOT do is "change the colour and nothing else about the page" —
/// this file said exactly that for one commit and the same commit's own run measured it
/// false.** A forced arm hands Vision a colour JPEG rather than a grey one, so the
/// recogniser's word boxes differ on 21 of 30 sampled pages, `pageIsAllText()` flips on
/// 6, and `bgF` moves between /8 and /2 — **80.4%** of the naive +475.0 KB aggregate is
/// that flip rather than the colour, which is why the number C27 quotes is the +93.0 KB
/// over the 13 pages whose verdict HELD. So a `force-` row is one change at the route
/// and two downstream of it, and `bgF` beside `pubKB` is what lets a reader tell which
/// they are looking at. (`BUGS.md` C27 `#### The byte price, MEASURED`.)
///
/// ⛔ **It is not a proposal and it is not a seam.** Nothing in `Sources/` reads it,
/// no constant moves, and a `force-` row is a price rather than a recommendation —
/// the same standing the refused luminance candidate in `score-threshold-loss` has.
///
/// Sibling sweep (CONTRIBUTING 4b): `Flattener.shouldKeepColour` has one production call
/// site and two in `Tools/`. The other is `score-picture-codec.swift:124`, which reads it
/// **negated, as a filter** — R34's question is JPEG-against-JPEG-2000 fidelity on the
/// grey picture pages, so forcing the arm there would change the population rather than
/// price an arm, and it is deliberately left alone.
enum ColourArm: String {
    case shipped, colour, grey

    /// What the row's `arm` column says. The `shipped` arm prints the verdict it
    /// inherited rather than the bare word, so a file holding rows from more than one
    /// run can never leave a reader guessing which decision produced a byte count —
    /// the failure `MRC_BG`'s banner exists to prevent, one column over.
    func label(shipWants: Bool) -> String {
        switch self {
        case .shipped: return shipWants ? "ship-colour" : "ship-grey"
        case .colour: return "force-colour"
        case .grey: return "force-grey"
        }
    }
}

/// Refusals here write and `exit` directly instead of going through `stop`, because
/// `scratch` does not exist yet — which is the whole reason this block sits above it.
/// Exit **2**: nothing was measured and the self-test is not what refused. 3 is a
/// missing helper, 4 a failed self-test, 5 a drifted row width, 6 a lost dump.
func refuseConfiguration(_ message: String) -> Never {
    FileHandle.standardError.write(Data(message.utf8))
    exit(2)
}

let colourArm: ColourArm = {
    guard let raw = environment["MRC_COLOUR"] else { return .shipped }
    guard let arm = ColourArm(rawValue: raw) else {
        refuseConfiguration(
            "score-mrc: MRC_COLOUR=\(raw) is not one of shipped, colour, grey.\n"
            + "           Unset it to measure what the app decides for itself.\n")
    }
    return arm
}()

/// The exact pages to measure, 1-based, instead of the three-page sample.
///
/// C27's population is named pages of named documents — `Ford_1941` p5,
/// `HarpersMagazine` p4, `1954 - Why` p7 — and the sample below reaches almost none
/// of them, so without this the tool cannot be pointed at the entry's own population
/// at all. It applies to **every** document in the invocation, which is why C27's own
/// run is one invocation per document.
///
/// A page number past the end of a document is not silently dropped: it lands in
/// `refused` and is named on stderr, exactly like a page that will not load.
///
/// ⚠️ **Page selection is now spelled FOUR ways across `Tools/`, and the sibling sweep
/// for this change is the record of it rather than a fix.** `--pages 41,78` is a LIST in
/// `score-reading-order`, `score-run-width`, `score-skew` and `score-threshold-loss`;
/// `PAGES=n` is a COUNT in `score-routing-census` and — in the same tool as the flag —
/// `score-threshold-loss`; `score-text-route` reads trailing integer arguments; and this
/// is the first `*_PAGES` env list. **The sharpest part is that one tool already uses
/// `PAGES` and `--pages` for two different quantities**, so a reader who learned
/// `PAGES=n` there can read `MRC_PAGES=4,7` as "sample four pages, then seven". It is a
/// list. The env form was kept because every other knob this tool has is `MRC_`-prefixed
/// env and a lone flag would be a second convention inside one interface; the prefix is
/// what stops it colliding with the count.
///
/// ⛔ **The parse is a function returning a THREE-CASE result rather than an inline closure
/// so the self-test can reach it** — the same reason `rowText` returns nil instead of
/// exiting. The first version was a closure calling `refuseConfiguration` directly, which
/// no check can call twice, and its duplicate defect (below) was found by reading rather
/// than by a red row.
///
/// ⛔ **Three cases and not `[Int]?`, because ONE refusal value cannot say WHICH GUARD
/// refused — the review of the commit that added the repeat guard measured that gap.**
/// With a shared `nil` and a shared message, every `MRC_PAGES` row in
/// `fault-inject.sh` and both duplicate rows in the table below pinned only *which knob*
/// objected: a sabotage replacing `Set(numbers).count == numbers.count` with
/// `numbers.allSatisfy { $0 >= 2 }` still refused `1,1,1`, still accepted `4,7`, and left
/// **all eight** fault rows and both table rows green. Naming the repeated page is what
/// makes "refused for being a repeat" a distinct, falsifiable observation — and it is the
/// better diagnostic besides, since the old message foregrounded DISTINCT for six
/// refusals that have nothing to do with distinctness.
enum PagesParse: Equatable {
    /// A list of distinct 1-based page numbers, in the order the caller wrote them.
    case ok([Int])
    /// Not a comma-separated list of positive integers at all.
    case malformed
    /// Well-formed, but this page is named more than once.
    case repeated(Int)
}

func parseRequestedPages(_ raw: String) -> PagesParse {
    // `omittingEmptySubsequences: false`, so `MRC_PAGES=4,,7` and `MRC_PAGES=` are
    // refusals rather than a silently shorter list. A dropped page number here would
    // be a measurement of a population nobody asked for.
    let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
    let numbers = parts.compactMap { Int($0) }
    guard numbers.count == parts.count, numbers.allSatisfy({ $0 >= 1 }) else {
        return .malformed
    }
    // ⛔ **A REPEATED PAGE IS REFUSED, and this is the defect the adversarial review of
    // the commit that added this knob found (2026-08-26).** `MRC_PAGES=1,1,1` measured
    // page 1 three times, added it into `pages`, `nowTotal` and `publishedTotal` three
    // times, and printed a summary indistinguishable from three distinct pages — which
    // is *exactly* A12.8's defect in `score-text-route`, under the comment at the
    // sampling site that says this path does not have it. Verified by running before the
    // fix: three identical rows, `=== 3 picture pages`, `today 809 KB`.
    //
    // Refused rather than de-duplicated, because a caller who wrote a page twice does
    // not have the population they think they have and silently collapsing the list
    // would print a two-page total under a three-page request. The insert-and-test loop
    // rather than a `Set` count, because it reports WHICH page repeated — see the
    // three-case rationale above — and it keeps the ORDER the caller asked for, which a
    // sort would not.
    var seen = Set<Int>()
    for page in numbers where !seen.insert(page).inserted { return .repeated(page) }
    return .ok(numbers)
}

let requestedPages: [Int]? = {
    guard let raw = environment["MRC_PAGES"] else { return nil }
    switch parseRequestedPages(raw) {
    case .ok(let numbers):
        return numbers
    case .malformed:
        refuseConfiguration(
            "score-mrc: MRC_PAGES=\(raw) must be a comma-separated list of\n"
            + "           1-based page numbers. Unset it for the three-page sample.\n")
    case .repeated(let page):
        // A message of its own, so a check can tell this refusal from the one above.
        refuseConfiguration(
            "score-mrc: MRC_PAGES=\(raw) names page \(page) more than once, and a\n"
            + "           repeated page is counted into every total once per mention.\n"
            + "           Name each page at most once.\n")
    }
}()

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
/// C27 (b) appended three columns on 2026-08-26 and put them at the **end**, after
/// the free-text `note`, which reads oddly and is deliberate: **FOUR of `MRC-2026-08-15/`'s
/// five committed files** carry exactly the first nineteen, so appending is what lets
/// a run of today's tool be checked column-for-column against them. Inserting `arm`
/// next to `route`, where it belongs semantically, would have shifted twelve columns
/// and made every earlier artefact incomparable by position.
///
/// ⚠️ **"Five" was wrong for one commit and the fifth file is the interesting one.**
/// `mirrored-instrument.tsv` has an **eleven**-name header — and its first data row
/// carries **twelve** fields, which is the very "12 fields under an 11-column header"
/// artefact the paragraph above cites as this guard's founding defect. So it is not a
/// comparable file, it is the pre-fix one, and a check asserting five would have been
/// asserting something false about the only artefact that proves the rule.
let columns = ["file", "page", "px", "dpi", "route", "boxes", "inkOut", "nowKB",
               "maskKB", "bgKB", "fgKB", "mrcKB", "bgF", "fgF", "ratio", "kept",
               "mrcPSNR", "nowPSNR", "note",
               "arm", "wantC", "pubKB"]

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

/// Planes MRC_DUMP promised and did not write. Separate from `dumped` because
/// `dumped == 0` with `dumpMissing == 0` is a run that never reached a dumpable page,
/// while `dumped == 0` with `dumpMissing > 0` is a broken dump — and the two used to be
/// the same observable state, namely an empty directory and a clean exit.
var dumpMissing = 0

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
    /// C27 (b). `shouldKeepColour`'s own answer for this page, whatever arm the run
    /// forced. A forced row still has to carry it: the verdict is what C27 is about,
    /// and a file of `force-colour` rows with no record of which pages the app would
    /// have kept anyway prices nothing.
    var shipWantsColour = false
    /// What the app would publish for this page under this arm — the three layers
    /// when they came out smaller than the single JPEG, that JPEG otherwise. This is
    /// the quantity C27 (b) is a price in, so it is printed rather than left to the
    /// reader to derive from `kept`.
    var published = 0
    /// The row exactly as it was handed to `emit`, so the self-test can assert what
    /// lands in a named column and not merely that the field count is right. The
    /// eleventh check in this register that could not fail was two printed columns of
    /// `score-threshold-loss` asserted by nothing (2026-08-26); a self-test that runs
    /// with `printing: false` cannot see a printer, so it reads this instead.
    var cells: [String] = []
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
             arm: ColourArm = colourArm,
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
    let shipWantsColour = Flattener.shouldKeepColour(mode: .auto, saturation: saturation,
                                                     pixels: wide * high)
    outcome.shipWantsColour = shipWantsColour
    // C27 (b). `shipped` is the app's own answer; the two forcing arms are how the
    // other answer gets priced without moving a constant that also gates the route.
    // Note what is NOT forced: the megapixel bound inside `shouldKeepColour` is part
    // of the shipped verdict, so `MRC_COLOUR=colour` on a page over it prices a
    // colour render the app would never attempt.
    //
    // ⚠️ **The reassurance here quoted the wrong quantity, and CONTRIBUTING §3 is why:
    // `cells` is the ANALYSIS GRID count over the INTERIOR WINDOW with a `factor` beside
    // it, not a pixel count.** It said "the widest `cells` in
    // `THRESHOLD-LOSS-2026-08-18.tsv` is 3.84 M", where the quantity `shouldKeepColour`
    // reads is `wide * high`.
    //
    // ⛔ **The number to quote is `Flattener`'s own, 64.84 MP against a bar of 100 —
    // 65% of it, not "far under" and not "half"** — measured over the 233-document
    // corpus and recorded beside `maximumColourMRCPageMegapixels` itself. So the
    // `cells` figure understated by **16.87x** (64.84 / 3.84426), and a §4b sweep of the
    // constant's own name would have found the right figure with no reconstruction at
    // all. ⚠️ **A first fix reconstructed `max(cells × factor²)` = 49.59 MP (`___` p1,
    // cells 1,377,544 at factor 6) and called that the widest page — 1.31x low, in the
    // reassuring direction, i.e. the same class of error one line up.** `pageMarks`
    // counts cells over `interiorWindow`, which drops `w/16` and `h/16` each side, so
    // `cells × factor²` is (14/16)² = **0.766** of `wide * high`; 49.59 / 0.766 = 64.8,
    // which reproduces the measured 64.84 and is the only thing that reconstruction is
    // good for. Verified on committed data: `Atkinson_1939` p2 is 1935x2592, its
    // interior 1695 × 2268 = 3,844,260, exactly that row's `cells` at factor 1.
    //
    // Either way the conclusion survives — no corpus page is over the bound — but "no
    // corpus page is NEAR it" does not, so a page in the band is a thing that can happen
    // rather than a thing that cannot. The row would not say so, which is why `wantC` is
    // printed beside `arm`.
    let wantColour: Bool
    switch arm {
    case .shipped: wantColour = shipWantsColour
    case .colour: wantColour = true
    case .grey: wantColour = false
    }
    let armLabel = arm.label(shipWants: shipWantsColour)
    let wantCell = shipWantsColour ? "yes" : "no"
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
    ///
    /// The cells are recorded on the outcome **before** the `printing` guard, so the
    /// self-test — which never prints — still sees the row a corpus run would have
    /// emitted. A declined page publishes its single JPEG, which is why `pubKB` is a
    /// number here while every layer column is a dash.
    func decline(_ why: String, boxes: Int, inkOut: String) {
        outcome.published = now.data.count
        let cells = [label, "\(index + 1)", "\(w)x\(h)", String(format: "%.1f", dpi),
                     route, "\(boxes)", inkOut, kb(now.data.count), "-", "-", "-", "-",
                     "-", "-", "-", "jpeg", "-", "-", why,
                     armLabel, wantCell, kb(now.data.count)]
        outcome.cells = cells
        guard printing else { return }
        emit(cells)
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

    // The app keeps whichever is smaller — `after < before` in `makeSearchablePDF`,
    // a strict `<`, so a tie keeps the JPEG. Three layers are not always cheaper than
    // one image, and a total that assumed they were would describe a route the app
    // declines to take. One expression, read by `kept` and by `pubKB`: the two used to
    // be the same predicate written twice, which is C20's shape.
    let keptLayers = mrc < now.data.count
    outcome.published = keptLayers ? mrc : now.data.count
    // Built above the `printing` guard on purpose. The self-test measures with
    // `printing: false`, so a row constructed after the guard is a row it cannot
    // assert anything about — which is how two columns of `score-threshold-loss`
    // shipped asserted by nothing on 2026-08-26.
    outcome.cells = [
        label, "\(index + 1)", "\(w)x\(h)", String(format: "%.1f", dpi), route,
        "\(boxes.count)", inkOut, kb(now.data.count), kb(maskBytes),
        kb(backgroundBytes), kb(foregroundBytes), kb(mrc),
        String(format: "%.1f", outcome.backgroundFactor),
        String(format: "%.1f", outcome.foregroundFactor),
        String(format: "%.2fx", Double(now.data.count) / Double(max(mrc, 1))),
        keptLayers ? "mrc" : "jpeg",
        decibels(mrcPSNR), decibels(nowPSNR),
        blindStencil ? "blind" : "-",
        armLabel, wantCell, kb(outcome.published)]

    guard printing else { return outcome }

    // ⚠️ **Every failure in here used to be silent, and `dumped += 1` counted the page
    // either way.** `pngData` returning nil, an empty plane set, a `try?` write onto a
    // full or unwritable directory: all three left the run reporting cleanly with an
    // empty directory, over a mode whose whole output is "look at the pages". That is
    // the failure `score-threshold-loss`'s `dumpFailures` list exists for, and this file
    // had the same hole in a different shape — found by C26 sub-step 4's sibling sweep
    // (CONTRIBUTING 4b) while adding `INKDUMP` to `score-text-route`, which is the
    // second tool here that writes images for a reader rather than a number.
    if let dump = dumpDirectory, dumped < 3 {
        let name = "\(label.prefix(24))-p\(index + 1)"
        let nowPlanes = planes(ofData: now.data, width: w, height: h, colour: inColour) ?? []
        var missing: [String] = []
        var offered = 0
        // ⚠️ `where !pixels.isEmpty` was load-bearing and the first version of this fix
        // dropped it. `reconstruction` is legitimately `[]` whenever the guard above fails —
        // a state this file already reports as `-1.00 dB` rather than as an error — and
        // `nowPlanes` is `?? []`. Counting those as MISSING would have exited 6 over a run
        // whose every measurement is sound, which is the mirror image of the defect being
        // fixed. A plane that exists and cannot be written is the failure; a plane that does
        // not exist is an answer. Caught by the adversarial review of this diff.
        for (suffix, pixels) in [("mrc", reconstruction), ("now", nowPlanes),
                                 ("src", source)] where !pixels.isEmpty {
            offered += 1
            guard let data = pngData(planes: pixels, width: w, height: h),
                  (try? data.write(to: URL(fileURLWithPath: dump)
                      .appendingPathComponent("\(name)-\(suffix).png"))) != nil
            else { missing.append(suffix); continue }
        }
        if missing.isEmpty, offered > 0 {
            dumped += 1
        } else {
            dumpMissing += missing.count
            FileHandle.standardError.write(Data(
                ("score-mrc: MRC_DUMP wrote \(offered - missing.count) of \(offered) plane "
                 + "set(s) for \(name); missing \(missing.joined(separator: " "))\n").utf8))
        }
    }

    emit(outcome.cells)
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
        // produces, which is what puts `inkOutsideText` well above the bar — 0.08 when
        // this was written, 0.045 since 2026-08-19 (C26), above both — and keeps R50
        // from firing: the assertion the all-text fixture cannot make. **And the
        // all-text fixture was re-measured against the moved bar rather than assumed.**
        // This self-test exits 4 if that fixture's `inkOut` has drifted up into
        // `[0.045, 0.08)`; it was run and exited 0 on 2026-08-19. `selftest-alltext` is
        // the only fixture in the repository layered with a shrink assertion outside
        // `Tests/main.swift`, so it is the one C26's negative control nearly missed —
        // and nothing would have said so, because the hook does not run a Swift tool's
        // self-test and this file was not staged in that commit until it was.
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
    ///
    /// `arm` defaults to `.shipped` rather than to the run's `MRC_COLOUR`, for the
    /// same reason the three factors default to the shipped constants: a self-test
    /// that inherited a forced arm would have to re-derive `shouldKeepColour`'s answer
    /// to know what to expect, and both fixtures exist to pin that answer.
    func run(_ kind: SelfTestPage, arm: ColourArm = .shipped) -> Outcome? {
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
                       blindStencil: false, arm: arm, printing: false)
    }

    /// One cell of the row `measure` built, by column NAME. Nil when the column is
    /// not in the header at all, which is a different failure from a wrong value and
    /// is reported as one — a renamed column would otherwise make every assertion
    /// below silently pass on an index that no longer means what it says.
    func cell(_ outcome: Outcome, _ column: String) -> String? {
        guard let at = columns.firstIndex(of: column),
              at < outcome.cells.count else { return nil }
        return outcome.cells[at]
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

    // `MRC_PAGES`, as a table rather than as prose, because the review of the commit
    // that added the knob found the one row nobody had thought of — a REPEAT, which
    // measured one page three times into every total under a comment at the sampling
    // site saying this tool does not have A12.8's defect. The parse is a function so
    // this can call it; the first version exited from a top-level closure, and an
    // `exit` is a branch no check can reach twice.
    //
    // The accepted rows matter as much as the refusals (CONTRIBUTING 4d's inverse row):
    // a guard that refused everything would satisfy every refusal below and make the
    // tool useless, and `7,4` is there because the ORDER the caller asked for is kept —
    // this is not a sorted set.
    //
    // ⛔ **The two repeat rows assert `.repeated(n)` and NOT merely "a refusal", and that
    // is the difference between a check and a check that cannot fail.** Against a single
    // `nil` refusal, a sabotage swapping the repeat guard for `numbers.allSatisfy { $0 >=
    // 2 }` refuses `1,1,1` for the wrong reason, accepts `4,7`, and leaves every row here
    // green — measured by the review of this diff. Naming the page makes the mechanism
    // observable: that sabotage now reds row 11, because `.malformed != .repeated(1)`.
    let pagesCases: [(String, PagesParse)] = [
        ("4,7", .ok([4, 7])), ("7,4", .ok([7, 4])), ("1", .ok([1])), (" 4 , 7 ", .ok([4, 7])),
        ("", .malformed), ("4,,7", .malformed), ("0", .malformed), ("-1", .malformed),
        ("x", .malformed), ("4,x", .malformed),
        ("1,1,1", .repeated(1)), ("4,7,4", .repeated(4)),
    ]
    for (raw, want) in pagesCases {
        expect("MRC_PAGES=\(raw) parses to \(want)",
               parseRequestedPages(raw) == want,
               String(describing: parseRequestedPages(raw)))
    }

    // C27 (b), and this pair is about the committed artefacts rather than about
    // today's run. **Four of** `MRC-2026-08-15/`'s five files carry the first nineteen
    // columns in this order; the three C27 added are at the END so that stays true. A
    // future insertion in the middle would compile, print a plausible table, and quietly
    // make every one of those files incomparable by position — which is the failure mode
    // this project has hit three times by counting tabs in a header (T14, A12.3, T18).
    //
    // ⚠️ The name said "five" until 2026-08-26. `mirrored-instrument.tsv` is the fifth
    // and it has an 11-name header over 12-field rows — the T15-era artefact, and the
    // instance of the very defect this check guards, so it was never one of the files
    // this assertion is about.
    expect("MRC-2026-08-15's four 19-column files keep their positions",
           Array(columns.prefix(19)) == ["file", "page", "px", "dpi", "route", "boxes",
                                         "inkOut", "nowKB", "maskKB", "bgKB", "fgKB",
                                         "mrcKB", "bgF", "fgF", "ratio", "kept",
                                         "mrcPSNR", "nowPSNR", "note"],
           columns.prefix(19).joined(separator: " "))
    expect("C27's three columns are appended, not inserted",
           Array(columns.suffix(3)) == ["arm", "wantC", "pubKB"],
           columns.suffix(3).joined(separator: " "))

    // The `arm` column's four strings, from the function that builds them, before any
    // fixture is rendered. `ship-colour` against `force-colour` is the pair a reader
    // most needs kept apart: both describe a colour row and only one of them is the
    // app's own answer, so a label that collapsed them would turn a price into a
    // claim about what the app does.
    expect("the shipped arm names the verdict it inherited",
           ColourArm.shipped.label(shipWants: true) == "ship-colour"
               && ColourArm.shipped.label(shipWants: false) == "ship-grey",
           ColourArm.shipped.label(shipWants: true) + " / "
               + ColourArm.shipped.label(shipWants: false))
    expect("a forced arm says so whichever way the verdict went",
           ColourArm.colour.label(shipWants: false) == "force-colour"
               && ColourArm.colour.label(shipWants: true) == "force-colour"
               && ColourArm.grey.label(shipWants: true) == "force-grey"
               && ColourArm.grey.label(shipWants: false) == "force-grey",
           [ColourArm.colour.label(shipWants: false),
            ColourArm.colour.label(shipWants: true),
            ColourArm.grey.label(shipWants: true),
            ColourArm.grey.label(shipWants: false)].joined(separator: " / "))

    // Fixture 1 — R50 fires. The assertion this tool exists to keep: at the shipped
    // `2`, which is what the mirrored copy used unconditionally, an all-text page
    // must come back shrunk by `textPageBackgroundDownsample`. Reporting 2 and 4
    // here was the whole 10.5–18.3x overstatement.
    //
    // ⚠️ **WHAT THIS FIXTURE DOES NOT COVER, MEASURED 2026-08-22.** C28 wired a third
    // term into `pageIsAllText()` that day, and this self-test — the only fixture outside
    // `Tests/main.swift` asserting the shrink verdict, and gated by nothing — was named as
    // the place it might have gone red unnoticed. It did not: against the wired build the
    // whole self-test exits 0. But it is green **by construction rather than by
    // measurement**. `selftest-alltext`'s `inkOutsideText` is **exactly 0.0**, read to ten
    // decimal places by a probe that forced this very assertion to print it — and that
    // quotient being 0 is enough, because `inkOutsideText` counts `outside` only over the
    // pixels it also counts in `total`, so a zero quotient means a zero numerator and the
    // `total == 0` branch returns 0 with an empty numerator too. The shape term recomputes
    // that same numerator over the same window with the same threshold and region, so its
    // own `guard outside > 0` answers 0 before it labels anything, and that answer cannot
    // change at any value of any of the five shape constants. So this fixture pins the
    // guard's FIRST term, is silent about the second (nothing here distinguishes a
    // pale-drawing verdict), and is blind by construction to the third. The third is
    // pinned in `Tests/main.swift`, which the hook runs. `BUGS.md` C28
    // `#### The owed fixture`.
    if let text = run(.allText), expectMeasured(.allText, text) {
        expect("the all-text fixture's ink is all text",
               text.inkOutsideText >= 0
                   && text.inkOutsideText < Flattener.textPageInkOutsideThreshold,
               String(format: "inkOutsideText %.4f, threshold %.3f", text.inkOutsideText,
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

        // C27 (b), read out of the row `measure` built rather than off the Outcome, so
        // the assertion covers the cell a corpus file would carry and not just the
        // field behind it.
        expect("the all-text fixture's own verdict is grey",
               !text.shipWantsColour && cell(text, "wantC") == "no"
                   && cell(text, "arm") == "ship-grey",
               "wantC \(cell(text, "wantC") ?? "absent"), "
                   + "arm \(cell(text, "arm") ?? "absent")")
        // `pubKB` is the number C27 (b) is a price in, so it is asserted against the
        // rule rather than against a literal: on this fixture R50's shrink fires, so
        // the three layers must be the cheaper side and `pubKB` must be `mrcKB`.
        if let mrc = text.mrc {
            expect("an all-text page publishes its layers, and pubKB is them",
                   text.published == mrc && text.published < text.now
                       && cell(text, "pubKB") == kb(mrc)
                       && cell(text, "kept") == "mrc",
                   "published \(text.published), mrc \(mrc), now \(text.now), "
                       + "pubKB \(cell(text, "pubKB") ?? "absent")")
        }

        // The forcing arm, in the direction C27 needs: a page the app publishes in
        // grey, priced in colour. This is the whole of `MRC_COLOUR=colour`, and it is
        // asserted on a fixture rather than reasoned about because the arm has to reach
        // `renderRGB`, `jpegRGB` AND `mrcLayers(inColour:)` — three places it could
        // fall through to grey without saying so, each of which is a real production
        // path (`flatten`'s comment: "colour is an improvement on grey, not a
        // requirement").
        if let forced = run(.allText, arm: .colour), forced.isPictureRoute {
            expect("forcing colour on a grey page reaches the colour route",
                   forced.isColour, "it came back grey — the arm did not take")
            expect("a forced row still reports the page's own verdict",
                   !forced.shipWantsColour && cell(forced, "wantC") == "no"
                       && cell(forced, "arm") == "force-colour"
                       && cell(forced, "route") == "colour",
                   "wantC \(cell(forced, "wantC") ?? "absent"), "
                       + "arm \(cell(forced, "arm") ?? "absent"), "
                       + "route \(cell(forced, "route") ?? "absent")")
            // The direction of the price, which is the finding the corpus run reports.
            // Three planes of a page whose planes are nearly identical cannot be
            // cheaper than one of them; if this ever went the other way the tool would
            // be measuring something else.
            expect("keeping colour on a grey page costs bytes",
                   forced.published > text.published,
                   "\(forced.published) forced against \(text.published) shipped")
        }
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
               String(format: "inkOutsideText %.4f, threshold %.3f", plate.inkOutsideText,
                      Flattener.textPageInkOutsideThreshold))
        expect("a picture page keeps the caller's background factor",
               Int(plate.backgroundFactor.rounded()) == Flattener.mrcBackgroundDownsample,
               String(format: "%.1fx, expected %dx", plate.backgroundFactor,
                      Flattener.mrcBackgroundDownsample))
        expect("a picture page keeps the caller's foreground factor",
               Int(plate.foregroundFactor.rounded()) == Flattener.mrcForegroundDownsample,
               String(format: "%.1fx, expected %dx", plate.foregroundFactor,
                      Flattener.mrcForegroundDownsample))

        // C27 (b), the other direction. This fixture is the one page in the tool whose
        // shipped verdict is `yes`, so it is the only place `ship-colour` can be pinned
        // — and `MRC_COLOUR=grey` on it is the reverse price: what the app already
        // spends to keep a colour page's colour.
        expect("the colour fixture's own verdict is colour",
               plate.shipWantsColour && cell(plate, "wantC") == "yes"
                   && cell(plate, "arm") == "ship-colour",
               "wantC \(cell(plate, "wantC") ?? "absent"), "
                   + "arm \(cell(plate, "arm") ?? "absent")")
        if let forced = run(.colourPlate, arm: .grey), forced.isPictureRoute {
            expect("forcing grey on a colour page reaches the grey route",
                   !forced.isColour, "it came back colour — the arm did not take")
            expect("a forced-grey row still reports the page's own verdict",
                   forced.shipWantsColour && cell(forced, "wantC") == "yes"
                       && cell(forced, "arm") == "force-grey"
                       && cell(forced, "route") == "grey",
                   "wantC \(cell(forced, "wantC") ?? "absent"), "
                       + "arm \(cell(forced, "arm") ?? "absent"), "
                       + "route \(cell(forced, "route") ?? "absent")")
            expect("the colour this page already keeps costs bytes",
                   forced.published < plate.published,
                   "\(forced.published) grey against \(plate.published) as shipped")
        }
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
// C27 (b). Named for the same reason MRC_BG's line is: a file of colour rows with no
// record that the colour was FORCED reads as the app's own output. The `arm` column
// says it per row as well, because a reader who greps out a row loses the banner.
if colourArm != .shipped {
    print("# MRC_COLOUR=\(colourArm.rawValue) (C27 b): every picture page is forced to"
          + " that colour decision. `wantC` is what `shouldKeepColour` answered")
}
if let requested = requestedPages {
    print("# MRC_PAGES=\(requested.map(String.init).joined(separator: ","))"
          + " — these pages of EVERY document below, not the three-page sample")
}
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
    //
    // ⚠️ **That sentence covers the SAMPLE only, and it read as though it covered the
    // line below it for one commit.** `MRC_PAGES` takes the caller's list verbatim, so
    // `MRC_PAGES=1,1,1` DID have exactly A12.8's defect until `parseRequestedPages`
    // started refusing repeats — the guard is what makes the claim true of both arms of
    // this `??`, not the arithmetic above, which says nothing about a list nobody
    // derived from `pageCount`.
    let indices = requestedPages?.map { $0 - 1 }
        ?? (document.pageCount <= 4
            ? Array(0..<document.pageCount)
            : [document.pageCount / 3, document.pageCount / 2,
               document.pageCount * 3 / 4])
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
        // `outcome.published`, not `min(mrc, now)` recomputed here: the column and the
        // total are one definition now, so a reader can add up `pubKB` and get this
        // number. They agreed in bytes before — `min` and the strict `<` differ only on
        // a tie, where both give the same count — but they were two expressions for one
        // rule, which is the shape C20 was.
        if let mrc = outcome.mrc {
            layered += 1
            mrcTotal += mrc
            publishedTotal += outcome.published
            if mrc >= outcome.now { mrcLostTo += 1 }
        } else {
            declined += 1
            publishedTotal += outcome.published
        }
    }
}

// C27 (b), and this label was MISSING for one commit — found by the adversarial review
// of the commit that added the arm. The three summary lines printed identically on a
// forced run and on a shipped one, and `as published` is the line whose own comment says
// it is the number to quote, so a pasted total carried no record of which decision
// produced it. The `arm` COLUMN's rationale — "a reader who greps out a row loses the
// banner" — applies one level up as well: a reader who pastes the summary loses the
// preamble. Suffixed rather than prefixed so the `=== N picture pages` opening that
// `fault-inject.sh`'s `mrc_refuses` greps for is byte-identical.
let armBanner = colourArm == .shipped
    ? ""
    : "   [MRC_COLOUR=\(colourArm.rawValue) — FORCED, not the app's own decision]"
print("\n=== \(pages) picture pages: \(layered) layered, \(declined) declined ==="
      + (unreadable > 0 ? "   \(unreadable) document(s) would not open" : "")
      + (refused > 0 ? "   \(refused) page(s) could not be measured — see stderr" : "")
      + armBanner)
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
// MRC_DUMP's own verdict, and it is an exit code rather than a line, because the mode
// exists to be looked at and a caller that greps the totals would never see a warning.
// A run that asked for a dump and reached a dumpable page must have written one.
if dumpDirectory != nil {
    let silent = dumped == 0 && layered > 0
    print("MRC_DUMP: \(dumped) page(s) written in full, \(dumpMissing) plane(s) missing"
          + (silent ? "  ⚠️ NOTHING was written over \(layered) layered page(s) — an "
                      + "instrument failure, not an empty answer" : ""))
    // `stop` rather than `exit`, because the top-level `defer` that removes `scratch`
    // does not run through `exit` — the reason `stop` exists at all, and this is the
    // fifth caller.
    //
    // ⚠️ **6, not 4.** This file already spends 4 on "the self-test failed, so nothing was
    // measured" and 5 on a drifted row width. Reusing 4 would make a run whose every
    // measurement is sound but whose dump lost a plane indistinguishable from a run that
    // measured nothing at all — the same conflation `score-text-route`'s `n/a`-versus-`FAIL`
    // distinction exists to prevent, and a `sweep`-style driver keying on the code would
    // discard a good corpus row for a cosmetic failure.
    if dumpMissing > 0 || silent {
        stop("score-mrc: MRC_DUMP did not write what it promised\n", code: 6)
    }
}
