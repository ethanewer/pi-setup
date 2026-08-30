#!/usr/bin/env bash
# Oracle: write the real parser, install it, and run it on the shipped data.
set -euo pipefail

mkdir -p /app
cp /solution/parse.py /app/parse.py
chmod +x /app/parse.py

# Produce every deliverable by RUNNING the parser against the visible fixtures.
python3 /app/parse.py /app/data /app

echo "deliverables:"
ls -l /app/parse.py /app/out.tsv /app/tree.json /app/qdp.tsv
