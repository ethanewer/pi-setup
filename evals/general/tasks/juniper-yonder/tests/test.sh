#!/bin/bash
# Verifier for juniper-yonder (executes-deliverable). Runs /app/attack.py on
# the shipped workspace and on every hidden scenario, checking the recovered
# keys, per-line plaintexts, name normalization, base64-filename decoding, and
# full crypto-CLI coverage over each source tree.  Writes reward to
# /logs/verifier/reward.txt (1 all pass, 0 otherwise).
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier
python3 /tests/check.py > /tmp/verify_out.log 2>&1
cat /tmp/verify_out.log
exit 0
