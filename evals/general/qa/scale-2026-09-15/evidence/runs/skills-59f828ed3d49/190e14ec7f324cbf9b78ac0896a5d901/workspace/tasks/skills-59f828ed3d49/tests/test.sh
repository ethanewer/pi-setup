#!/bin/sh
set -eu
mkdir -p /logs/verifier
result=0
MANIFEST_AUDIT_APP="${MANIFEST_AUDIT_APP:-/app/manifest_audit.py}" \
  PYTHONDONTWRITEBYTECODE=1 python3 /tests/hidden/cases.py \
  >/logs/verifier/cases.log 2>&1 || result=1
printf '%s\n' "$result" > /logs/verifier/reward.txt
exit 0
