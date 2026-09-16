#!/bin/sh
set -eu
mkdir -p /logs/verifier
result=0
MANIFEST_AUDIT_APP="${MANIFEST_AUDIT_APP:-/app/manifest_audit.py}" \
  PYTHONDONTWRITEBYTECODE=1 python3 tests/hidden/cases.py >/dev/null 2>/dev/null || result=1
printf '%s\n' "$result" > /logs/verifier/reward.txt
exit 0
