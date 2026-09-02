#!/usr/bin/env python3
"""cross_entropy_opt.py -- a cross-entropy optimizer that memoizes shared
prefix computation.

Planning score (documented reward, must stay stable):

   freq = [0]*K
   value = 0.0
   for i in range(L):
       a = int(seq[i]); freq[a] += 1
       value += W[i][a]
       if freq[a] > 1:
           value += BP[i][freq[a]]
       value += float(XC[i].dot(freq))     # state-interaction term

   score(seq) = value

W is (L, K); BP is (L, L+1); XC is (L, K).  BP[i][r] is the repeat-bonus paid
when action at position i becomes the r-th occurrence of its symbol (r >= 2).
A memo cache keyed on shared prefixes reuses the intermediate (value,
count-vector) state so batches of near-identical sequences are scored far
faster than recomputing every prefix from scratch.

Subcommands
-----------
  optimize --spec in.json -o out.json
      runs n_iterations of cross-entropy sampling + elite re-estimation and
      writes {"final_theta","history","rows","cols","improvement"}.
  memo --spec in.json -o out.json
      scores the given sequences both with and without prefix memoization and
      writes {"scores","speedup","max_abs_diff"}.
"""
import argparse
import json
import time

import numpy as np


# ---------------------------------------------------------------------------
# Reward
# ---------------------------------------------------------------------------
def score(seq, W, BP, XC):
    L, K = W.shape
    freq = np.zeros(K, dtype=int)
    value = 0.0
    for i in range(L):
        a = int(seq[i])
        freq[a] += 1
        value += W[i][a]
        if freq[a] > 1:
            value += BP[i][freq[a]]
        value += float(XC[i].dot(freq))
    return value


def _brute_scores(seqs, W, BP, XC):
    return np.array([score(s, W, BP, XC) for s in seqs])


def memoized_scores(seqs, W, BP, XC, _key_hint=None):
    """Score `seqs` caching every shared prefix with a trie keyed on integer
    node ids (Sequence -> unique prefix node), so extending an already-scored
    prefix is O(1) rather than re-deriving the shared computation.

    `_key_hint` is unused; it documents that numpy array keys can be passed.
    """
    L, K = W.shape
    children = {0: {}}
    state = {0: (0.0, np.zeros(K, dtype=int))}
    next_id = 1
    out = np.empty(len(seqs), dtype=float)
    for r, s in enumerate(seqs):
        a = np.asarray(s, dtype=np.int64).reshape(-1)
        node = 0
        value, freq = state[node]
        p = 0
        while p < L:
            child = children[node].get(a[p])
            if child is None:
                break
            node = child
            value, freq = state[node]
            p += 1
        freq = freq.copy()
        for q in range(p, L):
            idx = a[q]
            freq[idx] += 1
            value += W[q][idx]
            if freq[idx] > 1:
                value += BP[q][freq[idx]]
            value += float(XC[q].dot(freq))
            child = next_id
            next_id += 1
            children[node][idx] = child
            children[child] = {}
            state[child] = (value, freq.copy())
            node = child
        out[r] = value
    return out


def _timeit(fn, n=5):
    best = None
    for _ in range(n):
        t0 = time.perf_counter()
        fn()
        dt = time.perf_counter() - t0
        best = dt if best is None else min(best, dt)
    return best


# ---------------------------------------------------------------------------
# Optimizer (cross-entropy method)
# ---------------------------------------------------------------------------
def sample_sequences(theta, n_samples, rng):
    L, K = theta.shape
    out = np.empty((n_samples, L), dtype=int)
    for i in range(L):
        out[:, i] = rng.choice(K, size=n_samples, p=theta[i])
    return out


def optimize(theta0, W, BP, XC, n_samples=1200, elite=180, n_iterations=9, seed=7):
    """Run cross-entropy optimization; returns (theta_final, history, seed)."""
    rng = np.random.default_rng(seed)
    L, K = theta0.shape
    theta = np.clip(np.asarray(theta0, float), 1e-5, None)
    theta = theta / theta.sum(axis=1, keepdims=True)
    history = []
    for _ in range(n_iterations):
        X = sample_sequences(theta, n_samples, rng)
        scores = memoized_scores(X, W, BP, XC)
        order = np.argsort(scores)[::-1][:elite]
        elite_X = X[order]
        counts = np.zeros((L, K), dtype=float)
        for i in range(L):
            counts[i] = np.bincount(elite_X[:, i], minlength=K)
        theta = (counts + 1.0) / (elite_X.shape[0] + K)
        history.append(float(scores[order].mean()))
    return theta, history, seed


def _load(f):
    with open(f) as fh:
        return json.load(fh)


def cmd_optimize(args):
    spec = _load(args.spec)
    W = np.asarray(spec["W"], float)
    BP = np.asarray(spec["BP"], float)
    XC = np.asarray(spec.get("XC", np.zeros((len(W), len(W[0])))), float)
    theta0 = np.asarray(spec["theta0"], float)
    n_iterations = int(spec.get("n_iterations", 8))
    n_samples = int(spec.get("n_samples", 1200))
    seed = int(spec.get("seed", 7))
    theta, history, _ = optimize(theta0, W, BP, XC, n_samples=n_samples,
                                 n_iterations=n_iterations, seed=seed)
    out = {
        "rows": int(theta.shape[0]),
        "cols": int(theta.shape[1]),
        "final_theta": theta.tolist(),
        "history": history,
        "improvement": float(history[-1] - history[0]),
    }
    with open(args.output, "w") as f:
        json.dump(out, f)


def cmd_memo(args):
    spec = _load(args.spec)
    W = np.asarray(spec["W"], float)
    BP = np.asarray(spec["BP"], float)
    XC = np.asarray(spec.get("XC", np.zeros((len(W), len(W[0])))), float)
    seqs = spec["sequences"]
    brute = _brute_scores(seqs, W, BP, XC)
    memo = memoized_scores(seqs, W, BP, XC)
    d = float(np.max(np.abs(brute - memo))) if len(brute) else 0.0
    t_b = _timeit(lambda: _brute_scores(seqs, W, BP, XC))
    t_m = _timeit(lambda: memoized_scores(seqs, W, BP, XC))
    out = {
        "scores": memo.tolist(),
        "speedup": float(t_b / t_m) if t_m > 0 else 1.0,
        "max_abs_diff": d,
    }
    with open(args.output, "w") as f:
        json.dump(out, f)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    p1 = sub.add_parser("optimize")
    p1.add_argument("--spec", required=True)
    p1.add_argument("-o", "--output", required=True)
    p1.set_defaults(func=cmd_optimize)
    p2 = sub.add_parser("memo")
    p2.add_argument("--spec", required=True)
    p2.add_argument("-o", "--output", required=True)
    p2.set_defaults(func=cmd_memo)
    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()