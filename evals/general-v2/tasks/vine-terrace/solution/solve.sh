#!/usr/bin/env bash
# Vine Terrace oracle.
# Authors the deliverable program by copying the reference implementation to
# /app/analyze.py, then RUNS it to produce the two output deliverables
# (/app/primers.tsv and /app/adjust.json) from the visible fixtures.
set -euo pipefail

# 1. Deliver the authored program.
cp /solution/analyze.py /app/analyze.py
chmod +x /app/analyze.py

# 2. Run it to produce the output deliverables for the shipped (visible) inputs.
cd /app
python3 /app/analyze.py

# 3. Report what was produced.
echo "oracle: wrote /app/analyze.py, /app/primers.tsv, /app/adjust.json"
ls -l /app/analyze.py /app/primers.tsv /app/adjust.json
