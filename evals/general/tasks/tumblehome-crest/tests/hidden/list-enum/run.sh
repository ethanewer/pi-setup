#!/bin/bash
# Hidden case: membership check on an ordinary (non-tuple) container holding a
# single-member enum must NOT trigger a spurious 'Statement is unreachable'.
set -u
MAIN="$(cd "$(dirname "$0")" && pwd)/main.py"
cd /app/src || exit 1
OUT=$(mktemp /tmp/hc-list-enum.XXXXXX)
python3 -m mypy --no-incremental --warn-unreachable --cache-dir=/tmp/hc-cache "$MAIN" > "$OUT" 2>&1
rc=$?
if grep -q "Success: no issues found" "$OUT"; then exit 0; fi
cat "$OUT"
exit 1