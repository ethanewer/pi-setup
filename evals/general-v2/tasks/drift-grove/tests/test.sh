#!/bin/bash
set -uo pipefail
mkdir -p /logs/verifier
trap '[ -f /logs/verifier/reward.txt ] || echo 0 > /logs/verifier/reward.txt' EXIT
python3 /tests/run_all.py 2>&1 | tee /tmp/vlog.txt || true
reward=$(grep -o 'REWARD=[01]' /tmp/vlog.txt | tail -1 | cut -d= -f2)
[ -z "${reward:-}" ] && reward=0
echo "$reward" > /logs/verifier/reward.txt
echo "final reward: $reward"