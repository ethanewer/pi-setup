#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ]; then
  if python3 - <<'PYEOF'
import json, math
import numpy as np
d = json.load(open('/app/input.json'))
counts = np.array(d['counts'], dtype=np.float64)
target_q = np.array(d['target_q'], dtype=np.float64)
D = int(d['D'])
eps = 1e-9
p = (counts + eps) / (counts.sum() + D * eps)
q = (target_q + eps) / (target_q.sum() + D * eps)
logp = np.log(p); logq = np.log(q)
forward_kl = float(np.sum(p * (logp - logq)))
reverse_kl = float(np.sum(q * (logq - logp)))
res = {
    'p_sum': float(np.sum(p)),
    'q_sum': float(np.sum(q)),
    'forward_kl': forward_kl,
    'reverse_kl': reverse_kl,
}
got = json.load(open('/app/result.json'))
for k in res:
    assert math.isclose(got[k], res[k], rel_tol=1e-6, abs_tol=1e-6), (k, got[k], res[k])
PYEOF
then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt