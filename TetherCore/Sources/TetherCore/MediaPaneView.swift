import AppKit

/// A framed card that hosts a media pane (video player, image, PDF, text):
/// rounded corners matching the window style, a hairline separator border,
/// and a background that matches the window so letterboxed areas (video
/// pillarbox, image letterbox) read as deliberate design instead of
/// background slivers leaking around the content.
///
/// Shared by the FileLore note editor and the Quick Look extension via
/// `MediaPreview.makeFramedMediaView`. The container clips its content to
/// the rounded rect, so player views and scroll views cannot spill past
/// the card's corners.
public final class MediaPaneView: NSView {

    /// The wrapped media view (AVPlayerView, LetterboxedImageView, PDFView,
    /// or a scroll view hosting an NSTextView).
    public let contentView: NSView

    /// Padding between the card's border and the content.
    private let contentInset: CGFloat

    public init(contentView: NSView, contentInset: CGFloat = 0, cornerRadius: CGFloat = 10) {
        self.contentView = contentView
        self.contentInset = contentInset
        super.init(frame: .zero)

        wantsLayer = true
        if let layer {
            layer.cornerRadius = cornerRadius
            layer.masksToBounds = true
            // Hairline border: half a point so it stays crisp on Retina and
            // reads as a subtle separator rather than a heavy stroke.
            layer.borderWidth = 0.5
        }

        addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInset),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInset),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: contentInset),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInset),
        ])

        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    /// Re-resolve dynamic colors against the current appearance (light/dark).
    private func updateColors() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}
