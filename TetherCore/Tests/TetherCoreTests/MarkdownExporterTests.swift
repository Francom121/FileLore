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

    // MARK: - Batch export

    private let exportDate = Date(timeIntervalSince1970: 1_784_500_000) // fixed stamp

    private func item(
        _ fileName: String,
        body: String? = nil,
        tags: [String] = [],
        links: [LinkedFile] = []
    ) -> MarkdownExporter.ExportItem {
        MarkdownExporter.ExportItem(
            note: Note(body: body ?? "body of \(fileName)", tags: tags, links: links, created: created),
            fileName: fileName,
            filePath: "/Users/fm/Documents/\(fileName)"
        )
    }

    func testBatchFlatWhenNoTagsSortsByFileName() {
        let markdown = MarkdownExporter.batchMarkdown(
            for: [item("zebra.mov"), item("alpha.txt")],
            date: exportDate
        )

        let stamp = MarkdownExporter.exportDateString(from: exportDate)
        XCTAssertTrue(markdown.hasPrefix("# FileLore Export — \(stamp)\n\n## alpha.txt\n"))
        // Flat entries use level-2 headings, carry the full path, end with ---.
        XCTAssertTrue(markdown.contains("## alpha.txt\n**File:** /Users/fm/Documents/alpha.txt\n\nbody of alpha.txt\n\n*Noted Nov 14, 2023*\n\n---"))
        XCTAssertTrue(markdown.contains("## zebra.mov\n**File:** /Users/fm/Documents/zebra.mov"))
        XCTAssertFalse(markdown.contains("**Tags:**"))
        XCTAssertTrue(markdown.hasSuffix("---\n"))
        // No tag-group headers in flat mode.
        XCTAssertFalse(markdown.contains("## #"))
    }

    func testBatchSingleSharedTagStaysFlat() {
        let markdown = MarkdownExporter.batchMarkdown(
            for: [item("b.mov", tags: ["promo"]), item("a.mov", tags: ["promo"])],
            date: exportDate
        )

        XCTAssertFalse(markdown.contains("## #promo"))
        XCTAssertTrue(markdown.contains("## a.mov\n**File:** /Users/fm/Documents/a.mov\n**Tags:** #promo"))
    }

    func testBatchGroupsByTagWhenSelectionSpansTags() {
        let markdown = MarkdownExporter.batchMarkdown(
            for: [
                item("b-roll.mp4", tags: ["drone"]),
                item("promo cut.mp4", tags: ["tagpanda", "promo"]),
                item("voiceover.wav", tags: []),
            ],
            date: exportDate
        )

        // Group headers: tags sorted case-insensitively, Untagged last.
        let droneIdx = markdown.range(of: "\n## #drone\n")!.lowerBound
        let tagpandaIdx = markdown.range(of: "\n## #tagpanda\n")!.lowerBound
        let untaggedIdx = markdown.range(of: "\n## Untagged\n")!.lowerBound
        XCTAssertTrue(droneIdx < tagpandaIdx)
        XCTAssertTrue(tagpandaIdx < untaggedIdx)

        // Grouped entries are one level deeper and keep full metadata.
        XCTAssertTrue(markdown.contains("### promo cut.mp4\n**File:** /Users/fm/Documents/promo cut.mp4\n**Tags:** #tagpanda #promo"))
        XCTAssertTrue(markdown.contains("### b-roll.mp4\n**File:** /Users/fm/Documents/b-roll.mp4\n**Tags:** #drone"))
        XCTAssertTrue(markdown.contains("### voiceover.wav\n**File:** /Users/fm/Documents/voiceover.wav\n\nbody of voiceover.wav"))

        // A multi-tag note appears exactly once (under its first tag).
        XCTAssertEqual(markdown.components(separatedBy: "### promo cut.mp4\n").count - 1, 1)
    }

    func testBatchGroupAssignmentIsCaseInsensitive() {
        let markdown = MarkdownExporter.batchMarkdown(
            for: [
                item("one.mov", tags: ["Promo"]),
                item("two.mov", tags: ["promo", "other"]),
            ],
            date: exportDate
        )

        // "Promo" and "promo" collapse into a single group; both notes are
        // filed under their first tag, so "other" (a second tag) renders no
        // group of its own.
        XCTAssertEqual(markdown.components(separatedBy: "## #").count - 1, 1)
        XCTAssertTrue(markdown.contains("## #Promo\n"))
        XCTAssertTrue(markdown.contains("### one.mov"))
        XCTAssertTrue(markdown.contains("### two.mov"))
    }

    func testBatchRendersLinksResolvedAndBroken() throws {
        let linked = tempDir.appendingPathComponent("reference.png")
        try "img".write(to: linked, atomically: true, encoding: .utf8)
        let good = try BookmarkResolver.makeLinkedFile(for: linked, relativeTo: tempDir)
        let broken = LinkedFile(bookmark: Data([0x00, 0x01, 0x02]), displayName: "gone.png", relativePathHint: "gone.png")

        let markdown = MarkdownExporter.batchMarkdown(
            for: [item("clip.mp4", links: [good, broken])],
            date: exportDate
        )

        let resolvedPath = try XCTUnwrap(BookmarkResolver.resolve(good.bookmark).url).path(percentEncoded: false)
        XCTAssertTrue(markdown.contains("**Linked files:**\n- reference.png — \(resolvedPath)\n- gone.png (broken link)"))
    }

    func testBatchEmptyBodyOmitsBodySection() {
        let markdown = MarkdownExporter.batchMarkdown(
            for: [item("empty.txt", body: "")],
            date: exportDate
        )

        XCTAssertTrue(markdown.contains("## empty.txt\n**File:** /Users/fm/Documents/empty.txt\n\n*Noted Nov 14, 2023*\n\n---"))
    }

    func testExportDateStringFormat() {
        // Format is fixed; only the local calendar date varies.
        let stamp = MarkdownExporter.exportDateString(from: exportDate)
        XCTAssertEqual(stamp.count, 10)
        XCTAssertEqual(stamp.dropFirst(4).prefix(1), "-")
        XCTAssertEqual(stamp.dropFirst(7).prefix(1), "-")
    }
}
