#!/usr/bin/env python3
"""Fixture generator for opal-fathom.

Produces a deterministic seeded-rollout evaluation case for a small
signal-routing policy:

  - env_config.json : environment hyper-parameters (seed, state/action space,
    episodes, horizon, threshold) for the documented rollout recipe
  - policy.npz      : a trained MLP policy  (one-hot state -> tanh hidden ->
    n_actions logits), exported as float32 numpy arrays

The environment is a deterministic MDP:
  reward table  R = default_rng(seed).integers(0, 4, (S, A)) / 3.0
  start states  starts = same rng .integers(0, S, size=E)   (drawn AFTER R)
  transition    s' = (s + a + 1) mod S ; reward R[s, a] per step

The policy is built analytically to imitate the per-step greedy-optimal
behaviour-cloning target argmax_a R[s, a] (ties -> lowest action): a one-hot
state input turns the MLP into an exact lookup table with a comfortable
logit margin, so a correctly-loaded policy attains the per-step maximum while
any mis-loaded one diverges from the reference rollout.

Usage: python3 gen.py <outdir> <case_id> <seed> <S> <A> <T> <E>
"""
import json
import os
import sys

import numpy as np


def greedy_targets(R):
    """argmax_a R[s, a], ties -> lowest action index."""
    return [int(np.argmax(R[s])) for s in range(R.shape[0])]


def rollout(cfg, W1, b1, W2, b2):
    """The single reference implementation of the documented seeded rollout.

    Replicated verbatim in tests/verify.py and in the oracle's eval_policy.py.
    """
    S = int(cfg["n_states"])
    A = int(cfg["n_actions"])
    T = int(cfg["horizon"])
    E = int(cfg["episodes"])
    rng = np.random.default_rng(int(cfg["seed"]))
    R = rng.integers(0, 4, size=(S, A)).astype(np.float64) / 3.0
    starts = rng.integers(0, S, size=E)
    W1 = np.asarray(W1, dtype=np.float64)
    b1 = np.asarray(b1, dtype=np.float64)
    W2 = np.asarray(W2, dtype=np.float64)
    b2 = np.asarray(b2, dtype=np.float64)
    episode_rewards = []
    for e in range(E):
        s = int(starts[e])
        total = 0.0
        for _ in range(T):
            obs = np.zeros(S, dtype=np.float64)
            obs[s] = 1.0
            h = np.tanh(W1 @ obs + b1)
            logits = W2 @ h + b2
            a = int(np.argmax(logits))  # ties -> lowest action index
            total += float(R[s, a])
            s = (s + a + 1) % S
        episode_rewards.append(total)
    mean_reward = float(np.sum(episode_rewards) / (E * T))
    return {
        "R": R,
        "starts": [int(x) for x in starts],
        "episode_rewards": episode_rewards,
        "mean_reward": mean_reward,
    }


def build(outdir, case_id, seed, S, A, T, E):
    # Draw the environment instance with the documented recipe.
    rng_env = np.random.default_rng(seed)
    R = rng_env.integers(0, 4, size=(S, A)).astype(np.float64) / 3.0
    starts = rng_env.integers(0, S, size=E)

    targets = greedy_targets(R)
    H = S  # one hidden unit per state => exact lookup-table policy

    # Analytic behaviour-cloned weights (float32 on disk, like a real export).
    W1 = np.zeros((H, S), dtype=np.float32)
    for i in range(H):
        W1[i, i] = 2.0
    rng_w = np.random.default_rng(seed + 11)
    b1 = rng_w.uniform(-0.05, 0.05, size=(H,)).astype(np.float32)
    W2 = np.zeros((A, H), dtype=np.float32)
    for i in range(H):
        for a in range(A):
            W2[a, i] = 2.5 if a == targets[i] else -1.0
    b2 = np.zeros((A,), dtype=np.float32)

    cfg = {
        "case_id": case_id,
        "seed": int(seed),
        "n_states": int(S),
        "n_actions": int(A),
        "horizon": int(T),
        "episodes": int(E),
        "obs_dim": int(S),
        "hidden_dim": int(H),
        "transition": "s_next = (s + a + 1) mod n_states",
        "policy_file": "policy.npz",
        "min_mean_reward": 0.0,
    }

    ref = rollout(cfg, W1, b1, W2, b2)
    Rref = ref["mean_reward"]
    # greedy-optimal per-step: reward at every step equals max_a R[s, a]
    cfg["min_mean_reward"] = round(Rref - 0.02, 6)

    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "env_config.json"), "w") as fh:
        json.dump(cfg, fh, indent=2)
        fh.write("\n")
    np.savez(os.path.join(outdir, "policy.npz"),
             W1=W1, b1=b1, W2=W2, b2=b2)

    print("%s: starts=%s ep_rewards=%s mean=%.6f thr=%.6f" % (
        case_id, ref["starts"], [round(r, 3) for r in ref["episode_rewards"]],
        Rref, cfg["min_mean_reward"]))
    # sanity 1: per-state argmax of the cloned policy == greedy target
    for s in range(S):
        obs = np.zeros(S, dtype=np.float64)
        obs[s] = 1.0
        h = np.tanh(W1.astype(np.float64) @ obs + b1.astype(np.float64))
        lg = W2.astype(np.float64) @ h + b2.astype(np.float64)
        assert int(np.argmax(lg)) == targets[s], (case_id, s)
    # sanity 2: the cloned policy must clear the threshold
    assert Rref >= cfg["min_mean_reward"] - 1e-12
    # sanity 3: a scrambled (mis-loaded) policy must miss the reference
    rng_s = np.random.default_rng(seed + 99)
    W2s = rng_s.permutation(W2.reshape(-1)).reshape(W2.shape).astype(np.float32)
    if not np.array_equal(W2s, W2):
        broken = rollout(cfg, W1, b1, W2s, b2)
        assert abs(broken["mean_reward"] - Rref) > 1e-6, case_id


if __name__ == "__main__":
    outdir = sys.argv[1]
    case_id = sys.argv[2]
    seed = int(sys.argv[3])
    S, A, T, E = (int(x) for x in sys.argv[4:8])
    build(outdir, case_id, seed, S, A, T, E)
