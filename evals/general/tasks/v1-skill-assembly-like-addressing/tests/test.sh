#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json, re
expected = {}
with open('/app/ea.txt') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        m = re.match(r'^[Ee][Aa](\d+)\s+base=(-?\d+)\s+index=(-?\d+)\s+scale=(-?\d+)\s+disp=(-?\d+)$', line)
        assert m, line
        n, base, idx, scale, disp = (int(m.group(i)) for i in range(1, 6))
        expected['ea%d' % n] = base + idx * scale + disp
got = json.load(open('/app/answer.json'))
assert got == expected, (got, expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt