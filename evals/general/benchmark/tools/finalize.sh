#!/bin/bash
# Post-oracle: launch final benchmark run.
set -u
cd "$(dirname "$0")/.."
docker network prune -f >/dev/null 2>&1
PYTHONPATH=$PWD/agents harbor run \
  -p tasks -a p_agent:PAgent \
  -m openrouter/deepseek/deepseek-v4-flash-0731 \
  -n 24 -k 1 -y -o jobs --job-name deepseek-flash-run-2
echo FINAL_RUN_EXIT=$?
