namespace FileLore.Core;

/// <summary>
/// In-memory matching over <see cref="IndexedNote"/> results: a free-text
/// query against note body + file name + tags (case-insensitive substring)
/// combined with a tag-chip filter (a note must carry ALL active tags).
/// </summary>
public static class NoteSearch
{
    public static bool Matches(IndexedNote item, string? query, IReadOnlyCollection<string>? activeTags)
    {
        if (activeTags is { Count: > 0 }
            && !activeTags.All(tag => item.Note.Tags.Any(
                t => string.Equals(t, tag, StringComparison.OrdinalIgnoreCase))))
        {
            return false;
        }

        if (string.IsNullOrWhiteSpace(query)) return true;
        string q = query.Trim();

        return item.Note.Body.Contains(q, StringComparison.OrdinalIgnoreCase)
            || item.FileName.Contains(q, StringComparison.OrdinalIgnoreCase)
            || item.Note.Tags.Any(t => t.Contains(q, StringComparison.OrdinalIgnoreCase));
    }
}
