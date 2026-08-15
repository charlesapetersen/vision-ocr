// Did the reader's marks land where they were, drawn rather than counted?
//
// The third and least skippable part of TODO item 2's verification bar: "A highlight
// forty points low passes both checks above and misrepresents somebody's scholarship."
// Counting annotations and comparing `/Rect` values both check the *description* of a
// mark. This checks the pixels.
//
// **Why it does not diff the two pages against each other.** The point of the rebuild is
// that the page is a different image afterwards — a 1-bit stencil where there was a grey
// scan — so a whole-page difference is enormous and says nothing. What is comparable is
// each mark's own **footprint**: render the page with its annotations, render it again
// with them removed, and difference the two. That isolates exactly the ink the
// annotations contribute, independently of what is underneath. Do it on both files and
// the footprints must agree.
//
// Per annotation it reports the fraction of its own `/Rect` that the mark darkens, in
// the source and in the output. A highlight that moved is a footprint in the wrong
// place; a stamp whose appearance stream failed to carry is a footprint of zero.
//
//   mkdir -p /tmp/h && cp Tools/score-annotations.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/score-annotations -target "$(uname -m)-apple-macos13.0" \
//     $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift
//   /tmp/score-annotations <original.pdf> <rebuilt-and-annotated.pdf>
//
// Exit 0 if every mark agrees within tolerance, 1 if any does not, 2 for bad usage.
import AppKit
import CoreGraphics
import Foundation
import PDFKit

let arguments = CommandLine.arguments
guard arguments.count > 2 else {
    FileHandle.standardError.write(Data("usage: score-annotations <source> <output>\n".utf8))
    exit(2)
}
let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
guard let source = PDFDocument(url: sourceURL), let output = PDFDocument(url: outputURL) else {
    FileHandle.standardError.write(Data("cannot open both files\n".utf8))
    exit(2)
}
guard source.pageCount == output.pageCount else {
    print("FAIL\tpage count \(source.pageCount) vs \(output.pageCount)")
    exit(1)
}

/// The marks this app carries. Kept in step with `Annotations.copiedSubtypes` by
/// deriving from it, so the tool cannot drift from the thing it is checking.
let copied = Annotations.copiedSubtypes.map { String($0.dropFirst()) }

/// Render a page at a fixed scale, optionally with its annotations stripped.
///
/// The strip is done on a **detached copy** of the page. Removing annotations from the
/// open document and putting them back would be the kind of in-place edit that has bitten
/// this project before, and a copy costs one page render.
/// **RGB, not grey, and that is not a preference.** Rendered into a `DeviceGray`
/// context, PDFKit draws underlines and stamps and silently draws **no highlights at
/// all**: a `/Highlight` is composited in Multiply through a transparency group, and that
/// needs a colour space with alpha behind it. The first version of this tool was grey and
/// reported every one of 57 highlights as "draws nothing in the source" — a clean,
/// plausible, entirely wrong answer, and the fifth instrument in this project's history
/// to be wrong in the direction of agreeing with a hypothesis. Luminance is taken from
/// the RGB afterwards.
func render(_ page: PDFPage, scale: CGFloat, withAnnotations: Bool) -> (data: [UInt8], w: Int, h: Int)? {
    // **`Flattener.fullBox`, not `page.bounds(for: .mediaBox)`** (A12.5). PDFKit
    // reports the *unrotated* box, and `PDFPage.draw(with:to:)` applies the rotation
    // — so on a quarter-turned page this sized a portrait buffer and then drew a
    // landscape page into it, and every mark landed outside. The tool reported
    // `srcCover 0.000` and `SKIP draws nothing in the source`, twice, and **exited
    // 0**.
    //
    // That is this tool's own recorded failure coming back through another door: its
    // header says the off-page case was promoted from SKIP to FAIL because "counting
    // that as skipped is how a fixture with three provably lost highlights reported
    // 0 failures". A skip that fires for a *reason the tool caused* is the same lie
    // with a different cause.
    //
    // `Flattener.boxSize` sits in the same compiled sources with a comment saying
    // exactly this, which is the reason the fix is to call it rather than to repeat
    // the swap here.
    let box = Flattener.fullBox(of: page)
    let w = max(Int(box.width * scale), 1), h = max(Int(box.height * scale), 1)
    var rgba = [UInt8](repeating: 255, count: w * h * 4)
    var buffer = [UInt8](repeating: 255, count: w * h)
    let drew = rgba.withUnsafeMutableBytes { raw -> Bool in
        guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        // No translate by the box origin. `PDFPage.draw(with: .mediaBox, to:)` already
        // maps that box onto the context, so subtracting the origin here shifted the
        // page a second time — on `Cohen_1990` page 6, whose media box starts at
        // y = -24.69, that halved the measured coverage of the one highlight on it and
        // left the verdict one thousandth away from being skipped as "draws nothing".
        if withAnnotations {
            page.draw(with: .mediaBox, to: ctx)
        } else {
            // `PDFPage.draw` always draws annotations, so the only way to render the
            // page without them is to hand a copy that has none.
            guard let bare = page.copy() as? PDFPage else { return false }
            for annotation in bare.annotations { bare.removeAnnotation(annotation) }
            bare.draw(with: .mediaBox, to: ctx)
        }
        return true
    }
    guard drew else { return nil }
    for i in 0..<(w * h) {
        let r = Double(rgba[i * 4]), g = Double(rgba[i * 4 + 1]), b = Double(rgba[i * 4 + 2])
        buffer[i] = UInt8(min(max(0.299 * r + 0.587 * g + 0.114 * b, 0), 255))
    }
    return (buffer, w, h)
}

/// Where a mark draws, and how much of its own rectangle it touches.
///
/// **Coverage alone cannot be the test, and finding that out cost a rerun.** A
/// `/Highlight` is Multiply-blended, so what it changes depends on what is under it: over
/// a grey scan the anti-aliased edge of every glyph inside the highlight shifts a level
/// or two and counts as changed, while over the 1-bit rebuild those same glyph pixels are
/// pure black and Multiply leaves them pure black. The footprint is therefore
/// *legitimately smaller* on the rebuilt page — measured, 14 highlights at 0.41-0.54
/// against 0.54-0.71 — and a coverage comparison calls a perfect transplant a failure.
/// Opaque marks do not have this problem: every stamp in the file agreed to three
/// decimals.
///
/// So the geometry is what is compared. The **centroid** of the changed pixels, in units
/// of the mark's own rectangle, moves if and only if the mark moved — which is the thing
/// the check exists to catch. Coverage is still reported, and still has to be non-zero,
/// because a mark that draws nothing has failed to carry.
func footprint(_ a: (data: [UInt8], w: Int, h: Int), _ b: (data: [UInt8], w: Int, h: Int),
               in rect: CGRect, pageBox: CGRect, scale: CGFloat)
    -> (coverage: Double, cx: Double, cy: Double)? {
    guard a.w == b.w, a.h == b.h else { return nil }
    let x0 = max(Int((rect.minX - pageBox.minX) * scale), 0)
    let x1 = min(Int((rect.maxX - pageBox.minX) * scale) + 1, a.w)
    // Rows are top-down in the bitmap and bottom-up in PDF space.
    let y0 = max(a.h - Int((rect.maxY - pageBox.minY) * scale) - 1, 0)
    let y1 = min(a.h - Int((rect.minY - pageBox.minY) * scale) + 1, a.h)
    guard x0 < x1, y0 < y1 else { return nil }
    var changed = 0, total = 0, sumX = 0, sumY = 0
    for y in y0..<y1 {
        for x in x0..<x1 {
            total += 1
            if abs(Int(a.data[y * a.w + x]) - Int(b.data[y * b.w + x])) > 12 {
                changed += 1; sumX += x - x0; sumY += y - y0
            }
        }
    }
    guard total > 0 else { return nil }
    guard changed > 0 else { return (0, 0, 0) }
    return (Double(changed) / Double(total),
            Double(sumX) / Double(changed) / Double(x1 - x0),
            Double(sumY) / Double(changed) / Double(y1 - y0))
}

let scale: CGFloat = 2.0            // 144 DPI: enough to see a mark, cheap enough to run
/// How far a mark's centroid may move, in units of its own rectangle. 0.10 of the
/// rectangle is a small fraction of a highlight's height and far below the displacement
/// that would misrepresent which words were marked.
let centroidTolerance = 0.10
/// And how much of the source's coverage must survive. Generous on purpose: the Multiply
/// case above legitimately loses up to a third of its footprint, so this is here to catch
/// a mark that drew *nothing much*, not to compare areas.
let coverageFloor = 0.4

var failures = 0, checked = 0, skipped = 0
print("page\tsubtype\trect\tsrcCover\toutCover\tdrift\tverdict")
for index in 0..<source.pageCount {
    guard let sourcePage = source.page(at: index), let outputPage = output.page(at: index)
    else { continue }
    let marks = sourcePage.annotations.filter { copied.contains($0.type ?? "") }
    guard !marks.isEmpty else { continue }

    guard let sWith = render(sourcePage, scale: scale, withAnnotations: true),
          let sWithout = render(sourcePage, scale: scale, withAnnotations: false),
          let oWith = render(outputPage, scale: scale, withAnnotations: true),
          let oWithout = render(outputPage, scale: scale, withAnnotations: false) else {
        print("p\(index + 1)\t-\t-\t-\t-\tFAIL could not render")
        failures += 1
        continue
    }
    // The **rotated** boxes, matching the buffers `render` now sizes (A12.5), and a
    // transform that puts an annotation's rectangle into the same space.
    //
    // Sizing the buffer correctly was only half of it: a mark's `/Rect` is in
    // unrotated page space, so on a quarter-turned page a rect at y = 690..720 sat
    // outside a buffer only 612 tall and the tool skipped it as "off its own page" —
    // a different skip, same silence. `getDrawingTransform` is what
    // `PDFPage.draw(with:to:)` uses and what `SearchableWriter.cropRegion` already
    // uses for the crop box, so this is the app's own answer rather than a rotation
    // matrix written out a second time here.
    let sourceBox = Flattener.fullBox(of: sourcePage)
    let outputBox = Flattener.fullBox(of: outputPage)
    func intoDrawnSpace(_ rect: CGRect, of page: PDFPage, box: CGRect) -> CGRect {
        guard let cgPage = page.pageRef else { return rect }
        return rect.applying(cgPage.getDrawingTransform(
            .mediaBox, rect: box, rotate: 0, preserveAspectRatio: true))
    }

    // Pair each source mark with the output mark that claims to be it, by subtype and
    // order. **The output must be measured with the output's OWN rectangle**, not the
    // source's: the rebuild moves an offset media box to the origin, so the same words sit
    // at different coordinates in the two files. Measuring the output through the source's
    // rectangle made this tool fail a correctly-carried mark on `Cohen_1990` (0.709
    // against 0.000, "absent from the output") while passing genuinely misplaced ones —
    // an instrument that was inverted for exactly the 105 of 233 corpus documents it was
    // most needed on.
    var outputMarks = outputPage.annotations.filter { copied.contains($0.type ?? "") }
    for mark in marks {
        checked += 1
        let rect = mark.bounds
        // Same subtype, first unclaimed one, in order.
        let paired = outputMarks.firstIndex { $0.type == mark.type }
        let outputRect = paired.map { outputMarks[$0].bounds }
        if let paired { outputMarks.remove(at: paired) }
        let inSource = footprint(sWith, sWithout,
                                 in: intoDrawnSpace(rect, of: sourcePage, box: sourceBox),
                                 pageBox: sourceBox, scale: scale)
        let inOutput = outputRect.flatMap {
            footprint(oWith, oWithout,
                      in: intoDrawnSpace($0, of: outputPage, box: outputBox),
                      pageBox: outputBox, scale: scale)
        }
        let verdict: String
        var drift = 0.0
        if let inSource, let inOutput {
            drift = max(abs(inSource.cx - inOutput.cx), abs(inSource.cy - inOutput.cy))
        }
        if outputRect == nil {
            verdict = "FAIL no mark of that type in the output"
            failures += 1
        } else if inSource == nil {
            // The source's own rectangle falls outside its own page: nothing to compare
            // against, and not the output's fault.
            verdict = "SKIP the source rectangle is off its own page"
            skipped += 1
        } else if inOutput == nil {
            // **A failure, not a skip.** This is what a rotated page produced before the
            // transplant learned to refuse one: the carried rectangle lands outside the
            // rebuilt page, so the mark is *gone*. Counting that as "skipped" is how a
            // fixture with three provably lost highlights reported 0 failures.
            verdict = "FAIL the carried rectangle is off the rebuilt page"
            failures += 1
        } else if inSource!.coverage < 0.01 {
            // Nothing to compare against. A zero-area annotation, or one whose
            // appearance draws nothing in the original either.
            //
            // **Counted, and it makes the run non-zero** (A12.5). A skip here means
            // this tool measured nothing about a mark that exists, and until the
            // rotation bug above was fixed that was every mark on every
            // quarter-turned page — reported as a clean `0 failed, exit 0`. A skip is
            // a hole in the evidence, and the exit code is how a release script finds
            // out. The distinction from a FAIL is kept: a skip does not say the mark
            // was lost, it says nobody knows.
            verdict = "SKIP draws nothing in the source"
            skipped += 1
        } else if inOutput!.coverage < 0.01 {
            verdict = "FAIL absent from the output"
            failures += 1
        } else if inOutput!.coverage < inSource!.coverage * coverageFloor {
            verdict = "FAIL draws far less than the original"
            failures += 1
        } else if drift > centroidTolerance {
            verdict = "FAIL moved"
            failures += 1
        } else {
            verdict = "ok"
        }
        print(String(format: "p%d\t%@\t%.0f,%.0f\t%.3f\t%.3f\t%.3f\t%@", index + 1,
                     mark.type ?? "?", rect.minX, rect.minY,
                     inSource?.coverage ?? -1, inOutput?.coverage ?? -1, drift, verdict))
    }
}
print("")
print("\(checked) marks checked, \(failures) failed, \(skipped) skipped")
if skipped > 0 {
    print("SKIPPED marks are unmeasured, not verified — this run does not clear them.")
}
// A12.5: a skip is not a pass. `exit(failures == 0 ? 0 : 1)` let a run that
// measured nothing at all report success, which is how the rotation bug above
// stayed invisible through 57 highlights.
exit(failures == 0 && skipped == 0 ? 0 : 1)
