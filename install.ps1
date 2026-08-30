#Requires -Version 5.1
# Bootstrap Bun, locate this repository, and run the cross-platform installer.
$ErrorActionPreference = "Stop"

function Write-Log([string]$Message) { Write-Host "`n==> $Message" }
function Fail([string]$Message) { Write-Host "`nERROR: $Message" -ForegroundColor Red; exit 1 }

$RepoUrl = if ($env:PI_SETUP_REPO_URL) { $env:PI_SETUP_REPO_URL } else { "https://github.com/ethanewer/pi-setup.git" }
# Default matches main so `irm .../main/install.ps1 | iex` clones the same tree.
$RepoRef = if ($env:PI_SETUP_REF) { $env:PI_SETUP_REF } else { "main" }
$HomeDir = $env:USERPROFILE
if (-not $HomeDir) { $HomeDir = $HOME }
$env:BUN_INSTALL = if ($env:BUN_INSTALL) { $env:BUN_INSTALL } else { Join-Path $HomeDir ".bun" }

function Get-BunBin {
  $cmd = Get-Command bun -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $exe = Join-Path $env:BUN_INSTALL "bin\bun.exe"
  if (Test-Path $exe) { return $exe }
  $plain = Join-Path $env:BUN_INSTALL "bin\bun"
  if (Test-Path $plain) { return $plain }
  return $null
}

$bun = Get-BunBin
if (-not $bun) {
  Write-Log "Installing Bun"
  try {
    Invoke-RestMethod https://bun.sh/install.ps1 | Invoke-Expression
  } catch {
    Fail "Bun installation failed: $_"
  }
  $bun = Get-BunBin
  if (-not $bun) { Fail "Bun installation failed." }
}

$localBin = Join-Path $HomeDir ".local\bin"
$bunBin = Join-Path $env:BUN_INSTALL "bin"
$env:Path = "$localBin;$bunBin;$env:Path"

$mainDir = if ($env:PI_CODING_AGENT_DIR) { $env:PI_CODING_AGENT_DIR } else { Join-Path $HomeDir ".pi\agent" }

$src = $null
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "forks")) -and (Test-Path (Join-Path $PSScriptRoot "lib\install.mjs"))) {
  $src = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
  $here = Split-Path -Parent $MyInvocation.MyCommand.Path
  if ((Test-Path (Join-Path $here "forks")) -and (Test-Path (Join-Path $here "lib\install.mjs"))) {
    $src = $here
  }
}

if (-not $src) {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Fail "git is required to fetch the extension forks (install Git for Windows)."
  }
  $cloneDir = Join-Path $mainDir "setup-src"
  if (Test-Path (Join-Path $cloneDir ".git")) {
    Write-Log "Updating setup sources in $cloneDir"
    git -C $cloneDir remote set-url origin $RepoUrl
    git -C $cloneDir fetch --depth 1 origin $RepoRef
    $rev = "FETCH_HEAD"
  } else {
    Write-Log "Fetching setup sources into $cloneDir"
    if (Test-Path $cloneDir) { Remove-Item -Recurse -Force $cloneDir }
    New-Item -ItemType Directory -Force -Path (Split-Path $cloneDir) | Out-Null
    git clone --no-checkout --depth 1 --branch $RepoRef $RepoUrl $cloneDir
    $rev = "HEAD"
  }
  # evals/general-v2 contains fixture names Windows cannot represent (device
  # names like `aux`, an embedded colon, paths over 260 chars). The installer
  # never reads evals/, so keep the tree out of the checkout instead of
  # letting it abort on a fresh machine.
  git -C $cloneDir config core.longpaths true
  git -C $cloneDir config core.protectNTFS false
  git -C $cloneDir sparse-checkout init --no-cone
  [System.IO.File]::WriteAllText((Join-Path $cloneDir ".git\info\sparse-checkout"), "/*`n!/evals/`n")
  git -C $cloneDir checkout -q $rev
  $src = $cloneDir
}

$installer = Join-Path $src "lib\install.mjs"
if (-not (Test-Path $installer)) { Fail "Could not find lib/install.mjs in $src." }

$env:PI_SETUP_SRC = $src
& $bun $installer
exit $LASTEXITCODE
