#!/bin/sh
set -eu
MAIN_DIR="__MAIN_DIR__"
# ocdx is the Open Codex entrypoint: a full Pi environment running only
# open-weight models. Like piwf, it pins its own agent directory, so it must
# drop an inherited profile environment (agent-p, agent-wf, agent-occ,
# agent-ocdx) rather than let a tmux server started under another profile
# shadow its variables.
case "${PI_CODING_AGENT_DIR:-}" in
  "$HOME/.pi/agent-p"|"$HOME/.pi/agent-wf"|"$HOME/.pi/agent-occ"|"$HOME/.pi/agent-ocdx")
    unset PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR PI_SKIP_VERSION_CHECK ;;
esac
export PI_CODING_AGENT_DIR="$HOME/.pi/agent-ocdx"
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
echo "ocdx: could not locate @earendil-works/pi-coding-agent" >&2
exit 1
