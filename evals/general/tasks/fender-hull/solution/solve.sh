#!/bin/bash
# Oracle for fender-hull: applies the minimal upstream-equivalent fix to the
# DOMPurify checkout at /app/src, writes the reproduction deliverable, and
# rebuilds the cjs distributable from the repaired source. The verifier then
# runs the full acceptance flow (repro against pre-fix and repaired trees,
# the project's own suite with the golden regression tests, hidden cases).
set -e

# Deliverable 1: the reproduction script.
cp /solution/repro.js /app/repro.js

# Deliverable 2: fix the source (clobber-immune document-owner read).
python3 /solution/fix_dompurify.py /app/src/src/purify.ts

echo "== regenerating dist from the repaired source =="
cd /app/src && npm run build --no-progress

echo "== smoke: reproduction must pass against the repaired build =="
node /app/repro.js