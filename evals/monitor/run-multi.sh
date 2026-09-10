#!/usr/bin/env bash
# Run the full benchmark for several harnesses x models x seeds, ALL task-runs
# in parallel. Harnesses resolve from the LIVE setup (no pins in this eval).
# Usage: ./run-multi.sh   (defaults: harnesses "pi", 3 seeds, model list below)
set -uo pipefail
cd "$(dirname "$0")"

if [ -z "${OPENROUTER_API_KEY:-}" ] && command -v pi >/dev/null 2>&1; then
  OPENROUTER_API_KEY="$(pi auth print-api-key --provider openrouter 2>/dev/null || true)"
  export OPENROUTER_API_KEY
fi

HARNESSES="${HARNESSES:-pi}"
SEEDS="${SEEDS:-1 2 3}"
MODELS=(
  "openrouter/deepseek/deepseek-v4-flash-0731"
  "openrouter/z-ai/glm-5.2"
  "openrouter/qwen/qwen3.8-max"
  "openai/gpt-5.6-luna"
)
STAMP="$(date +%Y%m%d-%H%M%S)"
BASE="$PWD/results/${STAMP}_multi"
mkdir -p "$BASE"
ln -sfn "$BASE" "$PWD/results/latest-multi"

agent_version() {
  case "$1" in
    pi|p) pi --version 2>/dev/null | tail -1 ;;
    occ)  claude --version 2>/dev/null | head -1 ;;
    ocdx) codex --version 2>/dev/null | head -1 ;;
  esac
}

pids=()
for harness in $HARNESSES; do
  VER="$(agent_version "$harness")"
  for model in "${MODELS[@]}"; do
    slug=$(echo "$model" | tr '/:' '__')
    for seed in $SEEDS; do
      RUN_DIR="$BASE/${harness}_${slug}_seed${seed}"
      mkdir -p "$RUN_DIR"
      jq -n --arg model "$model" --arg seed "$seed" --arg harness "$harness" --arg ver "$VER" \
        '{model:$model, seed:$seed, harness:$harness, agentVersion:$ver, piVersion:$ver, startedAt:(now|todate)}' \
        > "$RUN_DIR/meta.json"
      for t in t1 t2 t3 t4 t5 t6 t7; do
        TASK=$t RUN_DIR="$RUN_DIR" SEED="$seed" MODEL="$model" HARNESS="$harness" \
          bash harness/launch-task.sh > "$RUN_DIR/$t.console.log" 2>&1 &
        pids+=($!)
        echo "started $harness $model seed=$seed $t (pid $!)"
      done
    done
  done
done

fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
echo "ALL TASKS DONE base=$BASE fail=$fail"
