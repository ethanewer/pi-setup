#!/bin/sh
set -eu
if command -v bun >/dev/null 2>&1; then
  BUN_BIN="$(command -v bun)"
elif [ -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun" ]; then
  BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun"
else
  BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun.exe"
fi
# A tmux server started from `p` can retain p's profile variables. Normal `pi`
# must never inherit that lean profile accidentally.
if [ "${PI_CODING_AGENT_DIR:-}" = "$HOME/.pi/agent-p" ]; then
  unset PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR PI_SKIP_VERSION_CHECK
fi
for ROOT in \
  "${PI_PACKAGE_ROOT:-}" \
  "${BUN_INSTALL:-$HOME/.bun}/install/global/node_modules/@earendil-works/pi-coding-agent" \
  "/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent" \
  "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent"
do
  if [ -n "$ROOT" ] && [ -f "$ROOT/dist/bun/cli.js" ]; then
    exec "$BUN_BIN" "$ROOT/dist/bun/cli.js" "$@"
  fi
done
echo "pi: could not locate @earendil-works/pi-coding-agent" >&2
exit 1
