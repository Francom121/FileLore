import AVKit
import SwiftUI
import TetherCore

/// Hosts TetherCore's AppKit media pane (video player / image / PDF / text)
/// for the noted file inside the SwiftUI note editor, beside the note controls.
///
/// Detection and view construction are shared with the Quick Look extension
/// via `MediaPreview`. The player starts paused; when the editor window
/// closes, `dismantleNSView` stops and releases it so no audio leaks from a
/// closed window.
struct MediaPreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        // Framed card: rounded corners, hairline border, window-matching
        // background so letterboxed video/image areas look deliberate.
        MediaPreview.makeFramedMediaView(for: url) ?? NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // The media view may be nested inside the MediaPaneView card, so
        // search the subtree for the player to stop and release.
        if let playerView = Self.findPlayerView(in: nsView) {
            playerView.player?.pause()
            playerView.player = nil
        }
    }

    private static func findPlayerView(in view: NSView) -> AVPlayerView? {
        if let playerView = view as? AVPlayerView { return playerView }
        for subview in view.subviews {
            if let playerView = findPlayerView(in: subview) { return playerView }
        }
        return nil
    }
}
