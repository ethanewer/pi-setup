#!/usr/bin/env python3
"""Verifier helper for juniper-gasket.

  python3 /tests/verify.py <casedir> <artifacts_dir>

Re-executes nothing here; it validates the artifact set produced by
/app/fit_screen.py for one case: the pickled model loads, predicts, and the
held-out test accuracy meets the case's stated floor, with the metrics file
consistent with recomputation. Prints "RESULT: PASS" on success.
"""
import json
import os
import pickle
import sys

import numpy as np
import pandas as pd


def fail(msg):
    print("VERIFY-FAIL: %s" % msg)
    sys.exit(1)


def main():
    case, out = sys.argv[1], sys.argv[2]
    meta = json.load(open(os.path.join(case, "meta.json")))
    model_path = os.path.join(out, "screen_model.pkl")
    metrics_path = os.path.join(out, "screen_metrics.json")
    if not os.path.isfile(model_path):
        fail("missing screen_model.pkl")
    if not os.path.isfile(metrics_path):
        fail("missing screen_metrics.json")

    try:
        with open(model_path, "rb") as f:
            model = pickle.load(f)
    except Exception as e:  # noqa: BLE001
        fail("screen_model.pkl does not unpickle: %r" % e)
    if not hasattr(model, "predict"):
        fail("screen_model.pkl has no .predict method")

    features = meta["features"]
    test = pd.read_csv(os.path.join(case, "test.csv"))
    for col in features + [meta["target"]]:
        if col not in test.columns:
            fail("test.csv missing column %s" % col)
    X = test[features].to_numpy(dtype=np.float64)
    y = test[meta["target"]].to_numpy(dtype=np.int64)

    try:
        pred = np.asarray(model.predict(X))
    except Exception as e:  # noqa: BLE001
        fail("model.predict failed on the holdout set: %r" % e)
    if pred.shape != y.shape:
        fail("predictions shape %s != labels %s" % (pred.shape, y.shape))
    acc = float((pred.astype(np.int64) == y).mean())

    floor = float(meta["accuracy_floor"])
    if acc < floor:
        fail("holdout accuracy %.4f < accuracy floor %.4f" % (acc, floor))

    m = json.load(open(metrics_path))
    for k in ("case_id", "test_accuracy", "accuracy_floor", "meets_floor"):
        if k not in m:
            fail("screen_metrics.json missing key %s" % k)
    if m["case_id"] != meta["case_id"]:
        fail("metrics case_id mismatch")
    if abs(float(m["test_accuracy"]) - acc) > 5e-3:
        fail("metrics test_accuracy %.4f != recomputed %.4f"
             % (float(m["test_accuracy"]), acc))
    if abs(float(m["accuracy_floor"]) - floor) > 1e-9:
        fail("metrics accuracy_floor mismatch")
    if bool(m["meets_floor"]) != (acc >= floor):
        fail("metrics meets_floor inconsistent")

    print("RESULT: PASS (holdout accuracy %.4f >= floor %.2f)" % (acc, floor))


if __name__ == "__main__":
    main()
