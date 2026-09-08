#!/bin/bash
# v3.3 re-runs: the 22 published records that shipped with no verifier/reward.txt.
# Same harness, model and flags as run-v31.sh so the new records are comparable
# with the ones they replace. Tasks come from the live suite, so every trial runs
# against the binarized verifiers and the restored fixture files.
#
#   pi/z-ai            8   pi/deepseek        6
#   terminus-2/deepseek 5  claude-code/z-ai   2   claude-code/deepseek 1
set -uo pipefail

HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SETS=/home/ee/general-eval-runs/v33-tasks
export PYTHONPATH=$EVAL/agents

GLM="openrouter/z-ai/glm-5.3-flash"
DSK="openrouter/deepseek/deepseek-v4-flash-0731"

mkdir -p "$OUT"
cd "$EVAL"

run_job() {
  local name=$1 set=$2; shift 2
  local n; n=$(find "$set" -mindepth 1 -maxdepth 1 | wc -l)
  echo "[v33] $(date -Is) START $name ($n tasks)"
  "$HARBOR" run \
    -p "$set" \
    -n 64 -k 1 -y -q \
    --job-name "$name" -o "$OUT" \
    "$@" > "$OUT/$name.harness.log" 2>&1
  local rc=$?
  echo "[v33] $(date -Is) DONE $name rc=$rc"
  local got; got=$(find "$OUT/$name" -name reward.txt 2>/dev/null | wc -l)
  echo "[v33]       rewards written: $got/$n"
  return $rc
}

fail=0
run_job v33-pi-glm  "$SETS/pi-glm" -a p_agent:PAgent -m "$GLM" || fail=1
run_job v33-pi-dsk  "$SETS/pi-dsk" -a p_agent:PAgent -m "$DSK" || fail=1
run_job v33-t2-dsk  "$SETS/t2-dsk" -a terminus-2     -m "$DSK" || fail=1

# claude-code goes through OpenRouter's Anthropic-compatible endpoint. Harbor
# keeps the full -m string as ANTHROPIC_MODEL, so pass the bare slug.
export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
run_job v33-claude-glm "$SETS/claude-glm" -a claude-code -m "z-ai/glm-5.3-flash" \
  --agent-setup-timeout-multiplier 4 -r 2 --retry-include AgentSetupTimeoutError || fail=1
run_job v33-claude-dsk "$SETS/claude-dsk" -a claude-code -m "deepseek/deepseek-v4-flash-0731" \
  --agent-setup-timeout-multiplier 4 -r 2 --retry-include AgentSetupTimeoutError || fail=1

total=$(find "$OUT"/v33-pi-glm "$OUT"/v33-pi-dsk "$OUT"/v33-t2-dsk \
             "$OUT"/v33-claude-glm "$OUT"/v33-claude-dsk \
             -name reward.txt 2>/dev/null | wc -l)
echo "[v33] ALL JOBS FINISHED: $total/22 rewards written, fail=$fail"
