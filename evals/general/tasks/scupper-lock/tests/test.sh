#!/bin/bash
# Verifier for scupper-lock (executes-deliverable).
#
# Executes /app/DataTable.tsx through the staged hidden fixtures under jsdom
# with @testing-library/react, strict type-checks two hidden consumer files
# against the exported prop types, and checks that /app/DataTable.md documents
# the full public API. Writes reward (0/1) to /logs/verifier/reward.txt.
#
# Guarantee a reward on every exit path: if a helper raises before the reward
# write, the EXIT trap supplies 0.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

reward=0

if [ ! -f /app/DataTable.tsx ]; then
  echo "missing deliverable /app/DataTable.tsx" >&2
else
  if [ ! -f /app/DataTable.md ]; then
    echo "missing deliverable /app/DataTable.md" >&2
  else
    cd /app || { echo "cannot enter /app" >&2; }
    if node /tests/verify.mjs; then
      reward=1
    fi
  fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0