#!/bin/bash
# Oracle for harbor-keystone: write the value-iteration trainer, then RUN it
# with no arguments on the shipped config to produce /app/policy.json.
# Never reads /tests.
set -eu

TRAINER="/app/train.py"

cat > "$TRAINER" <<'PY'
"""Slippery-warehouse policy trainer: exact value iteration on the
documented stochastic grid dynamics."""
import argparse
import json
import sys

import numpy as np

DELTAS = {0: (0, -1), 1: (0, 1), 2: (-1, 0), 3: (1, 0)}
GOAL_REWARD = 100.0
STEP_REWARD = -1.0


def die(msg):
    sys.stderr.write("error: %s\n" % msg)
    sys.exit(1)


def load_config(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            cfg = json.load(fh)
    except Exception as exc:
        die("cannot read config: %s" % exc)
    if not isinstance(cfg, dict):
        die("config must be a JSON object")
    for key in ("size", "goal", "obstacles", "slip", "gamma"):
        if key not in cfg:
            die("config missing required key %r" % key)
    size = int(cfg["size"])
    gx, gy = int(cfg["goal"][0]), int(cfg["goal"][1])
    if size <= 1:
        die("size must be >= 2")
    if not (0 <= gx < size and 0 <= gy < size):
        die("goal outside the grid")
    obstacles = {(int(a), int(b)) for a, b in cfg["obstacles"]}
    if (gx, gy) in obstacles:
        die("goal cell is an obstacle")
    slip = float(cfg["slip"])
    gamma = float(cfg["gamma"])
    if not (0.0 <= slip < 1.0):
        die("slip must be in [0, 1)")
    if not (0.0 < gamma < 1.0):
        die("gamma must be in (0, 1)")
    return size, (gx, gy), obstacles, slip, gamma


def move(size, obstacles, pos, action):
    dx, dy = DELTAS[action]
    nx, ny = pos[0] + dx, pos[1] + dy
    if 0 <= nx < size and 0 <= ny < size and (nx, ny) not in obstacles:
        return (nx, ny)
    return pos  # blocked: stay


def transition(size, obstacles, goal, slip, pos, action):
    """Return list of (prob, reward, next_pos_or_None) for the intended
    action; next None = terminal (entered the goal)."""
    probs = []
    for executed in range(4):
        q = (1.0 - slip) if executed == action else slip / 4.0
        if q == 0.0:
            continue
        nxt = move(size, obstacles, pos, executed)
        if nxt == goal:
            probs.append((q, GOAL_REWARD, None))
        else:
            probs.append((q, STEP_REWARD, nxt))
    return probs


def value_iteration(size, obstacles, goal, slip, gamma, tol=1e-11,
                    max_iter=200000):
    free = [(x, y) for x in range(size) for y in range(size)
            if (x, y) != goal and (x, y) not in obstacles]
    idx = {p: i for i, p in enumerate(free)}
    V = np.zeros(len(free))
    # precompute transitions per (cell, action)
    trans = {(p, a): transition(size, obstacles, goal, slip, p, a)
             for p in free for a in range(4)}
    for _ in range(max_iter):
        nv = np.empty_like(V)
        for p in free:
            i = idx[p]
            best = -np.inf
            for a in range(4):
                val = 0.0
                for q, r, nxt in trans[(p, a)]:
                    fut = 0.0 if nxt is None else gamma * V[idx[nxt]]
                    val += q * (r + fut)
                if val > best:
                    best = val
            nv[i] = best
        if np.max(np.abs(nv - V)) < tol:
            V = nv
            break
        V = nv
    return free, idx, V, trans


def greedy_policy(free, idx, V, trans):
    policy = {}
    for p in free:
        vals = []
        for a in range(4):
            val = 0.0
            for q, r, nxt in trans[(p, a)]:
                fut = 0.0 if nxt is None else V[idx[nxt]]
                val += q * (r + fut)
            vals.append(val)
        policy["%d,%d" % p] = int(np.argmax(vals))
    return policy


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="/app/rl_config.json")
    ap.add_argument("--out", default="/app/policy.json")
    args = ap.parse_args()

    size, goal, obstacles, slip, gamma = load_config(args.config)
    free, idx, V, trans = value_iteration(size, obstacles, goal, slip, gamma)
    policy = greedy_policy(free, idx, V, trans)
    out = {"size": size, "actions": policy}
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2, sort_keys=True)
    print("wrote policy for %d free cells to %s" % (len(policy), args.out))


if __name__ == "__main__":
    main()
PY

chmod +x "$TRAINER"

python3 "$TRAINER"

echo "solve.sh done"
ls -l "$TRAINER" /app/policy.json
