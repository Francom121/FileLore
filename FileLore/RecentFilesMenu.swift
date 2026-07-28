import SwiftUI
import AppKit

/// Menu bar dropdown: pinned tags (each a submenu of the noted files carrying
/// it) above the 10 most recently noted files.
/// Click opens the note editor; ⌥-click reveals the file in Finder.
struct RecentFilesMenu: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var pinnedStore = PinnedTagsStore.shared
    /// All known noted files (the pinned-tag submenus need files that may be
    /// older than the 10 shown under Recent Files).
    @State private var entries: [KnownFilesRegistry.Entry] = []

    private var recents: [KnownFilesRegistry.Entry] {
        Array(entries.sorted { $0.updatedAt > $1.updatedAt }.prefix(10))
    }

    var body: some View {
        Group {
            // Start a note from the menu bar: raises the single-instance drop
            // zone (the app's landing window for picking/dropping a file).
            Button("New Note…") {
                WindowRouter.shared.openMainWindow()
            }

            Divider()

            Section("Pinned Tags") {
                if pinnedStore.pinned.isEmpty {
                    Text("No pinned tags")
                } else {
                    ForEach(pinnedStore.pinned, id: \.self) { tag in
                        pinnedTagMenu(tag)
                    }
                }
            }

            Section("Recent Files") {
                if recents.isEmpty {
                    Text("No noted files yet")
                } else {
                    ForEach(recents, id: \.path) { entry in
                        Button {
                            openOrReveal(entry)
                        } label: {
                            Label(entry.displayName, systemImage: "note.text")
                        }
                    }
                    Text("⌥-click to reveal in Finder")
                        .font(.caption)
                }
            }

            Divider()
            Button("Search Notes…") {
                WindowRouter.shared.openSearch()
            }
            Button("Keyboard Shortcuts…") {
                WindowRouter.shared.openShortcuts()
            }
            Button("Global Shortcut: \(HotKeyManager.shared.currentShortcut.displayString)") {
                WindowRouter.shared.openSettings()
            }
            Button("Refresh") { reload() }
            Button("Check for Updates…") {
                UpdaterController.shared.checkForUpdates(nil)
            }
            Button("Quit FileLore") { NSApp.terminate(nil) }
        }
        .onAppear {
            reload()
            WindowRouter.shared.register(openWindow)
        }
    }

    /// One pinned tag → submenu of the noted files carrying it, most recently
    /// updated first (capped so the menu stays usable).
    private func pinnedTagMenu(_ tag: String) -> some View {
        let matches = entries
            .filter { $0.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(15)
        return Menu {
            if matches.isEmpty {
                Text("No noted files with #\(tag)")
            } else {
                ForEach(Array(matches), id: \.path) { entry in
                    Button {
                        openOrReveal(entry)
                    } label: {
                        Label(entry.displayName, systemImage: "note.text")
                    }
                }
            }
        } label: {
            Label("#\(tag)", systemImage: "tag")
        }
    }

    private func openOrReveal(_ entry: KnownFilesRegistry.Entry) {
        let url = URL(fileURLWithPath: entry.path)
        if NSEvent.modifierFlags.contains(.option) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            WindowRouter.shared.openNoteEditor(for: url)
        }
    }

    private func reload() {
        KnownFilesRegistry.shared.load()
        entries = KnownFilesRegistry.shared.entries
    }
}
