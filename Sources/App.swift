// App.swift. Memo: clipboard history in the menu bar.
//
// The app delegate owns the status item, the popover, the clipboard watcher, the shortcut and
// Settings. The SwiftUI views only read TenaxModel and call back here.
import AppKit
import ServiceManagement
import SwiftUI

#if TENAX_TEST
let testNotification = Notification.Name("com.solomon.Tenax.test")
#endif

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let glyph = TenaxGlyphView()
    private let popover = NSPopover()
    private let model = TenaxModel()
    private let store = Store.shared
    private let watcher = ClipboardWatcher()
    private var settingsWindow: NSWindow?
    private var introWindow: NSWindow?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var panelPrepared = false
    private var housekeeping: Timer?
    private var permissionPoll: Timer?
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.register() }
        installMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: 26)
        if let button = statusItem.button {
            button.wantsLayer = true
            button.action = #selector(statusClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Memo clipboard history")
            glyph.frame = button.bounds
            glyph.autoresizingMask = [.width, .height]
            button.addSubview(glyph)
        }

        wireModel()
        popover.delegate = self
        popover.behavior = .applicationDefined
        popover.animates = true
        let host = NSHostingController(rootView: PopoverView(model: model))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        // Storage health first: remove orphans, apply limits, then show the list.
        store.sweepOrphans()
        enforceLimits()
        reload()
        if let err = store.openError { model.errorText = err }

        watcher.settings = { [weak self] in
            guard let m = self?.model else { return (false, true, true, []) }
            return (m.paused, m.skipSecrets, m.cleanLinks, Set(m.ignored.map(\.bundle)))
        }
        watcher.onNewClip = { [weak self] clip in self?.record(clip) }
        watcher.start()

        HotkeyCenter.shared.onPress = { [weak self] in self?.togglePopover() }
        if !HotkeyCenter.shared.register(model.shortcut) {
            model.shortcutProblem = "\(model.shortcut?.display ?? "") is used by another app. Pick another."
        }

        // Age limits also apply while nothing new is copied.
        housekeeping = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.enforceLimits(); self?.reload()
        }
        // One panel at a time: another of our apps opening its panel closes this one.
        PanelGroup.listen { [weak self] in self?.closePopover() }
        #if TENAX_TEST
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(testCommand(_:)),
                                                            name: testNotification, object: nil)
        #endif
        Log.write("launched, \(model.items.count) items")
        if !UserDefaults.standard.bool(forKey: IntroPref.done) { showIntro() }
    }

    func applicationWillTerminate(_ notification: Notification) { store.checkpoint() }

    /// Opening Memo again from Finder or Spotlight shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { openPopover() }
        return false
    }

    // MARK: Model wiring

    private func wireModel() {
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        model.onPaste = { [weak self] item, style in self?.paste(item, style: style) }
        model.onLoadFull = { [weak self] item in self?.store.full(item) ?? item }
        model.onPin = { [weak self] item in
            self?.store.setPinned(item.id, !item.pinned); self?.reload()
        }
        model.onDelete = { [weak self] item in
            self?.store.delete(item.id); self?.reload()
        }
        model.onCopy = { [weak self] item in self?.copyOnly(item) }
        model.onSettingsChanged = { [weak self] in
            guard let self else { return }
            self.glyph.paused = self.model.paused
            self.enforceLimits()
            self.reload()
        }
        model.onOpenSettings = { [weak self] in self?.openSettings() }
        model.onQuit = { [weak self] in self?.quit() }
        model.onLogin = { [weak self] want in self?.setLogin(want) }
        model.onShortcut = { s in
            let ok = HotkeyCenter.shared.register(s)
            if ok { Shortcut.save(s) }
            return ok
        }
        model.onClearHistory = { [weak self] in self?.store.clearUnpinned(); self?.reload(); self?.updateStorage() }
        model.onAskPermission = { [weak self] in self?.askPermission() }
        glyph.paused = model.paused
    }

    private func record(_ clip: NewClip) {
        guard store.add(clip) else { return }
        enforceLimits()
        reload()
        glyph.playTick(reduceMotion: reduceMotion)
        bounceIcon()
    }

    private func enforceLimits() {
        store.enforceLimits(keepDays: model.keepDays, maxItems: model.maxItems, maxBytes: model.maxMB * 1_048_576)
    }

    private func reload() {
        model.items = store.all()
        if settingsWindow?.isVisible == true { updateStorage() }
    }

    /// "History uses 12 MB": measured only while Settings is open (it lists every file).
    private func updateStorage() {
        let bytes = store.diskBytes()
        model.storageText = bytes < 1_048_576 ? "\(max(1, bytes / 1024)) KB"
            : String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    // MARK: Paste

    /// The row's Copy button: puts the item on the clipboard and leaves the panel open.
    /// Not moved to the top of the list, so the row stays under the pointer.
    private func copyOnly(_ shown: ClipItem) {
        guard Paster.copy(store.full(shown), style: .normal) else { NSSound.beep(); return }
        glyph.playTick(reduceMotion: reduceMotion)
        Log.write("copy \(shown.kind.rawValue)")
    }

    private func paste(_ shown: ClipItem, style: PasteStyle) {
        let item = store.full(shown)
        guard Paster.copy(item, style: style) else { NSSound.beep(); return }
        store.markUsed(item.id)
        reload()
        closePopover()
        glyph.playTick(reduceMotion: reduceMotion)
        Log.write("paste \(item.kind.rawValue) style=\(style)")
        guard model.pasteDirectly, Paster.canPasteDirectly else { return }
        // Let the popover close and the front app take the keys back, then press ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Paster.pressPaste() }
    }

    private func askPermission() {
        Paster.askForPermission()
        permissionPoll?.invalidate()
        var tries = 0
        permissionPoll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            tries += 1
            let ok = Paster.canPasteDirectly
            self?.model.accessibilityOK = ok
            if ok || tries > 120 { t.invalidate() }
        }
    }

    // MARK: Status item + popover

    @objc private func statusClicked() { togglePopover() }

    private func togglePopover() { popover.isShown ? closePopover() : openPopover() }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        removeMonitors()
        model.accessibilityOK = Paster.canPasteDirectly
        model.query = ""
        model.collapse()
        model.selectedID = model.visible.first?.id
        model.mouseAtOpen = NSEvent.mouseLocation
        bounceIcon()
        PanelGroup.announceOpen()   // close our other apps' panels
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Never activate the app (that would swap the menu bar). A non-activating panel still gets keys.
        if let panel = popover.contentViewController?.view.window as? NSPanel, !panelPrepared {
            panel.styleMask.insert(.nonactivatingPanel)
            panelPrepared = true
        }
        popover.contentViewController?.view.window?.makeKey()
        model.openCount += 1
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if PanelGroup.isOnNoxSwitch() { return }   // Nox's quick dark-mode switch never closes a panel
            self?.closePopover()   // any other click outside (desktop, other apps, any menu bar item) closes it
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.popover.isShown, e.window === self.popover.contentViewController?.view.window else { return e }
            return self.handleKey(e) ? nil : e
        }
    }

    private func closePopover() {
        if popover.isShown { popover.performClose(nil) }
        removeMonitors()
    }

    /// A quick re-open during the close animation keeps its fresh monitors.
    func popoverDidClose(_ notification: Notification) { if !popover.isShown { removeMonitors() } }

    private func removeMonitors() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Keyboard in the panel. Returns true when the key was used.
    private func handleKey(_ e: NSEvent) -> Bool {
        // Typing Chinese, Japanese or Korean: let the input method finish first.
        if let editor = popover.contentViewController?.view.window?.firstResponder as? NSTextView, editor.hasMarkedText() {
            return false
        }
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let chars = e.charactersIgnoringModifiers ?? ""
        switch e.keyCode {
        case 125: model.move(1); return true                      // down
        case 126: model.move(-1); return true                     // up
        case 36, 76:                                              // return
            let style: PasteStyle = mods.contains(.option) ? (mods.contains(.shift) ? .markdown : .plain) : .normal
            model.pasteSelected(style); return true
        case 53:                                                  // esc: close the open row, then the search, then the panel
            if model.expandedID != nil { model.collapse() } else if model.query.isEmpty { closePopover() } else { model.query = "" }
            return true
        // Open and close a row. Only while the search is empty, so the arrows and Space still edit search text.
        case 124 where mods.isEmpty && model.query.isEmpty:       // right: show everything
            if let s = model.selected { model.expand(s.id) }
            return true
        case 123 where mods.isEmpty && model.query.isEmpty:       // left: show less
            model.collapse(); return true
        case 49 where mods.isEmpty && model.query.isEmpty:        // space: toggle
            if let s = model.selected { model.toggleExpand(s.id) }
            return true
        case 51 where mods == .command && model.query.isEmpty:    // ⌘⌫ (in search it clears text instead)
            if let s = model.selected { model.onDelete(s) }
            return true
        default: break
        }
        if mods == .command, chars == "p" { if let s = model.selected { model.onPin(s) }; return true }
        if mods == .command, chars == "," { openSettings(); return true }
        if mods == .command, chars == "q" { quit(); return true }
        // ⌘1–9 quick paste (bare digits stay free for searching, e.g. "2024").
        if let n = Int(chars), (1...9).contains(n), mods == .command {
            model.paste(number: n); return true
        }
        return false
    }

    private func bounceIcon() {
        guard !reduceMotion, let b = statusItem.button, let layer = b.layer else { return }
        let bounce = CASpringAnimation(keyPath: "transform")
        let cx = b.bounds.midX, cy = b.bounds.midY
        var t = CATransform3DMakeTranslation(cx, cy, 0)
        t = CATransform3DScale(t, 1.12, 1.12, 1)
        t = CATransform3DTranslate(t, -cx, -cy, 0)
        bounce.fromValue = t
        bounce.toValue = CATransform3DIdentity
        bounce.mass = 1; bounce.stiffness = 320; bounce.damping = 11
        bounce.duration = bounce.settlingDuration
        layer.add(bounce, forKey: "bounce")
    }

    // MARK: Welcome (shown once after install)

    private func showIntro(page: Int = 0) {
        introWindow?.close()
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.title = "Welcome to Memo"
        let view = IntroView(model: model, finish: { [weak self] openPanel in
            UserDefaults.standard.set(true, forKey: IntroPref.done)
            self?.introWindow?.close()
            self?.introWindow = nil
            if openPanel { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.openPopover() } }
        }, page: page)
        w.contentView = NSHostingView(rootView: view)
        w.setContentSize(w.contentView!.fittingSize)
        w.center()
        introWindow = w
        model.accessibilityOK = Paster.canPasteDirectly
        // A deliberate first-run window, so it comes to the front.
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }

    // MARK: Settings, login, quit

    private func openSettings() {
        closePopover()
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(model: model))
            let w = NSWindow(contentViewController: host)
            w.title = "Memo Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        model.accessibilityOK = Paster.canPasteDirectly
        updateStorage()
        // Opening Settings is a deliberate request, so bring it in front of the current app.
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    private func setLogin(_ want: Bool) {
        do {
            if want { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.write("login item: \(error.localizedDescription)")
        }
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Quit Memo", action: #selector(quitFromMenu), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    @objc private func openSettingsFromMenu() { openSettings() }
    @objc private func quitFromMenu() { quit() }

    /// Quit folds the panel away first, then closes.
    private func quit() {
        store.checkpoint()
        guard popover.isShown else { NSApp.terminate(nil); return }
        closePopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { NSApp.terminate(nil) }
    }

    // MARK: Test hook (test builds only; UI actions only, nothing a click couldn't do)
    #if TENAX_TEST

    @objc private func testCommand(_ n: Notification) {
        guard let cmd = n.object as? String else { return }
        let parts = cmd.split(separator: ":", maxSplits: 1).map(String.init)
        switch parts[0] {
        case "panel": openPopover()
        case "sharetest": ShareFriend.selfTest(report: "/tmp/memo-share-test.txt")
        case "noxhit":   // checks the Nox-switch exception without clicking it
            var lines = ["far \(PanelGroup.isOnNoxSwitch(NSPoint(x: 5, y: 5)))"]
            if let d = try? Data(contentsOf: PanelGroup.noxFrameFile),
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Double],
               let x = o["x"], let y = o["y"], let w = o["w"], let h = o["h"] {
                lines.append("nox \(PanelGroup.isOnNoxSwitch(NSPoint(x: x + w / 2, y: y + h / 2)))")
            }
            try? lines.joined(separator: "\n").write(toFile: "/tmp/memo-noxhit.txt", atomically: true, encoding: .utf8)
        case "close": closePopover()
        case "settings": openSettings()
        case "closesettings": settingsWindow?.close()
        case "intro": showIntro(page: Int(parts.count > 1 ? parts[1] : "") ?? 0)
        case "closeintro": introWindow?.close(); introWindow = nil
        case "down": model.move(1)
        case "up": model.move(-1)
        case "search": model.query = parts.count > 1 ? parts[1] : ""
        case "enter": model.pasteSelected(.normal)
        case "plain": model.pasteSelected(.plain)
        case "markdown": model.pasteSelected(.markdown)
        case "number": model.paste(number: Int(parts.count > 1 ? parts[1] : "") ?? 0)
        case "pin": if let s = model.selected { model.onPin(s) }
        case "delete": if let s = model.selected { model.onDelete(s) }
        case "pause": model.paused.toggle()
        case "expand":   // expand:<row number, 1 = top row>
            let n = Int(parts.count > 1 ? parts[1] : "") ?? 1
            if n >= 1, n <= model.visible.count { model.expand(model.visible[n - 1].id) }
        case "collapse": model.collapse()
        case "look":     // look:light / look:dark / look:system. This app only, never the Mac's setting.
            let a = parts.count > 1 ? parts[1] : "system"
            let look = a == "light" ? NSAppearance(named: .aqua) : a == "dark" ? NSAppearance(named: .darkAqua) : nil
            NSApp.appearance = look
            popover.appearance = look              // an open panel keeps its own look unless told
            settingsWindow?.appearance = look
            introWindow?.appearance = look
        case "quit": quit()
        default: break
        }
        writeState()
    }

    private func writeState() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
            // Never log what was copied: only kinds, lengths and positions.
            let rows = model.visible.prefix(8).map { "\($0.pinned ? "*" : "")\($0.kind.rawValue)/\($0.text.count)" }
            let sel = model.visible.firstIndex { $0.id == model.selectedID }.map { "\($0 + 1)" } ?? "-"
            let exp = model.visible.firstIndex { $0.id == model.expandedID }.map { "\($0 + 1)" } ?? "-"
            Log.write("STATE count=\(model.items.count) visible=\(model.visible.count) shown=\(popover.isShown) " +
                      "selected=\(sel) expanded=\(exp) paused=\(model.paused) look=\(NSApp.appearance?.name.rawValue ?? "system") rows=\(rows)")
        }
    }
    #endif
}

@main
enum TenaxApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
