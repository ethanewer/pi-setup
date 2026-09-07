#!/usr/bin/env bash
# kite-anchor verifier: runs every deliverable and writes the numeric reward.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -uo pipefail

python3 /tests/check.py
# check.py writes /logs/verifier/reward.txt
exit 0