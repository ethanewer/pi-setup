#!/bin/sh
set -eu
if command -v bun >/dev/null 2>&1; then
  BUN_BIN="$(command -v bun)"
elif [ -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun" ]; then
  BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun"
else
  BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun.exe"
fi
# A tmux server started from `p` or `piwf` can retain that profile's variables.
# Normal `pi` must never inherit a profile accidentally.
case "${PI_CODING_AGENT_DIR:-}" in
  "$HOME/.pi/agent-p"|"$HOME/.pi/agent-wf")
    unset PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR PI_SKIP_VERSION_CHECK ;;
esac
for ROOT in \
  "${PI_PACKAGE_ROOT:-}" \
  "${BUN_INSTALL:-$HOME/.bun}/install/global/node_modules/@earendil-works/pi-coding-agent" \
  "/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent" \
  "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent"
do
  if [ -n "$ROOT" ] && [ -f "$ROOT/dist/bun/cli.js" ]; then
    exec "$BUN_BIN" --use-system-ca "$ROOT/dist/bun/cli.js" "$@"
  fi
done
echo "pi: could not locate @earendil-works/pi-coding-agent" >&2
exit 1
