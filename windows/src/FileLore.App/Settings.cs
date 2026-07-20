using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace FileLore.App;

/// <summary>
/// App-wide settings persisted as JSON at
/// %LOCALAPPDATA%\FileLore\settings.json. Currently just the search roots —
/// folders the search window walks for noted files. The default root is
/// C:\FileLoreTest (the VM test directory) so a fresh install has somewhere
/// sensible to look.
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
        public List<string> Roots { get; set; } = new();
    }

    public static List<string> LoadRoots()
    {
        try
        {
            if (!File.Exists(StoragePath))
                return new List<string> { DefaultRoot };
            var data = JsonSerializer.Deserialize<SettingsData>(File.ReadAllText(StoragePath));
            if (data?.Roots is { } roots) // a saved list wins even when empty (user removed all)
                return roots.Where(r => !string.IsNullOrWhiteSpace(r)).ToList();
        }
        catch { /* malformed file → default */ }
        return new List<string> { DefaultRoot };
    }

    public static void SaveRoots(IEnumerable<string> roots)
    {
        var data = new SettingsData
        {
            Roots = roots
                .Where(r => !string.IsNullOrWhiteSpace(r))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList(),
        };
        Directory.CreateDirectory(DirectoryPath);
        File.WriteAllText(StoragePath,
            JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true }));
    }
}
