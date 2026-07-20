using System.Runtime.InteropServices;

namespace FileLore.Core;

/// <summary>
/// A file discovered by <see cref="NoteIndex.Scan"/> together with the note
/// carried by its ADS stream. The lightweight search-model counterpart of
/// the Mac app's index.
/// </summary>
public sealed class IndexedNote
{
    public required string Path { get; init; }
    public required Note Note { get; init; }

    public string FileName => System.IO.Path.GetFileName(Path);
    public string Folder => System.IO.Path.GetDirectoryName(Path) ?? "";
}

/// <summary>
/// Walks configured root folders and finds every file that carries a
/// <c>filelore.note</c> alternate data stream.
///
/// Stream detection uses <c>FindFirstStreamW</c>/<c>FindNextStreamW</c> (a
/// single kernel metadata call per file, name-only check) — the stream
/// <em>content</em> is opened only for the rare files that actually carry a
/// note, so walking a large tree stays cheap.
///
/// Safety rails: reparse points/junctions, hidden/system directories,
/// <c>C:\Windows</c>, <c>$Recycle.Bin</c>, <c>Program Files*</c> and
/// <c>AppData</c> are skipped; depth is capped at 12 and files visited per
/// root at 200k. Enumeration is synchronous and cooperative-cancellable —
/// callers run it on a background task and receive results incrementally
/// via <paramref name="onNote"/>.
/// </summary>
public static class NoteIndex
{
    private const int MaxDepth = 12;
    private const int MaxFilesPerRoot = 200_000;

    /// <summary>
    /// Scans <paramref name="roots"/> and reports each noted file as it is
    /// found. <paramref name="onRootStarted"/> fires once per existing root
    /// (for status lines like "Scanning C:\FileLoreTest…"). Roots where notes
    /// cannot exist (network shares, non-NTFS volumes — see
    /// <see cref="NoteStore.IsSupportedPath"/>) are skipped up front via
    /// <paramref name="onRootSkipped"/> with a friendly status line, so a UNC
    /// root never stalls the scan on network timeouts. Returns the total
    /// number of notes found. Inaccessible subtrees are skipped.
    /// </summary>
    public static int Scan(
        IReadOnlyList<string> roots,
        Action<IndexedNote> onNote,
        Action<string>? onRootStarted = null,
        CancellationToken cancellationToken = default,
        Action<string>? onRootSkipped = null)
    {
        int found = 0;
        foreach (string root in roots)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (NoteStore.IsNetworkPath(root))
            {
                onRootSkipped?.Invoke($"Skipped network folder {root} — notes can't live there");
                continue;
            }
            if (NoteStore.IsSupportedPath(root) is (false, var reason))
            {
                onRootSkipped?.Invoke($"Skipped {root} — {reason}");
                continue;
            }
            if (!Directory.Exists(root)) continue;
            onRootStarted?.Invoke(root);
            found += ScanRoot(root, onNote, cancellationToken);
        }
        return found;
    }

    private static int ScanRoot(string root, Action<IndexedNote> onNote, CancellationToken ct)
    {
        int found = 0;
        int visited = 0;
        var pending = new Stack<(string Dir, int Depth)>();
        pending.Push((root, 0));

        var options = new EnumerationOptions
        {
            IgnoreInaccessible = true,
            RecurseSubdirectories = false,
            AttributesToSkip = 0, // attribute filtering done by hand (dirs and files differ)
        };

        while (pending.Count > 0)
        {
            ct.ThrowIfCancellationRequested();
            var (dir, depth) = pending.Pop();
            if (visited >= MaxFilesPerRoot) break;

            IEnumerable<FileSystemInfo> entries;
            try { entries = new DirectoryInfo(dir).EnumerateFileSystemInfos("*", options); }
            catch { continue; } // races with deletion etc.

            foreach (var entry in entries)
            {
                ct.ThrowIfCancellationRequested();
                if (entry is DirectoryInfo subDir)
                {
                    if (depth + 1 > MaxDepth) continue;
                    if (ShouldSkipDirectory(subDir)) continue;
                    pending.Push((subDir.FullName, depth + 1));
                }
                else
                {
                    if ((entry.Attributes & FileAttributes.ReparsePoint) != 0) continue; // symlinks etc.
                    if (++visited > MaxFilesPerRoot) break;
                    if (!HasNoteStream(entry.FullName)) continue;

                    Note? note = null;
                    try { note = NoteStore.Read(entry.FullName); } catch { /* unreadable envelope → skip */ }
                    if (note is null) continue;

                    onNote(new IndexedNote { Path = entry.FullName, Note = note });
                    found++;
                }
            }
        }
        return found;
    }

    private static bool ShouldSkipDirectory(DirectoryInfo dir)
    {
        var attrs = dir.Attributes;
        if ((attrs & FileAttributes.ReparsePoint) != 0) return true; // junctions / symlinks
        if ((attrs & (FileAttributes.Hidden | FileAttributes.System)) != 0) return true;

        string name = dir.Name;
        if (name.Equals("$Recycle.Bin", StringComparison.OrdinalIgnoreCase)) return true;
        if (name.Equals("AppData", StringComparison.OrdinalIgnoreCase)) return true;
        if (name.StartsWith("Program Files", StringComparison.OrdinalIgnoreCase)) return true;

        // "Windows" only at a drive root (C:\Windows), not C:\FileLoreTest\Windows
        if (name.Equals("Windows", StringComparison.OrdinalIgnoreCase)
            && dir.Parent?.Parent is null)
        {
            return true;
        }
        return false;
    }

    // ---- stream-name detection -------------------------------------------------

    private static bool HasNoteStream(string path)
    {
        var data = new WIN32_FIND_STREAM_DATA();
        IntPtr handle = FindFirstStreamW(ExtendedPath(path), 0, ref data, 0);
        if (handle == InvalidHandle) return false;
        try
        {
            do
            {
                // cStreamName looks like ":filelore.note:$DATA"
                if (string.Equals(data.cStreamName, ":" + NoteStore.StreamName + ":$DATA",
                        StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
            while (FindNextStreamW(handle, ref data));
            return false;
        }
        finally
        {
            FindClose(handle);
        }
    }

    private static string ExtendedPath(string path)
        => path.Length > 250 && !path.StartsWith(@"\\?\", StringComparison.Ordinal)
            ? @"\\?\" + path
            : path;

    private static readonly IntPtr InvalidHandle = new(-1);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WIN32_FIND_STREAM_DATA
    {
        public long StreamSize;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 296)]
        public string cStreamName;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr FindFirstStreamW(
        string lpFileName, int InfoLevel, ref WIN32_FIND_STREAM_DATA lpFindStreamData, int dwFlags);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FindNextStreamW(IntPtr hFindStream, ref WIN32_FIND_STREAM_DATA lpFindStreamData);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FindClose(IntPtr hFindFile);
}
