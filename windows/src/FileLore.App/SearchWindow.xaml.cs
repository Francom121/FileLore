using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using FileLore.Core;
using WinForms = System.Windows.Forms;

namespace FileLore.App;

/// <summary>
/// The note search window (tray "Search notes…" / Ctrl+Alt+F). Re-indexes
/// the configured search roots on open and on Refresh, matching against
/// note body + file name + tags with an optional tag-chip filter, and opens
/// the editor for the chosen result. Indexing runs on a background task
/// (cancellable) and streams results in incrementally.
/// </summary>
public partial class SearchWindow : Window
{
    /// <summary>Flat row model bound by the results DataTemplate.</summary>
    private sealed class ResultRow
    {
        public required string Path { get; init; }
        public required string FileName { get; init; }
        public required string Folder { get; init; }
        public required string Snippet { get; init; }
        public required List<string> Tags { get; init; }
        public required string NotedLabel { get; init; }
        public required IndexedNote Source { get; init; }
    }

    private readonly List<IndexedNote> _all = new();
    private readonly HashSet<string> _activeTags = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<string> _roots;
    private CancellationTokenSource? _scanCts;

    public SearchWindow()
    {
        InitializeComponent();
        _roots = Settings.LoadRoots();
        Loaded += (_, _) =>
        {
            SearchBox.Focus();
            RebuildRootChips();
            RefreshIndex();
        };
        Closed += (_, _) => _scanCts?.Cancel();
    }

    // ---- indexing --------------------------------------------------------------

    private void Refresh_Click(object sender, RoutedEventArgs e) => RefreshIndex();

    private void RefreshIndex()
    {
        _scanCts?.Cancel();
        _scanCts = new CancellationTokenSource();
        var ct = _scanCts.Token;

        _all.Clear();
        ApplyFilter();

        var roots = _roots.ToList();
        if (roots.Count == 0)
        {
            StatusText.Text = "No search folders configured — use “Add folder…”.";
            return;
        }

        int found = 0;
        string currentRoot = roots[0];
        var skippedRoots = new List<string>();
        StatusText.Text = $"Scanning {currentRoot}…";

        Task.Run(() =>
        {
            try
            {
                NoteIndex.Scan(
                    roots,
                    onNote: note =>
                    {
                        int n = Interlocked.Increment(ref found);
                        Dispatcher.BeginInvoke(() =>
                        {
                            _all.Add(note);
                            StatusText.Text = $"Scanning {currentRoot}… {n} note(s) found";
                            ApplyFilter();
                        });
                    },
                    onRootStarted: root => Dispatcher.BeginInvoke(() => currentRoot = root),
                    cancellationToken: ct,
                    onRootSkipped: message => Dispatcher.BeginInvoke(() =>
                    {
                        skippedRoots.Add(message);
                        StatusText.Text = message;
                    }));

                Dispatcher.BeginInvoke(() =>
                {
                    RebuildTagChips();
                    ApplyFilter();
                    StatusText.Text = $"{_all.Count} note(s) indexed across {roots.Count} folder(s) — "
                        + (_all.Count == 0 ? "attach a note and hit Refresh." : "type to search, click chips to filter.")
                        + (skippedRoots.Count > 0 ? "  ·  " + string.Join("  ·  ", skippedRoots) : "");
                });
            }
            catch (OperationCanceledException) { /* superseded by a newer scan */ }
            catch (Exception ex)
            {
                Dispatcher.BeginInvoke(() => StatusText.Text = "Scan failed: " + ex.Message);
            }
        }, ct);
    }

    // ---- filtering ---------------------------------------------------------------

    private void ApplyFilter()
    {
        string query = SearchBox?.Text ?? "";
        var rows = _all
            .Where(n => NoteSearch.Matches(n, query, _activeTags))
            .OrderByDescending(n => n.Note.Modified)
            .Select(n => new ResultRow
            {
                Path = n.Path,
                FileName = n.FileName,
                Folder = n.Folder,
                Snippet = MakeSnippet(n.Note.Body),
                Tags = n.Note.Tags,
                NotedLabel = "Noted " + n.Note.Created.ToLocalTime().ToString("MMM d, yyyy"),
                Source = n,
            })
            .ToList();
        Results.ItemsSource = rows;
    }

    private static string MakeSnippet(string body)
    {
        string oneLine = body.Replace("\r", " ").Replace("\n", " ").Trim();
        return oneLine.Length <= 120 ? oneLine : oneLine[..120].TrimEnd() + "…";
    }

    // ---- tag chips ---------------------------------------------------------------

    private void RebuildTagChips()
    {
        var tags = _all
            .SelectMany(n => n.Note.Tags)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(t => t, StringComparer.OrdinalIgnoreCase)
            .ToList();
        _activeTags.RemoveWhere(t => !tags.Contains(t, StringComparer.OrdinalIgnoreCase));

        ChipsPanel.Children.Clear();
        foreach (string tag in tags)
        {
            ChipsPanel.Children.Add(MakeChip(tag, _activeTags.Contains(tag), isTagChip: true));
        }
    }

    private Border MakeChip(string text, bool active, bool isTagChip)
    {
        var chip = new Border
        {
            CornerRadius = new CornerRadius(11),
            Padding = new Thickness(10, 3, 10, 3),
            Margin = new Thickness(0, 0, 6, 6),
            Cursor = Cursors.Hand,
            Background = new SolidColorBrush(active
                ? Color.FromRgb(0xEB, 0x96, 0x1E)
                : Color.FromRgb(0xFD, 0xF3, 0xE3)),
            BorderBrush = new SolidColorBrush(Color.FromRgb(0xEB, 0x96, 0x1E)),
            BorderThickness = new Thickness(1),
        };
        var label = new TextBlock
        {
            Text = text,
            FontSize = 12,
            Foreground = new SolidColorBrush(active ? Colors.White : Color.FromRgb(0x44, 0x44, 0x44)),
        };
        chip.Child = label;
        if (isTagChip)
        {
            chip.MouseLeftButtonUp += (_, _) =>
            {
                bool nowActive = _activeTags.Add(text) ? true : _activeTags.Remove(text) && false;
                chip.Background = new SolidColorBrush(nowActive
                    ? Color.FromRgb(0xEB, 0x96, 0x1E)
                    : Color.FromRgb(0xFD, 0xF3, 0xE3));
                label.Foreground = new SolidColorBrush(nowActive ? Colors.White : Color.FromRgb(0x44, 0x44, 0x44));
                ApplyFilter();
            };
        }
        return chip;
    }

    // ---- search roots --------------------------------------------------------------

    private void RebuildRootChips()
    {
        RootsPanel.Children.Clear();
        foreach (string root in _roots)
        {
            string captured = root;
            var chip = new Border
            {
                CornerRadius = new CornerRadius(7),
                Padding = new Thickness(8, 2, 6, 2),
                Margin = new Thickness(0, 0, 6, 4),
                Background = new SolidColorBrush(Color.FromRgb(0xF2, 0xF2, 0xEE)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(0xDD, 0xDD, 0xD6)),
                BorderThickness = new Thickness(1),
            };
            var row = new StackPanel { Orientation = Orientation.Horizontal };
            row.Children.Add(new TextBlock
            {
                Text = root, FontSize = 11.5, Foreground = new SolidColorBrush(Color.FromRgb(0x66, 0x66, 0x5E)),
                VerticalAlignment = VerticalAlignment.Center,
            });
            var remove = new TextBlock
            {
                Text = "×", FontSize = 12, Margin = new Thickness(6, 0, 0, 0), Cursor = Cursors.Hand,
                Foreground = new SolidColorBrush(Color.FromRgb(0xB0, 0x74, 0x17)),
                VerticalAlignment = VerticalAlignment.Center, ToolTip = "Stop searching this folder",
            };
            remove.MouseLeftButtonUp += (_, _) =>
            {
                _roots.RemoveAll(r => string.Equals(r, captured, StringComparison.OrdinalIgnoreCase));
                Settings.SaveRoots(_roots);
                RebuildRootChips();
                RefreshIndex();
            };
            row.Children.Add(remove);
            chip.Child = row;
            RootsPanel.Children.Add(chip);
        }
    }

    private void AddFolder_Click(object sender, RoutedEventArgs e)
    {
        using var dlg = new WinForms.FolderBrowserDialog
        {
            Description = "Choose a folder to search for FileLore notes",
            UseDescriptionForTitle = true,
        };
        if (dlg.ShowDialog() != WinForms.DialogResult.OK) return;
        if (_roots.Any(r => string.Equals(r, dlg.SelectedPath, StringComparison.OrdinalIgnoreCase))) return;
        _roots.Add(dlg.SelectedPath);
        Settings.SaveRoots(_roots);
        RebuildRootChips();
        RefreshIndex();
    }

    // ---- opening results ------------------------------------------------------------

    private void OpenSelectedOrFirst()
    {
        var row = Results.SelectedItem as ResultRow
            ?? (Results.ItemsSource as List<ResultRow>)?.FirstOrDefault();
        if (row is null) return;
        ((App)Application.Current).OpenEditor(row.Path);
    }

    private void Results_MouseDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (Results.SelectedItem is ResultRow) OpenSelectedOrFirst();
    }

    private void Results_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            OpenSelectedOrFirst();
            e.Handled = true;
        }
    }

    private void SearchBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            OpenSelectedOrFirst();
            e.Handled = true;
        }
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        SearchHint.Visibility = string.IsNullOrEmpty(SearchBox.Text) ? Visibility.Visible : Visibility.Collapsed;
        ApplyFilter();
    }
}
