#!/usr/bin/env python3
"""Adversarial slow baseline for item-073-hard.

This is the starting point you must fix AND speed up.  It simulates the same
double-pendulum (arm.xml) as the (deliberately) slow reference, but it has two
problems stacked on top:

  1. performance: the MJCF model is recompiled from the XML string on every
     single step (paying full compile cost N times), and every record is
     copied through nested Python lists;
  2. correctness/robustness: the recording step "cleans" each velocity sample
     by dividing it by the current second-joint velocity.  Real double
     pendulums have zero-crossings, so this division produces ±Inf / NaN on
     some steps, and once NaN enters the state it stays.

Your optimize.py must reproduce the RAW simulation state (see the
instruction) with no such normalization, preserve the physics exactly, and be
at least 4x faster.
"""
import json
import time

import numpy as np
import mujoco

XML = "/app/arm.xml"
N = 3000
INIT_QPOS = np.array([1.3, 0.5], dtype=np.float64)
INIT_QVEL = np.array([0.0, 0.0], dtype=np.float64)


def simulate_slow():
    xml = open(XML).read()
    t0 = time.perf_counter()
    qpos_all = []
    qvel_rows = []
    t_rows = []
    state = None
    m = None
    for i in range(N):
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
        # BUG (adversarial): "cleaning" that divides by a DOF that crosses
        # zero -> inf/NaN appears on some rows.
        norm = float(state[1][1])
        qpos_all.append(list(state[0]))
        qvel_rows.append(list(state[1] / norm))
        t_rows.append((i + 1) * float(getattr(m.opt, "timestep", getattr(m.opt, "dt", 0.01))))
    elapsed = time.perf_counter() - t0

    qpos = np.array(qpos_all, dtype=np.float64)
    qvel = np.array(qvel_rows, dtype=np.float64)
    t = np.array(t_rows, dtype=np.float64)
    np.savez("/app/result.npz", t=t, qpos=qpos, qvel=qvel)
    return {"slow_seconds": elapsed, "steps": N}


if __name__ == "__main__":
    print(json.dumps(simulate_slow()))