#!/bin/bash
# v3.1 runs: 23 new tasks × all 6 harness/model pairs.
# terminus-2 additionally re-runs the fixed calm-canyon (memory bump does not
# affect pi/claude-code, whose v3.0 calm-canyon results stand).
set -uo pipefail

HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
export PYTHONPATH=$EVAL/agents

GLM="openrouter/z-ai/glm-5.3-flash"
DSK="openrouter/deepseek/deepseek-v4-flash-0731"

NEW="amber-engine amber-guest dusk-wicket ember-spire glacier-basin kelp-berth
marble-ridge marrow-vault myrtle-hearth pearl-gasket pewter-meridian
pipit-archive raven-core river-ferry sable-journal sable-wharf sedge-hearth
umbral-inlet velvet-terrace frost-link fume-wheel meadow-mural rust-orchid"

SET_NEW=/home/ee/general-eval-runs/v31-tasks/new
SET_TERM=/home/ee/general-eval-runs/v31-tasks/term
mkdir -p "$SET_NEW" "$SET_TERM"
for t in $NEW; do ln -sfn "$EVAL/tasks/$t" "$SET_NEW/$t"; ln -sfn "$EVAL/tasks/$t" "$SET_TERM/$t"; done
ln -sfn "$EVAL/tasks/calm-canyon" "$SET_TERM/calm-canyon"

cd "$EVAL"
run_job() {
  local name=$1 set=$2; shift 2
  echo "[rig] $(date -Is) START $name ($(ls "$set" | wc -l) tasks)"
  "$HARBOR" run \
    -p "$set" \
    -n 64 -k 1 -y -q \
    --job-name "$name" -o "$OUT" \
    "$@" > "$OUT/$name.harness.log" 2>&1
  echo "[rig] $(date -Is) DONE $name rc=$?"
}

run_job general-v31-pi-glm       "$SET_NEW"  -a p_agent:PAgent -m "$GLM"
run_job general-v31-pi-dsk       "$SET_NEW"  -a p_agent:PAgent -m "$DSK"
run_job general-v31-terminus-glm "$SET_TERM" -a terminus-2 -m "$GLM"
run_job general-v31-terminus-dsk "$SET_TERM" -a terminus-2 -m "$DSK"

export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
run_job general-v31-claude-glm "$SET_NEW" -a claude-code -m "z-ai/glm-5.3-flash" \
  --agent-setup-timeout-multiplier 4 -r 2 --retry-include AgentSetupTimeoutError
run_job general-v31-claude-dsk "$SET_NEW" -a claude-code -m "deepseek/deepseek-v4-flash-0731" \
  --agent-setup-timeout-multiplier 4 -r 2 --retry-include AgentSetupTimeoutError

echo "[rig] V31 RUNS COMPLETE"
