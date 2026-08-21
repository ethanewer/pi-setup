#!/bin/sh
set -eu
MAIN_DIR="__MAIN_DIR__"
export PI_SKIP_VERSION_CHECK=1
export PI_CODING_AGENT_DIR="$HOME/.pi/agent-p"
export PI_CODING_AGENT_SESSION_DIR="$MAIN_DIR/sessions"
if command -v bun >/dev/null 2>&1; then
  BUN_BIN="$(command -v bun)"
elif [ -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun" ]; then
  BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun"
else
  BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun.exe"
fi
for ROOT in \
  "${PI_PACKAGE_ROOT:-}" \
  "${BUN_INSTALL:-$HOME/.bun}/install/global/node_modules/@earendil-works/pi-coding-agent" \
  "/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent" \
  "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent"
do
  if [ -n "$ROOT" ] && [ -f "$ROOT/dist/bun/cli.js" ]; then
    exec "$BUN_BIN" --use-system-ca "$ROOT/dist/bun/cli.js" \
      --no-extensions \
      --no-skills \
      --extension "$MAIN_DIR/local/pi-voice-stt-safe/extensions/voice-stt/index.js" \
      --extension "$MAIN_DIR/local/pi-context-handoff/extensions/context-handoff/index.js" \
      --extension "$MAIN_DIR/local/pi-codex-compaction/extensions/codex-compaction/index.js" \
      --extension "$MAIN_DIR/local/pi-btw-side/extensions/btw/index.js" \
      --extension "$MAIN_DIR/extensions/mlx/index.js" \
      --extension "$MAIN_DIR/p/remove-pi-documentation.js" \
      "$@"
  fi
done
echo "p: could not locate @earendil-works/pi-coding-agent" >&2
exit 1
