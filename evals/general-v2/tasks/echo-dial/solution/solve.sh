#!/usr/bin/env bash
# Oracle for echo-dial: install the real relay scanner and run it for real
# against /app/relay so every deliverable in /app is produced by doing the work.
set -euo pipefail

install -m 0755 /solution/attack.py /app/attack.py
python3 /app/attack.py /app/relay /app

# sanity: the three deliverables must now exist and be non-empty
[ -s /app/name.txt ]
[ -s /app/plaintexts.txt ]
[ -s /app/word.txt ]

echo "solve.sh: echo-dial oracle complete"
