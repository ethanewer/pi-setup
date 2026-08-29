#!/usr/bin/env python3
"""iris-anchor verification. Exit 0 only if every check passes.

Group 1 (board reading)   : /app/board.json matches the visible board, and the
                            deliverable /app/decode_board.py correctly decodes
                            the 2 hidden board images.
Group 2 (block planner)  : /app/path.json reaches the goal on the visible grid,
                            plus the deliverable /app/planner.py solves all 3
                            hidden grids (valid actions reaching goal).
Group 3 (mujoco tuning)  : /app/tuned.xml auto-simulated against
                            /app/reference.xml: same dof topology, identical
                            sampled trajectory within TOL, wall time <= 0.6x.
"""
import glob
import json
import os
import subprocess
import sys
import time

import mujoco
import numpy as np

APP = "/app"
HIDDEN = "/tests/hidden"
DUR = 4.0
SP = 0.02
Q0 = np.array([1.2, -0.9])
TRAJ_TOL = 0.06     # rad
SPEED_FRAC = 0.60   # tuned wall-time fraction ceiling


def log(msg):
    print(msg, flush=True)


# ------------------------------------------------------------------- board
def board_stones(data):
    return sorted((s["r"], s["c"], s["color"]) for s in data.get("stones", []))


def check_board():
    if not os.path.exists(f"{APP}/board.json"):
        return False, "missing /app/board.json"
    got = board_stones(json.load(open(f"{APP}/board.json")))
    want = board_stones(json.load(open("/tests/expected.json")))
    if got != want:
        return False, "visible board mismatch"
    for case in sorted(glob.glob(f"{HIDDEN}/decode_*")):
        png = os.path.join(case, "board.png")
        truth = board_stones(json.load(open(os.path.join(case, "truth.json"))))
        out = "/tmp/decoded.json"
        if os.path.exists(out):
            os.remove(out)
        try:
            subprocess.check_call(
                ["python3", f"{APP}/decode_board.py", png, "-o", out],
                timeout=60)
        except Exception:
            return False, f"hidden decode {case} failed to run"
        if not os.path.exists(out):
            return False, f"hidden decode {case} produced no output"
        got = board_stones(json.load(open(out)))
        if got != truth:
            return False, f"hidden decode {case} mismatch"
    return True, "board decode ok"


# ------------------------------------------------------------------- planner
def validate_grid(grid, actions):
    R = grid["rows"]; C = grid["cols"]
    base = grid["base"]; bl = grid["blocked"]
    blocked = {(r, c) for r in range(R) for c in range(C) if bl[r][c]}
    cap = grid["capacity"]; max_stack = grid["max_stack"]
    pos = tuple(grid["start"]); carry = grid["start_carry"]
    add = {}
    def elev(p): return base[p[0]][p[1]] + add.get(p, 0)
    def inb(p): return 0 <= p[0] < R and 0 <= p[1] < C
    def targets(p):
        out = [p]
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (p[0] + dr, p[1] + dc)
            if inb(q):
                out.append(q)
        return out
    for a in actions:
        t = a.get("type")
        if t == "move":
            to = tuple(a["to"])
            if not inb(to) or to in blocked:
                return False
            if elev(to) > elev(pos) + 1:
                return False
            pos = to
        elif t == "place":
            at = tuple(a["at"])
            if at not in targets(pos) or at in blocked:
                return False
            if carry <= 0 or add.get(at, 0) >= max_stack:
                return False
            add[at] = add.get(at, 0) + 1; carry -= 1
        elif t == "pick":
            at = tuple(a["at"])
            if at not in targets(pos) or at in blocked:
                return False
            if add.get(at, 0) <= 0 or carry >= cap:
                return False
            add[at] = add.get(at, 0) - 1; carry += 1
        else:
            return False
    return pos == tuple(grid["goal"])


def check_planner():
    if not os.path.exists(f"{APP}/path.json"):
        return False, "missing /app/path.json"
    visible_ok = validate_grid(json.load(open(f"{APP}/grid.json")),
                               json.load(open(f"{APP}/path.json"))["actions"])
    if not visible_ok:
        return False, "visible path invalid / not reaching goal"
    for case in sorted(glob.glob(f"{HIDDEN}/grid_*")):
        grid_json = os.path.join(case, "grid.json")
        out = "/tmp/planned.json"
        if os.path.exists(out):
            os.remove(out)
        try:
            subprocess.run(["python3", f"{APP}/planner.py", grid_json,
                           "-o", out], timeout=120, check=True)
        except Exception:
            return False, f"hidden planner {case} failed to run"
        if not os.path.exists(out):
            return False, f"hidden planner {case} no output"
        if not validate_grid(json.load(open(grid_json)),
                             json.load(open(out))["actions"]):
            return False, f"hidden planner {case} invalid path"
    return True, "planner ok"


# ------------------------------------------------------------------- mujoco
def sim_profile(xml):
    m = mujoco.MjModel.from_xml_string(xml)
    n_steps = int(round(DUR / m.opt.timestep))
    times = []
    for _ in range(10):
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
    return median_time, np.array(trace), m.nq


def check_tuning():
    ref_path = f"{APP}/reference.xml"
    tune_path = f"{APP}/tuned.xml"
    for p in (ref_path, tune_path):
        if not os.path.exists(p):
            return False, f"missing {p}"
    ref_xml = open(ref_path).read()
    tune_xml = open(tune_path).read()
    try:
        ref_time, ref_trace, ref_nq = sim_profile(ref_xml)
        tune_time, tune_trace, tune_nq = sim_profile(tune_xml)
    except Exception as e:
        return False, f"model load/simulate failed: {e}"
    if ref_nq != tune_nq:
        return False, "different qpos dimensionality (topology changed)"
    err = float(np.max(np.abs(tune_trace - ref_trace)))
    if err > TRAJ_TOL:
        return False, f"trajectory diverged by {err:.4f} (> {TRAJ_TOL})"
    if tune_time > SPEED_FRAC * ref_time:
        return False, ("not tuned: tuned {tune_time:.4f}s vs ref "
                       f"{ref_time:.4f}s ({tune_time/ref_time:.3f} > 0.6)")
    return True, f"tuning ok  traj_err={err:.5f} time_ratio={tune_time/ref_time:.3f}"


def main():
    results = [("board", check_board()),
               ("planner", check_planner()),
               ("tuning", check_tuning())]
    ok = True
    for name, (passed, msg) in results:
        log(f"[{name}] {'PASS' if passed else 'FAIL'}: {msg}")
        ok = ok and passed
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()