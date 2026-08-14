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
    let box = page.bounds(for: .mediaBox)
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
        ctx.translateBy(x: -box.minX, y: -box.minY)
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

var failures = 0, checked = 0
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
    let sourceBox = sourcePage.bounds(for: .mediaBox)
    let outputBox = outputPage.bounds(for: .mediaBox)

    for mark in marks {
        checked += 1
        let rect = mark.bounds
        let inSource = footprint(sWith, sWithout, in: rect, pageBox: sourceBox, scale: scale)
        let inOutput = footprint(oWith, oWithout, in: rect, pageBox: outputBox, scale: scale)
        let verdict: String
        var drift = 0.0
        if let inSource, let inOutput {
            drift = max(abs(inSource.cx - inOutput.cx), abs(inSource.cy - inOutput.cy))
        }
        if inSource == nil || inOutput == nil {
            verdict = "SKIP off page"
        } else if inSource!.coverage < 0.01 {
            // Nothing to compare against. A zero-area annotation, or one whose
            // appearance draws nothing in the original either.
            verdict = "SKIP draws nothing in the source"
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
print("\(checked) marks checked, \(failures) failed")
exit(failures == 0 ? 0 : 1)
