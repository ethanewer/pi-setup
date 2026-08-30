"""Build-time fixture generator for vine-forge.

Creates:
  /app/scorer.npz        fixed patch scorer: W1 (16x32), b1 (16,), W2 (1x16), b2 (1,)
  /app/data/big_bag.csv  visible bag file: 8 contiguous bags x 15000 patches,
                         header bag_id,f0..f31

Deterministic: fixed seeds.
"""
import os

import numpy as np
import pandas as pd

DIM, HID = 32, 16


def main():
    os.makedirs("/app/data", exist_ok=True)

    rng = np.random.default_rng(20260831)
    W1 = rng.standard_normal((HID, DIM)) / np.sqrt(DIM)
    b1 = rng.standard_normal(HID) * 0.1
    W2 = rng.standard_normal((1, HID)) / np.sqrt(HID)
    b2 = rng.standard_normal(1) * 0.05
    np.savez("/app/scorer.npz", W1=W1, b1=b1, W2=W2, b2=b2)

    n_bags, per_bag = 8, 15000
    rows = []
    for b in range(n_bags):
        X = rng.uniform(-1.0, 1.0, (per_bag, DIM))
        df = pd.DataFrame(X, columns=[f"f{d}" for d in range(DIM)])
        df.insert(0, "bag_id", b)
        rows.append(df)
    pd.concat(rows, ignore_index=True).to_csv("/app/data/big_bag.csv", index=False)
    print("scorer.npz + big_bag.csv written (%d patches)" % (n_bags * per_bag))


if __name__ == "__main__":
    main()
