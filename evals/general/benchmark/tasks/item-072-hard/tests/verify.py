#!/usr/bin/env python3
"""Objective verifier for item-072-hard.

Re-checks everything from scratch after a clean re-run of the agent's train.py;
never trusts the agent's summary alone. Optionally accepts
[test.parquet, output_dir] as argv (output dir override for offline dry-runs).
"""
import json
import os
import subprocess
import sys

import pandas as pd

BASE = "/app"
OUT = os.path.join(BASE, "output")
REQ_ACC = 0.86
REQ_SIZE = 2_000_000
REQ_POS = 0.78
T_ACC = 0.85
T_POS = 0.76
T_NEG = 0.78

if len(sys.argv) > 2:
    OUT = sys.argv[2]
    BASE = os.path.dirname(OUT)


def load_json(path):
    with open(path) as fh:
        return json.load(fh)


def run_train_py():
    return subprocess.run([sys.executable, os.path.join(BASE, "train.py")],
                          cwd=BASE, capture_output=True, text=True, timeout=900)


def ft_class_stats(model, path):
    rows = pd.read_parquet(path)
    both = {k: [0, 0] for k in ["pos", "neg"]}
    for _, r in rows.iterrows():
        text = str(r["text"])
        truth = "pos" if r["stars"] >= 4 else "neg"
        pred = model.predict(text, k=1)[0][0].replace("__label__", "")
        both[truth][1] += 1
        both[truth][0] += pred == truth
    total = sum(v[1] for v in both.values())
    correct = sum(v[0] for v in both.values())
    return {
        "val_accuracy": correct / total,
        "pos_recall": both["pos"][0] / both["pos"][1],
        "neg_recall": both["neg"][0] / both["neg"][1],
    }


def metric_keys_ok(m):
    req = ["val_accuracy", "pos_recall", "neg_recall", "model_size_bytes", "dim",
           "bucket", "minn", "maxn", "epoch", "lr", "wordNgrams", "seed"]
    if not isinstance(m, dict):
        return False
    if any(k not in m for k in req):
        return False
    if not (0.0 <= m["val_accuracy"] <= 1.0) or not isinstance(m["val_accuracy"], (int, float)):
        return False
    if not (0.0 <= m["pos_recall"] <= 1.0) or not isinstance(m["pos_recall"], (int, float)):
        return False
    if not (0.0 <= m["neg_recall"] <= 1.0) or not isinstance(m["neg_recall"], (int, float)):
        return False
    if not isinstance(m["model_size_bytes"], int) or m["model_size_bytes"] <= 0:
        return False
    return True


def sweep_ok(sweep):
    if not isinstance(sweep, list) or len(sweep) < 5:
        return False
    sizes = [e["model_size_bytes"] for e in sweep]
    accs = [e["val_accuracy"] for e in sweep]
    if any(sizes[i] >= sizes[i + 1] for i in range(len(sizes) - 1)):
        return False
    if sizes[-1] < 5 * sizes[0]:
        return False
    if max(accs) - min(accs) > 0.02:
        return False
    for e in sweep:
        if not metric_keys_ok(e):
            return False
    return True


def main():
    train_py = os.path.join(BASE, "train.py")
    model_bin = os.path.join(OUT, "model.bin")
    if not (os.path.isfile(train_py) and os.path.isfile(os.path.join(OUT, "metrics.json"))
            and os.path.isfile(os.path.join(OUT, "sweep.json")) and os.path.isfile(model_bin)):
        print("REASONS missing artifact")
        return 1

    try:
        metrics_before = load_json(os.path.join(OUT, "metrics.json"))
    except Exception:
        print("REASONS bad initial json")
        return 1

    try:
        r = run_train_py()
    except subprocess.TimeoutExpired:
        print("REASONS train.py timed out")
        return 1
    if r.returncode != 0 or not all(os.path.isfile(p) for p in [
            os.path.join(OUT, "metrics.json"), os.path.join(OUT, "sweep.json"), model_bin]):
        print("REASONS train.py failed or missing outputs")
        return 1

    try:
        metrics = load_json(os.path.join(OUT, "metrics.json"))
        sweep = load_json(os.path.join(OUT, "sweep.json"))
    except Exception:
        print("REASONS unreadable post-run json")
        return 1

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
    if metrics["val_accuracy"] < REQ_ACC or metrics["pos_recall"] < REQ_POS:
        print("REASONS reported acc or pos recall under bar")
        return 1
    if metrics["model_size_bytes"] > REQ_SIZE:
        print("REASONS size over cap")
        return 1

    # final model = smallest sweep entry satisfying all three constraints
    passers = [e for e in sweep if e["val_accuracy"] >= REQ_ACC and e["model_size_bytes"] <= REQ_SIZE
               and e["pos_recall"] >= REQ_POS]
    target = min(passers, key=lambda e: e["model_size_bytes"]) if passers \
        else max(sweep, key=lambda e: e["val_accuracy"])
    if metrics["dim"] != target["dim"] or metrics["bucket"] != target["bucket"]:
        print("REASONS final model not minimal satisfying entry")
        return 1
    if abs(metrics["model_size_bytes"] - target["model_size_bytes"]) > 0.02 * target["model_size_bytes"]:
        print("REASONS final model size mismatch vs sweep")
        return 1

    # reproducibility
    if "val_accuracy" in metrics_before and abs(metrics_before["val_accuracy"] - metrics["val_accuracy"]) > 0.02:
        print("REASONS rerun not reproducible")
        return 1

    # generalization on hidden held-out test parquet
    import fasttext
    model = fasttext.load_model(model_bin)
    test_path = sys.argv[1] if len(sys.argv) > 1 else "/tests/test.parquet"
    if not os.path.exists(test_path):
        print("REASONS missing heldout")
        return 1
    ts = ft_class_stats(model, test_path)
    if ts["val_accuracy"] < T_ACC or ts["pos_recall"] < T_POS or ts["neg_recall"] < T_NEG:
        print("REASONS heldout acc/pos/neg %.4f %.4f %.4f" % (
            ts["val_accuracy"], ts["pos_recall"], ts["neg_recall"]))
        return 1
    print("PASS val=%.4f pos=%.4f size=%d heldout=%.4f/%.4f/%.4f" % (
        metrics["val_accuracy"], metrics["pos_recall"], actual_size,
        ts["val_accuracy"], ts["pos_recall"], ts["neg_recall"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())