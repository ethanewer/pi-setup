#!/usr/bin/env bash
# Oracle for juniper-pier: writes the real deliverable /app/posterior.py (the
# PyStan posterior-sampling + penalty-selection workflow), then RUNS it to
# produce hparams.json, posterior_means.json, posterior.csv, penalty.txt and
# model_comparison.csv. Never reads /tests.
set -eu
cd /app

cat > /app/posterior.py <<'JUPY'
#!/usr/bin/env python3
"""Juniper Pier — Bayesian calibration workflow (PyStan + penalty selection).

Runnable deliverable for the foundry calibration task.

Default invocation (produces every deliverable from the visible datasets):
    python3 /app/posterior.py
      posterior on /app/data/calib.csv    -> /app/posterior_means.json, /app/posterior.csv
      penalty   on /app/data/features.csv -> /app/penalty.txt, /app/model_comparison.csv
      faithful rstan->pystan map          -> /app/hparams.json

Re-runnable on new inputs (used by the verifier on hidden cases):
    python3 /app/posterior.py posterior --data=<csv> [--out=<json>] [--draws=<csv>]
    python3 /app/posterior.py penalty   --data=<csv> [--out=<txt>]  [--model-cmp=<csv>]
"""
import argparse
import json
import math
import sys
import warnings

import numpy as np
import pandas as pd

warnings.simplefilter("ignore")

REF = "/app/reference_rstan.yaml"
DATA_POST = "/app/data/calib.csv"
DATA_PEN = "/app/data/features.csv"


def parse_rstan(path):
    """Minimal reader for the fixed reference_rstan.yaml layout."""
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


def _num(v):
    try:
        return int(v)
    except ValueError:
        pass
    try:
        return float(v)
    except ValueError:
        return v


def translate_hyperparams(rstan):
    """Faithfully map rstan sampling hyperparameters to PyStan semantics.

    rstan `iter` is the TOTAL per-chain iteration count and already includes the
    warmup phase, so PyStan's `num_samples` (sampling phase only) equals
    iter - warmup. Getting warmup vs total semantics wrong is the classic failure
    mode that yields under-converged posterior means.
    """
    total = int(rstan["iter"])
    warmup = int(rstan["warmup"])
    chains = int(rstan["chains"])
    thin = int(rstan.get("thin", 1))
    num_samples = total - warmup
    if num_samples <= 0:
        raise ValueError("num_samples must be positive (iter=%r warmup=%r)"
                         % (total, warmup))
    return {
        "source": "reference_rstan.yaml",
        "num_chains": chains,
        "num_warmup": warmup,
        "num_samples": num_samples,
        "thin": thin,
        "seed": int(rstan["seed"]),
        "adapt_delta": rstan["control"].get("adapt_delta"),
        "max_treedepth": rstan["control"].get("max_treedepth"),
        "stepsize": rstan["control"].get("stepsize"),
        "notes": ("num_samples = rstan iter - rstan warmup; PyStan's num_samples "
                  "is the sampling (post-warmup) phase only"),
    }


def run_posterior(data_path, out_json, draws_csv):
    import stan
    rstan = parse_rstan(REF)
    hp = translate_hyperparams(rstan)
    df = pd.read_csv(data_path)
    x = df["tension"].astype(float).to_numpy()
    y = df["elongation"].astype(float).to_numpy()
    n = int(len(x))
    code = open("/app/model.stan").read()
    posterior = stan.build(code, data=dict(n=n, x=x, y=y), random_seed=hp["seed"])
    fit = posterior.sample(num_chains=hp["num_chains"],
                           num_warmup=hp["num_warmup"],
                           num_samples=hp["num_samples"])
    frame = fit.to_frame()[["alpha", "beta", "sigma"]]
    means = {c: float(frame[c].mean()) for c in ("alpha", "beta", "sigma")}
    if draws_csv:
        frame.to_csv(draws_csv, index=False)
    out = {
        "alpha": means["alpha"],
        "beta": means["beta"],
        "sigma": means["sigma"],
        "num_chains": hp["num_chains"],
        "num_warmup": hp["num_warmup"],
        "num_samples": hp["num_samples"],
        "thin": hp["thin"],
        "seed": hp["seed"],
        "effective_total_draws": hp["num_chains"] * hp["num_samples"],
        "data_rows": n,
    }
    with open(out_json, "w") as fh:
        json.dump(out, fh, indent=2)
    with open("/app/hparams.json", "w") as fh:
        json.dump(hp, fh, indent=2)
    print("POSTERIOR_OK alpha=%.4f beta=%.4f sigma=%.4f draws=%d"
          % (means["alpha"], means["beta"], means["sigma"], out["effective_total_draws"]))


def _aicc(n, rss, k):
    if n - k - 1 <= 0 or rss <= 0:
        return float("inf")
    return float(n * math.log(rss / n) + 2 * k + 2 * k * (k + 1) / (n - k - 1))


def run_penalty(data_path, out_txt, model_cmp):
    from sklearn.linear_model import Lasso, LassoCV, RidgeCV
    from sklearn.preprocessing import StandardScaler
    df = pd.read_csv(data_path)
    ycol = "stretch"
    Xraw = df.drop(columns=[ycol])
    y = df[ycol].astype(float).to_numpy()
    sc = StandardScaler().fit(Xraw)
    X = sc.transform(Xraw)

    cv = LassoCV(alphas=np.logspace(-3, 0.5, 60), cv=5, random_state=0,
                 max_iter=80000).fit(X, y)
    lam_cv = float(cv.alpha_)

    grid = np.logspace(-4, 1.0, 200)
    aic = []
    for lam in grid:
        m1 = Lasso(alpha=lam, max_iter=80000).fit(X, y)
        rss = float(np.sum((y - m1.predict(X)) ** 2))
        k = int(np.sum(np.abs(m1.coef_) > 1e-8))
        aic.append(_aicc(X.shape[0], rss, k))
    aic = np.asarray(aic)
    lam_aic = float(grid[int(np.argmin(aic))])

    ridge = RidgeCV(alphas=np.logspace(-4, 0.5, 60)).fit(X, y)
    lam_ridge = float(ridge.alpha_)

    # Two independent criteria: cross-validation and the corrected AIC. They
    # corroborate when their ratio is small; the reported penalty is pinned
    # between the two estimator values.
    lo, hi = min(lam_cv, lam_aic), max(lam_cv, lam_aic)
    chosen = math.sqrt(lam_cv * lam_aic)
    ratio = hi / lo if lo > 0 else float("inf")

    k_aic = int(np.sum(np.abs(
        Lasso(alpha=lam_aic, max_iter=80000).fit(X, y).coef_) > 1e-8))
    rows = pd.DataFrame({
        "variant": ["lasso_cv", "lasso_aicc", "ridge_cv"],
        "penalty": ["%.10g" % lam_cv, "%.10g" % lam_aic, "%.10g" % lam_ridge],
        "dof": [int(np.sum(np.abs(cv.coef_) > 1e-8)), k_aic, int(X.shape[1])],
        "criterion": ["cross_validation", "corrected_aic", "cross_validation"],
    })
    if model_cmp:
        rows.to_csv(model_cmp, index=False)

    if not (ratio <= 40.0 and math.isfinite(chosen) and chosen > 0 and lo > 0):
        print("PENALTY_UNRELIABLE ratio=%.2f" % ratio, flush=True)
        sys.exit(2)
    result_txt = "%.10g" % chosen
    if out_txt:
        with open(out_txt, "w") as fh:
            fh.write(result_txt + "\n")
    print(result_txt, flush=True)


def main():
    ap = argparse.ArgumentParser(prog="posterior.py")
    ap.add_argument("mode", nargs="?",
                    choices=["default", "posterior", "penalty"], default="default")
    ap.add_argument("--data")
    ap.add_argument("--out")
    ap.add_argument("--draws")
    ap.add_argument("--model-cmp")
    a = ap.parse_args()

    if a.mode == "posterior":
        run_posterior(a.data or DATA_POST,
                      a.out or "/app/posterior_means.json",
                      a.draws or "/app/posterior.csv")
        return
    if a.mode == "penalty":
        run_penalty(a.data or DATA_PEN,
                    a.out or "/app/penalty.txt",
                    a.model_cmp or "/app/model_comparison.csv")
        return
    # default
    run_posterior(DATA_POST, "/app/posterior_means.json", "/app/posterior.csv")
    run_penalty(DATA_PEN, "/app/penalty.txt", "/app/model_comparison.csv")


if __name__ == "__main__":
    main()
JUPY
chmod +x /app/posterior.py

# Run the real workflow on the visible datasets -> produces all five artifacts.
python3 /app/posterior.py

echo "= posterior_means.json ="; cat /app/posterior_means.json
echo "= penalty.txt ="; cat /app/penalty.txt
echo "= posterior.csv rows ="; wc -l < /app/posterior.csv
