#!/bin/bash
set -u
cd /home/eewer/pi-setup/evals/general/benchmark
PATH="/home/eewer/.local/bin:$PATH" harbor run \
  -p tmp/rerun-infra-t2 \
  -a terminus-2 \
  -m openrouter/deepseek/deepseek-v4-flash-0731 \
  --ak 'model_info={"max_input_tokens":1310720,"max_output_tokens":65536}' \
  -n 12 -k 1 -y -o jobs --job-name t2-rerun-infra 2>&1
echo "T2-RERUN-INFRA EXIT CODE: $?"
