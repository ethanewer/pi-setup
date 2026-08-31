#!/usr/bin/env python3
"""Build-time fixture generator for moss-loft.

Creates the visible labeled dataset, an evaluation split, and the trainer
config. Runs once during image build, then is deleted.
"""
import json
import math
import os
import random

SEED = 1234
INPUT_DIM = 8
NUM_CLASSES = 3
N_TRAIN = 900
N_EVAL = 240
NOISE_STD = 0.55


def make_split(rng, n, dim, classes, tag, start_id):
    # Gaussian class centers, well separated in `dim` dimensions.
    centers = [[rng.gauss(0.0, 2.0) for _ in range(dim)] for _ in range(classes)]
    rows = []
    for i in range(n):
        c = rng.randrange(classes)
        vec = [centers[c][j] + rng.gauss(0.0, NOISE_STD) for j in range(dim)]
        rows.append((start_id + i, vec, c))
    return rows


def write_csv(path, rows, dim):
    header = ["id"] + ["x%d" % j for j in range(dim)] + ["label"]
    lines = [",".join(header)]
    for rid, vec, label in rows:
        lines.append(",".join([str(rid)]
                              + ["%.6f" % v for v in vec]
                              + [str(label)]))
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def main():
    rng = random.Random(SEED)
    os.makedirs("/app/data", exist_ok=True)
    train = make_split(rng, N_TRAIN, INPUT_DIM, NUM_CLASSES, "train", 1)
    ev = make_split(rng, N_EVAL, INPUT_DIM, NUM_CLASSES, "eval", 500001)
    write_csv("/app/data/train.csv", train, INPUT_DIM)
    write_csv("/app/data/eval.csv", ev, INPUT_DIM)
    config = {
        "input_dim": INPUT_DIM,
        "hidden_units": 24,
        "num_classes": NUM_CLASSES,
        "epochs": 80,
        "learning_rate": 0.03,
        "batch_size": 32,
        "seed": 11,
    }
    with open("/app/config.json", "w", encoding="utf-8") as fh:
        json.dump(config, fh, indent=2, sort_keys=True)
    print("gen_data: wrote /app/data/train.csv (%d rows), "
          "/app/data/eval.csv (%d rows), /app/config.json"
          % (len(train), len(ev)))


if __name__ == "__main__":
    main()
