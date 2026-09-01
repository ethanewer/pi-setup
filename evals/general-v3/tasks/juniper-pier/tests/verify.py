#!/usr/bin/env python3
"""Verifier for juniper-pier (executes-deliverable).

Executes the deliverable's posterior sampler and penalty selector on the default
data and on the hidden datasets under tests/hidden, then cross-checks:

  (1) the rstan->pystan sampling hyperparameter map is faithful (warmup vs total
      semantics: num_samples = rstan iter - rstan warmup),
  (2) posterior means recover the data-generating (alpha,beta) on the default and
      hidden calibration data, and the seeded sampler is deterministic,
  (3) the chosen lasso penalty is corroborated by BOTH cross-validation and a
      corrected (AICc) criterion in the agent's run AND an independent
      re-derivation, with a distinct ridge variant.

Writes 0/1 to /logs/verifier/reward.txt.
"""
import json
import math
import os
import subprocess
import sys

import numpy as np
import pandas as pd

LOGDIR = "/logs/verifier"


def _num(v):
    try:
        return int(v)
    except ValueError:
        pass
    try:
        return float(v)
    except ValueError:
        return v


def parse_rstan(path):
    cfg = {}
    control = {}
    cur = None
    with open(path) as fh:
        for raw in fh:
            st = raw.strip()
            if not st or st.startswith("#"):
                continue
            if st == "control:":
                cur = control
                continue
            if ":" in st and not st.startswith("-"):
                k, v = st.split(":", 1)
                k = k.strip()
                v = _num(v.split("#")[0].strip())
                if cur is None:
                    cfg[k] = v
                else:
                    cur[k] = v
    cfg["control"] = control
    return cfg


def aicc(n, rss, k):
    if n - k - 1 <= 0 or rss <= 0:
        return float("inf")
    return float(n * math.log(rss / n) + 2 * k + 2 * k * (k + 1) / (n - k - 1))


def independent_penalty(data_path):
    from sklearn.linear_model import Lasso, LassoCV, RidgeCV
    from sklearn.preprocessing import StandardScaler
    df = pd.read_csv(data_path)
    Xraw = df.drop(columns=["stretch"])
    y = df["stretch"].astype(float).to_numpy()
    sc = StandardScaler().fit(Xraw)
    X = sc.transform(Xraw)
    cv = LassoCV(alphas=np.logspace(-3, 0.5, 60), cv=5, random_state=0,
                 max_iter=80000).fit(X, y)
    lam_cv = float(cv.alpha_)
    grid = np.logspace(-4, 1.0, 200)
    v = []
    for lam in grid:
        m = Lasso(alpha=lam, max_iter=80000).fit(X, y)
        rss = float(np.sum((y - m.predict(X)) ** 2))
        k = int(np.sum(np.abs(m.coef_) > 1e-8))
        v.append(aicc(X.shape[0], rss, k))
    v = np.asarray(v)
    lam_aic = float(grid[int(np.argmin(v))])
    lam_ridge = float(RidgeCV(alphas=np.logspace(-4, 0.5, 60)).fit(X, y).alpha_)
    return lam_cv, lam_aic, lam_ridge


def run_py(args):
    r = subprocess.run(["python3", "/app/posterior.py"] + args,
                       capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr)


def write_rew(n):
    with open(os.path.join(LOGDIR, "reward.txt"), "w") as fh:
        fh.write(str(int(n)))


def checks():
    ref = parse_rstan("/app/reference_rstan.yaml")
    total = int(ref["iter"])
    warmup = int(ref["warmup"])
    chains = int(ref["chains"])
    seed = int(ref["seed"])

    def bad(why):
        print("FAIL:", why)
        write_rew(0)
        sys.exit(1)

    # ---- (1) faithful rstan->pystan hyperparameter map ----
    if not os.path.exists("/app/hparams.json"):
        bad("missing /app/hparams.json")
    hp = json.load(open("/app/hparams.json"))
    faithful = (
        hp.get("num_chains") == chains
        and hp.get("num_warmup") == warmup
        and hp.get("num_samples") == total - warmup
        and hp.get("seed") == seed
        and hp.get("num_samples", 0) != warmup
        and hp.get("num_samples", 0) > 0
    )
    if not faithful:
        bad("hparams.json not a faithful rstan->pystan map: %r" % hp)

    # ---- (2) posterior means output ----
    if not os.path.exists("/app/posterior_means.json"):
        bad("missing /app/posterior_means.json")
    pm = json.load(open("/app/posterior_means.json"))
    alpha, beta = pm.get("alpha"), pm.get("beta")
    if not (isinstance(alpha, float) and isinstance(beta, float)):
        bad("posterior_means.json alpha/beta not floats")
    if not (abs(alpha - (-0.4)) < 0.25 and abs(beta - 1.5) < 0.25):
        bad("default posterior means out of range: alpha=%r beta=%r" % (alpha, beta))
    if not (pm.get("num_warmup") == warmup
            and pm.get("num_samples") == total - warmup
            and pm.get("num_chains") == chains
            and pm.get("seed") == seed):
        bad("posterior_means.json reports wrong sampling config")
    if pm.get("effective_total_draws") != chains * (total - warmup):
        bad("effective_total_draws mismatch in posterior_means.json")

    if not os.path.exists("/app/posterior.csv"):
        bad("missing /app/posterior.csv")
    dc = pd.read_csv("/app/posterior.csv")
    if len(dc) != chains * (total - warmup):
        bad("posterior.csv row count != effective draws (got %d)" % len(dc))
    for col in ("alpha", "beta", "sigma"):
        if col not in dc.columns or dc[col].isna().any():
            bad("posterior.csv missing/NaN column %r" % col)
    if abs(float(dc["alpha"].mean()) - pm["alpha"]) > 1e-3 or \
       abs(float(dc["beta"].mean()) - pm["beta"]) > 1e-3:
        bad("posterior.csv means disagree with posterior_means.json")

    # ---- (3) determinism: re-run the sampler, expect stable draws ----
    rc, out = run_py(["posterior", "--data=/app/data/calib.csv",
                      "--out=/tmp/det.json", "--draws=/tmp/det.csv"])
    if rc != 0:
        bad("determinism re-run failed rc=%d %s" % (rc, out[-300:]))
    det = json.load(open("/tmp/det.json"))
    if abs(det["alpha"] - pm["alpha"]) > 1e-3 or abs(det["beta"] - pm["beta"]) > 1e-3:
        bad("posterior sampler not deterministic: %r vs %r" % (det, pm))

    # ---- (4) penalty selection on the visible data ----
    if not os.path.exists("/app/penalty.txt"):
        bad("missing /app/penalty.txt")
    pt = float(open("/app/penalty.txt").read().split()[0].strip())
    if not (pt > 0):
        bad("penalty.txt not a positive number")
    if not os.path.exists("/app/model_comparison.csv"):
        bad("missing /app/model_comparison.csv")
    mc = pd.read_csv("/app/model_comparison.csv")
    variants = list(mc["variant"])
    if not {"lasso_cv", "lasso_aicc", "ridge_cv"} <= set(variants):
        bad("model_comparison.csv missing named variants: %s" % sorted(set(variants)))
    vals = {r.variant: float(r.penalty) for r in mc.itertuples()}
    if abs(vals["lasso_cv"] - vals["lasso_aicc"]) < 1e-9:
        bad("lasso_cv / lasso_aicc penalties must not be identical")
    if abs(vals["ridge_cv"] - pt) < 1e-6:
        bad("ridge_cv penalty must differ from the reported lasso penalty")

    lam_cv, lam_aic, _ridge = independent_penalty("/app/data/features.csv")
    lo, hi = min(lam_cv, lam_aic), max(lam_cv, lam_aic)
    if lo <= 0 or (hi / lo) > 10.0:
        bad("independent CV/AICc penalties do not corroborate on visible data "
            "(cv=%g aic=%g)" % (lam_cv, lam_aic))
    if not (lo * 0.6 <= pt <= hi * 1.6):
        bad("penalty.txt not within corroboration band on visible data (pt=%g band=[%g,%g])"
            % (pt, lo * 0.6, hi * 1.6))

    rc, out = run_py(["penalty", "--data=/app/data/features.csv",
                      "--out=/tmp/pt.txt", "--model-cmp=/tmp/pmc.csv"])
    if rc != 0:
        bad("penalty re-run failed (%s)" % out[-200:])
    re_pt = float(open("/tmp/pt.txt").read().strip())
    if abs(re_pt - pt) > 1e-6:
        bad("penalty re-run disagrees with penalty.txt (%g vs %g)" % (re_pt, pt))

    # ---- (5) hidden generalization ----
    H = "/tests/hidden"
    cp_data = os.path.join(H, "case_posterior", "data.csv")
    cp_exp = json.load(open(os.path.join(H, "case_posterior", "expected.json")))
    rc, out = run_py(["posterior", "--data=" + cp_data,
                      "--out=/tmp/cp.json", "--draws=/tmp/cp.csv"])
    if rc != 0:
        bad("hidden posterior re-run failed: %s" % out[-200:])
    cp = json.load(open("/tmp/cp.json"))
    if abs(cp["alpha"] - cp_exp["alpha"]) > cp_exp["tol"] or \
       abs(cp["beta"] - cp_exp["beta"]) > cp_exp["tol"]:
        bad("hidden posterior means off target: %r want %r" % (cp, cp_exp))
    if not (cp.get("num_warmup") == warmup
            and cp.get("num_samples") == total - warmup
            and cp.get("num_chains") == chains):
        bad("hidden posterior did not use the faithful sampling config")

    pen_data = os.path.join(H, "case_penalty", "data.csv")
    rc, out = run_py(["penalty", "--data=" + pen_data,
                      "--out=/tmp/pen.txt", "--model-cmp=/tmp/pen_cmp.csv"])
    if rc != 0:
        bad("hidden penalty re-run failed: %s" % out[-200:])
    hpt = float(open("/tmp/pen.txt").read().strip())
    hcv, haic, _hr = independent_penalty(pen_data)
    hlo, hhi = min(hcv, haic), max(hcv, haic)
    if hlo <= 0 or (hhi / hlo) > 10.0:
        bad("hidden penalties do not corroborate (ratio %g)" % (hhi / hlo))
    if not (hlo * 0.6 <= hpt <= hhi * 1.6):
        bad("hidden penalty not in corroboration band (got %g band [%g,%g])"
            % (hpt, hlo * 0.6, hhi * 1.6))

    # All checks passed
    write_rew(1)
    print("PASS juniper-pier")


if __name__ == "__main__":
    try:
        os.makedirs(LOGDIR, exist_ok=True)
        write_rew(0)
        checks()
    except SystemExit:
        raise
    except Exception:
        import traceback
        traceback.print_exc()
        write_rew(0)
        sys.exit(1)