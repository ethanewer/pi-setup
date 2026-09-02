#!/bin/bash
# Verifier for juniper-yonder (executes-deliverable). Runs /app/attack.py on
# the shipped workspace and on every hidden scenario, checking the recovered
# keys, per-line plaintexts, name normalization, base64-filename decoding, and
# full crypto-CLI coverage over each source tree.  Writes reward to
# /logs/verifier/reward.txt (1 all pass, 0 otherwise).
set -u
mkdir -p /logs/verifier
python3 /tests/check.py > /tmp/verify_out.log 2>&1
cat /tmp/verify_out.log
exit 0
