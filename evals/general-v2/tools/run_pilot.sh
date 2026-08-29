#!/bin/bash
# Model pilot for difficulty calibration (TODO.md 4.3).
# Runs a small panel of independent agents (no reference access: the v2
# containers contain only bench-base + task fixtures) on a task subset.
#
# Usage: bash tools/run_pilot.sh [N_PARALLEL] [TASK_FILTER]
set -euo pipefail
cd "$(dirname "$0")/.."
N="${1:-4}"
FILTER="${2:-}"

TASKS=()
for d in tasks/*/; do
  t="$(basename "$d")"
  if [ -z "$FILTER" ] || [[ "$t" == *"$FILTER"* ]]; then TASKS+=("tasks/$t"); fi
done
echo "pilot tasks: ${#TASKS[@]}"

PYTHONPATH=$PWD/agents harbor run \
  -p "${TASKS[@]}" \
  -a p_agent:PAgent \
  -m openrouter/deepseek/deepseek-v4-flash-0731 \
  -n "$N" -k 1 -y -o /tmp/general-v2-pilot \
  --job-name general-v2-pilot
