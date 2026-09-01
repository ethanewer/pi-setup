#!/usr/bin/env python3
"""Reference solver for juniper-mesh (pure stdlib).

Usage: python3 bnfit_ref.py <sensors.csv> <network.json> <outdir>
"""
import json, math, random, sys


def read_csv(path):
    with open(path) as f:
        lines = [l.strip() for l in f if l.strip()]
    header = lines[0].split(",")
    data = {c: [] for c in header}
    for l in lines[1:]:
        for c, v in zip(header, l.split(",")):
            data[c].append(float(v))
    return header, data


def pearson(a, b):
    n = len(a)
    ma = sum(a) / n; mb = sum(b) / n
    cov = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    va = math.sqrt(sum((x - ma) ** 2 for x in a))
    vb = math.sqrt(sum((y - mb) ** 2 for y in b))
    if va == 0.0 or vb == 0.0:
        return 0.0
    return cov / (va * vb)


def solve(A, b):
    """Gauss-Jordan with partial pivoting; A is k x k, b length k."""
    k = len(b)
    M = [row[:] + [b[i]] for i, row in enumerate(A)]
    for col in range(k):
        piv = max(range(col, k), key=lambda r: abs(M[r][col]))
        if abs(M[piv][col]) < 1e-12:
            raise ValueError("singular normal equations")
        M[col], M[piv] = M[piv], M[col]
        pv = M[col][col]
        M[col] = [x / pv for x in M[col]]
        for r in range(k):
            if r != col and M[r][col] != 0.0:
                f = M[r][col]
                M[r] = [x - f * y for x, y in zip(M[r], M[col])]
    return [M[i][k] for i in range(k)]


def ols(y, parents, data):
    """Multiple OLS of y on parents (+ intercept). Returns (intercept, {p: coef}, resid_std)."""
    n = len(y)
    cols = [[1.0] * n] + [data[p] for p in parents]
    k = len(cols)
    A = [[sum(cols[i][t] * cols[j][t] for t in range(n)) for j in range(k)] for i in range(k)]
    b = [sum(cols[i][t] * y[t] for t in range(n)) for i in range(k)]
    beta = solve(A, b)
    resid = []
    for t in range(n):
        pred = sum(cols[i][t] * beta[i] for i in range(k))
        resid.append(y[t] - pred)
    m = sum(resid) / n
    sd = math.sqrt(sum((r - m) ** 2 for r in resid) / n)
    return beta[0], {p: beta[i + 1] for i, p in enumerate(parents)}, sd


def main():
    csv_path, spec_path, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
    header, data = read_csv(csv_path)
    spec = json.load(open(spec_path))
    order = spec["order"]
    thr = float(spec["edge_threshold"])

    # structure discovery: edge p->c iff p precedes c in order and |corr| >= thr
    edges = []
    for ci, c in enumerate(order):
        for p in order[:ci]:
            if abs(pearson(data[p], data[c])) >= thr:
                edges.append((p, c))

    # parametric fit under the discovered DAG
    fit = {}
    for c in order:
        parents = [p for p in order if (p, c) in edges]
        y = data[c]
        if parents:
            b0, coefs, sd = ols(y, parents, data)
        else:
            m = sum(y) / len(y)
            b0, coefs = m, {}
            sd = math.sqrt(sum((v - m) ** 2 for v in y) / len(y))
        fit[c] = {"intercept": b0, "resid_std": sd, "coefficients": coefs}

    # ancestral sampling in the spec's order
    rng = random.Random(spec["seed"])
    rows = []
    for _ in range(spec["samples"]):
        val = {}
        for c in order:
            f = fit[c]
            v = f["intercept"] + sum(co * val[p] for p, co in f["coefficients"].items())
            v += rng.gauss(0.0, f["resid_std"])
            val[c] = v
        rows.append(val)

    with open(outdir + "/edges.csv", "w") as f:
        f.write("parent,child\n")
        for p, c in sorted(edges, key=lambda e: (order.index(e[1]), order.index(e[0]))):
            f.write("%s,%s\n" % (p, c))
    with open(outdir + "/fit.json", "w") as f:
        json.dump(fit, f, indent=1)
    with open(outdir + "/synthetic.csv", "w") as f:
        f.write(",".join(order) + "\n")
        for r in rows:
            f.write(",".join("%.6f" % r[c] for c in order) + "\n")
    print("BNFIT_OK")


if __name__ == "__main__":
    main()
