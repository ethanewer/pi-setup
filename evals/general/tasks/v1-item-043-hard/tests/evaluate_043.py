#!/usr/bin/env python3
"""Hidden evaluator for item-043-main / item-043-hard.

Runs nothing itself: it consumes the *regenerated* summaries the verifier
produced by re-running the agent's scripts, then scores them.

Usage: python3 /tests/evaluate_043.py <rstan.csv> <pystan.csv> <rstan_diag> <pystan_diag> [--hard]
Prints a JSON score dict; exit 0.
Scoring (soft): one point per gate (see tests/test.sh), plus cross-check.
"""
import json
import sys

import pandas as pd

CORE = ["rho", "alpha", "sigma", "b0", "tau", "b_g[1]", "b_g[2]", "b_g[3]"]


def load_summary(path):
    df = pd.read_csv(path)
    df["param"] = df["param"].astype(str).str.strip()
    return df.set_index("param")


def load_diag(path):
    return json.load(open(path))


def main():
    rs, ps, rd, pdg = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    hard = "--hard" in sys.argv
    R = load_summary(rs)
    P = load_summary(ps)
    rdg = load_diag(rd)
    pdg = load_diag(pdg)

    rhat_max = (1.10 if hard else 1.15)
    n_eff_min = (100 if hard else 50)

    def gates(df, diag):
        ok = True
        missing = [p for p in CORE if p not in df.index]
        if missing:
            return False
        sub = df.loc[CORE]
        if not (sub["rhat"].astype(float) <= rhat_max).all():
            ok = False
        if not (sub["n_eff"].astype(float) >= n_eff_min).all():
            ok = False
        if diag.get("divergent", 0) != 0:
            ok = False
        return ok

    r_ok, p_ok = gates(R, rdg), gates(P, pdg)

    # cross-check between the two samplers' posterior means
    cross_ok = False
    diffs = {}
    if r_ok and p_ok:
        ok = True
        for p in CORE:
            ra, pa = R.loc[p], P.loc[p]
            tol = max(0.05, 1.0 * (float(ra["sd"]) + float(pa["sd"])) / 2)
            d = abs(float(ra["mean"]) - float(pa["mean"]))
            diffs[p] = round(d, 5)
            if d > tol:
                ok = False
        cross_ok = ok

    score = {
        "rstan_gates": bool(r_ok),
        "pystan_gates": bool(p_ok),
        "cross_ok": bool(cross_ok),
        "diffs": diffs,
        "rhat_core": [float(R.loc[p, "rhat"]) for p in CORE],
    }
    print(json.dumps(score))
    return score


if __name__ == "__main__":
    s = main()
    sys.exit(0 if (s["rstan_gates"] and s["pystan_gates"] and s["cross_ok"]) else 1)