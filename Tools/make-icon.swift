// Renders the app icon: a macOS-style rounded square with a gradient and three faders.
// Usage: swiftc -O Tools/make-icon.swift -o /tmp/make-icon && /tmp/make-icon <iconset dir>
import AppKit

func render(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }

    let inset = size * 0.08                       // macOS icons sit inside a transparent margin
    let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let radius = rect.width * 0.2237
    let tile = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(tile); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    // Gradient tile
    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    let colors = [NSColor(calibratedRed: 0.42, green: 0.27, blue: 0.95, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.16, green: 0.55, blue: 0.98, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.10, green: 0.80, blue: 0.85, alpha: 1).cgColor]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

    // Soft highlight at the top
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor.white.withAlphaComponent(0.28).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(glow, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    ctx.restoreGState()

    // Three faders
    let trackW = rect.width * 0.07
    let trackH = rect.height * 0.52
    let knobW = rect.width * 0.17
    let knobH = rect.height * 0.085
    let xs: [CGFloat] = [0.30, 0.50, 0.70].map { rect.minX + rect.width * $0 }
    let knobYs: [CGFloat] = [0.62, 0.38, 0.54].map { rect.minY + rect.height * $0 }

    for (x, knobY) in zip(xs, knobYs) {
        let track = CGRect(x: x - trackW / 2, y: rect.midY - trackH / 2, width: trackW, height: trackH)
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: trackW / 2, cornerHeight: trackW / 2, transform: nil))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.28).cgColor)
        ctx.fillPath()

        // filled portion below the knob
        let filled = CGRect(x: track.minX, y: track.minY, width: trackW, height: max(trackW, knobY - track.minY))
        ctx.addPath(CGPath(roundedRect: filled, cornerWidth: trackW / 2, cornerHeight: trackW / 2, transform: nil))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        ctx.fillPath()

        let knob = CGRect(x: x - knobW / 2, y: knobY - knobH / 2, width: knobW, height: knobH)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.02, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(CGPath(roundedRect: knob, cornerWidth: knobH * 0.4, cornerHeight: knobH * 0.4, transform: nil))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        writePNG(render(size: CGFloat(px)), pixels: px, to: outDir.appendingPathComponent(name))
    }
}
print("wrote iconset to \(outDir.path)")
