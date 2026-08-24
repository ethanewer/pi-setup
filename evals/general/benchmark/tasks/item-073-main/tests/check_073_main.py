"""Verifier logic for item-073-main.

Independent checks (nothing read from the agent except its deliverables):
  1. reference = deterministic free-running simulation of arm.xml from the
     documented initial condition (continuous stepping),
  2. the agent's /app/result.npz must match the reference on qpos/qvel to
     1e-5 absolute and contain no NaN/Inf,
  3. the agent's /app/optimize.py must run meaningfully faster than a
     per-step model-recompiling baseline (speedup >= 2.5 for full credit).

Prints the reward (1, 0.5, or 0) to stdout; exit code is always 0 so the
shell layer can record whatever number was produced.
"""
import subprocess
import sys
import time

import numpy as np
import mujoco

XML = "/app/arm.xml"
N = 2000
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

        if residual <= 1e-5 and finite and speedup >= 2.5:
            print(1)
        elif residual <= 1e-5 and finite:
            print("0.5")  # physics right, too slow
        else:
            print(0)
    except Exception:
        print(0)


if __name__ == "__main__":
    main()
    sys.exit(0)