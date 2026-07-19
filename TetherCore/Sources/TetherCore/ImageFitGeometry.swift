import Foundation

/// Pure geometry for aspect-fit ("letterbox") image layout, shared by the
/// media panes and unit-tested directly.
///
/// Policy (Quick Look behavior):
/// - the image keeps its aspect ratio;
/// - it is scaled DOWN to fit when larger than the container;
/// - it is NEVER upscaled beyond its natural size (small images render 1:1,
///   centered) unless `allowUpscale` is requested;
/// - the result is centered inside the container, leaving neutral letterbox
///   margins on the short axis.
public enum ImageFitGeometry {

    /// The centered rect the image should occupy inside `bounds`.
    /// Returns `.zero` when either the image or the bounds are empty, so the
    /// caller draws nothing instead of a degenerate frame.
    public static func aspectFitRect(
        imageSize: CGSize,
        in bounds: CGRect,
        allowUpscale: Bool = false
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return .zero }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let applied = allowUpscale ? scale : min(scale, 1)
        let size = CGSize(
            width: (imageSize.width * applied).rounded(),
            height: (imageSize.height * applied).rounded()
        )
        return CGRect(
            x: bounds.minX + (bounds.width - size.width) / 2,
            y: bounds.minY + (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
