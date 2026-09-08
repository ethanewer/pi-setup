#!/usr/bin/env bash
# Retry the two claude-code/glm trials from v39-cc-glm-fixed that never measured
# anything: hinge-lathe (AgentSetupTimeoutError, zero-byte log, never started) and
# sable-quill (ApiConnectionClosedError after one synthetic message and no tool
# use). The other four from that job are valid and are published as they stand.
#
# The guard below is the corrected one. Its first version summed input_tokens and
# total_cost_usd from the trial log and condemned five of six trials. That was
# wrong: claude-code emits those fields only in its final result event, which
# never lands when harbor kills the CLI on an agent timeout. ashen-vane did 58
# real model turns and 25 tool calls and still reported zero usage, and it passed.
# Counting real assistant turns and tool_use blocks separates a run where the
# model was never reached from a run that was killed while working.
set -uo pipefail
HARBOR=/home/ee/general-eval-runs/venv/bin/harbor
EVAL=/home/ee/pi-setup/evals/general
OUT=/home/ee/general-eval-runs/jobs
ROOT=/home/ee/general-eval-runs/v39-tasks
JOB=v39-cc-glm-retry
export PYTHONPATH=$EVAL/agents
cd "$EVAL" || exit 1
set -a; . /home/ee/.env; set +a

# OpenRouter's Anthropic-compatible endpoint, exactly as run-all.sh sets it.
# Omitting these two is what made the first v39 attempt a silent no-op.
export ANTHROPIC_API_KEY="$OPENROUTER_API_KEY"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
[ -n "$ANTHROPIC_API_KEY" ] || { echo "FATAL: OPENROUTER_API_KEY empty"; exit 1; }
echo "[retry] BASE_URL=$ANTHROPIC_BASE_URL key=yes"

rm -rf "$ROOT/cc-retry"; mkdir -p "$ROOT/cc-retry"
for t in hinge-lathe sable-quill; do ln -sfn "$EVAL/tasks/$t" "$ROOT/cc-retry/$t"; done
echo "[retry] $(date -Is) START $(ls "$ROOT/cc-retry" | wc -l) tasks"

"$HARBOR" run -p "$ROOT/cc-retry" -n 2 -k 1 -y -q --job-name "$JOB" -o "$OUT" \
  -a claude-code -m "z-ai/glm-5.3-flash" > "$OUT/$JOB.harness.log" 2>&1
echo "[retry] $(date -Is) harbor rc=$?"
echo "[retry] guard: did the model actually answer?"
GUARD_OUT=$(python3 "$EVAL/tools/check_agent_actually_ran.py" --job "$OUT/$JOB" --harness claude-code)
echo "$GUARD_OUT"
guard=$?
echo "[retry] $(date -Is) guard rc=$guard"
echo "RETRY_DONE guard=$guard"
exit $guard
