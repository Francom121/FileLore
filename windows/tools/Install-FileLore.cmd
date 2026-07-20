@echo off
REM ============================================================
REM  FileLore per-user installer (Windows 10/11, x64)
REM  No admin rights needed: everything goes under %LOCALAPPDATA%
REM  and HKCU. Usage:
REM    Install-FileLore.cmd       interactive (pauses at the end)
REM    Install-FileLore.cmd /q    scripted (no pause)
REM ============================================================
setlocal EnableExtensions
set "QUIET=0"
if /i "%~1"=="/q" set "QUIET=1"

set "SRC=%~dp0FileLore.exe"
set "DEST=%LOCALAPPDATA%\FileLore"
set "EXE=%DEST%\FileLore.exe"

echo.
echo   FileLore - sticky notes for your files
echo   Installing for %USERNAME% ^(no admin needed^)...
echo.

if not exist "%SRC%" (
    echo   ERROR: FileLore.exe not found next to this script:
    echo          %SRC%
    echo   Unzip the whole download first, then run again.
    goto :fail
)

REM 1. Stop a running per-user copy (upgrade case). Any other copy
REM    of FileLore.exe on this PC is left alone.
powershell -NoProfile -Command "$t=$env:LOCALAPPDATA+'\FileLore\FileLore.exe'; Get-Process FileLore -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $t } | Stop-Process -Force" >nul 2>&1

REM 2. Copy the app.
if not exist "%DEST%" mkdir "%DEST%"
copy /y "%SRC%" "%EXE%" >nul
if errorlevel 1 (
    echo   ERROR: could not copy FileLore.exe to %DEST%
    goto :fail
)
echo   [OK] App copied to %EXE%

REM 3. Right-click verb "FileLore Note" for every file.
reg add "HKCU\Software\Classes\*\shell\FileLore" /ve /d "FileLore Note" /f >nul
reg add "HKCU\Software\Classes\*\shell\FileLore" /v Icon /d "\"%EXE%\"" /f >nul
reg add "HKCU\Software\Classes\*\shell\FileLore\command" /ve /d "\"%EXE%\" \"%%1\"" /f >nul
if errorlevel 1 (
    echo   ERROR: registry write failed.
    goto :fail
)
echo   [OK] Right-click verb "FileLore Note" registered

REM 4. Autostart the tray (hotkeys Ctrl+Alt+T / Ctrl+Alt+F live there).
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v FileLore /d "\"%EXE%\" --tray" /f >nul
if errorlevel 1 (
    echo   ERROR: autostart registration failed.
    goto :fail
)
echo   [OK] Tray autostart registered (Ctrl+Alt+T / Ctrl+Alt+F)

REM 5. Desktop + Start Menu shortcuts.
powershell -NoProfile -Command "$ws=New-Object -ComObject WScript.Shell; $exe=$env:LOCALAPPDATA+'\FileLore\FileLore.exe'; $l1=$env:USERPROFILE+'\Desktop\FileLore.lnk'; $l2=$env:APPDATA+'\Microsoft\Windows\Start Menu\Programs\FileLore.lnk'; foreach($lnk in @($l1, $l2)){ $s=$ws.CreateShortcut($lnk); $s.TargetPath=$exe; $s.WorkingDirectory=Split-Path $exe; $s.IconLocation=$exe+',0'; $s.Description='FileLore - sticky notes for your files'; $s.Save() }" >nul
if errorlevel 1 (
    echo   [WARN] Shortcut creation failed - the app still works
    echo          from the right-click menu.
) else (
    echo   [OK] Desktop + Start Menu shortcuts created
)

REM 6. Start the tray now so the hotkeys work immediately.
start "" "%EXE%" --tray

echo.
echo   Done! Try it: right-click any file -^> Show more options -^> FileLore Note.
echo   Hotkeys: Ctrl+Alt+T = note for selected file, Ctrl+Alt+F = search notes.
echo.
echo   NOTE: the FIRST launch can take up to a minute (one-time
echo         self-extraction + Windows scan). Later launches are fast.
echo.
echo   Updating from an older version? You're already done - this script
echo   replaced the old app; your notes and settings were kept.
echo   To remove FileLore later, run Uninstall-FileLore.cmd
echo.
if "%QUIET%"=="0" pause
endlocal
exit /b 0

:fail
echo.
echo   Install FAILED - see the messages above.
if "%QUIET%"=="0" pause
endlocal
exit /b 1
