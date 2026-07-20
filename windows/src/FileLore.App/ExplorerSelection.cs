using System.IO;
using System.Runtime.InteropServices;
using Microsoft.CSharp.RuntimeBinder;

namespace FileLore.App;

/// <summary>
/// Locates the foreground Explorer window through the Shell COM API
/// (<c>Shell.Application</c> → <c>ShellWindows</c>) and returns the path of
/// the first selected item. Late-bound via <c>dynamic</c> so the app needs
/// no COM interop assemblies or extra NuGet packages.
/// </summary>
public static class ExplorerSelection
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    /// <summary>
    /// Path of the first selected item in the foreground Explorer window, or
    /// <c>null</c> when no Explorer window is foreground, its selection is
    /// empty, or the item is not a real file (virtual shell folders etc.).
    /// </summary>
    public static string? TryGet()
    {
        try
        {
            long foreground = GetForegroundWindow().ToInt64();
            if (foreground == 0) return null;

            var shellType = Type.GetTypeFromProgID("Shell.Application")
                ?? throw new InvalidOperationException("Shell.Application ProgID not found");
            dynamic shell = Activator.CreateInstance(shellType)!;
            dynamic windows = shell.Windows();

            int count = windows.Count;
            for (int i = 0; i < count; i++)
            {
                dynamic window = windows.Item(i);
                try
                {
                    if ((long)window.HWND != foreground) continue;

                    dynamic items = window.Document.SelectedItems();
                    if (items.Count == 0) return null;

                    string? path = items.Item(0).Path as string;
                    return path is not null && File.Exists(path) ? path : null;
                }
                catch (COMException)
                {
                    // stale/busy shell window — keep scanning the rest
                }
                catch (RuntimeBinderException)
                {
                    // not an Explorer folder window (e.g. Internet Explorer) — skip
                }
            }
            return null;
        }
        catch (Exception ex)
        {
            AppLog.Write("ExplorerSelection.TryGet failed: " + ex.Message);
            return null;
        }
    }
}
