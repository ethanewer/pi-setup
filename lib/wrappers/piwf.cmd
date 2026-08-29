@echo off
setlocal EnableExtensions
set "MAIN_DIR=__MAIN_DIR__"
if /I "%PI_CODING_AGENT_DIR%"=="%USERPROFILE%\.pi\agent-p" (
  set "PI_CODING_AGENT_DIR="
  set "PI_CODING_AGENT_SESSION_DIR="
  set "PI_SKIP_VERSION_CHECK="
)
set "PI_CODING_AGENT_DIR=%USERPROFILE%\.pi\agent-wf"
set "PI_CODING_AGENT_SESSION_DIR=%MAIN_DIR%\sessions"

if exist "%USERPROFILE%\.local\lib\pi-coding-agent\pi.exe" (
  "%USERPROFILE%\.local\lib\pi-coding-agent\pi.exe" %*
  exit /b %ERRORLEVEL%
)

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
  echo piwf: bun not found 1>&2
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
  echo piwf: could not locate @earendil-works/pi-coding-agent 1>&2
  exit /b 1
)

"%BUN_BIN%" --use-system-ca "%CLI%" %*
exit /b %ERRORLEVEL%
