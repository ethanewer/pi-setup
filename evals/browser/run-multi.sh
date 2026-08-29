#!/usr/bin/env bash
# All arms x seeds: tasks run in parallel within an arm, arms run sequentially
# so browser daemons and profile directories never interact.
set -uo pipefail
cd "$(dirname "$0")"
if [ ! -d node_modules ]; then
  echo "Installing eval dependencies (bun install) ..."
  bun install
fi
MODEL="${MODEL:-openrouter/z-ai/glm-5.3-flash}"
ARMS="${ARMS:-agent-browser agent-browser-guided playwright devtools}"
SEEDS="${SEEDS:-101 202 303}"
SUMMARY="$PWD/results/latest-multi"
: > "$SUMMARY"
for arm in $ARMS; do
  for seed in $SEEDS; do
    echo "=== arm=$arm seed=$seed ==="
    ARM="$arm" MODEL="$MODEL" SEED="$seed" ./run.sh | tail -1
  done
done
echo "multi run complete; per-arm summaries:"
for a in $ARMS; do
  python3 score/aggregate.py $a results/*_${a}_seed* 2>/dev/null || true
done
