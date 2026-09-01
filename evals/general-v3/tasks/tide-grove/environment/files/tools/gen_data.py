#!/usr/bin/env python3
"""Deterministic separable dataset generator for tide-grove.

Usage:
  python3 gen_data.py <out_csv> --rows N --dims D --seed S --wseed W [--margin M]

Each row: id,x0..x{D-1},label.  The label rule is a fixed (wseed-seeded) unit
vector w with threshold `margin`: label = 1 iff dot(w, x) > margin.  The rule
vector is drawn independently of the sampling seed, so train and holdout files
generated with the same --wseed follow the same rule.
"""
import argparse
import random


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_csv")
    ap.add_argument("--rows", type=int, required=True)
    ap.add_argument("--dims", type=int, required=True)
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--wseed", type=int, required=True)
    ap.add_argument("--margin", type=float, default=0.25)
    ap.add_argument("--id-prefix", default="r")
    args = ap.parse_args()

    rw = random.Random(args.wseed)
    norm = 0.0
    w = []
    for _ in range(args.dims):
        v = rw.gauss(0.0, 1.0)
        w.append(v)
        norm += v * v
    norm = norm ** 0.5
    w = [v / norm for v in w]

    rng = random.Random(args.seed)
    lines = ["id," + ",".join(f"x{i}" for i in range(args.dims)) + ",label"]
    for i in range(args.rows):
        x = [rng.gauss(0.0, 1.0) for _ in range(args.dims)]
        score = sum(a * b for a, b in zip(w, x))
        label = 1 if score > args.margin else 0
        feats = ",".join("%.6f" % v for v in x)
        lines.append(f"{args.id_prefix}{i:05d},{feats},{label}")

    with open(args.out_csv, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print("wrote", args.out_csv, args.rows, "rows", args.dims, "dims")


if __name__ == "__main__":
    main()
