#!/bin/sh
set -eu
if command -v bun >/dev/null 2>&1; then
  BUN_BIN="$(command -v bun)"
elif [ -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun" ]; then
  BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun"
else
  BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun.exe"
fi
ROOT="${BUN_INSTALL:-$HOME/.bun}/install/global/node_modules/agent-browser"
exec "$BUN_BIN" "$ROOT/bin/agent-browser.js" "$@"
