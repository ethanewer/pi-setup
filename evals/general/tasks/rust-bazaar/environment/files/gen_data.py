"""Build-time generator (removed from the image after use).

Deterministically creates:
  * /app/base_snapshot.pt  -- pretrained Linear(24->48), ReLU, Linear(48->3)
    grader whose weights are constructed analytically (no training), so the
    build is fast and fully deterministic.
  * /app/data/line_fold.csv -- the visible adaptation fold, labeled by an
    independent grading rule (a different hidden-space prototype set).
"""
import os

import numpy as np
import torch

F, H, C = 24, 48, 3


def make_protos(seed):
    return np.random.default_rng(seed).normal(0, 1.0, (C, H))


def logits(X, W1, b1, protos):
    h = np.maximum(X @ W1.T + b1, 0.0)
    return h @ protos.T


def main():
    os.makedirs("/app/data", exist_ok=True)

    # ---- base grader: analytic weights, no training -----------------------
    rng = np.random.default_rng(4242)
    W1 = rng.normal(0, 0.5, (H, F)).astype(np.float32)
    b1 = rng.normal(0, 0.1, H).astype(np.float32)
    protos = make_protos(909).astype(np.float32)
    sd = {
        "l1.weight": torch.from_numpy(W1),
        "l1.bias": torch.from_numpy(b1),
        "l2.weight": torch.from_numpy(protos.copy()),
        "l2.bias": torch.zeros(C),
    }
    torch.save(sd, "/app/base_snapshot.pt")

    # ---- visible fold: independent rule, balanced across the 3 grades -----
    proto_seed, ds_seed, per_class = 777, 555, 200
    rng = np.random.default_rng(ds_seed)
    mu = rng.normal(0, 1.4, (C, F)).astype(np.float32)
    pool = (mu[:, None, :]
            + rng.normal(0, 0.9, (C, per_class * 10, F))).reshape(-1, F)
    pool = pool.astype(np.float32)
    protos_f = None
    y_pool = None
    for ps in range(proto_seed, proto_seed + 200):
        cand = make_protos(ps).astype(np.float32)
        counts = logits(pool, W1, b1, cand).argmax(1)
        if np.bincount(counts, minlength=3).min() >= per_class // 2:
            protos_f, y_pool = cand, counts
            break
    assert protos_f is not None
    picked = [np.where(y_pool == c)[0][:per_class] for c in range(C)]
    idx = np.concatenate(picked)
    idx = idx[rng.permutation(len(idx))]
    X, y = pool[idx], y_pool[idx]
    with open("/app/data/line_fold.csv", "w") as fh:
        fh.write("id," + ",".join(f"x{i}" for i in range(F)) + ",label\n")
        for i in range(len(X)):
            fh.write(f"{i + 1}," + ",".join(f"{v:.6f}" for v in X[i])
                     + f",{y[i]}\n")


if __name__ == "__main__":
    main()
