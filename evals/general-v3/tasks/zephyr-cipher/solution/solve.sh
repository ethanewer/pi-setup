#!/bin/bash
# Oracle for zephyr-cipher. Installs a working /app/solve.py (the reference
# solver) and RUNS it on the shipped visible scenario to produce /app/answer.json.
# Does the real work; never reads /tests and never cats a precomputed answer.
set -eu

cp /solution/solve.py /app/solve.py
chmod +x /app/solve.py

python3 /app/solve.py /app/scenario /app

echo "oracle produced /app/answer.json"
