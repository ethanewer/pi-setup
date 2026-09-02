#!/usr/bin/env python3
"""Deterministic train/val/test splitter for umber-vault.

Reads a labeled (or feature-only) CSV, sorts by id, shuffles the row indices
with a fixed documented seed, and writes train/val/test CSV files that are
byte-identical across invocations and pairwise-disjoint covering every id.
"""
import random
import sys

import pandas as pd

SPLIT_SEED = 20250531
TRAIN_FRAC = 0.7
VAL_FRAC = 0.15
NAME_ORDER = ["train", "val", "test"]


def split(df, seed=SPLIT_SEED):
    df = df.sort_values("id").reset_index(drop=True)
    n = len(df)
    indices = list(range(n))
    random.Random(seed).shuffle(indices)
    ntr = round(n * TRAIN_FRAC)
    nval = round(n * VAL_FRAC)
    nte = n - ntr - nval
    orders = {
        "train": indices[0:ntr],
        "val": indices[ntr:ntr + nval],
        "test": indices[ntr + nval:],
    }
    return {k: df.iloc[orders[k]].copy() for k in NAME_ORDER}, (ntr, nval, nte)


def main(argv=None):
    argv = list(sys.argv[1:]) if argv is None else argv
    if len(argv) != 2:
        sys.stderr.write("usage: split.py <input.csv> <out_prefix>\n")
        return 2
    src, prefix = argv
    df = pd.read_csv(src)
    parts, counts = split(df)
    for name in NAME_ORDER:
        parts[name].to_csv(f"{prefix}_{name}.csv", index=False)
    print(f"splits: train={counts[0]} val={counts[1]} test={counts[2]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())