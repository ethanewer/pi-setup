#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.txt ]; then
  if python3 - <<'PYEOF'
import numpy as np

A = np.loadtxt('/app/A.txt', dtype=int)
B = np.loadtxt('/app/B.txt', dtype=int)
expC = np.rint(A @ B).astype(int)
expD = (A + B).astype(int)

lines = open('/app/result.txt').read().splitlines()
if len(lines) < 8:
    raise SystemExit('result.txt too short')
if lines[0].strip() != 'C:' or lines[4].strip() != 'D:':
    raise SystemExit('missing section markers')
gotC = np.array([[int(x) for x in lines[i].split()] for i in range(1, 4)])
gotD = np.array([[int(x) for x in lines[i].split()] for i in range(5, 8)])
if gotC.shape != expC.shape or gotD.shape != expD.shape:
    raise SystemExit('wrong shape')
if (gotC != expC).any() or (gotD != expD).any():
    raise SystemExit('value mismatch')
print("PASS"); raise SystemExit(0)
PYEOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt