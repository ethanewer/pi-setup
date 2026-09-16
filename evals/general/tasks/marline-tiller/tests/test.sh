#!/bin/bash
# marline-tiller verifier entrypoint.
#
# Runs the local verification harness, which
#   1. runs `npm run build` in /app and asserts the packaging contract
#      (ESM artifact dist/marline-lib.mjs plus per-module .d.ts files),
#   2. imports the BUILT library into a jsdom process and renders every
#      component under @testing-library/react against the visible and the
#      hidden prop fixtures, asserting DOM output, event behaviour and
#      callback payloads (controlled/uncontrolled semantics).
# All green -> reward 1, any failure -> reward 0.
#
# Guarantee a reward on every exit path. Without this a verifier that raises
# while inspecting the agent's deliverable writes nothing at all, which yields
# a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier /tmp/mt-harness

# The harness is CJS and depends on the repository's baked node_modules; give
# module resolution a local hook so it finds them (no network at trial time).
ln -sfn /app/node_modules /tmp/mt-harness/node_modules
cp /tests/verify.cjs /tmp/mt-harness/verify.cjs

cases=""
for f in /tests/visible-case.json /tests/hidden/*/case.json; do
  [ -f "$f" ] && cases="$cases $f"
done

if timeout 540 node /tmp/mt-harness/verify.cjs $cases > /tmp/mt-verify.log 2>&1; then
  echo "1" > /logs/verifier/reward.txt
  echo "marline-tiller: ALL CHECKS PASSED"
else
  echo "0" > /logs/verifier/reward.txt
  echo "marline-tiller: VERIFIER FAILURES:" >&2
  cat /tmp/mt-verify.log >&2
fi
exit 0
