#!/bin/bash
# Verifier for item-072-hard. Always writes a numeric reward.
set +e
mkdir -p /logs/verifier
HERE="$(cd "$(dirname "$0")" && pwd)"

reward=0
if python3 "$HERE/verify.py" "$HERE/test.parquet" > /tmp/verify_out.txt 2>&1; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt
cp /tmp/verify_out.txt /logs/verifier/verify_out.txt 2>/dev/null
exit 0