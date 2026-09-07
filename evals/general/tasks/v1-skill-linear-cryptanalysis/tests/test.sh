#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ]; then
  if python3 - <<'PYEOF'
import json
sbox = [6, 2, 5, 0, 3, 1, 7, 4]
a, b = 5, 7
exp = sum(1 for i in range(8) if (bin(i & a).count('1') % 2) == (bin(sbox[i] & b).count('1') % 2))
got = json.load(open('/app/answer.json'))
assert int(got.get("count", -1)) == exp, (got, exp)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt