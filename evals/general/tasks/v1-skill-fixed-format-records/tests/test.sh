#!/bin/bash
mkdir -p /logs/verifier
APP="${TASK_APP:-/app}"
reward=0
if [ -f "$APP/people.dat" ] && [ -f "$APP/records.json" ]; then
  if python3 - "$APP" <<'PY'
import json, sys
base = sys.argv[1]
exp = []
for line in open(base + '/people.dat'):
    line = line.rstrip('\n')
    if not line:
        continue
    exp.append({
        "id": int(line[0:4]),
        "name": line[4:16].strip(),
        "age": int(line[16:19].strip()),
        "city": line[19:29].strip(),
    })
got = json.load(open(base + '/records.json'))
sys.exit(0 if got == exp else 1)
PY
  then reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt