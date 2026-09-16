#!/bin/bash
# Oracle for cistern-bridge: repairs DOMPurify's case-preserving attribute
# removal in the /app/src checkout, rebuilds the committed dist artifact with
# the project's own build so the fix is actually exercised, then runs the
# reproduction to prove the user-visible symptom is gone.
set -e

python3 /solution/fix_purify.py /app/src/src/purify.ts

echo "== rebuilding committed dist artifact with the project's own build =="
(cd /app/src && npm run build > /tmp/build.log 2>&1)
tail -3 /tmp/build.log

echo "== reproduction after the fix =="
node /app/repro.js

echo "== working tree surface (expect src plus dist artifacts only) =="
git -C /app/src status --porcelain