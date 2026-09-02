#!/bin/bash
# Verifier for marble-shard: byte-checks the visible deliverable, EXECUTES the
# deliverable program (/app/recover.py) against the live appliance and against
# hidden appliance states (several spawned keepers holding decoy deleted
# shards), and checks the negative-query exit contract. Writes REWARD (0/1)
# to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

if python3 /tests/verify.py; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
