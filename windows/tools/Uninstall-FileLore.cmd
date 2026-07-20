@echo off
REM ============================================================
REM  FileLore per-user uninstaller
REM  Removes the app, the right-click verb, autostart and
REM  shortcuts. Asks before deleting your tiny settings files.
REM    Uninstall-FileLore.cmd       interactive
REM    Uninstall-FileLore.cmd /q    scripted (no pause, keeps data)
REM ============================================================
setlocal EnableExtensions
set "QUIET=0"
if /i "%~1"=="/q" set "QUIET=1"

set "DEST=%LOCALAPPDATA%\FileLore"
set "EXE=%DEST%\FileLore.exe"

echo.
echo   FileLore uninstaller
echo.

REM 1. Stop the running per-user copy only (never other installs).
powershell -NoProfile -Command "$t=$env:LOCALAPPDATA+'\FileLore\FileLore.exe'; Get-Process FileLore -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $t } | Stop-Process -Force" >nul 2>&1
echo   [OK] App stopped

REM 2. Remove the right-click verb and the autostart entry.
reg delete "HKCU\Software\Classes\*\shell\FileLore" /f >nul 2>&1
reg delete "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v FileLore /f >nul 2>&1
echo   [OK] Right-click verb + autostart removed

REM 3. Remove shortcuts.
del /f /q "%USERPROFILE%\Desktop\FileLore.lnk" >nul 2>&1
del /f /q "%APPDATA%\Microsoft\Windows\Start Menu\Programs\FileLore.lnk" >nul 2>&1
echo   [OK] Shortcuts removed

REM 4. Remove the app binary; keep user data unless you say otherwise.
del /f /q "%EXE%" >nul 2>&1
echo   [OK] App removed from %DEST%

if exist "%DEST%\settings.json" (
    echo.
    echo   Your FileLore settings/recents/log are still in
    echo     %DEST%
    echo   They are tiny text files. The notes themselves live next
    echo   to your own files and are NEVER touched.
    if "%QUIET%"=="1" (
        echo   Keeping them ^(/q mode^).
    ) else (
        choice /c YN /n /m "   Delete these too? (Y/N) "
        if errorlevel 2 (
            echo   Kept.
        ) else (
            rmdir /s /q "%DEST%"
            echo   Deleted.
        )
    )
)

echo.
echo   FileLore uninstalled. Thanks for trying it!
if "%QUIET%"=="0" pause
endlocal
exit /b 0
