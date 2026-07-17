import Carbon
import AppKit

/// Global hotkeys via Carbon's `RegisterEventHotKey` (user-customizable):
///
/// - **Open note** (default ⌥T): opens the note editor for the current Finder selection.
/// - **Search** (default ⇧⌘F): opens/focuses the Spotlight-style search window.
///
/// The old Carbon hotkey API still works on modern macOS and — unlike
/// event monitors — requires no accessibility permission. The hotkeys fire
/// even while Tether is in the background, which is the whole point: press
/// the shortcut in Finder to act on the selected file / find a note.
///
/// The combos are persisted in UserDefaults (`GlobalShortcutStore`); the
/// settings window rebinds them via `updateShortcut(_:slot:)`.
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// Hotkey signature: 'TETH'.
    private static let signature: OSType = 0x54455448

    private static func hotKeyID(for slot: HotKeySlot) -> UInt32 {
        switch slot {
        case .openNote: return 1
        case .search: return 2
        }
    }

    private var hotKeyRefs: [HotKeySlot: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private(set) var isRegistered = false

    /// Invoked on the main thread when the "open note" hotkey is pressed.
    var onHotKey: (@MainActor () -> Void)?
    /// Invoked on the main thread when the "search" hotkey is pressed.
    var onSearchHotKey: (@MainActor () -> Void)?

    private init() {}

    /// The "open note" shortcut currently stored in settings (⌥T when nothing is stored).
    var currentShortcut: GlobalShortcut { GlobalShortcutStore.load(.openNote) }
    /// The "search" shortcut currently stored in settings (⇧⌘F when nothing is stored).
    var currentSearchShortcut: GlobalShortcut { GlobalShortcutStore.load(.search) }

    /// Persists a new shortcut for `slot` and re-registers the Carbon hotkeys:
    /// the old `EventHotKeyRef`s (and event handler) are torn down first.
    func updateShortcut(_ shortcut: GlobalShortcut, slot: HotKeySlot = .openNote) {
        GlobalShortcutStore.save(shortcut, slot: slot)
        unregister()
        register()
    }

    func register() {
        guard !isRegistered else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard err == noErr, hotKeyID.signature == HotKeyManager.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                switch hotKeyID.id {
                case HotKeyManager.hotKeyID(for: .openNote):
                    manager.fire(slot: .openNote)
                    return noErr
                case HotKeyManager.hotKeyID(for: .search):
                    manager.fire(slot: .search)
                    return noErr
                default:
                    return OSStatus(eventNotHandledErr)
                }
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard installStatus == noErr else {
            NSLog("Tether: InstallEventHandler failed (\(installStatus))")
            return
        }

        // Register every slot; the manager counts as registered when at least
        // one hotkey took (each failure is logged individually).
        var anyRegistered = false
        for slot in HotKeySlot.allCases {
            let shortcut = GlobalShortcutStore.load(slot)
            let hotKeyID = EventHotKeyID(
                signature: HotKeyManager.signature,
                id: HotKeyManager.hotKeyID(for: slot)
            )
            var ref: EventHotKeyRef?
            let registerStatus = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if registerStatus == noErr, let ref {
                hotKeyRefs[slot] = ref
                anyRegistered = true
                NSLog("Tether: \(shortcut.displayString) global hotkey registered (\(slot.rawValue))")
            } else {
                NSLog("Tether: RegisterEventHotKey failed (\(registerStatus)) — another app may already own \(shortcut.displayString)")
            }
        }
        isRegistered = anyRegistered
    }

    func unregister() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        isRegistered = false
    }

    private func fire(slot: HotKeySlot) {
        let openNote = onHotKey
        let search = onSearchHotKey
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                switch slot {
                case .openNote: openNote?()
                case .search: search?()
                }
            }
        }
    }
}
