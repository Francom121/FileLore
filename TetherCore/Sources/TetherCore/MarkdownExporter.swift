import Foundation

/// Renders a note (plus the name of the file it is attached to) as a Markdown
/// document — for pasting a prompt/process into show notes or a script doc.
public enum MarkdownExporter {

    /// Full document:
    ///
    ///     # <fileName>
    ///
    ///     <body verbatim>
    ///
    ///     **Tags:** #a #b
    ///
    ///     **Linked files:**
    ///     - name — /resolved/path
    ///     - other (broken link)
    ///
    ///     *Noted Jan 15, 2025*
    ///
    /// The Tags / Linked files sections are omitted when empty. Linked files
    /// show the resolved path when the security-scoped bookmark still
    /// resolves, and "(broken link)" when it doesn't.
    public static func markdown(for note: Note, fileName: String) -> String {
        var sections: [String] = ["# \(fileName)"]

        if !note.body.isEmpty {
            sections.append(note.body) // verbatim
        }

        if let tags = tagLine(for: note) {
            sections.append(tags)
        }

        if let links = linkBlock(for: note) {
            sections.append(links)
        }

        sections.append("*Noted \(Self.dateFormatter.string(from: note.created))*")
        return sections.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Batch export (many notes → one document)

    /// One entry in a batch export: the note plus the identity of the file it
    /// is attached to (the file itself is never read — the xattr already was).
    public struct ExportItem: Equatable, Sendable {
        public var note: Note
        /// Display name, e.g. "tagpanda promo1.mp4".
        public var fileName: String
        /// Full POSIX path of the noted file.
        public var filePath: String

        public init(note: Note, fileName: String, filePath: String) {
            self.note = note
            self.fileName = fileName
            self.filePath = filePath
        }
    }

    /// The `yyyy-MM-dd` stamp used in the export header and default file name
    /// (local calendar date, deterministic format).
    public static func exportDateString(from date: Date = Date()) -> String {
        Self.exportDateFormatter.string(from: date)
    }

    /// Many notes as ONE Markdown document:
    ///
    ///     # FileLore Export — 2026-07-18
    ///
    ///     ## #tag                     (only when the selection spans 2+ tags)
    ///
    ///     ### clip.mp4                (## when flat)
    ///     **File:** /full/path/clip.mp4
    ///     **Tags:** #a #b
    ///
    ///     <body verbatim>
    ///
    ///     **Linked files:**
    ///     - reference.png — /resolved/path
    ///
    ///     *Noted Nov 14, 2023*
    ///
    ///     ---
    ///
    /// Grouping: when the selection spans two or more distinct tags, entries
    /// are grouped under `## #tag` headers (each entry filed under its first
    /// tag, tagless entries last under `## Untagged`) and rendered one heading
    /// level deeper. Otherwise the document is a flat list ordered by file
    /// name. Tags / Linked files sections are omitted when empty, exactly like
    /// the single-note export.
    public static func batchMarkdown(for items: [ExportItem], date: Date = Date()) -> String {
        var parts: [String] = ["# FileLore Export — \(Self.exportDateFormatter.string(from: date))"]

        let tags = distinctTags(in: items)
        if tags.count >= 2 {
            // Group by each note's first tag (canonicalized to the sorted,
            // case-deduped tag list); notes without tags go last.
            var byTag: [String: [ExportItem]] = [:]
            var untagged: [ExportItem] = []
            for item in items {
                if let primary = item.note.tags.first,
                   let canonical = tags.first(where: { $0.caseInsensitiveCompare(primary) == .orderedSame }) {
                    byTag[canonical, default: []].append(item)
                } else {
                    untagged.append(item)
                }
            }
            for tag in tags {
                guard let group = byTag[tag], !group.isEmpty else { continue }
                parts.append("## #\(tag)")
                parts.append(group.sorted(by: fileNameAscending).map { entry($0, headingLevel: 3) }.joined(separator: "\n\n"))
            }
            if !untagged.isEmpty {
                parts.append("## Untagged")
                parts.append(untagged.sorted(by: fileNameAscending).map { entry($0, headingLevel: 3) }.joined(separator: "\n\n"))
            }
        } else {
            parts.append(items.sorted(by: fileNameAscending).map { entry($0, headingLevel: 2) }.joined(separator: "\n\n"))
        }

        return parts.joined(separator: "\n\n") + "\n"
    }

    // MARK: - Shared rendering helpers

    /// "**Tags:** #a #b", or nil when the note has no tags.
    private static func tagLine(for note: Note) -> String? {
        guard !note.tags.isEmpty else { return nil }
        return "**Tags:** " + note.tags.map { "#\($0)" }.joined(separator: " ")
    }

    /// The "**Linked files:**" block, or nil when the note has no links.
    /// Resolved bookmark → display name + path; unresolvable → "(broken link)".
    private static func linkBlock(for note: Note) -> String? {
        guard !note.links.isEmpty else { return nil }
        let lines = note.links.map { link -> String in
            if let resolved = BookmarkResolver.resolve(link.bookmark).url {
                return "- \(link.displayName) — \(resolved.path(percentEncoded: false))"
            }
            return "- \(link.displayName) (broken link)"
        }
        return (["**Linked files:**"] + lines).joined(separator: "\n")
    }

    /// One batch entry: heading + File/Tags metadata lines, then the same
    /// body / links / noted-date sections as the single-note export, closed
    /// by a horizontal rule.
    private static func entry(_ item: ExportItem, headingLevel: Int) -> String {
        let hashes = String(repeating: "#", count: headingLevel)
        var head = "\(hashes) \(item.fileName)\n**File:** \(item.filePath)"
        if let tags = tagLine(for: item.note) {
            head += "\n" + tags
        }

        var sections: [String] = [head]
        if !item.note.body.isEmpty {
            sections.append(item.note.body) // verbatim
        }
        if let links = linkBlock(for: item.note) {
            sections.append(links)
        }
        sections.append("*Noted \(Self.dateFormatter.string(from: item.note.created))*")
        return sections.joined(separator: "\n\n") + "\n\n---"
    }

    /// Every tag across `items`, case-insensitively deduped (first spelling
    /// wins) and sorted case-insensitively.
    private static func distinctTags(in items: [ExportItem]) -> [String] {
        var seen = Set<String>()
        return items
            .flatMap { $0.note.tags }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func fileNameAscending(_ lhs: ExportItem, _ rhs: ExportItem) -> Bool {
        lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
    }

    /// Just the note body — the "copy the prompt into another tool" helper.
    public static func promptSection(of note: Note) -> String {
        note.body
    }

    /// Deterministic (locale-independent) date rendering, e.g. "Jan 15, 2025".
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    /// Export-stamp rendering, e.g. "2026-07-18" (header + default file name).
    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
