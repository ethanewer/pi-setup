#!/bin/bash
# Verifier for cistern-berth (upstream-clone bug-fix task).
#
# All the logic lives in /tests/verify.py; this script only maps its exit
# code onto the binary reward. The EXIT trap guarantees a reward file exists
# on every path, including crashes and introspections gone wrong.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

python3 /tests/verify.py
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "REWARD 1: golden + upstream forwarded suite + hidden cases green; tree provenance intact"
    echo 1 > /logs/verifier/reward.txt
else
    echo "REWARD 0: verifier failed (see failures printed above)"
    echo 0 > /logs/verifier/reward.txt
fi
exit 0