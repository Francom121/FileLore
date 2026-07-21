@echo off
REM ============================================================
REM  Build FileLore.exe (native first-run launcher) for x64 AND
REM  ARM64. Run from any shell — finds VS Build Tools via vswhere.
REM  No ATL/MFC, /MT = statically linked CRT, zero dependencies.
REM
REM    build-launcher.cmd           builds both arches into out\
REM ============================================================
setlocal EnableExtensions

set "HERE=%~dp0"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" set "VSWHERE=%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe"

for /f "usebackq delims=" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%I"
if not defined VS (
    echo ERROR: Visual Studio Build Tools with the C++ workload not found.
    exit /b 1
)
echo Using VS at %VS%

call :build x64   || goto :fail
call :build arm64 || goto :fail
echo.
echo DONE: %HERE%out\x64\FileLore.exe and out\arm64\FileLore.exe
exit /b 0

:build
echo.
echo === Building FileLore.exe launcher (%~1) ===
set "OUT=%HERE%out\%~1"
if not exist "%OUT%" mkdir "%OUT%"
pushd "%OUT%"
call "%VS%\Common7\Tools\VsDevCmd.bat" -arch=%~1 -host_arch=arm64 >nul 2>&1
if errorlevel 1 call "%VS%\Common7\Tools\VsDevCmd.bat" -arch=%~1 >nul
rc /nologo /fo FileLoreLauncher.res "%HERE%FileLoreLauncher.rc" || (popd & exit /b 1)
cl /nologo /O2 /MT /W3 /utf-8 /DNDEBUG /DUNICODE /D_UNICODE /EHsc ^
   /c "%HERE%FileLoreLauncher.cpp" || (popd & exit /b 1)
link /nologo /SUBSYSTEM:WINDOWS /OUT:FileLore.exe ^
     FileLoreLauncher.obj FileLoreLauncher.res ^
     kernel32.lib user32.lib gdi32.lib shell32.lib || (popd & exit /b 1)
popd
exit /b 0

:fail
echo.
echo BUILD FAILED
exit /b 1
