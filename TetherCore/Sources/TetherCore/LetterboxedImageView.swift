import AppKit

/// An image view that renders its image like Quick Look does: aspect-fit,
/// letterboxed, centered, clipped strictly to its own bounds, downscale-only
/// (small images stay at their natural size).
///
/// Why not `NSImageView`: it reports the image's native size as its intrinsic
/// content size, so inside a SwiftUI `NSViewRepresentable` (which does not
/// clip hosted AppKit views) a large image ballooned the editor window and
/// flooded across the note controls. This view reports NO intrinsic size and
/// draws the image itself, so the pane — never the image — decides the frame.
public final class LetterboxedImageView: NSView {

    public var image: NSImage? {
        didSet { needsDisplay = true }
    }

    public init(image: NSImage?) {
        self.image = image
        super.init(frame: .zero)
        // Never let the view push back against its container: no intrinsic
        // size, minimal hugging and compression resistance in both axes.
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    public override func draw(_ dirtyRect: NSRect) {
        // Neutral backdrop for the whole pane.
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let target = ImageFitGeometry.aspectFitRect(imageSize: image.size, in: bounds)
        guard !target.isEmpty else { return }

        // Subtle checkerboard inside the image rect, so transparency in PNGs
        // and PSDs reads as transparency instead of a flat fill.
        drawCheckerboard(in: target)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }

    /// 8pt two-tone checkerboard, restrained to `rect` via a clip. The tones
    /// are alpha-blended black/white, so the pattern stays subtle against both
    /// light and dark window backgrounds.
    private func drawCheckerboard(in rect: CGRect) {
        let square: CGFloat = 8
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()

        NSColor(white: 1, alpha: 0.05).setFill()
        rect.fill()
        NSColor(white: 0, alpha: 0.05).setFill()

        var row = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX + (row % 2 == 0 ? 0 : square)
            while x < rect.maxX {
                CGRect(x: x, y: y, width: min(square, rect.maxX - x),
                       height: min(square, rect.maxY - y)).fill()
                x += square * 2
            }
            y += square
            row += 1
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
