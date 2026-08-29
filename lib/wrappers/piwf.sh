#!/bin/sh
set -eu
MAIN_DIR="__MAIN_DIR__"
# A tmux server started from `p` retains the lean profile's variables, notably
# PI_SKIP_VERSION_CHECK. piwf pins its own agent directory below, but must still
# drop the rest rather than inherit the lean profile's environment.
case "${PI_CODING_AGENT_DIR:-}" in
  "$HOME/.pi/agent-p")
    unset PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR PI_SKIP_VERSION_CHECK ;;
esac
export PI_CODING_AGENT_DIR="$HOME/.pi/agent-wf"
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
    exec "$BUN_BIN" --use-system-ca "$ROOT/dist/bun/cli.js" "$@"
  fi
done
echo "piwf: could not locate @earendil-works/pi-coding-agent" >&2
exit 1
