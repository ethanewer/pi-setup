#!/bin/sh
set +e
mkdir -p /logs/verifier
python /app/tests/hidden/verify.py >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    printf '1' > /logs/verifier/reward.txt
else
    printf '0' > /logs/verifier/reward.txt
fi
exit 0
