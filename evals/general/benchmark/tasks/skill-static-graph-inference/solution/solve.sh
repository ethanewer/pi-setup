#!/bin/bash
set -euo pipefail

cat > /app/trace_and_run.py <<'PY'
import torch
import importlib.util

spec = importlib.util.spec_from_file_location('m', '/app/model.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

model = m.Net()
model.load_state_dict(torch.load('/app/policy.pt', weights_only=False))
model.eval()

x = torch.tensor([1.5, -2.0])
traced = torch.jit.trace(model, x)
torch.jit.save(traced, '/app/traced.pt')

y = traced(x)
with open('/app/out.txt', 'w') as f:
    f.write(f"{float(y[0])}\n")
    f.write(f"{float(y[1])}\n")
PY

python3 /app/trace_and_run.py