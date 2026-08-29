#!/usr/bin/env bash
# One arm, one model, one seed: all tasks in parallel.
set -uo pipefail
cd "$(dirname "$0")"
if [ ! -d node_modules ]; then
  echo "Installing eval dependencies (bun install) ..."
  bun install
fi
ARM="${ARM:-agent-browser}"
MODEL="${MODEL:-openrouter/z-ai/glm-5.3-flash}"
SEED="${SEED:-$RANDOM}"
slug=$(echo "${ARM}_${MODEL}" | tr '/:' '__')
RUN_ID="$(date +%Y%m%d-%H%M%S)_${slug}_seed${SEED}"
RUN_DIR="$PWD/results/$RUN_ID"
mkdir -p "$RUN_DIR"
ln -sfn "$RUN_DIR" "$PWD/results/latest"
jq -n --arg arm "$ARM" --arg model "$MODEL" --arg seed "$SEED" \
  '{arm:$arm, model:$model, seed:$seed, startedAt:(now|todate)}' > "$RUN_DIR/meta.json"
pids=()
for t in t1 t2 t3 t4 t5; do
  TASK=$t ARM="$ARM" RUN_DIR="$RUN_DIR" SEED="$SEED" MODEL="$MODEL" bun harness/run-task.ts \
    > "$RUN_DIR/$t.console.log" 2>&1 &
  pids+=($!)
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
echo "ALL TASKS DONE run=$RUN_ID fail=$fail"
