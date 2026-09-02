#!/usr/bin/env python3
"""Supplied evaluator for item-002 (medium).

Reads the agent's /app/edges.json, /app/model.json and /app/intervention.json,
recomputes an independent ground truth from /workspace/data/graph1.csv, and
prints a PASS/FAIL report without revealing the expected numeric values.
Writes the verdict to /app/status.txt.
"""
import json

import numpy as np
import pandas as pd

DATA = "/workspace/data/graph1.csv"
ORDER = ["X", "Y", "Z", "W"]
TOL_MODEL = 0.3
TOL_EFFECT = 0.5


def load():
    return pd.read_csv(DATA)


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
            model[node] = {
                "intercept": float(beta[0]),
                "coefs": {p: float(c) for p, c in zip(par, beta[1:])},
            }
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
    return {
        "cause": cause, "target": target,
        "effect": float(high - low), "E_low": float(low), "E_high": float(high),
    }


def _structure_good(edges):
    if edges is None or set(edges.keys()) != set(ORDER):
        return False
    par = discover(load(), ORDER)
    return all(
        sorted(str(x) for x in edges.get(nm, []))
        == sorted(str(x) for x in par.get(nm, []))
        for nm in ORDER
    )


def _model_good(model):
    if model is None or set(model.keys()) != set(ORDER):
        return False
    par = discover(load(), ORDER)
    exp = fit(load(), par, ORDER)
    for node in ORDER:
        m = model.get(node, {})
        em = exp[node]
        if set(m.get("coefs", {}).keys()) != set(em["coefs"].keys()):
            return False
        if abs(float(m.get("intercept", 0.0)) - em["intercept"]) > TOL_MODEL:
            return False
        for p, cf in em["coefs"].items():
            if abs(float(m["coefs"][p]) - cf) > TOL_MODEL:
                return False
    return True


def _intervention_good(inter, need_model):
    if inter is None or need_model is False:
        return False
    df = load()
    par = discover(df, ORDER)
    mod = fit(df, par, ORDER)
    exp = {c: do_effect(df, par, mod, ORDER, c, "W") for c in ["X", "Y"]}
    eff_list = inter.get("effects", []) if isinstance(inter, dict) else []
    by_cause = {e.get("cause"): e for e in eff_list if isinstance(e, dict)}
    for c in ["X", "Y"]:
        e = by_cause.get(c)
        if e is None:
            return False
        if abs(float(e.get("effect", 1e9)) - exp[c]["effect"]) > TOL_EFFECT:
            return False
        if abs(float(e.get("E_low", 1e9)) - exp[c]["E_low"]) > 1.0:
            return False
        if abs(float(e.get("E_high", 1e9)) - exp[c]["E_high"]) > 1.0:
            return False
    return True


def main():
    ok = True

    def report(name, cond):
        nonlocal ok
        print((name + " PASS") if cond else (name + " FAIL"))
        ok = ok and cond

    edges = None
    try:
        with open("/app/edges.json") as f:
            edges = json.load(f)
    except Exception:
        edges = None
    sg = _structure_good(edges)
    report("structure", sg)

    model = None
    try:
        with open("/app/model.json") as f:
            model = json.load(f)
    except Exception:
        model = None
    mg = _model_good(model)
    report("model", mg)

    inter = None
    try:
        with open("/app/intervention.json") as f:
            inter = json.load(f)
    except Exception:
        inter = None
    ig = _intervention_good(inter, sg and mg)
    report("intervention", ig)

    with open("/app/status.txt", "w") as f:
        f.write("PASS\n" if ok else "FAIL\n")
    print("PASS" if ok else "FAIL")


if __name__ == "__main__":
    main()