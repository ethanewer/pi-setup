#!/usr/bin/env bash
# raven-anchor oracle: install the close-out pipeline and run it for real
# against the visible fixtures so every deliverable is produced under /app by
# executing the work. Never reads /tests or the verifier tree.
set -euo pipefail

install -m 0755 /solution/clean.py /app/clean.py
python3 /app/clean.py /app/data /app

# sanity: the literal /app deliverables must now exist
[ -s /app/aggregated.csv ]
[ -s /app/summary.csv ]
[ -s /app/result.json ]
[ -s /app/projects_grouped.csv ]
[ -s /app/filtered.csv ]
[ -s /app/top.tsv ]
[ -s /app/series_filled.csv ]
[ -s /app/papers.jsonl ]
echo "solve.sh: RAven-MART CLOSE-OUT complete"