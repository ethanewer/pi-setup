#!/bin/bash
set -euo pipefail

cat > /app/solve.py <<'PYEOF'
import json
import numpy as np
import pandas as pd

DATA = "/workspace/data/graph1.csv"
ORDER = ["X", "Y", "Z", "W"]
df = pd.read_csv(DATA)


def discover(df, order):
    parents = {}
    for node in order:
        cands = [p for p in order if order.index(p) < order.index(node)]
        if not cands:
            parents[node] = []
            continue
        Xm = np.column_stack([df[p].to_numpy() for p in cands])
        X1 = np.column_stack([np.ones(len(df)), Xm])
        beta, *_ = np.linalg.lstsq(X1, df[node].to_numpy(), rcond=None)
        parents[node] = [c for c, cf in zip(cands, beta[1:]) if abs(cf) > 0.3]
    return parents


def fit(df, parents, order):
    model = {}
    for node in order:
        par = parents[node]
        if not par:
            model[node] = {"intercept": float(df[node].mean()), "coefs": {}}
        else:
            X1 = np.column_stack([np.ones(len(df))] + [df[p].to_numpy() for p in par])
            beta, *_ = np.linalg.lstsq(X1, df[node].to_numpy(), rcond=None)
            model[node] = {"intercept": float(beta[0]),
                           "coefs": {p: float(c) for p, c in zip(par, beta[1:])}}
    return model


def do_effect(df, parents, model, order, cause, target):
    means = {c: float(df[c].mean()) for c in order}

    def ev(n, fixed):
        if n in fixed:
            return fixed[n]
        m = model[n]
        if not m["coefs"]:
            return means[n]
        val = m["intercept"]
        for p, cf in m["coefs"].items():
            val += cf * ev(p, fixed)
        return val

    low = ev(target, {})
    high = ev(target, {cause: means[cause] + 1.0})
    return {"cause": cause, "target": target, "effect": float(high - low),
            "E_low": float(low), "E_high": float(high)}


parents = discover(df, ORDER)
model = fit(df, parents, ORDER)
edges = {n: list(p) for n, p in parents.items()}
effects = [do_effect(df, parents, model, ORDER, c, "W") for c in ["X", "Y"]]

with open("/app/edges.json", "w") as f:
    json.dump(edges, f, indent=2)
with open("/app/model.json", "w") as f:
    json.dump(model, f, indent=2)
with open("/app/intervention.json", "w") as f:
    json.dump({"effects": effects}, f, indent=2)
PYEOF

python3 /app/solve.py
python3 /app/evaluate.py