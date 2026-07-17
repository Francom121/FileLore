import Carbon
import AppKit

/// Global hotkey via Carbon's `RegisterEventHotKey` (default ⌥T, user-customizable).
///
/// The old Carbon hotkey API still works on modern macOS and — unlike
/// event monitors — requires no accessibility permission. The hotkey fires
/// even while Tether is in the background, which is the whole point: press
/// the shortcut in Finder to open the note editor for the selected file.
///
/// The key combo is persisted in UserDefaults (`GlobalShortcutStore`); the
/// settings window rebinds it via `updateShortcut(_:)`.
final class HotKeyManager {
    static let shared = HotKeyManager()

    /// Hotkey signature: 'TETH'.
    private static let signature: OSType = 0x54455448
    private static let hotKeyID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private(set) var isRegistered = false

    /// Invoked on the main thread when the hotkey is pressed.
    var onHotKey: (@MainActor () -> Void)?

    private init() {}

    /// The shortcut currently stored in settings (⌥T when nothing is stored).
    var currentShortcut: GlobalShortcut { GlobalShortcutStore.load() }

    /// Persists a new shortcut and re-registers the Carbon hotkey:
    /// the old `EventHotKeyRef` (and event handler) is torn down first.
    func updateShortcut(_ shortcut: GlobalShortcut) {
        GlobalShortcutStore.save(shortcut)
        unregister()
        register()
    }

    func register() {
        guard !isRegistered else { return }
        let shortcut = GlobalShortcutStore.load()

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
                if err == noErr, hotKeyID.id == HotKeyManager.hotKeyID {
                    manager.fire()
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
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

        let hotKeyID = EventHotKeyID(signature: HotKeyManager.signature, id: HotKeyManager.hotKeyID)
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus == noErr {
            isRegistered = true
            NSLog("Tether: \(shortcut.displayString) global hotkey registered")
        } else {
            NSLog("Tether: RegisterEventHotKey failed (\(registerStatus)) — another app may already own \(shortcut.displayString)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        isRegistered = false
    }

    private func fire() {
        let callback = onHotKey
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                callback?()
            }
        }
    }
}
