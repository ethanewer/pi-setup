#!/bin/bash

mkdir -p /logs/verifier

reward=0

if [ -f /app/out/batches.json ]; then
python3 - <<'PY'
import json, sys

items = json.load(open('/app/items.json'))
CAP = 32
names = [it['name'] for it in items]
sizes = [it['size'] for it in items]
name2i = {n: i for i, n in enumerate(names)}

try:
    batches = json.load(open('/app/out/batches.json'))
except Exception:
    sys.exit(1)

if not isinstance(batches, list) or not batches:
    sys.exit(1)

seen = set()
for b in batches:
    if not isinstance(b, list):
        sys.exit(1)
    s = 0
    for nm in b:
        if nm not in name2i or nm in seen:
            sys.exit(1)
        seen.add(nm)
        s += sizes[name2i[nm]]
    if s > CAP:
        sys.exit(1)
if seen != set(names):
    sys.exit(1)

# exact minimum batch count via subset DP
n = len(items)
subsum = [0] * (1 << n)
for mask in range(1, 1 << n):
    lb = mask & -mask
    i = lb.bit_length() - 1
    subsum[mask] = subsum[mask ^ lb] + sizes[i]
INF = n + 1
dp = [INF] * (1 << n)
dp[0] = 0
for mask in range(1, 1 << n):
    sub = mask
    while sub:
        if subsum[sub] <= CAP:
            dp[mask] = min(dp[mask], dp[mask ^ sub] + 1)
        sub = (sub - 1) & mask
minb = dp[(1 << n) - 1]
if len(batches) != minb:
    sys.exit(1)

sys.exit(0)
PY
  if [ $? -eq 0 ]; then reward=1; else reward=0; fi
fi

echo "$reward" > /logs/verifier/reward.txt