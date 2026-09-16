#!/bin/sh
set +e
mkdir -p /logs/verifier
PYTHONPATH=/app/jinja/src pytest -q /app/tests/test.py /app/tests/hidden > /dev/null 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    printf '1' > /logs/verifier/reward.txt
else
    printf '0' > /logs/verifier/reward.txt
fi
exit 0
