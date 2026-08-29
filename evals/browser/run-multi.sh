#!/usr/bin/env bash
# All arms in parallel (each arm owns its pihome), seeds sequential within an arm.
set -uo pipefail
cd "$(dirname "$0")"
if [ ! -d node_modules ]; then
  echo "Installing eval dependencies (bun install) ..."
  bun install
fi
MODEL="${MODEL:-openrouter/z-ai/glm-5.3-flash}"
ARMS="${ARMS:-agent-browser agent-browser-guided playwright devtools}"
SEEDS="${SEEDS:-101 202 303}"
pids=()
for arm in $ARMS; do
  echo "launching arm=$arm (log: results/arm-${arm}.log)"
  ARM="$arm" MODEL="$MODEL" SEEDS="$SEEDS" ./run.sh > "results/arm-${arm}.log" 2>&1 &
  pids+=($!)
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done
echo "ALL ARMS DONE (fail=$fail)"
for arm in $ARMS; do
  python3 score/aggregate.py "$arm" results/*_${arm}_seed* 2>/dev/null | head -12 || true
done
