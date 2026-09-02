#!/usr/bin/env python3
"""Authoring/generation helper for the umber-larch ATE task.

Generates an observational-study case:
  <out>/obs.csv    observational data (treatment, outcome, covariates)
  <out>/dag.json   the DAG spec (nodes, edges, treatment/outcome columns)
and prints TRUE_ATE <value> on stdout (Monte-Carlo ground truth of the total
average treatment effect).  NOT shipped inside the task image.

DGP family (identical across layouts):
  - confounders cause treatment and outcome;
  - the outcome depends on continuous confounders nonlinearly (squares) and
    interacts with the treatment;
  - a mediator (caused only by treatment and confounders) also causes the
    outcome; a collider is caused by treatment and outcome; an instrument
    causes only the treatment; one pure-noise covariate is included.
Adjustment set (backdoor): parents(treatment) that still reach the outcome
when the treatment node and its edges are deleted.
"""
import argparse
import csv
import json
import math
import os

import numpy as np


def sigmoid(x):
    return 1.0 / (1.0 + np.exp(-x))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--n", type=int, default=9000)
    ap.add_argument("--layout", type=int, default=0, choices=[0, 1, 2])
    ap.add_argument("--a", type=float, default=1.1)      # direct treatment effect
    ap.add_argument("--b1", type=float, default=0.55)    # treat x conf1
    ap.add_argument("--b2", type=float, default=0.4)     # treat x conf2
    ap.add_argument("--sigma", type=float, default=1.0)  # outcome noise
    ap.add_argument("--m", type=float, default=0.9)      # mediator -> outcome
    ap.add_argument("--names", default="treat,outcome,conf1,conf2,instr,noise,med,coll")
    ap.add_argument("--root-name", default="root")
    args = ap.parse_args()

    rng = np.random.default_rng(args.seed)
    N = args.n
    T, Y, C1, C2, I, P, M, K, R = (args.names.split(",") + ["", ""])[:9]
    R = args.root_name

    if args.layout == 0:
        c1 = rng.normal(0.0, 1.0, N)
        c2 = (rng.random(N) < 0.4).astype(float)
        i = (rng.random(N) < 0.5).astype(float)
        t = (rng.random(N) < sigmoid(0.9 * i - 0.8 * c1 + 0.7 * c2 - 0.3)).astype(float)
        mt, mc = 0.8, 0.3
        med = mt * t + mc * c1 + rng.normal(0.0, 0.7, N)
        y = (args.a * t + args.b1 * t * c1 + args.b2 * t * c2 + args.m * med
             + 0.9 * c1 + 0.7 * c2 + 0.5 * c1 ** 2 + rng.normal(0.0, args.sigma, N))
        coll = 1.0 * t + 0.8 * y + rng.normal(0.0, 0.8, N)
        edges = [
            [I, T], [C1, T], [C2, T],
            [C1, Y], [C2, Y], [T, Y], [M, Y],
            [T, M], [C1, M],
            [T, K], [Y, K],
        ]
        nodes = [C1, C2, I, P, T, M, Y, K]
        cols = [C1, C2, I, P, T, M, K, Y]
        data = {C1: c1, C2: c2, I: i, P: rng.normal(0, 1, N),
                T: t, M: med, K: coll, Y: y}
    elif args.layout == 1:
        root = rng.normal(0.0, 1.0, N)
        c1 = 0.6 * root + rng.normal(0.0, 0.5, N)
        c2 = (rng.random(N) < 0.45).astype(float)
        i = rng.normal(0.0, 1.0, N)
        t = (rng.random(N) < sigmoid(0.7 * i + 0.9 * c1 + 0.5 * c2 - 0.4)).astype(float)
        mt, mc = 0.9, 0.25
        med = mt * t + mc * c1 + rng.normal(0.0, 0.6, N)
        y = (args.a * t + args.b1 * t * c1 + args.b2 * t * c2 + args.m * med
             + 0.8 * c1 + 0.6 * c2 + 0.4 * c1 ** 2 + rng.normal(0.0, args.sigma, N))
        coll = 0.9 * t + 0.7 * y + rng.normal(0.0, 0.9, N)
        edges = [
            [R, C1], [I, T], [C1, T], [C2, T],
            [C1, Y], [C2, Y], [T, Y], [M, Y],
            [T, M], [C1, M],
            [T, K], [Y, K],
        ]
        nodes = [R, C1, C2, I, P, T, M, Y, K]
        cols = [R, C1, C2, I, P, T, M, K, Y]
        data = {R: root, C1: c1, C2: c2, I: i, P: rng.normal(0, 1, N),
                T: t, M: med, K: coll, Y: y}
    else:
        c1 = (rng.random(N) < 0.35).astype(float)
        c2 = rng.normal(1.0, 1.2, N)
        i = (rng.random(N) < 0.6).astype(float)
        t = (rng.random(N) < sigmoid(1.0 * i - 0.7 * c1 + 0.5 * c2 - 0.2)).astype(float)
        mt = 0.7
        med = mt * t + 0.25 * c1 + 0.2 * c2 + rng.normal(0.0, 0.7, N)
        y = (args.a * t + args.b1 * t * c1 + args.b2 * t * c2 + args.m * med
             + 0.7 * c1 + 0.8 * c2 + 0.45 * c2 ** 2 + rng.normal(0.0, args.sigma, N))
        coll = 1.1 * t + 0.6 * y + rng.normal(0.0, 0.8, N)
        edges = [
            [I, T], [C1, T], [C2, T],
            [C1, Y], [C2, Y], [T, Y], [M, Y],
            [T, M], [C1, M], [C2, M],
            [T, K], [Y, K],
        ]
        nodes = [C1, C2, I, P, T, M, Y, K]
        cols = [C1, C2, I, P, T, M, K, Y]
        data = {C1: c1, C2: c2, I: i, P: rng.normal(0, 1, N),
                T: t, M: med, K: coll, Y: y}

    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "obs.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(cols)
        for r in range(N):
            w.writerow([data[c][r] for c in cols])
    dag = {
        "nodes": nodes,
        "edges": edges,
        "treatment_column": T,
        "outcome_column": Y,
    }
    with open(os.path.join(args.out, "dag.json"), "w") as fh:
        json.dump(dag, fh, indent=2)

    # ---- Monte-Carlo ground truth of the total ATE -------------------------
    n_mc = 1_000_000
    rr = np.random.default_rng(args.seed + 999_983)

    def draw(t_forced):
        if args.layout == 0:
            c1m = rr.normal(0.0, 1.0, n_mc)
            c2m = (rr.random(n_mc) < 0.4).astype(float)
            imm = (rr.random(n_mc) < 0.5).astype(float)
            medm = mt * t_forced + mc * c1m + rr.normal(0.0, 0.7, n_mc)
            return (args.a * t_forced + args.b1 * t_forced * c1m
                    + args.b2 * t_forced * c2m + args.m * medm
                    + 0.9 * c1m + 0.7 * c2m + 0.5 * c1m ** 2
                    + rr.normal(0.0, args.sigma, n_mc))
        if args.layout == 1:
            rootm = rr.normal(0.0, 1.0, n_mc)
            c1m = 0.6 * rootm + rr.normal(0.0, 0.5, n_mc)
            c2m = (rr.random(n_mc) < 0.45).astype(float)
            imm = rr.normal(0.0, 1.0, n_mc)
            medm = mt * t_forced + mc * c1m + rr.normal(0.0, 0.6, n_mc)
            return (args.a * t_forced + args.b1 * t_forced * c1m
                    + args.b2 * t_forced * c2m + args.m * medm
                    + 0.8 * c1m + 0.6 * c2m + 0.4 * c1m ** 2
                    + rr.normal(0.0, args.sigma, n_mc))
        c1m = (rr.random(n_mc) < 0.35).astype(float)
        c2m = rr.normal(1.0, 1.2, n_mc)
        imm = (rr.random(n_mc) < 0.6).astype(float)
        medm = mt * t_forced + 0.25 * c1m + 0.2 * c2m + rr.normal(0.0, 0.7, n_mc)
        return (args.a * t_forced + args.b1 * t_forced * c1m
                + args.b2 * t_forced * c2m + args.m * medm
                + 0.7 * c1m + 0.8 * c2m + 0.45 * c2m ** 2
                + rr.normal(0.0, args.sigma, n_mc))

    ate = float(np.mean(draw(1.0) - draw(0.0)))
    print("TRUE_ATE %.6f" % ate)


if __name__ == "__main__":
    main()
