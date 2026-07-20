using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using FileLore.Core;

namespace FileLore.App;

/// <summary>
/// The batch window: many files (from Explorer multi-select, the drop zone
/// or Browse…), one note body (Set / Append) and one tag list (Add /
/// Replace), applied per file via <see cref="BatchNoteService"/> with a
/// per-file result line and a summary ("5 notes updated, 1 skipped
/// (network path)").
/// </summary>
public partial class BatchWindow : Window
{
    private sealed record FileRow(string Path, bool Supported, string Reason);

    private readonly List<FileRow> _rows;

    public BatchWindow(IReadOnlyList<string> paths)
    {
        InitializeComponent();
        _rows = paths
            .Where(File.Exists)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Select(p =>
            {
                var (ok, reason) = NoteStore.IsSupportedPath(p);
                return new FileRow(p, ok, reason);
            })
            .ToList();

        HeaderText.Text = $"Batch notes — {_rows.Count} files";
        FileList.ItemsSource = _rows.Select(r => new
        {
            Mark = r.Supported ? "✓" : "⚠",
            MarkColor = r.Supported
                ? new SolidColorBrush(Color.FromRgb(0x2E, 0x7D, 0x32))
                : new SolidColorBrush(Color.FromRgb(0xC0, 0x39, 0x2B)),
            Name = Path.GetFileName(r.Path),
            Folder = r.Supported ? (Path.GetDirectoryName(r.Path) ?? "") : r.Reason,
        }).ToList();
    }

    private async void Apply_Click(object sender, RoutedEventArgs e)
    {
        string? body = string.IsNullOrWhiteSpace(BodyBox.Text) ? null : BodyBox.Text;
        var bodyMode = BodySet.IsChecked == true ? BatchBodyMode.Set : BatchBodyMode.Append;
        var tags = TagsBox.Text
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var tagMode = TagsAdd.IsChecked == true ? BatchTagMode.Add : BatchTagMode.Replace;

        if (body is null && tags.Length == 0)
        {
            SummaryText.Text = "Nothing to apply — write a body and/or tags first.";
            return;
        }

        ApplyBtn.IsEnabled = false;
        ResultsPanel.Children.Clear();
        SummaryText.Text = "Applying…";

        var paths = _rows.Select(r => r.Path).ToList();
        var results = await Task.Run(() => BatchNoteService.Apply(
            paths, body, bodyMode, tags, tagMode,
            onFileDone: result => Dispatcher.BeginInvoke(() => AddResultLine(result))));

        SummaryText.Text = BatchNoteService.Summarize(results);
        ApplyBtn.IsEnabled = true;
    }

    private void AddResultLine(BatchFileResult result)
    {
        var line = new TextBlock { FontSize = 12, Margin = new Thickness(0, 2, 0, 2), TextWrapping = TextWrapping.Wrap };
        if (result.Succeeded)
        {
            line.Text = $"✓  {Path.GetFileName(result.Path)}";
            line.Foreground = new SolidColorBrush(Color.FromRgb(0x2E, 0x7D, 0x32));
        }
        else if (result.Skipped)
        {
            line.Text = $"⚠  {Path.GetFileName(result.Path)} — skipped: {result.Reason}";
            line.Foreground = new SolidColorBrush(Color.FromRgb(0xB0, 0x74, 0x17));
        }
        else
        {
            line.Text = $"✗  {Path.GetFileName(result.Path)} — {result.Reason}";
            line.Foreground = new SolidColorBrush(Color.FromRgb(0xC0, 0x39, 0x2B));
        }
        ResultsPanel.Children.Add(line);
    }
}
