#!/usr/bin/env bash
# Run the benchmark across multiple seeds (one full 6-task run per seed).
# Ports are derived per-run, so multiple invocations can also run concurrently.
set -uo pipefail
cd "$(dirname "$0")"
SEEDS="${SEEDS:-1 2 3}"
MODEL="${MODEL:-openrouter/deepseek/deepseek-v4-flash-0731}"
for s in $SEEDS; do
  echo "=== seed $s ==="
  SEED="$s" MODEL="$MODEL" ./run.sh || echo "!! seed $s failed"
done
