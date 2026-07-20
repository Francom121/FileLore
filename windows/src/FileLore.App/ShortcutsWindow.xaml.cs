using System.Windows;

namespace FileLore.App;

/// <summary>
/// Keyboard Shortcuts panel (tray → Keyboard Shortcuts…): every shortcut
/// and interaction in the app, with the global-hotkey rows read from the
/// CURRENT bindings (so a rebind is reflected immediately).
/// </summary>
public partial class ShortcutsWindow : Window
{
    private sealed record Row(string Combo, string Description);

    public ShortcutsWindow()
    {
        InitializeComponent();
        var (open, search) = Settings.LoadHotkeys();
        List.ItemsSource = new[]
        {
            new Row(open.ToString(), "Note the file selected in Explorer (global)"),
            new Row(search.ToString(), "Search all notes (global)"),
            new Row("Ctrl+S", "Save the note (editor)"),
            new Row("Enter", "Add a tag (editor, tag field)"),
            new Row("Drag & drop", "Drop files onto the editor to link them; onto the drop zone for notes/batch"),
            new Row("Click / double-click", "Linked-file row opens the file with its default app"),
            new Row("Right-click tag chip", "Pin / unpin the tag (search window)"),
            new Row("Ctrl / Shift + click", "Multi-select search results, then Export… for one Markdown document"),
            new Row("Double-click result", "Open the note editor for that file (search window)"),
            new Row("Drop on shortcut", "Drop a file onto the Desktop shortcut to open its note"),
        };
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
