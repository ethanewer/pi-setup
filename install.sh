#!/usr/bin/env bash
set -euo pipefail

PI_VERSION="0.81.1"
VOICE_VERSION="0.4.0"
BROWSER_EXTENSION_VERSION="0.2.71"
WORKFLOW_VERSION="3.4.1"
AGENT_BROWSER_VERSION="0.32.2"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nWARNING: %s\n' "$*" >&2; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) fail "This installer supports macOS and Linux." ;;
esac
command -v curl >/dev/null 2>&1 || fail "curl is required."

export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
if command -v bun >/dev/null 2>&1; then
  BUN_BIN="$(command -v bun)"
elif [[ -x "$BUN_INSTALL/bin/bun" ]]; then
  BUN_BIN="$BUN_INSTALL/bin/bun"
else
  log "Installing Bun"
  curl -fsSL https://bun.sh/install | bash
  BUN_BIN="$BUN_INSTALL/bin/bun"
fi
[[ -x "$BUN_BIN" ]] || fail "Bun installation failed."

export PATH="$HOME/.local/bin:$BUN_INSTALL/bin:$PATH"
MAIN_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
P_DIR="$HOME/.pi/agent-p"
LOCAL_BIN="$HOME/.local/bin"
NPM_DIR="$MAIN_DIR/npm"
mkdir -p "$LOCAL_BIN" "$MAIN_DIR/bin" "$MAIN_DIR/p" "$NPM_DIR" "$P_DIR"

log "Installing Pi and agent-browser with Bun"
"$BUN_BIN" add --global \
  "@earendil-works/pi-coding-agent@$PI_VERSION" \
  "agent-browser@$AGENT_BROWSER_VERSION"

PI_ROOT="$BUN_INSTALL/install/global/node_modules/@earendil-works/pi-coding-agent"
AGENT_BROWSER_ROOT="$BUN_INSTALL/install/global/node_modules/agent-browser"
[[ -f "$PI_ROOT/dist/bun/cli.js" ]] || fail "Could not find Pi's Bun entrypoint at $PI_ROOT/dist/bun/cli.js"
[[ -f "$AGENT_BROWSER_ROOT/bin/agent-browser.js" ]] || fail "Could not find agent-browser at $AGENT_BROWSER_ROOT"

log "Installing pinned Pi extensions"
cat > "$NPM_DIR/package.json" <<JSON
{
  "private": true,
  "dependencies": {
    "pi-voice-stt": "$VOICE_VERSION",
    "pi-agent-browser-native": "$BROWSER_EXTENSION_VERSION",
    "@quintinshaw/pi-dynamic-workflows": "$WORKFLOW_VERSION"
  }
}
JSON
(
  cd "$NPM_DIR"
  "$BUN_BIN" install --production
)

cat > "$LOCAL_BIN/pi" <<'SH'
#!/bin/sh
set -eu
if command -v bun >/dev/null 2>&1; then
  BUN_BIN="$(command -v bun)"
else
  BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun"
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
SH

cat > "$LOCAL_BIN/agent-browser" <<'SH'
#!/bin/sh
set -eu
if command -v bun >/dev/null 2>&1; then
  BUN_BIN="$(command -v bun)"
else
  BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun"
fi
ROOT="${BUN_INSTALL:-$HOME/.bun}/install/global/node_modules/agent-browser"
exec "$BUN_BIN" "$ROOT/bin/agent-browser.js" "$@"
SH

cat > "$MAIN_DIR/p/remove-pi-documentation.js" <<'JS'
const SECTION_START = "\n\nPi documentation (read only when the user asks about pi itself, its SDK, extensions, themes, skills, or TUI):";
const SECTION_END = "\n- Always read pi .md files completely and follow links to related docs (e.g., tui.md for TUI API details)";
export default function (pi) {
  pi.on("before_agent_start", (event) => {
    const start = event.systemPrompt.indexOf(SECTION_START);
    if (start === -1) return;
    const marker = event.systemPrompt.indexOf(SECTION_END, start);
    if (marker === -1) return;
    const end = marker + SECTION_END.length;
    return { systemPrompt: event.systemPrompt.slice(0, start) + event.systemPrompt.slice(end) };
  });
}
JS

cat > "$LOCAL_BIN/p" <<'SH'
#!/bin/sh
set -eu
MAIN_DIR="$HOME/.pi/agent"
export PI_SKIP_VERSION_CHECK=1
export PI_CODING_AGENT_DIR="$HOME/.pi/agent-p"
export PI_CODING_AGENT_SESSION_DIR="$MAIN_DIR/sessions"
if command -v bun >/dev/null 2>&1; then
  BUN_BIN="$(command -v bun)"
else
  BUN_BIN="${BUN_INSTALL:-$HOME/.bun}/bin/bun"
fi
for ROOT in \
  "${PI_PACKAGE_ROOT:-}" \
  "${BUN_INSTALL:-$HOME/.bun}/install/global/node_modules/@earendil-works/pi-coding-agent" \
  "/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent" \
  "/usr/local/lib/node_modules/@earendil-works/pi-coding-agent"
do
  if [ -n "$ROOT" ] && [ -f "$ROOT/dist/bun/cli.js" ]; then
    exec "$BUN_BIN" "$ROOT/dist/bun/cli.js" \
      --no-extensions \
      --no-skills \
      --extension "$MAIN_DIR/npm/node_modules/pi-voice-stt/src/index.ts" \
      --extension "$MAIN_DIR/p/remove-pi-documentation.js" \
      "$@"
  fi
done
echo "p: could not locate @earendil-works/pi-coding-agent" >&2
exit 1
SH
chmod 755 "$LOCAL_BIN/pi" "$LOCAL_BIN/p" "$LOCAL_BIN/agent-browser"

log "Writing Pi configuration"
CONFIG_SCRIPT="$(mktemp)"
cat > "$CONFIG_SCRIPT" <<'JS'
import { existsSync, readFileSync, writeFileSync } from "node:fs";
const [mainPath, pPath, sttPath] = process.argv.slice(2);
const read = (path) => existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : {};
const main = read(mainPath);
main.lastChangelogVersion ??= "0.81.1";
main.defaultThinkingLevel = "medium";
main.defaultProvider = "openai";
main.defaultModel = "gpt-5.6-sol";
main.theme ??= "dark";
delete main.quietStartup;
const wanted = [
  "npm:pi-voice-stt@0.4.0",
  "npm:pi-agent-browser-native@0.2.71",
  "npm:@quintinshaw/pi-dynamic-workflows@3.4.1",
];
const names = new Set(["pi-voice-stt", "pi-agent-browser-native", "@quintinshaw/pi-dynamic-workflows"]);
const identity = (entry) => {
  const source = typeof entry === "string" ? entry : entry?.source;
  if (typeof source !== "string") return "";
  const spec = source.replace(/^npm:/, "");
  if (spec.startsWith("@")) return spec.split("@").slice(0, 2).join("@");
  return spec.split("@")[0];
};
main.packages = [...(main.packages ?? []).filter((entry) => !names.has(identity(entry))), ...wanted];
writeFileSync(mainPath, JSON.stringify(main, null, 2) + "\n");
const lean = {
  lastChangelogVersion: main.lastChangelogVersion,
  defaultThinkingLevel: main.defaultThinkingLevel,
  defaultProvider: main.defaultProvider,
  defaultModel: main.defaultModel,
  theme: main.theme,
  quietStartup: true,
};
writeFileSync(pPath, JSON.stringify(lean, null, 2) + "\n");
const stt = read(sttPath);
stt.keybind = "alt+p";
stt.provider = {
  type: "openai",
  model: "gpt-4o-mini-transcribe",
  apiKeyEnv: "OPENAI_API_KEY",
  language: "auto",
};
writeFileSync(sttPath, JSON.stringify(stt, null, 2) + "\n");
JS
"$BUN_BIN" "$CONFIG_SCRIPT" "$MAIN_DIR/settings.json" "$P_DIR/settings.json" "$MAIN_DIR/stt.json"
rm -f "$CONFIG_SCRIPT"

ln -sfn "$MAIN_DIR/auth.json" "$P_DIR/auth.json"
ln -sfn "$MAIN_DIR/models-store.json" "$P_DIR/models-store.json"
rm -rf "$P_DIR/bin"
ln -s "$MAIN_DIR/bin" "$P_DIR/bin"

add_path_line() {
  local file="$1"
  local line='export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"'
  touch "$file"
  grep -Fqx "$line" "$file" 2>/dev/null || printf '\n%s\n' "$line" >> "$file"
}
[[ -n "${ZDOTDIR:-}" ]] && ZSHRC="$ZDOTDIR/.zshrc" || ZSHRC="$HOME/.zshrc"
add_path_line "$ZSHRC"
add_path_line "$HOME/.bashrc"

if [[ "${PI_SETUP_SKIP_BROWSER_INSTALL:-0}" == "1" ]]; then
  warn "Skipping Chrome installation because PI_SETUP_SKIP_BROWSER_INSTALL=1."
else
  log "Installing browser runtime"
  if ! "$LOCAL_BIN/agent-browser" install; then
    warn "Chrome download failed. Re-run 'agent-browser install' later; an existing compatible Chrome may still work."
  fi
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  warn "ffmpeg is not installed. Voice STT needs ffmpeg and microphone permission."
fi
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  warn "OPENAI_API_KEY is not set. Pi and Voice STT are configured for OpenAI but need that environment variable."
fi

log "Verifying installation"
"$LOCAL_BIN/pi" --version
"$LOCAL_BIN/p" --version
"$LOCAL_BIN/agent-browser" --version

cat <<EOF

Installed successfully.

Open a new terminal, then use:
  pi  Full setup: Voice STT + browser + workflows
  p   Lean setup: Voice STT only, quiet startup

Voice dictation: Option+P on macOS, Alt+P on Linux.
EOF
