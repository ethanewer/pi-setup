#!/bin/bash
# Oracle for cistern-cairn: apply the res.clearCookie fix, then prove it by
# running the repro probe and the upstream regression test (copied into the
# tree so that its require('../') resolves to the repaired express).
set -e

node /solution/fix_response.js /app/src/lib/response.js

echo "== probe output after the fix =="
node /app/probe.js

echo "== upstream regression test =="
GOLDEN_TMP=/app/src/.oracle-golden
mkdir -p "$GOLDEN_TMP"
cp /opt/golden/res.clearCookie.js "$GOLDEN_TMP/"
cd /app/src
NODE_PATH=/app/src/node_modules ./node_modules/.bin/mocha --require test/support/env "$GOLDEN_TMP/res.clearCookie.js"
rm -rf "$GOLDEN_TMP"
