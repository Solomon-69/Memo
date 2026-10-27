// Intro.swift. The welcome window shown once after installing Memo: what it is, the one-time
// "paste for you" permission, and the shortcut. Three pages, skippable, springs throughout.
import AppKit
import SwiftUI

enum IntroPref {
    static let done = "introDone"
}

/// Each element of a page rises in a little after the one above it.
struct IntroRise: ViewModifier {
    let index: Int
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .blur(radius: shown || reduceMotion ? 0 : 4)
            .animation(reduceMotion ? .easeOut(duration: 0.2)
                       : .spring(response: 0.55, dampingFraction: 0.84).delay(0.08 + Double(index) * 0.07), value: shown)
    }
}

/// Frosted-glass panel on a plain soft backdrop. Nothing from the screen shows through it.
struct IntroGlass: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(dark ? 0.50 : 0.60)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(dark ? 0.20 : 0.85), Color.white.opacity(dark ? 0.04 : 0.15)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(dark ? 0.45 : 0.16), radius: 22, y: 12)
    }
}

extension View {
    func introGlass() -> some View { modifier(IntroGlass()) }
    func introRise(_ index: Int, _ shown: Bool) -> some View { modifier(IntroRise(index: index, shown: shown)) }
}

struct IntroView: View {
    @ObservedObject var model: TenaxModel
    let finish: (_ openPanel: Bool) -> Void
    @State var page = 0
    @State private var shown = false
    @State private var seen: Set<Int> = [0]     // pages whose rise-in already played; it never replays
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var accent: Color { accentChoice(model.accentIndex).color }
    static let pages = 3

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: welcome.transition(slide)
                case 1: permission.transition(slide)
                default: ready.transition(slide)
                }
            }
            .padding(.vertical, 10)
            .frame(height: 392, alignment: .top)
            .clipped()
            footer
        }
        .padding(.horizontal, 22).padding(.top, 26).padding(.bottom, 16)
        .introGlass()
        .padding(16)
        .frame(width: 456)
        .background(backdrop)
        .environment(\.tenaxAccent, accent)
        .tint(accent)
        .onAppear { shown = true }
    }

    private var slide: AnyTransition {
        reduceMotion ? .opacity
            : .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                          removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    /// Plain soft wash of the app colour. Opaque, so nothing behind the window shows.
    private var backdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [accent.opacity(0.30), accent.opacity(0)], center: .topLeading, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color.blue.opacity(0.18), Color.blue.opacity(0)], center: .bottomTrailing, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 92, height: 92)
                .shadow(color: accent.opacity(0.35), radius: 16, y: 8)
                .scaleEffect(shown || reduceMotion ? 1 : 0.55)
                .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.6).delay(0.05), value: shown)
                .introRise(0, shown)
            Text("Welcome to Memo").font(.system(size: 24, weight: .semibold, design: .rounded)).introRise(1, shown)
            Text("Everything you copy, one shortcut away.").font(.system(size: 13)).foregroundStyle(.secondary)
                .introRise(2, shown)
            VStack(spacing: 8) {
                feature("keyboard", "Press \(shortcutText) anywhere", "Your history opens right under the menu bar.").introRise(3, shown)
                feature("pin.fill", "Pin what you use every day", "Pinned items stay at the top.").introRise(4, shown)
                feature("lock.fill", "Stays on your Mac", "Passwords are skipped. Nothing is ever uploaded.").introRise(5, shown)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var permission: some View {
        VStack(spacing: 14) {
            IconTile(symbol: "hand.point.up.left.fill", size: 64).introRise(0, shown)
            Text("Paste straight into apps").font(.system(size: 22, weight: .semibold, design: .rounded)).introRise(1, shown)
            Text("Pick an item and Memo types it where your cursor is. macOS asks you once to allow this, in Privacy & Security under Accessibility.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .introRise(2, shown)
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(model.accessibilityOK ? accent : Color.primary.opacity(0.08))
                    Image(systemName: model.accessibilityOK ? "checkmark" : "hand.raised")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(model.accessibilityOK ? Color.white : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.accessibilityOK ? "Allowed" : "Not allowed yet").font(.system(size: 13, weight: .medium))
                    Text(model.accessibilityOK ? "Memo can paste for you." : "Until then Memo copies, and you press ⌘V.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if !model.accessibilityOK {
                    Button("Allow…") { model.onAskPermission() }.buttonStyle(PillButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(12)
            .cardStyle()
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: model.accessibilityOK)
            .introRise(3, shown)
            Text("You can change this any time in Memo's Settings.").font(.system(size: 11)).foregroundStyle(.secondary)
                .introRise(4, shown)
        }
        .frame(maxWidth: .infinity)
    }

    private var ready: some View {
        VStack(spacing: 12) {
            IconTile(symbol: "checkmark", size: 64)
                .scaleEffect(shown || reduceMotion ? 1 : 0.5)
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55), value: shown)
                .introRise(0, shown)
            Text("You're all set").font(.system(size: 24, weight: .semibold, design: .rounded)).introRise(1, shown)
            HStack(spacing: 6) {
                ForEach(Array(shortcutKeys.enumerated()), id: \.offset) { i, key in
                    Text(key)
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .frame(minWidth: 40, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                        .shadow(color: .black.opacity(0.06), radius: 0, y: 2)
                        .introRise(2 + i, shown)
                }
            }
            VStack(spacing: 8) {
                feature("doc.on.clipboard", "Copy as usual", "Memo keeps it. Press the shortcut to see your history.").introRise(5, shown)
                feature("magnifyingglass", "Type to find anything", "Search your history, then press Return to paste.").introRise(6, shown)
                feature("gearshape.fill", "Make it yours", "Colour, shortcut and how long to keep items: Settings.").introRise(7, shown)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .cardStyle()
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if page < Self.pages - 1 {
                IntroQuietLink(title: "Skip") { finish(false) }
            } else {
                IntroQuietLink(title: "Back") { go(page - 1) }
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<Self.pages, id: \.self) { i in
                    Capsule().fill(i == page ? accent : Color.primary.opacity(0.18))
                        .frame(width: i == page ? 18 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: page)
            Spacer()
            Button { page < Self.pages - 1 ? go(page + 1) : finish(true) } label: {
                Text(page < Self.pages - 1 ? "Continue" : "Open Memo")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 34)
                    .background(Capsule().fill(accent))
            }
            .buttonStyle(IntroPressStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private func go(_ p: Int) {
        guard (0..<Self.pages).contains(p) else { return }
        forward = p > page
        let first = !seen.contains(p)
        seen.insert(p)
        if first { shown = false }                  // only a page seen for the first time rises in
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86)) { page = p }
        if first { DispatchQueue.main.async { shown = true } }
    }

    private var shortcutText: String { model.shortcut?.display ?? "the shortcut" }
    private var shortcutKeys: [String] {
        guard let s = model.shortcut?.display else { return ["⌃", "⌘", "V"] }
        return s.map(String.init).reduce(into: [String]()) { keys, ch in
            // Modifier symbols are one key each; the rest (e.g. "F12", "Space") is one key.
            if "⌃⌥⇧⌘".contains(ch) || keys.isEmpty || "⌃⌥⇧⌘".contains(keys.last!) { keys.append(ch) } else { keys[keys.count - 1] += ch }
        }
    }
}

struct IntroPressStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(hover ? 0.05 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { hover = $0 }
    }
}

/// Skip / Back: a plain tappable label, so macOS never draws a keyboard focus box around it.
struct IntroQuietLink: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    @State private var pressed = false
    var body: some View {
        Text(title)
            .font(.system(size: 12))
            .foregroundStyle(hover ? Color.primary : Color.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hover ? 0.08 : 0)))
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: pressed)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { action() }
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in pressed = true }.onEnded { _ in pressed = false })
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(title)
    }
}
