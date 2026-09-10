#!/bin/bash
# Oracle for plinth-wicket: ship the hardened sanitizer and its bypass test,
# then run the bypass test to prove the fix works. Never reads /tests.
set -euo pipefail

cp /solution/sanitize.js /app/sanitize.js
cp /solution/bypass-test.js /app/bypass-test.js
chmod +x /app/bypass-test.js

# Prove the oracle's own hardening passes before reporting success.
node /app/bypass-test.js
echo "oracle: bypass-test passed; deliverables written to /app"
