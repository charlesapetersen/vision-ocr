// Synthesised pages for the routing decision the corpus cannot produce.
//
// FEATURES.md's spatial-signal entry says it plainly: "the two histogram
// discriminators tried in R49 both had a plausible-looking gap on the corpus and an
// overlap the corpus did not contain. Synthesise the adversarial cases; the corpus
// alone will not produce them." R50 then measured two specific misses of
// `inkOutsideText` and wrote them on the constant. This builds those two, plus the
// cases that must NOT be caught, so a threshold can be set against both kinds of
// error rather than against one.
//
// Each page is a plausible book page: real text laid out in a block, plus whatever
// the case is about. The text matters — a bare plate on white is not what the
// pipeline sees, and a signal measured on one would be calibrated for a page that
// does not exist.
//
//   pale-drawing     text + a line drawing at luminance 200. THE DANGEROUS ONE:
//                    Otsu calls it paper, so `inkOutsideText` reads 0.0000 and
//                    1-bit renders it as blank white. Total content loss.
//   flat-colour      text + a flat red field at luminance ~103. R50 measured this
//                    at inkOutsideText 0.0365 — under the 0.08 threshold — because
//                    Otsu lands mid-field and splits it in half.
//   tonal-plate      text + a continuous-tone photograph. Must read as a picture.
//   halftone         text + a coarse halftone. Bimodal, so 1-bit is *correct* here
//                    (R38) and it must not be dragged out of that route.
//   text-only        the control. Must read as text, or the feature saves nothing.
//   text-red-ink     text whose headings are red, no picture at all. The `Why?`
//                    pamphlet's shape, and the case where colour is *inside* the
//                    words rather than beside them.
//   faint-marks      the same curves as pale-drawing, at luminance 232 against paper at
//                    about 243 — eleven levels, where the drawing is forty-seven. A
//                    mark you can barely see is not content, and this is the fixture
//                    that says so: it must route to 1-bit. Added 2026-08-16 because
//                    `minimumMarkContrast`'s mutant SURVIVED a green 1,118-check suite:
//                    the constant is justified by 228 pages of `Himanen_2001` and
//                    nothing in the suite could see it.
//   pale-chart       a pale line chart with its axis labels and caption INSIDE its
//                    own bounding box. Added 2026-08-16 by the review of R56's fix,
//                    which observed that `maximumInkUnderADrawing` refuses a pale mark
//                    with this page's own type inside it — and that a chart, a
//                    captioned plate and an inset figure all have exactly that.
//                    `pale-drawing` sits on bare paper and therefore cannot see that
//                    constant at all: it reads 0.0197 at every value of it, including
//                    zero. This one can, and it is the hardest of the eight.
//
// **What these fixtures are blind to, by construction: geometry.** All eight are one
// page, 8.5x11, `/Rotate 0`. CLAUDE.md invariant 5 says a fixture needs two pages
// of differing size and one rotated page, because a single-page upright fixture
// cannot see a geometry bug at all — and R56 and R57 rest on these eight. So their
// evidence is about *routing*, and says nothing about whether a pale drawing or a
// tonal plate survives on a rotated or oddly-sized page. A11.8 tracks the coverage
// gap; A12.8 is where this was written down. If a fix for either entry is measured
// only here, it has been measured on the easy geometry.
//
//   mkdir -p /tmp/h && cp Tools/make-plate-fixtures.swift /tmp/h/main.swift
//   swiftc -O -o /tmp/plates -target "$(uname -m)-apple-macos13.0" /tmp/h/main.swift
//   /tmp/plates <output-directory>
import AppKit
import CoreGraphics
import Foundation

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
              ? CommandLine.arguments[1] : "./plates")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// 300 DPI Letter, which is what the corpus's scans mostly are.
let dpi = 300.0
let pageW = 8.5 * 72, pageH = 11.0 * 72
let pxW = Int(8.5 * dpi), pxH = Int(11.0 * dpi)

let body = """
The question of what a page is made of has an answer that depends entirely on \
who is asking. A compositor sees a forme; a binder sees a signature; a reader \
sees an argument. The scanner, which is the only one of them that must decide \
without understanding, sees a field of luminance and has to guess. That guess is \
the whole of the problem, and it is why a page of type and a page of tone cannot \
be treated as one kind of thing. What follows is set solid, in a measure narrow \
enough to break lines often, because the number of lines is what makes a page \
look like a page to anything counting components rather than reading words.
"""

/// A page of ink on paper, drawn at print resolution. `extra` adds the case.
func page(_ name: String, redHeadings: Bool = false,
          extra: (CGContext) -> Void) {
    guard let ctx = CGContext(data: nil, width: pxW, height: pxH,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return }
    // Cream stock, not pure white: every real scan has some, and pure white makes
    // Otsu's job easier than it ever is in practice.
    ctx.setFillColor(red: 0.97, green: 0.955, blue: 0.92, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))

    let scale = dpi / 72.0
    ctx.saveGState()
    ctx.scaleBy(x: scale, y: scale)
    ctx.textMatrix = .identity

    // Two blocks of body text with a heading over each, so the page has the line
    // count and the row structure of a real one.
    let margin = 72.0, column = pageW - 2 * margin
    var y = pageH - margin
    for block in 0..<2 {
        let heading = block == 0 ? "The Compositor's Question" : "What the Scanner Sees"
        let headColour = redHeadings
            ? NSColor(red: 0.72, green: 0.11, blue: 0.14, alpha: 1) : NSColor.black
        let headAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Times-Bold", size: 14) ?? NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: headColour]
        let head = NSAttributedString(string: heading, attributes: headAttrs)
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "Times-Roman", size: 10.5) ?? NSFont.systemFont(ofSize: 10.5),
            .foregroundColor: NSColor.black]
        let text = NSAttributedString(string: body, attributes: bodyAttrs)

        for (piece, height) in [(head, 20.0), (text, 260.0)] {
            let path = CGPath(rect: CGRect(x: margin, y: y - height,
                                           width: column, height: height), transform: nil)
            let frame = CTFramesetterCreateFrame(
                CTFramesetterCreateWithAttributedString(piece), CFRange(), path, nil)
            // Core Text draws bottom-up; the context is already in PDF space.
            ctx.saveGState()
            CTFrameDraw(frame, ctx)
            ctx.restoreGState()
            y -= height + 12
        }
        y -= 24
    }
    ctx.restoreGState()

    extra(ctx)

    guard let image = ctx.makeImage() else { return }
    // Wrapped as a PDF, because the pipeline's entry point is a PDF and a routing
    // decision made on a bare PNG is a decision about something else.
    let url = out.appendingPathComponent(name + ".pdf")
    guard let consumer = CGDataConsumer(url: url as CFURL) else { return }
    var box = CGRect(x: 0, y: 0, width: pageW, height: pageH)
    guard let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
    pdf.beginPDFPage(nil)
    pdf.draw(image, in: box)
    pdf.endPDFPage()
    pdf.closePDF()
    print("wrote \(url.lastPathComponent)")
}

/// Where a plate sits: lower third, full measure. Bottom-left origin.
let plate = CGRect(x: Int(1.0 * dpi), y: Int(1.2 * dpi),
                   width: Int(6.5 * dpi), height: Int(2.8 * dpi))

page("text-only") { _ in }

page("text-red-ink", redHeadings: true) { _ in }

// THE DANGEROUS ONE. Luminance 200 is above any Otsu split a text page produces,
// so this drawing is not ink, and an ink-based signal cannot see it at all.
page("pale-drawing") { ctx in
    ctx.setStrokeColor(gray: 200.0 / 255.0, alpha: 1)
    ctx.setLineWidth(3)
    for i in 0..<14 {
        let t = Double(i) / 13.0
        ctx.move(to: CGPoint(x: plate.minX, y: plate.minY + t * plate.height))
        ctx.addCurve(to: CGPoint(x: plate.maxX, y: plate.minY + (1 - t) * plate.height),
                     control1: CGPoint(x: plate.midX - 200, y: plate.maxY),
                     control2: CGPoint(x: plate.midX + 200, y: plate.minY))
    }
    ctx.strokePath()
    // A recognisable subject outline, still pale.
    ctx.setLineWidth(5)
    ctx.strokeEllipse(in: plate.insetBy(dx: plate.width * 0.3, dy: plate.height * 0.2))
}

// Faint. The same subject as `pale-drawing` and the same size, eleven luminance levels
// below the paper instead of forty-seven — the depth of a photocopy's background mottle
// and of the show-through on a real typescript. It must stay at 1-bit: losing it is
// exactly what `minimumMarkContrast` is for, and this is the only fixture that can tell
// whether that constant is doing anything.
page("faint-marks") { ctx in
    ctx.setStrokeColor(gray: 232.0 / 255.0, alpha: 1)
    ctx.setLineWidth(3)
    for i in 0..<14 {
        let t = Double(i) / 13.0
        ctx.move(to: CGPoint(x: plate.minX, y: plate.minY + t * plate.height))
        ctx.addCurve(to: CGPoint(x: plate.maxX, y: plate.minY + (1 - t) * plate.height),
                     control1: CGPoint(x: plate.midX - 200, y: plate.maxY),
                     control2: CGPoint(x: plate.midX + 200, y: plate.minY))
    }
    ctx.strokePath()
    ctx.setLineWidth(5)
    ctx.strokeEllipse(in: plate.insetBy(dx: plate.width * 0.3, dy: plate.height * 0.2))
}

// R50 measured this at inkOutsideText 0.0365: a flat field whose luminance
// straddles the page's own threshold, so half of it counts as ink and half does not.
page("flat-colour") { ctx in
    ctx.setFillColor(red: 0.62, green: 0.14, blue: 0.16, alpha: 1)   // luminance ~103
    ctx.fill(plate)
}

// Continuous tone: a smooth gradient with a dark subject on it. Must be a picture.
page("tonal-plate") { ctx in
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let gradient = CGGradient(colorsSpace: space,
                                    colors: [CGColor(gray: 0.85, alpha: 1),
                                             CGColor(gray: 0.18, alpha: 1)] as CFArray,
                                    locations: [0, 1]) else { return }
    ctx.saveGState()
    ctx.clip(to: plate)
    ctx.drawLinearGradient(gradient, start: CGPoint(x: plate.minX, y: plate.maxY),
                           end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
    ctx.setFillColor(gray: 0.08, alpha: 1)
    ctx.fillEllipse(in: plate.insetBy(dx: plate.width * 0.34, dy: plate.height * 0.22))
    ctx.restoreGState()
}

// A pale chart, drawn like a real one: pale plot lines and a pale frame, with **black
// axis numerals, a legend and a caption inside the plot's own rectangle**. That is the
// ordinary layout of a figure in a book, and it is the case `maximumInkUnderADrawing`
// is most likely to refuse — which would erase the chart. Must read as a picture.
page("pale-chart") { ctx in
    let dark = NSColor.black
    ctx.setStrokeColor(gray: 200.0 / 255.0, alpha: 1)
    ctx.setLineWidth(2)
    // The frame, and gridlines across it.
    ctx.stroke(plate.insetBy(dx: 40, dy: 40))
    for i in 1..<6 {
        let y = plate.minY + 40 + (plate.height - 80) * Double(i) / 6
        ctx.move(to: CGPoint(x: plate.minX + 40, y: y))
        ctx.addLine(to: CGPoint(x: plate.maxX - 40, y: y))
    }
    ctx.strokePath()
    // Three plotted series: long thin curves, which is the drawing profile.
    ctx.setLineWidth(3)
    for series in 0..<3 {
        var x = plate.minX + 40
        ctx.move(to: CGPoint(x: x, y: plate.minY + 60 + Double(series) * 30))
        var step = 0
        while x < plate.maxX - 40 {
            x += 24
            let wobble = sin(Double(step) * 0.7 + Double(series)) * 60
            ctx.addLine(to: CGPoint(x: x,
                                    y: plate.minY + 90 + Double(series) * 55
                                        + wobble + Double(step) * 4))
            step += 1
        }
        ctx.strokePath()
        ctx.move(to: CGPoint(x: plate.minX + 40, y: plate.minY + 60 + Double(series) * 30))
    }
    // …and this page's own type, inside the plot rectangle: axis numerals down the
    // left, a legend in the corner, a caption along the bottom.
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "Times-Roman", size: 26) ?? NSFont.systemFont(ofSize: 26),
        .foregroundColor: dark]
    func label(_ s: String, at p: CGPoint) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSAttributedString(string: s, attributes: attrs)
            .draw(at: NSPoint(x: p.x, y: p.y))
        NSGraphicsContext.restoreGraphicsState()
    }
    for i in 0..<6 {
        label("\(i * 20)", at: CGPoint(x: plate.minX + 6,
                                       y: plate.minY + 40 + (plate.height - 80)
                                           * Double(i) / 6 - 12))
    }
    label("Series A", at: CGPoint(x: plate.maxX - 260, y: plate.maxY - 90))
    label("Series B", at: CGPoint(x: plate.maxX - 260, y: plate.maxY - 130))
    label("Figure 4. Enrolment by decade", at: CGPoint(x: plate.minX + 60,
                                                       y: plate.minY + 4))
}

// Bimodal by construction: dots of solid ink on bare paper. R38's finding is that
// 1-bit is the *right* route for this, so it must not be pulled off it.
page("halftone") { ctx in
    ctx.setFillColor(gray: 0, alpha: 1)
    let pitch = Int(dpi / 45.0)          // a coarse 45 lpi screen
    var y = Int(plate.minY)
    while y < Int(plate.maxY) {
        var x = Int(plate.minX)
        while x < Int(plate.maxX) {
            // Dot size follows a shape, so it reads as an image rather than a field.
            let u = (Double(x) - plate.minX) / plate.width
            let v = (Double(y) - plate.minY) / plate.height
            let r = Double(pitch) * 0.5 * (0.25 + 0.7 * (1 - abs(u - 0.5) * 2) * (0.4 + v))
            if r > 0.4 {
                ctx.fillEllipse(in: CGRect(x: Double(x), y: Double(y), width: r, height: r))
            }
            x += pitch
        }
        y += pitch
    }
}
