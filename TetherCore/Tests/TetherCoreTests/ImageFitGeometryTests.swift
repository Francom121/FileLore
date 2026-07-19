import XCTest
@testable import TetherCore

final class ImageFitGeometryTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    /// A tall portrait image in a wide pane fits to height and letterboxes
    /// left/right (mockup2.png is 941×1672 — the shape that broke the editor).
    func testPortraitImageFitsHeightAndCentersHorizontally() {
        let rect = ImageFitGeometry.aspectFitRect(
            imageSize: CGSize(width: 941, height: 1672), in: bounds)
        XCTAssertEqual(rect.height, 300, accuracy: 0.5)
        XCTAssertEqual(rect.width, 941.0 / 1672.0 * 300, accuracy: 0.5)
        XCTAssertEqual(rect.midX, bounds.midX, accuracy: 0.5)
        XCTAssertEqual(rect.midY, bounds.midY, accuracy: 0.5)
        XCTAssertTrue(bounds.contains(rect))
    }

    /// A wide landscape image fits to width and letterboxes top/bottom.
    func testLandscapeImageFitsWidthAndCentersVertically() {
        let rect = ImageFitGeometry.aspectFitRect(
            imageSize: CGSize(width: 3840, height: 1600), in: bounds)
        XCTAssertEqual(rect.width, 400, accuracy: 0.5)
        XCTAssertEqual(rect.height, 1600.0 / 3840.0 * 400, accuracy: 0.5)
        XCTAssertEqual(rect.midX, bounds.midX, accuracy: 0.5)
        XCTAssertEqual(rect.midY, bounds.midY, accuracy: 0.5)
        XCTAssertTrue(bounds.contains(rect))
    }

    /// A square image in a rectangular pane fits the short axis.
    func testSquareImageFitsShortAxis() {
        let rect = ImageFitGeometry.aspectFitRect(
            imageSize: CGSize(width: 1200, height: 1200), in: bounds)
        XCTAssertEqual(rect.width, 300, accuracy: 0.5)
        XCTAssertEqual(rect.height, 300, accuracy: 0.5)
    }

    /// Small images must NOT be upscaled: they render at natural size,
    /// centered — never blown up to fill the pane.
    func testSmallImageStaysAtNaturalSize() {
        let rect = ImageFitGeometry.aspectFitRect(
            imageSize: CGSize(width: 120, height: 80), in: bounds)
        XCTAssertEqual(rect.size, CGSize(width: 120, height: 80))
        XCTAssertEqual(rect.midX, bounds.midX, accuracy: 0.5)
        XCTAssertEqual(rect.midY, bounds.midY, accuracy: 0.5)
    }

    /// Opt-in upscaling (not used by the media pane) does fill the pane.
    func testAllowUpscaleFillsPane() {
        let rect = ImageFitGeometry.aspectFitRect(
            imageSize: CGSize(width: 120, height: 80), in: bounds, allowUpscale: true)
        // Width-limited: scale = 400/120, so 400 × 80·(400/120) ≈ 400 × 267.
        XCTAssertEqual(rect.width, 400, accuracy: 0.5)
        XCTAssertEqual(rect.height, 80.0 * 400.0 / 120.0, accuracy: 0.5)
    }

    /// An image exactly matching the pane fills it edge to edge.
    func testExactFitFillsBounds() {
        let rect = ImageFitGeometry.aspectFitRect(
            imageSize: CGSize(width: 400, height: 300), in: bounds)
        XCTAssertEqual(rect, bounds)
    }

    /// Non-zero pane offsets are respected (the rect stays inside bounds).
    func testOffsetBoundsAreRespected() {
        let offset = CGRect(x: 50, y: 25, width: 400, height: 300)
        let rect = ImageFitGeometry.aspectFitRect(
            imageSize: CGSize(width: 941, height: 1672), in: offset)
        XCTAssertEqual(rect.midX, offset.midX, accuracy: 0.5)
        XCTAssertEqual(rect.midY, offset.midY, accuracy: 0.5)
        XCTAssertTrue(offset.contains(rect))
    }

    /// Degenerate inputs produce `.zero` (draw nothing) instead of NaN frames.
    func testDegenerateInputsReturnZero() {
        XCTAssertEqual(
            ImageFitGeometry.aspectFitRect(imageSize: .zero, in: bounds), .zero)
        XCTAssertEqual(
            ImageFitGeometry.aspectFitRect(imageSize: CGSize(width: 100, height: 0), in: bounds), .zero)
        XCTAssertEqual(
            ImageFitGeometry.aspectFitRect(imageSize: CGSize(width: 100, height: 100), in: .zero), .zero)
    }
}
