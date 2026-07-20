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
