import Cocoa
import Quartz
import SwiftUI
import TetherCore

/// Quick Look preview for files carrying a FileLore note.
///
/// Shows the file's native content (video player, image, PDF, or text) on the
/// left and the note panel on the right in an `NSSplitView` (~62%/38%). The
/// native content is rendered MANUALLY — `QLPreviewView` is never used, so the
/// preview cannot recurse into this same extension through the Quick Look
/// generator registry.
///
/// Known limitation (tracked for a later milestone): the extension declares
/// broad content types, so once enabled it can shadow the default Quick Look
/// preview for files without notes. For files with no note we throw, and
/// Quick Look reports "no preview available".
///
/// Sandbox note: direct `com.filelore.note` xattr reads were verified to work
/// inside this extension's sandbox (see `filelore-ql-debug.log` in the
/// container), so — unlike the Finder Sync badge path — no mirrored note
/// cache is needed.
@MainActor
final class PreviewViewController: NSViewController, QLPreviewingController {

    /// Fraction of the panel width given to the media pane; the note pane
    /// gets the rest, clamped to `noteMinWidth`.
    private let mediaFraction: CGFloat = 0.62
    private let noteMinWidth: CGFloat = 300
    private let mediaMinWidth: CGFloat = 320

    /// Keeps the security-scoped URL alive for the lifetime of the preview so
    /// the AVPlayer can stream from it.
    private var accessedURL: URL?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 960, height: 600))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        DebugLog.log("preparePreviewOfFile: \(url.path(percentEncoded: false))")

        let note: Note?
        do {
            note = try NoteStore.read(url: url)
            DebugLog.log("xattr read succeeded — \(note == nil ? "no note" : "note found (\(note!.body.count) chars, \(note!.tags.count) tags, \(note!.links.count) links)")")
        } catch {
            DebugLog.log("xattr read FAILED: \(error)")
            note = nil
        }
        guard let note else {
            DebugLog.log("no note — throwing so Quick Look reports no preview")
            throw NSError(
                domain: "com.filelore.app.QuickLook",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No FileLore note attached to this file."]
            )
        }

        if url.startAccessingSecurityScopedResource() {
            accessedURL = url
        }

        // Re-preparing the same controller: clear any previous content.
        view.subviews.forEach { $0.removeFromSuperview() }

        let mediaKind = MediaPreview.kind(for: url)
        DebugLog.log("media kind: \(mediaKind)")

        let mediaView: NSView
        switch mediaKind {
        case .av: DebugLog.log("media path: AVPlayerView (video/audio)")
        case .image: DebugLog.log("media path: NSImageView (image, decoded via ImageIO)")
        case .pdf: DebugLog.log("media path: PDFView")
        case .text: DebugLog.log("media path: NSTextView (plain text)")
        case .other: DebugLog.log("media path: file icon fallback")
        }
        if let framed = MediaPreview.makeFramedMediaView(for: url) {
            // Float the framed card (rounded corners, hairline border,
            // window-matching background) inside the split pane with a
            // margin on all sides.
            mediaView = Self.marginContainer(framed, margin: 10)
        } else {
            if mediaKind != .other { DebugLog.log("renderer could not decode file — falling back to icon") }
            mediaView = makeIconView(for: url)
        }
        let noteView = NSHostingView(rootView: NotePreviewView(note: note, fileURL: url))

        let splitView = NSSplitView(frame: view.bounds)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        splitView.delegate = self
        splitView.addSubview(mediaView)
        splitView.addSubview(noteView)
        // Note pane holds its width on window resize; media pane flexes.
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        view.addSubview(splitView)

        let mediaWidth = max(mediaMinWidth, splitView.bounds.width * mediaFraction)
        splitView.setPosition(mediaWidth, ofDividerAt: 0)
        DebugLog.log("split view rendered (media \(Int(mediaWidth))pt / note rest, min \(Int(noteMinWidth))pt)")
    }

    // MARK: - Native content rendering

    // Media-type detection and media-view construction live in TetherCore
    // (`MediaPreview`), shared with the main app's note-editor media pane.

    /// Wraps a view in a plain container that keeps a constant margin around
    /// it (autoresizing-based, so it plays well with NSSplitView's frame
    /// resizing). The container background matches the window.
    private static func marginContainer(_ content: NSView, margin: CGFloat) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        content.frame = container.bounds.insetBy(dx: margin, dy: margin)
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        return container
    }

    /// Fallback for files with no media renderer: large file icon.
    private func makeIconView(for url: URL) -> NSView {
        let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        icon.size = NSSize(width: 256, height: 256)

        let imageView = NSImageView(image: icon)
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    deinit {
        if let accessedURL {
            accessedURL.stopAccessingSecurityScopedResource()
        }
    }
}

// MARK: - NSSplitViewDelegate

extension PreviewViewController: NSSplitViewDelegate {
    /// Left (media) pane minimum width.
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        mediaMinWidth
    }

    /// Right (note) pane minimum width, expressed as the maximum divider position.
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        splitView.bounds.width - noteMinWidth
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
        .padding(20)
        .frame(minWidth: 260, minHeight: 300)
    }
}
