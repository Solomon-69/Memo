// Model.swift. What the popover and Settings show. Every setting saves the moment it changes
// (Maccy issue: settings fields reset when you click away).
import AppKit
import SwiftUI

enum Pref {
    static let keepDays = "keepDays"            // 0 = forever
    static let maxItems = "maxItems"
    static let maxMB = "maxMB"
    static let skipSecrets = "skipSecrets"
    static let cleanLinks = "cleanLinks"
    static let pasteDirectly = "pasteDirectly"
    static let paused = "paused"
    static let ignored = "ignoredApps"          // [bundle id]
    static let accent = "accentIndex"           // index into accentChoices (0 = Navy)
}

struct IgnoredApp: Identifiable, Equatable {
    var id: String { bundle }
    let bundle: String
    let name: String
}

final class TenaxModel: ObservableObject {
    // History
    @Published var items: [ClipItem] = [] { didSet { refilter() } }
    @Published var query = "" { didSet { refilter() } }
    @Published private(set) var visible: [ClipItem] = []
    @Published var selectedID: Int64?
    @Published var scrollTarget: Int64?
    @Published var openCount = 0
    /// The row opened to show everything that was copied (one at a time).
    @Published private(set) var expandedID: Int64?
    @Published private(set) var expandedText = ""
    var mouseAtOpen = NSPoint.zero
    @Published var accessibilityOK = Paster.canPasteDirectly
    @Published var storageText = ""
    @Published var errorText: String?

    // Settings (saved immediately)
    @Published var keepDays: Int { didSet { save(keepDays, Pref.keepDays) } }
    @Published var maxItems: Int { didSet { save(maxItems, Pref.maxItems) } }
    @Published var maxMB: Int { didSet { save(maxMB, Pref.maxMB) } }
    @Published var skipSecrets: Bool { didSet { save(skipSecrets, Pref.skipSecrets) } }
    @Published var cleanLinks: Bool { didSet { save(cleanLinks, Pref.cleanLinks) } }
    @Published var pasteDirectly: Bool { didSet { save(pasteDirectly, Pref.pasteDirectly) } }
    @Published var paused: Bool { didSet { save(paused, Pref.paused) } }
    @Published var ignored: [IgnoredApp] { didSet { saveIgnored() } }
    @Published var accentIndex: Int { didSet { UserDefaults.standard.set(accentIndex, forKey: Pref.accent) } }
    @Published var launchAtLogin = false
    @Published var shortcut: Shortcut? = Shortcut.load()
    @Published var shortcutProblem: String?

    // Actions (wired by AppDelegate)
    var onPaste: (ClipItem, PasteStyle) -> Void = { _, _ in }
    var onLoadFull: (ClipItem) -> ClipItem = { $0 }   // the list only holds the first 4,000 characters
    var onPin: (ClipItem) -> Void = { _ in }
    var onDelete: (ClipItem) -> Void = { _ in }
    var onCopy: (ClipItem) -> Void = { _ in }       // copy only: no paste, panel stays open
    var onSettingsChanged: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onQuit: () -> Void = {}
    var onLogin: (Bool) -> Void = { _ in }
    var onShortcut: (Shortcut?) -> Bool = { _ in true }
    var onClearHistory: () -> Void = {}
    var onAskPermission: () -> Void = {}

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [Pref.keepDays: 30, Pref.maxItems: 500, Pref.maxMB: 250, Pref.skipSecrets: true,
                              Pref.cleanLinks: true, Pref.pasteDirectly: true, Pref.paused: false])
        keepDays = d.integer(forKey: Pref.keepDays)
        maxItems = d.integer(forKey: Pref.maxItems)
        maxMB = d.integer(forKey: Pref.maxMB)
        skipSecrets = d.bool(forKey: Pref.skipSecrets)
        cleanLinks = d.bool(forKey: Pref.cleanLinks)
        pasteDirectly = d.bool(forKey: Pref.pasteDirectly)
        paused = d.bool(forKey: Pref.paused)
        accentIndex = d.integer(forKey: Pref.accent)
        let raw = d.array(forKey: Pref.ignored) as? [[String: String]] ?? []
        ignored = raw.compactMap { r in r["bundle"].map { IgnoredApp(bundle: $0, name: r["name"] ?? $0) } }
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
        onSettingsChanged()
    }

    private func saveIgnored() {
        UserDefaults.standard.set(ignored.map { ["bundle": $0.bundle, "name": $0.name] }, forKey: Pref.ignored)
        onSettingsChanged()
    }

    // MARK: Lists

    var pinned: [ClipItem] { items.filter(\.pinned).sorted { $0.pinOrder < $1.pinOrder } }
    var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private func refilter() {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            visible = pinned + items.filter { !$0.pinned }
        } else {
            visible = items
                .compactMap { item -> (ClipItem, Int)? in
                    let hay = item.kind == .image ? "image \(item.width)x\(item.height) \(item.source ?? "")"
                                                  : item.text + " " + (item.source ?? "")
                    return Fuzzy.score(q, in: hay).map { (item, $0) }
                }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
        if selectedID == nil || !visible.contains(where: { $0.id == selectedID }) {
            selectedID = visible.first?.id
        }
        if let e = expandedID, !visible.contains(where: { $0.id == e }) { expandedID = nil }
    }

    // MARK: Expand

    /// Longest text shown when a row is opened (a huge paste would make the panel crawl).
    static let expandLimit = 20_000

    func toggleExpand(_ id: Int64) {
        expandedID == id ? collapse() : expand(id)
    }

    func expand(_ id: Int64) {
        guard let item = visible.first(where: { $0.id == id }) else { return }
        let text = item.kind == .image ? "" : onLoadFull(item).text
        expandedText = String(text.prefix(Self.expandLimit))
        expandedTotal = text.count
        selectedID = id
        expandedID = id
        scrollTarget = id
    }

    func collapse() { expandedID = nil }

    /// Characters in the whole copied text (may be more than is shown).
    private(set) var expandedTotal = 0

    // MARK: Keyboard

    var selected: ClipItem? { visible.first { $0.id == selectedID } }

    func move(_ step: Int) {
        guard !visible.isEmpty else { return }
        let i = visible.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(i + step, 0), visible.count - 1)
        selectedID = visible[next].id
        scrollTarget = selectedID
        // While a row is open, the open row follows the selection, so you can read down the list.
        if expandedID != nil, let id = selectedID { expand(id) }
    }

    func pasteSelected(_ style: PasteStyle) { if let s = selected { onPaste(s, style) } }

    /// Quick paste: 1 = first item shown.
    func paste(number n: Int) {
        guard n >= 1, n <= min(9, visible.count) else { return }
        onPaste(visible[n - 1], .normal)
    }

    func mouseMovedSinceOpen() -> Bool {
        let p = NSEvent.mouseLocation
        return hypot(p.x - mouseAtOpen.x, p.y - mouseAtOpen.y) > 3
    }
}
