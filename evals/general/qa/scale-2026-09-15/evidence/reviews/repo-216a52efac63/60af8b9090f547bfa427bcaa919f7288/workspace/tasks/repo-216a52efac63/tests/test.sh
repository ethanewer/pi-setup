#!/bin/sh
set +e
mkdir -p /logs/verifier
compile_status=0
python3 -m py_compile /app/jinja/src/jinja2/filters.py >&2 || compile_status=$?
test_status=0
if [ "$compile_status" -eq 0 ]; then
    PYTHONPATH=/app/jinja/src python3 -m pytest -q /tests/test.py /tests/hidden >&2 || test_status=$?
else
    test_status=1
fi
if [ "$compile_status" -eq 0 ] && [ "$test_status" -eq 0 ]; then
    printf '1' > /logs/verifier/reward.txt
else
    printf '0' > /logs/verifier/reward.txt
fi
exit 0
