using FileLore.Core;

namespace FileLore.App;

/// <summary>
/// The single save path used by the editor's Save button and by the headless
/// self-test hook, so both exercise identical semantics: create-or-update,
/// preserving <see cref="Note.Created"/> and <see cref="Note.Links"/>,
/// refreshing <see cref="Note.Modified"/> (done by <see cref="NoteStore.Write"/>),
/// and recording the file in Recents.
/// </summary>
public static class NoteEditorService
{
    public static Note Save(string path, string body, IEnumerable<string> tags)
    {
        // Unsupported locations (network shares, non-NTFS volumes) get a
        // friendly, raw-path-free message instead of the OS syntax error
        // that names the hidden "<path>:filelore.note" stream.
        if (NoteStore.IsSupportedPath(path) is (false, var reason))
            throw new InvalidOperationException(reason + " " + NoteStore.LocalDriveGuidance);

        Note? existing = null;
        try { existing = NoteStore.Read(path); }
        catch { /* unreadable envelope → start fresh, mirroring the Mac store's forgiving read */ }

        var note = existing ?? new Note { Created = DateTime.UtcNow };
        note.Body = body;
        note.Tags = tags
            .Select(t => t.Trim())
            .Where(t => t.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        NoteStore.Write(path, note);
        Recents.Add(path);
        return note;
    }
}
