#!/usr/bin/env bash
# Oracle for tundra-ledge.
# Installs the real solver at /app/solve.py and RUNS it so every deliverable
# (/app/answer.json, /app/chess_state.pt) is produced by doing the work.
set -euo pipefail

install -m 0755 /solution/solve.py /app/solve.py
python3 /app/solve.py >/tmp/solve_oracle.log 2>&1

# sanity: deliverables now exist and are non-empty
[ -s /app/answer.json ]
[ -s /app/chess_state.pt ]
echo "solve.sh: tundra-ledge deliverable produced"