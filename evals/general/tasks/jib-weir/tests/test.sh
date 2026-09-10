#!/bin/bash
# jib-weir verifier: executes /app/start.sh (the deliverable) on the visible
# and three hidden datasets, asserts the HTTP contract, validates the emitted
# OpenAPI document (/app/openapi.json) and checks it against the live routes.
# Writes a strictly binary reward to /logs/verifier/reward.txt.
#
# Guarantee a reward on every exit path. A verifier that raises before
# reaching its write produces a record that cannot be scored at all, and the
# scalar-valued failure paths below must never be followed by another write.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier

if timeout 480 python3 /tests/verify.py > /tmp/jibw-verify.log 2>&1; then
  echo "1" > /logs/verifier/reward.txt
  echo "jib-weir: ALL CHECKS PASSED"
else
  echo "0" > /logs/verifier/reward.txt
  echo "jib-weir: VERIFIER FAILURES (see /tmp/jibw-verify.log):" >&2
  cat /tmp/jibw-verify.log >&2
fi
exit 0