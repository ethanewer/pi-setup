#!/bin/bash
# ashen-lattice verifier entrypoint: delegates to /tests/verify.py and always
# writes REWARD (0/1) to /logs/verifier/reward.txt.
set -uo pipefail
mkdir -p /logs/verifier
if python3 /tests/verify.py 2> /tmp/verify.err; then
  echo "1" > /logs/verifier/reward.txt
else
  echo "0" > /logs/verifier/reward.txt
  cat /tmp/verify.err >&2
fi
exit 0
