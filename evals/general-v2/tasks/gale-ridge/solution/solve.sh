#!/usr/bin/env bash
# Gale Ridge oracle: install the real workflow as the deliverable and run it,
# producing /app/artifact plus a live mlflow server. Uses only /app paths.
set -euo pipefail

cp /solution/solve.py /app/workflow.py
chmod +x /app/workflow.py

python3 /app/workflow.py --config /app/config.json --out /app/artifact

echo "solve.sh done"