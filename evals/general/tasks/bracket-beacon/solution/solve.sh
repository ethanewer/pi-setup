#!/usr/bin/env bash
# Oracle for bracket-beacon: repair the DOMPurify URI-validation bypass in the
# real checkout at /app/src.
#
# The reference solution works exactly like the agent is expected to:
#   1. demonstrate the bug on the unmodified checkout (the reproduction exits 1),
#   2. fix the root cause in the project source (src/purify.ts),
#   3. rebuild dist/ from the fixed source with the project's own build,
#   4. prove the reproduction now passes,
#   5. prove the project's own jsdom suite is still green.
# It never reads /tests.
set -euo pipefail

SRC=/app/src
cd "$SRC"

echo "== before: bug must reproduce on the unmodified checkout =="
if NODE_PATH=/app/src/node_modules node /solution/repro.js; then
  echo "FAIL: the dangerous URI did not survive; nothing to fix" >&2
  exit 1
fi
echo "ok: javascript: survived (bug present)"

echo "== fixing the root cause in the project source =="
python3 /solution/fix_uri_validation.py "$SRC"
echo "ok: source patched"

echo "== rebuilding dist/ from the fixed source =="
npm run build
test -f dist/purify.cjs.js

echo "== after: reproduction must pass =="
NODE_PATH=/app/src/node_modules node /solution/repro.js
 echo "ok: dangerous URI stripped; reproduction exits 0"

echo "== project's own jsdom suite must stay green =="
node test/jsdom-node-runner > /tmp/oracle-suite.tap
if grep -qE '^ ?not ok' /tmp/oracle-suite.tap; then
  echo "FAIL: project suite has failing cases" >&2
  grep -E '^ ?not ok' /tmp/oracle-suite.tap | head -10 >&2
  exit 1
fi
echo "oracle: jsdom suite green ($(grep -c '^ok ' /tmp/oracle-suite.tap) ok)"
echo "ORACLE DONE"