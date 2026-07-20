# check-windows.ps1 — writes the FileLore process's window state to
# C:\winstate.txt. Run inside the interactive session (schtasks /ru fm /it).
$out = "C:\Users\fm\AppData\Local\FileLore\winstate.txt"
"" | Out-File $out
try {
    Get-Process FileLore -ErrorAction Stop |
        Select-Object Id, MainWindowHandle, MainWindowTitle |
        Format-Table -AutoSize | Out-File -Append $out
} catch {
    "Get-Process FileLore failed: $_" | Out-File -Append $out
}
"--- desktop windows titled *FileLore* ---" | Out-File -Append $out
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public static class WinEnum {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    public static List<string> Titles() {
        var r = new List<string>();
        EnumWindows((h, l) => {
            if (!IsWindowVisible(h)) return true;
            var sb = new StringBuilder(256);
            GetWindowText(h, sb, 256);
            if (sb.Length > 0) r.Add(sb.ToString());
            return true;
        }, IntPtr.Zero);
        return r;
    }
}
"@
[WinEnum]::Titles() | Where-Object { $_ -like "*FileLore*" } | Out-File -Append $out
