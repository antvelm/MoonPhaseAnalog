@echo off
REM Build both Venu 3 sizes with the on-screen performance overlay compiled in
REM (source\Perf.mc): per-section frame times in ms, cur/peak total, live heap.
REM
REM Double-click it, or run it from a shell. Any extra arguments are passed
REM straight through to build.ps1, so `build-perf.bat -Debug` works.
REM
REM This is just build.ps1 -Perf in one click. It exists because that is the
REM build worth repeating while tuning the frame, and because the overlay is
REM easy to forget to ask for.
REM
REM WARNING: the .prg files it leaves in bin\ have the overlay drawn on the
REM dial. Never sideload one to a watch you actually wear -- run a plain
REM .\build.ps1 to overwrite them with clean ones first.

setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" -Perf %*
set EXITCODE=%ERRORLEVEL%

REM Keep the window up when this was double-clicked from Explorer, so the
REM build stats and any error are readable. cmdcmdline holds the full command
REM line: Explorer launches with /c, a shell that is already open does not.
REM The same test fires for a deliberate `cmd /c build-perf.bat`, which is why
REM NOPAUSE is here -- set it for a script or a CI step that must not block.
if defined NOPAUSE goto :done
echo %cmdcmdline% | find /i "/c" >nul && pause
:done

exit /b %EXITCODE%
