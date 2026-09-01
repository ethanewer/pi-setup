#!/bin/bash
mkdir -p /logs/verifier
reward=0

if [ ! -f /app/probe.py ] || [ ! -f /app/models.md ]; then
  echo "$reward" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import importlib.util, sys, json
import numpy as np

try:
    sys.path.insert(0, "/app")
    spec = importlib.util.spec_from_file_location("probe", "/app/probe.py")
    probe = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(probe)
    import model

    lo, hi = -4.0, 4.0
    seed = 7755319
    fresh = model.ReLUMLP(num_hidden=6, w1_scale=1.2, b_scale=1.7, w2_scale=1.0,
                          seed=seed)

    segs = probe.segment(fresh, lo, hi)
    if not isinstance(segs, list) or not segs:
        raise ValueError("segment() returned invalid result")

    # 1. coverage / contiguity
    ok_tile = (abs(segs[0]["left"] - lo) < 1e-6
               and abs(segs[-1]["right"] - hi) < 1e-6
               and all(abs(segs[i]["right"] - segs[i+1]["left"]) < 1e-4
                       for i in range(len(segs) - 1))
               and all(abs(s["right"] - s["left"]) > 1e-9 for s in segs))

    # 2. true segment count (distinct kinks strictly interior + 1)
    bp = sorted(set(round(float(p), 9) for p in fresh.breakpoints()))
    expected = len([p for p in bp if lo < p < hi]) + 1
    ok_count = abs(expected - len(segs)) <= 1

    # 3. fresh-input fit
    rng = np.random.default_rng(seed + 1)
    xs = rng.uniform(lo, hi, 6000)
    ys = np.asarray(fresh.predict(xs), dtype=float)
    rec = np.asarray(probe.evaluate(segs, xs), dtype=float)
    err = float(np.max(np.abs(ys - rec))) if rec.shape == ys.shape else 1e9
    ok_fit = bool(err < 0.05)

    if ok_tile and ok_fit and ok_count:
        reward = 1.0
    elif ok_tile and ok_fit:
        reward = 0.5
    elif ok_tile and ok_count:
        reward = 0.5
    else:
        reward = 0.0
    print(json.dumps({"reward": reward, "expected": expected, "got": len(segs),
                      "err": err}), file=sys.stderr)
except Exception as e:
    reward = 0.0
    print("verifier exception:", repr(e), file=sys.stderr)

open("/logs/verifier/reward.txt", "w").write(repr(reward))
PY