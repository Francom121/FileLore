using System.IO;
using System.Runtime.InteropServices;

namespace FileLore.App;

/// <summary>
/// Tells Windows Explorer to repaint the icon of a file whose note just
/// changed, so the FileLore overlay badge (FileLoreOverlay.dll, registered
/// opt-in via Settings) appears/disappears without a manual F5.
///
/// Wired to <see cref="NoteEvents"/> from <c>App</c> startup: every save,
/// delete, and batch run already raises NoteChanged with the file's path.
/// Costs nothing when no overlay handler is registered.
///
/// Refresh strategy (measured on Win11 23H2, see windows/README.md):
/// 1. <c>SHChangeNotify(SHCNE_UPDATEITEM)</c> — cheap, helps other shell
///    views; on its own NOT sufficient for overlay re-query on delete.
/// 2. <c>IShellWindows</c> scan + <c>IWebBrowserApp.Refresh()</c> on every
///    open Explorer window showing the noted file's folder — a programmatic
///    F5. This is the only thing that reliably makes Explorer re-run the
///    overlay handler's IsMemberOf() for an already-displayed item.
/// Folders are debounced (~1.5 s) so a batch save refreshes each folder once.
/// </summary>
internal static class ShellBadgeRefresh
{
    private const uint SHCNE_UPDATEITEM = 0x00002000;
    private const uint SHCNF_PATHW = 0x0005;
    private const uint SHCNF_FLUSH = 0x1000;

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern void SHChangeNotify(uint wEventId, uint uFlags,
        [MarshalAs(UnmanagedType.LPWStr)] string pszPath, IntPtr dwItem2);

    private static readonly object _gate = new();
    private static readonly HashSet<string> _pendingFolders = new(StringComparer.OrdinalIgnoreCase);
    private static System.Threading.Timer? _timer;

    /// <summary>Subscribe to note changes. Call once from App startup.</summary>
    public static void Hook() => NoteEvents.NoteChanged += OnNoteChanged;

    private static void OnNoteChanged(string path)
    {
        try
        {
            if (string.IsNullOrEmpty(path)) return;
            SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW | SHCNF_FLUSH, path, IntPtr.Zero);

            string? folder = Path.GetDirectoryName(path);
            if (folder is null) return;
            lock (_gate)
            {
                _pendingFolders.Add(folder);
                _timer ??= new System.Threading.Timer(_ => FlushFolders(), null,
                    dueTime: TimeSpan.FromMilliseconds(1500),
                    period: Timeout.InfiniteTimeSpan);
                _timer.Change(TimeSpan.FromMilliseconds(1500), Timeout.InfiniteTimeSpan);
            }
        }
        catch { /* a shell-refresh hiccup must never break the save that fired it */ }
    }

    private static void FlushFolders()
    {
        string[] folders;
        lock (_gate)
        {
            if (_pendingFolders.Count == 0) return;
            folders = _pendingFolders.ToArray();
            _pendingFolders.Clear();
        }
        try { RefreshExplorerWindows(folders); }
        catch { /* COM hiccup — next note change retries */ }
    }

    /// <summary>
    /// Late-bound <c>Shell.Application</c>: Refresh() every open Explorer
    /// window whose current folder is one of <paramref name="folders"/>.
    /// Late binding keeps zero COM references in the project.
    /// </summary>
    private static void RefreshExplorerWindows(string[] folders)
    {
        var shellType = Type.GetTypeFromProgID("Shell.Application");
        if (shellType is null) return;
        dynamic? shell = null;
        try
        {
            shell = Activator.CreateInstance(shellType);
            foreach (dynamic window in shell.Windows())
            {
                try
                {
                    string url = window.LocationURL ?? "";
                    if (!url.StartsWith("file:///", StringComparison.OrdinalIgnoreCase)) continue;
                    string winFolder = Uri.UnescapeDataString(
                        new Uri(url).LocalPath).TrimEnd('\\');
                    foreach (string f in folders)
                    {
                        if (string.Equals(winFolder, f.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase))
                        {
                            window.Refresh();
                            break;
                        }
                    }
                }
                catch { /* that window navigated away mid-scan — skip it */ }
            }
        }
        finally
        {
            if (shell is not null && Marshal.IsComObject(shell))
                Marshal.ReleaseComObject(shell);
        }
    }
}
