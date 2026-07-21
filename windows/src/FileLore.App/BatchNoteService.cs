using FileLore.Core;

namespace FileLore.App;

/// <summary>How the batch body text is applied to each file's note.</summary>
public enum BatchBodyMode { Set, Append }

/// <summary>How the batch tags are applied to each file's note.</summary>
public enum BatchTagMode { Add, Replace }

/// <summary>Outcome for one file in a batch run.</summary>
public sealed record BatchFileResult(string Path, bool Succeeded, bool Skipped, string? Reason);

/// <summary>
/// Applies the same note body and/or tags to many files at once — the
/// Windows counterpart of the Mac <c>BatchNoteService</c>. Each file is
/// processed independently: its note is read (or a blank one created), the
/// transforms are applied, and the note is written back. One file's failure
/// never stops the batch; unsupported locations (network shares, non-NTFS
/// volumes) are reported as skipped with the friendly reason.
///
/// Empty inputs are no-ops by design: an empty body leaves every body
/// untouched regardless of mode, and an empty tag list leaves every tag
/// list untouched — so "Set" can never wipe a field the user left blank.
/// </summary>
public static class BatchNoteService
{
    public static List<BatchFileResult> Apply(
        IReadOnlyList<string> paths,
        string? body,
        BatchBodyMode bodyMode,
        IReadOnlyList<string> tags,
        BatchTagMode tagMode,
        Action<BatchFileResult>? onFileDone = null)
    {
        var newTags = tags
            .Select(t => t.Trim().TrimStart('#'))
            .Where(t => t.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        bool touchBody = !string.IsNullOrEmpty(body);
        bool touchTags = newTags.Count > 0;

        var results = new List<BatchFileResult>();
        foreach (string path in paths)
        {
            BatchFileResult result;
            if (NoteStore.IsSupportedPath(path) is (false, var reason))
            {
                result = new BatchFileResult(path, Succeeded: false, Skipped: true, Reason: reason);
            }
            else
            {
                try
                {
                    Note? note = null;
                    try { note = NoteStore.Read(path); } catch { /* unreadable envelope → fresh note */ }
                    note ??= new Note { Created = DateTime.UtcNow };

                    if (touchBody)
                    {
                        note.Body = bodyMode == BatchBodyMode.Set
                            ? body!
                            : string.IsNullOrEmpty(note.Body) ? body! : note.Body + "\n\n" + body;
                    }
                    if (touchTags)
                    {
                        if (tagMode == BatchTagMode.Replace)
                        {
                            note.Tags = newTags.ToList();
                        }
                        else
                        {
                            foreach (string tag in newTags)
                                if (!note.Tags.Any(t => string.Equals(t, tag, StringComparison.OrdinalIgnoreCase)))
                                    note.Tags.Add(tag);
                        }
                    }

                    NoteStore.Write(path, note);
                    Recents.Add(path);
                    NoteEvents.RaiseChanged(path);
                    result = new BatchFileResult(path, Succeeded: true, Skipped: false, Reason: null);
                }
                catch (Exception ex)
                {
                    result = new BatchFileResult(path, Succeeded: false, Skipped: false, Reason: ex.Message);
                }
            }
            results.Add(result);
            onFileDone?.Invoke(result);
        }
        return results;
    }

    /// <summary>Summary line like "5 notes updated, 1 skipped (network path)".</summary>
    public static string Summarize(IReadOnlyList<BatchFileResult> results)
    {
        int ok = results.Count(r => r.Succeeded);
        int skipped = results.Count(r => r.Skipped);
        int failed = results.Count - ok - skipped;
        var parts = new List<string> { $"{ok} note{(ok == 1 ? "" : "s")} updated" };
        if (skipped > 0) parts.Add($"{skipped} skipped (network/unsupported path)");
        if (failed > 0) parts.Add($"{failed} failed");
        return string.Join(", ", parts);
    }
}
