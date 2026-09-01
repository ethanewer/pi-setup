#!/bin/bash
# Oracle solution for item-020-main: write and run the KL solver.
set -euo pipefail

cat > /app/solve.py <<'PYEOF'
#!/usr/bin/env python3
"""Solve item-020: forward/reverse KL in D=400 with leaky-smoothed p/q."""
import json
import numpy as np

d = json.load(open("/app/input.json"))
counts = np.array(d["counts"], dtype=np.float64)
target_q = np.array(d["target_q"], dtype=np.float64)
D = int(d["D"])
eps = 1e-9

p = (counts + eps) / (counts.sum() + D * eps)
q = (target_q + eps) / (target_q.sum() + D * eps)

logp = np.log(p)
logq = np.log(q)

forward_kl = float(np.sum(p * (logp - logq)))
reverse_kl = float(np.sum(q * (logq - logp)))

res = {
    "p_sum": float(np.sum(p)),
    "q_sum": float(np.sum(q)),
    "forward_kl": forward_kl,
    "reverse_kl": reverse_kl,
}
with open("/app/result.json", "w") as f:
    json.dump(res, f)
with open("/app/result.txt", "w") as f:
    f.write("forward_kl=%.9f\nreverse_kl=%.9f\n" % (forward_kl, reverse_kl))
print("done", forward_kl, reverse_kl)
PYEOF

python3 /app/solve.py
echo "solution wrote /app/result.json"