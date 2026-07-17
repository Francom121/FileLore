import XCTest
@testable import TetherCore

final class MarkdownExporterTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TetherCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private let created = Date(timeIntervalSince1970: 1_700_000_000) // Nov 14, 2023

    func testFullDocumentShape() throws {
        let linked = tempDir.appendingPathComponent("reference.png")
        try "img".write(to: linked, atomically: true, encoding: .utf8)
        let link = try BookmarkResolver.makeLinkedFile(for: linked, relativeTo: tempDir)

        let note = Note(
            body: "cinematic drone shot, golden hour\nanamorphic lens",
            tags: ["drone", "client-x"],
            links: [link],
            created: created
        )

        let markdown = MarkdownExporter.markdown(for: note, fileName: "clip-final.mp4")

        // The bookmark may resolve through the /var → /private/var symlink, so
        // build the expected path from the same resolution the exporter used.
        let resolvedPath = try XCTUnwrap(BookmarkResolver.resolve(link.bookmark).url)
            .path(percentEncoded: false)
        let expected = """
        # clip-final.mp4

        cinematic drone shot, golden hour
        anamorphic lens

        **Tags:** #drone #client-x

        **Linked files:**
        - reference.png — \(resolvedPath)

        *Noted Nov 14, 2023*

        """
        XCTAssertEqual(markdown, expected)
    }

    func testBrokenLinkRendersBrokenMarker() {
        // Random bytes can never resolve as a bookmark.
        let link = LinkedFile(
            bookmark: Data([0x00, 0x01, 0x02]),
            displayName: "gone.png",
            relativePathHint: "gone.png"
        )
        let note = Note(body: "body", links: [link], created: created)

        let markdown = MarkdownExporter.markdown(for: note, fileName: "clip.mp4")

        XCTAssertTrue(markdown.contains("**Linked files:**\n- gone.png (broken link)"))
        XCTAssertFalse(markdown.contains("gone.png —"))
    }

    func testNoTagsNoLinksOmitsThoseSections() {
        let note = Note(body: "just a body", created: created)

        let markdown = MarkdownExporter.markdown(for: note, fileName: "plain.txt")

        XCTAssertEqual(markdown, "# plain.txt\n\njust a body\n\n*Noted Nov 14, 2023*\n")
        XCTAssertFalse(markdown.contains("**Tags:**"))
        XCTAssertFalse(markdown.contains("**Linked files:**"))
    }

    func testEmptyBodyStillExportsHeaderAndDate() {
        let note = Note(body: "", tags: ["only-tag"], created: created)

        let markdown = MarkdownExporter.markdown(for: note, fileName: "empty.md.txt")

        XCTAssertEqual(markdown, "# empty.md.txt\n\n**Tags:** #only-tag\n\n*Noted Nov 14, 2023*\n")
    }

    func testPromptSectionReturnsBody() {
        let note = Note(body: "the prompt", tags: ["x"], created: created)
        XCTAssertEqual(MarkdownExporter.promptSection(of: note), "the prompt")
    }
}
