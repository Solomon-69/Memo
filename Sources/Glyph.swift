// Glyph.swift. The menu bar icon: two overlapping cards (the "copy" shape). When something is
// copied, a tick draws itself inside the front card, holds, then fades.
//
// Drawn in its own view on the status button (never by swapping the button image every frame,
// which leaves ghost copies on macOS 26).
import AppKit

final class TenaxGlyphView: NSView {
    var paused = false { didSet { needsDisplay = true } }
    private var tick: CGFloat = 0          // 0...1 how much of the tick is drawn
    private var tickAlpha: CGFloat = 0
    private var animTimer: Timer?
    private var started = Date()

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // clicks go to the button

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        // 16 pt drawing centred in the button.
        let ox = (bounds.width - 16) / 2, oy = (bounds.height - 16) / 2
        let ink = NSColor.labelColor.withAlphaComponent(paused ? 0.45 : 1)
        ink.setStroke()

        let front = NSRect(x: ox + 5.5, y: oy + 5.0, width: 8, height: 8.5)
        let back = NSRect(x: ox + 2.5, y: oy + 2.0, width: 8, height: 8.5)

        // Back card: only the part not covered by the front card (with a small gap).
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(rect: bounds)
        clip.append(NSBezierPath(roundedRect: front.insetBy(dx: -1.6, dy: -1.6), xRadius: 3, yRadius: 3))
        clip.windingRule = .evenOdd
        clip.addClip()
        let b = NSBezierPath(roundedRect: back, xRadius: 2, yRadius: 2)
        b.lineWidth = 1.5
        b.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let f = NSBezierPath(roundedRect: front, xRadius: 2, yRadius: 2)
        f.lineWidth = 1.5
        f.stroke()

        if paused {
            // Two small bars in the front card.
            for x in [ox + 8.2, ox + 10.6] {
                let bar = NSBezierPath()
                bar.move(to: NSPoint(x: x, y: oy + 7.6)); bar.line(to: NSPoint(x: x, y: oy + 11.0))
                bar.lineWidth = 1.4; bar.lineCapStyle = .round
                bar.stroke()
            }
        }

        if tick > 0, tickAlpha > 0 {
            let pts = [NSPoint(x: ox + 7.4, y: oy + 9.4), NSPoint(x: ox + 9.0, y: oy + 11.0), NSPoint(x: ox + 11.8, y: oy + 7.6)]
            let l1 = hypot(pts[1].x - pts[0].x, pts[1].y - pts[0].y)
            let l2 = hypot(pts[2].x - pts[1].x, pts[2].y - pts[1].y)
            var left = (l1 + l2) * tick
            let p = NSBezierPath()
            p.move(to: pts[0])
            let a = min(left, l1) / l1
            p.line(to: NSPoint(x: pts[0].x + (pts[1].x - pts[0].x) * a, y: pts[0].y + (pts[1].y - pts[0].y) * a))
            left -= l1
            if left > 0 {
                let c = min(left, l2) / l2
                p.line(to: NSPoint(x: pts[1].x + (pts[2].x - pts[1].x) * c, y: pts[1].y + (pts[2].y - pts[1].y) * c))
            }
            p.lineWidth = 1.6; p.lineCapStyle = .round; p.lineJoinStyle = .round
            NSColor.labelColor.withAlphaComponent(tickAlpha).setStroke()
            p.stroke()
        }
    }

    /// The "copied" tick: draws in 0.28 s, holds 1.2 s, fades in 0.2 s.
    func playTick(reduceMotion: Bool) {
        animTimer?.invalidate()
        started = Date()
        if reduceMotion {
            tick = 1; tickAlpha = 1; needsDisplay = true
            animTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                self?.tickAlpha = 0; self?.needsDisplay = true
            }
            return
        }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let e = Date().timeIntervalSince(self.started)
            let draw = min(1, e / 0.28)
            self.tick = CGFloat(1 - pow(1 - draw, 3))          // ease out
            self.tickAlpha = e < 1.48 ? 1 : CGFloat(max(0, 1 - (e - 1.48) / 0.2))
            self.needsDisplay = true
            if e > 1.7 { self.tick = 0; self.tickAlpha = 0; timer.invalidate() }
        }
        RunLoop.main.add(t, forMode: .common)
        animTimer = t
    }
}
