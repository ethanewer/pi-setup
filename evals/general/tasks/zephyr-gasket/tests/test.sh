#!/bin/bash
# Verifier entrypoint for zephyr-gasket (executes-deliverable).
# Re-invokes /app/solve.py on visible + hidden fixtures, independently checks
# the outputs against the reference, and writes the numeric reward.
set -u
mkdir -p /logs/verifier

python3 /tests/check.py
if [ ! -s /logs/verifier/reward.txt ]; then
  echo "0" > /logs/verifier/reward.txt
fi
exit 0