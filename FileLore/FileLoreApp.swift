import SwiftUI

@main
struct FileLoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("FileLore", id: "main") {
            DropZoneView()
        }
        .defaultSize(width: 440, height: 340)
        .commands {
            // ⌘F opens the search window whenever the app is active.
            CommandGroup(after: .newItem) {
                Button("Search Notes…") { WindowRouter.shared.openSearch() }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }

        WindowGroup("FileLore Note", id: "note-editor", for: URL.self) { $fileURL in
            if let fileURL {
                NoteEditorView(fileURL: fileURL)
            } else {
                Text("No file")
            }
        }
        .defaultSize(width: 520, height: 640)

        Window("Search Notes", id: "search") {
            SearchView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 620, height: 520)

        Window("Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)

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
