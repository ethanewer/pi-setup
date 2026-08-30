#!/bin/bash
# Oracle for opal-fathom: write the deliverable evaluation program, then RUN it
# on the visible fixture to produce /app/eval_report.json. Never reads /tests.
set -eu

SOLVER="/app/eval_policy.py"
OUT="/app/eval_report.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
"""Deterministic seeded rollout evaluation of a trained routing policy.

Usage: python3 /app/eval_policy.py [case_dir] [output_json]
       (defaults: /app/case /app/eval_report.json)
"""
import json
import os
import sys

import numpy as np


def load_case(case_dir):
    with open(os.path.join(case_dir, "env_config.json"), "r",
              encoding="utf-8") as fh:
        cfg = json.load(fh)
    policy_name = cfg.get("policy_file", "policy.npz")
    with np.load(os.path.join(case_dir, policy_name)) as z:
        W1 = np.asarray(z["W1"], dtype=np.float64)
        b1 = np.asarray(z["b1"], dtype=np.float64)
        W2 = np.asarray(z["W2"], dtype=np.float64)
        b2 = np.asarray(z["b2"], dtype=np.float64)
    return cfg, W1, b1, W2, b2


def policy_action(s, S, W1, b1, W2, b2):
    obs = np.zeros(S, dtype=np.float64)
    obs[s] = 1.0
    h = np.tanh(W1 @ obs + b1)
    logits = W2 @ h + b2
    return int(np.argmax(logits))  # ties -> lowest action index


def main(argv):
    case_dir = argv[1] if len(argv) > 1 else "/app/case"
    out_path = argv[2] if len(argv) > 2 else "/app/eval_report.json"

    cfg, W1, b1, W2, b2 = load_case(case_dir)
    S = int(cfg["n_states"])
    A = int(cfg["n_actions"])
    T = int(cfg["horizon"])
    E = int(cfg["episodes"])

    # Documented seeded recipe: reward table first, then start states.
    rng = np.random.default_rng(int(cfg["seed"]))
    R = rng.integers(0, 4, size=(S, A)).astype(np.float64) / 3.0
    starts = rng.integers(0, S, size=E)

    episode_rewards = []
    for e in range(E):
        s = int(starts[e])
        total = 0.0
        for _ in range(T):
            a = policy_action(s, S, W1, b1, W2, b2)
            total += float(R[s, a])
            s = (s + a + 1) % S
        episode_rewards.append(total)

    mean_reward = float(np.sum(episode_rewards) / (E * T))
    report = {
        "case_id": cfg["case_id"],
        "seed": int(cfg["seed"]),
        "episodes": E,
        "horizon": T,
        "mean_reward": mean_reward,
        "episode_rewards": [float(r) for r in episode_rewards],
        "total_steps": E * T,
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(report, fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    main(sys.argv)
PY
chmod +x "$SOLVER"

# 2. Run the produced program on the visible fixture to generate the report.
python3 "$SOLVER" /app/case "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
python3 - "$OUT" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
print("mean_reward=%.6f threshold check..." % r["mean_reward"])
cfg = json.load(open("/app/case/env_config.json"))
assert r["mean_reward"] >= cfg["min_mean_reward"], "below release floor"
print("release floor OK (%.4f)" % cfg["min_mean_reward"])
PY
