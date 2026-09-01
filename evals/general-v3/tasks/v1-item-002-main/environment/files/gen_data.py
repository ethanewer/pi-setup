"""Generate the synthetic observational dataset graph1.csv.

The data are drawn i.i.d. from a linear Gaussian Bayesian network (SEM):

    X, Y ~ N(0, 1)            (exogenous roots)
    Z     = 2.0 X + 1.5 Y + eps_Z
    W     = 1.0 + 0.5 Y + 2.5 Z + eps_W
    eps   ~ N(0, 0.1)

True DAG (arrows only go forward in the order X, Y, Z, W):
    parents(Z) = {X, Y}
    parents(W) = {Y, Z}
"""
import csv

import numpy as np

rng = np.random.default_rng(7)
n = 100000
X = rng.normal(0.0, 1.0, n)
Y = rng.normal(0.0, 1.0, n)
Z = 2.0 * X + 1.5 * Y + rng.normal(0.0, 0.1, n)
W = 1.0 + 0.5 * Y + 2.5 * Z + rng.normal(0.0, 0.1, n)

with open("/workspace/data/graph1.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["X", "Y", "Z", "W"])
    for i in range(n):
        w.writerow(["%.6f" % X[i], "%.6f" % Y[i], "%.6f" % Z[i], "%.6f" % W[i]])