#!/usr/bin/env python3
"""Oracle tuner for the dual-arm MJCF reference.

Loads the reference model, characterises its reference trajectory and wall-clock
cost at its baseline timestep, then empirically searches the allowed-step set for
the fastest configuration whose sampled joint trajectory still matches the
reference within a tolerance band. Writes the winning model to /app/tuned.xml.

The tuning is done by actually simulating (measuring time and trajectory); it
never hands off a precomputed answer.
"""
import sys
import time

import mujoco
import numpy as np

REF_PATH = "/app/reference.xml"
OUT_PATH = "/tmp/tuned.xml"
DUR = 4.0
SP = 0.02            # trajectory sampling period (s); must divide every allowed dt
Q0 = np.array([1.2, -0.9])   # release configuration
TOL = 0.05           # max |qpos_tuned - qpos_ref| sampled deviation (rad)
SPEED_RATIO = 0.60   # tuned wall time must be <= this fraction of reference
ALLOWED_DT = [0.0005, 0.001, 0.002, 0.004, 0.005, 0.01]


def run_model(xml, reps=10):
    m = mujoco.MjModel.from_xml_string(xml)
    n_steps = int(round(DUR / m.opt.timestep))
    times = []
    for _ in range(reps):
        d = mujoco.MjData(m)
        d.qpos[:] = Q0
        mujoco.mj_forward(m, d)
        t0 = time.perf_counter()
        for _ in range(n_steps):
            mujoco.mj_step(m, d)
        times.append(time.perf_counter() - t0)
    median_time = float(np.median(times))
    d = mujoco.MjData(m)
    d.qpos[:] = Q0
    mujoco.mj_forward(m, d)
    spp = int(round(SP / m.opt.timestep))
    trace = []
    for _ in range(int(round(DUR / SP))):
        for _ in range(spp):
            mujoco.mj_step(m, d)
        trace.append(np.array(d.qpos, copy=True))
    return median_time, np.array(trace)


def main():
    ref_xml = open(REF_PATH).read()
    ref_time, ref_trace = run_model(ref_xml)
    best, best_xml = None, None
    for dt in ALLOWED_DT:
        cand = ref_xml.replace('timestep="0.0005"', f'timestep="{dt}"')
        tune_time, tune_trace = run_model(cand)
        err = float(np.max(np.abs(tune_trace - ref_trace)))
        ratio = tune_time / ref_time
        if err <= TOL and ratio <= SPEED_RATIO and (best is None or dt > best[0]):
            best, best_xml = (dt, err, ratio), cand
    if best is None:
        print("no viable tuning configuration found", file=sys.stderr)
        sys.exit(1)
    dt, err, ratio = best
    with open(OUT_PATH, "w") as fh:
        fh.write(best_xml)
    print(f"tuned dt={dt} traj_err={err:.6f} time_ratio={ratio:.3f} -> {OUT_PATH}")


if __name__ == "__main__":
    main()