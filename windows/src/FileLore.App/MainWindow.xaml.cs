using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using FileLore.Core;

namespace FileLore.App;

/// <summary>
/// The note editor for a single file. Mirrors the Mac editor: header with
/// file icon/name/folder, a large note body, removable tag pills, and a
/// Save / Delete / Copy / Open File Location button row.
/// </summary>
public partial class MainWindow : Window
{
    private readonly string _path;

    public MainWindow(string path)
    {
        InitializeComponent();
        _path = path;
        Title = Path.GetFileName(path);
        Loaded += MainWindow_Loaded;
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.S && Keyboard.Modifiers == ModifierKeys.Control)
            {
                SaveNote();
                e.Handled = true;
            }
        };
    }

    private void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        bool exists = File.Exists(_path);
        FileNameText.Text = Path.GetFileName(_path);
        FolderText.Text = Path.GetDirectoryName(_path) ?? "";
        LoadFileIcon(exists);

        if (!exists)
        {
            SaveBtn.IsEnabled = false;
            SetStatus("File not found — cannot attach a note.", error: true);
            UpdateHints();
            return;
        }

        Note? note = null;
        try { note = NoteStore.Read(_path); }
        catch (Exception ex) { SetStatus("Could not read existing note: " + ex.Message, error: true); }

        if (note is not null)
        {
            BodyBox.Text = note.Body;
            foreach (var tag in note.Tags) AddPill(tag);
            DeleteBtn.Visibility = Visibility.Visible;
            SetStatus($"Existing note · modified {note.Modified.ToLocalTime():MMM d, yyyy h:mm tt}", neutral: true);
        }
        UpdateHints();
    }

    private void LoadFileIcon(bool exists)
    {
        try
        {
            if (exists)
            {
                using var icon = System.Drawing.Icon.ExtractAssociatedIcon(_path);
                if (icon is not null)
                {
                    var bmp = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
                        icon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                    bmp.Freeze();
                    FileIcon.Source = bmp;
                    return;
                }
            }
        }
        catch { /* fall through to app icon */ }

        var sri = Application.GetResourceStream(new Uri("pack://application:,,,/Resources/app.ico"));
        using var fallback = new System.Drawing.Icon(sri!.Stream);
        var fb = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
            fallback.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
        fb.Freeze();
        FileIcon.Source = fb;
    }

    // ---- tags ---------------------------------------------------------------

    private void AddPill(string tag)
    {
        tag = tag.Trim();
        if (tag.Length == 0) return;
        if (CurrentTags().Any(t => string.Equals(t, tag, StringComparison.OrdinalIgnoreCase))) return;

        var pill = new Border
        {
            Background = new SolidColorBrush(Color.FromRgb(0xFD, 0xF3, 0xE3)),
            BorderBrush = new SolidColorBrush(Color.FromRgb(0xEB, 0x96, 0x1E)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(11),
            Padding = new Thickness(9, 3, 7, 3),
            Margin = new Thickness(0, 0, 6, 6),
            Tag = tag,
        };
        var row = new StackPanel { Orientation = Orientation.Horizontal };
        row.Children.Add(new TextBlock { Text = tag, FontSize = 12, VerticalAlignment = VerticalAlignment.Center });
        var remove = new TextBlock
        {
            Text = "×",
            FontSize = 13,
            Margin = new Thickness(7, 0, 0, 0),
            Foreground = new SolidColorBrush(Color.FromRgb(0xB0, 0x74, 0x17)),
            Cursor = Cursors.Hand,
            VerticalAlignment = VerticalAlignment.Center,
            ToolTip = "Remove tag",
        };
        remove.MouseLeftButtonUp += (_, _) => PillsPanel.Children.Remove(pill);
        row.Children.Add(remove);
        pill.Child = row;
        PillsPanel.Children.Add(pill);
    }

    private IEnumerable<string> CurrentTags()
        => PillsPanel.Children.OfType<Border>().Select(b => (string)b.Tag);

    private void TagInput_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            AddPill(TagInput.Text);
            TagInput.Clear();
            e.Handled = true;
        }
    }

    // ---- actions --------------------------------------------------------------

    private void SaveNote()
    {
        try
        {
            NoteEditorService.Save(_path, BodyBox.Text, CurrentTags());
            DeleteBtn.Visibility = Visibility.Visible;
            SetStatus($"Saved ✓  {DateTime.Now:h:mm tt}");
        }
        catch (Exception ex)
        {
            SetStatus("Save failed: " + ex.Message, error: true);
        }
    }

    private void Save_Click(object sender, RoutedEventArgs e) => SaveNote();

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            NoteStore.Delete(_path);
            BodyBox.Clear();
            PillsPanel.Children.Clear();
            DeleteBtn.Visibility = Visibility.Collapsed;
            SetStatus("Note deleted.", neutral: true);
            UpdateHints();
        }
        catch (Exception ex)
        {
            SetStatus("Delete failed: " + ex.Message, error: true);
        }
    }

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            System.Windows.Clipboard.SetText(BodyBox.Text ?? "");
            SetStatus("Copied ✓");
        }
        catch (Exception ex)
        {
            SetStatus("Copy failed: " + ex.Message, error: true);
        }
    }

    private void OpenLocation_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start("explorer.exe", $"/select,\"{_path}\"");
        }
        catch (Exception ex)
        {
            SetStatus("Could not open location: " + ex.Message, error: true);
        }
    }

    // ---- helpers ----------------------------------------------------------------

    private void SetStatus(string message, bool error = false, bool neutral = false)
    {
        StatusText.Text = message;
        StatusText.Foreground = error
            ? new SolidColorBrush(Color.FromRgb(0xC0, 0x39, 0x2B))
            : neutral
                ? new SolidColorBrush(Color.FromRgb(0x8A, 0x8A, 0x84))
                : new SolidColorBrush(Color.FromRgb(0x2E, 0x7D, 0x32));
    }

    private void UpdateHints()
    {
        BodyHint.Visibility = string.IsNullOrEmpty(BodyBox.Text) ? Visibility.Visible : Visibility.Collapsed;
        TagHint.Visibility = string.IsNullOrEmpty(TagInput.Text) ? Visibility.Visible : Visibility.Collapsed;
    }

    private void BodyBox_TextChanged(object sender, TextChangedEventArgs e) => UpdateHints();
    private void TagInput_TextChanged(object sender, TextChangedEventArgs e) => UpdateHints();
}
