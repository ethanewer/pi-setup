@echo off
setlocal
set "SCRIPT=%~dp0pi-setup-doctor"
if exist "%ProgramFiles%\Git\bin\bash.exe" (
  "%ProgramFiles%\Git\bin\bash.exe" "%SCRIPT%" %*
  exit /b %ERRORLEVEL%
)
where bash >nul 2>&1 && (
  bash "%SCRIPT%" %*
  exit /b %ERRORLEVEL%
)
echo pi-setup-doctor: Git Bash is required on Windows 1>&2
exit /b 1
