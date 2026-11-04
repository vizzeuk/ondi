// Draws the app icon into an .iconset: the brand's squircle in glossy midnight blue with the white wave (LogoGeometry.swift).
// Built with the geometry file: swiftc scripts/make_icon.swift Sources/NXBiblioteca/LogoGeometry.swift (make_app.sh does it).
import AppKit

func renderIcon(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ns
    let ctx = ns.cgContext
    // y-down, as the geometry is drawn
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    // macOS icon grid: the shape fills about 80 % of the canvas, with room for its shadow
    let side = s * 0.805
    let rect = CGRect(x: (s - side) / 2, y: (s - side) / 2 - s * 0.012, width: side, height: side)
    let shape = LogoGeometry.squircle(in: rect)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor(srgbRed: 0x06/255, green: 0x14/255, blue: 0x1B/255, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Glossy body in the palette's darkest blue (#06141B), a touch lighter at the top for the gloss
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let body = CGGradient(colorsSpace: space, colors: [NSColor(srgbRed: 0x1A/255, green: 0x2D/255, blue: 0x3B/255, alpha: 1).cgColor, NSColor(srgbRed: 0x06/255, green: 0x14/255, blue: 0x1B/255, alpha: 1).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(body, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
    // Soft highlight across the top, like light on a drop of ink
    let gloss = CGGradient(colorsSpace: space, colors: [NSColor(white: 1, alpha: 0.22).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(gloss, startCenter: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.35), startRadius: 0,
                           endCenter: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.35), endRadius: rect.height * 0.78, options: [])
    // The wave's reflection: a thin, faint wave below it
    let reflection = LogoGeometry.wave(in: rect.offsetBy(dx: 0, dy: rect.height * 0.2), phase: 0.35, amplitude: LogoGeometry.waveAmplitude * 0.55)
    ctx.addPath(reflection)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.09).cgColor)
    ctx.setLineWidth(side * LogoGeometry.waveWidth * 0.32)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // The wave
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.006), blur: s * 0.018, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(LogoGeometry.wave(in: rect))
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(side * LogoGeometry.waveWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Hairline rim, so the dark shape still reads on a dark Dock
    ctx.addPath(shape)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
    ctx.setLineWidth(max(1, s * 0.004))
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
if out.pathExtension == "iconset" {
    for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                       ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
        try! renderIcon(px).write(to: out.appendingPathComponent("icon_\(name).png"))
    }
} else {
    try! renderIcon(1024).write(to: out.appendingPathComponent("app-icon-1024.png"))
}
