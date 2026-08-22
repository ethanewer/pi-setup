#!/usr/bin/env bash
# Run the full benchmark for several models, ALL task-runs in parallel.
# Usage: ./run-multi.sh            (default model list below, SEED overridable)
set -uo pipefail
cd "$(dirname "$0")"
if [ ! -d node_modules ]; then
  echo "Installing eval dependencies (bun install) ..."
  bun install
fi

SEED="${SEED:-42}"
MODELS=(
  "openrouter/deepseek/deepseek-v4-flash-0731"
  "openrouter/z-ai/glm-5.2"
  "openrouter/qwen/qwen3.8-max"
  "openai/gpt-5.6-luna"
)
STAMP="$(date +%Y%m%d-%H%M%S)"
BASE="$PWD/results/${STAMP}_multi_seed${SEED}"
mkdir -p "$BASE"
ln -sfn "$BASE" "$PWD/results/latest-multi"

pids=()
for model in "${MODELS[@]}"; do
  slug=$(echo "$model" | tr '/:' '__')
  RUN_DIR="$BASE/$slug"
  mkdir -p "$RUN_DIR"
  jq -n --arg model "$model" --arg seed "$SEED" \
    --arg pi "$(jq -r .version node_modules/@earendil-works/pi-coding-agent/package.json)" \
    '{model:$model, seed:$seed, piVersion:$pi, startedAt:(now|todate)}' > "$RUN_DIR/meta.json"
  for t in t1 t2 t3 t4 t5; do
    TASK=$t RUN_DIR="$RUN_DIR" SEED="$SEED" MODEL="$model" bun harness/run-task.ts \
      > "$RUN_DIR/$t.console.log" 2>&1 &
    pids+=($!)
    echo "started $model $t (pid $!)"
  done
done

fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
echo "ALL TASKS DONE base=$BASE fail=$fail"
