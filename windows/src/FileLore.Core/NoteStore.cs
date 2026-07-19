using System.Text.Json;

namespace FileLore.Core;

/// <summary>
/// Reads and writes <see cref="Note"/> values as a JSON-encoded NTFS
/// Alternate Data Stream on arbitrary files — the Windows counterpart of
/// the macOS xattr-based <c>NoteStore</c>.
///
/// The note lives <em>on the file itself</em> (stream
/// <c>&lt;path&gt;:filelore.note</c>), so it survives renames and moves on
/// the same NTFS volume without any separate database.
///
/// Intentional deviations from the Mac store:
///  - No legacy-stream fallback (the Mac store also reads the Tether-era
///    <c>com.tether.note</c> xattr; there are no Tether-era files on NTFS).
///  - JSON is pretty-printed in declaration order rather than
///    <c>.sortedKeys</c> order; key order is not semantically meaningful.
/// </summary>
public static class NoteStore
{
    /// <summary>Name of the alternate data stream that carries the note payload.</summary>
    public const string StreamName = "filelore.note";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true, // Mac uses .prettyPrinted
    };

    /// <summary>Full ADS path form, e.g. <c>C:\dir\file.mp4:filelore.note</c>.</summary>
    public static string StreamPath(string path) => path + ":" + StreamName;

    /// <summary>
    /// Writes (or overwrites) the note on <paramref name="path"/>, refreshing
    /// <see cref="Note.Modified"/> — same semantics as the Mac store.
    /// </summary>
    public static void Write(string path, Note note)
    {
        note.Modified = DateTime.UtcNow;
        string json = JsonSerializer.Serialize(new NoteEnvelope { Note = note }, JsonOptions);
        File.WriteAllText(StreamPath(path), json);
    }

    /// <summary>
    /// Returns the note attached to <paramref name="path"/>, or <c>null</c>
    /// when the file (or its note stream) does not exist.
    /// </summary>
    /// <exception cref="InvalidDataException">
    /// The stream holds an envelope with a newer <c>version</c> than this build understands.
    /// </exception>
    public static Note? Read(string path)
    {
        string json;
        try
        {
            json = File.ReadAllText(StreamPath(path));
        }
        catch (FileNotFoundException) { return null; }       // no such stream / no such file
        catch (DirectoryNotFoundException) { return null; }  // parent folder gone

        var envelope = JsonSerializer.Deserialize<NoteEnvelope>(json);
        if (envelope is null) return null;
        if (envelope.Version > NoteEnvelope.CurrentVersion)
            throw new InvalidDataException(
                $"Unsupported note envelope version {envelope.Version} on '{path}' " +
                $"(this build understands up to {NoteEnvelope.CurrentVersion}).");
        return envelope.Note;
    }

    /// <summary>Convenience non-throwing check, mirroring the Mac <c>hasNote</c>.</summary>
    public static bool HasNote(string path)
    {
        try { return Read(path) is not null; }
        catch { return false; } // malformed payload etc. → treated as "no readable note", like Mac's try?
    }

    /// <summary>
    /// Removes the note stream. Succeeds silently when no note is present
    /// (<see cref="File.Delete(string)"/> does not throw for missing files).
    /// </summary>
    public static void Delete(string path) => File.Delete(StreamPath(path));

    /// <summary>
    /// Raw payload bytes of the note stream, or <c>null</c> when absent.
    /// Exposed for diagnostics/proof output.
    /// </summary>
    public static byte[]? ReadRawBytes(string path)
    {
        try { return File.ReadAllBytes(StreamPath(path)); }
        catch (FileNotFoundException) { return null; }
        catch (DirectoryNotFoundException) { return null; }
    }
}
