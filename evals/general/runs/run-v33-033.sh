#!/usr/bin/env bash
# v1-item-033-hard's verifier was structurally unsolvable: `health` was awarded
# only when the server FAILED to come up, while the other six marks were checked
# only in the else branch, so a working server capped at 6 of 7 and full credit
# was unreachable. Every agent that scored 0.80 had a ready server plus all six
# other marks. Fixing the branch changes what those trials would have scored, so
# all six pairs have to be re-run against the corrected verifier rather than
# rescored arithmetically.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
SETS=/home/ee/general-eval-runs/v33-tasks
export PYTHONPATH=$EVAL/agents
GLM="openrouter/z-ai/glm-5.3-flash"
DSK="openrouter/deepseek/deepseek-v4-flash-0731"
cd "$EVAL"
mkdir -p "$SETS/only-033" "$OUT"
ln -sfn "$EVAL/tasks/v1-item-033-hard" "$SETS/only-033/v1-item-033-hard"

launch() {
  local name=$1; shift
  echo "[033] $(date -Is) LAUNCH $name"
  nohup "$HARBOR" run -p "$SETS/only-033" -n 1 -k 1 -y -q \
    --job-name "$name" -o "$OUT" "$@" > "$OUT/$name.harness.log" 2>&1 &
  echo "[033]   pid $!"
}

launch v33-033-pi-glm  -a p_agent:PAgent -m "$GLM"
launch v33-033-pi-dsk  -a p_agent:PAgent -m "$DSK"
launch v33-033-t2-glm  -a terminus-2     -m "$GLM"
launch v33-033-t2-dsk  -a terminus-2     -m "$DSK"

export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
launch v33-033-claude-glm -a claude-code -m "z-ai/glm-5.3-flash" \
  --agent-setup-timeout-multiplier 4 -r 2 --retry-include AgentSetupTimeoutError
launch v33-033-claude-dsk -a claude-code -m "deepseek/deepseek-v4-flash-0731" \
  --agent-setup-timeout-multiplier 4 -r 2 --retry-include AgentSetupTimeoutError

sleep 15
echo "[033] harbor processes: $(pgrep -cf 'bin/harbor run')"
echo "[033] LAUNCH_033_DONE"
