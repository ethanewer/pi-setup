#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

reward=0
ok=1
[ ! -f /tmp/worker_ready ] && ok=0
[ ! -f /tmp/worker_result.txt ] && ok=0
[ ! -f /app/result.txt ] && ok=0
if [ "$ok" == "1" ]; then
  exp=$(cat /tmp/worker_result.txt 2>/dev/null)
  got=$(cat /app/result.txt 2>/dev/null)
  if [ "$exp" != "$got" ] || [ -z "$exp" ]; then ok=0; fi
fi
if [ "$ok" == "1" ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
