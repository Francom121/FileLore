import SwiftUI
import AppKit
import Carbon

/// Settings window: rebind the global hotkeys — "open note for the Finder
/// selection" (default ⌥T) and "search notes" (default ⇧⌘F).
struct SettingsView: View {
    @State private var shortcut: GlobalShortcut = GlobalShortcutStore.load(.openNote)
    @State private var searchShortcut: GlobalShortcut = GlobalShortcutStore.load(.search)
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Global Shortcuts")
                .font(.headline)

            shortcutRow(
                title: "Open Note for Finder Selection",
                description: "Opens the note editor for the current Finder selection.",
                shortcut: $shortcut,
                fallback: GlobalShortcutStore.fallback(for: .openNote),
                slot: .openNote
            )

            Divider()

            shortcutRow(
                title: "Search Notes",
                description: "Opens the Spotlight-style search over all noted files.",
                shortcut: $searchShortcut,
                fallback: GlobalShortcutStore.fallback(for: .search),
                slot: .search
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("You can also assign any shortcut via System Settings → Keyboard → Keyboard Shortcuts → Services → Open Tether Note.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 400)
    }

    private func shortcutRow(
        title: String,
        description: String,
        shortcut: Binding<GlobalShortcut>,
        fallback: GlobalShortcut,
        slot: HotKeySlot
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ShortcutRecorder(
                    current: shortcut.wrappedValue,
                    onCapture: { captured in
                        errorMessage = nil
                        shortcut.wrappedValue = captured
                        HotKeyManager.shared.updateShortcut(captured, slot: slot)
                    },
                    onError: { message in
                        errorMessage = message
                    }
                )
                Button("Reset to \(fallback.displayString)") {
                    errorMessage = nil
                    shortcut.wrappedValue = fallback
                    HotKeyManager.shared.updateShortcut(fallback, slot: slot)
                }
            }
        }
    }
}

/// A shortcut recorder field: click it, then press the new key combination.
/// SwiftUI can't intercept raw key codes + modifiers, so this wraps an NSView
/// that owns an `NSEvent` local monitor while recording.
struct ShortcutRecorder: NSViewRepresentable {
    let current: GlobalShortcut
    let onCapture: (GlobalShortcut) -> Void
    let onError: (String) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onCapture = onCapture
        view.onError = onError
        view.displayString = current.displayString
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onError = onError
        nsView.displayString = current.displayString
    }
}

final class ShortcutRecorderNSView: NSView {
    var onCapture: ((GlobalShortcut) -> Void)?
    var onError: ((String) -> Void)?

    var displayString: String = "" {
        didSet { needsDisplay = true }
    }

    private var isRecording = false {
        didSet {
            needsDisplay = true
            updateMonitor()
        }
    }
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 28) }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
            resignObserver = nil
        }
        if let window {
            // Clicking away to another window stops recording.
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.isRecording = false
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let bezel = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: bezel, xRadius: 6, yRadius: 6)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isRecording ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let label = isRecording ? "Press shortcut…" : displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let attributed = NSAttributedString(string: label, attributes: attributes)
        let size = attributed.size()
        attributed.draw(at: NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        ))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording.toggle()
    }

    override func keyDown(with event: NSEvent) {
        // Keyboard activation (Space/Return) when focused but not yet recording.
        let keyCode = Int(event.keyCode)
        if !isRecording, keyCode == kVK_Space || keyCode == kVK_Return {
            isRecording = true
            return
        }
        super.keyDown(with: event)
    }

    private func updateMonitor() {
        if isRecording {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                guard let self, self.isRecording else { return event }
                return self.handleKeyDown(event) ? nil : event
            }
        } else if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// Returns true when the event was consumed.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Bare Esc cancels recording without changing the shortcut.
        if Int(event.keyCode) == kVK_Escape,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            isRecording = false
            return true
        }
        guard let shortcut = GlobalShortcut(event: event) else {
            isRecording = false
            onError?("A global shortcut needs at least one modifier (⌘ ⌥ ⇧ ⌃) — a bare key isn't allowed.")
            return true
        }
        isRecording = false
        onCapture?(shortcut)
        return true
    }
}
