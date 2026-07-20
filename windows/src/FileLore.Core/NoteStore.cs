using System.Runtime.InteropServices;
using System.Text;
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

    // ---- location support -------------------------------------------------------

    /// <summary>
    /// Second half of every unsupported-location message: what the user can
    /// do about it. Kept as one shared constant so the editor banner, the
    /// save-path exception and future callers all give identical guidance.
    /// Deliberately never mentions the raw <c>:filelore.note</c> stream path.
    /// </summary>
    public const string LocalDriveGuidance =
        "Notes work on files on this PC's own drives (NTFS) — move or copy the file " +
        @"to a local folder (e.g. C:\FileLoreTest or Documents on a normal Windows PC) and note it there.";

    private const string NetworkReason =
        "This file is on a network or shared folder, where FileLore notes can't be stored.";

    /// <summary>
    /// Whether a note can be stored on <paramref name="path"/>. Notes live in
    /// NTFS alternate data streams, which exist only on local NTFS volumes —
    /// on network shares (UNC paths, mapped network drives) and non-NTFS
    /// volumes (FAT32/exFAT) Windows rejects the ADS path with a raw
    /// "filename syntax is incorrect" error naming
    /// <c>&lt;path&gt;:filelore.note</c>. Callers check this first so they can
    /// show <paramref name="reason"/> (a friendly sentence, safe to display)
    /// instead. Reason is empty when supported.
    /// </summary>
    public static (bool Ok, string Reason) IsSupportedPath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
            return (false, "This location can't store FileLore notes (no valid path).");

        if (IsNetworkPath(path))
            return (false, NetworkReason);

        // Non-NTFS local volume (FAT32/exFAT USB sticks etc.): same ADS
        // limitation. If the filesystem can't be determined we stay
        // permissive — local fixed drives are NTFS on any normal Windows PC.
        string? root = null;
        try { root = Path.GetPathRoot(Path.GetFullPath(path)); } catch { /* fall through */ }
        var fsName = new StringBuilder(261);
        if (root is not null
            && GetVolumeInformationW(root, null, 0, out _, out _, out _, fsName, fsName.Capacity)
            && !string.Equals(fsName.ToString(), "NTFS", StringComparison.OrdinalIgnoreCase))
        {
            return (false,
                $"This file is on a {fsName} volume, which can't store FileLore notes " +
                "(notes need NTFS alternate data streams).");
        }

        return (true, "");
    }

    /// <summary>
    /// True when <paramref name="path"/> lives on a network/share location:
    /// a UNC path (<c>\\server\share\…</c>, including Parallels Shared
    /// Folders like <c>\\Mac\Home\…</c>) or a mapped network drive
    /// (<c>GetDriveType</c> → <c>DRIVE_REMOTE</c>).
    /// </summary>
    public static bool IsNetworkPath(string path)
    {
        string? root;
        try { root = Path.GetPathRoot(Path.GetFullPath(path)); }
        catch { return false; } // not a rooted path → let the NTFS check decide
        if (root is null) return false;
        if (root.StartsWith(@"\\", StringComparison.Ordinal)) return true; // UNC
        return GetDriveTypeW(root) == DriveRemote;
    }

    private const uint DriveRemote = 4;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern uint GetDriveTypeW(string lpRootPathName);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetVolumeInformationW(
        string lpRootPathName,
        StringBuilder? lpVolumeNameBuffer, int nVolumeNameSize,
        out uint lpVolumeSerialNumber, out uint lpMaximumComponentLength, out uint lpFileSystemFlags,
        StringBuilder lpFileSystemNameBuffer, int nFileSystemNameSize);

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
