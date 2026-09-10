#!/usr/bin/env bash
# One arm, one model: seeds sequential (browser load), tasks parallel within a seed.
# HARNESS selects the live setup under test: pi | p | occ | ocdx (default pi).
# ARM only applies to HARNESS=pi; other harnesses run their native surface.
set -uo pipefail
cd "$(dirname "$0")"
HARNESS="${HARNESS:-pi}"
case "$HARNESS" in pi|p|occ|ocdx) ;; *) echo "HARNESS must be pi, p, occ, or ocdx (got: $HARNESS)" >&2; exit 2 ;; esac
ARM="${ARM:-agent-browser}"
[ "$HARNESS" != "pi" ] && ARM="none"   # arms are pi's tool-surface dimension
MODEL="${MODEL:-openrouter/z-ai/glm-5.3-flash}"
SEEDS="${SEEDS:-101}"

if [ -z "${OPENROUTER_API_KEY:-}" ] && command -v pi >/dev/null 2>&1; then
  OPENROUTER_API_KEY="$(pi auth print-api-key --provider openrouter 2>/dev/null || true)"
  export OPENROUTER_API_KEY
fi

case "$HARNESS" in
  pi|p) AGENT_VERSION="$(pi --version 2>/dev/null | tail -1)" ;;
  occ)  AGENT_VERSION="$(claude --version 2>/dev/null | head -1)" ;;
  ocdx) AGENT_VERSION="$(codex --version 2>/dev/null | head -1)" ;;
esac

for seed in $SEEDS; do
  slug=$(echo "${HARNESS}_${ARM}_${MODEL}" | tr '/:~' '___')
  RUN_ID="$(date +%Y%m%d-%H%M%S)_${slug}_seed${seed}"
  RUN_DIR="$PWD/results/$RUN_ID"
  mkdir -p "$RUN_DIR"
  ln -sfn "$RUN_DIR" "$PWD/results/latest-${HARNESS}-${ARM}"
  jq -n --arg arm "$ARM" --arg model "$MODEL" --arg seed "$seed" --arg harness "$HARNESS" --arg ver "$AGENT_VERSION" \
    '{arm:$arm, model:$model, seed:$seed, harness:$harness, agentVersion:$ver, piVersion:$ver, startedAt:(now|todate)}' > "$RUN_DIR/meta.json"
  pids=()
  for t in t1 t2 t3 t4 t5; do
    TASK=$t ARM="$ARM" RUN_DIR="$RUN_DIR" SEED="$seed" MODEL="$MODEL" HARNESS="$HARNESS" bun harness/run-task.ts \
      > "$RUN_DIR/$t.console.log" 2>&1 &
    pids+=($!)
  done
  fail=0
  for p in "${pids[@]}"; do wait "$p" || fail=1; done
  echo "harness=$HARNESS arm=$ARM seed=$seed done (fail=$fail): $RUN_ID"
  sleep 5
done
