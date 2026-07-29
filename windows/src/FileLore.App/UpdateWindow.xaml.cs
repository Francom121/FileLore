using System.Windows;
using Velopack;

namespace FileLore.App;

/// <summary>
/// Manual "Check for Updates…" window (tray menu / Settings): runs the
/// check → download → apply flow with visible progress, unlike the silent
/// throttled background check. States: checking → up-to-date / downloading
/// (determinate bar) / ready (Restart now) / error (offline-friendly).
/// </summary>
public partial class UpdateWindow : Window
{
    private UpdateInfo? _pendingInfo;

    public UpdateWindow()
    {
        InitializeComponent();
        VersionText.Text = AppVersion.Full;
        Loaded += async (_, _) => await RunFlowAsync();
    }

    private async Task RunFlowAsync()
    {
        var mgr = Updates.CreateManager();
        if (mgr is null || !mgr.IsInstalled)
        {
            MessageText.Text =
                "This copy of FileLore wasn't installed by the FileLore Setup " +
                "(it's running unpacked), so it can't update itself. Grab the " +
                "Setup from filelore.netlify.app to get automatic updates.";
            return;
        }

        // A background check may already have downloaded an update.
        if (mgr.UpdatePendingRestart is { } alreadyPending)
        {
            ShowReady(alreadyPending.Version.ToString());
            return;
        }

        try
        {
            MessageText.Text = "Checking for updates…";
            var info = await mgr.CheckForUpdatesAsync();
            if (info is null)
            {
                MessageText.Text = $"You're up to date — {AppVersion.Display} is the latest release.";
                return;
            }

            _pendingInfo = info;
            string version = info.TargetFullRelease.Version.ToString();
            DownloadBar.Visibility = Visibility.Visible;
            MessageText.Text = $"Downloading FileLore {version}…";
            await mgr.DownloadUpdatesAsync(info, p =>
                Dispatcher.BeginInvoke(() => DownloadBar.Value = p));

            ShowReady(version);
        }
        catch (Exception ex)
        {
            AppLog.Write("updates: manual check failed: " + ex.Message);
            DownloadBar.Visibility = Visibility.Collapsed;
            MessageText.Text =
                "Couldn't check for updates. If you're offline this is normal — " +
                "FileLore keeps working and will try again on its own later. " +
                $"({ex.Message})";
        }
    }

    private void ShowReady(string version)
    {
        DownloadBar.Visibility = Visibility.Collapsed;
        DownloadBar.Value = 100;
        MessageText.Text =
            $"FileLore {version} is ready to install. It takes effect after a " +
            "quick restart — your notes and settings stay untouched.";
        ActionButton.Content = "Restart now";
        ActionButton.Visibility = Visibility.Visible;
        CloseButton.Content = "Later";
    }

    private void Action_Click(object sender, RoutedEventArgs e)
    {
        // Exits the process (Velopack swaps current\ and relaunches via the
        // native launcher, so the branded "getting ready" card covers the
        // post-update cold start). App.ApplyUpdateAndRestart cleans up the
        // tray icon + pipe server first.
        ((App)Application.Current).ApplyUpdateAndRestart();
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
