#!/bin/bash
set -euo pipefail

cat > /app/distributed.py <<'PY'
import json
import torch
import torch.distributed as dist

dist.init_process_group(backend='gloo',
                        init_method='tcp://127.0.0.1:29500',
                        rank=0, world_size=1)
try:
    vals = [float(t) for t in open('/app/values.txt').read().split()]
    t = torch.tensor(vals, dtype=torch.float64)
    dist.all_reduce(t, op=dist.ReduceOp.SUM)
    total = float(t.sum().item())
    out = {"total_sum": round(total, 4)}
    open('/app/result.json', 'w').write(json.dumps(out))
    print(json.dumps(out))
finally:
    dist.destroy_process_group()
PY

python3 /app/distributed.py