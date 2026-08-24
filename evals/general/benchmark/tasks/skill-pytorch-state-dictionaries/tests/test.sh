#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/out.txt ]; then
  if python3 - <<'PY'
import torch
model=torch.nn.Linear(3,2)
model.load_state_dict(torch.load('/app/policy.pt'))
x=torch.tensor([1.0,2.0,3.0])
expected=''.join("%.1f\n"%round(v,1) for v in model(x).tolist())
lines=[l.strip() for l in open('/app/out.txt') if l.strip()]
got=''.join(l+'\n' for l in lines)
if got==expected:
    print("PASS"); raise SystemExit(0)
print("FAIL GOT=%r EXP=%r"%(got,expected)); raise SystemExit(1)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt