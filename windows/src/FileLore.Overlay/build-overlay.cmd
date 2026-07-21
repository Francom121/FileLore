@echo off
REM ============================================================
REM  Build FileLoreOverlay.dll for x64 AND ARM64.
REM  Run from a "Developer Command Prompt" (or any shell where
REM  VsDevCmd.bat is reachable). No ATL, no CRT runtime dependency
REM  (/MT = statically linked) — safe to load inside explorer.exe.
REM
REM    build-overlay.cmd           builds both arches into out\
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
echo DONE: %HERE%out\x64\FileLoreOverlay.dll and out\arm64\FileLoreOverlay.dll
exit /b 0

:build
echo.
echo === Building FileLoreOverlay.dll (%~1) ===
set "OUT=%HERE%out\%~1"
if not exist "%OUT%" mkdir "%OUT%"
pushd "%OUT%"
call "%VS%\Common7\Tools\VsDevCmd.bat" -arch=%~1 -host_arch=arm64 >nul 2>&1
if errorlevel 1 call "%VS%\Common7\Tools\VsDevCmd.bat" -arch=%~1 >nul
rc /nologo /fo FileLoreOverlay.res "%HERE%FileLoreOverlay.rc" || (popd & exit /b 1)
cl /nologo /O2 /MT /W3 /DNDEBUG /DUNICODE /D_UNICODE /EHsc ^
   /c "%HERE%FileLoreOverlay.cpp" || (popd & exit /b 1)
link /nologo /DLL /DEF:"%HERE%FileLoreOverlay.def" /OUT:FileLoreOverlay.dll ^
     FileLoreOverlay.obj FileLoreOverlay.res ^
     kernel32.lib user32.lib ole32.lib shell32.lib advapi32.lib || (popd & exit /b 1)
popd
exit /b 0

:fail
echo.
echo BUILD FAILED
exit /b 1
