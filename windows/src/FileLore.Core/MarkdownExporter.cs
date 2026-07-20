using System.Globalization;

namespace FileLore.Core;

/// <summary>
/// Renders notes as Markdown — the Windows mirror of
/// <c>MarkdownExporter</c> in TetherCore/Sources/TetherCore/MarkdownExporter.swift.
/// Section order, heading levels, grouping rules and date formats match the
/// Mac output so an export looks the same on both platforms.
///
/// Linked files are resolved through <see cref="LinkResolver"/> (path +
/// same-folder fallback); the Mac resolves security-scoped bookmarks. Both
/// render "name — /resolved/path" or "name (broken link)".
/// </summary>
public static class MarkdownExporter
{
    /// <summary>One entry in a batch export: the note plus the identity of its file.</summary>
    public sealed record ExportItem(Note Note, string FileName, string FilePath);

    /// <summary>The yyyy-MM-dd stamp used in the batch header and default file name.</summary>
    public static string ExportDateString(DateTime? date = null)
        => (date ?? DateTime.Now).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);

    /// <summary>
    /// Full document for one note:
    ///
    ///     # &lt;fileName&gt;
    ///     **File:** &lt;filePath&gt;
    ///     **Tags:** #a #b            (omitted when empty)
    ///
    ///     &lt;body verbatim&gt;           (omitted when empty)
    ///
    ///     **Linked files:**          (omitted when empty)
    ///     - name — C:\resolved\path
    ///     - other (broken link)
    ///
    ///     *Noted Jan 15, 2025*
    ///
    /// The **File:**/**Tags:** header block mirrors the Mac's batch-entry
    /// header shape, promoted to a level-1 heading.
    /// </summary>
    public static string Markdown(Note note, string fileName, string filePath)
    {
        string head = $"# {fileName}\n**File:** {filePath}";
        if (TagLine(note.Tags) is { } tags)
            head += "\n" + tags;

        var sections = new List<string> { head };
        if (!string.IsNullOrEmpty(note.Body))
            sections.Add(note.Body); // verbatim
        if (LinkBlock(note, filePath) is { } links)
            sections.Add(links);
        sections.Add($"*Noted {FormatNotedDate(note.Created)}*");
        return string.Join("\n\n", sections) + "\n";
    }

    /// <summary>
    /// Many notes as ONE Markdown document, mirroring the Mac batch export:
    ///
    ///     # FileLore Export — 2026-07-18
    ///
    ///     ## #tag                     (only when the selection spans 2+ tags)
    ///
    ///     ### clip.mp4                (## when flat)
    ///     **File:** C:\full\path\clip.mp4
    ///     **Tags:** #a #b
    ///
    ///     &lt;body verbatim&gt;
    ///
    ///     **Linked files:**
    ///     - reference.png — C:\resolved\path
    ///
    ///     *Noted Nov 14, 2023*
    ///
    ///     ---
    ///
    /// Grouping: with two or more distinct tags across the selection, entries
    /// are filed under `## #tag` headers by their FIRST tag (canonicalized to
    /// the sorted, case-deduped tag list); tagless entries go last under
    /// `## Untagged`; entries render one heading level deeper. Otherwise the
    /// document is a flat `## &lt;file&gt;` list ordered by file name. Every
    /// entry ends with a horizontal rule, exactly like the Mac.
    /// </summary>
    public static string BatchMarkdown(IReadOnlyList<ExportItem> items, DateTime? date = null)
    {
        var parts = new List<string> { $"# FileLore Export — {ExportDateString(date)}" };

        var tags = DistinctTags(items);
        if (tags.Count >= 2)
        {
            var byTag = new Dictionary<string, List<ExportItem>>(StringComparer.Ordinal);
            var untagged = new List<ExportItem>();
            foreach (var item in items)
            {
                string? primary = item.Note.Tags.FirstOrDefault();
                string? canonical = primary is null
                    ? null
                    : tags.FirstOrDefault(t => string.Equals(t, primary, StringComparison.OrdinalIgnoreCase));
                if (canonical is null) untagged.Add(item);
                else
                {
                    if (!byTag.TryGetValue(canonical, out var group)) byTag[canonical] = group = new();
                    group.Add(item);
                }
            }
            foreach (string tag in tags)
            {
                if (!byTag.TryGetValue(tag, out var group) || group.Count == 0) continue;
                parts.Add($"## #{tag}");
                parts.Add(string.Join("\n\n", group.OrderBy(i => i.FileName, StringComparer.OrdinalIgnoreCase)
                                                   .Select(i => Entry(i, headingLevel: 3))));
            }
            if (untagged.Count > 0)
            {
                parts.Add("## Untagged");
                parts.Add(string.Join("\n\n", untagged.OrderBy(i => i.FileName, StringComparer.OrdinalIgnoreCase)
                                                       .Select(i => Entry(i, headingLevel: 3))));
            }
        }
        else
        {
            parts.Add(string.Join("\n\n", items.OrderBy(i => i.FileName, StringComparer.OrdinalIgnoreCase)
                                               .Select(i => Entry(i, headingLevel: 2))));
        }

        return string.Join("\n\n", parts) + "\n";
    }

    // ---- shared rendering helpers ------------------------------------------------

    /// <summary>"**Tags:** #a #b", or null when the note has no tags.</summary>
    private static string? TagLine(IReadOnlyList<string> tags)
        => tags.Count == 0 ? null : "**Tags:** " + string.Join(" ", tags.Select(t => "#" + t));

    /// <summary>
    /// The "**Linked files:**" block, or null when the note has no links.
    /// Resolved → "name — path"; unresolvable → "name (broken link)".
    /// <paramref name="notedFilePath"/> anchors the same-folder fallback.
    /// </summary>
    private static string? LinkBlock(Note note, string notedFilePath)
    {
        if (note.Links.Count == 0) return null;
        var lines = note.Links.Select(link =>
            LinkResolver.Resolve(link, notedFilePath) is { } resolved
                ? $"- {link.DisplayName} — {resolved}"
                : $"- {link.DisplayName} (broken link)");
        return "**Linked files:**\n" + string.Join("\n", lines);
    }

    /// <summary>One batch entry: heading + File/Tags metadata lines, then the same
    /// body / links / noted-date sections as the single-note export, closed by a rule.</summary>
    private static string Entry(ExportItem item, int headingLevel)
    {
        string head = $"{new string('#', headingLevel)} {item.FileName}\n**File:** {item.FilePath}";
        if (TagLine(item.Note.Tags) is { } tags)
            head += "\n" + tags;

        var sections = new List<string> { head };
        if (!string.IsNullOrEmpty(item.Note.Body))
            sections.Add(item.Note.Body); // verbatim
        if (LinkBlock(item.Note, item.FilePath) is { } links)
            sections.Add(links);
        sections.Add($"*Noted {FormatNotedDate(item.Note.Created)}*");
        return string.Join("\n\n", sections) + "\n\n---";
    }

    /// <summary>Every tag across <paramref name="items"/>, case-insensitively deduped
    /// (first spelling wins) and sorted case-insensitively.</summary>
    private static List<string> DistinctTags(IReadOnlyList<ExportItem> items)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<string>();
        foreach (var tag in items.SelectMany(i => i.Note.Tags))
            if (seen.Add(tag)) result.Add(tag);
        result.Sort(StringComparer.OrdinalIgnoreCase);
        return result;
    }

    /// <summary>Deterministic "MMM d, yyyy" rendering (en_US month names), local time,
    /// matching the Mac formatter ("Jan 15, 2025").</summary>
    public static string FormatNotedDate(DateTime created)
        => created.ToLocalTime().ToString("MMM d, yyyy", CultureInfo.InvariantCulture);
}
