using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace FileLore.App;

/// <summary>
/// Registers the two process-wide hotkeys (note-selection, search) on a
/// hidden message-only window and raises <see cref="HotkeyPressed"/> from
/// its WndProc. Combos come from <see cref="Settings"/> and can be rebound
/// at runtime: <see cref="Reregister"/> unregisters the old chords first,
/// registers the new ones, and rolls back to the previous working chords
/// when a new combo is owned by another app (reported via
/// <see cref="HotkeyFailed"/> so the caller can surface a balloon).
/// </summary>
public sealed class HotkeyManager : IDisposable
{
    public const int IdOpenSelection = 1;
    public const int IdSearch = 2;

    private const uint ModNoRepeat = 0x4000;
    private const int WmHotkey = 0x0312;

    private HwndSource? _source;
    private readonly Dictionary<int, HotkeyCombo> _registered = new();

    /// <summary>Raised on the UI thread when a registered hotkey fires. The int is the hotkey id.</summary>
    public event Action<int>? HotkeyPressed;

    /// <summary>Raised when a combo could not be registered (conflict). The int is the hotkey id.</summary>
    public event Action<int>? HotkeyFailed;

    /// <summary>Currently registered combos by hotkey id (evidence for rebinding/self-tests).</summary>
    public IReadOnlyDictionary<int, HotkeyCombo> Registered => _registered;

    /// <summary>Initial registration; must be called once before <see cref="Reregister"/>.</summary>
    public void Register(HotkeyCombo openSelection, HotkeyCombo search)
    {
        var parameters = new HwndSourceParameters("FileLoreHotkeySink")
        {
            Width = 0,
            Height = 0,
            ParentWindow = new IntPtr(-3), // HWND_MESSAGE: message-only window, never visible
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);

        TryRegister(IdOpenSelection, openSelection);
        TryRegister(IdSearch, search);
    }

    /// <summary>
    /// Live rebind: unregisters both current chords, then registers
    /// <paramref name="openSelection"/>/<paramref name="search"/>. When a new
    /// combo fails (conflict), the previous working chords are restored and
    /// the method returns false — the caller keeps the old settings.
    /// </summary>
    public bool Reregister(HotkeyCombo openSelection, HotkeyCombo search)
    {
        var previous = new Dictionary<int, HotkeyCombo>(_registered);
        UnregisterAll();

        bool ok = TryRegister(IdOpenSelection, openSelection)
                & TryRegister(IdSearch, search); // non-short-circuit: attempt both for complete logging
        if (ok) return true;

        AppLog.Write("rebind failed — restoring previous hotkeys");
        UnregisterAll();
        foreach (var (id, combo) in previous)
            TryRegister(id, combo);
        return false;
    }

    private bool TryRegister(int id, HotkeyCombo combo)
    {
        if (RegisterHotKey(_source!.Handle, id, combo.Modifiers | ModNoRepeat, combo.Key))
        {
            _registered[id] = combo;
            AppLog.Write($"RegisterHotKey succeeded for id {id} ({combo})");
            return true;
        }
        int error = Marshal.GetLastWin32Error();
        AppLog.Write($"RegisterHotKey FAILED for id {id} ({combo}) (Win32 error {error}) — combo owned by another app");
        HotkeyFailed?.Invoke(id);
        return false;
    }

    private void UnregisterAll()
    {
        if (_source is null) return;
        foreach (int id in _registered.Keys)
        {
            UnregisterHotKey(_source.Handle, id);
            AppLog.Write($"UnregisterHotKey id {id}");
        }
        _registered.Clear();
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
        UnregisterAll();
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
