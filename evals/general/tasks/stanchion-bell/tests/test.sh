#!/bin/bash
# Verifier for stanchion-bell (executes-deliverable).
#
# Renders pages from /app/src under jsdom with React, runs axe-core
# (color-contrast and target-size excluded as unmeasurable under jsdom) and
# enforces the targeted focus-order / ARIA / label / colour-state contract on
# the four visible pages plus three hidden pages staged under
# /tests/hidden. The heavy lifting lives in /tests/verify.mjs; this wrapper
# only checks the deliverable exists, runs it and writes the binary reward.
#
# A reward is guaranteed on every exit path: if anything raises before the
# write, the EXIT trap supplies 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

reward=0

if [ ! -d /app/src ]; then
  echo "missing deliverable /app/src/" >&2
else
  if [ ! -f /app/package.json ]; then
    echo "missing /app/package.json" >&2
  elif [ ! -f /app/vitest.config.mjs ]; then
    echo "missing /app/vitest.config.mjs" >&2
  else
    if node /tests/verify.mjs; then
      reward=1
    fi
  fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0