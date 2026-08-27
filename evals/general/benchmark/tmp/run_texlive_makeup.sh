#!/bin/bash
set -u
cd /home/eewer/pi-setup/evals/general/benchmark
PATH="$HOME/.local/bin:$PATH"
for t in item-052-main skill-pdflatex; do
  PYTHONPATH=$PWD/agents harbor run \
    -p tasks/$t \
    -a p_agent:PAgent \
    -m openrouter/deepseek/deepseek-v4-flash-0731 \
    -n 1 -k 1 -y -o jobs --job-name run4-texlive-$t 2>&1 | tail -8
  echo "TEXLIVE-MAKEUP $t EXIT: $?"
done
