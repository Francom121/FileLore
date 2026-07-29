using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace FileLore.App;

/// <summary>
/// Settings window (tray → Settings…): two capture boxes for the global
/// hotkeys. Click a box, press a combo (e.g. Ctrl+Alt+T), Save re-registers
/// live — unregistering the old chords first. A combo owned by another app
/// triggers the tray balloon and keeps the previous binding.
/// </summary>
public partial class SettingsWindow : Window
{
    private HotkeyCombo _open;
    private HotkeyCombo _search;
    private Border? _capturing;

    private static readonly Brush IdleBrush = new SolidColorBrush(Color.FromRgb(0xEC, 0xEC, 0xE6));
    private static readonly Brush CaptureBrush = new SolidColorBrush(Color.FromRgb(0xEB, 0x96, 0x1E));

    public SettingsWindow()
    {
        InitializeComponent();
        (_open, _search) = Settings.LoadHotkeys();
        RefreshBoxes();
        RefreshBadgePanel();
        RefreshUpdatePanel();
        // Re-check when the user comes back from the elevated helper.
        Activated += (_, _) => { RefreshBadgePanel(); RefreshUpdatePanel(); };
    }

    // ---- Updates (Velopack, 0.8.0+) -------------------------------------------

    private void RefreshUpdatePanel()
    {
        UpdateStatusText.Text = Updates.PendingRestartVersion() is { } pending
            ? $"{AppVersion.Full} — {pending} is downloaded and installs on the next restart."
            : $"{AppVersion.Full} — updates install automatically.";
    }

    private void Updates_Click(object sender, RoutedEventArgs e) =>
        ((App)Application.Current).ShowUpdateWindow();

    // ---- Explorer badges (opt-in, one-time admin step) ----------------------

    private void RefreshBadgePanel()
    {
        bool registered = BadgeRegistration.IsRegistered();
        BadgeOffButton.Visibility = registered ? Visibility.Visible : Visibility.Collapsed;
        BadgeButton.Visibility = registered ? Visibility.Collapsed : Visibility.Visible;

        if (!BadgeRegistration.FilesPresent)
        {
            BadgeButton.IsEnabled = false;
            BadgeStatusText.Text =
                "Badge files (FileLoreOverlay.dll) are not installed next to the app — " +
                "re-run Install-FileLore.cmd from a current download.";
            return;
        }

        if (registered)
        {
            int slot = BadgeRegistration.SlotPosition();
            int total = BadgeRegistration.HandlerCount();
            // Windows loads at most ~15 overlay handlers, alphabetically by
            // key name — our key is " FileLore" (leading space) precisely to
            // sort first. Warn if something crowded us out anyway.
            BadgeStatusText.Text = slot >= 0 && slot < 15
                ? $"On ✓ Noted files show a small badge in Explorer. (Overlay slot {slot + 1} of {total}; Windows keeps the first ~15.)"
                : $"Registered, but {total} overlay handlers compete for ~15 slots and FileLore currently sorts " +
                  "beyond the limit — badges will NOT show. Remove other apps' overlay handlers (cloud " +
                  "sync tools are the usual suspects) under HKLM\\...\\Explorer\\ShellIconOverlayIdentifiers, " +
                  "then restart Explorer.";
        }
        else
        {
            BadgeStatusText.Text =
                "Optional: noted files get a small badge in Explorer (like OneDrive's status icons). " +
                "One-time step that asks for admin rights once — Windows requires it for icon overlays. " +
                "Everything else in FileLore stays admin-free.";
        }
    }

    private void Badge_Click(object sender, RoutedEventArgs e)
    {
        var err = BadgeRegistration.RegisterElevated();
        BadgeStatusText.Text = err is null
            ? "UAC prompt opened — accept it to register the badge handler, then Explorer restarts. " +
              "Reopen Settings afterwards to confirm it says On ✓."
            : $"Could not start the registration step: {err}";
    }

    private void BadgeOff_Click(object sender, RoutedEventArgs e)
    {
        var err = BadgeRegistration.UnregisterElevated();
        BadgeStatusText.Text = err is null
            ? "UAC prompt opened — accept it to remove the badge handler; Explorer restarts and badges disappear."
            : $"Could not start the removal step: {err}";
    }

    private void RefreshBoxes()
    {
        OpenBoxText.Text = _open.ToString();
        SearchBoxText.Text = _search.ToString();
    }

    private void OpenBox_Click(object sender, MouseButtonEventArgs e) => BeginCapture(OpenBox, OpenBoxText);
    private void SearchBox_Click(object sender, MouseButtonEventArgs e) => BeginCapture(SearchBoxCap, SearchBoxText);

    private void BeginCapture(Border box, TextBlock label)
    {
        EndCapture();
        _capturing = box;
        box.BorderBrush = CaptureBrush;
        label.Text = "Press keys…";
        box.Focus();
    }

    private void EndCapture()
    {
        if (_capturing is null) return;
        _capturing.BorderBrush = IdleBrush;
        _capturing = null;
        RefreshBoxes();
    }

    private void Box_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (_capturing is null || (sender is Border b && b != _capturing)) return;
        e.Handled = true;

        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt
            or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin)
            return; // wait for the non-modifier key

        if (key == Key.Escape)
        {
            EndCapture();
            return;
        }

        uint modifiers = 0;
        if ((Keyboard.Modifiers & ModifierKeys.Control) != 0) modifiers |= HotkeyCombo.ModControl;
        if ((Keyboard.Modifiers & ModifierKeys.Alt) != 0) modifiers |= HotkeyCombo.ModAlt;
        if ((Keyboard.Modifiers & ModifierKeys.Shift) != 0) modifiers |= HotkeyCombo.ModShift;
        if ((Keyboard.Modifiers & ModifierKeys.Windows) != 0) modifiers |= HotkeyCombo.ModWin;
        if (modifiers == 0)
        {
            StatusText.Text = "Add a modifier — Ctrl, Alt, Shift or Win — plus a key.";
            return;
        }

        int vk = KeyInterop.VirtualKeyFromKey(key);
        if (vk <= 0) return;
        var combo = new HotkeyCombo((uint)modifiers, (uint)vk);

        if (_capturing == OpenBox) _open = combo;
        else _search = combo;
        EndCapture();
        StatusText.Text = $"Captured {combo} — Save to apply.";
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        var app = (App)Application.Current;
        if (app.ApplyHotkeys(_open, _search))
        {
            StatusText.Text = "Hotkeys updated ✓";
            RefreshBoxes();
        }
        else
        {
            // Rollback already happened; reload the true current bindings.
            (_open, _search) = Settings.LoadHotkeys();
            RefreshBoxes();
            StatusText.Text = "That combo is taken by another app — kept the previous bindings.";
        }
    }

    private void Reset_Click(object sender, RoutedEventArgs e)
    {
        _open = HotkeyCombo.DefaultOpenSelection;
        _search = HotkeyCombo.DefaultSearch;
        ((App)Application.Current).ResetHotkeysToDefaults();
        RefreshBoxes();
        StatusText.Text = "Back to Ctrl+Alt+T / Ctrl+Alt+F ✓";
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
