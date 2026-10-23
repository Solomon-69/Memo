// make-icon.swift: draws the Memo app icon ("Keepsake": a saved note card with a folded corner
// and a glowing pin) in a light and a dark version, at every size macOS needs.
// Usage: mkicon <outdir>  ->  <outdir>/light/*.png, <outdir>/dark/*.png, <outdir>/Memo-1024{,-dark}.png
import AppKit

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

struct Look {
    let bgTop, bgBottom, sheen, cardTop, cardBottom, flap, flapShade, lines, pin, pinGlow: NSColor
}
let lightLook = Look(bgTop: hex(0x3157C4), bgBottom: hex(0x0C1A4D), sheen: hex(0x9DB6FF, 0.40),
                     cardTop: hex(0xFFFFFF), cardBottom: hex(0xE6ECFA), flap: hex(0xC9D5F4), flapShade: hex(0x0C1A4D, 0.28),
                     lines: hex(0x1E3A8A, 0.22), pin: hex(0x2449B5), pinGlow: hex(0x6E93FF, 0.55))
let darkLook = Look(bgTop: hex(0x1C2440), bgBottom: hex(0x05070F), sheen: hex(0x4F6FD8, 0.30),
                    cardTop: hex(0xC7D3F7), cardBottom: hex(0x9FB1E6), flap: hex(0x7C93D9), flapShade: hex(0x000000, 0.35),
                    lines: hex(0x0C1A4D, 0.35), pin: hex(0x0F1C4A), pinGlow: hex(0x5B82FF, 0.65))

func shadow(_ blur: CGFloat, _ y: CGFloat, _ a: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(a); s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: -y)
    s.set(); draw()
    NSGraphicsContext.restoreGraphicsState()
}

/// Draws in a 1024-point space. fullBleed = edge-to-edge square art for macOS 26 icons
/// (the system cuts the rounded shape itself); otherwise the classic rounded tile with margins.
func drawIcon(_ L: Look, fullBleed: Bool = false) {
    var tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    var body = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    if fullBleed {
        // Map the 824-point tile onto the whole canvas.
        let k: CGFloat = 1024 / 824
        let t = NSAffineTransform(); t.scale(by: k); t.translateX(by: -100, yBy: -100); t.concat()
        tile = tile.insetBy(dx: -2, dy: -2)
        body = NSBezierPath(rect: tile)
    } else {
        shadow(28, 12, 0.35) { L.bgBottom.setFill(); body.fill() }
    }
    NSGradient(starting: L.bgTop, ending: L.bgBottom)?.draw(in: body, angle: -90)
    NSGraphicsContext.saveGraphicsState(); body.addClip()
    NSGradient(colors: [L.sheen, L.sheen.withAlphaComponent(0)])?
        .draw(fromCenter: NSPoint(x: 400, y: 990), radius: 0, toCenter: NSPoint(x: 400, y: 990), radius: 640, options: [])
    NSGraphicsContext.restoreGraphicsState()
    if !fullBleed {
        let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
        rim.lineWidth = 4; NSColor.white.withAlphaComponent(0.12).setStroke(); rim.stroke()
    }

    // The card, tilted very slightly for life.
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform(); t.translateX(by: 512, yBy: 512); t.rotate(byDegrees: -4); t.translateX(by: -512, yBy: -512); t.concat()
    let r = NSRect(x: 302, y: 236, width: 420, height: 548), fold: CGFloat = 132, cr: CGFloat = 46
    let card = NSBezierPath()
    card.move(to: NSPoint(x: r.minX + cr, y: r.minY))
    card.line(to: NSPoint(x: r.maxX - cr, y: r.minY))
    card.appendArc(from: NSPoint(x: r.maxX, y: r.minY), to: NSPoint(x: r.maxX, y: r.minY + cr), radius: cr)
    card.line(to: NSPoint(x: r.maxX, y: r.maxY - fold))
    card.line(to: NSPoint(x: r.maxX - fold, y: r.maxY))
    card.line(to: NSPoint(x: r.minX + cr, y: r.maxY))
    card.appendArc(from: NSPoint(x: r.minX, y: r.maxY), to: NSPoint(x: r.minX, y: r.maxY - cr), radius: cr)
    card.line(to: NSPoint(x: r.minX, y: r.minY + cr))
    card.appendArc(from: NSPoint(x: r.minX, y: r.minY), to: NSPoint(x: r.minX + cr, y: r.minY), radius: cr)
    card.close()
    shadow(54, 26, 0.5) { L.cardBottom.setFill(); card.fill() }
    NSGradient(starting: L.cardTop, ending: L.cardBottom)?.draw(in: card, angle: -90)

    // Folded corner with a soft shadow under it.
    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: r.maxX, y: r.maxY - fold))
    flap.line(to: NSPoint(x: r.maxX - fold + 16, y: r.maxY - fold))
    flap.appendArc(from: NSPoint(x: r.maxX - fold, y: r.maxY - fold), to: NSPoint(x: r.maxX - fold, y: r.maxY - fold + 16), radius: 16)
    flap.line(to: NSPoint(x: r.maxX - fold, y: r.maxY))
    flap.close()
    shadow(18, 6, 0.0) {}
    NSGraphicsContext.saveGraphicsState(); card.addClip()
    let under = NSBezierPath(rect: NSRect(x: r.maxX - fold - 30, y: r.maxY - fold - 30, width: fold + 30, height: 30))
    NSGradient(starting: L.flapShade, ending: L.flapShade.withAlphaComponent(0))?.draw(in: under, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: L.flap, ending: L.cardTop)?.draw(in: flap, angle: 135)

    // Three written lines.
    for (k, w) in [(0, 240.0), (1, 300.0), (2, 196.0)] {
        let line = NSBezierPath(roundedRect: NSRect(x: r.minX + 58, y: r.maxY - 206 - CGFloat(k) * 66, width: CGFloat(w), height: 28), xRadius: 14, yRadius: 14)
        L.lines.setFill(); line.fill()
    }
    // The glowing pin: "kept".
    let dot = NSRect(x: r.minX + 58, y: r.minY + 62, width: 76, height: 76)
    NSGradient(colors: [L.pinGlow, L.pinGlow.withAlphaComponent(0)])?
        .draw(in: NSBezierPath(ovalIn: dot.insetBy(dx: -46, dy: -46)), relativeCenterPosition: .zero)
    shadow(10, 4, 0.25) { L.pin.setFill(); NSBezierPath(ovalIn: dot).fill() }
    NSColor.white.withAlphaComponent(0.55).setFill()
    NSBezierPath(ovalIn: NSRect(x: dot.minX + 20, y: dot.maxY - 34, width: 20, height: 14)).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func render(_ px: Int, _ L: Look, fullBleed: Bool = false) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = NSAffineTransform(); s.scale(by: CGFloat(px) / 1024); s.concat()
    drawIcon(L, fullBleed: fullBleed)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
for (folder, look) in [("light", lightLook), ("dark", darkLook)] {
    let dir = out.appendingPathComponent(folder)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for px in [16, 32, 64, 128, 256, 512, 1024] { try? render(px, look)?.write(to: dir.appendingPathComponent("\(px).png")) }
}
try? render(1024, lightLook)?.write(to: out.appendingPathComponent("Memo-1024.png"))
try? render(1024, darkLook)?.write(to: out.appendingPathComponent("Memo-1024-dark.png"))
try? render(1024, lightLook, fullBleed: true)?.write(to: out.appendingPathComponent("art-light.png"))
try? render(1024, darkLook, fullBleed: true)?.write(to: out.appendingPathComponent("art-dark.png"))
