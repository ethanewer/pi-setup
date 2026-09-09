@echo off
setlocal EnableExtensions
rem occ — Open Claude Code. Runs the bash launcher through Git Bash, which pi
rem requires for its bash tool anyway. Best-effort on Windows: argument paths
rem pass through Git Bash's translation.
set "BASH_BIN="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_BIN=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH_BIN if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH_BIN=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH_BIN if exist "%ProgramFiles%\Git\usr\bin\bash.exe" set "BASH_BIN=%ProgramFiles%\Git\usr\bin\bash.exe"
if not defined BASH_BIN (
  where bash >nul 2>&1 && for /f "delims=" %%I in ('where bash') do (
    set "BASH_BIN=%%I"
    goto :have_bash
  )
)
:have_bash
if not defined BASH_BIN (
  echo occ: Git Bash not found; install Git for Windows 1>&2
  exit /b 1
)
"%BASH_BIN%" "%USERPROFILE%\.local\bin\occ.sh" %*
exit /b %ERRORLEVEL%
