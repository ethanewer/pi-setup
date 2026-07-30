#!/usr/bin/env bash
set -euo pipefail

PI_VERSION="0.83.0"
AGENT_BROWSER_VERSION="0.33.1"

# Upstream versions live in vendor.json, which is what bin/pi-setup-doctor and
# bin/pi-setup-vendor read. They used to be duplicated here as UPSTREAM_* variables that
# nothing consumed, so they could drift from the truth without any check noticing.

# Extensions are installed as Pi "local" packages from forks/ in this repository,
# never from npm. Pi never rewrites local packages, so the security fixes in these
# forks cannot be silently reverted by a later `bun install` or package update.
FORKS="pi-voice-stt-safe pi-agent-browser-native-safe pi-dynamic-workflows-safe pi-context-handoff pi-btw-side pi-process-monitor-safe pi-setup-maintenance"

REPO_URL="${PI_SETUP_REPO_URL:-https://github.com/ethanewer/pi-setup.git}"
REPO_REF="${PI_SETUP_REF:-main}"

log() { printf '\n==> %s\n' "$*"; }
warn() { printf '\nWARNING: %s\n' "$*" >&2; }
fail() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin|Linux) ;;
  *) fail "This installer supports macOS and Linux." ;;
esac
command -v curl >/dev/null 2>&1 || fail "curl is required."
# Bun's installer unpacks a zip, so a machine without unzip fails partway through with a
# confusing error rather than at the door.
if ! command -v bun >/dev/null 2>&1 && [[ ! -x "${BUN_INSTALL:-$HOME/.bun}/bin/bun" ]]; then
  command -v unzip >/dev/null 2>&1 || fail "unzip is required to install Bun (apt install unzip / brew install unzip)."
fi

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
LOCAL_PKG_DIR="$MAIN_DIR/local"
mkdir -p "$LOCAL_BIN" "$MAIN_DIR/bin" "$MAIN_DIR/p" "$NPM_DIR" "$LOCAL_PKG_DIR" "$P_DIR" "$P_DIR/npm"

# Locate forks/. When this script runs from a checkout we use it directly; when it is
# piped from curl we clone the repository so the forks are available.
SRC_DIR=""
SELF="${BASH_SOURCE[0]:-}"
if [[ -n "$SELF" && -f "$SELF" ]]; then
  CANDIDATE="$(cd "$(dirname "$SELF")" && pwd)"
  [[ -d "$CANDIDATE/forks" ]] && SRC_DIR="$CANDIDATE"
fi
if [[ -z "$SRC_DIR" ]]; then
  # `command -v git` is not enough on macOS: /usr/bin/git is a stub that prompts for the
  # Xcode command line tools and exits non-zero, so the clone would fail after the check.
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
[[ -d "$SRC_DIR/forks" ]] || fail "Could not find forks/ in $SRC_DIR."

log "Installing Pi and agent-browser with Bun"
"$BUN_BIN" add --global \
  "@earendil-works/pi-coding-agent@$PI_VERSION" \
  "agent-browser@$AGENT_BROWSER_VERSION"

PI_ROOT="$BUN_INSTALL/install/global/node_modules/@earendil-works/pi-coding-agent"
AGENT_BROWSER_ROOT="$BUN_INSTALL/install/global/node_modules/agent-browser"
[[ -f "$PI_ROOT/dist/bun/cli.js" ]] || fail "Could not find Pi's Bun entrypoint at $PI_ROOT/dist/bun/cli.js"
[[ -f "$AGENT_BROWSER_ROOT/bin/agent-browser.js" ]] || fail "Could not find agent-browser at $AGENT_BROWSER_ROOT"

log "Installing hardened extension forks as Pi local packages"
for fork in $FORKS; do
  [[ -d "$SRC_DIR/forks/$fork" ]] || fail "Missing fork: $SRC_DIR/forks/$fork"
  rm -rf "$LOCAL_PKG_DIR/$fork"
  mkdir -p "$LOCAL_PKG_DIR/$fork"
  # Copy contents rather than the directory itself so the destination path is exact.
  (cd "$SRC_DIR/forks/$fork" && tar cf - --exclude=node_modules .) | (cd "$LOCAL_PKG_DIR/$fork" && tar xf -)
  # Only forks that declare runtime dependencies need an install; the rest resolve
  # everything from Pi's own peer packages.
  if "$BUN_BIN" -e '
    const pkg = require(process.argv[1] + "/package.json");
    process.exit(Object.keys(pkg.dependencies ?? {}).length > 0 ? 0 : 1);
  ' "$LOCAL_PKG_DIR/$fork" 2>/dev/null; then
    printf '    installing dependencies for %s\n' "$fork"
    # Only real runtime dependencies. Pi supplies the peer packages at load time, and
    # installing them here would pull in ~180MB of provider SDKs per fork.
    (cd "$LOCAL_PKG_DIR/$fork" && "$BUN_BIN" install --omit=dev --omit=peer --silent)
  fi
done

# The browser fork ships two CLIs that npm used to link. Local packages get no bin
# links from Pi, so wrap them explicitly to keep both commands available.
for cli in config doctor; do
  TARGET="$LOCAL_PKG_DIR/pi-agent-browser-native-safe/scripts/$cli.mjs"
  if [[ -f "$TARGET" ]]; then
    rm -f "$LOCAL_BIN/pi-agent-browser-$cli"
    cat > "$LOCAL_BIN/pi-agent-browser-$cli" <<SH
#!/bin/sh
set -eu
if command -v bun >/dev/null 2>&1; then
  BUN_BIN="\$(command -v bun)"
else
  BUN_BIN="\${BUN_INSTALL:-\$HOME/.bun}/bin/bun"
fi
exec "\$BUN_BIN" "$TARGET" "\$@"
SH
    chmod 755 "$LOCAL_BIN/pi-agent-browser-$cli"
  fi
done

# Remove before writing: `cat >` follows a symlink and would write through it, clobbering
# whatever it points at rather than replacing the link.
rm -f "$LOCAL_BIN/pi"
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

rm -f "$LOCAL_BIN/agent-browser"
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

rm -f "$LOCAL_BIN/p"
# The one install-time value is printed separately so the body can stay a quoted heredoc:
# the installer honours PI_CODING_AGENT_DIR, so the lean profile must point at the directory
# actually installed into rather than assume ~/.pi/agent, and everything else in the script
# must reach the wrapper verbatim.
{
  printf '#!/bin/sh\nset -eu\nMAIN_DIR="%s"\n' "$MAIN_DIR"
  cat <<'SH'
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
      --extension "$MAIN_DIR/local/pi-voice-stt-safe/extensions/voice-stt/index.ts" \
      --extension "$MAIN_DIR/p/remove-pi-documentation.js" \
      "$@"
  fi
done
echo "p: could not locate @earendil-works/pi-coding-agent" >&2
exit 1
SH
} > "$LOCAL_BIN/p"
chmod 755 "$LOCAL_BIN/pi" "$LOCAL_BIN/p" "$LOCAL_BIN/agent-browser"

# `bun add --global` links its own pi/agent-browser shims into $BUN_INSTALL/bin. They
# point at the same single installation, but they bypass the wrappers above - notably
# pi's guard against inheriting the lean `p` profile - so remove them and leave exactly
# one entrypoint per command.
for shim in pi agent-browser; do
  [[ -e "$BUN_INSTALL/bin/$shim" || -L "$BUN_INSTALL/bin/$shim" ]] && rm -f "$BUN_INSTALL/bin/$shim"
done

log "Writing Pi configuration"
CONFIG_SCRIPT="$(mktemp)"
cat > "$CONFIG_SCRIPT" <<'JS'
import { existsSync, readFileSync, writeFileSync } from "node:fs";
const [mainPath, pPath, sttPath, npmPkgPath, pNpmPkgPath, piVersion, keybindingsSrcPath, mainKeybindsPath, pKeybindsPath] = process.argv.slice(2);
const read = (path) => existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : {};
const writeJson = (path, value) => writeFileSync(path, JSON.stringify(value, null, 2) + "\n");

const main = read(mainPath);
main.lastChangelogVersion ??= piVersion;
main.defaultThinkingLevel = "medium";
main.defaultProvider = "openai";
main.defaultModel = "gpt-5.6-sol";
main.theme ??= "dark";
delete main.quietStartup;

// Every extension is a hardened local fork. The upstream npm identities are dropped
// so a previously npm-installed copy cannot shadow the fork.
const wanted = [
  "local/pi-voice-stt-safe",
  "local/pi-agent-browser-native-safe",
  "local/pi-dynamic-workflows-safe",
  "local/pi-context-handoff",
  "local/pi-btw-side",
  "local/pi-process-monitor-safe",
  "local/pi-setup-maintenance",
];
const managed = new Set([
  "pi-voice-stt",
  "pi-agent-browser-native",
  "@quintinshaw/pi-dynamic-workflows",
  "pi-continue",
  "pi-process-monitor",
  "pi-voice-stt-safe",
  "pi-agent-browser-native-safe",
  "pi-dynamic-workflows-safe",
  "pi-context-handoff",
  "pi-btw-side",
  "pi-process-monitor-safe",
  "pi-setup-maintenance",
  // Unrelated npm packages that also register /btw through a TUI overlay. Listed so an
  // existing install of one is dropped rather than left racing pi-btw-side for the name.
  "pi-btw",
  "pi-render-btw",
  // Renamed: pi-btw-inline became pi-btw-side when it stopped rendering inline.
  "pi-btw-inline",
  // Retired: pi-continue replaced by pi-context-handoff. Listed so an existing
  // local/pi-continue-safe entry is removed rather than left loading alongside.
  "pi-continue-safe",
]);
const identity = (entry) => {
  const source = typeof entry === "string" ? entry : entry?.source;
  if (typeof source !== "string") return "";
  let spec = source.replace(/^npm:/, "");
  if (spec.startsWith("local/")) return spec.slice("local/".length);
  if (spec.startsWith("@")) return spec.split("@").slice(0, 2).join("@");
  return spec.split("@")[0];
};
main.packages = [
  ...(main.packages ?? []).filter((entry) => !managed.has(identity(entry))),
  ...wanted,
];
writeJson(mainPath, main);

const lean = {
  lastChangelogVersion: main.lastChangelogVersion,
  defaultThinkingLevel: main.defaultThinkingLevel,
  defaultProvider: main.defaultProvider,
  defaultModel: main.defaultModel,
  theme: main.theme,
  quietStartup: true,
};
writeJson(pPath, lean);

// Keybindings that a default tmux cannot deliver are remapped here. Only the ids this
// repository manages are touched, so any other binding the user added survives.
// docs/KEYBINDINGS.md records what each one is and why.
const managedKeys = read(keybindingsSrcPath);
for (const path of [mainKeybindsPath, pKeybindsPath]) {
  if (!path) continue;
  writeJson(path, { ...read(path), ...managedKeys });
}

const stt = read(sttPath);
stt.keybind = ["alt+p", "\u03c0"];
stt.provider = {
  type: "openai",
  model: "gpt-4o-mini-transcribe",
  apiKeyEnv: "OPENAI_API_KEY",
  language: "auto",
};
writeJson(sttPath, stt);

// Drop the extensions from the npm manifests so the old, unpatched copies are pruned,
// while leaving any unrelated package the user added in place. The lean profile keeps its
// own agent dir and npm tree, and an unreferenced copy there is still unpatched code on
// disk, so clean both.
let removed = false;
for (const path of [npmPkgPath, pNpmPkgPath]) {
  if (!path) continue;
  const pkg = read(path);
  const deps = pkg.dependencies ?? {};
  for (const name of Object.keys(deps)) {
    if (managed.has(name)) {
      delete deps[name];
      removed = true;
    }
  }
  pkg.private = true;
  pkg.dependencies = deps;
  writeJson(path, pkg);
}
if (removed) console.log("    pruned npm-installed extension copies");
JS
"$BUN_BIN" "$CONFIG_SCRIPT" \
  "$MAIN_DIR/settings.json" \
  "$P_DIR/settings.json" \
  "$MAIN_DIR/stt.json" \
  "$NPM_DIR/package.json" \
  "$P_DIR/npm/package.json" \
  "$PI_VERSION" \
  "$SRC_DIR/config/keybindings.json" \
  "$MAIN_DIR/keybindings.json" \
  "$P_DIR/keybindings.json"
rm -f "$CONFIG_SCRIPT"

# stt.json holds provider and capture configuration that the voice fork re-reads on
# every dictation, so keep it owner-only.
chmod 600 "$MAIN_DIR/stt.json" 2>/dev/null || true

(
  cd "$NPM_DIR"
  "$BUN_BIN" install --production --silent 2>/dev/null || true
)

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
if [[ -x "$SRC_DIR/bin/pi-setup-doctor" ]]; then
  "$SRC_DIR/bin/pi-setup-doctor" --quiet || warn "pi-setup-doctor reported problems; run 'bin/pi-setup-doctor' for detail."
fi

cat <<EOF

Installed successfully.

Open a new terminal, then use:
  pi  Full setup: Voice STT + browser + workflows + handoff briefs + monitor + /btw
  p   Lean setup: Voice STT only, quiet startup

Voice dictation: Option+P (or the π it composes) on macOS, Alt+P on Linux.
Side questions:  /btw <question>, escape to return.
Keybindings:     newline Option+Enter or Ctrl+J, queue Option+Tab. See docs/KEYBINDINGS.md.

Extensions are installed from forks/ as Pi local packages. Run
'bin/pi-setup-doctor' to check that the installed copies still match this
repository and whether upstream has published newer versions.
EOF
