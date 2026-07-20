# select-explorer-item.ps1 — opens a folder in Explorer (Shell COM), forces
# that window foreground, and selects one item in it, as the current
# interactive user. Used by milestone verification to set up the Ctrl+Alt+T
# "current Explorer selection" path. The script's own task console grants it
# foreground rights long enough to hand focus to Explorer.
# Usage: powershell -File select-explorer-item.ps1 C:\FileLoreTest clip.mp4
param(
    [Parameter(Mandatory=$true)][string]$Folder,
    [Parameter(Mandatory=$true)][string]$ItemName
)

$log = "$env:LOCALAPPDATA\FileLore\select.log"
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WinSel {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@

$shell = New-Object -ComObject Shell.Application
$shell.Open($Folder)
Start-Sleep -Seconds 2

$window = $shell.Windows() | Where-Object {
    try { $_.Document.Folder.Self.Path -eq $Folder } catch { $false }
} | Select-Object -First 1
if ($null -eq $window) { "ERROR: no Explorer window for $Folder" | Out-File $log; exit 1 }

$h = [IntPtr]([long]$window.HWND)
[WinSel]::ShowWindow($h, 9) | Out-Null        # SW_RESTORE
[WinSel]::BringWindowToTop($h) | Out-Null
[WinSel]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 600

$item = $window.Document.Folder.ParseName($ItemName)
if ($null -eq $item) { "ERROR: $ItemName not found in $Folder" | Out-File $log; exit 1 }

# SVSI_SELECT | SVSI_DESELECTOTHERS | SVSI_ENSUREVISIBLE
$window.Document.SelectItem($item, 0x1 -bor 0x4 -bor 0x8)
Start-Sleep -Milliseconds 600

$selCount = $window.Document.SelectedItems().Count
$fg = [WinSel]::GetForegroundWindow()
"selected $selCount item(s) in $Folder; explorerHwnd=$h foregroundHwnd=$fg" | Out-File $log
