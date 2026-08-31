#!/usr/bin/env python3
"""Verifier for sable-marsh (executes-deliverable).

Executes /app/fit_model.py on the shipped site data and on every hidden case,
then loads each persisted model with joblib and checks that it is a genuine
scikit-learn linear model whose coefficient vector length equals the input
feature count, consistent with the manifest, with recomputed holdout accuracy
above the floor. The malformed hidden case must exit non-zero without writing
the model. Writes the reward to /logs/verifier/reward.txt.
"""
import csv
import json
import os
import subprocess
import sys
import tempfile

FLOOR = 0.80
REWARD_FILE = "/logs/verifier/reward.txt"
SOLVE = "/app/fit_model.py"
fails = []


def fail(msg):
    print("FAIL: " + msg, file=sys.stderr)
    fails.append(msg)


def load_split(path):
    """Independent reader: returns (feature_names, X, y). Raises on error."""
    with open(path, newline="") as fh:
        rows = list(csv.reader(fh))
    header = rows[0]
    feats = [c for c in header if c != "fault"]
    tidx = header.index("fault")
    fidx = [i for i in range(len(header)) if i != tidx]
    X = [[float(r[i]) for i in fidx] for r in rows[1:]]
    y = [int(float(r[tidx])) for r in rows[1:]]
    return feats, X, y


def check_linear_model(model_path, n_features, label):
    """The competency check: persisted object is a sklearn linear model with
    a coefficient vector whose length equals the input feature count."""
    import joblib
    import numpy as np
    from sklearn.linear_model._base import LinearModel, LinearClassifierMixin

    try:
        m = joblib.load(model_path)
    except Exception as exc:
        fail("%s: joblib.load failed: %s" % (label, exc))
        return
    if not isinstance(m, (LinearModel, LinearClassifierMixin)) or not hasattr(m, "predict"):
        fail("%s: loaded object is not a sklearn linear model (%r)" % (label, type(m)))
        return
    try:
        coef = np.asarray(m.coef_, dtype=float).ravel()
    except Exception as exc:
        fail("%s: coef_ unreadable: %s" % (label, exc))
        return
    if coef.size != n_features:
        fail("%s: coef length %d != feature count %d" % (label, coef.size, n_features))


def check_manifest(manifest_path, n_features, feats, label):
    try:
        with open(manifest_path) as fh:
            man = json.load(fh)
    except Exception as exc:
        fail("%s: manifest unreadable: %s" % (label, exc))
        return None
    if not isinstance(man, dict):
        fail("%s: manifest is not a JSON object" % label)
        return None
    if man.get("n_features") != n_features:
        fail("%s: manifest n_features %r != %d" % (label, man.get("n_features"), n_features))
    if list(man.get("feature_columns", [])) != list(feats):
        fail("%s: manifest feature_columns %r != header %r" % (label, man.get("feature_columns"), feats))
    acc = man.get("holdout_accuracy")
    if not isinstance(acc, (int, float)):
        fail("%s: manifest holdout_accuracy not numeric: %r" % (label, acc))
        return None
    return float(acc)


def run_case(train_csv, holdout_csv, exp, label, model_out, manifest_out):
    for p in (model_out, manifest_out):
        if os.path.exists(p):
            os.remove(p)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, train_csv, holdout_csv, model_out, manifest_out],
            capture_output=True, text=True, timeout=200,
        )
    except subprocess.TimeoutExpired:
        fail("%s: fit_model.py timed out" % label)
        return
    if exp.get("error"):
        if r.returncode == 0:
            fail("%s: expected non-zero exit on malformed input" % label)
        if os.path.exists(model_out):
            fail("%s: model file written despite malformed input" % label)
        return
    if r.returncode != 0 or not os.path.exists(model_out):
        fail("%s: run failed rc=%d stderr=%s" % (label, r.returncode, r.stderr[-400:]))
        return
    try:
        feats, Xh, yh = load_split(holdout_csv)
    except Exception as exc:
        fail("%s: verifier could not parse holdout: %s" % (label, exc))
        return
    n_feats = exp.get("n_features", len(feats))
    check_linear_model(model_out, n_feats, label)
    man_acc = check_manifest(manifest_out, n_feats, feats, label)
    # independently recompute holdout accuracy with the persisted model
    try:
        import joblib
        m = joblib.load(model_out)
        preds = m.predict(Xh)
        acc = sum(1 for p, t in zip(preds, yh) if int(p) == t) / len(yh)
    except Exception as exc:
        fail("%s: could not recompute accuracy: %s" % (label, exc))
        return
    if acc < FLOOR:
        fail("%s: holdout accuracy %.4f below floor" % (label, acc))
    if man_acc is not None and abs(man_acc - acc) > 1e-6:
        fail("%s: manifest accuracy %.6f != recomputed %.6f" % (label, man_acc, acc))


def main():
    tmp = tempfile.mkdtemp(prefix="sable_marsh_")
    if not os.path.isfile(SOLVE):
        fail("missing /app/fit_model.py")
    else:
        # visible case: execute the deliverable on the shipped data
        run_case("/app/data/site_a.csv", "/app/data/site_b.csv", {"n_features": 5},
                 "visible", os.path.join(tmp, "vis.joblib"), os.path.join(tmp, "vis.json"))

        # registered artifacts must exist and satisfy the same properties
        art_model = "/app/artifacts/model.joblib"
        art_manifest = "/app/artifacts/manifest.json"
        try:
            feats, _, _ = load_split("/app/data/site_b.csv")
        except Exception as exc:
            fail("visible holdout unreadable: %s" % exc)
            feats = []
        if not os.path.isfile(art_model):
            fail("missing /app/artifacts/model.joblib")
        else:
            check_linear_model(art_model, 5, "artifacts")
            try:
                feats, Xh, yh = load_split("/app/data/site_b.csv")
                import joblib
                m = joblib.load(art_model)
                acc = sum(1 for p, t in zip(m.predict(Xh), yh) if int(p) == t) / len(yh)
                if acc < FLOOR:
                    fail("artifacts: holdout accuracy %.4f below floor" % acc)
            except Exception as exc:
                fail("artifacts: accuracy recompute failed: %s" % exc)
        if not os.path.isfile(art_manifest):
            fail("missing /app/artifacts/manifest.json")
        else:
            check_manifest(art_manifest, 5, feats, "artifacts")

    # hidden cases
    hidden_dir = "/tests/hidden"
    if not os.path.isdir(hidden_dir):
        fail("no hidden cases present")
    else:
        for case in sorted(os.listdir(hidden_dir)):
            base = os.path.join(hidden_dir, case)
            exp_path = os.path.join(base, "expected.json")
            try:
                with open(exp_path) as fh:
                    exp = json.load(fh)
            except Exception as exc:
                fail("hidden '%s': expected.json unreadable: %s" % (case, exc))
                continue
            tag = "hidden/" + case
            run_case(os.path.join(base, "train.csv"), os.path.join(base, "holdout.csv"),
                     exp, tag, os.path.join(tmp, case + ".joblib"), os.path.join(tmp, case + ".json"))

    print("verify failures: %d" % len(fails), file=sys.stderr)
    reward = 1 if not fails else 0
    with open(REWARD_FILE, "w") as fh:
        fh.write(str(reward))
    sys.exit(0 if reward else 1)


if __name__ == "__main__":
    main()
