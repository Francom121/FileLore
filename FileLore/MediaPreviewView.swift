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
        MediaPreview.makeMediaView(for: url) ?? NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        if let playerView = nsView as? AVPlayerView {
            playerView.player?.pause()
            playerView.player = nil
        }
    }
}
