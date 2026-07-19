using System.IO;
using System.Text.Json;

namespace FileLore.App;

/// <summary>
/// Most-recently-noted files, newest first, capped at 10. Persisted as JSON
/// at %LOCALAPPDATA%\FileLore\recents.json — a per-user store, so each
/// Windows account keeps its own list.
/// </summary>
public static class Recents
{
    private const int MaxEntries = 10;

    private static string DirectoryPath =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FileLore");

    public static string StoragePath => Path.Combine(DirectoryPath, "recents.json");

    public static List<string> Load()
    {
        try
        {
            return JsonSerializer.Deserialize<List<string>>(File.ReadAllText(StoragePath)) ?? new List<string>();
        }
        catch
        {
            return new List<string>(); // missing or malformed file → empty list
        }
    }

    public static void Add(string path)
    {
        var list = Load();
        list.RemoveAll(p => string.Equals(p, path, StringComparison.OrdinalIgnoreCase));
        list.Insert(0, path);
        if (list.Count > MaxEntries)
            list.RemoveRange(MaxEntries, list.Count - MaxEntries);

        Directory.CreateDirectory(DirectoryPath);
        File.WriteAllText(StoragePath, JsonSerializer.Serialize(list, new JsonSerializerOptions { WriteIndented = true }));
    }
}
