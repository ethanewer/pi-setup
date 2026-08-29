#!/usr/bin/env bash
# Verifier for tundra-ledge.
# Executes the /app/solve.py deliverable, validates the produced /app/answer.json
# and /app/chess_state.pt against independent references (main), and re-runs the
# solver's core routines on hidden fixtures (hidden). Writes REWARD to
# /logs/verifier/reward.txt.
set -uo pipefail

LOGS=/logs/verifier
mkdir -p "$LOGS"
reward=0

echo "[verifier] starting tundra-ledge"

# 0. deliverable script must exist
if [ ! -e /app/solve.py ]; then
  echo "[verifier] FAIL: /app/solve.py missing" >&2
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi

# 1. execute the deliverable on the /app scenario
if ! python3 /app/solve.py >/tmp/solve.log 2>&1; then
  echo "[verifier] FAIL: /app/solve.py did not run cleanly" >&2
  tail -5 /tmp/solve.log >&2
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi

fail=0

# 2. main scenario validation
if python3 /tests/check.py main; then
  echo "[verifier] main scenario passed"
else
  echo "[verifier] FAIL: main scenario" >&2
  fail=1
fi

# 3. hidden-case generalisation
if python3 /tests/check.py hidden; then
  echo "[verifier] hidden cases passed"
else
  echo "[verifier] FAIL: hidden cases" >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  reward=1
  echo "[verifier] REWARD=1"
else
  reward=0
  echo "[verifier] FAILED: REWARD=0"
fi
echo "$reward" > "$LOGS/reward.txt"
exit 0