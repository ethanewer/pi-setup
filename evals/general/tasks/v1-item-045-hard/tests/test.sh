#!/bin/bash
mkdir -p /logs/verifier
reward=0

for f in /app/probe.py /app/inferred.json /app/models.md; do
  if [ ! -f "$f" ] || [ ! -s "$f" ]; then
    echo "$reward" > /logs/verifier/reward.txt
    exit 0
  fi
done

python3 - <<'PY'
import importlib.util, sys, json
import numpy as np
sys.path.insert(0, "/app")
spec = importlib.util.spec_from_file_location("probe", "/app/probe.py")
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
import model

lo, hi = -6.0, 6.0
seed = 991827
fresh = model.ReLUMLP(num_hidden=12, w1_scale=1.4, b_scale=2.0, w2_scale=1.0, seed=seed)

try:
    segs = probe.segment(fresh, lo, hi)
except Exception:
    open("/logs/verifier/reward.txt", "w").write("0.0")
    raise SystemExit(0)

if not (isinstance(segs, list) and segs):
    open("/logs/verifier/reward.txt", "w").write("0.0")
    raise SystemExit(0)

ok_tile = (abs(segs[0]["left"] - lo) < 1e-6
           and abs(segs[-1]["right"] - hi) < 1e-6
           and all(abs(segs[i]["right"] - segs[i+1]["left"]) < 1e-3
                   for i in range(len(segs)-1)))
bp = sorted(set(round(float(p), 9) for p in fresh.breakpoints()))
expected = len([p for p in bp if lo < p < hi]) + 1
ok_count = abs(expected - len(segs)) <= 1

# uniform fresh fit
xs = np.linspace(lo, hi, 8000)
ys = np.asarray(fresh.predict(xs), dtype=float)
try:
    rec = np.asarray(probe.evaluate(segs, xs), dtype=float)
    err_u = float(np.max(np.abs(ys - rec))) if rec.shape == ys.shape else 1e9
except Exception:
    err_u = 1e9

# adversarial near-kink fit
err_k = err_u
try:
    for s in segs[:-1]:
        k = float(s["right"])
        for xi in (k-0.01, k-0.001, k+0.001, k+0.01):
            e = abs(float(fresh.predict(xi)) - float(np.asarray(probe.evaluate(segs, xi)).ravel()[0]))
            err_k = max(err_k, e)
except Exception:
    err_k = 1e9

ok_fit = err_u < 0.05 and err_k < 0.05
if ok_tile and ok_fit and ok_count:
    reward = 1.0
elif ok_tile and ok_fit:
    reward = 0.5
elif ok_tile and ok_count:
    reward = 0.5
else:
    reward = 0.0
open("/logs/verifier/reward.txt", "w").write(repr(reward))
print(json.dumps({"reward": reward, "expected": expected, "got": len(segs),
                  "err_u": err_u, "err_k": err_k}), file=sys.stderr)
PY