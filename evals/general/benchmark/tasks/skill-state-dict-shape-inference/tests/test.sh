#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/shapes.txt ]; then
  if python3 - <<'PY'
import torch

sd = torch.load('/app/policy.pt', weights_only=False)
expected = []
for name in ['fc1', 'fc2']:
    w = sd[f'{name}.weight']
    if w.ndim != 2:
        raise SystemExit(w.shape)
    in_, out_ = int(w.shape[1]), int(w.shape[0])
    expected.append(f"{name}: in={in_} out={out_}")

got = [ln.strip() for ln in open('/app/shapes.txt') if ln.strip()]
if got != expected:
    raise SystemExit((got, expected))
print("PASS"); raise SystemExit(0)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt