#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/model_out.json ]; then
  if python3 - <<'EOF'
import json
with open('/app/model.json') as f: m = json.load(f)
with open('/app/data.json') as f: d = json.load(f)
with open('/app/model_out.json') as f: out = json.load(f)

x = d["x"]; y = d["y"]
w, b = m["w"], m["b"]
lr = 0.1
N = len(x)
errors = [w*xi + b - yi for xi, yi in zip(x, y)]
grad_w = (2.0/N)*sum(e*xi for e, xi in zip(errors, x))
grad_b = (2.0/N)*sum(errors)
w_new = w - lr*grad_w
b_new = b - lr*grad_b

if abs(out["w"] - round(w_new, 3)) >= 1e-6:
    raise SystemExit((out, w_new))
if abs(out["b"] - round(b_new, 3)) >= 1e-6:
    raise SystemExit((out, b_new))
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt