import SwiftUI

/// Main window: a prominent drop zone. Dropping a file (or opening one via the
/// Dock icon / `tether://` URL) opens a note editor window for that file.
struct DropZoneView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "note.text.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text("Drop a file to attach a note")
                .font(.title2.weight(.semibold))
            Text("You can also drop files onto the Tether Dock icon,\nright-click a file in Finder → Add/Edit Tether Note,\nor select a file in Finder and press ⌥T.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .padding(16)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in openWindow(id: "note-editor", value: url) }
                }
            }
            return true
        }
        .onOpenURL { url in
            if url.scheme == "tether", let fileURL = TetherURLRouter.fileURL(from: url) {
                openWindow(id: "note-editor", value: fileURL)
            } else if url.isFileURL {
                openWindow(id: "note-editor", value: url)
            }
        }
        .onAppear { WindowRouter.shared.register(openWindow) }
    }
}
