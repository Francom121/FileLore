# bring-front.ps1 — restores and foregrounds FileLore's main window.
# Run inside the interactive session (schtasks /ru fm /it).
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WinFocus {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
}
"@
$p = Get-Process FileLore -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($null -eq $p) { Write-Output "no FileLore window"; exit 1 }
$h = $p.MainWindowHandle
[WinFocus]::ShowWindow($h, 9) | Out-Null   # SW_RESTORE
Start-Sleep -Milliseconds 300
[WinFocus]::BringWindowToTop($h) | Out-Null
[WinFocus]::SetForegroundWindow($h) | Out-Null
Write-Output "fronted '$($p.MainWindowTitle)' ($h)"
