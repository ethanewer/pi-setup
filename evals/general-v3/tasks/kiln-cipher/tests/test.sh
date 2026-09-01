#!/usr/bin/env bash
# Verifier for kiln-cipher (executes-deliverable).
# Delegates all scenario checking (including the hidden identity cases under
# /tests/hidden) to /tests/check.py, which EXECUTES the deliverable
# /app/mkcert.py on hidden (cn, bits) cases and validates every staged bundle
# (visible /app/identity/* and hidden outputs) with openssl.
# Reward = 1 iff all pass.
set -u
mkdir -p /logs/verifier

test -f /app/mkcert.py                  || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/identity/key.pem           || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/identity/cert.pem          || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/identity/bundle.pem        || { echo "0" > /logs/verifier/reward.txt; exit 0; }
test -f /app/identity/fingerprint.txt   || { echo "0" > /logs/verifier/reward.txt; exit 0; }

python3 /tests/check.py
rc=$?

if [ "$rc" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
