import SwiftUI
import AppKit

/// Central routing point for "open the note editor / main window" requests.
///
/// SwiftUI's `openWindow` environment action only exists inside a live view
/// hierarchy, so views register their action here as they appear. Requests
/// arriving when no window exists (Finder Sync `tether://` URLs, Dock-icon
/// drops, the ⌥T hotkey, Services) go through this router and therefore work
/// regardless of which windows are open — falling back to an AppKit-hosted
/// window in the unlikely case no action has been registered yet.
@MainActor
final class WindowRouter {
    static let shared = WindowRouter()

    private var openWindowAction: OpenWindowAction?
    private var fallbackWindowControllers: [NSWindowController] = []

    private init() {}

    /// Called by views (drop zone, menu bar extra) when their environment's
    /// `openWindow` action becomes available.
    func register(_ action: OpenWindowAction) {
        openWindowAction = action
    }

    /// Opens (or focuses) the note editor for `fileURL` and brings the app forward.
    func openNoteEditor(for fileURL: URL) {
        if let openWindowAction {
            // WindowGroup deduplicates by value: an already-open editor for the
            // same file is brought to the front instead of duplicated.
            openWindowAction(id: "note-editor", value: fileURL)
        } else {
            presentFallbackWindow(
                title: "Tether Note — \(fileURL.lastPathComponent)",
                size: NSSize(width: 520, height: 640),
                rootView: NoteEditorView(fileURL: fileURL)
            )
        }
        NSApp.activate()
    }

    /// Opens the main drop-zone window and brings the app forward.
    func openMainWindow() {
        if let openWindowAction {
            openWindowAction(id: "main")
        } else {
            presentFallbackWindow(
                title: "Tether",
                size: NSSize(width: 440, height: 340),
                rootView: DropZoneView()
            )
        }
        NSApp.activate()
    }

    /// Opens (or focuses) the settings window and brings the app forward.
    func openSettings() {
        if let openWindowAction {
            openWindowAction(id: "settings")
        } else {
            presentFallbackWindow(
                title: "Global Shortcut",
                size: NSSize(width: 440, height: 230),
                rootView: SettingsView()
            )
        }
        NSApp.activate()
    }

    /// Last-resort window presentation when no SwiftUI `openWindow` action has
    /// been registered (e.g. a `tether://` URL arrives before any scene's view
    /// hierarchy exists).
    private func presentFallbackWindow<Content: View>(title: String, size: NSSize, rootView: Content) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: rootView))
        window.title = title
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        fallbackWindowControllers.append(controller)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self, weak controller] _ in
            Task { @MainActor in
                guard let self, let controller else { return }
                self.fallbackWindowControllers.removeAll { $0 === controller }
            }
        }
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
