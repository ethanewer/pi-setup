#!/usr/bin/env bash
# Oracle for granite-grove. Creates the deliverable pipeline program and runs it
# (in self-contained mode) against the primary /app/data case so the workspace
# holds both required deliverables: /app/solve.py and /app/answer.json.
set -euo pipefail

# Write the real pipeline program into the workspace.
cp /solution/solve.py /app/solve.py
chmod +x /app/solve.py

# Produce the primary answer by actually running the pipeline's work.
python3 /app/solve.py --case /app/data --out /app/answer.json \
  > /tmp/oracle_run.log 2>&1

echo "oracle produced /app/solve.py and /app/answer.json"