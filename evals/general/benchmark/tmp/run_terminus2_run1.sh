#!/bin/bash
set -u
cd /home/eewer/pi-setup/evals/general/benchmark
PATH="$HOME/.local/bin:$PATH" harbor run \
  -p tasks \
  -a terminus-2 \
  -m openrouter/deepseek/deepseek-v4-flash-0731 \
  --ak 'model_info={"max_input_tokens":1310720,"max_output_tokens":65536}' \
  -n 24 -k 1 -y -o jobs --job-name terminus2-deepseek-run-1 2>&1
echo "TERMINUS2-RUN-1 EXIT CODE: $?"
