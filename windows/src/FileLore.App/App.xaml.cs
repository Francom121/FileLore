using System.IO;
using System.Windows;
using FileLore.Core;
using WinForms = System.Windows.Forms;

namespace FileLore.App;

/// <summary>
/// Entry point and tray host.
///
/// Instance model: a plain (session-local) mutex marks the first instance,
/// which owns the tray icon and lives until Exit. A later instance launched
/// with a file path (e.g. a second Explorer right-click) opens its own
/// editor window and exits when that window closes — two editors for two
/// files are fine, two tray icons are not.
/// </summary>
public partial class App : Application
{
    private Mutex? _mutex;
    private bool _ownsMutex;
    private WinForms.NotifyIcon? _tray;
    private System.Drawing.Icon? _trayIconImage;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Headless test hook used by the milestone verification harness:
        //   FileLore.exe --selftest <resultFile> <targetPath> <body> <tagsCsv>
        if (e.Args.Length >= 1 && e.Args[0] == "--selftest")
        {
            int code = SelfTest.Run(e.Args);
            Shutdown(code);
            return;
        }

        string? path = e.Args.Length >= 1 ? e.Args[0] : null;

        _mutex = new Mutex(initiallyOwned: true, name: "FileLore.SingleInstance", out bool firstInstance);
        _ownsMutex = firstInstance;

        if (firstInstance)
        {
            ShutdownMode = ShutdownMode.OnExplicitShutdown; // tray keeps app alive
            SetupTray();
            if (path is not null)
            {
                OpenEditor(path);
            }
            else
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

    private void SetupTray()
    {
        var sri = GetResourceStream(new Uri("pack://application:,,,/Resources/app.ico"));
        _trayIconImage = new System.Drawing.Icon(sri!.Stream);

        var menu = new WinForms.ContextMenuStrip();
        menu.Items.Add("Attach note to file…", null, (_, _) => AttachFlow());
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
        _trayIconImage?.Dispose();
        if (_ownsMutex)
        {
            try { _mutex?.ReleaseMutex(); } catch (ApplicationException) { /* not owned */ }
        }
        _mutex?.Dispose();
        base.OnExit(e);
    }
}
