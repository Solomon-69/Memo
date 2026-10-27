// PopoverView.swift. The Memo panel: search, pinned items, recent history.
import AppKit
import SwiftUI

/// One app colour, chosen in Settings. Each has a light-mode and a dark-mode shade.
struct AccentChoice {
    let name: String
    let ns: NSColor
    var color: Color { Color(nsColor: ns) }

    init(_ name: String, light: UInt32, dark: UInt32) {
        func c(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                    blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        let l = c(light), d = c(dark)
        self.name = name
        ns = NSColor(name: name) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l }
    }
}

/// Navy is the default (Solomon, 22 Oct 2026).
let accentChoices: [AccentChoice] = [
    AccentChoice("Navy", light: 0x1E3A8A, dark: 0x5876D6),
    AccentChoice("Ocean", light: 0x0A6CD6, dark: 0x4FA3FF),
    AccentChoice("Teal", light: 0x0E9F8E, dark: 0x2DD4BF),
    AccentChoice("Violet", light: 0x6D4BD8, dark: 0xA48BFF),
    AccentChoice("Rose", light: 0xC72C5B, dark: 0xFF6F93),
    AccentChoice("Ember", light: 0xD06A00, dark: 0xFF9F0A),
    AccentChoice("Moss", light: 0x2F7D3A, dark: 0x5FD06E),
    AccentChoice("Graphite", light: 0x3F4652, dark: 0xB4BCC8),
]

func accentChoice(_ i: Int) -> AccentChoice { accentChoices.indices.contains(i) ? accentChoices[i] : accentChoices[0] }

private struct TenaxAccentKey: EnvironmentKey { static let defaultValue = accentChoices[0].color }
extension EnvironmentValues {
    var tenaxAccent: Color {
        get { self[TenaxAccentKey.self] }
        set { self[TenaxAccentKey.self] = newValue }
    }
}
let panelSpring = Animation.spring(duration: 0.42, bounce: 0.18)

struct PopoverView: View {
    @ObservedObject var model: TenaxModel
    private var accent: Color { accentChoice(model.accentIndex).color }
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let width: CGFloat = 380
    static let listHeight: CGFloat = 392
    static let topID: Int64 = -1

    var body: some View {
        VStack(spacing: 8) {
            searchBar
            if model.paused { pausedBanner.transition(.move(edge: .top).combined(with: .opacity)) }
            if model.pasteDirectly && !model.accessibilityOK { permissionBanner }
            list
            footer
        }
        .padding(10)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .animation(reduceMotion ? nil : panelSpring, value: model.paused)
        .environment(\.tenaxAccent, accent)
        .tint(accent)
        .onChange(of: model.openCount) { _ in searchFocused = true }
        .onAppear { searchFocused = true }
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search history", text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .noFocusRing()
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
                    .help("Clear search")
            } else if let s = model.shortcut {
                Text(s.display).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(searchFocused ? accent.opacity(0.5) : Color.primary.opacity(0.07), lineWidth: 1))
    }

    private var pausedBanner: some View {
        HStack(spacing: 8) {
            IconTile(symbol: "pause.fill", size: 22)
            Text("Recording is paused").font(.system(size: 12, weight: .medium))
            Spacer()
            Button("Resume") { model.paused = false }.buttonStyle(PillButtonStyle())
        }
        .padding(8)
        .cardStyle()
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            IconTile(symbol: "hand.raised.fill", size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Allow pasting into apps").font(.system(size: 12, weight: .medium))
                Text("Until then Memo copies, and you press ⌘V.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Allow…") { model.onAskPermission() }.buttonStyle(PillButtonStyle())
        }
        .padding(8)
        .cardStyle()
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    Color.clear.frame(height: 0).id(PopoverView.topID)
                    if let err = model.errorText {
                        Text(err).font(.system(size: 12)).foregroundStyle(.red).padding(8)
                    }
                    if model.visible.isEmpty { emptyState }
                    let pins = model.searching ? [] : model.pinned
                    if !pins.isEmpty { sectionLabel("Pinned") }
                    ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, item in
                        if !pins.isEmpty, index == pins.count { sectionLabel("Recent") }
                        row(item, index: index)
                    }
                }
                .padding(.vertical, 2)
                .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82), value: model.visible.map(\.id))
            }
            .frame(height: Self.listHeight)
            .onChange(of: model.scrollTarget) { target in
                guard let target else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(target, anchor: nil) }
            }
            .onChange(of: model.openCount) { _ in
                proxy.scrollTo(PopoverView.topID, anchor: .top)
            }
        }
    }

    private func row(_ item: ClipItem, index: Int) -> some View {
        ClipRow(item: item, number: index < 9 ? index + 1 : nil,
                selected: item.id == model.selectedID, expanded: model.expandedID == item.id, model: model)
            .id(item.id)
            .entrance(index: index, trigger: model.openCount)
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 4).padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            IconTile(symbol: model.searching ? "magnifyingglass" : "doc.on.clipboard", size: 34)
            Text(model.searching ? "Nothing matches “\(model.query)”" : "Nothing copied yet")
                .font(.system(size: 13, weight: .medium))
            Text(model.searching ? "Try fewer letters." : "Copy some text, a link or a picture and it shows up here.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 110)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 4) {
            Button { model.paused.toggle() } label: {
                Label(model.paused ? "Resume" : "Pause", systemImage: model.paused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(QuietButtonStyle())
            .help(model.paused ? "Start saving what you copy again" : "Stop saving what you copy for now")
            Spacer()
            Text("↩ Paste  → Expand  ⌘1–9").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button { model.onOpenSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(QuietButtonStyle())
                .help("Settings")
            Button("Quit") { model.onQuit() }.buttonStyle(QuietButtonStyle())
        }
    }
}

// MARK: - Row

struct ClipRow: View {
    let item: ClipItem
    let number: Int?
    let selected: Bool
    let expanded: Bool
    @ObservedObject var model: TenaxModel
    @State private var hover = false
    @State private var copied = false
    @Environment(\.tenaxAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                ClipDetail(item: item, text: model.expandedText, total: model.expandedTotal)
                    .padding(.top, 8)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(selected ? accent.opacity(0.14) : Color.primary.opacity(hover ? 0.075 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(selected ? accent.opacity(0.55) : Color.primary.opacity(0.07), lineWidth: 1))
        .overlay(alignment: .leading) {
            // Pinned rows carry a bar in the app colour down their left edge.
            if item.pinned {
                Capsule().fill(accent).frame(width: 3).padding(.vertical, 10).padding(.leading, 2)
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onHover { h in
            hover = h
            // Only a real mouse move selects (not the row that happens to sit under the pointer on open).
            if h, model.mouseMovedSinceOpen() { model.selectedID = item.id }
        }
        .contextMenu { menuItems }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: item.pinned)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84), value: expanded)
    }

    /// The one-line summary. Clicking it pastes; the chevron opens the full text instead.
    private var header: some View {
        HStack(spacing: 10) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(ClipText.title(item)).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                Text(ClipText.subtitle(item)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.kind == .image, let name = item.image, let thumb = Store.shared.thumbnail(name) {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 30).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            }
            copyButton
            pinButton
            if selected || hover { moreMenu }
            if selected || hover || expanded { expandButton }
            if let number {
                Text("\(number)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(selected ? accent : Color.secondary)
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let opt = NSEvent.modifierFlags.contains(.option)
            model.onPaste(item, opt ? .plain : .normal)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var copyButton: some View {
        Button {
            model.onCopy(item)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: copied ? .bold : .regular))
                .foregroundStyle(copied ? accent : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowIconButtonStyle())
        .help(copied ? "Copied" : "Copy")
        .accessibilityLabel(copied ? "Copied" : "Copy")
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: copied)
    }

    private var pinButton: some View {
        Button { model.onPin(item) } label: {
            Image(systemName: item.pinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(item.pinned ? accent : Color.secondary)
                .rotationEffect(.degrees(item.pinned ? 0 : 45))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(RowIconButtonStyle())
        .help(item.pinned ? "Unpin" : "Pin")
        .accessibilityLabel(item.pinned ? "Unpin" : "Pin")
    }

    private var expandButton: some View {
        Button { model.toggleExpand(item.id) } label: {
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(expanded ? accent : Color.secondary)
                .rotationEffect(.degrees(expanded ? 180 : 0))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(expanded ? "Show less (←)" : "Show everything (→ or Space)")
        .accessibilityLabel(expanded ? "Show less" : "Show everything")
    }

    @ViewBuilder private var menuItems: some View {
        Button("Paste") { model.onPaste(item, .normal) }
        if item.kind != .image {
            Button("Paste as plain text") { model.onPaste(item, .plain) }
            Button("Paste as Markdown") { model.onPaste(item, .markdown) }
        }
        Divider()
        Button(expanded ? "Show less" : "Show everything") { model.toggleExpand(item.id) }
        Button(item.pinned ? "Unpin" : "Pin to top") { model.onPin(item) }
        Button("Delete") { model.onDelete(item) }
    }

    private var moreMenu: some View {
        Menu { menuItems } label: {
            Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More ways to paste")
    }

    @ViewBuilder private var tile: some View {
        if item.kind == .color, let c = ColorText.nsColor(item.text) {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: c))
                .frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
        } else {
            IconTile(symbol: ClipText.symbol(item.kind), size: 28)
        }
    }
}

/// What an opened row shows: the whole text (selectable), a big image, every file, or the colour.
struct ClipDetail: View {
    let item: ClipItem
    let text: String
    let total: Int
    @State private var image: NSImage?
    static let maxHeight: CGFloat = 230

    var body: some View {
        switch item.kind {
        case .image: imageView
        case .color: colorView
        default: textView
        }
    }

    private var textView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.vertical) {
                Text(text)
                    .font(.system(size: 12, design: item.kind == .text ? .default : .monospaced))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: Self.height(for: text))
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            Text(footnote).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var footnote: String {
        let lines = text.split(whereSeparator: \.isNewline).count
        var s = "\(total.formatted()) characters"
        if lines > 1 { s += " · \(lines.formatted()) lines" }
        if total > text.count { s += " · showing the first \(text.count.formatted())" }
        return s
    }

    /// Short texts get a short box; long ones scroll inside a box of at most maxHeight.
    static func height(for text: String) -> CGFloat {
        let perLine = 50   // characters that fit on one line of the box
        var lines = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lines += max(1, (line.count + perLine - 1) / perLine)
            if lines > 20 { break }
        }
        return min(maxHeight, CGFloat(lines) * 17 + 18)
    }

    private var imageView: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Self.maxHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)).frame(height: 120)
            }
        }
        .task(id: item.id) {
            guard let name = item.image else { return }
            let url = Store.shared.imageURL(name)
            image = await Task.detached { NSImage(contentsOf: url) }.value
        }
    }

    private var colorView: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: ColorText.nsColor(item.text) ?? .clear))
                .frame(height: 56)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
        }
    }
}

/// Small round icon button in a row: soft circle on hover, presses down a little.
struct RowIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { IconBody(configuration: configuration) }
    private struct IconBody: View {
        let configuration: Configuration
        @State private var hover = false
        var body: some View {
            configuration.label
                .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : hover ? 0.08 : 0)))
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
                .onHover { hover = $0 }
        }
    }
}

// MARK: - Text helpers

enum ClipText {
    static func symbol(_ k: ClipKind) -> String {
        switch k {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .color: return "paintpalette"
        }
    }

    static func title(_ item: ClipItem) -> String {
        switch item.kind {
        case .image: return "Image \(item.width) × \(item.height)"
        case .file:
            let paths = item.text.split(separator: "\n")
            let first = URL(fileURLWithPath: String(paths.first ?? "")).lastPathComponent
            return paths.count > 1 ? "\(first) and \(paths.count - 1) more" : first
        case .color: return item.text.uppercased()
        case .link:
            var s = item.text
            for p in ["https://", "http://", "www."] where s.hasPrefix(p) { s.removeFirst(p.count) }
            return s
        case .text:
            let line = item.text.split(whereSeparator: \.isNewline)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            return String(line.trimmingCharacters(in: .whitespaces).prefix(160))
        }
    }

    static func subtitle(_ item: ClipItem) -> String {
        var parts = [item.kind.label]
        if item.kind == .text {
            let lines = item.text.split(whereSeparator: \.isNewline).count
            if lines > 1 { parts.append("\(lines) lines") }
        }
        if item.cleaned { parts.append("tracking removed") }
        if let s = item.source, !s.isEmpty { parts.append(s) }
        parts.append(ago(item.used))
        return parts.joined(separator: " · ")
    }

    static func ago(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86_400 { return "\(s / 3600) h ago" }
        if s < 172_800 { return "yesterday" }
        return "\(s / 86_400) days ago"
    }
}

// MARK: - Shared pieces

/// A rounded tile with a white symbol, always in the app colour.
struct IconTile: View {
    let symbol: String
    var size: CGFloat = 28
    @Environment(\.tenaxAccent) private var accent
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(accent.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(.white))
    }
}

struct QuietButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(hover ? Color.primary : Color.secondary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hover ? 0.08 : 0)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
            .onHover { hover = $0 }
    }
}

struct PillButtonStyle: ButtonStyle {
    @State private var hover = false
    @Environment(\.tenaxAccent) private var accent
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(accent.opacity(hover ? 0.9 : 1)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
            .onHover { hover = $0 }
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.055)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

/// Rows rise in one after another each time the panel opens.
struct Entrance: ViewModifier {
    let index: Int
    let trigger: Int
    @State private var shown = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onChange(of: trigger) { _ in
                guard !reduceMotion, index < 12 else { return }
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { shown = false }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8).delay(0.03 + Double(index) * 0.022)) { shown = true }
            }
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
    func entrance(index: Int, trigger: Int) -> some View { modifier(Entrance(index: index, trigger: trigger)) }
}
