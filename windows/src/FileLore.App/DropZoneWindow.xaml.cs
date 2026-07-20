using System.IO;
using System.Windows;
using System.Windows.Media;
using WinForms = System.Windows.Forms;

namespace FileLore.App;

/// <summary>
/// The drop zone (tray → "New note / batch…"): a dashed drop target. One
/// file dropped opens the note editor; several files open the batch window.
/// A Browse… button offers the same split from a file picker.
/// </summary>
public partial class DropZoneWindow : Window
{
    public DropZoneWindow()
    {
        InitializeComponent();
    }

    private void Zone_DragEnter(object sender, System.Windows.DragEventArgs e) => Highlight(true);
    private void Zone_DragLeave(object sender, System.Windows.DragEventArgs e) => Highlight(false);

    private void Highlight(bool on)
    {
        Dash.Stroke = new SolidColorBrush(on ? Color.FromRgb(0xC5, 0x77, 0x0A) : Color.FromRgb(0xEB, 0x96, 0x1E));
        DropText.Text = on ? "Let go!" : "Drop files here";
    }

    private void Zone_DragOver(object sender, System.Windows.DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(System.Windows.DataFormats.FileDrop)
            ? System.Windows.DragDropEffects.Copy
            : System.Windows.DragDropEffects.None;
        e.Handled = true;
    }

    private void Zone_Drop(object sender, System.Windows.DragEventArgs e)
    {
        Highlight(false);
        if (e.Data.GetData(System.Windows.DataFormats.FileDrop) is string[] paths)
            Route(paths.Where(File.Exists).ToList());
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        using var dlg = new WinForms.OpenFileDialog
        {
            Title = "Choose files to note",
            Filter = "All files (*.*)|*.*",
            CheckFileExists = true,
            Multiselect = true,
        };
        if (dlg.ShowDialog() == WinForms.DialogResult.OK)
            Route(dlg.FileNames);
    }

    private void Route(IReadOnlyList<string> paths)
    {
        if (paths.Count == 0) return;
        var app = (App)Application.Current;
        if (paths.Count == 1) app.OpenEditor(paths[0]);
        else app.OpenBatch(paths);
        Close();
    }
}
