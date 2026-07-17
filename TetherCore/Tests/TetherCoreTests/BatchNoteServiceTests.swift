import XCTest
@testable import TetherCore

final class BatchNoteServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TetherCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try "content".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func note(body: String, tags: [String]) -> Note {
        Note(body: body, tags: tags, created: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testAppendModeAddsTagsAndBodyToExistingNote() throws {
        let file = try makeFile("a.txt")
        try NoteStore.write(note(body: "old body", tags: ["existing"]), to: file)

        let summary = BatchNoteService.apply(tags: ["new", "second"], body: "batch line", mode: .append, to: [file])

        XCTAssertEqual(summary.successCount, 1)
        let readBack = try XCTUnwrap(try NoteStore.read(url: file))
        XCTAssertEqual(readBack.tags, ["existing", "new", "second"])
        XCTAssertEqual(readBack.body, "old body\n\nbatch line")
    }

    func testReplaceModeOverwritesBodyKeepsAndMergesTags() throws {
        let file = try makeFile("a.txt")
        try NoteStore.write(note(body: "old body", tags: ["keep"]), to: file)

        BatchNoteService.apply(tags: ["added"], body: "replacement", mode: .replace, to: [file])

        let readBack = try XCTUnwrap(try NoteStore.read(url: file))
        XCTAssertEqual(readBack.body, "replacement")
        XCTAssertEqual(readBack.tags, ["keep", "added"])
    }

    func testOnlyIfEmptyModeWritesBodyOnlyWhenBlank() throws {
        let filled = try makeFile("filled.txt")
        let blank = try makeFile("blank.txt")
        try NoteStore.write(note(body: "already here", tags: []), to: filled)
        try NoteStore.write(note(body: "", tags: []), to: blank)

        BatchNoteService.apply(tags: [], body: "batch body", mode: .onlyIfEmpty, to: [filled, blank])

        XCTAssertEqual(try XCTUnwrap(try NoteStore.read(url: filled)).body, "already here")
        XCTAssertEqual(try XCTUnwrap(try NoteStore.read(url: blank)).body, "batch body")
    }

    func testFileWithNoPriorNoteGetsFreshNote() throws {
        let file = try makeFile("fresh.txt")
        XCTAssertFalse(NoteStore.hasNote(url: file))

        let summary = BatchNoteService.apply(tags: ["brand-new"], body: "first body", mode: .append, to: [file])

        XCTAssertEqual(summary.results, [BatchFileResult(fileURL: file, succeeded: true)])
        let readBack = try XCTUnwrap(try NoteStore.read(url: file))
        XCTAssertEqual(readBack.tags, ["brand-new"])
        XCTAssertEqual(readBack.body, "first body")
    }

    func testTagDedupeIsCaseInsensitiveAndPreservesExisting() throws {
        let file = try makeFile("a.txt")
        try NoteStore.write(note(body: "", tags: ["Portrait", "wip"]), to: file)

        BatchNoteService.apply(tags: ["portrait", "  PORTRAIT ", "", "Landscape"], body: nil, mode: .append, to: [file])

        let readBack = try XCTUnwrap(try NoteStore.read(url: file))
        // Existing casing/order preserved; only the genuinely new tag appended.
        XCTAssertEqual(readBack.tags, ["Portrait", "wip", "Landscape"])
    }

    func testNilBodyLeavesBodiesUntouchedInEveryMode() throws {
        for mode in BatchBodyMode.allCases {
            let file = try makeFile("\(mode.rawValue).txt")
            try NoteStore.write(note(body: "untouched", tags: []), to: file)
            BatchNoteService.apply(tags: ["t"], body: nil, mode: mode, to: [file])
            let readBack = try XCTUnwrap(try NoteStore.read(url: file))
            XCTAssertEqual(readBack.body, "untouched", "mode \(mode) must not touch the body")
            XCTAssertEqual(readBack.tags, ["t"])
        }
    }

    func testEmptyBodyInAppendModeIsNoOpButReplaceClears() throws {
        let appended = try makeFile("append.txt")
        let replaced = try makeFile("replace.txt")
        try NoteStore.write(note(body: "keep me", tags: []), to: appended)
        try NoteStore.write(note(body: "clear me", tags: []), to: replaced)

        BatchNoteService.apply(tags: [], body: "", mode: .append, to: [appended])
        BatchNoteService.apply(tags: [], body: "", mode: .replace, to: [replaced])

        XCTAssertEqual(try XCTUnwrap(try NoteStore.read(url: appended)).body, "keep me")
        XCTAssertEqual(try XCTUnwrap(try NoteStore.read(url: replaced)).body, "")
    }

    func testFailingFileDoesNotStopTheBatch() throws {
        let good = try makeFile("good.txt")
        let missing = tempDir.appendingPathComponent("does-not-exist.txt")

        let summary = BatchNoteService.apply(tags: ["x"], body: "y", mode: .append, to: [missing, good])

        XCTAssertEqual(summary.results.count, 2)
        XCTAssertEqual(summary.successCount, 1)
        XCTAssertEqual(summary.failureCount, 1)
        XCTAssertFalse(summary.results[0].succeeded)
        XCTAssertNotNil(summary.results[0].errorDescription)
        XCTAssertTrue(summary.results[1].succeeded)
        XCTAssertTrue(NoteStore.hasNote(url: good))
    }
}
