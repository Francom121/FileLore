import XCTest
@testable import TetherCore

final class NoteStoreTests: XCTestCase {

    private var tempDir: URL!
    private var testFile: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TetherCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        testFile = tempDir.appendingPathComponent("sample.txt")
        try "hello".write(to: testFile, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeNote(body: String = "Remember this", tags: [String] = ["demo"]) -> Note {
        Note(
            body: body,
            tags: tags,
            links: [],
            created: Date(timeIntervalSince1970: 1_700_000_000),
            modified: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testReadWhenNoNoteReturnsNil() throws {
        XCTAssertNil(try NoteStore.read(url: testFile))
        XCTAssertFalse(NoteStore.hasNote(url: testFile))
    }

    func testWriteReadRoundTrip() throws {
        let note = makeNote()
        try NoteStore.write(note, to: testFile)

        XCTAssertTrue(NoteStore.hasNote(url: testFile))
        let readBack = try XCTUnwrap(try NoteStore.read(url: testFile))
        XCTAssertEqual(readBack.body, note.body)
        XCTAssertEqual(readBack.tags, note.tags)
        XCTAssertEqual(readBack.created.timeIntervalSince1970, note.created.timeIntervalSince1970, accuracy: 0.001)
        // `modified` is refreshed on write.
        XCTAssertGreaterThanOrEqual(readBack.modified, note.modified)
    }

    func testEditOverwritesExistingNote() throws {
        try NoteStore.write(makeNote(body: "v1", tags: ["a"]), to: testFile)
        try NoteStore.write(makeNote(body: "v2", tags: ["b", "c"]), to: testFile)

        let readBack = try XCTUnwrap(try NoteStore.read(url: testFile))
        XCTAssertEqual(readBack.body, "v2")
        XCTAssertEqual(readBack.tags, ["b", "c"])
    }

    func testUnicodeAndEmojiBody() throws {
        let body = "生成プロンプト 🎬✨ — café “quotes” 中文测试 \u{1F680} ñoño"
        try NoteStore.write(makeNote(body: body), to: testFile)
        let readBack = try XCTUnwrap(try NoteStore.read(url: testFile))
        XCTAssertEqual(readBack.body, body)
    }

    func testMultiKilobyteBody() throws {
        let paragraph = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 1500)
        XCTAssertGreaterThan(paragraph.utf8.count, 60_000)
        try NoteStore.write(makeNote(body: paragraph), to: testFile)
        let readBack = try XCTUnwrap(try NoteStore.read(url: testFile))
        XCTAssertEqual(readBack.body, paragraph)
    }

    func testDeleteRemovesNote() throws {
        try NoteStore.write(makeNote(), to: testFile)
        XCTAssertTrue(NoteStore.hasNote(url: testFile))

        try NoteStore.delete(url: testFile)
        XCTAssertNil(try NoteStore.read(url: testFile))
        XCTAssertFalse(NoteStore.hasNote(url: testFile))

        // Deleting again must not throw (ENOENT/ENOATTR tolerated).
        XCTAssertNoThrow(try NoteStore.delete(url: testFile))
    }

    func testNoteSurvivesRenameOnSameVolume() throws {
        try NoteStore.write(makeNote(body: "tethered"), to: testFile)
        let renamed = tempDir.appendingPathComponent("renamed-file.txt")
        try FileManager.default.moveItem(at: testFile, to: renamed)

        let readBack = try XCTUnwrap(try NoteStore.read(url: renamed))
        XCTAssertEqual(readBack.body, "tethered")
    }

    func testUnsupportedVersionThrows() throws {
        let future = #"{"version": 99, "note": {"body":"x","tags":[],"links":[],"created":0,"modified":0}}"#
        let path = testFile.path(percentEncoded: false)
        let result = path.withCString { cPath in
            future.withCString { cValue in
                setxattr(cPath, NoteStore.xattrName, cValue, strlen(cValue), 0, XATTR_NOFOLLOW)
            }
        }
        XCTAssertEqual(result, 0)
        XCTAssertThrowsError(try NoteStore.read(url: testFile)) { error in
            XCTAssertEqual(error as? NoteStoreError, .unsupportedVersion(99))
        }
    }
}
