import SwiftUI
import AppKit

/// Menu bar dropdown: the 10 most recently noted files. Click reveals in Finder.
struct RecentFilesMenu: View {
    @State private var entries: [KnownFilesRegistry.Entry] = []

    var body: some View {
        Group {
            if entries.isEmpty {
                Text("No noted files yet")
            } else {
                ForEach(entries, id: \.path) { entry in
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
                    } label: {
                        Label(entry.displayName, systemImage: "note.text")
                    }
                }
            }
            Divider()
            Button("Refresh") { reload() }
            Button("Quit Tether") { NSApp.terminate(nil) }
        }
        .onAppear { reload() }
    }

    private func reload() {
        entries = KnownFilesRegistry.shared.recent(10)
    }
}
