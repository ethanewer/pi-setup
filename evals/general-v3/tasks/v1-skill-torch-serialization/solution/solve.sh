#!/bin/bash
set -euo pipefail

cat > /app/probe.py <<'PY'
import json
import torch

def load_state(path):
    try:
        return torch.load(path, map_location="cpu", weights_only=True)
    except TypeError:
        return torch.load(path, map_location="cpu")

d = load_state("/app/model.pt")
num_keys = len(d)
w_shape = list(d["w"].shape)
b_dtype = str(d["b"].dtype)
mean_w = round(float(d["w"].float().mean().item()), 3)

out = {
    "num_keys": num_keys,
    "w_shape": w_shape,
    "b_dtype": b_dtype,
    "mean_w": mean_w,
}
with open("/app/result.json", "w") as f:
    json.dump(out, f)
print(json.dumps(out))
PY

python3 /app/probe.py