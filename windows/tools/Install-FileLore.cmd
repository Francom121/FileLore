@echo off
REM ============================================================
REM  FileLore per-user installer (Windows 10/11, x64)
REM  No admin rights needed: everything goes under %LOCALAPPDATA%
REM  and HKCU. Usage:
REM    Install-FileLore.cmd       interactive (pauses at the end)
REM    Install-FileLore.cmd /q    scripted (no pause)
REM
REM  VERSION: keep "0.5.0" below in sync with AppVersion.cs
REM  (src/FileLore.App/AppVersion.cs) when cutting a new build.
REM ============================================================
setlocal EnableExtensions
set "QUIET=0"
if /i "%~1"=="/q" set "QUIET=1"
set "FAILED=0"

set "SRC=%~dp0FileLore.exe"
set "DEST=%LOCALAPPDATA%\FileLore"
set "EXE=%DEST%\FileLore.exe"

echo.
echo   FileLore - sticky notes for your files
echo   Installing FileLore 0.5.0 for %USERNAME% ^(no admin needed^)...
echo.

if not exist "%SRC%" (
    echo   ERROR: FileLore.exe not found next to this script:
    echo          %SRC%
    echo   Unzip the whole download first, then run again.
    goto :fail
)

REM 0. Detect an existing install and say which build is being replaced.
set "OLDDATE="
set "NEWDATE="
if exist "%EXE%" (
    for %%I in ("%EXE%") do set "OLDDATE=%%~tI"
    for %%I in ("%SRC%") do set "NEWDATE=%%~tI"
)
if defined OLDDATE (
    echo   Existing install found:
    echo     OLD build: %OLDDATE%
    echo     NEW build: %NEWDATE%
    echo   Replacing build from %OLDDATE% - notes and settings are kept.
    echo.
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
call :regset "HKCU\Software\Classes\*\shell\FileLore" "" "FileLore Note" "Right-click verb label (FileLore Note)"
call :regset "HKCU\Software\Classes\*\shell\FileLore" "Icon" "\"%EXE%\"" "Right-click verb icon"
call :regset "HKCU\Software\Classes\*\shell\FileLore\command" "" "\"%EXE%\" \"%%%%1\"" "Right-click verb command"

REM 4. Autostart the tray (hotkeys Ctrl+Alt+T / Ctrl+Alt+F live there).
call :regset "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" "FileLore" "\"%EXE%\" --tray" "Tray autostart (Run key)"

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
if "%FAILED%"=="1" (
    echo   WARNING: one or more registry entries failed verification
    echo            ^(see [FAIL] lines above^). The app is installed, but
    echo            the right-click menu entry may be missing.
    echo            Re-run this installer, or run FileLore-Diagnose.cmd
    echo            and share the report it writes to your Desktop.
) else (
    echo   Done! Try it: right-click any file -^> Show more options -^> FileLore Note.
    echo   Hotkeys: Ctrl+Alt+T = note for selected file, Ctrl+Alt+F = search notes.
)
echo.
echo   NOTE: the FIRST launch can take up to a minute (one-time
echo         self-extraction + Windows scan). Later launches are fast.
echo.
echo   Updating from an older version? You're already done - this script
echo   replaced the old app; your notes and settings were kept.
echo   To remove FileLore later, run Uninstall-FileLore.cmd
echo.

REM 7. Explorer caches shell verbs; a restart makes the new entry appear
REM    without signing out.
if "%QUIET%"=="1" (
    echo   NOTE: restart Explorer or sign out/in if FileLore Note isn't
    echo         in the right-click menu.
) else (
    set "RST=Y"
    set /p "RST=  Restart Explorer now so the menu entry shows up? [Y/n] "
    if /i "%RST%"=="n" (
        echo   Skipped - restart Explorer or sign out/in if FileLore Note
        echo   isn't in the right-click menu.
    ) else (
        echo   Restarting Explorer ^(taskbar flashes for a second^)...
        taskkill /f /im explorer.exe >nul 2>&1
        start "" explorer.exe
        echo   [OK] Explorer restarted
    )
)
echo.
set "RC=0"
if "%FAILED%"=="1" set "RC=1"
if "%QUIET%"=="0" pause
endlocal & exit /b %RC%

REM ------------------------------------------------------------
REM  :regset  - write one registry value, then READ IT BACK.
REM  %1 = key, %2 = value name (empty = default value),
REM  %3 = data, %4 = human label for the [OK]/[FAIL] line.
REM ------------------------------------------------------------
:regset
if "%~2"=="" (
    reg add "%~1" /ve /d "%~3" /f >nul 2>&1
) else (
    reg add "%~1" /v "%~2" /d "%~3" /f >nul 2>&1
)
if errorlevel 1 goto :regset_fail
if "%~2"=="" (
    reg query "%~1" /ve >nul 2>&1
) else (
    reg query "%~1" /v "%~2" >nul 2>&1
)
if errorlevel 1 goto :regset_fail
echo   [OK] %~4
exit /b 0
:regset_fail
if "%~2"=="" (
    echo   [FAIL] %~4  -^>  %~1 ^(default^)
) else (
    echo   [FAIL] %~4  -^>  %~1 \ %~2
)
set "FAILED=1"
exit /b 1

:fail
echo.
echo   Install FAILED - see the messages above.
if "%QUIET%"=="0" pause
endlocal
exit /b 1
