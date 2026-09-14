#!/bin/bash
# lighter-gate oracle: writes the reproduction deliverable and applies the
# fix to the /app/src checkout, then proves the repro passes against the
# repaired tree.
set -euo pipefail

mkdir -p /app/repro
cp /solution/repro_deliverable.py /app/repro/test_no_args_is_help.py

cd /app/src
if git apply --check /solution/fix.patch; then
  git apply /solution/fix.patch
elif git apply --reverse --check /solution/fix.patch; then
  echo "oracle: fix already applied"
else
  echo "oracle: patch state unclear (neither clean apply nor already applied)" >&2
  exit 1
fi

# Self-check: the reproduction must now pass against the repaired tree.
cd /
env -u PYTHONPATH python3 -m pytest -q -p no:cacheprovider /app/repro/test_no_args_is_help.py \
  >/tmp/oracle-repro.log 2>&1 || { cat /tmp/oracle-repro.log >&2; exit 1; }

[ -f /app/repro/test_no_args_is_help.py ]
echo "oracle ok: reproduction written and passing, fix applied to /app/src"