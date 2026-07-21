using System.Diagnostics;
using System.IO;
using System.Linq;
using Microsoft.Win32;

namespace FileLore.App;

/// <summary>
/// Status + one-time ADMIN registration for the Explorer overlay badge
/// (FileLoreOverlay.dll, IShellIconOverlayIdentifier).
///
/// The ShellIconOverlayIdentifiers enumeration key is HKLM-only, so enabling
/// badges is the ONE FileLore action that needs elevation — everything else
/// stays per-user. We never elevate the app itself: the "Show badges in
/// Explorer" button launches Register-FileLoreOverlay.cmd through
/// <c>powershell -Verb RunAs</c> (a UAC prompt for that script only).
///
/// Registration key name is " FileLore" — ONE LEADING SPACE, the
/// alphabetical-priority convention OneDrive uses so the badge survives the
/// system-wide ~15 overlay-handler limit. <see cref="SlotPosition"/> does the
/// same read-only enumeration Explorer does and reports where we'd sort.
/// </summary>
internal static class BadgeRegistration
{
    /// <summary>Overlay handler name, with the ONE leading space.</summary>
    public const string OverlayName = " FileLore";

    private const string OverlayKeyPath =
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers";

    // Must match CLSID_FileLoreOverlay in src/FileLore.Overlay/FileLoreOverlay.cpp.
    private const string Clsid = "{7F3C1A2E-9B4D-4E5F-A6C7-1D2E3F4A5B6C}";

    /// <summary>True when the HKLM overlay key for FileLore exists.</summary>
    public static bool IsRegistered()
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(OverlayKeyPath + "\\" + OverlayName);
            return key?.GetValue(null) is string v &&
                   v.Equals(Clsid, StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    /// <summary>
    /// 0-based slot the FileLore overlay would occupy when Explorer loads
    /// handlers alphabetically, or -1 when not registered. Slots beyond ~15
    /// are silently dropped by the shell.
    /// </summary>
    public static int SlotPosition()
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(OverlayKeyPath);
            if (key is null) return -1;
            var names = key.GetSubKeyNames()
                .OrderBy(n => n, StringComparer.OrdinalIgnoreCase)
                .ToList();
            return names.FindIndex(n => n.Equals(OverlayName, StringComparison.OrdinalIgnoreCase));
        }
        catch { return -1; }
    }

    /// <summary>Total number of registered overlay handlers (for the ~15 limit).</summary>
    public static int HandlerCount()
    {
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(OverlayKeyPath);
            return key?.GetSubKeyNames().Length ?? 0;
        }
        catch { return 0; }
    }

    /// <summary>Full path to FileLoreOverlay.dll next to the running exe.</summary>
    public static string DllPath =>
        Path.Combine(AppContext.BaseDirectory, "FileLoreOverlay.dll");

    /// <summary>Full path to Register-FileLoreOverlay.cmd next to the running exe.</summary>
    public static string RegisterScriptPath =>
        Path.Combine(AppContext.BaseDirectory, "Register-FileLoreOverlay.cmd");

    /// <summary>True when both the DLL and the elevated registration script ship alongside the exe.</summary>
    public static bool FilesPresent => File.Exists(DllPath) && File.Exists(RegisterScriptPath);

    /// <summary>
    /// Launch the elevated registration helper. Returns null on success
    /// (UAC accepted, script started), otherwise a user-facing error message.
    /// </summary>
    public static string? RegisterElevated() => RunElevated(RegisterScriptPath);

    /// <summary>Launch the elevated UNregistration helper (Settings → turn badges off).</summary>
    public static string? UnregisterElevated() => RunElevated(
        Path.Combine(AppContext.BaseDirectory, "Unregister-FileLoreOverlay.cmd"));

    private static string? RunElevated(string script)
    {
        if (!File.Exists(script)) return $"Missing helper: {script}";
        try
        {
            // ShellExecute "runas" on the .cmd directly: ONE UAC prompt for
            // the script only — the app itself never elevates.
            Process.Start(new ProcessStartInfo
            {
                FileName = script,
                Verb = "runas",
                UseShellExecute = true,
            });
            return null;
        }
        catch (Exception ex)
        {
            return ex.Message; // e.g. UAC declined (Win32Exception 1223)
        }
    }
}
