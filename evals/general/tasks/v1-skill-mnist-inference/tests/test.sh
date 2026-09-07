#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/prediction.txt ]; then
  if python3 - <<'PYEOF'
import numpy as np

x = np.load('/app/data/x.npy')
d = np.load('/app/data/model.npz')
W1, b1, W2, b2 = d['W1'], d['b1'], d['W2'], d['b2']

z1 = x @ W1 + b1
h = 1.0 / (1.0 + np.exp(-z1))
logits = h @ W2 + b2
expected = int(np.argmax(logits, axis=1)[0])

with open('/app/prediction.txt') as f:
    got = int(f.read().strip())

assert 0 <= got <= 9
assert got == expected, (got, expected)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt