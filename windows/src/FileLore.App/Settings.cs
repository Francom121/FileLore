using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace FileLore.App;

/// <summary>A named note template persisted in settings.json.</summary>
public sealed class NoteTemplate
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("body")]
    public string Body { get; set; } = "";
}

/// <summary>
/// A global-hotkey chord: Win32 modifier flags (MOD_ALT 0x1, MOD_CONTROL
/// 0x2, MOD_SHIFT 0x4, MOD_WIN 0x8) plus a virtual-key code. Serialized in
/// settings.json as a human-readable string like "Ctrl+Alt+T".
/// </summary>
public sealed class HotkeyCombo
{
    public uint Modifiers { get; set; }
    public uint Key { get; set; }

    public HotkeyCombo() { }
    public HotkeyCombo(uint modifiers, uint key) { Modifiers = modifiers; Key = key; }

    public const uint ModAlt = 0x0001;
    public const uint ModControl = 0x0002;
    public const uint ModShift = 0x0004;
    public const uint ModWin = 0x0008;

    public static HotkeyCombo DefaultOpenSelection => new(ModControl | ModAlt, 0x54); // Ctrl+Alt+T
    public static HotkeyCombo DefaultSearch => new(ModControl | ModAlt, 0x46);        // Ctrl+Alt+F

    public override string ToString() => Format(Modifiers, Key);

    public static string Format(uint modifiers, uint vk)
    {
        var parts = new List<string>();
        if ((modifiers & ModControl) != 0) parts.Add("Ctrl");
        if ((modifiers & ModAlt) != 0) parts.Add("Alt");
        if ((modifiers & ModShift) != 0) parts.Add("Shift");
        if ((modifiers & ModWin) != 0) parts.Add("Win");
        parts.Add(KeyName(vk));
        return string.Join("+", parts);
    }

    /// <summary>Display/parse name for a virtual-key code (letters, digits, F1–F24).</summary>
    public static string KeyName(uint vk)
    {
        if (vk is >= 0x41 and <= 0x5A) return ((char)vk).ToString();            // A–Z
        if (vk is >= 0x30 and <= 0x39) return ((char)vk).ToString();            // 0–9
        if (vk is >= 0x70 and <= 0x87) return $"F{vk - 0x70 + 1}";              // F1–F24
        return vk switch
        {
            0x20 => "Space", 0x0D => "Enter", 0x09 => "Tab", 0x1B => "Esc",
            0x2E => "Delete", 0x24 => "Home", 0x23 => "End",
            0x21 => "PageUp", 0x22 => "PageDown",
            0x25 => "Left", 0x26 => "Up", 0x27 => "Right", 0x28 => "Down",
            _ => $"0x{vk:X2}",
        };
    }

    /// <summary>Parses "Ctrl+Alt+T"-style strings; returns null when malformed.</summary>
    public static HotkeyCombo? Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var parts = text.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length < 2) return null;

        uint modifiers = 0;
        for (int i = 0; i < parts.Length - 1; i++)
        {
            switch (parts[i].ToLowerInvariant())
            {
                case "ctrl" or "control": modifiers |= ModControl; break;
                case "alt": modifiers |= ModAlt; break;
                case "shift": modifiers |= ModShift; break;
                case "win": modifiers |= ModWin; break;
                default: return null;
            }
        }

        string keyName = parts[^1];
        uint vk;
        if (keyName.Length == 1)
        {
            char c = char.ToUpperInvariant(keyName[0]);
            if (c is (>= 'A' and <= 'Z') or (>= '0' and <= '9')) vk = c;
            else return null;
        }
        else if (keyName.StartsWith('F') && int.TryParse(keyName[1..], out int f) && f is >= 1 and <= 24)
        {
            vk = (uint)(0x70 + f - 1);
        }
        else
        {
            vk = keyName.ToLowerInvariant() switch
            {
                "space" => 0x20, "enter" => 0x0D, "tab" => 0x09,
                "delete" => 0x2E, "home" => 0x24, "end" => 0x23,
                _ => 0,
            };
            if (vk == 0) return null;
        }
        if (modifiers == 0) return null;
        return new HotkeyCombo(modifiers, vk);
    }
}

/// <summary>
/// App-wide settings persisted as JSON at
/// %LOCALAPPDATA%\FileLore\settings.json: search roots, note templates,
/// pinned tags and the two global-hotkey bindings. Every Save* reads the
/// current file, mutates one field and writes it back, so unrelated fields
/// are preserved.
/// </summary>
public static class Settings
{
    private const string DefaultRoot = @"C:\FileLoreTest";

    private static string DirectoryPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FileLore");

    public static string StoragePath => Path.Combine(DirectoryPath, "settings.json");

    private sealed class SettingsData
    {
        [JsonPropertyName("roots")]
        public List<string>? Roots { get; set; }

        [JsonPropertyName("templates")]
        public List<NoteTemplate>? Templates { get; set; }

        [JsonPropertyName("pinnedTags")]
        public List<string>? PinnedTags { get; set; }

        [JsonPropertyName("hotkeyOpenSelection")]
        public string? HotkeyOpenSelection { get; set; }

        [JsonPropertyName("hotkeySearch")]
        public string? HotkeySearch { get; set; }
    }

    private static SettingsData LoadData()
    {
        try
        {
            if (File.Exists(StoragePath))
                return JsonSerializer.Deserialize<SettingsData>(File.ReadAllText(StoragePath)) ?? new SettingsData();
        }
        catch { /* malformed file → defaults */ }
        return new SettingsData();
    }

    private static void SaveData(Action<SettingsData> mutate)
    {
        var data = LoadData();
        mutate(data);
        Directory.CreateDirectory(DirectoryPath);
        File.WriteAllText(StoragePath,
            JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true }));
    }

    // ---- search roots ---------------------------------------------------------

    public static List<string> LoadRoots()
    {
        var roots = LoadData().Roots;
        if (roots is null) return new List<string> { DefaultRoot }; // key absent → default
        return roots.Where(r => !string.IsNullOrWhiteSpace(r)).ToList(); // saved list wins even when empty
    }

    public static void SaveRoots(IEnumerable<string> roots)
    {
        var clean = roots
            .Where(r => !string.IsNullOrWhiteSpace(r))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        SaveData(d => d.Roots = clean);
    }

    // ---- templates ------------------------------------------------------------

    /// <summary>The one template every install ships with; Mac templates are NOT synced.</summary>
    public static NoteTemplate DefaultTemplate => new()
    {
        Name = "AI Generation",
        Body = "Prompt:\n\nModel:\n\nVoice:\n\nLinks:\n",
    };

    public static List<NoteTemplate> LoadTemplates()
    {
        var templates = LoadData().Templates;
        if (templates is null) return new List<NoteTemplate> { DefaultTemplate };
        return templates.Where(t => !string.IsNullOrWhiteSpace(t.Name)).ToList();
    }

    public static void SaveTemplates(IEnumerable<NoteTemplate> templates)
    {
        var clean = templates
            .Where(t => !string.IsNullOrWhiteSpace(t.Name))
            .Select(t => new NoteTemplate { Name = t.Name.Trim(), Body = t.Body })
            .ToList();
        SaveData(d => d.Templates = clean);
    }

    // ---- pinned tags ------------------------------------------------------------

    public static List<string> LoadPinnedTags()
    {
        var pinned = LoadData().PinnedTags;
        if (pinned is null) return new List<string>();
        return pinned.Where(t => !string.IsNullOrWhiteSpace(t)).ToList();
    }

    public static void SavePinnedTags(IEnumerable<string> tags)
    {
        var clean = tags
            .Select(t => t.Trim())
            .Where(t => t.Length > 0)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        SaveData(d => d.PinnedTags = clean);
    }

    public static void PinTag(string tag)
    {
        var pinned = LoadPinnedTags();
        if (!pinned.Contains(tag, StringComparer.OrdinalIgnoreCase))
        {
            pinned.Add(tag.Trim());
            SavePinnedTags(pinned);
        }
    }

    public static void UnpinTag(string tag)
    {
        var pinned = LoadPinnedTags();
        pinned.RemoveAll(t => string.Equals(t, tag, StringComparison.OrdinalIgnoreCase));
        SavePinnedTags(pinned);
    }

    // ---- hotkeys ---------------------------------------------------------------

    public static (HotkeyCombo OpenSelection, HotkeyCombo Search) LoadHotkeys()
    {
        var data = LoadData();
        return (HotkeyCombo.Parse(data.HotkeyOpenSelection) ?? HotkeyCombo.DefaultOpenSelection,
                HotkeyCombo.Parse(data.HotkeySearch) ?? HotkeyCombo.DefaultSearch);
    }

    public static void SaveHotkeys(HotkeyCombo openSelection, HotkeyCombo search)
        => SaveData(d =>
        {
            d.HotkeyOpenSelection = openSelection.ToString();
            d.HotkeySearch = search.ToString();
        });
}
