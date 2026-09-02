#!/usr/bin/env python3
"""drift-terrace constrained logistic trainer.

Reads a YAML config under --config (default /app/config.yaml).  Every data
path, split/fold control, regularisation, accuracy floor, the designated
signed feature and the one-epoch debug override come from that config, so the
same program runs unchanged on a fresh dataset supplied at run time (via
--data / --out, which override the corresponding config keys).

The designated feature is forced to have a STRICTLY NEGATIVE coefficient with
an L-BFGS-B box constraint during the fit.  The fitted model (coefficient
vector + intercept + shape), a plain-text numeric vector file, and
config/progress files under the experiment-data directory are persisted.
"""
import argparse, os, sys, json, shutil
import numpy as np
import joblib
import yaml
import pandas as pd
from sklearn.model_selection import StratifiedKFold
from scipy.optimize import minimize


def parse():
    p = argparse.ArgumentParser()
    p.add_argument("--config", default="/app/config.yaml", help="YAML config path")
    p.add_argument("--out", default=None, help="override output.dir")
    p.add_argument("--data", default=None, help="override data.path")
    p.add_argument("--logs", default=None, help="override output.log_dir")
    return p.parse_args()


def main():
    args = parse()
    with open(args.config, "r") as f:
        cfg = yaml.safe_load(f)

    data_cfg = cfg["data"]
    data_path = args.data or data_cfg["path"]
    target_col = data_cfg["target_column"]
    drop_cols = data_cfg.get("drop_columns", []) or []
    id_col = data_cfg.get("id_column")

    model_cfg = cfg["model"]
    reg = float(model_cfg["reg_strength"])
    max_iter = int(model_cfg["max_iter"])

    opt_cfg = cfg["optim"]
    driver_feat = opt_cfg["driver_feature"]
    eps = float(opt_cfg.get("bound_epsilon", 1e-4))

    split_cfg = cfg["split"]
    seed = int(split_cfg["seed"])
    n_folds = int(split_cfg["n_folds"])
    held_out = int(split_cfg["held_out_fold"])

    ev_cfg = cfg["evaluate"]
    floor = float(ev_cfg["accuracy_floor"])

    debug = cfg.get("debug", {})
    one_epoch = bool(debug.get("one_epoch", False))
    solver_epochs = 1 if one_epoch else max_iter

    out_cfg = cfg["output"]
    out_dir = args.out or out_cfg["dir"]
    log_dir = args.logs or out_cfg.get("log_dir", "/app/experiment-data")
    model_file = out_cfg["model_file"]
    vector_file = out_cfg["vector_file"]
    progress_file = out_cfg.get("progress_file", "progress.log")

    # ---- load & select features ----
    df = pd.read_csv(data_path)
    if id_col:
        df = df.drop(columns=[id_col])
    df = df.drop(columns=[c for c in drop_cols if c in df.columns])
    if target_col not in df.columns:
        sys.exit("train failed: target column %s missing" % target_col)
    if driver_feat not in df.columns:
        sys.exit("train failed: driver feature %s missing" % driver_feat)
    feature_cols = [c for c in df.columns if c != target_col]
    X = df[feature_cols].to_numpy(dtype=np.float64)
    y = df[target_col].to_numpy().astype(np.float64)
    X = np.nan_to_num(X)
    constrained_idx = feature_cols.index(driver_feat)

    # ---- fixed (seeded) fold split, held_out fold used for accuracy ----
    skf = StratifiedKFold(n_splits=n_folds, shuffle=True, random_state=seed)
    folds = list(skf.split(X, y))
    train_idx, val_idx = folds[held_out]
    Xtr, ytr = X[train_idx], y[train_idx]
    Xva, yva = X[val_idx], y[val_idx]

    # ---- train with strict negative constraint on driver ----
    d = X.shape[1]

    def negobj(params):
        w = params[:d]
        b = params[d]
        z = Xtr @ w + b
        nll = np.sum(np.logaddexp(0.0, -ytr * z)) + 0.5 * reg * np.sum(w * w)
        sig = 1.0 / (1.0 + np.exp(-z))
        gw = (sig - ytr) @ Xtr + reg * w
        gb = np.sum(sig - ytr)
        return nll, np.concatenate([gw, [gb]])

    bounds = [(-np.inf, np.inf)] * d + [(-np.inf, np.inf)]
    bounds[constrained_idx] = (-np.inf, -eps)
    res = minimize(negobj, jac=True,
                   x0=np.zeros(d + 1), method="L-BFGS-B",
                   bounds=bounds, options={"maxiter": solver_epochs, "maxls": 50})
    w = res.x[:d]
    b = float(res.x[d])

    # ---- evaluate on held-out fold ----
    z_va = Xva @ w + b
    pred = (z_va >= 0.0).astype(int)
    va_acc = float(np.mean(pred == yva))
    k = w[constrained_idx]

    # ---- persist ----
    os.makedirs(out_dir, exist_ok=True)
    artifact = {
        "kind": "binary-logistic-constrained",
        "feature_names": feature_cols,
        "coef": w.tolist(),
        "intercept": b,
        "coef_shape": list(w.shape),
        "n_features": len(feature_cols),
        "constrained_feature": driver_feat,
        "constrained_coef": k,
        "n_folds": n_folds,
        "held_out_fold": held_out,
        "n_val": int(len(val_idx)),
        "val_accuracy": va_acc,
        "solver_epochs": solver_epochs,
    }
    joblib.dump(artifact, os.path.join(out_dir, model_file))
    with open(os.path.join(out_dir, vector_file), "w") as f:
        f.write("%d\n" % len(w))
        for v in w:
            f.write("%.10f\n" % v)
        f.write("%.10f\n" % b)
    os.makedirs(log_dir, exist_ok=True)
    with open(os.path.join(log_dir, progress_file), "w") as f:
        f.write("epochs=%d\n" % solver_epochs)
        f.write("folds=%d heldout_idx=%d\n" % (n_folds, held_out))
        f.write("val_accuracy=%.6f\n" % va_acc)
    shutil.copy(args.config, os.path.join(log_dir, "config.yaml"))

    # ---- self-test reporting (pass/fail tokens + mean statistic) ----
    neg_pass = k < -eps
    floor_pass = va_acc >= floor
    checks = [
        ("DRIVER_NEG", neg_pass, "%.6f < -%s" % (k, eps)),
        ("ACC_FLOOR", floor_pass, "%.4f >= %.4f" % (va_acc, floor)),
        ("PX_SHAPE", len(w) >= 2, "coef len %d" % len(w)),
    ]
    accs = [va_acc]  # mean over reported validation
    mean = float(np.mean(accs))
    print("SELFTEST driver_coef=%.6f PASS" % k if neg_pass else "SELFTEST driver_coef=%.6f FAIL" % k)
    print("SELFTEST val_accuracy=%.6f %s (floor %.4f)" % (va_acc, "PASS" if floor_pass else "FAIL", floor))
    print("SELFTEST MEAN_ACC=%.6f" % mean)
    print("SUMMARY saved_dir=%s model=%s vector=%s epochs=%d" % (out_dir, model_file, vector_file, solver_epochs))
    # exit non-zero if a hard check fails so orchestrators notice
    if not (neg_pass and floor_pass):
        print("SELFTEST OVERALL FAIL")
        return 1
    print("SELFTEST OVERALL PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as e:
        print("ERROR", repr(e))
        sys.exit(2)
PY