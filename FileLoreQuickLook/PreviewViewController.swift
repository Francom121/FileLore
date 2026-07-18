import AVFoundation
import AVKit
import Cocoa
import ImageIO
import PDFKit
import Quartz
import SwiftUI
import UniformTypeIdentifiers
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

        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data
        DebugLog.log("content type: \(contentType.identifier)")

        let mediaView = makeMediaView(for: url, contentType: contentType)
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

    /// Builds the left-hand media pane for the file, choosing the renderer by
    /// UTType conformance, with a path-extension heuristic as fallback for
    /// files whose UTI is dynamic (unregistered extensions get `dyn.*` UTIs
    /// that only conform to `public.data`). Every path logs its choice.
    private func makeMediaView(for url: URL, contentType: UTType) -> NSView {
        let ext = url.pathExtension.lowercased()
        if contentType.conforms(to: .audiovisualContent)
            || contentType.conforms(to: .movie)
            || contentType.conforms(to: .audio)
            || MediaKind.avExtensions.contains(ext) {
            DebugLog.log("media path: AVPlayerView (video/audio)")
            return makePlayerView(for: url)
        }
        if contentType.conforms(to: .image) || MediaKind.imageExtensions.contains(ext) {
            DebugLog.log("media path: NSImageView (image, decoded via ImageIO)")
            return makeImageView(for: url)
        }
        if contentType.conforms(to: .pdf) || ext == "pdf" {
            DebugLog.log("media path: PDFView")
            return makePDFView(for: url)
        }
        if contentType.conforms(to: .text) || contentType.conforms(to: .sourceCode)
            || MediaKind.textExtensions.contains(ext) {
            DebugLog.log("media path: NSTextView (plain text)")
            return makeTextView(for: url)
        }
        DebugLog.log("media path: file icon fallback")
        return makeIconView(for: url)
    }

    /// Path-extension fallbacks used when the file's UTI is dynamic and
    /// conformance checks can't see what the file is.
    private enum MediaKind {
        static let avExtensions: Set<String> = [
            "mp4", "m4v", "mov", "mpg", "mpeg", "mpe", "m2v", "mts", "m2ts",
            "avi", "mkv", "webm", "wmv", "flv", "3gp", "3g2",
            "mp3", "m4a", "aac", "aif", "aiff", "aifc", "au", "wav", "caf",
            "flac", "ogg", "opus", "wma",
        ]
        static let imageExtensions: Set<String> = [
            "png", "jpg", "jpeg", "tif", "tiff", "gif", "bmp", "heic", "heif",
            "webp", "psd", "psb", "raw", "dng", "cr2", "cr3", "nef", "arw",
            "orf", "rw2", "exr", "hdr",
        ]
        static let textExtensions: Set<String> = [
            "txt", "text", "md", "markdown", "log", "csv", "tsv", "json",
            "xml", "yaml", "yml", "toml", "ini", "cfg", "conf",
            "swift", "py", "js", "ts", "sh", "zsh", "bash", "c", "h", "cpp",
            "hpp", "cc", "java", "kt", "rb", "go", "rs", "html", "css", "sql",
        ]
    }

    /// Video/audio: playable `AVPlayerView` with inline controls.
    private func makePlayerView(for url: URL) -> NSView {
        let playerView = AVPlayerView()
        playerView.player = AVPlayer(url: url)
        playerView.controlsStyle = .inline
        playerView.videoGravity = .resizeAspect
        return playerView
    }

    /// Images: aspect-fit `NSImageView`. Decoding goes through ImageIO
    /// (`CGImageSource`), which also handles PSD (`com.adobe.photoshop-image`).
    private func makeImageView(for url: URL) -> NSView {
        var image: NSImage?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } else {
            image = NSImage(contentsOf: url)
            if image == nil {
                DebugLog.log("image decode FAILED via ImageIO and NSImage — falling back to icon")
                return makeIconView(for: url)
            }
            DebugLog.log("image decoded via NSImage fallback (ImageIO returned nil)")
        }
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        return imageView
    }

    /// PDF: `PDFKit.PDFView` with auto-scaling.
    private func makePDFView(for url: URL) -> NSView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        } else {
            DebugLog.log("PDFDocument FAILED to load — falling back to icon")
            return makeIconView(for: url)
        }
        return pdfView
    }

    /// Plain text: read-only, scrollable `NSTextView`. Very large files are
    /// truncated to the first 512 KB to stay within extension memory limits.
    private func makeTextView(for url: URL) -> NSView {
        var text: String?
        if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
            let capped = data.count > 512 * 1024 ? data.prefix(512 * 1024) : data
            text = String(data: capped, encoding: .utf8)
                ?? String(data: capped, encoding: .isoLatin1)
            if data.count > 512 * 1024 {
                text = (text ?? "") + "\n\n[… truncated — showing first 512 KB …]"
            }
        }
        guard let text else {
            DebugLog.log("text decode FAILED — falling back to icon")
            return makeIconView(for: url)
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.string = text
        // Wrap to the scroll view's width.
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    /// Anything else: large file icon.
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
