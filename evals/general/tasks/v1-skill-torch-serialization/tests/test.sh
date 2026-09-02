#!/bin/bash
# Verifier for skill-torch-serialization: recompute the four facts by loading
# the same serialized state dict and compare with /app/result.json.
mkdir -p /logs/verifier
reward=0

if [ -f /app/model.pt ] && [ -f /app/result.json ]; then
  if python3 - <<'PY'
import json, sys
import torch

def load_state(path):
    try:
        return torch.load(path, map_location="cpu", weights_only=True)
    except TypeError:
        return torch.load(path, map_location="cpu")

d = load_state("/app/model.pt")
expected = {
    "num_keys": len(d),
    "w_shape": list(d["w"].shape),
    "b_dtype": str(d["b"].dtype),
    "mean_w": round(float(d["w"].float().mean().item()), 3),
}

try:
    got = json.load(open("/app/result.json"))
except Exception:
    sys.exit(1)

assert isinstance(got, dict), got
assert got.get("num_keys") == expected["num_keys"], (got, expected)
assert list(got.get("w_shape", [])) == expected["w_shape"], (got, expected)
assert got.get("b_dtype") == expected["b_dtype"], (got, expected)
assert abs(float(got.get("mean_w")) - expected["mean_w"]) <= 1e-3, (got, expected)
print("PASS")
sys.exit(0)
PY
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt