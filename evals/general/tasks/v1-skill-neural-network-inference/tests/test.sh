#!/bin/bash

# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/class.txt ]; then
  if python3 - <<'EOF'
import numpy as np

x = np.load('/app/data/x.npy')
d = np.load('/app/data/net.npz')
hidden = np.tanh(x @ d['W1'] + d['b1'])
logits = hidden @ d['W2'] + d['b2']
expected = int(np.argmax(logits, axis=1)[0])

with open('/app/class.txt') as f:
    got = int(f.read().strip())
assert got in (0, 1, 2)
assert got == expected, (got, expected)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt