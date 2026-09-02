#!/bin/bash
# Oracle for zephyr-grove. Installs the working /app/solver.py (the reference
# scheduling engine), then RUNS it for real on the shipped config to produce the
# three checked deliverables. Never reads /tests and never cats a precomputed
# answer.
set -eu

cp /solution/solve.py /app/solver.py
chmod +x /app/solver.py

python3 /app/solver.py /app/config.json /app

echo "oracle produced /app/solver.py, /app/answer.txt, /app/grid.txt, /app/plans.txt"