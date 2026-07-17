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

        if !note.tags.isEmpty {
            sections.append("**Tags:** " + note.tags.map { "#\($0)" }.joined(separator: " "))
        }

        if !note.links.isEmpty {
            let lines = note.links.map { link -> String in
                if let resolved = BookmarkResolver.resolve(link.bookmark).url {
                    return "- \(link.displayName) — \(resolved.path(percentEncoded: false))"
                }
                return "- \(link.displayName) (broken link)"
            }
            sections.append((["**Linked files:**"] + lines).joined(separator: "\n"))
        }

        sections.append("*Noted \(Self.dateFormatter.string(from: note.created))*")
        return sections.joined(separator: "\n\n") + "\n"
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
}
