// snapshot.swift: renders Memo screens off-screen (light + dark) without opening anything on the
// user's screen. Build: QA/snap.sh. Output: PNGs in the folder given as the first argument.
import AppKit
import SwiftUI

@main
enum Snap {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/private/tmp/tenax-snap")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let now = Date()
        func item(_ id: Int64, _ k: ClipKind, _ t: String, ago: Double, pinned: Bool = false, order: Int = 0,
                  src: String? = "Safari", cleaned: Bool = false, w: Int = 0, h: Int = 0) -> ClipItem {
            ClipItem(id: id, kind: k, text: t, html: nil, image: nil, width: w, height: h, source: src,
                     created: now.addingTimeInterval(-ago), used: now.addingTimeInterval(-ago),
                     pinned: pinned, pinOrder: order, bytes: 100, cleaned: cleaned)
        }
        let sample: [ClipItem] = [
            item(1, .text, "hello@lunashift.app", ago: 9000, pinned: true, order: 0, src: "Mail"),
            item(2, .text, "Thanks so much for getting back to me about the partnership, here are the details.\n\nThe app is live on the App Store this week. You get a free year, and your followers get a 7-day trial through your own link.\n\nPosting once a week is all we ask. Tell me which days suit you and I will send the links and a short guide.\n\nSpeak soon,\nSolomon", ago: 4000, pinned: true, order: 1, src: "Notes"),
            item(3, .link, "https://apps.apple.com/app/luna-shift/id6809570772", ago: 20, cleaned: true),
            item(4, .image, "", ago: 140, src: "Screenshot", w: 1440, h: 900),
            item(5, .color, "#2DD4BF", ago: 600, src: "Figma"),
            item(6, .file, "/Users/you/Desktop/Report.pdf\n/Users/you/Desktop/Notes.txt", ago: 3700, src: "Finder"),
            item(7, .text, "line one\nline two\nline three", ago: 90_000, src: "Terminal"),
            item(8, .text, "A very long piece of copied text that should never overflow the row or push the number badge off the edge of the panel at all", ago: 200_000, src: "Claude"),
            item(9, .link, "https://example.com/page?id=5", ago: 300_000),
            item(10, .text, "Tenth item to show no number badge", ago: 400_000, src: nil),
        ]
        func shoot(_ name: String, _ view: some View, dark: Bool, size: NSSize? = nil, settle: Double = 0.6) {
            let host = NSHostingView(rootView: AnyView(view.background(Color(nsColor: dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.975, alpha: 1)))))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let fit = size ?? host.fittingSize
            let w = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: fit.width, height: fit.height),
                             styleMask: .borderless, backing: .buffered, defer: false)
            w.appearance = host.appearance
            w.backgroundColor = dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.97, alpha: 1)
            w.contentView = host
            w.orderBack(nil)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(settle))   // let springs settle
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            w.orderOut(nil)
            print("wrote \(name) \(Int(fit.width))x\(Int(fit.height))")
        }
        for dark in [false, true] {
            let m = TenaxModel(); m.paused = false; m.accentIndex = 0; m.items = sample; m.accessibilityOK = true; m.selectedID = 3
            shoot("popover", PopoverView(model: m), dark: dark)
            let x = TenaxModel(); x.paused = false; x.items = sample; x.accessibilityOK = true; x.expand(2)
            shoot("expanded", PopoverView(model: x), dark: dark)
            let xc = TenaxModel(); xc.paused = false; xc.items = sample; xc.accessibilityOK = true; xc.expand(5)
            shoot("expanded-colour", PopoverView(model: xc), dark: dark)
            for p in 0..<IntroView.pages {
                let im = TenaxModel(); im.accessibilityOK = p == 2
                shoot("intro-\(p + 1)", IntroView(model: im, finish: { _ in }, page: p), dark: dark, settle: 1.6)
            }
            let s = TenaxModel(); s.paused = false; s.items = sample; s.query = "lun"; s.accessibilityOK = true
            shoot("search", PopoverView(model: s), dark: dark)
            let e = TenaxModel(); e.items = []; e.paused = true; e.accessibilityOK = false; e.pasteDirectly = true
            shoot("empty-paused", PopoverView(model: e), dark: dark)
            let st = TenaxModel(); st.paused = false; st.storageText = "12.4 MB"; st.accessibilityOK = false
            st.ignored = [IgnoredApp(bundle: "com.apple.Safari", name: "Safari")]
            shoot("settings", SettingsView(model: st), dark: dark, size: NSSize(width: 480, height: 640))
            let st2 = TenaxModel(); st2.paused = false; st2.storageText = "12.4 MB"
            shoot("settings-full", ScrollView { SettingsView(model: st2).frame(height: 1400) }.frame(width: 480, height: 1400), dark: dark, size: NSSize(width: 480, height: 1400))
        }
        exit(0)
    }
}
