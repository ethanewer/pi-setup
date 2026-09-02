#!/usr/bin/env bash
# One arm, one model: seeds sequential (browser load), tasks parallel within a seed.
set -uo pipefail
cd "$(dirname "$0")"
if [ ! -d node_modules ]; then
  echo "Installing eval dependencies (bun install) ..."
  bun install
fi
ARM="${ARM:-agent-browser}"
MODEL="${MODEL:-openrouter/z-ai/glm-5.3-flash}"
SEEDS="${SEEDS:-101}"
for seed in $SEEDS; do
  slug=$(echo "${ARM}_${MODEL}" | tr '/:~' '___')
  RUN_ID="$(date +%Y%m%d-%H%M%S)_${slug}_seed${seed}"
  RUN_DIR="$PWD/results/$RUN_ID"
  mkdir -p "$RUN_DIR"
  ln -sfn "$RUN_DIR" "$PWD/results/latest-${ARM}"
  jq -n --arg arm "$ARM" --arg model "$MODEL" --arg seed "$seed" \
    '{arm:$arm, model:$model, seed:$seed, startedAt:(now|todate)}' > "$RUN_DIR/meta.json"
  pids=()
  for t in t1 t2 t3 t4 t5; do
    TASK=$t ARM="$ARM" RUN_DIR="$RUN_DIR" SEED="$seed" MODEL="$MODEL" bun harness/run-task.ts \
      > "$RUN_DIR/$t.console.log" 2>&1 &
    pids+=($!)
  done
  fail=0
  for p in "${pids[@]}"; do wait "$p" || fail=1; done
  echo "arm=$ARM seed=$seed done (fail=$fail): $RUN_ID"
  sleep 5
done
