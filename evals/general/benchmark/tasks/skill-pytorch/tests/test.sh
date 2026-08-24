#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/sum.txt ]; then
  if python3 - <<'PY'
import torch
t=torch.load('/app/values.pt')
expected=str(int(t.sum().item()))
got=open('/app/sum.txt').read().strip()
if got != expected:
    raise SystemExit((got, expected))
print("PASS"); raise SystemExit(0)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt