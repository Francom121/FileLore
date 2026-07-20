namespace FileLore.Core;

/// <summary>
/// Creates and resolves <see cref="LinkedFile"/> records on Windows.
///
/// macOS resolves links through security-scoped bookmarks; NTFS has no such
/// concept, so Windows resolves by path with a same-folder fallback:
///
///   1. <see cref="LinkedFile.Path"/> (absolute, written by Windows) exists → resolved.
///   2. A file named <see cref="LinkedFile.RelativePathHint"/> or
///      <see cref="LinkedFile.DisplayName"/> next to the NOTED file → resolved.
///      This covers the main real-world case: a reference photo that was
///      moved/renamed together with the noted file's folder.
///   3. Otherwise the link is broken (the UI offers Relink, which rebinds
///      <see cref="LinkedFile.Path"/> via a file picker).
/// </summary>
public static class LinkResolver
{
    /// <summary>
    /// Builds a link record for <paramref name="filePath"/>: fresh guid,
    /// empty bookmark placeholder (base64 "" in JSON — valid for the Mac
    /// app's <c>Data</c> decode), display name + relative hint set to the
    /// file name, absolute path, size and timestamp.
    /// </summary>
    public static LinkedFile CreateLink(string filePath)
    {
        string name = System.IO.Path.GetFileName(filePath);
        long size = 0;
        try { size = new FileInfo(filePath).Length; } catch { /* best effort */ }
        return new LinkedFile
        {
            Id = Guid.NewGuid(),
            Bookmark = Array.Empty<byte>(),
            DisplayName = name,
            RelativePathHint = name,
            Path = System.IO.Path.GetFullPath(filePath),
            Size = size,
            Added = DateTime.UtcNow,
        };
    }

    /// <summary>
    /// Resolves <paramref name="link"/> to an existing file path, or returns
    /// <c>null</c> when the link is broken. <paramref name="notedFilePath"/>
    /// is the file the note (and therefore the link) is attached to; its
    /// folder anchors the same-folder fallback.
    /// </summary>
    public static string? Resolve(LinkedFile link, string notedFilePath)
    {
        // 1) absolute path recorded at link time
        if (!string.IsNullOrWhiteSpace(link.Path)
            && System.IO.Path.IsPathRooted(link.Path)
            && File.Exists(link.Path))
        {
            return link.Path;
        }

        // 2) same-folder fallback: relativePathHint, then displayName, next to
        //    the noted file. Path.Combine returns the second argument when it
        //    is rooted, so a rooted hint also works as a plain path.
        string? notedDir = null;
        try { notedDir = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(notedFilePath)); }
        catch { /* malformed noted path → no fallback anchor */ }

        if (notedDir is not null)
        {
            foreach (string hint in new[] { link.RelativePathHint, link.DisplayName })
            {
                if (string.IsNullOrWhiteSpace(hint)) continue;
                string candidate;
                try { candidate = System.IO.Path.Combine(notedDir, hint); }
                catch { continue; }
                if (File.Exists(candidate)) return candidate;
            }
        }

        return null; // broken
    }

    /// <summary>
    /// Rebinds a (usually broken) link to <paramref name="newPath"/> — the
    /// Relink button's action. Keeps <see cref="LinkedFile.Id"/> stable so
    /// the Mac app sees the same link identity; refreshes name, hint, path,
    /// size and timestamp.
    /// </summary>
    public static void Relink(LinkedFile link, string newPath)
    {
        string name = System.IO.Path.GetFileName(newPath);
        link.DisplayName = name;
        link.RelativePathHint = name;
        link.Path = System.IO.Path.GetFullPath(newPath);
        try { link.Size = new FileInfo(newPath).Length; } catch { link.Size = 0; }
        link.Added = DateTime.UtcNow;
    }
}
