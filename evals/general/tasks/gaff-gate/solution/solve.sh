#!/bin/bash
# gaff-gate oracle: demonstrates the defect on the pristine tree with the
# deliverable reproduction, applies an authored fix to /app/src, and proves
# the reproduction now passes. Creates /app/reproduce.js (a declared
# deliverable). Never reads /tests.
set -euo pipefail

cp /solution/reproduce.js /app/reproduce.js
chmod 644 /app/reproduce.js

echo "oracle: running the reproduction against the pristine (pre-fix) tree..."
if node /app/reproduce.js; then
  echo "oracle: FAIL — reproduction passed on a pristine tree; the defect is not present" >&2
  exit 1
fi
echo "oracle: reproduction failed as expected on the pristine tree (bug confirmed)"

echo "oracle: applying the authored fix to /app/src..."
cd /app/src
git apply --whitespace=nowarn /solution/fix.patch

echo "oracle: running the reproduction against the repaired tree..."
node /app/reproduce.js
echo "oracle: done — /app/reproduce.js in place and the repair verified"