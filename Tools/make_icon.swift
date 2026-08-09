import AppKit

// Draws a simple document-with-text icon into an .iconset directory.
// Called by build.sh; failure is non-fatal (the app falls back to a generic icon).
//
// Draws into an NSBitmapImageRep context rather than NSImage.lockFocus():
// lockFocus needs a window server connection that a plain `swift` script
// doesn't have, and fails with "CGImageDestinationFinalize failed".

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ size: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let s = CGFloat(size)
    let inset = s * 0.14
    let page = NSRect(x: inset, y: inset * 0.8, width: s - inset * 2, height: s - inset * 1.6)
    let radius = s * 0.06
    let pagePath = NSBezierPath(roundedRect: page, xRadius: radius, yRadius: radius)

    NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.51, blue: 0.96, alpha: 1),
               ending: NSColor(calibratedRed: 0.11, green: 0.28, blue: 0.76, alpha: 1))?
        .draw(in: pagePath, angle: -90)

    // Text lines, ragged like a scanned paragraph.
    NSColor.white.withAlphaComponent(0.94).setFill()
    let widths: [CGFloat] = [0.74, 0.90, 0.60, 0.88, 0.44]
    let lineHeight = max(page.height * 0.060, 1)
    let gap = page.height * 0.108
    var y = page.maxY - page.height * 0.26
    for w in widths {
        let bar = NSRect(x: page.minX + page.width * 0.13,
                         y: y,
                         width: page.width * 0.74 * w,
                         height: lineHeight)
        NSBezierPath(roundedRect: bar, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
        y -= gap
    }

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])
}

for (size, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
                     (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
                     (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    guard let data = draw(size) else {
        FileHandle.standardError.write("failed to render \(name)\n".data(using: .utf8)!)
        exit(1)
    }
    try? data.write(to: out.appendingPathComponent("icon_\(name).png"))
}
