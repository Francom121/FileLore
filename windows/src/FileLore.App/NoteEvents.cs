namespace FileLore.App;

/// <summary>
/// In-process broadcast fired whenever a note is written or deleted, so
/// long-lived windows can update live instead of waiting for a manual
/// re-index — the search window updates its result list and tag chips the
/// moment an editor or batch run saves.
///
/// The payload is the noted file's path; receivers re-read the note
/// themselves (a missing note means it was deleted). Handlers may be
/// invoked on any thread — subscribers marshal to their Dispatcher.
/// </summary>
internal static class NoteEvents
{
    public static event Action<string>? NoteChanged;

    public static void RaiseChanged(string path)
    {
        try { NoteChanged?.Invoke(path); }
        catch { /* a listener's failure must never break the save that fired it */ }
    }
}
