#!/bin/bash
# Final benchmark run: `p` agent (lean pi profile) + deepseek-v4-flash.
# Usage: tools/run_final.sh [concurrency=24] [job-name=deepseek-flash-run-2]
set -u
cd "$(dirname "$0")/.."
N="${1:-24}"
JOB="${2:-deepseek-flash-run-2}"
PYTHONPATH=$PWD/agents harbor run \
  -p tasks \
  -a p_agent:PAgent \
  -m openrouter/deepseek/deepseek-v4-flash-0731 \
  -n "$N" -k 1 -y -o jobs --job-name "$JOB" 2>&1 | tail -40
