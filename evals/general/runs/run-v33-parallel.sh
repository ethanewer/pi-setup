#!/usr/bin/env bash
# Launch the four remaining v3.3 re-run jobs concurrently.
#
# run-v33.sh ran them sequentially, which put every job behind v1-item-043-hard:
# that task declares a 7200 s agent timeout and a 3600 s verifier timeout and
# runs MCMC in two stacks, so it alone can hold a job for hours, and it appears
# in both pi sets. The machine has 64 CPUs and ~111 GB free against a worst case
# of 14 trials at 2-8 GB each, so the jobs are independent and can overlap.
#
# v33-pi-glm is already running under its own harbor process and is left alone.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SETS=/home/ee/general-eval-runs/v33-tasks
export PYTHONPATH=$EVAL/agents
DSK="openrouter/deepseek/deepseek-v4-flash-0731"
GLM_SLUG="z-ai/glm-5.3-flash"
DSK_SLUG="deepseek/deepseek-v4-flash-0731"
cd "$EVAL"
mkdir -p "$OUT"

launch() {   # launch <job-name> <set> <extra args...>
  local name=$1 set=$2; shift 2
  local n; n=$(find "$set" -mindepth 1 -maxdepth 1 | wc -l)
  echo "[par] $(date -Is) LAUNCH $name ($n tasks)"
  nohup "$HARBOR" run -p "$set" -n 64 -k 1 -y -q \
    --job-name "$name" -o "$OUT" "$@" \
    > "$OUT/$name.harness.log" 2>&1 &
  echo "[par]   pid $!"
}

launch v33-pi-dsk "$SETS/pi-dsk" -a p_agent:PAgent -m "$DSK"
launch v33-t2-dsk "$SETS/t2-dsk" -a terminus-2     -m "$DSK"

# claude-code goes through OpenRouter's Anthropic-compatible endpoint. Harbor
# keeps the whole -m string as ANTHROPIC_MODEL, so pass the bare slug.
export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
launch v33-claude-glm "$SETS/claude-glm" -a claude-code -m "$GLM_SLUG" \
  --agent-setup-timeout-multiplier 4 -r 2 --retry-include AgentSetupTimeoutError
launch v33-claude-dsk "$SETS/claude-dsk" -a claude-code -m "$DSK_SLUG" \
  --agent-setup-timeout-multiplier 4 -r 2 --retry-include AgentSetupTimeoutError

sleep 20
echo "[par] harbor processes now: $(pgrep -cf 'bin/harbor run')"
echo "[par] PARALLEL_LAUNCH_DONE"
