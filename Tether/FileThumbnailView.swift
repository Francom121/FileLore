import SwiftUI
import AppKit
import QuickLookThumbnailing

/// Loads a file's real Quick Look thumbnail (what Finder shows) via
/// `QLThumbnailGenerator`, falling back to the generic workspace icon when
/// Quick Look can't produce one.
enum ThumbnailProvider {
    static func thumbnail(for url: URL, pointSize: CGFloat) async -> NSImage {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: pointSize, height: pointSize),
            scale: 2,
            representationTypes: .thumbnail
        )
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return representation.nsImage
        }
        return workspaceIcon(for: url, pointSize: pointSize)
    }

    /// The generic type icon (e.g. the VLC cone for mp4) — used as the
    /// placeholder while Quick Look loads and as the permanent fallback.
    static func workspaceIcon(for url: URL, pointSize: CGFloat) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        icon.size = CGSize(width: pointSize, height: pointSize)
        return icon
    }
}

/// A file's real Quick Look thumbnail, rendered asynchronously: shows the
/// generic workspace icon immediately, swaps in the Quick Look thumbnail when
/// it arrives, and keeps the icon if thumbnail generation fails.
struct FileThumbnailView: View {
    let url: URL
    var pointSize: CGFloat
    var cornerRadius: CGFloat = 8

    @State private var thumbnail: NSImage?

    var body: some View {
        Image(nsImage: thumbnail ?? ThumbnailProvider.workspaceIcon(for: url, pointSize: pointSize))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: pointSize, height: pointSize)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: url, priority: .userInitiated) {
                thumbnail = await ThumbnailProvider.thumbnail(for: url, pointSize: pointSize)
            }
    }
}
