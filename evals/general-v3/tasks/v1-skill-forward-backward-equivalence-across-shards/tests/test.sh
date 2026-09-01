#!/bin/bash
mkdir -p /logs/verifier
reward=0
if python3 - <<'PYEOF'
import json
import numpy as np
x = np.array(json.load(open('/app/input.json'))['x'])
sa = json.load(open('/app/shard_a.json'))
sb = json.load(open('/app/shard_b.json'))
W1 = np.array(sa['W1']); b1 = np.array(sa['b1'])
W2 = np.array(sb['W2']); b2 = np.array(sb['b2'])
h = W1 @ x + b1
y_layer = W2 @ h + b2
Wc = W2 @ W1
bc = b2 + W2 @ b1
y_comp = Wc @ x + bc
max_diff = float(np.max(np.abs(y_layer - y_comp)))
got = json.load(open('/app/forward_check.json'))
assert hasattr(got, 'get') and 'max_diff' in got
assert abs(float(got['max_diff']) - max_diff) <= 1e-6, (got['max_diff'], max_diff)
assert got['max_diff'] <= 1e-4
# outputs must match independent layer computation
gl = [float(v) for v in got['y_layer']]
assert all(abs(a - b) <= 1e-4 for a, b in zip(gl, [float(v) for v in y_layer])), (gl, y_layer)
PYEOF
then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt