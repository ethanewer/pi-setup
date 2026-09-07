#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/product.json ]; then
  if python3 - <<'PYEOF'
import json
import numpy as np

A = np.array([[1, 2], [3, 4]])
B = np.array([[5, 6], [7, 8]])
expected = np.asarray(A @ B, dtype=int).tolist()

with open('/app/product.json') as f:
    data = json.load(f)
got = data['C']
if got != expected:
    raise SystemExit((got, expected))
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt