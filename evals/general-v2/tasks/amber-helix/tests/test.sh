#!/bin/bash
# Verifier for tasks/amber-helix (executes-deliverable).
#
# Drives the independent checks in verify_helper.py, which re-execute every
# deliverable — /app/load_catalog.py, /app/design_primers.py,
# /app/train_affinity.py — over the mounted hidden cases in /tests/hidden
# (fresh catalog + name lists with whitespace/edge meshes, fresh mutagenesis
# loci incl. insufficient-flank and non-standard-bases templates, and a fresh
# descriptor/measurement pair plus malformed inputs) and independently re-derive
# the documented contract for each: case-insensitive catalog matches, primer
# annealing loci/orientation/Tm bounds, and held-out Spearman >= 0.9 across 8
# seeds.  Writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

if [ ! -f /app/load_catalog.py ] || [ ! -f /app/design_primers.py ] || \
   [ ! -f /app/train_affinity.py ]; then
  echo "missing one or more deliverable programs" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

PASS=0
FAIL=0
run() {
  local name="$1"
  if python3 /tests/verify_helper.py "$name" >/tmp/vout.log 2>&1; then
    PASS=$((PASS+1))
    echo "PASS  $name"
  else
    FAIL=$((FAIL+1))
    echo "FAIL  $name"
    sed 's/^/      | /' /tmp/vout.log >&2
  fi
}

run catalog-visible
run catalog-hidden
run catalog-edge
run primers-visible
run primers-hidden
run primers-edge
run affinity-visible
run affinity-hidden
run affinity-edge

reward=0
if [ "$FAIL" -eq 0 ] && [ "$PASS" -ge 9 ]; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward (pass=$PASS fail=$FAIL)"
exit 0