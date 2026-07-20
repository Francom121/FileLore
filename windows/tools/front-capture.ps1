# front-capture.ps1 — raises FileLore's main window above everything
# (including this task's own console window) and screenshots the desktop to
# C:\Users\fm\AppData\Local\FileLore\screen.png. Run inside the interactive
# session (schtasks /ru fm /it).
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WinFocus2 {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
}
"@
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$p = Get-Process FileLore -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($null -ne $p) {
    $h = $p.MainWindowHandle
    [WinFocus2]::ShowWindow($h, 9) | Out-Null  # SW_RESTORE
    [WinFocus2]::MoveWindow($h, 80, 50, 740, 660, $true) | Out-Null
    Start-Sleep -Milliseconds 500
    [WinFocus2]::BringWindowToTop($h) | Out-Null
    [WinFocus2]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 700
}

$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$out = "C:\Users\fm\AppData\Local\FileLore\screen.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output "saved $out; front window: $($p.MainWindowTitle)"
