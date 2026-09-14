#!/bin/bash
# Hidden case: sound negative narrowing on a tuple of a literal singleton
# (`x not in (None,)`) must be PRESERVED by the fix.
set -u
MAIN="$(cd "$(dirname "$0")" && pwd)/main.py"
cd /app/src || exit 1
OUT=$(mktemp /tmp/hc-tuple-soundness.XXXXXX)
python3 -m mypy --no-incremental --warn-unreachable --cache-dir=/tmp/hc-cache "$MAIN" > "$OUT" 2>&1
rc=$?
if grep -q "Success: no issues found" "$OUT"; then exit 0; fi
cat "$OUT"
exit 1