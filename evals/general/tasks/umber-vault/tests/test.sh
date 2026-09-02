#!/usr/bin/env bash
# Verifier for umber-vault (executes-deliverable). Delegates all checking to the
# helper /tests/check.py, which re-executes every deliverable on fresh and
# hidden inputs. Reward = 1 iff every check passes.
set -u
mkdir -p /logs/verifier

python3 /tests/check.py
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0