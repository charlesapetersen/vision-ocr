// How crooked is the material, really? — and can the estimator be trusted to say?
//
//   score-skew --validate <pdf>...            plant angles at the pixel level
//   score-skew [--pages N] [--dpi N] <pdf>... measure, one row per page
//   score-skew --summary ...                  …and a distribution at the end
//
// **This exists because deskew was declined once and the reason was the
// instrument, not the feature.** `FEATURES.md` item 2: the previous estimator
// failed its own self-test on 55 of 232 documents and there was no way to know
// which. The rule that came out of it is that a wrong angle on a straight page
// moves it *out* of the flat zone and into the band where text is lost, so an
// estimator that cannot abstain must not be allowed near archival pages.
//
// So this harness answers two questions in one run, and the first one matters
// more:
//
//  1. **Does the estimator recover an angle that was put there on purpose?**
//     `--validate` renders each page, rotates the *pixels* by a known angle,
//     re-measures, and reports the error. Pixel-level, because `Deskew.selfTest`
//     plants in the point cloud — cheap enough to run on every page, but it
//     tests the search rather than the rasteriser, and a shortcut that flatters
//     itself is this project's most repeated failure.
//  2. **How much skew is actually out there**, per page, with the abstentions
//     counted rather than dropped. A sweep that silently skips the pages it
//     cannot measure reports the skew of the pages that were easy.
//
// Rendering is `Flattener.renderGrey` at the crop box, the same call the
// no-rebuild recognition path makes, so what is measured is what Vision would
// be handed.
import Foundation
import PDFKit
import CoreGraphics

// **The estimator lives in this file, not in `Sources/`.** Deskew was measured
// and refused (see below and FEATURES.md item 2), so the app does not use it and
// shipping it in `Sources/` would be dead code in the binary — the same thing
// `Runner.searchPaths` had become. It stays here because the *measurement* is
// worth keeping: it is validated, it produced the library-wide skew distribution,
// and anyone revisiting the feature should start from a working instrument rather
// than rebuild one. One copy, in the one place that uses it.
//
// What it found, in one line: correcting the skew **loses** text, and loses more
// the more crooked the page — the opposite of the feature's premise.

/// How crooked a scanned page is, measured from its own text lines.
///
/// **Deskew was declined once, on measurement** (`FEATURES.md` item 2), and the
/// numbers that declined it are worth having before touching this file: over 176
/// corpus documents the median page skew was 0.10°, p95 0.36°, and 89.9% of pages
/// sat below 0.25° where there is no measurable recognition loss. The prize was
/// roughly 0.5–1% of corpus characters.
///
/// What killed it was not the size of the prize. It was that **the estimator
/// failed its own self-test on 24% of documents**, and a wrong estimate on a
/// straight page moves it *out* of the flat zone and into the band where text is
/// actually lost — the feature causing the exact damage it exists to prevent.
///
/// So this file's first responsibility is not accuracy. It is **knowing when to
/// say nothing**: `estimate` returns nil for any page whose ink does not carry a
/// detectable line structure, and a caller that gets nil must leave the page
/// alone. An abstention is a correct answer here; a confident wrong one is the
/// failure mode that matters.
enum Deskew {

    /// A measured skew, and how much the measurement is worth.
    struct Estimate {
        /// Degrees the page's text lines are rotated. Positive means the lines
        /// rise to the right, which is what `rotated(by:)` produces for a
        /// positive angle — the convention is pinned by "a planted angle comes
        /// back" in the suite rather than reasoned about, because getting it
        /// backwards doubles the skew instead of removing it.
        let degrees: Double
        /// How much better the best angle scored than a typical one, 0...1. A
        /// page of prose peaks hard; a photograph, a blank page or a table of
        /// figures does not peak at all.
        let confidence: Double
        /// Baseline points the estimate was computed from.
        let samples: Int
    }

    /// The widest skew this looks for, in degrees either way.
    ///
    /// Deliberately narrow. Beyond a few degrees a page is not a crooked scan,
    /// it is a rotated one, and Vision reads all four orientations perfectly
    /// well already — a fact this project established after building a whole
    /// feature for the opposite belief (HANDOFF, "Verify a diagnosis before
    /// believing it"). Widening this would mostly buy false positives on pages
    /// whose real structure is diagonal, like a title page or a plate.
    static let searchDegrees = 4.0

    /// Coarse sweep, then a refinement around the winner.
    static let coarseStep = 0.25
    static let fineStep = 0.02

    /// Below this the page is not saying anything about its own angle.
    ///
    /// **Measured, not chosen** — see `Tools/score-skew.swift`, which prints the
    /// distribution this was read off. The self-test is the real gate; this only
    /// keeps obviously structureless pages out of the sample before it runs.
    static let minimumConfidence = 0.35

    /// Fewer baseline points than this and there is not enough page to measure.
    static let minimumSamples = 400

    /// The angle planted by `selfTest`, and how far the recovered angle may sit
    /// from where it was put.
    ///
    /// 1.1° because it has to be far outside the range real pages sit in — a
    /// page that genuinely is at 1.1° would otherwise pass the test by accident.
    static let plantedDegrees = 1.1
    static let plantedTolerance = 0.25

    // MARK: - Measuring

    /// Baseline points: the bottom pixel of each vertical run of ink.
    ///
    /// **Not every ink pixel.** A projection profile over all ink is dominated by
    /// whatever is solid — a photograph, a rule, a block of heavy display type —
    /// and those have no line rhythm to find. The bottom edge of each run
    /// approximates the baselines, and reduces a solid block to its outline, so
    /// a plate stops shouting over the caption underneath it.
    static func baselinePoints(grey: [UInt8], width: Int, height: Int) -> [(x: Double, y: Double)] {
        guard width > 1, height > 1, grey.count >= width * height else { return [] }
        let threshold = Flattener.otsuThreshold(of: grey)
        var points: [(x: Double, y: Double)] = []
        points.reserveCapacity(width * 4)
        for x in 0..<width {
            var inRun = false
            for y in 0..<height {
                let isInk = grey[y * width + x] <= threshold
                if isInk {
                    inRun = true
                } else if inRun {
                    // y - 1 was the last ink row of this run.
                    points.append((x: Double(x), y: Double(y - 1)))
                    inRun = false
                }
            }
            if inRun { points.append((x: Double(x), y: Double(height - 1))) }
        }
        return points
    }

    /// How peaked the horizontal projection is when the page is sheared by
    /// `degrees`. Higher means the baselines line up better.
    ///
    /// Sheared, not rotated: shifting each point by `x * tan(θ)` is the same
    /// projection a rotation would give, without resampling the image once per
    /// angle. For the angles this searches the difference is far below a pixel.
    static func alignmentScore(_ points: [(x: Double, y: Double)],
                               degrees: Double, height: Int) -> Double {
        guard !points.isEmpty else { return 0 }
        let slope = tan(degrees * .pi / 180)
        // One bin per pixel row. The range is taken from the sheared values
        // themselves rather than from `height`, so the shear cannot push points
        // off either end of the histogram and quietly lose them.
        var lowest = Double.greatestFiniteMagnitude, highest = -Double.greatestFiniteMagnitude
        var shifted = [Double](repeating: 0, count: points.count)
        for i in points.indices {
            // `+`, and the sign is not obvious: a bitmap's row 0 is the visual
            // *top* while `rotated(by:)` turns the page in CoreGraphics'
            // bottom-left space, so the two conventions are mirror images. Got
            // backwards first time — every planted angle came back with the
            // right magnitude and the wrong sign, which would have *doubled*
            // every page's skew instead of removing it. Pinned by the
            // pixel-level plant in `Tools/score-skew.swift --validate` and by
            // "a planted angle comes back with its sign" in the suite.
            let v = points[i].y + points[i].x * slope
            shifted[i] = v
            if v < lowest { lowest = v }
            if v > highest { highest = v }
        }
        guard highest > lowest else { return 0 }
        let bins = max(Int(highest - lowest) + 1, 1)
        var histogram = [Double](repeating: 0, count: bins)
        for v in shifted {
            let index = min(max(Int(v - lowest), 0), bins - 1)
            histogram[index] += 1
        }
        // Sum of squares: the standard profile-peakedness measure. Normalised by
        // the point count so pages of different density are comparable, and by
        // the bin count so a taller page does not score higher for being taller.
        var sum = 0.0
        for v in histogram { sum += v * v }
        let n = Double(points.count)
        return sum / (n * n / Double(bins))
    }

    /// The page's skew, or nil if the page will not say.
    static func estimate(grey: [UInt8], width: Int, height: Int) -> Estimate? {
        let points = baselinePoints(grey: grey, width: width, height: height)
        return estimate(points: points, height: height)
    }

    /// The same, from a point cloud already extracted — which is what makes the
    /// self-test cheap enough to run on every page.
    static func estimate(points: [(x: Double, y: Double)], height: Int) -> Estimate? {
        guard points.count >= minimumSamples else { return nil }

        var scores: [(degrees: Double, score: Double)] = []
        var degrees = -searchDegrees
        while degrees <= searchDegrees + 1e-9 {
            scores.append((degrees, alignmentScore(points, degrees: degrees, height: height)))
            degrees += coarseStep
        }
        guard let best = scores.max(by: { $0.score < $1.score }) else { return nil }

        // How much better the winner is than a typical angle. A flat curve — a
        // photograph, a blank page — lands near zero and is refused.
        let sorted = scores.map(\.score).sorted()
        let median = sorted[sorted.count / 2]
        guard best.score > 0, median > 0 else { return nil }
        let confidence = max(0, min(1, (best.score - median) / best.score))
        guard confidence >= minimumConfidence else { return nil }

        // Refine around the coarse winner.
        var fine = best
        var d = best.degrees - coarseStep
        while d <= best.degrees + coarseStep + 1e-9 {
            let score = alignmentScore(points, degrees: d, height: height)
            if score > fine.score { fine = (d, score) }
            d += fineStep
        }
        return Estimate(degrees: fine.degrees, confidence: confidence, samples: points.count)
    }

    /// Does this page's ink actually carry a recoverable angle?
    ///
    /// Plants a known rotation in the point cloud and asks the estimator to find
    /// it. A page whose score curve is flat cannot be moved by planting, so it
    /// fails — which is the whole point. **This is the gate, not the confidence
    /// number**: the previous attempt at this feature was refused because its
    /// estimator failed exactly this test on 24% of the corpus and had no way to
    /// tell which 24%.
    ///
    /// It plants in the *points* rather than re-rendering the page, so it can run
    /// on every page for the price of one more sweep. That means it tests the
    /// search rather than the rasteriser — but the failure it exists to catch is
    /// a page with no line rhythm, and that shows up identically either way.
    /// `Tools/score-skew.swift` plants at the pixel level as well, on a sample,
    /// to check this shortcut does not flatter itself.
    static func selfTest(points: [(x: Double, y: Double)], height: Int,
                         measured: Double) -> Bool {
        // Minus, to match the shear above: transforming the cloud by
        // `y - x·tan(p)` is what moves the recovered angle by *plus* p.
        let slope = tan(plantedDegrees * .pi / 180)
        let planted = points.map { (x: $0.x, y: $0.y - $0.x * slope) }
        guard let recovered = estimate(points: planted, height: height) else { return false }
        return abs(recovered.degrees - (measured + plantedDegrees)) <= plantedTolerance
    }

    /// Measure and validate in one call. nil means "leave this page alone".
    static func trustworthyEstimate(grey: [UInt8], width: Int, height: Int) -> Estimate? {
        let points = baselinePoints(grey: grey, width: width, height: height)
        guard let estimate = estimate(points: points, height: height),
              selfTest(points: points, height: height, measured: estimate.degrees)
        else { return nil }
        return estimate
    }

    // MARK: - Correcting

    /// The page, straightened — **for the recogniser only.**
    ///
    /// The published page is never rotated. That is the whole reason this feature
    /// is defensible at all: rotating what the user gets back alters an
    /// irreplaceable document to fix something a reader cannot see (R13's
    /// territory), while rotating only the bitmap handed to Vision is invisible
    /// unless it works. The text layer's coordinates are computed from the page
    /// the app draws, not from this image, so a wrong estimate here costs
    /// recognition quality and nothing else.
    static func rotated(_ image: CGImage, byDegrees degrees: Double) -> CGImage? {
        guard degrees != 0, degrees.isFinite else { return image }
        let radians = degrees * .pi / 180
        let w = Double(image.width), h = Double(image.height)
        let wide = abs(w * cos(radians)) + abs(h * sin(radians))
        let high = abs(w * sin(radians)) + abs(h * cos(radians))
        // The same bound the rest of the pipeline works to: a buffer that cannot
        // be allocated is a crash, not a catchable error (R24).
        guard wide * high <= Double(Flattener.maximumPageMegapixels) * 1_000_000 else {
            return nil
        }
        let W = max(Int(wide.rounded()), 1), H = max(Int(high.rounded()), 1)
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: W, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        // Paper, not black: the corners exposed by the rotation must read as
        // page, or every deskewed page gains four black triangles for Vision to
        // wonder about.
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.translateBy(x: wide / 2, y: high / 2)
        ctx.rotate(by: radians)
        ctx.translateBy(x: -w / 2, y: -h / 2)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}


setvbuf(stdout, nil, _IOLBF, 0)

var pages = 3
var dpi = 150.0
var validate = false
var recover = false
var recoverRender = false
var summary = false
var files: [String] = []

var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
    case "--pages": pages = Int(arguments.removeFirst()) ?? 3
    case "--dpi": dpi = Double(arguments.removeFirst()) ?? 150
    case "--validate": validate = true
    case "--summary": summary = true
    case "--recover": recover = true
    case "--recover-render": recoverRender = true
    default: files.append(argument)
    }
}
guard !files.isEmpty else {
    fputs("usage: score-skew [--pages N] [--dpi N] [--validate] [--summary] <pdf>...\n", stderr)
    exit(2)
}

/// A page rendered the way recognition would see it.
func render(_ page: PDFPage) -> (grey: [UInt8], width: Int, height: Int)? {
    let box = Flattener.displayBox(of: page)
    let scale = dpi / 72.0
    let wide = (box.width * scale).rounded(), high = (box.height * scale).rounded()
    guard wide.isFinite, high.isFinite, wide >= 16, high >= 16,
          wide * high <= Double(Flattener.maximumPageMegapixels) * 1_000_000
    else { return nil }
    let w = Int(wide), h = Int(high)
    guard let grey = Flattener.renderGrey(page, box: box, scale: scale,
                                          width: w, height: h, from: .cropBox)
    else { return nil }
    return (grey, w, h)
}

/// A grey buffer as a CGImage, which is what Vision and `Deskew.rotated` take.
func greyImage(_ grey: [UInt8], width: Int, height: Int) -> CGImage? {
    guard let provider = CGDataProvider(data: Data(grey) as CFData) else { return nil }
    return CGImage(width: width, height: height, bitsPerComponent: 8,
                   bitsPerPixel: 8, bytesPerRow: width,
                   space: CGColorSpaceCreateDeviceGray(),
                   bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                   decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

/// Grey buffer -> CGImage -> rotated -> grey buffer, so a planted angle goes
/// through the same resampling a real crooked scan went through.
func rotatedGrey(_ grey: [UInt8], width: Int, height: Int,
                 degrees: Double) -> (grey: [UInt8], width: Int, height: Int)? {
    guard let image = greyImage(grey, width: width, height: height),
          let turned = Deskew.rotated(image, byDegrees: degrees)
    else { return nil }
    let w = turned.width, h = turned.height
    var out = [UInt8](repeating: 255, count: w * h)
    let ok = out.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        ctx.draw(turned, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    return ok ? (out, w, h) : nil
}

func samplePages(_ document: PDFDocument) -> [Int] {
    let count = document.pageCount
    guard count > 0 else { return [] }
    if count <= pages { return Array(0..<count) }
    // Spread through the document rather than taking the front: front matter is
    // title pages and plates, which is not what most of a book looks like.
    return (0..<pages).map { 1 + $0 * (count - 2) / max(pages - 1, 1) }
        .map { min(max($0, 0), count - 1) }
}

if validate {
    // Plant, measure, report the error. Anything the estimator declined to
    // measure is reported as an abstention, not skipped.
    print("file\tpage\tplanted\tmeasured\terror\tconfidence\tverdict")
    let plants = [-2.0, -0.75, 0.0, 0.75, 2.0]
    var errors: [Double] = []
    var abstained = 0, measured = 0, wrong = 0
    for path in files {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { continue }
        let name = (path as NSString).lastPathComponent
        for index in samplePages(document) {
            guard let page = document.page(at: index), let base = render(page) else { continue }
            // The page's own skew, so a planted angle can be checked against
            // where it actually started rather than against zero.
            let start = Deskew.trustworthyEstimate(grey: base.grey, width: base.width,
                                                   height: base.height)?.degrees
            for plant in plants {
                guard let turned = rotatedGrey(base.grey, width: base.width,
                                               height: base.height, degrees: plant)
                else { continue }
                let estimate = Deskew.trustworthyEstimate(grey: turned.grey, width: turned.width,
                                                          height: turned.height)
                guard let estimate, let start else {
                    abstained += 1
                    print("\(name)\t\(index + 1)\t\(plant)\t—\t—\t—\tabstained")
                    continue
                }
                let expected = start + plant
                let error = estimate.degrees - expected
                measured += 1
                errors.append(abs(error))
                if abs(error) > 0.25 { wrong += 1 }
                print(String(format: "%@\t%d\t%.2f\t%.3f\t%+.3f\t%.2f\t%@",
                             name, index + 1, plant, estimate.degrees, error,
                             estimate.confidence, abs(error) <= 0.25 ? "ok" : "WRONG"))
            }
        }
    }
    let sorted = errors.sorted()
    print("\n=== validation ===")
    print("  measured    \(measured)")
    print("  abstained   \(abstained)   (\(measured + abstained) attempts)")
    print("  wrong >0.25°\(wrong)")
    if !sorted.isEmpty {
        print(String(format: "  median error %.3f°   p95 %.3f°   worst %.3f°",
                     sorted[sorted.count / 2], sorted[min(sorted.count * 95 / 100,
                                                          sorted.count - 1)], sorted.last!))
    }
    // The number that decides the feature: of the pages it was willing to
    // measure, how many did it get right? An estimator that abstains often but
    // is right when it speaks is usable. One that speaks and is wrong is not.
    if measured > 0 {
        print(String(format: "  correct when it spoke: %.1f%%",
                     100.0 * Double(measured - wrong) / Double(measured)))
    }
    exit(wrong == 0 ? 0 : 1)
}

/// The page rasterised **once**, with a rotation folded into the drawing
/// transform, straight from the PDF's vector content.
///
/// This is the fair comparison, and the first version of `--recover` was not it.
/// Rotating an already-rendered bitmap resamples it a second time, so that
/// measurement compared a clean render against a twice-sampled one and charged
/// the difference to deskew. The 2026-08-12 session hit exactly this and said so:
/// "one sampling at the angle, drawn through a rotated CTM, so there is no
/// resampling on one side of the comparison and not the other".
///
/// It is also the only shape a production deskew could take without paying that
/// cost — which makes this both the honest measurement and a test of the design.
func renderRotated(_ page: PDFPage, degrees: Double) -> (grey: [UInt8], width: Int, height: Int)? {
    let box = Flattener.displayBox(of: page)
    let scale = dpi / 72.0
    let w = box.width * scale, h = box.height * scale
    let radians = degrees * .pi / 180
    let cw = abs(w * cos(radians)) + abs(h * sin(radians))
    let ch = abs(w * sin(radians)) + abs(h * cos(radians))
    guard cw.isFinite, ch.isFinite, cw >= 16, ch >= 16,
          cw * ch <= Double(Flattener.maximumPageMegapixels) * 1_000_000 else { return nil }
    let W = Int(cw.rounded()), H = Int(ch.rounded())
    var buffer = [UInt8](repeating: 255, count: W * H)
    let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: W, height: H,
                                  bitsPerComponent: 8, bytesPerRow: W,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.translateBy(x: cw / 2, y: ch / 2)
        ctx.rotate(by: radians)
        ctx.translateBy(x: -w / 2, y: -h / 2)
        ctx.scaleBy(x: scale, y: scale)
        guard let cgPage = page.pageRef else {
            page.draw(with: .cropBox, to: ctx)
            return true
        }
        ctx.concatenate(cgPage.getDrawingTransform(
            .cropBox, rect: CGRect(origin: .zero, size: box.size),
            rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(cgPage)
        return true
    }
    return ok ? (buffer, W, H) : nil
}

if recoverRender {
    let settings = Prefs.Snapshot(
        mode: .searchablePDF, textFormat: .text, besideOriginal: false, useJBIG2: false,
        photoDetail: .balanced, joinHyphenated: false, fast: false, languages: "",
        languageCorrection: true, confidence: 0.0, pdfDPIAuto: true, pdfDPI: 0,
        password: "", customWords: "", minTextHeightOn: false, minTextHeight: 0.0)
    func characters(_ grey: [UInt8], _ w: Int, _ h: Int) -> Int? {
        guard let image = greyImage(grey, width: w, height: h),
              let observations = try? Recogniser.recognise(image, settings: settings)
        else { return nil }
        return observations.reduce(0) { $0 + $1.text.count }
    }
    struct Bucket { var pages = 0, before = 0, after = 0, better = 0, worse = 0 }
    var buckets: [String: Bucket] = [:]
    let order = ["< 0.25 (control)", "0.25-0.5", "0.5-1.0", ">= 1.0"]
    func label(_ a: Double) -> String {
        a < 0.25 ? order[0] : a < 0.5 ? order[1] : a < 1.0 ? order[2] : order[3]
    }
    print("file\tpage\tdegrees\tbefore\tafter\tdelta")
    for path in files {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { continue }
        let name = (path as NSString).lastPathComponent
        for index in samplePages(document) {
            guard let page = document.page(at: index), let base = render(page),
                  let estimate = Deskew.trustworthyEstimate(grey: base.grey, width: base.width,
                                                            height: base.height),
                  let before = characters(base.grey, base.width, base.height),
                  let turned = renderRotated(page, degrees: -estimate.degrees),
                  let after = characters(turned.grey, turned.width, turned.height)
            else { continue }
            let key = label(abs(estimate.degrees))
            var bucket = buckets[key] ?? Bucket()
            bucket.pages += 1; bucket.before += before; bucket.after += after
            if after > before { bucket.better += 1 } else if after < before { bucket.worse += 1 }
            buckets[key] = bucket
            print(String(format: "%@\t%d\t%+.3f\t%d\t%d\t%+d",
                         name, index + 1, estimate.degrees, before, after, after - before))
        }
    }
    print("\n=== deskew folded into the render: one resampling on each side ===")
    print("bucket             pages   before      after      delta     better/worse")
    for key in order {
        guard let b = buckets[key], b.pages > 0 else { continue }
        let delta = b.after - b.before
        let pct = b.before > 0 ? 100.0 * Double(delta) / Double(b.before) : 0
        print(String(format: "%-18s %5d %10d %10d %+9d %+6.2f%%   %d/%d",
                     (key as NSString).utf8String!, b.pages, b.before, b.after,
                     delta, pct, b.better, b.worse))
    }
    exit(0)
}

if recover {
    // **The measurement that decides the feature.** Everything else here is
    // about whether the angle can be measured; this is whether correcting it
    // recovers any text — which is the only reason to do it at all.
    //
    // Every page the estimator was willing to measure is put through, straight
    // ones included. That is the inverse row (CONTRIBUTING 4d): the failure that
    // killed deskew last time was damage to pages that were already fine, so a
    // run that only looked at crooked pages would be measuring the half that
    // cannot lose.
    let settings = Prefs.Snapshot(
        mode: .searchablePDF, textFormat: .text, besideOriginal: false, useJBIG2: false,
        photoDetail: .balanced, joinHyphenated: false, fast: false, languages: "",
        languageCorrection: true, confidence: 0.0, pdfDPIAuto: true, pdfDPI: 0,
        password: "", customWords: "", minTextHeightOn: false, minTextHeight: 0.0)

    func characters(_ image: CGImage) -> Int? {
        guard let observations = try? Recogniser.recognise(image, settings: settings)
        else { return nil }
        return observations.reduce(0) { $0 + $1.text.count }
    }

    struct Bucket { var pages = 0, before = 0, after = 0, better = 0, worse = 0 }
    var buckets: [String: Bucket] = [:]
    let order = ["< 0.25 (control)", "0.25-0.5", "0.5-1.0", ">= 1.0"]
    func label(_ a: Double) -> String {
        a < 0.25 ? order[0] : a < 0.5 ? order[1] : a < 1.0 ? order[2] : order[3]
    }

    print("file\tpage\tdegrees\tbefore\tafter\tdelta\tresidual")
    for path in files {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { continue }
        let name = (path as NSString).lastPathComponent
        for index in samplePages(document) {
            guard let page = document.page(at: index), let r = render(page),
                  let estimate = Deskew.trustworthyEstimate(grey: r.grey, width: r.width,
                                                            height: r.height),
                  let image = greyImage(r.grey, width: r.width, height: r.height),
                  let before = characters(image)
            else { continue }

            // Minus the measured angle: a page whose lines rise to the right is
            // straightened by turning it back. Getting this backwards doubles
            // the skew, which is why `residual` below is printed — it is the
            // estimator re-run on the corrected page, and it must come back near
            // zero. It is the same check that caught the sign error in the
            // shear, and it is cheap enough to leave in.
            guard let corrected = rotatedGrey(r.grey, width: r.width, height: r.height,
                                              degrees: -estimate.degrees),
                  let correctedImage = greyImage(corrected.grey, width: corrected.width,
                                                 height: corrected.height),
                  let after = characters(correctedImage)
            else { continue }
            let residual = Deskew.trustworthyEstimate(grey: corrected.grey,
                                                      width: corrected.width,
                                                      height: corrected.height)?.degrees

            let key = label(abs(estimate.degrees))
            var bucket = buckets[key] ?? Bucket()
            bucket.pages += 1; bucket.before += before; bucket.after += after
            if after > before { bucket.better += 1 } else if after < before { bucket.worse += 1 }
            buckets[key] = bucket
            print(String(format: "%@\t%d\t%+.3f\t%d\t%d\t%+d\t%@",
                         name, index + 1, estimate.degrees, before, after, after - before,
                         residual.map { String(format: "%+.3f", $0) } ?? "—"))
        }
    }

    print("\n=== characters recovered by deskewing the recogniser's input ===")
    print("bucket             pages   before      after      delta     better/worse")
    for key in order {
        guard let b = buckets[key], b.pages > 0 else { continue }
        let delta = b.after - b.before
        let pct = b.before > 0 ? 100.0 * Double(delta) / Double(b.before) : 0
        print(String(format: "%-18s %5d %10d %10d %+9d %+6.2f%%   %d/%d",
                     (key as NSString).utf8String!, b.pages, b.before, b.after,
                     delta, pct, b.better, b.worse))
    }
    print("""

  The control row is the one to read first. If straight pages lose text, the
  correction is doing damage where there was nothing to fix, and no gain on the
  crooked ones is worth that — that is precisely why this feature was declined
  the first time.
""")
    exit(0)
}

print("file\tpage\tdegrees\tconfidence\tsamples")
var angles: [Double] = []
var abstained = 0, documentsWithSkew = 0
for path in files {
    guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { continue }
    let name = (path as NSString).lastPathComponent
    var worst = 0.0
    for index in samplePages(document) {
        guard let page = document.page(at: index), let r = render(page) else { continue }
        guard let estimate = Deskew.trustworthyEstimate(grey: r.grey, width: r.width,
                                                        height: r.height) else {
            abstained += 1
            print("\(name)\t\(index + 1)\t—\t—\t—")
            continue
        }
        angles.append(abs(estimate.degrees))
        worst = max(worst, abs(estimate.degrees))
        print(String(format: "%@\t%d\t%+.3f\t%.2f\t%d",
                     name, index + 1, estimate.degrees, estimate.confidence, estimate.samples))
    }
    if worst >= 0.5 { documentsWithSkew += 1 }
}

if summary {
    let sorted = angles.sorted()
    print("\n=== skew over \(sorted.count) measured pages (\(abstained) abstained) ===")
    guard !sorted.isEmpty else { exit(0) }
    func share(_ test: (Double) -> Bool) -> String {
        String(format: "%.1f%%", 100.0 * Double(sorted.filter(test).count) / Double(sorted.count))
    }
    print("  median      \(String(format: "%.3f", sorted[sorted.count / 2]))°")
    print("  p95         \(String(format: "%.3f", sorted[min(sorted.count * 95 / 100, sorted.count - 1)]))°")
    print("  worst       \(String(format: "%.3f", sorted.last!))°")
    print("  below 0.25° \(share { $0 < 0.25 })   (no measurable loss)")
    print("  0.25-0.5°   \(share { $0 >= 0.25 && $0 < 0.5 })")
    print("  0.5-1.5°    \(share { $0 >= 0.5 && $0 < 1.5 })   (the band that costs)")
    print("  over 1.5°   \(share { $0 >= 1.5 })")
    print("  documents with a page at 0.5° or worse: \(documentsWithSkew)")
}
