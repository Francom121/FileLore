# install-shortcuts.ps1 — creates Desktop + Start Menu shortcuts for FileLore.
# Run as SYSTEM or an elevated user: both targets are machine-wide locations
# (C:\Users\Public\Desktop and C:\ProgramData\...\Start Menu\Programs).
$ErrorActionPreference = "Stop"

$exe = "C:\FileLore\FileLore.exe"
if (-not (Test-Path $exe)) { throw "FileLore.exe not found at $exe" }

$ws = New-Object -ComObject WScript.Shell
$targets = @(
    "C:\Users\Public\Desktop\FileLore.lnk",
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\FileLore.lnk"
)

foreach ($lnk in $targets) {
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = $exe
    $s.WorkingDirectory = "C:\FileLore"
    $s.IconLocation = "$exe,0"
    $s.Description = "FileLore - sticky notes for your files"
    $s.Save()
    Write-Output "OK: $lnk"
}
