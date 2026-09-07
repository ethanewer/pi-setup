#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/packages.json ]; then
  if python3 - <<'PYEOF'
import json
recs = []
cur = {}
with open('/app/debian-sources.list') as f:
    for line in f:
        line = line.rstrip('\n')
        if not line.strip():
            if cur:
                recs.append(cur)
                cur = {}
            continue
        k, _, v = line.partition(':')
        cur[k.strip()] = v.strip()
    if cur:
        recs.append(cur)
recs.sort(key=lambda r: (int(r['Priority']), r['Name']))
expected = [{"name": r['Name'], "version": r['Version']} for r in recs]
got = json.load(open('/app/packages.json'))
assert got == expected, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt