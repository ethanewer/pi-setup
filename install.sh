#!/usr/bin/env bash
# Bootstrap Bun, locate this repository, and run the cross-platform installer.
set -euo pipefail

REPO_URL="${PI_SETUP_REPO_URL:-https://github.com/ethanewer/pi-setup.git}"
REPO_REF="${PI_SETUP_REF:-main}"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nWARNING: %s\n' "$*" >&2; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

is_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  return 1
}

case "$(uname -s)" in
  Darwin|Linux|MINGW*|MSYS*|CYGWIN*) ;;
  *) fail "This installer supports macOS, Linux, and Windows (PowerShell or Git Bash)." ;;
esac

command -v curl >/dev/null 2>&1 || fail "curl is required."
# lib/install.mjs applies the pinned Pi AI reasoning fix with patch(1). macOS and Linux
# have it (or get it with their base tools); on Windows it comes from Git Bash, which the
# installer requires for Pi's bash tool anyway and checks there.
if ! is_windows; then
  command -v patch >/dev/null 2>&1 || fail "patch is required to install the pinned Pi reasoning fix."
fi
# Bun's installer unpacks a zip, so a machine without unzip fails partway through with a
# confusing error rather than at the door.
if ! command -v bun >/dev/null 2>&1 && [[ ! -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun" && ! -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun.exe" ]]; then
  if ! is_windows; then
    command -v unzip >/dev/null 2>&1 || fail "unzip is required to install Bun (apt install unzip / brew install unzip)."
  fi
fi

export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
bun_bin() {
  if command -v bun >/dev/null 2>&1; then
    command -v bun
  elif [[ -x "$BUN_INSTALL/bin/bun" ]]; then
    printf '%s\n' "$BUN_INSTALL/bin/bun"
  elif [[ -x "$BUN_INSTALL/bin/bun.exe" ]]; then
    printf '%s\n' "$BUN_INSTALL/bin/bun.exe"
  else
    return 1
  fi
}

if ! BUN_BIN="$(bun_bin)"; then
  if ! is_windows; then
    command -v unzip >/dev/null 2>&1 || fail "unzip is required to install Bun (apt install unzip / brew install unzip)."
  fi
  log "Installing Bun"
  if is_windows; then
    powershell.exe -NoProfile -Command "irm https://bun.sh/install.ps1 | iex" \
      || fail "Bun installation failed."
  else
    curl -fsSL https://bun.sh/install | bash
  fi
  BUN_BIN="$(bun_bin)" || fail "Bun installation failed."
fi

export PATH="$HOME/.local/bin:$BUN_INSTALL/bin:$PATH"
MAIN_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

SRC_DIR=""
SELF="${BASH_SOURCE[0]:-}"
if [[ -n "$SELF" && -f "$SELF" ]]; then
  CANDIDATE="$(cd "$(dirname "$SELF")" && pwd)"
  [[ -d "$CANDIDATE/forks" && -f "$CANDIDATE/lib/install.mjs" ]] && SRC_DIR="$CANDIDATE"
fi
if [[ -z "$SRC_DIR" ]]; then
  git --version >/dev/null 2>&1 || fail "git is required to fetch the extension forks (on macOS: xcode-select --install)."
  CLONE_DIR="$MAIN_DIR/setup-src"
  if [[ -d "$CLONE_DIR/.git" ]]; then
    log "Updating setup sources in $CLONE_DIR"
    git -C "$CLONE_DIR" remote set-url origin "$REPO_URL"
    git -C "$CLONE_DIR" fetch --depth 1 origin "$REPO_REF"
    git -C "$CLONE_DIR" checkout -q FETCH_HEAD
  else
    log "Fetching setup sources into $CLONE_DIR"
    rm -rf "$CLONE_DIR"
    git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$CLONE_DIR"
  fi
  SRC_DIR="$CLONE_DIR"
fi
[[ -f "$SRC_DIR/lib/install.mjs" ]] || fail "Could not find lib/install.mjs in $SRC_DIR."

export PI_SETUP_SRC="$SRC_DIR"
exec "$BUN_BIN" "$SRC_DIR/lib/install.mjs"
