#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/person.bin ]; then
  if python3 - <<'PYEOF'
import sys
sys.path.insert(0, '/app')
import person_pb2
p = person_pb2.Person()
p.ParseFromString(open('/app/person.bin','rb').read())
assert p.name == 'Grace Hopper', p.name
assert p.id == 7, p.id
assert p.email == 'grace@example.org', p.email
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt