# press-hotkey.ps1 — synthesizes a global-hotkey keystroke in the current
# interactive session. Used by milestone verification to fire FileLore's
# RegisterHotKey combos without physical keys.
# Usage: powershell -File press-hotkey.ps1 F   (or T)
param([Parameter(Mandatory=$true)][string]$Key)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class KeySynth {
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@

$VK_CONTROL = 0x11; $VK_MENU = 0x12  # Alt
$vk = [byte][char]$Key.ToUpperInvariant()
$KEYEVENTF_KEYUP = 0x2

[KeySynth]::keybd_event($VK_CONTROL, 0, 0, [UIntPtr]::Zero)
[KeySynth]::keybd_event($VK_MENU, 0, 0, [UIntPtr]::Zero)
[KeySynth]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 120
[KeySynth]::keybd_event($vk, 0, $KEYEVENTF_KEYUP, [UIntPtr]::Zero)
[KeySynth]::keybd_event($VK_MENU, 0, $KEYEVENTF_KEYUP, [UIntPtr]::Zero)
[KeySynth]::keybd_event($VK_CONTROL, 0, $KEYEVENTF_KEYUP, [UIntPtr]::Zero)
Write-Output "pressed Ctrl+Alt+$($Key.ToUpperInvariant())"
