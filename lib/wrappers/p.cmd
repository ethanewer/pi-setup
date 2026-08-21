@echo off
setlocal EnableExtensions
set "MAIN_DIR=__MAIN_DIR__"
set "PI_SKIP_VERSION_CHECK=1"
set "PI_CODING_AGENT_DIR=%USERPROFILE%\.pi\agent-p"
set "PI_CODING_AGENT_SESSION_DIR=%MAIN_DIR%\sessions"

set "BUN_BIN="
if defined BUN_INSTALL if exist "%BUN_INSTALL%\bin\bun.exe" set "BUN_BIN=%BUN_INSTALL%\bin\bun.exe"
if not defined BUN_BIN if exist "%USERPROFILE%\.bun\bin\bun.exe" set "BUN_BIN=%USERPROFILE%\.bun\bin\bun.exe"
if not defined BUN_BIN (
  where bun >nul 2>&1 && for /f "delims=" %%I in ('where bun') do (
    set "BUN_BIN=%%I"
    goto :have_bun
  )
)
:have_bun
if not defined BUN_BIN (
  echo p: bun not found 1>&2
  exit /b 1
)

if defined BUN_INSTALL (
  set "BUN_HOME=%BUN_INSTALL%"
) else (
  set "BUN_HOME=%USERPROFILE%\.bun"
)

set "CLI="
if defined PI_PACKAGE_ROOT if exist "%PI_PACKAGE_ROOT%\dist\bun\cli.js" set "CLI=%PI_PACKAGE_ROOT%\dist\bun\cli.js"
if not defined CLI if exist "%BUN_HOME%\install\global\node_modules\@earendil-works\pi-coding-agent\dist\bun\cli.js" (
  set "CLI=%BUN_HOME%\install\global\node_modules\@earendil-works\pi-coding-agent\dist\bun\cli.js"
)
if not defined CLI (
  echo p: could not locate @earendil-works/pi-coding-agent 1>&2
  exit /b 1
)

"%BUN_BIN%" "%CLI%" --no-extensions --no-skills --extension "%MAIN_DIR%\local\pi-voice-stt-safe\extensions\voice-stt\index.js" --extension "%MAIN_DIR%\local\pi-context-handoff\extensions\context-handoff\index.js" --extension "%MAIN_DIR%\local\pi-codex-compaction\extensions\codex-compaction\index.js" --extension "%MAIN_DIR%\local\pi-btw-side\extensions\btw\index.js" --extension "%MAIN_DIR%\p\remove-pi-documentation.js" %*
exit /b %ERRORLEVEL%
