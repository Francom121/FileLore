@echo off
REM ============================================================
REM  FileLore — enable Explorer badges (ONE-TIME, needs admin)
REM
REM  Registers FileLoreOverlay.dll as an IShellIconOverlayIdentifier
REM  so noted files show a small FileLore badge in Explorer.
REM  The overlay-handler enumeration key is HKLM-only — this is the
REM  ONE FileLore step that requires admin rights.
REM
REM  Usually launched from the app: Settings > "Show badges in
REM  Explorer". Safe to re-run.
REM ============================================================
setlocal EnableExtensions

set "DLL=%~dp0FileLoreOverlay.dll"
set "CLSID={7F3C1A2E-9B4D-4E5F-A6C7-1D2E3F4A5B6C}"
REM  ONE LEADING SPACE in the key name below is deliberate — the
REM  alphabetical-priority convention (OneDrive does the same) so the
REM  badge survives the system-wide ~15 overlay-handler limit.
set "OKEY=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\ShellIconOverlayIdentifiers\ FileLore"

echo.
echo   FileLore - enable Explorer badges
echo.

REM 0. Must be elevated (launched via UAC from the app, or by hand
REM    with "Run as administrator").
net session >nul 2>&1
if errorlevel 1 (
    echo   ERROR: this step needs admin rights.
    echo   Right-click Register-FileLoreOverlay.cmd -^> Run as administrator,
    echo   or use the "Show badges in Explorer" button in FileLore Settings.
    goto :fail
)

if not exist "%DLL%" (
    echo   ERROR: FileLoreOverlay.dll not found next to this script:
    echo          %DLL%
    goto :fail
)

REM 1. COM registration (HKLM\SOFTWARE\Classes\CLSID\...).
call :regset "HKLM\SOFTWARE\Classes\CLSID\%CLSID%" "" "FileLore icon overlay" "CLSID label"
call :regset "HKLM\SOFTWARE\Classes\CLSID\%CLSID%\InprocServer32" "" "%DLL%" "InprocServer32 path"
call :regset "HKLM\SOFTWARE\Classes\CLSID\%CLSID%\InprocServer32" "ThreadingModel" "Apartment" "Threading model"

REM 2. The overlay-handler enumeration key (" FileLore" — leading space!).
call :regset "%OKEY%" "" "%CLSID%" "Overlay handler key (HKLM ...\ShellIconOverlayIdentifiers\ FileLore)"

REM 3. Tell the shell associations changed so the new handler is picked up.
powershell -NoProfile -Command "Add-Type -MemberDefinition '[System.Runtime.InteropServices.DllImport(\"shell32.dll\")] public static extern void SHChangeNotify(int wEventId, uint uFlags, System.IntPtr i1, System.IntPtr i2);' -Name Sh -Namespace Fl; [Fl.Sh]::SHChangeNotify(0x08000000, 0, [System.IntPtr]::Zero, [System.IntPtr]::Zero)" >nul 2>&1

echo.
echo   Badge handler registered for:
echo     %DLL%
echo.
set "RST=Y"
if /i "%~1"=="/q" set "RST=n"
if /i not "%~1"=="/q" set /p "RST=  Restart Explorer now so badges show up? [Y/n] "
if /i "%RST%"=="n" (
    echo   Skipped - badges appear after you restart Explorer or sign out/in.
) else (
    echo   Restarting Explorer ^(taskbar flashes for a second^)...
    taskkill /f /im explorer.exe >nul 2>&1
    start "" explorer.exe
    echo   [OK] Explorer restarted
)
echo.
echo   Done. Files with a FileLore note now show a small badge in Explorer.
echo.
if /i not "%~1"=="/q" pause
endlocal
exit /b 0

:regset
if "%~2"=="" (
    reg add "%~1" /ve /d "%~3" /f >nul 2>&1
) else (
    reg add "%~1" /v "%~2" /d "%~3" /f >nul 2>&1
)
if errorlevel 1 goto :regset_fail
echo   [OK] %~4
exit /b 0
:regset_fail
echo   [FAIL] %~4  -^>  %~1
goto :fail

:fail
echo.
echo   Registration FAILED - see the messages above.
if /i not "%~1"=="/q" pause
endlocal
exit /b 1
