#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/dates.json ]; then
  if python3 - <<'EOF'
import json, sys
from datetime import date, datetime, timedelta
data = json.load(open('/app/climate.json'))
got = json.load(open('/app/dates.json'))
if len(got) != len(data['variables']):
    sys.exit("num variables")
for v, entry in zip(data['variables'], got):
    if entry.get('name') != v['name']:
        sys.exit("name order")
    unit, _, ref = v['units'].partition('since')
    y, m, d = (int(x) for x in ref.strip().split()[0].split('-'))
    exp = []
    if unit.strip().startswith('day'):
        base = date(y, m, d)
        for off in v['offsets']:
            exp.append((base + timedelta(days=off)).isoformat())
    else:
        base = datetime(y, m, d)
        for off in v['offsets']:
            exp.append((base + timedelta(hours=off)).date().isoformat())
    if entry.get('dates') != exp:
        sys.exit("dates mismatch for %s" % v['name'])
sys.exit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt