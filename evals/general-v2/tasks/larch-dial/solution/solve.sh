#!/bin/bash
# Oracle for larch-dial. Installs the real solver into /app and RUNS it on the
# visible fixture to produce /app/answer.json. This does the actual work; it
# never reads /tests and never cats a precomputed answer.
set -eu

cp /solution/solver.py /app/solve.py
chmod +x /app/solve.py

python3 /app/solve.py /app/project /app/weights.json /app/inputs.csv /app/answer.json

echo "oracle produced /app/solve.py and /app/answer.json"