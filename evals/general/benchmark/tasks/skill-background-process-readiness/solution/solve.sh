#!/bin/bash
set -euo pipefail
python3 /app/worker.py &
while [ ! -f /tmp/worker_ready ]; do sleep 0.05; done
while [ ! -f /tmp/worker_result.txt ]; do sleep 0.05; done
cp /tmp/worker_result.txt /app/result.txt
