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
[[ -d "$BUN_GLOBAL" ]] || { echo "fork-suites.sh: no bun global tree at $BUN_GLOBAL; run ./install.sh" >&2; exit 2; }

for fork in pi-process-monitor-safe; do
  dir="$REPO_DIR/forks/$fork"
  [[ -d "$dir/test" ]] || continue
  printf '\n=== %s\n' "$fork"
  # A real node_modules from a previous `bun install` is left alone; only the symlink is ours.
  if [[ ! -e "$dir/node_modules" ]]; then
    ln -s "$BUN_GLOBAL" "$dir/node_modules"
    created=1
  else
    created=0
  fi
  (cd "$dir" && bun test) || STATUS=1
  [[ "$created" == "1" && -L "$dir/node_modules" ]] && rm -f "$dir/node_modules"
done

exit "$STATUS"
