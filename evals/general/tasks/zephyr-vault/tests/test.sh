#!/usr/bin/env bash
# Verifier for zephyr-vault (executes-deliverable). Delegates scenario checking
# (including the hidden cases under /tests/hidden) to /tests/check.py, which
# executes each /app deliverable with literal paths, throws the payload
# batteries at the running server, drives the spreadsheet REST mock, and
# validates the audit memo. Reward = 1 iff check.py exits 0.
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

test -f /app/app.py           || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/server_check.py  || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/sheets_client.py || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/audit_report.md  || { echo "0" > /logs/verifier/reward.txt; exit 0; }

python3 /tests/check.py
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0