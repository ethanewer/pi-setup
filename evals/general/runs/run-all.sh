#!/bin/bash
# General eval: 765 tasks × {pi(p), terminus-2, claude-code} × {glm-5.3-flash, deepseek-v4-flash-0731}
# 6 sequential runs, 64 concurrent trials each.
set -uo pipefail

HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
export PYTHONPATH=$EVAL/agents

GLM="openrouter/z-ai/glm-5.3-flash"
DSK="openrouter/deepseek/deepseek-v4-flash-0731"

cd "$EVAL"
mkdir -p "$OUT"

run_job() {
  local name=$1; shift
  echo "[rig] $(date -Is) START $name"
  "$HARBOR" run \
    -p tasks \
    -n 64 -k 1 -y -q \
    --job-name "$name" -o "$OUT" \
    "$@" > "$OUT/$name.harness.log" 2>&1
  echo "[rig] $(date -Is) DONE $name rc=$?"
}

# pi with the user's 'p' setup (lean profile: no extensions, no skills)
run_job general-pi-glm      -a p_agent:PAgent -m "$GLM"
run_job general-pi-dsk      -a p_agent:PAgent -m "$DSK"

# terminus-2
run_job general-terminus-glm -a terminus-2 -m "$GLM"
run_job general-terminus-dsk -a terminus-2 -m "$DSK"

# claude-code via OpenRouter's Anthropic-compatible endpoint.
# Harbor keeps the full -m string as ANTHROPIC_MODEL, so pass the bare
# OpenRouter slug (no openrouter/ provider prefix).
export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
run_job general-claude-glm  -a claude-code -m "z-ai/glm-5.3-flash"
run_job general-claude-dsk  -a claude-code -m "deepseek/deepseek-v4-flash-0731"

echo "[rig] ALL 6 RUNS COMPLETE"
