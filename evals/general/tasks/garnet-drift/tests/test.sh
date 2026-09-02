#!/usr/bin/env bash
# Verifier for garnet-drift (executes-deliverable).
# Checks the visible deliverables, then delegates to /tests/check.py, which
# generates fresh hidden key/cert pairs (PKCS#8 RSA, EC, noisy input, and a
# mismatched pair), executes the deliverable /app/mkbundle.py on each, and
# validates the produced bundles (parse, block order, key/cert match, mode).
# Reward = 1 iff all checks pass.
set -u
mkdir -p /logs/verifier

test -f /app/mkbundle.py          || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/pki/bundle.pem       || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/pki/bundle.meta.json || { echo "0" > /logs/verifier/reward.txt; exit 0; }

python3 /tests/check.py
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
