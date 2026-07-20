@echo off
REM ============================================================
REM  FileLore-Diagnose.cmd - remote-diagnostics collector
REM  Double-click it (no admin needed). It gathers everything we
REM  need to debug "FileLore Note isn't in the right-click menu"
REM  or "which build am I running?", writes FileLore-Diagnose.txt
REM  to your Desktop, and opens it in Notepad. Send that file
REM  back when asked for diagnostics.
REM  Pure cmd - no PowerShell, no admin, works from any folder.
REM ============================================================
setlocal EnableExtensions

set "EXE=%LOCALAPPDATA%\FileLore\FileLore.exe"
set "OUT=%USERPROFILE%\Desktop\FileLore-Diagnose.txt"
set "TMPD=%TEMP%\filelore-diag-%RANDOM%%RANDOM%"
mkdir "%TMPD%" >nul 2>&1

echo Collecting FileLore diagnostics...

REM ---- header -------------------------------------------------
(
echo ============================================================
echo  FileLore diagnostics
echo  collected: %DATE% %TIME%
echo  user:      %USERNAME%  on %COMPUTERNAME%
echo ============================================================
echo.
echo ---- Windows version ----------------------------------------
ver
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v UBR
echo.
) > "%OUT%" 2>&1

REM ---- installed app ------------------------------------------
(
echo ---- Installed app ------------------------------------------
echo Expected location: %EXE%
) >> "%OUT%" 2>&1
if exist "%EXE%" (
    for %%I in ("%EXE%") do (
        echo   EXISTS - size: %%~zI bytes, modified: %%~tI
    ) >> "%OUT%" 2>&1
    echo. >> "%OUT%"
    echo App --version output: >> "%OUT%"
    call :appversion
) else (
    echo   NOT FOUND - FileLore is not installed for this user. >> "%OUT%"
)
(
echo.
echo ---- HKCU right-click verb ^(per-user install^) ---------------
) >> "%OUT%" 2>&1
reg query "HKCU\Software\Classes\*\shell\FileLore" /s >> "%OUT%" 2>&1
if errorlevel 1 echo   NOT PRESENT - the per-user verb is missing; re-run Install-FileLore.cmd >> "%OUT%"
(
echo.
echo ---- HKLM right-click verb ^(machine-wide, just in case^) -----
) >> "%OUT%" 2>&1
reg query "HKLM\Software\Classes\*\shell\FileLore" /s >> "%OUT%" 2>&1
if errorlevel 1 echo   NOT PRESENT ^(normal - the installer is per-user^) >> "%OUT%"
(
echo.
echo ---- Autostart ^(Run key^) ------------------------------------
) >> "%OUT%" 2>&1
reg query "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v FileLore >> "%OUT%" 2>&1
if errorlevel 1 echo   NOT PRESENT - tray will not start at sign-in >> "%OUT%"
(
echo.
echo ---- Running processes --------------------------------------
) >> "%OUT%" 2>&1
tasklist | findstr /i "filelore" >> "%OUT%" 2>&1
if errorlevel 1 echo   FileLore.exe is NOT running right now >> "%OUT%"
(
echo.
echo ---- End of report ------------------------------------------
echo If "FileLore Note" is missing from the right-click menu:
echo   1. On Windows 11 it lives inside "Show more options".
echo   2. Restart Explorer: Ctrl+Shift+Esc -^> Windows Explorer -^> Restart.
echo   3. Re-run Install-FileLore.cmd and look for [FAIL] lines.
echo   4. Send this file back for analysis.
) >> "%OUT%" 2>&1

rmdir /s /q "%TMPD%" >nul 2>&1

echo.
echo   Report written to:
echo     %OUT%
echo   Opening it in Notepad - please send this file back.
echo.
start "" notepad.exe "%OUT%"
pause
endlocal
exit /b 0

REM ------------------------------------------------------------
REM  :appversion - collect "FileLore.exe --version" output.
REM  cmd never waits for GUI-subsystem apps, so the app writes the
REM  version straight to a file ("--version <file>") and we poll
REM  for it (first launch can take a while - self-extraction).
REM ------------------------------------------------------------
:appversion
del "%TMPD%\ver.txt" >nul 2>&1
"%EXE%" --version "%TMPD%\ver.txt"
REM Wait up to ~90s, but WITHOUT goto (goto inside a called subroutine
REM discards the return address in cmd.exe and would kill the script).
for /l %%W in (1,1,90) do (
    if not exist "%TMPD%\ver.txt" ping -n 2 127.0.0.1 >nul
)
if exist "%TMPD%\ver.txt" (
    type "%TMPD%\ver.txt" >> "%OUT%"
) else (
    echo   ^(no version output - pre-0.5.0 build, or exe failed to start^) >> "%OUT%"
)
exit /b 0
