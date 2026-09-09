#!/usr/bin/env bash
set -euo pipefail

# ocdx — Open Codex. Runs the real Codex CLI against OpenRouter's
# OpenAI-compatible endpoint, on the open-weight models this setup pins. The
# GPT family and every Anthropic model are refused: this profile only ever
# runs the pinned open-weight models. Reasoning defaults to high (written into
# the managed config.toml); /model in the session still adjusts it.
#
# Codex's state lives in CODEX_HOME=~/.pi/agent-ocdx/codex, so sessions and
# config never mix with a personal ~/.codex. The installer writes config.toml
# there: model_provider=openrouter, wire_api=responses, default model glm-flash,
# model_reasoning_effort=high.
#
# Deliberately bash 3.2 compatible (macOS ships 3.2): no associative arrays,
# model lookups are case functions.

HANDLES="ds-flash ds-pro glm-flash glm kimi qwen-flash qwen-max"

slug_for() {
  case "$1" in
    ds-flash)   printf '%s' "deepseek/deepseek-v4-flash-0731" ;;
    ds-pro)     printf '%s' "deepseek/deepseek-v4-pro-0813" ;;
    glm-flash)  printf '%s' "z-ai/glm-5.3-flash" ;;
    glm)        printf '%s' "z-ai/glm-5.3" ;;
    kimi)       printf '%s' "moonshotai/kimi-k3" ;;
    qwen-flash) printf '%s' "qwen/qwen3.8-flash" ;;
    qwen-max)   printf '%s' "qwen/qwen3.8-max-0902" ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: ocdx [--model MODEL] [--effort LEVEL] [--list] [codex args]

MODEL    ds-flash | ds-pro | glm-flash | glm | kimi | qwen-flash | qwen-max,
         or a full OpenRouter slug. Default: glm-flash (from config.toml).
LEVEL    minimal | low | medium | high. Default: high. Passed as
         model_reasoning_effort; /model also works in the session.

Other arguments pass through to codex. Put -- before them if they start with -.
EOF
}

model=""
effort=""
list=0
extra=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) model="${2:-}"; shift 2 ;;
    --model=*) model="${1#*=}"; shift ;;
    --effort) effort="${2:-}"; shift 2 ;;
    --effort=*) effort="${1#*=}"; shift ;;
    --list) list=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; extra+=("$@"); break ;;
    *) extra+=("$1"); shift ;;
  esac
done

if [[ "$list" == 1 ]]; then
  printf '%-11s %s\n' "handle" "OpenRouter slug"
  for k in $HANDLES; do
    printf '%-11s %s\n' "$k" "$(slug_for "$k")"
  done
  exit 0
fi

if [[ -n "$effort" ]]; then
  case "$effort" in
    minimal|low|medium|high) ;;
    *) echo "error: codex effort must be minimal, low, medium, or high (got: $effort)" >&2; exit 2 ;;
  esac
fi

# Resolve MODEL from a handle or accept a raw slug. Empty means "let
# config.toml's default model stand" (glm-flash).
if [[ -n "$model" ]] && slug="$(slug_for "$model")"; then
  model="$slug"
fi

# Never route to a closed-weight model, even by accident: the managed
# config.toml already pins the provider, this keeps the model id honest too.
if [[ "$model" == *claude* || "$model" == *anthropic* || "$model" == *openai/* || "$model" == *gpt* ]]; then
  echo "error: refusing to run a closed-weight model ($model)" >&2
  echo "       ocdx only launches the OpenRouter open-weight models (ocdx --list)" >&2
  exit 2
fi

# OpenRouter key: env var, then ~/.openrouter-key, then pi's credential chain
# (which covers the macOS keychain). Never prompts.
key="${OPENROUTER_API_KEY:-}"
if [[ -z "$key" && -f "$HOME/.openrouter-key" ]]; then
  key="$(<"$HOME/.openrouter-key")"
fi
if [[ -z "$key" ]] && command -v pi >/dev/null 2>&1; then
  key="$(pi auth print-api-key --provider openrouter 2>/dev/null || true)"
fi
key="$(tr -d '[:space:]' <<<"${key:-}")"

if [[ -z "$key" ]]; then
  echo "error: no OpenRouter key found" >&2
  echo "       export OPENROUTER_API_KEY=..., put it in ~/.openrouter-key," >&2
  echo "       or store it with 'pi auth' (provider openrouter)" >&2
  exit 2
fi
if [[ "$key" != sk-or-* ]]; then
  echo "warning: the resolved OpenRouter key does not start with sk-or-" >&2
fi

# Isolated Codex state, with the installer-managed config.toml. The endpoint
# (https://openrouter.ai/api/v1), the responses wire API, the default model, and the
# high reasoning default all come from that file; the key is injected per launch
# (config.toml sets env_key), never written to disk here.
export CODEX_HOME="${CODEX_HOME:-$HOME/.pi/agent-ocdx/codex}"
mkdir -p "$CODEX_HOME"
if [[ ! -f "$CODEX_HOME/config.toml" ]]; then
  echo "error: $CODEX_HOME/config.toml is missing; re-run the pi-setup installer, which writes the openrouter provider config" >&2
  exit 2
fi

# Never let a personal OpenAI or Anthropic credential be auto-detected: drop
# them before codex resolves auth, then inject the OpenRouter key only.
unset OPENAI_API_KEY ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
export OPENROUTER_API_KEY="$key"

args=()
[[ -n "$model" ]] && args+=(-m "$model")
[[ -n "$effort" ]] && args+=(-c "model_reasoning_effort=\"$effort\"")
# Match the cdx alias: skip approvals and sandbox and disable the apps/plugins
# surfaces. The OpenAI developer-docs MCP server is disabled in the managed
# config.toml rather than here - a -c override on an undefined server creates an
# entry without a transport, which codex rejects as invalid.
args+=(--dangerously-bypass-approvals-and-sandbox --disable apps --disable plugins)
# The ${arr[@]+...} guard is for bash 3.2 (macOS): expanding an empty array
# under set -u errors there.
exec codex ${args[@]+"${args[@]}"} ${extra[@]+"${extra[@]}"}
