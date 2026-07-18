import Cocoa
import Quartz
import SwiftUI
import TetherCore

/// Quick Look preview for files carrying a FileLore note.
///
/// Known limitation (tracked for a later milestone): the extension declares a
/// broad content type (`public.data`), so once enabled it can shadow the
/// default Quick Look preview for files without notes. For files with no note
/// we throw, and Quick Look reports "no preview available".
final class PreviewViewController: NSViewController, QLPreviewingController {

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        guard let note = try NoteStore.read(url: url) else {
            throw NSError(
                domain: "com.filelore.app.QuickLook",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No FileLore note attached to this file."]
            )
        }
        let hostingView = NSHostingView(rootView: NotePreviewView(note: note, fileURL: url))
        hostingView.frame = view.bounds
        hostingView.autoresizingMask = [.width, .height]
        view.addSubview(hostingView)
    }
}

/// Renders the note: body (with clickable web links), tags, and linked files.
struct NotePreviewView: View {
    let note: Note
    let fileURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(fileURL.lastPathComponent).font(.headline)
                    Text("FileLore Note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            ScrollView {
                Text(LinkDetector.attributedString(for: note.body))
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)

            if !note.tags.isEmpty {
                Text(note.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !note.links.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Linked Files").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(note.links) { link in
                        Label(link.displayName, systemImage: "paperclip")
                            .font(.callout)
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 320)
    }
}
