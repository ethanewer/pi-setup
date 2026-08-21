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
  echo pi-agent-browser: bun not found 1>&2
  exit /b 1
)

"%BUN_BIN%" "__TARGET__" %*
exit /b %ERRORLEVEL%
