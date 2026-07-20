using System.IO;

namespace FileLore.App;

/// <summary>
/// Tiny append-only log at %LOCALAPPDATA%\FileLore\app.log — the only place
/// headless/diagnostic events (hotkey registration, explorer selection
/// lookups) can be observed after the fact, since this is a GUI-subsystem
/// binary with no console.
/// </summary>
public static class AppLog
{
    private static readonly object Gate = new();

    public static string StoragePath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "FileLore", "app.log");

    public static void Write(string message)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(StoragePath)!);
                File.AppendAllText(StoragePath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}{Environment.NewLine}");
            }
        }
        catch { /* logging must never take the app down */ }
    }
}
