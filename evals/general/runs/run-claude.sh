#!/bin/bash
# Claude-code runs (restarted): 4x agent-setup timeout (claude CLI npm
# install at 64-way concurrency exceeds the default 360s), 2 retries on
# setup timeouts.
set -uo pipefail

HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
cd "$EVAL"
mkdir -p "$OUT"

# OpenRouter Anthropic-compatible endpoint; harbor keeps the full -m string
# as ANTHROPIC_MODEL, so use bare OpenRouter slugs.
export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"

run_job() {
  local name=$1 model=$2
  echo "[rig] $(date -Is) START $name"
  "$HARBOR" run \
    -p tasks \
    -n 64 -k 1 -y -q \
    --agent-setup-timeout-multiplier 4 \
    -r 2 --retry-include AgentSetupTimeoutError \
    --job-name "$name" -o "$OUT" \
    -a claude-code -m "$model" > "$OUT/$name.harness.log" 2>&1
  echo "[rig] $(date -Is) DONE $name rc=$?"
}

run_job general-claude-glm "z-ai/glm-5.3-flash"
run_job general-claude-dsk "deepseek/deepseek-v4-flash-0731"

echo "[rig] CLAUDE RUNS COMPLETE"
