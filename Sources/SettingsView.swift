// SettingsView.swift. Memo Settings: same card rows as Nox and Awayke. Everything saves instantly.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: TenaxModel
    @State private var confirmClear = false
    private var accent: Color { accentChoice(model.accentIndex).color }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header
                group("Look") {
                    SettingRow(symbol: "paintpalette.fill", title: "App colour",
                               subtitle: accentChoice(model.accentIndex).name) {
                        AccentDots(selected: model.accentIndex) { model.accentIndex = $0 }
                    }
                }
                group("General") {
                    SettingRow(symbol: "command", title: "Open Memo",
                               subtitle: model.shortcutProblem ?? "Press this anywhere to open your history") {
                        ShortcutRecorder(model: model)
                    }
                    SettingRow(symbol: "power", title: "Open at login",
                               subtitle: "Start Memo when your Mac starts") {
                        SmoothSwitch(isOn: model.launchAtLogin, title: "Open at login", tint: accent) { want in
                            model.launchAtLogin = want
                            DispatchQueue.main.async { model.onLogin(want) }
                        }
                    }
                    SettingRow(symbol: "arrow.down.doc", title: "Paste straight into the app",
                               subtitle: model.accessibilityOK ? "Allowed" : "Needs your OK in Privacy & Security") {
                        HStack(spacing: 8) {
                            if model.pasteDirectly && !model.accessibilityOK {
                                Button("Allow…") { model.onAskPermission() }.buttonStyle(PillButtonStyle())
                            }
                            SmoothSwitch(isOn: model.pasteDirectly, title: "Paste straight into the app", tint: accent) {
                                model.pasteDirectly = $0
                            }
                        }
                    }
                }
                group("Share") { MemoShareRow() }
                group("History") {
                    pickerCard(symbol: "calendar", title: "Keep items for",
                               subtitle: "Older ones are removed. Pinned items stay.") {
                        NumberChipDrum(title: "Keep for", value: model.keepDays, values: [0] + Array(1...365),
                                       presets: [1, 7, 30, 90, 365, 0], tint: accent,
                                       label: { $0 == 0 ? "Forever" : ($0 == 1 ? "1 day" : "\($0) days") },
                                       short: { $0 == 0 ? "∞" : "\($0)" }) { model.keepDays = $0 }
                    }
                    pickerCard(symbol: "list.number", title: "Keep at most",
                               subtitle: "The oldest go first when the list is full.") {
                        NumberChipDrum(title: "Items", value: model.maxItems, values: Array(stride(from: 50, through: 5000, by: 50)),
                                       presets: [100, 250, 500, 1000, 2500, 5000], tint: accent,
                                       label: { "\($0) items" }, short: { "\($0)" }) { model.maxItems = $0 }
                    }
                    pickerCard(symbol: "externaldrive", title: "Size limit",
                               subtitle: "History never grows past this.") {
                        NumberChipDrum(title: "Limit", value: model.maxMB, values: Array(stride(from: 50, through: 2000, by: 50)),
                                       presets: [100, 250, 500, 1000], tint: accent,
                                       label: { $0 >= 1000 && $0 % 1000 == 0 ? "\($0 / 1000) GB" : "\($0) MB" },
                                       short: { "\($0)" }) { model.maxMB = $0 }
                    }
                    SettingRow(symbol: "chart.pie", title: "History uses \(model.storageText)",
                               subtitle: "Stored only on this Mac") {
                        Button("Clear history…") { confirmClear = true }.buttonStyle(QuietButtonStyle())
                    }
                }
                group("Privacy") {
                    SettingRow(symbol: "key.fill", title: "Skip passwords and secrets",
                               subtitle: "Ignores password managers and hidden clipboard items") {
                        SmoothSwitch(isOn: model.skipSecrets, title: "Skip passwords", tint: accent) { model.skipSecrets = $0 }
                    }
                    SettingRow(symbol: "link", title: "Clean links",
                               subtitle: "Removes tracking bits like utm_source and fbclid") {
                        SmoothSwitch(isOn: model.cleanLinks, title: "Clean links", tint: accent) { model.cleanLinks = $0 }
                    }
                    SettingRow(symbol: "pause.fill", title: "Pause recording",
                               subtitle: model.paused ? "Paused: nothing new is saved" : "Saving what you copy") {
                        SmoothSwitch(isOn: model.paused, title: "Pause recording", tint: accent) { model.paused = $0 }
                    }
                    ignoredCard
                }
                Text("Nothing you copy ever leaves this Mac.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 4)
            }
            .padding(18)
        }
        .frame(width: 480, height: 640)
        .environment(\.tenaxAccent, accent)
        .tint(accent)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.accentIndex)
        .alert("Clear history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { model.onClearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything except pinned items is removed. This can't be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Memo").font(.system(size: 18, weight: .semibold))
                Text("Your clipboard history").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            content()
        }
        .padding(.top, 6)
    }

    private func pickerCard<C: View>(symbol: String, title: String, subtitle: String,
                                     @ViewBuilder _ picker: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RowLabel(symbol: symbol, title: title, subtitle: subtitle)
            picker()
        }
        .padding(12)
        .cardStyle()
    }

    private var ignoredCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                RowLabel(symbol: "eye.slash.fill", title: "Ignore these apps",
                         subtitle: "Nothing copied in them is saved")
                Spacer()
                Menu("Add app") {
                    ForEach(runningApps, id: \.bundle) { app in
                        Button(app.name) { add(app) }
                    }
                    Divider()
                    Button("Choose from Applications…") { chooseApp() }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            ForEach(model.ignored) { app in
                HStack(spacing: 8) {
                    appIcon(app.bundle).resizable().frame(width: 18, height: 18)
                    Text(app.name).font(.system(size: 12))
                    Spacer()
                    Button { model.ignored.removeAll { $0.bundle == app.bundle } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop ignoring \(app.name)")
                }
                .padding(.leading, 38)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .cardStyle()
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: model.ignored)
    }

    private var runningApps: [IgnoredApp] {
        let taken = Set(model.ignored.map(\.bundle))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { a in a.bundleIdentifier.map { IgnoredApp(bundle: $0, name: a.localizedName ?? $0) } }
            .filter { !taken.contains($0.bundle) && $0.bundle != Bundle.main.bundleIdentifier }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func add(_ app: IgnoredApp) {
        guard !model.ignored.contains(app) else { return }
        model.ignored.append(app)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let b = Bundle(url: url), let id = b.bundleIdentifier else { return }
        add(IgnoredApp(bundle: id, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")))
    }

    private func appIcon(_ bundle: String) -> Image {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        }
        return Image(systemName: "app")
    }
}

struct RowLabel: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingRow<Control: View>: View {
    let symbol: String
    let title: String
    let subtitle: String
    @ViewBuilder let control: () -> Control
    var body: some View {
        HStack(spacing: 10) {
            RowLabel(symbol: symbol, title: title, subtitle: subtitle)
            Spacer(minLength: 8)
            control()
        }
        .padding(12)
        .cardStyle()
    }
}

/// Preset chips plus one scroll drum, for counts like days, items and megabytes.
struct NumberChipDrum: View {
    let title: String
    let value: Int
    let values: [Int]
    let presets: [Int]
    var tint: Color = .accentColor
    let label: (Int) -> String
    let short: (Int) -> String
    let onChange: (Int) -> Void

    private var index: Int { values.firstIndex(of: value) ?? values.indices.min(by: { abs(values[$0] - value) < abs(values[$1] - value) }) ?? 0 }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label(value)).font(.system(size: 13, weight: .semibold)).monospacedDigit().foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: value)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), alignment: .leading, spacing: 6) {
                    ForEach(presets, id: \.self) { p in
                        Chip(text: label(p), selected: p == value, tint: tint) {
                            guard p != value else { return }
                            DrumTick.play()
                            onChange(p)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DrumWheel(count: values.count, selection: index, wraps: false,
                      text: { short(values[$0]) }, accessibilityName: title, width: 50) { onChange(values[$0]) }
                .frame(width: 58)
                .padding(.horizontal, 4)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04))
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.14))
                            .frame(height: DrumWheel.rowHeight).padding(.horizontal, 4)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

private struct Chip: View {
    let text: String
    let selected: Bool
    let tint: Color
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: selected ? .semibold : .medium)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
            .frame(maxWidth: .infinity).frame(height: 26)
            .background(Capsule().fill(selected ? tint : Color.primary.opacity(hover ? 0.10 : 0.06)))
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.primary.opacity(0.10), lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture(perform: action)
            .onHover { hover = $0 }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { action() }
    }
}

/// Click, then press the new shortcut. Esc cancels, Delete turns the shortcut off.
/// The app colour picker: one dot per colour, the chosen one ringed.
struct AccentDots: View {
    let selected: Int
    let onPick: (Int) -> Void
    var body: some View {
        HStack(spacing: 7) {
            ForEach(accentChoices.indices, id: \.self) { i in
                let isSel = i == selected
                Button { onPick(i) } label: {
                    Circle().fill(accentChoices[i].color)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                        .padding(3)
                        .overlay(Circle().strokeBorder(isSel ? accentChoices[i].color : .clear, lineWidth: 1.6))
                        .scaleEffect(isSel ? 1 : 0.86)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(accentChoices[i].name)
                .accessibilityLabel("\(accentChoices[i].name) colour")
                .accessibilityAddTraits(isSel ? .isSelected : [])
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
    }
}

struct ShortcutRecorder: View {
    @ObservedObject var model: TenaxModel
    @Environment(\.tenaxAccent) private var accent
    @State private var recording = false
    @State private var monitor: Any?
    @State private var resign: Any?

    var body: some View {
        Button { recording ? stop() : start() } label: {
            Text(recording ? "Press keys…" : (model.shortcut?.display ?? "None"))
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(recording ? Color.white : Color.primary)
                .frame(minWidth: 86).padding(.vertical, 5).padding(.horizontal, 10)
                .background(Capsule().fill(recording ? accent : Color.primary.opacity(0.07)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(recording ? 0 : 0.12)))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: recording)
        .help("Click, then press the shortcut you want")
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotkeyCenter.shared.unregister()   // so pressing the old one doesn't open the panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            handle(e)
            return nil
        }
        // Clicking into another app ends recording and puts the old shortcut back.
        resign = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { _ in
            stop()
        }
    }

    private func handle(_ e: NSEvent) {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        if e.keyCode == 53 { stop(); return }                         // Esc: keep the old one
        if (e.keyCode == 51 || e.keyCode == 117) && mods.isEmpty {     // Delete: no shortcut
            model.shortcutProblem = nil
            _ = model.onShortcut(nil)
            model.shortcut = nil
            stop(); return
        }
        // Shortcuts every Mac app relies on can't be taken over.
        let reserved: [(UInt16, NSEvent.ModifierFlags)] = [(12, .command), (13, .command), (4, .command), (49, .command),
                                                           (48, .command), (8, .command), (9, .command), (0, .command)]
        if reserved.contains(where: { $0.0 == e.keyCode && $0.1 == mods }) {
            model.shortcutProblem = "That one is used by every app. Try another."
            NSSound.beep(); return
        }
        let isFKey = (96...122).contains(Int(e.keyCode))
        guard isFKey || !mods.intersection([.command, .option, .control]).isEmpty else {
            model.shortcutProblem = "Add ⌘, ⌥ or ⌃ to the key"
            NSSound.beep(); return
        }
        let s = Shortcut(keyCode: UInt32(e.keyCode), modifiers: mods)
        if model.onShortcut(s) {
            model.shortcut = s
            model.shortcutProblem = nil
        } else {
            model.shortcutProblem = "\(s.display) is used by another app. Try another."
        }
        stop()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resign { NotificationCenter.default.removeObserver(resign) }
        resign = nil
        if recording { recording = false; _ = model.onShortcut(model.shortcut) }
    }
}


/// "Share with a friend": zips a clean copy of Memo (no history inside) and opens the share picker, AirDrop first.
struct MemoShareRow: View {
    @State private var box = ShareAnchorBox()
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Button {
            guard !busy else { return }
            busy = true; error = nil
            ShareFriend.share(from: box.view) { error = $0; busy = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { busy = false }
        } label: {
            HStack(spacing: 10) {
                RowLabel(symbol: "square.and.arrow.up", title: ShareFriend.title, subtitle: error ?? ShareFriend.hint)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardStyle()
        .background(ShareAnchor(box: box))
        .accessibilityLabel(ShareFriend.title)
    }
}
