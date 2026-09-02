#!/usr/bin/env bash
# Verifier for umber-engine. Compiles the Rust deliverable, then runs the python
# verifier which executes every deliverable on visible + hidden inputs and
# writes reward.txt.
set -u
mkdir -p /logs/verifier
reward=0
cd /app

# Compile the Rust deliverable from source (fails -> reward 0 on a pristine image).
if rustc -O /app/seq.rs -o /app/seq_rs 2>/tmp/rs_compile.err; then
  if python3 /tests/verify.py; then
    reward=1
  fi
fi

echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0