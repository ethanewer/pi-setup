#!/bin/bash
# stanchion-compass verifier entrypoint.
#
# Rebuilds the app from /app (package.json -> dist), asserts the emitted
# chunk graph (initial byte budget, chunk count, per-view lazy chunks, vendor
# separation) and boots the built bundle under jsdom for the visible case and
# the hidden route cases, asserting each route's chunk is fetched and runs.
#
# Guarantee a reward on every exit path: without the trap, a verifier that
# raises while inspecting the deliverable writes nothing and the run cannot be
# scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

set -u
mkdir -p /logs/verifier /tmp/sc-harness

ln -sfn /app/node_modules /tmp/sc-harness/node_modules
cp /tests/verify.cjs /tmp/sc-harness/verify.cjs
cp /tests/boot.cjs /tmp/sc-harness/boot.cjs

cases=""
for f in /tests/visible-case.json /tests/hidden/*/case.json; do
  [ -f "$f" ] && cases="$cases $f"
done

cd /tmp/sc-harness
if timeout 540 node verify.cjs $cases > /tmp/sc-verify.log 2>&1; then
  echo "1" > /logs/verifier/reward.txt
  echo "stanchion-compass: ALL CHECKS PASSED"
else
  echo "0" > /logs/verifier/reward.txt
  echo "stanchion-compass: VERIFIER FAILURES:" >&2
  cat /tmp/sc-verify.log >&2
fi
exit 0