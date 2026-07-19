import SwiftUI

@main
struct FileLoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("FileLore", id: "main") {
            DropZoneView()
        }
        .defaultSize(width: 440, height: 340)
        // The drop zone is opened explicitly by AppDelegate/WindowRouter
        // (cold launch, Dock-icon reopen, or an explicit user command) and
        // never restored, so a previously duplicated drop zone can never
        // resurrect a second one; there is exactly one drop zone,
        // raised/reused via WindowRouter.openMainWindow().
        .restorationBehavior(.disabled)
        // This scene must NOT be a target for incoming files/URLs: without
        // this, SwiftUI delivers every open-document event to the "main"
        // WindowGroup by materializing a NEW drop-zone window per event
        // (one per Finder right-click → Add/Edit FileLore Note).
        .handlesExternalEvents(matching: [])
        .commands {
            // ⌘F opens the search window whenever the app is active.
            CommandGroup(after: .newItem) {
                Button("Search Notes…") { WindowRouter.shared.openSearch() }
                    .keyboardShortcut("f", modifiers: .command)
            }
            // The app ships no Help Book; the Help menu slot becomes the
            // keyboard-shortcut cheat sheet.
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts…") { WindowRouter.shared.openShortcuts() }
            }
        }

        WindowGroup("FileLore Note", id: "note-editor", for: URL.self) { $fileURL in
            if let fileURL {
                NoteEditorView(fileURL: fileURL)
            } else {
                Text("No file")
            }
        }
        // Roomier default so the media peek pane fits beside the note controls.
        .defaultSize(width: 900, height: 560)
        // Editors are presented exclusively via WindowRouter (openWindow),
        // which deduplicates by file URL. Declaring no external events keeps
        // SwiftUI from materializing a zombie nil-value editor window for
        // every incoming open-document event.
        .handlesExternalEvents(matching: [])

        Window("Search Notes", id: "search") {
            SearchView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 620, height: 520)
        // Not a target for incoming files/URLs (see "main" above).
        .handlesExternalEvents(matching: [])

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])

        Window("Keyboard Shortcuts", id: "shortcuts") {
            ShortcutsPanelView()
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: [])

        // The status item is SwiftUI-managed: created exactly once at launch,
        // independent of any window state, and alive for the whole app run.
        // Keep this unconditional — no `isInserted:` binding, no preference
        // gate, nothing tied to window lifecycle. The branded quill image is
        // template-rendered so it adapts to the menu bar's light/dark state,
        // and the asset is named "FileLore" on purpose: the menu bar item's
        // accessibility label comes from the asset name, which is how the
        // item is identified in System Settings → Menu Bar. (If the item
        // still doesn't appear, the cause is user-side: macOS 26 collapses
        // menu bar items behind the » chevron and manages them per app in
        // System Settings → Menu Bar.)
        MenuBarExtra("FileLore", image: "FileLore") {
            RecentFilesMenu()
        }
    }
}

enum FileLoreURLRouter {
    /// Handles `filelore://open?path=...` links (e.g. from the Finder Sync extension).
    static func fileURL(from url: URL) -> URL? {
        guard url.scheme == "filelore", url.host == "open" else { return nil }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = comps.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
