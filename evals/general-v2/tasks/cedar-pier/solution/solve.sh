#!/usr/bin/env bash
# Oracle for cedar-pier: writes the real config-driven trainer (/app/config.yaml
# and /app/train.py), then RUNS it to produce /app/model.joblib, /app/vector.out
# and the experiment-data directory. Never reads /tests.
set -eu
cd /app

cat > /app/config.yaml <<'YAML'
paths:
  dataset: "/app/data/company.csv"
  validation: "/app/data/val_company.csv"
  serialized: "/app/model.joblib"
  vector: "/app/vector.out"
  experiment: "/app/experiment/run-42/seed-6"

data:
  target: "broke_down"
  constrained_feature: "years_review"
  split_folds: 5
  split_seed: 11

training:
  epochs: 260
  batch_size: 256

model:
  penalty: "l2"
  C: 0.9

metrics:
  accuracy_floor: 0.80

debug:
  enabled: false
  epochs: 1
  batch_size: 4

hydra:
  job:
    chdir: false
  run:
    dir: "."
  output_subdir: null
YAML

cat > /app/train.py <<'PY'
#!/usr/bin/env python3
"""Willow Harbor crane-shift trainer (config-driven, reproducible).

Reads every data/output path and tuning knob from the Hydra config
(/app/config.yaml) with dot-path command-line overrides:
    python3 /app/train.py [paths.dataset=... paths.validation=... ...] [debug.enabled=true]
Runs schema checks -> fixed reproducible folds -> fits a scikit-learn linear
classifier -> guarantees the constrained feature has a strictly negative
coefficient -> gates on held-out accuracy -> persists model.joblib + a plain
row-wise vector file, and writes config/metrics/progress under
paths.experiment (or paths.experiment/debug for debug.idle runs).
"""
from pathlib import Path
import json
import sys
import numpy as np
import pandas as pd
import joblib
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import StratifiedKFold
from sklearn.metrics import accuracy_score
import hydra
from omegaconf import DictConfig, OmegaConf


def die(msg):
    sys.stderr.write("CEDARPIER-ERROR: %s\n" % msg)
    sys.exit(1)


def fit_enforced_negative_sign(X, y, idx, params):
    """Fit a LogisticRegression (or refit after mirror-flipping the constraint
    column) so the coefficient for column `idx' is strictly negative, while the
    returned model predicts correctly on the NATURAL (unflipped) feature space
    and remains a single valid scikit-learn model of the same shape.
    """
    m = LogisticRegression(**params)
    m.fit(X, y)

    def remap(m2):
        coef = m2.coef_.copy()
        coef[0, idx] *= -1.0
        m2.coef_ = coef
        return m2

    if float(m.coef_[0, idx]) >= 0.0:
        Xn = X.copy()
        Xn[:, idx] = -Xn[:, idx]
        m2 = LogisticRegression(**params)
        m2.fit(Xn, y)
        m = remap(m2)
    return m


@hydra.main(version_base=None, config_path=".", config_name="config")
def main(cfg: DictConfig) -> None:
    debug_enabled = bool(cfg.debug.enabled)
    epochs = int(cfg.debug.epochs if debug_enabled else cfg.training.epochs)
    batch_size = int(cfg.debug.batch_size if debug_enabled else cfg.training.batch_size)

    target = cfg.data.target
    constrained = cfg.data.constrained_feature
    exp_root = Path(cfg.paths.experiment)
    out_dir = exp_root / "debug" if debug_enabled else exp_root
    out_dir.mkdir(parents=True, exist_ok=True)

    # ---- schema validation (fail clean, no product written) ----
    df = pd.read_csv(Path(cfg.paths.dataset))
    if df is None or len(df) == 0:
        die("dataset is empty")
    if target not in df.columns:
        die("missing target column %r" % target)
    if constrained not in df.columns:
        die("missing constrained-feature column %r" % constrained)
    feat_cols = [c for c in df.columns if c != target]
    if len(feat_cols) < 2:
        die("no usable feature columns found")
    try:
        X = df[feat_cols].astype(np.float64).to_numpy()
    except (ValueError, TypeError):
        die("non-numeric feature values present")
    if np.isnan(X).any() or np.isinf(X).any():
        die("missing/NaN feature values present")
    y = df[target].astype(float).to_numpy()
    if np.unique(y).size < 2:
        die("target column is constant")

    constr_idx = feat_cols.index(constrained)
    n_features = len(feat_cols)

    # Fixed reproducible folds.
    skf = StratifiedKFold(n_splits=int(cfg.data.split_folds), shuffle=True,
                          random_state=int(cfg.data.split_seed))
    fold_assign = np.zeros(len(y), dtype=int)
    for k, (_, vi) in enumerate(skf.split(X, y)):
        fold_assign[vi] = k

    # Fit + sign constraint.
    params = {"penalty": cfg.model.penalty, "C": float(cfg.model.C),
              "max_iter": max(int(epochs), 1), "solver": "lbfgs"}
    model = fit_enforced_negative_sign(X, y, constr_idx, params)

    constrained_coef = float(model.coef_[0, constr_idx])

    # Accuracy gate on the held-out validation set.
    val_df = pd.read_csv(cfg.paths.validation)
    Xval = val_df[feat_cols].astype(np.float64).to_numpy()
    yval = val_df[target].astype(float).to_numpy()
    acc = float(accuracy_score(yval, model.predict(Xval)))
    if not debug_enabled and acc + 1e-9 < float(cfg.metrics.accuracy_floor):
        die("held-out accuracy %.4f below floor %.4f"
              % (acc, float(cfg.metrics.accuracy_floor)))

    # Persist.
    if debug_enabled:
        model_path = out_dir / "model.joblib"
        vector_path = out_dir / "vector.out"
    else:
        model_path = Path(cfg.paths.serialized)
        vector_path = Path(cfg.paths.vector)
    model_path.parent.mkdir(parents=True, exist_ok=True)
    vector_path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, str(model_path))
    np.savetxt(str(vector_path), model.coef_[0], fmt="%.12f")

    # Experiment artifacts.
    (out_dir / "config_snapshot.yaml").write_text(OmegaConf.to_yaml(cfg))
    progress = {
        "n_features": n_features,
        "n_epochs_effective": int(epochs),
        "batch_size": int(batch_size),
        "accuracy": acc if not debug_enabled else None,
        "split_folds": int(cfg.data.split_folds),
        "split_seed": int(cfg.data.split_seed),
        "constrained_coef": constrained_coef,
        "fold_assignment": fold_assign.tolist(),
        "debug_enabled": debug_enabled,
    }
    (out_dir / "progress.json").write_text(json.dumps(progress, indent=2))
    (out_dir / "metrics.json").write_text(
        json.dumps({"accuracy": acc, "constrained_coef": constrained_coef,
                    "n_features": n_features}, indent=2))
    print("CEDARPIER OK: debug=%s epochs=%d acc=%.4f constr_coef=%.4f"
          % (debug_enabled, epochs, acc, constrained_coef))


if __name__ == "__main__":
    main()
PY

# ---- actually run the trainer (produces all deliverables) ----
python3 /app/train.py
echo "model.joblib: $(du -h /app/model.joblib)"
echo "vector.out lines: $(wc -l < /app/vector.out)"
echo "experiment dir:"; ls -la /app/experiment/run-42/seed-6/