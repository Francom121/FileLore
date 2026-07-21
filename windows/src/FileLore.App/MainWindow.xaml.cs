using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using FileLore.Core;
using WinForms = System.Windows.Forms;

namespace FileLore.App;

/// <summary>
/// The note editor for a single file. Mac-parity layout: a media pane on
/// the left (video/audio player, aspect-fit image, shell thumbnail for
/// WIC-unsupported formats, or a big icon for the rest — PDF rendering is a
/// documented non-goal) and the note controls on the right: template
/// dropdown, body, tags, linked files (drag &amp; drop or "Add files…",
/// thumbnails, parent folder, broken-link relink), and the action row.
/// </summary>
public partial class MainWindow : Window
{
    private enum MediaKind { None, Video, Audio, Image, Thumbnail, Icon }

    private static readonly HashSet<string> VideoExt = new(StringComparer.OrdinalIgnoreCase)
        { ".mp4", ".mov", ".m4v", ".wmv", ".avi", ".mpg", ".mpeg", ".mkv", ".webm" };
    private static readonly HashSet<string> AudioExt = new(StringComparer.OrdinalIgnoreCase)
        { ".mp3", ".wav", ".m4a", ".aac", ".flac", ".wma", ".ogg" };
    private static readonly HashSet<string> ImageExt = new(StringComparer.OrdinalIgnoreCase)
        { ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tif", ".tiff", ".ico" };
    private static readonly HashSet<string> ThumbnailExt = new(StringComparer.OrdinalIgnoreCase)
        { ".psd", ".heic", ".heif", ".dng", ".raw", ".cr2", ".nef", ".ai", ".eps" };

    private readonly string _path;
    private bool _canEdit;
    private DateTime? _created;
    private List<LinkedFile> _links = new();

    private bool _playing;
    private bool _mediaReady;
    private bool _scrubbing;
    private bool _templateComboBusy;
    private DispatcherTimer? _mediaTimer;

    public MainWindow(string path)
    {
        InitializeComponent();
        _path = path;
        Title = Path.GetFileName(path);
        Loaded += MainWindow_Loaded;
        Closed += MainWindow_Closed;
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
        RefreshTemplateCombo();

        if (!exists)
        {
            SaveBtn.IsEnabled = false;
            SetStatus("File not found — cannot attach a note.", error: true);
            UpdateHints();
            return;
        }

        // Network shares / non-NTFS volumes can't carry the ADS note stream.
        // Show a friendly banner and disable note editing instead of letting
        // the user hit the raw OS error that names "<path>:filelore.note".
        if (NoteStore.IsSupportedPath(_path) is (false, var unsupportedReason))
        {
            UnsupportedText.Text = unsupportedReason + " " + NoteStore.LocalDriveGuidance;
            UnsupportedBanner.Visibility = Visibility.Visible;
            SaveBtn.IsEnabled = false;
            DeleteBtn.Visibility = Visibility.Collapsed;
            BodyBox.IsReadOnly = true;
            TagInput.IsEnabled = false;
            TemplateCombo.IsEnabled = false;
            SetStatus("Notes can't be stored at this location.", neutral: true);
            UpdateHints();
            return;
        }

        _canEdit = true;
        SetupMediaPane();

        Note? note = null;
        try { note = NoteStore.Read(_path); }
        catch (Exception ex) { SetStatus("Could not read existing note: " + ex.Message, error: true); }

        if (note is not null)
        {
            _created = note.Created;
            BodyBox.Text = note.Body;
            foreach (var tag in note.Tags) AddPill(tag);
            _links = note.Links.ToList();
            DeleteBtn.Visibility = Visibility.Visible;
            SetStatus($"Existing note · modified {note.Modified.ToLocalTime():MMM d, yyyy h:mm tt}", neutral: true);
        }
        RebuildLinks();
        UpdateHints();
    }

    // ======================= media pane =======================

    private MediaKind DetectMediaKind()
    {
        string ext = Path.GetExtension(_path);
        if (VideoExt.Contains(ext)) return MediaKind.Video;
        if (AudioExt.Contains(ext)) return MediaKind.Audio;
        if (ImageExt.Contains(ext)) return MediaKind.Image;
        if (ThumbnailExt.Contains(ext)) return MediaKind.Thumbnail;
        return MediaKind.Icon;
    }

    private void SetupMediaPane()
    {
        var kind = DetectMediaKind();
        if (kind == MediaKind.None) return;

        MediaColumn.Width = new GridLength(1, GridUnitType.Star);
        MediaPane.Visibility = Visibility.Visible;
        Width = 900;
        MinWidth = 780;

        switch (kind)
        {
            case MediaKind.Video:
            case MediaKind.Audio:
                VideoPane.Visibility = Visibility.Visible;
                if (kind == MediaKind.Audio)
                {
                    AudioArt.Visibility = Visibility.Visible;
                    AudioIcon.Source = LoadAssociatedIcon();
                }
                Media.Source = new Uri(_path);
                // Watchdog: on systems where the open neither succeeds nor
                // fails (missing codec pack, odd container), don't leave a
                // black rectangle — fall back to the thumbnail pane.
                var watchdog = new DispatcherTimer { Interval = TimeSpan.FromSeconds(12) };
                watchdog.Tick += (_, _) =>
                {
                    watchdog.Stop();
                    if (!_mediaReady)
                    {
                        VideoPane.Visibility = Visibility.Collapsed;
                        ShowThumbnailPane();
                    }
                };
                watchdog.Start();
                break;

            case MediaKind.Image:
                try
                {
                    var bmp = new BitmapImage();
                    bmp.BeginInit();
                    bmp.UriSource = new Uri(_path);
                    bmp.CacheOption = BitmapCacheOption.OnLoad;
                    bmp.EndInit();
                    bmp.Freeze();
                    ImageView.Source = bmp;
                    ImagePane.Visibility = Visibility.Visible;
                }
                catch { ShowThumbnailPane(); } // WIC can't decode it → shell thumbnail
                break;

            case MediaKind.Thumbnail:
                ShowThumbnailPane();
                break;

            case MediaKind.Icon:
                BigIcon.Source = LoadAssociatedIcon();
                IconLabel.Text = Path.GetExtension(_path).TrimStart('.').ToUpperInvariant()
                    + " file — no inline preview on Windows (the Mac app renders PDFs inline; this is a known difference).";
                IconPane.Visibility = Visibility.Visible;
                break;
        }
    }

    private void ShowThumbnailPane()
    {
        ThumbView.Source = ShellThumbnail.Get(_path, 256, thumbnailOnly: true) ?? LoadAssociatedIcon();
        ThumbPane.Visibility = Visibility.Visible;
    }

    private BitmapSource? LoadAssociatedIcon()
    {
        try
        {
            using var icon = System.Drawing.Icon.ExtractAssociatedIcon(_path);
            if (icon is null) return null;
            var bmp = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(
                icon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            bmp.Freeze();
            return bmp;
        }
        catch { return null; }
    }

    private void Media_MediaOpened(object sender, RoutedEventArgs e)
    {
        _mediaReady = true;
        if (Media.NaturalDuration.HasTimeSpan)
            SeekSlider.Maximum = Media.NaturalDuration.TimeSpan.TotalSeconds;
        Media.Volume = VolumeSlider.Value;

        // Decode a poster frame while starting paused (like the Mac player):
        // play briefly, then freeze on the decoded frame instead of seeking
        // back to a possibly-black position zero.
        Media.Play();
        var poster = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(450) };
        poster.Tick += (_, _) =>
        {
            poster.Stop();
            if (!_playing) // user didn't press play in the meantime
            {
                Media.Pause();
                PlayPauseBtn.Content = "⏵";
                UpdateTimeText();
            }
        };
        poster.Start();

        _mediaTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        _mediaTimer.Tick += (_, _) =>
        {
            if (_scrubbing) return;
            SeekSlider.Value = Math.Min(Media.Position.TotalSeconds, SeekSlider.Maximum);
            UpdateTimeText();
        };
        _mediaTimer.Start();
    }

    private void Media_MediaFailed(object? sender, ExceptionRoutedEventArgs e)
    {
        // Codec missing (e.g. MKV/WebM/H.264 without a pack) → thumbnail fallback.
        _mediaReady = false;
        VideoPane.Visibility = Visibility.Collapsed;
        _mediaTimer?.Stop();
        ShowThumbnailPane();
    }

    private void Media_MediaEnded(object sender, RoutedEventArgs e)
    {
        Media.Position = TimeSpan.Zero;
        Media.Pause();
        _playing = false;
        PlayPauseBtn.Content = "⏵";
    }

    private void PlayPause_Click(object sender, RoutedEventArgs e)
    {
        if (_playing) { Media.Pause(); PlayPauseBtn.Content = "⏵"; }
        else { Media.Play(); PlayPauseBtn.Content = "⏸"; }
        _playing = !_playing;
    }

    private void Seek_Down(object sender, MouseButtonEventArgs e) => _scrubbing = true;

    private void Seek_Up(object sender, MouseButtonEventArgs e)
    {
        Media.Position = TimeSpan.FromSeconds(SeekSlider.Value);
        _scrubbing = false;
        UpdateTimeText();
    }

    private void Volume_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (Media is not null) Media.Volume = VolumeSlider.Value;
    }

    private void UpdateTimeText()
    {
        string pos = FormatTime(Media.Position);
        TimeText.Text = Media.NaturalDuration.HasTimeSpan
            ? $"{pos} / {FormatTime(Media.NaturalDuration.TimeSpan)}"
            : pos;
    }

    private static string FormatTime(TimeSpan t)
        => t.TotalHours >= 1 ? t.ToString(@"h\:mm\:ss") : t.ToString(@"m\:ss");

    private void MainWindow_Closed(object? sender, EventArgs e)
    {
        _mediaTimer?.Stop();
        try
        {
            Media.Stop();
            Media.Close(); // releases the codec/file handle
            Media.Source = null;
        }
        catch { /* never block window teardown */ }
    }

    // ======================= linked files =======================

    private void RebuildLinks()
    {
        LinksPanel.Children.Clear();
        LinksHint.Visibility = _links.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        foreach (var link in _links)
        {
            string? resolved = LinkResolver.Resolve(link, _path);
            bool broken = resolved is null;

            var row = new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(0xFA, 0xFA, 0xF8)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(0xEF, 0xEF, 0xEA)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(8, 6, 8, 6),
                Margin = new Thickness(2, 2, 2, 4),
                Cursor = broken ? Cursors.Arrow : Cursors.Hand,
            };

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var thumb = new Image
            {
                Width = 32, Height = 32, Margin = new Thickness(0, 0, 10, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Source = ShellThumbnail.Get(resolved ?? link.Path ?? "", 32) ?? LoadAssociatedIcon(),
            };
            Grid.SetColumn(thumb, 0);
            grid.Children.Add(thumb);

            var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
            texts.Children.Add(new TextBlock
            {
                Text = link.DisplayName,
                FontSize = 12.5,
                FontWeight = FontWeights.SemiBold,
                TextTrimming = TextTrimming.CharacterEllipsis,
            });
            if (broken)
            {
                texts.Children.Add(new TextBlock
                {
                    Text = "Link broken — relink?",
                    Foreground = new SolidColorBrush(Color.FromRgb(0xC0, 0x39, 0x2B)),
                    FontSize = 11.5,
                });
            }
            else
            {
                // Mac behavior: parent folder path on line 2.
                texts.Children.Add(new TextBlock
                {
                    Text = Path.GetDirectoryName(resolved) ?? "",
                    Foreground = new SolidColorBrush(Color.FromRgb(0x8A, 0x8A, 0x84)),
                    FontSize = 11.5,
                    TextTrimming = TextTrimming.CharacterEllipsis,
                });
            }
            Grid.SetColumn(texts, 1);
            grid.Children.Add(texts);

            if (broken)
            {
                var relink = new Button
                {
                    Content = "Relink…",
                    Style = (Style)FindResource("GhostBtn"),
                    Padding = new Thickness(8, 2, 8, 2),
                    FontSize = 11,
                    Margin = new Thickness(8, 0, 0, 0),
                    VerticalAlignment = VerticalAlignment.Center,
                };
                LinkedFile captured = link;
                relink.Click += (_, _) => RelinkFile(captured);
                Grid.SetColumn(relink, 2);
                grid.Children.Add(relink);
            }

            var remove = new TextBlock
            {
                Text = "×",
                FontSize = 15,
                Margin = new Thickness(8, 0, 2, 0),
                Foreground = new SolidColorBrush(Color.FromRgb(0xB0, 0x74, 0x17)),
                Cursor = Cursors.Hand,
                VerticalAlignment = VerticalAlignment.Center,
                ToolTip = "Remove link",
            };
            LinkedFile capturedRemove = link;
            remove.MouseLeftButtonUp += (_, e) =>
            {
                _links.Remove(capturedRemove);
                SaveNote(quiet: true);
                RebuildLinks();
                SetStatus("Link removed ✓");
                e.Handled = true;
            };
            Grid.SetColumn(remove, 3);
            grid.Children.Add(remove);

            if (!broken)
            {
                string capturedPath = resolved!;
                row.MouseLeftButtonUp += (_, e) =>
                {
                    try
                    {
                        Process.Start(new ProcessStartInfo(capturedPath) { UseShellExecute = true });
                    }
                    catch (Exception ex)
                    {
                        SetStatus("Could not open linked file: " + ex.Message, error: true);
                    }
                    e.Handled = true;
                };
            }

            row.Child = grid;
            LinksPanel.Children.Add(row);
        }
    }

    private void AddLinks(IEnumerable<string> paths)
    {
        if (!_canEdit) return;
        int added = 0;
        foreach (string p in paths)
        {
            if (!File.Exists(p)) continue; // folders and ghosts are not linkable
            if (string.Equals(Path.GetFullPath(p), Path.GetFullPath(_path), StringComparison.OrdinalIgnoreCase))
                continue; // a file never links to itself
            string full = Path.GetFullPath(p);
            if (_links.Any(l => string.Equals(l.Path, full, StringComparison.OrdinalIgnoreCase)))
                continue; // already linked
            _links.Add(LinkResolver.CreateLink(full));
            added++;
        }
        if (added == 0) return;
        SaveNote(quiet: true);
        RebuildLinks();
        SetStatus($"{added} linked file{(added == 1 ? "" : "s")} added ✓");
    }

    private void RelinkFile(LinkedFile link)
    {
        using var dlg = new WinForms.OpenFileDialog
        {
            Title = $"Relink “{link.DisplayName}” to a file",
            Filter = "All files (*.*)|*.*",
            CheckFileExists = true,
            InitialDirectory = Path.GetDirectoryName(_path) ?? "",
        };
        if (dlg.ShowDialog() != WinForms.DialogResult.OK) return;
        LinkResolver.Relink(link, dlg.FileName);
        SaveNote(quiet: true);
        RebuildLinks();
        SetStatus("Link rebound ✓");
    }

    private void AddFiles_Click(object sender, RoutedEventArgs e)
    {
        using var dlg = new WinForms.OpenFileDialog
        {
            Title = "Link files to this note",
            Filter = "All files (*.*)|*.*",
            CheckFileExists = true,
            Multiselect = true,
            InitialDirectory = Path.GetDirectoryName(_path) ?? "",
        };
        if (dlg.ShowDialog() == WinForms.DialogResult.OK)
            AddLinks(dlg.FileNames);
    }

    private void Window_DragOver(object sender, System.Windows.DragEventArgs e)
    {
        e.Effects = _canEdit && e.Data.GetDataPresent(System.Windows.DataFormats.FileDrop)
            ? System.Windows.DragDropEffects.Copy
            : System.Windows.DragDropEffects.None;
        e.Handled = true;
    }

    private void Window_Drop(object sender, System.Windows.DragEventArgs e)
    {
        if (!_canEdit) return;
        if (e.Data.GetData(System.Windows.DataFormats.FileDrop) is string[] paths)
            AddLinks(paths);
    }

    // ======================= templates =======================

    private void RefreshTemplateCombo()
    {
        _templateComboBusy = true;
        TemplateCombo.Items.Clear();
        TemplateCombo.Items.Add("Templates…");
        foreach (var t in Settings.LoadTemplates())
            TemplateCombo.Items.Add(t.Name);
        TemplateCombo.Items.Add("Manage templates…");
        TemplateCombo.SelectedIndex = 0;
        _templateComboBusy = false;
    }

    private void TemplateCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_templateComboBusy || TemplateCombo.SelectedIndex <= 0) return;
        string choice = (string)TemplateCombo.SelectedItem;
        _templateComboBusy = true;
        TemplateCombo.SelectedIndex = 0;
        _templateComboBusy = false;

        if (choice == "Manage templates…")
        {
            var dialog = new TemplatesWindow { Owner = this };
            dialog.ShowDialog();
            RefreshTemplateCombo();
            return;
        }

        // Prefill only into an EMPTY body — a template never clobbers text.
        if (string.IsNullOrEmpty(BodyBox.Text))
        {
            var template = Settings.LoadTemplates()
                .FirstOrDefault(t => string.Equals(t.Name, choice, StringComparison.Ordinal));
            if (template is not null)
            {
                BodyBox.Text = template.Body;
                SetStatus($"Template “{template.Name}” applied", neutral: true);
            }
        }
        else
        {
            SetStatus("Templates apply only to an empty note.", neutral: true);
        }
    }

    // ======================= export =======================

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        var note = new Note
        {
            Body = BodyBox.Text,
            Tags = CurrentTags().ToList(),
            Links = _links.ToList(),
            Created = _created ?? DateTime.UtcNow,
            Modified = DateTime.UtcNow,
        };
        string markdown = MarkdownExporter.Markdown(note, Path.GetFileName(_path), _path);

        var dlg = new Microsoft.Win32.SaveFileDialog
        {
            Title = "Export note as Markdown",
            FileName = Path.GetFileNameWithoutExtension(_path) + "-note.md",
            Filter = "Markdown (*.md)|*.md|All files (*.*)|*.*",
            DefaultExt = ".md",
            InitialDirectory = Path.GetDirectoryName(_path) ?? "",
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            File.WriteAllText(dlg.FileName, markdown);
            SetStatus($"Exported → {Path.GetFileName(dlg.FileName)} ✓");
        }
        catch (Exception ex)
        {
            SetStatus("Export failed: " + ex.Message, error: true);
        }
    }

    // ======================= header =======================

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

    // ======================= tags =======================

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
        var row = new StackPanel { Orientation = System.Windows.Controls.Orientation.Horizontal };
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

    private void TagInput_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            AddPill(TagInput.Text);
            TagInput.Clear();
            e.Handled = true;
        }
    }

    // ======================= actions =======================

    private void SaveNote(bool quiet = false)
    {
        try
        {
            NoteEditorService.Save(_path, BodyBox.Text, CurrentTags(), _links);
            DeleteBtn.Visibility = Visibility.Visible;
            if (!quiet) SetStatus($"Saved ✓  {DateTime.Now:h:mm tt}");
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
            NoteEvents.RaiseChanged(_path);
            BodyBox.Clear();
            PillsPanel.Children.Clear();
            _links.Clear();
            RebuildLinks();
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

    // ======================= helpers =======================

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
