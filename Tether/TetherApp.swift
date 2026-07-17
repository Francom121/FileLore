import SwiftUI

@main
struct TetherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Tether", id: "main") {
            DropZoneView()
        }
        .defaultSize(width: 440, height: 340)

        WindowGroup("Tether Note", id: "note-editor", for: URL.self) { $fileURL in
            if let fileURL {
                NoteEditorView(fileURL: fileURL)
            } else {
                Text("No file")
            }
        }
        .defaultSize(width: 520, height: 640)

        Window("Global Shortcut", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Tether", systemImage: "note.text") {
            RecentFilesMenu()
        }
    }
}

enum TetherURLRouter {
    /// Handles `tether://open?path=...` links (e.g. from the Finder Sync extension).
    static func fileURL(from url: URL) -> URL? {
        guard url.scheme == "tether", url.host == "open" else { return nil }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = comps.queryItems?.first(where: { $0.name == "path" })?.value,
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
