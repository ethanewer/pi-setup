#!/bin/bash
set -euo pipefail

cat > /app/infer.py <<'PY'
import torch

sd = torch.load('/app/policy.pt', weights_only=False)

# Order layers deterministically by subscript, then by 'weight' vs 'bias'.
W = {k: v for k, v in sd.items() if k.endswith('.weight') and v.ndim == 2}
out = {}
for layer_name in ['fc1', 'fc2']:
    w = W[layer_name + '.weight']
    out[layer_name] = (int(w.shape[1]), int(w.shape[0]))

with open('/app/shapes.txt', 'w') as f:
    for name in ['fc1', 'fc2']:
        in_, out_ = out[name]
        f.write(f"{name}: in={in_} out={out_}\n")
PY

python3 /app/infer.py