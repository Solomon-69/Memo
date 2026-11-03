// SettingsNav.swift. Arrow-key walk through Settings: Up/Down moves a soft highlight from row to row
// (wrapping), Left/Right or Space/Return changes the highlighted row, Esc closes the window.
// Ignored while a text field has the keyboard or the shortcut recorder is listening.
import AppKit
import SwiftUI

struct NavAction {
    var step: (Int) -> Void
    var activate: () -> Void
}

extension Notification.Name {
    static let memoStartRecording = Notification.Name("MemoStartRecording")
}

@MainActor final class SettingsNav: ObservableObject {
    @Published var current: String?
    var actions: [String: NavAction] = [:]
    var frames: [String: CGRect] = [:]
    var reveal: ((String) -> Void)?
    /// Set by the shortcut recorder while it is listening, so arrows and Esc reach it instead.
    static var recordingShortcut = false

    /// Rows top to bottom, as they are laid out now.
    func order() -> [String] {
        actions.keys.filter { frames[$0] != nil }.sorted { frames[$0]!.minY < frames[$1]!.minY }
    }

    func move(_ d: Int) {
        let ids = order()
        guard !ids.isEmpty else { return }
        let i = current.flatMap { ids.firstIndex(of: $0) }
        let n = i.map { ($0 + d + ids.count) % ids.count } ?? (d > 0 ? 0 : ids.count - 1)
        current = ids[n]
        reveal?(ids[n])
    }

    /// True when the key was used.
    func handle(_ e: NSEvent, in window: NSWindow?) -> Bool {
        guard let window, e.window === window, window.isKeyWindow, !Self.recordingShortcut else { return false }
        guard e.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        if let r = window.firstResponder, r is NSTextView || r is NSTextField { return false }
        switch e.keyCode {
        case 126: move(-1)
        case 125: move(1)
        case 123: current.flatMap { actions[$0] }?.step(-1)
        case 124: current.flatMap { actions[$0] }?.step(1)
        case 49, 36, 76: current.flatMap { actions[$0] }?.activate()
        case 53: window.performClose(nil)
        default: return false
        }
        return true
    }
}

private struct NavKey: EnvironmentKey { static let defaultValue: SettingsNav? = nil }
extension EnvironmentValues {
    var settingsNav: SettingsNav? {
        get { self[NavKey.self] }
        set { self[NavKey.self] = newValue }
    }
}

struct NavFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct NavRow: ViewModifier {
    let id: String
    let action: NavAction
    @Environment(\.settingsNav) private var nav

    func body(content: Content) -> some View {
        content
            .id("nav-\(id)")
            .background(GeometryReader { g in
                Color.clear.preference(key: NavFramesKey.self, value: [id: g.frame(in: .named("settingsContent"))])
            })
            .onAppear { nav?.actions[id] = action }
    }
}

extension View {
    /// Makes a Settings row reachable with the arrow keys.
    func nav(_ id: String, step: @escaping (Int) -> Void = { _ in }, activate: @escaping () -> Void) -> some View {
        modifier(NavRow(id: id, action: NavAction(step: step, activate: activate)))
    }
}

/// Finds the window this view lives in, and listens for keys while it is on screen.
struct NavKeys: NSViewRepresentable {
    let nav: SettingsNav
    func makeNSView(context: Context) -> Probe { Probe(nav: nav) }
    func updateNSView(_ v: Probe, context: Context) {}

    final class Probe: NSView {
        let nav: SettingsNav
        private var monitor: Any?
        init(nav: SettingsNav) { self.nav = nav; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self else { return e }
                return MainActor.assumeIsolated { self.nav.handle(e, in: self.window) } ? nil : e
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}
