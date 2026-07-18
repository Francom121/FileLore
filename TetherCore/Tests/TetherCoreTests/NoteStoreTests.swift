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

    // MARK: - Rename migration (com.tether.note → com.filelore.note)

    /// Writes raw bytes to the legacy Tether-era attribute, bypassing NoteStore.
    private func writeLegacyXattr(_ string: String) throws {
        let path = testFile.path(percentEncoded: false)
        let result = path.withCString { cPath in
            string.withCString { cValue in
                setxattr(cPath, NoteStore.legacyXattrName, cValue, strlen(cValue), 0, XATTR_NOFOLLOW)
            }
        }
        XCTAssertEqual(result, 0)
    }

    /// True when the given xattr exists on the test file.
    private func hasXattr(_ name: String) -> Bool {
        let path = testFile.path(percentEncoded: false)
        return path.withCString { cPath in
            name.withCString { cName in
                getxattr(cPath, cName, nil, 0, 0, XATTR_NOFOLLOW) >= 0
            }
        }
    }

    private func legacyEnvelopeJSON(body: String) -> String {
        """
        {"version": 1, "note": {"body": "\(body)", "tags": ["legacy"], "links": [], "created": 1700000000, "modified": 1700000000}}
        """
    }

    func testReadFallsBackToLegacyTetherAttribute() throws {
        // A Tether-era file: only the legacy attribute is present.
        try writeLegacyXattr(legacyEnvelopeJSON(body: "from the tether era"))
        XCTAssertFalse(hasXattr(NoteStore.xattrName))

        let note = try XCTUnwrap(try NoteStore.read(url: testFile))
        XCTAssertEqual(note.body, "from the tether era")
        XCTAssertEqual(note.tags, ["legacy"])
        XCTAssertTrue(NoteStore.hasNote(url: testFile))
    }

    func testSaveMigratesLegacyAttributeToCurrentName() throws {
        try writeLegacyXattr(legacyEnvelopeJSON(body: "legacy body"))

        var note = try XCTUnwrap(try NoteStore.read(url: testFile))
        note.body = "updated"
        try NoteStore.write(note, to: testFile)

        // The current attribute holds the note; the legacy one is gone.
        XCTAssertTrue(hasXattr(NoteStore.xattrName))
        XCTAssertFalse(hasXattr(NoteStore.legacyXattrName))
        let readBack = try XCTUnwrap(try NoteStore.read(url: testFile))
        XCTAssertEqual(readBack.body, "updated")
    }

    func testCurrentAttributeWinsOverLegacy() throws {
        // Both present (a file saved by FileLore before the legacy attr was
        // cleaned): the current name is authoritative.
        try NoteStore.write(makeNote(body: "current"), to: testFile)
        try writeLegacyXattr(legacyEnvelopeJSON(body: "stale legacy"))

        let note = try XCTUnwrap(try NoteStore.read(url: testFile))
        XCTAssertEqual(note.body, "current")
    }

    func testDeleteRemovesBothCurrentAndLegacyAttributes() throws {
        try writeLegacyXattr(legacyEnvelopeJSON(body: "legacy"))
        try NoteStore.write(makeNote(body: "current"), to: testFile)
        // Re-add the legacy attr to simulate a partially migrated file.
        try writeLegacyXattr(legacyEnvelopeJSON(body: "legacy"))

        try NoteStore.delete(url: testFile)
        XCTAssertFalse(hasXattr(NoteStore.xattrName))
        XCTAssertFalse(hasXattr(NoteStore.legacyXattrName))
        XCTAssertFalse(NoteStore.hasNote(url: testFile))
    }
}
