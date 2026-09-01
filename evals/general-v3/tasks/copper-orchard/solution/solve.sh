#!/bin/bash
# copper-orchard oracle: install the real solver program into /app and RUN it
# to produce the visible deliverable. This does the actual statistical work; it
# never reads /tests and never cats a precomputed answer.
set -eu

# 1) Write the solver program (the deliverable the agent must also produce).
#    /solution/solver.py is the canonical, correct implementation.
cp /solution/solver.py /app/solve.py
chmod +x /app/solve.py

# 2) Run the program on the visible input to produce the visible deliverable.
python3 /app/solve.py /app/readings.csv /app/answer.json

echo "oracle produced /app/solve.py and /app/answer.json"