#!/bin/sh
set +e
mkdir -p /logs/verifier
python -m py_compile /app/httpx/_models.py >/logs/verifier/diagnostics.log 2>&1
compile_rc=$?
if [ "$compile_rc" -ne 0 ]; then
    printf '0' > /logs/verifier/reward.txt
    exit 0
fi
python /tests/hidden/verify.py >>/logs/verifier/diagnostics.log 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    printf '1' > /logs/verifier/reward.txt
else
    printf '0' > /logs/verifier/reward.txt
fi
exit 0
