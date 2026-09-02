"""Build-time generator (removed from the image after use).

Deterministically creates:
  * /app/model.npz -- frozen anomaly model Linear(32->16), ReLU,
    Linear(16->1) weights (float64, seeded PRNG, analytic -- no training).
  * /app/data/traces_visible.csv -- 6 traces, 75,000 patch rows total; every
    trace has its own latent mean shift so per-trace anomaly rates differ.
"""
import os

import numpy as np

F = 32


def main():
    rng = np.random.default_rng(915)
    W1 = rng.normal(0, 0.5, (16, F))
    b1 = rng.normal(0, 0.1, 16)
    W2 = rng.normal(0, 1.0, (1, 16))
    b2 = rng.normal(0, 0.1, 1)
    os.makedirs("/app/data", exist_ok=True)
    np.savez("/app/model.npz", W1=W1, b1=b1, W2=W2, b2=b2)

    ids = ["t-204", "t-117", "t-331", "t-089", "t-256", "t-402"]
    sizes = [20000, 15000, 12000, 9000, 11000, 8000]
    shifts = np.random.default_rng(777).uniform(-1.3, 1.3, len(ids))
    drng = np.random.default_rng(3131)
    with open("/app/data/traces_visible.csv", "w") as fh:
        fh.write("trace_id," + ",".join(f"x{i}" for i in range(F)) + "\n")
        for tid, n, sh in zip(ids, sizes, shifts):
            X = drng.normal(0, 1.0, (n, F)) + sh
            for row in X:
                fh.write(tid + "," + ",".join(f"{v:.6f}" for v in row) + "\n")


if __name__ == "__main__":
    main()
