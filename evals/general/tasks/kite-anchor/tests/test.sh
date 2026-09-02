#!/usr/bin/env bash
# kite-anchor verifier: runs every deliverable and writes the numeric reward.
set -uo pipefail

python3 /tests/check.py
# check.py writes /logs/verifier/reward.txt
exit 0