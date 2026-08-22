#!/usr/bin/env bash
# Launch all 6 benchmark tasks in parallel against one model.
set -uo pipefail
cd "$(dirname "$0")"
if [ ! -d node_modules ]; then
  echo "Installing eval dependencies (bun install) ..."
  bun install
fi
MODEL="${MODEL:-openrouter/deepseek/deepseek-v4-flash-0731}"
SEED="${SEED:-$RANDOM}"
slug=$(echo "$MODEL" | tr '/:' '__')
RUN_ID="$(date +%Y%m%d-%H%M%S)_${slug}_seed${SEED}"
RUN_DIR="$PWD/results/$RUN_ID"
mkdir -p "$RUN_DIR"
ln -sfn "$RUN_DIR" "$PWD/results/latest"
jq -n --arg model "$MODEL" --arg seed "$SEED" \
  --arg pi "$(jq -r .version node_modules/@earendil-works/pi-coding-agent/package.json)" \
  '{model:$model, seed:$seed, piVersion:$pi, startedAt:(now|todate)}' > "$RUN_DIR/meta.json"
pids=()
for t in t1 t2 t3 t4 t5 t6; do
  TASK=$t RUN_DIR="$RUN_DIR" SEED="$SEED" MODEL="$MODEL" bun harness/run-task.ts \
    > "$RUN_DIR/$t.console.log" 2>&1 &
  pids+=($!)
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
echo "ALL TASKS DONE run=$RUN_ID fail=$fail"
