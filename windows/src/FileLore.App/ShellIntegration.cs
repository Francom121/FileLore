using System.Diagnostics;
using System.IO;
using Microsoft.Win32;
using Velopack;

namespace FileLore.App;

/// <summary>
/// Per-user shell integration driven by Velopack hooks (0.8.0+): the
/// Explorer right-click verb, the tray-autostart Run key, and cleanup of
/// the legacy 0.7.x zip layout. All writes are HKCU / %LOCALAPPDATA% —
/// the no-admin principle is unchanged.
///
/// Layout context: Velopack's Setup.exe installs to
/// %LOCALAPPDATA%\FileLore\ with Update.exe + current\ at the root and the
/// app files inside current\. The `current` directory name is STABLE
/// across updates (Velopack swaps its contents in place), so the verb,
/// Run key and the opt-in HKLM overlay registration (which points at
/// current\FileLoreOverlay.dll) all survive updates without re-writing —
/// we re-assert the HKCU entries on every install/update anyway as cheap
/// self-healing.
///
/// These methods run inside Velopack FastCallback hooks (30 s / 15 s
/// budget, no UI allowed): everything here is fast registry/file work.
/// </summary>
internal static class ShellIntegration
{
    private const string VerbKeyPath = @"Software\Classes\*\shell\FileLore";
    private const string RunKeyPath = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValueName = "FileLore";

    /// <summary>Velopack OnAfterInstallFastCallback / OnAfterUpdateFastCallback.</summary>
    public static void Install(SemanticVersion version)
    {
        try
        {
            RestoreLegacySettingsFromRollbackDir();
            ApplyVerbAndAutostart();
            CleanLegacyZipLayout();
            AppLog.Write($"shell integration applied (velo install/update {version})");
        }
        catch (Exception ex)
        {
            // Never let a hook fail the install/update — worst case the user
            // re-runs setup or re-registers from a diagnose session.
            AppLog.Write("shell integration install failed: " + ex.Message);
        }
    }

    /// <summary>
    /// 0.7.x→0.8.0 migration rescue: when Setup.exe installs over the legacy
    /// zip layout, Velopack RENAMES the existing %LOCALAPPDATA%\FileLore to
    /// "FileLore.&lt;random16&gt;" (rollback dir) and wipes the target BEFORE
    /// any app code can run — losing settings.json / recents.json (notes
    /// themselves live in NTFS streams on user files and are never touched).
    /// The rollback dir still exists while this hook runs (Setup deletes it
    /// only after the install completes), so restore the two user-data files
    /// from it when the fresh root doesn't have them.
    /// </summary>
    private static void RestoreLegacySettingsFromRollbackDir()
    {
        string currentDir = AppContext.BaseDirectory.TrimEnd('\\');
        string? root = Path.GetDirectoryName(currentDir);
        string? parent = root is null ? null : Path.GetDirectoryName(root);
        if (root is null || parent is null) return;

        string rootName = Path.GetFileName(root); // "FileLore"
        foreach (string dir in Directory.GetDirectories(parent, rootName + ".*"))
        {
            foreach (string name in new[] { "settings.json", "recents.json" })
            {
                try
                {
                    string backup = Path.Combine(dir, name);
                    string target = Path.Combine(root, name);
                    if (File.Exists(backup) && !File.Exists(target))
                    {
                        File.Copy(backup, target);
                        AppLog.Write($"migration: restored {name} from rollback dir {Path.GetFileName(dir)}");
                    }
                }
                catch (Exception ex) { AppLog.Write($"migration: {name} restore skipped: {ex.Message}"); }
            }
        }
    }

    /// <summary>Velopack OnBeforeUninstallFastCallback.</summary>
    public static void Uninstall(SemanticVersion version)
    {
        try
        {
            Registry.CurrentUser.DeleteSubKeyTree(VerbKeyPath, throwOnMissingSubKey: false);
            using (var run = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true))
                run?.DeleteValue(RunValueName, throwOnMissingValue: false);
            AppLog.Write($"shell integration removed (velo uninstall {version})");
        }
        catch (Exception ex)
        {
            AppLog.Write("shell integration uninstall failed: " + ex.Message);
        }
    }

    /// <summary>
    /// Write the Explorer verb + Run key pointing into the CURRENT install
    /// directory (AppContext.BaseDirectory = ...\FileLore\current\ when
    /// running installed). Idempotent.
    /// </summary>
    private static void ApplyVerbAndAutostart()
    {
        string dir = AppContext.BaseDirectory.TrimEnd('\\');
        string launcher = Path.Combine(dir, "FileLore.exe");    // native card launcher
        string app = Path.Combine(dir, "FileLoreApp.exe");      // real WPF app

        using (var verb = Registry.CurrentUser.CreateSubKey(VerbKeyPath))
        {
            verb.SetValue(null, "FileLore Note");
            verb.SetValue("Icon", $"\"{launcher}\"");
        }
        using (var command = Registry.CurrentUser.CreateSubKey(VerbKeyPath + @"\command"))
            command.SetValue(null, $"\"{launcher}\" \"%1\"");

        // Tray autostart goes DIRECTLY to the app (no launcher card at login),
        // same as the 0.7.x installer.
        using (var run = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true))
            run?.SetValue(RunValueName, $"\"{app}\" --tray");
    }

    /// <summary>
    /// Migration from the 0.7.x zip layout: that install put FileLore.exe /
    /// FileLoreApp.exe / overlay files FLAT in %LOCALAPPDATA%\FileLore\ —
    /// the very folder Velopack now uses as its root (settings.json,
    /// recents.json, app.log also live there and must be KEPT). Stop any
    /// running legacy processes and delete the stale flat binaries; the
    /// verb/Run key were just repointed into current\ by
    /// <see cref="ApplyVerbAndAutostart"/>.
    /// </summary>
    private static void CleanLegacyZipLayout()
    {
        string currentDir = AppContext.BaseDirectory.TrimEnd('\\');
        string? root = Path.GetDirectoryName(currentDir);
        if (root is null) return;

        string legacyLauncher = Path.Combine(root, "FileLore.exe");
        string legacyApp = Path.Combine(root, "FileLoreApp.exe");
        if (!File.Exists(legacyLauncher) && !File.Exists(legacyApp))
            return; // never a 0.7.x zip install here

        AppLog.Write("legacy 0.7.x flat install detected — migrating to Velopack layout");

        // Stop legacy processes first (a running old tray would hold the exes
        // locked and keep answering the single-instance pipe with an old build).
        // Filter by name BEFORE touching MainModule — reading the module path
        // of unrelated/system processes throws AccessDenied.
        foreach (var proc in Process.GetProcesses())
        {
            try
            {
                if (!proc.ProcessName.Equals("FileLore", StringComparison.OrdinalIgnoreCase) &&
                    !proc.ProcessName.Equals("FileLoreApp", StringComparison.OrdinalIgnoreCase))
                    continue;
                string? path = proc.MainModule?.FileName;
                if (path is null) continue;
                if (!path.Equals(legacyLauncher, StringComparison.OrdinalIgnoreCase) &&
                    !path.Equals(legacyApp, StringComparison.OrdinalIgnoreCase))
                    continue;
                AppLog.Write($"stopping legacy process {proc.ProcessName} (pid {proc.Id})");
                proc.Kill(entireProcessTree: false);
                proc.WaitForExit(5000);
            }
            catch (Exception ex) { AppLog.Write("legacy process stop skipped: " + ex.Message); }
            finally { proc.Dispose(); }
        }

        foreach (string name in new[]
        {
            "FileLore.exe", "FileLoreApp.exe", "FileLoreOverlay.dll",
            "Install-FileLore.cmd", "Uninstall-FileLore.cmd",
            "Register-FileLoreOverlay.cmd", "Unregister-FileLoreOverlay.cmd",
            "FileLore-Diagnose.cmd", "README-WINDOWS.txt",
        })
        {
            try
            {
                string p = Path.Combine(root, name);
                if (File.Exists(p)) File.Delete(p);
            }
            catch (Exception ex) { AppLog.Write($"legacy cleanup: could not delete {name}: {ex.Message}"); }
        }
    }
}
