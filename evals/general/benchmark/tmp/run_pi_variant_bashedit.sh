#!/bin/bash
set -u
cd /home/eewer/pi-setup/evals/general/benchmark
PYTHONPATH=$PWD/agents PATH="/home/eewer/.local/bin:$PATH" harbor run \
  -p tasks \
  -a p_variant:PVariantBashEdit \
  -m openrouter/deepseek/deepseek-v4-flash-0731 \
  -n 24 -k 1 -y -o jobs --job-name pi-bashedit-run-1 2>&1
echo "PI-BASHEDIT-RUN-1 EXIT CODE: $?"
