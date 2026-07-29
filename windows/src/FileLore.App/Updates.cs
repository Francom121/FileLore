using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using Velopack;

namespace FileLore.App;

/// <summary>
/// Velopack auto-update service (0.8.0+), the Windows mirror of the Mac's
/// Sparkle setup: a static feed on filelore.netlify.app, a throttled
/// background check on startup, a manual "Check for Updates…" (tray menu
/// and Settings), and an apply-on-restart flow.
///
/// Feed layout (static Netlify hosting, plain HTTPS GETs — no API):
///   /releases/win-x64/    releases.win.json + FileLore-x.y.z-full.nupkg (+deltas)
///   /releases/win-arm64/  same file names, ARM64 payloads
/// The app picks the directory matching its own process architecture;
/// FILELORE_UPDATE_URL overrides the whole URL (local end-to-end tests).
///
/// Velopack applies a DOWNLOADED update automatically on the next app
/// start (SetAutoApplyOnStartup, on by default) — so the background check
/// only needs to download; "applies on next run" like Sparkle. A pending
/// download is also surfaced in the tray menu ("Restart to update to …").
///
/// This class is UI-free: the App wires tray balloons / the update window.
/// </summary>
internal static class Updates
{
    public const string FeedUrlX64 = "https://filelore.netlify.app/releases/win-x64/";
    public const string FeedUrlArm64 = "https://filelore.netlify.app/releases/win-arm64/";

    /// <summary>Update feed URL for this process (env override wins).</summary>
    public static string FeedUrl
    {
        get
        {
            string? overrideUrl = Environment.GetEnvironmentVariable("FILELORE_UPDATE_URL");
            if (!string.IsNullOrWhiteSpace(overrideUrl))
                return overrideUrl.TrimEnd('/') + "/";
            return RuntimeInformation.ProcessArchitecture == Architecture.Arm64
                ? FeedUrlArm64
                : FeedUrlX64;
        }
    }

    /// <summary>Minimum time between automatic background checks.</summary>
    private static readonly TimeSpan AutoCheckInterval = TimeSpan.FromHours(6);

    /// <summary>
    /// A manager for the current install, or null when Velopack can't
    /// initialize (e.g. running unpacked from a build folder). NEVER throws.
    /// </summary>
    public static UpdateManager? CreateManager()
    {
        try { return new UpdateManager(FeedUrl); }
        catch (Exception ex)
        {
            AppLog.Write("updates: UpdateManager init failed: " + ex.Message);
            return null;
        }
    }

    /// <summary>True when this process runs from a Velopack install (current\).</summary>
    public static bool IsInstalled => CreateManager()?.IsInstalled == true;

    /// <summary>Version of an already-downloaded update waiting for a restart, else null.</summary>
    public static string? PendingRestartVersion()
    {
        try { return CreateManager()?.UpdatePendingRestart?.Version.ToString(); }
        catch (Exception ex) { AppLog.Write("updates: pending-restart probe failed: " + ex.Message); return null; }
    }

    // ---- throttled background check ------------------------------------------

    private sealed class UpdateState
    {
        public DateTime LastAutoCheckUtc { get; set; }
    }

    private static string StatePath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "FileLore", "update-state.json");

    private static UpdateState LoadState()
    {
        try
        {
            if (File.Exists(StatePath))
                return JsonSerializer.Deserialize<UpdateState>(File.ReadAllText(StatePath)) ?? new();
        }
        catch { /* corrupt state file → fresh */ }
        return new();
    }

    private static void SaveState(UpdateState state)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(StatePath)!);
            File.WriteAllText(StatePath, JsonSerializer.Serialize(state));
        }
        catch { /* best effort */ }
    }

    /// <summary>
    /// Startup background check (throttled to once per 6 h): check, download
    /// silently, log everything to app.log. When an update was downloaded,
    /// <paramref name="onReady"/> is invoked on the UI thread with the new
    /// version string (tray balloon). Completely silent on any failure
    /// (offline laptops must never see update noise).
    /// </summary>
    public static async Task BackgroundCheckAsync(Action<string>? onReady)
    {
        try
        {
            var mgr = CreateManager();
            if (mgr is null || !mgr.IsInstalled)
            {
                AppLog.Write("updates: background check skipped (not an installed copy)");
                return;
            }

            var state = LoadState();
            if (DateTime.UtcNow - state.LastAutoCheckUtc < AutoCheckInterval)
            {
                AppLog.Write("updates: background check skipped (throttled)");
                return;
            }
            state.LastAutoCheckUtc = DateTime.UtcNow;
            SaveState(state);

            AppLog.Write($"updates: background check → {FeedUrl}");
            var info = await mgr.CheckForUpdatesAsync();
            if (info is null)
            {
                AppLog.Write("updates: up to date");
                return;
            }

            string version = info.TargetFullRelease.Version.ToString();
            AppLog.Write($"updates: {version} available — downloading in background");
            await mgr.DownloadUpdatesAsync(info);
            AppLog.Write($"updates: {version} downloaded — applies on next restart");
            if (onReady is not null)
                System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => onReady(version));
        }
        catch (Exception ex)
        {
            AppLog.Write("updates: background check failed (offline? " + ex.GetType().Name + "): " + ex.Message);
        }
    }

    /// <summary>
    /// Applies an already-downloaded update and restarts via Velopack.
    /// Exits the process immediately — callers must clean up (tray icon,
    /// pipe server) BEFORE calling. Returns false when nothing is pending.
    /// </summary>
    public static bool ApplyPendingAndRestart()
    {
        var mgr = CreateManager();
        if (mgr?.UpdatePendingRestart is null) return false;
        AppLog.Write("updates: applying pending update and restarting");
        mgr.ApplyUpdatesAndRestart(mgr.UpdatePendingRestart);
        return true; // unreachable — ApplyUpdatesAndRestart exits the process
    }
}
