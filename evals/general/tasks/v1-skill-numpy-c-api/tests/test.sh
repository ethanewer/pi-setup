#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json, sys
sys.path.insert(0, '/app/src')
import numpy as np
import sqmod
x = np.array([1, 2, 3, 4, 5, 6, 7, 8], dtype=np.int64)
y = np.asarray(sqmod.squares(x), dtype=np.int64)
expected = {'in': x.tolist(), 'out': y.tolist()}
got = json.load(open('/app/result.json'))
assert got == expected, (got, expected)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt