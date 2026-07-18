import XCTest
@testable import TetherCore

final class BookmarkResolverTests: XCTestCase {

    private var tempDir: URL!
    private var linkedFile: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TetherCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        linkedFile = tempDir.appendingPathComponent("reference photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: linkedFile)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCreateAndResolve() throws {
        let bookmark = try BookmarkResolver.createBookmark(for: linkedFile)
        XCTAssertFalse(bookmark.isEmpty)

        let resolution = BookmarkResolver.resolve(bookmark)
        XCTAssertFalse(resolution.isBroken)
        XCTAssertEqual(resolution.url?.standardizedFileURL, linkedFile.standardizedFileURL)
    }

    func testResolveAfterRenameOnSameVolume() throws {
        let bookmark = try BookmarkResolver.createBookmark(for: linkedFile)

        // Rename the linked file — the bookmark must still resolve to it.
        let renamed = tempDir.appendingPathComponent("renamed reference.png")
        try FileManager.default.moveItem(at: linkedFile, to: renamed)

        let resolution = BookmarkResolver.resolve(bookmark)
        XCTAssertFalse(resolution.isBroken, "bookmark should follow a same-volume rename")
        XCTAssertEqual(resolution.url?.lastPathComponent, "renamed reference.png")
    }

    func testResolveAfterMoveToSiblingFolder() throws {
        let bookmark = try BookmarkResolver.createBookmark(for: linkedFile)

        let subdir = tempDir.appendingPathComponent("refs", isDirectory: true)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        let moved = subdir.appendingPathComponent(linkedFile.lastPathComponent)
        try FileManager.default.moveItem(at: linkedFile, to: moved)

        let resolution = BookmarkResolver.resolve(bookmark)
        XCTAssertFalse(resolution.isBroken)
        XCTAssertEqual(resolution.url?.standardizedFileURL, moved.standardizedFileURL)
    }

    func testGarbageDataIsBroken() {
        let resolution = BookmarkResolver.resolve(Data([0x00, 0x01, 0x02]))
        XCTAssertTrue(resolution.isBroken)
        XCTAssertNil(resolution.url)
    }

    func testDeletedFileIsBroken() throws {
        let bookmark = try BookmarkResolver.createBookmark(for: linkedFile)
        try FileManager.default.removeItem(at: linkedFile)

        let resolution = BookmarkResolver.resolve(bookmark)
        XCTAssertTrue(resolution.isBroken, "resolving a deleted file should report broken")
    }

    func testMakeLinkedFileCachesMetadata() throws {
        let lf = try BookmarkResolver.makeLinkedFile(for: linkedFile, relativeTo: tempDir)
        XCTAssertEqual(lf.displayName, "reference photo.png")
        XCTAssertEqual(lf.relativePathHint, "reference photo.png")
        XCTAssertFalse(lf.bookmark.isEmpty)
    }

    func testLocationDisplayShowsParentFolderWithTrailingSlash() throws {
        // tempDir's path already carries a trailing slash (directory URL).
        XCTAssertEqual(
            BookmarkResolver.locationDisplay(for: linkedFile),
            tempDir.path(percentEncoded: false)
        )
        XCTAssertTrue(BookmarkResolver.locationDisplay(for: linkedFile).hasSuffix("/"))
    }

    func testLocationDisplayHandlesSpacesAndRoot() throws {
        let spaced = URL(fileURLWithPath: "/Users/fm/Documents/TagPanda/Social Media/ads girl.png")
        XCTAssertEqual(
            BookmarkResolver.locationDisplay(for: spaced),
            "/Users/fm/Documents/TagPanda/Social Media/"
        )
        XCTAssertEqual(BookmarkResolver.locationDisplay(for: URL(fileURLWithPath: "/file.txt")), "/")
    }
}
