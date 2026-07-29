namespace FileLore.App;

/// <summary>
/// Single source of truth for the human-visible version string. BUMP HERE
/// (and &lt;Version&gt; in FileLore.App.csproj, which stamps the exe's file
/// properties) when cutting a new build — see the "For developers" section
/// of windows/README.md.
///
/// Shown in the tray menu (bottom, above Exit), printed by
/// <c>FileLore.exe --version</c>, and echoed by Install-FileLore.cmd, so
/// "which build are you running?" is answerable on any machine.
/// </summary>
internal static class AppVersion
{
    /// <summary>Semantic version. Keep in sync with the csproj &lt;Version&gt;.</summary>
    public const string Number = "0.8.0";

    /// <summary>Build date stamp (yyyy-MM-dd) of the release this source produced.</summary>
    public const string BuildDate = "2026-07-28";

    /// <summary>Short label, e.g. "FileLore 0.6.0" (tray menu, installer echo).</summary>
    public const string Display = "FileLore " + Number;

    /// <summary>Full label with build date, e.g. "FileLore 0.6.0 (build 2026-07-21)".</summary>
    public const string Full = Display + " (build " + BuildDate + ")";
}
