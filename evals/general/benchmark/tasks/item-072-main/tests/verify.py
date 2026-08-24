#!/usr/bin/env python3
"""Objective verifier for item-072-main (medium).

Re-checks everything from scratch; never trusts the agent's summary alone.
Runs AFTER the agent is done, as root, inside the container.
"""
import json
import os
import subprocess
import sys

import pandas as pd

BASE = "/app"
OUT = os.path.join(BASE, "output")
REQ_ACC = 0.90
REQ_SIZE = 2_000_000
TEST_ACC = 0.90

# Allow an explicit output dir (used for offline dry-runs while authoring).
if len(sys.argv) > 2:
    OUT = sys.argv[2]
    BASE = os.path.dirname(OUT)


def load_json(path):
    with open(path) as fh:
        return json.load(fh)


def run_train_py():
    # Cwd must be /app; train.py relates nothing to cwd by contract, but run
    # from /app to mirror the instruction.
    return subprocess.run([sys.executable, os.path.join(BASE, "train.py")],
                          cwd=BASE, capture_output=True, text=True, timeout=900)


def ft_acc(model, path):
    corr = tot = 0
    rows = pd.read_parquet(path)
    for _, r in rows.iterrows():
        text = str(r["text"])
        truth = "pos" if r["stars"] >= 4 else "neg"
        pred = model.predict(text, k=1)[0][0].replace("__label__", "")
        corr += pred == truth
        tot += 1
    return corr / tot if tot else 0.0


def metric_keys_ok(m):
    req = ["val_accuracy", "model_size_bytes", "dim", "bucket", "minn", "maxn",
           "epoch", "lr", "wordNgrams", "seed"]
    if not isinstance(m, dict):
        return False
    for k in req:
        if k not in m:
            return False
    if not isinstance(m["val_accuracy"], (int, float)) or not (0.0 <= m["val_accuracy"] <= 1.0):
        return False
    if not isinstance(m["model_size_bytes"], int) or m["model_size_bytes"] <= 0:
        return False
    return True


def sweep_ok(sweep):
    if not isinstance(sweep, list) or len(sweep) < 3:
        return False
    sizes = []
    accs = []
    for e in sweep:
        if not metric_keys_ok(e):
            return False
        sizes.append(e["model_size_bytes"])
        accs.append(e["val_accuracy"])
    if any(sizes[i] >= sizes[i + 1] for i in range(len(sizes) - 1)):
        return False  # must be strictly increasing
    if sizes[-1] < 5 * sizes[0]:
        return False  # real range
    if max(accs) - min(accs) > 0.02:
        return False  # accuracy survives shrinkage
    return True


def main():
    reasons = []

    train_py = os.path.join(BASE, "train.py")
    model_bin = os.path.join(OUT, "model.bin")
    if not (os.path.isfile(train_py) and os.path.isfile(os.path.join(OUT, "metrics.json"))
            and os.path.isfile(os.path.join(OUT, "sweep.json")) and os.path.isfile(model_bin)):
        print("REASONS missing artifact")
        return 1

    try:
        metrics_before = load_json(os.path.join(OUT, "metrics.json"))
        sweep_before = load_json(os.path.join(OUT, "sweep.json"))
        size_before = os.path.getsize(model_bin)
    except Exception:
        print("REASONS bad initial json")
        return 1

    # 1. Force a clean reproducible re-run; the resulting files are what we grade.
    try:
        r = run_train_py()
    except subprocess.TimeoutExpired:
        print("REASONS train.py timed out")
        return 1
    post_files = all(os.path.isfile(p) for p in [
        os.path.join(OUT, "metrics.json"), os.path.join(OUT, "sweep.json"), model_bin])
    if r.returncode != 0 or not post_files:
        print("REASONS train.py failed or missing outputs")
        return 1

    try:
        metrics = load_json(os.path.join(OUT, "metrics.json"))
        sweep = load_json(os.path.join(OUT, "sweep.json"))
    except Exception:
        print("REASONS unreadable post-run json")
        return 1

    # 2. schema + self-consistency
    if not metric_keys_ok(metrics):
        print("REASONS bad metrics schema")
        return 1
    if not sweep_ok(sweep):
        print("REASONS bad sweep")
        return 1

    actual_size = os.path.getsize(model_bin)
    if abs(actual_size - metrics["model_size_bytes"]) > 0.02 * metrics["model_size_bytes"]:
        print("REASONS model size mismatch")
        return 1
    if metrics["model_size_bytes"] < 100_000:
        print("REASONS degenerate model")
        return 1
    if metrics["val_accuracy"] < REQ_ACC:
        print("REASONS reported acc below bar")
        return 1
    if metrics["model_size_bytes"] > REQ_SIZE:
        print("REASONS size over cap")
        return 1

    # 3. final model = smallest sweep entry meeting both constraints
    passers = [e for e in sweep if e["val_accuracy"] >= REQ_ACC and e["model_size_bytes"] <= REQ_SIZE]
    if passers:
        target = min(passers, key=lambda e: e["model_size_bytes"])
    else:
        target = max(sweep, key=lambda e: e["val_accuracy"])
    if metrics["dim"] != target["dim"] or metrics["bucket"] != target["bucket"]:
        print("REASONS final model not minimal satisfying entry")
        return 1
    if abs(metrics["model_size_bytes"] - target["model_size_bytes"]) > 0.02 * target["model_size_bytes"]:
        print("REASONS final model size mismatch vs sweep")
        return 1

    # 4. reproducibility: rerun must keep val_accuracy (approx)
    if "val_accuracy" in metrics_before and abs(metrics_before["val_accuracy"] - metrics["val_accuracy"]) > 0.02:
        print("REASONS rerun not reproducible")
        return 1

    # 5. generalization on a held-out test parquet the agent never saw
    import fasttext
    model = fasttext.load_model(model_bin)
    test_path = sys.argv[1] if len(sys.argv) > 1 else "/tests/test.parquet"
    if not os.path.exists(test_path):
        print("REASONS missing heldout")
        return 1
    tacc = ft_acc(model, test_path)
    if tacc < TEST_ACC:
        print("REASONS heldout acc %.3f" % tacc)
        return 1
    print("PASS val=%.4f size=%d heldout=%.4f" % (metrics["val_accuracy"], actual_size, tacc))
    return 0


if __name__ == "__main__":
    sys.exit(main())