#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/result.json ]; then
  if python3 - <<'PY'
import json
import torch
import torch.distributed as dist

dist.init_process_group(backend='gloo',
                        init_method='tcp://127.0.0.1:29700',
                        rank=0, world_size=1)
try:
    vals = [float(t) for t in open('/app/values.txt').read().split()]
    t = torch.tensor(vals, dtype=torch.float64)
    dist.all_reduce(t, op=dist.ReduceOp.SUM)
    exp = round(float(t.sum().item()), 4)
    got = json.load(open('/app/result.json'))['total_sum']
    if abs(got - exp) > 0.0001:
        raise SystemExit((got, exp))
    print("PASS"); raise SystemExit(0)
finally:
    dist.destroy_process_group()
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt