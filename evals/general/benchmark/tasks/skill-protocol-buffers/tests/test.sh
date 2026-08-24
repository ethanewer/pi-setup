#!/bin/bash
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