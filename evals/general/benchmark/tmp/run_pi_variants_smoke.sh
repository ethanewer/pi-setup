#!/bin/bash
set -u
cd /home/eewer/pi-setup/evals/general/benchmark
export PATH="/home/eewer/.local/bin:$PATH"
for v in p_variant:PVariantBash p_variant:PVariantBashEdit; do
  n=$(echo $v | cut -d: -f2)
  PYTHONPATH=$PWD/agents timeout 1200 harbor run \
    -p tasks/golden-example \
    -a "$v" \
    -m openrouter/deepseek/deepseek-v4-flash-0731 \
    -n 1 -k 1 -y -o jobs --job-name smoke-$n 2>&1 | tail -6
  echo "SMOKE $n EXIT: $?"
done
