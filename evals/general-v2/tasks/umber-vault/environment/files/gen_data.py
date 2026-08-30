#!/usr/bin/env python3
"""Build-time fixture generator for umber-vault.

Writes the provided (already-labeled / feature-only) CSV fixtures that the agent
trains and serves from. All fixtures are produced from fixed seeds so every
build is byte-identical. The concrete rule that maps synthetic features to
labels lives only here and is removed from the image after generation, so the
agent must genuinely train a model rather than guess the mapping.
"""
import os

import numpy as np
import pandas as pd

F = 48
FEATS = [f"x{i}" for i in range(F)]
OUT = "/app/data"
os.makedirs(OUT, exist_ok=True)


def gen_classifier(rng, n, thresh=0.6):
    """Return (feats, labels): n linearly-separable rows w.r.t. a fresh weight
    vector drawn from ``rng``. Rows whose signed distance to the decision plane
    is within ``thresh`` are resampled so a small linear net can fit to ~100%."""
    w = rng.normal(size=F)
    b = float(rng.uniform(-0.3, 0.3))
    feats, labs = [], []
    while len(labs) < n:
        rows = rng.uniform(-1.0, 1.0, (n * 2, F))
        score = rows @ w + b
        ok = np.abs(score) > thresh
        feats.append(rows[ok])
        labs.append(score[ok] > 0)
    feats = np.concatenate(feats)[:n]
    labs = np.concatenate(labs)[:n].astype(np.int8)
    return feats, labs


def frame(feats, labels, start_id=0):
    df = pd.DataFrame(feats, columns=FEATS)
    df.insert(0, "id", np.arange(start_id, start_id + len(feats), dtype=np.int64))
    if labels is not None:
        df["label"] = labels
    return df.round(6)


def main():
    # 1) training dataset: 1200 separable labeled rows.
    feats, labs = gen_classifier(np.random.default_rng(2001), 1200)
    frame(feats, labs).to_csv(os.path.join(OUT, "dataset.csv"), index=False)

    # 2) unlabeled rows to predict at inference time -> /app/pred_labels.txt.
    feats = np.random.default_rng(2002).uniform(-1.0, 1.0, (200, F))
    frame(feats, None, start_id=5000).to_csv(os.path.join(OUT, "unlabeled.csv"),
                                             index=False)

    # 3) demo fold for a dry-run of the fine-tuning script. The fold is drawn
    #    from an INDEPENDENT decision hyperplane (different seed + fresh weights),
    #    so a good fine-tune really has to adapt the base weights to the fold.
    feats, labs = gen_classifier(np.random.default_rng(2004), 400)
    frame(feats, labs, start_id=9000).to_csv(os.path.join(OUT, "finetune_fold.csv"),
                                             index=False)

    # 4) demo big bag for the streaming scorer -> /app/large_bag_scores.txt.
    rng = np.random.default_rng(2005)
    bag_sizes = [8000, 12000, 7000, 15000, 9000, 9000]  # total 60,000 patches
    rows = []
    for bag_id, sz in enumerate(bag_sizes):
        feats = rng.uniform(-1.0, 1.0, (sz, F))
        d = pd.DataFrame(feats, columns=FEATS)
        d.insert(0, "bag_id", np.full(sz, bag_id, dtype=np.int64))
        rows.append(d.round(6))
    pd.concat(rows, ignore_index=True).to_csv(os.path.join(OUT, "big_bag.csv"),
                                              index=False)

    for name in ("dataset.csv", "unlabeled.csv", "finetune_fold.csv", "big_bag.csv"):
        p = os.path.join(OUT, name)
        print(f"{name}: {os.path.getsize(p)} bytes")


if __name__ == "__main__":
    main()