@echo off
REM ============================================================
REM  FileLore — disable Explorer badges (needs admin)
REM
REM  Removes the HKLM overlay-handler registration written by
REM  Register-FileLoreOverlay.cmd and restarts Explorer so the DLL
REM  is unloaded (Explorer keeps it mapped while running).
REM
REM  Called from FileLore Settings, and by Uninstall-FileLore.cmd
REM  when badges were enabled.
REM ============================================================
setlocal EnableExtensions

set "CLSID={7F3C1A2E-9B4D-4E5F-A6C7-1D2E3F4A5B6C}"
set "OKEY=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers\ FileLore"

echo.
echo   FileLore - disable Explorer badges
echo.

net session >nul 2>&1
if errorlevel 1 (
    echo   ERROR: this step needs admin rights.
    echo   Right-click Unregister-FileLoreOverlay.cmd -^> Run as administrator.
    goto :fail
)

reg delete "%OKEY%" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Classes\CLSID\%CLSID%\InprocServer32" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Classes\CLSID\%CLSID%" /f >nul 2>&1
echo   [OK] Overlay registration removed

powershell -NoProfile -Command "Add-Type -MemberDefinition '[System.Runtime.InteropServices.DllImport(\"shell32.dll\")] public static extern void SHChangeNotify(int wEventId, uint uFlags, System.IntPtr i1, System.IntPtr i2);' -Name Sh -Namespace Fl; [Fl.Sh]::SHChangeNotify(0x08000000, 0, [System.IntPtr]::Zero, [System.IntPtr]::Zero)" >nul 2>&1

echo   Restarting Explorer to unload the badge DLL...
taskkill /f /im explorer.exe >nul 2>&1
start "" explorer.exe
echo.
echo   Done - Explorer badges are off. The DLL file itself is removed
echo   by the app installer/uninstaller; your notes are untouched.
echo.
if /i not "%~1"=="/q" pause
endlocal
exit /b 0

:fail
echo.
echo   Unregister FAILED - see the messages above.
if /i not "%~1"=="/q" pause
endlocal
exit /b 1
