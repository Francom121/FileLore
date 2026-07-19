import SwiftUI
import AppKit

/// Central routing point for "open the note editor / main window" requests.
///
/// SwiftUI's `openWindow` environment action only exists inside a live view
/// hierarchy, so views register their action here as they appear. Requests
/// arriving when no window exists (Finder Sync `filelore://` URLs, Dock-icon
/// drops, the ⌥T hotkey, Services) go through this router and therefore work
/// regardless of which windows are open — falling back to an AppKit-hosted
/// window in the unlikely case no action has been registered yet.
@MainActor
final class WindowRouter {
    static let shared = WindowRouter()

    private var openWindowAction: OpenWindowAction?
    private var fallbackWindowControllers: [NSWindowController] = []
    /// The live drop-zone window, captured by `DropZoneView` once it joins a
    /// window. Lets `openMainWindow()` raise the existing drop zone instead
    /// of duplicating it.
    private weak var mainWindow: NSWindow?

    private init() {}

    /// Called by views (drop zone, menu bar extra) when their environment's
    /// `openWindow` action becomes available.
    func register(_ action: OpenWindowAction) {
        openWindowAction = action
    }

    /// Called by the drop-zone view when its hosting window materializes.
    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
    }

    /// Opens (or focuses) the note editor for `fileURL` and brings the app forward.
    func openNoteEditor(for fileURL: URL) {
        openNoteEditor(for: fileURL, retriesRemaining: 100)
    }

    private func openNoteEditor(for fileURL: URL, retriesRemaining: Int) {
        if let openWindowAction {
            // WindowGroup deduplicates by value: an already-open editor for the
            // same file is brought to the front instead of duplicated.
            openWindowAction(id: "note-editor", value: fileURL)
            NSApp.activate()
            return
        }
        if retriesRemaining > 0 {
            // Cold launch: no scene has registered its openWindow action yet
            // (SwiftUI materializes scenes a moment after didFinishLaunching,
            // and a first-run privacy prompt can stall that for seconds).
            // Falling back to an AppKit window right away would duplicate the
            // editor SwiftUI presents for the same file a moment later —
            // retry briefly first (100 × 0.1s), then fall back as before.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.openNoteEditor(for: fileURL, retriesRemaining: retriesRemaining - 1)
            }
            return
        }
        presentFallbackEditor(for: fileURL)
        NSApp.activate()
    }

    /// Opens (or focuses) the main drop-zone window and brings the app forward.
    ///
    /// Single-instance: if a drop-zone window already exists it is raised,
    /// never duplicated — `openWindow(id:)` on a WindowGroup would create a
    /// NEW window on every call, which is how repeated Finder "Add/Edit
    /// FileLore Note" invocations used to pile up drop-zone windows.
    func openMainWindow() {
        if let mainWindow, mainWindow.isVisible || mainWindow.isMiniaturized {
            if mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            }
            mainWindow.makeKeyAndOrderFront(nil)
        } else if let openWindowAction {
            openWindowAction(id: "main")
        } else {
            presentFallbackWindow(
                title: "FileLore",
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
                title: "Settings",
                size: NSSize(width: 440, height: 230),
                rootView: SettingsView()
            )
        }
        NSApp.activate()
    }

    /// Opens (or focuses) the keyboard-shortcut cheat sheet and brings the
    /// app forward.
    func openShortcuts() {
        if let openWindowAction {
            openWindowAction(id: "shortcuts")
        } else {
            presentFallbackWindow(
                title: "Keyboard Shortcuts",
                size: NSSize(width: 520, height: 560),
                rootView: ShortcutsPanelView()
            )
        }
        NSApp.activate()
    }

    /// Opens (or focuses) the Spotlight-style search window and brings the app forward.
    func openSearch() {
        if let openWindowAction {
            openWindowAction(id: "search")
        } else {
            presentFallbackWindow(
                title: "Search Notes",
                size: NSSize(width: 620, height: 520),
                rootView: SearchView()
            )
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens (or focuses) the batch tag/note editor for `fileURLs` and brings
    /// the app forward. A single URL keeps the classic behavior: one editor.
    ///
    /// Always presented through the AppKit-hosted fallback window: value-based
    /// `WindowGroup` presentation with an Array value proved to silently no-op,
    /// so no scene involvement here keeps batch presentation deterministic.
    func openBatchEditor(for fileURLs: [URL]) {
        guard fileURLs.count > 1 else {
            if let only = fileURLs.first { openNoteEditor(for: only) }
            return
        }
        presentFallbackWindow(
            title: "FileLore Batch Edit — \(fileURLs.count) files",
            size: NSSize(width: 560, height: 620),
            rootView: BatchEditView(fileURLs: fileURLs)
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Last-resort window presentation when no SwiftUI `openWindow` action has
    /// been registered (e.g. a `filelore://` URL arrives before any scene's view
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

    /// Fallback note editors, keyed by file URL, so a late-materializing
    /// SwiftUI editor for the same file can replace them (never two editors
    /// for one file).
    private var fallbackEditors: [URL: NSWindowController] = [:]

    /// Fallback window presentation specifically for note editors: tracked so
    /// `swiftUIEditorDidAppear(for:)` can close it if SwiftUI also presents
    /// an editor for the same file.
    private func presentFallbackEditor(for fileURL: URL) {
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: NoteEditorView(fileURL: fileURL, isFallbackHosted: true)
        ))
        window.title = "FileLore Note — \(fileURL.lastPathComponent)"
        window.setContentSize(NSSize(width: 900, height: 560))
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        fallbackEditors[fileURL] = controller
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.fallbackEditors.removeValue(forKey: fileURL)
            }
        }
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    /// Called by a SwiftUI-hosted note editor when it appears. If a fallback
    /// AppKit editor is open for the same file (cold-launch race), close it —
    /// the SwiftUI window is the canonical one.
    func swiftUIEditorDidAppear(for fileURL: URL) {
        guard let controller = fallbackEditors.removeValue(forKey: fileURL) else { return }
        controller.window?.close()
    }
}
