using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace FileLore.App;

/// <summary>
/// Registers process-wide hotkeys (Ctrl+Alt+T, Ctrl+Alt+F) on a hidden
/// message-only window and raises <see cref="HotkeyPressed"/> from its
/// WndProc. A combo that another app already owns simply fails
/// <c>RegisterHotKey</c> — that is reported via <see cref="HotkeyFailed"/>
/// so the caller can surface a balloon instead of crashing. All registered
/// ids are unregistered on <see cref="Dispose"/>.
/// </summary>
public sealed class HotkeyManager : IDisposable
{
    public const int IdOpenSelection = 1; // Ctrl+Alt+T
    public const int IdSearch = 2;        // Ctrl+Alt+F

    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;
    private const uint ModNoRepeat = 0x4000;
    private const uint VkT = 0x54;
    private const uint VkF = 0x46;
    private const int WmHotkey = 0x0312;

    private HwndSource? _source;
    private readonly List<int> _registered = new();

    /// <summary>Raised on the UI thread when a registered hotkey fires. The int is the hotkey id.</summary>
    public event Action<int>? HotkeyPressed;

    /// <summary>Raised when a combo could not be registered (conflict). The int is the hotkey id.</summary>
    public event Action<int>? HotkeyFailed;

    public void Register()
    {
        var parameters = new HwndSourceParameters("FileLoreHotkeySink")
        {
            Width = 0,
            Height = 0,
            ParentWindow = new IntPtr(-3), // HWND_MESSAGE: message-only window, never visible
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);

        TryRegister(IdOpenSelection, ModControl | ModAlt | ModNoRepeat, VkT);
        TryRegister(IdSearch, ModControl | ModAlt | ModNoRepeat, VkF);
    }

    private void TryRegister(int id, uint modifiers, uint key)
    {
        if (RegisterHotKey(_source!.Handle, id, modifiers, key))
        {
            _registered.Add(id);
            AppLog.Write($"RegisterHotKey succeeded for id {id}");
        }
        else
        {
            int error = Marshal.GetLastWin32Error();
            AppLog.Write($"RegisterHotKey FAILED for id {id} (Win32 error {error}) — combo owned by another app");
            HotkeyFailed?.Invoke(id);
        }
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmHotkey)
        {
            HotkeyPressed?.Invoke(wParam.ToInt32());
            handled = true;
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        if (_source is null) return;
        foreach (int id in _registered)
        {
            UnregisterHotKey(_source.Handle, id);
        }
        _registered.Clear();
        _source.RemoveHook(WndProc);
        _source.Dispose();
        _source = null;
        AppLog.Write("hotkeys unregistered");
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
