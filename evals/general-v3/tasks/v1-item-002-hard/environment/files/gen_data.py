"""Generate the synthetic observational datasets for item-002 (hard).

Two independent draws from the same linear Gaussian Bayesian network:

    X ~ N(0,1), Y ~ N(0,1)              (exogenous roots; Y is a full distractor)
    Z     = 0.8 X + eps_Z
    W     = 1.1 X + 0.7 Z + eps_W
    eps   ~ N(0, 0.15)

True DAG (arrows only go forward in the order X, Y, Z, W):
    parents(Z) = {X}
    parents(W) = {X, Z}
    Y has no outgoing edges — it must be recognized as independent.

graph2_train.csv (150000 rows) is the estimation set; graph2_test.csv
(120000 rows) is a held-out set used only to score model fit.
"""
import csv

import numpy as np


def gen(n, seed):
    rng = np.random.default_rng(seed)
    X = rng.normal(0.0, 1.0, n)
    Y = rng.normal(0.0, 1.0, n)
    Z = 0.8 * X + rng.normal(0.0, 0.15, n)
    W = 1.1 * X + 0.7 * Z + rng.normal(0.0, 0.15, n)
    return X, Y, Z, W


def write_csv(path, cols):
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["X", "Y", "Z", "W"])
        for i in range(len(cols[0])):
            w.writerow(["%.6f" % cols[0][i], "%.6f" % cols[1][i],
                        "%.6f" % cols[2][i], "%.6f" % cols[3][i]])


write_csv("/workspace/data/graph2_train.csv", gen(150000, 11))
write_csv("/workspace/data/graph2_test.csv", gen(120000, 99))