#!/bin/bash
set -u
cd /home/eewer/pi-setup/evals/general/benchmark
PYTHONPATH=$PWD/agents PATH="$HOME/.local/bin:$PATH" harbor run \
  -p tasks \
  -a p_agent:PAgent \
  -m openrouter/deepseek/deepseek-v4-flash-0731 \
  -n 24 -k 1 -y -o jobs --job-name pi-run-4-postfix 2>&1
echo "PI-RUN-4 EXIT CODE: $?"
