import Carbon
import AppKit

/// A global keyboard shortcut: Carbon virtual key code + Carbon modifier mask
/// (`cmdKey` / `optionKey` / `shiftKey` / `controlKey`), as passed to
/// `RegisterEventHotKey`.
struct GlobalShortcut: Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// At least one of ⌘⌥⇧⌃ is required — a bare letter can't be a global hotkey.
    var isValid: Bool {
        carbonModifiers & (UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey) | UInt32(controlKey)) != 0
    }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Captures a shortcut from a key-down event. Returns nil when the event
    /// carries no ⌘⌥⇧⌃ modifier.
    init?(event: NSEvent) {
        let carbon = GlobalShortcut.carbonModifiers(
            from: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )
        guard carbon != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    /// "⌥T"-style display string, modifiers in the conventional ⌃⌥⇧⌘ order.
    var displayString: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += GlobalShortcut.keyName(for: keyCode)
        return result
    }

    /// Human-readable names for the Carbon virtual key codes a user is
    /// realistically going to bind (US-layout labels for letters/punctuation).
    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Grave: return "`"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "PgUp"
        case kVK_PageDown: return "PgDn"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key \(keyCode)"
        }
    }
}

/// Which global hotkey a stored shortcut belongs to.
enum HotKeySlot: String, CaseIterable {
    /// Opens the note editor for the current Finder selection (default ⌥T).
    case openNote
    /// Opens/focuses the Spotlight-style search window (default ⇧⌘F).
    case search
}

/// UserDefaults persistence for the user's global shortcuts. Defaults are
/// ⌥T (open note) and ⇧⌘F (search).
enum GlobalShortcutStore {
    static func fallback(for slot: HotKeySlot) -> GlobalShortcut {
        switch slot {
        case .openNote:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_T), carbonModifiers: UInt32(optionKey))
        case .search:
            return GlobalShortcut(keyCode: UInt32(kVK_ANSI_F), carbonModifiers: UInt32(shiftKey | cmdKey))
        }
    }

    /// ⌥T — kept as a convenience for the original call sites.
    static var fallback: GlobalShortcut { fallback(for: .openNote) }

    private static func keyCodeDefaultsKey(for slot: HotKeySlot) -> String {
        switch slot {
        case .openNote: return "globalShortcut.keyCode" // original keys, untouched
        case .search: return "searchShortcut.keyCode"
        }
    }

    private static func modifiersDefaultsKey(for slot: HotKeySlot) -> String {
        switch slot {
        case .openNote: return "globalShortcut.carbonModifiers"
        case .search: return "searchShortcut.carbonModifiers"
        }
    }

    static func load(_ slot: HotKeySlot = .openNote) -> GlobalShortcut {
        let defaults = UserDefaults.standard
        let keyCodeKey = keyCodeDefaultsKey(for: slot)
        guard defaults.object(forKey: keyCodeKey) != nil else { return fallback(for: slot) }
        let shortcut = GlobalShortcut(
            keyCode: UInt32(clamping: defaults.integer(forKey: keyCodeKey)),
            carbonModifiers: UInt32(clamping: defaults.integer(forKey: modifiersDefaultsKey(for: slot)))
        )
        return shortcut.isValid ? shortcut : fallback(for: slot)
    }

    static func save(_ shortcut: GlobalShortcut, slot: HotKeySlot = .openNote) {
        let defaults = UserDefaults.standard
        defaults.set(Int(shortcut.keyCode), forKey: keyCodeDefaultsKey(for: slot))
        defaults.set(Int(shortcut.carbonModifiers), forKey: modifiersDefaultsKey(for: slot))
    }
}
