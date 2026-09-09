#!/usr/bin/env bash
set -euo pipefail

# occ — Open Claude Code. Runs the real Claude Code CLI against OpenRouter's
# Anthropic-compatible endpoint, on the open-weight models this setup pins.
# The GPT family and every Anthropic model are refused: this profile only ever
# runs the pinned open-weight models. Reasoning defaults to high; /effort in
# the session still works because CLAUDE_CODE_ALWAYS_ENABLE_EFFORT is set.
#
# Claude Code's state lives in CLAUDE_CONFIG_DIR=~/.pi/agent-occ, so sessions,
# history, and settings never mix with a personal ~/.claude.
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
    qwen-max)   printf '%s' "qwen/qwen3.8-max" ;;
    *) return 1 ;;
  esac
}

# Cheap sibling used for background work (title generation, classifiers) and,
# with --family-tiers, for low/medium effort.
fast_for() {
  case "$1" in
    ds-flash|ds-pro)     slug_for ds-flash ;;
    glm-flash|glm)       slug_for glm-flash ;;
    kimi)                slug_for kimi ;;
    qwen-flash|qwen-max) slug_for qwen-flash ;;
    *) return 1 ;;
  esac
}

# Strong sibling used by --family-tiers for high effort.
full_for() {
  case "$1" in
    ds-flash|ds-pro)     slug_for ds-pro ;;
    glm-flash|glm)       slug_for glm ;;
    kimi)                slug_for kimi ;;
    qwen-flash|qwen-max) slug_for qwen-max ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: occ [--model MODEL] [--effort LEVEL] [--family-tiers] [--list] [claude args]

MODEL    Optional. ds-flash | ds-pro | glm-flash | glm | kimi | qwen-flash |
         qwen-max, or a full OpenRouter slug. Without it, claude starts on the
         default slot and /model switches between the slot-mapped open-weight
         models (haiku: glm-flash, sonnet: ds-flash, opus: glm, fable: ds-pro).
LEVEL    low | medium | high | xhigh | max. Default: high. Forwarded to
         claude --effort; /effort also works in the session.
--family-tiers
         With --model: map low/medium to the family's fast model and
         high/xhigh/max to the family's full model, so effort also picks the
         model. Default: every effort level uses MODEL.

Other arguments pass through to claude. Put -- before them if they start with -.
EOF
}

model=""
effort="high"
family=0
list=0
extra=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) model="${2:-}"; shift 2 ;;
    --model=*) model="${1#*=}"; shift ;;
    --effort) effort="${2:-}"; shift 2 ;;
    --effort=*) effort="${1#*=}"; shift ;;
    --family-tiers) family=1; shift ;;
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

case "$effort" in
  low|medium|high|xhigh|max) ;;
  *) echo "error: effort must be low, medium, high, xhigh, or max (got: $effort)" >&2; exit 2 ;;
esac

# Resolve MODEL from a handle or accept a raw slug. Empty means no launch-time
# pick: claude starts on the default slot and /model selects in-session.
handle=""
if [[ -n "$model" ]]; then
  if slug="$(slug_for "$model")"; then
    handle="$model"
    model="$slug"
  else
    for k in $HANDLES; do
      if [[ "$(slug_for "$k")" == "$model" ]]; then
        handle="$k"
        break
      fi
    done
  fi
fi

# Never route to an Anthropic or GPT model, even by accident: the base URL
# below already pins the endpoint, this keeps the model id honest too.
if [[ "$model" == *claude* || "$model" == *anthropic* || "$model" == *openai/* || "$model" == *gpt* ]]; then
  echo "error: refusing to run a closed-weight model ($model)" >&2
  echo "       occ only launches the OpenRouter open-weight models (occ --list)" >&2
  exit 2
fi

fast="$model"
full="$model"
if [[ -n "$handle" ]]; then
  fast="$(fast_for "$handle")"
  full="$(full_for "$handle")"
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

# Endpoint. Forced, not defaulted: no request may reach Anthropic.
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"

# Never let a personal Anthropic or OpenAI credential be auto-detected: drop
# every OAuth/key variable claude might pick up, then authenticate from the
# resolved OpenRouter key only.
unset OPENAI_API_KEY ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN CLAUDE_CODE_OAUTH_TOKEN
export ANTHROPIC_API_KEY="$key"
export ANTHROPIC_AUTH_TOKEN="$key"

# Model selection. Without --model, the four tier slots expose the pinned
# open-weight models by strength, so /model switches between them in-session
# and the default slot (glm-flash) starts the session. With --model, every
# slot is pinned to the chosen model so the effort selector can never route a
# request to an Anthropic model; effort only changes the thinking budget (or,
# with --family-tiers, moves between the family's fast/full pair).
if [[ -n "$model" ]]; then
  export ANTHROPIC_MODEL="$model"
  export ANTHROPIC_DEFAULT_MODEL="$model"
  if [[ "$family" == 1 ]]; then
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$fast"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$fast"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$full"
    export ANTHROPIC_DEFAULT_FABLE_MODEL="$full"
  else
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$model"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$model"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$model"
    export ANTHROPIC_DEFAULT_FABLE_MODEL="$model"
  fi
  export ANTHROPIC_SMALL_FAST_MODEL="$fast"
else
  export ANTHROPIC_DEFAULT_MODEL="$(slug_for glm-flash)"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="$(slug_for glm-flash)"
  export ANTHROPIC_DEFAULT_SONNET_MODEL="$(slug_for ds-flash)"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="$(slug_for glm)"
  export ANTHROPIC_DEFAULT_FABLE_MODEL="$(slug_for ds-pro)"
  export ANTHROPIC_SMALL_FAST_MODEL="$(slug_for glm-flash)"
fi

# Keep /effort available on model ids Claude Code does not recognize.
export CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1

# Third-party endpoint defaults.
export API_TIMEOUT_MS="${API_TIMEOUT_MS:-600000}"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export DISABLE_TELEMETRY=1

# Isolated Claude Code state: sessions, history, and settings stay here.
export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.pi/agent-occ}"
mkdir -p "$CLAUDE_CONFIG_DIR"

args=(--effort "$effort")
[[ -n "$model" ]] && args+=(--model "$model")
# The ${arr[@]+...} guard is for bash 3.2 (macOS): expanding an empty array
# under set -u errors there.
exec claude "${args[@]}" ${extra[@]+"${extra[@]}"}
