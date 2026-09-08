#!/bin/bash
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/smoke
export PYTHONPATH=$EVAL/agents
cd "$EVAL"
mkdir -p "$OUT"

smoke() {
  local name=$1; shift
  echo "=== SMOKE START $name"
  "$HARBOR" run -p /home/ee/general-eval-runs/smoke-tasks \
    -n 2 -k 1 -y -q --job-name "$name" -o "$OUT" "$@" > "$OUT/$name.log" 2>&1
  echo "=== SMOKE DONE $name rc=$?"
}

smoke smoke-pi      -a p_agent:PAgent -m openrouter/z-ai/glm-5.3-flash
smoke smoke-terminus -a terminus-2   -m openrouter/z-ai/glm-5.3-flash
ANTHROPIC_API_KEY="$OPENROUTER_API_KEY" ANTHROPIC_BASE_URL="https://openrouter.ai/api" \
  smoke smoke-claude -a claude-code  -m z-ai/glm-5.3-flash
echo "=== SMOKE ALL DONE"
