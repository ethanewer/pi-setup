#!/bin/bash
# juniper-quill oracle. Installs the reference recovery program at /app/recover.py
# and RUNS it so every deliverable is produced by doing the real work. Does not
# read /tests and never cats a precomputed answer.
set -eu

cp /solution/recover.py /app/recover.py
chmod +x /app/recover.py

# Produce every deliverable by actually running the recovery pipeline.
python3 /app/recover.py /app

# Confirm every required deliverable was created by running the work.
[ -f /app/merged.json ] || { echo "oracle: missing merged.json" >&2; exit 1; }
[ -f /app/fd.txt ]      || { echo "oracle: missing fd.txt" >&2; exit 1; }
[ -f /app/warehouse/clean.db ] || { echo "oracle: missing clean.db" >&2; exit 1; }
for t in $(seq 1 20); do
  [ -f "/app/trial_$t.csv" ] || { echo "oracle: missing trial_$t.csv" >&2; exit 1; }
done

# Oracle creates the full /app/trial_*.csv family (trial_1.csv..trial_20.csv).
# Confirm the wildcard actually expands to all 20 trial deliverables.
count=$(compgen -G "/app/trial_*.csv" | wc -l)
[ "$count" -eq 20 ] || { echo "oracle: expected 20 files matching /app/trial_*.csv, got $count" >&2; exit 1; }
