// Hotkey.swift. The global "open Memo" shortcut.
//
// Uses the system hot key service (works in every app, needs no permission). Registration
// failures are reported back, so the recorder can say "taken by another app" instead of
// silently doing nothing (common clipboard-manager issue: shortcut recorder problems).
import AppKit
import Carbon.HIToolbox

struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags   // only command, option, control, shift

    static let fallback = Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: [.control, .command])

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    /// e.g. "⌃⌘V"
    var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let s = special[Int(code)] { return s }
        // Ask the current keyboard layout which character the key types (so it is right on any layout).
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    // Saved as two numbers in UserDefaults.
    static func load() -> Shortcut? {
        let d = UserDefaults.standard
        guard d.object(forKey: "hotkeyCode") != nil else { return fallback }
        let code = d.integer(forKey: "hotkeyCode")
        if code < 0 { return nil }   // switched off
        return Shortcut(keyCode: UInt32(code), modifiers: NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: "hotkeyMods"))))
    }

    static func save(_ s: Shortcut?) {
        let d = UserDefaults.standard
        d.set(s.map { Int($0.keyCode) } ?? -1, forKey: "hotkeyCode")
        d.set(Int(s?.modifiers.rawValue ?? 0), forKey: "hotkeyMods")
    }
}

final class HotkeyCenter {
    static let shared = HotkeyCenter()
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotkeyCenter.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    /// Returns false if another app already owns this shortcut.
    @discardableResult
    func register(_ s: Shortcut?) -> Bool {
        unregister()
        guard let s else { return true }
        let id = EventHotKeyID(signature: OSType(0x544E5853), id: 1)   // "TNXS"
        let status = RegisterEventHotKey(s.keyCode, s.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { ref = nil; Log.write("hotkey \(s.display) not available (\(status))") }
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
