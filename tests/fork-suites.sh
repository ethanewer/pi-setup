#!/usr/bin/env bash
# Run the test suites that live inside the forks themselves.
#
#   tests/fork-suites.sh
#
# Only pi-process-monitor-safe ships one. Its tests need dev dependencies that install.sh
# deliberately does not install (they would pull provider SDKs into every fork), but every
# one of them — typebox, the pi packages, @types/node — is already present in Bun's global
# tree because Pi itself depends on them. Linking that tree in is enough, costs no download,
# and forks/*/node_modules is gitignored.
#
# Without this the suite does not run at all: 12 files that look like coverage and provide
# none. It was dark until 2026-07-30.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUN_GLOBAL="${BUN_INSTALL:-$HOME/.bun}/install/global/node_modules"
STATUS=0

command -v bun >/dev/null 2>&1 || { echo "fork-suites.sh: bun is required" >&2; exit 2; }
[[ -d "$BUN_GLOBAL" ]] || { echo "fork-suites.sh: no bun global tree at $BUN_GLOBAL; run the installer" >&2; exit 2; }

is_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
  esac
  return 1
}

# Junctions on Windows need rmdir, not rm -rf: Git Bash `rm -rf` on a junction can
# walk into Bun's global tree and delete it.
link_node_modules() { # link_node_modules <dir> -> echoes symlink|junction|existing
  local dir="$1"
  if [[ -e "$dir/node_modules" ]]; then
    printf 'existing\n'
    return 0
  fi
  if is_windows; then
    local dest src
    dest="$(cygpath -w "$dir/node_modules")"
    src="$(cygpath -w "$BUN_GLOBAL")"
    cmd.exe //c mklink //J "$dest" "$src" >/dev/null || return 1
    printf 'junction\n'
  else
    ln -s "$BUN_GLOBAL" "$dir/node_modules" || return 1
    printf 'symlink\n'
  fi
}

unlink_node_modules() { # unlink_node_modules <dir> <kind>
  local dir="$1" kind="$2"
  case "$kind" in
    symlink) rm -f "$dir/node_modules" ;;
    junction) cmd.exe //c rmdir "$(cygpath -w "$dir/node_modules")" >/dev/null ;;
  esac
}

for fork in pi-process-monitor-safe; do
  dir="$REPO_DIR/forks/$fork"
  [[ -d "$dir/test" ]] || continue
  printf '\n=== %s\n' "$fork"
  # A real node_modules from a previous `bun install` is left alone; only the link is ours.
  created="$(link_node_modules "$dir")" || { echo "fork-suites.sh: could not link node_modules for $fork" >&2; STATUS=1; continue; }
  (cd "$dir" && bun test) || STATUS=1
  unlink_node_modules "$dir" "$created"
done

exit "$STATUS"
