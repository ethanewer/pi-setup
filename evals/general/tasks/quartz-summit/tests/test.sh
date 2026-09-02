#!/usr/bin/env bash
# Verifier for quartz-summit.
# Executes the /app/train.py deliverable on hidden fixtures, validates the
# produced /app/artifact, and checks RL policy / edge cases and clustering via
# the agent's own left-behind environment and functions. Writes REWARD to
# /logs/verifier/reward.txt.
set -uo pipefail

LOGS=/logs/verifier
mkdir -p "$LOGS"
reward=0

echo "[verifier] starting quartz-summit"

# 0. deliverable must exist
if [ ! -e /app/train.py ]; then
  echo "[verifier] FAIL: /app/train.py missing" >&2
  echo "0" > "$LOGS/reward.txt"
  exit 0
fi

fail=0

# 1. main scenario (agent's /app/artifact + visible RL/cluster/STS)
if python3 /tests/check.py main; then
  echo "[verifier] main scenario passed"
else
  echo "[verifier] FAIL: main scenario" >&2
  fail=1
fi

# 2. hidden-case generalisation
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
