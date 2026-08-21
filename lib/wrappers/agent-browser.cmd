@echo off
setlocal EnableExtensions
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
  echo agent-browser: bun not found 1>&2
  exit /b 1
)

if defined BUN_INSTALL (
  set "BUN_HOME=%BUN_INSTALL%"
) else (
  set "BUN_HOME=%USERPROFILE%\.bun"
)

set "ROOT=%BUN_HOME%\install\global\node_modules\agent-browser"
if not exist "%ROOT%\bin\agent-browser.js" (
  echo agent-browser: could not locate agent-browser 1>&2
  exit /b 1
)

"%BUN_BIN%" --use-system-ca "%ROOT%\bin\agent-browser.js" %*
exit /b %ERRORLEVEL%
