#!/usr/bin/env bash
# v1-item-041-hard's environment changed (base image ubuntu-24.04 -> node-22 so
# the verifier's `node tools/run.js` resolves), so its six published records no
# longer reflect the task as specified. Two claude-code runs had scored 1.0 and
# four scored 0.4, which was an artifact of whether the agent happened to put
# node on PATH for the verifier, not of whether it solved the task.
#
# The corrected image is already built and the oracle scores 1 against it, so
# these six jobs can share it.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SETS=/home/ee/general-eval-runs/v33-tasks
export PYTHONPATH=$EVAL/agents
GLM="openrouter/z-ai/glm-5.3-flash"
DSK="openrouter/deepseek/deepseek-v4-flash-0731"
cd "$EVAL"
mkdir -p "$SETS/only-041h" "$OUT"
ln -sfn "$EVAL/tasks/v1-item-041-hard" "$SETS/only-041h/v1-item-041-hard"

launch() {
  local name=$1; shift
  echo "[041] $(date -Is) LAUNCH $name"
  nohup "$HARBOR" run -p "$SETS/only-041h" -n 1 -k 1 -y -q \
    --job-name "$name" -o "$OUT" "$@" > "$OUT/$name.harness.log" 2>&1 &
  echo "[041]   pid $!"
}

launch v33-041h-pi-glm  -a p_agent:PAgent -m "$GLM"
launch v33-041h-pi-dsk  -a p_agent:PAgent -m "$DSK"
launch v33-041h-t2-glm  -a terminus-2     -m "$GLM"
launch v33-041h-t2-dsk  -a terminus-2     -m "$DSK"

export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
launch v33-041h-claude-glm -a claude-code -m "z-ai/glm-5.3-flash" \
  --agent-setup-timeout-multiplier 4 -r 2 --retry-include AgentSetupTimeoutError
launch v33-041h-claude-dsk -a claude-code -m "deepseek/deepseek-v4-flash-0731" \
  --agent-setup-timeout-multiplier 4 -r 2 --retry-include AgentSetupTimeoutError

sleep 15
echo "[041] harbor processes: $(pgrep -cf 'bin/harbor run')"
echo "[041] LAUNCH_041_DONE"
