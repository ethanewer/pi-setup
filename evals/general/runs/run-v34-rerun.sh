#!/usr/bin/env bash
# v3.4 re-runs: every task repaired for this release, across all six pairs.
#
# A repaired task invalidates the records already published for it, and it
# invalidates them for every pair, not only for the pairs that failed. Re-running
# only the failures would re-roll the dice for losses and never for wins, which
# biases the scoreboard upward, so each repaired task is re-run for all six
# harness/model combinations and the whole row is replaced.
#
# Concurrency is per job. Six jobs at -n 5 caps the fleet at 30 concurrent trials;
# with these tasks declaring 1 CPU and 2048 MB each that is about 60 GB against
# the ~110 GB available, and it leaves headroom for the verifier steps that follow
# each rollout.
set -uo pipefail
ROOT=/home/ee/pi-setup
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=$ROOT/evals/general
OUT=/home/ee/general-eval-runs/jobs
SET=/home/ee/general-eval-runs/v34-tasks/rerun
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
# OPENROUTER_API_KEY lives in the home .env; the repository .env carries only
# HF_TOKEN. Sourcing the wrong one launches six jobs that all fail auth.
set -a; . /home/ee/.env; set +a
[ -n "${OPENROUTER_API_KEY:-}" ] || { echo "FATAL: OPENROUTER_API_KEY not set" >&2; exit 1; }
echo "[rerun] OPENROUTER_API_KEY present (${#OPENROUTER_API_KEY} chars)"

GLM="openrouter/z-ai/glm-5.3-flash"
DSK="openrouter/deepseek/deepseek-v4-flash-0731"
GLM_SLUG="z-ai/glm-5.3-flash"
DSK_SLUG="deepseek/deepseek-v4-flash-0731"

mkdir -p "$SET" "$OUT"
rm -f "$SET"/*
# Only tasks whose repair was confirmed by an oracle run earning reward 1.
while read -r T; do
  [ -z "$T" ] && continue
  ln -sfn "$EVAL/tasks/$T" "$SET/$T"
done < /tmp/v34_rerun_tasks.txt
n=$(find "$SET" -mindepth 1 -maxdepth 1 | wc -l)
echo "[rerun] $(date -Is) $n repaired tasks x 6 pairs = $((n * 6)) trials"

launch() {   # launch <job-name> <extra args...>
  local name=$1; shift
  echo "[rerun] $(date -Is) LAUNCH $name"
  nohup "$HARBOR" run -p "$SET" -n 5 -k 1 -y -q \
    --job-name "$name" -o "$OUT" "$@" \
    > "$OUT/$name.harness.log" 2>&1 &
  echo "[rerun]   pid $!"
}

launch v34-pi-glm     -a p_agent:PAgent -m "$GLM"
launch v34-pi-dsk     -a p_agent:PAgent -m "$DSK"
launch v34-t2-glm     -a terminus-2     -m "$GLM"
launch v34-t2-dsk     -a terminus-2     -m "$DSK"

# claude-code goes through OpenRouter's Anthropic-compatible endpoint. Harbor
# keeps the whole -m string as ANTHROPIC_MODEL, so pass the bare slug.
export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
launch v34-claude-glm -a claude-code -m "$GLM_SLUG" \
  --agent-setup-timeout-multiplier 4 -r 2 --retry-include AgentSetupTimeoutError
launch v34-claude-dsk -a claude-code -m "$DSK_SLUG" \
  --agent-setup-timeout-multiplier 4 -r 2 --retry-include AgentSetupTimeoutError

sleep 30
echo "[rerun] $(date -Is) harbor processes: $(pgrep -cf 'harbor run')"
echo "RERUN_LAUNCHED"
