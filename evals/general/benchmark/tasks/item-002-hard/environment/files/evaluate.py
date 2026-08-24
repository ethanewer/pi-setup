#!/usr/bin/env python3
"""Supplied evaluator for item-002 (hard).

Reads the agent's /app/edges2.json, /app/model2.json, /app/intervention2.json
and /app/score2.json, recomputes an independent ground truth from
/workspace/data/graph2_train.csv (and scores against graph2_test.csv), and
prints a PASS/FAIL report without revealing the expected numeric values.
Writes the verdict to /app/status.txt.
"""
import json

import numpy as np
import pandas as pd

TRAIN = "/workspace/data/graph2_train.csv"
TEST = "/workspace/data/graph2_test.csv"
ORDER = ["X", "Y", "Z", "W"]
TOL_MODEL = 0.3
TOL_EFFECT = 0.5
TOL_SCORE = 0.03


def load(path):
    return pd.read_csv(path)


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


def combined_rmse(train_df, test_df, parents, model, order):
    """Predicted-vs-actual combined RMSE for all non-root variables on test."""
    terms = []
    for node in order:
        if not parents[node]:
            continue
        m = model[node]
        pred = np.ones(len(test_df)) * m["intercept"]
        for p, cf in m["coefs"].items():
            pred = pred + cf * test_df[p].to_numpy()
        terms.append((pred - test_df[node].to_numpy()) ** 2)
    return float(np.sqrt(np.mean(np.concatenate(terms))))


def _structure_good(edges):
    if edges is None or set(edges.keys()) != set(ORDER):
        return False
    par = discover(load(TRAIN), ORDER)
    return all(
        sorted(str(x) for x in edges.get(n, [])) == sorted(str(x) for x in par.get(n, []))
        for n in ORDER
    )


def _model_good(model):
    if model is None or set(model.keys()) != set(ORDER):
        return False
    tr = load(TRAIN)
    par = discover(tr, ORDER)
    exp = fit(tr, par, ORDER)
    for node in ORDER:
        m = model.get(node, {})
        em = exp[node]
        if set(m.get("coefs", {}).keys()) != set(em["coefs"].keys()):
            return False
        if abs(float(m.get("intercept", 0.0)) - em["intercept"]) > TOL_MODEL:
            return False
        for p, cf in em["coefs"].items():
            if abs(float(m.get("coefs", {}).get(p, 1e9)) - cf) > TOL_MODEL:
                return False
    return True


def _intervention_good(inter, need_model):
    if inter is None or not need_model:
        return False
    tr = load(TRAIN)
    par = discover(tr, ORDER)
    mod = fit(tr, par, ORDER)
    exp = {c: do_effect(tr, par, mod, ORDER, c, "W") for c in ["X", "Y", "Z"]}
    eff_list = inter.get("effects", []) if isinstance(inter, dict) else []
    by_cause = {e.get("cause"): e for e in eff_list if isinstance(e, dict)}
    for c in ["X", "Y", "Z"]:
        e = by_cause.get(c)
        if e is None:
            return False
        if abs(float(e.get("effect", 1e9)) - exp[c]["effect"]) > TOL_EFFECT:
            return False
    return True


def _score_good(score):
    if score is None:
        return False
    tr = load(TRAIN)
    te = load(TEST)
    par = discover(tr, ORDER)
    mod = fit(tr, par, ORDER)
    expected = combined_rmse(tr, te, par, mod, ORDER)
    got = float(score.get("rmse", -1.0) if isinstance(score, dict) else -1.0)
    return abs(got - expected) <= TOL_SCORE


def main():
    ok = True

    def report(name, cond):
        nonlocal ok
        print((name + " PASS") if cond else (name + " FAIL"))
        ok = ok and cond

    edges = None
    try:
        edges = json.load(open("/app/edges2.json"))
    except Exception:
        edges = None
    sg = _structure_good(edges)
    report("structure", sg)

    model = None
    try:
        model = json.load(open("/app/model2.json"))
    except Exception:
        model = None
    mg = _model_good(model)
    report("model", mg)

    inter = None
    try:
        inter = json.load(open("/app/intervention2.json"))
    except Exception:
        inter = None
    ig = _intervention_good(inter, sg and mg)
    report("interventions", ig)

    score = None
    try:
        score = json.load(open("/app/score2.json"))
    except Exception:
        score = None
    scg = _score_good(score)
    report("score", scg)

    with open("/app/status.txt", "w") as f:
        f.write("PASS\n" if ok else "FAIL\n")
    print("PASS" if ok else "FAIL")


if __name__ == "__main__":
    main()