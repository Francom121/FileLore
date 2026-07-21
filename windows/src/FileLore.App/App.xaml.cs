using System.IO;
using System.Windows;
using FileLore.Core;
using WinForms = System.Windows.Forms;

namespace FileLore.App;

/// <summary>
/// Entry point and tray host.
///
/// Instance model: a session-local mutex marks the first instance, which
/// owns the tray icon, the global hotkeys, the search window and a named
/// pipe (<see cref="InstanceMessenger"/>). Explorer multi-select fires one
/// process per file: instances 2..N forward their path over the pipe and
/// exit; the first instance debounce-collects (~1.5 s) every path —
/// including its own command-line argument — and opens ONE batch window
/// for many files or the note editor for a single file.
///
/// Command line:
///   FileLore.exe [path]            open the editor for path (no path: open the drop zone)
///   FileLore.exe --tray            start tray-only, no balloon (autostart)
///   FileLore.exe --version [outFile]  print the version + build date and exit
///                                    (optional file target for diagnostics)
///   FileLore.exe --hotkey-open-selection   dev hook: run the note-selection handler
///   FileLore.exe --selftest …      headless verification (see SelfTest)
/// </summary>
public partial class App : Application
{
    private Mutex? _mutex;
    private bool _ownsMutex;
    private WinForms.NotifyIcon? _tray;
    private System.Drawing.Icon? _trayIconImage;
    private HotkeyManager? _hotkeys;
    private SearchWindow? _searchWindow;
    private DropZoneWindow? _dropZone;
    private SettingsWindow? _settingsWindow;
    private ShortcutsWindow? _shortcutsWindow;
    private SplashWindow? _splash;

    // Debounce collector for paths arriving via the pipe / command line.
    private readonly object _pendingGate = new();
    private readonly List<string> _pendingPaths = new();
    private System.Threading.Timer? _pendingTimer;
    private static readonly TimeSpan CollectWindow = TimeSpan.FromMilliseconds(1500);

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Version query: print and exit before touching the mutex or tray.
        // The app is a GUI-subsystem binary, so attach to the parent console
        // (when launched from cmd/Explorer's "Open in Terminal") to make the
        // output visible; redirected stdout (diagnose script) works either way.
        if (e.Args.Length >= 1 && e.Args[0] is "--version" or "-v")
        {
            PrintVersionToConsole(e.Args);
            Shutdown(0);
            return;
        }

        // Headless verification hooks (see SelfTest for the full list):
        if (e.Args.Length >= 1 && e.Args[0] == "--selftest")
        {
            int code = SelfTest.Run(e.Args);
            Shutdown(code);
            return;
        }

        // Dev hook: run the exact note-selection hotkey handler without physical keys.
        if (e.Args.Length >= 1 && e.Args[0] == "--hotkey-open-selection")
        {
            ShutdownMode = ShutdownMode.OnLastWindowClose;
            OpenEditorForExplorerSelection();
            return;
        }

        bool trayOnly = e.Args.Contains("--tray");
        string? path = e.Args.FirstOrDefault(a => !a.StartsWith("--", StringComparison.Ordinal));

        _mutex = new Mutex(initiallyOwned: true, name: "FileLore.SingleInstance", out bool firstInstance);
        _ownsMutex = firstInstance;

        if (firstInstance)
        {
            ShutdownMode = ShutdownMode.OnExplicitShutdown; // tray keeps app alive

            // Cold start is the "looks frozen" window: JIT + tray/hotkey/pipe
            // setup + the 1.5 s multi-select debounce all happen before any
            // window appears. Put the animated splash up first so there is
            // visible feedback the whole time. Tray autostart at login stays
            // silent — a splash on every logon would be noise.
            if (!trayOnly)
                ShowSplash(path is null ? "Starting FileLore…" : "Getting your note ready…");

            SetupTray();
            SetupHotkeys();
            InstanceMessenger.StartServer(EnqueuePath, OnInstanceCommand);
            if (path is not null)
            {
                EnqueuePath(path); // own arg joins the same debounce batch as piped paths
            }
            else if (!trayOnly)
            {
                // No-arg launch = "I want to make a note": open the drop zone
                // (idempotent — the tray "New note / batch…" item uses the
                // same method). The window IS the feedback, so no tray
                // balloon; close the splash as the drop zone shows (the
                // fade-out covers its first layout pass).
                ShowDropZone();
                CloseSplash();
            }
        }
        else
        {
            if (path is null)
            {
                // Second instance launched bare (not --tray autostart):
                // raise the drop zone on the first instance — same UX as a
                // no-arg first launch — instead of exiting silently.
                if (!trayOnly)
                    InstanceMessenger.TrySendCommand(CommandShowDropZone);
                Shutdown();
                return;
            }
            // Explorer multi-select: forward our file to the first instance
            // and exit, so N right-clicked files become ONE batch window.
            if (InstanceMessenger.TrySend(path))
            {
                Shutdown();
                return;
            }
            // No server answered (shouldn't happen) — open our own editor.
            ShutdownMode = ShutdownMode.OnLastWindowClose;
            OpenEditor(path);
        }
    }

    // ---- version --------------------------------------------------------------

    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    private static extern bool AttachConsole(int dwProcessId);

    private const int AttachParentProcess = -1;

    private static void PrintVersionToConsole(string[] args)
    {
        AppLog.Write("--version: " + AppVersion.Full);

        // Optional file target:  FileLore.exe --version <file>
        // Used by FileLore-Diagnose.cmd — cmd never waits for GUI-subsystem
        // apps and stdout redirection of a WinExe single-file binary proved
        // unreliable, so the script passes a file and polls for it.
        if (args.Length >= 2)
        {
            try { File.WriteAllText(args[1], AppVersion.Full + Environment.NewLine); }
            catch (Exception ex) { AppLog.Write("--version file write failed: " + ex.Message); }
        }

        // Interactive best effort: attach to the caller's console and write
        // via CONOUT$ (a GUI app has no standard handles of its own).
        try
        {
            if (AttachConsole(AttachParentProcess))
            {
                using var con = new StreamWriter(File.OpenWrite("CONOUT$")) { AutoFlush = true };
                con.WriteLine(AppVersion.Full);
            }
        }
        catch { /* no console available */ }
        try { Console.WriteLine(AppVersion.Full); } catch { /* no usable stdout */ }
    }

    // ---- path collection (single-file → editor, many → batch window) -------------

    /// <summary>Pipe command raised by a second instance launched with no arguments.</summary>
    private const string CommandShowDropZone = "SHOW-DROPZONE";

    /// <summary>
    /// Command handler for <see cref="InstanceMessenger"/> (background pipe
    /// thread → marshal to the UI thread). A second instance launched bare
    /// asks us to raise the drop zone instead of exiting silently.
    /// </summary>
    private void OnInstanceCommand(string command)
    {
        if (command == CommandShowDropZone)
            Dispatcher.BeginInvoke(() => ShowDropZone());
    }

    private void EnqueuePath(string path)
    {
        int pending;
        lock (_pendingGate)
        {
            if (!_pendingPaths.Contains(path, StringComparer.OrdinalIgnoreCase))
                _pendingPaths.Add(path);
            pending = _pendingPaths.Count;
            _pendingTimer?.Dispose();
            _pendingTimer = new System.Threading.Timer(_ => FlushPendingPaths(), null,
                CollectWindow, System.Threading.Timeout.InfiniteTimeSpan);
        }
        // The debounce window means nothing visible happens for ~1.5 s after
        // the user right-clicks a file — cover it with the animated splash
        // (also when the paths arrive over the pipe while the tray idles).
        Dispatcher.BeginInvoke(() => ShowSplash(pending > 1
            ? $"Collecting {pending} selected files…"
            : "Getting your note ready…"));
    }

    private void FlushPendingPaths()
    {
        List<string> paths;
        lock (_pendingGate)
        {
            paths = new List<string>(_pendingPaths);
            _pendingPaths.Clear();
            _pendingTimer?.Dispose();
            _pendingTimer = null;
        }
        if (paths.Count == 0) return;
        Dispatcher.BeginInvoke(() =>
        {
            if (paths.Count == 1) OpenEditor(paths[0]);
            else OpenBatch(paths);
        });
    }

    // ---- windows --------------------------------------------------------------

    internal void OpenEditor(string path)
    {
        if (NoteStore.HasNote(path))
            Recents.Add(path); // opening an already-noted file counts as activity

        var window = new MainWindow(path);
        window.Show();
        window.Activate();
        CloseSplash(); // the fade-out covers the editor's first layout pass
    }

    internal void OpenBatch(IReadOnlyList<string> paths)
    {
        var window = new BatchWindow(paths);
        window.Show();
        window.Activate();
        CloseSplash();
    }

    // ---- loading splash --------------------------------------------------------

    /// <summary>
    /// Shows (or updates) the animated branded splash. Reused for every
    /// "work is happening but no window is up yet" gap: cold start, and the
    /// Explorer multi-select debounce. Call on the UI thread.
    /// </summary>
    internal void ShowSplash(string message)
    {
        // Reuse guard deliberately does NOT require IsLoaded: a queued
        // ShowSplash (EnqueuePath → Dispatcher.BeginInvoke at Normal
        // priority) can run BEFORE the first splash's Loaded event fires;
        // requiring IsLoaded then spawned a second splash and orphaned the
        // first (Topmost over the editor until the 25 s failsafe).
        // UpdateMessage writes the text block directly and works pre-Loaded.
        if (_splash is { IsFadingOut: false })
        {
            _splash.UpdateMessage(message);
            return;
        }
        _splash = new SplashWindow(message);
        _splash.Closed += (_, _) => _splash = null;
        _splash.Show();
    }

    internal void CloseSplash() => _splash?.FadeOutAndClose();

    internal void ShowDropZone()
    {
        if (_dropZone is { IsLoaded: true })
        {
            _dropZone.Activate();
            return;
        }
        _dropZone = new DropZoneWindow();
        _dropZone.Closed += (_, _) => _dropZone = null;
        _dropZone.Show();
        _dropZone.Activate();
    }

    internal void ShowSearchWindow()
    {
        if (_searchWindow is { IsLoaded: true })
        {
            _searchWindow.Activate(); // raise the existing window
            return;
        }
        _searchWindow = new SearchWindow();
        _searchWindow.Closed += (_, _) => _searchWindow = null;
        _searchWindow.Show();
        _searchWindow.Activate();
    }

    internal void ShowSettingsWindow()
    {
        if (_settingsWindow is { IsLoaded: true })
        {
            _settingsWindow.Activate();
            return;
        }
        _settingsWindow = new SettingsWindow();
        _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }

    internal void ShowShortcutsWindow()
    {
        if (_shortcutsWindow is { IsLoaded: true })
        {
            _shortcutsWindow.Activate();
            return;
        }
        _shortcutsWindow = new ShortcutsWindow();
        _shortcutsWindow.Closed += (_, _) => _shortcutsWindow = null;
        _shortcutsWindow.Show();
        _shortcutsWindow.Activate();
    }

    // ---- hotkeys ---------------------------------------------------------------

    private void SetupHotkeys()
    {
        _hotkeys = new HotkeyManager();
        _hotkeys.HotkeyPressed += id =>
        {
            AppLog.Write($"hotkey pressed: id {id}");
            if (id == HotkeyManager.IdOpenSelection) OpenEditorForExplorerSelection();
            else if (id == HotkeyManager.IdSearch) ShowSearchWindow();
        };
        _hotkeys.HotkeyFailed += id =>
        {
            var (open, search) = Settings.LoadHotkeys();
            string combo = (id == HotkeyManager.IdOpenSelection ? open : search).ToString();
            _tray?.ShowBalloonTip(6000, "FileLore",
                $"Hotkey {combo} is unavailable (another app owns it) — keeping the previous binding.",
                WinForms.ToolTipIcon.Warning);
        };
        var (openCombo, searchCombo) = Settings.LoadHotkeys();
        _hotkeys.Register(openCombo, searchCombo);
    }

    /// <summary>
    /// Applies new hotkey bindings live (Settings window Save). On success
    /// the combos are persisted; on conflict the previous chords stay
    /// registered (HotkeyManager rolls back) and the balloon explains it.
    /// </summary>
    internal bool ApplyHotkeys(HotkeyCombo openSelection, HotkeyCombo search)
    {
        if (_hotkeys is null) return false;
        bool ok = _hotkeys.Reregister(openSelection, search);
        if (ok)
        {
            Settings.SaveHotkeys(openSelection, search);
            AppLog.Write($"hotkeys rebound: open={openSelection}, search={search}");
        }
        return ok;
    }

    internal void ResetHotkeysToDefaults()
    {
        if (_hotkeys is null) return;
        if (_hotkeys.Reregister(HotkeyCombo.DefaultOpenSelection, HotkeyCombo.DefaultSearch))
            Settings.SaveHotkeys(HotkeyCombo.DefaultOpenSelection, HotkeyCombo.DefaultSearch);
    }

    /// <summary>
    /// The note-selection hotkey handler: open the editor for the current
    /// Explorer selection; when nothing usable is selected, fall back to a
    /// file dialog. Also exposed headlessly as
    /// <c>--hotkey-open-selection</c> so milestone verification can drive it
    /// without physical key presses.
    /// </summary>
    internal void OpenEditorForExplorerSelection()
    {
        string? selected = ExplorerSelection.TryGet();
        AppLog.Write("hotkey open-selection: " + (selected ?? "(no Explorer selection — file dialog)"));
        if (selected is not null)
        {
            OpenEditor(selected);
            return;
        }
        AttachFlow();
    }

    // ---- tray ---------------------------------------------------------------

    private void SetupTray()
    {
        var sri = GetResourceStream(new Uri("pack://application:,,,/Resources/app.ico"));
        _trayIconImage = new System.Drawing.Icon(sri!.Stream);

        var menu = new WinForms.ContextMenuStrip();
        menu.Opening += (_, _) => RebuildTrayMenu(menu);

        _tray = new WinForms.NotifyIcon
        {
            Text = "FileLore",
            Icon = _trayIconImage,
            Visible = true,
            ContextMenuStrip = menu,
        };
        _tray.DoubleClick += (_, _) => AttachFlow();
    }

    /// <summary>
    /// Rebuilds the tray menu on every opening so hotkey labels, recent
    /// notes and pinned tags always reflect the current settings.
    /// </summary>
    private void RebuildTrayMenu(WinForms.ContextMenuStrip menu)
    {
        menu.Items.Clear();
        var (openCombo, searchCombo) = Settings.LoadHotkeys();

        menu.Items.Add("Attach note to file…", null, (_, _) => AttachFlow());
        menu.Items.Add("New note / batch…", null, (_, _) => ShowDropZone());
        menu.Items.Add($"Search notes…  {searchCombo}", null, (_, _) => ShowSearchWindow());

        // Recent notes
        var recent = new WinForms.ToolStripMenuItem("Recent notes");
        var items = Recents.Load();
        if (items.Count == 0)
        {
            recent.DropDownItems.Add(new WinForms.ToolStripMenuItem("(no recent notes)") { Enabled = false });
        }
        else
        {
            foreach (var p in items)
            {
                string captured = p;
                var item = new WinForms.ToolStripMenuItem(Path.GetFileName(p)) { ToolTipText = p };
                item.Click += (_, _) => OpenEditor(captured);
                recent.DropDownItems.Add(item);
            }
        }
        menu.Items.Add(recent);

        // Pinned tags: submenu per tag listing noted files (filled async).
        var pinnedItem = new WinForms.ToolStripMenuItem("Pinned Tags");
        BuildPinnedTagsMenu(pinnedItem);
        menu.Items.Add(pinnedItem);

        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add("Settings…", null, (_, _) => ShowSettingsWindow());
        menu.Items.Add("Keyboard Shortcuts…", null, (_, _) => ShowShortcutsWindow());
        menu.Items.Add(new WinForms.ToolStripSeparator());
        // Disabled version label so "which build am I on?" is answerable from the tray.
        menu.Items.Add(new WinForms.ToolStripMenuItem(AppVersion.Full) { Enabled = false });
        menu.Items.Add("Exit", null, (_, _) => ExitApp());
    }

    private void BuildPinnedTagsMenu(WinForms.ToolStripMenuItem pinnedItem)
    {
        var pinned = Settings.LoadPinnedTags();
        if (pinned.Count == 0)
        {
            pinnedItem.DropDownItems.Add(
                new WinForms.ToolStripMenuItem("(pin tags from the search window)") { Enabled = false });
            return;
        }

        foreach (string tag in pinned)
        {
            var tagItem = new WinForms.ToolStripMenuItem("#" + tag);
            tagItem.DropDownItems.Add(new WinForms.ToolStripMenuItem("scanning…") { Enabled = false });
            pinnedItem.DropDownItems.Add(tagItem);
        }
        pinnedItem.DropDownItems.Add(new WinForms.ToolStripSeparator());
        pinnedItem.DropDownItems.Add("Search notes…", null, (_, _) => ShowSearchWindow());

        // Fill each tag's noted-file list off the UI thread; the menu stays
        // open and updates in place when the scan finishes.
        var roots = Settings.LoadRoots();
        Task.Run(() =>
        {
            var noted = new List<IndexedNote>();
            try
            {
                NoteIndex.Scan(roots, noted.Add, onRootStarted: null, CancellationToken.None);
            }
            catch (Exception ex)
            {
                AppLog.Write("pinned-tags scan failed: " + ex.Message);
                return;
            }
            Dispatcher.BeginInvoke(() =>
            {
                for (int i = 0; i < pinned.Count; i++)
                {
                    string tag = pinned[i];
                    if (pinnedItem.DropDownItems[i] is not WinForms.ToolStripMenuItem tagItem) continue;
                    tagItem.DropDownItems.Clear();
                    var files = noted
                        .Where(n => n.Note.Tags.Any(t => string.Equals(t, tag, StringComparison.OrdinalIgnoreCase)))
                        .OrderByDescending(n => n.Note.Modified)
                        .Take(10)
                        .ToList();
                    if (files.Count == 0)
                    {
                        tagItem.DropDownItems.Add(
                            new WinForms.ToolStripMenuItem("(no noted files with this tag)") { Enabled = false });
                    }
                    else
                    {
                        foreach (var n in files)
                        {
                            string captured = n.Path;
                            var item = new WinForms.ToolStripMenuItem(n.FileName) { ToolTipText = n.Path };
                            item.Click += (_, _) => OpenEditor(captured);
                            tagItem.DropDownItems.Add(item);
                        }
                    }
                }
            });
        });
    }

    private void AttachFlow()
    {
        using var dlg = new WinForms.OpenFileDialog
        {
            Title = "Attach a FileLore note to a file",
            Filter = "All files (*.*)|*.*",
            CheckFileExists = true,
        };
        if (dlg.ShowDialog() == WinForms.DialogResult.OK)
            OpenEditor(dlg.FileName);
    }

    private void ExitApp()
    {
        if (_tray is not null)
        {
            _tray.Visible = false;
            _tray.Dispose();
            _tray = null;
        }
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        InstanceMessenger.StopServer();
        _hotkeys?.Dispose();
        _trayIconImage?.Dispose();
        if (_ownsMutex)
        {
            try { _mutex?.ReleaseMutex(); } catch (ApplicationException) { /* not owned */ }
        }
        _mutex?.Dispose();
        base.OnExit(e);
    }
}
