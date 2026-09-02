#!/bin/bash
# Verifier for fume-marsh: checks the visible deliverables and EXECUTES the
# deliverable tool (/app/fit_model.py) on every hidden case in /tests/hidden.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import csv
import json
import os
import subprocess
import sys

import joblib
import numpy as np

TOOL = "/app/fit_model.py"
VISIBLE_CSV = "/app/data/pump_readings.csv"
VISIBLE_MODEL = "/app/model.pkl"
VISIBLE_MANIFEST = "/app/manifest.json"

failures = []


def read_table(path):
    with open(path, newline="") as fh:
        rows = list(csv.reader(fh))
    return rows[0], rows[1:]


def check_pair(csv_path, model_path, manifest_path):
    """Validate a (dataset, persisted model, manifest) triple."""
    try:
        header, rows = read_table(csv_path)
    except Exception as exc:
        return ["cannot read %s: %s" % (csv_path, exc)]
    n_feats = len(header) - 1

    if not os.path.isfile(model_path):
        return ["missing serialized model %s" % model_path]
    if not os.path.isfile(manifest_path):
        return ["missing manifest %s" % manifest_path]

    try:
        model = joblib.load(model_path)
    except Exception as exc:
        return ["model %s does not load with joblib: %s" % (model_path, exc)]

    # must be a sklearn linear model
    if not type(model).__module__.startswith("sklearn.linear_model"):
        return ["model class %s.%s is not a sklearn linear model"
                % (type(model).__module__, type(model).__name__)]
    if not hasattr(model, "coef_"):
        return ["model has no coef_ attribute"]
    if len(np.ravel(model.coef_)) != n_feats:
        return ["coefficient vector length %d != feature count %d"
                % (len(np.ravel(model.coef_)), n_feats)]

    try:
        with open(manifest_path) as fh:
            manifest = json.load(fh)
    except Exception as exc:
        return ["manifest %s is not valid JSON: %s" % (manifest_path, exc)]

    for key in ("n_features", "n_samples", "feature_columns",
                "target_column", "model_class"):
        if key not in manifest:
            return ["manifest missing key %r" % key]
    if manifest["n_features"] != n_feats:
        return ["manifest n_features %r != %d" % (manifest["n_features"], n_feats)]
    if manifest["n_samples"] != len(rows):
        return ["manifest n_samples %r != %d" % (manifest["n_samples"], len(rows))]
    if manifest["model_class"] != type(model).__name__:
        return ["manifest model_class %r != %r"
                % (manifest["model_class"], type(model).__name__)]

    try:
        X = np.array([[float(c) for c in r[:n_feats]] for r in rows], dtype=float)
        y = np.array([int(float(r[-1])) for r in rows], dtype=int)
    except Exception as exc:
        return ["cannot parse dataset %s: %s" % (csv_path, exc)]
    try:
        preds = np.asarray(model.predict(X))
    except Exception as exc:
        return ["model.predict failed on raw features: %s" % exc]
    if preds.shape[0] != len(rows):
        return ["predict returned %d outputs for %d rows" % (preds.shape[0], len(rows))]
    acc = float((preds.astype(int) == y).mean())
    if acc < 0.65:
        return ["persisted model fits the data poorly (accuracy %.3f)" % acc]
    return []


def run_tool(csv_path, tag):
    model_out = "/tmp/fm_model_%s.pkl" % tag
    manifest_out = "/tmp/fm_manifest_%s.json" % tag
    for p in (model_out, manifest_out):
        if os.path.exists(p):
            os.remove(p)
    try:
        r = subprocess.run([sys.executable, TOOL, csv_path, model_out, manifest_out],
                           capture_output=True, text=True, timeout=120)
    except Exception as exc:
        return None, None, ["tool execution failed on %s: %s" % (csv_path, exc)]
    return r, model_out, manifest_out


if not os.path.isfile(TOOL):
    failures.append("missing /app/fit_model.py")
else:
    # ---- visible deliverables ----
    failures.extend(check_pair(VISIBLE_CSV, VISIBLE_MODEL, VISIBLE_MANIFEST))

    # ---- hidden cases ----
    hidden_dir = "/tests/hidden"
    cases = sorted(os.listdir(hidden_dir)) if os.path.isdir(hidden_dir) else []
    if not cases:
        failures.append("no hidden cases present")
    for case in cases:
        base = os.path.join(hidden_dir, case)
        csv_path = os.path.join(base, "data.csv")
        if not os.path.isfile(csv_path):
            failures.append("hidden '%s' malformed (no data.csv)" % case)
            continue
        if case == "badcell":
            # malformed dataset: tool must exit non-zero and write nothing
            r, model_out, manifest_out = run_tool(csv_path, case)
            if r is None:
                failures.append("hidden '%s': tool crashed instead of failing cleanly" % case)
            elif r.returncode == 0:
                failures.append("hidden '%s': tool exited 0 on a malformed dataset" % case)
            elif os.path.exists(model_out) or os.path.exists(manifest_out):
                failures.append("hidden '%s': outputs written despite validation failure" % case)
            continue
        r, model_out, manifest_out = run_tool(csv_path, case)
        if r is None:
            continue
        if r.returncode != 0:
            failures.append("hidden '%s': tool exited %d (%s)"
                            % (case, r.returncode, r.stderr[-200:]))
            continue
        failures.extend(["hidden '%s': %s" % (case, m) for m in
                         check_pair(csv_path, model_out, manifest_out)])

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
