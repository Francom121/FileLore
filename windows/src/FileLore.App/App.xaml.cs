using System.IO;
using System.Windows;
using FileLore.Core;
using WinForms = System.Windows.Forms;

namespace FileLore.App;

/// <summary>
/// Entry point and tray host.
///
/// Instance model: a plain (session-local) mutex marks the first instance,
/// which owns the tray icon, the global hotkeys and the search window, and
/// lives until Exit. A later instance launched with a file path (e.g. a
/// second Explorer right-click) opens its own editor window and exits when
/// that window closes — two editors for two files are fine, two tray icons
/// are not.
///
/// Command line:
///   FileLore.exe [path]            open the editor for path (or start tray)
///   FileLore.exe --tray            start tray-only, no balloon (autostart)
///   FileLore.exe --hotkey-open-selection   dev hook: run the Ctrl+Alt+T handler
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

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Headless test hook used by the milestone verification harness:
        //   FileLore.exe --selftest <resultFile> <targetPath> <body> <tagsCsv>
        //   FileLore.exe --selftest search <resultFile>
        if (e.Args.Length >= 1 && e.Args[0] == "--selftest")
        {
            int code = SelfTest.Run(e.Args);
            Shutdown(code);
            return;
        }

        // Dev hook: run the exact Ctrl+Alt+T handler without physical keys.
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
            SetupTray();
            SetupHotkeys();
            if (path is not null)
            {
                OpenEditor(path);
            }
            else if (!trayOnly)
            {
                _tray!.ShowBalloonTip(6000, "FileLore",
                    "FileLore is running — right-click any file to attach a note.",
                    WinForms.ToolTipIcon.Info);
            }
        }
        else
        {
            if (path is null)
            {
                Shutdown(); // tray already running elsewhere; nothing to do
                return;
            }
            ShutdownMode = ShutdownMode.OnLastWindowClose;
            OpenEditor(path);
        }
    }

    internal void OpenEditor(string path)
    {
        if (NoteStore.HasNote(path))
            Recents.Add(path); // opening an already-noted file counts as activity

        var window = new MainWindow(path);
        window.Show();
        window.Activate();
    }

    // ---- search window ------------------------------------------------------------

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
            string combo = id == HotkeyManager.IdOpenSelection ? "Ctrl+Alt+T" : "Ctrl+Alt+F";
            _tray?.ShowBalloonTip(6000, "FileLore",
                $"Hotkey {combo} is unavailable (another app owns it).", WinForms.ToolTipIcon.Warning);
        };
        _hotkeys.Register();
    }

    /// <summary>
    /// The Ctrl+Alt+T handler: open the editor for the current Explorer
    /// selection; when nothing usable is selected, fall back to a file dialog.
    /// Also exposed headlessly as <c>--hotkey-open-selection</c> so milestone
    /// verification can drive it without physical key presses.
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
        menu.Items.Add("Attach note to file…", null, (_, _) => AttachFlow());
        menu.Items.Add("Search notes…  Ctrl+Alt+F", null, (_, _) => ShowSearchWindow());
        var recent = new WinForms.ToolStripMenuItem("Recent notes");
        menu.Items.Add(recent);
        menu.Items.Add(new WinForms.ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => ExitApp());
        menu.Opening += (_, _) => RebuildRecentMenu(recent);

        _tray = new WinForms.NotifyIcon
        {
            Text = "FileLore",
            Icon = _trayIconImage,
            Visible = true,
            ContextMenuStrip = menu,
        };
        _tray.DoubleClick += (_, _) => AttachFlow();
    }

    private void RebuildRecentMenu(WinForms.ToolStripMenuItem recent)
    {
        recent.DropDownItems.Clear();
        var items = Recents.Load();
        if (items.Count == 0)
        {
            recent.DropDownItems.Add(new WinForms.ToolStripMenuItem("(no recent notes)") { Enabled = false });
            return;
        }
        foreach (var p in items)
        {
            string captured = p;
            var item = new WinForms.ToolStripMenuItem(Path.GetFileName(p)) { ToolTipText = p };
            item.Click += (_, _) => OpenEditor(captured);
            recent.DropDownItems.Add(item);
        }
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
