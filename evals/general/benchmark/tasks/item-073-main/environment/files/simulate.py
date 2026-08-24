#!/usr/bin/env python3
"""Baseline (deliberately slow, yet semantically correct) MuJoCo simulation.

It recompiles the model from the XML string on every step, so it is correct
but slow.  Produce /app/optimize.py that computes the SAME recorded state at
least 4x faster (and with no NaN/Inf), changing only the implementation, never
the physics.
"""
import json
import time

import numpy as np
import mujoco

XML = "/app/arm.xml"
N = 2000
INIT_QPOS = np.array([1.3, 0.5], dtype=np.float64)
INIT_QVEL = np.array([0.0, 0.0], dtype=np.float64)


def simulate_slow():
    xml = open(XML).read()
    t0 = time.perf_counter()
    qpos_all = []
    qvel_all = []
    t_all = []
    state = None
    m = None
    dt = None
    for i in range(N):
        # The model is (re)compiled from the XML string on every step.
        m = mujoco.MjModel.from_xml_string(xml)
        d = mujoco.MjData(m)
        if state is None:
            d.qpos[:] = INIT_QPOS
            d.qvel[:] = INIT_QVEL
        else:
            d.qpos[:] = state[0]
            d.qvel[:] = state[1]
        mujoco.mj_step(m, d)
        state = (d.qpos.copy(), d.qvel.copy())
        dt = float(getattr(m.opt, "timestep", getattr(m.opt, "dt", 0.01)))
        qpos_all.append(state[0])
        qvel_all.append(state[1])
        t_all.append((i + 1) * dt)
    elapsed = time.perf_counter() - t0
    qpos = np.array(qpos_all, dtype=np.float64).reshape(N, m.nq)
    qvel = np.array(qvel_all, dtype=np.float64).reshape(N, m.nv)
    t = np.array(t_all, dtype=np.float64)
    np.savez("/app/result.npz", t=t, qpos=qpos, qvel=qvel)
    return {"slow_seconds": elapsed, "steps": N}


if __name__ == "__main__":
    print(json.dumps(simulate_slow()))