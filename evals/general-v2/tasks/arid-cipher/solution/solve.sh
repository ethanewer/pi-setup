#!/usr/bin/env bash
# Oracle: install the close-out pipeline and run it for real against the sample
# input so every deliverable in /app is produced by executing the work.
set -euo pipefail

install -m 0755 /solution/clean.py /app/clean.py
python3 /app/clean.py /app/input /app

# sanity: every declared deliverable must now exist (created by running clean.py)
[ -s /app/result.json ]
[ -s /app/top.tsv ]
[ -s /app/summaries.csv ]
[ -s /app/category_lists.csv ]
[ -s /app/contacts_filtered.csv ]
[ -s /app/hourly.csv ]
[ -s /app/papers.jsonl ]
[ -s /app/trials/trial_00.csv ]
[ -s /app/trials/trial_19.csv ]
echo "solve.sh: close-out complete"
