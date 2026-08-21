@echo off
setlocal
set "SCRIPT=%~dp0pi-setup-keyprobe"
where bun >nul 2>&1 && (
  bun "%SCRIPT%" %*
  exit /b %ERRORLEVEL%
)
if defined BUN_INSTALL if exist "%BUN_INSTALL%\bin\bun.exe" (
  "%BUN_INSTALL%\bin\bun.exe" "%SCRIPT%" %*
  exit /b %ERRORLEVEL%
)
if exist "%USERPROFILE%\.bun\bin\bun.exe" (
  "%USERPROFILE%\.bun\bin\bun.exe" "%SCRIPT%" %*
  exit /b %ERRORLEVEL%
)
if exist "%ProgramFiles%\Git\bin\bash.exe" (
  "%ProgramFiles%\Git\bin\bash.exe" "%SCRIPT%" %*
  exit /b %ERRORLEVEL%
)
echo pi-setup-keyprobe: bun is required on Windows 1>&2
exit /b 1
