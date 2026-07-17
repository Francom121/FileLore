import SwiftUI
import AppKit

/// Menu bar dropdown: the 10 most recently noted files.
/// Click opens the note editor; ⌥-click reveals the file in Finder.
struct RecentFilesMenu: View {
    @Environment(\.openWindow) private var openWindow
    @State private var entries: [KnownFilesRegistry.Entry] = []

    var body: some View {
        Group {
            if entries.isEmpty {
                Text("No noted files yet")
            } else {
                ForEach(entries, id: \.path) { entry in
                    Button {
                        let url = URL(fileURLWithPath: entry.path)
                        if NSEvent.modifierFlags.contains(.option) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } else {
                            WindowRouter.shared.openNoteEditor(for: url)
                        }
                    } label: {
                        Label(entry.displayName, systemImage: "note.text")
                    }
                }
                Divider()
                Text("⌥-click to reveal in Finder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button("Search Notes…") {
                WindowRouter.shared.openSearch()
            }
            Button("Global Shortcut: \(HotKeyManager.shared.currentShortcut.displayString)") {
                WindowRouter.shared.openSettings()
            }
            Button("Refresh") { reload() }
            Button("Quit Tether") { NSApp.terminate(nil) }
        }
        .onAppear {
            reload()
            WindowRouter.shared.register(openWindow)
        }
    }

    private func reload() {
        entries = KnownFilesRegistry.shared.recent(10)
    }
}
