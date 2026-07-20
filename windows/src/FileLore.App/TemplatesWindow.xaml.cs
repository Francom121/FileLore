using System.Windows;
using System.Windows.Controls;

namespace FileLore.App;

/// <summary>
/// Manage Templates dialog (editor dropdown → "Manage templates…", or tray
/// → Settings). Add / edit / delete named templates; every change is
/// persisted immediately to settings.json.
/// </summary>
public partial class TemplatesWindow : Window
{
    private readonly List<NoteTemplate> _templates;

    public TemplatesWindow()
    {
        InitializeComponent();
        _templates = Settings.LoadTemplates();
        RebuildList(selectIndex: _templates.Count > 0 ? 0 : -1);
    }

    private void RebuildList(int selectIndex)
    {
        TemplateList.Items.Clear();
        foreach (var t in _templates)
            TemplateList.Items.Add(t.Name);
        if (selectIndex >= 0 && selectIndex < TemplateList.Items.Count)
            TemplateList.SelectedIndex = selectIndex;
        else
            ClearEditor();
    }

    private void ClearEditor()
    {
        NameBox.Text = "";
        BodyBoxEdit.Text = "";
    }

    private int SelectedIndexOf(string name)
        => _templates.FindIndex(t => string.Equals(t.Name, name, StringComparison.Ordinal));

    private void TemplateList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (TemplateList.SelectedIndex < 0 || TemplateList.SelectedIndex >= _templates.Count)
        {
            ClearEditor();
            return;
        }
        var t = _templates[TemplateList.SelectedIndex];
        NameBox.Text = t.Name;
        BodyBoxEdit.Text = t.Body;
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        string name = NameBox.Text.Trim();
        if (name.Length == 0) return;

        int existing = TemplateList.SelectedIndex;
        if (existing >= 0 && existing < _templates.Count)
        {
            // Rename-safe update: if the name changed, drop any other entry with that name.
            int clash = SelectedIndexOf(name);
            if (clash >= 0 && clash != existing) _templates.RemoveAt(clash);
            if (clash >= 0 && clash < existing) existing--;
            _templates[existing] = new NoteTemplate { Name = name, Body = BodyBoxEdit.Text };
        }
        else
        {
            int clash = SelectedIndexOf(name);
            if (clash >= 0) _templates[clash] = new NoteTemplate { Name = name, Body = BodyBoxEdit.Text };
            else _templates.Add(new NoteTemplate { Name = name, Body = BodyBoxEdit.Text });
            existing = SelectedIndexOf(name);
        }

        Settings.SaveTemplates(_templates);
        RebuildList(existing);
    }

    private void New_Click(object sender, RoutedEventArgs e)
    {
        string baseName = "New template";
        string name = baseName;
        int n = 2;
        while (SelectedIndexOf(name) >= 0) name = $"{baseName} {n++}";
        _templates.Add(new NoteTemplate { Name = name, Body = "" });
        Settings.SaveTemplates(_templates);
        RebuildList(_templates.Count - 1);
        NameBox.Focus();
        NameBox.SelectAll();
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        int existing = TemplateList.SelectedIndex;
        if (existing < 0 || existing >= _templates.Count) return;
        _templates.RemoveAt(existing);
        Settings.SaveTemplates(_templates);
        RebuildList(Math.Min(existing, _templates.Count - 1));
    }
}
