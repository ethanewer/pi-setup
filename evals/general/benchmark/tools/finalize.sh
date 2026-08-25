#!/bin/bash
# Final benchmark run: single harbor invocation (parallel harbor runs
# on overlapping scratch dirs corrupt state).
set -u
cd "$(dirname "$0")/.."
docker network prune -f >/dev/null 2>&1
PYTHONPATH=$PWD/agents harbor run \
  -p tasks -a p_agent:PAgent \
  -m openrouter/deepseek/deepseek-v4-flash-0731 \
  -n 24 -k 1 -y -o jobs --job-name deepseek-flash-run-3
echo FINAL_RUN_EXIT=$?
