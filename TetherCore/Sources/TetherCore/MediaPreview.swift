import AppKit
import AVFoundation
import AVKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// The media treatment a file gets in FileLore's preview surfaces (Quick Look
/// extension, note editor media pane).
public enum MediaPreviewKind: Equatable, Sendable {
    /// Video/audio → playable `AVPlayerView` (start-paused).
    case av
    /// Images, including PSD (decoded via ImageIO) → aspect-fit `NSImageView`.
    case image
    /// PDF → `PDFKit.PDFView`.
    case pdf
    /// Plain text → read-only scrollable `NSTextView`.
    case text
    /// Anything else → callers show their own fallback (no media pane).
    case other
}

/// Shared media-type detection and media-pane construction for the FileLore
/// app and the Quick Look extension. Sandbox-safe APIs only: file URLs,
/// ImageIO, AVKit, PDFKit — no workspace open, no inter-process calls.
public enum MediaPreview {

    // MARK: - Type detection

    /// Path-extension fallbacks used when the file's UTI is dynamic
    /// (unregistered extensions get `dyn.*` UTIs that only conform to
    /// `public.data`, so conformance checks alone can't see what the file is).
    private static let avExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mpg", "mpeg", "mpe", "m2v", "mts", "m2ts",
        "avi", "mkv", "webm", "wmv", "flv", "3gp", "3g2",
        "mp3", "m4a", "aac", "aif", "aiff", "aifc", "au", "wav", "caf",
        "flac", "ogg", "opus", "wma",
    ]
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tif", "tiff", "gif", "bmp", "heic", "heif",
        "webp", "psd", "psb", "raw", "dng", "cr2", "cr3", "nef", "arw",
        "orf", "rw2", "exr", "hdr",
    ]
    private static let textExtensions: Set<String> = [
        "txt", "text", "md", "markdown", "log", "csv", "tsv", "json",
        "xml", "yaml", "yml", "toml", "ini", "cfg", "conf",
        "swift", "py", "js", "ts", "sh", "zsh", "bash", "c", "h", "cpp",
        "hpp", "cc", "java", "kt", "rb", "go", "rs", "html", "css", "sql",
    ]

    /// Maps a file URL to its media kind: UTType conformance first (read from
    /// the file's real content type when available), with a path-extension
    /// heuristic as fallback for dynamic UTIs.
    public static func kind(for url: URL) -> MediaPreviewKind {
        let contentType = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data
        let ext = url.pathExtension.lowercased()
        if contentType.conforms(to: .audiovisualContent)
            || contentType.conforms(to: .movie)
            || contentType.conforms(to: .audio)
            || avExtensions.contains(ext) {
            return .av
        }
        if contentType.conforms(to: .image) || imageExtensions.contains(ext) {
            return .image
        }
        if contentType.conforms(to: .pdf) || ext == "pdf" {
            return .pdf
        }
        if contentType.conforms(to: .text) || contentType.conforms(to: .sourceCode)
            || textExtensions.contains(ext) {
            return .text
        }
        return .other
    }

    // MARK: - View construction

    /// Builds the media pane for the file, choosing the renderer via
    /// `kind(for:)`. Returns `nil` for `.other` and when the specific renderer
    /// can't decode the file, so the caller decides the fallback (Quick Look
    /// shows a large file icon; the app editor omits the media pane).
    public static func makeMediaView(for url: URL) -> NSView? {
        switch kind(for: url) {
        case .av: return makePlayerView(for: url)
        case .image: return makeImageView(for: url)
        case .pdf: return makePDFView(for: url)
        case .text: return makeTextView(for: url)
        case .other: return nil
        }
    }

    /// Video/audio: playable `AVPlayerView` with inline controls. The player
    /// starts paused — no autoplay-with-sound surprises.
    private static func makePlayerView(for url: URL) -> NSView {
        let playerView = AVPlayerView()
        playerView.player = AVPlayer(url: url)
        playerView.controlsStyle = .inline
        playerView.videoGravity = .resizeAspect
        return playerView
    }

    /// Images: aspect-fit `NSImageView`. Decoding goes through ImageIO
    /// (`CGImageSource`), which also handles PSD (`com.adobe.photoshop-image`).
    private static func makeImageView(for url: URL) -> NSView? {
        var image: NSImage?
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } else {
            image = NSImage(contentsOf: url)
        }
        guard let image else { return nil }
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        return imageView
    }

    /// PDF: `PDFKit.PDFView` with auto-scaling.
    private static func makePDFView(for url: URL) -> NSView? {
        guard let document = PDFDocument(url: url) else { return nil }
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = document
        return pdfView
    }

    /// Plain text: read-only, scrollable `NSTextView`. Very large files are
    /// truncated to the first 512 KB to stay within extension memory limits.
    private static func makeTextView(for url: URL) -> NSView? {
        var text: String?
        if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
            let capped = data.count > 512 * 1024 ? data.prefix(512 * 1024) : data
            text = String(data: capped, encoding: .utf8)
                ?? String(data: capped, encoding: .isoLatin1)
            if data.count > 512 * 1024 {
                text = (text ?? "") + "\n\n[… truncated — showing first 512 KB …]"
            }
        }
        guard let text else { return nil }

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
}
