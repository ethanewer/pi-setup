#!/bin/bash
# Real oracle for flint-ember. Installs the reference pipeline program into
# /app/solve.py, then RUNS it on the visible input to emit every required
# artifact by actually doing the work. Does not read /tests and never cats a
# precomputed answer.
set -eu

cp /solution/solve.py /app/solve.py
chmod +x /app/solve.py

# Run the program (default workdir = /app) to produce the required outputs.
python3 /app/solve.py /app

# Confirm every required deliverable was actually created by running it.
for f in /app/plans.jsonl /app/decision.txt /app/result.csv \
          /app/output/results.json /app/answer.json /app/ledger.xlsx; do
  [ -f "$f" ] || { echo "oracle did not create $f" >&2; exit 1; }
done