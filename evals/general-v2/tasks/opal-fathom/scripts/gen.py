#!/usr/bin/env python3
"""Fixture generator for opal-fathom.

Produces a corridor coin-collection RL-evaluation case:
  - env_config.json : environment + policy hyper-parameters (incl. the
    deterministic sampling recipe seed and a min_mean_reward threshold)
  - policy.npz      : a small behaviour-cloned MLP policy
    (one-hot position -> tanh hidden -> 2 logits; 0 = left, 1 = right)

The policy is built analytically to imitate a "walk toward the nearest
remaining coin" behaviour-cloning target (one-hot input => the MLP is an
exact lookup table with a comfortable logit margin), so a correctly loaded
policy collects nearly every reachable coin while a wrongly-loaded one does
not.

Usage: python3 gen.py <outdir> <case_id> <seed> <L> <K> <T> <E>
"""
import json
import os
import sys

import numpy as np


def target_actions(coins, L):
    """Behaviour-cloning target: a sweep policy. If any corridor cell to the
    right of p still holds an (uncollected-at-demo-time) coin, walk right;
    otherwise walk left.  This stateless target sweeps the corridor and walks
    over every coin, so a correctly-loaded policy collects the whole coin set
    within the horizon, while any mis-loaded one does not."""
    targets = []
    for p in range(L):
        targets.append(1 if any(c > p for c in coins) else 0)
    return targets


def rollout(cfg, W1, b1, W2, b2):
    """The single reference implementation of the documented environment.

    Replicated verbatim in tests/verify.py and in the oracle's eval_policy.py.
    """
    L = int(cfg["corridor_len"])
    K = int(cfg["n_coins"])
    T = int(cfg["horizon"])
    E = int(cfg["episodes"])
    rng = np.random.default_rng(int(cfg["seed"]))
    # coins never spawn on the top cell L-1 (the charging dock)
    coins = [int(c) for c in rng.choice(L - 1, size=K, replace=False)]
    starts = [int(s) for s in rng.integers(0, L, size=E)]
    coin_set = set(coins)
    W1 = np.asarray(W1, dtype=np.float64)
    b1 = np.asarray(b1, dtype=np.float64)
    W2 = np.asarray(W2, dtype=np.float64)
    b2 = np.asarray(b2, dtype=np.float64)
    episode_rewards = []
    for s0 in starts:
        pos = int(s0)
        collected = set()
        total = 0
        for _ in range(T):
            obs = np.zeros(L, dtype=np.float64)
            obs[pos] = 1.0
            h = np.tanh(W1 @ obs + b1)
            logits = W2 @ h + b2
            action = int(np.argmax(logits))  # ties -> lower index (left)
            if action == 0:
                npos = max(pos - 1, 0)
            else:
                npos = min(pos + 1, L - 1)
            if npos in coin_set and npos not in collected:
                total += 1
                collected.add(npos)
            pos = npos
        episode_rewards.append(total)
    mean_reward = sum(episode_rewards) / E
    return {
        "coins": coins,
        "starts": starts,
        "episode_rewards": episode_rewards,
        "mean_reward": mean_reward,
    }


def build(outdir, case_id, seed, L, K, T, E):
    targets = None
    # Draw the env instance first (same recipe the evaluation must replicate).
    rng_env = np.random.default_rng(seed)
    # coins never spawn on the top cell L-1 (the charging dock)
    coins = [int(c) for c in rng_env.choice(L - 1, size=K, replace=False)]
    starts = [int(s) for s in rng_env.integers(0, L, size=E)]

    targets = target_actions(coins, L)
    H = L  # one hidden unit per corridor cell => exact lookup-table policy

    # Analytic behaviour-cloned weights (float32 on disk, like a real export).
    W1 = np.zeros((H, L), dtype=np.float32)
    for i in range(H):
        W1[i, i] = 2.0
    rng_w = np.random.default_rng(seed + 7)
    b1 = rng_w.uniform(-0.05, 0.05, size=(H,)).astype(np.float32)
    W2 = np.zeros((2, H), dtype=np.float32)
    for i in range(H):
        sgn = 2.0 if targets[i] == 0 else -2.0
        W2[0, i] = sgn
        W2[1, i] = -sgn
    b2 = np.zeros((2,), dtype=np.float32)

    cfg = {
        "case_id": case_id,
        "seed": int(seed),
        "corridor_len": int(L),
        "n_coins": int(K),
        "horizon": int(T),
        "episodes": int(E),
        "obs_dim": int(L),
        "hidden_dim": int(H),
        "n_actions": 2,
        "policy_file": "policy.npz",
        "min_mean_reward": 0.0,
    }

    ref = rollout(cfg, W1, b1, W2, b2)
    R = ref["mean_reward"]
    cfg["min_mean_reward"] = round(R * 0.9, 6)

    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "env_config.json"), "w") as fh:
        json.dump(cfg, fh, indent=2)
        fh.write("\n")
    np.savez(os.path.join(outdir, "policy.npz"),
             W1=W1, b1=b1, W2=W2, b2=b2)

    print("%s: coins=%s starts=%s rewards=%s mean=%.4f thr=%.4f" % (
        case_id, ref["coins"][:6], ref["starts"], ref["episode_rewards"],
        R, cfg["min_mean_reward"]))
    # sanity: correct policy must reach the threshold with margin
    assert R >= cfg["min_mean_reward"] - 1e-12
    if K > 0:
        # a broken (zero-head) policy must not reach the threshold
        zW2 = np.zeros_like(W2)
        broken = rollout(cfg, W1, b1, zW2, b2)
        assert broken["mean_reward"] < cfg["min_mean_reward"], (
            case_id, broken["mean_reward"], cfg["min_mean_reward"])
        # and the per-position argmax of the cloned policy must match the
        # behaviour target exactly (comfortable logit margin)
        for p in range(L):
            obs = np.zeros(L, dtype=np.float64)
            obs[p] = 1.0
            h = np.tanh(W1.astype(np.float64) @ obs + b1.astype(np.float64))
            lg = W2.astype(np.float64) @ h + b2.astype(np.float64)
            assert int(np.argmax(lg)) == targets[p], (case_id, p)


if __name__ == "__main__":
    outdir = sys.argv[1]
    case_id = sys.argv[2]
    seed = int(sys.argv[3])
    L, K, T, E = (int(x) for x in sys.argv[4:8])
    build(outdir, case_id, seed, L, K, T, E)
