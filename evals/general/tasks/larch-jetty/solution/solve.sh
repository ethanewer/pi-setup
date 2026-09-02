#!/bin/bash
# Meridian back-office consolidator (oracle).
# Writes the deliverable program /app/solve.py, then RUNS it on /app/data to
# produce /app/answer.json. Never reads /tests.
set -e

mkdir -p /app
cp /solution/solve.py /app/solve.py
chmod +x /app/solve.py
python3 /app/solve.py /app/data /app/answer.json
echo "oracle finished; answer written:"
ls -l /app/answer.json