#!/bin/bash
set -euo pipefail

# Oracle solution for item-073-main.
# 1. Writes the optimized physics loop /app/optimize.py (model compiled once).
# 2. Runs it to produce /app/result.npz.
# 3. Measures slow-vs-fast wall time and state residual -> /app/timing.json.

cat > /app/optimize.py <<'PYEOF'
#!/usr/bin/env python3
"""Optimized (physics-preserving) MuJoCo simulation.

Same model / timestep / initial condition / number of steps as simulate.py,
but the model is compiled exactly ONCE and a single MjData is stepped N times.
"""
import numpy as np
import mujoco

XML = "/app/arm.xml"
N = 2000
INIT_QPOS = [1.3, 0.5]
INIT_QVEL = [0.0, 0.0]


def main():
    m = mujoco.MjModel.from_xml_string(open(XML).read())
    d = mujoco.MjData(m)
    d.qpos[:] = INIT_QPOS
    d.qvel[:] = INIT_QVEL
    qpos = np.empty((N, m.nq), dtype=np.float64)
    qvel = np.empty((N, m.nv), dtype=np.float64)
    t = np.empty(N, dtype=np.float64)
    for i in range(N):
        mujoco.mj_step(m, d)
        qpos[i] = d.qpos
        qvel[i] = d.qvel
        t[i] = (i + 1) * float(getattr(m.opt, "timestep", getattr(m.opt, "dt", 0.01)))
    np.savez("/app/result.npz", t=t, qpos=qpos, qvel=qvel)


if __name__ == "__main__":
    main()
PYEOF

python3 /app/optimize.py

python3 - <<'PYEOF'
import json
import subprocess
import time

import numpy as np
import mujoco

XML = "/app/arm.xml"
N = 2000
INIT_QPOS = [1.3, 0.5]
INIT_QVEL = [0.0, 0.0]


def slow_loop_seconds():
    xml = open(XML).read()
    t0 = time.perf_counter()
    state = None
    for _ in range(N):
        m = mujoco.MjModel.from_xml_string(xml)
        d = mujoco.MjData(m)
        if state is None:
            d.qpos[:] = INIT_QPOS
        else:
            d.qpos[:] = state
        mujoco.mj_step(m, d)
        state = d.qpos.copy()
    return time.perf_counter() - t0


def reference():
    m = mujoco.MjModel.from_xml_string(open(XML).read())
    d = mujoco.MjData(m)
    d.qpos[:] = INIT_QPOS
    d.qvel[:] = INIT_QVEL
    ref_q = np.empty((N, m.nq), dtype=np.float64)
    ref_v = np.empty((N, m.nv), dtype=np.float64)
    for i in range(N):
        mujoco.mj_step(m, d)
        ref_q[i] = d.qpos
        ref_v[i] = d.qvel
    return ref_q, ref_v


slow_sec = slow_loop_seconds()
t0 = time.perf_counter()
subprocess.run(["python3", "/app/optimize.py"], check=True)
opt_sec = time.perf_counter() - t0

ref_q, ref_v = reference()
data = np.load("/app/result.npz")
residual = max(
    float(np.max(np.abs(data["qpos"] - ref_q))),
    float(np.max(np.abs(data["qvel"] - ref_v))),
)
finite = bool(np.isfinite(data["qpos"]).all() and np.isfinite(data["qvel"]).all())

report = {
    "slow_seconds": round(slow_sec, 6),
    "optimized_seconds": round(opt_sec, 6),
    "speedup": round(slow_sec / opt_sec, 4),
    "max_residual": residual,
    "finite": finite,
}
with open("/app/timing.json", "w") as f:
    json.dump(report, f, indent=2)

print(json.dumps(report))
PYEOF