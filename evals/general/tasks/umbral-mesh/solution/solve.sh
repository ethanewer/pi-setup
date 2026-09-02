#!/bin/bash
# umbral-mesh oracle. Installs the reference solver at /app/solve.py and RUNS it
# on the visible fixtures to produce /app/recovered_edges.csv. Never reads /tests.
set -eu

cp /solution/solve.py /app/solve.py
chmod +x /app/solve.py

python3 /app/solve.py /app/telemetry.csv /app/spec.json /app/recovered_edges.csv

[ -f /app/solve.py ] || { echo "oracle: missing /app/solve.py" >&2; exit 1; }
[ -f /app/recovered_edges.csv ] || { echo "oracle: missing /app/recovered_edges.csv" >&2; exit 1; }
echo "oracle done: /app/solve.py and /app/recovered_edges.csv"
