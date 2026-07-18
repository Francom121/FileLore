import XCTest
@testable import TetherCore

final class MediaPreviewKindTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TetherCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Creates a temp file with the given name; content is irrelevant — type
    /// detection keys off the real content type (extension-derived) first.
    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data([0x00]).write(to: url)
        return url
    }

    private func kind(_ name: String) throws -> MediaPreviewKind {
        MediaPreview.kind(for: try makeFile(name))
    }

    func testVideoAndAudioAreAV() throws {
        for name in ["clip.mp4", "clip.mov", "clip.m4v", "song.mp3", "song.m4a", "song.wav"] {
            XCTAssertEqual(try kind(name), .av, name)
        }
    }

    func testUppercaseExtensionIsDetectedCaseInsensitively() throws {
        XCTAssertEqual(try kind("CLIP.MP4"), .av)
        XCTAssertEqual(try kind("PHOTO.PNG"), .image)
        XCTAssertEqual(try kind("DOC.PDF"), .pdf)
        XCTAssertEqual(try kind("NOTES.TXT"), .text)
    }

    func testImagesAreImage() throws {
        for name in ["photo.png", "photo.jpg", "photo.heic", "photo.tiff"] {
            XCTAssertEqual(try kind(name), .image, name)
        }
    }

    /// PSD must route to the image path even when its UTI is unhelpful —
    /// the extension fallback set covers it.
    func testPhotoshopFilesAreImage() throws {
        XCTAssertEqual(try kind("design.psd"), .image)
        XCTAssertEqual(try kind("design.psb"), .image)
    }

    func testPDFIsPDF() throws {
        XCTAssertEqual(try kind("paper.pdf"), .pdf)
    }

    func testPlainTextAndFriendsAreText() throws {
        for name in ["notes.txt", "notes.md", "data.csv", "config.json", "main.swift", "app.log"] {
            XCTAssertEqual(try kind(name), .text, name)
        }
    }

    func testUnknownAndBinaryTypesAreOther() throws {
        XCTAssertEqual(try kind("archive.zip"), .other)
        XCTAssertEqual(try kind("mystery.zzzqqq"), .other)
        XCTAssertEqual(try kind("noextension"), .other)
    }

    /// Detection must also work for files that don't exist on disk (falls
    /// back to extension-only typing).
    func testNonexistentFileFallsBackToExtension() {
        let url = tempDir.appendingPathComponent("ghost.mp4")
        XCTAssertEqual(MediaPreview.kind(for: url), .av)
    }
}
