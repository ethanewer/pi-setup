#!/bin/bash
set -u
cd /home/eewer/pi-setup/evals/general/benchmark
PATH="$HOME/.local/bin:$PATH" timeout 1200 harbor run \
  -p tasks/golden-example \
  -a terminus-2 \
  -m openrouter/deepseek/deepseek-v4-flash-0731 \
  --ak 'model_info={"max_input_tokens":1310720,"max_output_tokens":65536}' \
  -n 1 -k 1 -y -o jobs --job-name smoke-terminus2 2>&1
echo "TERMINUS2-SMOKE EXIT CODE: $?"
