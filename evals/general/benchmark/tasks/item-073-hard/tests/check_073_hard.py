"""Verifier logic for item-073-hard.

Independent objective checks:
  1. reference free-run of arm.xml from the documented initial condition,
  2. agent /app/result.npz must match on qpos/qvel within 1e-6, all finite,
  3. agent's optimize.py must be >= 4x faster than a per-step recompiling
     baseline (measured in-container).

Prints reward (1, 0.5, 0) to stdout; always exits 0.
"""
import subprocess
import sys
import time

import numpy as np
import mujoco

XML = "/app/arm.xml"
N = 3000
INIT_QPOS = [1.3, 0.5]
INIT_QVEL = [0.0, 0.0]
RESULT = "/app/result.npz"


def reference():
    m = mujoco.MjModel.from_xml_string(open(XML).read())
    d = mujoco.MjData(m)
    d.qpos[:] = INIT_QPOS
    d.qvel[:] = INIT_QVEL
    ref_q = np.empty((N, m.nq))
    ref_v = np.empty((N, m.nv))
    for i in range(N):
        mujoco.mj_step(m, d)
        ref_q[i] = d.qpos
        ref_v[i] = d.qvel
    return ref_q, ref_v


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


def agent_seconds():
    t0 = time.perf_counter()
    subprocess.run(["python3", "/app/optimize.py"], check=True, timeout=250,
                   capture_output=True)
    return time.perf_counter() - t0


def main():
    try:
        ref_q, ref_v = reference()
        data = np.load(RESULT)
        got_q = data["qpos"]
        got_v = data["qvel"]
        if got_q.shape != ref_q.shape or got_v.shape != ref_v.shape:
            print(0)
            return
        residual = max(
            float(np.max(np.abs(got_q - ref_q))),
            float(np.max(np.abs(got_v - ref_v))),
        )
        finite = bool(
            np.isfinite(got_q).all()
            and np.isfinite(got_v).all()
            and np.isfinite(data["t"]).all()
        )
        slow = slow_loop_seconds()
        opt = agent_seconds()
        speedup = (slow / opt) if opt > 0 else 0.0

        if residual <= 1e-6 and finite and speedup >= 4.0:
            print(1)
        elif residual <= 1e-6 and finite:
            print("0.5")
        else:
            print(0)
    except Exception:
        print(0)


if __name__ == "__main__":
    main()
    sys.exit(0)