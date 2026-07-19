@echo off
REM Registers the Explorer right-click verb "FileLore Note" for all files.
REM Writes HKLM, so run elevated. Usage:
REM   install-context-menu.cmd [full-path-to-FileLore.exe]
setlocal
set "EXE=%~1"
if "%EXE%"=="" set "EXE=C:\FileLore\FileLore.exe"

reg add "HKLM\Software\Classes\*\shell\FileLore" /ve /d "FileLore Note" /f
reg add "HKLM\Software\Classes\*\shell\FileLore" /v Icon /d "\"%EXE%\"" /f
reg add "HKLM\Software\Classes\*\shell\FileLore\command" /ve /d "\"%EXE%\" \"%%1\"" /f

echo FileLore context menu verb registered for %EXE%
endlocal
